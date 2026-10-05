$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=$PSScriptRoot
$assets=Get-Content -LiteralPath (Join-Path $root 'assets-manifest.json') -Raw | ConvertFrom-Json -AsHashtable
$probe=[Drawing.Bitmap]::new((Join-Path $root 'assets\body-normal.png'));$full=($probe.Width -eq 1152 -and $probe.Height -eq 2048);$probe.Dispose();if(-not $full){throw 'Assets are already trimmed. Run prepare-assets.ps1 and add-symbols-and-review.ps1 before trimming again.'}
foreach($a in $assets) {
 $path=Join-Path $root $a.file;$b=[Drawing.Bitmap]::new($path)
 $left=$b.Width;$top=$b.Height;$right=-1;$bottom=-1
 $data=$b.LockBits([Drawing.Rectangle]::new(0,0,$b.Width,$b.Height),[Drawing.Imaging.ImageLockMode]::ReadOnly,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
 $pixels=[byte[]]::new($b.Width*$b.Height*4);[Runtime.InteropServices.Marshal]::Copy($data.Scan0,$pixels,0,$pixels.Length);$b.UnlockBits($data)
 for($y=0;$y -lt $b.Height;$y++) {for($x=0;$x -lt $b.Width;$x++){if($pixels[($y*$b.Width+$x)*4+3] -gt 0){if($x -lt $left){$left=$x};if($y -lt $top){$top=$y};if($x -gt $right){$right=$x};if($y -gt $bottom){$bottom=$y}}}}
 if($right -ge $left) {$c=$b.Clone([Drawing.Rectangle]::new($left,$top,($right-$left+1),($bottom-$top+1)),[Drawing.Imaging.PixelFormat]::Format32bppArgb);$temp=$path+'.trim.png';$c.Save($temp,[Drawing.Imaging.ImageFormat]::Png);$c.Dispose();$b.Dispose();Move-Item -LiteralPath $temp -Destination $path -Force;$a.x+=$left;$a.y+=$top;$a.width=$right-$left+1;$a.height=$bottom-$top+1}
 else {$a.width=$b.Width;$a.height=$b.Height;$b.Dispose()}
 $a.centerX=$a.x+$a.width/2.0-576;$a.centerY=$a.y+$a.height/2.0-1024
}
$assets | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'assets-manifest-trimmed.json') -Encoding utf8
