# Kisa omurlu PENCERELI instance ile ekran goruntusu alir.
# (--headless render uretemez; pencere acilir ve kendiliginden kapanir.)
# Modlar: menu (ana menu) | preview (bos mac) | demo (tum sprite'lar +
#         catisma) | end (zafer ekrani)
param(
    [string]$OutFile = 'screenshots\preview.png',
    [ValidateSet('menu', 'preview', 'demo', 'end')][string]$Mode = 'preview'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) { Write-Error "Godot yok: $bin"; exit 1 }

$out = $OutFile
if (-not [System.IO.Path]::IsPathRooted($out)) { $out = Join-Path $root $OutFile }
New-Item -ItemType Directory -Force (Split-Path $out -Parent) | Out-Null

$flags = switch ($Mode) {
    'menu'    { @() }
    'preview' { @('--preview') }
    'demo'    { @('--demo') }
    'end'     { @('--preview', '--end') }
}
& $bin --path $root -- @flags "--screenshot=$out"
if ($LASTEXITCODE -ne 0) { Write-Host "Screenshot basarisiz (exit $LASTEXITCODE)"; exit 1 }
Write-Host "Kaydedildi: $out"
