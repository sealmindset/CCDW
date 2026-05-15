param($ConfigFile)
$cfg = Get-Content $ConfigFile | ConvertFrom-Json
$prereqs = $cfg.prereqs.host
if (-not $prereqs) { exit 0 }
$failCount = 0
foreach ($p in $prereqs) {
    $label = $p.label
    $check = $p.check
    $required = [bool]$p.required
    $failMsg = $p.fail_message
    if ($check -eq 'manual') {
        Write-Host ('  ? ' + $label + ' (verify manually)') -ForegroundColor Yellow
        if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow }
        continue
    }
    if ($check -eq 'info') {
        Write-Host ('  i ' + $label) -ForegroundColor Cyan
        if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor DarkGray }
        continue
    }
    try {
        $result = cmd /c $check 2>&1
        $expect = $p.expect
        if ($LASTEXITCODE -eq 0 -and (-not $expect -or ($result -join ' ') -match $expect)) {
            Write-Host ('  OK ' + $label) -ForegroundColor Green
        } else {
            Write-Host ('  X  ' + $label) -ForegroundColor Red
            if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow }
            if ($required) { $failCount++ }
        }
    } catch {
        Write-Host ('  X  ' + $label) -ForegroundColor Red
        if ($failMsg) { Write-Host ('    ' + $failMsg) -ForegroundColor Yellow }
        if ($required) { $failCount++ }
    }
}
if ($failCount -gt 0) { exit 1 } else { exit 0 }
