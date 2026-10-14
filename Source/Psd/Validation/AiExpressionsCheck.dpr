program AiExpressionsCheck;
{$APPTYPE CONSOLE}
// 架空台本・所有キャラ・隔離設定だけで一括判定と表示を確認する。--live時だけ実Codexへ送る。
uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.Hash, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.ExtCtrls,
  Vcl.Imaging.pngimage, RigmWizardMainForm, RigmWizardWorkspace, RigmScriptCastingFrame,
  RigmScriptAiExpressions, RigmScriptCastingModel, RigmMovieModel, RigmMovieActing,
  RigmMovieComposition, RigmModel, RigmSample, RigmStorage, RigmJson, PsdJson;
{$R *.res}
type
  TObserver = class
    Frame: TRigmScriptCastingFrame;
    procedure Changed(Sender: TObject);
  end;
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Host: TForm;
  Frame: TRigmScriptCastingFrame; Observer: TObserver; Checks: TJSONArray; Root: string;
procedure TObserver.Changed(Sender: TObject);
begin if Frame<>nil then Frame.RefreshState; end;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS ',Name); end;
procedure Pump(Milliseconds: Cardinal);
begin
  var Deadline := GetTickCount64+Milliseconds;
  repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=Deadline;
end;
function LiveRequested: Boolean;
begin
  Result := False;
  for var I := 1 to ParamCount do if ParamStr(I)='--live' then Exit(True);
end;
function ContentWithoutFaces(P: TRigmMovieProject): string;
begin
  var O := P.Json;
  try
    O.RemovePair('revision').Free;
    JO(JO(O,'scriptWizard'),'casting').RemovePair('selectedCue').Free;
    for var V in JA(O,'cues') do for var Key in ['emotion','expression','faceAutomatic'] do TJSONObject(V).RemovePair(Key).Free;
    Result := O.ToJSON;
  finally O.Free; end;
