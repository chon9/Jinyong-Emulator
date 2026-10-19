$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$youxiaRoot = Split-Path -Parent $PSScriptRoot
$youxiaSizes = @(16,32,48,64,128,256)
$youxiaImages = @()
foreach ($youxiaSize in $youxiaSizes) {
    $youxiaBitmap = [System.Drawing.Bitmap]::new($youxiaSize,$youxiaSize)
    $youxiaGraphics = [System.Drawing.Graphics]::FromImage($youxiaBitmap)
    $youxiaGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $youxiaGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $youxiaGraphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#111b21'))
    $youxiaGold = [System.Drawing.ColorTranslator]::FromHtml('#d7bb7d')
    $youxiaPen = [System.Drawing.Pen]::new($youxiaGold,[single]([Math]::Max(1,$youxiaSize * 6 / 256)))
    $youxiaInset = [single]($youxiaSize * 15 / 256)
    $youxiaGraphics.DrawRectangle($youxiaPen,$youxiaInset,$youxiaInset,[single]($youxiaSize - $youxiaInset * 2),[single]($youxiaSize - $youxiaInset * 2))
    $youxiaBrush = [System.Drawing.SolidBrush]::new($youxiaGold)
    $youxiaFont = [System.Drawing.Font]::new('Microsoft JhengHei',[single]($youxiaSize * 143 / 256),[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
    $youxiaFormat = [System.Drawing.StringFormat]::new()
    $youxiaFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $youxiaFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
    $youxiaGraphics.DrawString('俠',$youxiaFont,$youxiaBrush,[System.Drawing.RectangleF]::new(0,0,$youxiaSize,[single]($youxiaSize * 250 / 256)),$youxiaFormat)
    $youxiaMemory = [System.IO.MemoryStream]::new()
    $youxiaBitmap.Save($youxiaMemory,[System.Drawing.Imaging.ImageFormat]::Png)
    $youxiaImages += ,$youxiaMemory.ToArray()
    $youxiaMemory.Dispose()
    $youxiaFormat.Dispose()
    $youxiaFont.Dispose()
    $youxiaBrush.Dispose()
    $youxiaPen.Dispose()
    $youxiaGraphics.Dispose()
    $youxiaBitmap.Dispose()
}
New-Item -ItemType Directory -Path (Join-Path $youxiaRoot 'assets') -Force | Out-Null
$youxiaWriter = [System.IO.BinaryWriter]::new([System.IO.File]::Create((Join-Path $youxiaRoot 'assets\icon.ico')))
try {
    $youxiaWriter.Write([uint16]0)
    $youxiaWriter.Write([uint16]1)
    $youxiaWriter.Write([uint16]$youxiaSizes.Count)
    $youxiaOffset = 6 + 16 * $youxiaSizes.Count
    for ($youxiaIndex = 0; $youxiaIndex -lt $youxiaSizes.Count; $youxiaIndex++) {
        $youxiaEncodedSize = [byte]($youxiaSizes[$youxiaIndex] % 256)
        $youxiaWriter.Write($youxiaEncodedSize)
        $youxiaWriter.Write($youxiaEncodedSize)
        $youxiaWriter.Write([byte]0)
        $youxiaWriter.Write([byte]0)
        $youxiaWriter.Write([uint16]1)
        $youxiaWriter.Write([uint16]32)
        $youxiaWriter.Write([uint32]$youxiaImages[$youxiaIndex].Length)
        $youxiaWriter.Write([uint32]$youxiaOffset)
        $youxiaOffset += $youxiaImages[$youxiaIndex].Length
    }
    foreach ($youxiaImage in $youxiaImages) { $youxiaWriter.Write([byte[]]$youxiaImage) }
} finally { $youxiaWriter.Dispose() }
