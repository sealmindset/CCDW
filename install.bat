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
REM Guard: Detect elevated (admin) prompt and warn the user
REM Running elevated changes %USERPROFILE% to the admin account's folder,
REM which breaks volume mounts, shortcuts, and project paths.
REM ---------------------------------------------------------------------------
net session >nul 2>&1
if !ERRORLEVEL! equ 0 (
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
    choice /C YN /M "Continue anyway (not recommended)? Y=Yes, N=Close"
    if !ERRORLEVEL! equ 2 exit /b 0
    echo.
    echo   OK, continuing. Some paths may point to the admin account's folders.
    echo.
)

REM ---------------------------------------------------------------------------
REM Step 1: Find the Docker CLI
REM Rancher Desktop installs per-user in %USERPROFILE%\.rd\bin.
REM If IT installed it under a shared admin account (e.g. SSMITH), docker.exe
REM won't be on the current user's PATH. We search multiple locations.
REM ---------------------------------------------------------------------------
set "DOCKER_CMD="
set "DOCKER_SOURCE="
set "FOUND_OTHER_USER="

REM --- 1a. Already on PATH (best case) ---
where docker >nul 2>nul
if !ERRORLEVEL! equ 0 (
    set "DOCKER_CMD=docker"
    set "DOCKER_SOURCE=system PATH"
    goto :found_cli
)

REM --- 1b. Current user's Rancher Desktop ---
if exist "%USERPROFILE%\.rd\bin\docker.exe" (
    set "DOCKER_CMD=%USERPROFILE%\.rd\bin\docker.exe"
    set "DOCKER_SOURCE=Rancher Desktop"
    set "PATH=%USERPROFILE%\.rd\bin;!PATH!"
    goto :found_cli
)

REM --- 1c. Docker Desktop in Program Files ---
if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" (
    set "DOCKER_CMD=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"
    set "DOCKER_SOURCE=Docker Desktop"
    set "PATH=%ProgramFiles%\Docker\Docker\resources\bin;!PATH!"
    goto :found_cli
)

REM --- 1d. Rancher Desktop installed under a different Windows user ---
REM Common in corporate environments where IT installs software via a shared
REM local admin account. We scan C:\Users\*\.rd\bin for any Rancher install.
for /d %%D in (C:\Users\*) do (
    if exist "%%D\.rd\bin\docker.exe" (
        if /i "%%D" neq "%USERPROFILE%" (
            set "FOUND_OTHER_USER=%%~nxD"
            set "FOUND_OTHER_PATH=%%D\.rd\bin"
        )
    )
)

if defined FOUND_OTHER_USER (
    echo [INFO] Rancher Desktop is installed under the !FOUND_OTHER_USER! account.
    echo        That's OK -- you have two options:
    echo.
    echo   A. Install Rancher Desktop under YOUR account (recommended)
    echo      This is a one-time fix so you never need admin again:
    echo        1. Download from https://rancherdesktop.io/
    echo        2. Run the installer -- no admin password needed
    echo        3. Open Rancher Desktop from the Start menu
    echo        4. Preferences, Container Engine, select "dockerd (moby)"
    echo        5. Wait until it finishes starting, then run install.bat again
    echo.
    echo   B. Use the copy from the !FOUND_OTHER_USER! account (quick fix)
    echo      This works as long as Rancher Desktop was started from that
    echo      account at least once since the last reboot.
    echo.
    choice /C AB /M "Pick A or B"
    if !ERRORLEVEL! equ 1 (
        echo.
        echo   Opening the download page...
        start https://rancherdesktop.io/
        echo.
        echo   After installing and starting Rancher Desktop under your
        echo   own account, double-click install.bat again.
        echo.
        pause
        exit /b 0
    )
    echo.
    set "DOCKER_CMD=!FOUND_OTHER_PATH!\docker.exe"
    set "DOCKER_SOURCE=Rancher Desktop (!FOUND_OTHER_USER! account)"
    set "PATH=!FOUND_OTHER_PATH!;!PATH!"
    goto :found_cli
)

