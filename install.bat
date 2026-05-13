@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code Docker - Windows One-Click Installer
REM Usage:
REM   install.bat --ai=foundry     Azure AI Foundry (default)
REM   install.bat --ai=bedrock     AWS Bedrock
REM   install.bat --ai=anthropic   Anthropic API key
REM   install.bat                  Interactive prompt or auto-detect
REM =============================================================================

title Claude Code - Setup

echo.
echo ========================================
echo   Claude Code - Setup
echo ========================================
echo.
echo   This will set up your AI development environment.
echo   It takes about 2-3 minutes on a good connection.
echo.

REM ---------------------------------------------------------------------------
REM Parse --ai= argument
REM ---------------------------------------------------------------------------
set "AI_PROVIDER="
for %%A in (%*) do (
    set "ARG=%%A"
    if "!ARG:~0,5!"=="--ai=" set "AI_PROVIDER=!ARG:~5!"
)

REM Normalize provider name
if /i "!AI_PROVIDER!"=="foundry"         set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="azure-foundry"   set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="azure"           set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="bedrock"         set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="aws-bedrock"     set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="aws"             set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="anthropic"       set "AI_PROVIDER=anthropic"
if /i "!AI_PROVIDER!"=="api-key"         set "AI_PROVIDER=anthropic"
if /i "!AI_PROVIDER!"=="apikey"          set "AI_PROVIDER=anthropic"

if defined AI_PROVIDER (
    if /i "!AI_PROVIDER!" neq "foundry" if /i "!AI_PROVIDER!" neq "bedrock" if /i "!AI_PROVIDER!" neq "anthropic" (
        echo [ERROR] Unknown provider: !AI_PROVIDER!
        echo.
        echo   Valid options:
        echo     --ai=foundry     Azure AI Foundry
        echo     --ai=bedrock     AWS Bedrock
        echo     --ai=anthropic   Anthropic API key
        echo.
        pause
        exit /b 1
    )
)

REM ---------------------------------------------------------------------------
REM Guard: Detect elevated prompt and warn the user
REM ---------------------------------------------------------------------------
net session >nul 2>&1
if !ERRORLEVEL! neq 0 goto :not_admin

echo [WARNING] This window is running as Administrator.
echo.
echo   When you run as admin, your files may end up in
echo   the wrong user folder. This causes problems.
echo.
echo   Instead:
echo     1. Close this window
echo     2. DOUBLE-CLICK install.bat normally
echo     3. Do NOT right-click "Run as administrator"
echo.
choice /C YN /M "Continue anyway? Y=Yes, N=Close"
if !ERRORLEVEL! equ 2 exit /b 0
echo.
echo   OK, continuing. Some paths may point to the admin account's folders.
echo.

:not_admin

REM ---------------------------------------------------------------------------
REM Preflight checks
REM ---------------------------------------------------------------------------
echo [...]  Checking your setup...

REM --- Check: WSL2 is installed and working ---
where wsl >nul 2>nul
if !ERRORLEVEL! neq 0 goto :wsl_not_installed

REM wsl.exe exists -- check if the kernel is actually loaded
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 goto :wsl_running

REM wsl exists but kernel not loaded -- try a lightweight test
wsl -l >nul 2>nul
if !ERRORLEVEL! equ 0 goto :wsl_running

REM WSL2 was installed but machine hasn't been rebooted yet
echo [ERROR] Your computer needs to be restarted.
echo.
echo   WSL2 was recently installed (probably with Rancher Desktop)
echo   but it can't start until you restart your computer.
echo.
echo   What to do:
echo     1. Close this window
echo     2. Restart your computer
echo     3. After it restarts, wait about 60 seconds for
echo        Rancher Desktop to finish starting up
echo     4. Double-click install.bat again
echo.
pause
exit /b 1

:wsl_not_installed
echo [ERROR] WSL is not installed.
echo.
echo   Rancher Desktop needs WSL2 to run Docker containers.
echo.
echo   How to install WSL2:
echo     1. Open PowerShell as Administrator
echo     2. Run: wsl --install
echo     3. Restart your computer when prompted
echo     4. Double-click install.bat again
echo.
pause
exit /b 1

:wsl_running

REM --- Check: WSL2 is the default version (not WSL1) ---
wsl --status 2>nul | findstr /i /c:"Default Version: 1" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [WARN] WSL is set to version 1. Switching to WSL2...
    wsl --set-default-version 2 >nul 2>nul
)
echo [OK] WSL2 is ready.

REM --- Check: Rancher Desktop or Docker Desktop is running (auto-start if not) ---
tasklist /fi "imagename eq Rancher Desktop.exe" 2>nul | findstr /i "Rancher" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK] Rancher Desktop is running.
    goto :desktop_running
)
tasklist /fi "imagename eq rdctl.exe" 2>nul | findstr /i "rdctl" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK] Rancher Desktop is running.
    goto :desktop_running
)
tasklist /fi "imagename eq Docker Desktop.exe" 2>nul | findstr /i "Docker" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK] Docker Desktop is running.
    goto :desktop_running
)

REM Nothing running -- try to auto-start Rancher Desktop
echo [...]  Rancher Desktop is not running. Starting it...
set "RD_EXE="
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe" set "RD_EXE=%LOCALAPPDATA%\Programs\Rancher Desktop\Rancher Desktop.exe"
if not defined RD_EXE if exist "%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe" set "RD_EXE=%ProgramFiles%\Rancher Desktop\Rancher Desktop.exe"
if not defined RD_EXE (
    for /d %%D in (C:\Users\*) do (
        if not defined RD_EXE if exist "%%D\AppData\Local\Programs\Rancher Desktop\Rancher Desktop.exe" set "RD_EXE=%%D\AppData\Local\Programs\Rancher Desktop\Rancher Desktop.exe"
    )
)

if defined RD_EXE (
    REM Detect first-run: no rancher-desktop distro registered in WSL yet
    set "RD_FIRST_RUN=0"
    wsl -l 2>nul | findstr /i "rancher-desktop" >nul 2>nul
    if !ERRORLEVEL! neq 0 set "RD_FIRST_RUN=1"

    REM Pre-configure Rancher Desktop to use dockerd before first launch.
    REM This eliminates the engine selection dialog that confuses new users.
    if "!RD_FIRST_RUN!"=="1" (
        set "RD_SETTINGS_DIR=%APPDATA%\rancher-desktop"
        if not exist "!RD_SETTINGS_DIR!" mkdir "!RD_SETTINGS_DIR!"
        if not exist "!RD_SETTINGS_DIR!\settings.json" (
            powershell -NoProfile -Command ^
                "$s = @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } }; " ^
                "$s | ConvertTo-Json -Depth 5 | Set-Content '!RD_SETTINGS_DIR!\settings.json' -Encoding UTF8"
        )
    )

    start "" "!RD_EXE!"
    if "!RD_FIRST_RUN!"=="1" (
        echo [OK] Rancher Desktop is starting for the first time.
        echo      First-time setup takes 3-5 minutes. Do NOT close this window.
        echo      The installer will wait and continue automatically.
    ) else (
        echo [OK] Rancher Desktop is starting up.
        echo      It needs about 60 seconds to initialize -- the installer
        echo      will wait for it automatically.
    )
) else (
    echo [WARN] Could not find Rancher Desktop to auto-start.
    echo        Please open Rancher Desktop from your Start menu.
)

