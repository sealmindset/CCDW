param($OutputPath)
$ProgressPreference = 'SilentlyContinue'
try {
    $headers = @{}
    $rel = Invoke-RestMethod 'https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest' -Headers $headers -TimeoutSec 20
    $msi = $rel.assets | Where-Object { $_.name -like 'Rancher.Desktop.Setup*.msi' -and $_.name -notlike '*.sha512*' } | Select-Object -First 1
    if (-not $msi) { Write-Host 'No MSI found in latest release'; exit 1 }
    Write-Host ('Downloading ' + $msi.name + ' (' + [math]::Round($msi.size/1MB,1) + ' MB)...')
    Invoke-WebRequest $msi.browser_download_url -OutFile $OutputPath -UseBasicParsing
    if ((Get-Item $OutputPath).Length -lt 1MB) { Write-Host 'Download too small -- likely blocked'; exit 1 }
    exit 0
} catch {
    Write-Host ('Download failed: ' + $_.Exception.Message)
    exit 1
}
