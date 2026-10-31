#Requires -Version 5.1
# Removes MelonLoader from A Dance of Fire and Ice on Windows.
# Leaves UMMCompat (Plugins/UserLibs) and your mods (Mods/, UMMMods/) in place.
$ErrorActionPreference = 'Stop'

$GameDirName = 'A Dance of Fire and Ice'
$GameExe     = 'A Dance of Fire and Ice.exe'

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

$GamePath = Get-GamePath
if (-not $GamePath) {
    Write-Output "error:ADOFAI ($GameExe) not found in any Steam library."
    exit 1
}

Write-Output "Removing MelonLoader artifacts from $GamePath..."
$targets = @(
    'MelonLoader',
    'version.dll',
    'winhttp.dll',
    'dobby.dll',
    'NOTICE.txt'
)
foreach ($t in $targets) {
    $p = Join-Path $GamePath $t
    if (Test-Path -LiteralPath $p) {
        Write-Output "  rm $t"
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}

Write-Output ""
Write-Output "ok:MelonLoader uninstalled."
