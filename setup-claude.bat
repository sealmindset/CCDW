@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code - One-Click Setup
REM
REM Download this file and double-click it. It handles everything:
REM   1. Installs Git (if needed)
REM   2. Enables WSL2 (if needed - requires one reboot)
REM   3. Installs Rancher Desktop (if needed)
REM   4. Downloads Claude Code Docker
REM   5. Runs the installer
REM
REM You do NOT need to open a terminal or know any commands.
REM Just double-click this file and follow the prompts.
REM =============================================================================

title Claude Code - Setup

echo.
echo ========================================
echo   Claude Code - Setup
echo ========================================
echo.

REM ---------------------------------------------------------------------------
REM Determine install location (user's Documents folder, auto-detected)
REM ---------------------------------------------------------------------------
set "INSTALL_DIR=%USERPROFILE%\Documents\CCDW"
echo   Install location: !INSTALL_DIR!
echo.

REM ---------------------------------------------------------------------------
REM Progress tracking: resume from where we left off after reboot/retry
REM ---------------------------------------------------------------------------
set "STATE_FILE=%TEMP%\claude-setup-state.txt"
set "S_GIT=0"
set "S_WSL=0"
set "S_DOCKER=0"
set "S_CLONE=0"
if exist "!STATE_FILE!" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("!STATE_FILE!") do (
        if /i "%%A"=="GIT" set "S_GIT=%%B"
        if /i "%%A"=="WSL" set "S_WSL=%%B"
        if /i "%%A"=="DOCKER" set "S_DOCKER=%%B"
        if /i "%%A"=="CLONE" set "S_CLONE=%%B"
    )
    echo [OK]  Resuming from where you left off.
    echo.
)

REM ---------------------------------------------------------------------------
REM Step 0: Connectivity check (catch VPN/network issues before anything else)
REM ---------------------------------------------------------------------------
echo [...]  Checking internet connection...
curl.exe -s --connect-timeout 5 -o nul https://github.com 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  Internet connection.
) else (
    echo.
    echo ========================================
    echo   No internet connection
    echo ========================================
    echo.
    echo   This setup needs to download files from the internet.
    echo.
    echo   Please check:
    echo     1. Are you connected to Wi-Fi or Ethernet?
    echo     2. Is your VPN connected? Look for the GlobalProtect
    echo        icon in the system tray ^(bottom-right corner of
    echo        your screen, near the clock^). It should say
    echo        "Connected". If not, click it and connect.
    echo.
    echo   After connecting, run this file again.
    echo.
    pause
    exit /b 1
)

:vpn_check
echo [...]  Checking VPN connection...
curl.exe -s --connect-timeout 8 -o nul https://snapistg-scus.azure.sleepnumber.com 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  VPN connected.
) else (
    echo.
    echo ========================================
    echo   VPN is not connected
    echo ========================================
    echo.
    echo   Claude Code needs VPN to reach Sleep Number services.
    echo.
    echo   How to connect:
    echo     1. Look for the GlobalProtect icon in the system tray
    echo        ^(bottom-right corner, near the clock^)
    echo     2. Click it and make sure it says "Connected"
    echo     3. If you don't see it, search for "GlobalProtect"
    echo        in the Start menu and open it
    echo.
    echo   Press any key after connecting your VPN...
    echo.
    pause
    curl.exe -s --connect-timeout 8 -o nul https://snapistg-scus.azure.sleepnumber.com 2>nul
    if !ERRORLEVEL! neq 0 (
        echo.
        echo [ERROR] Still cannot reach Sleep Number services.
        echo         Make sure GlobalProtect VPN is connected and try again.
        echo.
        pause
        exit /b 1
    )
    echo [OK]  VPN connected.
)

REM ---------------------------------------------------------------------------
REM Step 1: Check for Git
REM ---------------------------------------------------------------------------
if "!S_GIT!"=="1" (
    echo [OK]  Git ^(already done^)
    goto :git_ok
)

echo [...]  Checking for Git...
where git >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  Git is installed.
    goto :git_done
)

