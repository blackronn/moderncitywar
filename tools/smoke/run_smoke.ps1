# Uctan uca duman testi: 127.0.0.1'de host + istemci iki HEADLESS instance.
# Loopback oldugu icin Windows Firewall tetiklenmez. Basari kosulu: iki
# instance da exit 0 + loglarda SMOKE_PASS_HOST / SMOKE_PASS_CLIENT.
param([int]$TimeoutSec = 120)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) { Write-Error "Godot yok: $bin"; exit 1 }

$logDir = Join-Path $env:TEMP 'mcw_smoke'
New-Item -ItemType Directory -Force $logDir | Out-Null
$hostLog = Join-Path $logDir 'host.log'
$clientLog = Join-Path $logDir 'client.log'
foreach ($f in @($hostLog, $clientLog, "$hostLog.err", "$clientLog.err")) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

Write-Host 'Host instance basliyor...'
$hostP = Start-Process -FilePath $bin `
    -ArgumentList @('--headless', '--path', $root, '--', '--smoke-host', '--speed=8') `
    -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err" -PassThru -NoNewWindow
$null = $hostP.Handle   # ExitCode'un okunabilmesi icin handle'i cikistan ONCE yakala (PS 5.1)
Start-Sleep -Seconds 3
Write-Host 'Istemci instance basliyor...'
$clientP = Start-Process -FilePath $bin `
    -ArgumentList @('--headless', '--path', $root, '--', '--smoke-join=127.0.0.1', '--speed=8') `
    -RedirectStandardOutput $clientLog -RedirectStandardError "$clientLog.err" -PassThru -NoNewWindow
$null = $clientP.Handle

if (-not $clientP.WaitForExit($TimeoutSec * 1000)) {
    Stop-Process -Id $clientP.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $hostP.Id -Force -ErrorAction SilentlyContinue
    Write-Host 'SMOKE TIMEOUT (istemci bitmedi)'
    Get-Content $hostLog, $clientLog | Write-Host
    exit 1
}
if (-not $hostP.WaitForExit(30000)) {
    Stop-Process -Id $hostP.Id -Force -ErrorAction SilentlyContinue
    Write-Host 'SMOKE TIMEOUT (host bitmedi)'
    Get-Content $hostLog, $clientLog | Write-Host
    exit 1
}

$hostTxt = ''
$clientTxt = ''
if (Test-Path $hostLog) { $hostTxt = Get-Content $hostLog -Raw }
if (Test-Path $clientLog) { $clientTxt = Get-Content $clientLog -Raw }
$pass = ($hostP.ExitCode -eq 0) -and ($clientP.ExitCode -eq 0) -and `
    ($hostTxt -match 'SMOKE_PASS_HOST') -and ($clientTxt -match 'SMOKE_PASS_CLIENT')

if ($pass) {
    Write-Host 'SMOKE_OK'
    exit 0
}
Write-Host ("host exit={0} client exit={1}" -f $hostP.ExitCode, $clientP.ExitCode)
Write-Host '--- HOST LOG ---'
Write-Host $hostTxt
if (Test-Path "$hostLog.err") { Write-Host (Get-Content "$hostLog.err" -Raw) }
Write-Host '--- CLIENT LOG ---'
Write-Host $clientTxt
if (Test-Path "$clientLog.err") { Write-Host (Get-Content "$clientLog.err" -Raw) }
Write-Host 'SMOKE_FAILED'
exit 1
