param($FreeBytes)
if ([long]$FreeBytes -lt 5368709120) {
    Write-Host '[WARN] Less than 5 GB free disk space. Docker build may fail.' -ForegroundColor Yellow
} else {
    Write-Host '[OK] Disk space is sufficient.' -ForegroundColor Green
}
