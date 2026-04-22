# 1. Define the path at the TOP of the script (Global Scope)
$venvPath = Join-Path $PSScriptRoot "snmp_env_stable"
$pythonInVenv = Join-Path $venvPath "Scripts\python.exe"

function Ensure-SnmpEnv {
    # 1. If it venv exists with python inside, return
    if (Test-Path $pythonInVenv) {
		# Write-Host "[+] Check SNMPv3 support" -ForegroundColor Yellow
		# Invoke-SnmpPatch -VenvPath $venvPath
        return $true
    }

    Write-Host "[!] Environment not found. Searching PATH for Python 3.11/3.12..." -ForegroundColor Yellow

    $stablePython = Get-Command python.exe -All -ErrorAction SilentlyContinue | 
                    Where-Object { (& $_.Source --version 2>&1) -match "3\.(11|12)" } | 
                    Select-Object -First 1 -ExpandProperty Source

    if (-not $stablePython) { 
        Write-Host "[-] No compatible Python found. Please install 3.11 or 3.12." -ForegroundColor Red
        return $false 
    }

    Write-Host "[+] Found compatible blueprint: $stablePython"
    Write-Host "[*] Creating venv and installing libraries..." -ForegroundColor Cyan
    
    # 2. Original creation and install logic
    & $stablePython -m venv "$venvPath"
    & (Join-Path $venvPath "Scripts\pip.exe") install "snmpsim==1.1.7" "pysnmp==6.2.6" pysnmp-mibs lxml --quiet
    Write-Host "[+] venv created!" -ForegroundColor Green
    Start-Sleep -Seconds 2
	# 3. THE NEW PART: Patch the source code to unlock SNMPv3
    Invoke-SnmpPatch -VenvPath $venvPath
    
    Write-Host "[+] Setup Complete and SNMPv3 Unlocked!" -ForegroundColor Green
    Read-Host "Press Enter to continue to the Manager"
    return $true
}

# Helper function used inside Ensure-SnmpEnv to keep code clean
function Invoke-SnmpPatch {
    param($VenvPath)
    
    # Path inside the venv to the recorder script
    $targetFile = Join-Path $VenvPath "Lib\site-packages\snmpsim\commands\cmd2rec.py"
    
    if (Test-Path $targetFile) {
        $content = Get-Content -Path $targetFile -Raw
        
        $old1 = 'SNMPv1/v2c parameters'
        $new1 = 'SNMPv1/v2c/3 parameters'
        $old2 = '["1", "2c"]'
        $new2 = '["1", "2c", "3"]'
        $old3 = 'SNMPv1/v2c protocol version'
        $new3 = 'SNMPv1/v2c/3 protocol version'

        # Use .Contains() to see if the patch is needed
        if ($content.Contains($old2)) {
            Write-Host "[*] Re-enable SNMPv3 selection in recorder.py..." -ForegroundColor Cyan
            
            # Chain all three replacements
            $content = $content.Replace($old1, $new1).Replace($old2, $new2).Replace($old3, $new3)
            
            # Save back to file
            [System.IO.File]::WriteAllText($targetFile, $content)
            Write-Host "[+] File patched successfully." -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host "[i] Patch already applied or string mismatch." -ForegroundColor Gray
			   Start-Sleep -Seconds 1
        }
    } 
	else {
		Write-Host "[i] File not found." -ForegroundColor Gray
		Start-Sleep -Seconds 3
	}
}

# Script START.
Clear-Host
$setupSuccess = Ensure-SnmpEnv

if (-not $setupSuccess) { 
    Write-Host "[!] ERROR: No compatible Python (3.11/3.12) found in PATH."
    exit 1 
}
# Going into virtualEnvironment
$activateScript = Join-Path $venvPath "Scripts\Activate.ps1"

