<#
.SYNOPSIS
    Snmpsim manager for creating a stable environment and running simulations.
	Used hardcoded Python and libraries versions. See function Ensure-SnmpEnv code.
	Use py for Python selection
.NOTES
    Author: Voljka + Copilot. He did it!
    Version: 1.2.1
#>

[CmdletBinding()]
param ()

# -----------------------------
# Configuration / constants
# -----------------------------

$dbFolder = "db"
$dbPath   = Join-Path $PSScriptRoot $dbFolder

$venvName     = "snmp_env_stable"
$venvPath     = Join-Path $PSScriptRoot $venvName
$pythonInVenv = Join-Path $venvPath "Scripts\python.exe"
$script:LastCaptureFile = $null

# -----------------------------
# Message helpers 
# -----------------------------

function Info($m)     { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m)     { Write-Host "[!] $m" -ForegroundColor Yellow }
function ErrorMsg($m) { Write-Host "[-] $m" -ForegroundColor Red }
function Dim($m)      { Write-Host "    $m" -ForegroundColor DarkGray }
function Choise($m)	  { Write-Host "    $m" -ForegroundColor White }

# -----------------------------
# Environment setup
# -----------------------------

function Ensure-SnmpEnv {

    if (Test-Path $pythonInVenv) {
        Ok "Virtual environment already exists"
		Start-Sleep 1
        return $true
    }

	if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        ErrorMsg "Python Launcher (py.exe) not found. Please install Python 3.11 or 3.12 with launcher enabled."
        ErrorMsg "Download: https://www.python.org/downloads/windows/"
		Info "py allows to use correct python version without setting PATH var"
        return $false
    }

    Warn "Environment not found. Using Python Launcher (py)"

    $pyExe  = "py"
    $pyArgs = $null

    foreach ($ver in "3.12","3.11") {
        try {
            & $pyExe "-$ver" --version *> $null
            $pyArgs = "-$ver"
            break
        } catch {}
    }

    if (-not $pyArgs) {
        ErrorMsg "Python 3.11.x or 3.12.x required (3.13+ NOT supported)"
        return $false
    }

    try {
        
		Info "Creating virtual environment (py $pyArgs)"
		& $pyExe $pyArgs -m venv "$venvPath" --clear

		# ---- hard validation: venv must exist ----
		if (-not (Test-Path $pythonInVenv)) {
			ErrorMsg "Python runtime $($pyArgs.TrimStart('-')) is not installed."
			ErrorMsg "Install it with:"
			ErrorMsg "  py install $($pyArgs.TrimStart('-'))"
			ErrorMsg "Or download from:"
			ErrorMsg "  https://www.python.org/downloads/windows/"
			return $false
		}

		$ver = & "$pythonInVenv" --version

        if ($ver -notmatch 'Python 3\.(11|12)\.') {
            throw "Unsupported Python runtime detected: $ver"
        }

        Info "Installing pinned dependencies"
        & $pythonInVenv -m pip install --upgrade pip --quiet
        & $pythonInVenv -m pip install snmpsim==1.1.7 pysnmp==6.2.6 pysnmp-mibs lxml --quiet

        Invoke-SnmpPatch -PythonExe $pythonInVenv

        Ok "Environment ready ($ver)"
		Start-Sleep 5
        return $true
    }
    catch {
        ErrorMsg $_.Exception.Message
        return $false
    }
}

# -----------------------------
# SNMPv3 unlock patch (Python-driven)
# -----------------------------

function Invoke-SnmpPatch {
    param (
        [Parameter(Mandatory)]
        [string] $PythonExe
    )

    Info "Checking SNMPv3 patch status"

    $tempPy = Join-Path $env:TEMP "snmpsim_patch.py"

@"
import sys
from pathlib import Path
import snmpsim.commands.cmd2rec as m

p = Path(m.__file__)
t = p.read_text(encoding="utf-8")

if 'choices=["1", "2c", "3"]' in t:
    print("[i] Patch already applied")
    sys.exit(0)

t = (
    t.replace('choices=["1", "2c"]', 'choices=["1", "2c", "3"]')
     .replace('SNMPv1/v2c parameters', 'SNMPv1/v2c/3 parameters')
     .replace('SNMPv1/v2c protocol version', 'SNMPv1/v2c/3 protocol version')
)

p.write_text(t, encoding="utf-8")
print("[+] SNMPv3 patch applied")
"@ | Set-Content -Path $tempPy -Encoding UTF8

    & "$PythonExe" "$tempPy"

    Remove-Item $tempPy -ErrorAction SilentlyContinue
}

# -----------------------------
# Menu UI
# -----------------------------

