@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code Docker - Reset to Fresh Install
REM
REM Removes the container, volumes, and settings so you can start over.
REM Your project files in Documents\GitHub are NOT deleted.
REM =============================================================================

title Claude Code Docker - Reset

echo.
echo ========================================
echo   Claude Code Docker - Reset
echo ========================================
echo.
echo   This will reset Claude Code to a fresh install.
echo.
echo   What gets removed:
echo     - Claude Code container and its settings
echo     - Saved login sessions (you will need to sign in again)
echo     - Desktop shortcut
echo.
echo   What is kept:
echo     - Your project files (Documents\GitHub folder)
echo     - Rancher Desktop (Docker)
echo     - This installer (you can run install.bat again)
echo.
choice /C YN /M "Continue with reset? Y=Yes, N=Cancel"
if !ERRORLEVEL! equ 2 (
    echo.
    echo   Reset cancelled. Nothing was changed.
    echo.
    pause
    exit /b 0
)

echo.

REM ---------------------------------------------------------------------------
REM Find Docker CLI (same search order as install.bat)
REM ---------------------------------------------------------------------------
set "DOCKER_CMD="
where docker >nul 2>nul && set "DOCKER_CMD=docker"
if not defined DOCKER_CMD if exist "%USERPROFILE%\.rd\bin\docker.exe" set "DOCKER_CMD=%USERPROFILE%\.rd\bin\docker.exe"
if not defined DOCKER_CMD if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" set "DOCKER_CMD=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"
if not defined DOCKER_CMD if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_CMD=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe"

if not defined DOCKER_CMD (
    echo [SKIP] Docker not found -- skipping container cleanup.
    goto :skip_docker_cleanup
)

REM ---------------------------------------------------------------------------
REM Stop and remove the container
REM ---------------------------------------------------------------------------
echo [...]  Stopping Claude Code container...
"!DOCKER_CMD!" rm -f claude-code >nul 2>nul
echo [OK]  Container removed.

REM ---------------------------------------------------------------------------
REM Remove named volumes (settings, auth cache, git config)
REM ---------------------------------------------------------------------------
echo [...]  Removing saved settings...
for %%V in (claude-code-data claude-code-gh claude-code-git-config) do (
    "!DOCKER_CMD!" volume rm %%V >nul 2>nul
)
echo [OK]  Settings removed.

:skip_docker_cleanup

REM ---------------------------------------------------------------------------
REM Remove desktop shortcut
REM ---------------------------------------------------------------------------
echo [...]  Removing desktop shortcut...
powershell -NoProfile -Command ^
    "$desktop = [Environment]::GetFolderPath('Desktop'); " ^
    "foreach ($name in @('Claude.lnk','Claude Code.url')) { " ^
    "  $p = Join-Path $desktop $name; " ^
    "  if (Test-Path $p) { Remove-Item $p -Force -EA SilentlyContinue } " ^
    "}"
echo [OK]  Shortcut removed.

REM ---------------------------------------------------------------------------
REM Remove generated icon
REM ---------------------------------------------------------------------------
if exist "%~dp0claude.ico" del "%~dp0claude.ico" >nul 2>nul

REM ---------------------------------------------------------------------------
REM Reset .env to template (keep a backup)
REM ---------------------------------------------------------------------------
if exist "%~dp0.env" (
    if exist "%~dp0.env.example" (
        copy "%~dp0.env" "%~dp0.env.backup" >nul 2>nul
        copy "%~dp0.env.example" "%~dp0.env" >nul 2>nul
        echo [OK]  Reset .env to defaults (backup saved as .env.backup^)
    )
)

echo.
echo ========================================
echo   Reset complete!
echo ========================================
echo.
echo   To set up Claude Code again, double-click install.bat
echo.
pause
endlocal
exit /b 0
