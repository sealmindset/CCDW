@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code — Access Check (Windows)
REM Checks whether your computer is ready to install. Doesn't install anything.
REM Usage:
REM   check-access.bat                 Check everything
REM   check-access.bat --ai=foundry    Check for Azure AI Foundry
REM   check-access.bat --ai=bedrock    Check for AWS Bedrock
REM   check-access.bat --ai=anthropic  Check for Anthropic API
REM =============================================================================

title Claude Code - Access Check

set "PASS=0"
set "FAIL=0"
set "WARN=0"

REM --- Parse --ai= argument ---
set "AI_PROVIDER="
for %%A in (%*) do (
    set "ARG=%%A"
    if "!ARG:~0,5!"=="--ai=" set "AI_PROVIDER=!ARG:~5!"
)
if /i "!AI_PROVIDER!"=="foundry"       set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="azure-foundry" set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="azure"         set "AI_PROVIDER=foundry"
if /i "!AI_PROVIDER!"=="bedrock"       set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="aws-bedrock"   set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="aws"           set "AI_PROVIDER=bedrock"
if /i "!AI_PROVIDER!"=="anthropic"     set "AI_PROVIDER=anthropic"
if /i "!AI_PROVIDER!"=="api-key"       set "AI_PROVIDER=anthropic"
if /i "!AI_PROVIDER!"=="apikey"        set "AI_PROVIDER=anthropic"

echo.
echo ========================================
echo   Claude Code - Access Check
echo ========================================
echo.
echo   This checks whether your computer is ready
echo   to install Claude Code. It doesn't install anything.
echo.

REM --- Admin check ---
net session >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   [!] WARNING: Running as Administrator.
    echo       The installer should NOT run as admin.
    echo       Close this and double-click normally instead.
    echo.
    set /a WARN+=1
)

echo   Basic Requirements
echo.

REM --- WSL2 ---
where wsl >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo   X  WSL2 is not installed
    echo       Open PowerShell as Admin and run: wsl --install
    echo       Then restart your computer.
    set /a FAIL+=1
    goto :after_wsl
)
wsl --status >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK WSL2 is ready
    set /a PASS+=1
) else (
    wsl -l >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo   OK WSL2 is ready
        set /a PASS+=1
    ) else (
        echo   X  WSL2 installed but needs a reboot
        echo       Restart your computer, then run this check again.
        set /a FAIL+=1
    )
)
:after_wsl

REM --- Docker installed (search common locations) ---
set "DOCKER_FOUND=0"
where docker >nul 2>nul && set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="0" if exist "%USERPROFILE%\.rd\bin\docker.exe" set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="0" if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="0" if exist "%ProgramFiles%\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="0" if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_FOUND=1"
if "!DOCKER_FOUND!"=="1" (
    echo   OK Docker CLI found
    set /a PASS+=1
) else (
    echo   X  Docker is not installed
    echo       Install Rancher Desktop from rancherdesktop.io
    echo       or Docker Desktop from docker.com.
    set /a FAIL+=1
)

REM --- Docker running ---
docker info >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK Docker engine is running
    set /a PASS+=1
) else (
    echo   X  Docker engine is not running
    echo       Open Rancher Desktop or Docker Desktop and wait for it to start.
    set /a FAIL+=1
)

REM --- Internet connectivity ---
curl.exe -sf --connect-timeout 5 https://www.google.com -o nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK Internet connectivity
    set /a PASS+=1
) else (
    echo   X  Cannot reach the internet
    echo       Check your Wi-Fi or Ethernet connection.
    set /a FAIL+=1
)

REM --- SSL / content filter ---
powershell -NoProfile -Command ^
    "try { " ^
    "  $r = Invoke-WebRequest -Uri 'https://www.google.com' -UseBasicParsing -TimeoutSec 10 -EA Stop; " ^
    "  exit 0 " ^
    "} catch { " ^
    "  if ($_.Exception.Message -match 'SSL|TLS|certificate|trust') { exit 2 } " ^
    "  exit 1 " ^
    "}"
if !ERRORLEVEL! equ 0 (
    echo   OK SSL/TLS connections working ^(no content filter blocking^)
    set /a PASS+=1
) else if !ERRORLEVEL! equ 2 (
    echo   X  SSL inspection is blocking HTTPS connections
    echo       Zscaler, Netskope, or another content filter is interfering.
    echo       Contact IT to get added to the DevOps bypass group.
    set /a FAIL+=1
) else (
    echo   X  HTTPS connection test failed
    echo       Check your network connection and proxy settings.
    set /a FAIL+=1
)

