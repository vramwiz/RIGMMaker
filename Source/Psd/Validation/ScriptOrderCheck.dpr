program ScriptOrderCheck;
{$APPTYPE CONSOLE}
// 専用台本と専用キャラだけで工程順・直接入力・保存再開・総評の独立シーンを確認する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Hash, System.Math,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Themes, Vcl.Styles,
  RigmWizardMainForm, RigmWizardWorkspace, RigmPageNavigation, RigmScriptCreatorFrame,
  RigmScriptTextFrame, RigmScriptSubtitleFrame, RigmScriptSummaryFrame, RigmScriptClosingFrame, RigmScriptConfirmationFrame, RigmScriptSceneAssignmentFrame, RigmScriptCastingFrame,
  RigmScriptVoiceFrame, SerifVoicevoxSettingsFrame, SerifVoicevoxAccentView, SerifVoicevoxAudioSettings,
  SerifVoicevoxAudioSettingsFrame, SerifVoicevoxIntonationFrame, SerifVoicevoxLengthFrame, VerticalSliderControl, VoicevoxToolbarButtons,
  RigmScriptNavigationProbe, RigmScriptNavigationModel, RigmScriptPlacementModel, RigmScriptPlacementFrame, RigmPlacementGeometry,
  RigmMovieModel, RigmMovieChart, RigmMovieAudio, RigmModel, RigmSample, RigmStorage, RigmMovieActing, ArtDocument,
  RigmScriptTextModel, RigmScriptReviewModel, RigmScriptVoiceModel, RigmScriptCastingModel, RigmScriptSummaryModel, RigmScriptSubtitleModel,
  RigmScriptConfirmationModel, RigmScriptResearchModel, RigmScriptSceneAssignmentModel, RigmScriptScenesModel, RigmJson, PsdJson,
  RigmScriptThumbnailModel, RigmMovieEndCards, RigmMovieEndingDialog, RigmScriptClosingModel,
  System.NetEncoding, System.Generics.Collections, RigmScriptScenesFrame, RigmMovieComposition,
  RigmMovieCompositor, RigmMovieLayout, RigmMovieImageTransfer, RigmMovieRendering, RigmMovieSession,
  RigmMovieMp4, RigmFFmpegApi, RigmFFmpegTypes, RigmMovieText, RigmMovieCompositionCommands,
  RigmMoviePsdRendering, RigmCharacterCatalog, PsdCharacter, PsdWorkspace, PsdPackage, PsdAnimation;
{$R *.res}
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Creator: TRigmScriptCreatorFrame;
  Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
function StageFrame(Kind: TClass): TComponent;
begin Result := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I].InheritsFrom(Kind) then Exit(Creator.Components[I]); end;
procedure Go(const Stage: string);
begin
  ClickScriptStage(Creator,Stage);
  if (Stage='editor') and (Main.CurrentPage=apMovieEdit) then Exit;
  if W.CurrentScriptStage<>Stage then raise Exception.Create('Cannot open '+Stage+': '+(Creator.FindComponent('ScriptTitleStatus') as TLabel).Caption);
end;
procedure Capture(const Name: string);
begin
  var B := TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(Main.ClientWidth,Main.ClientHeight); Main.PaintTo(B.Canvas,0,0); P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally P.Free; B.Free; end;
end;
procedure WaitVoice;
begin
  var Deadline := GetTickCount64+10000;
  repeat
    Application.ProcessMessages; Sleep(10);
    var State := W.VoiceConnectionStatus; try if JS(State,'error')<>'' then raise Exception.Create(JS(State,'error')); finally State.Free; end;
    if W.VoiceCatalogReady then Break;
    if GetTickCount64>Deadline then raise Exception.Create('Owned voice wait timed out');
  until False;
