@echo off
title Claude Code - Setup
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

REM --- Prevent window from closing: re-launch in a persistent cmd /k shell ---
REM Double-clicking a .bat runs it under cmd /c which closes on exit.
REM We re-launch under cmd /k (same window) so the window stays open.
REM The --wrapped flag prevents infinite re-launch loop.
if "%~1"=="--wrapped" goto :start_main
cmd /k call "%~f0" --wrapped
echo.
echo   Window kept open for review. Press any key to close...
pause >nul
exit

:start_main
setlocal EnableDelayedExpansion

REM --- Log file: captures progress so we can diagnose if window closes ---
set "SETUP_LOG=%TEMP%\claude-setup-log.txt"
echo [%date% %time%] Claude Code Setup started > "!SETUP_LOG!"

echo.
echo ========================================
echo   Claude Code - Setup
echo ========================================
echo.
echo   Log file: !SETUP_LOG!
echo.

REM ---------------------------------------------------------------------------
REM Determine install location (user's Documents folder, auto-detected)
REM ---------------------------------------------------------------------------
echo [%date% %time%] Determining install location >> "!SETUP_LOG!"
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
echo [%date% %time%] Step 0: Connectivity check >> "!SETUP_LOG!"
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
echo [...]  Checking Sleep Number network access...
curl.exe -so nul -w "%%{http_code}" --connect-timeout 10 https://snapistg-scus.azure.sleepnumber.com 2>nul | findstr /v "^000$" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  Sleep Number network reachable.
) else (
    echo.
    echo ========================================
    echo   Cannot reach Sleep Number services
    echo ========================================
    echo.
    echo   Claude Code needs access to Sleep Number services.
    echo   This works on the corporate network OR via VPN.
    echo.
    echo   If you're in the office:
    echo     - Make sure you're on the corporate network ^(not guest Wi-Fi^)
    echo.
    echo   If you're remote:
    echo     1. Look for the GlobalProtect icon in the system tray
    echo        ^(bottom-right corner, near the clock^)
    echo     2. Click it and make sure it says "Connected"
    echo     3. If you don't see it, search for "GlobalProtect"
    echo        in the Start menu and open it
    echo.
    echo   Press any key after connecting...
    echo.
    pause
    curl.exe -so nul -w "%%{http_code}" --connect-timeout 10 https://snapistg-scus.azure.sleepnumber.com 2>nul | findstr /v "^000$" >nul 2>nul
    if !ERRORLEVEL! neq 0 (
        echo.
        echo [ERROR] Still cannot reach Sleep Number services.
        echo         Check your network connection ^(corporate network or VPN^) and try again.
        echo.
        pause
        exit /b 1
    )
    echo [OK]  Sleep Number network reachable.
)

REM ---------------------------------------------------------------------------
REM Step 1: Check for Git
REM ---------------------------------------------------------------------------
echo [%date% %time%] Step 1: Git check >> "!SETUP_LOG!"
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
echo [%date% %time%] Step 2: WSL2 check >> "!SETUP_LOG!"
if "!S_WSL!"=="0" goto :wsl_check_fresh
REM --- WSL resume: verify it actually works (restart may not have happened) ---
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 goto :wsl_resume_ok
wsl -l -q >nul 2>nul
if !ERRORLEVEL! equ 0 goto :wsl_resume_ok
wsl --version >nul 2>nul
if !ERRORLEVEL! equ 0 goto :wsl_resume_ok
goto :wsl_needs_restart

:wsl_resume_ok
echo [OK]  WSL2 ^(verified^)
goto :wsl_ok

