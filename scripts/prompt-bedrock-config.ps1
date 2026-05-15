param($ConfigFile)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
if (-not $cfg.sso_start_url) {
    $sso = Read-Host '  AWS SSO Start URL (https://d-xxx.awsapps.com/start)'
    $acct = Read-Host '  AWS Account ID'
    $role = Read-Host '  SSO Role Name'
    $rgn = Read-Host '  Bedrock Region [us-east-1]'
    if (-not $rgn) { $rgn = 'us-east-1' }
    $cfg.sso_start_url = $sso
    $cfg.account_id = $acct
    $cfg.role_name = $role
    $cfg.region = $rgn
    $cfg.sso_region = $rgn
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
    Write-Host '  [OK] Bedrock SSO config saved'
}
Write-Host '  Note: AWS SSO sign-in will happen after the container starts.' -ForegroundColor Cyan