end;
{$I RigmPlacementOverflowValidation.inc}
{$I RigmCastingExpressionValidation.inc}
{$I RigmAccentEditingValidation.inc}
{$I RigmVoiceReuseValidation.inc}
{$I RigmSceneAssignmentValidation.inc}
{$I RigmScriptDisplayValidation.inc}
procedure StartScript;
begin
  Main.NavigateTo(apHome); W.NewScriptDraft; W.ScriptDraft.EngineUrl := ParamStr(2); Main.NavigateTo(apScriptCreate);
  Creator := Main.PageInstance(apScriptCreate) as TRigmScriptCreatorFrame;
  (Creator.FindComponent('ScriptTitle') as TEdit).Text := '専用の工程順確認'; Go('characters');
  var Deadline := GetTickCount64+10000; var Found := False;
  repeat
    Application.ProcessMessages;
    for var Item in (Creator.FindComponent('ScriptCharacters') as TListView).Items do
      if JB(TJSONObject(Item.Data),'readyForScript') then begin Item.Checked := True; Found := True; end;
    if Found then Break; if GetTickCount64>Deadline then raise Exception.Create('Owned character not ready'); Sleep(10);
  until False;
  Go('layout'); Go('placement'); CheckPlacementOverflow; Go('text');
  if not FindCmdLineSwitch('check-summary-lines') then CheckScriptDisplay;
  W.SetScriptText('opening','前段の確認セリフ。'); W.SetScriptText('body','本題の一行目。'+#13#10+'本題の二行目。'); W.SetScriptText('closing','〆の確認セリフ。');
  Go('review'); Go('summary'); Check(W.ScriptDraft.Cues.Count=0,'stage six proceeds to summary before casting creates dialogue');
end;
procedure ConfirmClosing;
  procedure CheckLayout(Frame: TComponent; Ppi: Integer);
  begin
    var B := TBitmap.Create;
    try
      for var I := 0 to 1 do begin
        var L := Frame.FindComponent('ScriptClosingImageLabel'+I.ToString) as TLabel;
        var Choice := Frame.FindComponent('ScriptClosingChoice'+I.ToString) as TComboBox;
        var Adopt := Frame.FindComponent('ScriptClosingAdopt'+I.ToString) as TButton;
        var Path := Frame.FindComponent('ScriptClosingPath'+I.ToString) as TLabel;
        B.Canvas.Font.Assign(L.Font);
        Check(L.Visible and (L.Width>=B.Canvas.TextWidth(L.Caption)) and (L.Height>=B.Canvas.TextHeight(L.Caption)) and
          (L.Top+L.Height<=Choice.Top) and (Choice.Left+Choice.Width<Adopt.Left) and
          (Adopt.Left+Adopt.Width<=Adopt.Parent.ClientWidth) and (Path.Width=L.Width),
          'closing image heading, choice, button and path stay readable at '+Ppi.ToString+' DPI, row '+I.ToString);
      end;
      var Memo := Frame.FindComponent('ScriptClosingSpeech') as TMemo;
      var Confirm := Frame.FindComponent('ScriptClosingReady') as TButton;
      B.Canvas.Font.Assign(Confirm.Font);
      Check((Memo.Height>=MulDiv(100,Ppi,96)) and not Memo.ReadOnly and
        (Confirm.Width>B.Canvas.TextWidth(Confirm.Caption)+MulDiv(12,Ppi,96)),
        'closing speech and labeled confirmation remain usable at '+Ppi.ToString+' DPI');
    finally B.Free; end;
  end;
begin
  var Frame := StageFrame(TRigmScriptClosingFrame);
  Check((Frame.FindComponent('ScriptClosingRects')=nil) and (Frame.FindComponent('ScriptClosingEndSeconds')=nil) and
    (Frame.FindComponent('ScriptClosingThumbnailSeconds')=nil) and (Frame.FindComponent('ScriptClosingAddReserved')=nil),
    'closing page removes seconds and coordinate table controls');
  Check(not (Frame.FindComponent('ScriptClosingChoice2') as TComboBox).Visible and
    ((Frame.FindComponent('ScriptClosingPreviewMode') as TComboBox).Items.Count=2),'closing defers mandatory thumbnail to the final image item');
  for var I := 0 to 1 do Check((Frame.FindComponent('ScriptClosingChoice'+I.ToString) as TComboBox).Text<>'',
    'unselected closing image has an explicit prompt '+I.ToString);
  if FindCmdLineSwitch('check-dpi') then begin
    for var Ppi in [96,144,192] do begin
      Main.Scaled := True; Main.ScaleForPPI(Ppi); Main.Scaled := False;
      Main.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(900,Ppi,96)); Main.Update;
      CheckLayout(Frame,Ppi); Capture('closing-unselected-'+Ppi.ToString);
    end;
    Main.Scaled := True; Main.ScaleForPPI(96); Main.Scaled := False; Main.SetBounds(0,0,1440,900);
  end else CheckLayout(Frame,96);
  var D := JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  try
    PsdJson.Put(D,'endSeconds','7.5'); PsdJson.Put(D,'thumbnailSeconds','3.5');
    PsdJson.Put(JO(D,'rect'),'x','0.04'); W.SetScriptClosingDraft(D);
    (Frame.FindComponent('ScriptClosingTitle') as TEdit).Text := '締めに表示する架空の題名';
    TButton(Frame.FindComponent('ScriptClosingDone')).Click;
    var Actual := JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft');
    Check((JS(Actual,'endSeconds')='7.5') and (JS(Actual,'thumbnailSeconds')='3.5') and
      (JO(Actual,'rect').ToJSON=JO(D,'rect').ToJSON) and (JA(Actual,'reserved').ToJSON=JA(D,'reserved').ToJSON),
      'editing visible closing fields preserves existing hidden seconds and geometry');
  finally D.Free; end;
  var Image := TBitmap.Create; var Png := TPngImage.Create;
  try Image.SetSize(160,90); Image.Canvas.Brush.Color := clBlue; Image.Canvas.FillRect(Rect(0,0,160,90));
    Png.Assign(Image); Png.SaveToFile(TPath.Combine(Root,'closing-owned.png'));
  finally Png.Free; Image.Free; end;
  var ImageIndex := 0;
  for var Kind in ['representative','endImage'] do begin
    W.AdoptScriptClosingImage(Kind,TPath.Combine(Root,'closing-owned.png'));
    var SelectedPath := (Frame.FindComponent('ScriptClosingPath'+ImageIndex.ToString) as TLabel).Caption;
    Check(((Frame.FindComponent('ScriptClosingChoice'+ImageIndex.ToString) as TComboBox).ItemIndex=1) and
      (Pos('画像を選択済み',SelectedPath)=1),
      'adopting an existing closing image refreshes its visible selection '+Kind);
    Inc(ImageIndex);
  end;
  var Mode := Frame.FindComponent('ScriptClosingPreviewMode') as TComboBox;
  var BeforePaint := W.ScriptDraft.Json;
  try
    for var I := 0 to 1 do begin Mode.ItemIndex := I; Mode.OnChange(Mode); Capture('closing-selected-'+I.ToString); end;
    var AfterPaint := W.ScriptDraft.Json;
    try Check(AfterPaint.ToJSON=BeforePaint.ToJSON,'closing previews leave choices, source text and saved geometry unchanged');
    finally AfterPaint.Free; end;
  finally BeforePaint.Free; end;
  Mode.ItemIndex := 0; Mode.OnChange(Mode);
  for var I := 0 to 1 do begin var Choice := Frame.FindComponent('ScriptClosingChoice'+I.ToString) as TComboBox; Choice.ItemIndex := 0; Choice.OnChange(Choice); end;
  (Frame.FindComponent('ScriptClosingSpeech') as TMemo).Text := '締め設定で編集した〆のセリフ。';
  TButton(Frame.FindComponent('ScriptClosingReady')).Click;
  Check(JS(JO(W.ScriptDraft.ScriptWizard,'closingData'),'status')='complete','closing confirms image choices without casting or generated audio');
  Capture('closing-before-casting');
  Go('script-confirm');