:wsl_needs_restart
echo.
echo ========================================
echo   WSL2 needs a restart to finish
echo ========================================
echo.
echo   WSL2 was installed earlier but is not responding.
echo   A Windows restart is needed to activate it.
echo.
echo   This is the most common issue -- once you restart,
echo   everything else installs smoothly.
echo.
choice /c RQ /n /m "  [R]estart now  [Q]uit and restart later: "
if !ERRORLEVEL! equ 1 (
    call :schedule_resume
    echo.
    echo   Restarting in 10 seconds...
    echo   Setup will resume automatically after restart.
    shutdown /r /t 10 /c "Restarting to complete WSL2 setup..."
    exit /b 0
)
echo.
echo   After restarting Windows, double-click this file again.
echo.
pause
exit /b 0

:wsl_check_fresh
echo [...]  Checking for WSL2...

REM --- Pre-flight: Windows build check (WSL2 needs build 18362+) ---
REM ver output: "Microsoft Windows [Version 10.0.BUILD.REV]"
for /f "tokens=2 delims=[]" %%V in ('ver 2^>nul') do (
    for /f "tokens=3 delims=." %%B in ("%%V") do set "WIN_BUILD=%%B"
)
if defined WIN_BUILD (
    if !WIN_BUILD! LSS 18362 (
        echo.
        echo ========================================
        echo   Windows version too old for WSL2
        echo ========================================
        echo.
        echo   WSL2 requires Windows 10 build 18362 ^(May 2019^) or later.
        echo   Your build: !WIN_BUILD!
        echo.
        echo   Please update Windows via Settings ^> Update ^& Security
        echo   ^> Windows Update, then run this setup again.
        echo.
        pause
        exit /b 1
    )
)

REM --- Pre-flight: CPU virtualization check (VT-x / AMD-V) ---
REM Advisory only -- some vPro/enterprise systems report false even when working.
REM Single-line PowerShell to avoid cmd.exe misinterpreting parentheses in multi-line commands.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check-vtx.ps1" >nul 2>nul
if !ERRORLEVEL! equ 1 (
    echo [NOTE] VT-x check could not confirm hardware virtualization is enabled.
    echo        This is normal on some corporate/vPro systems.
    echo        If Docker has trouble starting later, VT-x may need to be
    echo        enabled in BIOS -- ask IT for help if that happens.
    echo.
)

REM First check if WSL2 is already working.
REM wsl --status returns non-zero on some machines even when WSL works fine
REM (e.g., features enabled but no default distro). Check multiple signals.
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 is installed.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_ok
)
REM Fallback: if wsl.exe exists and a distro is installed, WSL is working.
where wsl >nul 2>nul
if !ERRORLEVEL! equ 0 (
    wsl -l -q >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo [OK]  WSL2 is installed.
        >> "!STATE_FILE!" echo WSL=1
        goto :wsl_ok
    )
)

REM WSL2 not installed or not working. wsl --install handles everything:
REM enables Windows features, downloads WSL, installs default distro.
REM Skip manual feature detection -- Get-WindowsOptionalFeature needs admin
REM to query accurately on some corporate/vPro machines and gives false negatives.
echo.
echo ========================================
echo   Installing WSL2
echo ========================================
echo.
echo   This sets up WSL2 ^(needed by Docker^). It handles
echo   everything automatically -- features, downloads, install.
echo.
echo   If Windows asks for an admin password, use your
echo   SSMITH Local Admin credentials:
echo     Username:  SSMITH  ^(all caps, exactly as shown^)
echo     Password:  from your "Local Admin" email or CyberArk
echo.
echo   To find the password: search email for "Local Admin"
echo   or "SSMITH". If you can't find it, check CyberArk or
echo   contact IT Service Desk.
echo.
echo   Wrong password or not sure? Click "No" on the prompt --
echo   setup will try a workaround that may not need admin.
echo.

wsl --install --no-launch
if !ERRORLEVEL! neq 0 (
    REM wsl --install may fail but still succeed -- Windows quirk.
    REM Also try wsl --update as a fallback.
    echo [...]  Trying WSL update as fallback...
    wsl --update >nul 2>nul
)

REM Check if WSL is now functional (may work without reboot on newer Windows)
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 installed and ready.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_ok
)
wsl --version >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK]  WSL2 installed and ready.
    >> "!STATE_FILE!" echo WSL=1
    goto :wsl_ok
)