echo [...]  Git is not installed. Installing now...
where winget >nul 2>nul
if !ERRORLEVEL! neq 0 goto :no_winget_git
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
if !ERRORLEVEL! equ 0 goto :git_install_ok
:no_winget_git
echo [ERROR] Could not install Git automatically.
echo.
echo   Please install Git manually:
echo     1. Open your browser
echo     2. Go to https://git-scm.com/download/win
echo     3. Download and run the installer
echo     4. Then double-click this file again
echo.
pause
exit /b 1
:git_install_ok

REM Refresh PATH so git is found in this session
set "GIT_PATHS=%ProgramFiles%\Git\cmd;%LOCALAPPDATA%\Programs\Git\cmd"
set "PATH=!GIT_PATHS!;!PATH!"
where git >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo [OK]  Git was installed. Please restart your computer, then double-click this file again.
    pause
    exit /b 0
)
echo [OK]  Git installed.

:git_done
> "!STATE_FILE!" echo GIT=1
:git_ok

REM ---------------------------------------------------------------------------
REM Step 2: Check for WSL2 (includes Windows feature enablement)
REM ---------------------------------------------------------------------------
if "!S_WSL!"=="1" (
    echo [OK]  WSL2 ^(already done^)
    goto :wsl_ok
)

echo [...]  Checking for WSL2...

REM First check if WSL2 is already working
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 is installed.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_ok
)

REM WSL2 not working -- check if the required Windows features are enabled.
REM On clean Win 11 Pro these are pre-enabled, but older/upgraded machines
REM or machines with corporate group policies may not have them.
echo [...]  Checking Windows features for WSL2...

set "WSL_FEATURES_NEEDED=0"

REM Check VirtualMachinePlatform
powershell -NoProfile -Command ^
    "$f = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue; " ^
    "if (-not $f -or $f.State -ne 'Enabled') { exit 1 } else { exit 0 }" >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo [INFO] Windows feature "Virtual Machine Platform" is not enabled.
    set "WSL_FEATURES_NEEDED=1"
)

REM Check Microsoft-Windows-Subsystem-Linux
powershell -NoProfile -Command ^
    "$f = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue; " ^
    "if (-not $f -or $f.State -ne 'Enabled') { exit 1 } else { exit 0 }" >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo [INFO] Windows feature "Windows Subsystem for Linux" is not enabled.
    set "WSL_FEATURES_NEEDED=1"
)

if "!WSL_FEATURES_NEEDED!"=="0" goto :wsl_features_ok

REM Features missing -- need admin elevation to enable them
echo.
echo ========================================
echo   Windows features need to be enabled
echo ========================================
echo.
echo   Docker needs two Windows features that aren't turned on yet.
echo   This is normal on older machines or corporate-managed PCs.
echo.
echo   Windows will pop up asking for an admin password.
echo   Use your SSMITH Local Admin credentials. To find them:
echo     - Search your email for "Local Admin" or "SSMITH"
echo     - The username is usually SSMITH ^(all caps^)
echo     - The password was in that email
echo.
echo   If you can't find the email, contact the IT Service Desk.
echo.
echo   Your computer will need to restart after this step.
echo.
pause

REM Enable both features via DISM (requires elevation)
REM Use PowerShell Start-Process -Verb RunAs to get the UAC prompt
powershell -NoProfile -Command ^
    "try { " ^
    "  $script = @' " ^
    "dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart " ^
    "dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart " ^
    "'@ ; " ^
    "  $tmpFile = Join-Path $env:TEMP 'enable-wsl-features.cmd'; " ^
    "  Set-Content -Path $tmpFile -Value $script -Encoding ASCII; " ^
    "  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $tmpFile -Verb RunAs -Wait -PassThru; " ^
    "  Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue; " ^
    "  exit $proc.ExitCode " ^
    "} catch { " ^
    "  Write-Host 'Admin elevation was cancelled or failed.'; " ^
    "  exit 1 " ^
    "}"