end;
procedure CheckSummaryDefaults;
begin
  var Project := TRigmMovieProject.Create; Project.ScriptWizard := TJSONObject.Create;
  try
    PrepareScriptSummary(Project);
    var Data := JO(Project.ScriptWizard,'summaryData'); var Default := JO(Data,'draft');
    Check(JA(Default,'items').Count=5,'new summary drafts contain exactly five named rating axes');
    var Legacy := Default.Clone as TJSONObject;
    var Items := TJSONArray.Create;
    for var I := 1 to 8 do begin
      var Item := TJSONObject.Create; Item.AddPair('label','旧項目'+I.ToString); Item.AddPair('value',I.ToString); Items.AddElement(Item);
    end;
    PsdJson.Put(Legacy,'items',Items); PsdJson.Put(Legacy,'text','保持する総評');
    var Fixed := ScriptSummaryFixedDraft(Legacy);
    try
      RigmScriptSummaryModel.SetScriptSummaryDraft(Project,Legacy);
      RigmScriptSummaryModel.SetScriptSummaryDraft(Project,Fixed);
      Check((JA(JO(Data,'draft'),'items').Count=5) and (JS(JO(Data,'draft'),'text')='保持する総評') and
        (JS(TJSONObject(JA(JO(Data,'draft'),'items')[2]),'value')='3'),
        'legacy summary conversion keeps the entered speech and existing ordinal scores');
      Check(JO(Data,'previousChartDraft').ToJSON=Legacy.ToJSON,
        'converting legacy axes archives every original label and score including rows beyond five');
    finally Fixed.Free; Legacy.Free; end;
  finally Project.Free; end;
end;
procedure CheckSummary;
begin
  CheckSummaryDefaults;
  var Choice := Creator.FindComponent('ScriptSummaryChoice') as TRadioGroup;
  Choice.ItemIndex := 1; Choice.OnClick(Choice); Go('summary-edit');
  var Frame := StageFrame(TRigmScriptSummaryFrame);
  var Text := Frame.FindComponent('ScriptSummaryText') as TMemo;
  Check(not Text.ReadOnly,'summary text accepts input immediately without an edit-mode button');
  Text.Text := '入力した総評のセリフ。';
  Check(JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'text')=Text.Text,'typing summary text immediately updates the shared draft');
  var Rejected := False; try W.CompleteScriptSummary; except on E: Exception do Rejected := True; end;
  Check(Rejected,'missing chart values cannot be falsely confirmed');
  (Frame.FindComponent('ScriptSummarySubtitle') as TMemo).Text := '独立した総評字幕';
  (Frame.FindComponent('ScriptSummaryReading') as TMemo).Text := 'そうひょうのよみ。';
  (Frame.FindComponent('ScriptSummaryTitle') as TEdit).Text := '架空の評価';
  var Grid := Frame.FindComponent('ScriptSummaryAxes') as TStringGrid;
  Check((Grid.RowCount=6) and (Grid.FixedCols=1) and (goAlwaysShowEditor in Grid.Options) and
    (Frame.FindComponent('ScriptSummaryToolbar').FindComponent('ScriptSummaryAddAxis')=nil),
    'summary provides five fixed rating rows with immediately editable scores');
  for var I := 1 to Length(ScriptSummaryAxisNames) do begin
    Check(Grid.Cells[0,I]=ScriptSummaryAxisNames[I-1],'summary fixed rating name '+I.ToString);
    Grid.Col := 1; Grid.Row := I; Grid.SetFocus; Grid.EditorMode := True;
    var Editor := FindControl(GetFocus) as TCustomEdit;
    Check(Editor<>nil,'score cell opens a native editor '+I.ToString);
    Editor.SelectAll;
    Editor.Perform(WM_CHAR,Ord('4'),0); Editor.Perform(WM_CHAR,Ord('.'),0); Editor.Perform(WM_CHAR,Ord('5'),0);
    Application.ProcessMessages;
    Check((Grid.Cells[1,I]='4.5') and (Editor.Text='4.5') and
      (JS(TJSONObject(JA(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'items')[I-1]),'value')='4.5'),
      'native typing persists a multi-character score without resetting the editor '+I.ToString);
  end;
  Text.SetFocus;
  Capture('summary-fixed-five');
  if FindCmdLineSwitch('check-dpi') then for var Ppi in [96,144,192] do begin
    Main.Scaled := True; Main.ScaleForPPI(Ppi); Main.Scaled := False;
    Main.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(900,Ppi,96)); Main.Update;
    var Left := Frame.FindComponent('ScriptSummaryTextColumn') as TPanel;
    var Right := Frame.FindComponent('ScriptSummaryChartColumn') as TPanel;
    Check((Left.Width>Right.Width) and (Left.Width<Round(Right.Width*1.5)),'summary columns share the width at '+Ppi.ToString+' DPI');
    Check((Text.Height>MulDiv(100,Ppi,96)) and (Grid.Height>MulDiv(120,Ppi,96)),'summary text and chart values remain usable at '+Ppi.ToString+' DPI');
    Check(not Text.ReadOnly and (Text.Text='入力した総評のセリフ。'),'DPI changes preserve editable human summary at '+Ppi.ToString+' DPI');
    Capture('summary-'+Ppi.ToString);
  end;
  if FindCmdLineSwitch('check-dpi') then begin Main.Scaled := True; Main.ScaleForPPI(96); Main.Scaled := False; Main.SetBounds(0,0,1440,900); end;
  TToolButton(Frame.FindComponent('ScriptSummaryToolbar').FindComponent('ScriptSummaryReady')).Click;
  Check((JS(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'status')='complete') and (W.ScriptDraft.Cues.Count=0),'summary confirms text and chart before any role or voice exists');
  Go('closing'); ConfirmClosing;