:desktop_running

REM --- Check: Disk space (need at least 5 GB for image build) ---
for /f "tokens=3" %%S in ('dir /-C "%~dp0." 2^>nul ^| findstr /c:"bytes free"') do set "FREE_BYTES=%%S"
if defined FREE_BYTES (
    powershell -NoProfile -Command "if ([long]'!FREE_BYTES!' -lt 5368709120) { Write-Host '[WARN] Less than 5 GB free disk space. Docker build may fail.' -ForegroundColor Yellow } else { Write-Host '[OK] Disk space is sufficient.' -ForegroundColor Green }"
) else (
    echo [OK] Disk space check skipped.
)

REM --- Check: Required ports are available ---
set "PORT_CONFLICT=0"
REM Skip port check if our container is already running (reinstall scenario)
docker inspect claude-code >nul 2>nul
if !ERRORLEVEL! equ 0 goto :ports_ok

powershell -NoProfile -Command ^
    "$conflicts = @(); " ^
    "foreach ($p in @(3000,7681,7682,8080,9200)) { " ^
    "  $r = netstat -ano 2>$null | Select-String \":$p\s.*LISTENING\"; " ^
    "  if ($r) { $conflicts += $p } " ^
    "} " ^
    "if ($conflicts.Count -gt 0) { " ^
    "  foreach ($p in $conflicts) { Write-Host \"[WARN] Port $p is already in use.\" -ForegroundColor Yellow } " ^
    "  exit 1 " ^
    "} else { exit 0 }"
if !ERRORLEVEL! neq 0 (
    set "PORT_CONFLICT=1"
    echo.
    echo   Another program is using a port that Claude Code needs:
    echo.
    powershell -NoProfile -Command ^
        "foreach ($p in @(3000,7681,7682,8080,9200)) { " ^
        "  try { " ^
        "    $conn = Get-NetTCPConnection -LocalPort $p -State Listen -EA Stop; " ^
        "    $proc = Get-Process -Id $conn[0].OwningProcess -EA Stop; " ^
        "    Write-Host ('   Port ' + $p + ' is used by: ' + $proc.ProcessName) -ForegroundColor Yellow " ^
        "  } catch { } " ^
        "}"
    echo.
    echo   Close those programs, then run this installer again.
    echo.
    echo   Not sure what they are? Restarting your computer usually
    echo   clears stuck ports. Then double-click install.bat again.
    echo.
    pause
    exit /b 1
)
:ports_ok
if "!PORT_CONFLICT!"=="0" echo [OK] Required ports are available.

echo.

REM ---------------------------------------------------------------------------
REM Step 1: Find the Docker CLI
REM ---------------------------------------------------------------------------
set "DOCKER_CMD="
set "DOCKER_SOURCE="
set "FOUND_OTHER_USER="
set "FOUND_OTHER_PATH="

REM --- 1a. Already on PATH ---
where docker >nul 2>nul
if !ERRORLEVEL! equ 0 (
    set "DOCKER_CMD=docker"
    set "DOCKER_SOURCE=system PATH"
    goto :found_cli
)

REM --- 1b. docker.exe placed next to this script ---
if exist "%~dp0docker.exe" (
    set "DOCKER_CMD=%~dp0docker.exe"
    set "DOCKER_SOURCE=local copy"
    set "PATH=%~dp0;!PATH!"
    goto :found_cli
)

REM --- 1c. Current user's Rancher Desktop ---
if exist "%USERPROFILE%\.rd\bin\docker.exe" (
    set "DOCKER_CMD=%USERPROFILE%\.rd\bin\docker.exe"
    set "DOCKER_SOURCE=Rancher Desktop"
    set "PATH=%USERPROFILE%\.rd\bin;!PATH!"
    goto :found_cli
)

REM --- 1d. Docker Desktop in Program Files ---
if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" (
    set "DOCKER_CMD=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"
    set "DOCKER_SOURCE=Docker Desktop"
    set "PATH=%ProgramFiles%\Docker\Docker\resources\bin;!PATH!"
    goto :found_cli
)

REM --- 1e. Rancher Desktop MSI install in Program Files ---
if exist "%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin\docker.exe" (
    set "DOCKER_CMD=%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin\docker.exe"
    set "DOCKER_SOURCE=Rancher Desktop - Program Files"
    set "PATH=%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin;!PATH!"
    goto :found_cli
)

REM --- 1f. Rancher Desktop in current user's Local Programs ---
if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" (
    set "DOCKER_CMD=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe"
    set "DOCKER_SOURCE=Rancher Desktop - Local Programs"
    set "PATH=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin;!PATH!"
    goto :found_cli
)

REM --- 1g. Search Windows registry for Rancher Desktop install path ---
echo [...]  Searching for Docker...
for /f "delims=" %%P in ('powershell -NoProfile -Command "foreach ($loc in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) { foreach ($x in (Get-ItemProperty $loc -EA 0)) { if ($x.DisplayName -like '*Rancher Desktop*' -and $x.InstallLocation) { $d = Join-Path $x.InstallLocation 'resources\resources\win32\bin\docker.exe'; if (Test-Path $d) { $d; exit } } } }" 2^>nul') do (
    set "DOCKER_CMD=%%P"
    set "DOCKER_SOURCE=Rancher Desktop - registry"
    for %%F in ("%%~dpP.") do set "PATH=%%~fF;!PATH!"
    goto :found_cli
)

REM --- 1h. Scan other user profiles for Rancher Desktop ---
for /d %%D in (C:\Users\*) do (
    if exist "%%D\.rd\bin\docker.exe" (
        if /i "%%D" neq "%USERPROFILE%" (
            set "FOUND_OTHER_USER=%%~nxD"
            set "FOUND_OTHER_PATH=%%D\.rd\bin"
        )
    )
)

if defined FOUND_OTHER_USER goto :found_other_user

REM --- 1i. DOCKER_PATH override from .env ---
:check_env_docker_path
if not exist "%~dp0.env" goto :check_pipe_hint
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do if /i "%%A"=="DOCKER_PATH" call :try_docker_path "%%B"
goto :check_pipe_hint
:try_docker_path
set "_DP=%~1"
if exist "!_DP!\docker.exe" (
    set "DOCKER_CMD=!_DP!\docker.exe"
    set "DOCKER_SOURCE=.env DOCKER_PATH"
    set "PATH=!_DP!;!PATH!"
    goto :found_cli
)
exit /b

