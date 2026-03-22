@echo off
title Secure USB Local Vault ^& Master Sync Agent
color 0B
setlocal enabledelayedexpansion

set "installDir=%LOCALAPPDATA%\USBLocalVault"
set "psScript=%installDir%\usb_local_vault.ps1"

:MAIN_MENU
cls
echo ==================================================================
echo             SECURE USB LOCAL VAULT ^& MASTER SYNC
echo ==================================================================
echo.
echo Please select an option:
echo.
echo   [1] Install / Configure Local Agent
echo   [2] View Application Information
echo   [3] Uninstall Complete Agent
echo   [4] Exit
echo.
set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto INSTALL
if "%choice%"=="2" goto INFO
if "%choice%"=="3" goto UNINSTALL
if "%choice%"=="4" exit /b
goto MAIN_MENU

:INFO
cls
echo ==================================================================
echo                      HOW THIS AGENT WORKS
echo ==================================================================
echo.
echo This tool runs completely offline, monitoring your USB ports.
echo It operates in two modes:
echo.
echo 1. STANDARD ACQUISITION: 
echo    When a regular USB is inserted, it performs an ultra-fast, 
echo    uncompressed mirror copy to your secure local vault.
echo    (Skips locked/open files automatically to prevent stalling).
echo.
echo 2. MASTER CONSOLIDATION:
echo    When the configured 'Master Pendrive' is inserted, it rapidly
echo    transfers all accumulated local backups into the Master drive.
echo.
echo DIRECTORIES:
echo - Local Vault: %USERPROFILE%\Secure_Local_Vault
echo - Logs/Status: %USERPROFILE%\Secure_Local_Vault\logs
echo - Autostart: Registry (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
echo.
echo Live status available at:
echo %USERPROFILE%\Secure_Local_Vault\logs\live_status.txt
echo.
pause
goto MAIN_MENU

:UNINSTALL
cls
echo ==================================================================
echo                      UNINSTALLING AGENT
echo ==================================================================
echo Stopping background processes...
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'usb_local_vault' -and $_.CommandLine -match '-RunWorker' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >nul 2>&1
echo Removing Registry Autostart...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "USBLocalVaultAgent" /f >nul 2>&1
echo Deleting application core folders...
if exist "%installDir%" rmdir /s /q "%installDir%" >nul 2>&1
if exist "%TEMP%\USBLocalVault.lock" del /f /q "%TEMP%\USBLocalVault.lock" >nul 2>&1
echo.
echo Agent successfully uninstalled.
echo (Note: Your stored backups in %USERPROFILE%\Secure_Local_Vault were NOT deleted).
pause
goto MAIN_MENU

:INSTALL
cls
echo ==================================================================
echo                      INSTALLATION WIZARD
echo ==================================================================
echo Stopping previous instances if running...
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'usb_local_vault' -and $_.CommandLine -match '-RunWorker' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >nul 2>&1

if not exist "%installDir%" mkdir "%installDir%"

echo [1/3] Configuring PowerShell Execution Policies...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue"

echo [2/3] Extracting core engine...
powershell -Command "$lines = Get-Content -Path '%~f0'; $start = [array]::IndexOf($lines, '----BEGIN POWERSHELL SCRIPT----') + 1; $end = [array]::IndexOf($lines, '----END POWERSHELL SCRIPT----') - 1; Set-Content -Path '%psScript%' -Value $lines[$start..$end]"

set "vbsPath=%installDir%\launcher.vbs"
echo Set objShell = CreateObject^("WScript.Shell"^) > "%vbsPath%"
echo objShell.Run "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""%psScript%"" -RunWorker", 0, False >> "%vbsPath%"

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "USBLocalVaultAgent" /t REG_SZ /d "wscript.exe \"%vbsPath%\"" /f >nul

echo [3/3] Master Drive Configuration...
powershell -ExecutionPolicy Bypass -File "%psScript%" -Install
if %errorlevel% neq 0 (
    echo.
    echo Installation aborted due to configuration error.
    pause
    goto MAIN_MENU
)

echo Starting background service...
start "" wscript.exe "%vbsPath%"
echo.
echo ==================================================================
echo SUCCESS: Installation Complete. The Agent is now running silently.
echo ==================================================================
pause
goto MAIN_MENU

----BEGIN POWERSHELL SCRIPT----
param(
    [switch]$RunWorker,
    [switch]$Install
)

$installDir = Join-Path $env:LOCALAPPDATA "USBLocalVault"
$configPath = Join-Path $installDir "config_local.json"
$localBackupsDest = Join-Path $env:USERPROFILE "Secure_Local_Vault"
$logDir = Join-Path $localBackupsDest "logs"
$lockFile = Join-Path $env:TEMP "USBLocalVault.lock"

function Write-StatusLog($text) {
    $file = Join-Path $logDir "agent_status.log"
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent)
    Add-Content -Path $file -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
}