end;
{$IFDEF CHECK_BACKGROUND}
{$I RigmCommonBackgroundValidation.inc}
{$I RigmSceneNamesValidation.inc}
{$I RigmMovieTextValidation.inc}
{$ENDIF}
{$I RigmScriptThumbnailValidation.inc}
procedure CheckConfirmation;
begin
  var Frame := StageFrame(TRigmScriptConfirmationFrame);
  Check((Frame<>nil) and TWinControl(Frame).Showing,'new confirmation page is visible after closing');
  Check((Frame.FindComponent('ScriptConfirmopening')<>nil) and (Frame.FindComponent('ScriptConfirmbody')<>nil) and
    (Frame.FindComponent('ScriptConfirmsummary')<>nil) and (Frame.FindComponent('ScriptConfirmclosing')<>nil),'confirmation exposes all four script sections');
  var Title := Frame.FindComponent('ScriptConfirmationWorkTitle') as TEdit;
  var CopyButton := Frame.FindComponent('ScriptConfirmationCopyTitle') as TButton;
  Check((Title<>nil) and Title.ReadOnly and (Title.Text=W.ScriptDraft.Title) and
    (CopyButton<>nil) and CopyButton.Enabled,'confirmation exposes a selectable work title and copy action');
  var OriginalResearch := W.ScriptDraft.ScriptWizard.RemovePair('research');
  var Revision := W.ScriptDraft.Revision;
  try
    PrepareScriptResearch(W.ScriptDraft);
    var Research := ScriptResearch(W.ScriptDraft);
    PsdJson.Put(Research,'title','検索時の題名'); PsdJson.Put(Research,'selectedCandidateId','owned');
    JA(Research,'candidates').AddElement(PsdJson.ObjectText(
      '{"id":"owned","name":"確認した正式な作品名","author":"","overview":"","identity":"","details":{},"sources":[]}'));
    TRigmScriptConfirmationFrame(Frame).RefreshState;
    Check((Title.Text='確認した正式な作品名') and (W.ScriptDraft.Revision=Revision),
      'confirmation reads the selected work name without modifying the script');
    Title.SelStart := 2; Title.SelLength := 3;
    TRigmScriptConfirmationFrame(Frame).RefreshState;
    Check((Title.SelStart=2) and (Title.SelLength=3),'confirmation refresh preserves title selection for copying');
  finally
    W.ScriptDraft.ScriptWizard.RemovePair('research').Free;
    if OriginalResearch<>nil then W.ScriptDraft.ScriptWizard.AddPair(OriginalResearch);
    TRigmScriptConfirmationFrame(Frame).RefreshState;
  end;
  for var Id in ['opening','body','summary','closing'] do begin
    var Memo := Frame.FindComponent('ScriptConfirm'+Id) as TMemo;
    Check(Memo.Enabled and not Memo.ReadOnly,'confirmation allows editing '+Id);
    Memo.Text := Memo.Text+' 確認画面で編集。';
  end;
  Check(JS(ScriptSection(W.ScriptDraft,'summary'),'text')=JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'text'),'confirmation summary edit updates both draft and casting source');
  Capture('script-confirmation');
  if FindCmdLineSwitch('check-dpi') then for var Ppi in [144,192] do begin
    Main.Scaled := True; Main.ScaleForPPI(Ppi); Main.Scaled := False;
    Main.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(900,Ppi,96)); Main.Update;
    var Body := Frame.FindComponent('ScriptConfirmbody') as TMemo;
    var Closing := Frame.FindComponent('ScriptConfirmclosing') as TMemo;
    Check((Body.Width>MulDiv(300,Ppi,96)) and (Body.Height>MulDiv(180,Ppi,96)) and
      (Closing.Top+Closing.Height<=Closing.Parent.ClientHeight),'confirmation editors remain inside their panels at '+Ppi.ToString+' DPI');
    Capture('script-confirmation-'+Ppi.ToString);
  end;
  if FindCmdLineSwitch('check-dpi') then begin Main.Scaled := True; Main.ScaleForPPI(96); Main.Scaled := False; Main.SetBounds(0,0,1440,900); end;
  W.SaveScriptDraft(False);
  var Path := W.ScriptDraft.FileName; var Fresh := TRigmWizardWorkspace.Create(nil);
  try Fresh.StartPipe(Main.DataRoot); Fresh.OpenWork(Path);
    Check((Fresh.CurrentScriptStage='script-confirm') and (JS(ScriptSection(Fresh.ScriptDraft,'closing'),'text')=JS(ScriptSection(W.ScriptDraft,'closing'),'text')),'fresh workspace resumes confirmation and edited closing speech');
  finally Fresh.Free; end;
  var Rejected := False; try W.SetScriptStage('casting'); except on E: Exception do Rejected := True; end;
  Check(Rejected,'direct selection cannot bypass current script confirmation');
  Creator.SetActive(False); Go('casting');
  CheckCastingExpressions;
  W.RefreshVoiceCatalog; WaitVoice; Check(W.VoiceCatalogReady,'owned catalog supplies voices without touching the installed engine');
  Check(ScriptDialogueConfirmed(W.ScriptDraft),'entering casting saves the fingerprint of all confirmed sections');
  var Summary := ScriptSummaryCue(W.ScriptDraft);
  Check((Summary<>nil) and (CastingRow(W.ScriptDraft,Summary.Id)<>nil),'summary participates in the same casting pass as other speech');
  Check(W.ScriptDraft.Cues.IndexOf(Summary)<W.ScriptDraft.Cues.Count-1,'summary speech precedes closing speech');
  Check(MovieChartEnabled(W.ScriptDraft.Scene(Summary.Scene).Chart),'summary retains its independent chart scene');
  ValidateScriptSummary(W.ScriptDraft); ValidateScriptCasting(W.ScriptDraft);
  var CueId := Summary.Id; var SceneId := Summary.Scene;
  var State := W.ScriptStatus;
  try Check(not ScriptStageAvailable(State,'subtitles'),'missing voice keeps the next casting stage unavailable'); finally State.Free; end;
  var People := StageFrame(TRigmScriptCastingFrame).FindComponent('ScriptCastingVoiceStyle') as TComboBox;
  People.ItemIndex := 1; People.OnChange(People);
  for var I := 0 to W.ScriptDraft.Cues.Count-4 do W.AssignCasting(W.ScriptDraft.Cues[I].Id,1,True);
  State := W.ScriptStatus;
  try
    Check(JI(JO(JO(State,'wizard'),'casting'),'pending')=3,'three assigned rows reproduce the pending casting confirmation');
    Check(JB(State,'canConfirmCasting') and not JB(State,'canAdvance'),'assigned valid voices permit human casting confirmation without silently confirming rows');
    Check(ScriptStageAvailable(State,'subtitles') and not ScriptStageAvailable(State,'voice'),'only the immediate next stage is available before casting confirmation');
  finally State.Free; end;
  var Stages := Creator.FindComponent('ScriptStages') as TListBox;
  Check(Stages.Items.IndexOf(ScriptStageCaption('subtitles'))>=0,'voice selection immediately displays subtitles in the left stage list');
  Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
  Check(Rejected,'external next still requires explicit human casting confirmation');
  Go('subtitles');
  State := W.ScriptStatus;
  try Check(JI(JO(JO(State,'wizard'),'casting'),'pending')=0,'selecting subtitles confirms every assigned casting row'); finally State.Free; end;
  var Saved := LoadMovie(W.ScriptDraft.FileName);
  try Check(JS(Saved.ScriptWizard,'stage')='subtitles','left stage selection saves the confirmed casting and destination'); finally Saved.Free; end;
  CheckSubtitleDirectEditing;
  Go('voice');
  CheckAccentEditing;
  CheckCommonVoiceSettings;
  var Furthest := JS(W.ScriptDraft.ScriptWizard,'furthestStage');
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'furthestStage','scenes');
  for var Target in ['voice-effects','scene-assignment','scenes','editor'] do begin
    State := W.ScriptStatus;
    try Check(not ScriptStageAvailable(State,Target),'unfinished voice blocks every later stage '+Target); finally State.Free; end;
    Rejected := False; try W.SetScriptStage(Target); except on E: Exception do Rejected := True; end;
    Check(Rejected,'workspace rejects unfinished voice bypass to '+Target);
  end;
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'furthestStage',Furthest);
  var Audio := TRigmPcm.Create;
  try Audio.Rate := 48000; SetLength(Audio.Samples,24000); Audio.Save(TPath.Combine(Root,'owned.wav'));
    for var Cue in W.ScriptDraft.Cues do begin Cue.WaveFile := TPath.Combine(Root,'owned.wav'); Cue.AudioSeconds := Audio.Duration; Cue.AudioKey := W.ScriptDraft.AudioFingerprint(Cue); Cue.VoiceHeardKey := Cue.AudioKey; end;
  finally Audio.Free; end;
  W.ScriptDraft.Changed; W.SaveScriptDraft(False); Creator.SetActive(False); Go('voice-effects');
  CheckScriptVoiceReuse;
  var WavePath := W.ScriptDraft.Cues[0].WaveFile; W.ScriptDraft.Cues[0].WaveFile := TPath.Combine(Root,'missing-audio.wav');
  State := W.ScriptStatus;
  try Check(not JB(State,'canAdvance') and not ScriptStageAvailable(State,'scene-assignment'),'effects cannot advance when an earlier audio file is missing'); finally State.Free; end;
  Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
  Check(Rejected,'external next shares the missing audio prerequisite in effects');
  W.ScriptDraft.Cues[0].WaveFile := WavePath;
  State := W.ScriptStatus;
  try Check(JB(State,'canAdvance') and ScriptStageAvailable(State,'scene-assignment'),'restoring current audio immediately permits the next stage'); finally State.Free; end;
  Creator.SetActive(False); Go('scene-assignment');
  var List := StageFrame(TRigmScriptSceneAssignmentFrame).FindComponent('ScriptSceneAssignmentRows') as TListView;
  Check(List.Items.Count=W.ScriptDraft.Cues.Count-1,'scene assignment UI omits summary speech');
  for var Item in List.Items do Check(Item.SubItems[3]<>CueId,'scene assignment row is ordinary dialogue only');
  var Args := TJSONObject.Create;
  try Args.AddPair('projectId',W.ScriptDraft.Id); AddN(Args,'revision',W.ScriptDraft.Revision); AddN(Args,'limit',1);
    var Response := W.ReadScriptSceneAssignment(Args);
    try Check((JI(Response,'count')=List.Items.Count) and (JI(Response,'nextOffset')=1) and JB(Response,'hasMore'),'filtered assignment pipe count and pagination match the UI'); finally Response.Free; end;
    for var Offset := 0 to List.Items.Count-1 do begin
      PsdJson.Put(Args,'offset',TJSONNumber.Create(Offset)); Response := W.ReadScriptSceneAssignment(Args);
      try Check((JA(Response,'rows').Count=1) and (JS(TJSONObject(JA(Response,'rows')[0]),'cueId')<>CueId),
        'every assignment pipe page omits summary at offset '+Offset.ToString); finally Response.Free; end;
    end;
  finally Args.Free; end;
  var Before := W.ScriptDraft.Cue(CueId).Json.ToJSON; var Chart := W.ScriptDraft.Scene(SceneId).Chart.ToJSON;
  W.SetScriptSceneStart(W.ScriptDraft.Cues[2].Id,True); W.SetScriptSceneStart(W.ScriptDraft.Cues[2].Id,False);
  Check((W.ScriptDraft.Cue(CueId).Json.ToJSON=Before) and (W.ScriptDraft.Scene(SceneId).Chart.ToJSON=Chart),'ordinary scene split and merge preserve summary scene speech and audio');
  var RejectedSummary := False; try W.SetScriptSceneStart(CueId,False); except on E: Exception do RejectedSummary := True; end;
  Check(RejectedSummary,'summary scene cannot merge through the assignment API');
  Capture('scene-assignment-without-summary');
  CheckSceneAssignmentChanges;
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'furthestStage','scenes');
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'scene-assignmentStatus','in-progress');
  State := W.ScriptStatus;
  try Check(ScriptStageAvailable(State,'scenes'),'valid assignment can be confirmed by the left stage selection'); finally State.Free; end;
  Rejected := False; try W.SetScriptStage('scenes'); except on E: Exception do Rejected := True; end;
  Check(Rejected,'direct stage selection cannot bypass saving assignment confirmation');
  Go('scenes');
  for var Scene in W.ScriptDraft.Scenes do begin
    if not MovieChartEnabled(Scene.Chart) then Scene.DisplayMode := 'none';
    RigmScriptScenesModel.SetScriptSceneApproved(W.ScriptDraft,Scene.Id,True);
  end;
  {$IFDEF CHECK_BACKGROUND} CheckSceneNames; CheckCommonBackground; {$ENDIF}
  CheckThumbnail;
  W.ScriptDraft.Changed; W.SaveScriptDraft(False); Creator.SetActive(False); Go('editor');
  Check(Main.CurrentPage=apMovieEdit,'new ordered workflow reaches movie editing');
  var Target := TPath.Combine(Root,'Exports\専用.mp4'); W.ActiveSession.Project.OutputTarget := Target; W.ActiveSession.Project.Changed;
  W.ReturnMovieToScript;
  Check((W.CurrentScriptStage='text') and (W.ScriptDraft.OutputTarget=Target) and (W.ScriptDraft.Cue(CueId)<>nil),'return from movie retains summary and MP4 full path');
  W.SaveScriptDraft(False); W.OpenScriptDraft(W.ScriptDraft.FileName);
  Check(W.ScriptDraft.Cue(CueId).Json.ToJSON=Before,'save and reopen preserve independent summary audio and text');
  var Legacy := W.ScriptDraft.Clone;
  try Legacy.ScriptWizard.RemovePair('flowVersion').Free; PsdJson.Put(Legacy.ScriptWizard,'furthestStage','summary-edit'); UpgradeScriptFlow(Legacy);
    Check(JS(Legacy.ScriptWizard,'furthestStage')='scenes','old reordered furthest-stage ID restores access to existing later data');
  finally Legacy.Free; end;
  Legacy := W.ScriptDraft.Clone;
  try
    var SummaryData := JO(Legacy.ScriptWizard,'summaryData'); var Cast := JO(Legacy.ScriptWizard,'casting');
    var Rows := TJSONArray.Create; var Sections := TJSONArray.Create;
    for var V in JA(Cast,'rows') do if JS(TJSONObject(V),'section')<>'summary' then Rows.AddElement(V.Clone as TJSONObject);
    for var V in JA(Cast,'sections') do if JS(TJSONObject(V),'id')<>'summary' then Sections.AddElement(V.Clone as TJSONObject);
    PsdJson.Put(Cast,'rows',Rows); PsdJson.Put(Cast,'sections',Sections);
    Sections := TJSONArray.Create;
    for var V in JA(JO(Legacy.ScriptWizard,'scriptText'),'sections') do if JS(TJSONObject(V),'id')<>'summary' then Sections.AddElement(V.Clone as TJSONObject);
    PsdJson.Put(JO(Legacy.ScriptWizard,'scriptText'),'sections',Sections);
    PsdJson.Put(SummaryData,'castingRow',TJSONBool.Create(False));
    PsdJson.Put(JO(SummaryData,'draft'),'role',TJSONNumber.Create(1)); PsdJson.Put(JO(SummaryData,'appliedDraft'),'role',TJSONNumber.Create(1));
    Legacy.ScriptWizard.RemovePair('scriptConfirmedFingerprint').Free;
    Legacy.Cues.Move(Legacy.Cues.IndexOf(Legacy.Cue(CueId)),Legacy.Cues.Count-1);
    Legacy.Scenes.Move(Legacy.Scenes.IndexOf(Legacy.Scene(SceneId)),Legacy.Scenes.Count-1);
    PsdJson.Put(Cast,'selectedCue',Legacy.Cues[0].Id); PsdJson.Put(Cast,'sourceFingerprint',ScriptFingerprint(Legacy));
    RequestScriptCasting(Legacy); ValidateScriptCasting(Legacy); ValidateScriptSummary(Legacy);
    Check(ScriptDialogueConfirmed(Legacy),'old materialized summary and confirmed casting remain readable');
    Sections.AddElement(PsdJson.ObjectText('{"id":"summary","scope":"episode","text":""}'));
    PsdJson.Put(ScriptSection(Legacy,'summary'),'text',JS(JO(SummaryData,'draft'),'text'));
    PrepareScriptCasting(Legacy); ValidateScriptSummary(Legacy);
    Check(Legacy.Cue(CueId).Json.ToJSON=Before,'old separately appended summary preserves its ID and audio when moved before closing');
    Check((CastingRow(Legacy,CueId)<>nil) and (Legacy.Cues.IndexOf(Legacy.Cue(CueId))=Legacy.Cues.Count-2),'old summary upgrades to casting without duplicating speech');
    PrepareScriptCasting(Legacy);
    Check(Legacy.Cue(CueId).Json.ToJSON=Before,'reconfirming unchanged dialogue preserves summary audio and independent subtitle');
    var Draft := JO(SummaryData,'draft').Clone as TJSONObject;
    try PsdJson.Put(Draft,'reading','変更した総評の読み。'); SetScriptSummaryDraft(Legacy,Draft); finally Draft.Free; end;
    PrepareScriptCasting(Legacy);
    Check((Legacy.Cue(CueId).VoiceReading='変更した総評の読み。') and not Legacy.AudioReady(Legacy.Cue(CueId)),
      'changed summary reading updates the cue and requires fresh audio');
  finally Legacy.Free; end;
  Go('script-confirm'); W.SetScriptText('body',JS(ScriptSection(W.ScriptDraft,'body'),'text')+' 追記。');
  Check(not ScriptDialogueConfirmed(W.ScriptDraft),'editing confirmed speech invalidates its confirmation fingerprint');
  Rejected := False; try W.SetScriptStage('casting'); except on E: Exception do Rejected := True; end;
  Check(Rejected,'returning directly to casting cannot reuse an obsolete confirmation');