REM --- 1j. Docker pipe exists but no docker.exe ---
:check_pipe_hint
set "PIPE_HINT=0"
powershell -NoProfile -Command "if (Test-Path \\.\pipe\docker_engine) { exit 0 } else { exit 1 }" >nul 2>nul
if !ERRORLEVEL! equ 0 set "PIPE_HINT=1"
if "!PIPE_HINT!"=="0" (
    powershell -NoProfile -Command "if (Test-Path \\.\pipe\dockerDesktopLinuxEngine) { exit 0 } else { exit 1 }" >nul 2>nul
    if !ERRORLEVEL! equ 0 set "PIPE_HINT=1"
)

if "!PIPE_HINT!"=="0" goto :no_docker_found

echo [INFO] Docker is RUNNING on this machine, but the installer
echo        cannot find docker.exe due to file permissions.
echo.
echo   This happens when Rancher Desktop was installed under a
echo   different Windows account. The docker.exe file is locked
echo   inside that account's profile folder.
echo.
echo   EASIEST FIX -- ask your admin to do this once:
echo     1. Log in as the admin account
echo     2. Open File Explorer and go to:
echo          C:\Users\ADMIN-NAME\.rd\bin
echo     3. Copy docker.exe to this folder:
echo          %~dp0
echo     4. Log back in as your account
echo     5. Double-click install.bat again
echo.
echo   PERMANENT FIX -- install Rancher Desktop under your own account:
echo     1. Download from https://rancherdesktop.io/
echo     2. Run the installer -- no admin password needed
echo     3. Open Rancher Desktop, set engine to dockerd
echo     4. Double-click install.bat again
echo.
echo   MANUAL FIX -- if you know the path to docker.exe:
echo     1. Open .env in this folder with Notepad
echo     2. Add this line: DOCKER_PATH=C:\path\to\folder\with\docker.exe
echo     3. Double-click install.bat again
echo.
pause
exit /b 1

:no_docker_found
echo [ERROR] Could not find Docker on this computer.
echo.
echo   Checked these locations:
echo     - System PATH
echo     - %USERPROFILE%\.rd\bin
echo     - %ProgramFiles%\Docker\Docker\resources\bin
echo     - %ProgramFiles%\Rancher Desktop\resources\resources\win32\bin
echo     - %LOCALAPPDATA%\Programs\Rancher Desktop\...
echo     - Windows registry
echo     - Other user profiles in C:\Users
echo     - DOCKER_PATH in .env
echo.
echo   Install Rancher Desktop -- it's free, no admin needed:
echo     1. Download from https://rancherdesktop.io/
echo     2. Run the installer
echo     3. Open Rancher Desktop from the Start menu
echo     4. Go to Preferences, Container Engine, select dockerd
echo     5. Wait for it to finish starting
echo     6. Double-click install.bat again
echo.
echo   IMPORTANT: Install it while logged in as YOUR Windows account,
echo   not a shared admin account. This avoids permission problems.
echo.
pause
exit /b 1

:found_other_user
echo [INFO] Rancher Desktop is installed under the !FOUND_OTHER_USER! account.
echo        That's OK -- you have two options:
echo.
echo   A. Install Rancher Desktop under YOUR account
echo      This is the recommended one-time fix:
echo        1. Download from https://rancherdesktop.io/
echo        2. Run the installer -- no admin password needed
echo        3. Open Rancher Desktop from the Start menu
echo        4. Preferences, Container Engine, select dockerd
echo        5. Wait until it finishes, then run install.bat again
echo.
echo   B. Use the copy from the !FOUND_OTHER_USER! account
echo      This works as long as Rancher Desktop was started from
echo      that account at least once since the last reboot.
echo.
choice /C AB /M "Pick A or B"
if !ERRORLEVEL! neq 1 goto :use_other_user_docker

echo.
echo   Opening the download page...
start https://rancherdesktop.io/
echo.
echo   After installing and starting Rancher Desktop under your
echo   own account, double-click install.bat again.
echo.
pause
exit /b 0

:use_other_user_docker
echo.
set "DOCKER_CMD=!FOUND_OTHER_PATH!\docker.exe"
set "DOCKER_SOURCE=!FOUND_OTHER_USER! account"
set "PATH=!FOUND_OTHER_PATH!;!PATH!"
goto :found_cli

:found_cli
echo [OK] Found Docker via !DOCKER_SOURCE!.

REM ---------------------------------------------------------------------------
REM Step 2: Wait for the Docker engine to be ready
REM ---------------------------------------------------------------------------
set "PIPE_OK=0"
powershell -NoProfile -Command "if (Test-Path \\.\pipe\docker_engine) { exit 0 } else { exit 1 }" >nul 2>nul
if !ERRORLEVEL! equ 0 set "PIPE_OK=1"

if "!PIPE_OK!"=="0" (
    powershell -NoProfile -Command "if (Test-Path \\.\pipe\dockerDesktopLinuxEngine) { exit 0 } else { exit 1 }" >nul 2>nul
    if !ERRORLEVEL! equ 0 set "PIPE_OK=1"
)

docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :engine_ok

echo [...]  Waiting for Docker engine to be ready...
echo        (this can take a minute or two if it just started)
set DOCKER_WAIT=0

:docker_retry
if !DOCKER_WAIT! geq 24 goto :engine_fail
ping -n 6 127.0.0.1 >nul
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :engine_ok
set /a DOCKER_WAIT+=1
if !DOCKER_WAIT! leq 6 (
    echo          Starting up... !DOCKER_WAIT! of 24
) else if !DOCKER_WAIT! leq 12 (
    echo          Almost ready... !DOCKER_WAIT! of 24
) else (
    echo          Still working... !DOCKER_WAIT! of 24
)
goto :docker_retry

:engine_fail
echo.
echo [ERROR] The Docker engine did not start after 2 minutes.
echo.

if not defined FOUND_OTHER_USER goto :engine_fail_generic

echo   The Docker engine needs Rancher Desktop to be running.
echo   Since it was installed under the !FOUND_OTHER_USER! account,
echo   the engine may not auto-start for your account.
echo.
echo   BEST FIX -- permanent, no more admin headaches:
echo     1. Download Rancher Desktop: https://rancherdesktop.io/
echo     2. Install it under YOUR Windows account -- no admin needed
echo     3. Open it, set engine to dockerd
echo     4. Double-click install.bat again
echo.
echo   QUICK FIX -- for right now:
echo     1. Open Rancher Desktop from the !FOUND_OTHER_USER! account's Start menu
echo     2. Wait for it to fully start
echo     3. Double-click install.bat again
echo.
pause
exit /b 1

:engine_fail_generic
echo   How to fix:
echo.
echo     Rancher Desktop:
echo       1. Open Rancher Desktop from the Start menu
echo       2. Wait for it to finish starting
echo       3. IMPORTANT: The engine must be set to dockerd --
echo          Preferences, Container Engine, dockerd
echo       4. Double-click install.bat again
echo.
echo     Docker Desktop:
echo       1. Open Docker Desktop from the Start menu
echo       2. Wait for it to say "running" in the system tray
echo       3. Double-click install.bat again
echo.
pause
exit /b 1

:engine_ok
echo [OK] Docker engine is running.

