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
powershell -NoProfile -Command ^
    "$p = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue; " ^
    "if ($p.VirtualizationFirmwareEnabled -eq $true) { exit 0 } " ^
    "elseif ($p.VirtualizationFirmwareEnabled -eq $false) { exit 1 } " ^
    "else { exit 0 }" >nul 2>nul
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
echo     - Search your email for "Local Admin" or "SSMITH"
echo     - The username is usually SSMITH ^(all caps^)
echo     - The password was in that email
echo.
echo   If you can't find the email, contact the IT Service Desk.
echo.

wsl --install --no-launch
if !ERRORLEVEL! neq 0 (
    REM wsl --install may fail but still succeed (Windows quirk).
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
echo   WSL2 installed -- restart may help
echo ========================================
echo.
echo   WSL2 was installed but isn't responding yet.
echo   A restart usually fixes this, but it may also
echo   work if you continue ^(especially if Docker
echo   manages its own WSL setup^).
echo.
>> "!STATE_FILE!" echo WSL=1
choice /c CR /n /m "  [C]ontinue anyway  [R]estart now: "
if !ERRORLEVEL! equ 2 (
    call :schedule_resume
    echo.
    echo   Restarting in 10 seconds...
    echo   Setup will resume automatically after restart.
    shutdown /r /t 10 /c "Restarting to complete WSL2 setup..."
    exit /b 0
)
echo [WARN] Continuing without confirmed WSL2. Docker may handle it.

:wsl_ok

REM ---------------------------------------------------------------------------
REM Step 3: Check for Docker (Rancher Desktop)
REM ---------------------------------------------------------------------------
if "!S_DOCKER!"=="1" (
    echo [OK]  Rancher Desktop ^(already installed^)
    goto :docker_ok
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
if !ERRORLEVEL! equ 0 (
    for /f "delims=" %%P in ('where docker 2^>nul') do (
        echo "%%P" | find /i "Docker Desktop" >nul 2>nul
        if !ERRORLEVEL! neq 0 (
            echo "%%P" | find /i "\Docker\" >nul 2>nul
            if !ERRORLEVEL! neq 0 (
                set "DOCKER_FOUND=1"
            )
        )
    )
)
:docker_found

if "!DOCKER_FOUND!"=="1" (
    echo [OK]  Docker is available ^(Rancher Desktop^).
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
set "WINGET_ERR=!ERRORLEVEL!"
if "!WINGET_ERR!"=="0" goto :rancher_installed

winget install --id SUSE.RancherDesktop -e --accept-package-agreements --accept-source-agreements >nul 2>nul
set "WINGET_ERR=!ERRORLEVEL!"
if "!WINGET_ERR!"=="0" goto :rancher_installed

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
set "MSI_ERR=!ERRORLEVEL!"

REM 1625 = ERROR_INSTALL_PACKAGE_REJECTED (Group Policy block)
REM 1624 = ERROR_INSTALL_TRANSFORM_REJECTED
REM 1530 = ERROR_INSTALL_POLICY
if "!MSI_ERR!"=="1625" goto :policy_blocked
if "!MSI_ERR!"=="1624" goto :policy_blocked
if "!MSI_ERR!"=="1530" goto :policy_blocked

if "!MSI_ERR!" neq "0" (
    echo [...]  Passive install did not work -- trying with installer UI...
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
    powershell -NoProfile -Command ^
        "$s = @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } }; " ^
        "$s | ConvertTo-Json -Depth 5 | Set-Content '%RD_SETTINGS_DIR%\settings.json' -Encoding UTF8"
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
powershell -NoProfile -Command ^
    "$p = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue; " ^
    "if ($p.VirtualizationFirmwareEnabled -eq $true) { exit 0 } " ^
    "elseif ($p.VirtualizationFirmwareEnabled -eq $false) { exit 1 } " ^
    "else { exit 0 }" >nul 2>nul
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
if not defined RD_EXE (
    for /d %%U in (C:\Users\*) do (
        if exist "%%U\AppData\Local\Programs\Rancher Desktop\Rancher Desktop.exe" (
            if /i not "%%U"=="%USERPROFILE%" (
                echo.
                echo ========================================
                echo   Rancher Desktop installed under
                echo   a different Windows account
                echo ========================================
                echo.
                echo   Rancher Desktop was installed under %%~nxU
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
            )
        )
    )
)

if defined RD_EXE (
    echo [...]  Starting Rancher Desktop...
    start "" "!RD_EXE!"
    echo [WAIT] Waiting for Docker to start ^(this can take 30-60 seconds^)...
    set "DOCKER_WAIT=0"
    :docker_wait_loop
    if !DOCKER_WAIT! GEQ 12 goto :docker_wait_done
    timeout /t 5 /nobreak >nul
    docker info >nul 2>nul
    if !ERRORLEVEL! equ 0 goto :docker_running
    set /a DOCKER_WAIT+=1
    goto :docker_wait_loop
    :docker_wait_done
)

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
