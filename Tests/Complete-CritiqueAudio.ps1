#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile,[ValidateRange(0,45)][int]$WaitSeconds=0)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$deadline=[DateTime]::UtcNow.AddSeconds($WaitSeconds)
do{
  $job=Invoke-Product 'movie-job-status' @{jobId=$run.audioJobId}
  $job | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'audio-status.json') -Encoding utf8BOM
  if($job.done -or [DateTime]::UtcNow -ge $deadline){break}
  Start-Sleep -Milliseconds 1000
}while($true)
if(-not $job.done){$job | Select-Object state,completed,total,elapsedSeconds | ConvertTo-Json;return}
if($job.state -ne 'succeeded' -or -not $job.collected -or $job.staleResult){
  throw ('Real voice generation was not collected successfully: '+($job | ConvertTo-Json -Compress))
}
$null=Invoke-Product 'movie-save' @{path=$run.movie}
$opened=Invoke-Product 'movie-open' @{path=$run.movie}
$project=Invoke-Product 'movie-project' @{offset=0;limit=100}
$inputProject=[IO.File]::ReadAllText((Join-Path $run.runDirectory 'production-input.json')) | ConvertFrom-Json -AsHashtable
$cueReport=@();$elapsed=0.0;$speech=0.0
if($project.cues.Count -ne 18){throw 'Reopened work has a different cue count'}
for($i=0;$i -lt $project.cues.Count;$i++){
  $cue=$project.cues[$i];$expected=$inputProject.cues[$i]
  $emotion=if($cue.emotion){$cue.emotion}else{'neutral'}
  if($cue.text -ne $expected.text -or $cue.subtitle -ne $expected.subtitle -or $emotion -ne $expected.emotion -or $cue.acting.variants.Count -ne $expected.acting.variants.Count){
    throw ('Reopened work does not preserve narration, subtitles, emotion or real variants: '+$cue.id)
  }
  $wave=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $run.movie) $cue.waveFile))
  $lab=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $run.movie) $cue.labFile))
  if(-not $cue.audioKey -or $cue.audioSeconds -le 0 -or -not (Test-Path -LiteralPath $wave -PathType Leaf) -or -not (Test-Path -LiteralPath $lab -PathType Leaf)){
    throw ('Real generated audio or alignment is missing: '+$cue.id)
  }
  $labels=@([IO.File]::ReadAllLines($lab));if($labels.Count -lt 3){throw ('No real phoneme alignment: '+$cue.id)}
  $cueReport+=@{id=$cue.id;scene=$cue.scene;emotion=$emotion;start=$elapsed;audioSeconds=$cue.audioSeconds;pause=$cue.pause;wave=$wave;lab=$lab;labelCount=$labels.Count;waveSha256=(Get-FileHash -LiteralPath $wave -Algorithm SHA256).Hash;labSha256=(Get-FileHash -LiteralPath $lab -Algorithm SHA256).Hash}
  $elapsed+=$cue.audioSeconds+$cue.pause;$speech+=$cue.audioSeconds
}
if([Math]::Abs($opened.duration-$elapsed) -gt 0.001){throw 'Actual timeline does not match the eighteen speech clips and pauses'}
if((Get-FileHash -LiteralPath $run.sourceMovie -Algorithm SHA256).Hash -ne $run.sourceMovieSha256){throw 'Original user work changed'}
if((Get-FileHash -LiteralPath $run.rig -Algorithm SHA256).Hash -ne $run.rigSha256){throw 'Prepared source rig changed'}
$ready=Invoke-Product 'movie-preparation'
if($ready.audioPending -ne 0){throw 'Product says that one or more voice clips are stale'}
$report=@{
  success=$true;actualEngine=$project.engineUrl;voiceStyleId=108;voiceSpeed=$project.speakers[0].speed
  cueCount=$project.cues.Count;speechSeconds=$speech;pauseSeconds=($elapsed-$speech);timelineSeconds=$elapsed
  savedAndReopened=$true;movie=$run.movie;movieSha256=(Get-FileHash -LiteralPath $run.movie -Algorithm SHA256).Hash
  projectId=$opened.projectId;revision=$opened.revision;audioPending=$ready.audioPending
  sourceUnchanged=$true;rigUnchanged=$true;cues=$cueReport;completedUtc=[DateTime]::UtcNow.ToString('o')
}
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'audio-results.json') -Encoding utf8BOM
$ready | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'preparation-after-audio.json') -Encoding utf8BOM
$run.stage='real speech generated, saved and reopened';$run.actualSeconds=$elapsed;$run.speechSeconds=$speech
$run | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $RunFile -Encoding utf8BOM
$report | Select-Object success,cueCount,timelineSeconds,speechSeconds,pauseSeconds,movie,audioPending | ConvertTo-Json -Depth 5