REM --- Check: Docker is using dockerd (not containerd/nerdctl) ---
docker version --format "{{.Server.Components}}" 2>nul | findstr /i "Engine" >nul 2>nul
if !ERRORLEVEL! neq 0 (
    REM Could be containerd/nerdctl -- check for docker compose support
    docker compose version >nul 2>nul
    if !ERRORLEVEL! neq 0 (
        echo.
        echo [ERROR] Rancher Desktop is using the wrong engine setting.
        echo.
        echo   How to fix:
        echo     1. Look for the Rancher Desktop icon in your system tray
        echo        ^(bottom-right corner, near the clock^)
        echo     2. Right-click it and choose "Preferences"
        echo     3. Click "Container Engine" on the left side
        echo     4. Select "dockerd ^(moby^)" -- NOT containerd
        echo     5. Wait about 60 seconds for it to restart
        echo     6. Double-click install.bat again
        echo.
        pause
        exit /b 1
    )
)

REM ---------------------------------------------------------------------------
REM Create required folders
REM ---------------------------------------------------------------------------
set "PROJECTS_DIR="

if not exist "%~dp0.env" goto :default_projects_dir
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do if /i "%%A"=="PROJECTS_PATH" set "PROJECTS_DIR=%%B"

:default_projects_dir
if not defined PROJECTS_DIR set "PROJECTS_DIR=%USERPROFILE%\Documents"
set "PROJECTS_DIR=!PROJECTS_DIR:"=!"
set "AZURE_DIR=%USERPROFILE%\.azure"
set "AWS_DIR=%USERPROFILE%\.aws"

if not exist "!PROJECTS_DIR!" mkdir "!PROJECTS_DIR!" 2>nul
if not exist "!PROJECTS_DIR!" goto :projects_dir_fail
echo [OK] Projects folder: !PROJECTS_DIR!
goto :projects_dir_ok

:projects_dir_fail
echo [ERROR] Could not create !PROJECTS_DIR!
echo.
echo   This can happen if OneDrive is redirecting your folders.
echo   Add this to .env and pick a folder you have access to:
echo     PROJECTS_PATH=C:\Users\%USERNAME%\Documents\Github
echo.
pause
exit /b 1

:projects_dir_ok
if not exist "!AZURE_DIR!" mkdir "!AZURE_DIR!" 2>nul
if not exist "!AWS_DIR!" mkdir "!AWS_DIR!" 2>nul

REM ---------------------------------------------------------------------------
REM Create .env from template if it doesn't exist
REM ---------------------------------------------------------------------------
set "ENV_FILE=%~dp0.env"
if exist "!ENV_FILE!" goto :env_exists
if exist "%~dp0.env.example" (
    echo [...]  Creating .env from template...
    copy "%~dp0.env.example" "!ENV_FILE!" >nul
    echo [OK] Created .env
)
:env_exists

REM ---------------------------------------------------------------------------
REM REGISTRY_MIRROR: only add if explicitly uncommented in .env.example
REM (commented out by default — users opt in by editing .env)
REM ---------------------------------------------------------------------------
goto :after_registry_mirror_check
:after_registry_mirror_check

REM ---------------------------------------------------------------------------
REM Ensure PROJECTS_PATH is set in .env (docker-compose needs explicit Windows path)
REM ---------------------------------------------------------------------------
if exist "!ENV_FILE!" (
    findstr /i /b "PROJECTS_PATH=" "!ENV_FILE!" >nul 2>nul
    if !ERRORLEVEL! neq 0 (
        echo.>> "!ENV_FILE!"
        echo PROJECTS_PATH=!PROJECTS_DIR!>> "!ENV_FILE!"
        echo [OK] Set projects folder in .env: !PROJECTS_DIR!
    )
)

REM ---------------------------------------------------------------------------
REM AI Provider Setup
REM ---------------------------------------------------------------------------
set "HAS_PROVIDER=0"
if exist "!ENV_FILE!" (
    findstr /i /b "ANTHROPIC_API_KEY=" "!ENV_FILE!" >nul 2>nul && set "HAS_PROVIDER=1"
    findstr /i /b "ANTHROPIC_FOUNDRY_BASE_URL=" "!ENV_FILE!" >nul 2>nul && set "HAS_PROVIDER=1"
    findstr /i /b "CLAUDE_CODE_USE_BEDROCK=1" "!ENV_FILE!" >nul 2>nul && set "HAS_PROVIDER=1"
)

if "!HAS_PROVIDER!"=="1" if not defined AI_PROVIDER (
    echo [OK] AI provider already configured in .env
    REM Check if Foundry provider is missing API key (causes auth failure inside container)
    set "NEEDS_FOUNDRY_KEY=0"
    findstr /i /b "ANTHROPIC_FOUNDRY_BASE_URL=" "!ENV_FILE!" >nul 2>nul && set "NEEDS_FOUNDRY_KEY=1"
    findstr /i /b "ANTHROPIC_FOUNDRY_API_KEY=" "!ENV_FILE!" >nul 2>nul && set "NEEDS_FOUNDRY_KEY=0"
    if "!NEEDS_FOUNDRY_KEY!"=="1" call :prompt_foundry_key
    goto :skip_setup
)

REM --- If no --ai= argument, prompt interactively ---
if not defined AI_PROVIDER (
    echo.
    echo ========================================
    echo   Choose your AI provider:
    echo ========================================
    echo.
    echo     1. Azure AI Foundry  ^(Claude via Azure^)
    echo     2. AWS Bedrock       ^(Claude via AWS^)
    echo     3. Anthropic API     ^(direct API key^)
    echo     4. Skip for now      ^(edit .env manually^)
    echo.
    choice /C 1234 /M "Enter choice"
    if !ERRORLEVEL! equ 4 goto :skip_setup
    if !ERRORLEVEL! equ 3 set "AI_PROVIDER=anthropic"
    if !ERRORLEVEL! equ 2 set "AI_PROVIDER=bedrock"
    if !ERRORLEVEL! equ 1 set "AI_PROVIDER=foundry"
)

if not defined AI_PROVIDER goto :skip_setup

set "CONFIG_FILE=%~dp0config\!AI_PROVIDER!.json"
if not exist "!CONFIG_FILE!" (
    echo [ERROR] Config file not found: !CONFIG_FILE!
    pause
    exit /b 1
)

