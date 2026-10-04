#requires -Version 7.0
param([string]$NativeExe,[switch]$Execute,[string]$Prefix='cleanup',[switch]$TestsOnly,[switch]$FailedAnimeTests)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if($root -ne 'D:\DelphiProg\RIGMMaker'){throw 'Unexpected workspace'}
$validation=Join-Path $root 'Win64\Validation'
$planPath=Join-Path $validation ($Prefix+'-plan.json')
$resultPath=Join-Path $validation ($Prefix+'-result.json')
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Inventory([string]$Path){
  $item=Get-Item -LiteralPath $Path -Force
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point rejected'}
  if($item.PSIsContainer){
    $files=@(Get-ChildItem -LiteralPath $Path -Recurse -Force -File|ForEach-Object{
      if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point rejected'}
      @{relative=[IO.Path]::GetRelativePath($Path,$_.FullName);sha256=(Sha $_.FullName);bytes=$_.Length}
    })
  }else{$files=@(@{relative='';sha256=(Sha $Path);bytes=$item.Length})}
  @{path=$item.FullName;directory=$item.PSIsContainer;files=$files;bytes=($files|Measure-Object bytes -Sum).Sum}
}
if(-not $Execute){
  $delivery=Get-Content -LiteralPath (Join-Path $validation 'ai-release-verification.json') -Raw|ConvertFrom-Json
  $active=@(Get-Process -ErrorAction Stop|ForEach-Object{try{if($_.Path){[IO.Path]::GetFullPath($_.Path)}}catch{}})
  $targets=[Collections.Generic.List[object]]::new()
  $skipped=[Collections.Generic.List[object]]::new()
  function AddTarget([string]$Path,[string]$Reason){
    $absolute=[IO.Path]::GetFullPath($Path)
    if(-not $absolute.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Outside workspace'}
    if($active -contains $absolute){$skipped.Add(@{path=$absolute;reason='running executable'});return}
    if(@($targets|Where-Object {$_.directory -and $absolute.StartsWith($_.path+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){return}
    $record=Inventory $absolute;$record.reason=$Reason;$targets.Add($record)
  }
  $old=if($TestsOnly){@()}else{@($delivery.preservedExecutables|Where-Object name -ne 'RIGMMaker.exe')}
  foreach($oldExe in $old){
    foreach($file in @(Get-ChildItem -LiteralPath $root -Filter $oldExe.name -File)+@(Get-ChildItem -LiteralPath (Join-Path $root 'Win64\PreservedArtifacts') -Filter $oldExe.name -Recurse -File)){
      if((Sha $file.FullName) -eq $oldExe.sha256){AddTarget $file.FullName 'superseded task alias; matches preserved SHA256'}
      else{$skipped.Add(@{path=$file.FullName;reason='different/unknown build hash'})}
    }
  }
  $testNames=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.dpr'|ForEach-Object{$_.BaseName+'.exe'})
  foreach($file in Get-ChildItem -LiteralPath $validation -Recurse -Filter '*.exe' -File){
    if($file.Name -in $testNames){AddTarget $file.FullName 'compiled permanent regression/helper source'}
    else{$skipped.Add(@{path=$file.FullName;reason='product build or executable without test-source provenance'})}
  }
  foreach($dir in Get-ChildItem -LiteralPath $validation -Recurse -Directory|Where-Object Name -like '*Dcu'){
    $files=@(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File)
    if(@($files|Where-Object Extension -ne '.dcu').Count -eq 0){AddTarget $dir.FullName 'compiler-only DCU directory'}
  }
  foreach($name in @('RigmCollaborationTests.map','RigmCollaborationTests.drc','RigmCompositionTests.map','RigmCompositionTests.drc')){
    $path=Join-Path $validation $name
    if(Test-Path -LiteralPath $path){AddTarget $path 'map/resource-string output of current collaboration test runner'}
  }
  $uiFixtures=Join-Path $validation 'UiRevisionFixture'
  if(Test-Path -LiteralPath $uiFixtures){
    foreach($dir in Get-ChildItem -LiteralPath $uiFixtures -Recurse -Directory -Filter '*.assets'){
      AddTarget $dir.FullName 'asset copies created only by the owned UI revision history/save fixtures'
    }
  }
  $movieRoots=@('Movie','Movie1080','MovieLong','MovieSender','MovieWorkflow','Quality','CollaborationFixture','Resume','CompositionFixture','ProductionStartup','ProductionFixture','UiRevisionFixture','TimelineExportFixture')
  foreach($category in $movieRoots){
    $path=Join-Path $validation $category
    if(Test-Path -LiteralPath $path){
      foreach($file in Get-ChildItem -LiteralPath $path -Recurse -File|Where-Object {$_.Name.EndsWith('.rigmovie') -or $_.Name.EndsWith('.rigmovie.bak')}){
        $json=Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8|ConvertFrom-Json
        if($json.format -eq 'RIGM-MOVIE'){AddTarget $file.FullName 'project saved by permanent movie regression runner'}
        else{$skipped.Add(@{path=$file.FullName;reason='unexpected movie format'})}
      }
    }
  }
  foreach($category in @('CompositionFixture','Quality','Classification','ProductionStartup','UiRevisionFixture')){
    $path=Join-Path $validation $category
    if(Test-Path -LiteralPath $path){
      foreach($file in Get-ChildItem -LiteralPath $path -Recurse -File|Where-Object {$_.Name.EndsWith('.rigm') -or $_.Name.EndsWith('.rigm.bak') -or ($category -eq 'Classification' -and $_.Name -like 'readonly-input-*.psd')}){
        AddTarget $file.FullName 'owned character/import copy in dedicated permanent regression fixture directory'
      }
    }
  }
  $guiDeliveryPath=Join-Path $validation 'timeline-export-documents-delivery.json'
  if($TestsOnly -and (Test-Path -LiteralPath $guiDeliveryPath)){
    $gui=Get-Content -LiteralPath $guiDeliveryPath -Raw -Encoding utf8|ConvertFrom-Json
    $decode=Get-Content -LiteralPath (Join-Path $validation 'timeline-export-independent-decode.json') -Raw -Encoding utf8|ConvertFrom-Json
    $owned=[IO.Path]::GetFullPath($gui.sourceGuiExport)
    $expected=Join-Path $validation 'TimelineExportFixture'
    if(-not $owned.StartsWith($expected+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($owned) -ne 'gui-menu-real-speech.mp4'){throw 'Unrecognized owned GUI export'}
    if(-not $gui.success -or -not $decode.success -or $decode.path -ne $owned -or $gui.sha256 -ne $decode.sha256 -or $gui.delivered -eq $owned -or (Sha $gui.delivered) -ne $gui.sha256){throw 'GUI MP4 delivery/decode recovery evidence mismatch'}
    if(Test-Path -LiteralPath $owned){
      if((Sha $owned) -ne $gui.sha256){throw 'GUI test export changed'}
      AddTarget $owned 'owned full GUI MP4 test output; independent decode passed and byte-identical Documents delivery preserved'
    }
  }
  if($FailedAnimeTests){
    $final=Get-Content -LiteralPath (Join-Path $validation 'anime-preview-results.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $productionRoot=Join-Path $root '制作成果'
    foreach($suffix in @('20261003T223612744','20261003T223808068','20261003T223956057')){
      $failed=Join-Path $productionRoot ('星灯り郵便局-'+$suffix)
      if(-not(Test-Path -LiteralPath $failed)){continue}
      if($failed -eq $final.directory){throw 'Final user production is protected'}
      $report=Get-Content -LiteralPath (Join-Path $failed 'verification.json') -Raw -Encoding UTF8|ConvertFrom-Json
      if($report.success -or $report.directory -ne $failed -or $report.source -ne $final.source -or $report.sourceSha256 -ne $final.sourceSha256){throw 'Unrecognized failed test output'}
      if(@($active|Where-Object {[IO.Path]::GetFileName($_) -like 'RIGMMaker*.exe'}).Count){$skipped.Add(@{path=$failed;reason='user application present; preserve project tests'})}
      else{AddTarget $failed 'explicit unsuccessful anime test run; final successful production is preserved'}
    }
  }
  @{root=$root;atUtc=[DateTime]::UtcNow.ToString('o');targets=@($targets);skipped=@($skipped);protected=@('all root and preserved executable builds in tests-only mode','final Debug/Release products','all Source/Tests/documents and result JSON/logs','final successful anime production including all WAV/assets/script/documents','all other RIGM/PSD and media evidence','unknown builds and live/user data');nativeMethod='force recycle only, never permanent delete'}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $planPath -Encoding utf8
  @{planned=$targets.Count;bytes=($targets|Measure-Object bytes -Sum).Sum;skipped=$skipped.Count}|ConvertTo-Json
  return
}
if(-not $NativeExe -or -not (Test-Path -LiteralPath $NativeExe)){throw 'Provide native helper compiled in Temp'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$recycleRoot=Join-Path 'D:\$Recycle.Bin' $sid
Get-ChildItem -LiteralPath $recycleRoot -Force -ErrorAction Stop|Out-Null
$plan=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json
if($plan.root -ne $root){throw 'Plan root mismatch'}
$active=@(Get-Process|ForEach-Object{try{$_.Path}catch{}})
foreach($target in $plan.targets){
  $path=[IO.Path]::GetFullPath($target.path)
  if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $path -in @((Join-Path $root 'RIGMMaker.exe'),(Join-Path $root 'RIGMMaker.ai.exe'),(Join-Path $root 'RIGMMaker.workflow.exe'),(Join-Path $root 'RIGMMaker.preview.exe'),(Join-Path $root 'RIGMMaker.resume.exe')) -or $active -contains $path){throw "Protected or running path: $path"}
  foreach($file in $target.files){$source=if($target.directory){Join-Path $path $file.relative}else{$path};if((Sha $source) -ne $file.sha256){throw "Changed since plan: $source"}}
}
& $NativeExe $planPath (Join-Path $validation ($Prefix+'-native-result.json'))
$native=Get-Content -LiteralPath (Join-Path $validation ($Prefix+'-native-result.json')) -Raw|ConvertFrom-Json
$verified=[Collections.Generic.List[object]]::new()
foreach($target in $plan.targets){
  $item=@($native.items|Where-Object sourcePath -eq $target.path|Where-Object recycleItemReturned|Select-Object -Last 1)
  $location=if($item.Count){$item[0].recycleLocation}else{''}
  $ok=$false;$metadata=''
  if($location -and $location.StartsWith($recycleRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
    $metadata=Join-Path (Split-Path -Parent $location) ((Split-Path -Leaf $location) -replace '^\$R','$$I')
    if((Test-Path -LiteralPath $metadata) -and (Test-Path -LiteralPath $location) -and -not (Test-Path -LiteralPath $target.path)){
      $bytes=[IO.File]::ReadAllBytes($metadata)
      $version=[BitConverter]::ToInt64($bytes,0)
      $offset=if($version -eq 2){28}else{24}
      $original=[Text.Encoding]::Unicode.GetString($bytes,$offset,$bytes.Length-$offset).TrimEnd([char]0)
      $ok=$original -eq $target.path
      foreach($file in $target.files){$payload=if($target.directory){Join-Path $location $file.relative}else{$location};if(-not (Test-Path -LiteralPath $payload) -or (Sha $payload) -ne $file.sha256){$ok=$false}}
    }
  }
  $verified.Add(@{path=$target.path;reason=$target.reason;bytes=$target.bytes;recycleLocation=$location;recycleMetadata=$metadata;recoverableVerified=$ok})
}
$success=$native.success -and @($verified|Where-Object {-not $_.recoverableVerified}).Count -eq 0
@{success=$success;atUtc=[DateTime]::UtcNow.ToString('o');accountSid=$sid;method='IFileOperation force recycle; original path metadata and every payload SHA256 verified';permanentDeleteFallback=$false;count=$verified.Count;bytes=($verified|Measure-Object bytes -Sum).Sum;items=@($verified);restore='Windows Recycle Bin: select the corresponding original filename/path and Restore. Exact $I/$R paths are recorded.'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding utf8
@{success=$success;count=$verified.Count;bytes=($verified|Measure-Object bytes -Sum).Sum;unverified=@($verified|Where-Object {-not $_.recoverableVerified}).Count}|ConvertTo-Json
if(-not $success){throw 'Recycle verification incomplete; no permanent-delete fallback was attempted'}
