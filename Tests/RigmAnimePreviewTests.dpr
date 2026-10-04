program RigmAnimePreviewTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Math, System.Types, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Graphics, Vcl.Imaging.pngimage, RigmEditorForm, RigmMovieForm,
  RigmMovieTimeline, RigmMovieModel, RigmMovieSession, RigmMovieWorkflow,
  RigmMovieAudio, RigmMovieRendering, RigmStorage, RigmModel, RigmJson,
  RigmPipeTestClient;
type TTimelineAccess = class(TRigmMovieTimeline)
  public procedure Pick(X,Y: Integer);
  end;
procedure TTimelineAccess.Pick(X,Y: Integer);
begin MouseDown(mbLeft,[],X,Y); end;
var Host: TRigmEditorForm; Studio: TRigmMovieForm; Root,Source,SourceHash,PipeName: string;
  Checks: TJSONArray;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Find(Parent: TWinControl; const Name: string): TControl;
begin Result := nil; for var I := 0 to Parent.ControlCount-1 do begin var C := Parent.Controls[I]; if C.Name=Name then Exit(C); if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end; end; end;
procedure Pump(Ms: Cardinal=160);
begin var Deadline := GetTickCount64+Ms; repeat Application.ProcessMessages; Host.Editor.PollMovie; Sleep(5); until GetTickCount64>=Deadline; end;
function Call(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  Args.AddPair('projectId',Host.Editor.Movie.Project.Id); AddN(Args,'revision',Host.Editor.Movie.Project.Revision);
  var Reply := PipeCall(PipeName,'movie-'+Name,Args);
  try if not JB(Reply,'ok') then raise Exception.Create(Reply.ToJSON); Result := JO(Reply,'data').Clone as TJSONObject; finally Reply.Free; end;
end;
procedure Run(const Name: string; Args: TJSONObject=nil);
begin var O := Call(Name,Args); O.Free; end;
procedure Job;
begin
  var Deadline := GetTickCount64+180000;
  repeat Pump(20); var O := Call('job-status'); try if JB(O,'done') then begin Check(JS(O,'state')='succeeded','real engine / render job succeeds: '+JS(O,'kind')+' '+JS(O,'error')); Exit; end; finally O.Free; end; until GetTickCount64>=Deadline;
  raise Exception.Create('Real engine job timeout');
end;
procedure Capture(const Name: string);
begin
  var B := TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(Studio.ClientWidth,Studio.ClientHeight); Studio.PaintTo(B.Canvas,0,0); P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png')); finally P.Free; B.Free; end;
end;
procedure Tests;
const Script = '# 導入'+sLineBreak+
  'narrator:こんにちは、東北きりたんです。今日は架空のアニメ「星灯り郵便局」を紹介します。実在する作品ではありません。'+sLineBreak+
  '# おすすめ点'+sLineBreak+
  'narrator:見どころは、夜空に浮かぶ島へ手紙を届ける二人の掛け合いです。淡い星明かりの背景も、ほっとする雰囲気ですね。'+sLineBreak+
  '# 気になる点'+sLineBreak+
  'narrator:気になる点は、序盤に世界のルール説明が続くことです。テンポの速い作品が好きな人には、少しゆっくり感じるかもしれません。'+sLineBreak+
  '# 総評'+sLineBreak+
  'narrator:総評は、静かな冒険と心温まる会話を楽しみたい人向け。これは制作プレビュー用の架空レビューでした。ご視聴ありがとうございました。';
var O,A: TJSONObject; Plot: TRigmMovieTimeline; PCM: TRigmPcm; Doc: TRigmDocument;
begin
  Check(not FileExists(TPath.Combine(Root,'星灯り郵便局.rigmovie')),'new independent production target does not overwrite existing project');
  SourceHash := THashSHA2.GetHashStringFromFile(Source);
  Doc := LoadRigm(Source);
  try Check(Length(Doc.Layers)=44,'registered Kiritan material contains original 44 layers'); Check(Doc.Bones.Count>0,'registered character already supplies rig bones'); finally Doc.Free; end;
  Host := TRigmEditorForm.Create(nil);
  try
    Host.OpenSample;
    var PipeDirectory := ''; for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--pipe-dir=') then PipeDirectory := ParamStr(I).Substring(11);
    O := ParseObject(TFile.ReadAllText(TDirectory.GetFiles(PipeDirectory,'*.control.json')[0],TEncoding.UTF8)); try PipeName := JS(O,'commandPipe'); finally O.Free; end;
    Host.ShowMovieStudio(nil);
    for var I := 0 to Host.ComponentCount-1 do if Host.Components[I] is TRigmMovieForm then Studio := TRigmMovieForm(Host.Components[I]);
    Check(Studio<>nil,'shared pipe and GUI use the single host-owned movie studio'); Pump;
    A := TJSONObject.Create; A.AddPair('text',Script); Run('workflow-run',A); Run('workflow-next');
    Check(Host.Editor.Movie.Project.Cues.Count=4,'fictional review imports four independent sections');
    A := TJSONObject.Create; A.AddPair('character',Source); A.AddPair('title','架空アニメ紹介：星灯り郵便局'); A.AddPair('engineUrl','http://127.0.0.1:50021'); Run('update-project',A);
    Run('speakers-refresh'); Job;
    O := Call('speaker-list');
    try var Found := False; for var V in JA(O,'styles') do if (JS(TJSONObject(V),'name')='東北きりたん') and (JI(TJSONObject(V),'styleId')=108) then Found := True; Check(Found,'actual local VOICEVOX catalog supplies Tohoku Kiritan normal style 108'); finally O.Free; end;
    A := ParseObject('{"id":"narrator","name":"東北きりたん","styleId":108,"speed":1.05,"pitch":0,"intonation":1,"volume":1}'); Run('update-speaker',A);
    Run('workflow-run');
    var Deadline := GetTickCount64+15000; var Ready := False;
    repeat Pump(30); O := Call('preparation'); Ready := JB(O,'diagnosticsCurrent') and not JB(O,'diagnosticsBusy'); O.Free; until Ready or (GetTickCount64>=Deadline);
    Check(Ready,'real character and engine setup diagnosis becomes current'); Run('workflow-next');
    Check(Host.Editor.Movie.Project.WorkflowStage='audio','setup advances only after explicit next');
    A := TJSONObject.Create; A.AddPair('directory',TPath.Combine(Root,'Speech')); Run('workflow-run',A); Job;
    for var C in Host.Editor.Movie.Project.Cues do begin
      Check(Host.Editor.Movie.Project.AudioReady(C),'actual speech fingerprint is current for '+C.Scene);
      PCM := TRigmPcm.Load(C.WaveFile);
      try var Peak := 0; var Nonzero := 0; for var S in PCM.Samples do begin Peak := Max(Peak,Abs(Integer(S))); if S<>0 then Inc(Nonzero); end;
        Check((PCM.Duration>2) and (Peak>1000) and (Nonzero>PCM.Rate),'generated dialogue contains substantial decoded PCM for '+C.Scene);
      finally PCM.Free; end;
    end;
    Run('workflow-next'); Check(Host.Editor.Movie.Project.WorkflowStage='preview','audio advances explicitly to preview');
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'preview.png')); AddN(A,'time',1.0); Run('workflow-run',A); Job;
    Check((Host.Editor.Movie.Project.Width=1920) and (Host.Editor.Movie.Project.Height=1080) and (Host.Editor.Movie.Project.Fps=30),'production retains FullHD defaults');
    Check(not TRigmMoviePreview(Find(Studio,'MoviePreviewImage')).Frame.Empty,'real character speech preview is displayed');
    Run('waveform-refresh'); Job; Pump;
    PCM := MixMovieAudio(Host.Editor.Movie.Project);
    try PCM.Save(TPath.Combine(Root,'preview-dialogue.wav')); Check(SameValue(PCM.Duration,Host.Editor.Movie.Project.Duration,0.001),'combined real dialogue exactly matches timeline duration'); finally PCM.Free; end;
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'星灯り郵便局.rigmovie')); Run('save',A);
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'星灯り郵便局.rigmovie')); Run('open',A); Pump;
    Check(Host.Editor.Movie.Project.AudioReady(Host.Editor.Movie.Project.Cues[3]),'independent portable project reopens with actual speech');
    Plot := TRigmMovieTimeline(Find(Studio,'MovieWaveTimeline'));
    Check(Find(Studio,'MoviePreviewImage').ClientToScreen(Point(0,Find(Studio,'MoviePreviewImage').Height)).Y<=Plot.ClientToScreen(Point(0,0)).Y,'video preview is above horizontal timeline');
    var Offset := Host.Editor.Movie.Project.CueDuration(Host.Editor.Movie.Project.Cues[0])+0.5;
    var X := Plot.ScaleValue(82)+Round(Offset/Host.Editor.Movie.Project.Duration*(Plot.Width-Plot.ScaleValue(82)));
    TTimelineAccess(Plot).Pick(X,Plot.ScaleValue(50)); Pump;
    Check(Plot.SelectedCueId=Host.Editor.Movie.Project.Cues[1].Id,'timeline clip selects corresponding cue for right-side adjustment');
    Check(TMemo(Find(Studio,'MovieCueText')).Text=Host.Editor.Movie.Project.Cues[1].Text,'selected section editor shows matching dialogue');
    Check(Abs(Host.Editor.Movie.Time-Offset)<0.3,'horizontal timeline click seeks shared model');
    Deadline := GetTickCount64+15000; while (Host.Editor.Movie.Busy or Studio.PreviewPending) and (GetTickCount64<Deadline) do Pump(20);
    var BeforeTime := Host.Editor.Movie.Time; Run('play');
    Deadline := GetTickCount64+15000; while (Host.Editor.Movie.Time<BeforeTime+1) and (GetTickCount64<Deadline) do Pump(30);
    if not Host.Editor.Movie.Playing or (Host.Editor.Movie.Time<BeforeTime+1) then begin
      Writeln('PLAYBACK ',TLabel(Find(Studio,'MovieStatus')).Caption);
      O := Call('job-status'); Writeln('PLAYBACK JOB ',O.ToJSON); O.Free;
    end;
    Check(Host.Editor.Movie.Playing and (Host.Editor.Movie.Time>=BeforeTime+1),'Windows real-WAV playback starts and shared playhead advances');
    Run('pause'); Pump; Check(not Host.Editor.Movie.Playing,'stop action stops synchronized playback');
    while Host.Editor.Movie.Busy do Pump(20);
    Capture('editor-preview');
    TFile.WriteAllText(TPath.Combine(Root,'台本.txt'),Script,TEncoding.UTF8);
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'registered source character bytes remain unchanged');
  finally Host.Free; Host := nil; Studio := nil; end;
end;
begin
  Application.Initialize; Checks := TJSONArray.Create;
  for var I := 1 to ParamCount do begin if ParamStr(I).StartsWith('--production-dir=') then Root := ParamStr(I).Substring(17); if ParamStr(I).StartsWith('--character=') then Source := ParamStr(I).Substring(12); end;
  ForceDirectories(Root); var Report := TJSONObject.Create;
  try
    try Tests; AddB(Report,'success',True); except on E: Exception do begin AddB(Report,'success',False); Report.AddPair('error',E.Message); Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
    AddN(Report,'passed',Checks.Count); Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('directory',Root); Report.AddPair('source',Source); Report.AddPair('sourceSha256',SourceHash);
    Report.AddPair('voice','VOICEVOX:東北きりたん / ノーマル / styleId 108'); AddB(Report,'syntheticFixture',False); AddB(Report,'subjectiveListeningVerified',False); AddB(Report,'desktopScreenshotVerified',False);
    TFile.WriteAllText(TPath.Combine(Root,'verification.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; Checks.Free; end;
end.