REM --- Run provider-specific preflight checks ---
:run_preflight
echo.
echo ========================================
echo   Checking Your Setup
echo ========================================
echo.
powershell -NoProfile -Command ^
    "$cfg = Get-Content '!CONFIG_FILE!' | ConvertFrom-Json; " ^
    "$prereqs = $cfg.prereqs.host; " ^
    "if (-not $prereqs) { exit 0 } " ^
    "$failCount = 0; " ^
    "foreach ($p in $prereqs) { " ^
    "  $label = $p.label; " ^
    "  $check = $p.check; " ^
    "  $required = [bool]$p.required; " ^
    "  $failMsg = $p.fail_message; " ^
    "  if ($check -eq 'manual') { " ^
    "    Write-Host ('  ? ' + $label + ' (verify manually)') -ForegroundColor Yellow; " ^
    "    if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow } " ^
    "    continue " ^
    "  } " ^
    "  if ($check -eq 'info') { " ^
    "    Write-Host ('  i ' + $label) -ForegroundColor Cyan; " ^
    "    if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor DarkGray } " ^
    "    continue " ^
    "  } " ^
    "  try { " ^
    "    $result = cmd /c $check 2>&1; " ^
    "    $expect = $p.expect; " ^
    "    if ($LASTEXITCODE -eq 0 -and (-not $expect -or ($result -join ' ') -match $expect)) { " ^
    "      Write-Host ('  OK ' + $label) -ForegroundColor Green " ^
    "    } else { " ^
    "      Write-Host ('  X  ' + $label) -ForegroundColor Red; " ^
    "      if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow } " ^
    "      if ($required) { $failCount++ } " ^
    "    } " ^
    "  } catch { " ^
    "    Write-Host ('  X  ' + $label) -ForegroundColor Red; " ^
    "    if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow } " ^
    "    if ($required) { $failCount++ } " ^
    "  } " ^
    "} " ^
    "if ($failCount -gt 0) { exit 1 } else { exit 0 }"
if !ERRORLEVEL! neq 0 (
    echo.
    echo ========================================
    echo   Some checks need attention
    echo ========================================
    echo.
    echo   Most common fix: connect your VPN ^(GlobalProtect^).
    echo   Look for it in the system tray ^(bottom-right, near clock^).
    echo.
    echo   Press any key after fixing, and we'll check again...
    echo.
    pause
    goto :run_preflight
)
echo.
echo [OK] Preflight checks passed.

REM ---------------------------------------------------------------------------
REM Prompt for missing values per provider (matches install.command behavior)
REM ---------------------------------------------------------------------------
if "!AI_PROVIDER!"=="foundry" (
    powershell -NoProfile -Command ^
        "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
        "if (-not $cfg.endpoint) { " ^
        "  $ep = Read-Host '  Foundry endpoint URL'; " ^
        "  if ($ep) { $cfg.endpoint = $ep; $cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'; Write-Host '  [OK] Endpoint saved' } " ^
        "}"
    call :foundry_key_setup
)

if "!AI_PROVIDER!"=="bedrock" (
    powershell -NoProfile -Command ^
        "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
        "if (-not $cfg.sso_start_url) { " ^
        "  $sso = Read-Host '  AWS SSO Start URL (https://d-xxx.awsapps.com/start)'; " ^
        "  $acct = Read-Host '  AWS Account ID'; " ^
        "  $role = Read-Host '  SSO Role Name'; " ^
        "  $rgn = Read-Host '  Bedrock Region [us-east-1]'; " ^
        "  if (-not $rgn) { $rgn = 'us-east-1' } " ^
        "  $cfg.sso_start_url = $sso; $cfg.account_id = $acct; $cfg.role_name = $role; " ^
        "  $cfg.region = $rgn; $cfg.sso_region = $rgn; " ^
        "  $cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'; " ^
        "  Write-Host '  [OK] Bedrock SSO config saved' " ^
        "} " ^
        "Write-Host '  Note: AWS SSO sign-in will happen after the container starts.' -ForegroundColor Cyan"
)

if "!AI_PROVIDER!"=="anthropic" (
    powershell -NoProfile -Command ^
        "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
        "if (-not $cfg.api_key) { " ^
        "  $key = Read-Host '  Anthropic API key (sk-ant-...)' -AsSecureString; " ^
        "  $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($key)); " ^
        "  if ($plain) { $cfg.api_key = $plain; $cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'; Write-Host '  [OK] API key saved' } " ^
        "}"
)

REM ---------------------------------------------------------------------------
REM Configure provider from config JSON using PowerShell
REM ---------------------------------------------------------------------------
echo.
echo [...]  Configuring AI provider from config\!AI_PROVIDER!.json...

REM Use PowerShell to read config JSON, resolve templates, and write .env
powershell -NoProfile -Command ^
    "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
    "$envPath = '!ENV_FILE!'; " ^
    "" ^
    "function Resolve-Template($val, $cfg) { " ^
    "  if (-not $val) { return '' } " ^
    "  [regex]::Replace([string]$val, '\{([^}]+)\}', { " ^
    "    param($m) " ^
    "    $keys = $m.Groups[1].Value -split '\.' ; " ^
    "    $v = $cfg; " ^
    "    foreach ($k in $keys) { " ^
    "      if ($v.PSObject.Properties[$k]) { $v = $v.$k } else { return '' } " ^
    "    }; " ^
    "    return [string]$v " ^
    "  }) " ^
    "} " ^
    "" ^
    "$lines = @(); " ^
    "if (Test-Path $envPath) { $lines = Get-Content $envPath } " ^
    "" ^
    "$commentKeys = @('ANTHROPIC_API_KEY','CLAUDE_CODE_USE_FOUNDRY','ANTHROPIC_FOUNDRY_BASE_URL'," ^
    "  'ANTHROPIC_FOUNDRY_API_KEY','CLAUDE_CODE_USE_BEDROCK','AWS_PROFILE','AWS_REGION'," ^
    "  'ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL'," ^
    "  'ANTHROPIC_DEFAULT_OPUS_MODEL','DISABLE_PROMPT_CACHING'); " ^
    "" ^
    "for ($i = 0; $i -lt $lines.Count; $i++) { " ^
    "  $t = $lines[$i].Trim(); " ^
    "  if ($t -and -not $t.StartsWith('#')) { " ^
    "    $eq = $t.IndexOf('='); " ^
    "    if ($eq -gt 0) { " ^
    "      $k = $t.Substring(0, $eq).Trim(); " ^
    "      if ($commentKeys -contains $k) { $lines[$i] = '# ' + $lines[$i] } " ^
    "    } " ^
    "  } " ^
    "} " ^
    "" ^
    "$allVars = @{}; " ^
    "if ($cfg.env_vars) { " ^
    "  $cfg.env_vars.PSObject.Properties | ForEach-Object { $allVars[$_.Name] = $_.Value } " ^
    "} " ^
    "if ($cfg.env_vars_optional) { " ^
    "  $cfg.env_vars_optional.PSObject.Properties | ForEach-Object { $allVars[$_.Name] = $_.Value } " ^
    "} " ^
    "" ^
    "foreach ($entry in $allVars.GetEnumerator()) { " ^
    "  $key = $entry.Key; " ^
    "  $val = Resolve-Template $entry.Value $cfg; " ^
    "  if (-not $val -and $cfg.env_vars_optional -and $cfg.env_vars_optional.PSObject.Properties[$key]) { continue } " ^
    "  $found = $false; " ^
    "  for ($i = 0; $i -lt $lines.Count; $i++) { " ^
    "    $raw = $lines[$i] -replace '^#+\s*',''; " ^
    "    $eq = $raw.IndexOf('='); " ^
    "    if ($eq -gt 0 -and $raw.Substring(0,$eq).Trim() -eq $key) { " ^
    "      $lines[$i] = $key + '=' + $val; " ^
    "      $found = $true; break " ^
    "    } " ^
    "  } " ^
    "  if (-not $found) { $lines += ($key + '=' + $val) } " ^
    "} " ^
    "" ^
    "$lines -join \"`r`n\" | Set-Content $envPath -NoNewline; " ^
    "Write-Host ('[OK] ' + $cfg.display_name + ' configured in .env')"

