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

# --- Step 1: Detect all WSL distros Rancher Desktop depends on ---
$distroList = wsl -l -q 2>&1 | ForEach-Object { $_ -replace '\x00','' } | Where-Object { $_.Trim() -ne '' }
$hasRD      = $distroList | Where-Object { $_ -match '^rancher-desktop$' }
$hasRDData  = $distroList | Where-Object { $_ -match '^rancher-desktop-data$' }
$hasUbuntu  = $distroList | Where-Object { $_ -match '^Ubuntu$' }

if (-not $hasRD -and -not $hasRDData -and -not $hasUbuntu) {
    Write-Status "[OK]  No Rancher-related WSL distributions found -- nothing to repair."
    exit 1
}

# --- Step 2: Test if the distros are healthy ---
# Rancher Desktop uses three distros: rancher-desktop, rancher-desktop-data, and Ubuntu.
# Ubuntu is used for docker-plugins and kubeconfig integration.
$healthy = $true
$corruptedDistros = @()

if ($hasRD) {
    $testOut = wsl -d rancher-desktop -- echo ok 2>&1
    if ($LASTEXITCODE -ne 0 -or $testOut -notmatch 'ok') {
        $healthy = $false
        $corruptedDistros += 'rancher-desktop'
        Write-Status "[FAIL] rancher-desktop distro is not responding."
    } else {
        Write-Status "[OK]  rancher-desktop distro is healthy."
    }
}
if ($hasUbuntu) {
    $testOut = wsl -d Ubuntu -- echo ok 2>&1
    if ($LASTEXITCODE -ne 0 -or $testOut -notmatch 'ok') {
        $healthy = $false
        $corruptedDistros += 'Ubuntu'
        Write-Status "[FAIL] Ubuntu distro is not responding (used by Rancher for docker-plugins)."
    } else {
        Write-Status "[OK]  Ubuntu distro is healthy."
    }
}
if ($hasRDData) {
    $statusOut = wsl -l -v 2>&1 | ForEach-Object { $_ -replace '\x00','' }
    $dataLine = $statusOut | Where-Object { $_ -match 'rancher-desktop-data' }
    if ($dataLine -match 'Stopped|Running') {
        Write-Status "[OK]  rancher-desktop-data distro is present."
    }
}

if ($healthy -and -not $DiagOnly) {
    Write-Status "[OK]  All WSL distributions appear healthy."
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
        Write-Status "  Result: All distributions look healthy."
    } else {
        Write-Status "  Result: Corrupted: $($corruptedDistros -join ', ')"
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
# Unregister ALL three if any are corrupted -- Rancher Desktop needs a clean slate.
# Even if only Ubuntu is broken, Rancher's docker-plugins and kubeconfig fail,
# so a full reset is the reliable fix.
foreach ($distro in @('rancher-desktop', 'rancher-desktop-data', 'Ubuntu')) {
    $present = $distroList | Where-Object { $_ -match "^${distro}$" }
    if ($present) {
        Write-Status "[...]  Removing $distro distribution..."
        wsl --unregister $distro 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "[OK]  $distro removed."
        } else {
            Write-Status "[WARN] Could not remove $distro (may already be gone)."
        }
    }
}

# --- Step 5b: Reinstall Ubuntu (Rancher needs it for docker-plugins/kubeconfig) ---
Write-Status "[...]  Reinstalling Ubuntu for WSL..."
wsl --install -d Ubuntu --no-launch 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Status "[OK]  Ubuntu reinstalled."
} else {
    # wsl --install sometimes returns non-zero even on success (Windows quirk)
    Write-Status "[WARN] Ubuntu install returned non-zero -- may still work after restart."
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