if ($Install) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host "                 MASTER PENDRIVE CONFIGURATION" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "The 'Master Pendrive' is the specific USB drive that, when inserted,"
    Write-Host "will automatically extract all accumulated backups from this PC."
    Write-Host "You must provide the exact 'Volume Label' (Name) of this drive.`n" -ForegroundColor Cyan

    $masterLabel = Read-Host "Enter the Volume Label of your Master Pendrive (e.g., ADMIN_VAULT)"

    if ([string]::IsNullOrWhiteSpace($masterLabel)) {
        Write-Host "Error: Master label cannot be empty." -ForegroundColor Red
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    New-Item -ItemType Directory -Force -Path $localBackupsDest | Out-Null

    $config = @{ masterDriveLabel = $masterLabel }
    $config | ConvertTo-Json | Set-Content -Path $configPath -Force
    
    Write-Host "`n[OK] Master drive configured securely." -ForegroundColor Green
    exit 0
}

if ($RunWorker) {
    if (Test-Path $lockFile) {
        $lastWrite = (Get-Item $lockFile).LastWriteTime
        if ((Get-Date) - $lastWrite -lt [TimeSpan]::FromMinutes(1)) { exit } else { Remove-Item $lockFile -Force }
    }
    
    $null = New-Item -Path $lockFile -ItemType File -Force

    if (-not (Test-Path $configPath)) {
        Remove-Item $lockFile -Force
        exit
    }
    
    $config = Get-Content $configPath | ConvertFrom-Json
    $masterDriveLabel = $config.masterDriveLabel
    $currentMasterDeviceId = $null

    # --- FASE DE INICIALIZACION (BOOT BUFFER) ---
    Write-StatusLog "Agent starting... Pausing for 10 seconds to allow OS hardware stack initialization."
    Start-Sleep -Seconds 10
    
    $initialDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue
    if ($initialDrives) {
        Write-StatusLog "Initial Scan: Found $($initialDrives.Count) pre-inserted USB drive(s). Processing..."
    } else {
        Write-StatusLog "Initial Scan: No pre-inserted USB drives found."
    }
    # --------------------------------------------

    Write-StatusLog "Local Vault Agent is now active. Monitoring for USBs. Master Label: '$masterDriveLabel'"

    $processedDrives = @{}
    $liveStatusFile = Join-Path $logDir "live_status.txt"
    "$(Get-Date -Format 'HH:mm:ss') - [IDLE] Ready and monitoring USB ports..." | Set-Content -Path $liveStatusFile -Force

    while ($true) {
        try {
            (Get-Date).ToString() | Set-Content $lockFile
            $allUsbDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue

            # --- MASTER DRIVE HANDLING ---
            $masterDrives = $allUsbDrives | Where-Object { $_.VolumeName -eq $masterDriveLabel }
            
            if ($masterDrives) {
                $currentMaster = $masterDrives[0]
                
                if ($currentMaster.DeviceId -ne $currentMasterDeviceId) {
                    Write-StatusLog "Master Drive '$masterDriveLabel' detected ($($currentMaster.DeviceId)). Consolidating local vault..."
                    
                    Start-Job -Name "ConsolidateToMaster" -ScriptBlock {
                        param($sourceRoot, $destMaster, $jobLogDir, $liveFile)
                        
                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $destFolder = Join-Path ($destMaster + "\") "Consolidated_Vault_$timestamp"
                        
                        function Write-JobLog($text) {
                            $file = Join-Path $jobLogDir "job_consolidate_${timestamp}.log"
                            Add-Content -Path $file -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
                        }

                        function Start-ActiveTimer($phaseText) {
                            $scriptCode = {
                                param($path, $text, $d)
                                $start = Get-Date
                                while($true) {
                                    $e = (Get-Date) - $start
                                    $tf = if ($e.Hours -gt 0) { "{0:hh\:mm\:ss}" -f $e } else { "{0:mm\:ss}" -f $e }
                                    "$(Get-Date -Format 'HH:mm:ss') - [$d] $text [Duration: $tf]" | Set-Content -Path $path -Force
                                    Start-Sleep -Seconds 2
                                }
                            }
                            return Start-Job -ScriptBlock $scriptCode -ArgumentList $liveFile, $phaseText, $destMaster
                        }

                        function Stop-ActiveTimer($jobObj, $finalMsg) {
                            if ($jobObj) { Stop-Job $jobObj -ErrorAction SilentlyContinue; Remove-Job $jobObj -ErrorAction SilentlyContinue }
                            if ($finalMsg) { "$(Get-Date -Format 'HH:mm:ss') - [$destMaster] $finalMsg" | Set-Content -Path $liveFile -Force }
                        }

                        Write-JobLog "Consolidation Job initiated to Master '$destMaster'."
                        New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
                        $activeTimer = $null

                        try {
                            $activeTimer = Start-ActiveTimer "[CONSOLIDATING] Syncing local vault to Master Drive (Multi-thread)..."
                            Write-JobLog "Transferring all offline backups to Master..."
                            
                            # Uso de /R:0 /W:0 para ignorar archivos bloqueados en local sin perder tiempo
                            $robocopyLog = robocopy $sourceRoot $destFolder /E /R:0 /W:0 /MT:8 /NDL /NFL /NJH /NJS /NP /XD "logs"
                            $rcCode = $LASTEXITCODE
                            
                            Stop-ActiveTimer $activeTimer "[COMPLETED] All backups consolidated. Safe to remove Master Drive."
                            
                            if ($rcCode -ge 16) { throw "Fatal filesystem error (Code $rcCode)." }
                            
                            if ($rcCode -ge 8) {
                                Write-JobLog "WARNING: Some local files were locked/open and could not be consolidated:"
                                $errors = $robocopyLog | Where-Object { $_ -match "ERROR" }
                                foreach ($err in $errors) { Write-JobLog " -> $($err.Trim())" }
                            } else {
                                Write-JobLog "Consolidation completed successfully with 100% data mirrored."
                            }
                        } catch {
                            if ($activeTimer) { Stop-ActiveTimer $activeTimer $null }
                            Write-JobLog "ERROR during consolidation: $($_.Exception.Message)"
                            Stop-ActiveTimer $null "[ERROR] Consolidation failed. Check job_consolidate log."
                        }
                    } -ArgumentList $localBackupsDest, $currentMaster.DeviceId, $logDir, $liveStatusFile | Out-Null
                    
                    $currentMasterDeviceId = $currentMaster.DeviceId
                }
            } else {
                if ($currentMasterDeviceId) {
                    Write-StatusLog "Master Drive '$currentMasterDeviceId' disconnected."
                    $currentMasterDeviceId = $null
                    "$(Get-Date -Format 'HH:mm:ss') - [IDLE] Ready and monitoring USB ports..." | Set-Content -Path $liveStatusFile -Force
                }
            }
            # -------------------------------------

            # --- NORMAL ACQUISITION HANDLING ---
            $currentDrives = $allUsbDrives | Where-Object { $_.VolumeName -ne $masterDriveLabel } | Select-Object -ExpandProperty DeviceID

            foreach ($drive in $currentDrives) {
                if (-not $processedDrives.ContainsKey($drive)) {
                    Write-StatusLog "New Target USB detected: $drive"
                    
                    Start-Job -Name "Acquisition_$drive" -ScriptBlock {
                        param($drv, $logDirectory, $liveFile, $destRoot)

                        $driveLetter = $drv.Substring(0,1)
                        $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                        $label = if ([string]::IsNullOrWhiteSpace($vol.FileSystemLabel)) { "USB_$driveLetter" } else { $vol.FileSystemLabel }

                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $usbFolder = "${label}_${driveLetter}"
                        $targetFolder = Join-Path (Join-Path $destRoot $usbFolder) $timestamp
                        New-Item -ItemType Directory -Force -Path $targetFolder | Out-Null
                        
                        function Write-JobLog($text) {
                            $file = Join-Path $logDirectory "job_$(Get-Date -Format 'yyyyMMdd').log"
                            Add-Content -Path $file -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$drv] $text"
                        }

                        function Start-ActiveTimer($phaseText) {
                            $scriptCode = {
                                param($path, $text, $d)
                                $start = Get-Date
                                while($true) {
                                    $e = (Get-Date) - $start
                                    $tf = if ($e.Hours -gt 0) { "{0:hh\:mm\:ss}" -f $e } else { "{0:mm\:ss}" -f $e }
                                    "$(Get-Date -Format 'HH:mm:ss') - [$d] $text [Duration: $tf]" | Set-Content -Path $path -Force
                                    Start-Sleep -Seconds 2
                                }
                            }
                            return Start-Job -ScriptBlock $scriptCode -ArgumentList $liveFile, $phaseText, $drv
                        }

                        function Stop-ActiveTimer($jobObj, $finalMsg) {
                            if ($jobObj) { Stop-Job $jobObj -ErrorAction SilentlyContinue; Remove-Job $jobObj -ErrorAction SilentlyContinue }
                            if ($finalMsg) { "$(Get-Date -Format 'HH:mm:ss') - [$drv] $finalMsg" | Set-Content -Path $liveFile -Force }
                        }

                        Write-JobLog "Direct Local Acquisition started."
                        $activeTimer = $null

                        try {
                            $activeTimer = Start-ActiveTimer "[ACQUIRING] Direct mirror to local vault in progress..."
                            Write-JobLog "Mirroring data to $targetFolder..."
                            
                            $origin = $drv + "\"
                            # Uso de /R:0 /W:0 para ignorar archivos en uso (Ej: PDF abierto) y capturar la salida
                            $robocopyLog = robocopy $origin $targetFolder /E /R:0 /W:0 /NDL /NFL /NJH /NJS /NP /XD "System Volume Information" "$RECYCLE.BIN"
                            $rcCode = $LASTEXITCODE

                            Stop-ActiveTimer $activeTimer $null
                            
                            if ($rcCode -ge 16) { throw "Fatal filesystem error on source drive (Code $rcCode)." }

                            if ($rcCode -ge 8) {
                                Write-JobLog "WARNING: Some files were locked by running processes and were skipped:"
                                $errors = $robocopyLog | Where-Object { $_ -match "ERROR" }
                                foreach ($err in $errors) { Write-JobLog " -> $($err.Trim())" }
                                Stop-ActiveTimer $null "[COMPLETED WITH SKIPS] Acquisition done. Some locked files were ignored."
                            } else {
                                Write-JobLog "Acquisition completed successfully with 100% data extraction."
                                Stop-ActiveTimer $null "[COMPLETED] Acquisition stored locally. Waiting for new drive..."
                            }

                        } catch {
                            if ($activeTimer) { Stop-ActiveTimer $activeTimer $null }
                            Write-JobLog "ERROR: $($_.Exception.Message)"
                            Stop-ActiveTimer $null "[ERROR] Acquisition failed. Check logs."
                        }
                    } -ArgumentList $drive, $logDir, $liveStatusFile, $localBackupsDest | Out-Null

                    $processedDrives[$drive] = $true
                }
            }

            $disconnectedDrives = @($processedDrives.Keys | Where-Object { $_ -notin $currentDrives })
            foreach ($drive in $disconnectedDrives) {
                Write-StatusLog "Target USB disconnected: $drive"
                $processedDrives.Remove($drive)
            }

            Get-Job | Where-Object { $_.State -in 'Completed','Failed' } | ForEach-Object { Remove-Job $_ }
            Start-Sleep -Seconds 5
        } catch {
            Write-StatusLog "Monitor Error: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
}
----END POWERSHELL SCRIPT----