REM For Bedrock, also write AWS config
if "!AI_PROVIDER!"=="bedrock" (
    powershell -NoProfile -Command ^
        "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
        "if (-not $cfg.sso_start_url -or -not $cfg.account_id -or -not $cfg.role_name) { " ^
        "  Write-Host '[INFO] Bedrock SSO not fully configured -- edit config\bedrock.json'; exit 0 " ^
        "} " ^
        "$awsDir = Join-Path $env:USERPROFILE '.aws'; " ^
        "if (-not (Test-Path $awsDir)) { New-Item $awsDir -ItemType Directory | Out-Null } " ^
        "$cfgPath = Join-Path $awsDir 'config'; " ^
        "$profile = if ($cfg.profile_name) { $cfg.profile_name } else { 'sso-bedrock' }; " ^
        "$session = 'aws-sso'; " ^
        "$existing = ''; if (Test-Path $cfgPath) { $existing = Get-Content $cfgPath -Raw } " ^
        "$out = @(); $skip = $false; " ^
        "foreach ($line in $existing -split '`n') { " ^
        "  if ($line -match ('^\[(sso-session\s+' + [regex]::Escape($session) + '|profile\s+' + [regex]::Escape($profile) + ')\]')) { $skip = $true } " ^
        "  elseif ($line -match '^\[') { $skip = $false } " ^
        "  if (-not $skip) { $out += $line } " ^
        "} " ^
        "$ssoRegion = if ($cfg.sso_region) { $cfg.sso_region } else { 'us-east-1' }; " ^
        "$region = if ($cfg.region) { $cfg.region } else { 'us-east-1' }; " ^
        "$out += ''; " ^
        "$out += \"[sso-session $session]\"; " ^
        "$out += \"sso_start_url = $($cfg.sso_start_url)\"; " ^
        "$out += \"sso_region = $ssoRegion\"; " ^
        "$out += 'sso_registration_scopes = sso:account:access'; " ^
        "$out += ''; " ^
        "$out += \"[profile $profile]\"; " ^
        "$out += \"sso_session = $session\"; " ^
        "$out += \"sso_account_id = $($cfg.account_id)\"; " ^
        "$out += \"sso_role_name = $($cfg.role_name)\"; " ^
        "$out += \"region = $region\"; " ^
        "$out += 'output = json'; " ^
        "$out -join \"`n\" | Set-Content $cfgPath -NoNewline; " ^
        "Write-Host \"[OK] AWS config written to $cfgPath\""
)

goto :skip_foundry_key_subs

:foundry_key_setup
REM Try to decrypt bundled key with passphrase, fall back to manual entry
set "ENC_FILE=%~dp0config\foundry-key.enc"
if not exist "!ENC_FILE!" goto :foundry_key_manual
echo.
echo ========================================
echo   AI Foundry Setup
echo ========================================
echo.
echo   Enter the setup passphrase to activate Claude.
echo   (Get this from your team lead or the AI CoE team.)
echo   Press Enter to skip (will use Azure SSO instead).
echo.
set "SETUP_PHRASE="
set /p "SETUP_PHRASE=  Setup passphrase: "
if not defined SETUP_PHRASE echo [OK] Using Azure SSO -- you will need to run az login inside the container.& exit /b
for /f "usebackq delims=" %%K in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\decrypt-key.ps1" -EncFile "!ENC_FILE!" -Passphrase "!SETUP_PHRASE!" 2^>nul`) do set "DECRYPTED_KEY=%%K"
if not defined DECRYPTED_KEY (
    echo [WARN] Wrong passphrase. Falling back to manual entry...
    goto :foundry_key_manual
)
REM Save decrypted key to config JSON and .env
powershell -NoProfile -Command ^
    "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
    "$cfg.api_key = '!DECRYPTED_KEY!'; " ^
    "$cfg.auth_mode = 'apikey'; " ^
    "$cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'"
echo [OK] API key configured.
exit /b

:foundry_key_manual
echo.
echo   Or enter the API key directly (press Enter to skip):
set "MANUAL_KEY="
set /p "MANUAL_KEY=  AI Foundry API key: "
if defined MANUAL_KEY (
    powershell -NoProfile -Command ^
        "$cfg = Get-Content '!CONFIG_FILE!' -Raw | ConvertFrom-Json; " ^
        "$cfg.api_key = '!MANUAL_KEY!'; " ^
        "$cfg.auth_mode = 'apikey'; " ^
        "$cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'"
    echo [OK] API key saved.
) else (
    echo [OK] Using Azure SSO -- you will need to run az login inside the container.
)
exit /b

:prompt_foundry_key
REM Called when re-running install and foundry is configured but API key is missing
set "ENC_FILE=%~dp0config\foundry-key.enc"
if not exist "!ENC_FILE!" goto :prompt_foundry_key_manual
echo.
echo   Enter the setup passphrase to activate Claude (press Enter to skip):
set "SETUP_PHRASE="
set /p "SETUP_PHRASE=  Setup passphrase: "
if not defined SETUP_PHRASE exit /b
for /f "usebackq delims=" %%K in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\decrypt-key.ps1" -EncFile "!ENC_FILE!" -Passphrase "!SETUP_PHRASE!" 2^>nul`) do set "DECRYPTED_KEY=%%K"
if not defined DECRYPTED_KEY (
    echo [WARN] Wrong passphrase.
    exit /b
)
echo ANTHROPIC_FOUNDRY_API_KEY=!DECRYPTED_KEY!>> "!ENV_FILE!"
echo [OK] API key saved to .env
exit /b
:prompt_foundry_key_manual
set "MANUAL_KEY="
set /p "MANUAL_KEY=  AI Foundry API key (press Enter to skip): "
if defined MANUAL_KEY (
    echo ANTHROPIC_FOUNDRY_API_KEY=!MANUAL_KEY!>> "!ENV_FILE!"
    echo [OK] API key saved to .env
)
exit /b

:skip_foundry_key_subs

:skip_setup

REM ---------------------------------------------------------------------------
REM Auto-extract SSL inspection proxy certificates (Zscaler, Netskope, etc.)
REM Searches Windows cert store and exports any proxy CA certs to certs/
REM so Docker builds trust corporate HTTPS inspection.
REM ---------------------------------------------------------------------------
echo.
echo [...]  Checking network security settings...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\extract-certs.ps1" -CertsDir "%~dp0certs" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fix-vscode-certs.ps1" >nul 2>nul
echo [OK] Network security configured.

