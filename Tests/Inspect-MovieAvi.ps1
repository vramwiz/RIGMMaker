#requires -Version 7.0
param([Parameter(Mandatory)][string]$Avi,[Parameter(Mandatory)][string]$FFmpegDirectory,[Parameter(Mandatory)][string]$OutputDirectory,[int]$ExpectedFrames=24,[int]$Width=640,[int]$Height=360,[int]$Fps=15,[switch]$Mp4)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Choose a new inspection directory'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$probe=& (Join-Path $FFmpegDirectory 'ffprobe.exe') -v error -count_frames -show_streams -show_format -of json $Avi
if($LASTEXITCODE -ne 0){throw 'ffprobe failed'}
$probe | Set-Content (Join-Path $OutputDirectory 'probe.json') -Encoding utf8
$p=$probe | ConvertFrom-Json;$v=$p.streams | Where-Object codec_type -eq video;$a=$p.streams | Where-Object codec_type -eq audio
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
if($Mp4){Check ($v.codec_name -eq 'h264' -and $a.codec_name -eq 'aac') 'H264 and AAC streams recognized independently'}
else{Check ($v.codec_name -eq 'mjpeg' -and $a.codec_name -eq 'pcm_s16le') 'MJPEG and PCM streams recognized independently'}
Check ($v.width -eq $Width -and $v.height -eq $Height) 'decoded frame dimensions match project'
Check ($v.avg_frame_rate -eq "$Fps/1") 'video frame rate matches project'
Check ([int]$v.nb_read_frames -eq $ExpectedFrames) 'every encoded frame decodes'
Check ([double]$v.start_time -eq 0 -and [double]$a.start_time -eq 0) 'both streams start at zero'
& (Join-Path $FFmpegDirectory 'ffmpeg.exe') -v error -n -i $Avi -map '0:v:0' -fps_mode passthrough (Join-Path $OutputDirectory 'frame-%03d.png') -map '0:a:0' -c:a pcm_s16le (Join-Path $OutputDirectory 'audio.wav')
if($LASTEXITCODE -ne 0){throw 'full video/audio decode failed'}
Check ((Get-ChildItem $OutputDirectory -Filter 'frame-*.png').Count -eq $ExpectedFrames) 'full frame sequence exported by independent decoder'
$wave=[IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $OutputDirectory 'audio.wav')))
try{
  $null=$wave.ReadBytes(12);$data=[byte[]]@();$rate=0;$align=0
  while($wave.BaseStream.Position+8 -le $wave.BaseStream.Length){
    $code=[Text.Encoding]::ASCII.GetString($wave.ReadBytes(4));$length=$wave.ReadUInt32();$next=$wave.BaseStream.Position+$length+($length -band 1)
    if($code -eq 'fmt '){$format=$wave.ReadUInt16();$channels=$wave.ReadUInt16();$rate=$wave.ReadUInt32();$null=$wave.ReadUInt32();$align=$wave.ReadUInt16();$bits=$wave.ReadUInt16()}
    elseif($code -eq 'data'){$data=$wave.ReadBytes($length)}
    $wave.BaseStream.Position=$next
  }
}finally{$wave.Dispose()}
Check ($format -eq 1 -and $rate -eq 48000 -and $channels -eq 1 -and $bits -eq 16) 'audio independently decodes as 48kHz PCM16 mono'
$seconds=$data.Length/$align/$rate
if($Mp4){Check ([Math]::Abs([double]$a.duration-$ExpectedFrames/$Fps) -lt 0.001) 'AAC presentation duration matches video despite codec frame padding'}
else{Check ([Math]::Abs($seconds-$ExpectedFrames/$Fps) -lt 0.00003) 'decoded audio and video durations agree within one PCM sample'}
$energy=0.0;for($i=4800;$i -lt 19200;$i++){$sample=[BitConverter]::ToInt16($data,$i*2);$energy+=$sample*$sample}
Check ($energy/14400 -gt 1000000) 'decoded speech interval contains original fixture waveform energy'
$silence=0.0;for($i=26400;$i -lt 36000;$i++){$sample=[BitConverter]::ToInt16($data,$i*2);$silence+=$sample*$sample}
if($Mp4){Check ($silence/9600 -lt 100) 'decoded AAC pause remains silent within codec noise tolerance'}
else{Check ($silence -eq 0) 'decoded inter-cue pause remains exact digital silence'}
$hash=(Get-FileHash -LiteralPath $Avi -Algorithm SHA256).Hash
@{success=$true;passed=$checks.Count;avi=$Avi;sha256=$hash;decodedDirectory=$OutputDirectory;frames=$ExpectedFrames;width=$Width;height=$Height;fps=$Fps;audioSamples=$data.Length/$align;audioSeconds=$seconds;audioSource='explicit test tone; not real VOICEVOX';checks=$checks.ToArray()} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputDirectory 'inspection.json') -Encoding utf8
Get-Content (Join-Path $OutputDirectory 'inspection.json') -Raw
