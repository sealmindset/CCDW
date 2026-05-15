param($ProjectDir, $IcoPath)
$projDir = $ProjectDir.TrimEnd('\')
$vbsPath = Join-Path $projDir 'launch-claude.vbs'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'Claude.lnk'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = $vbsPath
$lnk.WorkingDirectory = $projDir
$lnk.Description = 'Start Claude Code Docker and open in browser'
if (Test-Path $IcoPath) { $lnk.IconLocation = $IcoPath + ',0' }
else { $lnk.IconLocation = 'shell32.dll,14' }
$lnk.Save()
Write-Host '[OK] Claude shortcut added to your desktop.' -ForegroundColor Green