REM --- GitHub Container Registry ---
curl.exe -sf --connect-timeout 10 https://ghcr.io -o nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK GitHub Container Registry ^(ghcr.io^) reachable
    set /a PASS+=1
) else (
    echo   X  Cannot reach ghcr.io ^(GitHub Container Registry^)
    echo       Your network may be blocking GitHub. Contact IT.
    set /a FAIL+=1
)

REM --- Disk space ---
for /f "tokens=3" %%S in ('dir /-C "%~dp0." 2^>nul ^| findstr /c:"bytes free"') do set "FREE_BYTES=%%S"
if defined FREE_BYTES (
    powershell -NoProfile -Command ^
        "$fb = [long]'!FREE_BYTES!'; $gb = [math]::Floor($fb / 1GB); " ^
        "if ($fb -ge 5368709120) { Write-Host \"  OK Disk space: $gb GB free (5 GB required)\"; exit 0 } " ^
        "else { Write-Host \"  X  Low disk space: $gb GB free (5 GB required)\"; Write-Host '      Free up space before installing.'; exit 1 }"
    if !ERRORLEVEL! equ 0 ( set /a PASS+=1 ) else ( set /a FAIL+=1 )
) else (
    echo   ?  Could not check disk space ^(verify manually^)
    set /a WARN+=1
)

REM --- Config files ---
set "CFG_COUNT=0"
if exist "%~dp0config\foundry.json"   set /a CFG_COUNT+=1
if exist "%~dp0config\bedrock.json"   set /a CFG_COUNT+=1
if exist "%~dp0config\anthropic.json" set /a CFG_COUNT+=1
if !CFG_COUNT! gtr 0 (
    echo   OK AI provider config found ^(!CFG_COUNT! config files^)
    set /a PASS+=1
) else (
    echo   X  No AI provider config files in config\
    echo       Should contain foundry.json, bedrock.json, or anthropic.json.
    set /a FAIL+=1
)

REM =========================================================================
REM Provider-specific checks
REM =========================================================================

REM --- Foundry ---
if defined AI_PROVIDER if /i "!AI_PROVIDER!" neq "foundry" goto :skip_foundry
if not defined AI_PROVIDER if not exist "%~dp0config\foundry.json" goto :skip_foundry

echo.
echo   Azure AI Foundry
echo.

where az >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK Azure CLI installed
    set /a PASS+=1
) else (
    echo   X  Azure CLI ^(az^) is not installed
    echo       Install from: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
    set /a FAIL+=1
)

curl.exe -sf --connect-timeout 10 https://login.microsoftonline.com -o nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK Azure AD login reachable
    set /a PASS+=1
) else (
    echo   X  Cannot reach Azure AD login
    echo       Check your internet connection or VPN.
    set /a FAIL+=1
)

REM Foundry endpoint from config
if exist "%~dp0config\foundry.json" (
    for /f "usebackq delims=" %%E in (`powershell -NoProfile -Command "(Get-Content '%~dp0config\foundry.json' | ConvertFrom-Json).endpoint" 2^>nul`) do set "FOUNDRY_EP=%%E"
)
if defined FOUNDRY_EP if "!FOUNDRY_EP!" neq "" (
    powershell -NoProfile -Command ^
        "try { $r = Invoke-WebRequest -Uri '!FOUNDRY_EP!' -UseBasicParsing -TimeoutSec 10 -EA Stop; exit 0 } " ^
        "catch { if ($_.Exception.Response) { exit 0 } else { exit 1 } }"
    if !ERRORLEVEL! equ 0 (
        echo   OK AI Foundry endpoint reachable
        set /a PASS+=1
    ) else (
        echo   X  Cannot reach AI Foundry endpoint
        echo       You need corporate network or VPN ^(GlobalProtect^).
        set /a FAIL+=1
    )
) else (
    echo   ?  No Foundry endpoint configured ^(verify manually^)
    echo       Set endpoint in config\foundry.json to test connectivity.
    set /a WARN+=1
)

