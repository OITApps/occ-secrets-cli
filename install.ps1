<#
.SYNOPSIS
  Install occ-fetch-secret and occ-store-secret on Windows.

.DESCRIPTION
  Checks for winget, Azure CLI, and Python 3.8+. Offers to install missing
  prereqs via winget. Downloads the two scripts to $env:USERPROFILE\.local\bin
  and ensures it's on the User PATH. Creates batch shims so the scripts can be
  invoked without the .py extension.

.EXAMPLE
  irm https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0/install.ps1 | iex

.NOTES
  Requires Windows 10+ and PowerShell 5+ (default on supported Windows).
#>

[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:USERPROFILE ".local\bin"),
  [string]$RepoBase   = "https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0"
)

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "info: $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "ok:   $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "warn: $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "fail: $msg" -ForegroundColor Red; exit 1 }

function Prompt-YN($question) {
  $reply = Read-Host "$question [y/N]"
  return $reply -match '^(y|yes)$'
}

function Test-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# Refuse to overwrite reparse points (symlinks, junctions) at install destinations.
# A local attacker who pre-places a link at the target could redirect the write.
function Assert-NotReparsePoint($path) {
  $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Write-Fail "refusing to overwrite reparse point (symlink/junction) at $path"
  }
}

function Ensure-Winget {
  if (Test-Command winget) { return }
  Write-Warn2 "winget not found. winget ships with App Installer on Windows 10/11."
  Write-Warn2 "Install 'App Installer' from the Microsoft Store, then re-run this installer."
  Write-Fail "winget required for automatic prereq install on Windows."
}

function Install-Python {
  Ensure-Winget
  Write-Info "installing Python 3 via winget..."
  winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
  # Refresh PATH for current session
  $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}

function Install-AzCli {
  Ensure-Winget
  Write-Info "installing Azure CLI via winget..."
  winget install --id Microsoft.AzureCLI -e --accept-source-agreements --accept-package-agreements
  $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}

function Get-PythonCommand {
  # Returns the command to invoke Python 3 (either "python" or "py -3"), or $null.
  if (Test-Command python) {
    $v = (python --version 2>&1).Trim()
    if ($v -match '^Python 3\.') { return "python" }
  }
  if (Test-Command py) {
    $v = (py -3 --version 2>&1).Trim()
    if ($v -match '^Python 3\.') { return "py -3" }
  }
  return $null
}

function Check-Python {
  $script:PyCmd = Get-PythonCommand
  if (-not $script:PyCmd) {
    Write-Warn2 "Python 3 not found (checked: python, py -3)."
    if (Prompt-YN "Install Python 3?") { Install-Python; $script:PyCmd = Get-PythonCommand } else { Write-Fail "Python 3 required." }
  }
  if (-not $script:PyCmd) { Write-Fail "Python 3 still not found after install — open a new terminal and retry." }
  $verLine = (& cmd /c "$script:PyCmd --version 2>&1").Trim()
  if (-not ($verLine -match '^Python (\d+)\.(\d+)')) {
    Write-Fail "could not parse python version: $verLine"
  }
  $major = [int]$Matches[1]; $minor = [int]$Matches[2]
  Write-Ok "$script:PyCmd found: $verLine"
  if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
    Write-Fail "Python too old. Need >= 3.8; have $major.$minor."
  }
}

function Check-Az {
  if (-not (Test-Command az)) {
    Write-Warn2 "az CLI not found."
    if (Prompt-YN "Install Azure CLI?") { Install-AzCli } else { Write-Fail "az CLI required." }
  }
  Write-Ok "az CLI found: $((az --version 2>&1 | Select-Object -First 1))"
}

function Install-Scripts {
  if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null }
  # Under `irm | iex`, $MyInvocation.MyCommand.Path is null — skip local-copy mode in that case.
  $scriptDir = $null
  if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  }
  foreach ($name in @("occ-fetch-secret", "occ-store-secret")) {
    $target = Join-Path $InstallDir "$name.py"
    Write-Info "writing $target"
    Assert-NotReparsePoint $target
    $localCandidate = if ($scriptDir) { Join-Path $scriptDir $name } else { $null }
    $tmp = "$target.tmp"
    if ($localCandidate -and (Test-Path $localCandidate)) {
      Copy-Item -Path $localCandidate -Destination $tmp -Force
    } else {
      Invoke-WebRequest -Uri "$RepoBase/$name" -OutFile $tmp -UseBasicParsing
    }
    Move-Item -LiteralPath $tmp -Destination $target -Force
    # Shim: try py launcher first (most reliable on Windows), fall back to python.
    $shim = Join-Path $InstallDir "$name.cmd"
    Assert-NotReparsePoint $shim
    @"
@echo off
where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 "%~dp0$name.py" %*
  exit /b %ERRORLEVEL%
)
python "%~dp0$name.py" %*
"@ | Set-Content -Path $shim -Encoding ASCII
    Write-Ok "installed $name (+ shim $name.cmd)"
  }
}

function Ensure-Path {
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -split ";" -contains $InstallDir) {
    Write-Ok "$InstallDir already on User PATH"
    return
  }
  Write-Warn2 "$InstallDir is NOT on User PATH."
  if (Prompt-YN "Append it to your User PATH?") {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $InstallDir } else { "$userPath;$InstallDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path += ";$InstallDir"
    Write-Ok "updated User PATH — open a new terminal to pick it up everywhere."
  } else {
    Write-Warn2 "Skipped. Invoke scripts by full path, or add $InstallDir to PATH manually."
  }
}

function Seed-Config {
  $cfgDir = Join-Path $env:USERPROFILE ".claude"
  $cfg = Join-Path $cfgDir ".occ-vault.json"
  if (Test-Path $cfg) {
    Write-Ok "vault config already exists at $cfg"
    return
  }
  Assert-NotReparsePoint $cfg
  if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir | Out-Null }
  $upn = (az account show --query user.name -o tsv 2>$null)
  if ($upn -and $upn -like "*@*") {
    $user = ($upn -split "@")[0]
    $vault = "occ-secrets-$user"
    $cfgTmp = "$cfg.tmp"
    @{userVault = $vault} | ConvertTo-Json | Set-Content -Path $cfgTmp -Encoding UTF8
    Move-Item -LiteralPath $cfgTmp -Destination $cfg -Force
    Write-Ok "wrote $cfg with userVault: $vault"
  } else {
    Write-Warn2 "az not logged in — vault config not seeded. Run 'az login' then re-run, or set OCC_USER_VAULT."
  }
}

Write-Info "occ-secrets-cli installer (Windows)"
Check-Python
Check-Az
Install-Scripts
Ensure-Path
Seed-Config
Write-Host ""
Write-Ok "Done. Open a new terminal, then try:"
Write-Ok "  occ-fetch-secret --help"
Write-Ok "  occ-fetch-secret --vault company --list"
