<#
  Starts the whole Likho application on this machine, each service and web app in a window of its
  own, so the logs are visible and closing a window stops that part. Run it from likho-infra after
  `.\stack.ps1 up`. Parts already running (their port answers) are left alone.

    .\dev.ps1            start everything that is not running
    .\dev.ps1 status     what is running
    .\dev.ps1 stop       close the windows this script opened

  The repositories are expected side by side with likho-infra (D:\likho\likho-api, …).
#>
param(
  [ValidateSet('start', 'status', 'stop')][string]$Command = 'start',
  # Without windows, each part's log in %TEMP%\likho-logs: for starting it from a session that may
  # close (a remote session, an agent). The parts outlive that session.
  [switch]$Background
)

$root = Split-Path -Parent $PSScriptRoot
$pnpm = 'npx pnpm@10.34.6'

# Order matters for the first start: likho-transcription before likho-search (search reads transcripts).
$parts = @(
  @{ Name = 'likho-media';           Port = 4010; Dir = 'likho-media';           Run = 'go run ./cmd/likho-media' },
  @{ Name = 'likho-language';        Port = 4030; Dir = 'likho-language';        Run = 'uv run likho-language' },
  @{ Name = 'likho-transcription';   Port = 4020; Dir = 'likho-transcription';   Run = 'uv run likho-transcription' },
  @{ Name = 'likho-search';          Port = 4040; Dir = 'likho-search';          Run = 'go run ./cmd/likho-search' },
  @{ Name = 'likho-insights';        Port = 4050; Dir = 'likho-insights';        Run = 'uv run likho-insights' },
  @{ Name = 'likho-analytics';       Port = 4070; Dir = 'likho-analytics';       Run = 'go run ./cmd/likho-analytics' },
  @{ Name = 'likho-api';             Port = 4000; Dir = 'likho-api';             Run = "$pnpm build; node dist/main.js" },
  @{ Name = 'likho-connector-ameyo'; Port = 4060; Dir = 'likho-connector-ameyo'; Run = "$pnpm build; node dist/cli.js serve" },
  @{ Name = 'web-shell';             Port = 5173; Dir = 'likho-web-shell';       Run = "$pnpm exec vite --port 5173 --strictPort" },
  @{ Name = 'app-library';           Port = 5174; Dir = 'likho-mfe-library';     Run = "$pnpm exec vite --port 5174 --strictPort" },
  @{ Name = 'app-transcript';        Port = 5175; Dir = 'likho-mfe-transcript';  Run = "$pnpm exec vite --port 5175 --strictPort" },
  @{ Name = 'app-admin';             Port = 5176; Dir = 'likho-mfe-admin';       Run = "$pnpm exec vite --port 5176 --strictPort" },
  @{ Name = 'app-vocabulary';        Port = 5177; Dir = 'likho-mfe-vocabulary';  Run = "$pnpm exec vite --port 5177 --strictPort" },
  @{ Name = 'app-insights';          Port = 5178; Dir = 'likho-mfe-insights';    Run = "$pnpm exec vite --port 5178 --strictPort" }
)

function Test-Port([int]$Port) {
  [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

$pidFile = Join-Path $env:TEMP 'likho-dev-windows.txt'

switch ($Command) {
  'status' {
    foreach ($p in $parts) {
      $state = if (Test-Port $p.Port) { 'running' } else { 'stopped' }
      '{0,-24} {1,-6} {2}' -f $p.Name, $p.Port, $state
    }
    $gateway = if (Test-Port 8080) { 'running' } else { 'stopped (.\stack.ps1 up)' }
    '{0,-24} {1,-6} {2}' -f 'gateway (stack)', 8080, $gateway
  }
  'stop' {
    if (Test-Path $pidFile) {
      foreach ($id in Get-Content $pidFile) {
        # The window's PowerShell and everything it started.
        & taskkill /PID $id /T /F 2>$null | Out-Null
      }
      Remove-Item $pidFile
      'stopped what this script started'
    } else { 'no windows of this script are known' }
  }
  'start' {
    if (-not (Test-Port 8080)) { Write-Warning 'The stack is not running: start it first with .\stack.ps1 up' }
    foreach ($p in $parts) {
      if (Test-Port $p.Port) { "{0,-24} already running" -f $p.Name; continue }
      $dir = Join-Path $root $p.Dir
      if (-not (Test-Path $dir)) { Write-Warning "$($p.Dir) is not cloned next to likho-infra; skipped"; continue }
      if ($Background) {
        # Through Windows' process service, so the part outlives the session that started it.
        $logs = Join-Path $env:TEMP 'likho-logs'
        New-Item -ItemType Directory -Force $logs | Out-Null
        $log = Join-Path $logs "$($p.Name).log"
        $line = "powershell -NoProfile -WindowStyle Hidden -Command `"$($p.Run) *> '$log'`""
        $made = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $line; CurrentDirectory = $dir }
        Add-Content -Path $pidFile -Value $made.ProcessId
        "{0,-24} starting in the background (log: $log)" -f $p.Name
      } else {
        $title = "Likho - $($p.Name)"
        $script = "`$Host.UI.RawUI.WindowTitle = '$title'; Set-Location '$dir'; $($p.Run)"
        $window = Start-Process powershell -ArgumentList '-NoExit', '-Command', $script -PassThru
        Add-Content -Path $pidFile -Value $window.Id
        "{0,-24} starting in its own window" -f $p.Name
      }
      if ($p.Name -eq 'likho-transcription') {
        # Give it a head start so search finds it.
        for ($i = 0; $i -lt 40 -and -not (Test-Port 5020); $i++) { Start-Sleep 2 }
      }
    }
    ''
    'Open http://localhost:8080 once the windows say they are listening (the first start takes a minute or two).'
  }
}
