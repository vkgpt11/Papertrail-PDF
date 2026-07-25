Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'assets\branding'
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

function New-PapertrailIcon([int]$size, [string]$outputPath) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(91, 91, 214))

    $scale = $size / 1024.0
    $page = New-Object System.Drawing.Drawing2D.GraphicsPath
    $page.AddPolygon([System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(286*$scale, 190*$scale),
        [System.Drawing.PointF]::new(604*$scale, 190*$scale),
        [System.Drawing.PointF]::new(758*$scale, 344*$scale),
        [System.Drawing.PointF]::new(758*$scale, 834*$scale),
        [System.Drawing.PointF]::new(286*$scale, 834*$scale)
    ))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $graphics.FillPath($white, $page)

    $fold = New-Object System.Drawing.Drawing2D.GraphicsPath
    $fold.AddPolygon([System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(604*$scale, 190*$scale),
        [System.Drawing.PointF]::new(758*$scale, 344*$scale),
        [System.Drawing.PointF]::new(604*$scale, 344*$scale)
    ))
    $foldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(208, 208, 255))
    $graphics.FillPath($foldBrush, $fold)

    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(91, 91, 214), [single](38*$scale))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($pen, 390*$scale, 486*$scale, 654*$scale, 486*$scale)
    $graphics.DrawLine($pen, 390*$scale, 596*$scale, 654*$scale, 596*$scale)
    $graphics.DrawLine($pen, 390*$scale, 706*$scale, 570*$scale, 706*$scale)

    $directory = Split-Path -Parent $outputPath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $foldBrush.Dispose(); $white.Dispose(); $page.Dispose(); $fold.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}

$source = Join-Path $sourceDir 'papertrail-icon-1024.png'
New-PapertrailIcon 1024 $source

$androidIcons = @{
    48='mipmap-mdpi'; 72='mipmap-hdpi'; 96='mipmap-xhdpi'; 144='mipmap-xxhdpi'; 192='mipmap-xxxhdpi'
}
foreach ($entry in $androidIcons.GetEnumerator()) {
    $path = Join-Path $projectRoot "android\app\src\main\res\$($entry.Value)\ic_launcher.png"
    New-PapertrailIcon $entry.Key $path
}

$iosDir = Join-Path $projectRoot 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
$iosIcons = @{
    'Icon-App-20x20@1x.png'=20; 'Icon-App-20x20@2x.png'=40; 'Icon-App-20x20@3x.png'=60;
    'Icon-App-29x29@1x.png'=29; 'Icon-App-29x29@2x.png'=58; 'Icon-App-29x29@3x.png'=87;
    'Icon-App-40x40@1x.png'=40; 'Icon-App-40x40@2x.png'=80; 'Icon-App-40x40@3x.png'=120;
    'Icon-App-60x60@2x.png'=120; 'Icon-App-60x60@3x.png'=180;
    'Icon-App-76x76@1x.png'=76; 'Icon-App-76x76@2x.png'=152;
    'Icon-App-83.5x83.5@2x.png'=167; 'Icon-App-1024x1024@1x.png'=1024
}
foreach ($entry in $iosIcons.GetEnumerator()) {
    New-PapertrailIcon $entry.Value (Join-Path $iosDir $entry.Key)
}

Write-Output "Generated Papertrail icons from $source"
