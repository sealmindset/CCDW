# =============================================================================
# Claude Code Docker — One-Line Bootstrap (Windows) — Public Edition
#
# Usage:
#   Set-ExecutionPolicy -Scope Process Bypass
#   irm https://raw.githubusercontent.com/sealmindset/CCDW/main/seal_bootstrap.ps1 | iex
#
# This downloads the full installer and runs it.
# Everything else (Rancher Desktop, Docker, configuration) is automatic.
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Blue
Write-Host "    Claude Code - One-Line Installer" -ForegroundColor Blue
Write-Host "  ========================================" -ForegroundColor Blue
Write-Host ""

# ---------------------------------------------------------------------------
# Connectivity check
# ---------------------------------------------------------------------------
Write-Host "[...]  Checking network..." -ForegroundColor Yellow
try {
    $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "[OK]   Internet connected." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] No internet connection." -ForegroundColor Red
    Write-Host "  Check your Wi-Fi and try again."
    exit 1
}

# ---------------------------------------------------------------------------
# Determine install location
# ---------------------------------------------------------------------------
$InstallDir = Join-Path $env:USERPROFILE "Documents\CCDW"
$SetupScript = Join-Path $InstallDir "seal_setup-claude.bat"

# ---------------------------------------------------------------------------
# Download repo
# ---------------------------------------------------------------------------
if (Test-Path $SetupScript) {
    Write-Host "[OK]   Found existing install at $InstallDir" -ForegroundColor Green
    Write-Host "[...]  Updating..." -ForegroundColor Yellow
    Push-Location $InstallDir
    try { git pull 2>$null } catch {}
    Pop-Location
} else {
    Write-Host "[...]  Downloading Claude Code Docker..." -ForegroundColor Yellow

    $CloneOk = $false

    # Strategy 1: git clone
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            git clone "https://github.com/sealmindset/CCDW.git" $InstallDir 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK]   Downloaded via git." -ForegroundColor Green
                $CloneOk = $true
            }
        } catch {}
    }

    # Strategy 2: ZIP fallback
    if (-not $CloneOk) {
        Write-Host "[...]  Trying ZIP download..." -ForegroundColor Yellow
        $ZipPath = Join-Path $env:TEMP "CCDW.zip"
        $ExtractPath = Join-Path $env:TEMP "CCDW-extract"
        try {
            Invoke-WebRequest -Uri "https://github.com/sealmindset/CCDW/archive/refs/heads/main.zip" `
                -OutFile $ZipPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

            if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }
            Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force

            if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
            Move-Item (Join-Path $ExtractPath "CCDW-main") $InstallDir

            Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK]   Downloaded via ZIP." -ForegroundColor Green
            $CloneOk = $true
        } catch {
            Write-Host "[WARN] ZIP download failed." -ForegroundColor Yellow
            Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $CloneOk) {
        Write-Host "[ERROR] Could not download Claude Code Docker." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Check:"
        Write-Host "    1. Your internet connection is working"
        Write-Host "    2. You can access github.com in a browser"
        Write-Host ""
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Run setup
# ---------------------------------------------------------------------------
if (-not (Test-Path $SetupScript)) {
    Write-Host "[ERROR] Setup script not found: $SetupScript" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK]   Starting setup..." -ForegroundColor Green
Write-Host ""

# Run the batch file in the current window
Push-Location $InstallDir
& cmd.exe /c $SetupScript
Pop-Location
