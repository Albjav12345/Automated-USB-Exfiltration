@echo off
title USB Backup Agent - B2 Cloud Edition
color 0B
setlocal enabledelayedexpansion

set "installDir=%LOCALAPPDATA%\USBBackupAgent"
set "psScript=%installDir%\usb_backup_agent.ps1"

:MAIN_MENU
cls
echo ==================================================================
echo                  USB BACKUP AGENT - B2 CLOUD EDITION
echo ==================================================================
echo.
echo Please select an option:
echo.
echo   [1] Install / Configure Agent
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
echo This tool runs silently in the background monitoring your USB ports.
echo When a new USB drive is connected, it automatically:
echo   1. Copies the contents to a temporary local folder.
echo   2. Compresses the data into a Zip64 archive.
echo   3. Uploads the archive to your Backblaze B2 Bucket.
echo   4. Cleans up the local temporary files.
echo.
echo SYSTEM CHANGES ^& DIRECTORIES:
echo - Engine: %LOCALAPPDATA%\USBBackupAgent
echo - Logs/Status: %USERPROFILE%\USB_Backups\logs
echo - Temp Workdir: %TEMP%\USBBackupTemp
echo - Autostart: Registry (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
echo.
echo You can check the live status anytime by opening:
echo %USERPROFILE%\USB_Backups\logs\live_status.txt
echo.
pause
goto MAIN_MENU

:UNINSTALL
cls
echo ==================================================================
echo                      UNINSTALLING AGENT
echo ==================================================================
echo Stopping background processes...
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'usb_backup_agent' -and $_.CommandLine -match '-RunWorker' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >nul 2>&1
echo Removing Registry Autostart...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "USBBackupAgentB2" /f >nul 2>&1
echo Deleting application folders...
if exist "%installDir%" rmdir /s /q "%installDir%" >nul 2>&1
if exist "%TEMP%\USBBackupTemp" rmdir /s /q "%TEMP%\USBBackupTemp" >nul 2>&1
if exist "%TEMP%\USBBackupAgent.lock" del /f /q "%TEMP%\USBBackupAgent.lock" >nul 2>&1
echo.
echo Agent successfully uninstalled from your system.
echo (Note: Your backup logs in %USERPROFILE%\USB_Backups were kept).
pause
goto MAIN_MENU

:INSTALL
cls
echo ==================================================================
echo                      INSTALLATION WIZARD
echo ==================================================================
echo Stopping previous instances if running...
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'usb_backup_agent' -and $_.CommandLine -match '-RunWorker' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >nul 2>&1

if not exist "%installDir%" mkdir "%installDir%"

echo [1/4] Configuring PowerShell Execution Policies...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue"

echo [2/4] Checking AWS.Tools.S3 module (Required for B2)...
powershell -Command "if (-not (Get-Module -ListAvailable -Name AWS.Tools.S3)) { Install-Module -Name AWS.Tools.S3 -Force -AllowClobber -Scope CurrentUser -Repository PSGallery }"

echo [3/4] Extracting core engine...
powershell -Command "$lines = Get-Content -Path '%~f0'; $start = [array]::IndexOf($lines, '----BEGIN POWERSHELL SCRIPT----') + 1; $end = [array]::IndexOf($lines, '----END POWERSHELL SCRIPT----') - 1; Set-Content -Path '%psScript%' -Value $lines[$start..$end]"

set "vbsPath=%installDir%\launcher.vbs"
echo Set objShell = CreateObject^("WScript.Shell"^) > "%vbsPath%"
echo objShell.Run "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""%psScript%"" -RunWorker", 0, False >> "%vbsPath%"

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "USBBackupAgentB2" /t REG_SZ /d "wscript.exe \"%vbsPath%\"" /f >nul

echo [4/4] B2 Cloud Credentials Setup...
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

$installDir = Join-Path $env:LOCALAPPDATA "USBBackupAgent"
$configPath = Join-Path $installDir "config_b2.json"
$logDir = Join-Path $env:USERPROFILE "USB_Backups\logs"
$zipTempDir = Join-Path $env:TEMP "USBBackupTemp"
$lockFile = Join-Path $env:TEMP "USBBackupAgent.lock"

function Write-StatusLog($text) {
    $file = Join-Path $logDir "agent_status.log"
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent)
    Add-Content -Path $file -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
}

