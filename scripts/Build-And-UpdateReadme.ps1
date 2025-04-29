param(
    [Parameter(Mandatory=$true)]
    [string]$AppPath,
    [string]$DownloadLink = "",
    [switch]$BuildIntuneWin
)

Write-Host "== Start Build-And-UpdateReadme.ps1 voor $AppPath =="

# 1. Lees meta.json uit
$metaPath = Join-Path $AppPath 'app-meta.json'
if (-not (Test-Path $metaPath)) { throw "meta.json niet gevonden ($metaPath)" }
$meta = Get-Content $metaPath | ConvertFrom-Json

$displayName   = $meta.displayName
$instructies   = $meta.instructions
$publisher     = $meta.publisher
$installScript = $meta.installScript
$uninstallCmd  = $meta.uninstallCommand
$detection     = $meta.detection
$icon          = $meta.icon
$description   = $meta.description

# 2. Zoek een EXE/MSI in files/
$exeOrMsi = Get-ChildItem -Path (Join-Path $AppPath 'files') -Include *.exe,*.msi -File | Select-Object -First 1
if (-not $exeOrMsi) {
    Write-Warning "Geen EXE of MSI gevonden in $AppPath\files"
    $appVersion = "onbekend"
} else {
    if ($exeOrMsi.Extension -ieq ".msi") {
        $appVersion = (Get-ItemProperty $exeOrMsi.FullName).VersionInfo.ProductVersion
    } else {
        $appVersion = (Get-Item $exeOrMsi.FullName).VersionInfo.FileVersion
        if (-not $appVersion) { $appVersion = (Get-Item $exeOrMsi.FullName).VersionInfo.ProductVersion }
    }
    if (-not $appVersion) { $appVersion = "onbekend" }
}

# 3. (Optioneel) Build .intunewin bestand
if ($BuildIntuneWin) {
    $intuneUtilPath = "$env:GITHUB_WORKSPACE/scripts/IntuneWinAppUtil.exe"
    if (-not (Test-Path $intuneUtilPath)) {
        Write-Host "Download de nieuwste IntuneWinAppUtil.exe"
        Invoke-WebRequest -Uri "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest/download/IntuneWinAppUtil.exe" -OutFile $intuneUtilPath
    }
    $outputFolder = Join-Path $AppPath 'build'
    if (-not (Test-Path $outputFolder)) { New-Item -Path $outputFolder -ItemType Directory | Out-Null }
    & $intuneUtilPath -c (Join-Path $AppPath 'files') -s $installScript -o $outputFolder
    $packageName = "$($displayName.ToLower().Replace(' ', ''))-$appVersion.intunewin"
    $srcIntunewin = Get-ChildItem -Path $outputFolder -Filter *.intunewin | Select-Object -Last 1
    if ($srcIntunewin) {
        Rename-Item -Path $srcIntunewin.FullName -NewName $packageName -Force
    }
} else {
    $outputFolder = Join-Path $AppPath 'build'
    $packageName = "$($displayName.ToLower().Replace(' ', ''))-$appVersion.intunewin"
}

# 4. README.md genereren
$uninstText = if ($uninstallCmd) { "**Uninstall:** $uninstallCmd`n" } else { "" }
$detectText = if ($detection) {
    "**Detectie:** type `${($detection.type)}` - pad `${($detection.path)}``n"
} else { "" }
$iconText = if (($icon) -and (Test-Path "$AppPath/$icon")) {
    "![App logo]($icon)`n"
} else { "" }

$readme = @"
# $displayName

$iconText
**Versie:** $appVersion

**Laatste intunewin package:** $DownloadLink

**Uitgever:** $publisher  
$uninstText$detectText
**Beschrijving:** $description

## Installatie-instructies
$instructies

## Changelog
- Versie $appVersion : automatische build door GitHub Actions op $(Get-Date -Format 'yyyy-MM-dd HH:mm')
"@

Set-Content -Path (Join-Path $AppPath 'README.md') -Value $readme -Encoding UTF8

Write-Host "::set-output name=app_version::$appVersion"
Write-Host "::set-output name=package_name::$packageName"
Write-Host "::set-output name=build_dir::$outputFolder"
Write-Host "::set-output name=app_name::$($displayName.ToLower().Replace(' ', ''))"
Write-Host "::set-output name=icon::$icon"