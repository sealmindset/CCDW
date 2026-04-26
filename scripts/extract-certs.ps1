param([string]$CertsDir)

if (-not (Test-Path $CertsDir)) { New-Item $CertsDir -ItemType Directory | Out-Null }

$patterns = @('Zscaler','Netskope','Palo Alto','GlobalProtect','Blue Coat','Forcepoint','Symantec Web','ContentKeeper')
$found = 0

foreach ($storePath in @('Cert:\LocalMachine\Root','Cert:\CurrentUser\Root','Cert:\LocalMachine\CA','Cert:\CurrentUser\CA')) {
    try {
        foreach ($cert in (Get-ChildItem $storePath -EA SilentlyContinue)) {
            $subj = $cert.Subject + ' ' + $cert.Issuer
            foreach ($p in $patterns) {
                if ($subj -match $p) {
                    $safeName = ($cert.Subject -replace 'CN=','') -replace '[^a-zA-Z0-9._-]','-'
                    $safeName = $safeName.Trim('-').ToLower()
                    $outPath = Join-Path $CertsDir ($safeName + '.crt')
                    if (-not (Test-Path $outPath)) {
                        $b64 = [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
                        $nl = [char]10
                        Set-Content $outPath ('-----BEGIN CERTIFICATE-----' + $nl + $b64 + $nl + '-----END CERTIFICATE-----')
                        Write-Host ('[OK] Exported: ' + $cert.Subject) -ForegroundColor Green
                        $found++
                    }
                    break
                }
            }
        }
    } catch {}
}

if ($found -eq 0) {
    Write-Host '[OK] No SSL proxy certs found -- not behind an inspection proxy' -ForegroundColor Green
} else {
    Write-Host ('[OK] Exported ' + $found + ' proxy certs to certs/') -ForegroundColor Green
}
