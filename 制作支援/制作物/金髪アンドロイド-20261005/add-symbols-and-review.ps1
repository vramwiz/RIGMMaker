$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Add-Type -AssemblyName System.Drawing
$assets=Get-Content -LiteralPath (Join-Path $root 'assets-manifest.json') -Raw | ConvertFrom-Json -AsHashtable
$symbols=@('なし','驚き','疑問','汗','怒り','きらめき','ハート')
for($i=0;$i -lt $symbols.Count;$i++) {
 $b=[Drawing.Bitmap]::new(120,140);$g=[Drawing.Graphics]::FromImage($b);$g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
 $gold=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255,255,197,55));$cyan=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255,92,195,250));$red=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255,232,77,84));$pen=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,95,70,45),3)
 switch($i) {
  1 {$g.FillPolygon($gold,[Drawing.Point[]]@([Drawing.Point]::new(40,15),[Drawing.Point]::new(74,15),[Drawing.Point]::new(65,94),[Drawing.Point]::new(49,94)));$g.FillEllipse($gold,46,106,25,25)}
  2 {$font=[Drawing.Font]::new('Yu Gothic UI',87,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel);$g.DrawString('?',$font,$cyan,22,0);$font.Dispose()}
  3 {$path=[Drawing.Drawing2D.GraphicsPath]::new();$path.AddBezier(58,15,44,46,14,69,30,105);$path.AddBezier(30,105,54,145,105,105,84,75);$path.AddBezier(84,75,77,59,66,29,58,15);$g.FillPath($cyan,$path);$shine=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(220,255,255,255));$g.FillEllipse($shine,37,76,13,27);$shine.Dispose();$path.Dispose()}
  4 {$p=[Drawing.Pen]::new($red.Color,9);$p.StartCap='Round';$p.EndCap='Round';$g.DrawArc($p,16,14,40,40,0,90);$g.DrawArc($p,66,14,40,40,90,90);$g.DrawArc($p,16,64,40,40,270,90);$g.DrawArc($p,66,64,40,40,180,90);$p.Dispose()}
  5 {$g.FillPolygon($gold,[Drawing.Point[]]@([Drawing.Point]::new(60,8),[Drawing.Point]::new(72,49),[Drawing.Point]::new(108,65),[Drawing.Point]::new(72,82),[Drawing.Point]::new(60,125),[Drawing.Point]::new(47,82),[Drawing.Point]::new(10,65),[Drawing.Point]::new(47,49)));$g.FillEllipse($gold,5,12,13,13);$g.FillEllipse($gold,96,108,12,12)}
  6 {$path=[Drawing.Drawing2D.GraphicsPath]::new();$path.AddBezier(60,122,35,103,5,80,10,47);$path.AddBezier(10,47,18,8,50,19,60,41);$path.AddBezier(60,41,76,9,113,20,111,55);$path.AddBezier(111,55,109,83,78,108,60,122);$g.FillPath($red,$path);$path.Dispose()}
 }
 $base='symbol-'+$i;$b.Save((Join-Path $root ('assets/'+$base+'.png')),[Drawing.Imaging.ImageFormat]::Png)
 $assets+=@{file=('assets/'+$base+'.png');group='感情記号';name=('*'+$symbols[$i]);role='accessory';visible=($i -eq 0);x=725;y=165}
 $pen.Dispose();$gold.Dispose();$cyan.Dispose();$red.Dispose();$g.Dispose();$b.Dispose()
}
$assets | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'assets-manifest.json') -Encoding utf8
function Compose($eye='eyes-original',$brow='brows-0',$mouth='mouth-original',$face='face-normal',$body='body-normal',$symbol='symbol-0') {
 $canvas=[Drawing.Bitmap]::new(1152,2048);$g=[Drawing.Graphics]::FromImage($canvas)
 foreach($file in @($body,'hair-back',$face,$eye,$brow,$mouth,'hair-clean',$symbol)) {
  $a=$assets | Where-Object { $_.file -eq ('assets/'+$file+'.png') } | Select-Object -First 1
  $img=[Drawing.Bitmap]::new((Join-Path $root ('assets/'+$file+'.png')));$g.DrawImageUnscaled($img,[int]$a.x,[int]$a.y);$img.Dispose()
 }
 $g.Dispose();return $canvas
}
$normal=Compose;$normal.Save((Join-Path $root 'neutral-preview.png'),[Drawing.Imaging.ImageFormat]::Png);$normal.Dispose()
$modes=@(@{eye='eyes-original';mouth='mouth-original';brow='brows-0';face='face-normal';body='body-normal';symbol='symbol-0';label='通常'},@{eye='eyes-3';mouth='mouths-7';brow='brows-1';face='face-color-1';body='body-present';symbol='symbol-5';label='笑顔・紹介'},@{eye='eyes-4';mouth='mouths-6';brow='brows-4';face='face-normal';body='body-point';symbol='symbol-1';label='驚き・指さし'},@{eye='eyes-2';mouth='mouths-8';brow='brows-3';face='face-color-2';body='body-think';symbol='symbol-3';label='困る・青ざめ'},@{eye='eyes-1';mouth='mouths-3';brow='brows-2';face='face-color-3';body='body-normal';symbol='symbol-4';label='真剣・不調'})
$review=[Drawing.Bitmap]::new(1500,880);$g=[Drawing.Graphics]::FromImage($review);$g.Clear([Drawing.Color]::FromArgb(36,40,48));$font=[Drawing.Font]::new('Yu Gothic UI',18,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
for($i=0;$i -lt $modes.Count;$i++) {$m=$modes[$i];$c=Compose $m.eye $m.brow $m.mouth $m.face $m.body $m.symbol;$g.DrawImage($c,[Drawing.Rectangle]::new($i*300,34,300,533));$g.DrawImage($c,[Drawing.Rectangle]::new($i*300,595,300,225),[Drawing.Rectangle]::new(455,260,240,180),[Drawing.GraphicsUnit]::Pixel);$g.DrawString($m.label,$font,[Drawing.Brushes]::White,$i*300+12,7);$c.Dispose()}
$g.Dispose();$font.Dispose();$review.Save((Join-Path $root 'variants-review.png'),[Drawing.Imaging.ImageFormat]::Png);$review.Dispose()
