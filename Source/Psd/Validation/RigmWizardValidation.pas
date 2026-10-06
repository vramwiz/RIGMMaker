unit RigmWizardValidation;
interface
uses RigmWizardMainForm;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
procedure VerifyUiResponsiveness(Main: TRigmWizardMainForm; const ResultPath: string);
procedure VerifyCharacterCreate(Main: TRigmWizardMainForm; const ResultPath: string);
procedure VerifyScriptTitle(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptCharacters(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyThumbnailCache(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptLayout(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptPlacement(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptText(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptReview(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptSubtitles(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
procedure VerifyScriptCasting(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math, System.Types, System.DateUtils, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, System.UITypes,
  RigmPageNavigation, PsdStudioFrame, PsdJson, RigmCharacterEditPage,
  RigmScriptCreatorFrame, RigmMovieWorkspaceFrame, RigmJson, Winapi.Windows, Winapi.Messages,
  PsdPreviewControl, PsdSettingsPanel, PsdMotionReferenceForm, Vcl.Graphics, Vcl.Imaging.pngimage,
  PsdSession, PsdProduction, RigmCharacterCatalog, RigmCharacterManagerFrame, PsdWorkspace,
  PsdPackage, RigmLegacyEditorFrame, Winapi.ShellAPI, Winapi.ShlObj, System.StrUtils, ArtLayerList, RigmModel, ArtDocument,
  RigmWizardWorkspace, RigmMovieModel, RigmScriptManagerFrame, RigmThumbnailCache, RigmScriptLayoutFrame, RigmMovieLayout,
  RigmScriptPlacementFrame, RigmScriptPlacementModel, RigmScriptTextFrame, RigmScriptTextModel,
  RigmMovieComposition, RigmMovieCompositionCommands, RigmMovieCompositor, RigmScriptReviewFrame, RigmScriptReviewModel, RigmScriptCastingFrame, RigmScriptCastingModel, RigmScriptSubtitleFrame, RigmScriptSubtitleModel;
type
  TReturnDialogAnswer = class
  public
    Answer: Integer; Seen: Boolean;
    procedure Tick(Sender: TObject);
  end;
  TThumbnailHeartbeat = class
  public
    Count: Integer; Last,MaxGap: UInt64;
    procedure Tick(Sender: TObject);
  end;
  TLegacyLoadingProbe = class
  public
    Host: TRigmCharacterEditPage; Forward: TRigmLegacyCharacterLoadEvent;
    Starts,Finishes: Integer; FramesBefore: UInt64; OnVisible: TProc;
    procedure LoadingChanged(Sender: TObject; const Path: string; Loading: Boolean);
  end;
  // 実際の読込通知をホストへ転送し、その前後の可視性と初回フレームを検査する。
  TCharacterLoadingProbe = class
  public
    Host: TRigmCharacterEditPage; Editor: TPsdStudioFrame;
    Forward: TPsdCharacterLoadEvent; OnVisible: TProc;
    ExpectFrame: Boolean; FramesBefore: Double; Starts,Finishes: Integer;
    procedure LoadingChanged(Sender: TObject; const Path: string; Loading: Boolean);
  end;
procedure TThumbnailHeartbeat.Tick(Sender: TObject);
begin
  var Current := GetTickCount64;
  if Last<>0 then MaxGap := Max(MaxGap,Current-Last);
  Last := Current; Inc(Count);
end;
procedure WaitThumbnailLibrary(W: TRigmWizardWorkspace);
begin
  var Deadline := GetTickCount64+20000;
  repeat
    var LibraryState := W.ScriptCharacterLibrary(False); var Loading := False;
    try for var V in JA(LibraryState,'characters') do Loading := Loading or JB(TJSONObject(V),'loading');
    finally LibraryState.Free; end;
    Application.ProcessMessages; if not Loading then Exit; Sleep(5);
  until GetTickCount64>Deadline;
  raise Exception.Create('Thumbnail completion timeout');
end;
procedure TReturnDialogAnswer.Tick(Sender: TObject);
begin
  // この所有検証プロセスのモーダルダイアログだけを操作する。
  for var Index := 0 to Screen.FormCount-1 do begin
    var Form := Screen.Forms[Index];
    if not (fsModal in Form.FormState) then Continue;
    for var I := 0 to Form.ComponentCount-1 do
      if (Form.Components[I] is TButton) and (TButton(Form.Components[I]).ModalResult=Answer) then begin
        Seen := True; TTimer(Sender).Enabled := False; TButton(Form.Components[I]).Click; Exit;
      end;
  end;
end;
procedure ClickReturn(Editor: TPsdStudioFrame; Answer: Integer);
begin
  var Timer := TTimer.Create(nil); var Probe := TReturnDialogAnswer.Create;
  try
    Probe.Answer := Answer; Timer.Interval := 50; Timer.OnTimer := Probe.Tick;
    TToolButton(TToolBar(Editor.FindComponent('PsdStageToolbar')).FindComponent('PsdReturnToManagement')).Click;
    if not Probe.Seen then raise Exception.Create('Expected return confirmation was not shown');
  finally Timer.Free; Probe.Free; end;
end;
function PreviewDigest(const Pixels: TBytes): string;
begin var Hash := THashSHA2.Create; Hash.Update(Pixels); Result := Hash.HashAsString; end;
procedure TLegacyLoadingProbe.LoadingChanged(Sender: TObject; const Path: string; Loading: Boolean);
begin
  var Panel := TRigmCharacterLoadingPanel(Host.FindComponent('CharacterLoading'));
  if Loading then begin
    Forward(Sender,Path,True); Inc(Starts); FramesBefore := Host.LegacyEditor.PreviewRenderCount;
    if not Panel.Showing or Host.LegacyEditor.Visible or not Host.LoadPaintedBeforeActivation then
      raise Exception.Create(Format('RIGM preparation must be painted while editor remains hidden (panel=%d, editor=%d, painted=%d)',
        [Ord(Panel.Showing),Ord(Host.LegacyEditor.Visible),Ord(Host.LoadPaintedBeforeActivation)]));
    if Assigned(OnVisible) then OnVisible();
  end else begin
    if not Panel.Showing or Host.LegacyEditor.Visible or (Host.LegacyEditor.PreviewRenderCount<=FramesBefore) then
      raise Exception.Create('RIGM preview must be ready before preparation ends');
    Inc(Finishes); Forward(Sender,Path,False);
  end;
end;
procedure TCharacterLoadingProbe.LoadingChanged(Sender: TObject; const Path: string; Loading: Boolean);
begin
  var Panel := TRigmCharacterLoadingPanel(Host.FindComponent('CharacterLoading'));
  if Loading then begin
    Forward(Sender,Path,True); Inc(Starts);
    if not Panel.Showing or not Host.LoadPaintedBeforeActivation or Editor.Visible or (Panel.Caption<>'') or Panel.ShowCaption then
      raise Exception.Create('PSD loading panel must be painted with the editor hidden');
    var D := Editor.Diagnostics;
    try FramesBefore := N(D,'previewFrames'); finally D.Free; end;
    if Assigned(OnVisible) then OnVisible();
    D := Editor.Diagnostics;
    try if N(D,'previewFrames')<>FramesBefore then raise Exception.Create('Animation continued behind loading panel'); finally D.Free; end;
  end else begin
    if not Panel.Showing or Editor.Visible then raise Exception.Create('Editor became visible before loading completed');
    var D := Editor.Diagnostics;
    try
      if ExpectFrame and (N(D,'previewFrames')<=FramesBefore) then raise Exception.Create('First frame was not ready before editor display');
      if not ExpectFrame and (N(D,'previewFrames')<>FramesBefore) then raise Exception.Create('Failed load changed the preview');
    finally D.Free; end;
    Forward(Sender,Path,False); Inc(Finishes);
    if Panel.Visible or not Editor.Showing then raise Exception.Create('Loading panel did not return to the editor');
  end;
end;
function VerifyCharacterLoading(Host: TRigmCharacterEditPage; CaptureLoading: TProc): Integer;
  procedure Run(const Command,Path: string; Discard: Boolean = False);
  begin
    var Status := Host.PsdEditor.Session.Status; var A := TJSONObject.Create;
    try
      A.AddPair('sessionId',S(Status,'sessionId')); A.AddPair('revision',S(Status,'revision'));
      A.AddPair('path',Path); A.AddPair('discardChanges',TJSONBool.Create(Discard));
      var R := Host.PsdEditor.ExternalCommand(Command,A); R.Free;
    finally A.Free; Status.Free; end;
  end;
begin
  var Editor := Host.PsdEditor; var Probe := TCharacterLoadingProbe.Create;
  var SavedPath := Editor.Session.SavedPath; var SavedId := Editor.Session.Character.Id;
  var SavedHash := THashSHA2.GetHashStringFromFile(SavedPath);
  Probe.Host := Host; Probe.Editor := Editor; Probe.Forward := Editor.OnCharacterLoad;
  Editor.OnCharacterLoad := Probe.LoadingChanged;
  try
    Probe.ExpectFrame := True; Run('open',SavedPath);
    var InvalidPath := Editor.Session.Workspace.Resolve('Exchange\invalid.psd',False);
    ForceDirectories(ExtractFileDir(InvalidPath)); TFile.WriteAllText(InvalidPath,'invalid PSD',TEncoding.ASCII);
    Probe.ExpectFrame := False; var Rejected := False;
    try Run('import-psd',InvalidPath); except on E: Exception do Rejected := True; end;
    if not Rejected or (Editor.Session.Character.Id<>SavedId) or (Editor.Session.SavedPath<>SavedPath) or Editor.Session.Dirty then
      raise Exception.Create('Failed raw PSD import did not preserve the current character');
    Probe.ExpectFrame := True; Probe.OnVisible := CaptureLoading;
    Run('import-psd','Characters\fixture.psd'); Probe.OnVisible := nil;
    if (Editor.Session.Character.Policy<>'external') or not Editor.Session.Dirty then raise Exception.Create('Raw PSD fixture did not import');
    Run('open',SavedPath,True);
    if (Probe.Starts<>4) or (Probe.Finishes<>4) or (Editor.Session.Character.Id<>SavedId) or Editor.Session.Dirty or
      (THashSHA2.GetHashStringFromFile(SavedPath)<>SavedHash) then raise Exception.Create('Loading lifecycle or fixture preservation failed');
    Result := Probe.Finishes;
  finally Editor.OnCharacterLoad := Probe.Forward; Probe.Free; end;
end;
function VerifyPreviewLayout(Main: TRigmWizardMainForm; Editor: TPsdStudioFrame): Integer;
  procedure Check(Value: Boolean; const Text: string);
  begin if not Value then raise Exception.Create('Preview layout: '+Text); Inc(Result); end;
  function ChildrenFit(Parent: TWinControl): Boolean;
  begin
    Result := True;
    for var I := 0 to Parent.ControlCount-1 do begin
      var C := Parent.Controls[I]; var R := C.BoundsRect;
      if (R.Left<0) or (R.Top<0) or (R.Right>Parent.ClientWidth) or (R.Bottom>Parent.ClientHeight) or R.IsEmpty then Exit(False);
      for var J := I+1 to Parent.ControlCount-1 do begin
        var Other := Parent.Controls[J].BoundsRect; var Intersection: TRect;
        if IntersectRect(Intersection,R,Other) and not Intersection.IsEmpty then Exit(False);
      end;
    end;
  end;
begin
  Result := 0;
  var Toolbar := TToolBar(Editor.FindComponent('PsdStageToolbar'));
  var Preview := TPsdPreviewControl(Editor.FindComponent('PsdPreviewSurface'));
  var Reference := TPsdMotionReferencePage(Editor.FindComponent('PsdMotionReferenceEditor'));
  var OriginalPPI := Main.CurrentPPI; var Bounds := Main.BoundsRect;
  var Revision := Editor.Session.Revision; var Id := Editor.Session.Character.Id;
  var Play := TCheckBox(Editor.FindComponent('PsdPlay')); var WasPlaying := Play.Checked;
  Play.Checked := False; // 配置検査中は描画タイマーの連続更新からメッセージ処理を独立させる。
  try
    for var PPI in [96,120,144,192] do begin
      Main.ScaleForPPI(PPI); Main.SetBounds(40,40,MulDiv(1000,PPI,96),MulDiv(740,PPI,96));
      Application.ProcessMessages;
      for var Stage := 0 to 3 do begin
        TToolButton(Toolbar.FindComponent('PsdStage'+Stage.ToString)).Click;
        Application.ProcessMessages;
        var Settings: TPsdSettingsPanel;
        if Stage=2 then Settings := Reference.SettingsPanel else Settings := TPsdSettingsPanel(Editor.FindComponent('PsdSettings'+Stage.ToString));
        var Surface := Preview; if Stage=2 then Surface := Reference.Preview;
        var Left := Surface.ClientToScreen(Point(0,0)); var Right := Settings.ClientToScreen(Point(0,0));
        Check(Surface.Showing and Settings.Showing and (Right.X>=Left.X+Surface.ClientWidth),PPI.ToString+' stage '+Stage.ToString+' left preview and right settings');
        var RowsFit := True; var RowsSeparate := True;
        for var I := 0 to Settings.Content.ControlCount-1 do begin
          var Row := TWinControl(Settings.Content.Controls[I]);
          RowsFit := RowsFit and ChildrenFit(Row) and (Row.Top+Row.Height<=Settings.Content.Height);
          for var J := I+1 to Settings.Content.ControlCount-1 do begin
            var Intersection: TRect;
            if IntersectRect(Intersection,Row.BoundsRect,Settings.Content.Controls[J].BoundsRect) and not Intersection.IsEmpty then RowsSeparate := False;
          end;
        end;
        Check(RowsFit,PPI.ToString+' stage '+Stage.ToString+' controls fit their rows');
        Check(RowsSeparate,PPI.ToString+' stage '+Stage.ToString+' settings do not overlap');
        Check((Settings.Content.Height<=Settings.ClientHeight) or
          (Settings.VertScrollBar.Visible and (Settings.VertScrollBar.Range>=Settings.Content.Height)),PPI.ToString+' stage '+Stage.ToString+' overflow is scrollable');
        Settings.VertScrollBar.Position := Settings.VertScrollBar.Range; Application.ProcessMessages;
        var LastBottom := 0;
        for var I := 0 to Settings.Content.ControlCount-1 do
          LastBottom := Max(LastBottom,Settings.Content.Controls[I].Top+Settings.Content.Controls[I].Height);
        Check(Settings.Content.Top+LastBottom<=Settings.ClientHeight,PPI.ToString+' stage '+Stage.ToString+' last setting can be reached');
        Settings.VertScrollBar.Position := 0;
      end;
    end;
  finally
    Main.ScaleForPPI(OriginalPPI); Main.BoundsRect := Bounds;
    TToolButton(Toolbar.FindComponent('PsdStage0')).Click;
    Play.Checked := WasPlaying;
  end;
  Check((Editor.Session.Revision=Revision) and (Editor.Session.Character.Id=Id) and not Editor.Session.Dirty,
    'layout, DPI and scrolling preserve character content');
end;
procedure CaptureUiWindow(Main: TRigmWizardMainForm; const ResultPath,Suffix: string);
  begin
    Main.Update;
    var Request := TJSONObject.Create; var Token := PsdJson.NewId;
    try
      Request.AddPair('pid',TJSONNumber.Create(GetCurrentProcessId)); Request.AddPair('stage',Suffix); Request.AddPair('token',Token);
      var RequestPath := ResultPath+'.capture-request.json';
      TFile.WriteAllText(RequestPath+'.pending',Request.ToJSON,TEncoding.UTF8);
      if not MoveFileEx(PChar(RequestPath+'.pending'),PChar(RequestPath),MOVEFILE_REPLACE_EXISTING) then RaiseLastOSError;
    finally Request.Free; end;
    var Deadline := GetTickCount64+45000;
    repeat
      Application.ProcessMessages; Sleep(10);
      if FileExists(ResultPath+'.capture-ack.txt') then try
        var Ack := TFileStream.Create(ResultPath+'.capture-ack.txt',fmOpenRead or fmShareDenyNone);
        var Data: TBytes;
        try
          if (Ack.Size>0) and (Ack.Size<256) then begin SetLength(Data,Ack.Size); Ack.ReadBuffer(Data[0],Length(Data)); end;
        finally Ack.Free; end;
        if TEncoding.UTF8.GetString(Data).Trim.TrimLeft([#$FEFF])=Token then Exit;
      except on E: Exception do
        if not ((E is EOSError) or (E is EFOpenError) or (E is EInOutError)) then raise;
      end;
    until GetTickCount64>Deadline;
    raise Exception.Create('Owned native capture timed out');
  end;
procedure VerifyScriptTitle(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Name: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Script title validation failed: '+Name); Results.Add(Name); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptStage1.Validation.v1' then raise Exception.Create('Owned script validation root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
  Main.Update; Application.ProcessMessages;
  var Results := TJSONArray.Create; var Report := TJSONObject.Create;
  try
    Report.AddPair('checks',Results);
    Check(ScriptUpdatedAtLocal('2026-10-06T02:49:47.196Z')=ScriptUpdatedAtLocal('2026-10-06T11:49:47.196+09:00'),
      'UTC and explicit Japanese offset display the same local time without double conversion',Results);
    Check((ScriptUpdatedAtLocal('')='') and (ScriptUpdatedAtLocal('invalid')='日時不明'),'empty and invalid timestamps are safe',Results);
    if TTimeZone.Local.GetUtcOffset(Now).TotalMinutes=540 then begin
      Check(ScriptUpdatedAtLocal('2026-10-06T02:49:47.196Z')='2026-10-06 11:49:47','Japanese local time matches the actual saved user timestamp',Results);
      Check(ScriptUpdatedAtLocal('2026-10-05T16:01:00Z')='2026-10-06 01:01:00','local conversion handles date rollover',Results);
    end;
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    var Manager := Main.PageInstance(apScripts); var List := TListView(Manager.FindComponent('ScriptLibrary'));
    var Bar := TToolBar(Manager.FindComponent('ScriptLibraryToolbar'));
    var W := Main.Workspace;
    if Reopen then begin
      var State := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try
        var Path := JS(State,'path');
        for var Item in List.Items do if SameText(Item.SubItems[3],Path) then Item.Selected := True;
        Check((List.Selected<>nil) and SameText(List.Selected.SubItems[3],Path),'persisted title draft appears after process restart',Results);
        List.OnDblClick(List);
        var Frame := Main.PageInstance(apScriptCreate); var Title := TEdit(Frame.FindComponent('ScriptTitle'));
        Check((W.ScriptDraft.Id=JS(State,'projectId')) and (Title.Text='終了時の途中入力') and not W.ScriptDraft.Modified,
          'fresh process resumes same UID and interrupted input',Results);
        Check((Main.CurrentPage=apScriptCreate) and (Main.PageInstance(apMovieEdit)=nil) and (W.Sessions.Count=0),
          'restart stays at title without creating movie production',Results);
        CaptureUiWindow(Main,ResultPath,'.reopened');
      finally State.Free; end;
    end else begin
      Check((Main.CreatedPageCount=2) and (Screen.FormCount=1) and (W.Sessions.Count=0),
        'home and library use one form and only requested frames',Results);
      Check(not Bar.ShowCaptions and (Bar.Buttons[0].Name='ScriptNew') and (Bar.Buttons[0].Hint<>''),
        'compact library icons have hints',Results);
      CaptureUiWindow(Main,ResultPath,'.library');
      var NewButton := TToolButton(Bar.FindComponent('ScriptNew')); NewButton.Click;
      var Id := W.ScriptDraft.Id; var Path := W.ScriptDraft.FileName;
      var Frame := Main.PageInstance(apScriptCreate); var Title := TEdit(Frame.FindComponent('ScriptTitle'));
      var TitleBar := TToolBar(Frame.FindComponent('ScriptTitleToolbar'));
      var Save := TToolButton(TitleBar.FindComponent('ScriptSave')); var Back := TToolButton(TitleBar.FindComponent('ScriptReturn'));
      Check((Main.CurrentPage=apScriptCreate) and FileExists(Path) and (Title.Text='') and not Save.Enabled,
        'new creates saved empty title draft in UID folder',Results);
      Check(SameText(ExtractFileName(ExtractFileDir(Path)),Id) and (ExtractFileName(Path)='project.rigmovie'),
        'physical directory uses UID rather than title',Results);
      NewButton.Click;
      Check((W.ScriptDraft.Id=Id) and (Length(TDirectory.GetFiles(TPath.Combine(Main.DataRoot,'Projects'),'*.rigmovie',TSearchOption.soAllDirectories))=1),
        'rapid repeated new reuses the just-created draft',Results);
      var Failed := False;
      try W.SaveScriptDraft(True); except on E: Exception do Failed := True; end;
      Check(Failed and (Main.CurrentPage=apScriptCreate),'empty title cannot be confirmed',Results);
      Title.Text := '同じ題名'; Save.Click;
      Check(not W.ScriptDraft.Modified and (JS(W.ScriptDraft.ScriptWizard,'titleStatus')='complete') and (W.ScriptDraft.Title='同じ題名'),
        'human save confirms title and persists it',Results);
      Check((Main.CurrentPage=apScriptCreate) and (Frame.FindComponent('ScriptNext')=nil) and (Frame.FindComponent('CreationGoMovie')=nil) and
        (Main.PageInstance(apMovieEdit)=nil) and (Main.PageInstance(apCharacterEdit)=nil) and (W.Sessions.Count=0),
        'save cannot advance or launch legacy production',Results);
      CaptureUiWindow(Main,ResultPath,'.title');
      Back.Click; List.OnDblClick(List);
      Check((Main.PageInstance(apScriptCreate)=Frame) and (W.ScriptDraft.Id=Id) and (Title.Text='同じ題名'),
        'library double click resumes same frame and UID',Results);
      Title.Text := '戻る時の途中入力'; Back.Click; List.OnDblClick(List);
      Check((Title.Text='戻る時の途中入力') and (JS(W.ScriptDraft.ScriptWizard,'titleStatus')='in-progress') and not W.ScriptDraft.Modified,
        'return saves unfinished input without confirming title',Results);
      var FileHash := THashSHA2.GetHashStringFromFile(Path); Title.Text := '保存失敗でも保持';
      var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try
        Save.Click; TButton(Main.FindComponent('WizardHome')).Click;
        var CanClose := True; Main.OnCloseQuery(Main,CanClose);
        Check(not CanClose and (Main.CurrentPage=apScriptCreate) and W.ScriptDraft.Modified and (Title.Text='保存失敗でも保持') and
          (THashSHA2.GetHashStringFromFile(Path)=FileHash),'failed save blocks return and closing while retaining input and original file',Results);
      finally Guard.Free; end;
      TButton(Main.FindComponent('WizardHome')).Click;
      Check((Main.CurrentPage=apHome) and not W.ScriptDraft.Modified,'home saves unfinished input after write lock released',Results);
      TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click; NewButton.Click;
      var SecondId := W.ScriptDraft.Id; Title.Text := '同じ題名'; Save.Click; Back.Click;
      Check((SecondId<>Id) and (List.Items.Count=2),'same display title can use separate UID folders',Results);
      for var Item in List.Items do if SameText(Item.SubItems[3],Path) then Item.Selected := True;
      List.OnDblClick(List);
      Check((W.ScriptDraft.Id=Id) and (Title.Text='保存失敗でも保持'),'selecting another draft restores its own title',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe');
      Check((Title.Text='AIの題名案') and not W.ScriptDraft.Modified and (JS(W.ScriptDraft.ScriptWizard,'titleStatus')='in-progress'),
        'real workspace pipe updates GUI and saves without human confirmation',Results);
      Save.Click;
      Check((JS(W.ScriptDraft.ScriptWizard,'titleStatus')='complete') and (Main.CurrentPage=apScriptCreate),
        'human confirms AI title and remains at stage one',Results);
      // 旧作品と除外素材は、この所有Temp内の小さな模擬ファイルだけで確認する。
      var Legacy := TRigmMovieProject.Create;
      try
        Legacy.Title := '従来作品'; SaveMovie(Legacy,TPath.Combine(Main.DataRoot,'Scripts\従来.rigmovie'),False);
        SaveMovie(Legacy,TPath.Combine(Main.DataRoot,'Scripts\Documents\保護作品.rigmovie'),False);
        SaveMovie(Legacy,TPath.Combine(Main.DataRoot,'Scripts\ignored\除外作品.rigmovie'),False);
      finally Legacy.Free; end;
      TFile.WriteAllText(TPath.Combine(Main.DataRoot,'Scripts\ignored\.rigmignore'),'owned excluded fixture',TEncoding.UTF8);
      var LegacyHash := THashSHA2.GetHashStringFromFile(TPath.Combine(Main.DataRoot,'Scripts\従来.rigmovie'));
      var Listing := W.ScriptLibrary;
      try
        Check((JI(Listing,'total')=3) and (JA(Listing,'scripts').Count=3),'library separates legacy while excluding Documents and rigmignore folders',Results);
        var LegacyFound := False;
        for var V in JA(Listing,'scripts') do if JS(TJSONObject(V),'title')='従来作品' then LegacyFound := JS(TJSONObject(V),'kind')='legacy';
        Check(LegacyFound,'legacy project is distinguished from wizard titles',Results);
      finally Listing.Free; end;
      Failed := False;
      try W.OpenScriptDraft(TPath.Combine(Main.DataRoot,'Scripts\従来.rigmovie')); except on E: Exception do Failed := True; end;
      Check(Failed and (W.ScriptDraft.Id=Id) and (THashSHA2.GetHashStringFromFile(TPath.Combine(Main.DataRoot,'Scripts\従来.rigmovie'))=LegacyHash),
        'title-only open rejects legacy without modifying it or current draft',Results);
      Failed := False;
      try W.OpenScriptDraft('..\outside.rigmovie'); except on E: Exception do Failed := True; end;
      Check(Failed and (W.ScriptDraft.Id=Id),'path outside data root is rejected and active title retained',Results);
      Title.Text := '終了時の途中入力'; var CanClose := True; Main.OnCloseQuery(Main,CanClose);
      Check(CanClose and not W.ScriptDraft.Modified and (JS(W.ScriptDraft.ScriptWizard,'titleStatus')='in-progress'),
        'window close query saves interrupted title',Results);
      var Loaded := LoadMovie(Path);
      try Check((Loaded.Id=Id) and (JS(Loaded.ScriptWizard,'titleInput')='終了時の途中入力') and
        (JS(Loaded.ScriptWizard,'createdAt')<>'') and (JS(Loaded.ScriptWizard,'updatedAt')<>''),'saved title includes identity state and timestamps',Results);
      finally Loaded.Free; end;
      var Resume := TJSONObject.Create;
      try Resume.AddPair('projectId',Id); Resume.AddPair('path',Path); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8);
      finally Resume.Free; end;
      Check((Screen.FormCount=1) and (Main.CreatedPageCount=3) and (W.Sessions.Count=0),'whole stage stays in one main form with no production sessions',Results);
    end;
    Report.AddPair('reopened',TJSONBool.Create(Reopen)); Report.AddPair('state',W.ScriptStatus);
    var Output := ResultPath; if Reopen then Output := Output+'.reopened.json';
    TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
procedure VerifyScriptCharacters(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Script character validation failed: '+Text); Results.Add(Text); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptStage2.Validation.v1' then raise Exception.Create('Owned stage two validation root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
  Main.Update; Application.ProcessMessages;
  var Results := TJSONArray.Create; var Report := TJSONObject.Create;
  try
    Report.AddPair('checks',Results); var W := Main.Workspace;
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    var Manager := Main.PageInstance(apScripts); var LibraryList := TListView(Manager.FindComponent('ScriptLibrary'));
    var Bar := TToolBar(Manager.FindComponent('ScriptLibraryToolbar'));
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try
        W.OpenScriptDraft(JS(Resume,'path')); Main.NavigateTo(apScriptCreate);
        var Frame := Main.PageInstance(apScriptCreate); var List := TListView(Frame.FindComponent('ScriptCharacters'));
        Check((W.ScriptDraft.Id=JS(Resume,'projectId')) and (JS(W.ScriptDraft.ScriptWizard,'stage')='characters') and List.Showing,
          'fresh process restores UID and character stage',Results);
        var Count := 0; for var Item in List.Items do if Item.Checked then Inc(Count);
        Check((Count=1) and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=1) and not W.ScriptDraft.Modified,
          'fresh process restores checked character selection',Results);
        Check(JS(JO(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Items[0]),'voiceBinding'),'speakerId')='retained-test-speaker',
          'existing voice binding metadata survives restart',Results);
        CaptureUiWindow(Main,ResultPath,'.reopened');
      finally Resume.Free; end;
    end else begin
      TToolButton(Bar.FindComponent('ScriptNew')).Click;
      var Frame := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Frame.FindComponent('ScriptTitleToolbar'));
      var Title := TEdit(Frame.FindComponent('ScriptTitle')); var Save := TToolButton(Toolbar.FindComponent('ScriptSave'));
      var Next := TToolButton(Toolbar.FindComponent('ScriptNext')); var Back := TToolButton(Toolbar.FindComponent('ScriptReturn'));
      var Id := W.ScriptDraft.Id; var Path := W.ScriptDraft.FileName;
      Check(not Next.Enabled,'unconfirmed title cannot advance',Results);
      W.ScriptDraft.ScriptWizard.RemovePair('selectedCharacters').Free;
      W.ScriptDraft.ScriptWizard.RemovePair('charactersStatus').Free;
      Title.Text := 'キャラ選択の所有検証'; Save.Click;
      W.OpenScriptDraft(Path);
      Check(W.ScriptDraft.ScriptWizard.GetValue('selectedCharacters')=nil,'existing title-only wizard opens without forced metadata migration',Results);
      Check(Next.Enabled and (JS(W.ScriptDraft.ScriptWizard,'stage')='title'),'title confirmation enables manual next and stays at title',Results);
      Next.Click; var List := TListView(Frame.FindComponent('ScriptCharacters'));
      Check(List.Showing and (JS(W.ScriptDraft.ScriptWizard,'stage')='characters') and Next.Visible,
        'manual next opens only character stage',Results);
      var Failed := False; try W.SaveScriptDraft(True); except on E: Exception do Failed := True; end;
      Check(Failed and not Save.Enabled,'minimum one selected character required for confirmation',Results);
      WaitThumbnailLibrary(W); Sleep(100); Application.ProcessMessages;
      var PsdItem,RigItem,IncompleteItem: TListItem; PsdItem := nil; RigItem := nil; IncompleteItem := nil;
      for var Item in List.Items do begin
        var E := TJSONObject(Item.Data);
        if JB(E,'readyForScript') then begin
          if JS(E,'renderFormat')='psd' then PsdItem := Item else RigItem := Item;
        end else IncompleteItem := Item;
      end;
      Check((PsdItem<>nil) and (RigItem<>nil) and (IncompleteItem<>nil) and (PsdItem.ImageIndex>=0) and (RigItem.ImageIndex>=0),
        'registered PSD and RIGM share thumbnail rendering with format labels and completion checks',Results);
      var RigPath := W.Pipe.Workspace.Resolve(JS(TJSONObject(RigItem.Data),'path'));
      var OriginalRig := TFile.ReadAllBytes(RigPath);
      try
        TFile.WriteAllBytes(RigPath,TFile.ReadAllBytes(W.Pipe.Workspace.Resolve(JS(TJSONObject(IncompleteItem.Data),'path'))));
        var Paths := TJSONArray.Create; Failed := False;
        try
          Paths.Add(JS(TJSONObject(RigItem.Data),'path'));
          try W.SetScriptCharacters(Paths); except on E: Exception do Failed := True; end;
        finally Paths.Free; end;
        Check(Failed and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=0),
          'source version invalidates cached completion when a registered file changes',Results);
      finally TFile.WriteAllBytes(RigPath,OriginalRig); end;
      WaitThumbnailLibrary(W); Sleep(100); Application.ProcessMessages;
      IncompleteItem.Checked := True; Application.ProcessMessages;
      Check(not IncompleteItem.Checked and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=0),'incomplete character checkbox is rejected',Results);
      PsdItem.Checked := True; Application.ProcessMessages; RigItem.Checked := True; Application.ProcessMessages;
      Check((JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2) and Save.Enabled,'multiple complete characters update shared state',Results);
      var ProjectJson := W.ScriptDraft.Json; var SpeakersBefore: string;
      try SpeakersBefore := JA(ProjectJson,'speakers').ToJSON; finally ProjectJson.Free; end;
      // 所有検証だけの既存配役を模擬し、選択変更で削られないことを確かめる。
      TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Items[0]).AddPair('voiceBinding',
        PsdJson.ObjectText('{"speakerId":"retained-test-speaker","styleId":12345}'));
      Save.Click;
      Check((JS(W.ScriptDraft.ScriptWizard,'charactersStatus')='complete') and not W.ScriptDraft.Modified,
        'human confirmation saves character stage',Results);
      ProjectJson := W.ScriptDraft.Json;
      try Check((JA(ProjectJson,'speakers').ToJSON=SpeakersBefore) and (W.ScriptDraft.Characters.Count=0) and (W.ScriptDraft.Cues.Count=0) and
        (W.ScriptDraft.Scenes.Count=0),'selection preserves existing speakers and creates no voice layout or script body',Results); finally ProjectJson.Free; end;
      CaptureUiWindow(Main,ResultPath,'.characters');
      TToolButton(Toolbar.FindComponent('ScriptTitleStage')).Click;
      Check(Title.Showing and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2),'returning to title retains selections',Results);
      Title.Text := '題名を修正してもキャラを保持'; Save.Click; Next.Click;
      Check(PsdItem.Checked and RigItem.Checked and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2),'title editing and returning restore selections',Results);
      var Hash := THashSHA2.GetHashStringFromFile(Path); RigItem.Checked := False; Application.ProcessMessages;
      var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try
        Back.Click;
        Check((Main.CurrentPage=apScriptCreate) and W.ScriptDraft.Modified and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=1) and
          (THashSHA2.GetHashStringFromFile(Path)=Hash),'failed selection save retains input original file and current page',Results);
      finally Guard.Free; end;
      RigItem.Checked := True; Application.ProcessMessages; Back.Click;
      Check((Main.CurrentPage=apScripts) and not W.ScriptDraft.Modified,'return saves character selection without confirmation',Results);
      for var Item in LibraryList.Items do if SameText(Item.SubItems[3],Path) then LibraryList.Selected := Item;
      Check(LibraryList.Selected.SubItems[0]='キャラ：選択中','library displays persisted character stage',Results);
      LibraryList.OnDblClick(LibraryList);
      Check(List.Showing and PsdItem.Checked and RigItem.Checked and (W.ScriptDraft.Id=Id),'library resumes character stage on same UID',Results);
      CaptureUiWindow(Main,ResultPath,'.pipechars');
      Check((JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=1) and (JS(W.ScriptDraft.ScriptWizard,'charactersStatus')='in-progress') and
        not W.ScriptDraft.Modified,'actual pipe updates and saves same character state without human confirmation',Results);
      var Count := 0; for var Item in List.Items do if Item.Checked then Inc(Count);
      Check(Count=1,'actual pipe change appears in GUI checkboxes',Results);
      var FirstPath := JS(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Items[0]),'path');
      var AddedPath := TPath.Combine(Main.DataRoot,'Characters\owned-late-registration.psdchar');
      TFile.Copy(W.Pipe.Workspace.Resolve(FirstPath),AddedPath,False);
      WaitThumbnailLibrary(W);
      var Paths := TJSONArray.Create;
      try Paths.Add(FirstPath); Paths.Add('Characters\owned-late-registration.psdchar'); W.SetScriptCharacters(Paths); finally Paths.Free; end;
      var AddedChecked := False;
      for var Item in List.Items do if SameText(JS(TJSONObject(Item.Data),'path'),'Characters\owned-late-registration.psdchar') then AddedChecked := Item.Checked;
      Check(AddedChecked,'character registered after opening appears when shared state selects it',Results);
      // 所有fixtureを作業領域へ移して一覧から外す。元素材は触らない。
      ForceDirectories(TPath.Combine(Main.DataRoot,'Work'));
      TFile.Move(AddedPath,TPath.Combine(Main.DataRoot,'Work\owned-late-registration.psdchar'));
      Paths := TJSONArray.Create;
      try Paths.Add(FirstPath); W.SetScriptCharacters(Paths); finally Paths.Free; end;
      TToolButton(Toolbar.FindComponent('ScriptCharactersRefresh')).Click;
      Save.Click; var CanClose := True; Main.OnCloseQuery(Main,CanClose);
      Check(CanClose and (JS(W.ScriptDraft.ScriptWizard,'charactersStatus')='complete'),'confirmation and close keep character state saved',Results);
      var Resume := TJSONObject.Create;
      try Resume.AddPair('projectId',Id); Resume.AddPair('path',Path); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; end;
    end;
    Check((Screen.FormCount=1) and (W.Sessions.Count=0) and (Main.PageInstance(apMovieEdit)=nil),'stage two creates no movie production or extra forms',Results);
    Report.AddPair('state',W.ScriptStatus); var Output := ResultPath; if Reopen then Output := Output+'.reopened.json';
    TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
procedure VerifyThumbnailCache(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Thumbnail validation failed: '+Text); Results.Add(Text); end;
  function Counter(W: TRigmWizardWorkspace; const Name: string): Integer;
  begin var S := W.Thumbnails.Stats; try Result := JI(S,Name); finally S.Free; end; end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ThumbnailCache.Validation.v1' then raise Exception.Create('Owned cache validation root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
  Main.Update; Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; var Times := TJSONObject.Create;
  var Probe := TThumbnailHeartbeat.Create; var Timer := TTimer.Create(nil);
  try
    Report.AddPair('checks',Results); Report.AddPair('timesMs',Times);
    Timer.Interval := 40; Timer.OnTimer := Probe.Tick; Probe.Last := GetTickCount64;
    var W := Main.Workspace; var Started := GetTickCount64;
    Main.NavigateTo(apCharacters);
    var Manager := TRigmCharacterManagerFrame(Main.PageInstance(apCharacters)); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    Times.AddPair('grid',TJSONNumber.Create(GetTickCount64-Started));
    Check((List.Items.Count=3) and Manager.Showing,'list shell and rows are visible before generation completes',Results);
    if not Reopen then begin
      var Pending := Counter(W,'pending'); Check(Pending>0,'cold list returns while background generation is pending',Results);
      Manager.RefreshLibrary(Main); Manager.RefreshLibrary(Main);
      // 所有中の別一覧を生成直後に破棄し、結果が破棄済みUIへ通知されないことを確認。
      var Transient := TRigmCharacterManagerFrame.CreateForRoot(nil,Main.DataRoot,W);
      Transient.RefreshLibrary(Main); Transient.Free;
      Main.NavigateTo(apHome); Main.NavigateTo(apCharacters);
    end;
    WaitThumbnailLibrary(W); Sleep(100); Application.ProcessMessages;
    Times.AddPair('allImages',TJSONNumber.Create(GetTickCount64-Started));
    var Images := 0; for var Item in List.Items do if Item.ImageIndex>=0 then Inc(Images);
    Check(Images=3,'all thumbnails eventually appear through UI polling',Results);
    Check(Probe.MaxGap<500,'UI heartbeat remains responsive during generation',Results);
    Check(not W.Thumbnails.Stats.ToJSON.Contains('Temp\PsdJobs'),'persistent cache is outside ordinary work cleanup',Results);
    if Reopen then begin
      Check(Counter(W,'packageReads')=0,'fresh process uses persistent thumbnails without reading packages',Results);
      Check(Counter(W,'diskHits')=3,'fresh process restores three disk cache entries',Results);
      CaptureUiWindow(Main,ResultPath,'.reopened');
    end else begin
      Check((Counter(W,'packageReads')=3) and (Counter(W,'generated')=3),'refresh and multiple lists deduplicate source generation',Results);
      CaptureUiWindow(Main,ResultPath,'.cold');
      Started := GetTickCount64; Manager.RefreshLibrary(Main); Application.ProcessMessages;
      Times.AddPair('warmRefresh',TJSONNumber.Create(GetTickCount64-Started));
      Check(Counter(W,'packageReads')=3,'warm refresh does not read or hash full packages',Results);
      W.NewScriptDraft; W.SetScriptTitle('サムネイルの所有検証'); W.SaveScriptDraft(True); W.SetScriptStage('characters');
      Started := GetTickCount64; Main.NavigateTo(apScriptCreate); Application.ProcessMessages;
      Times.AddPair('scriptList',TJSONNumber.Create(GetTickCount64-Started));
      var Frame := Main.PageInstance(apScriptCreate); var Actors := TListView(Frame.FindComponent('ScriptCharacters'));
      Images := 0; for var Item in Actors.Items do if Item.ImageIndex>=0 then Inc(Images);
      Check((Images=3) and (Counter(W,'packageReads')=3),'character selection reuses the same cached pixels and metadata',Results);
      var PsdItem: TListItem := nil; var RigPath,IncompletePath: string;
      for var Item in Actors.Items do begin
        var E := TJSONObject(Item.Data);
        if JS(E,'renderFormat')='psd' then PsdItem := Item
        else if JB(E,'readyForScript') then RigPath := W.Pipe.Workspace.Resolve(JS(E,'path'))
        else IncompletePath := W.Pipe.Workspace.Resolve(JS(E,'path'));
      end;
      Check(PsdItem<>nil,'PSD row contains completed cached registration metadata',Results);
      PsdItem.Checked := True; Application.ProcessMessages;
      Check(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=1,'completed cached character can still be selected',Results);
      var RigBytes := TFile.ReadAllBytes(RigPath); var OriginalTime := TFile.GetLastWriteTimeUtc(RigPath);
      var Signature := CharacterSourceSignature(RigPath); var Reads := Counter(W,'packageReads');
      try
        TFile.WriteAllBytes(RigPath,TFile.ReadAllBytes(IncompletePath)); TFile.SetLastWriteTimeUtc(RigPath,OriginalTime);
        Check(CharacterSourceSignature(RigPath)<>Signature,'source identity detects changes even when timestamp is restored',Results);
        Started := GetTickCount64; Manager.RefreshLibrary(Main); WaitThumbnailLibrary(W); Sleep(100); Application.ProcessMessages;
        Times.AddPair('changedSource',TJSONNumber.Create(GetTickCount64-Started));
        var E := W.Thumbnails.Request(RigPath);
        Check((E<>nil) and not JB(E.Metadata,'readyForScript') and (Counter(W,'packageReads')=Reads+1),
          'only changed source is regenerated with updated completion state',Results);
      finally TFile.WriteAllBytes(RigPath,RigBytes); end;
      WaitThumbnailLibrary(W); Sleep(100); Application.ProcessMessages;
      var PsdPath := W.Pipe.Workspace.Resolve(JS(TJSONObject(PsdItem.Data),'path'));
      var Cached := W.Thumbnails.Request(PsdPath); var Expected := PreviewDigest(Cached.Pixels);
      TFile.WriteAllBytes(W.Thumbnails.CachePath(PsdPath),TEncoding.UTF8.GetBytes('broken-owned-cache'));
      var Recovery := TRigmThumbnailCache.Create(Main.DataRoot);
      try
        Started := GetTickCount64; var Deadline := Started+20000; var E: TRigmThumbnailEntry;
        repeat E := Recovery.Request(PsdPath); Application.ProcessMessages; if E<>nil then Break; Sleep(5); until GetTickCount64>Deadline;
        Check((E<>nil) and (PreviewDigest(E.Pixels)=Expected),'corrupt cache is safely recreated from unchanged source',Results);
        var S := Recovery.Stats; try Check(JI(S,'packageReads')=1,'corrupt cache regenerates only its own source',Results); finally S.Free; end;
        Times.AddPair('corruptRecovery',TJSONNumber.Create(GetTickCount64-Started));
        var Bitmap := TBitmap.Create;
        try
          PaintCharacterPixels(E.Pixels,E.Width,E.Height,Bitmap,288,352);
          Check((Bitmap.Width=288) and (Bitmap.Height=352),'cached original aspect ratio can render at higher DPI',Results);
        finally Bitmap.Free; end;
      finally Recovery.Free; end;
      CaptureUiWindow(Main,ResultPath,'.shared');
    end;
    Check((Screen.FormCount=1) and (W.Sessions.Count=0) and (Main.PageInstance(apMovieEdit)=nil),'cache work does not enter later production stages',Results);
    Times.AddPair('heartbeatMaxGap',TJSONNumber.Create(Probe.MaxGap)); Report.AddPair('stats',W.Thumbnails.Stats);
    var Output := ResultPath; if Reopen then Output := Output+'.reopened.json';
    TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Timer.Free; Probe.Free; Report.Free; end;
end;
procedure Drop(Manager: TFrame; const Path: string);
  begin
    // Explorerと同じWM_DROPFILES経路をアプリ所有のファイルで検証する。
    var DropHandle := GlobalAlloc(GHND,SizeOf(TDropFiles)+(Length(Path)+2)*SizeOf(Char));
    if DropHandle=0 then RaiseLastOSError;
    var Data := GlobalLock(DropHandle);
    if Data=nil then begin GlobalFree(DropHandle); RaiseLastOSError; end;
    PDropFiles(Data).pFiles := SizeOf(TDropFiles); PDropFiles(Data).fWide := True;
    Move(PChar(Path)^,PByte(Data)[SizeOf(TDropFiles)],Length(Path)*SizeOf(Char));
    GlobalUnlock(DropHandle); Manager.Perform(WM_DROPFILES,WPARAM(DropHandle),0);
  end;
procedure VerifyRigmSelection(Main: TRigmWizardMainForm; Manager: TFrame; List: TListView;
  const RigSourcePath,ResultPath: string; Results: TJSONArray);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('RIGM selection validation failed: '+Text); Results.Add(Text); end;
begin
    // RIGMも準備表示の背後で初回フレームを作り、同じホストで開く。
    var RigSource := RigSourcePath; Drop(Manager,RigSource); var RigPath := List.Selected.SubItems[1];
    var BeforeRigCount := List.Items.Count; Drop(Manager,RigSource);
    Check((List.Items.Count=BeforeRigCount) and (List.Selected.SubItems[1]=RigPath),'RIGM duplicate drop selects existing UID',Results);
    var A := TJSONObject.Create;
    try var R := Main.Workspace.Command('legacy-status',A); R.Free; finally A.Free; end;
    var Host := TRigmCharacterEditPage(Main.PageInstance(apCharacterEdit)); Main.NavigateTo(apCharacters);
    var Probe := TLegacyLoadingProbe.Create;
    try
      Probe.Host := Host; Probe.Forward := Host.LegacyEditor.OnCharacterLoad;
      Probe.OnVisible := procedure begin CaptureUiWindow(Main,ResultPath,'.rigm-loading'); end;
      Host.LegacyEditor.OnCharacterLoad := Probe.LoadingChanged; List.OnDblClick(List);
      Check((Probe.Starts=1) and (Probe.Finishes=1) and Host.LegacyEditor.Showing and not
        TPanel(Host.FindComponent('CharacterLoading')).Visible,'RIGM loading prepares preview behind one existing loading page: '+
        Probe.Starts.ToString+'/'+Probe.Finishes.ToString+'; '+TLabel(Manager.FindComponent('CharacterLibraryStatus')).Caption,Results);
    finally Host.LegacyEditor.OnCharacterLoad := Probe.Forward; Probe.Free; end;
    var HasMovieButton := False;
    for var Index := 0 to Host.LegacyEditor.ComponentCount-1 do if Host.LegacyEditor.Components[Index] is TToolBar then begin
      var Bar := TToolBar(Host.LegacyEditor.Components[Index]);
      if Bar.FindComponent('MovieStudioButton')<>nil then HasMovieButton := True;
    end;
    Check(not HasMovieButton and not Assigned(Host.LegacyEditor.Editor.OnMovieOpen),'character movie shortcut and its dedicated callback removed',Results);
    Check(Host.FindComponent('CharacterEditorToolbar')=nil,'removed host return and format-switch icon row',Results);
    var Legacy := Host.LegacyEditor; Legacy.Editor.SwitchPage(rpLayer); Application.ProcessMessages;
    var LayerList := TArtLayerList(Legacy.FindComponent('LayerList'));
    var LayerPane := TPanel(Legacy.FindComponent('RigmLayerPane'));
    var Properties := TScrollBox(Legacy.FindComponent('PropertyScrollBox'));
    var LayerToolbar := TToolBar(Legacy.FindComponent('PageToolbar'));
    Check((LayerToolbar.Parent=LayerPane) and (LayerToolbar.Top<LayerList.Top) and (LayerToolbar.ButtonCount=8),'eight layer tools placed directly above layer list',Results);
    Check((Properties.Parent=LayerPane.Parent) and (Properties.Left>=LayerPane.Left+LayerPane.Width) and
      (Properties.ClientWidth>0) and not Properties.HorzScrollBar.Visible,'selected-layer properties positioned right of layer list with vertical scroll',Results);
    Check((Legacy.FindComponent('PsdImportHint')=nil) and (LayerToolbar.FindComponent('AddBoneButton')=nil) and
      (LayerToolbar.FindComponent('GenerateMeshesButton')=nil) and (Legacy.FindComponent('EditorToolbar')<>nil),'removed explanatory row and non-layer tools while preserving stage navigation',Results);
    var Preview := TRigmFramePreviewPaintBox(Legacy.FindComponent('CharacterPreview')); var Revision := Legacy.Editor.Document.Art.Revision;
    var Cursor := Point(Preview.ClientWidth div 2+10,Preview.ClientHeight div 2+10);
    var OldRect := Preview.ImageRect; var U := (Cursor.X-OldRect.Left)/OldRect.Width; var V := (Cursor.Y-OldRect.Top)/OldRect.Height;
    var ScreenPoint := Preview.ClientToScreen(Cursor); var Renders := Legacy.PreviewRenderCount;
    Preview.Perform(WM_MOUSEWHEEL,MakeWParam(0,120),MakeLParam(ScreenPoint.X,ScreenPoint.Y));
    var NewRect := Preview.ImageRect;
    Check((Preview.Zoom>1) and (Abs(U-(Cursor.X-NewRect.Left)/NewRect.Width)<0.01) and
      (Abs(V-(Cursor.Y-NewRect.Top)/NewRect.Height)<0.01),'RIGM wheel zoom stays centred under cursor',Results);
    var OldPan := Preview.Pan;
    Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Cursor.X,Cursor.Y));
    Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Cursor.X+25,Cursor.Y+18));
    Preview.Perform(WM_LBUTTONUP,0,MakeLParam(Cursor.X+25,Cursor.Y+18));
    Check(Preview.LeftPanEnabled and (Abs(Preview.Pan.X-OldPan.X-25)<1) and
      (Abs(Preview.Pan.Y-OldPan.Y-18)<1),'RIGM layer-page left drag pans the preview',Results);
    Preview.LeftPanEnabled := False; OldPan := Preview.Pan;
    Preview.Perform(WM_MBUTTONDOWN,MK_MBUTTON,MakeLParam(Cursor.X,Cursor.Y));
    Preview.Perform(WM_MOUSEMOVE,MK_MBUTTON,MakeLParam(Cursor.X+15,Cursor.Y+12));
    Preview.Perform(WM_MBUTTONUP,0,MakeLParam(Cursor.X+15,Cursor.Y+12));
    Check((Abs(Preview.Pan.X-OldPan.X-15)<1) and (Abs(Preview.Pan.Y-OldPan.Y-12)<1) and
      (Legacy.Editor.Document.Art.Revision=Revision) and (Legacy.PreviewRenderCount=Renders),'middle drag pans without changing parts or regenerating character image',Results);
    var Builds := Legacy.PropertyBuildCount;
    if LayerList.Selected<>nil then LayerList.Selected := LayerList.Selected;
    Check(Legacy.PropertyBuildCount=Builds,'same layer selection does not rebuild property controls',Results);
    for var PPI in [144,96] do begin
      Main.ScaleForPPI(PPI); Main.SetBounds(40,40,900,740); Application.ProcessMessages;
      Check((Properties.Left>=LayerPane.Left+LayerPane.Width) and (Properties.ClientWidth>0) and
        (Preview.ClientWidth>0),'RIGM narrow layout remains separate at '+PPI.ToString+' DPI',Results);
    end;
    Main.SetBounds(40,40,1280,840); Application.ProcessMessages;
    CaptureUiWindow(Main,ResultPath,'.rigm-editor');
    // 入力のコピーで工程のレイアウトだけを確認する。ユーザー作品へ保存しない。
    Legacy.Editor.Document.LayerComplete := True; Legacy.Editor.Document.BoneComplete := True; Legacy.Editor.Document.MeshComplete := True;
    for var Page in [rpBone,rpMesh,rpPreview] do begin
      Legacy.Editor.SwitchPage(Page); Application.ProcessMessages;
      Check(not LayerToolbar.Visible and not LayerPane.ShowCaption and (LayerPane.Caption=''),
        'no residual layer toolbar or panel caption on stage '+IntToStr(Ord(Page)),Results);
      if Page=rpPreview then Check(not LayerPane.Visible and (Properties.Left=0) and Properties.Showing,
        'preview keeps parameter controls without empty list pane',Results)
      else begin
        var Objects := TListBox(Legacy.FindComponent('BoneMeshList'));
        Check(LayerPane.Showing and Objects.Showing and (Objects.Align=alClient) and (Objects.Top=0) and
          (Objects.Height=LayerPane.ClientHeight) and Properties.Showing and
          (((Page=rpBone) and (Preview.PopupMenu.Items.Count>0)) or
            ((Page=rpMesh) and (Properties.FindComponent('ApplyMeshPropertiesButton')<>nil))),
          'bone or mesh list fills pane and retains properties and editing actions on stage '+IntToStr(Ord(Page)),Results);
      end;
      CaptureUiWindow(Main,ResultPath,'.rigm-'+IntToStr(Ord(Page)));
    end;
    Main.NavigateTo(apCharacters); var Broken := List.Items.Add; Broken.Caption := 'broken'; Broken.SubItems.Add('RIGM'); Broken.SubItems.Add(TPath.Combine(Main.DataRoot,'missing.rigm')); List.Selected := Broken;
    List.OnDblClick(List);
    Check((Main.CurrentPage=apCharacters) and not TPanel(Host.FindComponent('CharacterLoading')).Visible and
      (Host.LegacyEditor.Editor.FileName=RigPath),'failed RIGM load returns to library without losing previous editor',Results);
    Check(Screen.FormCount=1,'complete wizard and drop flows keep a single main form',Results);
end;
procedure VerifyCharacterCreate(Main: TRigmWizardMainForm; const ResultPath: string);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Character create validation failed: '+Text); Results.Add(Text); end;
begin
  var Owner := ObjectText(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  var FixturePath := S(Owner,'fixturePath');
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned GUI validation root required'); finally Owner.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show;
  ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update; Application.ProcessMessages;
  var Results := TJSONArray.Create;
  try
    Main.NavigateTo(apCharacters);
    var Manager := Main.PageInstance(apCharacters); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    var NewButton := TButton(Manager.FindComponent('CharacterNew'));
    for var Index := 1 to ParamCount do if ParamStr(Index)='--rigm-only' then begin
      VerifyRigmSelection(Main,Manager,List,TPath.Combine(ExtractFileDir(FixturePath),'fixture.rigm'),ResultPath,Results);
      Main.NavigateTo(apHome); TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8); Exit;
    end;
    Check((Manager.FindComponent('CharacterOpen')=nil) and (NewButton.Caption='新規作成'),'new menu replaces material registration and removes redundant open button',Results);
    var Count := List.Items.Count; NewButton.Click;
    Check((Main.CurrentPage=apCharacters) and (Main.PageInstance(apCharacterEdit)=nil) and (List.Items.Count=Count+1),'new creates a library entry without opening the editor',Results);
    Check((List.Selected<>nil) and (List.Selected.ImageIndex>=0) and (Pos('未完成',List.Selected.Caption)>0),'new entry is selected with incomplete thumbnail status',Results);
    var Path := List.Selected.SubItems[1];
    Check(FileExists(Path) and Path.StartsWith(TPath.Combine(Main.DataRoot,'Characters')+PathDelim,True),'new package saved under managed character root',Results);
    CaptureUiWindow(Main,ResultPath,'.library');
    List.OnDblClick(List);
    var Host := TRigmCharacterEditPage(Main.PageInstance(apCharacterEdit)); var Editor := Host.PsdEditor;
    var Pages := TPageControl(Editor.FindComponent('PsdCharacterPages'));
    Check((Main.CurrentPage=apCharacterEdit) and (Pages.ActivePageIndex=0) and (Editor.Session.SavedPath=Path),'double click opens new character at layer page',Results);
    var LayerTree: TTreeView := nil;
    for var Index := 0 to Editor.ComponentCount-1 do if Editor.Components[Index] is TTreeView then LayerTree := TTreeView(Editor.Components[Index]);
    var Guidance := TLabel(Editor.FindComponent('PsdEmptyLayerGuidance'));
    Check((LayerTree<>nil) and (LayerTree.Items.Count=0) and Guidance.Visible and Guidance.Parent.Showing and (Pos('Codex',Guidance.Caption)>0),'empty layers show material creation guidance',Results);
    var C := Editor.Session.Character; var Id := C.Id; var Reason: string;
    Check((C.Name='新規キャラ') and (C.SupplementName='') and (Id<>'') and (S(C.Production,'stage')='draft') and
      not Editor.Session.Dirty and not Editor.Session.ReadyForScript(Reason),'default name supplement and stable UID retained in saved incomplete draft',Results);
    Check(not CharacterReadyForNewScript(Path,Reason) and (Reason<>''),'actual script catalog rejects incomplete character',Results);
    var Previous := TButton(Editor.FindComponent('PsdPrevious')); var Next := TButton(Editor.FindComponent('PsdNext'));
    Application.ProcessMessages;
    Check((Previous.Align=alLeft) and (Next.Align=alRight),'back is left and next is right',Results);
    var StageToolbar := TToolBar(Editor.FindComponent('PsdStageToolbar'));
    Check((StageToolbar.Buttons[0].Name='PsdReturnToManagement') and not StageToolbar.ShowCaptions and
      (StageToolbar.Buttons[0].Hint='キャラ管理へ戻る'),'return icon is first in existing stage toolbar with hint',Results);
    var ReturnHash := THashSHA2.GetHashStringFromFile(Path);
    TEdit(Editor.FindComponent('PsdCharacterName')).Text := '戻る確認の下書き';
    ClickReturn(Editor,mrCancel);
    Check((Main.CurrentPage=apCharacterEdit) and (TEdit(Editor.FindComponent('PsdCharacterName')).Text='戻る確認の下書き') and
      (THashSHA2.GetHashStringFromFile(Path)=ReturnHash),'return cancellation retains unapplied draft and saved package',Results);
    ClickReturn(Editor,mrNo); List.OnDblClick(List);
    Check((Main.CurrentPage=apCharacterEdit) and (TEdit(Editor.FindComponent('PsdCharacterName')).Text='戻る確認の下書き') and
      (THashSHA2.GetHashStringFromFile(Path)=ReturnHash),'return without save resumes the same retained draft',Results);
    ClickReturn(Editor,mrYes);
    Check((Main.CurrentPage=apCharacters) and (Editor.Session.Character.Name='戻る確認の下書き') and not Editor.Session.Dirty,
      'return with save applies and saves draft before returning',Results);
    List.OnDblClick(List);
    CaptureUiWindow(Main,ResultPath,'.layers');
    TEdit(Editor.FindComponent('PsdCharacterName')).Text := '新規作成の保存確認';
    TEdit(Editor.FindComponent('PsdCharacterSupplement')).Text := '衣装の補足';
    // 編集ページの明示反映を使い、未完成キャラの既存自動保存経路も確認する。
    TButton(Editor.FindComponent('PsdInfoApply')).Click;
    Check((Editor.Session.Character.Id=Id) and (Editor.Session.Character.Name='新規作成の保存確認') and (Editor.Session.Character.SupplementName='衣装の補足') and
      not Editor.Session.Dirty,'draft name update persists without changing UID',Results);
    var FileHash := THashSHA2.GetHashStringFromFile(Path);
    Next.Click; Check((Pages.ActivePageIndex=0) and not Next.Visible,'empty draft cannot advance before layer validation',Results);
    Previous.Click; Check(Pages.ActivePageIndex=0,'back remains at first layer page',Results);
    TToolButton(TToolBar(Editor.FindComponent('PsdStageToolbar')).FindComponent('PsdReturnToManagement')).Click;
    Check((Main.CurrentPage=apCharacters) and (List.Selected.SubItems[1]=Path) and (Pos('新規作成の保存確認',List.Selected.Caption)>0),'return to library retains and refreshes the new entry',Results);
    List.OnDblClick(List);
    Check((Host.PsdEditor=Editor) and (Pages.ActivePageIndex=0) and (Editor.Session.Character.Id=Id),'double click reopens the same draft at layer page',Results);
    Main.NavigateTo(apCharacters); List.OnDblClick(List);
    Check((Pages.ActivePageIndex=0) and (THashSHA2.GetHashStringFromFile(Path)=FileHash),'same-character resume and navigation save rules retained',Results);
    var Reopened := TPsdSession.Create(Main.DataRoot,False);
    try
      var A := Reopened.Status;
      try A.AddPair('path',Path); var R := Reopened.Command('open',A); R.Free; finally A.Free; end;
      Check((Reopened.Character.Id=Id) and (Reopened.Character.Name='新規作成の保存確認') and (Reopened.Character.SupplementName='衣装の補足') and
        (Arr(Reopened.Character.Settings,'groups').Count=0) and not Reopened.ReadyForScript(Reason),'fresh session loads persisted draft with empty layers and incomplete status',Results);
    finally Reopened.Free; end;
    Main.NavigateTo(apCharacters); NewButton.Click;
    var SecondPath := List.Selected.SubItems[1]; List.OnDblClick(List);
    Check((SecondPath<>Path) and (Editor.Session.Character.Id<>Id) and (Pages.ActivePageIndex=0),'second new draft has unique UID and starts at layer page despite prior expression page',Results);
    Check((Screen.FormCount=1) and (Length(TDirectory.GetFiles(TPath.Combine(Main.DataRoot,'Characters'),'*.psdchar',TSearchOption.soAllDirectories))=Count+2),'flow keeps one form and one package per character',Results);
    Main.NavigateTo(apCharacters); var SourceHash := THashSHA2.GetHashStringFromFile(FixturePath);
    Drop(Manager,FixturePath); var RegisteredPath := List.Selected.SubItems[1];
    Check((List.Items.Count=Count+3) and FileExists(RegisteredPath) and (RegisteredPath<>FixturePath),'native file drop registers package from outside data root',Results);
    var RegisteredHash := THashSHA2.GetHashStringFromFile(RegisteredPath);
    Drop(Manager,FixturePath);
    Check((List.Items.Count=Count+3) and (List.Selected.SubItems[1]=RegisteredPath) and
      (THashSHA2.GetHashStringFromFile(RegisteredPath)=RegisteredHash),'repeat drop selects existing package without overwriting',Results);
    var SourceRoot := TPsdWorkspace.Create(ExtractFileDir(FixturePath)); SourceRoot.Initialize;
    try
      var Clone := LoadCharacter(SourceRoot,FixturePath);
      try
        Clone.Name := Clone.Name+'（同じUID）'; var SameUid := SourceRoot.Resolve('same-uid.psdchar',False); SaveCharacter(Clone,SourceRoot,SameUid);
        Drop(Manager,SameUid);
        Check((List.Items.Count=Count+3) and (List.Selected.SubItems[1]=RegisteredPath) and
          (THashSHA2.GetHashStringFromFile(RegisteredPath)=RegisteredHash),'same UID with different file bytes selects original without overwriting',Results);
        Clone.Id := NewId; Clone.Name := '新規キャラ'; var Twin := SourceRoot.Resolve('same-name.psdchar',False); SaveCharacter(Clone,SourceRoot,Twin);
        Drop(Manager,Twin);
        Check((List.Items.Count=Count+4) and (List.Selected.SubItems[1]<>RegisteredPath),'same display name with different UID can be registered',Results);
        var TwinPath := List.Selected.SubItems[1]; List.OnDblClick(List);
        Check((Pages.ActivePageIndex=0) and Next.Visible,'valid layers automatically enable next',Results);
        var HasRemovedAction := False;
        for var Index := 0 to Editor.ComponentCount-1 do if Editor.Components[Index] is TButton then
          if MatchText(TButton(Editor.Components[Index]).Caption,['キャラを開く','キャラを保存','PSDの必須仕様を検査',
            'キャラ管理へ戻る','分離済み素材のmanifestを登録','外部PSDを参照登録','選択部位に透過PNGを追加']) then HasRemovedAction := True;
        Check(not HasRemovedAction,'editor header has no open manual save or inspection buttons',Results);
        TCheckBox(Editor.FindComponent('PsdPlay')).Checked := False;
        var View := Editor.Session.State; View.AutoBlink := False; View.HasPhoneme := False; View.Motion := 'none';
        View.Expression := ''; View.Gaze := 'front'; Editor.Session.SetView(View);
        var ViewRevision := Editor.Session.Revision; var SettingsBefore := Editor.Session.Character.Settings.ToJSON;
        var PreviewBefore := PreviewDigest(Editor.Session.Frame(0,960,540));
        var ClosedId := S(Obj(Obj(Editor.Session.Character.Settings,'animation'),'blink'),'closedPartId');
        var Tree := TTreeView(Editor.FindComponent('PsdLayerTree'));
        for var I := 0 to Tree.Items.Count-1 do if TArtLayer(Tree.Items[I].Data).Id=ClosedId then Tree.Selected := Tree.Items[I];
        var Deadline := GetTickCount64+1000; var Rendered: Boolean;
        var SelectedDigest := PreviewDigest(Editor.Session.Frame(0,960,540,ClosedId));
        repeat Application.ProcessMessages; Sleep(5); var D := Editor.Diagnostics;
          Rendered := (S(D,'previewLayerId')=ClosedId) and (S(D,'previewDigest')=SelectedDigest);
          D.Free;
        until Rendered or (GetTickCount64>Deadline);
        Check(Rendered and (PreviewDigest(Editor.Session.Frame(0,960,540,ClosedId))<>PreviewBefore),
          'hidden closed-eye selection changes actual preview pixels',Results);
        Check((Editor.Session.Revision=ViewRevision) and (Editor.Session.Character.Settings.ToJSON=SettingsBefore),
          'single layer selection preserves saved exclusive choices and revision',Results);
        CaptureUiWindow(Main,ResultPath,'.layer-selection');
        Next.Click;
        var D := Editor.Diagnostics;
        try Check((S(D,'previewLayerId')='') and (Editor.Session.State.Expression=View.Expression) and
          (Editor.Session.Character.Settings.ToJSON=SettingsBefore),'page navigation resets only temporary layer preview',Results);
        finally D.Free; end;
        Previous.Click;
        var Before := Editor.Diagnostics;
        try
          var A := Editor.Session.Status; try A.AddPair('expression','喜び'); var R := Editor.ExternalCommand('set-view',A); R.Free; finally A.Free; end;
          var After := Editor.Diagnostics;
          try Check(N(Before,'stageValidationChecks')=N(After,'stageValidationChecks'),'view-only changes do not repeat stage validation',Results); finally After.Free; end;
        finally Before.Free; end;
        Next.Click; Check((Pages.ActivePageIndex=1) and Next.Visible,'valid expressions blink and phonemes enable next',Results);
        Main.NavigateTo(apCharacters); List.OnDblClick(List);
        Check(Pages.ActivePageIndex=1,'registered character resumes its previous stage',Results);
        Next.Click; Check((Pages.ActivePageIndex=2) and Next.Visible,'valid motion reference enables next',Results);
        var Reference := TPsdMotionReferencePage(Editor.FindComponent('PsdMotionReferenceEditor'));
        TButton(Reference.FindComponent('MotionReferenceReset')).Click; Next.Click;
        Check((Pages.ActivePageIndex=2) and not Next.Visible,'partial motion reference prevents advancement',Results);
        Reference.ReloadCharacter(Editor.Session.Character,Editor.Session.Workspace);
        Check(Next.Visible,'restoring saved motion reference restores next',Results);
        Next.Click; Check((Pages.ActivePageIndex=3) and Next.Visible and (Next.Caption='保存') and
          (Previous.Left+Previous.Width<=Next.Left),'final stage changes next caption to save at right of back',Results);
        CaptureUiWindow(Main,ResultPath,'.final-save');
        TEdit(Editor.FindComponent('PsdCharacterName')).Text := '';
        Next.Click; Check((Main.CurrentPage=apCharacterEdit) and not Next.Visible,'invalid name prevents final save and keeps editor open',Results);
        TEdit(Editor.FindComponent('PsdCharacterName')).Text := '最終保存の確認';
        var BeforeSaveHash := THashSHA2.GetHashStringFromFile(TwinPath);
        var Guard := TFileStream.Create(TwinPath,fmOpenRead or fmShareDenyWrite);
        try
          Next.Click; Check((Main.CurrentPage=apCharacterEdit) and Editor.Session.Dirty and
            (THashSHA2.GetHashStringFromFile(TwinPath)=BeforeSaveHash),'failed final save keeps dirty editor and existing file intact',Results);
        finally Guard.Free; end;
        Next.Click;
        Check((Main.CurrentPage=apCharacters) and not Editor.Session.Dirty and CharacterReadyForNewScript(TwinPath,Reason),'successful final save returns to library with completed character',Results);
        Clone.Id := NewId; Clone.Production.Free; Clone.Production := ObjectText('{"stage":"draft","checked":false}');
        Clone.Settings.RemovePair('animation').Free; var MissingAnimation := SourceRoot.Resolve('missing-animation.psdchar',False); SaveCharacter(Clone,SourceRoot,MissingAnimation);
        Drop(Manager,MissingAnimation); List.OnDblClick(List); Next.Click;
        TToolButton(TToolBar(Editor.FindComponent('PsdStageToolbar')).FindComponent('PsdStage3')).Click;
        Check((Pages.ActivePageIndex=1) and not Next.Visible,'missing blink or phonemes blocks next and direct stage bypass',Results);
        Main.NavigateTo(apCharacters);
      finally Clone.Free; end;
      // 外部PSDは既存の参照専用規則で登録し、同名のPSDキャラと混同しない。
      var Complete := LoadCharacter(SourceRoot,FixturePath);
      try ExportPsd(Complete,SourceRoot,'reference.psd'); finally Complete.Free; end;
      var PsdPath := SourceRoot.Resolve('reference.psd'); var PsdHash := THashSHA2.GetHashStringFromFile(PsdPath);
      var BeforeCount := List.Items.Count; Drop(Manager,PsdPath); var ExternalPath := List.Selected.SubItems[1];
      var Imported := LoadCharacter(Editor.Session.Workspace,ExternalPath);
      try Check((List.Items.Count=BeforeCount+1) and (Imported.Policy='external'),'PSD file drop preserves external read-only policy and distinct format',Results); finally Imported.Free; end;
      Drop(Manager,PsdPath); Check((List.Items.Count=BeforeCount+1) and (List.Selected.SubItems[1]=ExternalPath),'same PSD source is not registered twice',Results);
      var Invalid := SourceRoot.Resolve('invalid.psd',False); TFile.WriteAllText(Invalid,'invalid image',TEncoding.UTF8);
      Drop(Manager,Invalid); Drop(Manager,SourceRoot.Resolve('unsupported.png',False));
      Check(List.Items.Count=BeforeCount+1,'invalid image and unsupported file drop leave library unchanged',Results);
      Check((THashSHA2.GetHashStringFromFile(FixturePath)=SourceHash) and (THashSHA2.GetHashStringFromFile(PsdPath)=PsdHash),'all drop sources remain unchanged',Results);
    finally SourceRoot.Free; end;
    VerifyRigmSelection(Main,Manager,List,TPath.Combine(ExtractFileDir(FixturePath),'fixture.rigm'),ResultPath,Results);
    Main.NavigateTo(apHome); TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
procedure VerifyUiResponsiveness(Main: TRigmWizardMainForm; const ResultPath: string);
const Expressions: array[0..2] of string = ('喜び','怒り','通常');
  procedure Capture(const Suffix: string);
  begin CaptureUiWindow(Main,ResultPath,Suffix); end;
  procedure Pump(Milliseconds: UInt64);
  begin
    var UntilTime := GetTickCount64+Milliseconds;
    repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=UntilTime;
  end;
begin
  var Owner := ObjectText(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned UI validation root required'); finally Owner.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show;
  ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update; Application.ProcessMessages;
  var Results := TJSONObject.Create;
  try
    var ExStyle := GetWindowLong(Main.Handle,GWL_EXSTYLE);
    var TaskbarWindow := Main.ShowInTaskBar and Application.MainFormOnTaskBar and (GetWindow(Main.Handle,GW_OWNER)=0) and
      ((ExStyle and WS_EX_APPWINDOW)<>0) and ((ExStyle and WS_EX_TOOLWINDOW)=0);
    var BigIcon := SendMessage(Main.Handle,WM_GETICON,ICON_BIG,0);
    var SmallIcon := SendMessage(Main.Handle,WM_GETICON,ICON_SMALL2,0);
    if not TaskbarWindow or (BigIcon=0) or (SmallIcon=0) then raise Exception.Create('Main form taskbar eligibility or window icon is missing');
    Results.AddPair('taskbarWindow',TJSONBool.Create(TaskbarWindow));
    Results.AddPair('taskbarIcons',TJSONBool.Create((BigIcon<>0) and (SmallIcon<>0)));
    var Started := GetTickCount64; Main.NavigateTo(apCharacters);
    Results.AddPair('libraryMs',TJSONNumber.Create(GetTickCount64-Started));
    var Manager := Main.PageInstance(apCharacters); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    for var Item in List.Items do if SameText(Item.SubItems[0],'PSD') then begin Item.Selected := True; Break; end;
    if List.Selected=nil then raise Exception.Create('PSD thumbnail fixture missing');
    Results.AddPair('thumbnailMode',TJSONBool.Create((List.ViewStyle=vsIcon) and (List.LargeImages<>nil) and (List.Selected.ImageIndex>=0)));
    Capture('.library');
    Started := GetTickCount64; List.OnDblClick(List);
    Results.AddPair('firstOpenMs',TJSONNumber.Create(GetTickCount64-Started));
    var Host := TRigmCharacterEditPage(Main.PageInstance(apCharacterEdit)); var Editor := Host.PsdEditor;
    if (Editor=nil) or (Editor.Session.Character=nil) then raise Exception.Create('PSD edit failed');
    if not Host.LoadPaintedBeforeActivation then raise Exception.Create('Loading screen was not painted before activation');
    Results.AddPair('loadingPaintedBeforeRead',TJSONBool.Create(Host.LoadPaintedBeforeActivation));
    Results.AddPair('loadingFeedbackMs',TJSONNumber.Create(Host.LoadFeedbackMs));
    Results.AddPair('opened',Editor.Diagnostics);
    var First := Editor.Diagnostics;
    try
      var Ready := N(First,'previewFrames')>0;
      if not Ready then raise Exception.Create('Initial editor opened without a prepared preview');
      Results.AddPair('firstFrameReadyBeforeEditor',TJSONBool.Create(Ready));
    finally First.Free; end;
    var Before := Editor.Diagnostics; Pump(1000); var After := Editor.Diagnostics;
    try Results.AddPair('animatedFrames',TJSONNumber.Create(N(After,'previewFrames')-N(Before,'previewFrames'))); finally Before.Free; After.Free; end;
    Capture('.editor');
    var Pages := TPageControl(Editor.FindComponent('PsdCharacterPages'));
    var Toolbar := TToolBar(Editor.FindComponent('PsdStageToolbar'));
    for var Index := 0 to 3 do if Pages.Pages[Index].TabVisible then raise Exception.Create('Text stage tabs remain visible');
    var Stage := TToolButton(Toolbar.FindComponent('PsdStage1')); Stage.Click;
    if (Toolbar.ShowCaptions) or (Pages.ActivePageIndex<>1) or not Stage.Down or
      (Stage.Hint<>'表情') then raise Exception.Create('Stage icon navigation failed');
    Results.AddPair('stageIcons',TJSONBool.Create(True));
    var Preview := TPsdPreviewControl(Editor.FindComponent('PsdPreviewSurface'));
    Results.AddPair('layoutChecks',TJSONNumber.Create(VerifyPreviewLayout(Main,Editor)));
    TToolButton(Toolbar.FindComponent('PsdStage0')).Click;
    var NameEdit := TEdit(Editor.FindComponent('PsdCharacterName')); NameEdit.SetFocus;
    var Revision := Editor.Session.Revision; var Cursor := Point(Preview.ClientWidth div 2+24,Preview.ClientHeight div 2);
    var OldRect := Preview.ImageRect; var U := (Cursor.X-OldRect.Left)/OldRect.Width; var V := (Cursor.Y-OldRect.Top)/OldRect.Height;
    var ScreenPoint := Preview.ClientToScreen(Cursor);
    Preview.Perform(WM_MOUSEWHEEL,MakeWParam(0,60),MakeLParam(ScreenPoint.X,ScreenPoint.Y));
    if Preview.Zoom<>1 then raise Exception.Create('Partial wheel input changed zoom too early');
    Preview.Perform(WM_MOUSEWHEEL,MakeWParam(0,60),MakeLParam(ScreenPoint.X,ScreenPoint.Y));
    var NewRect := Preview.ImageRect;
    if (Preview.Zoom<=1) or (Abs(U-(Cursor.X-NewRect.Left)/NewRect.Width)>0.01) or
      (Abs(V-(Cursor.Y-NewRect.Top)/NewRect.Height)>0.01) or (Main.ActiveControl<>NameEdit) then
      raise Exception.Create('Cursor-centred wheel zoom or setting focus failed');
    var PanBefore := Preview.Pan;
    Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Cursor.X,Cursor.Y));
    Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Cursor.X+42,Cursor.Y+28));
    Preview.Perform(WM_LBUTTONUP,0,MakeLParam(Cursor.X+42,Cursor.Y+28));
    if (Abs(Preview.Pan.X-PanBefore.X-42)>1) or (Abs(Preview.Pan.Y-PanBefore.Y-28)>1) or (GetCapture=Preview.Handle) then
      raise Exception.Create('Left drag did not slide or release the preview');
    var Zoom := Preview.Zoom; var Pan := Preview.Pan;
    TToolButton(Toolbar.FindComponent('PsdStage1')).Click;
    if (Preview.Zoom<>Zoom) or (Preview.Pan<>Pan) or (Editor.Session.Revision<>Revision) or Editor.Session.Dirty then
      raise Exception.Create('Stage change did not preserve display-only zoom and pan');
    Preview.WheelAt(360,Cursor); Pump(120); Capture('.zoom');
    Preview.WheelAt(2400,Cursor); Preview.WheelAt(2400,Cursor);
    if Preview.Zoom<>16 then raise Exception.Create('Zoom upper limit failed');
    for var Index := 0 to 3 do Preview.WheelAt(-2400,Cursor);
    if Preview.Zoom<>0.1 then raise Exception.Create('Zoom lower limit failed');
    TToolButton(Toolbar.FindComponent('PsdPreviewFit')).Click;
    if (Preview.Zoom<>1) or (Preview.Pan<>PointF(0,0)) then raise Exception.Create('Fit preview failed');
    Results.AddPair('wheelZoomAndLeftDrag',TJSONBool.Create(True));
    var Reference := TPsdMotionReferencePage(Editor.FindComponent('PsdMotionReferenceEditor'));
    TToolButton(Toolbar.FindComponent('PsdStage2')).Click; Capture('.bone');
    var ReferenceBefore := Reference.Reference.ToJSON; var RefPreview := Reference.Preview;
    Cursor := Point(RefPreview.ClientWidth div 2,RefPreview.ClientHeight div 2);
    RefPreview.WheelAt(240,Cursor);
    RefPreview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Cursor.X,Cursor.Y));
    RefPreview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Cursor.X+32,Cursor.Y+20));
    RefPreview.Perform(WM_LBUTTONUP,0,MakeLParam(Cursor.X+32,Cursor.Y+20));
    if Reference.HasDraft or (Reference.Reference.ToJSON<>ReferenceBefore) then raise Exception.Create('Reference drag changed a bone point');
    var R := RefPreview.ImageRect; var PX := R.Left+Round(R.Width*0.5); var PY := R.Top+Round(R.Height*0.4);
    TComboBox(Reference.FindComponent('MotionReferenceStep')).ItemIndex := 2;
    RefPreview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(PX,PY)); RefPreview.Perform(WM_LBUTTONUP,0,MakeLParam(PX,PY));
    var Neck := Obj(Reference.Reference,'neck');
    if not Reference.HasDraft or (Abs(N(Neck,'x')-Editor.Session.Character.Document.Width*0.5)>4) or
      (Abs(N(Neck,'y')-Editor.Session.Character.Document.Height*0.4)>4) then raise Exception.Create('Zoomed reference click did not use image coordinates');
    Reference.ReloadCharacter(Editor.Session.Character,Editor.Session.Workspace);
    Results.AddPair('referenceClickAndDrag',TJSONBool.Create(not Reference.HasDraft and (Reference.Reference.ToJSON=ReferenceBefore)));
    TToolButton(Toolbar.FindComponent('PsdStage3')).Click; Capture('.motion');
    TToolButton(Toolbar.FindComponent('PsdStage1')).Click;
    var Probe := TBitmap.Create;
    try
      Probe.SetSize(16,16); Probe.Canvas.Brush.Color := clFuchsia; Probe.Canvas.FillRect(Rect(0,0,16,16));
      var Retained := (Preview.Perform(WM_ERASEBKGND,Probe.Canvas.Handle,0)=1) and (Probe.Canvas.Pixels[0,0]=clFuchsia);
      if not Retained then raise Exception.Create('Preview background erase modifies visible pixels');
      Results.AddPair('previewRetainsFrameOnErase',TJSONBool.Create(Retained));
    finally Probe.Free; end;
    var Combo: TComboBox := nil;
    for var Index := 0 to Editor.ComponentCount-1 do if Editor.Components[Index] is TComboBox then begin
      var C := TComboBox(Editor.Components[Index]); if C.Items.IndexOf('喜び')>=0 then Combo := C;
    end;
    if Combo=nil then raise Exception.Create('Expression control missing');
    Before := Editor.Diagnostics; Started := GetTickCount64;
    for var Index := 0 to 2 do begin Combo.ItemIndex := Combo.Items.IndexOf(Expressions[Index]); Combo.OnChange(Combo); end;
    After := Editor.Diagnostics;
    try Results.AddPair('viewChangeMs',TJSONNumber.Create(GetTickCount64-Started)); Results.AddPair('viewUiBuilds',TJSONNumber.Create(N(After,'uiBuilds')-N(Before,'uiBuilds'))); finally Before.Free; After.Free; end;
    Main.SetBounds(40,40,1040,740); Pump(200);
    if Preview.PaintCount=0 then raise Exception.Create('Resized preview did not paint');
    Capture('.resized'); Main.SetBounds(40,40,1280,840);
    TCheckBox(Editor.FindComponent('PsdPlay')).Checked := False; Pump(100);
    Before := Editor.Diagnostics; Pump(500); After := Editor.Diagnostics;
    try Results.AddPair('pausedFrames',TJSONNumber.Create(N(After,'previewFrames')-N(Before,'previewFrames'))); finally Before.Free; After.Free; end;
    Main.NavigateTo(apHome); Before := Editor.Diagnostics; Pump(500); After := Editor.Diagnostics;
    try Results.AddPair('hiddenFrames',TJSONNumber.Create(N(After,'previewFrames')-N(Before,'previewFrames'))); finally Before.Free; After.Free; end;
    Started := GetTickCount64; TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click;
    List.OnDblClick(List);
    Results.AddPair('reopenMs',TJSONNumber.Create(GetTickCount64-Started));
    Results.AddPair('sameEditor',TJSONBool.Create(Host.PsdEditor=Editor)); Results.AddPair('final',Editor.Diagnostics);
    if Editor.Session.Dirty or (Screen.FormCount<>1) then raise Exception.Create('UI check changed character or form ownership');
    var PreviousId := Editor.Session.Character.Id; var PreviousPath := Editor.Session.SavedPath;
    var Rejected := False;
    try Main.NavigateTo(apCharacterEdit,TPath.Combine(Main.DataRoot,'Characters\missing.psdchar'));
    except on E: Exception do Rejected := True; end;
    var Retained := Rejected and (Editor.Session.Character.Id=PreviousId) and
      (Editor.Session.SavedPath=PreviousPath) and not Editor.Session.Dirty and
      not TPanel(Host.FindComponent('CharacterLoading')).Visible;
    if not Retained then raise Exception.Create('Failed loading did not restore the current editor');
    Results.AddPair('failedLoadRetainsEditor',TJSONBool.Create(Retained));
    Results.AddPair('loadingLifecycleChecks',TJSONNumber.Create(VerifyCharacterLoading(Host,procedure begin CaptureUiWindow(Main,ResultPath,'.loading'); end)));
    Main.NavigateTo(apScriptCreate); Application.ProcessMessages;
    var Creation := Main.PageInstance(apScriptCreate).FindComponent('MovieCreationPage');
    if Creation=nil then raise Exception.Create('Creation page missing');
    var Characters := TListView(TComponent(Creation).FindComponent('CreationCharacters'));
    Results.AddPair('creationThumbnailMode',TJSONBool.Create((Characters<>nil) and (Characters.ViewStyle=vsIcon) and (Characters.LargeImages<>nil) and Characters.Checkboxes));
    Capture('.creation'); Main.NavigateTo(apHome);
    TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Wizard validation failed: '+Text); Results.Add(Text); end;
