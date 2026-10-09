program ScriptNavigationCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Hash,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmWizardWorkspace, RigmScriptCreatorFrame, RigmScriptNavigationModel,
  RigmScriptNavigationProbe, RigmScriptPlacementModel, RigmPageNavigation,
  RigmMovieModel, RigmMovieComposition, RigmScriptTextModel, RigmScriptReviewModel, RigmScriptCastingModel,
  RigmScriptScenesModel, RigmScriptScenesFrame, RigmMovieLayout, RigmJson, PsdJson;
{$R *.res}
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Frame: TRigmScriptCreatorFrame;
  Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
procedure Capture(const Name: string);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try Bitmap.SetSize(Main.ClientWidth,Main.ClientHeight); Main.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
function StateAt(const Stage,Reached: string; Advance: Boolean): TJSONObject;
begin
  Result := PsdJson.ObjectText('{"hasProject":true,"castingReady":true,"wizard":{"scene-assignmentStatus":"complete"}}');
  AddB(Result,'canAdvance',Advance); PsdJson.Put(JO(Result,'wizard'),'stage',Stage);
  PsdJson.Put(JO(Result,'wizard'),'furthestStage',Reached);
end;
function Contains(State: TJSONObject; const Stage: string): Boolean;
begin Result := False; for var Id in ScriptVisibleStages(State) do if Id=Stage then Exit(True); end;
procedure CheckModel;
begin
  var State := StateAt('title','title',False);
  try
    Check(not Contains(State,'characters'),'next stage is hidden until title is ready');
    PsdJson.Put(State,'canAdvance',TJSONBool.Create(True));
    Check(Contains(State,'characters') and not Contains(State,'layout'),'only immediate next stage unlocks');
  finally State.Free; end;
  State := StateAt('scene-assignment','scenes',False);
  try Check(not ScriptStageAvailable(State,'scenes'),'revisited assignment cannot bypass completion'); finally State.Free; end;
  State := StateAt('subtitles','scenes',False);
  try
    AddB(State,'canConfirmSubtitles',True);
    Check(ScriptStageAvailable(State,'voice'),'valid subtitle input can be confirmed by selecting voice');
    Check(not ScriptStageAvailable(State,'scenes'),'subtitle confirmation cannot skip directly to scenes');
  finally State.Free; end;
  State := StateAt('voice','voice',False);
  try
    Check(not Contains(State,'voice-effects'),'unheard or unfinished audio does not unlock effects');
    AddB(State,'canConfirmVoice',True); Check(Contains(State,'voice-effects'),'heard audio unlocks effects with GUI confirmation');
  finally State.Free; end;
  State := StateAt('scenes','scenes',False);
  try
    Check(not Contains(State,'editor'),'unconfirmed scenes do not offer editor');
    PsdJson.Put(State,'canAdvance',TJSONBool.Create(True));
    Check(Contains(State,'editor') and not Contains(State,'summary'),'approved scenes offer editor directly');
    Check(ScriptStageAvailable(State,'title') and ScriptStageAvailable(State,'layout'),'reached earlier stages remain reachable');
  finally State.Free; end;
  State := StateAt('summary','summary',True);
  try
    PsdJson.Put(JO(State,'wizard'),'summaryChoice','none');
    Check(Contains(State,'closing') and not Contains(State,'summary-edit'),'legacy summary-none branch opens closing');
    PsdJson.Put(JO(State,'wizard'),'summaryChoice','yes');
    Check(Contains(State,'summary-edit') and not Contains(State,'closing'),'legacy summary-yes branch opens summary editing');
    Check(ScriptNextStage('summary-edit',JO(State,'wizard'))='voice','summary audio returns to voice');
    PsdJson.Put(JO(State,'wizard'),'voiceReturnStage','closing');
    Check(ScriptNextStage('voice-effects',JO(State,'wizard'))='closing','legacy supplementary audio returns to closing');
  finally State.Free; end;