REM --- 1e. DOCKER_PATH override from .env ---
if exist "%~dp0.env" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0.env") do (
        if /i "%%A"=="DOCKER_PATH" (
            if exist "%%B\docker.exe" (
                set "DOCKER_CMD=%%B\docker.exe"
                set "DOCKER_SOURCE=.env DOCKER_PATH"
                set "PATH=%%B;!PATH!"
                goto :found_cli
            )
        )
    )
)

REM --- Nothing found ---
echo [ERROR] Could not find Docker on this computer.
echo.
echo   Install Rancher Desktop (free, no admin needed):
echo     1. Download from https://rancherdesktop.io/
echo     2. Run the installer
echo     3. Open Rancher Desktop from the Start menu
echo     4. Go to Preferences, Container Engine, select "dockerd (moby)"
echo     5. Wait for it to finish starting
echo     6. Double-click install.bat again
echo.
echo   IMPORTANT: Install it while logged in as YOUR Windows account,
echo   not a shared admin account. This avoids permission problems.
echo.
echo   Already installed under a different account?
echo     Add this line to the .env file in this folder:
echo       DOCKER_PATH=C:\Users\ACCOUNTNAME\.rd\bin
echo     Then double-click install.bat again.
echo.
pause
exit /b 1

:found_cli
echo [OK] Found Docker (%DOCKER_SOURCE%).

REM ---------------------------------------------------------------------------
REM Step 2: Wait for the Docker engine to be ready
REM Rancher Desktop can take a while to start the dockerd engine. We check
REM the Windows named pipe first (fast), then fall back to docker info.
REM ---------------------------------------------------------------------------

REM Quick pipe check -- this tells us if the Docker daemon is listening at all
set "PIPE_OK=0"
powershell -NoProfile -Command "if (Test-Path \\.\pipe\docker_engine) { exit 0 } else { exit 1 }" >nul 2>nul
if !ERRORLEVEL! equ 0 set "PIPE_OK=1"
if "!PIPE_OK!"=="0" (
    powershell -NoProfile -Command "if (Test-Path \\.\pipe\dockerDesktopLinuxEngine) { exit 0 } else { exit 1 }" >nul 2>nul
    if !ERRORLEVEL! equ 0 set "PIPE_OK=1"
)

docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :engine_ok

REM Engine not responding yet -- wait with a progress indicator
if "!PIPE_OK!"=="1" (
    echo [...]  Docker engine is starting up, waiting...
) else (
    echo [...]  Waiting for Docker engine...
)
set DOCKER_WAIT=0
:docker_retry
if !DOCKER_WAIT! geq 12 goto :engine_fail
ping -n 6 127.0.0.1 >nul
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 goto :engine_ok
set /a DOCKER_WAIT+=1
echo          Still waiting... (!DOCKER_WAIT! of 12)
goto :docker_retry

:engine_fail
echo.
echo [ERROR] The Docker engine did not start after 60 seconds.
echo.

