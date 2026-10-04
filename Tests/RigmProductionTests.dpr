program RigmProductionTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  System.Hash, System.Generics.Collections, Winapi.Windows, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmEditorForm, RigmMovieSession, RigmMovieModel, RigmMovieProduction,
  RigmPipeTestClient, RigmJson;
var Checks: TJSONArray; Root,Fixture,FFmpeg,PipeName: string; F: TRigmEditorForm;
function Call(const Command: string; Args: TJSONObject): TJSONObject;
begin
  var Status := PipeCall(PipeName,'movie-status',TJSONObject.Create);
  try
    if not JB(Status,'ok') then raise Exception.Create('movie-status: '+Status.ToJSON);
    if Args.GetValue('projectId')=nil then Args.AddPair('projectId',JS(JO(Status,'data'),'projectId'));
    if Args.GetValue('revision')=nil then AddN(Args,'revision',JI(JO(Status,'data'),'revision'));
  finally Status.Free; end;
  var Reply := PipeCall(PipeName,'movie-'+Command,Args);
  try
    if not JB(Reply,'ok') then raise Exception.Create(Reply.ToJSON);
    Result := JO(Reply,'data').Clone as TJSONObject;
  finally Reply.Free; end;
end;
function Command(const Name,Json: string): TJSONObject;
begin Result := Call(Name,ParseObject(Json)); end;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Wait(const Key: string): TJSONObject;
begin
  var Deadline := GetTickCount64+20000;
  repeat
    Application.ProcessMessages; Result := Command('production-status','{"requestKey":"'+Key+'"}');
    if JB(Result,'done') then Exit;
    Result.Free; Sleep(10);
  until GetTickCount64>Deadline;
  raise Exception.Create('Production timeout: '+Key);
end;
function Needs(O: TJSONObject; const Code: string): Boolean;
begin Result := False; for var V in JA(O,'needs') do if JS(TJSONObject(V),'code')=Code then Exit(True); end;
function Request(const Key,Name: string): TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('requestKey',Key);
  Result.AddPair('script','narrator:This is a fictional test scene.'+sLineBreak+'narrator:The imaginary shop closes at dusk.');
  Result.AddPair('outputPath',TPath.Combine(Root,Name));
  var S := ParseObject('{"character":"@sample","width":320,"height":180,"fps":10,"encodeProfile":"fast"}');
  S.AddPair('engineUrl','http://127.0.0.1:51235'); S.AddPair('ffmpeg',FFmpeg); Result.AddPair('settings',S);
  Result.AddPair('voices',ParseObject('{"narrator":101}'));
  Result.AddPair('acting',ParseObject('{"mouthMode":"auto","blinkMode":"auto","headGain":0.5,"bodyGain":0.5}'));
end;
function SynthesisCount: Integer;
begin
  var Path := TPath.Combine(Fixture,'synthesis-count.txt');
  if FileExists(Path) then Result := StrToInt(TFile.ReadAllText(Path).Trim) else Result := 0;