end;
procedure SceneFixture;
begin
  W.NewScriptDraft;
  var P := W.ScriptDraft; P.Speaker('narrator').VoiceUuid := 'owned'; P.Speaker('narrator').StyleId := 0;
  PrepareScriptText(P); var Body := '';
  for var I := 0 to 11 do begin
    var S := TRigmMovieScene.Create; S.Title := 'シーン '+(I+1).ToString; P.Scenes.Add(S);
    var C := TRigmMovieCue.Create; C.Scene := S.Id; C.Text := 'シーン '+(I+1).ToString+' の画像を考えるためのセリフ。'; C.Subtitle := C.Text; P.Cues.Add(C);
    if I>0 then Body := Body+#13#10; Body := Body+C.Text;
  end;
  PsdJson.Put(ScriptSection(P,'body'),'text',Body);
  var Cast := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptCasting","schemaVersion":1,"state":"ready","requestId":"owned","roles":[],"rows":[]}');
  PsdJson.Put(P.ScriptWizard,'casting',Cast); Cast.AddPair('selectedCue',P.Cues[0].Id);
  var Role := TJSONObject.Create; JA(Cast,'roles').AddElement(Role); AddN(Role,'number',1);
  Role.AddPair('path','RIGM\fixture.rigm'); Role.AddPair('speakerId','narrator'); AddB(Role,'active',True);
  var Offset := 0;
  for var C in P.Cues do begin
    var Row := TJSONObject.Create; JA(Cast,'rows').AddElement(Row); Row.AddPair('cueId',C.Id); Row.AddPair('section','body');
    AddN(Row,'offset',Offset); AddN(Row,'length',Length(C.Text)); AddN(Row,'role',1); AddB(Row,'confirmed',True); Row.AddPair('origin','human'); Inc(Offset,Length(C.Text)+2);
  end;
  Cast.AddPair('sourceFingerprint',ScriptFingerprint(P)); Cast.AddPair('fingerprint',CastingFingerprint(P));
  P.Layout := 'theme'; P.LDirection := 'right'; P.BackgroundColor := LayoutBackgroundColor('dark');
  PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'layoutStatus','complete'); PsdJson.Put(P.ScriptWizard,'backgroundTone','dark');
  PsdJson.Put(P.ScriptWizard,'castingStatus','complete'); PsdJson.Put(P.ScriptWizard,'voiceStatus','complete');
  PsdJson.Put(P.ScriptWizard,'stage','scenes'); PsdJson.Put(P.ScriptWizard,'furthestStage','scenes');
  PsdJson.Put(P.ScriptWizard,'titleInput','工程リストとシーン一覧'); PsdJson.Put(P.ScriptWizard,'titleStatus','complete');
  PsdJson.Put(P.ScriptWizard,'scene-assignmentStatus','complete'); PrepareScriptScenes(P,False);
  P.Scenes[0].ImagePrompt := '雪の山を望む景色'; P.Scenes[0].Description := '山頂へ向かう'; P.Changed;
  W.SaveScriptDraft; W.OpenScriptDraft(P.FileName); Frame.SetActive(True); Application.ProcessMessages;