end;
{$I RigmSummaryLinesValidation.inc}
procedure CheckNone;
begin
  StartScript; var Choice := Creator.FindComponent('ScriptSummaryChoice') as TRadioGroup;
  Choice.ItemIndex := 0; Choice.OnClick(Choice); Go('closing'); ConfirmClosing;
  var Frame := StageFrame(TRigmScriptConfirmationFrame);
  var Memo := Frame.FindComponent('ScriptConfirmsummary') as TMemo;
  Check(Memo.Enabled and not Memo.ReadOnly,'summary-none confirmation still accepts summary speech input');
  Creator.SetActive(False); Go('casting');
  Check(ScriptSummaryCue(W.ScriptDraft)=nil,'summary-none casting creates no extra dialogue or chart scene');
  for var V in JA(JO(W.ScriptDraft.ScriptWizard,'casting'),'rows') do Check(JS(TJSONObject(V),'section')<>'summary','summary-none casting contains ordinary speech only');
  Go('script-confirm'); Memo.SetFocus;
  var Text := '総評の一行目。'+#13#10+'総評の二行目。'+#13#10+'総評の三行目。'+#13#10+'総評の四行目。'+#13#10+'総評の五行目。'+#13#10+'総評の六行目。';
  Memo.Perform(EM_REPLACESEL,1,LPARAM(PChar(Text)));
  Check((Memo.Text=Text) and (JS(W.ScriptDraft.ScriptWizard,'summaryChoice')='none'),'native memo input preserves the saved summary-none choice');
  Check(JS(ScriptSection(W.ScriptDraft,'summary'),'text')=Text,'native summary input updates the shared script section');
  var State := W.ScriptStatus;
  try
    var Seen := False; for var Stage in ScriptVisibleStages(State) do Seen := Seen or (Stage='summary-edit');
    Check(not Seen and JB(State,'canAdvance') and (JS(State,'advanceBlockedReason')=''),
      'summary-none input keeps the optional chart hidden and permits casting');
    Check(not (Frame.FindComponent('ScriptConfirmationRepairSummary') as TButton).Visible and
      (Pos('総評なし',(Frame.FindComponent('ScriptConfirmLabelsummary') as TLabel).Caption)>0),
      'confirmation marks the unused summary draft without asking for chart scores');
  finally State.Free; end;
  W.SaveScriptDraft(False); W.OpenScriptDraft(W.ScriptDraft.FileName); Go('script-confirm');
  Check((Memo.Text=Text) and (JS(W.ScriptDraft.ScriptWizard,'summaryChoice')='none'),
    'saving and reopening retains both the summary-none choice and typed draft');
  Capture('script-confirmation-summary-none'); Go('casting');
  Check(ScriptDialogueConfirmed(W.ScriptDraft) and (ScriptSummaryCue(W.ScriptDraft)=nil),
    'summary-none with a stored draft advances to casting without a chart');
  Go('summary'); Choice.ItemIndex := 1; Choice.OnClick(Choice);
  Check(JS(W.ScriptDraft.ScriptWizard,'summaryChoice')='yes','only an explicit choice enables the stored summary draft');
  Go('closing'); Go('script-confirm'); State := W.ScriptStatus;
  try
    Check(not JB(State,'canAdvance') and (JS(State,'advanceBlockedReason')<>''),'explicit summary-yes still requires human chart values before casting');
    Check((Pos('第8段階',JS(State,'advanceBlockedReason'))>0) and
      (Pos('1行目',JS(State,'advanceBlockedReason'))>0) and (Pos('ストーリー',JS(State,'advanceBlockedReason'))>0) and (Pos('点数',JS(State,'advanceBlockedReason'))>0),
      'missing summary chart identifies its input stage, first row and required fields');
    Check((Frame.FindComponent('ScriptConfirmationBlockedReason') as TLabel).Caption=JS(State,'advanceBlockedReason'),
      'confirmation page shows the blocking reason beside its repair action');
  finally State.Free; end;
  W.SaveScriptDraft(False); W.OpenScriptDraft(W.ScriptDraft.FileName); Go('script-confirm');
  Check((Memo.Text=Text) and Memo.Enabled and not Memo.ReadOnly,'summary speech remains editable after save and reopen');
  Capture('script-confirmation-blocked');
  var Repair := Frame.FindComponent('ScriptConfirmationRepairSummary') as TButton;
  Check(Repair.Visible and Repair.Enabled,'missing chart offers a labeled action to return to its input page');
  var Before := JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON;
  var SummaryBefore := JO(W.ScriptDraft.ScriptWizard,'summaryData').ToJSON;
  var Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
  Check(Rejected and (W.CurrentScriptStage='script-confirm'),'missing chart still blocks casting without inventing evaluation values');
  Repair.Click;
  Check((W.CurrentScriptStage='summary-edit') and (JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON=Before) and
    (JO(W.ScriptDraft.ScriptWizard,'summaryData').ToJSON=SummaryBefore),'repair action preserves all script sections and chart draft');
  var SummaryFrame := StageFrame(TRigmScriptSummaryFrame);
  var Grid := SummaryFrame.FindComponent('ScriptSummaryAxes') as TStringGrid;
  Check((Pos('固定5項目',Grid.Cells[0,0])>0) and (Pos('必須',Grid.Cells[1,0])>0) and
    (Pos('ストーリー',(SummaryFrame.FindComponent('ScriptSummaryGuide') as TLabel).Caption)>0),
    'chart input fixes the five labels and identifies the missing score');
  for var I := 1 to Length(ScriptSummaryAxisNames) do begin
    Grid.Cells[1,I] := I.ToString; Grid.OnSetEditText(Grid,1,I,Grid.Cells[1,I]);
  end;
  Grid.Cells[1,2] := '未入力'; Grid.OnSetEditText(Grid,1,2,Grid.Cells[1,2]);
  var D := JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'); var DraftBefore := D.ToJSON;
  var Reason := ScriptSummaryDraftReason(D);
  Check((Pos('2行目',Reason)>0) and (Pos('キャラクター',Reason)>0) and (Pos('数値',Reason)>0) and (D.ToJSON=DraftBefore),
    'invalid score identifies the row and item without changing the draft');
  Grid.Cells[1,2] := '2'; Grid.OnSetEditText(Grid,1,2,Grid.Cells[1,2]);
  W.CompleteScriptSummary; Go('script-confirm');
  Check(not Repair.Visible and ((Frame.FindComponent('ScriptConfirmationBlockedReason') as TLabel).Caption=''),
    'valid chart clears the blocking reason and repair action');
  W.SaveScriptDraft(False); W.OpenScriptDraft(W.ScriptDraft.FileName); Go('script-confirm');
  Go('casting');
  Check(ScriptDialogueConfirmed(W.ScriptDraft) and (ScriptSummaryCue(W.ScriptDraft)<>nil) and
    (ScriptSummaryCue(W.ScriptDraft).Text='総評の一行目。'),'completed chart saves, reopens and advances to casting with the entered summary');
  CheckSummaryLines;
