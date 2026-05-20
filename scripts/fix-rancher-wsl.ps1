# fix-rancher-wsl.ps1 -- Repair corrupted Rancher Desktop WSL distributions
# Exit code 0 = repaired, 1 = no repair needed, 2 = repair failed
#
# Rancher Desktop uses two internal WSL distros: rancher-desktop and rancher-desktop-data.
# When these get corrupted, Rancher logs "wsl.exe exited with code 4294967295" in a loop.
# Fix: unregister both, shutdown WSL, let Rancher recreate them on next start.

param(
    [switch]$DiagOnly,
    [switch]$Quiet
)

function Write-Status($msg) {
    if (-not $Quiet) { Write-Host $msg }
}

# --- Step 1: Detect if Rancher WSL distros are registered ---
$distroList = wsl -l -q 2>&1 | ForEach-Object { $_ -replace '\x00','' } | Where-Object { $_.Trim() -ne '' }
$hasRD      = $distroList | Where-Object { $_ -match '^rancher-desktop$' }
$hasRDData  = $distroList | Where-Object { $_ -match '^rancher-desktop-data$' }

if (-not $hasRD -and -not $hasRDData) {
    Write-Status "[OK]  No Rancher Desktop WSL distributions found -- nothing to repair."
    exit 1
}

# --- Step 2: Test if the distros are healthy ---
$healthy = $true
if ($hasRD) {
    $testOut = wsl -d rancher-desktop -- echo ok 2>&1
    if ($LASTEXITCODE -ne 0 -or $testOut -notmatch 'ok') {
        $healthy = $false
        Write-Status "[FAIL] rancher-desktop distro is not responding."
    } else {
        Write-Status "[OK]  rancher-desktop distro is healthy."
    }
}
if ($hasRDData) {
    # rancher-desktop-data is a data-only distro, just check if wsl can list its status
    $statusOut = wsl -l -v 2>&1 | ForEach-Object { $_ -replace '\x00','' }
    $dataLine = $statusOut | Where-Object { $_ -match 'rancher-desktop-data' }
    if ($dataLine -match 'Stopped|Running') {
        Write-Status "[OK]  rancher-desktop-data distro is present."
    }
}

if ($healthy -and -not $DiagOnly) {
    Write-Status "[OK]  Rancher Desktop WSL distributions appear healthy."
    Write-Status "      If you are still having issues, run with -DiagOnly to see details,"
    Write-Status "      or re-run fix-rancher.bat and choose Force Repair."
    exit 1
}

if ($DiagOnly) {
    Write-Status ""
    Write-Status "=== WSL Distribution Status ==="
    wsl -l -v 2>&1 | ForEach-Object { $_ -replace '\x00','' } | ForEach-Object { Write-Status "  $_" }
    Write-Status ""
    if ($healthy) {
        Write-Status "  Result: Distributions look healthy."
    } else {
        Write-Status "  Result: One or more distributions are corrupted."
        Write-Status "  Fix: Re-run fix-rancher.bat and choose Repair."
    }
    exit 0
}

# --- Step 3: Stop Rancher Desktop ---
Write-Status ""
Write-Status "[...]  Closing Rancher Desktop..."
$rdProc = Get-Process "Rancher Desktop" -ErrorAction SilentlyContinue
if ($rdProc) {
    # Try graceful close via rdctl first
    $rdctl = "$env:USERPROFILE\.rd\bin\rdctl.exe"
    if (Test-Path $rdctl) {
        & $rdctl shutdown 2>$null
        Start-Sleep -Seconds 3
    }
    # Force kill if still running
    $rdProc = Get-Process "Rancher Desktop" -ErrorAction SilentlyContinue
    if ($rdProc) {
        Stop-Process -Name "Rancher Desktop" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
Write-Status "[OK]  Rancher Desktop closed."

# --- Step 4: Shutdown WSL ---
Write-Status "[...]  Shutting down WSL..."
wsl --shutdown 2>$null
Start-Sleep -Seconds 3
Write-Status "[OK]  WSL shut down."

# --- Step 5: Unregister corrupted distros ---
if ($hasRD) {
    Write-Status "[...]  Removing corrupted rancher-desktop distribution..."
    wsl --unregister rancher-desktop 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Status "[OK]  rancher-desktop removed."
    } else {
        Write-Status "[WARN] Could not remove rancher-desktop (may already be gone)."
    }
}
if ($hasRDData) {
    Write-Status "[...]  Removing corrupted rancher-desktop-data distribution..."
    wsl --unregister rancher-desktop-data 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Status "[OK]  rancher-desktop-data removed."
    } else {
        Write-Status "[WARN] Could not remove rancher-desktop-data (may already be gone)."
    }
}

# --- Step 6: Pre-configure Rancher Desktop settings for clean start ---
$settingsDir = "$env:APPDATA\rancher-desktop"
$settingsFile = "$settingsDir\settings.json"
if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}
# Preserve existing settings but ensure dockerd engine
if (Test-Path $settingsFile) {
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        $settings.containerEngine.name = 'moby'
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        Write-Status "[OK]  Preserved settings with dockerd engine."
    } catch {
        # Corrupted settings file -- recreate
        @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } } |
            ConvertTo-Json -Depth 5 | Set-Content $settingsFile -Encoding UTF8
        Write-Status "[OK]  Reset settings to defaults (dockerd engine, no Kubernetes)."
    }
} else {
    @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } } |
        ConvertTo-Json -Depth 5 | Set-Content $settingsFile -Encoding UTF8
    Write-Status "[OK]  Created settings (dockerd engine, no Kubernetes)."
}

# --- Step 7: Restart Rancher Desktop ---
Write-Status ""
Write-Status "[...]  Starting Rancher Desktop (it will recreate fresh WSL distributions)..."

$rdExe = $null
if (Test-Path "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe") {
    $rdExe = "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe"
} elseif (Test-Path "$env:ProgramFiles\Rancher Desktop\Rancher Desktop.exe") {
    $rdExe = "$env:ProgramFiles\Rancher Desktop\Rancher Desktop.exe"
}

if (-not $rdExe) {
    Write-Status "[WARN] Could not find Rancher Desktop executable."
    Write-Status "       Open Rancher Desktop from the Start menu manually."
    exit 0
}

Start-Process $rdExe
Write-Status "[OK]  Rancher Desktop is starting."
Write-Status ""
Write-Status "       First-time setup after repair takes 2-5 minutes."
Write-Status "       Wait for the Rancher Desktop icon in your system tray"
Write-Status "       to show a green checkmark before using Docker."

# --- Step 8: Wait for Docker engine (up to 5 minutes) ---
Write-Status ""
Write-Status "[...]  Waiting for Docker engine..."
$maxWait = 60  # 60 x 5s = 5 minutes
for ($i = 1; $i -le $maxWait; $i++) {
    Start-Sleep -Seconds 5
    $dockerOk = $false
    try {
        $info = docker info 2>&1
        if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
    } catch {}
    if ($dockerOk) {
        Write-Status "[OK]  Docker engine is running. Repair complete!"
        exit 0
    }
    if ($i % 6 -eq 0) {
        $elapsed = $i * 5
        Write-Status "       Still waiting... ${elapsed}s"
    }
}

Write-Status ""
Write-Status "[WARN] Docker engine did not start within 5 minutes."
Write-Status "       This is normal for first-time setup after repair."
Write-Status "       Wait for Rancher Desktop to finish, then try again."
exit 2
