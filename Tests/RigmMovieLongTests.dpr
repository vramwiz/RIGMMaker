program RigmMovieLongTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Math, Winapi.Windows, Winapi.PsAPI,
  RigmMovieModel, RigmMovieAudio, RigmMovieSession, RigmJson;
var Session: TRigmMovieSession; Root: string; Checks: TJSONArray; PeakPrivate,PeakWorking,PeakStaging: UInt64; PeakGdi: Cardinal;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
procedure Memory;
var Counters: TProcessMemoryCountersEx;
begin
  Counters := Default(TProcessMemoryCountersEx); Counters.cb := SizeOf(Counters);
  if GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then begin
    PeakPrivate := Max(PeakPrivate,Counters.PrivateUsage); PeakWorking := Max(PeakWorking,Counters.WorkingSetSize);
  end;
  PeakGdi := Max(PeakGdi,GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS));
end;
function Call(const Command: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try Args.AddPair('projectId',Session.Project.Id); AddN(Args,'revision',Session.Project.Revision); Result := Session.Execute(Command,Args); finally Args.Free; end;
end;
procedure Run(const Command: string; Args: TJSONObject=nil);
begin var O := Call(Command,Args); O.Free; end;
function WaitJob: TJSONObject;
var Deadline,ReportAt: UInt64;
begin
  Deadline := GetTickCount64+600000; ReportAt := 0;
  repeat
    Session.Poll; Memory; Result := Call('job-status'); if JB(Result,'done') then Exit;
    if GetTickCount64>=ReportAt then begin
      for var FileName in TDirectory.GetFiles(Root,'*.part*') do try PeakStaging := Max(PeakStaging,UInt64(TFile.GetSize(FileName))); except end;
      Writeln('PROGRESS '+JS(Result,'kind')+' '+JI(Result,'completed').ToString+'/'+JI(Result,'total').ToString); ReportAt := GetTickCount64+2000;
    end;
    Result.Free; Sleep(5);
  until GetTickCount64>Deadline;
  Run('job-cancel'); raise Exception.Create('Long export exceeded ten minute test budget');
end;
procedure Tests;
var P: TRigmMovieProject; Audio: TRigmPcm; O,A: TJSONObject; Elapsed: UInt64; Script: string; BaselineGdi: Cardinal; Progress: Integer;
begin
  Script := '';
  for var I := 0 to 59 do begin
    if I mod 10=0 then Script := Script+'# シーン'+(I div 10+1).ToString+sLineBreak;
    Script := Script+'narrator:自作の三分検証、セリフ'+(I+1).ToString+'です。'+sLineBreak;
  end;
  P := TRigmMovieProject.FromText(Script); Audio := TRigmPcm.Create;
  try
    P.CharacterFile := '@sample'; P.Width := 640; P.Height := 360; P.Fps := 15;
    P.FfmpegExe := ParamStr(1); Audio.Rate := 24000; SetLength(Audio.Samples,67200);
    for var I := 0 to High(Audio.Samples) do
      if (I>=1200) and (I<66000) then Audio.Samples[I] := Round(Sin(I*2*Pi*220/Audio.Rate)*10000);
    var Wave := TPath.Combine(Root,'EXPLICIT-TEST-TONE-2.8s.wav'); Audio.Save(Wave);
    for var I := 0 to P.Cues.Count-1 do begin
      var C := P.Cues[I]; C.Pause := 0.2; C.WaveFile := Wave; C.AudioSeconds := 2.8; C.AudioKey := P.AudioFingerprint(C);
      C.Motion := 'nod'; if I mod 3=1 then C.Expression := 'smile';
      C.Acting.HeadGain := 0.8; C.Acting.BodyGain := 0.6; C.Acting.FadeIn := 0.2; C.Acting.FadeOut := 0.2;
    end;
    SaveMovie(P,TPath.Combine(Root,'three-minute.rigmovie')); Session.SetProject(P); P := nil;
    Check(SameValue(Session.Project.Duration,180),'sixty exact WAV cues and pauses form real 180 second timeline');
    Run('waveform-refresh'); O := WaitJob;
    try Check(JS(O,'state')='succeeded','three minute waveform builds from actual explicit tone PCM'); finally O.Free; end;
    O := Call('waveform'); try Check((JI(O,'sampleCount')=8640000) and (JA(O,'peaks').Count=2048),'long waveform represents all 8.64 million PCM samples in bounded response'); finally O.Free; end;
    for var Time in [0.1,60.1,120.1,179.8] do begin
      A := TJSONObject.Create; AddN(A,'time',Time); A.AddPair('path',TPath.Combine(Root,'seek-'+Round(Time*10).ToString+'.png')); Run('preview',A); O := WaitJob;
      try Check(JS(O,'state')='succeeded','long timeline preview seek '+FloatToStr(Time,TFormatSettings.Invariant)); finally O.Free; end;
      var Frame := Session.TakeFrame; Frame.Free;
    end;
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'cancelled.mp4')); Run('export',A);
    var CancelDeadline := GetTickCount64+30000;
    repeat O := Call('job-status'); Progress := JI(O,'completed'); O.Free; Memory; Sleep(5); until (Progress>=15) or (GetTickCount64>CancelDeadline);
    Run('job-cancel'); O := WaitJob; try Check(JS(O,'state')='cancelled','actual long frame export cancels'); finally O.Free; end;
    Check(not FileExists(TPath.Combine(Root,'cancelled.mp4')),'cancelled long export leaves no final video');
    Check(Length(TDirectory.GetFiles(Root,'*.part*'))=0,'cancelled long export cleans its own staging files');
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'three-minute.rigmovie')); Run('open',A);
    Check(not Session.Project.Modified and Session.Project.AudioReady(Session.Project.Cues[59]),'three minute saved project reopens with audio and acting');
    BaselineGdi := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS); Elapsed := GetTickCount64;
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'three-minute-tone.mp4')); Run('export',A); O := WaitJob;
    try Check(JS(O,'state')='succeeded','all 2700 frames export to three minute H264 AAC MP4: '+JS(O,'error')); finally O.Free; end;
    Elapsed := GetTickCount64-Elapsed;
    Check(FileExists(TPath.Combine(Root,'three-minute-tone.mp4')),'completed long MP4 exists');
    Check(PeakPrivate<512*1024*1024,'measured application private memory remains below 512 MiB');
    Check(PeakGdi<BaselineGdi+1000,'GDI objects do not grow by one per frame');
    O := TJSONObject.Create;
    try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('directory',Root); AddN(O,'duration',180); AddN(O,'frames',2700);
      AddN(O,'exportWallMs',Elapsed); AddN(O,'videoBytes',TFile.GetSize(TPath.Combine(Root,'three-minute-tone.mp4')));
      AddN(O,'peakPrivateBytes',PeakPrivate); AddN(O,'peakWorkingSetBytes',PeakWorking); AddN(O,'peakGdiObjects',PeakGdi);
      AddN(O,'peakObservedStagingBytes',PeakStaging); O.AddPair('memoryScope','RigmMovieLongTests process only; excludes FFmpeg child');
      O.AddPair('audio','explicit test tone, not VOICEVOX speech'); O.AddPair('checks',Checks.Clone as TJSONArray);
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'movie-long-results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally P.Free; Audio.Free; end;
end;
begin
  Session := TRigmMovieSession.Create; Checks := TJSONArray.Create;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)),'MovieLong\'+FormatDateTime('yyyymmdd-hhnnss-zzz',Now)); ForceDirectories(Root);
  try try Tests; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; Session.Free; end;
end.