if !ERRORLEVEL! neq 0 (
    echo.
    echo [ERROR] Could not enable Windows features.
    echo.
    echo   This usually means:
    echo     - The admin password was wrong
    echo     - You cancelled the admin prompt
    echo     - You don't have Local Admin rights
    echo.
    echo   Search your email for "Local Admin" or "SSMITH" to find
    echo   your credentials. If you don't have them, contact the
    echo   IT Service Desk to request Local Admin access.
    echo.
    pause
    exit /b 1
)

echo [OK]  Windows features enabled.
echo.
echo ========================================
echo   Restart required
echo ========================================
echo.
echo   The Windows features were enabled successfully.
echo.
echo   Your computer needs to restart for them to take effect.
echo   Setup will continue automatically after restart.
echo.
>> "!STATE_FILE!" echo GIT=!S_GIT!
call :schedule_resume
pause
shutdown /r /t 10 /c "Restarting to finish WSL2 setup. Setup will resume automatically."
exit /b 0

:wsl_features_ok
REM Features are enabled but WSL still not working -- try wsl --install
echo.
echo ========================================
echo   WSL2 needs to be installed
echo ========================================
echo.
echo   The Windows features are enabled, but WSL2 itself
echo   needs to be downloaded and installed.
echo.
echo   Windows may pop up asking for an admin password.
echo   Use your SSMITH Local Admin credentials. To find them:
echo     - Search your email for "Local Admin" or "SSMITH"
echo     - The username is usually SSMITH ^(all caps^)
echo     - The password was in that email
echo.
echo   If you can't find the email, contact the IT Service Desk.
echo.
echo   After installing, your computer must restart.
echo   Then double-click this file again to continue.
echo.
pause

wsl --install
if !ERRORLEVEL! neq 0 (
    REM wsl --install may fail but still succeed (Windows quirk).
    REM Also try wsl --update as a fallback.
    echo [...]  Trying WSL update as fallback...
    wsl --update >nul 2>nul
)

REM Verify WSL is now working
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 installed.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_check_reboot
)

REM Still not working -- may need reboot for features to take effect
echo.
echo [INFO] WSL2 install ran. A restart may be needed to finish.

:wsl_check_reboot
echo.
echo ========================================
echo   Restart required
echo ========================================
echo.
echo   WSL2 was installed successfully.
echo.
echo   Your computer needs to restart.
echo   Setup will continue automatically after restart.
echo.
>> "!STATE_FILE!" echo WSL=1
call :schedule_resume
pause
exit /b 0

:wsl_ok

REM ---------------------------------------------------------------------------
REM Step 3: Check for Docker (Rancher Desktop)
REM ---------------------------------------------------------------------------
if "!S_DOCKER!"=="1" (
    echo [OK]  Rancher Desktop ^(already installed^)
    goto :docker_ok
)

echo [...]  Checking for Docker...

set "DOCKER_FOUND=0"
where docker >nul 2>nul && set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="1" goto :docker_found
if exist "%USERPROFILE%\.rd\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%USERPROFILE%\.rd\bin;!PATH!"
if "!DOCKER_FOUND!"=="1" goto :docker_found
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin;!PATH!"
if "!DOCKER_FOUND!"=="1" goto :docker_found
if exist "%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin;!PATH!"
:docker_found

if "!DOCKER_FOUND!"=="1" (
    echo [OK]  Docker is available.
    goto :docker_ok
)

echo.
echo ========================================
echo   Rancher Desktop needs to be installed
echo ========================================
echo.
echo   Rancher Desktop provides Docker for your computer.
echo   It's free and installs under your own account (no admin needed).
echo.

REM --- Strategy 1: Try winget (with source refresh, output suppressed) ---
where winget >nul 2>nul
if !ERRORLEVEL! neq 0 goto :try_direct_download

echo [...]  Updating package sources...
winget source update --name winget >nul 2>nul

echo [...]  Installing Rancher Desktop via winget...
echo         (this may take a few minutes)
winget install --id suse.RancherDesktop -e --source winget --accept-package-agreements --accept-source-agreements >nul 2>nul
if !ERRORLEVEL! equ 0 goto :rancher_installed

