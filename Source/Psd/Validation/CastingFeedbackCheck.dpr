program CastingFeedbackCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmWizardWorkspace, RigmScriptCreatorFrame, RigmScriptCastingFrame,
  RigmScriptManagerFrame, RigmVoiceConnection, RigmPageNavigation, RigmScriptNavigationProbe,
  RigmScriptCastingModel, RigmMovieModel, RigmModel, RigmSample, RigmStorage, RigmJson, PsdJson;
{$R *.res}
type
  TObserver = class
    Workspace: TRigmWizardWorkspace;
    Casting: TRigmScriptCastingFrame;
    Loading: TPanel;
    Changed: TNotifyEvent;
    Navigate: TRigmNavigateEvent;
    LoadingProc: TWndMethod;
    Ticks,SelectionFeedback,LoadingPaints: Integer;
    LoadingSeen,LoadingPainted: Boolean;
    procedure Tick(Sender: TObject);
    procedure ScriptChanged(Sender: TObject);
    procedure Navigation(Sender: TObject; Page: TRigmAppPage; const Path: string);
    procedure PaintLoading(var Message: TMessage);
  end;
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Creator: TRigmScriptCreatorFrame;
  Casting: TRigmScriptCastingFrame; Observer: TObserver; Timer: TTimer;
  Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
procedure TObserver.Tick(Sender: TObject);
begin Inc(Ticks); end;
procedure TObserver.ScriptChanged(Sender: TObject);
begin
  if Assigned(Changed) then Changed(Sender);
  if TPanel(Casting.FindComponent('ScriptCastingVoiceWait')).Visible and
    (Pos('反映しています',TLabel(Casting.FindComponent('ScriptCastingVoiceWaitText')).Caption)>0) then Inc(SelectionFeedback);
end;
procedure Capture(const Name: string); forward;
procedure TObserver.Navigation(Sender: TObject; Page: TRigmAppPage; const Path: string);
begin
  LoadingSeen := Loading.Showing;
  LoadingPainted := LoadingSeen and (LoadingPaints>0) and IsWindowVisible(Loading.Handle) and not GetUpdateRect(Loading.Handle,nil,False);
  Capture('work-loading');
  if Assigned(Navigate) then Navigate(Sender,Page,Path);
end;
procedure TObserver.PaintLoading(var Message: TMessage);
begin if (Message.Msg=WM_PAINT) and Loading.Showing then Inc(LoadingPaints); LoadingProc(Message); end;
procedure Capture(const Name: string);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try Bitmap.SetSize(Main.ClientWidth,Main.ClientHeight); Main.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure WaitCatalog(Ready: Boolean);
begin
  var Deadline := GetTickCount64+15000;
  repeat
    Application.ProcessMessages; Sleep(10);
    if not W.VoiceBusy and (W.VoiceCatalogReady=Ready) then Break;
    if GetTickCount64>Deadline then raise Exception.Create('Catalog wait timed out');
  until False;
  var Finish := GetTickCount64+400;
  repeat Application.ProcessMessages; Sleep(10); until GetTickCount64>=Finish;
end;
procedure CheckLabels(Ppi: Integer);
begin
  Main.ScaleForPPI(Ppi); Main.SetBounds(0,0,MulDiv(1360,Ppi,96),MulDiv(840,Ppi,96)); Application.ProcessMessages;
  var Actor := Casting.FindComponent('ScriptCastingVoiceActor') as TLabel;
  var Emotion := Casting.FindComponent('ScriptCastingEmotionLabel') as TLabel;
  var Person := Casting.FindComponent('ScriptCastingVoiceStyle') as TComboBox;
  var State := Casting.FindComponent('ScriptCastingVoiceState') as TComboBox;
  Check((Actor.Width=MulDiv(220,Ppi,96)) and (Person.Left>=Actor.Left+Actor.Width),'person caption has reserved width at '+Ppi.ToString+' DPI');
  Check((Emotion.Width=MulDiv(220,Ppi,96)) and (State.Left>=Emotion.Left+Emotion.Width),'emotion caption has reserved width at '+Ppi.ToString+' DPI');
  Check((Person.Width>MulDiv(200,Ppi,96)) and (State.Width>MulDiv(200,Ppi,96)),'selectors remain usable at '+Ppi.ToString+' DPI');
  Check(Actor.Visible and Emotion.Visible and Actor.Parent.Showing and Emotion.Parent.Showing,'both captions are visible at '+Ppi.ToString+' DPI');
  Check(Pos('声（人物）',Actor.Caption)=1,'person caption remains identifiable for a long character name at '+Ppi.ToString+' DPI');
  Capture('ready-'+Ppi.ToString);
