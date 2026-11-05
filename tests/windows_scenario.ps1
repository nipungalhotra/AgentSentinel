<#
  End-user scenario on a real Windows machine (run by CI under Windows PowerShell 5.1):
  install from the repo, let it hook Claude Code, run the hook exactly as an agent would
  (through cmd.exe and through Git Bash), approve/deny from the CLI, then uninstall.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function Check($cond, $msg) { if (-not $cond) { throw "FAILED: $msg" } else { Write-Host "ok  $msg" } }

# Pretend Claude Code is installed, with an existing setting that must survive.
New-Item -ItemType Directory -Force (Join-Path $HOME '.claude') | Out-Null
$settings = Join-Path $HOME '.claude\settings.json'
Set-Content -Encoding ASCII -Path $settings -Value '{"model":"opus"}'

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'packaging\install.ps1')
Check ($LASTEXITCODE -eq 0) 'install.ps1 succeeded'
$cli = Join-Path $env:LOCALAPPDATA 'Loggdin\bin\loggdin.cmd'

$cfg = Get-Content $settings -Raw | ConvertFrom-Json
Check ($cfg.model -eq 'opus') 'existing Claude Code settings kept'
$hook = $cfg.hooks.PermissionRequest[0].hooks[0].command
Write-Host "hook command: $hook"
Check ($hook -match 'sentinel-hook' -and $hook -match '--agent claude-code') 'PermissionRequest hook registered'

$work = Join-Path $env:TEMP 'lgscenario'
New-Item -ItemType Directory -Force $work | Out-Null

function Ask($command, $shell) {
  $in = Join-Path $work 'in.json'; $out = Join-Path $work "out-$shell.json"
  Remove-Item -ErrorAction SilentlyContinue $out
  $payload = @{ hook_event_name = 'PermissionRequest'; session_id = 's1'; cwd = $HOME; tool_name = 'Bash';
                tool_input = @{ command = $command } } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($in, $payload)
  if ($shell -eq 'cmd') {
    $script = Join-Path $work 'run.cmd'
    [IO.File]::WriteAllText($script, "@$hook < `"$in`" > `"$out`"`r`n")
    $p = Start-Process -FilePath cmd.exe -ArgumentList '/d', '/c', "`"$script`"" -NoNewWindow -PassThru
  } else {
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    $script = Join-Path $work 'run.sh'
    [IO.File]::WriteAllText($script, "$hook < '$($in -replace '\\','/')' > '$($out -replace '\\','/')'`n")
    $p = Start-Process -FilePath $bash -ArgumentList ($script -replace '\\', '/') -NoNewWindow -PassThru
  }
  for ($i = 0; $i -lt 100; $i++) {
    $pending = & $cli pending --json | Out-String
    if ($pending -match [regex]::Escape($command)) { break }
    Start-Sleep -Milliseconds 100
  }
  Check ($pending -match [regex]::Escape($command)) "[$shell] request '$command' reached loggdin"
  return @{ Process = $p; Out = $out }
}

foreach ($shell in @('cmd', 'bash')) {
  $a = Ask "rm -rf build-$shell" $shell
  & $cli deny | Out-Host
  $a.Process.WaitForExit(30000) | Out-Null
  $r = Get-Content $a.Out -Raw | ConvertFrom-Json
  Check ($r.hookSpecificOutput.decision.behavior -eq 'deny') "[$shell] agent received deny"

  $a = Ask "npm test-$shell" $shell
  & $cli allow once | Out-Host
  $a.Process.WaitForExit(30000) | Out-Null
  $r = Get-Content $a.Out -Raw | ConvertFrom-Json
  Check ($r.hookSpecificOutput.decision.behavior -eq 'allow') "[$shell] agent received allow"
}

# Daemon comes back on demand after being stopped.
& $cli stop | Out-Host
$a = Ask 'make build' 'cmd'
& $cli allow once | Out-Host
$a.Process.WaitForExit(30000) | Out-Null
$r = Get-Content $a.Out -Raw | ConvertFrom-Json
Check ($r.hookSpecificOutput.decision.behavior -eq 'allow') 'daemon restarted on demand by the hook'

$run = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name loggdin -ErrorAction SilentlyContinue
Check ($run -and $run.loggdin -match 'pyw') 'windowless autostart registered'

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'packaging\install.ps1') -Uninstall
$after = Get-Content $settings -Raw
Check (-not ($after -match 'sentinel-hook')) 'uninstall removed the Claude Code hooks'
Check ((Get-Content $settings -Raw | ConvertFrom-Json).model -eq 'opus') 'settings still intact after uninstall'
Check (-not (Test-Path $cli)) 'CLI removed'
Write-Host 'Windows end-user scenario passed.'
