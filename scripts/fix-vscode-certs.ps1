#Requires -Version 5.1
<#
.SYNOPSIS
    Fix VSCode extension certificate errors caused by SSL inspection proxies.
.DESCRIPTION
    Fixes UNKNOWN_CERTIFICATE_VERIFICATION_ERROR in VSCode extensions
    (Claude, GitHub Copilot, etc.) caused by SSL inspection proxies
    (Zscaler, Netskope, Palo Alto GlobalProtect, etc.)

    Steps:
    1. Finds SSL inspection proxy root CAs in Windows certificate store
    2. Exports them to %USERPROFILE%\.ssl-proxy-certs\proxy-ca-bundle.pem
    3. Sets NODE_EXTRA_CA_CERTS as persistent user environment variable
    4. Optionally patches VSCode settings.json

.PARAMETER Check
    Show current certificate configuration status.
.PARAMETER PatchVSCode
    Also patch VSCode settings.json with terminal env var.
.PARAMETER QuickFix
    Just disable http.proxyStrictSSL in VSCode (fast workaround, less secure).

.EXAMPLE
    .\fix-vscode-certs.ps1                  # Auto-detect and fix
    .\fix-vscode-certs.ps1 -Check           # Check status
    .\fix-vscode-certs.ps1 -PatchVSCode     # Fix + patch VSCode settings
    .\fix-vscode-certs.ps1 -QuickFix        # Disable strict SSL (workaround)
#>

param(
    [switch]$Check,
    [switch]$PatchVSCode,
    [switch]$QuickFix
)

$ErrorActionPreference = "Stop"
$CertDir = Join-Path $env:USERPROFILE ".ssl-proxy-certs"
$CertFile = Join-Path $CertDir "proxy-ca-bundle.pem"

# SSL inspection proxy patterns to search for
$ProxyPatterns = @('Zscaler','Netskope','Palo Alto','GlobalProtect','Blue Coat','Forcepoint','Symantec Web','ContentKeeper')

function Write-OK   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "       $msg" }

function Get-VSCodeSettingsPath {
    return Join-Path $env:APPDATA "Code\User\settings.json"
}

# ---------------------------------------------------------------------------
# Quick fix
# ---------------------------------------------------------------------------

if ($QuickFix) {
    Write-Host ""
    Write-Host "=== Quick Fix: Disable SSL Strict Verification ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Warn "This disables certificate verification in VSCode — use as a temporary workaround."
    Write-Info "Run without -QuickFix to properly install proxy certificates instead."
    Write-Host ""

    $vsSettings = Get-VSCodeSettingsPath
    if (-not (Test-Path $vsSettings)) {
        $vsDir = Split-Path $vsSettings
        if (-not (Test-Path $vsDir)) { New-Item -ItemType Directory -Path $vsDir -Force | Out-Null }
        Set-Content -Path $vsSettings -Value "{}" -Encoding UTF8
    }

    $settings = Get-Content $vsSettings -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName 'http.proxyStrictSSL' -NotePropertyValue $false -Force
    $settings | ConvertTo-Json -Depth 10 | Set-Content $vsSettings -Encoding UTF8
    Write-OK "Set http.proxyStrictSSL = false in VSCode settings"
    Write-Host ""
    Write-Info "Restart VSCode for this to take effect."
    Write-Info "To undo: VSCode Settings -> search 'proxy strict ssl' -> check the box"
    Write-Host ""
    exit 0
}

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------

if ($Check) {
    Write-Host ""
    Write-Host "=== SSL Proxy Certificate Status ===" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $CertFile) {
        Write-OK "Proxy CA bundle: $CertFile"
        $certCount = (Select-String -Path $CertFile -Pattern "BEGIN CERTIFICATE" -AllMatches).Matches.Count
        Write-Info "Contains $certCount certificate(s)"
    } else {
        Write-Warn "No proxy CA bundle at $CertFile"
    }

    $envUser = [Environment]::GetEnvironmentVariable("NODE_EXTRA_CA_CERTS", "User")
    if ($envUser) {
        Write-OK "NODE_EXTRA_CA_CERTS (User env): $envUser"
    } else {
        Write-Warn "NODE_EXTRA_CA_CERTS not set as user environment variable"
    }

    if ($env:NODE_EXTRA_CA_CERTS) {
        Write-OK "NODE_EXTRA_CA_CERTS (Session): $env:NODE_EXTRA_CA_CERTS"
    } else {
        Write-Warn "NODE_EXTRA_CA_CERTS not set in current session"
    }

    Write-Host ""
    $vsSettings = Get-VSCodeSettingsPath
    if (Test-Path $vsSettings) {
        try {
            $s = Get-Content $vsSettings -Raw | ConvertFrom-Json
            $sslVal = if ($s.'http.proxyStrictSSL' -ne $null) { $s.'http.proxyStrictSSL' } else { "not set" }
            Write-Info "VSCode http.proxyStrictSSL: $sslVal"
        } catch {
            Write-Info "VSCode settings.json: parse error"
        }
    } else {
        Write-Info "VSCode settings.json not found"
    }

    Write-Host ""
    # Find proxy certs in store
    $found = $false
    foreach ($storePath in @('Cert:\LocalMachine\Root','Cert:\CurrentUser\Root')) {
        foreach ($pattern in $ProxyPatterns) {
            $certs = Get-ChildItem $storePath -ErrorAction SilentlyContinue | Where-Object { $_.Subject -like "*$pattern*" }
            foreach ($cert in $certs) {
                Write-OK "Proxy cert in store: $($cert.Subject) (Expires: $($cert.NotAfter))"
                $found = $true
            }
        }
    }
    if (-not $found) {
        Write-Info "No proxy certificates found in Windows certificate store"
    }

    Write-Host ""
    exit 0
}