REM WSL installed but not responding yet -- let user decide
echo.
echo ========================================
echo   WSL2 installed -- restart required
echo ========================================
echo.
echo   WSL2 was installed but needs a Windows restart
echo   to become active. Rancher Desktop cannot install
echo   without a working WSL2.
echo.
echo   This restart is the most important step -- once done,
echo   everything else installs smoothly.
echo.
>> "!STATE_FILE!" echo WSL=1
choice /c RC /n /m "  [R]estart now (recommended)  [C]ontinue (will likely need restart later): "
if !ERRORLEVEL! equ 1 (
    call :schedule_resume
    echo.
    echo   Restarting in 10 seconds...
    echo   Setup will resume automatically after restart.
    shutdown /r /t 10 /c "Restarting to complete WSL2 setup..."
    exit /b 0
)
echo [WARN] Continuing without confirmed WSL2. Rancher Desktop may fail to install.

:wsl_ok

REM ---------------------------------------------------------------------------
REM Step 2b: Check Rancher Desktop WSL distribution health
REM Rancher uses three distros: rancher-desktop, rancher-desktop-data, Ubuntu.
REM If any are corrupted (exit code 4294967295), auto-repair all of them.
REM ---------------------------------------------------------------------------
set "WSL_CORRUPT=0"
wsl -l 2>nul | findstr /i "rancher-desktop" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    wsl -d rancher-desktop -- echo ok >nul 2>nul
    if !ERRORLEVEL! neq 0 set "WSL_CORRUPT=1"
)
if "!WSL_CORRUPT!"=="0" (
    wsl -l 2>nul | findstr /i "Ubuntu" >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        wsl -d Ubuntu -- echo ok >nul 2>nul
        if !ERRORLEVEL! neq 0 set "WSL_CORRUPT=1"
    )
)
if "!WSL_CORRUPT!"=="0" goto :wsl_distros_ok
echo [%date% %time%] WSL distros corrupted -- auto-repairing >> "!SETUP_LOG!"
echo [WARN] WSL distributions are corrupted. Repairing...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fix-rancher-wsl.ps1" -Quiet
if !ERRORLEVEL! equ 0 (
    echo [OK]  Rancher Desktop repaired.
    echo [%date% %time%] Rancher WSL repair successful >> "!SETUP_LOG!"
) else (
    echo [WARN] Auto-repair did not fully complete. Continuing...
    echo [%date% %time%] Rancher WSL repair incomplete >> "!SETUP_LOG!"
)
:wsl_distros_ok

REM ---------------------------------------------------------------------------
REM Step 3: Check for Docker (Rancher Desktop)
REM ---------------------------------------------------------------------------
echo [%date% %time%] Step 3: Docker check >> "!SETUP_LOG!"
if "!S_DOCKER!"=="1" (
    if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" (
        echo [OK]  Rancher Desktop ^(verified^)
        goto :docker_ok
    )
    if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" (
        echo [OK]  Rancher Desktop ^(verified^)
        goto :docker_ok
    )
    if exist "%USERPROFILE%\.rd\bin\docker.exe" (
        echo [OK]  Rancher Desktop ^(verified^)
        goto :docker_ok
    )
    echo [WARN] Rancher Desktop was marked installed but not found on disk.
    echo        Re-running installation step...
    echo.
)

echo [...]  Checking for Docker...

REM --- Check if Docker Desktop is running (conflicts with Rancher Desktop) ---
set "DD_RUNNING=0"
tasklist /fi "imagename eq Docker Desktop.exe" 2>nul | find /i "Docker Desktop" >nul 2>nul
if !ERRORLEVEL! equ 0 set "DD_RUNNING=1"
REM com.docker.backend is the Docker Desktop engine process
tasklist /fi "imagename eq com.docker.backend.exe" 2>nul | find /i "com.docker.backend" >nul 2>nul
if !ERRORLEVEL! equ 0 set "DD_RUNNING=1"