end;
procedure CheckStageGates;
  function Visible(State: TJSONObject; const Stage: string): Boolean;
  begin Result := False; for var Id in ScriptVisibleStages(State) do if Id=Stage then Exit(True); end;
begin
  var State := PsdJson.ObjectText('{"hasProject":true,"canAdvance":false,"scriptConfirmed":true,"castingReady":true,"subtitlesReady":true,"voiceReady":false,"assignmentReady":true,"scenesReady":true,"wizard":{"stage":"voice","furthestStage":"scenes","summaryChoice":"yes"}}');
  try
    for var Target in ['voice-effects','scene-assignment','scenes','editor'] do
      Check(not ScriptStageAvailable(State,Target) and not Visible(State,Target),'incomplete voice hides and blocks reached future stage '+Target);
    AddB(State,'canConfirmVoice',True);
    Check(ScriptStageAvailable(State,'voice-effects') and Visible(State,'voice-effects'),'heard voice reveals the immediate confirmation destination');
    Check(not ScriptStageAvailable(State,'scene-assignment'),'pending voice confirmation cannot skip effects');
    PsdJson.Put(State,'canAdvance',TJSONBool.Create(True)); PsdJson.Put(State,'voiceReady',TJSONBool.Create(True));
    Check(ScriptStageAvailable(State,'voice-effects') and ScriptStageAvailable(State,'scene-assignment') and ScriptStageAvailable(State,'scenes'),'completed prerequisites restore every valid reached destination');
    PsdJson.Put(JO(State,'wizard'),'stage','voice-effects'); PsdJson.Put(State,'voiceReady',TJSONBool.Create(False));
    Check(not ScriptStageAvailable(State,'scene-assignment') and not ScriptStageAvailable(State,'scenes'),'missing earlier audio blocks all forward moves from effects');
    Check(ScriptStageAvailable(State,'voice') and Visible(State,'voice'),'earlier voice stage remains reachable for repair');
    PsdJson.Put(State,'voiceReady',TJSONBool.Create(True)); PsdJson.Put(State,'subtitlesReady',TJSONBool.Create(False));
    Check(not ScriptStageAvailable(State,'scene-assignment'),'effects cannot bypass incomplete earlier subtitles');
    PsdJson.Put(State,'subtitlesReady',TJSONBool.Create(True)); PsdJson.Put(State,'castingReady',TJSONBool.Create(False));
    Check(not ScriptStageAvailable(State,'scene-assignment'),'effects cannot bypass incomplete earlier casting');
    PsdJson.Put(State,'castingReady',TJSONBool.Create(True)); PsdJson.Put(State,'scriptConfirmed',TJSONBool.Create(False));
    Check(not ScriptStageAvailable(State,'scene-assignment'),'effects cannot bypass changed dialogue confirmation');
    PsdJson.Put(State,'scriptConfirmed',TJSONBool.Create(True)); PsdJson.Put(State,'assignmentReady',TJSONBool.Create(False));
    Check(ScriptStageAvailable(State,'scene-assignment') and not ScriptStageAvailable(State,'scenes'),'incomplete assignment offers its editor and blocks the later image stage');
    PsdJson.Put(JO(State,'wizard'),'stage','scenes'); PsdJson.Put(State,'assignmentReady',TJSONBool.Create(True)); PsdJson.Put(State,'scenesReady',TJSONBool.Create(False));
    Check(not ScriptStageAvailable(State,'editor') and not Visible(State,'editor'),'incomplete scenes hide movie editing');
    PsdJson.Put(State,'scenesReady',TJSONBool.Create(True));
    Check(ScriptStageAvailable(State,'editor') and Visible(State,'editor'),'completed scenes reveal movie editing');
  finally State.Free; end;
