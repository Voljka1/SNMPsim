<#
.SYNOPSIS
    Snmpsim manager for creating a stable environment and running simulations.
.EXAMPLE
    .\snmpsim.ps1
    Explains how to run the script and what the expected output is.

.NOTES
    Author:       Voljka
    Date:         2026-04-23
    Version:      1.1.0
    GitHub/Wiki:  https://github.com/Voljka1
    
    Change Log:
    v1.0.0 (2026-04-22) - Initial Release
	v1.1.0 (2026-04-22) - Cleanup code
	v1.2.0 (2026-04-24) - snmpsim-command-responder use persistent folder,
						  second run use already compiled index files.
						  persistent workplace in script working wolder,
						  easy to delete, when not needed.
#>

[CmdletBinding()]
param ()

# --- Configuration ---
$venvName      = "snmp_env_stable"
$dbFolder	   = "db"
$venvPath      = Join-Path $PSScriptRoot $venvName
$dbPath 	   = Join-Path $PSScriptRoot $dbFolder	
$pythonInVenv  = Join-Path $venvPath "Scripts\python.exe"
$pipInVenv     = Join-Path $venvPath "Scripts\pip.exe"

# --- Functions ---

function Ensure-SnmpEnv {
    if (Test-Path $pythonInVenv) { return $true }

    Write-Host "[!] Environment not found. Searching for Python 3.11/3.12..." -ForegroundColor Yellow

    # Find Python
    $stablePython = Get-Command python.exe -All -ErrorAction SilentlyContinue | 
                    Where-Object { (& $_.Source --version 2>&1) -match "3\.(11|12)" } | 
                    Select-Object -First 1 -ExpandProperty Source
	
    if (-not $stablePython) { 
        Write-Host "[-] ERROR: No compatible Python found. Please install 3.11 or 3.12." -ForegroundColor Red
        return $false 
    }

    try {
        Write-Host "[*] Creating virtual environment at: $venvPath" -ForegroundColor Cyan
        & $stablePython -m venv "$venvPath" --clear
        
        Write-Host "[*] Upgrading pip and installing snmpsim dependencies..." -ForegroundColor Cyan
        & $pythonInVenv -m pip install --upgrade pip --quiet
        & $pipInVenv install "snmpsim==1.1.7" "pysnmp==6.2.6" pysnmp-mibs lxml --quiet
        
        Invoke-SnmpPatch -VenvPath $venvPath
        
        Write-Host "[+] Setup Complete!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[-] Failed to set up environment: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-SnmpPatch {
    param($VenvPath)
    
    $targetFile = Join-Path $VenvPath "Lib\site-packages\snmpsim\commands\cmd2rec.py"
    
    if (-not (Test-Path $targetFile)) {
        Write-Host "[i] Patch target not found. Skipping." -ForegroundColor Gray
        return
    }

    try {
        $content = Get-Content -Path $targetFile -Raw
        
        # This is our 'anchor'. It's very specific to the version selection logic.
        $targetPattern = '["1", "2c"]'
        
        if ($content.Contains($targetPattern)) {
            Write-Host "[*] Target found. Applying SNMPv3 unlock..." -ForegroundColor Cyan
            
            # We only replace these specific strings. 
            # Using the .Replace() method on the whole string is fine as long as 
            # we know the 'anchor' exists, but let's be even more precise:
            $content = $content.
							Replace('choices=["1", "2c"]', 'choices=["1", "2c", "3"]').
                            Replace('help="SNMPv1/v2c parameters"', 'help="SNMPv1/v2c/3 parameters"').
                            Replace('help="SNMPv1/v2c protocol version"', 'help="SNMPv1/v2c/3 protocol version"')
            
            [System.IO.File]::WriteAllText($targetFile, $content)
            Write-Host "[+] Patch applied successfully." -ForegroundColor Green
        }
        else {
            Write-Host "[i] Patch already applied or file structure has changed." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "[!] Error during patching: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Main Execution ---
cls
if (-not (Ensure-SnmpEnv)) { exit 1 }

# Going into virtualEnvironment
$activateScript = Join-Path $venvPath "Scripts\Activate.ps1"

# Main cycle - Menu
do {
    cls
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
			
			# Build parameters for SNMP flavor
			switch ($verChoice) {
                { $_ -eq "1" -or $_ -eq "2" } {
					$community = Read-Host "Enter Community String"
        
					# Add protocol version
					$proto = if ($_ -eq "1") { "1" } else { "2c" }
					$argList += "--protocol-version", $proto
        
					# Add the community string. 
					# We wrap it in quotes here just to be safe for the .exe
					$argList += "--community", "`"$community`""
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
                # What? 3 choices not enough? Sorry.
				Default {
                    Write-Host "Invalid selection, returning to menu..." -ForegroundColor Yellow
                    $skipCapture = $true
                }
            }
			# Where to store captured data
            if (-not $skipCapture) {
                Write-Host "Enter Output Filename: " -ForegroundColor Cyan -NoNewline
                $dest = Read-Host
                # 1. Finalize the path logic first
				if ($dest -notlike "*.snmprec") { $dest += ".snmprec" }
                # THIS IS YOUR CLEAN PATH (No quotes)
				$cleanPath = Join-Path $PSScriptRoot $dest
				# 2. Make sure the folder exists
				$null = New-Item -ItemType Directory -Path (Split-Path $cleanPath) -Force

				# 3. Add to arguments (Wrap it in quotes ONLY here)
				$argList += "--output-file", "`"$cleanPath`""

				# 4. Start the work
				$job = Start-Process -FilePath $recorderExe -ArgumentList $argList -NoNewWindow -PassThru
				
				# 5. Monitor the file (Use the CLEAN path here)
				while (-not $job.HasExited) {
					if (Test-Path $cleanPath) { 
						$lastLine = Get-Content $cleanPath -Tail 1 -ErrorAction SilentlyContinue
						if ($lastLine) { 
                            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -ForegroundColor Gray -NoNewline
                            Write-Host "Captured: " -NoNewline -ForegroundColor Cyan
                            Write-Host $lastLine -ForegroundColor White 
                        }
                    }
					# Do not remove, this is 5 sec delay between peeking.
                    Start-Sleep -Seconds 5
                }
                Read-Host "`nCapture complete. Press Enter to return to menu..."
            }
        }
				
		"2" {
            $responderExe = Join-Path $venvPath "Scripts\snmpsim-command-responder.exe"

            Write-Host "Enter filename from \$dbFolder\ to play: " -ForegroundColor Cyan -NoNewline
            $fileInput = Read-Host
            
            if ($fileInput -notlike "*.snmprec") { $fileInput += ".snmprec" }
            $sourceFile = Join-Path $dbPath $fileInput

            if (-not (Test-Path $sourceFile)) {
                Write-Host "[-] ERROR: File $fileInput not found in $dbPath" -ForegroundColor Red
                Start-Sleep -Seconds 2
            } 
            else {
                # 1. Setup a Persistent Workspace for this specific file
                $safeName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
                $workDir  = Join-Path $PSScriptRoot "work_$safeName"
                
                try {
                    if (-not (Test-Path $workDir)) {
                        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
                    }

                    $sourceItem = Get-Item $sourceFile
                    $destFile   = Join-Path $workDir $fileInput

                    # 2. Logic: Only copy if necessary to preserve LastWriteTime integrity
                    if (-not (Test-Path $destFile) -or 
                        (Get-Item $destFile).LastWriteTime -lt $sourceItem.LastWriteTime) {
                            
                        Write-Host "[*] Updating workspace recording..." -ForegroundColor Gray
                        Copy-Item -Path $sourceFile -Destination $destFile -Force
                    }
                    else {
                        Write-Host "[+] Using existing recording and index (No changes detected)." -ForegroundColor DarkGray
                    }
                    
                    # Visual summary for the user
                    cls
                    Write-Host "`n[!] STATUS: Starting Simulation" -ForegroundColor Green
                    Write-Host "[!] Master File:  $fileInput" -ForegroundColor Gray
                    Write-Host "[!] Workspace:    $workDir" -ForegroundColor DarkGray
                    Write-Host "[!] Community:    $safeName" -ForegroundColor Cyan
                    Write-Host "[!] Port:         1161" -ForegroundColor Gray
                    Write-Host "[!] Press CTRL+C to stop`n" -ForegroundColor Yellow
                    
                    Start-Sleep -Seconds 5

                    # 3. Run the Responder
                                        
                    $replayArgs = @(
                        "--data-dir=$workDir", 
						"--cache-dir=$workDir",
                        "--agent-udpv4-endpoint=0.0.0.0:1161"
                    )

                    & $responderExe $replayArgs
                }
                finally {
                    Write-Host "`n[!] Simulation stopped. Workspace preserved for fast-start." -ForegroundColor DarkGray
                }
            } # End of if (Test-Path $sourceFile)
        } # End of switch case "2"
		
        "3" {
			Write-Host "`n[!] Launching Virtual Environment Shell..." -ForegroundColor Green
			# We use a double-quoted string for the whole command so $activateScript expands correctly
			$action = ". '$activateScript'; Write-Host '--- SNMP VENV ACTIVE ---' -ForegroundColor Cyan; Write-Host '[!] Type ''exit'' to return to the Manager menu.' -ForegroundColor Yellow"
			powershell.exe -NoExit -ExecutionPolicy Bypass -Command $action
		}

        "0" { cls; exit }
    }
} while ($choice -ne "0")