if "!DD_RUNNING!"=="1" (
    echo.
    echo ========================================
    echo   Docker Desktop is running
    echo ========================================
    echo.
    echo   Docker Desktop and Rancher Desktop cannot run at
    echo   the same time -- both try to control the Docker
    echo   engine and WSL2 integration.
    echo.
    echo   Claude Code uses Rancher Desktop.
    echo   Docker Desktop needs to be closed first.
    echo.
    choice /c SQ /n /m "  [S]top Docker Desktop automatically  [Q]uit and close it yourself: "
    if !ERRORLEVEL! equ 2 (
        echo.
        echo   Close Docker Desktop ^(right-click its icon in the
        echo   system tray near the clock, click "Quit Docker Desktop"^),
        echo   then run this setup again.
        echo.
        pause
        exit /b 1
    )
    echo.
    echo [%date% %time%] Stopping Docker Desktop >> "!SETUP_LOG!"
    echo [...]  Stopping Docker Desktop...
    taskkill /im "Docker Desktop.exe" /f >nul 2>nul
    taskkill /im "com.docker.backend.exe" /f >nul 2>nul
    taskkill /im "com.docker.service" /f >nul 2>nul
    timeout /t 3 /nobreak >nul
    REM Verify it stopped
    tasklist /fi "imagename eq com.docker.backend.exe" 2>nul | find /i "com.docker.backend" >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo [WARN] Could not fully stop Docker Desktop.
        echo        Right-click its tray icon and "Quit Docker Desktop",
        echo        then run this setup again.
        echo.
        pause
        exit /b 1
    )
    echo [OK]  Docker Desktop stopped.
    echo.
)

REM --- Look for Rancher Desktop's docker (not Docker Desktop's) ---
set "DOCKER_FOUND=0"
if exist "%USERPROFILE%\.rd\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%USERPROFILE%\.rd\bin;!PATH!"
if "!DOCKER_FOUND!"=="1" goto :docker_found
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin;!PATH!"
if "!DOCKER_FOUND!"=="1" goto :docker_found
if exist "%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1" & set "PATH=%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin;!PATH!"
if "!DOCKER_FOUND!"=="1" goto :docker_found
REM Only fall back to generic docker if it's NOT Docker Desktop's
where docker >nul 2>nul
if !ERRORLEVEL! neq 0 goto :docker_found
for /f "delims=" %%P in ('where docker 2^>nul') do (
    set "_SKIP=0"
    echo "%%P" | find /i "Docker Desktop" >nul 2>nul && set "_SKIP=1"
    echo "%%P" | find /i "\Docker\" >nul 2>nul && set "_SKIP=1"
    if "!_SKIP!"=="0" set "DOCKER_FOUND=1"
)
:docker_found

if "!DOCKER_FOUND!"=="1" (
    echo [OK]  Docker is available ^(Rancher Desktop^).
    goto :docker_ok
)

REM --- Rancher Desktop installed but docker CLI not in PATH yet? ---
REM This catches the case where Rancher is installed but has never been
REM fully started, so .rd\bin\docker.exe does not exist yet.
set "RD_INSTALLED=0"
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" set "RD_INSTALLED=1"
if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" set "RD_INSTALLED=1"
REM Also detect if it's already running
tasklist /fi "imagename eq Rancher Desktop.exe" 2>nul | findstr /i "Rancher" >nul 2>nul
if !ERRORLEVEL! equ 0 set "RD_INSTALLED=1"
tasklist /fi "imagename eq rdctl.exe" 2>nul | findstr /i "rdctl" >nul 2>nul
if !ERRORLEVEL! equ 0 set "RD_INSTALLED=1"

