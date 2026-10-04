#requires -Version 7.0
param([string]$CheckpointName='ai-checkpoint.json',[string]$AliasName='RIGMMaker.ai.exe',
 [string]$RecordName='ai-release-verification.json',[int]$ExpectedPassed=1423,[string]$SmokeCategory='aiSmoke')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validation=Join-Path $root 'Win64\Validation'
$checkpoint=Get-Content (Join-Path $validation $CheckpointName) -Raw | ConvertFrom-Json
if(-not $checkpoint.success -or $checkpoint.freshPassed -ne $ExpectedPassed){throw 'Incomplete final validation'}
foreach($item in $checkpoint.sourceHashes){if((Get-FileHash $item.path).Hash -ne $item.sha256){throw ('Source changed after verification: '+$item.path)}}
if((Get-FileHash (Join-Path $root 'RIGMMaker.dproj')).Hash -ne $checkpoint.mainProjectHash){throw 'Main project changed; re-read and rebuild current user settings'}
$release=Join-Path $validation 'Release\RIGMMaker.exe'
$debug=Join-Path $validation 'Debug\RIGMMaker.exe'
if((Get-FileHash $release).Hash -ne $checkpoint.releaseSha256 -or (Get-FileHash $debug).Hash -ne $checkpoint.debugSha256){throw 'Final binaries changed'}
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class AiManifestRead {
 [DllImport("kernel32",CharSet=CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
 [DllImport("kernel32")] static extern IntPtr FindResource(IntPtr module,IntPtr name,IntPtr type);
 [DllImport("kernel32")] static extern uint SizeofResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32")] static extern IntPtr LoadResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32")] static extern IntPtr LockResource(IntPtr resource);
 [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr module);
 public static string Read(string path) {var module=LoadLibraryEx(path,IntPtr.Zero,2|32);if(module==IntPtr.Zero)throw new Exception("Cannot load executable resources");
  try {var resource=FindResource(module,(IntPtr)1,(IntPtr)24);if(resource==IntPtr.Zero)throw new Exception("Embedded manifest absent");
   var bytes=new byte[SizeofResource(module,resource)];Marshal.Copy(LockResource(LoadResource(module,resource)),bytes,0,bytes.Length);return System.Text.Encoding.UTF8.GetString(bytes);
  }finally{FreeLibrary(module);}}
}
'@
$manifests=@(foreach($cfg in @('Debug','Release')){
 $path=Join-Path $validation ($cfg+'\RIGMMaker.exe');$xml=[AiManifestRead]::Read($path)
 if(-not($xml.Contains('>PerMonitorV2<') -and $xml.Contains('level="asInvoker"') -and $xml.Contains('uiAccess="false"') -and $xml.Contains('Microsoft.Windows.Common-Controls'))){throw ('Incorrect final embedded manifest: '+$cfg)}
 [IO.File]::WriteAllText((Join-Path $validation ('manifest-'+$cfg+'.xml')),$xml,[Text.UTF8Encoding]::new($false))
 @{configuration=$cfg;path=$path;sha256=(Get-FileHash $path).Hash;PerMonitorV2=$true;asInvoker=$true;uiAccess=$false;runtimeThemes=$true}
})
$manifests | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $validation 'dpi-manifests.json') -Encoding utf8
$id=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
$preserved=Join-Path $root ('Win64\PreservedArtifacts\before-ai-'+$id)
New-Item -ItemType Directory -Path $preserved | Out-Null
$originals=@(Get-ChildItem $root -Filter '*.exe' -File | ForEach-Object {
 $hash=(Get-FileHash $_.FullName).Hash;Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $preserved $_.Name)
 if((Get-FileHash (Join-Path $preserved $_.Name)).Hash -ne $hash){throw 'Backup copy differs'}
 @{name=$_.Name;path=$_.FullName;sha256=$hash;backup=(Join-Path $preserved $_.Name)}
})
$alias=Join-Path $root $AliasName
if(Test-Path -LiteralPath $alias){throw 'Delivery alias already exists; inspect rather than overwrite'}
Copy-Item -LiteralPath $release -Destination $alias
if((Get-FileHash $alias).Hash -ne $checkpoint.releaseSha256){throw 'Delivered executable differs from verified Release'}
$smokeDirectory=Join-Path $validation ($SmokeCategory+'\'+$id)
New-Item -ItemType Directory -Path $smokeDirectory -Force | Out-Null
$process=Start-Process -FilePath $alias -ArgumentList @(('"--data-dir='+$smokeDirectory+'\Library"'),('"--pipe-dir='+$smokeDirectory+'\Pipes"'),('"--settings-dir='+$smokeDirectory+'\Settings"')) -WindowStyle Hidden -PassThru
$smoke=@{directory=$smokeDirectory;pid=$process.Id;inputIdle=$false;normalClose=$false;exitCode=$null}
try {
 $smoke.inputIdle=$process.WaitForInputIdle(10000);Start-Sleep -Milliseconds 300;$process.Refresh()
 if($process.HasExited){throw 'Isolated release exited early'}
 if(-not $process.CloseMainWindow()){throw 'Normal close of isolated release was unavailable; no force termination performed'}
 $smoke.normalClose=$process.WaitForExit(10000)
 if(-not $smoke.normalClose){throw 'Isolated release did not close normally'}
 $smoke.exitCode=$process.ExitCode;if($smoke.exitCode -ne 0){throw 'Isolated release exit was nonzero'}
}finally{$process.Dispose()}
foreach($item in $originals){if((Get-FileHash $item.path).Hash -ne $item.sha256){throw 'Original root executable changed'}}
$copies=@(Get-Content (Join-Path $validation 'production-library-originals.json') -Raw | ConvertFrom-Json | ForEach-Object {
 if((Get-FileHash $_.source).Hash -ne $_.sha256){throw 'Original reused library changed'};$_
})
$record=@{success=$true;atUtc=[DateTime]::UtcNow.ToString('o');freshPassed=$ExpectedPassed;alias=$alias;releaseSha256=$checkpoint.releaseSha256;debugSha256=$checkpoint.debugSha256;mainProjectHash=$checkpoint.mainProjectHash;manifests=$manifests;smoke=$smoke;preservedDirectory=$preserved;preservedExecutables=$originals;checkpoint=$checkpoint;originalLibraries=$copies;rootExeReplaced=$false;userApplicationsTerminated=$false;userDocumentsEdited=$false;realSpeechVerified=$false;physicalMonitorTransitionVerified=$false;cleanupCompleted=$false}
$record | ConvertTo-Json -Depth 48 | Set-Content (Join-Path $validation $RecordName) -Encoding utf8
$record | Select-Object success,freshPassed,alias,releaseSha256,smoke | ConvertTo-Json -Depth 6