winget install --id SUSE.RancherDesktop -e --accept-package-agreements --accept-source-agreements >nul 2>nul
if !ERRORLEVEL! equ 0 goto :rancher_installed

echo [...]  Winget install did not work -- downloading directly...

REM --- Strategy 2: Direct download from GitHub releases ---
:try_direct_download
echo [...]  Downloading Rancher Desktop installer...
set "RD_INSTALLER=%TEMP%\RancherDesktopSetup.msi"
powershell -NoProfile -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "  $headers = @{}; " ^
    "  $rel = Invoke-RestMethod 'https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest' -Headers $headers -TimeoutSec 20; " ^
    "  $msi = $rel.assets | Where-Object { $_.name -like 'Rancher.Desktop.Setup*.msi' -and $_.name -notlike '*.sha512*' } | Select-Object -First 1; " ^
    "  if (-not $msi) { Write-Host 'No MSI found in latest release'; exit 1 }; " ^
    "  Write-Host ('   Downloading ' + $msi.name + ' (' + [math]::Round($msi.size/1MB,1) + ' MB)...'); " ^
    "  Invoke-WebRequest $msi.browser_download_url -OutFile '%RD_INSTALLER%' -UseBasicParsing; " ^
    "  if ((Get-Item '%RD_INSTALLER%').Length -lt 1MB) { Write-Host 'Download too small -- likely blocked'; exit 1 }; " ^
    "  exit 0 " ^
    "} catch { Write-Host ('Download failed: ' + $_.Exception.Message); exit 1 }"
if !ERRORLEVEL! neq 0 goto :download_failed

echo [...]  Installing (this may take a minute or two)...
echo         Please wait -- do not close this window.
REM ALLUSERS=0 = per-user install, no admin needed
start /wait msiexec /i "!RD_INSTALLER!" /passive /norestart ALLUSERS=0
if !ERRORLEVEL! neq 0 (
    echo [...]  Passive install did not work -- trying with installer UI...
    start /wait msiexec /i "!RD_INSTALLER!" /norestart ALLUSERS=0
)
del "!RD_INSTALLER!" >nul 2>nul

REM Wait for Rancher Desktop to actually exist on disk before continuing
echo [...]  Verifying installation...
set "RD_VERIFY=0"
for /L %%I in (1,1,12) do (
    if "!RD_VERIFY!"=="0" (
        if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" set "RD_VERIFY=1"
        if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" set "RD_VERIFY=1"
        if exist "%USERPROFILE%\.rd\bin\docker.exe" set "RD_VERIFY=1"
        if "!RD_VERIFY!"=="0" (
            timeout /t 5 /nobreak >nul
        )
    )
)
if "!RD_VERIFY!"=="0" (
    echo [WARN] Could not verify Rancher Desktop installed.
    echo        It may still be finishing. Restart and re-run this file.
    pause
    exit /b 1
)
goto :rancher_installed

:download_failed
REM --- Strategy 3: Open browser to download page (last resort) ---
echo.
echo ========================================
echo   Automatic install did not work
echo ========================================
echo.
echo   Opening the Rancher Desktop download page in your browser...
echo.
echo   When the page opens:
echo     1. Click the Windows download button
echo     2. Run the installer when it finishes downloading
echo     3. Choose "Install for me only" if asked
echo     4. Restart your computer
echo     5. Then double-click this file again
echo.
start "" "https://rancherdesktop.io/"
pause
exit /b 1

:rancher_installed
echo [OK]  Rancher Desktop installed.

REM Pre-configure Rancher Desktop to use dockerd (not containerd) and skip Kubernetes.
REM This prevents the first-run dialog from asking the user to choose an engine.
set "RD_SETTINGS_DIR=%APPDATA%\rancher-desktop"
if not exist "!RD_SETTINGS_DIR!" mkdir "!RD_SETTINGS_DIR!"
if not exist "!RD_SETTINGS_DIR!\settings.json" (
    powershell -NoProfile -Command ^
        "$s = @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } }; " ^
        "$s | ConvertTo-Json -Depth 5 | Set-Content '%RD_SETTINGS_DIR%\settings.json' -Encoding UTF8"
    echo [OK]  Pre-configured Rancher Desktop to use the correct engine.
)

