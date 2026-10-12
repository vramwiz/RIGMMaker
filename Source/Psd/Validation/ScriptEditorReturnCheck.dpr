program ScriptEditorReturnCheck;
{$APPTYPE CONSOLE}
// 専用台本で実ボタン・工程リストの往復と保存の失敗を確認する。実作品と通常アプリは操作しない。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmWizardWorkspace, RigmMovieWorkspaceFrame, RigmMovieEditorFrame,
  RigmMovieSession, RigmMovieModel, RigmMovieComposition, RigmMovieAudio, RigmPageNavigation, RigmScriptCreatorFrame,
  RigmScriptNavigationProbe, RigmScriptNavigationModel, RigmScriptTextModel, RigmScriptReviewModel,
  RigmScriptCastingModel, RigmScriptSubtitleModel, RigmScriptScenesModel, RigmMovieLayout, RigmJson, PsdJson,
  RigmModel, RigmSample, RigmStorage, RigmScriptClosingFrame, RigmScriptSummaryFrame;
{$R *.res}
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
function Movie: TRigmMovieWorkspaceFrame;
begin Result := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)); end;
function Creator: TRigmScriptCreatorFrame;
begin Result := TRigmScriptCreatorFrame(Main.PageInstance(apScriptCreate)); end;
procedure CaptureHeader(const Name: string; Header: TPanel);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try Bitmap.SetSize(Header.ClientWidth,Header.ClientHeight); Header.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure WaitIdle;
begin
  var Deadline := GetTickCount64+5000;
  while W.ActiveSession.Busy do begin
    W.ActiveSession.Poll;
    if GetTickCount64>Deadline then raise Exception.Create('Owned preview did not finish');
    Sleep(5);
  end;
  W.ActiveSession.Poll;
end;
procedure Fixture;
begin
  var Doc := TRigmDocument.Create;
  try PopulateRigmSample(Doc); Doc.Usable := True;
    ForceDirectories(W.Pipe.Workspace.Resolve('RIGM',False));
    SaveRigm(Doc,W.Pipe.Workspace.Resolve('RIGM\fixture.rigm',False));
  finally Doc.Free; end;
  W.NewScriptDraft; Main.NavigateTo(apScriptCreate);
  var P := W.ScriptDraft; P.Width := 640; P.Height := 360; P.Fps := 15;
  JA(P.ScriptWizard,'selectedCharacters').AddElement(PsdJson.ObjectText('{"path":"RIGM\\fixture.rigm","name":"専用キャラ","renderFormat":"rigm"}'));
  P.Speakers[0].VoiceUuid := 'owned'; P.Speakers[0].StyleId := 0;
  PrepareScriptText(P); var Text := '往復を確認する架空台本です。';
  PsdJson.Put(ScriptSection(P,'body'),'text',Text);
  var S := TRigmMovieScene.Create; S.Title := '専用シーン'; S.DisplayMode := 'none'; P.Scenes.Add(S);
  var C := TRigmMovieCue.Create; C.Scene := S.Id; C.Text := Text; C.Subtitle := Text; P.Cues.Add(C);
  var Audio := TRigmPcm.Create;
  try Audio.Rate := 48000; SetLength(Audio.Samples,24000);
    C.WaveFile := TPath.Combine(Root,'owned.wav'); C.AudioSeconds := Audio.Duration; Audio.Save(C.WaveFile);
  finally Audio.Free; end;
  C.AudioKey := P.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  var Cast := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptCasting","schemaVersion":1,"state":"ready","requestId":"owned","roles":[],"rows":[]}');
  PsdJson.Put(P.ScriptWizard,'casting',Cast); Cast.AddPair('selectedCue',C.Id);
  var Role := PsdJson.ObjectText('{"number":1,"path":"RIGM\\fixture.rigm","speakerId":"narrator","active":true}');
  JA(Cast,'roles').AddElement(Role);
  var Row := TJSONObject.Create; Row.AddPair('cueId',C.Id); Row.AddPair('section','body');
  AddN(Row,'offset',0); AddN(Row,'length',Length(Text)); AddN(Row,'role',1); AddB(Row,'confirmed',True);
  Row.AddPair('origin','human'); JA(Cast,'rows').AddElement(Row);
  Cast.AddPair('sourceFingerprint',ScriptFingerprint(P)); Cast.AddPair('fingerprint',CastingFingerprint(P));
  // 後工程へ到達済みのfixtureにも、現行の台本・字幕確認を揃える。
  PsdJson.Put(P.ScriptWizard,'scriptConfirmedFingerprint',ScriptFingerprint(P));
  PrepareScriptSubtitles(P); PsdJson.Put(P.ScriptWizard,'subtitlesStatus','complete');
  P.BackgroundColor := LayoutBackgroundColor('dark');
  PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'layoutStatus','complete');
  PsdJson.Put(P.ScriptWizard,'backgroundTone','dark'); PsdJson.Put(P.ScriptWizard,'castingStatus','complete');
  PsdJson.Put(P.ScriptWizard,'voiceStatus','complete'); PsdJson.Put(P.ScriptWizard,'titleInput','専用の往復台本');
  PsdJson.Put(P.ScriptWizard,'titleStatus','complete'); PsdJson.Put(P.ScriptWizard,'scene-assignmentStatus','complete');
  PsdJson.Put(P.ScriptWizard,'stage','scenes'); PsdJson.Put(P.ScriptWizard,'furthestStage','scenes');
  PrepareScriptScenes(P,False); RigmScriptScenesModel.SetScriptSceneApproved(P,S.Id,True); P.Changed;
  W.SaveScriptDraft; W.OpenScriptDraft(P.FileName); Creator.SetActive(True);
  Check(W.ScriptScenesAdvanceReason='','owned confirmed scene can enter movie editor');
  ClickScriptStage(Creator,'editor');
  Check(Main.CurrentPage=apMovieEdit,'actual stage list enters movie editor');
  WaitIdle;