end;
procedure Run;
begin
  Root := ParamStr(1); if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh root required');
  var DataRoot := TPath.Combine(Root,'OwnedData'); ForceDirectories(TPath.Combine(DataRoot,'RIGM'));
  var Doc := TRigmDocument.Create;
  try PopulateRigmSample(Doc); Doc.Usable := True; SaveRigm(Doc,TPath.Combine(DataRoot,'RIGM\fixture.rigm'));
  finally Doc.Free; end;
  Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace; Main.ScaleForPPI(96);
  Main.SetBounds(0,0,1360,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update; W.NewScriptDraft;
  W.ScriptDraft.EngineUrl := ParamStr(2); Main.NavigateTo(apScriptCreate);
  Creator := Main.PageInstance(apScriptCreate) as TRigmScriptCreatorFrame;
  W.SetScriptTitle('配役の待機表示の確認'); W.NextScriptDraft;
  var Deadline := GetTickCount64+10000; var Found := False;
  repeat
    Application.ProcessMessages;
    for var Item in (Creator.FindComponent('ScriptCharacters') as TListView).Items do
      if JB(TJSONObject(Item.Data),'readyForScript') then begin Item.Checked := True; Found := True; end;
    if Found then Break; Sleep(10);
    if GetTickCount64>Deadline then raise Exception.Create('Owned fixture character was not ready');
  until False;
  W.NextScriptDraft; W.NextScriptDraft; W.NextScriptDraft;
  W.SetScriptText('body','確認用の一行です。'+#13#10+'二行目の声を確認します。');
  W.NextScriptDraft; ClickScriptStage(Creator,'casting');
  Check(W.CurrentScriptStage='casting','optional research still opens casting from the list');
  for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptCastingFrame then Casting := TRigmScriptCastingFrame(Creator.Components[I]);
  var Connection: TRigmVoiceConnection := nil;
  for var I := 0 to Casting.ComponentCount-1 do if Casting.Components[I] is TRigmVoiceConnection then Connection := TRigmVoiceConnection(Casting.Components[I]);
  var WaitPanel := Casting.FindComponent('ScriptCastingVoiceWait') as TPanel;
  var Choices := Casting.FindComponent('ScriptCastingVoiceChoices') as TPanel;
  var WaitText := Casting.FindComponent('ScriptCastingVoiceWaitText') as TLabel;
  var Progress := Casting.FindComponent('ScriptCastingVoiceProgress') as TProgressBar;
  Check(WaitPanel.Showing and not Choices.Visible,'connection preparation replaces the selectors immediately');
  Check(not WaitPanel.ShowCaption,'processing page does not display an internal control name');
  Observer := TObserver.Create; Observer.Workspace := W; Observer.Casting := Casting;
  Timer := TTimer.Create(nil); Timer.Interval := 50; Timer.OnTimer := Observer.Tick;
  Deadline := GetTickCount64+5000;
  repeat
    Application.ProcessMessages; Sleep(10);
    if Pos('人物・感情一覧',WaitText.Caption)>0 then Break;
    if GetTickCount64>Deadline then raise Exception.Create('Speaker phase was not displayed');
  until False;
  Check(W.VoiceBusy and WaitPanel.Showing and not Choices.Visible,'delayed speaker request keeps the processing page visible');
  Check(Progress.Style=pbstMarquee,'connection wait uses an animated indeterminate progress bar');
  var InitialText := WaitText.Caption; var InitialTicks := Observer.Ticks; Capture('loading-speakers');
  var UntilTick := GetTickCount64+1200;
  repeat Application.ProcessMessages; Sleep(10); until GetTickCount64>=UntilTick;
  Check(W.VoiceBusy and (Observer.Ticks-InitialTicks>=15),'UI timers continue during delayed network response');
  Check(WaitText.Caption<>InitialText,'elapsed waiting time updates while the network request is active');
  WaitCatalog(True); Check(Choices.Showing and not WaitPanel.Visible,'successful connection restores the selectors');
  for var Ppi in [96,144,192] do CheckLabels(Ppi);
  Main.ScaleForPPI(96); Main.SetBounds(0,0,1360,840);
  Observer.Changed := W.OnScriptChanged; W.OnScriptChanged := Observer.ScriptChanged;
  var Person := Casting.FindComponent('ScriptCastingVoiceStyle') as TComboBox;
  Person.ItemIndex := 1; Person.OnChange(Person);
  Check(Observer.SelectionFeedback>0,'person selection displays its work before restoring the selectors');
  Check(W.ScriptDraft.Speaker(JS(CastingRole(W.ScriptDraft,1),'speakerId')).VoiceUuid='fixture-voice','person selection uses the actual fixture catalog UUID');
  var Before := Observer.SelectionFeedback; var Emotion := Casting.FindComponent('ScriptCastingVoiceState') as TComboBox;
  Emotion.ItemIndex := 1; Emotion.OnChange(Emotion);
  Check(Observer.SelectionFeedback>Before,'emotion selection displays its work before restoring the selectors');
  Check(Choices.Showing and not WaitPanel.Visible,'selection completion restores the controls');
  W.OnScriptChanged := Observer.Changed;
  W.RefreshVoiceCatalog; Deadline := GetTickCount64+5000;
  repeat
    Application.ProcessMessages; Sleep(10);
    if FileExists(ParamStr(3)) and (Trim(TFile.ReadAllText(ParamStr(3)))='2') then Break;
    if GetTickCount64>Deadline then raise Exception.Create('Second fixture request was not received');
  until False;
  W.CancelVoice; WaitCatalog(False);
  Check(not WaitPanel.Visible and Choices.Showing,'cancelling connection work dismisses the waiting page');
  Check((Casting.FindComponent('ScriptCastingLocateEngine') as TButton).Visible,'cancelled connection exposes reconnection control');
  W.RefreshVoiceCatalog; WaitCatalog(False);
  Check(not WaitPanel.Visible and Choices.Showing,'failed speaker request restores the controls');
  Check(Pos('VOICEVOX接続',TLabel(Casting.FindComponent('ScriptCastingVoiceStatus')).Caption)>0,'connection failure displays its reason');
  Capture('connection-failed'); Connection.Prepare; WaitCatalog(True);
  Check(Choices.Showing and not WaitPanel.Visible,'retry recovers from a failed connection');
  W.SaveScriptDraft; var SavedPath := W.ScriptDraft.FileName; var SavedHash := THashSHA2.GetHashStringFromFile(SavedPath);
  Main.NavigateTo(apScripts); var Manager := Main.PageInstance(apScripts) as TRigmScriptManagerFrame;
  var List := Manager.FindComponent('ScriptLibrary') as TListView;
  Observer.Loading := Manager.FindComponent('ScriptLibraryLoading') as TPanel;
  Observer.LoadingProc := Observer.Loading.WindowProc; Observer.Loading.WindowProc := Observer.PaintLoading;
  Observer.Navigate := W.OnNavigate; W.OnNavigate := Observer.Navigation;
  List.OnDblClick(List);
  Check(Observer.LoadingSeen and Observer.LoadingPainted,'opening work paints the loading page before navigating to the editor');
  Check((Main.CurrentPage=apScriptCreate) and (W.CurrentScriptStage='casting'),'opening work restores the saved stage');
  Check(not Observer.Loading.Visible,'successful open removes the loading page');
  Main.NavigateTo(apScripts); var Cursor := Screen.Cursor;
  List.Selected.SubItems[3] := TPath.Combine(Root,'missing.rigmovie'); List.OnDblClick(List);
  Check(not Observer.Loading.Visible and List.Visible and (Screen.Cursor=Cursor),'failed open restores list and cursor');
  Check(THashSHA2.GetHashStringFromFile(SavedPath)=SavedHash,'failed open preserves the current saved project');
  Check(W.CurrentScriptStage='casting','failed open retains the current script');
  W.OnNavigate := Observer.Navigate; Observer.Loading.WindowProc := Observer.LoadingProc;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  Timer.Free;
  if Root<>'' then begin
    var Report := TJSONObject.Create;
    try Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  end;
  Main.Free; Observer.Free; Checks.Free;
end.
