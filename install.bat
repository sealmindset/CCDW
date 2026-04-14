@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code Docker - Windows One-Click Installer
REM Double-click this file to install and start Claude Code Docker.
REM =============================================================================

title Claude Code Docker - Installer

echo.
echo ========================================
echo   Claude Code Docker - Installer
echo ========================================
echo.

REM ---------------------------------------------------------------------------
REM Check for Docker (via Rancher Desktop or Docker Desktop)
REM ---------------------------------------------------------------------------
where docker >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker is not installed.
    echo.
    echo Please install Rancher Desktop:
    echo   https://rancherdesktop.io/
    echo.
    echo During installation, select "dockerd (moby)" as the container engine.
    echo After installing, restart your computer and double-click this file again.
    echo.
    pause
    exit /b 1
)

REM Docker engine can take up to 60s to start -- wait and retry
set DOCKER_READY=0
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 (
    set DOCKER_READY=1
) else (
    echo [...]  Docker engine is starting up, waiting...
    for /L %%i in (1,1,12) do (
        if !DOCKER_READY! equ 0 (
            ping -n 6 127.0.0.1 >nul
            docker info >nul 2>nul
            if !ERRORLEVEL! equ 0 set DOCKER_READY=1
        )
    )
)

if !DOCKER_READY! equ 0 (
    echo [ERROR] Docker engine did not start after 60 seconds.
    echo.
    echo How to fix:
    echo   1. Open Rancher Desktop from your Start menu
    echo   2. Wait for it to finish starting (icon stops spinning in system tray)
    echo   3. Make sure the container engine is set to "dockerd (moby)":
    echo      Rancher Desktop ^> Preferences ^> Container Engine ^> dockerd (moby)
    echo   4. Double-click this file again
    echo.
    echo If you're using Docker Desktop instead, make sure it's running.
    echo.
    pause
    exit /b 1
)

echo [OK] Docker is running.

REM ---------------------------------------------------------------------------
REM Create required folders
REM ---------------------------------------------------------------------------
set "PROJECTS_DIR=%USERPROFILE%\Documents\GitHub"
set "AZURE_DIR=%USERPROFILE%\.azure"

if not exist "%PROJECTS_DIR%" (
    echo [...]  Creating projects folder: %PROJECTS_DIR%
    mkdir "%PROJECTS_DIR%"
)
if not exist "%PROJECTS_DIR%" (
    echo [ERROR] Could not create %PROJECTS_DIR%
    pause
    exit /b 1
)
echo [OK] Projects folder: %PROJECTS_DIR%

if not exist "%AZURE_DIR%" (
    echo [...]  Creating Azure config folder: %AZURE_DIR%
    mkdir "%AZURE_DIR%"
)

REM ---------------------------------------------------------------------------
REM Auto-update: always pull latest image
REM ---------------------------------------------------------------------------
echo.
echo [...]  Checking for updates and downloading latest version...
docker pull ghcr.io/sealmindset/claude-code-docker:latest
if %ERRORLEVEL% neq 0 (
    echo [WARN] Could not check for updates. Using cached image if available.
)
echo [OK] Image is up to date.

REM ---------------------------------------------------------------------------
REM Stop existing container if running
REM ---------------------------------------------------------------------------
docker rm -f claude-code >nul 2>nul

REM ---------------------------------------------------------------------------
REM Start the container
REM ---------------------------------------------------------------------------
echo.
echo [...]  Starting Claude Code Docker...
docker run -d ^
    --name claude-code ^
    --group-add 0 ^
    -p 3000:3000 ^
    -p 7681:7681 ^
    -p 8080:8080 ^
    -v //var/run/docker.sock:/var/run/docker.sock ^
    -v "%PROJECTS_DIR%:/home/coder/Documents/GitHub" ^
    -v "%AZURE_DIR%:/home/coder/.azure" ^
    -v claude-code-data:/home/coder/.claude ^
    -v claude-code-gh:/home/coder/.config/gh ^
    -v claude-code-git-config:/home/coder/.gitconfig.d ^
    ghcr.io/sealmindset/claude-code-docker:latest

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to start the container.
    echo.
    echo Common fixes:
    echo   - Make sure ports 3000, 7681 and 8080 are not in use
    echo   - Restart Rancher Desktop and try again
    echo.
    pause
    exit /b 1
)

echo [OK] Claude Code Docker is running!

REM ---------------------------------------------------------------------------
REM Wait for the dashboard to be ready, then open browser
REM ---------------------------------------------------------------------------
echo.
echo [...]  Waiting for dashboard to start...

set ATTEMPTS=0
:waitloop
if !ATTEMPTS! geq 30 goto timedout
ping -n 3 127.0.0.1 >nul
curl.exe -s -o nul http://localhost:3000 2>nul
if !ERRORLEVEL! equ 0 goto ready
set /a ATTEMPTS+=1
goto waitloop

:ready
echo [OK] Dashboard is ready!
echo.
echo ========================================
echo   Opening Claude Code in your browser...
echo ========================================
echo.
start http://localhost:3000
goto shortcuts

:timedout
echo.
echo [OK] Container is starting up (it may take another moment).
echo      Opening browser anyway...
start http://localhost:3000

:shortcuts
REM ---------------------------------------------------------------------------
REM Create desktop shortcut
REM ---------------------------------------------------------------------------
echo.
echo [...]  Creating desktop shortcut...

set "SHORTCUT=%USERPROFILE%\Desktop\Claude Code.url"
(
    echo [InternetShortcut]
    echo URL=http://localhost:3000
    echo IconIndex=0
) > "%SHORTCUT%"

if exist "%SHORTCUT%" (
    echo [OK] Desktop shortcut created: "Claude Code" on your desktop
) else (
    echo [WARN] Could not create desktop shortcut
)

echo.
echo ========================================
echo   Claude Code Docker is ready!
echo ========================================
echo.
echo   Dashboard:     http://localhost:3000
echo   Web Terminal:  http://localhost:7681
echo   VS Code:       http://localhost:8080
echo.
echo   FIRST TIME? Click "Web Terminal" in the dashboard
echo   and follow the login wizard to sign in to Azure.
echo.
echo   To stop:    docker rm -f claude-code
echo   To restart: double-click "Claude Code" on your desktop
echo.
pause
endlocal
exit /b 0
