#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile,[switch]$Decode)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
if(-not $run.exportJobId){throw 'No export job is registered; this command does not start one'}
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$job=Invoke-Product 'movie-job-status' @{jobId=$run.exportJobId}
$job | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'export-status.json') -Encoding utf8BOM
if(-not $job.done){
  $job | Select-Object state,phase,completed,total,phaseCompleted,phaseTotal,elapsedSeconds,remainingSeconds | ConvertTo-Json
  return
}
if($job.state -ne 'succeeded' -or -not $job.collected -or -not $job.encoderExited -or $job.staleResult -or -not (Test-Path -LiteralPath $run.output -PathType Leaf)){
  throw ('Actual MP4 export did not succeed: '+($job | ConvertTo-Json -Compress))
}
$workflow=Invoke-Product 'movie-workflow-status'
if($workflow.currentStage -eq 'export'){
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while($workflow.busy -and [DateTime]::UtcNow -lt $deadline){
    Start-Sleep -Milliseconds 100
    $workflow=Invoke-Product 'movie-workflow-status'
  }
  if(-not $workflow.canNext){throw ('Finished video is not current in product workflow: '+($workflow | ConvertTo-Json -Depth 15 -Compress))}
  $workflow=Invoke-Product 'movie-workflow-next'
}
if($workflow.currentStage -ne 'complete'){throw 'Actual production workflow did not reach complete'}
$null=Invoke-Product 'movie-save' @{path=$run.movie}
$source=[IO.File]::ReadAllText($run.movie) | ConvertFrom-Json -AsHashtable
$encoder=$source.ffmpeg;$probe=Join-Path (Split-Path -Parent $encoder) 'ffprobe.exe'
if(-not (Test-Path -LiteralPath $probe -PathType Leaf)){throw 'Actual ffprobe executable is missing'}
$probeText=& $probe -v error -show_streams -show_format -of json $run.output
if($LASTEXITCODE -ne 0){throw 'Actual MP4 ffprobe failed'}
$probeText | Set-Content -LiteralPath (Join-Path $run.runDirectory 'export-probe.json') -Encoding utf8BOM
$metadata=($probeText -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable
$video=$metadata.streams | Where-Object {$_.codec_type -eq 'video'} | Select-Object -First 1
$audio=$metadata.streams | Where-Object {$_.codec_type -eq 'audio'} | Select-Object -First 1
$expected=[double]$run.actualSeconds
$expectedFrames=[Math]::Ceiling($expected*30)
if([long]$video.nb_frames -ne $expectedFrames -or $audio.sample_rate -ne '48000' -or $audio.channels -ne 1 -or [Math]::Abs([double]$audio.duration-$expected) -gt 0.1 -or [Math]::Abs([double]$video.start_time) -gt 0.001 -or [Math]::Abs([double]$audio.start_time) -gt 0.001){
  throw 'Actual MP4 frame count, audio duration or stream start synchronization is incorrect'
}
if($video.width -ne 1920 -or $video.height -ne 1080 -or $video.avg_frame_rate -ne '30/1' -or $video.codec_name -ne 'h264' -or $audio.codec_name -ne 'aac' -or [Math]::Abs([double]$metadata.format.duration-$expected) -gt 0.1){
  throw 'Actual MP4 codec, dimensions, frame rate, speech stream or duration are incorrect'
}
$decodeOK=$false
if($Decode){
  $decodeLog=Join-Path $run.runDirectory 'export-decode.log'
  $started=[DateTime]::UtcNow
  & $encoder -hide_banner -v error -i $run.output -map '0:v:0' -map '0:a:0' -f null NUL *> $decodeLog
  $code=$LASTEXITCODE
  @{exitCode=$code;success=($code -eq 0);output=$run.output;fullVideoAndAudio=$true;startedUtc=$started.ToString('o');completedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'export-decode.json') -Encoding utf8BOM
  if($code -ne 0){throw 'Full video and audio decode failed'}
  $decodeOK=$true
}
if((Get-FileHash -LiteralPath $run.sourceMovie -Algorithm SHA256).Hash -ne $run.sourceMovieSha256){throw 'Original work changed'}
if((Get-FileHash -LiteralPath $run.rig -Algorithm SHA256).Hash -ne $run.rigSha256){throw 'Prepared source rig changed'}
if($run.provisional -and ((Get-FileHash -LiteralPath $run.provisionalSource -Algorithm SHA256).Hash -ne $run.provisionalSourceSha256)){throw 'Image-pending manga source changed'}
$report=@{
  success=$true;completedUtc=[DateTime]::UtcNow.ToString('o');work=$run.work
  executable=$run.executable;executableSha256=$run.executableSha256;ownedProductPid=$run.pid
  movie=$run.movie;movieSha256=(Get-FileHash -LiteralPath $run.movie -Algorithm SHA256).Hash
  output=$run.output;outputSha256=(Get-FileHash -LiteralPath $run.output -Algorithm SHA256).Hash
  bytes=(Get-Item -LiteralPath $run.output).Length;durationSeconds=[double]$metadata.format.duration
  width=$video.width;height=$video.height;fps=$video.avg_frame_rate;frames=$video.nb_frames
  videoCodec=$video.codec_name;audioCodec=$audio.codec_name;sampleRate=$audio.sample_rate
  fullVideoAudioDecode=$decodeOK;workflowStage=$workflow.currentStage;job=$job
  provisional=[bool]$run.provisional;sceneImagesReady=[bool]$run.imageReady
  audioDurationSeconds=[double]$audio.duration;videoDurationSeconds=[double]$video.duration;streamStartTimes=@{video=[double]$video.start_time;audio=[double]$audio.start_time}
  humanDesktopVerification=$false;notificationEventCountForThisProductInstanceVerified=$false
  originalsUnchanged=$true
}
$report | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'export-results.json') -Encoding utf8BOM
$run.stage=if($decodeOK){'actual MP4 complete, saved and fully decoded'}else{'actual MP4 complete and saved; full decode remains'}
$run | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $RunFile -Encoding utf8BOM
$report | Select-Object success,movie,output,bytes,durationSeconds,frames,fullVideoAudioDecode,workflowStage | ConvertTo-Json -Depth 5
