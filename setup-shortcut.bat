@echo off
setlocal EnableDelayedExpansion
REM ---------------------------------------------------------------------------
REM Setup Claude desktop shortcut (standalone)
REM Removes Rancher Desktop shortcut, creates Claude launcher with branded icon.
REM ---------------------------------------------------------------------------

echo.
echo [...]  Setting up desktop shortcut...

REM Clean up unwanted desktop shortcuts
powershell -NoProfile -Command ^
    "$desktop = [Environment]::GetFolderPath('Desktop'); " ^
    "$pub = [Environment]::GetFolderPath('CommonDesktopDirectory'); " ^
    "foreach ($d in @($desktop, $pub)) { " ^
    "  foreach ($name in @('Rancher Desktop.lnk','Claude Code.url')) { " ^
    "    $p = Join-Path $d $name; " ^
    "    if (Test-Path $p) { Remove-Item $p -Force -EA SilentlyContinue; if (-not (Test-Path $p)) { Write-Host ('       Removed: ' + $name) } } " ^
    "  } " ^
    "}"

REM Generate Claude icon (terracotta circle with white C)
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Drawing; " ^
    "$sz = 64; " ^
    "$bmp = New-Object System.Drawing.Bitmap $sz,$sz; " ^
    "$g = [System.Drawing.Graphics]::FromImage($bmp); " ^
    "$g.SmoothingMode = 'AntiAlias'; " ^
    "$g.Clear([System.Drawing.Color]::Transparent); " ^
    "$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(217,119,87)); " ^
    "$g.FillEllipse($brush, 2, 2, ($sz-4), ($sz-4)); " ^
    "$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White); " ^
    "$font = New-Object System.Drawing.Font('Segoe UI',28,[System.Drawing.FontStyle]::Bold); " ^
    "$sf = New-Object System.Drawing.StringFormat; " ^
    "$sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'; " ^
    "$rect = New-Object System.Drawing.RectangleF(0,0,$sz,$sz); " ^
    "$g.DrawString('C',$font,$white,$rect,$sf); " ^
    "$g.Dispose(); " ^
    "$ico = Join-Path '%~dp0' 'claude.ico'; " ^
    "$ms = New-Object System.IO.MemoryStream; " ^
    "$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); " ^
    "$png = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose(); " ^
    "$fs = [System.IO.File]::Create($ico); " ^
    "$bw = New-Object System.IO.BinaryWriter($fs); " ^
    "$bw.Write([Int16]0); $bw.Write([Int16]1); $bw.Write([Int16]1); " ^
    "$bw.Write([byte]$sz); $bw.Write([byte]$sz); $bw.Write([byte]0); " ^
    "$bw.Write([byte]0); $bw.Write([Int16]1); $bw.Write([Int16]32); " ^
    "$bw.Write([int]$png.Length); $bw.Write([int]22); " ^
    "$bw.Write($png); $bw.Close(); $fs.Close()"

REM Create desktop shortcut
powershell -NoProfile -Command ^
    "$projDir = '%~dp0'.TrimEnd('\'); " ^
    "$vbsPath = Join-Path $projDir 'launch-claude.vbs'; " ^
    "$icoPath = Join-Path $projDir 'claude.ico'; " ^
    "$desktop = [Environment]::GetFolderPath('Desktop'); " ^
    "$lnkPath = Join-Path $desktop 'Claude.lnk'; " ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$lnk = $ws.CreateShortcut($lnkPath); " ^
    "$lnk.TargetPath = $vbsPath; " ^
    "$lnk.WorkingDirectory = $projDir; " ^
    "$lnk.Description = 'Start Claude Code Docker and open in browser'; " ^
    "if (Test-Path $icoPath) { $lnk.IconLocation = $icoPath + ',0' } " ^
    "else { $lnk.IconLocation = 'shell32.dll,14' }; " ^
    "$lnk.Save(); " ^
    "Write-Host '[OK] Claude shortcut added to your desktop.' -ForegroundColor Green"

echo.
echo Done.
endlocal
