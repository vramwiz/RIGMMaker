unit RigmWizardValidation;
interface
uses RigmWizardMainForm;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
procedure VerifyUiResponsiveness(Main: TRigmWizardMainForm; const ResultPath: string);
procedure VerifyCharacterCreate(Main: TRigmWizardMainForm; const ResultPath: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, System.UITypes,
  RigmPageNavigation, PsdStudioFrame, PsdJson, RigmCharacterEditPage,
  RigmScriptCreatorFrame, RigmMovieWorkspaceFrame, RigmJson, Winapi.Windows, Winapi.Messages,
  PsdPreviewControl, PsdSettingsPanel, PsdMotionReferenceForm, Vcl.Graphics, Vcl.Imaging.pngimage,
  PsdSession, PsdProduction, RigmCharacterCatalog, RigmCharacterManagerFrame, PsdWorkspace,
  PsdPackage, RigmLegacyEditorFrame, Winapi.ShellAPI, Winapi.ShlObj, System.StrUtils, ArtLayerList, RigmModel, ArtDocument;
type
  TReturnDialogAnswer = class
  public
    Answer: Integer; Seen: Boolean;
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
    var Deadline := GetTickCount64+15000;
    repeat
      Application.ProcessMessages; Sleep(10);
      if FileExists(ResultPath+'.capture-ack.txt') then try
        if TFile.ReadAllText(ResultPath+'.capture-ack.txt',TEncoding.UTF8).Trim=Token then Exit;
      except on E: EOSError do
        if not (E.ErrorCode in [ERROR_FILE_NOT_FOUND,ERROR_ACCESS_DENIED,ERROR_SHARING_VIOLATION]) then raise;
      end;
    until GetTickCount64>Deadline;
    raise Exception.Create('Owned native capture timed out');
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
end.