# Delete previous temporary folders, if exists
$oldTemps = Get-ChildItem -Path $PSScriptRoot -Filter "temp_snmp_*" -Directory -ErrorAction SilentlyContinue
if ($oldTemps) {
    Write-Host "[!] Cleaning up leftover temporary directories..." -ForegroundColor DarkGray
    $oldTemps | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# Main cycle - Menu
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
            $recorderExe = Join-Path $venvPath "Scripts\snmpsim-record-commands.exe"
            $skipCapture = $false
            
            Write-Host "Enter Target IP Address: " -ForegroundColor Cyan -NoNewline
            $ip = Read-Host
            
            Write-Host "`n--- Select SNMP Version ---" -ForegroundColor Yellow
            Write-Host "[1] SNMP v1"
            Write-Host "[2] SNMP v2c"
            Write-Host "[3] SNMP v3"
            Write-Host "Select version: " -ForegroundColor Cyan -NoNewline
            $verChoice = Read-Host

            # Initialize as array with spaces as separators
            $argList = @("--agent-udpv4-endpoint", "$($ip):161")

            switch ($verChoice) {
                "1" {
                    Write-Host "Enter Community v1 String: " -ForegroundColor Cyan -NoNewline
                    $community = Read-Host
                    $argList += "--protocol-version", "1"
                    $argList += "--community", $community
                }
                "2" {
                    Write-Host "Enter Community v2c String: " -ForegroundColor Cyan -NoNewline
                    $community = Read-Host
                    $argList += "--protocol-version", "2c"
                    $argList += "--community", $community
                }
                "3" {
                    Write-Host "Enter full pathname to v3 settings JSON file: " -ForegroundColor Cyan -NoNewline
                    $v3File = Read-Host
                    if (-not (Test-Path $v3File)) {
                        Write-Host "[-] ERROR: File not found!" -ForegroundColor Red
                        Start-Sleep -Seconds 2
                        $skipCapture = $true
                    } else {
                        $v3 = Get-Content $v3File | ConvertFrom-Json
						$argList += "--protocol-version", "3"
                        $argList += "--v3-user", $v3.user

                        if ($v3.auth_protocol -and $v3.auth_key) {
                            $argList += "--v3-auth-proto", $v3.auth_protocol
                            $argList += "--v3-auth-key", $v3.auth_key
                        
                            if ($v3.priv_protocol -and $v3.priv_key) {
                                $argList += "--v3-priv-proto", $v3.priv_protocol
                                $argList += "--v3-priv-key", $v3.priv_key
                            }
                        }
                        
					}
                }
                Default {
                    Write-Host "Invalid selection, returning to menu..." -ForegroundColor Yellow
                    $skipCapture = $true
                }
            }

            if (-not $skipCapture) {
                Write-Host "Enter Output Filename: " -ForegroundColor Cyan -NoNewline
                $dest = Read-Host
                if ($dest -notlike "*.snmprec") { $dest += ".snmprec" }
                $argList += "--output-file", $dest

                $argString = $argList -join " "
                Write-Host "`n[DEBUG] Executing: $recorderExe $argString" -ForegroundColor DarkYellow
                Write-Host "[!] Starting Capture. Press CTRL+C to stop." -ForegroundColor Green
				Start-Sleep -Seconds 2
                
                $job = Start-Process -FilePath $recorderExe -ArgumentList $argString -NoNewWindow -PassThru
                
                while (-not $job.HasExited) {
                    if (Test-Path $dest) {
                        $lastLine = Get-Content -Path $dest -Tail 1 -ErrorAction SilentlyContinue
                        if ($lastLine) { 
                            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -ForegroundColor Gray -NoNewline
                            Write-Host "Captured: " -NoNewline -ForegroundColor Cyan
                            Write-Host $lastLine -ForegroundColor White 
                        }
                    }
                    Start-Sleep -Seconds 5
                }
                Read-Host "`nCapture complete. Press Enter to return to menu..."
            }
        }
        
        "2" {
            $responderExe = Join-Path $venvPath "Scripts\snmpsim-command-responder.exe"
            Write-Host "Enter filename to play: " -ForegroundColor Cyan -NoNewline
            $file = Read-Host
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
			# We use a double-quoted string for the whole command so $activateScript expands correctly
			$action = ". '$activateScript'; Write-Host '--- SNMP VENV ACTIVE ---' -ForegroundColor Cyan; Write-Host '[!] Type ''exit'' to return to the Manager menu.' -ForegroundColor Yellow"
			powershell.exe -NoExit -ExecutionPolicy Bypass -Command $action
		}

        "0" { exit }
    }
} while ($choice -ne "0")
