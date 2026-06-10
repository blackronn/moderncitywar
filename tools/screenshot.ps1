# Kisa omurlu PENCERELI instance ile offline onizleme ekran goruntusu alir.
# (--headless render uretemez; o yuzden pencere acilir ve kendiliginden kapanir.)
param([string]$OutFile = 'screenshots\preview.png', [switch]$Demo)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) { Write-Error "Godot yok: $bin"; exit 1 }

$out = $OutFile
if (-not [System.IO.Path]::IsPathRooted($out)) { $out = Join-Path $root $OutFile }
New-Item -ItemType Directory -Force (Split-Path $out -Parent) | Out-Null

$flags = @('--preview')
if ($Demo) { $flags = @('--demo') }
& $bin --path $root -- @flags "--screenshot=$out"
if ($LASTEXITCODE -ne 0) { Write-Host "Screenshot basarisiz (exit $LASTEXITCODE)"; exit 1 }
Write-Host "Kaydedildi: $out"
