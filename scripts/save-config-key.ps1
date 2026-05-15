param($ConfigFile, $ApiKey, $AuthMode)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$cfg.api_key = $ApiKey
if ($AuthMode) { $cfg.auth_mode = $AuthMode }
$cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
