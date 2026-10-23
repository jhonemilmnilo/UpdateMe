const sharp = null;
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Use sharp or powershell script file
const script = `
Add-Type -AssemblyName System.Drawing
$srcPath = "C:\\Users\\Jhon Emil Nilo\\.gemini\\antigravity-ide\\brain\\a27b5fce-2676-4faa-9807-ebb283d5d5f8\\updateme_monogram_icon_1792724673587.jpg"
$src = [System.Drawing.Image]::FromFile($srcPath)
$sizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}
foreach ($entry in $sizes.GetEnumerator()) {
    $dir = "c:\\Users\\Jhon Emil Nilo\\Projects\\update_me\\android\\app\\src\\main\\res\\" + $entry.Key
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $target = Join-Path $dir "ic_launcher.png"
    $targetRound = Join-Path $dir "ic_launcher_round.png"
    $size = $entry.Value
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, 0, 0, $size, $size)
    $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Save($targetRound, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "Generated $target ($size x $size)"
}
$src.Dispose()
Write-Host "Icons generated successfully!"
`;

fs.writeFileSync('backend/scripts/generate-icons.ps1', script);
console.log('Script written.');