if "!RD_INSTALLED!"=="1" (
    echo [OK]  Rancher Desktop is installed -- just needs to start.
    >> "!STATE_FILE!" echo DOCKER=1
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

REM --- Pre-check: WSL2 must be functional before Rancher Desktop can install ---
set "WSL_GATE=0"
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 set "WSL_GATE=1"
if "!WSL_GATE!"=="0" (
    wsl -l -q >nul 2>nul
    if !ERRORLEVEL! equ 0 set "WSL_GATE=1"
)
if "!WSL_GATE!"=="0" (
    wsl --version >nul 2>nul
    if !ERRORLEVEL! equ 0 set "WSL_GATE=1"
)
if "!WSL_GATE!"=="1" goto :wsl_gate_passed
echo.
echo ========================================
echo   Restart needed before Rancher Desktop
echo ========================================
echo.
echo   Rancher Desktop requires WSL2, but WSL2 is not
echo   responding yet. A Windows restart is needed to
echo   activate the WSL2 features that were installed.
echo.
>> "!STATE_FILE!" echo WSL=1
choice /c RQ /n /m "  [R]estart now  [Q]uit and restart later: "
if !ERRORLEVEL! equ 1 (
    call :schedule_resume
    echo.
    echo   Restarting in 10 seconds...
    echo   Setup will resume automatically after restart.
    shutdown /r /t 10 /c "Restarting to activate WSL2..."
    exit /b 0
)
echo.
echo   After restarting Windows, double-click this file again.
echo.
pause
exit /b 0

:wsl_gate_passed

REM --- Strategy 1: Try winget (with source refresh, output suppressed) ---
where winget >nul 2>nul
if !ERRORLEVEL! neq 0 goto :try_direct_download

echo [...]  Updating package sources...
winget source update --name winget >nul 2>nul

echo [%date% %time%] Installing via winget >> "!SETUP_LOG!"
echo [...]  Installing Rancher Desktop via winget...
echo         This may take a few minutes -- you will see
echo         progress from the Windows package manager below.
echo.
winget install --id suse.RancherDesktop -e --source winget --accept-package-agreements --accept-source-agreements
set "WINGET_ERR=!ERRORLEVEL!"
if "!WINGET_ERR!"=="0" goto :rancher_installed

winget install --id SUSE.RancherDesktop -e --accept-package-agreements --accept-source-agreements
set "WINGET_ERR=!ERRORLEVEL!"
if "!WINGET_ERR!"=="0" goto :rancher_installed

echo.
echo [...]  Winget install did not work -- downloading directly...

REM --- Strategy 2: Direct download from GitHub releases ---
:try_direct_download
echo [...]  Downloading Rancher Desktop installer...
set "RD_INSTALLER=%TEMP%\RancherDesktopSetup.msi"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download-rancher-installer.ps1" "!RD_INSTALLER!"
if !ERRORLEVEL! neq 0 goto :download_failed

echo.
echo [...]  Installing Rancher Desktop...
echo.
echo         A separate installer window will appear.
echo         DO NOT close this window -- it will continue
echo         automatically when the installer finishes.
echo.
echo         If nothing appears after 30 seconds, check your
echo         taskbar for the installer window.
echo.
REM ALLUSERS=0 = per-user install, no admin needed
echo [%date% %time%] Running msiexec /passive >> "!SETUP_LOG!"
start /wait msiexec /i "!RD_INSTALLER!" /passive /norestart ALLUSERS=0
set "MSI_ERR=!ERRORLEVEL!"
echo [%date% %time%] msiexec returned: !MSI_ERR! >> "!SETUP_LOG!"

REM 1625 = ERROR_INSTALL_PACKAGE_REJECTED (Group Policy block)
REM 1624 = ERROR_INSTALL_TRANSFORM_REJECTED
REM 1530 = ERROR_INSTALL_POLICY
if "!MSI_ERR!"=="1625" goto :policy_blocked
if "!MSI_ERR!"=="1624" goto :policy_blocked
if "!MSI_ERR!"=="1530" goto :policy_blocked

if "!MSI_ERR!" neq "0" (
    echo [...]  Passive install returned error !MSI_ERR! -- retrying with full UI...
    echo         Follow the installer prompts in the new window.
    echo.
    start /wait msiexec /i "!RD_INSTALLER!" /norestart ALLUSERS=0
    set "MSI_ERR=!ERRORLEVEL!"
    if "!MSI_ERR!"=="1625" goto :policy_blocked
    if "!MSI_ERR!"=="1624" goto :policy_blocked
    if "!MSI_ERR!"=="1530" goto :policy_blocked
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
    echo        It may still be finishing.
    echo.
    choice /c CR /n /m "  [C]ontinue anyway  [R]etry: "
    if !ERRORLEVEL! equ 2 (
        echo [...]  Re-checking...
        if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" set "RD_VERIFY=1"
        if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" set "RD_VERIFY=1"
        if exist "%USERPROFILE%\.rd\bin\docker.exe" set "RD_VERIFY=1"
        if "!RD_VERIFY!"=="0" (
            echo [WARN] Still not found. Continuing anyway...
        ) else (
            echo [OK]  Found it.
        )
    )
)
goto :rancher_installed

:policy_blocked
echo [%date% %time%] POLICY BLOCKED - MSI error !MSI_ERR! >> "!SETUP_LOG!"
del "!RD_INSTALLER!" >nul 2>nul
echo.
echo ========================================
echo   Windows policy is blocking install
echo ========================================
echo.
echo   Your system administrator has set policies that
echo   prevent installing new software ^(MSI packages^).
echo.
echo   This is a corporate security restriction, not a
echo   problem with Rancher Desktop itself.
echo.
echo   To resolve this, contact IT and request one of:
echo.
echo     Option A: Have IT install Rancher Desktop for you
echo       - Tell them: "I need Rancher Desktop installed
echo         for Docker container development"
echo       - Package: SUSE Rancher Desktop ^(free/open-source^)
echo.
echo     Option B: Ask IT to whitelist Rancher Desktop
echo       - MSI package: Rancher.Desktop.Setup.*.msi
echo       - Publisher: SUSE LLC
echo       - This lets you install it yourself
echo.
echo     Option C: Temporary policy exemption
echo       - IT can grant a time-limited exception to
echo         the software restriction policy
echo.
echo   After IT resolves this, run this setup again.
echo.
pause
exit /b 1

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
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\configure-rancher-settings.ps1" "!RD_SETTINGS_DIR!\settings.json"
    echo [OK]  Pre-configured Rancher Desktop to use the correct engine.
)

