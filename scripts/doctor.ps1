# Checks that this machine can run the Likho stack: Docker, free ports, tools, memory.
$ErrorActionPreference = 'Continue'
$problems = 0
function Ok($text) { Write-Host "  ok    $text" }
function Bad($text) { Write-Host "  FIX   $text" -ForegroundColor Yellow; $script:problems++ }

Write-Host 'Docker'
docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -eq 0) {
  $mem = [math]::Round([double](docker info --format '{{.MemTotal}}') / 1GB, 1)
  Ok "daemon is running ($mem GB available to containers)"
} else { Bad 'Docker Desktop is not running. Start it and try again.' }

Write-Host 'Ports (from .env or defaults)'
$ports = @{ GATEWAY_PORT = 8080; POSTGRES_PORT = 5433; REDIS_PORT = 6380; MONGO_PORT = 27017; NATS_PORT = 4222; S3_PORT = 9000; MEILI_PORT = 7700 }
if (Test-Path "$PSScriptRoot\..\.env") {
  Get-Content "$PSScriptRoot\..\.env" | Where-Object { $_ -match '^\s*([A-Z_]+)=(\d+)' } | ForEach-Object { $ports[$Matches[1]] = [int]$Matches[2] }
}
foreach ($name in $ports.Keys | Sort-Object) {
  $port = $ports[$name]
  $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $conn) { Ok "$name $port is free"; continue }
  $owner = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).ProcessName
  if ($owner -match 'docker|wslrelay|vpnkit') { Ok "$name $port is held by Docker (the stack is up)" }
  else { Bad "$name $port is used by '$owner'. Set another port in .env." }
}

Write-Host 'Tools'
foreach ($tool in 'git', 'node', 'npm', 'uv', 'go') {
  if (Get-Command $tool -ErrorAction SilentlyContinue) { Ok $tool } else { Bad "$tool is not installed" }
}
foreach ($tool in 'gh', 'pnpm') {
  if (Get-Command $tool -ErrorAction SilentlyContinue) { Ok $tool } else { Write-Host "  note  $tool is not installed (needed for GitHub work / the web apps)" }
}

Write-Host 'Memory'
$os = Get-CimInstance Win32_OperatingSystem
$free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
if ($free -ge 3) { Ok "$free GB free of $total GB" } else { Bad "only $free GB free of $total GB; the speech model needs about 2.5 GB" }

if ($problems -eq 0) { Write-Host 'Ready.' } else { Write-Host "$problems thing(s) to fix." -ForegroundColor Yellow; exit 1 }