end;
procedure CheckOptionalStages;
begin
  Check((W.ScriptDraft.ScriptWizard.GetValue('summaryData')=nil) and
    (W.ScriptDraft.ScriptWizard.GetValue('closingData')=nil),'direct scene-to-editor project has no optional drafts');
  ClickScriptStage(Creator,'summary');
  var State := W.ScriptStatus;
  try Check((W.CurrentScriptStage='summary') and not JB(State,'canAdvance'),'summary choice opens without inventing a decision');
  finally State.Free; end;
  CaptureHeader('summary-choice',Creator.FindComponent('ScriptPageBody') as TPanel);
  // 総評が未選択のまま次工程へ進まず、到達済みの締めを台本入力から再訪する。
  ClickScriptStage(Creator,'text');
  // 到達済みリストから未訪問の締めへ移動する、動画編集からの復帰経路。
  ClickScriptStage(Creator,'closing');
  State := W.ScriptStatus;
  try Check((W.CurrentScriptStage='closing') and not JB(State,'canAdvance') and
    (W.ScriptDraft.ScriptWizard.GetValue('closingData') is TJSONObject),'unvisited closing opens with an unconfirmed draft');
  finally State.Free; end;
  var Closing: TRigmScriptClosingFrame := nil;
  for var I := 0 to Creator.ComponentCount-1 do
    if Creator.Components[I] is TRigmScriptClosingFrame then Closing := TRigmScriptClosingFrame(Creator.Components[I]);
  Check((Closing<>nil) and Closing.Showing,'first closing visit displays the actual editing controls');
  CaptureHeader('closing-first-visit',Creator.FindComponent('ScriptPageBody') as TPanel);
  (Closing.FindComponent('ScriptClosingTitle') as TEdit).Text := '人間が入力した締め題名';
  Check(Closing.RequestFinish,'closing input can be retained without confirming completion');
  W.SaveScriptDraft(False);
  var ClosingDraft := JO(W.ScriptDraft.ScriptWizard,'closingData').ToJSON;
  var CueCount := W.ScriptDraft.Cues.Count; var SceneCount := W.ScriptDraft.Scenes.Count;
  // 完成済みの専用キャラが、通常の次工程の検査にも使えるまで待つ。
  var Deadline := GetTickCount64+10000;
  repeat
    State := W.ScriptCharacterLibrary(False); var Ready := False;
    try for var V in JA(State,'characters') do if JS(TJSONObject(V),'path')='RIGM\fixture.rigm' then Ready := JB(TJSONObject(V),'readyForScript');
    finally State.Free; end;
    if Ready then Break;
    if GetTickCount64>Deadline then raise Exception.Create('Owned optional-stage character did not become ready');
    Application.ProcessMessages; Sleep(10);
  until False;
  ClickScriptStage(Creator,'summary');
  var Choice := Creator.FindComponent('ScriptSummaryChoice') as TRadioGroup;
  Choice.ItemIndex := 0; Choice.OnClick(Choice); ClickScriptStage(Creator,'closing');
  Check((W.CurrentScriptStage='closing') and (JO(W.ScriptDraft.ScriptWizard,'closingData').ToJSON=ClosingDraft),
    'summary none follows the next-stage route and preserves existing closing input');
  ClickScriptStage(Creator,'summary'); Choice.ItemIndex := 1; Choice.OnClick(Choice);
  ClickScriptStage(Creator,'summary-edit');
  State := W.ScriptStatus;
  try Check((W.CurrentScriptStage='summary-edit') and not JB(State,'canAdvance') and
    (JS(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'status')='draft'),'summary yes opens an unconfirmed human draft');
  finally State.Free; end;
  var Summary: TRigmScriptSummaryFrame := nil;
  for var I := 0 to Creator.ComponentCount-1 do
    if Creator.Components[I] is TRigmScriptSummaryFrame then Summary := TRigmScriptSummaryFrame(Creator.Components[I]);
  Check((Summary<>nil) and Summary.Showing,'summary input controls are visible after choosing yes');
  CaptureHeader('summary-first-visit',Creator.FindComponent('ScriptPageBody') as TPanel);
  (Summary.FindComponent('ScriptSummaryText') as TMemo).Text := '専用台本の途中の総評です。';
  Check(Summary.RequestFinish,'incomplete summary can be saved without fabricating chart values');
  W.SaveScriptDraft(False);
  var Path := W.ScriptDraft.FileName; W.OpenScriptDraft(Path); Creator.SetActive(True);
  Check((W.CurrentScriptStage='summary-edit') and
    (JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'text')='専用台本の途中の総評です。') and
    (JO(W.ScriptDraft.ScriptWizard,'closingData').ToJSON=ClosingDraft),'reopening retains both optional human drafts');
  var Reopened := TRigmWizardWorkspace.Create(nil);
  try Reopened.StartPipe(Main.DataRoot); Reopened.OpenWork(Path);
    Check((Reopened.CurrentScriptStage='summary-edit') and
      (JO(Reopened.ScriptDraft.ScriptWizard,'summaryData').ToJSON=JO(W.ScriptDraft.ScriptWizard,'summaryData').ToJSON) and
      (JO(Reopened.ScriptDraft.ScriptWizard,'closingData').ToJSON=ClosingDraft),'fresh workspace restores summary and closing drafts without a GUI cache');
  finally Reopened.Free; end;
  ClickScriptStage(Creator,'summary'); Choice.ItemIndex := 0; Choice.OnClick(Choice); ClickScriptStage(Creator,'closing');
  Check((W.CurrentScriptStage='closing') and (W.ScriptDraft.Cues.Count=CueCount) and
    (W.ScriptDraft.Scenes.Count=SceneCount),'turning off an unconfirmed summary keeps original scenes and dialogue');
  ClickScriptStage(Creator,'summary'); Choice.ItemIndex := 1; Choice.OnClick(Choice); ClickScriptStage(Creator,'summary-edit');
  Check(JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'text')='専用台本の途中の総評です。',
    'revisiting summary never resets accepted human input');
  ClickScriptStage(Creator,'text');