function Show-MainMenu {
    cls
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "      SNMP MANAGER (VENV MODE)          " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host " [1] Capture (Record)" -ForegroundColor Gray
    Write-Host " [2] Replay  (Respond)" -ForegroundColor Gray
    Write-Host " [3] Enter Environment (Shell)" -ForegroundColor Gray
    Write-Host " [0] Exit" -ForegroundColor Red
    Write-Host "----------------------------------------" -ForegroundColor Magenta
}

# -----------------------------
# Capture
# -----------------------------

function Start-Capture {

    $exe = Join-Path $venvPath "Scripts\snmpsim-record-commands.exe"
    if (-not (Test-Path $exe)) { throw "Recorder not found in venv" }

    $ip = Read-Host "Target IP"
    if (-not $ip) { throw "IP address required" }

    $args = @(
		"--agent-udpv4-endpoint",
		"$($ip):161"
	)

    Warn "Select SNMP version"
    Choise "[1] v1   [2] v2c   [3] v3"

    switch (Read-Host "Version") {
        "1" { $args += Get-SnmpV1V2Args "1" }
        "2" { $args += Get-SnmpV1V2Args "2c" }
        "3" { $args += Get-SnmpV3Args }
        default { throw "Invalid SNMP version" }
    }

    $file = Read-Host "Output file"
    if (-not $file) { throw "Output file required" }
    if ($file -notlike "*.snmprec") { $file += ".snmprec" }

    $out = Join-Path $PSScriptRoot $file
    New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null

    $args += "--output-file",$out
	
	$script:LastCaptureFile = $out
    
	Warn "Press Ctrl-C to stop capture"
	Info "Starting capture"

	& "$exe" $args
	
}

function Get-SnmpV1V2Args($proto) {
    $c = Read-Host "Community"
    if (-not $c) { throw "Community string required" }
    return @("--protocol-version",$proto,"--community",$c)
}

function Get-SnmpV3Args {
    $f = Read-Host "Path to SNMPv3 JSON"
    if (-not (Test-Path $f)) { throw "JSON file not found" }

    $v = Get-Content $f | ConvertFrom-Json
    $a = @("--protocol-version","3","--v3-user",$v.user)

    if ($v.auth_protocol) {
        $a += "--v3-auth-proto",$v.auth_protocol,"--v3-auth-key",$v.auth_key
    }
    if ($v.priv_protocol) {
        $a += "--v3-priv-proto",$v.priv_protocol,"--v3-priv-key",$v.priv_key
    }
    return $a
}

# -----------------------------
# Replay
# -----------------------------

function Start-Replay {

    $exe = Join-Path $venvPath "Scripts\snmpsim-command-responder.exe"
    if (-not (Test-Path $exe)) { throw "Responder not found in venv" }

    $f = Read-Host "Recording name in $dbPath"
    if (-not $f) { throw "Recording name required" }
    if ($f -notlike "*.snmprec") { $f += ".snmprec" }

    $src = Join-Path $dbPath $f
    if (-not (Test-Path $src)) { throw "Recording not found" }

    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    $work = Join-Path $PSScriptRoot "work_$name"
    New-Item -ItemType Directory $work -Force | Out-Null
    Copy-Item $src (Join-Path $work $f) -Force
	
	$community = [System.IO.Path]::GetFileNameWithoutExtension($f)
	
    cls
    Ok "Starting simulation"
    Dim "Workspace: $work"
	Ok "Listen at Port: 1162, v2 Community: $community"
    Warn "Press CTRL+C to stop"
	Start-Sleep 5
    & $exe "--data-dir=$work" "--cache-dir=$work" "--agent-udpv4-endpoint=0.0.0.0:1161"
}

# -----------------------------
# Venv shell
# -----------------------------

function Enter-VenvShell {

    $act = Join-Path $venvPath "Scripts\Activate.ps1"
    if (-not (Test-Path $act)) { throw "Activate.ps1 not found" }
	cls
    Warn "Launching virtual environment shell"
	Info "Type 'exit' for exit"
    powershell -NoExit -ExecutionPolicy Bypass `
        -Command ". '$act'; Write-Host '--- SNMP VENV ACTIVE ---' -ForegroundColor Cyan"
}

# -----------------------------
# Main
# -----------------------------

function Main {

    if (-not (Ensure-SnmpEnv)) { return }

    $actions = @{
        "1" = { Start-Capture }
        "2" = { Start-Replay }
        "3" = { Enter-VenvShell }
    }

    do {
        Show-MainMenu
        $c = Read-Host "Select option"

        if ($c -eq "0") { break }

        try {
            if ($actions.ContainsKey($c)) {
                & $actions[$c]
            } else {
                Warn "Invalid menu option"
				Start-Sleep 1
            }
        }
        catch {
            ErrorMsg $_
            Start-Sleep 2
        }
    } while ($true)
}

# -----------------------------
# Entry point guard
# -----------------------------

if ($MyInvocation.InvocationName -ne '.') {
    Main
}