REM ---------------------------------------------------------------------------
REM ACR image registry (bypasses Zscaler / SSL inspection entirely)
REM If REGISTRY_MIRROR is set in .env, use it for base images and pre-built pulls.
REM Images are pre-imported into ACR via az acr import (not cache proxied).
REM ---------------------------------------------------------------------------
set "REGISTRY_MIRROR="
set "ACR_HOST="
if exist "!ENV_FILE!" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("!ENV_FILE!") do if /i "%%A"=="REGISTRY_MIRROR" if "%%B" neq "" set "REGISTRY_MIRROR=%%B"
)

if not defined REGISTRY_MIRROR goto :skip_acr

REM Ensure trailing slash for Dockerfile FROM prefix
if "!REGISTRY_MIRROR:~-1!" neq "/" set "REGISTRY_MIRROR=!REGISTRY_MIRROR!/"

REM Extract ACR hostname (e.g., dockyardgwprod.azurecr.io/docker.io/library/ -> dockyardgwprod.azurecr.io)
for /f "delims=/" %%H in ("!REGISTRY_MIRROR!") do set "ACR_HOST=%%H"

REM Read ACR subscription from .env
set "ACR_SUBSCRIPTION="
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("!ENV_FILE!") do if /i "%%A"=="ACR_SUBSCRIPTION" if "%%B" neq "" set "ACR_SUBSCRIPTION=%%B"

REM Extract ACR name (e.g., dockyardgwprod.azurecr.io -> dockyardgwprod)
for /f "delims=." %%N in ("!ACR_HOST!") do set "ACR_NAME=%%N"

REM Authenticate to ACR (az acr login does proper token exchange for blob access)
where az >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo [WARN] Azure CLI not found -- image registry may not work.
    goto :acr_auth_done
)

set "ACR_LOGIN_ARGS=--name !ACR_NAME!"
if defined ACR_SUBSCRIPTION set "ACR_LOGIN_ARGS=!ACR_LOGIN_ARGS! --subscription !ACR_SUBSCRIPTION!"

call az acr login !ACR_LOGIN_ARGS! >nul 2>nul
if !ERRORLEVEL! equ 0 goto :acr_auth_ok

echo [WARN] Image registry not authenticated. Will use public Docker Hub instead.
goto :acr_auth_done

:acr_auth_ok
echo [OK] Image registry: !ACR_HOST!

:acr_auth_done

:skip_acr

REM ---------------------------------------------------------------------------
REM Auto-update: pull latest image (try local file, gateway, direct, then build)
REM ---------------------------------------------------------------------------
echo.
echo [...]  Downloading latest version...

REM --- Try 0: Load from local .tar file (pre-baked image distribution) ---
REM   Place claude-code-docker.tar next to this script to skip all network pulls.
REM   Create with: docker save ghcr.io/sealmindset/claude-code-docker:latest -o claude-code-docker.tar
if exist "%~dp0claude-code-docker.tar" (
    echo [...]  Found local image file -- loading...
    docker load -i "%~dp0claude-code-docker.tar"
    if !ERRORLEVEL! equ 0 (
        echo [OK]  Image loaded from local file.
        goto :image_ready
    )
    echo [...]  Local file load failed -- trying network methods...
)

REM --- Try 1: Pull pre-built image from ACR (imported, bypasses Zscaler) ---
if defined ACR_HOST (
    echo [...]  Downloading via image registry...
    docker pull "!ACR_HOST!/claude-code-docker:latest"
    if !ERRORLEVEL! equ 0 (
        docker tag "!ACR_HOST!/claude-code-docker:latest" ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
        echo [OK]  Image downloaded via registry.
        goto :image_ready
    )
    echo [...]  Registry pull didn't work -- trying other methods...
)

REM --- Try 2: Pull directly from GitHub (works if not behind Zscaler) ---
docker pull ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
if !ERRORLEVEL! equ 0 goto :image_ready

REM --- Try 3: Use cached image if available ---
docker image inspect ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK] Could not check for updates, using cached image.
    goto :image_ready
)

REM --- Try 4: Build from source using ACR-imported base images ---
echo [...]  No cached image. Building locally -- this may take a few minutes...
set "BUILD_ARGS="
if defined REGISTRY_MIRROR set "BUILD_ARGS=--build-arg REGISTRY_MIRROR=!REGISTRY_MIRROR!"
docker build !BUILD_ARGS! -t ghcr.io/sealmindset/claude-code-docker:latest "%~dp0."
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Build failed.
    if defined REGISTRY_MIRROR (
        echo.
        echo   The build could not download its base components.
        echo   This can happen if:
        echo     - The base image has not been imported into ACR yet
        echo       ^(ask the AI CoE team to run: az acr import --name !ACR_NAME! --source docker.io/library/node:20-alpine --image node:20-alpine^)
        echo     - Your network is blocking the connection
    ) else (
        echo.
        echo   The build could not download its base components.
        echo   Check your internet connection and try again.
    )
    echo.
    pause
    exit /b 1
)

:image_ready
echo [OK] Image is ready.