end;
procedure Run;
var O,A,R: TJSONObject; Path,Hash,JobId,PreviewPath: string; Before: Integer;
begin
  Application.Initialize; F := TRigmEditorForm.Create(nil);
  try
    F.OpenSample; F.Editor.Save(TPath.Combine(Root,'protected-fixture.rigm')); Path := F.Editor.FileName;
    Hash := THashSHA2.GetHashStringFromFile(Path); var Revision := F.Editor.Document.Art.Revision;
    var PipeDirectory := '';
    for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--pipe-dir=') then PipeDirectory := ParamStr(I).Substring(11);
    var Info := ParseObject(TFile.ReadAllText(TDirectory.GetFiles(PipeDirectory,'*.control.json')[0],TEncoding.UTF8));
    try PipeName := JS(Info,'commandPipe'); finally Info.Free; end;
    O := Command('schema','{}'); try Check(JO(O,'commands').Count=64,'all 64 movie commands are exposed through common pipe'); finally O.Free; end;
    A := Request('single-request','fictional.avi'); var Signature := MovieProductionSignature(A);
    O := Call('produce',A.Clone as TJSONObject);
    try Check(not JB(O,'done') and (JS(O,'requestKey')='single-request'),'one top-level request starts continuous production'); JobId := JS(JO(O,'job'),'jobId'); finally O.Free; end;
    O := Call('produce',A.Clone as TJSONObject);
    try Check(JS(JO(O,'job'),'jobId')=JobId,'duplicate running request returns same job'); finally O.Free; end;
    R := Wait('single-request');
    try
      Check(JS(R,'state')='succeeded','single request completes audio preview and video');
      Check(JA(R,'completedSteps').ToJSON='["diagnostics","audio","preview","export"]','continuous steps run in order without manual stage commands');
      Path := JS(JO(R,'result'),'videoPath'); PreviewPath := JS(JO(R,'result'),'previewPath');
      Check(FileExists(Path) and FileExists(PreviewPath),'video and preview references identify actual outputs');
      Check((JI(JO(R,'result'),'audioTotal')=2) and (JA(JO(R,'result'),'audioFiles').Count=2),'all generated WAV and LAB references are returned');
      var Image := TPngImage.Create; try Image.LoadFromFile(PreviewPath); Check((Image.Width=320) and (Image.Height=180),'preview has exact production pixel dimensions'); finally Image.Free; end;
      Check(JA(R,'needs').Count=0,'completed production asks for no confirmations or configured information');
      Before := SynthesisCount; var VideoHash := THashSHA2.GetHashStringFromFile(Path);
      O := Call('produce',A.Clone as TJSONObject);
      try Check((JS(O,'state')='succeeded') and (JS(JO(O,'job'),'jobId')=JobId),'completed replay returns original result'); finally O.Free; end;
      Check((Before=SynthesisCount) and (THashSHA2.GetHashStringFromFile(Path)=VideoHash),'replay produces no duplicate audio and never rewrites video');
      O := Command('production-resume','{"requestKey":"single-request"}');
      try Check(JS(O,'state')='succeeded','resume of completed request is a no-op'); finally O.Free; end;
      A.RemovePair('script').Free; A.AddPair('script','narrator:Conflicting instruction.');
      O := Call('produce',A); A := nil;
      try Check(Needs(O,'request_conflict'),'same request key rejects different instructions'); finally O.Free; end;
      O := Command('status','{}'); try Check(JB(O,'modified'),'production changes remain unsaved and undoable'); finally O.Free; end;
    finally R.Free; A.Free; end;
    // No settings/voice/acting re-entry: the saved in-session setup is inherited.
    A := ParseObject('{"requestKey":"inherited","script":"narrator:A second fictional scene."}');
    O := Call('produce',A); O.Free; O := Wait('inherited');
    try Check((JS(O,'state')='succeeded') and (JA(O,'needs').Count=0),'new script inherits character voice engine output profile and acting defaults'); finally O.Free; end;
    O := Command('project','{}');
    try Check((JS(O,'character')='@sample') and (JI(O,'width')=320) and (JI(TJSONObject(JA(O,'speakers')[0]),'styleId')=101),'configured settings persist across top-level requests'); finally O.Free; end;
    // A disconnected real-style endpoint is blocked before any new synthesis/output.
    A := Request('engine-block','engine-block.avi'); JO(A,'settings').RemovePair('engineUrl').Free;
    JO(A,'settings').AddPair('engineUrl','http://127.0.0.1:51236'); Before := SynthesisCount;
    O := Call('produce',A); O.Free; O := Wait('engine-block');
    try Check((JS(O,'state')='blocked') and Needs(O,'engine_unavailable'),'missing VOICEVOX returns machine-readable engine_unavailable');
      Check((Before=SynthesisCount) and not FileExists(TPath.Combine(Root,'engine-block.avi')),'missing engine does not substitute a tone or create video');
    finally O.Free; end;
    O := Command('production-resume','{"requestKey":"engine-block","settings":{"engineUrl":"http://127.0.0.1:51235"}}'); O.Free;
    O := Wait('engine-block'); try Check(JS(O,'state')='succeeded','blocked production resumes after only missing engine correction'); finally O.Free; end;
    // Failure after one cue preserves it; resume generates only remaining cues.
    TFile.WriteAllText(TPath.Combine(Fixture,'fail-synthesis-number.txt'),(SynthesisCount+2).ToString);
    A := Request('partial-fail','partial.avi'); A.RemovePair('script').Free; A.AddPair('script','narrator:New partial first line.'+sLineBreak+'narrator:New partial second line.');
    O := Call('produce',A); O.Free; O := Wait('partial-fail');
    try Check((JS(O,'state')='failed') and Needs(O,'job_failed') and (JI(JO(O,'result'),'audioTotal')=1),'failure returns reason and preserves successful cue audio'); finally O.Free; end;
    Before := SynthesisCount; TFile.Delete(TPath.Combine(Fixture,'fail-synthesis-number.txt'));
    O := Command('production-resume','{"requestKey":"partial-fail"}'); O.Free; O := Wait('partial-fail');
    try Check(JS(O,'state')='succeeded','failed production resumes'); Check(SynthesisCount=Before+1,'resume synthesizes only unfinished cue'); finally O.Free; end;
    // Cancellation operates on this request's HTTP job and returns resumable status.
    TFile.WriteAllText(TPath.Combine(Fixture,'delay-ms.txt'),'800');
    if FileExists(TPath.Combine(Fixture,'synthesis-active.txt')) then TFile.Delete(TPath.Combine(Fixture,'synthesis-active.txt'));
    A := Request('cancel','cancel.avi'); A.RemovePair('script').Free; A.AddPair('script','narrator:A new cancel fixture line.');
    O := Call('produce',A); O.Free; var Deadline := GetTickCount64+5000;
    while not FileExists(TPath.Combine(Fixture,'synthesis-active.txt')) and (GetTickCount64<Deadline) do begin Application.ProcessMessages; Sleep(10); end;
    O := Command('production-status','{"requestKey":"cancel"}'); try Check(not JB(O,'done') and (JS(JO(O,'job'),'phase')='audio'),'status exposes live audio progress before cancellation'); finally O.Free; end;
    O := Command('production-cancel','{"requestKey":"cancel"}'); O.Free; O := Wait('cancel');
    try Check((JS(O,'state')='cancelled') and Needs(O,'job_cancelled') and not FileExists(TPath.Combine(Root,'cancel.avi')),'cancellation returns resumable result without completed video'); finally O.Free; end;
    TFile.WriteAllText(TPath.Combine(Fixture,'delay-ms.txt'),'120');
    O := Command('production-resume','{"requestKey":"cancel"}'); O.Free; O := Wait('cancel');
    try Check(JS(O,'state')='succeeded','cancelled production resumes through same upper-level API'); finally O.Free; end;
    // Existing user-like output is preserved and fixed by providing only a new path.
    var Existing := TPath.Combine(Root,'protected-output.avi'); TFile.WriteAllText(Existing,'KEEP');
    A := Request('existing-output','protected-output.avi'); O := Call('produce',A); O.Free; O := Wait('existing-output');
    try Check((JS(O,'state')='blocked') and Needs(O,'output_exists'),'existing destination returns only actual output conflict'); finally O.Free; end;
    Check(TFile.ReadAllText(Existing)='KEEP','existing output remains unchanged');
    A := TJSONObject.Create; A.AddPair('requestKey','existing-output'); A.AddPair('outputPath',TPath.Combine(Root,'new-output.avi'));
    O := Call('production-resume',A); O.Free; O := Wait('existing-output'); try Check(JS(O,'state')='succeeded','new destination correction resumes blocked output'); finally O.Free; end;
    O := Command('production-status','{"requestKey":"single-request"}'); try Check(JS(JO(O,'result'),'videoPath')=TPath.Combine(Root,'fictional.avi'),'earlier result remains retrievable after later requests'); finally O.Free; end;
    A := Request('missing-voice','voice.avi'); A.RemovePair('script').Free; A.AddPair('script','narrator:A new voice fixture line.');
    JO(A,'voices').RemovePair('narrator').Free; AddN(JO(A,'voices'),'narrator',-1);
    O := Call('produce',A); O.Free; O := Wait('missing-voice');
    try Check((JS(O,'state')='blocked') and (JA(O,'needs').Count=1) and Needs(O,'speaker_unavailable'),
      'unselected voice requests only that missing speaker assignment'); finally O.Free; end;
    O := Command('production-resume','{"requestKey":"missing-voice","voices":{"narrator":101}}'); O.Free; O := Wait('missing-voice');
    try Check(JS(O,'state')='succeeded','voice correction resumes with retained script and settings'); finally O.Free; end;
    A := Request('preview-only','preview-only.avi'); A.AddPair('deliver','preview');
    O := Call('produce',A); O.Free; O := Wait('preview-only');
    try Check((JS(O,'state')='succeeded') and FileExists(JS(JO(O,'result'),'previewPath')) and
      not FileExists(TPath.Combine(Root,'preview-only.avi')),'preview delivery completes audio and acting without creating video'); finally O.Free; end;
    A := Request('mp4','fictional.mp4'); O := Call('produce',A); O.Free; O := Wait('mp4');
    try Check((JS(O,'state')='succeeded') and FileExists(JS(JO(O,'result'),'videoPath')),'top-level request reuses existing FFmpeg MP4 export'); finally O.Free; end;
    A := ParseObject('{"requestKey":"json-inherited","script":{"cues":[{"speaker":"narrator","text":"An original JSON test line.","subtitle":"Explicit JSON subtitle."}]}}');
    O := Call('produce',A); O.Free; O := Wait('json-inherited');
    try Check(JS(O,'state')='succeeded','JSON script also inherits configured speaker engine character and output'); finally O.Free; end;
    O := Command('project','{}'); try Check(JS(TJSONObject(JA(O,'cues')[0]),'subtitle')='Explicit JSON subtitle.','authored JSON subtitles survive orchestration'); finally O.Free; end;
    A := ParseObject('{"requestKey":"stale","revision":-1,"script":"narrator:Stale input."}');
    O := Call('produce',A); try Check(Needs(O,'revision_stale'),'stale top-level mutation is machine-readable and rejected before edits'); finally O.Free; end;
    O := Command('production-status','{"requestKey":"unknown"}'); try Check(Needs(O,'request_unknown'),'unknown result key is reported explicitly'); finally O.Free; end;
    A := ParseObject('{"requestKey":"invalid","script":123}'); O := Call('produce',A);
    try Check(Needs(O,'input_invalid'),'invalid input is an actionable blocked response'); finally O.Free; end;
    A := ParseObject('{"requestKey":"invalid","script":"narrator:Corrected original input."}'); O := Call('production-resume',A); O.Free; O := Wait('invalid');
    try Check(JS(O,'state')='succeeded','intake error resumes with only corrected input'); finally O.Free; end;
    var X := ParseObject('{"settings":{"width":320,"height":180},"revision":1,"projectId":"a","requestKey":"a"}');
    var Y := ParseObject('{"requestKey":"b","settings":{"height":180,"width":320},"projectId":"b","revision":9}');
    try Check(MovieProductionSignature(X)=MovieProductionSignature(Y),'idempotence signature ignores key order and current identity fields'); finally Y.Free; X.Free; end;
    Check((F.Editor.Document.Art.Revision=Revision) and (THashSHA2.GetHashStringFromFile(TPath.Combine(Root,'protected-fixture.rigm'))=Hash),'production never changes its hosting RIGM document or saved input');
    Check(not FileExists(TPath.Combine(Root,'automatic.rigmovie')),'production does not automatically save a project');
  finally F.Free; end;
end;
begin
  Root := ''; Fixture := ''; FFmpeg := '';
  for var I := 1 to ParamCount do begin
    if ParamStr(I).StartsWith('--production-dir=') then Root := ParamStr(I).Substring(17);
    if ParamStr(I).StartsWith('--fixture-dir=') then Fixture := ParamStr(I).Substring(14);
    if ParamStr(I).StartsWith('--ffmpeg=') then FFmpeg := ParamStr(I).Substring(9);
  end;
  ForceDirectories(Root); Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); Checks.Add(E.Message); ExitCode := 1; end; end;
    var O := TJSONObject.Create;
    try AddN(O,'passed',Checks.Count-Ord(ExitCode<>0)); AddB(O,'success',ExitCode=0); AddB(O,'realSpeechVerified',False);
      O.AddPair('audioSource','explicit HTTP tone fixture, not VOICEVOX speech'); O.AddPair('directory',Root);
      O.AddPair('checks',Checks); Checks := nil; TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'production-results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally Checks.Free; end;
end.
