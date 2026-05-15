param([switch]$Detail)
$ports = @(3000,7681,7682,8080,9200)
if ($Detail) {
    foreach ($p in $ports) {
        try {
            $conn = Get-NetTCPConnection -LocalPort $p -State Listen -EA Stop
            $proc = Get-Process -Id $conn[0].OwningProcess -EA Stop
            Write-Host ('   Port ' + $p + ' is used by: ' + $proc.ProcessName) -ForegroundColor Yellow
        } catch { }
    }
} else {
    $conflicts = @()
    foreach ($p in $ports) {
        $r = netstat -ano 2>$null | Select-String (":${p}\s.*LISTENING")
        if ($r) { $conflicts += $p }
    }
    if ($conflicts.Count -gt 0) {
        foreach ($p in $conflicts) { Write-Host "[WARN] Port $p is already in use." -ForegroundColor Yellow }
        exit 1
    } else { exit 0 }
}
