unit RigmWizardValidation;
interface
uses RigmWizardMainForm;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
procedure VerifyUiResponsiveness(Main: TRigmWizardMainForm; const ResultPath: string);
procedure VerifyCharacterCreate(Main: TRigmWizardMainForm; const ResultPath: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  RigmPageNavigation, PsdStudioFrame, PsdJson, RigmCharacterEditPage,
  RigmScriptCreatorFrame, RigmMovieWorkspaceFrame, RigmJson, Winapi.Windows, Winapi.Messages,
  PsdPreviewControl, PsdSettingsPanel, PsdMotionReferenceForm, Vcl.Graphics, Vcl.Imaging.pngimage,
  PsdSession, PsdProduction, RigmCharacterCatalog;
type
  // 実際の読込通知をホストへ転送し、その前後の可視性と初回フレームを検査する。
  TCharacterLoadingProbe = class
  public
    Host: TRigmCharacterEditPage; Editor: TPsdStudioFrame;
    Forward: TPsdCharacterLoadEvent; OnVisible: TProc;
    ExpectFrame: Boolean; FramesBefore: Double; Starts,Finishes: Integer;
    procedure LoadingChanged(Sender: TObject; const Path: string; Loading: Boolean);
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
procedure VerifyCharacterCreate(Main: TRigmWizardMainForm; const ResultPath: string);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Character create validation failed: '+Text); Results.Add(Text); end;
begin
  var Owner := ObjectText(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned GUI validation root required'); finally Owner.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; Main.Update; Application.ProcessMessages;
  var Results := TJSONArray.Create;
  try
    Main.NavigateTo(apCharacters);
    var Manager := Main.PageInstance(apCharacters); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    var NewButton := TButton(Manager.FindComponent('CharacterNew'));
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
    Check((Previous.Align=alLeft) and (Next.Align=alRight) and (Previous.Left+Previous.Width<=Next.Left),'back is left and next is right',Results);
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
    TButton(Editor.FindComponent('PsdReturnToManagement')).Click;
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
    TButton(Editor.FindComponent('PsdReturnToManagement')).Click;
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
    TToolButton(TToolBar(EditHost.FindComponent('CharacterEditorToolbar')).FindComponent('CharacterLegacyEditor')).Click;
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
