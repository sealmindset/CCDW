@echo off
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
REM Check for Docker
REM ---------------------------------------------------------------------------
where docker >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker is not installed.
    echo.
    echo Please install one of the following:
    echo   - Docker Desktop:   https://www.docker.com/products/docker-desktop/
    echo   - Rancher Desktop:  https://rancherdesktop.io/
    echo.
    echo After installing, restart your computer and double-click this file again.
    echo.
    pause
    exit /b 1
)

docker info >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker is installed but not running.
    echo.
    echo Please start Docker Desktop or Rancher Desktop, wait for it to finish
    echo loading, then double-click this file again.
    echo.
    pause
    exit /b 1
)

echo [OK] Docker is running.

REM ---------------------------------------------------------------------------
REM Create projects folder
REM ---------------------------------------------------------------------------
set "PROJECTS_DIR=%USERPROFILE%\Documents\GitHub"

if not exist "%PROJECTS_DIR%" (
    echo [...]  Creating projects folder: %PROJECTS_DIR%
    mkdir "%PROJECTS_DIR%"
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Could not create %PROJECTS_DIR%
        pause
        exit /b 1
    )
)
echo [OK] Projects folder: %PROJECTS_DIR%

REM ---------------------------------------------------------------------------
REM Pull the latest image
REM ---------------------------------------------------------------------------
echo.
echo [...]  Downloading Claude Code Docker (this may take a few minutes)...
docker pull ghcr.io/sealmindset/claude-code-docker:latest
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to download the image. Check your internet connection.
    pause
    exit /b 1
)
echo [OK] Image downloaded.

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
    -p 7681:7681 ^
    -p 8080:8080 ^
    -v //var/run/docker.sock:/var/run/docker.sock ^
    -v "%PROJECTS_DIR%:/home/coder/Documents/GitHub" ^
    ghcr.io/sealmindset/claude-code-docker:latest

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to start the container.
    echo.
    echo Common fixes:
    echo   - Make sure ports 7681 and 8080 are not in use
    echo   - Restart Docker Desktop and try again
    echo.
    pause
    exit /b 1
)

echo [OK] Claude Code Docker is running!

REM ---------------------------------------------------------------------------
REM Wait for the web terminal to be ready, then open browser
REM ---------------------------------------------------------------------------
echo.
echo [...]  Waiting for web terminal to start...

set ATTEMPTS=0
:waitloop
if %ATTEMPTS% geq 30 goto timeout
timeout /t 2 /nobreak >nul
curl -s -o nul http://localhost:7681 2>nul
if %ERRORLEVEL% equ 0 goto ready
set /a ATTEMPTS+=1
goto waitloop

:ready
echo [OK] Web terminal is ready!
echo.
echo ========================================
echo   Opening Claude Code in your browser...
echo ========================================
echo.
start http://localhost:7681
echo.
echo   Web Terminal:  http://localhost:7681
echo   VS Code:       http://localhost:8080
echo.
echo   To stop: docker rm -f claude-code
echo   To restart: double-click this file again
echo.
pause
exit /b 0

:timeout
echo.
echo [OK] Container is starting up (it may take another moment).
echo      Opening browser anyway...
start http://localhost:7681
echo.
echo   Web Terminal:  http://localhost:7681
echo   VS Code:       http://localhost:8080
echo.
pause
exit /b 0
