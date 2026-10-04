#requires -Version 7.0
param([ValidateSet('movie','production','fullhd','guided')][string]$Edition='movie',
      [ValidatePattern('^[A-Za-z0-9._-]+\.exe$')][string]$AliasName='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validation=Join-Path $root 'Win64\Validation'
$counts=[ordered]@{}
foreach($name in @('RigmTests','RigmControllerTests','RigmPsdTests','RigmClassificationTests','RigmOpenTests','RigmUiTests','RigmInteractionTests','RigmToolbarTests','RigmBoneTests','RigmApiTests','RigmPreviewTests')){
  $counts[$name]=(Select-String -LiteralPath (Join-Path $validation ($name+'.log')) -Pattern '^PASS:').Count
}
$sender=Get-Content (Join-Path $validation 'Sender\results.json') -Raw | ConvertFrom-Json
$counts['Sender']=$sender.passed
if(-not $sender.success -or (($counts.Values | Measure-Object -Sum).Sum -ne 527)){throw 'Expected complete 527 existing checks'}
$core=Get-Content (Join-Path $validation 'Movie\results.json') -Raw | ConvertFrom-Json
$workflow=Get-Content (Join-Path $validation 'movie-workflow-results.json') -Raw | ConvertFrom-Json
$movieSender=Get-Content (Join-Path $validation 'movie-sender-results.json') -Raw | ConvertFrom-Json
$avi=Get-Content (Join-Path $workflow.directory 'DecodedAVI\inspection.json') -Raw | ConvertFrom-Json
$mp4=Get-Content (Join-Path $workflow.directory 'DecodedMP4\inspection.json') -Raw | ConvertFrom-Json
if(-not ($core.success -and $workflow.success -and $movieSender.success -and $avi.success -and $mp4.success)){throw 'Movie validation is incomplete'}
$long=$null;$longInspection=$null;$additionalPassed=0
if($Edition -eq 'production'){
  $long=Get-Content (Join-Path $validation 'movie-long-results.json') -Raw | ConvertFrom-Json
  $longInspection=Get-Content (Join-Path $validation 'movie-long-inspection.json') -Raw | ConvertFrom-Json
  if(-not ($long.success -and $longInspection.success) -or $long.duration -ne 180 -or $longInspection.frames -ne 2700){throw 'Three minute validation is incomplete'}
  if((Get-FileHash -LiteralPath $longInspection.video).Hash -ne $longInspection.sha256){throw 'Long validation video changed'}
  $additionalPassed=$long.passed+$longInspection.passed
}
$fullhd=$null;$fullhdInspection=$null;$quality=$null
if($Edition -in @('fullhd','guided')){
  $fullhd=Get-Content (Join-Path $validation 'movie-1080-latest.json') -Raw | ConvertFrom-Json
  $fullhdInspection=Get-Content (Join-Path $validation 'movie-1080-inspection.json') -Raw | ConvertFrom-Json
  $material=Get-Content (Join-Path $validation 'quality-material.json') -Raw | ConvertFrom-Json
  $quality=Get-Content (Join-Path $material.directory 'after-results.json') -Raw | ConvertFrom-Json
  $cancel=Get-Content (Join-Path $workflow.directory 'encoder-cancel.json') -Raw | ConvertFrom-Json
  if(-not ($fullhd.success -and $fullhdInspection.success -and $quality.success) -or $fullhd.duration -ne 180 -or $fullhdInspection.frames -ne 5400){throw 'Full HD real material validation incomplete'}
  if($core.passed -lt 73 -or $workflow.passed -lt 104 -or $quality.passed -lt 22 -or $fullhdInspection.passed -lt 18){throw 'Missing new regression checks'}
  if($cancel.state -ne 'cancelled' -or -not $cancel.encoderExited){throw 'Encoder cancellation not verified'}
  if((Get-FileHash -LiteralPath $fullhdInspection.video).Hash -ne $fullhdInspection.sha256){throw 'Full HD validation video changed'}
  if((Get-FileHash -LiteralPath $material.source).Hash -ne $material.originalSha256){throw 'Original material changed'}
  if((Get-FileHash -LiteralPath (Join-Path $root 'RIGMMaker.production.exe')).Hash -ne 'DCA180F0D501380C93ECDFD09F82C2D3870F6F83F6B65B9F51C63D590EA300F0'){throw 'Protected production executable changed'}
  $additionalPassed=$quality.passed+$fullhdInspection.passed
  if($Edition -eq 'guided'){
    if($core.passed -lt 102 -or $workflow.passed -lt 125 -or $movieSender.passed -lt 14){throw 'Guided preparation regression is incomplete'}
    $baseline=Get-Content (Join-Path $validation 'fullhd-release-verification.json') -Raw | ConvertFrom-Json
    if((Get-FileHash (Join-Path $root 'RIGMMaker.fullhd.exe')).Hash -ne $baseline.releaseSha256){throw 'Protected fullhd executable changed'}
    $unchangedOutputUnits=@(foreach($file in @('RigmMovieRendering.pas','RigmMovieActing.pas','RigmMovieAudio.pas','RigmMovieAvi.pas','RigmMovieOutput.pas')){
      $matches=@(Get-ChildItem -LiteralPath (Join-Path $root 'Source\Studio') -Filter $file -Recurse -File)
      if($matches.Count -ne 1){throw ('Expected exactly one source unit: '+$file)}
      $path=$matches[0].FullName
      # Older records store the paths from before the responsibility folders were introduced.
      $old=@($baseline.sourceHashes | Where-Object { [IO.Path]::GetFileName($_.path) -eq $file })
      if($old.Count -ne 1){throw ('Expected exactly one baseline source unit: '+$file)}
      $hash=(Get-FileHash $path).Hash
      if($hash -ne $old.sha256){throw ('Retained fullhd benchmark is invalid for changed '+$file)}
      @{path=$path;sha256=$hash;matchesFullhdBaseline=$true}
    })
  }
}
$logs=@('build-Debug.log','build-Release.log','build-RigmMovieTests.log','build-MovieWorkflowTests.log')+@($counts.Keys | Where-Object {$_ -ne 'Sender'} | ForEach-Object {'build-'+$_+'.log'})
if($Edition -eq 'production'){$logs+=@('build-MovieLongTests.log')}
if($Edition -eq 'fullhd'){$logs+=@('build-MovieQualityTests.log','build-Movie1080Tests.log')}
if($Edition -eq 'guided'){$logs+=@('build-MovieQualityTests.log')}
foreach($name in $logs){if((Get-Content (Join-Path $validation $name) -Raw) -match '\b[WEH]\d{4}\b'){throw ('Compiler diagnostics in '+$name)}}
$id=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
$preserved=Join-Path $root ('Win64\PreservedArtifacts\before-'+$Edition+'-'+$id)
New-Item -ItemType Directory -Path $preserved | Out-Null
$originals=@(Get-ChildItem -LiteralPath $root -Filter '*.exe' -File | ForEach-Object {
  $hash=(Get-FileHash -LiteralPath $_.FullName).Hash
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $preserved $_.Name)
  if((Get-FileHash -LiteralPath (Join-Path $preserved $_.Name)).Hash -ne $hash){throw 'Executable backup verification failed'}
  @{name=$_.Name;path=$_.FullName;sha256=$hash}
})
$alias=Join-Path $root ('RIGMMaker.'+$Edition+'.exe')
if($AliasName){$alias=Join-Path $root $AliasName}
if(Test-Path -LiteralPath $alias){$alias=Join-Path $root ('RIGMMaker.'+$Edition+'-'+$id+'.exe')}
$release=Join-Path $validation 'Release\RIGMMaker.exe'
Copy-Item -LiteralPath $release -Destination $alias
$releaseHash=(Get-FileHash -LiteralPath $release).Hash
if((Get-FileHash -LiteralPath $alias).Hash -ne $releaseHash){throw 'Release copy verification failed'}
foreach($original in $originals){if((Get-FileHash -LiteralPath $original.path).Hash -ne $original.sha256){throw 'Existing root executable changed'}}
$smokeDirectory=Join-Path $validation ($Edition+'Smoke\'+$id)
New-Item -ItemType Directory -Path $smokeDirectory -Force | Out-Null
$process=Start-Process -FilePath $alias -ArgumentList @(('"--data-dir='+$smokeDirectory+'\Library"'),('"--pipe-dir='+$smokeDirectory+'\Pipes"')) -WindowStyle Hidden -PassThru
$smoke=@{directory=$smokeDirectory;pid=$process.Id;inputIdle=$false;normalClose=$false;exitCode=$null}
try {
  $smoke.inputIdle=$process.WaitForInputIdle(10000)
  Start-Sleep -Milliseconds 300;$process.Refresh()
  if($process.HasExited){throw 'Release exited before startup check'}
  $smoke.mainWindowTitle=$process.MainWindowTitle
  if(-not $process.CloseMainWindow()){throw 'Could not request normal close of own isolated release'}
  $smoke.normalClose=$process.WaitForExit(10000)
  if(-not $smoke.normalClose){throw 'Isolated release did not close normally; no force termination performed'}
  $smoke.exitCode=$process.ExitCode
  if($smoke.exitCode -ne 0){throw 'Release startup/close returned nonzero exit'}
}finally{$process.Dispose()}
$sourceHashes=@(Get-ChildItem -LiteralPath @((Join-Path $root 'Source\Studio'),(Join-Path $root 'Source\Shell\CharacterEditor')) -Filter '*.pas' -Recurse -File | ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$record=@{success=$true;atUtc=[DateTime]::UtcNow.ToString('o');existingCounts=$counts;existingPassed=527;movieCore=$core;movieWorkflow=$workflow;movieSender=$movieSender;avi=$avi;mp4=$mp4;totalPassed=527+$core.passed+$workflow.passed+$movieSender.passed+$avi.passed+$mp4.passed;compilerDiagnostics=0;debugSha256=(Get-FileHash (Join-Path $validation 'Debug\RIGMMaker.exe')).Hash;releaseSha256=$releaseHash;alias=$alias;preservedDirectory=$preserved;preservedExecutables=$originals;smoke=$smoke;sourceHashes=$sourceHashes;rootExeReplaced=$false;liveDocumentCommandsSent=$false;userApplicationsTerminated=$false;realVoicevoxSpeechVerified=$false;audioFixture='explicit local test tone HTTP fixture, not VOICEVOX speech';limitations=@('real VOICEVOX engine repair awaits user permission','physical desktop mouse/controller and multi-monitor DPI not verified','true side views and new expression assets are not synthesized; existing RIGM variants and parameter acting only','MP4 uses AVI staging and retains 2GB AVI limit')}
$record.totalPassed+=$additionalPassed
$record['edition']=$Edition;$record['longExport']=$long;$record['longInspection']=$longInspection
$record['cancelMeasurements']=@(Get-ChildItem -LiteralPath $workflow.directory -Filter 'cancel-metrics*.json' | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json})
$record['visualEvidence']=@(Get-ChildItem -LiteralPath $workflow.directory -Filter 'studio-*.png' | ForEach-Object {$_.FullName})
$record['visualMethod']='own VCL test forms PaintTo capture; physical desktop operation not claimed'
$record['longValidationScope']='640x360, 15 fps, 180 seconds, 60 cues/6 scenes, sample RIGM, explicit test tone; app memory excludes FFmpeg child; no 1080p/real-material performance claim'
if($Edition -in @('fullhd','guided')){
  $record['fullhdExport']=$fullhd;$record['fullhdInspection']=$fullhdInspection;$record['quality']=$quality
  $record['material']=$material;$record['encoderCancellation']=$cancel
  $record['longValidationScope']='1920x1080, 30fps, 180s, 60 cues/6 scenes, independent stored Kiritan copy prepared with six bones/5x5 meshes, actual pose/brow variants; explicit test tone; app and own FFmpeg child memory sampled separately'
  $record['performanceBuildScope']='Measured console export build precedes encoder PID/cleanup telemetry and UI wiring; final same renderer/audio/preset path verified by core/real asset/GUI/export/cancel regression'
  $record['limitations']+=@('original Kiritan contains no bones/meshes; preparation only in independent validation copy','remaining time estimates cover current render or encode phase, not both phases combined','fast measured; balanced/quality choices are tested for persistence and cancellation, not three-minute speed benchmarks','largest material/dense mesh workload and physical controller remain unmeasured')
  $record['copyOriginals']=@(Get-Content (Join-Path $validation 'production-library-originals.json') -Raw | ConvertFrom-Json | ForEach-Object {if((Get-FileHash -LiteralPath $_.source).Hash -ne $_.sha256){throw 'Copied library original changed'};$_})
}
if($Edition -eq 'guided'){
  $record['freshPassed']=$record.totalPassed-$fullhdInspection.passed
  $record['retainedFullhdPassed']=$fullhdInspection.passed
  $record['unchangedOutputUnits']=$unchangedOutputUnits
  $record['performanceBuildScope']='Retained fullhd 180s benchmark and independent decode from previous completed release; five renderer/acting/audio/AVI/output units match that baseline by SHA256. This release reruns short AVI/MP4, real-material, complete regression, diagnosis and UI tests; no new 180s speed measurement.'
  $record['preparationReadOnly']=$true;$record['scopeComplete']=$true
  $record['externalSpeechBlocker']='Existing VOICEVOX missing engine_internal/setuptools/_vendor/jaraco/text/Lorem ipsum.txt; repair not authorized or performed; real Japanese speech remains unverified.'
  $record['practicalLimitations']=@('existing face/pose sprites only; no synthesized natural side/back view or new expression images','head/body motion requires prepared bones and meshes; static display and existing pose groups remain available','AVI staging has 2GB ceiling even for MP4','preflight time/storage are heuristics; write permission and FFmpeg codec/launch are checked by actual export rather than read-only diagnosis','GUI material chooser displays first 20 groups; pipe assets supports pagination')
  $record['unverifiedUsage']=@('physical desktop mouse/Pro HID and multi-monitor DPI','real VOICEVOX Japanese speech and lip sync with real speech','three-minute balanced/quality and largest dense-mesh performance')
}
$record | ConvertTo-Json -Depth 32 | Set-Content (Join-Path $validation ($Edition+'-release-verification.json')) -Encoding utf8
$record | Select-Object success,totalPassed,alias,releaseSha256,preservedDirectory,smoke | ConvertTo-Json -Depth 6