echo.
>> "!STATE_FILE!" echo DOCKER=1
echo ========================================
echo   Rancher Desktop installed
echo ========================================
echo.
echo   A restart is recommended but you can try
echo   continuing -- Rancher may work without one.
echo.
choice /c CR /n /m "  [C]ontinue anyway  [R]estart now: "
if !ERRORLEVEL! equ 2 (
    call :schedule_resume
    echo.
    echo   Restarting in 10 seconds...
    echo   Setup will resume automatically after restart.
    shutdown /r /t 10 /c "Restarting to complete Rancher Desktop setup..."
    exit /b 0
)
echo [...]  Continuing without restart...

:docker_ok

REM Verify Docker is actually running
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :docker_running

REM Docker not running -- check VT-x as a diagnostic hint (not a blocker).
REM Some vPro/enterprise systems report VT-x as disabled even when working.
REM Single-line PowerShell to avoid cmd.exe misinterpreting parentheses in multi-line commands.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check-vtx.ps1" >nul 2>nul
if !ERRORLEVEL! equ 1 (
    echo.
    echo [NOTE] VT-x check could not confirm hardware virtualization.
    echo        If Docker fails to start, this might be why.
    echo        Ask IT to enable VT-x in BIOS if problems persist.
    echo.
)

REM Docker not running -- try to find and launch Rancher Desktop
set "RD_EXE="
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" (
    set "RD_EXE=%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe"
)
if not defined RD_EXE if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" (
    set "RD_EXE=%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe"
)