end;
procedure Run;
begin
  Root := ParamStr(1); if (Root='') or DirectoryExists(TPath.Combine(Root,'OwnedData')) then raise Exception.Create('Fresh owned root required');
  ForceDirectories(TPath.Combine(Root,'OwnedData\RIGM'));
  var Doc := TRigmDocument.Create;
  try PopulateRigmSample(Doc); AddExpressionFixture(Doc); Doc.Usable := True; SaveRigm(Doc,TPath.Combine(Root,'OwnedData\RIGM\fixture.rigm')); finally Doc.Free; end;
  Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace; Main.ScaleForPPI(96); Main.SetBounds(0,0,1440,900);
  Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update;
  Check((ScriptStageIndex('review')=5) and (ScriptStageIndex('summary')=6) and (ScriptStageIndex('script-confirm')=9) and (ScriptStageIndex('casting')=10),'stable IDs expose the requested stage order');
  {$IFDEF CHECK_BACKGROUND} CheckMovieText; {$ENDIF}
  if FindCmdLineSwitch('check-summary-lines') then CheckNone
  else begin CheckStageGates; StartScript; CheckSummary; CheckConfirmation; CheckNone; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  if Root<>'' then begin var Report := TJSONObject.Create; try Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('error',Error); TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end; end;
  Main.Free; Checks.Free;
end.
