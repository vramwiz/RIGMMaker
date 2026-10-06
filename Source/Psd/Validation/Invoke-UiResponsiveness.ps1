param([ValidateSet('before','after')][string]$Phase='after',[ValidateSet('Debug','Release','Current')][string]$Configuration='Release',[string]$ExecutablePath='')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-UiCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters'),(Join-Path $root 'RIGM')|Out-Null
Copy-Item -LiteralPath 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar' -Destination (Join-Path $root 'Characters\fixture.psdchar')
Copy-Item -LiteralPath 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psd' -Destination (Join-Path $root 'Characters\fixture.psd')
Get-ChildItem -LiteralPath 'D:\Users\take6\RIGMMaker\RIGM' -Filter *.rigm -File|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $root 'RIGM')}
'{"owner":"RIGMMaker.GuiValidation.v1"}'|Set-Content -LiteralPath (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$out=Join-Path $repo ('Win64\Validation\PsdStudio\ui-performance-'+$Phase+'-'+$Configuration.ToLower()+'.json')
$exe=Join-Path $repo 'RIGMMaker.exe'
if($ExecutablePath -ne ''){$exe=[IO.Path]::GetFullPath($ExecutablePath)}
$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--verify-ui-responsiveness',('"'+$out+'"')) -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(80);$captured=@{}
while(-not $process.HasExited){
 $requestPath=$out+'.capture-request.json'
 if(Test-Path -LiteralPath $requestPath){
  $request=$null
  try {
   $stream=[IO.File]::Open($requestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
   $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
   try {$request=$reader.ReadToEnd()|ConvertFrom-Json} finally {$reader.Dispose()}
  } catch [IO.IOException] { }
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($out+$request.stage+'.png')
   $request.token|Set-Content -LiteralPath ($out+'.capture-ack.txt') -Encoding UTF8
   $captured[$request.token]=$true
  }
 }
 if([DateTime]::UtcNow -gt $deadline){throw ('Owned UI check remains active: '+$process.Id)}
 Start-Sleep -Milliseconds 100
}
$process.WaitForExit()
if($process.ExitCode -ne 0){if(Test-Path -LiteralPath ($out+'.error.txt')){Get-Content -LiteralPath ($out+'.error.txt') -Encoding UTF8};throw 'UI responsiveness check failed'}
$result=Get-Content -LiteralPath $out -Raw -Encoding UTF8|ConvertFrom-Json
if($Phase -eq 'after'){
 if(-not $result.thumbnailMode -or -not $result.creationThumbnailMode -or -not $result.sameEditor -or $result.hiddenFrames -ne 0 -or $result.pausedFrames -ne 0 -or $result.viewUiBuilds -ne 0 -or $result.animatedFrames -lt 1 -or -not $result.loadingPaintedBeforeRead -or -not $result.stageIcons -or -not $result.previewRetainsFrameOnErase -or -not $result.opened.previewOwnWindow -or -not $result.failedLoadRetainsEditor){throw 'Expected UI optimization missing'}
 if($result.layoutChecks -ne 81 -or -not $result.wheelZoomAndLeftDrag -or -not $result.referenceClickAndDrag){throw 'Expected preview layout or interaction checks missing'}
 if(-not $result.taskbarWindow -or -not $result.taskbarIcons -or -not $result.firstFrameReadyBeforeEditor -or $result.loadingLifecycleChecks -ne 4){throw 'Expected taskbar icon or PSD loading lifecycle checks missing'}
}
@{phase=$Phase;configuration=$Configuration;root=$root;result=$out;exe=$exe;exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;normalExit=$true}|ConvertTo-Json|Set-Content -LiteralPath ($out+'.metadata.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 4
