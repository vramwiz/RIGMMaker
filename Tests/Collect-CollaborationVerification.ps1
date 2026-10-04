#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validation=Join-Path $root 'Win64\Validation'
function Json([string]$Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Passes([string]$Log){[regex]::Matches([IO.File]::ReadAllText((Join-Path $validation $Log)),'(?m)^PASS:').Count}
$core=Passes 'collaboration-core-console.log';$dpi=Passes 'collaboration-dpi-console.log'
$movie=Json (Join-Path $validation 'Movie\results.json')
$staged=Json (Join-Path $validation 'collaboration-results.json')
$legacy=Json (Join-Path $validation 'movie-workflow-results.json')
$batch=Json (Join-Path $validation 'production-results.json')
$sender=Json (Join-Path $validation 'movie-sender-results.json')
$material=Json (Join-Path $validation 'quality-material.json')
$quality=Json (Join-Path $material.directory 'after-results.json')
$decodePaths=@((Join-Path $legacy.directory 'DecodedAVI\inspection.json'),(Join-Path $legacy.directory 'DecodedMP4\inspection.json'),(Join-Path $batch.directory 'DecodedAVI\inspection.json'),(Join-Path $batch.directory 'DecodedMP4\inspection.json'),(Join-Path $staged.directory 'DecodedCooperative\inspection.json'))
$decodes=@(foreach($path in $decodePaths){Json $path})
foreach($result in @($movie,$staged,$legacy,$batch,$sender,$quality)+$decodes){if(-not $result.success){throw 'Expected regression success is missing'}}
if($core -ne 527 -or $dpi -ne 547){throw 'Core/DPI count mismatch'}
$total=$core+$movie.passed+$dpi+$staged.passed+$legacy.passed+$batch.passed+$sender.passed+$quality.passed+($decodes|Measure-Object passed -Sum).Sum
$checkpoint=@{success=$true;stage='final collaboration regression and Win64 builds complete; delivery and cleanup pending';atUtc=[DateTime]::UtcNow.ToString('o');freshPassed=$total;corePassed=$core;dpiPassed=$dpi;movie=$movie;staged=$staged;workflow=$legacy;production=$batch;sender=$sender;quality=$quality;decodes=$decodes;releaseSha256=(Get-FileHash -LiteralPath (Join-Path $validation 'Release\RIGMMaker.exe')).Hash;debugSha256=(Get-FileHash -LiteralPath (Join-Path $validation 'Debug\RIGMMaker.exe')).Hash;mainProjectHash=(Get-FileHash -LiteralPath (Join-Path $root 'RIGMMaker.dproj')).Hash;sourceHashes=@(Get-ChildItem -LiteralPath (Join-Path $root 'Source') -Recurse -File|Where-Object Extension -in @('.pas','.dfm')|ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}});realSpeechVerified=$false;physicalMonitorTransitionVerified=$false;normalPath='explicit staged collaboration';batchPath='optional compatibility';aliasProvided=$false;cleanupCompleted=$false}
$initial=Join-Path $validation 'collaboration-initial-checkpoint.json'
if(-not(Test-Path -LiteralPath $initial)){Copy-Item -LiteralPath (Join-Path $validation 'collaboration-checkpoint.json') -Destination $initial}
$checkpoint|ConvertTo-Json -Depth 64|Set-Content -LiteralPath (Join-Path $validation 'collaboration-checkpoint.json') -Encoding utf8
$checkpoint|Select-Object success,freshPassed,releaseSha256,debugSha256|ConvertTo-Json