end;
procedure Run;
begin
  Root := ParamStr(1); if Root='' then raise Exception.Create('New output root required');
  if DirectoryExists(TPath.Combine(Root,'OwnedData')) then raise Exception.Create('Choose new output root');
  ForceDirectories(TPath.Combine(Root,'OwnedData')); CheckModel;
  var EmptyWorkspace := TRigmWizardWorkspace.Create(nil); var EmptyForm := TForm.Create(nil);
  EmptyWorkspace.StartPipe(TPath.Combine(Root,'EmptyData'));
  var EmptyFrame := TRigmScriptCreatorFrame.CreateForWorkspace(EmptyForm,EmptyWorkspace,TPath.Combine(Root,'EmptyData'));
  try
    EmptyWorkspace.OnScriptChanged(EmptyWorkspace);
    Check((EmptyFrame.FindComponent('ScriptStages') as TListBox).Items.Count=0,'workspace without a draft clears navigation safely');
  finally EmptyFrame.Free; EmptyWorkspace.Free; EmptyForm.Free; end;
  Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace; Main.ScaleForPPI(96);
  Main.SetBounds(0,0,1280,840); Main.Show; Application.ProcessMessages;
  Check((Main.FindComponent('WizardHeader') as TPanel).Visible,'shared header is visible on home');
  W.NewScriptDraft; Main.NavigateTo(apScriptCreate); Frame := Main.PageInstance(apScriptCreate) as TRigmScriptCreatorFrame;
  var List := Frame.FindComponent('ScriptStages') as TListBox; var Title := Frame.FindComponent('ScriptTitle') as TEdit;
  var Save := Frame.FindComponent('ScriptSave') as TButton; var Back := Frame.FindComponent('ScriptReturn') as TButton;
  Check(not (Main.FindComponent('WizardHeader') as TPanel).Visible,'script creator removes old top page description');
  Check((Frame.FindComponent('ScriptTitleToolbar')=nil) and (Frame.FindComponent('ScriptNext')=nil),'navigation icons and next button are removed');
  Check((List.Items.Count=1) and (List.ItemIndex=0),'empty script shows current title stage only');
  Title.Text := '工程リストの保存確認';
  Check(List.Items.Count=2,'entering title immediately reveals character stage');
  Title.Clear; Check(List.Items.Count=1,'clearing title hides unopened character stage'); Title.Text := '工程リストの保存確認';
  var InvalidTitle := '不正な題名'+#1; Title.Text := InvalidTitle;
  ClickScriptStage(Frame,'characters');
  Check((W.CurrentScriptStage='title') and (Title.Text=InvalidTitle) and (List.ItemIndex=0),'invalid title blocks navigation and retains exact pending input');
  Save.Click; Check(Title.Text=InvalidTitle,'save also retains invalid title input for correction');
  Title.Text := '工程リストの保存確認'; Save.Click;
  Check(not W.ScriptDraft.Modified and (W.CurrentScriptStage='title'),'save persists input without navigation');
  var OriginalBytes := TFile.ReadAllBytes(W.ScriptDraft.FileName);
  Title.Text := '保存失敗時にも保持';
  try
    TFile.WriteAllText(W.ScriptDraft.FileName,TFile.ReadAllText(W.ScriptDraft.FileName)+#13#10,TEncoding.UTF8);
    var ChangedHash := THashSHA2.GetHashStringFromFile(W.ScriptDraft.FileName); ClickScriptStage(Frame,'characters');
    Check((W.CurrentScriptStage='title') and (List.ItemIndex=0) and (Title.Text='保存失敗時にも保持') and W.ScriptDraft.Modified,'failed forward save retains current stage and pending input');
    Check(THashSHA2.GetHashStringFromFile(W.ScriptDraft.FileName)=ChangedHash,'failed forward save preserves externally changed file');
  finally TFile.WriteAllBytes(W.ScriptDraft.FileName,OriginalBytes); end;
  Title.Text := '工程リストの保存確認'; Save.Click;
  Capture('title-96'); ClickScriptStage(Frame,'characters');
  var Path := W.ScriptDraft.FileName; var Loaded := LoadMovie(Path);
  try Check((W.CurrentScriptStage='characters') and (JS(Loaded.ScriptWizard,'stage')='characters') and not W.ScriptDraft.Modified,'list forward saves destination before changing page'); finally Loaded.Free; end;
  Check((List.Items.Count=2) and (List.ItemIndex=1),'character stage waits for a selection before revealing layout');
  ClickScriptStage(Frame,'title'); Check((W.CurrentScriptStage='title') and (List.ItemIndex=0),'list returns to reached earlier stage');
  Title.Text := '戻った題名も保存'; Back.Click;
  Check((Main.CurrentPage=apScripts) and (Main.FindComponent('WizardHeader') as TPanel).Visible,'save and return opens management and restores its header');
  W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
  Check((W.CurrentScriptStage='characters') and (Title.Text='戻った題名も保存') and (Main.PageInstance(apScriptCreate)=Frame),'reopen restores saved input and last advanced stage in same frame');
  ClickScriptStage(Frame,'title');
  for var Ppi in [96,144,192] do begin
    Main.ScaleForPPI(Ppi); Main.SetBounds(0,0,MulDiv(1024,Ppi,96),MulDiv(680,Ppi,96)); Application.ProcessMessages;
    var Header := Frame.FindComponent('ScriptHeader') as TPanel; var LabelStage := Frame.FindComponent('ScriptCurrentStage') as TLabel;
    Check((Save.Left>=Back.Left+Back.Width) and (LabelStage.Left>=Save.Left+Save.Width) and (LabelStage.Left+LabelStage.Width<=Header.ClientWidth),'header actions and current stage fit at '+Ppi.ToString+' DPI');
    Check((List.ItemHeight=MulDiv(30,Ppi,96)) and (Title.Width>0) and (List.Parent.Width<Frame.Width),'sidebar and editor remain usable at '+Ppi.ToString+' DPI');
    List.Canvas.Font.Assign(List.Font);
    for var Stage in ScriptStages do
      Check(List.Canvas.TextWidth(ScriptStageCaption(Stage))+MulDiv(20,Ppi,96)<=List.ClientWidth,'stage caption fits without clipping at '+Ppi.ToString+' DPI: '+Stage);
    Check((GetWindowLong(List.Handle,GWL_STYLE) and (WS_HSCROLL or WS_VSCROLL))=0,'sidebar has no horizontal or vertical scrollbar at '+Ppi.ToString+' DPI');
    Capture('title-'+Ppi.ToString);
  end;
  Main.ScaleForPPI(96); Main.SetBounds(0,0,1280,840); SceneFixture;
  Check((W.CurrentScriptStage='scenes') and (List.ItemIndex=11) and (List.Items.Count=12),'image stage highlights stage twelve and retains earlier stages');
  var State := W.ScriptStatus;
  try Check(not Contains(State,'editor'),'real incomplete image fixture does not unlock editor'); finally State.Free; end;
  var SceneFrame: TRigmScriptScenesFrame := nil; var FirstRow: TRigmSceneImageRow := nil;
  for var I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TRigmScriptScenesFrame then SceneFrame := TRigmScriptScenesFrame(Frame.Components[I]);
  for var I := 0 to SceneFrame.ComponentCount-1 do if (SceneFrame.Components[I] is TRigmSceneImageRow) and
    (TRigmSceneImageRow(SceneFrame.Components[I]).SceneId=W.ScriptDraft.Scenes[0].Id) then FirstRow := TRigmSceneImageRow(SceneFrame.Components[I]);
  Check((FirstRow.Prompt.Text='雪の山を望む景色') and (FirstRow.Description.Text='山頂へ向かう'),'scene prompt and supplement survive sidebar layout and reopening');
  Check((FirstRow.Picture.Left+FirstRow.Picture.Width<=FirstRow.Width) and (FirstRow.Position.Left+FirstRow.Position.Width<=FirstRow.Width),'scene image and position controls fit narrowed editor');
  for var Stage in ScriptStages do begin
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'stage',Stage); W.BeginScriptTextEdit;
    Check(not W.ScriptTextEditing,'input hooks never lock communication at stage '+Stage);
  end;
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'stage','scenes');
  var OriginalHeight := Main.Height; Main.Height := 400; Application.ProcessMessages;
  Check((GetWindowLong(List.Handle,GWL_STYLE) and (WS_HSCROLL or WS_VSCROLL))=0,'crowded sidebar still shows no scrollbar');
  List.SetFocus; List.Perform(WM_KEYDOWN,VK_HOME,0); List.Perform(WM_KEYUP,VK_HOME,0);
  List.Perform(WM_KEYDOWN,VK_END,0); List.Perform(WM_KEYUP,VK_END,0);
  Check((List.ItemIndex=List.Items.Count-1) and (List.TopIndex>0),'keyboard reaches last stage in a short sidebar');
  var PreviousTop := List.TopIndex; List.Perform(WM_MOUSEWHEEL,WPARAM(120 shl 16),0);
  Check(List.TopIndex<PreviousTop,'mouse wheel scrolls sidebar without a visible scrollbar');
  Main.Height := OriginalHeight; Application.ProcessMessages;
  Capture('scenes-96');
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  if Root<>'' then begin
    var Result := TJSONObject.Create;
    try Result.AddPair('checks',Checks.Clone as TJSONArray); Result.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Result.ToJSON,TEncoding.UTF8);
    finally Result.Free; end;
  end;
  Main.Free; Checks.Free;
end.
