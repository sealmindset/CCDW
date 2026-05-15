foreach ($loc in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)) {
    foreach ($x in (Get-ItemProperty $loc -EA 0)) {
        if ($x.DisplayName -like '*Rancher Desktop*' -and $x.InstallLocation) {
            $d = Join-Path $x.InstallLocation 'resources\resources\win32\bin\docker.exe'
            if (Test-Path $d) { $d; exit }
        }
    }
}
