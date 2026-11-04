<#
  loggdin - Windows installer (per-user, no admin rights needed).

    powershell -ExecutionPolicy Bypass -File install.ps1              # install + hook detected agents
    powershell -ExecutionPolicy Bypass -File install.ps1 -NoAgents    # don't touch agent configs
    powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#>
param(
  [switch]$NoAgents,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$SrcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinSrc = if (Test-Path (Join-Path $SrcDir 'loggdin.py')) { $SrcDir } else { Join-Path $SrcDir '..\bin' }

function Find-Python {
  foreach ($spec in @('py -3', 'python', 'python3')) {
    $c = $spec -split ' '   # (nested one-item arrays would be flattened by PowerShell)
    $exe = Get-Command $c[0] -ErrorAction SilentlyContinue
    if (-not $exe) { continue }
    # Skip the Microsoft Store "python" stub, which only opens the Store.
    if ($exe.Source -like '*\WindowsApps\*') { continue }
    $pyArgs = @($c | Select-Object -Skip 1) + @('-c', 'import sys; print(sys.executable) if sys.version_info >= (3, 9) else sys.exit(1)')
    $path = & $exe.Source @pyArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $path) { return $path.Trim() }
  }
  return $null
}

$Python = Find-Python
if (-not $Python) {
  Write-Host 'Python 3.9+ is required. Install it from https://www.python.org/downloads/windows/ (tick "Add python.exe to PATH") and re-run.' -ForegroundColor Red
  exit 1
}

$StateDir = Join-Path $env:APPDATA 'Loggdin'
$ShimDir  = Join-Path $env:LOCALAPPDATA 'Loggdin\bin'
$Shim     = Join-Path $ShimDir 'loggdin.cmd'
$Script   = Join-Path $StateDir 'loggdin.py'

if ($Uninstall) {
  if (Test-Path $Script) {
    & $Python $Script uninstall all
    & $Python $Script autostart off
    & $Python $Script stop
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $Shim
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath) {
    $kept = ($userPath -split ';' | Where-Object { $_ -and ($_ -ne $ShimDir) }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $kept, 'User')
  }
  Write-Host "loggdin removed. Rules and audit log are kept in $StateDir (delete it to erase them)."
  exit 0
}

Write-Host "Installing loggdin for Windows with $Python"
& $Python (Join-Path $BinSrc 'loggdin.py') deploy
if ($LASTEXITCODE -ne 0) { throw 'deploy failed' }

New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null
# Prefer the version-independent py launcher so the command survives Python upgrades.
$Launcher = Get-Command py -ErrorAction SilentlyContinue
$Runner = if ($Launcher) { "`"$($Launcher.Source)`" -3" } else { "`"$Python`"" }
Set-Content -Path $Shim -Encoding ASCII -Value "@echo off`r`n$Runner `"$Script`" %*"
Write-Host "CLI installed: $Shim"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $ShimDir)) {
  [Environment]::SetEnvironmentVariable('Path', (@($userPath, $ShimDir) | Where-Object { $_ }) -join ';', 'User')
  Write-Host "Added $ShimDir to your PATH (open a new terminal to use 'loggdin')."
}

& $Python $Script autostart on
& $Python $Script start
if (-not $NoAgents) { & $Python $Script install detected }

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host 'Node.js not found: needed only for the MCP integration (Cursor / Claude Desktop).'
}
Write-Host ''
Write-Host "Done. Approve requests with:  loggdin ui   (or: loggdin allow / loggdin deny)" -ForegroundColor Green
