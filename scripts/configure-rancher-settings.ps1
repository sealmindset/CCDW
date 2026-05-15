param($SettingsPath)
$s = @{ version = 10; containerEngine = @{ name = 'moby' }; kubernetes = @{ enabled = $false } }
$s | ConvertTo-Json -Depth 5 | Set-Content $SettingsPath -Encoding UTF8