REM Check if Rancher was installed under a different user profile (e.g. SSMITH admin)
set "RD_OTHER_USER="
if defined RD_EXE goto :skip_other_user_rd_check
for /d %%U in (C:\Users\*) do (
    if exist "%%U\AppData\Local\Programs\Rancher Desktop\Rancher Desktop.exe" if /i not "%%U"=="%USERPROFILE%" set "RD_OTHER_USER=%%~nxU"
)
if not defined RD_OTHER_USER goto :skip_other_user_rd_check
echo.
echo ========================================
echo   Rancher Desktop installed under
echo   a different Windows account
echo ========================================
echo.
echo   Rancher Desktop was installed under !RD_OTHER_USER!
echo   but you're logged in as %USERNAME%.
echo.
echo   Rancher Desktop needs to be installed for YOUR account.
echo   It does NOT need admin rights to install.
echo.
echo   I'll open the download page -- install it again:
echo     1. Click the Windows download button
echo     2. Run the installer
echo     3. Choose "Install for me only" if asked
echo     4. Restart your computer
echo     5. Then double-click this file again
echo.
start "" "https://rancherdesktop.io/"
pause
exit /b 1
:skip_other_user_rd_check

if not defined RD_EXE goto :skip_rd_start
echo [...]  Starting Rancher Desktop...
start "" "!RD_EXE!"
echo [WAIT] Waiting for Docker to start (this can take 30-60 seconds)...
set "DOCKER_WAIT=0"
:docker_wait_loop
if !DOCKER_WAIT! GEQ 12 goto :docker_wait_done
timeout /t 5 /nobreak >nul
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :docker_running
set /a DOCKER_WAIT+=1
goto :docker_wait_loop
:docker_wait_done
:skip_rd_start

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
echo.
echo [WARN] Docker still not responding.
echo.
choice /c CR /n /m "  [C]ontinue to clone step anyway  [R]etry Docker check: "
if !ERRORLEVEL! equ 2 (
    docker info >nul 2>nul
    if !ERRORLEVEL! equ 0 goto :docker_running
    echo [ERROR] Docker still not running.
    echo         Try restarting your computer and running this file again.
    pause
    exit /b 1
)
echo [WARN] Proceeding without Docker -- install step may fail.
:docker_running
echo [OK]  Docker is running.
>> "!STATE_FILE!" echo DOCKER=1

REM ---------------------------------------------------------------------------
REM Step 4: Download or update Claude Code Docker
REM ---------------------------------------------------------------------------
echo [%date% %time%] Step 4: Clone/update >> "!SETUP_LOG!"
echo [...]  Getting Claude Code Docker...

if "!S_CLONE!"=="1" if exist "!INSTALL_DIR!\install.bat" goto :ccdw_update
if exist "!INSTALL_DIR!\install.bat" goto :ccdw_update

REM --- Check if we can reach the private repo (tests both network + auth) ---
echo [...]  Checking GitHub access...
git ls-remote --exit-code https://github.com/SleepNumberInc/CCDW.git HEAD >nul 2>nul
if !ERRORLEVEL! equ 0 goto :github_auth_ok

REM --- GitHub not reachable or not authenticated. Try to fix auth. ---
echo [%date% %time%] GitHub auth needed >> "!SETUP_LOG!"
echo [...]  GitHub authentication needed.
echo.

REM --- Strategy A: Use GitHub CLI (gh) if available ---
where gh >nul 2>nul
if !ERRORLEVEL! equ 0 goto :gh_auth

REM --- Strategy B: Try to install GitHub CLI via winget ---
where winget >nul 2>nul
if !ERRORLEVEL! neq 0 goto :no_gh_cli
echo [...]  Installing GitHub CLI...
winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements >nul 2>nul
REM Refresh PATH for gh
set "GH_PATHS=%ProgramFiles%\GitHub CLI;%LOCALAPPDATA%\Programs\GitHub CLI"
set "PATH=!GH_PATHS!;!PATH!"
where gh >nul 2>nul
if !ERRORLEVEL! neq 0 goto :no_gh_cli

