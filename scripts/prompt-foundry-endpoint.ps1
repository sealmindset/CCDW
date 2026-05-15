param($ConfigFile)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
if (-not $cfg.endpoint) {
    $ep = Read-Host '  Foundry endpoint URL'
    if ($ep) {
        $cfg.endpoint = $ep
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        Write-Host '  [OK] Endpoint saved'
    }
}
