# Uctan uca duman testi: 127.0.0.1'de host + istemci(ler) HEADLESS instance.
# Loopback oldugu icin Windows Firewall tetiklenmez. Basari kosulu: tum
# instance'lar exit 0 + loglarda SMOKE_PASS_HOST / SMOKE_PASS_CLIENT.
# Senaryolar: war | disconnect | metro (1 istemci), ffa (3 istemci, 4 oyuncu).
param([int]$TimeoutSec = 120, [string]$Scenario = 'war')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$bin = $env:GODOT_BIN
if (-not $bin) { $bin = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.6.3-stable_win64_console.exe' }
if (-not (Test-Path $bin)) { Write-Error "Godot yok: $bin"; exit 1 }

$clientCount = 1
if ($Scenario -eq 'ffa') { $clientCount = 3 }

$logDir = Join-Path $env:TEMP 'mcw_smoke'
New-Item -ItemType Directory -Force $logDir | Out-Null
$hostLog = Join-Path $logDir 'host.log'
$oldLogs = @($hostLog, "$hostLog.err")
for ($i = 1; $i -le 3; $i++) {
    $oldLogs += (Join-Path $logDir "client$i.log")
    $oldLogs += (Join-Path $logDir "client$i.log.err")
}
foreach ($f in $oldLogs) { if (Test-Path $f) { Remove-Item $f -Force } }

Write-Host "Host instance basliyor (senaryo: $Scenario, istemci: $clientCount)..."
$hostP = Start-Process -FilePath $bin `
    -ArgumentList @('--headless', '--path', $root, '--', '--smoke-host', '--speed=8', "--scenario=$Scenario") `
    -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err" -PassThru -NoNewWindow
$null = $hostP.Handle   # ExitCode'un okunabilmesi icin handle'i cikistan ONCE yakala (PS 5.1)
Start-Sleep -Seconds 3

$clients = @()
for ($i = 1; $i -le $clientCount; $i++) {
    Write-Host "Istemci $i basliyor..."
    $cLog = Join-Path $logDir "client$i.log"
    $cP = Start-Process -FilePath $bin `
        -ArgumentList @('--headless', '--path', $root, '--', '--smoke-join=127.0.0.1', '--speed=8', "--scenario=$Scenario") `
        -RedirectStandardOutput $cLog -RedirectStandardError "$cLog.err" -PassThru -NoNewWindow
    $null = $cP.Handle
    $clients += @{ Proc = $cP; Log = $cLog }
    Start-Sleep -Milliseconds 1200
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$timedOut = $false
foreach ($c in $clients) {
    $remainMs = [int][Math]::Max(1000, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $c.Proc.WaitForExit($remainMs)) { $timedOut = $true; break }
}
if (-not $timedOut) {
    if (-not $hostP.WaitForExit(30000)) { $timedOut = $true }
}
if ($timedOut) {
    Stop-Process -Id $hostP.Id -Force -ErrorAction SilentlyContinue
    foreach ($c in $clients) { Stop-Process -Id $c.Proc.Id -Force -ErrorAction SilentlyContinue }
    Write-Host 'SMOKE TIMEOUT'
    Get-Content $hostLog | Write-Host
    foreach ($c in $clients) { if (Test-Path $c.Log) { Get-Content $c.Log | Write-Host } }
    exit 1
}

$hostTxt = ''
if (Test-Path $hostLog) { $hostTxt = Get-Content $hostLog -Raw }
$pass = ($hostP.ExitCode -eq 0) -and ($hostTxt -match 'SMOKE_PASS_HOST')
foreach ($c in $clients) {
    $cTxt = ''
    if (Test-Path $c.Log) { $cTxt = Get-Content $c.Log -Raw }
    $pass = $pass -and ($c.Proc.ExitCode -eq 0) -and ($cTxt -match 'SMOKE_PASS_CLIENT')
}

if ($pass) {
    Write-Host 'SMOKE_OK'
    exit 0
}
Write-Host ("host exit={0}" -f $hostP.ExitCode)
Write-Host '--- HOST LOG ---'
Write-Host $hostTxt
if (Test-Path "$hostLog.err") { Write-Host (Get-Content "$hostLog.err" -Raw) }
$ci = 1
foreach ($c in $clients) {
    Write-Host ("--- CLIENT {0} LOG (exit={1}) ---" -f $ci, $c.Proc.ExitCode)
    if (Test-Path $c.Log) { Write-Host (Get-Content $c.Log -Raw) }
    if (Test-Path "$($c.Log).err") { Write-Host (Get-Content "$($c.Log).err" -Raw) }
    $ci++
}
Write-Host 'SMOKE_FAILED'
exit 1