REM Azure subscription (informational)
if exist "%~dp0config\foundry.json" (
    for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "(Get-Content '%~dp0config\foundry.json' | ConvertFrom-Json).subscription_name" 2^>nul`) do (
        if "%%S" neq "" (
            echo   ?  Azure subscription: %%S ^(verify manually^)
            echo       Verify you have access in the Azure portal.
            set /a WARN+=1
        )
    )
)
:skip_foundry

REM --- Bedrock ---
if defined AI_PROVIDER if /i "!AI_PROVIDER!" neq "bedrock" goto :skip_bedrock
if not defined AI_PROVIDER if not exist "%~dp0config\bedrock.json" goto :skip_bedrock

echo.
echo   AWS Bedrock
echo.

where aws >nul 2>nul
if !ERRORLEVEL! equ 0 (
    aws --version 2>&1 | findstr /c:"aws-cli/2" >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo   OK AWS CLI v2 installed
        set /a PASS+=1
    ) else (
        echo   X  AWS CLI v1 found ^(v2 required^)
        echo       Upgrade: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
        set /a FAIL+=1
    )
) else (
    echo   X  AWS CLI is not installed
    echo       Install v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    set /a FAIL+=1
)

curl.exe -sf --connect-timeout 10 https://aws.amazon.com -o nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK AWS reachable
    set /a PASS+=1
) else (
    echo   X  Cannot reach AWS
    echo       Check your internet connection.
    set /a FAIL+=1
)

REM SSO portal from config
if exist "%~dp0config\bedrock.json" (
    for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "(Get-Content '%~dp0config\bedrock.json' | ConvertFrom-Json).sso_start_url" 2^>nul`) do set "SSO_URL=%%U"
)
if defined SSO_URL if "!SSO_URL!" neq "" (
    curl.exe -sf --connect-timeout 10 "!SSO_URL!" -o nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo   OK AWS SSO portal reachable
        set /a PASS+=1
    ) else (
        echo   X  Cannot reach AWS SSO portal
        echo       Check your network connection.
        set /a FAIL+=1
    )
)

echo   ?  Okta group: aws-bedrock-model-access ^(verify manually^)
echo       If not in this group, create an EMB ticket requesting access.
set /a WARN+=1
:skip_bedrock

REM --- Anthropic ---
if defined AI_PROVIDER if /i "!AI_PROVIDER!" neq "anthropic" goto :skip_anthropic
if not defined AI_PROVIDER if not exist "%~dp0config\anthropic.json" goto :skip_anthropic

echo.
echo   Anthropic API
echo.

set "HAS_KEY=0"
if exist "%~dp0config\anthropic.json" (
    powershell -NoProfile -Command ^
        "$k = (Get-Content '%~dp0config\anthropic.json' | ConvertFrom-Json).api_key; " ^
        "if ($k) { exit 0 } else { exit 1 }" 2>nul
    if !ERRORLEVEL! equ 0 set "HAS_KEY=1"
)
if "!HAS_KEY!"=="0" if exist "%~dp0.env" (
    findstr /b "ANTHROPIC_API_KEY=sk-" "%~dp0.env" >nul 2>nul && set "HAS_KEY=1"
)
if "!HAS_KEY!"=="1" (
    echo   OK Anthropic API key configured
    set /a PASS+=1
) else (
    echo   ?  No API key found yet ^(verify manually^)
    echo       You will need a key ^(sk-ant-...^) during install. Get one at console.anthropic.com.
    set /a WARN+=1
)

curl.exe -sf --connect-timeout 10 https://api.anthropic.com -o nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo   OK Anthropic API reachable
    set /a PASS+=1
) else (
    echo   X  Cannot reach Anthropic API
    echo       Check your internet. Corporate networks may block this.
    set /a FAIL+=1
)
:skip_anthropic

REM =========================================================================
REM Summary
REM =========================================================================
echo.
echo ========================================
set /a TOTAL=PASS+FAIL+WARN
if !FAIL! equ 0 (
    echo   Ready to install!  ^(!PASS! passed^)
    echo.
    echo   Run install.bat to get started.
) else (
    echo   !FAIL! item^(s^) need attention before installing.
    if !WARN! gtr 0 echo   !WARN! item^(s^) need manual verification.
    echo.
    echo   Fix the items marked with X above, then run this check again.
)
echo ========================================
echo.
pause
if !FAIL! equ 0 ( exit /b 0 ) else ( exit /b 1 )
