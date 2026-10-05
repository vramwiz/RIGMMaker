$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.IO;
public static class RigPixels {
 public static byte[] Read(Bitmap b) {
  var d=b.LockBits(new Rectangle(0,0,b.Width,b.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
  var v=new byte[b.Width*b.Height*4]; for(int y=0;y<b.Height;y++) Marshal.Copy(d.Scan0+y*d.Stride,v,y*b.Width*4,b.Width*4); b.UnlockBits(d); return v;
 }
 public static Bitmap Make(int w,int h,byte[] v) { var b=new Bitmap(w,h,PixelFormat.Format32bppArgb); var d=b.LockBits(new Rectangle(0,0,w,h),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb); for(int y=0;y<h;y++) Marshal.Copy(v,y*w*4,d.Scan0+y*d.Stride,w*4); b.UnlockBits(d); return b; }
 public static bool Poly(int x,int y,int[] p) {bool c=false; for(int i=0,j=p.Length-2;i<p.Length;j=i,i+=2) if(((p[i+1]>y)!=(p[j+1]>y)) && x<(double)(p[j]-p[i])*(y-p[i+1])/(p[j+1]-p[i+1])+p[i]) c=!c; return c;}
 public static Rectangle Box(Bitmap b,int a) {var v=Read(b); int l=b.Width,t=b.Height,r=-1,bt=-1; for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) if(v[(y*b.Width+x)*4+3]>=a) {l=Math.Min(l,x);t=Math.Min(t,y);r=Math.Max(r,x);bt=Math.Max(bt,y);} return r<l?new Rectangle(0,0,1,1):Rectangle.FromLTRB(l,t,r+1,bt+1);}
 public static Bitmap Resize(Bitmap b,int w,int h) {var o=new Bitmap(w,h,PixelFormat.Format32bppArgb); using(var g=Graphics.FromImage(o)) {g.CompositingMode=CompositingMode.SourceCopy;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.HighQuality;g.DrawImage(b,new Rectangle(0,0,w,h),new Rectangle(0,0,b.Width,b.Height),GraphicsUnit.Pixel);} return o;}
 public static void Save(Bitmap b,string p) {b.Save(p,ImageFormat.Png);}
 public static Bitmap Clean(Bitmap b,int threshold,int pad) {var v=Read(b); var keep=new bool[b.Width*b.Height]; for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) if(v[(y*b.Width+x)*4+3]>=threshold) for(int dy=-pad;dy<=pad;dy++) for(int dx=-pad;dx<=pad;dx++) if(x+dx>=0&&x+dx<b.Width&&y+dy>=0&&y+dy<b.Height) keep[(y+dy)*b.Width+x+dx]=true; for(int i=0;i<keep.Length;i++) if(!keep[i]) {v[i*4]=v[i*4+1]=v[i*4+2]=v[i*4+3]=0;} return Make(b.Width,b.Height,v);}
 public static Bitmap Cut(Bitmap b,Rectangle r) {return b.Clone(r,PixelFormat.Format32bppArgb);}
 public static void Separate(string source,string foundation,string dest) {
  using(var src=new Bitmap(source)) using(var gen=new Bitmap(foundation)) {
   int w=src.Width,h=src.Height;var p=Read(src);var body=new byte[p.Length];var hair=new byte[p.Length];var face=new byte[p.Length];var eyes=new byte[p.Length];var brows=new byte[p.Length];var mouth=new byte[p.Length];
   var headPoly=new int[]{576,178,620,188,654,218,674,255,678,326,673,377,650,411,610,440,580,451,545,434,515,410,496,378,482,330,481,270,495,222,530,187};
   var visibleFace=new int[]{497,290,536,281,539,302,546,319,563,338,581,343,597,326,611,294,614,278,656,289,676,318,675,355,670,381,659,402,638,422,608,440,581,451,555,439,534,425,514,410,501,393,492,370,486,340,486,320};
   var collar=new int[]{536,440,624,440,627,483,690,525,458,525,533,482};
   var leftEye=new int[]{488,316,502,310,522,311,540,321,546,334,541,350,533,359,512,359,500,350,490,334,481,321};
   var rightEye=new int[]{610,322,624,311,645,310,661,314,674,326,674,340,666,352,648,359,627,358,614,348,606,335};
   var fbase=new Bitmap(w,h,PixelFormat.Format32bppArgb);
   using(var g=Graphics.FromImage(fbase)) {g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(gen,new RectangleF(576-622*.272f,374-820*.272f,gen.Width*.272f,gen.Height*.272f));}
   face=Read(fbase);fbase.Dispose();
   for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
    int i=(y*w+x)*4; int b=p[i],gr=p[i+1],r=p[i+2],a=p[i+3];
    if(!Poly(x,y,headPoly)) face[i]=face[i+1]=face[i+2]=face[i+3]=0;
    if(a==0) continue;
    bool isBody=y>=525 || (y>=440&&Poly(x,y,collar));
    bool eye=(Poly(x,y,leftEye)||Poly(x,y,rightEye)) && ((r-gr<18&&gr-b<27) || b>r-7 || (r<157&&gr<132));
    bool brow=((x>=504&&x<548&&y>=284&&y<298)||(x>=611&&x<662&&y>=281&&y<295)) && r-gr>8 && r<205 && gr<173;
    bool mou=Poly(x,y,new int[]{572,409,581,408,591,411,591,414,581,413,572,414});
    bool skin=Poly(x,y,visibleFace) && (r-gr>=Math.Max(7,(gr-b)*.77)) && r>155;
    byte[] target=isBody?body:eye?eyes:brow?brows:mou?mouth:skin?face:hair;
    if(!isBody && (eye||brow||mou)) {face[i]=face[i+1]=face[i+2]=face[i+3]=0;}
    Array.Copy(p,i,target,i,4);
   }
   // Fill feature holes from generated skin while keeping original skin elsewhere.
   // Keep only the connected hair silhouette; isolated skin/lip highlights are not hair.
   var visited=new bool[w*h];var queue=new int[w*h];var largest=new int[0];
   for(int start=0;start<visited.Length;start++) if(!visited[start]&&hair[start*4+3]>16) {int count=1,read=0;queue[0]=start;visited[start]=true;while(read<count){int cur=queue[read++],cx=cur%w,cy=cur/w;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=cx+dx,yy=cy+dy;if(xx<0||yy<0||xx>=w||yy>=h)continue;int next=yy*w+xx;if(!visited[next]&&hair[next*4+3]>16){visited[next]=true;queue[count++]=next;}}}if(count>largest.Length){largest=new int[count];Array.Copy(queue,largest,count);}}
   var keepHair=new bool[w*h];foreach(int cur in largest){int cx=cur%w,cy=cur/w;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)if(cx+dx>=0&&cy+dy>=0&&cx+dx<w&&cy+dy<h)keepHair[(cy+dy)*w+cx+dx]=true;}
   for(int i=0;i<keepHair.Length;i++)if(!keepHair[i]&&hair[i*4+3]>0){int k=i*4;Array.Copy(p,k,i/w>=440?body:face,k,4);hair[k]=hair[k+1]=hair[k+2]=hair[k+3]=0;}
   // Remove one-pixel highlight flecks in the exposed face without changing the hair's outer contour.
   var core=new bool[w*h];var opened=new bool[w*h];
   for(int y=270;y<450;y++)for(int x=481;x<678;x++){bool solid=true;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)solid=solid&&hair[((y+dy)*w+x+dx)*4+3]>32;core[y*w+x]=solid;}
   for(int y=270;y<450;y++)for(int x=481;x<678;x++)if(core[y*w+x])for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)opened[(y+dy)*w+x+dx]=true;
   for(int y=278;y<447;y++)for(int x=485;x<675;x++)if(Poly(x,y,visibleFace)&&!opened[y*w+x]&&hair[(y*w+x)*4+3]>0){int k=(y*w+x)*4;Array.Copy(p,k,face,k,4);hair[k]=hair[k+1]=hair[k+2]=hair[k+3]=0;}
   int[][] strands={new int[]{532,200,615,200,615,265,609,297,595,324,579,340,564,337,551,324,543,308,537,282},new int[]{516,236,519,238,514,275,513,296,517,315,525,326,535,335,535,338,521,331,513,320,509,305,510,280},new int[]{536,254,540,276,545,301,554,324,568,338,580,343,581,345,566,340,552,328,543,310,537,287,534,266},new int[]{627,237,628,250,622,280,617,303,610,327,606,336,603,337,610,309,616,276,621,249},new int[]{634,248,643,271,653,291,665,307,674,323,673,335,669,332,660,314,648,300,637,278,629,257},new int[]{494,291,499,280,509,253,510,254,503,283,494,310,484,325,484,326,490,320}};
   for(int y=278;y<447;y++)for(int x=485;x<675;x++)if(Poly(x,y,visibleFace)){int k=(y*w+x)*4;bool strand=false;foreach(var poly in strands)strand=strand||Poly(x,y,poly);strand=strand&&p[k+2]>p[k]+12&&!(x<542&&y>316);if(strand)Array.Copy(p,k,hair,k,4);else if(hair[k+3]>0){Array.Copy(p,k,face,k,4);hair[k]=hair[k+1]=hair[k+2]=hair[k+3]=0;}}
   using(var gf=new Bitmap(w,h,PixelFormat.Format32bppArgb)) {using(var g=Graphics.FromImage(gf)){g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(gen,new RectangleF(576-622*.272f,374-820*.272f,gen.Width*.272f,gen.Height*.272f));} var gp=Read(gf);for(int y=0;y<h;y++)for(int x=0;x<w;x++){int i=(y*w+x)*4;if(!Poly(x,y,headPoly)||gp[i+3]==0)continue;bool feature=eyes[i+3]>0||brows[i+3]>0||mouth[i+3]>0||Poly(x,y,leftEye)||Poly(x,y,rightEye);double mix=feature?0:Math.Max(0,Math.Min(1,(y-355)/50.0)); if(face[i+3]==0)mix=0;for(int c=0;c<3;c++)face[i+c]=(byte)(gp[i+c]*(1-mix)+face[i+c]*mix);face[i+3]=Math.Max(gp[i+3],face[i+3]);}}
   string[] names={"body-normal","hair-original","face-normal","eyes-original","brows-original","mouth-original"};byte[][] data={body,hair,face,eyes,brows,mouth};for(int j=0;j<names.Length;j++) using(var bm=Make(w,h,data[j])) Save(bm,Path.Combine(dest,names[j]+".png"));
  }
 }
 public static Bitmap Overlay(Bitmap below,Bitmap above) {var o=(Bitmap)below.Clone();using(var g=Graphics.FromImage(o))g.DrawImageUnscaled(above,0,0);return o;}
 public static Bitmap Canvas(Bitmap b,int w,int h,int x,int y) {var o=new Bitmap(w,h,PixelFormat.Format32bppArgb);using(var g=Graphics.FromImage(o))g.DrawImageUnscaled(b,x,y);return o;}
 public static Bitmap FaceColor(Bitmap normal,Bitmap neutral,Bitmap variant) {
  var n=Read(normal);var baseP=Read(neutral);var v=Read(variant);for(int i=0;i<n.Length;i+=4) if(n[i+3]>0&&baseP[i+3]>128&&v[i+3]>128) for(int c=0;c<3;c++) n[i+c]=(byte)Math.Max(0,Math.Min(255,n[i+c]+v[i+c]-baseP[i+c]));return Make(normal.Width,normal.Height,n);
 }
}
'@ -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Runtime,System.Runtime.InteropServices,System.Private.Windows.GdiPlus,System.Private.Windows.Core
[RigPixels]::Separate('C:\Users\vramw\Pictures\magnific__background__16889.png',(Join-Path $root 'generated\foundation.png'),(Join-Path $root 'assets'))
$manifest=[Collections.Generic.List[object]]::new()
function Add-Asset($file,$group,$name,$role,$visible=$false,$x=0,$y=0) {
 $manifest.Add(@{file=('assets/'+$file+'.png');group=$group;name=$name;role=$role;visible=$visible;x=$x;y=$y})
}
Add-Asset 'body-normal' '体' '*通常' 'body' $true
$hb=[Drawing.Bitmap]::new((Join-Path $root 'assets\hair-original.png'));$crop=[RigPixels]::Cut($hb,[Drawing.Rectangle]::new(0,350,1152,175));$back=[RigPixels]::Canvas($crop,1152,2048,0,350);$back.Save((Join-Path $root 'assets\hair-back.png'),[Drawing.Imaging.ImageFormat]::Png);Add-Asset 'hair-back' '後ろ髪' '後ろ髪' 'hair' $true;$hb.Dispose();$crop.Dispose();$back.Dispose()
Add-Asset 'face-normal' '顔色' '*通常' 'face' $true
Add-Asset 'hair-original' '髪' '*原画保持' 'hair'
$hair=[Drawing.Bitmap]::new((Join-Path $root 'generated\hair-clean.png'));$clean=[RigPixels]::Clean($hair,220,1);$box=[RigPixels]::Box($clean,16);$part=[RigPixels]::Cut($clean,$box);$small=[RigPixels]::Resize($part,361,428);$small.Save((Join-Path $root 'assets\hair-clean.png'),[Drawing.Imaging.ImageFormat]::Png);Add-Asset 'hair-clean' '髪' '*通常' 'hair' $true 402 97;$hair.Dispose();$clean.Dispose();$part.Dispose();$small.Dispose()
Add-Asset 'eyes-original' '目' '*通常' 'eye' $true
Add-Asset 'brows-original' '眉' '*原画保持' 'brow'
Add-Asset 'mouth-original' '口' '*通常' 'mouth' $true
function Split-Sheet($file,$cols,$rows,$names,$group,$role,$scale,$cx,$cy,$threshold) {
 $sheet=[Drawing.Bitmap]::new((Join-Path $root ('generated/'+$file+'.png')))
 for($i=0;$i -lt $names.Count;$i++) {
  $cw=[int]($sheet.Width/$cols);$ch=[int]($sheet.Height/$rows)
  $cell=[RigPixels]::Cut($sheet,[Drawing.Rectangle]::new(($i%$cols)*$cw,[int][Math]::Floor($i/$cols)*$ch,$cw,$ch))
  $pad=if($role -eq 'brow'){0}else{1};$clean=[RigPixels]::Clean($cell,$threshold,$pad);$box=[RigPixels]::Box($clean,10)
  $part=[RigPixels]::Cut($clean,$box);$small=[RigPixels]::Resize($part,[Math]::Max(1,[int]($part.Width*$scale)),[Math]::Max(1,[int]($part.Height*$scale)))
  $base=$file+'-'+$i;$small.Save((Join-Path $root ('assets/'+$base+'.png')),[Drawing.Imaging.ImageFormat]::Png)
  if($names[$i]) {Add-Asset $base $group ('*'+$names[$i]) $role $false ([int]($cx-$small.Width/2)) ([int]($cy-$small.Height/2))}
  $cell.Dispose();$clean.Dispose();$part.Dispose();$small.Dispose()
 }
 $sheet.Dispose()
}
# The generated calibration pair measures about 556 px; original outer pair span is 195 px.
Split-Sheet 'eyes' 2 3 @('','半開き','閉じ','笑顔閉じ','見開き','やさしい目') '目' 'eye' .35 578 335 230
Split-Sheet 'mouths' 3 3 @('ん','半開き','あ','い','う','え','お','微笑み','悲しい') '口' 'mouth' .13 579 413 240
Split-Sheet 'brows' 2 3 @('通常','喜','怒','哀','疑問','困る') '眉' 'brow' .35 580 290 252
$manifest | Where-Object {$_.file -eq 'assets/brows-0.png'} | ForEach-Object {$_.visible=$true}
# Normal is also the closed resting mouth in the original artwork.
$normal=[Drawing.Bitmap]::new((Join-Path $root 'assets\mouth-original.png'));$normal.Save((Join-Path $root 'assets\mouth-closed.png'),[Drawing.Imaging.ImageFormat]::Png);$normal.Dispose()
Add-Asset 'mouth-closed' '口' '*閉じ' 'mouth'
# All generated pose sprites align the neck stub and sole line with the source.
$poseData=@(@{file='point';name='左上を指さす';neckX=494;neckY=186;bottom=1580},@{file='present';name='手のひらで紹介';neckX=422;neckY=64;bottom=1602},@{file='think';name='胸に手を添える';neckX=471;neckY=88;bottom=1576})
foreach($item in $poseData) {
 $img=[Drawing.Bitmap]::new((Join-Path $root ('generated/'+$item.file+'.png')));$clean=[RigPixels]::Clean($img,220,1)
 $sc=1562.0/($item.bottom-$item.neckY);$new=[RigPixels]::Resize($clean,[int]($img.Width*$sc),[int]($img.Height*$sc))
 $x=[int](580-$item.neckX*$sc);$y=[int](446-$item.neckY*$sc)
 $new.Save((Join-Path $root ('assets/body-'+$item.file+'.png')),[Drawing.Imaging.ImageFormat]::Png)
 Add-Asset ('body-'+$item.file) '体' ('*'+$item.name) 'body' $false $x $y
 $img.Dispose();$clean.Dispose();$new.Dispose()
}
# Use generated color differences on the existing face silhouette, preserving original skin detail.
$normal=[Drawing.Bitmap]::new((Join-Path $root 'assets\face-normal.png'))
$sheet=[Drawing.Bitmap]::new((Join-Path $root 'generated\colors.png'))
$heads=@();$colorNames=@('通常','赤面','青ざめ','不調')
for($i=0;$i -lt 4;$i++) {
 $cw=[int]($sheet.Width/2);$ch=[int]($sheet.Height/2);$cell=[RigPixels]::Cut($sheet,[Drawing.Rectangle]::new(($i%2)*$cw,[int][Math]::Floor($i/2)*$ch,$cw,$ch))
 $clean=[RigPixels]::Clean($cell,225,1);$box=[RigPixels]::Box($clean,200);$part=[RigPixels]::Cut($clean,$box)
 # Align all head centers and chin; skin ears stay occluded by original hair.
 $size=[RigPixels]::Resize($part,222,272);$heads+=,[RigPixels]::Canvas($size,1152,2048,469,179)
 $cell.Dispose();$clean.Dispose();$part.Dispose();$size.Dispose()
}
for($i=1;$i -lt 4;$i++) {$out=[RigPixels]::FaceColor($normal,$heads[0],$heads[$i]);$out.Save((Join-Path $root ('assets/face-color-'+$i+'.png')),[Drawing.Imaging.ImageFormat]::Png);Add-Asset ('face-color-'+$i) '顔色' ('*'+$colorNames[$i]) 'face';$out.Dispose()}
foreach($h in $heads){$h.Dispose()};$normal.Dispose();$sheet.Dispose()
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'assets-manifest.json') -Encoding utf8
