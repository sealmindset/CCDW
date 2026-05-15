$desktop = [Environment]::GetFolderPath('Desktop')
$pub = [Environment]::GetFolderPath('CommonDesktopDirectory')
foreach ($d in @($desktop, $pub)) {
    foreach ($name in @('Rancher Desktop.lnk','Claude Code.url')) {
        $p = Join-Path $d $name
        if (Test-Path $p) { Remove-Item $p -Force -EA SilentlyContinue }
    }
}
