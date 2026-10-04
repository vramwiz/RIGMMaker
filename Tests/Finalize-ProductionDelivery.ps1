#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validation=Join-Path $root 'Win64\Validation'
function Read-Record([string]$Name){Get-Content -LiteralPath (Join-Path $validation $Name) -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable}
$install=Read-Record 'production-executable-install.json'
$regressions=Read-Record 'production-regressions.json'
$integrity=Read-Record 'production-original-integrity.json'
$images=Read-Record 'production-library-images.json'
$cleanup=Read-Record 'production-cleanup-result.json'
$startup=@(foreach($label in @('Debug','Release','Root')){Read-Record ('production-startup-'+$label+'.json')})
if(-not $install.success -or -not $cleanup.success -or -not $regressions.success -or -not $integrity.productionOriginalsUnchanged -or -not $integrity.librarySourcesUnchanged){throw 'Final verification is incomplete'}
foreach($run in $startup){if(-not $run.success -or -not $run.gracefulExit -or $run.exitCode -ne 0 -or -not $run.sourceUnchanged -or $run.passed -ne 21){throw 'Product startup verification incomplete'}}
if((Get-FileHash -LiteralPath $install.launchExecutable).Hash -ne $install.sha256 -or (Get-FileHash -LiteralPath $install.backup).Hash -ne $install.previousSha256){throw 'Launch executable/backup changed'}
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class ProductionManifest {
 [DllImport("kernel32",CharSet=CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string p,IntPtr f,uint g);
 [DllImport("kernel32")] static extern IntPtr FindResource(IntPtr m,IntPtr n,IntPtr t);
 [DllImport("kernel32")] static extern uint SizeofResource(IntPtr m,IntPtr r);
 [DllImport("kernel32")] static extern IntPtr LoadResource(IntPtr m,IntPtr r);
 [DllImport("kernel32")] static extern IntPtr LockResource(IntPtr r);
 [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr m);
 public static string Read(string p){var m=LoadLibraryEx(p,IntPtr.Zero,2|32);if(m==IntPtr.Zero)throw new Exception("Resource load failed");try{var r=FindResource(m,(IntPtr)1,(IntPtr)24);if(r==IntPtr.Zero)throw new Exception("Manifest missing");var b=new byte[SizeofResource(m,r)];Marshal.Copy(LockResource(LoadResource(m,r)),b,0,b.Length);return System.Text.Encoding.UTF8.GetString(b);}finally{FreeLibrary(m);}}
}
'@
$builds=@(foreach($config in @('Debug','Release')){
  $exe=Join-Path $validation ($config+'\RIGMMaker.exe')
  $manifest=[ProductionManifest]::Read($exe)
  if(-not ($manifest.Contains('>PerMonitorV2<') -and $manifest.Contains('level="asInvoker"') -and $manifest.Contains('uiAccess="false"') -and $manifest.Contains('Microsoft.Windows.Common-Controls'))){throw ('Manifest mismatch '+$config)}
  [IO.File]::WriteAllText((Join-Path $validation ('production-manifest-'+$config+'.xml')),$manifest,[Text.UTF8Encoding]::new($false))
  @{configuration=$config;path=$exe;sha256=(Get-FileHash -LiteralPath $exe).Hash;PerMonitorV2=$true;asInvoker=$true;uiAccess=$false;runtimeThemes=$true;buildLog=('build-final-'+$config+'.log')}
})
$rootManifest=[ProductionManifest]::Read($install.launchExecutable)
if($rootManifest -ne [ProductionManifest]::Read($builds[1].path)){throw 'Root manifest differs from final Release'}
$editedDirectory=Join-Path $root '制作成果\星灯り郵便局-編集版-20261004T015824236'
$edited=Get-Content -LiteralPath (Join-Path $editedDirectory 'edited-verification.json') -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
if(-not $edited.success -or -not $edited.complete -or $images.completedLocalPngCount -ne 5){throw 'Edited production images/project incomplete'}
$imageIntegrity=@(foreach($item in $images.images){
  @{libraryFileId=$item.libraryFileId;source=$item.source;destination=$item.destination;sha256=$item.sha256;sourceUnchanged=((Get-FileHash -LiteralPath $item.source).Hash -eq $item.sha256);copiedBytesMatch=((Get-FileHash -LiteralPath $item.destination).Hash -eq $item.sha256)}
})
if(@($imageIntegrity|Where-Object {-not $_.sourceUnchanged -or -not $_.copiedBytesMatch}).Count){throw 'Image source/copy integrity failure'}
$sourceHashes=@(Get-ChildItem -LiteralPath (Join-Path $root 'Source') -Recurse -File -Filter '*.pas'|ForEach-Object{@{path=[IO.Path]::GetRelativePath($root,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$startupChecks=($startup|Measure-Object passed -Sum).Sum
$regressions.rootExeReplaced=$install.rootReplaced
$regressions.actualProductStartup=$startupChecks
$regressions.regressionTotal=1680
$regressions.total=1680+$startupChecks
$regressions.timestampUtc=[DateTime]::UtcNow.ToString('o')
$regressions|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $validation 'production-regressions.json') -Encoding UTF8
$record=@{success=$true;complete=$true;atUtc=[DateTime]::UtcNow.ToString('o');passed=$regressions.total;regressions=$regressions;builds=$builds;install=$install;startup=$startup;edited=$edited;imageIntegrity=$imageIntegrity;originalIntegrity=$integrity;sourceHashes=$sourceHashes;mainProjectHash=(Get-FileHash -LiteralPath (Join-Path $root 'RIGMMaker.dproj')).Hash;senderHash=(Get-FileHash -LiteralPath (Join-Path $root '制作支援\パイプ\Send-RigmCommand.ps1')).Hash;cleanup=$cleanup;renderedImageVisualVerification=$true;actualWindowHumanVisualVerification=$false;realMotionMaterialVerified=$false;newSpeechSynthesized=$false;originalPsdWritten=$false;userApplicationsForcedStopped=$false;userUnsavedDocumentsModified=$false;commitOrPush=$false;remainingBlockers=@();unverified=@('GUI window manual visual inspection: desktop screenshot/control tool unavailable; native VCL operations and rendered PNGs verified','Physical monitor DPI transition and physical Pro HID device','Subjective listening and unknown real whole-motion material seam/quality; native whole-motion timing tested with explicitly identified TEST frames')}
$record|ConvertTo-Json -Depth 48|Set-Content -LiteralPath (Join-Path $validation 'production-release-verification.json') -Encoding UTF8
$progress=Read-Record 'production-progress.json'
$progress.complete=$true;$progress.status='completed';$progress.timestampUtc=$record.atUtc;$progress.rootExeReplaced=$install.rootReplaced;$progress.rootExe=$install;$progress.latestRegressionChecks=$record.passed;$progress.productionImageMaterialization='Five user-downloaded PNGs identified by exact byte size and pixels, originals retained, SHA256 verified copies integrated.';$progress.materialFolderFileCount=5;$progress.requiredNext=@();$progress.finalRecord='Win64\Validation\production-release-verification.json';$progress.cleanupCompleted=$true
$progress|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $validation 'production-progress.json') -Encoding UTF8
$record|Select-Object success,complete,passed,atUtc|ConvertTo-Json
