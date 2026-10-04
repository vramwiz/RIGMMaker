#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validation=Join-Path $root 'Win64\Validation'
function Json([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
function Passes([string]$Log){[regex]::Matches([IO.File]::ReadAllText((Join-Path $validation $Log)),'(?m)^PASS:').Count}
$interim=Json (Join-Path $validation 'anime-interim-checkpoint.json')
foreach($item in $interim.sourceHashes){if((Get-FileHash -LiteralPath $item.path).Hash -ne $item.sha256){throw ('Source changed after final compilation: '+$item.path)}}
if((Get-FileHash -LiteralPath (Join-Path $root 'RIGMMaker.dproj')).Hash -ne $interim.mainProjectHash){throw 'Preserve and rebuild changed user project settings'}
foreach($configuration in @('Debug','Release')){
  $expected=if($configuration -eq 'Debug'){$interim.debugSha256}else{$interim.releaseSha256}
  if((Get-FileHash -LiteralPath (Join-Path $validation ($configuration+'\RIGMMaker.exe'))).Hash -ne $expected){throw 'Final build hash mismatch'}
}
$core=Passes 'anime-core-console.log'; $dpi=Passes 'anime-dpi-console.log'
if($core -ne 527 -or $dpi -ne 571){throw 'Fresh core/DPI count mismatch'}
$movie=Json (Join-Path $validation 'Movie\results.json')
$staged=Json (Join-Path $validation 'collaboration-results.json')
$workflow=Json (Join-Path $validation 'movie-workflow-results.json')
$production=Json (Join-Path $validation 'production-results.json')
$sender=Json (Join-Path $validation 'movie-sender-results.json')
$material=Json (Join-Path $validation 'quality-material.json')
$quality=Json (Join-Path $material.directory 'after-results.json')
$speech=Json (Join-Path $validation 'anime-preview-results.json')
$sync=Json (Join-Path $validation 'AnimePreview\Sync\sync-results.json')
$decodePaths=@((Join-Path $workflow.directory 'DecodedAVI\inspection.json'),(Join-Path $workflow.directory 'DecodedMP4\inspection.json'),(Join-Path $production.directory 'DecodedAVI\inspection.json'),(Join-Path $production.directory 'DecodedMP4\inspection.json'),(Join-Path $staged.directory 'DecodedCooperative\inspection.json'))
$decodes=@(foreach($path in $decodePaths){Json $path})
foreach($result in @($movie,$staged,$workflow,$production,$sender,$quality,$speech,$sync)+$decodes){if(-not $result.success){throw 'A final regression result is unsuccessful'}}
if($speech.syntheticFixture -or $speech.passed -ne 32 -or $sync.passed -ne 7){throw 'Actual speech verification is incomplete'}
if((Get-FileHash -LiteralPath $speech.source).Hash -ne $speech.sourceSha256){throw 'Registered original character changed'}
$total=$core+$dpi+$movie.passed+$staged.passed+$workflow.passed+$production.passed+$sender.passed+$quality.passed+$speech.passed+$sync.passed+($decodes|Measure-Object passed -Sum).Sum
$checkpoint=@{success=$true;stage='final actual speech preview, regression and Win64 builds complete; delivery and cleanup pending';atUtc=[DateTime]::UtcNow.ToString('o');freshPassed=$total;compiledRegressionPassed=$total-$speech.passed-$sync.passed-($decodes|Measure-Object passed -Sum).Sum;corePassed=$core;dpiPassed=$dpi;movie=$movie;staged=$staged;workflow=$workflow;production=$production;sender=$sender;quality=$quality;actualSpeech=$speech;sync=$sync;decodes=$decodes;project=$interim.project;durationSeconds=$interim.duration;engine=$interim.engine;releaseSha256=$interim.releaseSha256;debugSha256=$interim.debugSha256;mainProjectHash=$interim.mainProjectHash;sourceHashes=$interim.sourceHashes;realSpeechVerified=$true;subjectiveListeningVerified=$false;physicalMonitorTransitionVerified=$false;desktopScreenshotVerified=$false;paintToAndFrameImagesInspected=$true;normalPath='explicit staged collaboration with existing real VOICEVOX';aliasProvided=$false;cleanupCompleted=$false}
$checkpoint|ConvertTo-Json -Depth 64|Set-Content -LiteralPath (Join-Path $validation 'anime-checkpoint.json') -Encoding UTF8
$checkpoint|Select-Object success,freshPassed,compiledRegressionPassed,releaseSha256,debugSha256|ConvertTo-Json
