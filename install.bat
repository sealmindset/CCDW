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

title Claude Code Docker - Installer

echo.
echo ========================================
echo   Claude Code Docker - Installer
echo ========================================
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
echo          Still waiting... !DOCKER_WAIT! of 12
goto :docker_retry

:engine_fail
echo.
echo [ERROR] The Docker engine did not start after 60 seconds.
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

REM ---------------------------------------------------------------------------
REM Create required folders
REM ---------------------------------------------------------------------------
set "PROJECTS_DIR="

if not exist "%~dp0.env" goto :default_projects_dir
for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0.env") do (
    if /i "%%A"=="PROJECTS_PATH" set "PROJECTS_DIR=%%B"
)

:default_projects_dir
if not defined PROJECTS_DIR set "PROJECTS_DIR=%USERPROFILE%\GitHub"
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
echo     PROJECTS_PATH=C:\Users\%USERNAME%\GitHub
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
echo.
echo ========================================
echo   Preflight Checks: !AI_PROVIDER!
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
    echo [ERROR] Some required preflight checks failed.
    echo         Fix the items above and run the installer again.
    echo.
    pause
    exit /b 1
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
        "} " ^
        "if ($cfg.auth_mode -eq 'apikey' -and -not $cfg.api_key) { " ^
        "  $key = Read-Host '  API key' -AsSecureString; " ^
        "  $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($key)); " ^
        "  if ($plain) { $cfg.api_key = $plain; $cfg | ConvertTo-Json -Depth 10 | Set-Content '!CONFIG_FILE!'; Write-Host '  [OK] API key saved' } " ^
        "} elseif ($cfg.auth_mode -ne 'apikey') { " ^
        "  Write-Host '  Note: Azure SSO sign-in will happen after the container starts.' -ForegroundColor Cyan " ^
        "}"
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
        "if (!(Test-Path $awsDir)) { New-Item $awsDir -ItemType Directory | Out-Null } " ^
        "$cfgPath = Join-Path $awsDir 'config'; " ^
        "$profile = if ($cfg.profile_name) { $cfg.profile_name } else { 'sso-bedrock' }; " ^
        "$session = 'aws-sso'; " ^
        "$existing = ''; if (Test-Path $cfgPath) { $existing = Get-Content $cfgPath -Raw } " ^
        "$out = @(); $skip = $false; " ^
        "foreach ($line in $existing -split '`n') { " ^
        "  if ($line -match ('^\[(sso-session\s+' + [regex]::Escape($session) + '|profile\s+' + [regex]::Escape($profile) + ')\]')) { $skip = $true } " ^
        "  elseif ($line -match '^\[') { $skip = $false } " ^
        "  if (!$skip) { $out += $line } " ^
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

:skip_setup

REM ---------------------------------------------------------------------------
REM Auto-update: pull latest image
REM ---------------------------------------------------------------------------
echo.
echo [...]  Checking for updates...
docker pull ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
if !ERRORLEVEL! equ 0 goto :image_ready

docker image inspect ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [OK] Could not check for updates, using cached image.
    goto :image_ready
)

echo [...]  No cached image. Building locally -- this may take a few minutes...
docker build -t ghcr.io/sealmindset/claude-code-docker:latest "%~dp0."
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Build failed. Check the output above for details.
    echo.
    pause
    exit /b 1
)

:image_ready
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

if not exist "!ENV_FILE!" goto :run_without_env

echo [OK] Loading environment from .env
docker run -d --name claude-code --restart unless-stopped --group-add 0 --env-file "!ENV_FILE!" -p 3000:3000 -p 7681:7681 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents/GitHub" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest
goto :check_run_result

:run_without_env
docker run -d --name claude-code --restart unless-stopped --group-add 0 -p 3000:3000 -p 7681:7681 -p 8080:8080 -p 9200:9200 -v //var/run/docker.sock:/var/run/docker.sock -v "!PROJECTS_DIR!:/home/coder/Documents/GitHub" -v "!AZURE_DIR!:/home/coder/.azure" -v "!AWS_DIR!:/home/coder/.aws" -v claude-code-data:/home/coder/.claude -v claude-code-gh:/home/coder/.config/gh -v claude-code-git-config:/home/coder/.gitconfig.d ghcr.io/sealmindset/claude-code-docker:latest

:check_run_result
if !ERRORLEVEL! equ 0 goto :run_ok

echo.
echo [ERROR] Failed to start the container.
echo.
echo   Common fixes:
echo     - Make sure ports 3000, 7681, 8080, 9200 are not in use
echo     - Restart Rancher Desktop or Docker Desktop and try again
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
echo [OK] Claude Code Docker is running!

REM ---------------------------------------------------------------------------
REM Wait for dashboard
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
echo [OK] Container is still starting up -- this can take a minute.
echo      Opening browser anyway...
start http://localhost:3000

:shortcuts
REM ---------------------------------------------------------------------------
REM Desktop shortcut
REM ---------------------------------------------------------------------------
echo.
echo [...]  Creating desktop shortcut...

set "SHORTCUT=%USERPROFILE%\Desktop\Claude Code.url"
echo [InternetShortcut]> "!SHORTCUT!"
echo URL=http://localhost:3000>> "!SHORTCUT!"
echo IconIndex=0>> "!SHORTCUT!"

if exist "!SHORTCUT!" (
    echo [OK] Desktop shortcut created: "Claude Code" on your desktop
) else (
    echo [WARN] Could not create desktop shortcut -- not a problem
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
