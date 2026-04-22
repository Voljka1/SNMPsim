function Ensure-SnmpEnv {
    $venvPath = Join-Path $PSScriptRoot "snmp_env_stable"
    $pythonInVenv = Join-Path $venvPath "Scripts\python.exe"

    if (Test-Path $pythonInVenv) { return $venvPath }

    Write-Host "[!] Environment not found. Searching PATH for Python 3.11/3.12..."

    $stablePython = Get-Command python.exe -All -ErrorAction SilentlyContinue | 
                    Where-Object { (& $_.Source --version 2>&1) -match "3\.(11|12)" } | 
                    Select-Object -First 1 -ExpandProperty Source

    if (-not $stablePython) { return $null }

    Write-Host "[+] Found compatible blueprint: $stablePython"
    Write-Host "[*] Creating venv and installing libraries (this takes a moment)..."
    
    & $stablePython -m venv "$venvPath"
    & (Join-Path $venvPath "Scripts\pip.exe") install "snmpsim==1.1.7" "pysnmp==6.2.6" pysnmp-mibs lxml
    
    Write-Host "[+] Setup Complete!"
    Read-Host "Press Enter to continue to the Manager"
    return $venvPath
}

# --- Main Manager Logic ---
$venv = Ensure-SnmpEnv

if ($null -eq $venv) { 
    Write-Host "[!] ERROR: No compatible Python (3.11/3.12) found in PATH."
    exit 1 
}

$activateScript = Join-Path $venv "Scripts\Activate.ps1"

# --- Cleanup Leftovers from Crashed Sessions ---
$oldTemps = Get-ChildItem -Path $PSScriptRoot -Filter "temp_snmp_*" -Directory -ErrorAction SilentlyContinue
if ($oldTemps) {
    Write-Host "[!] Cleaning up leftover temporary directories..." -ForegroundColor DarkGray
    $oldTemps | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

do {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "      SNMP MANAGER (VENV MODE)         " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host " [1]" -ForegroundColor White -NoNewline; Write-Host " Capture (Record)" -ForegroundColor Gray
    Write-Host " [2]" -ForegroundColor White -NoNewline; Write-Host " Replay (Respond)" -ForegroundColor Gray
    Write-Host " [3]" -ForegroundColor White -NoNewline; Write-Host " Enter Environment (Shell)" -ForegroundColor Gray
    Write-Host " [0]" -ForegroundColor Red   -NoNewline; Write-Host " Exit" -ForegroundColor Gray
    Write-Host "----------------------------------------" -ForegroundColor Magenta
    
    $choice = Read-Host " Select an option"

    switch ($choice) {
        "1" {
            $recorderExe = Join-Path $venv "Scripts\snmpsim-record-commands.exe"
            $ip = Read-Host "Enter Target IP Address"
            $community = Read-Host "Enter Community String"
            $dest = Read-Host "Enter Output Filename"
            if ($dest -notlike "*.snmprec") { $dest += ".snmprec" }
            
            $argList = @(
                "--agent-udpv4-endpoint=$($ip):161",
                "--community=$community",
                "--output-file=$dest"
            )

            Write-Host "[!] Starting Capture. Press CTRL+C to stop."
            $job = Start-Process -FilePath $recorderExe -ArgumentList $argList -PassThru -NoNewWindow
            
            while (-not $job.HasExited) {
                if (Test-Path $dest) {
                    $lastLine = Get-Content -Path $dest -Tail 1 -ErrorAction SilentlyContinue
                    if ($lastLine) { 
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -ForegroundColor Gray -NoNewline
                        Write-Host "Last captured OID: " -NoNewline -ForegroundColor Cyan
                        Write-Host $lastLine -ForegroundColor White 
                    }
                }
                Start-Sleep -Seconds 5
            }
            Read-Host "Capture complete. Press Enter..."
        }
        
        "2" {
            $responderExe = Join-Path $venv "Scripts\snmpsim-command-responder.exe"
            $file = Read-Host "Enter filename to play"
            if ($file -notlike "*.snmprec") { $file += ".snmprec" }

            if (-not (Test-Path $file)) {
                Write-Host "[-] ERROR: File not found!" -ForegroundColor Red
                Start-Sleep -Seconds 2
            } else {
                $tempDir = Join-Path $PSScriptRoot "temp_snmp_$(Get-Random)"
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                Copy-Item -Path $file -Destination $tempDir
                $commName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                Write-Host "`n[!] ACTIVE: Playing simulation" -ForegroundColor Green
                Write-Host "[!] Use Community String: " -NoNewline; Write-Host "$commName" -ForegroundColor Cyan
                Write-Host "[!] Port: 1161" -ForegroundColor Gray
                Write-Host "[!] Press CTRL+C to terminate simulation`n" -ForegroundColor Yellow
				Start-Sleep -Seconds 3
                & $responderExe --data-dir="$tempDir" --agent-udpv4-endpoint=0.0.0.0:1161
                Remove-Item -Path $tempDir -Recurse -Force
            }
        }

        "3" {
            Write-Host "`n[!] Launching Virtual Environment Shell..." -ForegroundColor Green
            # Using double single-quotes for the exit hint
            $action = ". '$activateScript'; Write-Host '--- SNMP VENV ACTIVE ---' -ForegroundColor Cyan; Write-Host '[!] Type ''exit'' to return to the Manager menu.' -ForegroundColor Yellow"
            powershell.exe -NoExit -ExecutionPolicy Bypass -Command $action
        }

        "0" { exit }
    }
} while ($choice -ne "0")