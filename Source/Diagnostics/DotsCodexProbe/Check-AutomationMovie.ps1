param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$VideoPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$OutDir=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $OutDir){throw 'Fresh evidence directory required.'}
$bin=Join-Path $OutDir 'bin';New-Item -ItemType Directory -Path $bin,(Join-Path $OutDir 'dcu')|Out-Null
$reference=[IO.File]::ReadAllText((Join-Path $repo 'Source\Psd\Validation\BundledMp4Check.dpr'))
$start=$reference.IndexOf('type');$finish=$reference.IndexOf('function FixtureAudio:')
$decoder=$reference.Substring($start,$finish-$start)
$header=@'
program AutomationMovieCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  Winapi.Windows, RigmFFmpegApi, RigmFFmpegTypes, RigmMovieModel, RigmScriptVoiceModel;
'@
$main=@'
begin
  Checks := TJSONArray.Create;
  var Report := TJSONObject.Create;
  try
    try
      var P := LoadMovie(ParamStr(2));
      try
        var D := Decode(ParamStr(1));
        Check((D.Width=P.Width) and (D.Height=P.Height),'decoded resolution equals saved project');
        Check(D.VideoFrames=Ceil(P.Duration*P.Fps),'all expected video frames decoded');
        Check((D.AudioSamples>0) and (D.Peak>0.0001),'decoded audio is non-silent');
        Check(Abs(D.AudioDuration-P.Duration)<0.15,'audio and saved project durations agree');
        for var C in P.Cues do begin
          Check(C.Text=C.Subtitle,'dialogue and subtitles match');
          Check(C.Text=C.SpokenText,'spoken text equals dialogue');
          Check(P.AudioReady(C) and ScriptVoiceAccepted(P,C),'generated current audio accepted by automation policy');
          Check(not P.AudioHeard(C),'automation does not record fictional human playback');
        end;
        var Manual := P.Clone;
        try
          Manual.ScriptWizard.RemovePair('automation').Free;
          for var C in Manual.Cues do Check(not ScriptVoiceAccepted(Manual,C),'manual project still requires actual playback');
        finally Manual.Free; end;
        Report.AddPair('videoFrames',TJSONNumber.Create(D.VideoFrames));
        Report.AddPair('audioSamples',TJSONNumber.Create(D.AudioSamples));
        Report.AddPair('audioDuration',TJSONNumber.Create(D.AudioDuration));
        Report.AddPair('projectDuration',TJSONNumber.Create(P.Duration));
        Report.AddPair('width',TJSONNumber.Create(D.Width));Report.AddPair('height',TJSONNumber.Create(D.Height));
        Report.AddPair('success',TJSONBool.Create(True));
      finally P.Free; end;
    except on E: Exception do begin Report.AddPair('success',TJSONBool.Create(False)); Report.AddPair('error',E.Message); ExitCode := 1; end; end;
    Report.AddPair('checks',Checks); Checks := nil;
    TFile.WriteAllText(ParamStr(3),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; Checks.Free; end;
end.
'@
$source=Join-Path $OutDir 'AutomationMovieCheck.dpr'
[IO.File]::WriteAllText($source,$header+"`r`n"+$decoder+$main,[Text.UTF8Encoding]::new($true))
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable);$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';'|Where-Object {$_ -and -not $_.StartsWith('$(')}|ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+(Join-Path $OutDir 'dcu')),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data')
& 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags $source *> (Join-Path $OutDir 'build.log')
if($LASTEXITCODE -ne 0){Get-Content (Join-Path $OutDir 'build.log') -Tail 12;throw 'Decode check compilation failed.'}
Copy-Item -LiteralPath (Join-Path $repo 'Runtime') -Destination (Join-Path $bin 'Runtime') -Recurse
& (Join-Path $bin 'AutomationMovieCheck.exe') ([IO.Path]::GetFullPath($VideoPath)) ([IO.Path]::GetFullPath($ProjectPath)) (Join-Path $OutDir 'result.json') --data-root (Join-Path $OutDir 'OwnedData') --settings-dir (Join-Path $OutDir 'Settings') *> (Join-Path $OutDir 'decode.log')
if($LASTEXITCODE -ne 0){Get-Content (Join-Path $OutDir 'result.json');throw 'Full artifact decode check failed.'}
Get-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