end;
function ReplyFor(Request: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('projectId',JS(Request,'projectId')).AddPair('requestId',JS(Request,'requestId'));
  var A := TJSONArray.Create; Result.AddPair('assignments',A);
  for var V in JA(Request,'cues') do A.AddElement(TJSONObject.Create.AddPair('cueId',JS(TJSONObject(V),'cueId')).AddPair('expression','happy'));
end;
procedure ExpectRejected(Base: TRigmMovieProject; const CaseName: string; Change: TProc<TRigmMovieProject,TJSONObject,TJSONObject>);
begin
  var P := Base.Clone; var Request := CreateExpressionRequest(P); var Reply := ReplyFor(Request);
  try
    Change(P,Request,Reply);
    var Before := P.Json; var Rejected := False;
    try
      try ApplyExpressionResponse(P,Request,Reply); except on E: Exception do Rejected := True; end;
      Check(Rejected,CaseName+' is rejected');
      var After := P.Json;
      try Check(Before.ToJSON=After.ToJSON,CaseName+' does not partially modify the project'); finally After.Free; end;
    finally Before.Free; end;
  finally Reply.Free; Request.Free; P.Free; end;
end;
procedure ModelChecks;
begin
  var P := W.ScriptDraft.Clone;
  try
    P.Cues[0].Acting.Variants.AddElement(TJSONObject.Create.AddPair('groupId',PsdJson.NewId).AddPair('partId',PsdJson.NewId));
    var Request := CreateExpressionRequest(P); var Reply := ReplyFor(Request); var Schema := ExpressionOutputSchema(Request);
    try
      Check(JA(Request,'cues').Count=P.Cues.Count,'one request includes every dialogue cue');
      Check(JS(JO(JO(Schema,'properties'),'assignments'),'type')='array','structured output schema describes a batch');
      var Original := ContentWithoutFaces(P);
      Check(ApplyExpressionResponse(P,Request,Reply)=P.Cues.Count,'complete batch changes every automatic expression');
      Check(Original=ContentWithoutFaces(P),'voice text audio keys role confirmation subtitles scenes and variants are preserved');
      for var C in P.Cues do Check(not C.FaceAutomatic and (C.Emotion='happy'),'batch uses a saved explicit visual expression '+C.Id);
      var Reload := P.Clone;
      try Check(Reload.Cues[0].Emotion='happy','expressions survive JSON serialization'); finally Reload.Free; end;
    finally Schema.Free; Reply.Free; Request.Free; end;
  finally P.Free; end;
  ExpectRejected(W.ScriptDraft,'wrong request ID',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin PsdJson.Put(R,'requestId','other'); end);
  ExpectRejected(W.ScriptDraft,'wrong project ID',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin PsdJson.Put(R,'projectId','other'); end);
  ExpectRejected(W.ScriptDraft,'missing row',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin JA(R,'assignments').Remove(0).Free; end);
  ExpectRejected(W.ScriptDraft,'duplicate row',procedure(P: TRigmMovieProject; Q,R: TJSONObject)
    begin PsdJson.Put(TJSONObject(JA(R,'assignments')[1]),'cueId',JS(TJSONObject(JA(R,'assignments')[0]),'cueId')); end);
  ExpectRejected(W.ScriptDraft,'unknown row',procedure(P: TRigmMovieProject; Q,R: TJSONObject)
    begin PsdJson.Put(TJSONObject(JA(R,'assignments')[0]),'cueId','unknown'); end);
  ExpectRejected(W.ScriptDraft,'invalid expression in last row',procedure(P: TRigmMovieProject; Q,R: TJSONObject)
    begin PsdJson.Put(TJSONObject(JA(R,'assignments')[JA(R,'assignments').Count-1]),'expression','not-an-expression'); end);
  ExpectRejected(W.ScriptDraft,'changed source text',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin P.Cues[0].Text := '処理中に変更した文'; P.Changed; end);
  ExpectRejected(W.ScriptDraft,'manual expression change',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin P.Cues[0].FaceAutomatic := False; P.Cues[0].Emotion := 'angry'; P.Changed; end);
  ExpectRejected(W.ScriptDraft,'changed character assignment',procedure(P: TRigmMovieProject; Q,R: TJSONObject) begin P.Cues[0].SpeakerId := 'other'; P.Changed; end);
  P := W.ScriptDraft.Clone;
  try
    var Request := CreateExpressionRequest(P); var Reply := ReplyFor(Request);
    try
      PsdJson.Put(JO(P.ScriptWizard,'casting'),'selectedCue',P.Cues[1].Id); P.Changed;
      Check(ApplyExpressionResponse(P,Request,Reply)=P.Cues.Count,'selection-only revision change does not discard valid batch');
    finally Reply.Free; Request.Free; end;
  finally P.Free; end;
end;
procedure PrepareFixture;
begin
  var DataRoot := TPath.Combine(Root,'OwnedData'); ForceDirectories(TPath.Combine(DataRoot,'RIGM'));
  var D := TRigmDocument.Create;
  try PopulateRigmSample(D); D.Usable := True; SaveRigm(D,TPath.Combine(DataRoot,'RIGM\fixture.rigm')); finally D.Free; end;
  Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace;
  W.NewScriptDraft; W.SetScriptTitle('AI表情の架空台本'); W.NextScriptDraft;
  var Ready := False; var Deadline := GetTickCount64+15000;
  repeat
    var Catalog := W.ScriptCharacterLibrary(False);
    try for var V in JA(Catalog,'characters') do Ready := Ready or JB(TJSONObject(V),'readyForScript'); finally Catalog.Free; end;
    if Ready then Break;
    Pump(100);
    if GetTickCount64>Deadline then raise Exception.Create('Owned character preparation timeout');
  until False;
  var Paths := TJSONArray.Create; Paths.Add('RIGM\fixture.rigm');
  try W.SetScriptCharacters(Paths); finally Paths.Free; end;
  W.NextScriptDraft; W.NextScriptDraft; W.NextScriptDraft;
  Check(W.CurrentScriptStage='text','owned fixture follows the normal title character layout and placement stages');
  W.SetScriptText('body','やった、ずっと欲しかった本が手に入ったよ。'+#13#10+
    '大切な友だちを失って、涙が止まらない。'+#13#10+'約束を何度も破るなんて、もう許せない。'+#13#10+
    'どうして鍵が内側から掛かっているのだろう。'+#13#10+'ここは危険だ。全員、安全な場所へ避難してくれ。'+#13#10+
    '落ち着いて。そばにいるから、大丈夫だよ。');
  W.EndScriptTextEdit; W.NextScriptDraft;
  W.NextScriptDraft; W.SetScriptSummaryChoice('none'); W.NextScriptDraft;
  var Draft := JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  try for var Key in ['representativeChoice','endChoice','thumbnailChoice'] do PsdJson.Put(Draft,Key,'none'); W.SetScriptClosingDraft(Draft); finally Draft.Free; end;
  W.CompleteScriptClosing; W.NextScriptDraft; W.NextScriptDraft;
  Check(W.CurrentScriptStage='casting','owned fixture reaches casting through script confirmation');
  Check(W.ScriptDraft.Cues.Count>=6,'all fictional lines are materialized');
  for var I := 0 to W.ScriptDraft.Cues.Count-1 do W.AssignCasting(W.ScriptDraft.Cues[I].Id,1,True);
  for var C in W.ScriptDraft.Cues do begin
    C.VoiceReading := C.Text; C.AudioKey := W.ScriptDraft.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  end;
  Host := TForm.CreateNew(nil); Host.Caption := 'AI表情一括設定の所有fixture'; Host.SetBounds(40,40,1280,820);
  Frame := TRigmScriptCastingFrame.CreateForWorkspace(Host,W); Frame.Parent := Host;
  Observer := TObserver.Create; Observer.Frame := Frame; W.OnScriptChanged := Observer.Changed;
  Host.Show; ShowWindow(Host.Handle,SW_SHOWNOACTIVATE); Frame.RefreshState; Pump(100);
  Check(Frame.FindComponent('ScriptCastingExpressionAi') is TButton,'casting UI has the AI batch button');
  var Button := Frame.FindComponent('ScriptCastingExpressionAi') as TButton;
  var Status := Frame.FindComponent('ScriptCastingExpressionAiStatus') as TLabel;
  var Face := Frame.FindComponent('ScriptCastingFacePanel') as TPanel;
  var Rows := Frame.FindComponent('ScriptCastingRows') as TListView;
  Check(Button.Showing and (Button.Width>150) and (Status.Width>150),'batch button and status have usable visible areas');
  Check(Button.Parent.Top>=Face.Top+Face.Height,'AI action row does not overlap expression selection');
  Check(Rows.Top>=Button.Parent.Top+Button.Parent.Height,'dialogue list begins below the AI action row');
end;
procedure FailureChecks;
begin
  var Before := W.ScriptDraft.Json;
  var Previous := GetEnvironmentVariable('CODEX_PIPE_EXE');
  try
    Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(TPath.Combine(Root,'missing-codex.exe')));
    (Frame.FindComponent('ScriptCastingExpressionAi') as TButton).Click;
    var Deadline := GetTickCount64+10000;
    while W.ExpressionAiBusy do begin Pump(50); if GetTickCount64>Deadline then raise Exception.Create('Failure recovery timeout'); end;
    Check(Pos('失敗',W.ExpressionAiMessage)>0,'missing Codex executable is reported as a failure');
    var After := W.ScriptDraft.Json;
    try Check(Before.ToJSON=After.ToJSON,'startup failure does not change any project field'); finally After.Free; end;
    Check((Frame.FindComponent('ScriptCastingExpressionAi') as TButton).Enabled,'startup failure restores the retry button');
  finally
    if Previous='' then Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',nil)
    else Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(Previous));
    Before.Free;
  end;
