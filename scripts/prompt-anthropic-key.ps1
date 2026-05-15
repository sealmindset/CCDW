param($ConfigFile)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
if (-not $cfg.api_key) {
    $key = Read-Host '  Anthropic API key (sk-ant-...)' -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($key))
    if ($plain) {
        $cfg.api_key = $plain
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        Write-Host '  [OK] API key saved'
    }
}