if defined FOUND_OTHER_USER if "!DOCKER_SOURCE!"=="Rancher Desktop (!FOUND_OTHER_USER! account)" (
    echo   The Docker engine needs Rancher Desktop to be running.
    echo   Since it was installed under the !FOUND_OTHER_USER! account,
    echo   the engine may not auto-start for your account.
    echo.
    echo   BEST FIX (permanent -- no more admin headaches):
    echo     1. Download Rancher Desktop: https://rancherdesktop.io/
    echo     2. Install it under YOUR Windows account (no admin needed)
    echo     3. Open it, set engine to "dockerd (moby)"
    echo     4. Double-click install.bat again
    echo.
    echo   QUICK FIX (for right now):
    echo     1. Open Rancher Desktop (it may be in !FOUND_OTHER_USER!'s Start menu)
    echo     2. Wait for it to fully start
    echo     3. Double-click install.bat again
    echo.
    pause
    exit /b 1
)

echo   How to fix:
echo.
echo     Rancher Desktop:
echo       1. Open Rancher Desktop from the Start menu
echo       2. Wait for it to finish starting (the icon stops spinning)
echo       3. IMPORTANT: The engine must be set to "dockerd (moby)":
echo          Preferences, Container Engine, dockerd (moby)
echo       4. Double-click install.bat again
echo.
echo     Docker Desktop:
echo       1. Open Docker Desktop from the Start menu
echo       2. Wait for it to say "running" in the system tray
echo       3. Double-click install.bat again
echo.
echo   TIP: If Rancher Desktop says "running" but this still fails, check
echo        that the Container Engine is set to "dockerd (moby)", NOT containerd.
echo        Preferences, Container Engine, dockerd (moby).
echo.
pause
exit /b 1

:engine_ok
echo [OK] Docker engine is running.

REM ---------------------------------------------------------------------------
REM Create required folders
REM Use PROJECTS_PATH from .env if set, otherwise default to user's Documents
REM ---------------------------------------------------------------------------
set "PROJECTS_DIR="

REM Check .env for a custom PROJECTS_PATH
if exist "%~dp0.env" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0.env") do (
        if /i "%%A"=="PROJECTS_PATH" (
            set "PROJECTS_DIR=%%B"
        )
    )
)

REM Default to current user's Documents\GitHub
if not defined PROJECTS_DIR set "PROJECTS_DIR=%USERPROFILE%\Documents\GitHub"

REM Trim any surrounding quotes
set "PROJECTS_DIR=!PROJECTS_DIR:"=!"

set "AZURE_DIR=%USERPROFILE%\.azure"

if not exist "!PROJECTS_DIR!" (
    echo [...]  Creating projects folder: !PROJECTS_DIR!
    mkdir "!PROJECTS_DIR!"
)
if not exist "!PROJECTS_DIR!" (
    echo [ERROR] Could not create !PROJECTS_DIR!
    echo.
    echo   If this folder is on a network drive or restricted location,
    echo   add this to .env and pick a folder you have access to:
    echo     PROJECTS_PATH=C:\Users\%USERNAME%\MyProjects
    echo.
    pause
    exit /b 1
)
echo [OK] Projects folder: !PROJECTS_DIR!

if not exist "!AZURE_DIR!" (
    echo [...]  Creating Azure config folder: !AZURE_DIR!
    mkdir "!AZURE_DIR!"
)

REM ---------------------------------------------------------------------------
REM Create .env from template if it doesn't exist
REM ---------------------------------------------------------------------------
set "ENV_FILE=%~dp0.env"
if not exist "!ENV_FILE!" (
    if exist "%~dp0.env.example" (
        echo [...]  Creating .env from template...
        copy "%~dp0.env.example" "!ENV_FILE!" >nul
        echo [OK] Created .env -- edit it to add your API key if needed.
    )
)

REM ---------------------------------------------------------------------------
REM Auto-update: pull latest image (continue on failure -- might be offline)
REM ---------------------------------------------------------------------------
echo.
echo [...]  Checking for updates...
docker pull ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
if !ERRORLEVEL! neq 0 (
    REM Check if we have a cached image to fall back to
    docker image inspect ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo [OK] Could not check for updates, using cached image.
    ) else (
        echo [...]  No cached image. Building locally (this may take a few minutes)...
        docker build -t ghcr.io/sealmindset/claude-code-docker:latest "%~dp0."
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Build failed. Check the output above for details.
            echo.
            pause
            exit /b 1
        )
    )
)
echo [OK] Image is ready.

REM ---------------------------------------------------------------------------
REM Stop existing container if running
REM ---------------------------------------------------------------------------
docker rm -f claude-code >nul 2>nul
docker compose -f "%~dp0docker-compose.yml" down >nul 2>nul

