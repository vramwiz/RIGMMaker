param([Parameter(Mandatory)][int]$ProcessId,[Parameter(Mandatory)][string]$Path,[string]$WindowClass='TRigmWizardMainForm')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RigmValidationWindow {
 public delegate bool Callback(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback c, IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 public struct Rect { public int Left,Top,Right,Bottom; }
 public static IntPtr Find(int pid, string name) {
  IntPtr result=IntPtr.Zero;
  EnumWindows((h,p)=>{ uint owner; GetWindowThreadProcessId(h,out owner); var s=new StringBuilder(256); GetClassName(h,s,256);
   if(owner==(uint)pid && s.ToString()==name){result=h;return false;}return true;},IntPtr.Zero);
  return result;
 }
}
'@
$previousDpi=[RigmValidationWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
$window=[RigmValidationWindow]::Find($ProcessId,$WindowClass)
if($window -eq [IntPtr]::Zero){throw 'Owned wizard window was not found'}
[void][RigmValidationWindow]::ShowWindow($window,4)
Start-Sleep -Milliseconds 300
$rect=[RigmValidationWindow+Rect]::new()
if(-not [RigmValidationWindow]::GetWindowRect($window,[ref]$rect)){throw 'Cannot read window bounds'}
$bitmap=[Drawing.Bitmap]::new($rect.Right-$rect.Left,$rect.Bottom-$rect.Top)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$dc=$graphics.GetHdc();try{if(-not [RigmValidationWindow]::PrintWindow($window,$dc,2)){throw 'Native window capture failed'}}finally{$graphics.ReleaseHdc($dc)};$bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose();[void][RigmValidationWindow]::SetThreadDpiAwarenessContext($previousDpi)}
