param($OutputPath)
Add-Type -AssemblyName System.Drawing
$sz = 64
$bmp = New-Object System.Drawing.Bitmap $sz,$sz
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(217,119,87))
$g.FillEllipse($brush, 2, 2, ($sz-4), ($sz-4))
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font('Segoe UI',28,[System.Drawing.FontStyle]::Bold)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
$rect = New-Object System.Drawing.RectangleF(0,0,$sz,$sz)
$g.DrawString('C',$font,$white,$rect,$sf)
$g.Dispose()
$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose()
$fs = [System.IO.File]::Create($OutputPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([Int16]0); $bw.Write([Int16]1); $bw.Write([Int16]1)
$bw.Write([byte]$sz); $bw.Write([byte]$sz); $bw.Write([byte]0)
$bw.Write([byte]0); $bw.Write([Int16]1); $bw.Write([Int16]32)
$bw.Write([int]$png.Length); $bw.Write([int]22)
$bw.Write($png); $bw.Close(); $fs.Close()
