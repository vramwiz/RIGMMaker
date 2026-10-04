#requires -Version 7.0
param([string]$FFmpegDirectory='C:\Users\zan12\Downloads\ffmpeg-8.1.1-full_build-shared\ffmpeg-8.1.1-full_build-shared\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$r=Get-Content (Join-Path $root 'Win64\Validation\movie-1080-latest.json') -Raw | ConvertFrom-Json
if(-not $r.success){throw 'Long export did not succeed'}
$video=Join-Path $r.directory 'fullhd-tone.mp4'
$out=Join-Path $r.directory ('IndependentDecode-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
New-Item -ItemType Directory -Path $out | Out-Null
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name);Write-Output ('PASS: '+$Name)}
$probe=& (Join-Path $FFmpegDirectory 'ffprobe.exe') -v error -count_frames -show_streams -show_format -of json $video
if($LASTEXITCODE -ne 0){throw 'ffprobe failed'}
$probe | Set-Content (Join-Path $out 'probe.json') -Encoding utf8
$p=$probe | ConvertFrom-Json;$v=$p.streams | Where-Object codec_type -eq video;$a=$p.streams | Where-Object codec_type -eq audio
Check ($v.codec_name -eq 'h264' -and $a.codec_name -eq 'aac') 'long movie contains actual H264 and AAC'
Check ($v.width -eq 1920 -and $v.height -eq 1080 -and $v.avg_frame_rate -eq '30/1') 'long decoded dimensions and fps match tested project'
Check ([int]$v.nb_read_frames -eq 5400) 'all 5400 encoded frames independently decode'
Check ([Math]::Abs([double]$v.duration-180) -lt 0.00003 -and [Math]::Abs([double]$a.duration-180) -lt 0.00003) 'both stream presentation durations are exactly 180 seconds'
Check ([double]$v.start_time -eq 0 -and [double]$a.start_time -eq 0) 'long audio and video presentation start at zero'
& (Join-Path $FFmpegDirectory 'ffmpeg.exe') -v error -n -i $video -map '0:v:0' -fps_mode passthrough -f framemd5 (Join-Path $out 'all-frames.framemd5') -map '0:a:0' -c:a pcm_s16le (Join-Path $out 'all-audio.wav')
if($LASTEXITCODE -ne 0){throw 'Independent full decode failed'}
$frames=@(Get-Content (Join-Path $out 'all-frames.framemd5') | Where-Object {$_ -match '^0,'})
Check ($frames.Count -eq 5400) 'independent decoder emits every frame checksum'
Check (@($frames | ForEach-Object {($_ -split ',')[-1].Trim()} | Select-Object -Unique).Count -gt 100) 'long frames contain changing rendered acting scenes and subtitles'
$badTimestamp=0
for($i=0;$i -lt $frames.Count;$i++){$fields=$frames[$i] -split ',';if([int]$fields[2] -ne $i -or [int]$fields[3] -ne 1){$badTimestamp++}}
Check ($badTimestamp -eq 0) 'every independently decoded frame has consecutive 30fps timing without gaps or duplicates'
$reader=[IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $out 'all-audio.wav')))
try{
  $null=$reader.ReadBytes(12);$data=[byte[]]@();$rate=0;$align=0
  while($reader.BaseStream.Position+8 -le $reader.BaseStream.Length){
    $code=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4));$length=$reader.ReadUInt32();$next=$reader.BaseStream.Position+$length+($length -band 1)
    if($code -eq 'fmt '){$format=$reader.ReadUInt16();$channels=$reader.ReadUInt16();$rate=$reader.ReadUInt32();$null=$reader.ReadUInt32();$align=$reader.ReadUInt16();$bits=$reader.ReadUInt16()}
    elseif($code -eq 'data'){$data=$reader.ReadBytes($length)}
    $reader.BaseStream.Position=$next
  }
}finally{$reader.Dispose()}
Check ($format -eq 1 -and $rate -eq 48000 -and $channels -eq 1 -and $bits -eq 16) 'all AAC audio decodes to expected 48k mono PCM16'
$samples=$data.Length/$align
Check ($samples -ge 8640000 -and $samples -le 8641024) 'full decoded PCM covers all 8.64 million presentation samples with bounded AAC padding'
$minSpeech=[double]::PositiveInfinity;$maxPause=0.0
for($cue=0;$cue -lt 60;$cue++){
  $speech=0.0; $first=($cue*3+0.1)*48000
  for($i=0;$i -lt 12000;$i++){$sample=[BitConverter]::ToInt16($data,([int]$first+$i)*2);$speech+=$sample*$sample}
  $pause=0.0; $first=($cue*3+2.86)*48000
  for($i=0;$i -lt 3840;$i++){$sample=[BitConverter]::ToInt16($data,([int]$first+$i)*2);$pause+=$sample*$sample}
  $minSpeech=[Math]::Min($minSpeech,$speech/12000);$maxPause=[Math]::Max($maxPause,$pause/3840)
}
Check ($minSpeech -gt 1000000) 'all sixty speech positions retain explicit source tone energy'
Check ($maxPause -lt 100) 'all sixty inter-cue pauses stay silent within AAC noise tolerance'
$project=Get-Content (Join-Path $r.directory 'fullhd.rigmovie') -Raw | ConvertFrom-Json
Check ($project.cues.Count -eq 60 -and @($project.cues.scene | Select-Object -Unique).Count -eq 6) 'saved real timeline contains sixty cues in six scenes'
Check (@($project.cues | Where-Object {$_.acting.headGain -ne 0.6 -or $_.acting.bodyGain -ne 0.5 -or $_.acting.fadeIn -ne 0.2}).Count -eq 0) 'long project preserves authored acting for every cue'
foreach($time in @(0.1,30.1,60.1,90.1,120.1,150.1,179.8)){
  & (Join-Path $FFmpegDirectory 'ffmpeg.exe') -v error -n -ss $time -i $video -frames:v 1 (Join-Path $out ('scene-'+$time+'.png'))
  if($LASTEXITCODE -ne 0){throw 'Selected scene decode failed'}
}
Check ((Get-ChildItem $out -Filter 'scene-*.png').Count -eq 7) 'scene boundaries and final pause produce independently viewable frames'
Check (@($project.cues | Where-Object {$_.acting.mouthMode -ne 'assets' -or $_.acting.blinkMode -ne 'assets'}).Count -eq 0) 'all real-material cues use existing mouth and eye assets'
Check (@($project.cues | ForEach-Object {$_.acting.variants} | Where-Object {$_.groupId} | ForEach-Object {$_.partId} | Select-Object -Unique).Count -ge 8) 'three-minute actual material movie keeps authored pose and eyebrow selections'
Check (@(Get-ChildItem -LiteralPath $r.directory -File | Where-Object { $_.Name.StartsWith('fullhd-tone.mp4.') }).Count -eq 0) 'successful export cleans its own staging and encoder logs'
$record=@{success=$true;passed=$checks.Count;video=$video;sha256=(Get-FileHash $video).Hash;directory=$out;frames=5400;duration=180;decodedSamples=$samples;minimumSpeechEnergy=$minSpeech;maximumPauseEnergy=$maxPause;audioSource='explicit test tone, not VOICEVOX speech';checks=$checks.ToArray()}
$record | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'inspection.json') -Encoding utf8
$record | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'Win64\Validation\movie-1080-inspection.json') -Encoding utf8
