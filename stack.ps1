<#
  Likho local stack helper for Windows.

    .\stack.ps1 up        start databases, event bus, object store, search, gateway and wait until healthy
    .\stack.ps1 obs       also start Grafana (logs, traces, metrics) - about 1 GB of RAM
    .\stack.ps1 smoke     run the checks in scripts/smoke.sh
    .\stack.ps1 ps        what is running, with memory use
    .\stack.ps1 logs nats follow the logs of one service (or all)
    .\stack.ps1 down      stop everything, keep the data
    .\stack.ps1 reset     stop everything and DELETE the data (asks first)
    .\stack.ps1 doctor    check Docker, ports and tools
#>
param(
  [Parameter(Position = 0)][ValidateSet('up', 'obs', 'smoke', 'ps', 'logs', 'down', 'reset', 'doctor')][string]$Command = 'ps',
  [Parameter(Position = 1)][string]$Service = ''
)
# Docker writes its progress to stderr. With 'Stop', Windows PowerShell turns that into an error as soon
# as output is redirected, so failures are detected from exit codes instead.
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

function Start-Stack([string[]]$Profiles) {
  # Long-running services first; "up --wait" fails if a one-shot job exits, so those run afterwards.
  docker compose @Profiles up -d --wait
  if ($LASTEXITCODE -ne 0) { throw 'The stack did not become healthy. Run: .\stack.ps1 logs' }
  foreach ($job in 'init-nats', 'init-objectstore') {
    docker compose --profile infra --profile init run --rm $job
    if ($LASTEXITCODE -ne 0) { throw "Setup job $job failed." }
  }
  'Stack is up.'
}

switch ($Command) {
  'up'    { Start-Stack @('--profile', 'infra') }
  'obs'   { Start-Stack @('--profile', 'infra', '--profile', 'obs') }
  'smoke' { & "$env:ProgramFiles\Git\bin\bash.exe" scripts/smoke.sh }
  'ps'    {
    docker compose --profile infra --profile obs ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Health}}\t{{.Ports}}'
    docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'
  }
  'logs'  { if ($Service) { docker compose logs -f --tail 100 $Service } else { docker compose --profile infra --profile obs logs -f --tail 50 } }
  'down'  { docker compose --profile infra --profile obs --profile init down }
  'reset' {
    $answer = Read-Host 'This deletes every local database, stream, bucket and index of the Likho stack. Type DELETE to continue'
    if ($answer -ceq 'DELETE') { docker compose --profile infra --profile obs --profile init down --volumes } else { 'Nothing deleted.' }
  }
  'doctor' { & "$PSScriptRoot\scripts\doctor.ps1" }
}
exit $LASTEXITCODE
