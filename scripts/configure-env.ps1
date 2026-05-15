param($ConfigFile, $EnvFile)
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$envPath = $EnvFile

function Resolve-Template($val, $cfg) {
    if (-not $val) { return '' }
    [regex]::Replace([string]$val, '\{([^}]+)\}', {
        param($m)
        $keys = $m.Groups[1].Value -split '\.'
        $v = $cfg
        foreach ($k in $keys) {
            if ($v.PSObject.Properties[$k]) { $v = $v.$k } else { return '' }
        }
        return [string]$v
    })
}

$lines = @()
if (Test-Path $envPath) { $lines = @(Get-Content $envPath) }

$commentKeys = @('ANTHROPIC_API_KEY','CLAUDE_CODE_USE_FOUNDRY','ANTHROPIC_FOUNDRY_BASE_URL',
    'ANTHROPIC_FOUNDRY_API_KEY','CLAUDE_CODE_USE_BEDROCK','AWS_PROFILE','AWS_REGION',
    'ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL','DISABLE_PROMPT_CACHING')

for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    if ($t -and -not $t.StartsWith('#')) {
        $eq = $t.IndexOf('=')
        if ($eq -gt 0) {
            $k = $t.Substring(0, $eq).Trim()
            if ($commentKeys -contains $k) { $lines[$i] = '# ' + $lines[$i] }
        }
    }
}

$allVars = @{}
if ($cfg.env_vars) {
    $cfg.env_vars.PSObject.Properties | ForEach-Object { $allVars[$_.Name] = $_.Value }
}
if ($cfg.env_vars_optional) {
    $cfg.env_vars_optional.PSObject.Properties | ForEach-Object { $allVars[$_.Name] = $_.Value }
}

foreach ($entry in $allVars.GetEnumerator()) {
    $key = $entry.Key
    $val = Resolve-Template $entry.Value $cfg
    if (-not $val -and $cfg.env_vars_optional -and $cfg.env_vars_optional.PSObject.Properties[$key]) { continue }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i] -replace '^#+\s*',''
        $eq = $raw.IndexOf('=')
        if ($eq -gt 0 -and $raw.Substring(0,$eq).Trim() -eq $key) {
            $lines[$i] = $key + '=' + $val
            $found = $true; break
        }
    }
    if (-not $found) { $lines += ($key + '=' + $val) }
}

$lines -join "`r`n" | Set-Content $envPath -NoNewline
Write-Host ('[OK] ' + $cfg.display_name + ' configured in .env')
