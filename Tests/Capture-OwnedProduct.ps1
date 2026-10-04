#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile,[Parameter(Mandatory)][string]$Name)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
if(-not $run.owned){throw 'Capture is limited to our owned product instance'}
$process=Get-Process -Id $run.pid
if([IO.Path]::GetFullPath($process.Path) -ne [IO.Path]::GetFullPath($run.executable)){throw 'Owned PID now belongs to another executable'}
if((Get-FileHash -LiteralPath $process.Path -Algorithm SHA256).Hash -ne $run.executableSha256){throw 'Owned executable changed'}
Add-Type -AssemblyName System.Drawing
if(-not ('RigmOwnedWindow' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RigmOwnedWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int command);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int hgt,uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
  delegate bool EnumProc(IntPtr h,IntPtr param);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr param);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc callback,IntPtr param);
  public static IntPtr MainForm(uint requested) {
    IntPtr result=IntPtr.Zero;
    EnumWindows((h,p)=>{uint pid;GetWindowThreadProcessId(h,out pid);var name=new StringBuilder(256);GetClassName(h,name,256);
      if(pid==requested&&name.ToString()=="TMainForm"){result=h;return false;}return true;},IntPtr.Zero);
    return result;
  }
  public static void HideApplicationHelper(uint requested) {
    EnumWindows((h,p)=>{uint pid;GetWindowThreadProcessId(h,out pid);var name=new StringBuilder(256);GetClassName(h,name,256);
      if(pid==requested&&name.ToString()=="TApplication"&&IsWindowVisible(h))ShowWindow(h,0);
      return true;},IntPtr.Zero);
  }
  public static int VisibleProgressPosition(IntPtr root) {
    int value=-1;
    EnumChildWindows(root,(h,p)=>{var name=new StringBuilder(256);GetClassName(h,name,256);
      if(IsWindowVisible(h)&&name.ToString().IndexOf("Progress",StringComparison.OrdinalIgnoreCase)>=0)
        value=SendMessage(h,0x0408,IntPtr.Zero,IntPtr.Zero).ToInt32();
      return true;},IntPtr.Zero);
    return value;
  }
}
'@
}
$null=[RigmOwnedWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
$window=[RigmOwnedWindow]::MainForm([uint32]$run.pid)
if($window -eq [IntPtr]::Zero){throw 'Owned main window is unavailable'}
$windowPid=[uint32]0
$null=[RigmOwnedWindow]::GetWindowThreadProcessId($window,[ref]$windowPid)
if($windowPid -ne $run.pid){throw 'Window does not belong to the recorded production process'}
[RigmOwnedWindow]::HideApplicationHelper([uint32]$run.pid)
$null=[RigmOwnedWindow]::ShowWindow($window,4)
Start-Sleep -Milliseconds 250
$rectangle=[RigmOwnedWindow+Rect]::new()
if(-not [RigmOwnedWindow]::GetWindowRect($window,[ref]$rectangle)){throw 'Cannot read owned window bounds'}
$width=$rectangle.Right-$rectangle.Left;$height=$rectangle.Bottom-$rectangle.Top
if($width -lt 100 -or $height -lt 100 -or $width -gt 4096 -or $height -gt 2160){throw 'Owned window capture bounds are invalid'}
$path=Join-Path $run.runDirectory ($Name+'.png')
if(Test-Path -LiteralPath $path){throw 'Choose a new capture name'}
$bitmap=[Drawing.Bitmap]::new($width,$height)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$dc=$graphics.GetHdc()
try{
  if(-not [RigmOwnedWindow]::PrintWindow($window,$dc,2)){throw 'Native PrintWindow failed; no other desktop capture is attempted'}
}finally{$graphics.ReleaseHdc($dc);$graphics.Dispose()}
try{$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
$info=@{
  pid=$run.pid;owned=$true;windowPid=$windowPid;windowClass='TMainForm';windowHandle=$window.ToInt64();visible=[RigmOwnedWindow]::IsWindowVisible($window)
  width=$width;height=$height;path=$path;nativeProgressPosition=[RigmOwnedWindow]::VisibleProgressPosition($window)
  physicalDpiCoordinates=$true;humanDesktopVerification=$false;utc=[DateTime]::UtcNow.ToString('o')
}
$info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run.runDirectory ($Name+'.json')) -Encoding utf8BOM
$info | ConvertTo-Json -Depth 5
