$p = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
if ($p.VirtualizationFirmwareEnabled -eq $true) { exit 0 }
elseif ($p.VirtualizationFirmwareEnabled -eq $false) { exit 1 }
else { exit 0 }
