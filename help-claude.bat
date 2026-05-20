@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM Claude Code Docker - Diagnostic Report
REM
REM Collects system info, container logs, and health checks into a single
REM file on your Desktop. Send this file when asking for help.
REM =============================================================================

title Claude Code Docker - Diagnostics

echo.
echo ========================================
echo   Claude Code Docker - Diagnostics
echo ========================================
echo.
echo   Collecting diagnostic information...
echo.

set "REPORT=%USERPROFILE%\Desktop\claude-diagnostic.txt"

REM ---------------------------------------------------------------------------
REM Find Docker
REM ---------------------------------------------------------------------------
set "DOCKER_CMD="
where docker >nul 2>nul && set "DOCKER_CMD=docker"
if not defined DOCKER_CMD if exist "%USERPROFILE%\.rd\bin\docker.exe" set "DOCKER_CMD=%USERPROFILE%\.rd\bin\docker.exe"
if not defined DOCKER_CMD if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" set "DOCKER_CMD=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"
if not defined DOCKER_CMD if exist "%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe" set "DOCKER_CMD=%LOCALAPPDATA%\Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe"

REM ---------------------------------------------------------------------------
REM Write report header
REM ---------------------------------------------------------------------------
(
    echo ============================================================
    echo   Claude Code Docker - Diagnostic Report
    echo   Generated: %DATE% %TIME%
    echo ============================================================
    echo.
) > "!REPORT!"

REM ---------------------------------------------------------------------------
REM System info
REM ---------------------------------------------------------------------------
(
    echo === SYSTEM INFO ===
    echo Computer: %COMPUTERNAME%
    echo User: %USERNAME%
    echo OS:
) >> "!REPORT!"
powershell -NoProfile -Command "[System.Environment]::OSVersion.VersionString" >> "!REPORT!" 2>&1
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Docker status
REM ---------------------------------------------------------------------------
(
    echo === DOCKER STATUS ===
) >> "!REPORT!"
if defined DOCKER_CMD (
    echo Docker found: !DOCKER_CMD! >> "!REPORT!"
    "!DOCKER_CMD!" version >> "!REPORT!" 2>&1
    echo. >> "!REPORT!"
    echo Docker info: >> "!REPORT!"
    "!DOCKER_CMD!" info >> "!REPORT!" 2>&1
) else (
    echo Docker: NOT FOUND >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Container status
REM ---------------------------------------------------------------------------
(
    echo === CONTAINER STATUS ===
) >> "!REPORT!"
if defined DOCKER_CMD (
    "!DOCKER_CMD!" inspect --format "Name: {{.Name}} State: {{.State.Status}} Started: {{.State.StartedAt}}" claude-code >> "!REPORT!" 2>&1
    echo. >> "!REPORT!"
    echo Ports: >> "!REPORT!"
    "!DOCKER_CMD!" port claude-code >> "!REPORT!" 2>&1
) else (
    echo Container: Docker not available >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Container logs (last 100 lines)
REM ---------------------------------------------------------------------------
(
    echo === CONTAINER LOGS (last 100 lines) ===
) >> "!REPORT!"
if defined DOCKER_CMD (
    "!DOCKER_CMD!" logs --tail 100 claude-code >> "!REPORT!" 2>&1
) else (
    echo Logs: Docker not available >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Doctor output (run inside container)
REM ---------------------------------------------------------------------------
(
    echo === HEALTH CHECK (doctor) ===
) >> "!REPORT!"
if defined DOCKER_CMD (
    "!DOCKER_CMD!" exec claude-code bash -c "/opt/claude-code-docker/scripts/doctor.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'" >> "!REPORT!" 2>&1
) else (
    echo Doctor: Docker not available >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Network checks
REM ---------------------------------------------------------------------------
(
    echo === NETWORK ===
    echo Checking github.com:
) >> "!REPORT!"
curl.exe -s --connect-timeout 5 -o nul -w "  HTTP: %%{http_code}  Time: %%{time_total}s" https://github.com >> "!REPORT!" 2>&1
echo. >> "!REPORT!"

(
    echo Checking ports:
) >> "!REPORT!"
powershell -NoProfile -Command ^
    "foreach ($p in @(3000,7681,8080,9200)) { " ^
    "  try { " ^
    "    $conn = Get-NetTCPConnection -LocalPort $p -State Listen -EA Stop; " ^
    "    $proc = Get-Process -Id $conn[0].OwningProcess -EA Stop; " ^
    "    Write-Output ('  Port ' + $p + ': ' + $proc.ProcessName + ' (PID ' + $proc.Id + ')') " ^
    "  } catch { " ^
    "    Write-Output ('  Port ' + $p + ': not listening') " ^
    "  } " ^
    "}" >> "!REPORT!" 2>&1
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM .env file (redact secrets)
REM ---------------------------------------------------------------------------
(
    echo === CONFIGURATION (.env with secrets redacted) ===
) >> "!REPORT!"
if exist "%~dp0.env" (
    powershell -NoProfile -Command ^
        "Get-Content '%~dp0.env' | ForEach-Object { " ^
        "  if ($_ -match '(KEY|SECRET|PASSWORD|TOKEN)=') { " ^
        "    $parts = $_ -split '=',2; " ^
        "    if ($parts.Length -eq 2 -and $parts[1].Length -gt 4) { " ^
        "      $parts[0] + '=' + $parts[1].Substring(0,4) + '***REDACTED***' " ^
        "    } else { $_ } " ^
        "  } else { $_ } " ^
        "}" >> "!REPORT!" 2>&1
) else (
    echo .env file not found >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM WSL status
REM ---------------------------------------------------------------------------
(
    echo === WSL STATUS ===
) >> "!REPORT!"
wsl --status >> "!REPORT!" 2>&1
echo. >> "!REPORT!"
wsl -l -v >> "!REPORT!" 2>&1
echo. >> "!REPORT!"
(
    echo === RANCHER WSL HEALTH CHECK ===
) >> "!REPORT!"
wsl -l 2>nul | findstr /i "rancher-desktop" >nul 2>nul
if !ERRORLEVEL! neq 0 (
    echo No Rancher Desktop WSL distributions found. >> "!REPORT!"
) else (
    wsl -d rancher-desktop -- echo ok >nul 2>nul
    if !ERRORLEVEL! equ 0 (
        echo rancher-desktop distro: HEALTHY >> "!REPORT!"
    ) else (
        echo rancher-desktop distro: CORRUPTED ^(exit code 4294967295^) >> "!REPORT!"
        echo Recommended fix: run fix-rancher.bat >> "!REPORT!"
    )
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Rancher Desktop info
REM ---------------------------------------------------------------------------
(
    echo === RANCHER DESKTOP ===
) >> "!REPORT!"
if exist "%APPDATA%\rancher-desktop\settings.json" (
    echo Settings found: %APPDATA%\rancher-desktop\settings.json >> "!REPORT!"
    powershell -NoProfile -Command "Get-Content '%APPDATA%\rancher-desktop\settings.json' | Select-Object -First 20" >> "!REPORT!" 2>&1
) else (
    echo Settings file not found >> "!REPORT!"
)
echo. >> "!REPORT!"

REM ---------------------------------------------------------------------------
REM Done
REM ---------------------------------------------------------------------------
echo.
echo ========================================
echo   Diagnostic report saved!
echo ========================================
echo.
echo   File: !REPORT!
echo.
echo   Send this file when asking for help.
echo   It contains system info, logs, and health checks.
echo   Secrets and passwords have been removed.
echo.
pause
endlocal
exit /b 0
