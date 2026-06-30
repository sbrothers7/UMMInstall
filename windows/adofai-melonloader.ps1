#Requires -Version 5.1
# Installs MelonLoader + UMMCompat for A Dance of Fire and Ice on Windows.
#
# On Windows MelonLoader injects via a proxy version.dll dropped next to the
# game exe, so there's no launch wrapper, no Homebrew/mono, and no Steam launch
# options to set (unlike macOS).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$MelonVersion = '0.7.3'
$AppId        = '977950'
$GameDirName  = 'A Dance of Fire and Ice'
$GameExe      = 'A Dance of Fire and Ice.exe'

function Get-SteamPath {
    foreach ($key in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            $p = $props.SteamPath; if (-not $p) { $p = $props.InstallPath }
            if ($p -and (Test-Path $p)) { return $p }
        } catch {}
    }
    $def = 'C:\Program Files (x86)\Steam'
    if (Test-Path $def) { return $def }
    return $null
}

function Get-SteamLibraries([string]$steam) {
    $libs = [System.Collections.Generic.List[string]]::new()
    $libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($line in Get-Content -LiteralPath $vdf) {
            # Current format: "path"  "D:\\SteamLibrary"  — older: "1"  "D:\\..."
            if ($line -match '"(?:path|\d+)"\s+"([A-Za-z]:\\.*?)"') {
                $libs.Add(($matches[1] -replace '\\\\', '\'))
            }
        }
    }
    return $libs
}

function Get-GamePath {
    $steam = Get-SteamPath
    if (-not $steam) { return $null }
    foreach ($lib in (Get-SteamLibraries $steam)) {
        $candidate = Join-Path $lib "steamapps\common\$GameDirName"
        if (Test-Path (Join-Path $candidate $GameExe)) { return $candidate }
    }
    return $null
}

function Download-File([string]$url, [string]$dest) {
    Write-Output "info:Downloading $([IO.Path]::GetFileName($dest))..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

$GamePath = Get-GamePath
if (-not $GamePath) {
    Write-Output "error:ADOFAI ($GameExe) not found in any Steam library."
    Write-Output "error:Install/verify the game in Steam, then re-run this installer."
    exit 1
}
Write-Output "Detected ADOFAI at $GamePath"

# Remove any prior MelonLoader / UMM-proxy artifacts for a clean install.
Write-Output "Removing any prior MelonLoader artifacts..."
foreach ($t in @('MelonLoader', 'version.dll', 'winhttp.dll', 'dobby.dll', 'NOTICE.txt')) {
    $p = Join-Path $GamePath $t
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

$mlZip = Join-Path $env:TEMP 'adofai-melonloader.zip'
Download-File "https://github.com/LavaGang/MelonLoader/releases/download/v$MelonVersion/MelonLoader.x64.zip" $mlZip
Write-Output "Extracting MelonLoader into game folder..."
Expand-Archive -LiteralPath $mlZip -DestinationPath $GamePath -Force
Remove-Item -LiteralPath $mlZip -Force

# Record the installed version so future runs know what's there.
$mlDir = Join-Path $GamePath 'MelonLoader'
New-Item -ItemType Directory -Force -Path $mlDir | Out-Null
Set-Content -LiteralPath (Join-Path $mlDir 'MelonLoader.version') -Value $MelonVersion -NoNewline

# UMMCompat (square3ang) — lets UMM mods in UMMMods/ load under MelonLoader.
$ummZip = Join-Path $env:TEMP 'adofai-ummcompat.zip'
try {
    Download-File 'https://github.com/modlist-org/UMMCompat/releases/latest/download/UMMCompat.zip' $ummZip
    Expand-Archive -LiteralPath $ummZip -DestinationPath $GamePath -Force
    Remove-Item -LiteralPath $ummZip -Force
    Write-Output "ok:UMMCompat installed."
} catch {
    Write-Output "error:Failed to install UMMCompat - UMM mods in UMMMods/ won't load until it's installed."
}

# Pre-create mod folders. MelonLoader mods go in Mods/; UMM mods (via UMMCompat) in UMMMods/.
New-Item -ItemType Directory -Force -Path (Join-Path $GamePath 'Mods')    | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $GamePath 'UMMMods') | Out-Null

Write-Output ""
Write-Output "ok:MelonLoader $MelonVersion installed."
Write-Output "info:Launch the game via Steam and press Ctrl+F10 for the UMM menu."
