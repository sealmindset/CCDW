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
REM Step 2: Check for WSL2
REM ---------------------------------------------------------------------------
if "!S_WSL!"=="1" (
    echo [OK]  WSL2 ^(already done^)
    goto :wsl_ok
)

echo [...]  Checking for WSL2...
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 is installed.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_ok
)

echo.
echo ========================================
echo   WSL2 needs to be installed
echo ========================================
echo.
echo   WSL2 is a Windows feature that Docker needs.
echo.
echo   Windows will pop up asking for an admin password.
echo   Use your SSMITH Local Admin credentials. To find them:
echo     - Search your email for "Local Admin" or "SSMITH"
echo     - The username is usually SSMITH (all caps)
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
    echo.
    echo [ERROR] WSL2 installation failed.
    echo.
    echo   This usually means the admin password was wrong or you
    echo   don't have Local Admin rights on this computer.
    echo.
    echo   Search your email for "Local Admin" or "SSMITH" to find
    echo   your credentials. If you don't have them, contact the
    echo   IT Service Desk to request Local Admin access.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Restart required
echo ========================================
echo.
echo   WSL2 was installed successfully.
echo.
echo   Please restart your computer now.
echo   After it restarts, double-click this file again.
echo.
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

REM Try winget first
where winget >nul 2>nul
if !ERRORLEVEL! neq 0 goto :no_winget_rancher
echo [...]  Installing Rancher Desktop...
winget install --id suse.RancherDesktop -e --source winget --accept-package-agreements --accept-source-agreements
if !ERRORLEVEL! neq 0 goto :no_winget_rancher
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
echo   Please restart your computer, then double-click this file again.
echo   After restarting, wait for the Rancher Desktop icon in your
echo   system tray to stop spinning before running this setup again.
echo.
pause
exit /b 0
:no_winget_rancher

echo   Please install Rancher Desktop manually:
echo.
echo     1. Open your browser
echo     2. Go to https://rancherdesktop.io
echo     3. Click the download button
echo     4. Run the installer -- choose "Install for me only"
echo     5. Restart your computer
echo     6. Then double-click this file again
echo.
pause
exit /b 1

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
echo.
echo ========================================
echo   Starting Claude Code installer...
echo ========================================
echo.

cd /d "!INSTALL_DIR!"
call "!INSTALL_DIR!\install.bat" --ai=foundry