end;
procedure LiveChecks;
begin
  var Button := Frame.FindComponent('ScriptCastingExpressionAi') as TButton;
  var Cancel := Frame.FindComponent('ScriptCastingExpressionAiCancel') as TButton;
  var Progress := Frame.FindComponent('ScriptCastingExpressionAiProgress') as TProgressBar;
  var Original := ContentWithoutFaces(W.ScriptDraft);
  Button.Click;
  Check(W.ExpressionAiBusy and not Button.Enabled,'button starts an asynchronous job and prevents duplicate requests');
  Check(Progress.Visible and (Progress.Style=pbstMarquee) and Cancel.Visible,'processing progress and cancellation are visible');
  var Rejected := False; try W.StartExpressionAi; except on E: Exception do Rejected := True; end;
  Check(Rejected,'duplicate start is rejected while busy');
  // 行の選択は許可し、入力内容が同一なら返却結果を適用する。
  W.SelectCasting(W.ScriptDraft.Cues[1].Id);
  var Deadline := GetTickCount64+330000; var Ticks := 0;
  while W.ExpressionAiBusy do begin Pump(100); Inc(Ticks); if GetTickCount64>Deadline then raise Exception.Create('Live AI timeout'); end;
  Check(Ticks>0,'VCL message loop continues during the AI request');
  Check(Pos('判定が完了',W.ExpressionAiMessage)>0,'live Codex JSON batch is validated and applied: '+W.ExpressionAiMessage);
  Check(Original=ContentWithoutFaces(W.ScriptDraft),'live response preserves all content except visual expression revision and selected row');
  var Distinct := TDictionary<string,Boolean>.Create;
  try
    for var C in W.ScriptDraft.Cues do begin
      Check(not C.FaceAutomatic,'live response sets explicit expression '+C.Id);
      Check(C.AudioKey=W.ScriptDraft.AudioFingerprint(C),'live expression preserves generated audio fingerprint '+C.Id);
      Check(C.VoiceHeardKey=C.AudioKey,'live expression preserves playback confirmation '+C.Id);
      Distinct.AddOrSetValue(C.Emotion,True);
    end;
    Check(Distinct.Count>=3,'actual model distinguishes at least three meanings without relying on punctuation');
  finally Distinct.Free; end;
  Check(Button.Enabled and not Progress.Visible and not Cancel.Visible,'completion restores normal UI controls');
  var LiveLog := W.ExpressionAiLogPath;
  TFile.WriteAllText(TPath.Combine(Root,'live-log-path.txt'),LiveLog,TEncoding.UTF8);
  W.SaveScriptDraft;
  var Saved := LoadMovie(W.ScriptDraft.FileName);
  try
    for var I := 0 to Saved.Cues.Count-1 do Check(Saved.Cues[I].Emotion=W.ScriptDraft.Cues[I].Emotion,'saved expressions reopen '+I.ToString);
  finally Saved.Free; end;
  var Before := W.ScriptDraft.Json;
  try
    Button.Click; Cancel.Click;
    Deadline := GetTickCount64+10000;
    while W.ExpressionAiBusy do begin Pump(50); if GetTickCount64>Deadline then raise Exception.Create('Cancel timeout'); end;
    var After := W.ScriptDraft.Json;
    try Check(Before.ToJSON=After.ToJSON,'cancelled AI job leaves all project data unchanged'); finally After.Free; end;
    Check(Pos('中止',W.ExpressionAiMessage)>0,'cancellation is reported visibly');
  finally Before.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1); ForceDirectories(Root); Checks := TJSONArray.Create;
  var Report := TJSONObject.Create; Report.AddPair('checks',Checks);
  try
    try
      PrepareFixture; ModelChecks; FailureChecks;
      if LiveRequested then LiveChecks;
      AddB(Report,'live',LiveRequested); AddB(Report,'success',True);
    except on E: Exception do begin Report.AddPair('error',E.ClassName+': '+E.Message); ExitCode := 1; Writeln('FAIL ',E.Message); end; end;
    TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  finally
    if W<>nil then W.OnScriptChanged := nil;
    Observer.Free; Host.Free; Main.Free; Report.Free;
  end;
end.