:gh_auth
echo ========================================
echo   Sign in to GitHub
echo ========================================
echo.
echo   A browser window will open for you to sign in to GitHub.
echo   If it doesn't open automatically, look for a code to enter
echo   at https://github.com/login/device
echo.
echo   Use your Sleep Number GitHub account.
echo.
gh auth login --hostname github.com --git-protocol https --web
if !ERRORLEVEL! equ 0 (
    echo [OK]  GitHub authenticated.
    REM Configure git to use gh for credentials
    gh auth setup-git >nul 2>nul
    goto :github_auth_check
)
echo [WARN] GitHub CLI sign-in did not complete. Trying other methods...
echo.

:no_gh_cli
REM --- Strategy C: Let Git Credential Manager handle it (browser popup) ---
REM GCM ships with Git for Windows and triggers on clone. Try clone directly
REM WITHOUT suppressing stderr so GCM's browser auth prompt can appear.
echo ========================================
echo   Sign in to GitHub
echo ========================================
echo.
echo   When you see a browser window or pop-up from Git, sign in
echo   with your Sleep Number GitHub account.
echo.
echo   If you are asked for a username and password instead:
echo     - Username: your GitHub username
echo     - Password: a Personal Access Token (NOT your GitHub password)
echo       Get one at: https://github.com/settings/tokens
echo       Select scope: repo
echo.
echo [...]  Downloading (a sign-in window may appear)...
git clone https://github.com/SleepNumberInc/CCDW.git "!INSTALL_DIR!"
if !ERRORLEVEL! equ 0 goto :ccdw_ready
goto :clone_failed

:github_auth_check
REM Verify auth actually works now
git ls-remote --exit-code https://github.com/SleepNumberInc/CCDW.git HEAD >nul 2>nul
if !ERRORLEVEL! neq 0 goto :clone_failed

:github_auth_ok
echo [OK]  GitHub access confirmed.
echo [...]  Downloading (this may take a minute)...
git clone https://github.com/SleepNumberInc/CCDW.git "!INSTALL_DIR!"
if !ERRORLEVEL! equ 0 goto :ccdw_ready

:clone_failed
echo [%date% %time%] Clone failed >> "!SETUP_LOG!"
echo.
echo ========================================
echo   Could not download Claude Code
echo ========================================
echo.
echo   Three things to check:
echo.
echo   1. GitHub sign-in -- Did the browser sign-in complete?
echo      If not, try running this file again. The sign-in
echo      window sometimes appears behind other windows.
echo.
echo   2. GitHub organization access -- Your account must be
echo      a member of the Sleep Number GitHub organization.
echo      After signing in at https://github.com, check that
echo      you can visit:
echo        https://github.com/SleepNumberInc
echo      If you see "404" or "Page not found", ask your
echo      manager or the AI CoE team to add your account.
echo.
echo   3. VPN -- Make sure GlobalProtect is connected.
echo      Look for its icon in the system tray ^(bottom-right,
echo      near the clock^). It should say "Connected".
echo.
echo   After fixing, run this file again.
echo.
pause
exit /b 1
:ccdw_update
echo [...]  Updating to latest version...
pushd "!INSTALL_DIR!"
git pull
popd
:ccdw_ready
echo [OK]  Ready.
>> "!STATE_FILE!" echo CLONE=1

REM ---------------------------------------------------------------------------
REM Step 5: Run the installer (clean up state file -- setup is complete)
REM ---------------------------------------------------------------------------
echo [%date% %time%] Step 5: Running installer >> "!SETUP_LOG!"
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\schedule-resume.ps1" "%SELF_PATH%"
if !ERRORLEVEL! equ 0 (
    echo [OK]  Setup will resume automatically after restart.
) else (
    echo [INFO] Could not set up auto-resume. After restarting,
    echo        double-click this file again to continue.
)
goto :eof
