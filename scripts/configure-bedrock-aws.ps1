param($ConfigFile)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
if (-not $cfg.sso_start_url -or -not $cfg.account_id -or -not $cfg.role_name) {
    Write-Host '[INFO] Bedrock SSO not fully configured -- edit config\bedrock.json'
    exit 0
}
$awsDir = Join-Path $env:USERPROFILE '.aws'
if (-not (Test-Path $awsDir)) { New-Item $awsDir -ItemType Directory | Out-Null }
$cfgPath = Join-Path $awsDir 'config'
$profile = if ($cfg.profile_name) { $cfg.profile_name } else { 'sso-bedrock' }
$session = 'aws-sso'
$existing = ''; if (Test-Path $cfgPath) { $existing = Get-Content $cfgPath -Raw }
$out = @(); $skip = $false
foreach ($line in $existing -split "`n") {
    if ($line -match ('^\[(sso-session\s+' + [regex]::Escape($session) + '|profile\s+' + [regex]::Escape($profile) + ')\]')) { $skip = $true }
    elseif ($line -match '^\[') { $skip = $false }
    if (-not $skip) { $out += $line }
}
$ssoRegion = if ($cfg.sso_region) { $cfg.sso_region } else { 'us-east-1' }
$region = if ($cfg.region) { $cfg.region } else { 'us-east-1' }
$out += ''
$out += "[sso-session $session]"
$out += "sso_start_url = $($cfg.sso_start_url)"
$out += "sso_region = $ssoRegion"
$out += 'sso_registration_scopes = sso:account:access'
$out += ''
$out += "[profile $profile]"
$out += "sso_session = $session"
$out += "sso_account_id = $($cfg.account_id)"
$out += "sso_role_name = $($cfg.role_name)"
$out += "region = $region"
$out += 'output = json'
$out -join "`n" | Set-Content $cfgPath -NoNewline
Write-Host "[OK] AWS config written to $cfgPath"
