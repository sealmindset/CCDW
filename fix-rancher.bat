@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code - Fix Rancher Desktop
REM
REM Fixes the "wsl.exe exited with code 4294967295" error that happens when
REM Rancher Desktop's internal WSL distributions get corrupted.
REM
REM What this does:
REM   1. Closes Rancher Desktop
REM   2. Removes the corrupted internal distributions (your files are safe)
REM   3. Restarts Rancher Desktop so it recreates fresh ones
REM   4. Waits for Docker to be ready
REM
REM What it does NOT touch:
REM   - Your project files
REM   - Your Ubuntu or other WSL distributions
REM   - Your Docker containers and images
REM   - Your Claude Code settings
REM =============================================================================

title Claude Code - Fix Rancher Desktop

echo.
echo ========================================
echo   Claude Code - Fix Rancher Desktop
echo ========================================
echo.
echo   This fixes the issue where Rancher Desktop gets stuck
echo   and Docker stops working. Your files and projects are
echo   not affected.
echo.

REM ---------------------------------------------------------------------------
REM Quick diagnosis: show current WSL state
REM ---------------------------------------------------------------------------
echo   Current status:
echo.
wsl -l -v 2>nul | findstr /i "rancher" >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo     No Rancher Desktop distributions found in WSL.
    echo     Rancher Desktop may need to be reinstalled.
    echo.
    echo     Try opening Rancher Desktop from the Start menu.
    echo     If that does not work, run setup-claude.bat to reinstall.
    echo.
    pause
    exit /b 0
)

REM Show the WSL distro status
echo     WSL distributions:
for /f "delims=" %%L in ('wsl -l -v 2^>nul') do echo       %%L
echo.

REM ---------------------------------------------------------------------------
REM Test if the distros are actually broken
REM ---------------------------------------------------------------------------
echo [...]  Testing Rancher Desktop WSL health...
set "NEEDS_REPAIR=0"

REM Test rancher-desktop distro
wsl -d rancher-desktop -- echo ok >nul 2>nul
if !ERRORLEVEL! neq 0 (
    set "NEEDS_REPAIR=1"
    echo [FAIL] rancher-desktop distribution is not responding.
) else (
    echo [OK]   rancher-desktop distribution is healthy.
)

REM Test Ubuntu distro (Rancher uses it for docker-plugins and kubeconfig)
wsl -l 2>nul | findstr /i "Ubuntu" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    wsl -d Ubuntu -- echo ok >nul 2>nul
    if !ERRORLEVEL! neq 0 (
        set "NEEDS_REPAIR=1"
        echo [FAIL] Ubuntu distribution is not responding.
    ) else (
        echo [OK]   Ubuntu distribution is healthy.
    )
)

REM Check if Docker itself is working
docker info >nul 2>nul
if !ERRORLEVEL! neq 0 (
    set "NEEDS_REPAIR=1"
    echo [FAIL] Docker engine is not responding.
) else (
    echo [OK]   Docker engine is running.
)

if "!NEEDS_REPAIR!"=="0" (
    echo.
    echo ========================================
    echo   Everything looks healthy!
    echo ========================================
    echo.
    echo   Rancher Desktop and Docker are both working.
    echo.
    echo   If you are still having issues, you can force
    echo   a repair anyway.
    echo.
    choice /C FQ /N /M "  [F]orce repair anyway  [Q]uit: "
    if !ERRORLEVEL! equ 2 (
        echo.
        echo   No changes made.
        echo.
        pause
        exit /b 0
    )
    echo.
)

REM ---------------------------------------------------------------------------
REM Confirm before proceeding
REM ---------------------------------------------------------------------------
echo.
echo   The repair will:
echo     - Close Rancher Desktop
echo     - Remove its internal WSL distributions
echo       ^(NOT Ubuntu or other personal distros^)
echo     - Restart Rancher Desktop with fresh distributions
echo.
echo   This takes about 3-5 minutes.
echo.
choice /C RQ /N /M "  [R]epair now  [Q]uit: "
if !ERRORLEVEL! equ 2 (
    echo.
    echo   No changes made.
    echo.
    pause
    exit /b 0
)

echo.

REM ---------------------------------------------------------------------------
REM Run the PowerShell repair script
REM ---------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fix-rancher-wsl.ps1"
set "FIX_RESULT=!ERRORLEVEL!"

echo.
if "!FIX_RESULT!"=="0" (
    echo ========================================
    echo   Repair complete!
    echo ========================================
    echo.
    echo   Rancher Desktop is running with fresh WSL distributions
    echo   and Docker is ready.
    echo.
    echo   You can now run install.bat or use Docker normally.
) else if "!FIX_RESULT!"=="2" (
    echo ========================================
    echo   Repair in progress
    echo ========================================
    echo.
    echo   The corrupted distributions were removed and Rancher
    echo   Desktop is recreating them. This can take a few
    echo   more minutes.
    echo.
    echo   Wait for the Rancher Desktop icon in your system tray
    echo   to show a green checkmark, then try install.bat again.
) else (
    echo ========================================
    echo   No repair needed
    echo ========================================
    echo.
    echo   If Docker still is not working, try:
    echo     1. Close Rancher Desktop ^(right-click tray icon, Quit^)
    echo     2. Restart your computer
    echo     3. Open Rancher Desktop from the Start menu
    echo     4. Wait 2-3 minutes
    echo     5. Run install.bat
)

echo.
pause
endlocal
exit /b 0
