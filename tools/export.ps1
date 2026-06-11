# VoxGard.exe uretir (tek dosya, pck gomulu). Ilk calistirmada Godot export
# sablonlarini indirir (~1.1 GB, tek seferlik). Cikti: export\VoxGard.exe
# Kullanim: powershell -ExecutionPolicy Bypass -File tools\export.ps1
param([switch]$SkipTemplateCheck)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) { Write-Error "Godot yok: $bin"; exit 1 }

$ver = '4.6.3.stable'
$tplDir = Join-Path $env:APPDATA "Godot\export_templates\$ver"
$tplExe = Join-Path $tplDir 'windows_release_x86_64.exe'

if (-not $SkipTemplateCheck -and -not (Test-Path $tplExe)) {
    Write-Host "Export sablonlari yok, indiriliyor (~1.1 GB, tek seferlik)..."
    $tpz = Join-Path $env:TEMP 'godot_export_templates.tpz'
    $url = 'https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz'
    & curl.exe -L --fail -o $tpz $url
    if ($LASTEXITCODE -ne 0) { Write-Error "Sablon indirme basarisiz"; exit 1 }
    Write-Host "Aciliyor..."
    $tmp = Join-Path $env:TEMP 'godot_tpl_extract'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    & tar -xf $tpz -C $tmp    # tpz = zip; tar Win10+ hizli acar
    if ($LASTEXITCODE -ne 0) { Write-Error "Sablon acma basarisiz"; exit 1 }
    New-Item -ItemType Directory -Force $tplDir | Out-Null
    Move-Item (Join-Path $tmp 'templates\*') $tplDir -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $tpz -Force
    if (-not (Test-Path $tplExe)) { Write-Error "Sablon kurulumu dogrulanamadi: $tplExe"; exit 1 }
    Write-Host "Sablonlar kuruldu: $tplDir"
}

$outDir = Join-Path $root 'export'
New-Item -ItemType Directory -Force $outDir | Out-Null
$outExe = Join-Path $outDir 'VoxGard.exe'
if (Test-Path $outExe) { Remove-Item $outExe -Force }

Write-Host "Export ediliyor..."
& $bin --headless --path $root --export-release 'Windows Desktop' $outExe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outExe)) {
    Write-Error "Export basarisiz (exit $LASTEXITCODE)"
    exit 1
}
$mb = [Math]::Round((Get-Item $outExe).Length / 1MB, 1)
Write-Host "EXPORT_OK $outExe ($mb MB)"
Write-Host "Arkadasina sadece VoxGard.exe dosyasini gonder; Godot kurmasi gerekmez."
