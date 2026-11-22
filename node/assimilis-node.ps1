<#
Assimilis Node for Windows: lend this PC's RAM (and GPU) to Assimilis Mobile's Devices & RAM pool,
or host a big model here using phones and other PCs as extra RAM.

  worker (default):  .\assimilis-node.ps1
  GPU worker:        .\assimilis-node.ps1 -Backend vulkan      (or cuda)
  host a model:      .\assimilis-node.ps1 -Mode host -Model C:\models\big.gguf -Workers 192.168.1.20:50052,192.168.1.21:50052

Uses llama.cpp release b11157, the same engine version as the app, so the RPC protocol matches (rpc7).
SECURITY: the worker has no password. Only run it on your own Wi-Fi or over Tailscale.
#>
param(
  [ValidateSet('worker', 'host')] [string]$Mode = 'worker',
  [ValidateSet('cpu', 'vulkan', 'cuda')] [string]$Backend = 'cpu',
  [int]$Port = 50052,
  [string]$Model = '',
  [string[]]$Workers = @(),
  [int]$HostPort = 8080
)
$ErrorActionPreference = 'Stop'
$Release = 'b11157'
$Asset = switch ($Backend) {
  'vulkan' { "llama-$Release-bin-win-vulkan-x64.zip" }
  'cuda'   { "llama-$Release-bin-win-cuda-12.4-x64.zip" }
  default  { "llama-$Release-bin-win-cpu-x64.zip" }
}
$Home_ = Join-Path $env:LOCALAPPDATA "AssimilisNode\$Release-$Backend"
$Exe = Join-Path $Home_ 'ggml-rpc-server.exe'

if (-not (Test-Path $Exe)) {
  Write-Host "Downloading llama.cpp $Release ($Backend) from github.com/ggml-org/llama.cpp ..." -ForegroundColor Magenta
  New-Item -ItemType Directory -Force $Home_ | Out-Null
  $zip = Join-Path $Home_ 'llama.zip'
  Invoke-WebRequest "https://github.com/ggml-org/llama.cpp/releases/download/$Release/$Asset" -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath $Home_ -Force
  Remove-Item $zip
}

$ips = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
  Select-Object -ExpandProperty IPAddress
$freeMb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)

if ($Mode -eq 'host') {
  if (-not (Test-Path $Model)) { throw "Give -Model path\to\model.gguf" }
  $server = Join-Path $Home_ 'llama-server.exe'
  $args_ = @('-m', $Model, '--host', '0.0.0.0', '--port', $HostPort, '-ngl', '99')
  if ($Workers.Count -gt 0) { $args_ += @('--rpc', ($Workers -join ',')) }
  Write-Host ""
  Write-Host "ASSIMILIS NODE · HOST" -ForegroundColor Magenta
  Write-Host "Model: $Model"
  if ($Workers.Count) { Write-Host "Using extra RAM from: $($Workers -join ', ')" }
  foreach ($ip in $ips) { Write-Host "In Assimilis Mobile > Models & Links (or A's brain), use base URL  http://${ip}:$HostPort/v1" -ForegroundColor Cyan }
  & $server @args_
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "ASSIMILIS NODE · RAM WORKER" -ForegroundColor Magenta
Write-Host "Lending this PC ($env:COMPUTERNAME, about $freeMb MB free) to your Assimilis devices."
Write-Host "On the phone: Devices & RAM > Add manually, then type one of:" -ForegroundColor Cyan
foreach ($ip in $ips) { Write-Host "    ${ip}:$Port" -ForegroundColor White }
Write-Host "Keep this window open while you use the model. Ctrl+C to stop."
Write-Host "Windows may ask to allow it through the firewall: allow Private networks only."
$threads = [Environment]::ProcessorCount
& $Exe -H 0.0.0.0 -p $Port -c -t $threads
