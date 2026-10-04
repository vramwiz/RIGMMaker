program RigmMovieStreamingTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Math,
  Winapi.Windows, Winapi.PsAPI, Vcl.Forms, RigmMovieModel, RigmMovieSession, RigmJson;
var Source,Root,Encoder: string; S: TRigmMovieSession; Checks: TJSONArray;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS '+Name); Flush(Output); end;
function Call(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try Result := S.Execute(Name,Args); finally Args.Free; end;
end;
function WaitJob(const Id: string; CancelAfterFrame: Boolean=False): TJSONObject;
begin
  var Started := GetTickCount64; var Deadline := Started+120000; var SentCancel := False;
  repeat
    S.Poll; var A := TJSONObject.Create; A.AddPair('jobId',Id); Result := Call('job-status',A);
    if CancelAfterFrame and not SentCancel and (JI(Result,'encoderProcessId')>0) and (GetTickCount64-Started>=500) then begin
      var R := Call('job-cancel'); R.Free; SentCancel := True;
    end;
    if JB(Result,'done') then begin
      TFile.WriteAllText(TPath.Combine(Root,'job-'+Id.Trim(['{','}'])+'.json'),Result.ToJSON,TEncoding.UTF8);
      Writeln(Result.ToJSON); Flush(Output); Exit;
    end;
    Result.Free; Sleep(10);
  until GetTickCount64>Deadline;
  raise Exception.Create('Owned streaming job did not finish');
end;
function Start(const Path: string): string;
begin var A := TJSONObject.Create; A.AddPair('path',Path); var R := Call('export',A); try Result := JS(R,'jobId'); finally R.Free; end; end;
procedure NoStaging;
begin Check(Length(TDirectory.GetFiles(Root,'*.part*'))=0,'streaming job removes its own video, WAV and log staging'); end;
procedure Test;
begin
  var Before := THashSHA2.GetHashStringFromFile(Source);
  var P := LoadMovie(Source);
  try
    while P.Cues.Count>1 do P.Cues.Delete(P.Cues.Count-1);
    while P.Scenes.Count>1 do P.Scenes.Delete(P.Scenes.Count-1);
    P.Width := 640; P.Height := 360; P.Fps := 30; P.EncodeProfile := 'fast'; P.FfmpegExe := Encoder;
    P.Validate; S.SetProject(P); P := nil;
    Check(S.Project.AudioReady(S.Project.Cues[0]),'proxy retains actual generated speech and phoneme alignment');
    var Id := Start(TPath.Combine(Root,'cancel-real.mp4')); var R := WaitJob(Id,True);
    try
      Check(JS(R,'state')='cancelled','active real FFmpeg streaming export cancels');
      Check(JB(R,'encoderExited') and (JI(R,'cancelWorkerMs')<5000),'cancel retires only its own encoder promptly');
    finally R.Free; end;
    Check(not FileExists(TPath.Combine(Root,'cancel-real.mp4')),'cancel does not publish a final video'); NoStaging;
    var Fake := TPath.Combine(Root,'ffmpeg.exe'); TFile.Copy(ParamStr(0),Fake,False);
    S.Project.FfmpegExe := Fake;
    Id := Start(TPath.Combine(Root,'broken-consumer.mp4')); R := WaitJob(Id);
    try Check((JS(R,'state')='failed') and JB(R,'encoderExited'),'early encoder exit fails without a blocked writer or leaked encoder'); finally R.Free; end;
    Check(not FileExists(TPath.Combine(Root,'broken-consumer.mp4')),'early encoder failure publishes no video'); NoStaging;
    TFile.WriteAllText(Fake+'.blocked','explicit fault fixture');
    Id := Start(TPath.Combine(Root,'blocked-consumer.mp4')); R := WaitJob(Id,True);
    try
      Check(JS(R,'state')='cancelled','encoder that never reads stdin can still be cancelled');
      Check(JB(R,'encoderExited') and (JI(R,'cancelWorkerMs')<5000),'blocked pipe cancellation retires child and writer in bounded time');
    finally R.Free; end;
    NoStaging; S.Project.FfmpegExe := Encoder;
    var Protected := TPath.Combine(Root,'protected.mp4'); TFile.WriteAllText(Protected,'existing output must stay intact');
    var Hash := THashSHA2.GetHashStringFromFile(Protected); var Rejected := False;
    try
      Id := Start(Protected); R := WaitJob(Id);
      try Rejected := JS(R,'state')='failed'; finally R.Free; end;
    except on E: Exception do Rejected := E.Message<>''; end;
    Check(Rejected and (Hash=THashSHA2.GetHashStringFromFile(Protected)),'existing video is rejected and remains byte-identical');
    Id := Start(TPath.Combine(Root,'real-speech-proxy.mp4')); R := WaitJob(Id);
    try
      Check((JS(R,'state')='succeeded') and JB(R,'collected') and JB(R,'encoderExited'),'actual FFmpeg raw-frame speech export completes and is collected');
      Check(JS(R,'exportBackend')='ffmpeg-raw-bgra-pipe','MP4 uses the raw-frame pipe rather than legacy AVI');
      Check(JN(R,'exportStagingPeakBytes')<64*1024*1024,'proxy staging is bounded to audio and compressed output');
      TFile.WriteAllText(TPath.Combine(Root,'export-job.json'),R.ToJSON,TEncoding.UTF8);
    finally R.Free; end;
    NoStaging; Check(Before=THashSHA2.GetHashStringFromFile(Source),'saved production and all original references remain unchanged');
    var Report := TJSONObject.Create;
    try AddB(Report,'success',True); AddN(Report,'passed',Checks.Count); Report.AddPair('checks',Checks.Clone as TJSONArray);
      Report.AddPair('output',TPath.Combine(Root,'real-speech-proxy.mp4'));
      AddN(Report,'expectedSeconds',S.Project.Duration); AddN(Report,'expectedFrames',Ceil(S.Project.Duration*S.Project.Fps));
      Report.AddPair('sourceSha256',Before); AddB(Report,'faultConsumersAreExplicitTestFixtures',True);
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  finally P.Free; end;
end;
begin
  if ParamStr(1)='-hide_banner' then begin
    if FileExists(ParamStr(0)+'.blocked') then Sleep(60000);
    Halt(7);
  end;
  Application.Initialize; Source := ParamStr(1); Root := ParamStr(2); Encoder := ParamStr(3);
  ForceDirectories(Root); S := TRigmMovieSession.Create; Checks := TJSONArray.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; S.Free; end;
end.