begin
  var Owner := ObjectText(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned GUI validation root required'); finally Owner.Free; end;
  var Results := TJSONArray.Create;
  try
    Check((Main.CurrentPage=apHome) and (Main.CreatedPageCount=1) and (Main.PageInstance(apCharacterEdit)=nil),'startup creates only home',Results);
    Main.Position := poDesigned; Main.SetBounds(-1400,-1000,1280,840); Main.Show; Main.Update; Application.ProcessMessages;
    Check(Screen.FormCount=1,'one top-level form at startup',Results);
    TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click;
    Check((Main.CurrentPage=apCharacters) and (Main.CreatedPageCount=2),'first navigation creates only requested management frame',Results);
    var Manager := Main.PageInstance(apCharacters); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    Check((List.Items.Count>0) and (List.Selected<>nil),'registered character visible in management',Results);
    var Path := List.Selected.SubItems[1]; var OriginalHash := THashSHA2.GetHashStringFromFile(Path);
    List.OnDblClick(List);
    var EditHost := TRigmCharacterEditPage(Main.PageInstance(apCharacterEdit)); var Editor := EditHost.PsdEditor;
    Check((Main.CurrentPage=apCharacterEdit) and (Main.CreatedPageCount=3) and (Editor.Session.Character<>nil),'management opens editor frame in same form',Results);
    var Name := TEdit(Editor.FindComponent('PsdCharacterName')); Name.Text := Name.Text+'（保持する下書き）';
    var Draft := Name.Text; var Id := Editor.Session.Character.Id;
    var Pages := TPageControl(Editor.FindComponent('PsdCharacterPages')); Pages.ActivePageIndex := 2; Pages.OnChange(Pages);
    ClickReturn(Editor,mrNo);
    Check((Main.CurrentPage=apCharacters) and (Main.PageInstance(apCharacters)=Manager),'editor returns to existing management frame',Results);
    TButton(Main.FindComponent('WizardHome')).Click;
    TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click; List.OnDblClick(List);
    Check((Main.PageInstance(apCharacterEdit)=EditHost) and (EditHost.PsdEditor=Editor) and (Editor.Session.Character.Id=Id) and (Name.Text=Draft) and (Pages.ActivePageIndex=2),'home and same-character return preserve frame, identity, draft and page',Results);
    Check(THashSHA2.GetHashStringFromFile(Path)=OriginalHash,'navigation does not save unapplied draft',Results);
    var PresetName := TEdit(Editor.FindComponent('PsdExpressionName')); PresetName.Text := '部位選択の登録検証';
    Main.NavigateTo(apHome); Main.NavigateTo(apCharacterEdit);
    Check(PresetName.Text='部位選択の登録検証','expression registration input survives page navigation',Results);
    TButton(Editor.FindComponent('PsdExpressionRegister')).Click;
    Check((PsdJson.Obj(Editor.Session.Character.Settings,'expressions').GetValue('部位選択の登録検証')<>nil) and (PresetName.Text=''),'native expression registration creates a reusable preset',Results);
    Name.Text := Editor.Session.Character.Name; TButton(Editor.FindComponent('PsdInfoApply')).Click;
    Editor.VerifyPageFlow(ResultPath+'.pages.json');
    Check(Screen.FormCount=1,'PSD page workflow keeps one main form',Results);
    if SmokePath<>'' then Editor.CaptureSmoke(SmokePath);
    TButton(Main.FindComponent('WizardHome')).Click; TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.CurrentPage=apScripts) and (Main.CreatedPageCount=4),'script management lazily created',Results);
    var Scripts := Main.PageInstance(apScripts); TButton(Scripts.FindComponent('ScriptNew')).Click;
    Check((Main.CurrentPage=apScriptCreate) and (Main.CreatedPageCount=5),'script creation lazily creates existing creation UI',Results);
    var Creator := TRigmScriptCreatorFrame(Main.PageInstance(apScriptCreate)); var Script := TMemo(Creator.Creator.FindComponent('CreationScript'));
    Script.Text := 'フレーム移行の短い検証台本です。'; var ScriptDraft := Script.Text;
    TButton(Creator.FindComponent('CreationGoMovie')).Click;
    Check((Main.CurrentPage=apMovieEdit) and (Main.CreatedPageCount=6),'movie navigation lazily creates existing editor frame',Results);
    var MovieHost := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)); var Movie := MovieHost.CurrentEditor;
    Check((Movie.FindComponent('MovieMenuAction37')<>nil) and (Movie.FindComponent('MovieMenuAction39')<>nil),'frame exposes existing save-as and export menu operations',Results);
    Check(Movie.Session=Main.Workspace.ActiveSession,'creation and movie share the same session',Results);
    Main.NavigateTo(apScriptCreate); Check(Script.Text=ScriptDraft,'unapplied script draft retained across movie navigation',Results);
    Main.NavigateTo(apMovieEdit); Check(MovieHost.CurrentEditor=Movie,'movie editor reused after page return',Results);
    var Title := TEdit(Movie.FindComponent('MovieTitle')); Title.Text := '移行後の保存検証';
    Main.NavigateTo(apHome); Main.NavigateTo(apMovieEdit); Check(Title.Text='移行後の保存検証','movie input draft retained across home return',Results);
    Movie.InvokeAction(14);
    var A := TJSONObject.Create; var Session := Movie.Session;
    try A.AddPair('path',TPath.Combine(Main.DataRoot,'saved-frame-work.rigmovie')); A.AddPair('projectId',Session.Project.Id); RigmJson.AddN(A,'revision',Session.Project.Revision); var R := Session.Execute('save',A); R.Free;
    finally A.Free; end;
    Check(not Session.Project.Modified and FileExists(Session.Project.FileName),'existing session save writes movie project',Results);
    var SavedPath := Session.Project.FileName; Main.Workspace.OpenWork(SavedPath);
    Check((Main.Workspace.ActiveSession=Session) and (MovieHost.CurrentEditor=Movie),'reopening active saved work preserves existing editor',Results);
    TButton(Main.FindComponent('WizardHome')).Click;
    Check(Main.CurrentPage=apHome,'movie returns home through main navigation',Results);
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.PageInstance(apScripts)=Scripts) and (Main.CreatedPageCount=6) and (Screen.FormCount=1),'repeated navigation reuses owned frames without additional forms',Results);
    Main.NavigateTo(apCharacterEdit);
    EditHost.ActivateLegacyEditor;
    var Legacy := EditHost.LegacyEditor;
    Check((Legacy<>nil) and (Screen.FormCount=1),'legacy character editor created lazily in same form',Results);
    Legacy.OpenSample; var RigPath := TPath.Combine(Main.DataRoot,'RIGM\legacy-frame-fixture.rigm'); ForceDirectories(ExtractFileDir(RigPath)); Legacy.Editor.Save(RigPath);
    Check(Legacy.SaveCharacter and FileExists(RigPath),'legacy explicit save uses existing editor persistence',Results);
    Legacy.Editor.NewDocument('未保存の保持検証',256,320); var LegacyId := Legacy.Editor.Document.FileId;
    Main.NavigateTo(apHome); Main.NavigateTo(apCharacterEdit);
    Check((EditHost.LegacyEditor=Legacy) and (Legacy.Editor.Document.FileId=LegacyId) and Legacy.Editor.Modified,'legacy unsaved document survives home return',Results);
    Legacy.Editor.Save(RigPath); Legacy.OpenFile(RigPath);
    Check((Legacy.Editor.Document.Name='未保存の保持検証') and not Legacy.Editor.Modified,'legacy save and reopen retain document',Results);
    Check(Screen.FormCount=1,'all migrated pages retain a single main form',Results);
    TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