end;
procedure Run;
begin
  Root := ParamStr(1); if Root='' then raise Exception.Create('Fresh output root required');
  if DirectoryExists(TPath.Combine(Root,'OwnedData')) then raise Exception.Create('Use a fresh root');
  ForceDirectories(Root); Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace;
  Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update;
  Check(not W.CanReturnMovieToScript and (W.Sessions.Count=0),'availability check never creates an empty session');
  W.NewWork; var Other := W.ActiveSession; Other.Project.Title := '別の未保存動画'; Main.NavigateTo(apMovieEdit);
  var Button := Main.FindComponent('WizardReturnScript') as TButton;
  Check(not Button.Visible,'legacy movie without wizard has no return button');
  Fixture; Check(Button.Visible and W.CanReturnMovieToScript,'wizard movie exposes return button');
  for var Ppi in [96,144,192] do begin
    Main.Scaled := True; Main.ScaleForPPI(Ppi); Main.Scaled := False;
    Main.SetBounds(0,0,MulDiv(1280,Ppi,96),MulDiv(840,Ppi,96));
    Check(Button.Width=MulDiv(160,Ppi,96),'return button scales once at '+Ppi.ToString+' DPI');
    var Header := Main.FindComponent('WizardHeader') as TPanel; var Canvas := TControlCanvas.Create;
    try Canvas.Control := Button; Canvas.Font.Assign(Button.Font);
      Check((Button.Left>=0) and (Button.Left+Button.Width<=Header.ClientWidth) and
        (Canvas.TextWidth(Button.Caption)+MulDiv(16,Ppi,96)<Button.ClientWidth),'return caption fits header at '+Ppi.ToString+' DPI');
    finally Canvas.Free; end;
    CaptureHeader('movie-header-'+Ppi.ToString,Header);
  end;
  Main.Scaled := True; Main.ScaleForPPI(96); Main.Scaled := False;
  var Id := W.ActiveSession.Project.Id; var Path := W.ActiveSession.Project.FileName;
  var CueId := W.ActiveSession.Project.Cues[0].Id; var WaveHash := THashSHA2.GetHashStringFromFile(ResolveMoviePath(Path,W.ActiveSession.Project.Cues[0].WaveFile));
  Check(W.Sessions.Count=2,'fixture and unrelated movie have distinct sessions');
  var Editor := Movie.CurrentEditor;
  var Title := Editor.FindComponent('MovieTitle') as TEdit; Title.Text := '未適用の題名';
  var Rejected := False; try Editor.PrepareScriptReturn; except on E: Exception do Rejected := E.Message.Contains('未適用'); end;
  Check(Rejected and (Main.CurrentPage=apMovieEdit) and (Title.Text='未適用の題名'),'unapplied property input blocks return and remains intact');
  Editor.InvokeAction(33); // 明示的に最新データへ戻した後で、別の入力を検証する。
  var A := W.ActiveSession.Status;
  try var Reply := W.ActiveSession.Execute('edit-begin',A); Reply.Free; finally A.Free; end;
  Rejected := False; try W.ReturnMovieToScript; except on E: Exception do Rejected := E.Message.Contains('ロック'); end;
  Check(Rejected and (W.Sessions.Count=2) and (W.ScriptDraft=nil),'edit lease blocks handoff without replacing either model');
  A := TJSONObject.Create; try var Reply := W.ActiveSession.Execute('edit-release',A); Reply.Free; finally A.Free; end;
  var Current := W.ActiveSession; var Before := THashSHA2.GetHashStringFromFile(Path);
  var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try Rejected := False; try W.ReturnMovieToScript; except on E: Exception do Rejected := True; end;
    Check(Rejected and (W.ActiveSession=Current) and (Movie.CurrentEditor=Editor) and (W.ScriptDraft=nil),'failed save retains live session and borrowed editor');
    Check(Before=THashSHA2.GetHashStringFromFile(Path),'failed save leaves original project unchanged');
  finally Guard.Free; end;
  Current.Project.Title := '動画で変更した題名'; Current.Project.OutputTarget := TPath.Combine(Root,'Exports\再開する動画.mp4');
  Current.Project.Changed; Main.NavigateTo(apMovieEdit); WaitIdle;
  Editor := Movie.CurrentEditor;
  var Subtitle := Editor.FindComponent('MovieCueSubtitle') as TMemo; Subtitle.Text := '動画で入力した字幕';
  var Target := Current.Project.OutputTarget;
  Button.Click;
  Check((Main.CurrentPage=apScriptCreate) and (W.CurrentScriptStage='text'),'actual return button opens stage five of the same script');
  Check((W.ScriptDraft.Id=Id) and SameText(W.ScriptDraft.FileName,Path),'return retains project UID and canonical file');
  Check((W.ScriptDraft.Title='動画で変更した題名') and (JS(W.ScriptDraft.ScriptWizard,'titleInput')=W.ScriptDraft.Title),'movie title survives subsequent script saves');
  Check(W.ScriptDraft.Cue(CueId).Subtitle='動画で入力した字幕','pending subtitle is applied before leaving movie editor');
  Check(W.ScriptDraft.OutputTarget=Target,'MP4 full path survives return');
  Check((W.Sessions.Count=1) and (W.Sessions[0]=Other) and (Other.Project.Title='別の未保存動画'),'handoff closes only the current movie session');
  Check(Movie.CurrentEditor=nil,'borrowed view is released before session disposal');
  Check(THashSHA2.GetHashStringFromFile(ResolveMoviePath(Path,W.ScriptDraft.Cue(CueId).WaveFile))=WaveHash,'existing audio material is preserved');
  var Saved := LoadMovie(Path);
  try Check((JS(Saved.ScriptWizard,'stage')='text') and (Saved.OutputTarget=Target) and (Saved.Cue(CueId).Subtitle='動画で入力した字幕'),'stage and current movie edits are saved together');
  finally Saved.Free; end;
  var Reopened := TRigmWizardWorkspace.Create(nil);
  try Reopened.StartPipe(Main.DataRoot); Reopened.OpenWork(Path);
    Check((Reopened.ScriptDraft<>nil) and (Reopened.ScriptDraft.Id=Id) and (Reopened.CurrentScriptStage='text'),'fresh workspace resumes script instead of stale movie session');
  finally Reopened.Free; end;
  ClickScriptStage(Creator,'scenes'); Check(W.CurrentScriptStage='scenes','left list reaches completed scenes after returning');
  ClickScriptStage(Creator,'editor');
  Check((Main.CurrentPage=apMovieEdit) and (W.Sessions.Count=2),'second editor entry succeeds without duplicate-session rejection');
  WaitIdle;
  Check((W.ActiveSession.Project.Id=Id) and (W.ActiveSession.Project.OutputTarget=Target) and (W.ActiveSession.Project.Cue(CueId).Subtitle='動画で入力した字幕'),'second editor displays the updated project and output path');
  Check(Movie.CurrentEditor<>nil,'new editor borrows the new live session');
  Button.Click;
  Check((Main.CurrentPage=apScriptCreate) and (W.Sessions.Count=1),'second return disposes the matching view safely');
  ClickScriptStage(Creator,'scenes'); ClickScriptStage(Creator,'editor'); WaitIdle;
  Editor := Movie.CurrentEditor; (Editor.FindComponent('MovieCueText') as TMemo).Text := '動画で変更したセリフです。';
  Editor.PrepareScriptReturn; W.ReturnMovieToScript;
  Check((W.ScriptDraft.Cue(CueId).Text='動画で変更したセリフです。') and (JS(JO(W.ScriptDraft.ScriptWizard,'casting'),'state')='stale'),'changed movie dialogue is retained and stale casting requires confirmation');
  W.SaveScriptDraft; W.OpenWork(Path);
  Check((Main.CurrentPage=apScriptCreate) and (W.ScriptDraft.Cue(CueId).Text='動画で変更したセリフです。'),'changed dialogue survives saving and reopening');
  CheckOptionalStages;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  if Root<>'' then begin
    var Report := TJSONObject.Create;
    try Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  end;
  Main.Free; Checks.Free;
end.
