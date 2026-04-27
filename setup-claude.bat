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
REM Step 1: Check for Git
REM ---------------------------------------------------------------------------
echo [...]  Checking for Git...
where git >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  Git is installed.
    goto :git_ok
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

:git_ok

REM ---------------------------------------------------------------------------
REM Step 2: Check for WSL2
REM ---------------------------------------------------------------------------
echo [...]  Checking for WSL2...
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 is installed.
    goto :wsl_ok
)

echo.
echo ========================================
echo   WSL2 needs to be installed
echo ========================================
echo.
echo   WSL2 is a Windows feature that Docker needs.
echo   Windows will ask for an admin password.
echo   Use the admin credentials from your Local Admin email.
echo.
echo   After installing, your computer must restart.
echo   Then double-click this file again to continue.
echo.
pause

wsl --install
if !ERRORLEVEL! neq 0 (
    echo [ERROR] WSL2 installation failed.
    echo         Make sure you have Local Admin rights.
    echo         See the setup guide for how to request them.
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

REM ---------------------------------------------------------------------------
REM Step 4: Download or update Claude Code Docker
REM ---------------------------------------------------------------------------
echo [...]  Getting Claude Code Docker...

if exist "!INSTALL_DIR!\install.bat" goto :ccdw_update
echo [...]  Downloading (this may take a minute)...
git clone https://github.com/SleepNumberInc/CCDW.git "!INSTALL_DIR!" 2>nul
if !ERRORLEVEL! equ 0 goto :ccdw_ready
echo [ERROR] Could not download Claude Code Docker.
echo         Make sure you have GitHub access and are connected to VPN.
echo         See the setup guide for how to request GitHub access.
pause
exit /b 1
:ccdw_update
echo [...]  Updating to latest version...
pushd "!INSTALL_DIR!"
git pull >nul 2>nul
popd
:ccdw_ready
echo [OK]  Ready.

REM ---------------------------------------------------------------------------
REM Step 5: Run the installer
REM ---------------------------------------------------------------------------
echo.
echo ========================================
echo   Starting Claude Code installer...
echo ========================================
echo.

cd /d "!INSTALL_DIR!"
call "!INSTALL_DIR!\install.bat" --ai=foundry