echo.
echo   Please restart your computer now.
echo   Setup will continue automatically after restart.
echo.
>> "!STATE_FILE!" echo DOCKER=1
call :schedule_resume
pause
exit /b 0

:docker_ok

REM Verify Docker is actually running
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :docker_running
echo.
echo [WAIT] Docker is installed but not running yet.
echo.
echo   Look for the Rancher Desktop icon in your system tray
echo   (bottom-right corner of your screen, near the clock).
echo.
echo   Wait for it to stop spinning, then press any key.
echo.
pause
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :docker_running
echo [ERROR] Docker still not running.
echo         Try restarting your computer and running this file again.
pause
exit /b 1
:docker_running
echo [OK]  Docker is running.
>> "!STATE_FILE!" echo DOCKER=1

REM ---------------------------------------------------------------------------
REM Step 4: Download or update Claude Code Docker
REM ---------------------------------------------------------------------------
echo [...]  Getting Claude Code Docker...

if "!S_CLONE!"=="1" if exist "!INSTALL_DIR!\install.bat" goto :ccdw_update
if exist "!INSTALL_DIR!\install.bat" goto :ccdw_update
echo [...]  Downloading (this may take a minute)...
git clone https://github.com/SleepNumberInc/CCDW.git "!INSTALL_DIR!" 2>nul
if !ERRORLEVEL! equ 0 goto :ccdw_ready
echo.
echo ========================================
echo   Could not download Claude Code
echo ========================================
echo.
echo   Two things to check:
echo.
echo   1. VPN -- Make sure GlobalProtect is connected.
echo      Look for its icon in the system tray ^(bottom-right,
echo      near the clock^). Click it and verify it says "Connected".
echo.
echo   2. GitHub access -- Your GitHub account needs access to
echo      the Sleep Number organization. If you haven't set this
echo      up yet, go to https://github.com and sign in, then ask
echo      your manager or the AI CoE team to add you.
echo.
echo   After fixing, run this file again.
echo.
pause
exit /b 1
:ccdw_update
echo [...]  Updating to latest version...
pushd "!INSTALL_DIR!"
git pull >nul 2>nul
popd
:ccdw_ready
echo [OK]  Ready.
>> "!STATE_FILE!" echo CLONE=1

REM ---------------------------------------------------------------------------
REM Step 5: Run the installer (clean up state file -- setup is complete)
REM ---------------------------------------------------------------------------
if exist "!STATE_FILE!" del "!STATE_FILE!" >nul 2>nul
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "ClaudeCodeSetup" /f >nul 2>nul
echo.
echo ========================================
echo   Starting Claude Code installer...
echo ========================================
echo.

cd /d "!INSTALL_DIR!"
call "!INSTALL_DIR!\install.bat" --ai=foundry
goto :eof

REM ---------------------------------------------------------------------------
REM Subroutine: Schedule this script to auto-run after reboot
REM Uses HKCU\...\RunOnce -- no admin needed, runs once then deletes itself
REM ---------------------------------------------------------------------------
:schedule_resume
set "SELF_PATH=%~f0"
powershell -NoProfile -Command ^
    "try { " ^
    "  $path = '%SELF_PATH%'; " ^
    "  $val = 'cmd.exe /c \"' + $path + '\"'; " ^
    "  New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' " ^
    "    -Name 'ClaudeCodeSetup' -Value $val -PropertyType String -Force | Out-Null; " ^
    "  exit 0 " ^
    "} catch { exit 1 }"
if !ERRORLEVEL! equ 0 (
    echo [OK]  Setup will resume automatically after restart.
) else (
    echo [INFO] Could not set up auto-resume. After restarting,
    echo        double-click this file again to continue.
)
goto :eof