REM ---------------------------------------------------------------------------
REM Desktop shortcut (runs before container start so it's always created)
REM ---------------------------------------------------------------------------
echo.
echo [...]  Setting up desktop shortcut...

REM Clean up unwanted desktop shortcuts (uses PowerShell to find real Desktop path)
powershell -NoProfile -Command ^
    "$desktop = [Environment]::GetFolderPath('Desktop'); " ^
    "$pub = [Environment]::GetFolderPath('CommonDesktopDirectory'); " ^
    "foreach ($d in @($desktop, $pub)) { " ^
    "  foreach ($name in @('Rancher Desktop.lnk','Claude Code.url')) { " ^
    "    $p = Join-Path $d $name; " ^
    "    if (Test-Path $p) { Remove-Item $p -Force -EA SilentlyContinue } " ^
    "  } " ^
    "}"

REM Generate Claude icon (terracotta circle with white C)
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Drawing; " ^
    "$sz = 64; " ^
    "$bmp = New-Object System.Drawing.Bitmap $sz,$sz; " ^
    "$g = [System.Drawing.Graphics]::FromImage($bmp); " ^
    "$g.SmoothingMode = 'AntiAlias'; " ^
    "$g.Clear([System.Drawing.Color]::Transparent); " ^
    "$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(217,119,87)); " ^
    "$g.FillEllipse($brush, 2, 2, ($sz-4), ($sz-4)); " ^
    "$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White); " ^
    "$font = New-Object System.Drawing.Font('Segoe UI',28,[System.Drawing.FontStyle]::Bold); " ^
    "$sf = New-Object System.Drawing.StringFormat; " ^
    "$sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'; " ^
    "$rect = New-Object System.Drawing.RectangleF(0,0,$sz,$sz); " ^
    "$g.DrawString('C',$font,$white,$rect,$sf); " ^
    "$g.Dispose(); " ^
    "$ico = Join-Path '%~dp0' 'claude.ico'; " ^
    "$ms = New-Object System.IO.MemoryStream; " ^
    "$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); " ^
    "$png = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose(); " ^
    "$fs = [System.IO.File]::Create($ico); " ^
    "$bw = New-Object System.IO.BinaryWriter($fs); " ^
    "$bw.Write([Int16]0); $bw.Write([Int16]1); $bw.Write([Int16]1); " ^
    "$bw.Write([byte]$sz); $bw.Write([byte]$sz); $bw.Write([byte]0); " ^
    "$bw.Write([byte]0); $bw.Write([Int16]1); $bw.Write([Int16]32); " ^
    "$bw.Write([int]$png.Length); $bw.Write([int]22); " ^
    "$bw.Write($png); $bw.Close(); $fs.Close()"

REM Create desktop shortcut with Claude icon (fall back to shell globe if .ico failed)
powershell -NoProfile -Command ^
    "$projDir = '%~dp0'.TrimEnd('\'); " ^
    "$vbsPath = Join-Path $projDir 'launch-claude.vbs'; " ^
    "$icoPath = Join-Path $projDir 'claude.ico'; " ^
    "$desktop = [Environment]::GetFolderPath('Desktop'); " ^
    "$lnkPath = Join-Path $desktop 'Claude.lnk'; " ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$lnk = $ws.CreateShortcut($lnkPath); " ^
    "$lnk.TargetPath = $vbsPath; " ^
    "$lnk.WorkingDirectory = $projDir; " ^
    "$lnk.Description = 'Start Claude Code Docker and open in browser'; " ^
    "if (Test-Path $icoPath) { $lnk.IconLocation = $icoPath + ',0' } " ^
    "else { $lnk.IconLocation = 'shell32.dll,14' }; " ^
    "$lnk.Save(); " ^
    "Write-Host '[OK] Claude shortcut added to your desktop.' -ForegroundColor Green"

REM ---------------------------------------------------------------------------
REM Stop existing container if running
REM ---------------------------------------------------------------------------
docker rm -f claude-code >nul 2>nul
docker compose -f "%~dp0docker-compose.yml" down >nul 2>nul

REM ---------------------------------------------------------------------------
REM Start the container
REM ---------------------------------------------------------------------------
echo.
echo [...]  Starting Claude Code...

if not exist "!ENV_FILE!" goto :run_without_env

echo [OK] Loading environment from .env
docker run -d --name claude-code --restart unless-stopped --group-add 0 --env-file "!ENV_FILE!" -p 3000:3000 -p 7681:7681 -p 7682:7682 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents" -v "%USERPROFILE%\Downloads:/home/coder/Downloads" -v "%USERPROFILE%\Desktop:/home/coder/Desktop" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest >"%TEMP%\claude-code-start.log" 2>&1
set "RUN_WITH_ENV=1"
goto :check_run_result

:run_without_env
docker run -d --name claude-code --restart unless-stopped --group-add 0 -p 3000:3000 -p 7681:7681 -p 7682:7682 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents" -v "%USERPROFILE%\Downloads:/home/coder/Downloads" -v "%USERPROFILE%\Desktop:/home/coder/Desktop" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest >"%TEMP%\claude-code-start.log" 2>&1
set "RUN_WITH_ENV=0"

:check_run_result
if !ERRORLEVEL! equ 0 goto :run_ok

REM --- Auto-recover from stale image (OCI "file exists" error) ---
findstr /i "file exists" "%TEMP%\claude-code-start.log" >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo.
    echo [...] Downloaded image is outdated. Rebuilding locally ^(one-time fix^)...
    docker rm -f claude-code >nul 2>nul
    docker rmi ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
    set "BUILD_CMD=docker build"
    if defined REGISTRY_MIRROR set "BUILD_CMD=docker build --build-arg REGISTRY_MIRROR=!REGISTRY_MIRROR!"
    !BUILD_CMD! -t ghcr.io/sealmindset/claude-code-docker:latest . >"%TEMP%\claude-code-build.log" 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [OK] Rebuild complete.
        echo.
        echo [...] Starting Claude Code...
        if "!RUN_WITH_ENV!"=="1" (
            docker run -d --name claude-code --restart unless-stopped --group-add 0 --env-file "!ENV_FILE!" -p 3000:3000 -p 7681:7681 -p 7682:7682 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents" -v "%USERPROFILE%\Downloads:/home/coder/Downloads" -v "%USERPROFILE%\Desktop:/home/coder/Desktop" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest >"%TEMP%\claude-code-start.log" 2>&1
        ) else (
            docker run -d --name claude-code --restart unless-stopped --group-add 0 -p 3000:3000 -p 7681:7681 -p 7682:7682 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents" -v "%USERPROFILE%\Downloads:/home/coder/Downloads" -v "%USERPROFILE%\Desktop:/home/coder/Desktop" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest >"%TEMP%\claude-code-start.log" 2>&1
        )
        if !ERRORLEVEL! equ 0 goto :run_ok
    )
    echo [!] Rebuild did not fix the problem.
)

echo.
echo [!] Could not start Claude Code.
echo.
if exist "%TEMP%\claude-code-start.log" (
    echo   Error details:
    type "%TEMP%\claude-code-start.log"
    echo.
)
echo   Common causes:
echo     - A port is already in use -- 3000, 7681, 8080, or 9200
echo     - Docker ran out of disk space
echo     - The Docker engine needs to be restarted
echo.
echo   Try: restart Docker, then double-click install.bat again.
echo.
pause
exit /b 1

:run_ok
ping -n 4 127.0.0.1 >nul

for /f %%s in ('docker inspect -f "{{.State.Running}}" claude-code 2^>nul') do set RUNNING=%%s
if /i "!RUNNING!"=="true" goto :container_ok

echo.
echo [ERROR] Container started but stopped right away.
echo.
echo --- Recent logs ---
docker logs --tail 30 claude-code 2>&1
echo --- End of logs ---
echo.
echo   Share these logs with the AI CoE team for help.
echo.
pause
exit /b 1

:container_ok
echo [OK] Claude Code is running!

REM ---------------------------------------------------------------------------
REM Wait for dashboard
REM ---------------------------------------------------------------------------
echo.
echo [...]  Getting everything ready...

set ATTEMPTS=0
:waitloop
if !ATTEMPTS! geq 30 goto :timedout
ping -n 3 127.0.0.1 >nul
curl.exe -s -o nul http://localhost:3000 2>nul
if !ERRORLEVEL! equ 0 goto :ready
set /a ATTEMPTS+=1
goto :waitloop

:ready
echo [OK] Dashboard is ready!
echo.
echo ========================================
echo   Opening Claude Code in your browser...
echo ========================================
echo.
start http://localhost:3000
goto :done

:timedout
echo.
echo [OK] Container is still starting up -- this can take a minute.
echo      Opening browser anyway...
start http://localhost:3000

:done

echo.
echo ========================================
echo   Claude Code is ready!
echo ========================================
echo.
echo   http://localhost:3000
echo.
echo   A desktop shortcut has been created so you can come back anytime.
echo   To stop Claude Code: close Docker or run "docker rm -f claude-code"
echo.
pause
endlocal
exit /b 0
