param(
    [Parameter(Mandatory=$true)][string]$ConnectionFile,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

# Run this from the SAME Dots execution environment that gets Access Denied.
# A normal terminal's token does not diagnose a sandboxed sender's access.
if (-not ('DotsPipeAccessNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Collections.Generic;
public static class DotsPipeAccessNative {
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetTokenInformation(IntPtr token, int infoClass, IntPtr data, int length, out int needed);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WaitNamedPipe(string name, uint milliseconds);
    static IntPtr TokenInfo(IntPtr token, int kind) {
        int needed;
        GetTokenInformation(token,kind,IntPtr.Zero,0,out needed);
        if (needed<=0) return IntPtr.Zero;
        IntPtr data=Marshal.AllocHGlobal(needed);
        if (!GetTokenInformation(token,kind,data,needed,out needed)) {
            Marshal.FreeHGlobal(data); return IntPtr.Zero;
        }
        return data;
    }
    public static string[] Groups(IntPtr token,int kind) {
        IntPtr data=TokenInfo(token,kind);
        if(data==IntPtr.Zero) return new string[0];
        try {
            int count=Marshal.ReadInt32(data);
            int offset=IntPtr.Size==8 ? 8 : 4;
            int step=IntPtr.Size==8 ? 16 : 8;
            var result=new List<string>();
            for(int i=0;i<count;i++) {
                IntPtr sid=Marshal.ReadIntPtr(data,offset+i*step);
                result.Add(new SecurityIdentifier(sid).Value);
            }
            return result.ToArray();
        } finally { Marshal.FreeHGlobal(data); }
    }
    public static string FirstSid(IntPtr token,int kind) {
        IntPtr data=TokenInfo(token,kind);
        if(data==IntPtr.Zero) return null;
        try {
            IntPtr sid=Marshal.ReadIntPtr(data);
            return sid==IntPtr.Zero ? null : new SecurityIdentifier(sid).Value;
        } finally { Marshal.FreeHGlobal(data); }
    }
    public static int Number(IntPtr token,int kind) {
        IntPtr data=TokenInfo(token,kind);
        if(data==IntPtr.Zero) return -1;
        try { return Marshal.ReadInt32(data); }
        finally { Marshal.FreeHGlobal(data); }
    }
    public static int TestOpen(string name) {
        string path=@"\\.\pipe\"+name;
        for(int attempt=0;attempt<3;attempt++) {
            IntPtr pipe=CreateFile(path,0xC0000000,0,IntPtr.Zero,3,0x40000000,IntPtr.Zero);
            if(pipe!=new IntPtr(-1)) { CloseHandle(pipe); return 0; }
            int error=Marshal.GetLastWin32Error();
            if(error!=231) return error;
            WaitNamedPipe(path,1000);
        }
        return 231;
    }
}
'@
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $discovery = Get-Content -LiteralPath $ConnectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($discovery.protocol -ne 'dots-codex-probe/1') { throw 'Unsupported discovery protocol.' }
    $server = Get-Process -Id $discovery.processId -ErrorAction SilentlyContinue
    $report = [ordered]@{
        purpose = 'Run inside the failing Dots runtime; compare with a normal terminal.'
        connectionFile = [IO.Path]::GetFullPath($ConnectionFile)
        pipeName = $discovery.pipeName
        serverProcessId = $discovery.processId
        serverProcessExists = ($null -ne $server)
        senderProcessId = $PID
        senderUserSid = $identity.User.Value
        integritySid = [DotsPipeAccessNative]::FirstSid($identity.Token,25)
        restrictedSids = @([DotsPipeAccessNative]::Groups($identity.Token,11))
        isAppContainer = [DotsPipeAccessNative]::Number($identity.Token,29)
        appContainerSid = [DotsPipeAccessNative]::FirstSid($identity.Token,31)
        capabilitySids = @([DotsPipeAccessNative]::Groups($identity.Token,30))
        isElevated = [DotsPipeAccessNative]::Number($identity.Token,20)
        nativeOpenWin32Error = -1
        nativeOpenMessage = ''
        pingSucceeded = $false
    }
    $nativeError = [DotsPipeAccessNative]::TestOpen($discovery.pipeName)
    $report.nativeOpenWin32Error = $nativeError
    $report.nativeOpenMessage = if ($nativeError -eq 0) { 'Opened successfully' } else { [ComponentModel.Win32Exception]::new($nativeError).Message }
    if ($nativeError -eq 0) {
        try {
            $ping = & (Join-Path $PSScriptRoot 'Send-ProbeCommand.ps1') -ConnectionFile $ConnectionFile -Command ping -TimeoutMs 5000
            $report.pingSucceeded = [bool]$ping.ok
        } catch { $report.pingError = $_.Exception.Message }
    }
    $json = $report | ConvertTo-Json -Depth 8
    if ($OutFile) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json,[Text.UTF8Encoding]::new($false)) }
    $json
} finally { $identity.Dispose() }
