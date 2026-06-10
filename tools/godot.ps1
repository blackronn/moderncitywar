# Pinlenmis Godot konsol binary'sini calistirir; GODOT_BIN env ile override edilebilir.
# Konsol exe sart: GUI exe PowerShell'e stdout/stderr basmaz.
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) {
    Write-Error "Godot bulunamadi: $bin -- tools/setup_godot.ps1 calistir veya GODOT_BIN ayarla."
    exit 1
}
& $bin @args
exit $LASTEXITCODE
