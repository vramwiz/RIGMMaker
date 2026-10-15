param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [Parameter(Mandatory=$true)][string]$Exe
)
$ErrorActionPreference = 'Stop'
$outputRoot = [IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $outputRoot) { throw 'Choose a new output directory.' }
$Exe = [IO.Path]::GetFullPath($Exe)
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$reports = Join-Path $outputRoot 'reports'
New-Item -ItemType Directory -Path $reports | Out-Null
$compiler = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
& $compiler -B -Q ('-E'+$outputRoot) ('-N0'+$outputRoot) (Join-Path $PSScriptRoot 'AppContainerPipeClient.dpr')
if ($LASTEXITCODE -ne 0) { throw 'AppContainer client compile failed.' }
# Only the newly created verification folder is made readable by test containers.
& icacls.exe $outputRoot /grant '*S-1-15-2-1:(OI)(CI)RX' '*S-1-15-2-2:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Fixture read ACL failed.' }
if (-not ('DotsTestAppContainer' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.ComponentModel;
public static class DotsTestAppContainer {
    [StructLayout(LayoutKind.Sequential)] struct SI {
        public int cb; public IntPtr reserved,desktop,title;
        public int x,y,xSize,ySize,xChars,yChars,fill,flags;
        public short show,reserved2; public IntPtr reservedBytes,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct SX { public SI info; public IntPtr attributes; }
    [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr process,thread; public uint pid,tid; }
    [StructLayout(LayoutKind.Sequential)] struct SC { public IntPtr sid,capabilities; public uint count,reserved; }
    [StructLayout(LayoutKind.Sequential)] struct SA { public int size; public IntPtr descriptor; public int inherit; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref SA security,uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadFile(IntPtr handle,byte[] bytes,int length,out int count,IntPtr overlapped);
    [DllImport("userenv.dll",CharSet=CharSet.Unicode)] static extern int CreateAppContainerProfile(string name,string display,string description,IntPtr caps,uint count,out IntPtr sid);
    [DllImport("userenv.dll",CharSet=CharSet.Unicode)] static extern int DeleteAppContainerProfile(string name);
    [DllImport("advapi32.dll")] static extern IntPtr FreeSid(IntPtr sid);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr bytes);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr kind,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string exe,StringBuilder cmd,IntPtr pSecurity,IntPtr tSecurity,bool inherit,uint flags,IntPtr env,string dir,ref SX startup,out PI process);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static uint Run(string exe,string arguments,string directory,bool lessPrivileged,out string report) {
        report="";
        string profile="DotsPipeTest."+Guid.NewGuid().ToString("N");
        IntPtr sid=IntPtr.Zero,list=IntPtr.Zero,scPointer=IntPtr.Zero,policy=IntPtr.Zero;
        bool initialized=false; PI process=new PI();
        IntPtr outputRead=IntPtr.Zero,outputWrite=IntPtr.Zero;
        int result=CreateAppContainerProfile(profile,profile,"Temporary Dots pipe verification",IntPtr.Zero,0,out sid);
        if(result<0) Marshal.ThrowExceptionForHR(result);
        try {
            IntPtr size=IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero,lessPrivileged?2:1,0,ref size);
            list=Marshal.AllocHGlobal(size);
            if(!InitializeProcThreadAttributeList(list,lessPrivileged?2:1,0,ref size)) throw new Win32Exception();
            initialized=true;
            SC security=new SC(); security.sid=sid;
            scPointer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SC)));
            Marshal.StructureToPtr(security,scPointer,false);
            if(!UpdateProcThreadAttribute(list,0,new IntPtr(0x20009),scPointer,new IntPtr(Marshal.SizeOf(typeof(SC))),IntPtr.Zero,IntPtr.Zero)) throw new Win32Exception();
            if(lessPrivileged) {
                policy=Marshal.AllocHGlobal(4); Marshal.WriteInt32(policy,1);
                if(!UpdateProcThreadAttribute(list,0,new IntPtr(0x2000F),policy,new IntPtr(4),IntPtr.Zero,IntPtr.Zero)) throw new Win32Exception();
            }
            SA pipeSecurity=new SA(); pipeSecurity.size=Marshal.SizeOf(typeof(SA)); pipeSecurity.inherit=1;
            if(!CreatePipe(out outputRead,out outputWrite,ref pipeSecurity,4096)) throw new Win32Exception();
            if(!SetHandleInformation(outputRead,1,0)) throw new Win32Exception();
            SX startup=new SX(); startup.info.cb=Marshal.SizeOf(typeof(SX)); startup.attributes=list;
            startup.info.flags=0x100; startup.info.output=outputWrite; startup.info.error=outputWrite;
            if(!CreateProcess(exe,new StringBuilder("\""+exe+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,true,0x08080000,IntPtr.Zero,directory,ref startup,out process)) throw new Win32Exception();
            CloseHandle(outputWrite); outputWrite=IntPtr.Zero;
            if(WaitForSingleObject(process.process,30000)!=0) {
                TerminateProcess(process.process,2); WaitForSingleObject(process.process,5000);
                throw new Exception("AppContainer helper timeout");
            }
            byte[] buffer=new byte[4096]; int count;
            if(ReadFile(outputRead,buffer,buffer.Length,out count,IntPtr.Zero)) report=Encoding.UTF8.GetString(buffer,0,count);
            uint code; GetExitCodeProcess(process.process,out code); return code;
        } finally {
            if(outputRead!=IntPtr.Zero) CloseHandle(outputRead);
            if(outputWrite!=IntPtr.Zero) CloseHandle(outputWrite);
            if(process.thread!=IntPtr.Zero) CloseHandle(process.thread);
            if(process.process!=IntPtr.Zero) CloseHandle(process.process);
            if(initialized) DeleteProcThreadAttributeList(list);
            if(list!=IntPtr.Zero) Marshal.FreeHGlobal(list);
            if(scPointer!=IntPtr.Zero) Marshal.FreeHGlobal(scPointer);
            if(policy!=IntPtr.Zero) Marshal.FreeHGlobal(policy);
            if(sid!=IntPtr.Zero) FreeSid(sid);
            int removed=DeleteAppContainerProfile(profile);
            if(removed<0) Marshal.ThrowExceptionForHR(removed);
        }
    }
}
'@
}
$checks = [Collections.Generic.List[string]]::new()
$sids = [Collections.Generic.List[string]]::new()
$helper = Join-Path $outputRoot 'AppContainerPipeClient.exe'
Add-Type -AssemblyName System.Drawing
$fixture = [Drawing.Bitmap]::new(32,24)
$fixtureStream = [IO.MemoryStream]::new()
try { $fixture.Save($fixtureStream,[Drawing.Imaging.ImageFormat]::Png); $fixtureBytes = $fixtureStream.ToArray() }
finally { $fixtureStream.Dispose(); $fixture.Dispose() }
$fixtureBase64 = [Convert]::ToBase64String($fixtureBytes)
$uploadedImageId = ''
function Check([bool]$Condition,[string]$Name) { if (-not $Condition) { throw ('FAILED: '+$Name) }; $checks.Add($Name) }
foreach ($mode in @('default','appcontainer')) {
    $stateDir = Join-Path $outputRoot $mode
    $arguments = '--state-dir "'+$stateDir+'"'
    if ($mode -eq 'appcontainer') { $arguments += ' --allow-appcontainer' }
    $owned = Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
    try {
        $connectionFile = Join-Path $stateDir 'connection.json'
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $connectionFile)) {
            if ($owned.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Server startup failed.' }
            Start-Sleep -Milliseconds 100
        }
        $connection=Get-Content -LiteralPath $connectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $cases = if ($mode -eq 'default') { @('denied') } else { @('first','rotated','missing-token','lpac','echo','upload','download') }
        foreach ($case in $cases) {
            $token = if ($mode -eq 'appcontainer' -and $case -ne 'missing-token') { $connection.accessToken } else { '-' }
            $reportFile=Join-Path $reports ($mode+'-'+$case+'.json')
            $rawReport=''
            $childArguments = '"'+$connection.pipeName+'" "'+$token+'" "'+$case+'"'
            if ($case -eq 'upload') { $childArguments += ' "'+$fixtureBase64+'"' }
            if ($case -eq 'download') { $childArguments += ' "'+$uploadedImageId+'"' }
            $exit=[DotsTestAppContainer]::Run($helper,$childArguments,$outputRoot,($case -eq 'lpac'),[ref]$rawReport)
            [IO.File]::WriteAllText($reportFile,$rawReport,[Text.UTF8Encoding]::new($false))
            Check ($exit -eq 0) ($mode+'/'+$case+' helper exited successfully')
            $report=Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
            Check ($report.integritySid -eq 'S-1-16-4096' -and $report.appContainerSid -like 'S-1-15-2-*') ($mode+'/'+$case+' real Low AppContainer')
            if ($mode -eq 'default') { Check ($report.openError -eq 5) 'Default mode denies Low AppContainer' }
            elseif ($case -eq 'missing-token') { Check ($report.openError -eq 0 -and $report.response.error.code -eq 'unauthorized') 'Missing token cannot issue commands' }
            elseif ($case -eq 'echo') {
                Check ($report.openError -eq 0 -and $report.response.ok -and $report.response.data.text -ceq "Dotsからこんにちは。`n画像通信の前のテキスト試験") 'AppContainer UTF-8 text round trip'
                $sids.Add($report.appContainerSid)
            }
            elseif ($case -eq 'upload') {
                Check ($report.openError -eq 0 -and $report.response.ok -and $report.response.data.width -eq 32 -and $report.response.data.height -eq 24) 'AppContainer image upload decoded and stored'
                $uploadedImageId = $report.response.data.imageId
                $sids.Add($report.appContainerSid)
            }
            elseif ($case -eq 'download') {
                Check ($report.openError -eq 0 -and $report.response.ok -and $report.response.data.base64 -ceq $fixtureBase64) 'Different AppContainer receives identical image bytes'
                $sids.Add($report.appContainerSid)
            }
            else {
                Check ($report.openError -eq 0 -and $report.response.ok -and $report.response.data.message -eq 'pong') ($case+' AppContainer ping/pong')
                $sids.Add($report.appContainerSid)
            }
        }
        $normal=& (Join-Path $PSScriptRoot 'Send-ProbeCommand.ps1') -ConnectionFile $connectionFile -Command ping
        Check $normal.ok ($mode+' normal caller remains usable')
    } finally {
        # Verification owns this exact process and its unused state directory.
        if (-not $owned.HasExited) { Stop-Process -Id $owned.Id }
        $owned.Dispose()
    }
}
Check (($sids | Sort-Object -Unique).Count -eq 6) 'All six successful containers have different SIDs'
@{success=$true;checks=$checks.ToArray();appContainerSids=$sids.ToArray()} | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
'Passed '+$checks.Count+' AppContainer checks. Evidence: '+$outputRoot