REM ---------------------------------------------------------------------------
REM Start the container
REM ---------------------------------------------------------------------------
echo.
echo [...]  Starting Claude Code Docker...

set "RUN_ARGS=-d --name claude-code --restart unless-stopped --group-add 0"
set "RUN_PORTS=-p 3000:3000 -p 7681:7681 -p 8080:8080 -p 9200:9200"
set "RUN_VOLS=-v //var/run/docker.sock:/var/run/docker.sock"
set "RUN_VOLS=!RUN_VOLS! -v "!PROJECTS_DIR!:/home/coder/Documents/GitHub""
set "RUN_VOLS=!RUN_VOLS! -v "!AZURE_DIR!:/home/coder/.azure""
set "RUN_VOLS=!RUN_VOLS! -v claude-code-data:/home/coder/.claude"
set "RUN_VOLS=!RUN_VOLS! -v claude-code-gh:/home/coder/.config/gh"
set "RUN_VOLS=!RUN_VOLS! -v claude-code-git-config:/home/coder/.gitconfig.d"

if exist "!ENV_FILE!" (
    echo [OK] Loading environment from .env
    docker run !RUN_ARGS! --env-file "!ENV_FILE!" !RUN_PORTS! !RUN_VOLS! ghcr.io/sealmindset/claude-code-docker:latest
) else (
    docker run !RUN_ARGS! !RUN_PORTS! !RUN_VOLS! ghcr.io/sealmindset/claude-code-docker:latest
)

if !ERRORLEVEL! neq 0 (
    echo.
    echo [ERROR] Failed to start the container.
    echo.
    echo   Common fixes:
    echo     - Make sure ports 3000, 7681, 8080, 9200 are not in use
    echo     - Restart Rancher Desktop or Docker Desktop and try again
    echo.
    echo   Port conflict? Add these to .env with different numbers:
    echo     WELCOME_PORT=3001
    echo     TTYD_PORT=7682
    echo     CODE_SERVER_PORT=8081
    echo.
    pause
    exit /b 1
)

REM Give the container a moment to start or crash
ping -n 4 127.0.0.1 >nul

REM Verify the container is still running
docker inspect -f "{{.State.Running}}" claude-code >nul 2>nul
if !ERRORLEVEL! neq 0 goto :container_crashed
for /f %%s in ('docker inspect -f "{{.State.Running}}" claude-code 2^>nul') do set RUNNING=%%s
if /i "!RUNNING!" neq "true" goto :container_crashed
goto :container_ok

:container_crashed
echo.
echo [ERROR] Container started but stopped right away.
echo.
echo --- Recent logs ---
docker logs --tail 30 claude-code 2>&1
echo --- End of logs ---
echo.
echo   This usually means something inside the container hit an error.
echo   Share these logs with the AI CoE team for help.
echo.
pause
exit /b 1

:container_ok
echo [OK] Claude Code Docker is running!

REM ---------------------------------------------------------------------------
REM Wait for the dashboard to be ready, then open browser
REM ---------------------------------------------------------------------------
echo.
echo [...]  Waiting for dashboard to start...

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
goto :shortcuts

:timedout
echo.
echo [OK] Container is still starting up (this can take a minute).
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
) > "!SHORTCUT!"

if exist "!SHORTCUT!" (
    echo [OK] Desktop shortcut created: "Claude Code" on your desktop
) else (
    echo [WARN] Could not create desktop shortcut (not a problem)
)

echo.
echo ========================================
echo   Claude Code Docker is ready!
echo ========================================
echo.
echo   Dashboard:     http://localhost:3000
echo   Workshop:      http://localhost:9200
echo   Web Terminal:  http://localhost:7681
echo   VS Code:       http://localhost:8080
echo.
echo   FIRST TIME? Click "Workshop" in the dashboard to build
echo   your first app -- no coding needed!
echo.
echo   To stop:    docker rm -f claude-code
echo   To restart: double-click "Claude Code" on your desktop
echo.
pause
endlocal
exit /b 0
