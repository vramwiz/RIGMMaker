#requires -Version 7.0
param([string]$Metadata='Win64\Validation\media-revision-run.json')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$m=Get-Content -LiteralPath (Join-Path $root $Metadata) -Raw | ConvertFrom-Json
$visual=Get-Content -LiteralPath (Join-Path $m.root 'Visual\results.json') -Raw | ConvertFrom-Json
if(-not $visual.success -or $visual.videoFrames.Count -ne 5){throw 'Five native LAB frame references are required'}
$directory=Join-Path $m.root 'Decode'
New-Item -ItemType Directory -Path $directory -Force|Out-Null
$project=Get-Content -LiteralPath $m.target -Raw -Encoding utf8 | ConvertFrom-Json
$video=if($m.export){$m.export}else{$project.outputTarget}
if(-not [IO.Path]::IsPathRooted($video)){$video=[IO.Path]::GetFullPath((Join-Path (Split-Path $m.target) $video))}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$OK,[string]$Name){if(-not $OK){throw $Name};$checks.Add($Name);Write-Output ('PASS: '+$Name)}
function Ffmpeg([string[]]$Arguments,[string]$Log){
  $output=& $m.ffmpeg @Arguments 2>&1
  $code=$LASTEXITCODE
  $output|Set-Content -LiteralPath (Join-Path $directory $Log) -Encoding utf8
  if($code -ne 0){throw ('Independent FFmpeg failed: '+$Log+' exit '+$code)}
  return @($output|ForEach-Object {$_.ToString()})
}
function Psnr([string]$Decoded,[string]$Reference,[object]$Crop,[string]$Log){
  $filter='[0:v][1:v]psnr'
  if($Crop){$c='crop='+$Crop.width+':'+$Crop.height+':'+$Crop.x+':'+$Crop.y;$filter='[0:v]'+$c+'[a];[1:v]'+$c+'[b];[a][b]psnr'}
  $lines=Ffmpeg @('-hide_banner','-i',$Decoded,'-i',$Reference,'-filter_complex',$filter,'-f','null','-') $Log
  $match=[regex]::Match(($lines -join ' '),'average:([0-9.]+|inf)')
  if(-not $match.Success){throw 'PSNR metric missing'}
  if($match.Groups[1].Value -eq 'inf'){return 100.0}
  return [double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
}
$probe=Join-Path (Split-Path $m.ffmpeg) 'ffprobe.exe'
$raw=& $probe -v error -show_streams -show_format -of json $video
if($LASTEXITCODE -ne 0){throw 'Independent probe failed'}
$raw|Set-Content -LiteralPath (Join-Path $directory 'ffprobe.json') -Encoding utf8
$streams=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$v=$streams.streams|Where-Object codec_type -eq video
$a=$streams.streams|Where-Object codec_type -eq audio
Check ($v.codec_name -eq 'h264' -and $a.codec_name -eq 'aac') 'MP4 contains actual H264 video and AAC audio'
Check ($v.width -eq 1920 -and $v.height -eq 1080 -and $v.r_frame_rate -eq '30/1') 'actual movie is Full HD at 30 fps'
Check ([int]$v.nb_frames -eq 1117) 'all 1117 exported frames are present'
Check ([Math]::Abs([double]$v.duration-[double]$a.duration) -lt 0.001) 'audio/video container durations differ by less than 1ms'
Check ([Math]::Abs([double]$v.duration-37.2106666666667) -lt 1/30) 'movie duration keeps actual speech timing within one output frame'
$null=Ffmpeg @('-v','error','-i',$video,'-f','null','-') 'decode-full-final.log'
Check $true 'independent full audio/video decode exits zero without an error'
$measurements=@()
foreach($frame in $visual.videoFrames){
  $path=Join-Path $directory ('mouth-'+$frame.phoneme+'.png')
  $filter='select=eq(n\,'+$frame.frame+')'
  $null=Ffmpeg @('-v','error','-y','-i',$video,'-vf',$filter,'-frames:v','1','-fps_mode','passthrough',$path) ('extract-mouth-'+$frame.phoneme+'.log')
  Check (Test-Path -LiteralPath $path) ('decode extracts exact LAB frame '+$frame.phoneme+' #'+$frame.frame)
  $full=Psnr $path $frame.path $null ('compare-full-'+$frame.phoneme+'.log')
  $mouth=Psnr $path $frame.path $frame.mouthCrop ('compare-mouth-'+$frame.phoneme+'.log')
  Check ($full -gt 28) ('encoded frame matches native image composition '+$frame.phoneme)
  Check ($mouth -gt 18) ('encoded mouth pixels match the actual LAB sprite '+$frame.phoneme)
  $crop=$frame.mouthCrop
  $null=Ffmpeg @('-v','error','-y','-i',$path,'-vf',('crop='+$crop.width+':'+$crop.height+':'+$crop.x+':'+$crop.y),'-frames:v','1',(Join-Path $directory ('mouth-detail-'+$frame.phoneme+'.png'))) ('crop-mouth-'+$frame.phoneme+'.log')
  $measurements+=@{phoneme=$frame.phoneme;frame=$frame.frame;time=$frame.time;mouthPart=$frame.mouthPart;decoded=$path;fullPsnr=$full;mouthPsnr=$mouth}
}
$project=Get-Content -LiteralPath $m.target -Raw|ConvertFrom-Json
$time=0.0
foreach($scene in $project.scenes){
  $seconds=0.0
  foreach($cue in $project.cues|Where-Object scene -eq $scene.id){$seconds+=[double]$cue.audioSeconds+[double]$cue.pause}
  $seconds+=[double]$scene.padding
  $index=[int][Math]::Round(($time+[Math]::Min(3.0,$seconds/2))*30)
  $path=Join-Path $directory ('scene-'+$scene.id+'.png')
  $null=Ffmpeg @('-v','error','-y','-i',$video,'-vf',('select=eq(n\,'+$index+')'),'-frames:v','1','-fps_mode','passthrough',$path) ('extract-scene-'+$scene.id+'.log')
  Check (Test-Path -LiteralPath $path) ('encoded movie includes scene image and shared background '+$scene.id)
  $scenePsnr=Psnr $path (Join-Path $m.root ('Visual\scene-'+$scene.id+'.png')) $null ('compare-scene-'+$scene.id+'.log')
  Check ($scenePsnr -gt 28) ('decoded scene matches its native image and background '+$scene.id)
  $time+=$seconds
}
foreach($frame in @(30,36,42,60)){
  $null=Ffmpeg @('-v','error','-y','-i',$video,'-vf',('select=eq(n\,'+$frame+')'),'-frames:v','1','-fps_mode','passthrough',(Join-Path $directory ('motion-'+$frame+'.png'))) ('extract-motion-'+$frame+'.log')
}
$actorCrop=@{x=1450;y=150;width=400;height=700}
$baselinePsnr=Psnr (Join-Path $directory 'motion-30.png') (Join-Path $m.root 'Visual\motion-baseline.png') $actorCrop 'compare-motion-baseline.log'
Check ($baselinePsnr -gt 28) 'decoded whole-character motion keeps the normal actor size and baseline'
$motionPsnr=Psnr (Join-Path $directory 'motion-30.png') (Join-Path $directory 'motion-36.png') $actorCrop 'compare-motion-travel.log'
Check ($motionPsnr -lt 50) 'encoded whole-character motion visibly changes the actor pixels'
$audio=Join-Path $directory 'decoded-real-speech.wav'
$null=Ffmpeg @('-v','error','-y','-i',$video,'-vn','-c:a','pcm_s16le','-ar','48000','-ac','1',$audio) 'decode-audio.log'
if(-not ('RigmMediaAudioMeasure' -as [type])){
Add-Type @'
using System;
using System.IO;
public static class RigmMediaAudioMeasure {
  static short[] Read(string p) {
    using(var r=new BinaryReader(File.OpenRead(p))) {
      if(new string(r.ReadChars(4))!="RIFF")throw new Exception("No WAV RIFF"); r.ReadInt32();r.ReadChars(4);
      while(r.BaseStream.Position+8<=r.BaseStream.Length) {
        var id=new string(r.ReadChars(4));var n=r.ReadInt32();var next=r.BaseStream.Position+n+(n&1);
        if(id=="fmt ") {if(r.ReadInt16()!=1 || r.ReadInt16()!=1 || r.ReadInt32()!=48000)throw new Exception("Unexpected PCM format");}
        if(id=="data") {var b=r.ReadBytes(n);var s=new short[n/2];Buffer.BlockCopy(b,0,s,0,n);return s;}
        r.BaseStream.Position=next;
      } throw new Exception("No PCM data");
    }
  }
  public static double[] Compare(string reference,string decoded) {
    var a=Read(reference);var b=Read(decoded);int n=Math.Min(a.Length,b.Length);double aa=0,bb=0,ab=0,m=0;
    for(int i=0;i<n;i++){aa+=(double)a[i]*a[i];bb+=(double)b[i]*b[i];ab+=(double)a[i]*b[i];}
    int x=48000,y=Math.Min(b.Length,120000);for(int i=x;i<y;i++)m+=(double)b[i]*b[i];
    return new double[]{a.Length/48000.0,b.Length/48000.0,ab/Math.Sqrt(aa*bb),Math.Sqrt(bb/n),Math.Sqrt(m/(y-x))};
  }
}
'@
}
$audioMetrics=[RigmMediaAudioMeasure]::Compare((Join-Path $m.root 'Visual\reference-real-speech.wav'),$audio)
Check ($audioMetrics[2] -gt 0.97) 'independently decoded AAC retains the actual speech waveform'
Check ($audioMetrics[3] -gt 200) 'decoded movie contains audible real speech'
Check ($audioMetrics[4] -gt 200) 'real speech continues during the whole-character motion interval'
@{success=$true;passed=$checks.Count;path=$video;sha256=(Get-FileHash -LiteralPath $video).Hash;videoDuration=[double]$v.duration;audioDuration=[double]$a.duration;frames=[int]$v.nb_frames;mouthFrames=$measurements;motion=@{baselinePsnr=$baselinePsnr;travelPsnr=$motionPsnr};audio=@{referenceSeconds=$audioMetrics[0];decodedSeconds=$audioMetrics[1];correlation=$audioMetrics[2];rms=$audioMetrics[3];motionIntervalRms=$audioMetrics[4]};checks=$checks.ToArray();humanDesktopVerification=$false;method='independent FFmpeg decode, native reference PSNR and actual PCM waveform correlation'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'results.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $directory 'results.json') -Raw