# ---------------------------------------------------------------------------
# Step 1: Find proxy certificates
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== VSCode Certificate Fix ===" -ForegroundColor Cyan
Write-Host ""

$FoundCerts = @()

foreach ($storePath in @('Cert:\LocalMachine\Root','Cert:\CurrentUser\Root','Cert:\LocalMachine\CA','Cert:\CurrentUser\CA')) {
    try {
        foreach ($cert in (Get-ChildItem $storePath -ErrorAction SilentlyContinue)) {
            $subj = $cert.Subject + ' ' + $cert.Issuer
            foreach ($pattern in $ProxyPatterns) {
                if ($subj -match $pattern) {
                    $FoundCerts += $cert
                    break
                }
            }
        }
    } catch {}
}

if ($FoundCerts.Count -eq 0) {
    Write-Warn "No SSL inspection proxy certificates found in certificate store."
    Write-Info "Check: certmgr.msc -> Trusted Root Certification Authorities -> Certificates"
    Write-Host ""
    $yn = Read-Host "Continue anyway? [y/N]"
    if ($yn -ne 'y' -and $yn -ne 'Y') { exit 0 }
} else {
    Write-OK "Found $($FoundCerts.Count) proxy certificate(s)"
}

# ---------------------------------------------------------------------------
# Step 2: Export as PEM bundle
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Exporting proxy root CA certificates..."

if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

$nl = [char]10
$pemContent = ""
$exported = 0

foreach ($cert in $FoundCerts) {
    $b64 = [Convert]::ToBase64String($cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
    $pemContent += "-----BEGIN CERTIFICATE-----" + $nl + $b64 + $nl + "-----END CERTIFICATE-----" + $nl
    Write-Info "  Exported: $($cert.Subject)"
    $exported++
}

Set-Content -Path $CertFile -Value $pemContent -Encoding ASCII -NoNewline
Write-OK "Exported $exported certificate(s) to $CertFile"

# ---------------------------------------------------------------------------
# Step 3: Set NODE_EXTRA_CA_CERTS
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Setting NODE_EXTRA_CA_CERTS..."

[Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $CertFile, "User")
$env:NODE_EXTRA_CA_CERTS = $CertFile

Write-OK "NODE_EXTRA_CA_CERTS set to $CertFile (persistent user env var)"

# ---------------------------------------------------------------------------
# Step 4: Patch VSCode settings (optional)
# ---------------------------------------------------------------------------

if ($PatchVSCode) {
    Write-Host ""
    Write-Host "Patching VSCode settings..."

    $vsSettings = Get-VSCodeSettingsPath
    if (-not (Test-Path $vsSettings)) {
        $vsDir = Split-Path $vsSettings
        if (-not (Test-Path $vsDir)) { New-Item -ItemType Directory -Path $vsDir -Force | Out-Null }
        Set-Content -Path $vsSettings -Value "{}" -Encoding UTF8
    }

    try {
        $settings = Get-Content $vsSettings -Raw | ConvertFrom-Json

        # Terminal env var
        if (-not $settings.'terminal.integrated.env.windows') {
            $settings | Add-Member -NotePropertyName 'terminal.integrated.env.windows' -NotePropertyValue @{} -Force
        }
        $settings.'terminal.integrated.env.windows' | Add-Member -NotePropertyName 'NODE_EXTRA_CA_CERTS' -NotePropertyValue $CertFile -Force

        # Keep proxyStrictSSL true (we have the cert now)
        if ($settings.'http.proxyStrictSSL' -eq $null) {
            $settings | Add-Member -NotePropertyName 'http.proxyStrictSSL' -NotePropertyValue $true -Force
        }

        $settings | ConvertTo-Json -Depth 10 | Set-Content $vsSettings -Encoding UTF8
        Write-OK "VSCode settings updated"
    } catch {
        Write-Warn "Could not patch VSCode settings: $_"
    }
}

# ---------------------------------------------------------------------------
# Step 5: Verify
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Verification ===" -ForegroundColor Cyan

$nodePath = Get-Command node -ErrorAction SilentlyContinue
if ($nodePath) {
    try {
        $env:NODE_EXTRA_CA_CERTS = $CertFile
        $result = node -e @"
const https = require('https');
const req = https.get('https://api.anthropic.com', {timeout: 5000}, (res) => {
    console.log('OK:' + res.statusCode);
    process.exit(0);
});
req.on('error', (e) => { console.log('FAIL:' + e.code); process.exit(1); });
req.on('timeout', () => { console.log('FAIL:TIMEOUT'); req.destroy(); process.exit(1); });
"@ 2>&1

        if ($result -match "OK:") {
            Write-OK "Node.js connects to api.anthropic.com with proxy CA -- certificate fix working"
        } else {
            Write-Warn "Connection test: $result"
            Write-Info "Try the quick-fix as a workaround: .\fix-vscode-certs.ps1 -QuickFix"
        }
    } catch {
        Write-Warn "Connection test failed: $_"
    }
} else {
    Write-Warn "Node.js not found -- skipping connection test"
}

Write-Host ""
Write-OK "Done! Restart VSCode for changes to take effect."
Write-Host ""
Write-Host "  If you still see UNKNOWN_CERTIFICATE_VERIFICATION_ERROR:" -ForegroundColor Yellow
Write-Host "    1. Fully quit and reopen VSCode (not just reload window)"
Write-Host '    2. Verify: echo $env:NODE_EXTRA_CA_CERTS'
Write-Host "    3. Quick workaround: .\fix-vscode-certs.ps1 -QuickFix"
Write-Host ""
