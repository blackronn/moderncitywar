# Portable Godot 4.6.3'u (konsol exe dahil) %USERPROFILE%\Tools\Godot altina indirir.
$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:USERPROFILE 'Tools\Godot'
$exe = Join-Path $dest 'Godot_v4.6.3-stable_win64_console.exe'
$url = 'https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_win64.exe.zip'
$zip = Join-Path $env:TEMP 'godot463.zip'

if (Test-Path $exe) {
    Write-Host "Godot 4.6.3 zaten kurulu: $dest"
    exit 0
}
New-Item -ItemType Directory -Force $dest | Out-Null
Write-Host 'Godot 4.6.3 indiriliyor (~60 MB)...'
curl.exe -L --retry 3 -o $zip $url
if ($LASTEXITCODE -ne 0) { Write-Error "Indirme basarisiz: $url"; exit 1 }
Expand-Archive $zip -DestinationPath $dest -Force
Remove-Item $zip
Write-Host "Tamam: $dest"