if ($Install) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host "                 BACKBLAZE B2 CREDENTIALS GUIDE" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "To connect the agent, you need to generate API keys in Backblaze:"
    Write-Host " 1. Log in to https://secure.backblaze.com"
    Write-Host " 2. Go to 'Buckets' -> Create a Bucket (or use an existing one)."
    Write-Host "    -> Copy your 'Bucket Name' and 'Endpoint' (e.g., s3.us-west-004...)"
    Write-Host " 3. Go to 'App Keys' -> Click 'Add a New Application Key'."
    Write-Host " 4. Name the key and grant it access to your bucket."
    Write-Host "    -> Copy the 'keyID' and 'applicationKey' (App Key is shown ONLY ONCE!)."
    Write-Host "==================================================================`n" -ForegroundColor Cyan

    $bucketName = Read-Host "1. Enter your B2 Bucket Name"
    $endpoint = Read-Host "2. Enter your S3 Endpoint (e.g., s3.us-west-004.backblazeb2.com)"
    $keyID = Read-Host "3. Enter your Key ID"
    $appKeyPlain = Read-Host "4. Enter your Application Key (Secret)"

    if ([string]::IsNullOrWhiteSpace($bucketName) -or [string]::IsNullOrWhiteSpace($keyID)) {
        Write-Host "Error: Credentials cannot be empty." -ForegroundColor Red
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    New-Item -ItemType Directory -Force -Path $zipTempDir | Out-Null

    try {
        Set-AWSCredential -AccessKey $keyID -SecretKey $appKeyPlain -StoreAs default
        Write-Host "`n[OK] Credentials verified and stored securely." -ForegroundColor Green
    } catch {
        Write-Host "`n[ERROR] Failed to configure AWS Credentials. Please check your Key ID and App Key." -ForegroundColor Red
        exit 1
    }

    $config = @{ bucketName = $bucketName; endpoint = $endpoint }
    $config | ConvertTo-Json | Set-Content -Path $configPath -Force
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
    Write-StatusLog "Agent started. Target: B2://$($config.bucketName)"

    $processedDrives = @{}
    $liveStatusFile = Join-Path $logDir "live_status.txt"
    "$(Get-Date -Format 'HH:mm:ss') - [IDLE] Ready and monitoring USB ports..." | Set-Content -Path $liveStatusFile -Force

    while ($true) {
        try {
            (Get-Date).ToString() | Set-Content $lockFile
            $currentDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DeviceID

            foreach ($drive in $currentDrives) {
                if (-not $processedDrives.ContainsKey($drive)) {
                    Write-StatusLog "New USB detected: $drive"
                    
                    Start-Job -Name "Backup_$drive" -ScriptBlock {
                        param($drv, $cfgPath, $logDirectory, $tmpDirectory, $liveFile)

                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        $cfg = Get-Content $cfgPath | ConvertFrom-Json
                        $driveLetter = $drv.Substring(0,1)
                        
                        $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                        $label = if ([string]::IsNullOrWhiteSpace($vol.FileSystemLabel)) { "USB_$driveLetter" } else { $vol.FileSystemLabel }
                        
                        $cimDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($driveLetter):'" -ErrorAction SilentlyContinue
                        $usedBytes = if ($cimDisk) { $cimDisk.Size - $cimDisk.FreeSpace } else { 0 }
                        $sizeStr = if ($usedBytes -gt 1GB) { "$([math]::Round($usedBytes / 1GB, 2)) GB" } else { "$([math]::Round($usedBytes / 1MB, 2)) MB" }

                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $zipName = "${label}_${driveLetter}_${timestamp}.zip"
                        $zipPath = Join-Path $tmpDirectory $zipName

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

                        Write-JobLog "Backup initiated. Detected footprint: $sizeStr"
                        $tempCopyDir = Join-Path $tmpDirectory "temp_$timestamp"
                        New-Item -ItemType Directory -Force -Path $tempCopyDir | Out-Null
                        $activeTimer = $null

                        try {
                            # PHASE 1: COPY
                            $activeTimer = Start-ActiveTimer "[PHASE 1/3] Copying $sizeStr to local drive..."
                            Write-JobLog "Copying files..."
                            $origin = $drv + "\"
                            $robocopyResult = robocopy $origin $tempCopyDir /E /R:1 /W:1 /NDL /NFL /NJH /NJS /XD "System Volume Information" "$RECYCLE.BIN"
                            $rcCode = $LASTEXITCODE
                            Stop-ActiveTimer $activeTimer $null
                            
                            if ($rcCode -ge 8) { throw "Robocopy reported physical read errors (Exit Code $rcCode)." }
                            if ((Get-ChildItem -Path $tempCopyDir -Recurse | Measure-Object).Count -eq 0) {
                                Write-JobLog "WARNING: USB drive was empty or locked."
                                Stop-ActiveTimer $null "[CANCELLED] The USB drive contained no readable data."
                                return
                            }

                            # PHASE 2: COMPRESSION
                            $activeTimer = Start-ActiveTimer "[PHASE 2/3] Compressing $sizeStr (Zip64 engine running)..."
                            Write-JobLog "Compressing data..."
                            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempCopyDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
                            Stop-ActiveTimer $activeTimer $null

                            $zipItem = Get-Item -Path $zipPath -ErrorAction Stop
                            if ($zipItem.Length -le 22) { throw "Generated ZIP archive is corrupt or empty." }
                            $zipSizeStr = if ($zipItem.Length -gt 1GB) { "$([math]::Round($zipItem.Length / 1GB, 2)) GB" } else { "$([math]::Round($zipItem.Length / 1MB, 2)) MB" }

                            # PHASE 3: UPLOAD
                            $activeTimer = Start-ActiveTimer "[PHASE 3/3] Uploading $zipSizeStr archive to Backblaze B2..."
                            Write-JobLog "Uploading $zipSizeStr to B2..."
                            Import-Module AWS.Tools.S3 -ErrorAction Stop
                            $s3Key = "Backups/${label}_${driveLetter}/$timestamp.zip"
                            
                            Write-S3Object -BucketName $cfg.bucketName -Key $s3Key -File $zipPath -EndpointUrl "https://$($cfg.endpoint)" -ForcePathStyle $true -ErrorAction Stop
                            Stop-ActiveTimer $activeTimer "[COMPLETED] Last backup successful. Waiting for new USB drive..."
                            Write-JobLog "Upload completed successfully."

                        } catch {
                            if ($activeTimer) { Stop-ActiveTimer $activeTimer $null }
                            Write-JobLog "CRITICAL ERROR: $($_.Exception.Message)"
                            Stop-ActiveTimer $null "[ERROR] Backup failed: $($_.Exception.Message). Check log file."
                        } finally {
                            Remove-Item -Path $tempCopyDir -Recurse -Force -ErrorAction SilentlyContinue
                            Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
                        }
                    } -ArgumentList $drive, $configPath, $logDir, $zipTempDir, $liveStatusFile | Out-Null

                    $processedDrives[$drive] = $true
                }
            }

            $disconnectedDrives = @($processedDrives.Keys | Where-Object { $_ -notin $currentDrives })
            foreach ($drive in $disconnectedDrives) {
                Write-StatusLog "USB disconnected: $drive"
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