procedure VerifyScriptLayout(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Script layout validation failed: '+Text); Results.Add(Text); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptStage3.Validation.v1' then raise Exception.Create('Owned stage three root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
  Main.Update; Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace;
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    var Manager := Main.PageInstance(apScripts); var List := TListView(Manager.FindComponent('ScriptLibrary'));
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try
        W.OpenScriptDraft(JS(Resume,'path')); Main.NavigateTo(apScriptCreate);
        Check((W.ScriptDraft.Id=JS(Resume,'projectId')) and (JS(W.ScriptDraft.ScriptWizard,'stage')='layout'),
          'fresh process restores same UID and layout stage',Results);
      finally Resume.Free; end;
    end else begin
      TToolButton(TToolBar(Manager.FindComponent('ScriptLibraryToolbar')).FindComponent('ScriptNew')).Click;
    end;
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar'));
    var Save := TToolButton(Toolbar.FindComponent('ScriptSave')); var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    if not Reopen then begin
      Check(Creator.FindComponent('RigmScriptLayoutFrame')=nil,'layout page is not eagerly created',Results);
      TEdit(Creator.FindComponent('ScriptTitle')).Text := 'レイアウト構図の所有検証'; Save.Click; Next.Click;
      WaitThumbnailLibrary(W); Sleep(120); Application.ProcessMessages;
      var Characters := TListView(Creator.FindComponent('ScriptCharacters'));
      for var Item in Characters.Items do if JB(TJSONObject(Item.Data),'readyForScript') then Item.Checked := True;
      Application.ProcessMessages; Save.Click;
      Check((JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2) and Next.Visible and Next.Enabled,
        'confirmed multiple characters enable manual next',Results);
      Next.Click;
      Check((JS(W.ScriptDraft.ScriptWizard,'stage')='layout') and not Next.Visible,'manual next opens layout and stops at stage three',Results);
    end;
    var LayoutFrame: TRigmScriptLayoutFrame := nil;
    for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptLayoutFrame then LayoutFrame := TRigmScriptLayoutFrame(Creator.Components[I]);
    Check(LayoutFrame<>nil,'layout frame exists on first entry',Results);
    var Choice := TRadioGroup(LayoutFrame.FindComponent('ScriptLayoutChoices'));
    var Background := TComboBox(LayoutFrame.FindComponent('ScriptLayoutBackground'));
    if Reopen then begin
      Check((Choice.ItemIndex=0) and (Background.ItemIndex=2) and (JS(W.ScriptDraft.ScriptWizard,'layoutStatus')='complete') and
        (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2) and not W.ScriptDraft.Modified,
        'fresh process restores GUI choice background confirmation and selections',Results);
      Check((W.ScriptDraft.Layout='theme') and (W.ScriptDraft.BackgroundColor=LayoutBackgroundColor('blue')),
        'persisted movie model agrees with wizard layout',Results);
      WaitThumbnailLibrary(W); Application.ProcessMessages; CaptureUiWindow(Main,ResultPath,'.reopened');
    end else begin
      var Id := W.ScriptDraft.Id; var Path := W.ScriptDraft.FileName;
      var Selected := JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON;
      for var I := 0 to 2 do begin
        Choice.ItemIndex := I; Choice.OnClick(Choice); Application.ProcessMessages;
        Check((W.ScriptDraft.Id=Id) and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON=Selected),
          'layout switch '+I.ToString+' preserves UID and selected character metadata',Results);
        Check(Background.Enabled=(I=0),'background control follows common background '+I.ToString,Results);
        CaptureUiWindow(Main,ResultPath,'.layout'+I.ToString);
      end;
      Check((W.ScriptDraft.Layout='l') and (W.ScriptDraft.LDirection='right') and
        (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2),'reverse L accepts multiple characters',Results);
      var Left := MovieLayoutRegions('l','left'); var Right := MovieLayoutRegions('l','right');
      var FHD := ScaleLayoutRect(Left.Image,1920,1080); var HD := ScaleLayoutRect(Left.Image,1280,720);
      Check((FHD.Left=800) and (FHD.Right=1860) and (HD.Left=533) and (HD.Bottom=447) and
        (Abs(Left.Image.Left-(1-Right.Image.Right))<0.0001),'existing FHD layout scales by ratio and mirrors horizontally',Results);
      TToolButton(Toolbar.FindComponent('ScriptCharactersStage')).Click;
      Check((JS(W.ScriptDraft.ScriptWizard,'charactersStatus')='complete') and TListView(Creator.FindComponent('ScriptCharacters')).Showing,
        'back to character stage keeps confirmed selection',Results);
      TToolButton(Toolbar.FindComponent('ScriptLayoutStage')).Click;
      Check((Choice.ItemIndex=2) and (W.ScriptDraft.Id=Id),'returning to layout retains reverse L choice',Results);
      Save.Click;
      Check((JS(W.ScriptDraft.ScriptWizard,'layoutStatus')='complete') and not W.ScriptDraft.Modified,'human confirms layout without advancing',Results);
      TToolButton(Toolbar.FindComponent('ScriptReturn')).Click;
      for var Item in List.Items do if SameText(Item.SubItems[3],Path) then List.Selected := Item;
      Check((List.Selected<>nil) and (List.Selected.SubItems[0]='レイアウト：確認済み'),'library displays saved layout stage',Results);
      List.OnDblClick(List);
      Check((Choice.ItemIndex=2) and (W.ScriptDraft.Id=Id),'library reopens saved layout in same cached frame',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe');
      Check((Choice.ItemIndex=0) and (Background.ItemIndex=2) and (JS(W.ScriptDraft.ScriptWizard,'layoutStatus')='in-progress') and
        not W.ScriptDraft.Modified,'actual pipe change and save update same GUI without human confirmation',Results);
      Save.Click;
      var Resume := TJSONObject.Create;
      try Resume.AddPair('projectId',Id); Resume.AddPair('path',Path); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; end;
    end;
    Check((Screen.FormCount=1) and (W.Sessions.Count=0) and (Main.PageInstance(apMovieEdit)=nil) and
      (W.ScriptDraft.Characters.Count=0) and (W.ScriptDraft.Cues.Count=0) and (W.ScriptDraft.Scenes.Count=0),
      'no character placement voice script production or additional forms',Results);
    var State := W.ScriptStatus;
    try Check(not JB(State,'canAdvance'),'stage four is unavailable',Results); Report.AddPair('state',State); except State.Free; raise; end;
    var Output := ResultPath; if Reopen then Output := Output+'.reopened.json';
    TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
procedure VerifyScriptPlacement(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Script placement validation failed: '+Text); Results.Add(Text); end;
  function DragPoint(const R: TRect): TPoint;
  begin Result := Point((R.Left+R.Right) div 2,(R.Top+R.Bottom) div 2); end;
  procedure Mouse(Control: TControl; Message: Cardinal; const P: TPoint);
  begin Control.Perform(Message,MK_LBUTTON,NativeInt(Cardinal(P.X and $FFFF) or (Cardinal(P.Y and $FFFF) shl 16))); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptStage4.Validation.v1' then raise Exception.Create('Owned stage four root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    var Manager := Main.PageInstance(apScripts); var LibraryList := TListView(Manager.FindComponent('ScriptLibrary'));
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try W.OpenScriptDraft(JS(Resume,'path')); Main.NavigateTo(apScriptCreate);
        Check((W.ScriptDraft.Id=JS(Resume,'projectId')) and (W.CurrentScriptStage='placement'),'restart resumes last Next destination and same UID',Results);
      finally Resume.Free; end;
    end else TToolButton(TToolBar(Manager.FindComponent('ScriptLibraryToolbar')).FindComponent('ScriptNew')).Click;
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar'));
    var Title := TEdit(Creator.FindComponent('ScriptTitle')); var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    var Back := TToolButton(Toolbar.FindComponent('ScriptReturn')); var Path := W.ScriptDraft.FileName; var Id := W.ScriptDraft.Id;
    if not Reopen then begin
      Check(not Next.Enabled,'empty title cannot advance',Results);
      Title.Text := 'Next保存とキャラ配置の所有検証'; Check(Next.Enabled,'title input alone enables Next without Save confirmation',Results);
      Next.Click;
      var Saved := LoadMovie(Path);
      try Check((Saved.Id=Id) and (JS(Saved.ScriptWizard,'stage')='characters') and (Saved.Title=Title.Text) and not W.ScriptDraft.Modified,
        'title Next saves content and destination together',Results); finally Saved.Free; end;
      Check(W.CurrentScriptStage='characters','title Next displays characters only after save',Results);
      Back.Click; W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
      Check(W.CurrentScriptStage='characters','exit and reopen resumes character destination',Results);
      WaitThumbnailLibrary(W); Sleep(120); Application.ProcessMessages;
      var Characters := TListView(Creator.FindComponent('ScriptCharacters'));
      for var Item in Characters.Items do if JB(TJSONObject(Item.Data),'readyForScript') then Item.Checked := True;
      Check((JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2) and Next.Enabled,'multiple character selection needs no separate Save',Results);
      var Hash := THashSHA2.GetHashStringFromFile(Path); var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try Next.Click;
        Check((W.CurrentScriptStage='characters') and Characters.Showing and W.ScriptDraft.Modified and
          (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2) and (THashSHA2.GetHashStringFromFile(Path)=Hash),
          'failed Next retains source stage input and disk project',Results);
      finally Guard.Free; end;
      Next.Click; Saved := LoadMovie(Path);
      try Check((JS(Saved.ScriptWizard,'stage')='layout') and (JA(Saved.ScriptWizard,'selectedCharacters').Count=2),
        'character Next persists layout destination with selection',Results); finally Saved.Free; end;
      TToolButton(Toolbar.FindComponent('ScriptTitleStage')).Click; Title.Text := '戻った題名の下書きを保全'; Back.Click;
      W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
      Check((W.CurrentScriptStage='layout') and (JS(W.ScriptDraft.ScriptWizard,'titleInput')='戻った題名の下書きを保全'),
        'backward draft saves preserve edits and last Next resume destination',Results);
      Next.Click; Check((W.CurrentScriptStage='placement') and not Next.Visible and not W.ScriptDraft.Modified,
        'layout Next saves and displays placement with stage five unavailable',Results);
    end;
    var Frame: TRigmScriptPlacementFrame := nil;
    for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptPlacementFrame then Frame := TRigmScriptPlacementFrame(Creator.Components[I]);
    Check((Frame<>nil) and Frame.Showing,'placement uses lazy frame within main form',Results);
    var Preview := Frame.Preview; var List := TListView(Frame.FindComponent('ScriptPlacementCharacters'));
    WaitThumbnailLibrary(W); Sleep(120); Application.ProcessMessages;
    var First := JS(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters')[0]),'path');
    if Reopen then begin
      Check((JA(W.ScriptDraft.ScriptWizard,'placements').Count=2) and (List.Items.Count=2) and (List.Items[0].ImageIndex>=0),
        'restart restores multiple format-neutral placements and cached list images',Results);
      Check(JB(Placement(W.ScriptDraft,First),'flipX'),'restart restores common horizontal reflection',Results);
      Check((W.ScriptDraft.Layout='l') and (W.ScriptDraft.LDirection='left'),'restart restores selected L guide',Results);
      CaptureUiWindow(Main,ResultPath,'.reopened');
    end else begin
      Check((JA(W.ScriptDraft.ScriptWizard,'placements').Count=2) and (List.Items.Count=2) and (List.Items[0].ImageIndex>=0),
        'PSD and RIGM placements use existing shared thumbnail cache',Results);
      W.SelectScriptPlacement(First); var O := TJSONObject.Create;
      try O.AddPair('path',First); AddN(O,'x',200/1920); AddN(O,'y',200/1080); AddN(O,'width',200/1920); AddN(O,'height',500/1080); W.SetScriptPlacement(O); finally O.Free; end;
      var Start := DragPoint(Preview.CharacterBounds(First)); Mouse(Preview,WM_LBUTTONDOWN,Start);
      Check(Preview.Dragging and W.PlacementEditing,'GUI drag obtains shared edit guard',Results);
      Mouse(Preview,WM_MOUSEMOVE,Point(Start.X+20,Start.Y+10)); CaptureUiWindow(Main,ResultPath,'.drag');
      Mouse(Preview,WM_LBUTTONUP,Point(Start.X+20,Start.Y+10)); var B := PlacementRect(Placement(W.ScriptDraft,First));
      Check(not Preview.Dragging and not W.PlacementEditing and (Abs(B.Left/10-Round(B.Left/10))<0.001) and
        (Abs(B.Width-200)<0.01) and (Abs(B.Left-200)>5),'move snaps in FullHD coordinates and preserves size',Results);
      for var I := 0 to 7 do begin
        var Before := PlacementRect(Placement(W.ScriptDraft,First)); Start := DragPoint(Preview.HandleRect(I));
        Mouse(Preview,WM_LBUTTONDOWN,Start); Mouse(Preview,WM_MOUSEMOVE,Point(Start.X+5,Start.Y+5)); Mouse(Preview,WM_LBUTTONUP,Point(Start.X+5,Start.Y+5));
        B := PlacementRect(Placement(W.ScriptDraft,First));
        Check((Abs(B.Width/B.Height-Before.Width/Before.Height)<0.0001) and ((Abs(B.Width-Before.Width)>0.1) or (Abs(B.Height-Before.Height)>0.1)),
          'handle '+I.ToString+' resizes while preserving aspect ratio',Results);
      end;
      var Flip := TCheckBox(Frame.FindComponent('ScriptPlacementFlip')); Flip.Checked := True; Application.ProcessMessages;
      Check(JB(Placement(W.ScriptDraft,First),'flipX'),'horizontal reflection is common saved display state',Results);
      var StoredRect := Placement(W.ScriptDraft,First).ToJSON; Main.SetBounds(40,40,1460,900); Application.ProcessMessages;
      var Center := DragPoint(Preview.CharacterBounds(First)); var BasePoint := Preview.ScreenToBase(Center.X,Center.Y);
      B := PlacementRect(Placement(W.ScriptDraft,First));
      Check((Abs(BasePoint.X-(B.Left+B.Right)/2)<4) and (Abs(BasePoint.Y-(B.Top+B.Bottom)/2)<4) and
        (Placement(W.ScriptDraft,First).ToJSON=StoredRect),'preview resize changes display only and maps back to FullHD coordinates',Results);
      Main.SetBounds(40,40,1280,840); Application.ProcessMessages;
      CaptureUiWindow(Main,ResultPath,'.placement');
      TToolButton(Toolbar.FindComponent('ScriptLayoutStage')).Click;
      var LayoutFrame: TRigmScriptLayoutFrame := nil;
      for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptLayoutFrame then LayoutFrame := TRigmScriptLayoutFrame(Creator.Components[I]);
      var Choice := TRadioGroup(LayoutFrame.FindComponent('ScriptLayoutChoices')); Choice.ItemIndex := 1; Choice.OnClick(Choice);
      CaptureUiWindow(Main,ResultPath,'.pipe-next');
      Check((W.CurrentScriptStage='placement') and (W.ScriptDraft.Id=Id) and not W.ScriptDraft.Modified,
        'actual pipe Next saves layout and destination then changes GUI',Results);
      var Area := PlacementArea(W.ScriptDraft); B := PlacementRect(Placement(W.ScriptDraft,First));
      Check((JA(W.ScriptDraft.ScriptWizard,'placements').Count=2) and (B.Left>=Area.Left-0.01) and (B.Right<=Area.Right+0.01),
        'L layout retains multiple placements and fits them to character guide',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe-placement');
      Check((JS(W.ScriptDraft.ScriptWizard,'placementSelected')=First) and JB(Placement(W.ScriptDraft,First),'flipX') and
        not W.ScriptDraft.Modified and Flip.Checked,'actual pipe placement updates selection and visible controls',Results);
      Check((List.Selected<>nil) and SameText(List.Selected.SubItems[0],First) and
        (Abs(JN(Placement(W.ScriptDraft,First),'x')-0.1)<0.0001) and
        (Pos('324',TLabel(Frame.FindComponent('ScriptPlacementBounds')).Caption)>0),'pipe coordinates update bounds readout and selected list row',Results);
      Start := DragPoint(Preview.CharacterBounds(First)); Mouse(Preview,WM_LBUTTONDOWN,Start); Mouse(Preview,WM_MOUSEMOVE,Point(Start.X-2000,Start.Y-2000));
      Mouse(Preview,WM_LBUTTONUP,Point(Start.X-2000,Start.Y-2000)); B := PlacementRect(Placement(W.ScriptDraft,First));
      Check((B.Left>=Area.Left-0.01) and (B.Top>=Area.Top-0.01),'drag is clamped to L character area',Results);
      TToolButton(Toolbar.FindComponent('ScriptCharactersStage')).Click; Back.Click;
      W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
      Check((W.CurrentScriptStage='placement') and Frame.Showing,'back and exit resume last Next placement destination',Results);
      var CanClose := True; Main.OnCloseQuery(Main,CanClose); Check(CanClose,'close saves current draft',Results);
      var Resume := TJSONObject.Create; try Resume.AddPair('projectId',Id); Resume.AddPair('path',Path); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; end;
    end;
    Check((Screen.FormCount=1) and (W.Sessions.Count=0) and (Main.PageInstance(apMovieEdit)=nil) and
      (W.ScriptDraft.Characters.Count=0) and (W.ScriptDraft.Cues.Count=0) and (W.ScriptDraft.Scenes.Count=0),
      'placement creates no old movie sessions voice script or production',Results);
    var State := W.ScriptStatus; Check(not JB(State,'canAdvance'),'unimplemented script input remains blocked',Results); Report.AddPair('state',State);
    var Output := ResultPath; if Reopen then Output := Output+'.reopened.json'; TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
{$I RigmScriptTextValidation.inc}
{$I RigmScriptReviewValidation.inc}
{$I RigmScriptCastingValidation.inc}
{$I RigmScriptSubtitleValidation.inc}
end.
