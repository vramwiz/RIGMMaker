unit RigmEditorForm;

interface
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Menus, RigmModel, RigmEditor, RigmValidation, RigmPipe, ArtDocument, ArtLayerList,
  SwitchProInput, RigmGamepadPreview, RigmPropertyScrollBox, RigmIconToolbar;

type
  TRigmPreviewPaintBox = class(TPaintBox)
  public
    property MouseCapture;
  end;

  TRigmEditorForm = class(TForm)
  private
    FEditor: TRigmEditor;
    FMovieForm: TForm;
    FPipe: TRigmPipeHub;
    FPages: array[TRigmPage] of TToolButton;
    FHeaderBar, FToolbar: TRigmIconToolbar;
    FRight, FBottom: TPanel;
    FPaint: TRigmPreviewPaintBox;
    FLayerList: TArtLayerList;
    FObjectList: TListBox;
    FProperties: TScrollBox;
    FFields: TDictionary<string, TControl>;
    FUsedProperties: TDictionary<TControl, Boolean>;
    FPropertiesUpdating, FPropertyLayoutReady: Boolean;
    FPropertySchema: Integer;
    FPropertyDocument: TRigmDocument;
    FPropertyFileId, FPropertySelectedId, FViewState: string;
    FPropertyRevision: UInt64;
    FLog: TMemo;
    FIssueList: TListBox;
    FIssues: TRigmIssues;
    FStatus, FPsdHint: TLabel;
    FBitmap, FPreviewBuffer: TBitmap;
    FPreviewDirty: Boolean;
    FPreviewRenderCount, FPropertyBuildCount: UInt64;
    FPreviewMode, FDirect, FShowBones, FShowMeshes, FUpdating, FShowReference: Boolean;
    FPropertyY, FVertex: Integer;
    FDragging: Boolean;
    FDragPoint, FDragStart, FDragOrigin: TPointF;
    FDragId: string;
    FDragRevision: UInt64;
    FPopup, FIssuePopup: TPopupMenu;
    FTimer: TTimer;
    FGamepad: string;
    FGamepadInput: TSwitchProInput;
    FGamepadPreview: TRigmGamepadPreview;
    FGamepadEnabled, FGamepadWasConnected: Boolean;
    FUIPage: TRigmPage;
    FOnSaved: TNotifyEvent;
    procedure BuildUI;
    procedure RefreshView(Sender: TObject);
    procedure RefreshStatus;
    procedure RefreshToolbars;
    procedure RefreshLayerGuide;
    function CanSelectPage(Page: TRigmPage): Boolean;
    function AdvanceStage: Boolean;
    procedure BuildProperties;
    procedure RefreshPreview;
    procedure RenderPreview;
    procedure PreviewResize(Sender: TObject);
    procedure RefreshParameterLabel(Track: TTrackBar);
    procedure PaintPreview(Sender: TObject);
    procedure PageClick(Sender: TObject);
    procedure ToolbarClick(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure LayerRename(Sender: TObject; Layer: TArtLayer; const Name: string);
    procedure LayerAttributes(Sender: TObject; Layer: TArtLayer; Visible: Boolean; Opacity: Byte);
    procedure ApplyProperties(Sender: TObject);
    procedure ParameterChanged(Sender: TObject);
    procedure VertexChanged(Sender: TObject);
    procedure IssueFocus(Sender: TObject);
    procedure IssueAction(Sender: TObject);
    procedure PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TimerTick(Sender: TObject);
    procedure GamepadOptionsChanged(Sender: TObject);
    procedure StopGamepadInput(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure Closed(Sender: TObject; var Action: TCloseAction);
    function Execute(const Command: string; Args: TJSONObject): Boolean;
    function PreviewRect: TRect;
    function ToWorld(X, Y: Integer): TPointF;
    function ToScreen(X, Y: Double): TPoint;
    function FieldText(const Key: string): string;
    function FieldNumber(const Key: string): Double;
    function FieldChecked(const Key: string): Boolean;
    function ComboId(const Key: string; Bone: Boolean): string;
    function AddButton(Parent: TWinControl; const Caption, Name: string; Tag: Integer; X, Y, Width: Integer): TButton;
    function AddEdit(const Key, Caption, Value: string; ReadOnly: Boolean = False;
      X: Integer = 12; EditWidth: Integer = 328): TEdit;
    function AddNumber(const Key, Caption: string; Value: Double; Minimum, Maximum: Integer): TEdit;
    function AddCheck(const Key, Caption: string; Value: Boolean): TCheckBox;
    function AddCombo(const Key, Caption: string): TComboBox;
    procedure AddBoneCombo(const Key, Caption, Selected: string);
    procedure AddPartCombo(const Key, Caption, Selected: string; GroupsOnly: Boolean = False);
    procedure NumberChanged(Sender: TObject);
    function PropertyControl(const Name: string; ControlClass: TControlClass): TControl;
    procedure PlaceProperty(Control: TControl; X, Y, Width, Height: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FileName: string);
    procedure NewCharacter(const Name, FileName: string);
    procedure OpenSample;
    function OpenSeparatedPsd(const FileName: string): TRigmEditorForm;
    function SaveCharacter: Boolean;
    procedure ShowMovieStudio(Sender: TObject);
    property Editor: TRigmEditor read FEditor;
    property OnSaved: TNotifyEvent read FOnSaved write FOnSaved;
    property PreviewRenderCount: UInt64 read FPreviewRenderCount;
    property PropertyBuildCount: UInt64 read FPropertyBuildCount;
  end;

implementation
uses System.Math, System.StrUtils, System.IOUtils, System.UITypes, Winapi.Windows,
  Vcl.Dialogs, RigmJson, RigmRenderer, RigmSample, GamepadState, RigmToolbarIcons, RigmMovieForm;

const
  acSave = 1; acSaveAs = 2; acUndo = 3; acRedo = 4; acPng = 5; acPsd = 6;
  acGroup = 7; acComplete = 8; acMode = 9; acAddBone = 10; acHideBone = 11;
  acRestoreBone = 12; acResetBone = 13; acGenerate = 14; acAddVertex = 15;
  acDeleteVertex = 16; acResetPose = 17; acBones = 18; acMeshes = 19;
  acDirect = 20; acLayerUp = 21; acLayerDown = 22; acDeleteLayer = 23;
  acReference = 24; acTriangles = 25; acReplace = 27; acClassify = 28;
  acMovie = 29;

constructor TRigmEditorForm.Create(AOwner: TComponent);
begin
  inherited CreateScaledNew(AOwner,96);
  var TargetPPI := Monitor.PixelsPerInch;
  Name := 'RigmEditorWindow' + IntToHex(NativeUInt(Self), SizeOf(Pointer) * 2);
  Caption := 'RIGM Maker — 編集';
  Width := 1280; Height := 880; Constraints.MinWidth := 1000; Constraints.MinHeight := 700;
  Position := poScreenCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 10; DoubleBuffered := True;
  FEditor := TRigmEditor.Create; FBitmap := Vcl.Graphics.TBitmap.Create;
  FPreviewBuffer := Vcl.Graphics.TBitmap.Create; FPreviewBuffer.PixelFormat := pf32bit;
  FFields := TDictionary<string, TControl>.Create; FIssues := TRigmIssues.Create(True);
  FUsedProperties := TDictionary<TControl, Boolean>.Create;
  FGamepadInput := TSwitchProInput.Create; FGamepadPreview := TRigmGamepadPreview.Create;
  FShowBones := True; FShowMeshes := True; FVertex := -1;
  BuildUI; ScaleForPPI(TargetPPI);
  FEditor.OnChanged := RefreshView; FEditor.OnMovieOpen := ShowMovieStudio; OnCloseQuery := Closing; OnClose := Closed;
  OnDeactivate := StopGamepadInput; OnHide := StopGamepadInput;
  var PipeDirectory := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RIGMMaker\pipes');
  for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--pipe-dir=') then PipeDirectory := ExpandFileName(ParamStr(I).Substring(11));
  try FPipe := TRigmPipeHub.Create(FEditor, PipeDirectory);
  except on E: Exception do FEditor.AiLog.Add('パイプ開始に失敗: ' + E.Message); end;
  RefreshView(Self);
end;

destructor TRigmEditorForm.Destroy;
begin
  FMovieForm.Free;
  OnDeactivate := nil; OnHide := nil;
  if FTimer <> nil then FTimer.Enabled := False;
  StopGamepadInput(Self); FGamepadPreview.Free; FGamepadInput.Free;
  FPipe.Free;
  if FEditor <> nil then FEditor.OnChanged := nil;
  if FLayerList <> nil then begin FLayerList.OnSelect := nil; FLayerList.SetRoots(nil); end;
  FUsedProperties.Free; FFields.Free; FIssues.Free; FPreviewBuffer.Free; FBitmap.Free; FEditor.Free; inherited;
end;

function TRigmEditorForm.AddButton(Parent: TWinControl; const Caption, Name: string; Tag, X, Y, Width: Integer): TButton;
begin
  if Parent = FProperties then begin
    Result := TButton(PropertyControl(Name, TButton));
    Result.Caption := Caption; Result.Tag := Tag;
    PlaceProperty(Result, X, Y, Width, 30); Result.OnClick := ToolbarClick;
    Exit;
  end;
  Result := TButton.Create(Self); Result.Parent := Parent; Result.Caption := Caption; Result.Name := Name;
  Result.Tag := Tag; Result.SetBounds(X, Y, Width, 30); Result.OnClick := ToolbarClick;
end;

procedure TRigmEditorForm.BuildUI;
var Center, BottomBar: TPanel; Page: TRigmPage; Button: TButton; Item: TMenuItem;
const PageCaptions: array[TRigmPage] of string = ('1  レイヤー', '2  ボーン', '3  メッシュ', '4  プレビュー');
      IssueCaptions: array[0..3] of string = ('自動修正', 'AIに修正依頼', '詳細 / 対象へ移動', '警告を無視');
begin
  FHeaderBar := TRigmIconToolbar.Create(Self); FHeaderBar.Name := 'EditorToolbar';
  FHeaderBar.Parent := Self; FHeaderBar.Align := alTop;
  for Page := Low(TRigmPage) to High(TRigmPage) do begin
    FPages[Page] := FHeaderBar.AddIcon('Page' + IntToStr(Ord(Page)), PageCaptions[Page],
      TRigmToolbarIcon(Ord(Page)), Ord(Page), PageClick, True);
  end;
  FHeaderBar.AddSeparator;
  FHeaderBar.AddIcon('CompleteStageButton', '工程を自動検証して次へ進む', riComplete, acComplete, ToolbarClick);
  FHeaderBar.AddIcon('SaveCharacterButton', '保存', riSave, acSave, ToolbarClick);
  FHeaderBar.AddIcon('SaveAsCharacterButton', '名前を付けて保存', riSaveAs, acSaveAs, ToolbarClick);
  FHeaderBar.AddSeparator;
  FHeaderBar.AddIcon('UndoButton', '元に戻す', riUndo, acUndo, ToolbarClick);
  FHeaderBar.AddIcon('RedoButton', 'やり直す', riRedo, acRedo, ToolbarClick);
  FHeaderBar.AddIcon('ResetPoseButton', '初期ポーズに戻す', riReset, acResetPose, ToolbarClick);
  FHeaderBar.AddIcon('EditModeButton', '編集 / プレビュー', riEditPreview, acMode, ToolbarClick, True);
  FHeaderBar.AddIcon('DirectModeButton', 'パラメータ / 直接操作', riDirect, acDirect, ToolbarClick, True);
  FHeaderBar.AddIcon('BoneOverlayButton', 'ボーン表示', riBoneOverlay, acBones, ToolbarClick, True);
  FHeaderBar.AddIcon('MeshOverlayButton', 'メッシュ表示', riMeshOverlay, acMeshes, ToolbarClick, True);
  FHeaderBar.AddIcon('MovieStudioButton', '台本から動画を制作', riPreview, acMovie, ToolbarClick);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Name := 'PageToolbar';
  FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Top := FHeaderBar.Height;
  FToolbar.AddIcon('ImportPngButton', 'PNGパーツ追加', riPng, acPng, ToolbarClick);
  FToolbar.AddIcon('ImportPsdButton', '分解済みPSDを読込', riPsd, acPsd, ToolbarClick);
  FToolbar.AddIcon('AddGroupButton', 'グループ追加', riGroup, acGroup, ToolbarClick);
  FToolbar.AddIcon('ReferenceButton', '元画像を表示（任意の比較）', riReference, acReference, ToolbarClick, True);
  FToolbar.AddIcon('ClassifyLayersButton', '未分類を再判定', riClassify, acClassify, ToolbarClick);
  FToolbar.AddIcon('ToolbarLayerUp', '選択レイヤーを上へ', riUp, acLayerUp, ToolbarClick);
  FToolbar.AddIcon('ToolbarLayerDown', '選択レイヤーを下へ', riDown, acLayerDown, ToolbarClick);
  FToolbar.AddIcon('ToolbarReplacePng', '選択パーツのPNGを置換', riPng, acReplace, ToolbarClick);
  FToolbar.AddIcon('ToolbarDeleteLayer', '選択レイヤーを削除', riDelete, acDeleteLayer, ToolbarClick);
  FToolbar.AddIcon('AddBoneButton', 'ボーン追加 / 子を復活', riAddBone, acRestoreBone, ToolbarClick);
  FToolbar.AddIcon('HideBoneButton', '子ボーンと一緒に非表示', riHideBone, acHideBone, ToolbarClick);
  FToolbar.AddIcon('ResetBoneButton', 'ボーンを初期位置へ', riResetBone, acResetBone, ToolbarClick);
  FToolbar.AddIcon('GenerateMeshesButton', '全パーツにメッシュ生成', riGenerate, acGenerate, ToolbarClick);
  FToolbar.AddIcon('AddVertexButton', '頂点追加（面を分割）', riAddVertex, acAddVertex, ToolbarClick);
  FToolbar.AddIcon('DeleteVertexButton', '選択頂点を削除', riDeleteVertex, acDeleteVertex, ToolbarClick);
  FPsdHint := TLabel.Create(Self); FPsdHint.Parent := Self; FPsdHint.Align := alTop;
  FPsdHint.Name := 'PsdImportHint'; FPsdHint.AutoSize := True; FPsdHint.Height := 52;
  FPsdHint.WordWrap := True; FPsdHint.Layout := tlCenter;
  FPsdHint.AlignWithMargins := True; FPsdHint.Margins.SetBounds(12, 4, 12, 4);
  FBottom := TPanel.Create(Self); FBottom.Parent := Self; FBottom.Align := alBottom; FBottom.Height := 176; FBottom.BevelOuter := bvNone;
  BottomBar := TPanel.Create(Self); BottomBar.Parent := FBottom; BottomBar.Align := alTop; BottomBar.Height := 32; BottomBar.BevelOuter := bvNone;
  Button := TButton.Create(Self); Button.Parent := BottomBar; Button.Caption := 'AIログ'; Button.SetBounds(12, 2, 84, 28);
  Button.Tag := 100; Button.OnClick := IssueAction;
  Button := TButton.Create(Self); Button.Parent := BottomBar; Button.Caption := '異常リスト'; Button.SetBounds(104, 2, 100, 28);
  Button.Tag := 101; Button.OnClick := IssueAction;
  FLog := TMemo.Create(Self); FLog.Parent := FBottom; FLog.Align := alClient; FLog.ReadOnly := True; FLog.ScrollBars := ssVertical;
  FIssueList := TListBox.Create(Self); FIssueList.Parent := FBottom; FIssueList.Align := alClient; FIssueList.OnDblClick := IssueFocus;
  FIssueList.Name := 'ValidationIssues';
  FIssuePopup := TPopupMenu.Create(Self);
  for var I := 0 to 3 do begin
    Item := TMenuItem.Create(Self); Item.Caption := IssueCaptions[I];
    Item.Tag := I; Item.OnClick := IssueAction; FIssuePopup.Items.Add(Item);
  end;
  FIssueList.PopupMenu := FIssuePopup;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 25; FStatus.Layout := tlCenter;
  Center := TPanel.Create(Self); Center.Parent := Self; Center.Align := alClient; Center.BevelOuter := bvNone;
  Center.DoubleBuffered := True; Center.ParentBackground := False;
  FRight := TPanel.Create(Self); FRight.Parent := Center; FRight.Align := alRight; FRight.Width := 380; FRight.BevelOuter := bvNone;
  FLayerList := TArtLayerList.Create(Self); FLayerList.Parent := FRight; FLayerList.Align := alTop; FLayerList.Height := 225;
  FLayerList.Name := 'LayerList'; FLayerList.OnSelect := SelectionChanged; FLayerList.OnRename := LayerRename; FLayerList.OnAttributes := LayerAttributes;
  FObjectList := TListBox.Create(Self); FObjectList.Parent := FRight; FObjectList.Align := alTop; FObjectList.Height := 175;
  FObjectList.Name := 'BoneMeshList'; FObjectList.OnClick := SelectionChanged;
  FProperties := TRigmPropertyScrollBox.Create(Self); FProperties.Parent := FRight; FProperties.Align := alClient;
  FProperties.Name := 'PropertyScrollBox'; FProperties.HorzScrollBar.Visible := False;
  FPaint := TRigmPreviewPaintBox.Create(Self); FPaint.Parent := Center; FPaint.Align := alClient; FPaint.Name := 'CharacterPreview';
  FPaint.OnPaint := PaintPreview; FPaint.OnMouseDown := PreviewMouseDown; FPaint.OnMouseMove := PreviewMouseMove; FPaint.OnMouseUp := PreviewMouseUp;
  FPaint.OnResize := PreviewResize;
  FPopup := TPopupMenu.Create(Self); FPaint.PopupMenu := FPopup;
  FTimer := TTimer.Create(Self); FTimer.Interval := 33; FTimer.OnTimer := TimerTick;
end;

procedure TRigmEditorForm.OpenFile(const FileName: string);
begin FEditor.Open(FileName); if FPipe <> nil then FPipe.Sync; end;

procedure TRigmEditorForm.NewCharacter(const Name, FileName: string);
begin FEditor.NewDocument(Name, 1024, 1024); FEditor.Save(FileName); if FPipe <> nil then FPipe.Sync; end;

procedure TRigmEditorForm.OpenSample;
begin
  FEditor.NewDocument('編集テスト用サンプル（未保存）', 256, 320);
  PopulateRigmSample(FEditor.Document); FEditor.Document.Art.Changed;
  if FPipe <> nil then FPipe.Sync; RefreshView(Self);
end;

function TRigmEditorForm.OpenSeparatedPsd(const FileName: string): TRigmEditorForm;
var Args, Reply: TJSONObject;
begin
  if (FEditor.Document.Parts.Count > 0) or (FEditor.Document.Bones.Count > 0) or
    (FEditor.Document.Meshes.Count > 0) then begin
    Result := TRigmEditorForm.Create(Owner);
    try
      Result.OnSaved := FOnSaved; Result.OpenSeparatedPsd(FileName); Result.Show;
    except Result.Free; raise; end;
    Exit;
  end;
  Args := TJSONObject.Create;
  try
    Args.AddPair('path', FileName);
    if FEditor.FileName = '' then Args.AddPair('name', ChangeFileExt(ExtractFileName(FileName), ''));
    Reply := FEditor.Execute('import-psd', Args); Reply.Free;
  finally Args.Free; end;
  FEditor.AiLog.Add('分解済みPSDから開始（画像生成を省略）: ' + FEditor.Document.PsdSourceName);
  if FEditor.Document.PsdImportNotes <> '' then FEditor.AiLog.Add(FEditor.Document.PsdImportNotes);
  RefreshView(Self); Result := Self;
end;

function TRigmEditorForm.SaveCharacter: Boolean;
var Dialog: TSaveDialog;
begin
  Result := False;
  if FEditor.FileName <> '' then begin FEditor.Save(FEditor.FileName); Result := True; end
  else begin
    Dialog := TSaveDialog.Create(Self);
    try
      Dialog.Filter := 'RIGM キャラクター (*.rigm)|*.rigm'; Dialog.DefaultExt := 'rigm';
      Dialog.Options := Dialog.Options + [ofOverwritePrompt]; Dialog.FileName := FEditor.Document.Name.Replace('（未保存）', '') + '.rigm';
      if Dialog.Execute then begin FEditor.Save(Dialog.FileName); Result := True; end;
    finally Dialog.Free; end;
  end;
  if Result and Assigned(FOnSaved) then FOnSaved(Self);
end;

function TRigmEditorForm.Execute(const Command: string; Args: TJSONObject): Boolean;
var Reply: TJSONObject;
begin
  Result := False;
  try
    try Reply := FEditor.Execute(Command, Args); Reply.Free; Result := True;
    except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
  finally Args.Free; end;
end;

procedure TRigmEditorForm.PageClick(Sender: TObject);
var Page: TRigmPage;
begin
  Page := TRigmPage(TControl(Sender).Tag);
  if not FEditor.Document.CanOpen(Page) then begin
    if (Ord(Page) = Ord(FEditor.Document.LastPage) + 1) then AdvanceStage;
    Exit;
  end;
  try FEditor.SwitchPage(Page); FPreviewMode := False; FDirect := False; RefreshView(Self);
  except on E: Exception do MessageDlg(E.Message, mtInformation, [mbOK], 0); end;
end;

function TRigmEditorForm.CanSelectPage(Page: TRigmPage): Boolean;
begin
  Result := FEditor.Document.CanOpen(Page) or
    ((Ord(Page) = Ord(FEditor.Document.LastPage) + 1) and
     FEditor.Document.CanOpen(FEditor.Document.LastPage) and
     not HasErrors(FIssues, FEditor.Document.LastPage));
end;

function TRigmEditorForm.AdvanceStage: Boolean;
var Args, Reply: TJSONObject;
begin
  Result := False;
  Args := TJSONObject.Create;
  try
    try
      Reply := FEditor.Execute('mark-complete', Args); Reply.Free; Result := True;
    except on E: Exception do begin
      // Revalidate and show the blocking issue without a confirmation dialog.
      FViewState := ''; RefreshView(Self);
      FLog.Visible := False; FIssueList.Visible := True;
      for var I := 0 to FIssueList.Items.Count - 1 do begin
        var Issue := TRigmIssue(FIssueList.Items.Objects[I]);
        if Issue.Error and (Issue.Page <= FEditor.Document.LastPage) then begin
          FIssueList.ItemIndex := I;
          if FEditor.Document.Bone(Issue.TargetId) <> nil then begin
            FEditor.SelectedId := Issue.TargetId; RefreshView(Self);
          end;
          Break;
        end;
      end;
      FStatus.Caption := '  次へ進めません: ' + E.Message + '  |  異常リストの対象を修正してください。';
    end; end;
  finally Args.Free; end;
end;

procedure TRigmEditorForm.RefreshView(Sender: TObject);
var Page: TRigmPage; L: TArtLayer; Index: Integer; Selected, State: string; Item: TMenuItem;
begin
  if FUpdating then Exit;
  if FUIPage <> FEditor.Document.LastPage then begin
    StopGamepadInput(Self);
    FUIPage := FEditor.Document.LastPage; FPreviewMode := False; FDirect := False; FShowReference := False;
  end;
  State := IntToHex(NativeUInt(FEditor.Document)) + FEditor.Document.FileId +
    FEditor.Document.Art.Revision.ToString + ':' + IntToStr(Ord(FEditor.Document.LastPage)) +
    BoolToStr(FPreviewMode) + BoolToStr(FDirect) + BoolToStr(FShowReference) +
    BoolToStr(FShowBones) + BoolToStr(FShowMeshes);
  if State = FViewState then begin
    RefreshStatus;
    if FPropertySelectedId <> FEditor.SelectedId then begin
      FUpdating := True;
      try
        if FEditor.Document.LastPage = rpLayer then FLayerList.Selected := FEditor.Document.Art.FindLayer(FEditor.SelectedId)
        else if FEditor.Document.LastPage in [rpBone, rpMesh] then
          for Index := 0 to FObjectList.Items.Count - 1 do begin
            if FEditor.Document.LastPage = rpBone then Selected := TRigmBone(FObjectList.Items.Objects[Index]).Id
            else Selected := TRigmMesh(FObjectList.Items.Objects[Index]).Id;
            if Selected = FEditor.SelectedId then begin FObjectList.ItemIndex := Index; Break; end;
          end;
      finally FUpdating := False; end;
      BuildProperties; RefreshToolbars;
      if FEditor.Document.LastPage <> rpLayer then FPaint.Invalidate;
    end;
    Exit;
  end;
  FUpdating := True;
  try
    Caption := 'RIGM Maker — ' + FEditor.Document.Name + IfThen(FEditor.Modified, ' *', '');
    for Page := Low(TRigmPage) to High(TRigmPage) do begin
      FPages[Page].Enabled := CanSelectPage(Page);
      FPages[Page].Down := Page = FEditor.Document.LastPage;
    end;
    FLayerList.Visible := FEditor.Document.LastPage = rpLayer; FObjectList.Visible := FEditor.Document.LastPage in [rpBone, rpMesh];
    Selected := FEditor.SelectedId;
    FLayerList.SetRoots(FEditor.Document.Art.Roots); L := FEditor.Document.Art.FindLayer(Selected);
    if L <> nil then FLayerList.Selected := L;
    if (Selected = '') and (FLayerList.Selected <> nil) and (FEditor.Document.LastPage = rpLayer) then Selected := FLayerList.Selected.Id;
    FObjectList.Items.Clear; Index := -1;
    if FEditor.Document.LastPage = rpBone then for var Bone in FEditor.Document.Bones do begin
      var I := FObjectList.Items.AddObject(IfThen(Bone.Visible, '● ', '○ 非表示 ') + Bone.Name, Bone);
      if Bone.Id = Selected then Index := I;
    end;
    if FEditor.Document.LastPage = rpMesh then for var Mesh in FEditor.Document.Meshes do begin
      var I := FObjectList.Items.AddObject(Mesh.Name + '  (' + IntToStr(Length(Mesh.Vertices)) + '頂点)', Mesh);
      if Mesh.Id = Selected then Index := I;
    end;
    if (Index < 0) and (FObjectList.Items.Count > 0) then Index := 0;
    FObjectList.ItemIndex := Index;
    if Index >= 0 then begin
      if FEditor.Document.LastPage = rpBone then Selected := TRigmBone(FObjectList.Items.Objects[Index]).Id;
      if FEditor.Document.LastPage = rpMesh then Selected := TRigmMesh(FObjectList.Items.Objects[Index]).Id;
    end;
    FEditor.SelectedId := Selected;
    FPopup.Items.Clear;
  finally FUpdating := False; end;
  case FEditor.Document.LastPage of
    rpBone: begin
      for var Action in [acRestoreBone, acHideBone, acResetBone] do begin
        Item := TMenuItem.Create(Self); Item.Tag := Action; Item.OnClick := ToolbarClick;
        case Action of acRestoreBone: Item.Caption := '追加 / 子ボーン復活'; acHideBone: Item.Caption := '子と一緒に非表示'; acResetBone: Item.Caption := '初期位置へ戻す'; end;
        FPopup.Items.Add(Item);
      end;
    end;
  end;
  FIssues.Free; FIssues := ValidateRigm(FEditor.Document, FEditor.Pose); FIssueList.Items.Clear;
  for var Issue in FIssues do if not Issue.Ignored then FIssueList.Items.AddObject(
    IfThen(Issue.Error, '● ', '△ ') + PageName(Issue.Page) + ' : ' + Issue.Message, Issue);
  FIssueList.Visible := FIssueList.Items.Count > 0; FLog.Visible := not FIssueList.Visible;
  RefreshStatus;
  BuildProperties; RefreshToolbars; RefreshPreview;
  FViewState := State;
end;

procedure TRigmEditorForm.RefreshStatus;
begin
  Caption := 'RIGM Maker — ' + FEditor.Document.Name + IfThen(FEditor.Modified, ' *', '');
  if FLog.Lines.Text <> FEditor.AiLog.Text then FLog.Lines.Assign(FEditor.AiLog);
  FStatus.Caption := '  ' + IfThen(FEditor.Document.Usable, '使用可能', '未完成') + '  |  ' +
    PageName(FEditor.Document.LastPage) + '  |  ' + IfThen(FPreviewMode, 'プレビューモード', '編集モード') +
    '  |  保存先: ' + IfThen(FEditor.FileName = '', '未保存', FEditor.FileName);
  RefreshLayerGuide;
  RefreshToolbars;
end;

procedure TRigmEditorForm.RefreshToolbars;
var Page: TRigmPage; B: TToolButton; Layer: TArtLayer; Part: TRigmPart; Bone: TRigmBone; Mesh: TRigmMesh;
begin
  Page := FEditor.Document.LastPage;
  Layer := FEditor.Document.Art.FindLayer(FEditor.SelectedId);
  FEditor.Document.Parts.TryGetValue(FEditor.SelectedId, Part);
  Bone := FEditor.Document.Bone(FEditor.SelectedId); Mesh := FEditor.Document.Mesh(FEditor.SelectedId);
  for var P := Low(TRigmPage) to High(TRigmPage) do begin
    FPages[P].Down := P = Page; FPages[P].Enabled := CanSelectPage(P);
    FPages[P].Hint := FPages[P].Caption;
    if (Ord(P) = Ord(Page) + 1) and not FEditor.Document.CanOpen(P) then
      FPages[P].Hint := FPages[P].Caption + IfThen(FPages[P].Enabled,
        ' — 現工程を自動検証して進む', ' — 現工程の異常を修正してください');
  end;
  for var I := 0 to FHeaderBar.ButtonCount - 1 do begin
    B := FHeaderBar.Buttons[I];
    if B.Style = tbsSeparator then Continue;
    if not Assigned(B.OnClick) then Continue;
    if StartsText('Page', B.Name) then Continue;
    case B.Tag of
      acUndo: B.Enabled := FEditor.CanUndo;
      acRedo: B.Enabled := FEditor.CanRedo;
      acMode: begin B.Enabled := Page in [rpBone, rpMesh]; B.Down := FPreviewMode; end;
      acDirect: begin B.Enabled := Page = rpPreview; B.Down := FDirect and (Page = rpPreview); end;
      acBones: B.Down := FShowBones;
      acMeshes: B.Down := FShowMeshes;
      acComplete: B.Hint := IfThen(Page = rpPreview, '自動検証して使用可能にする', '工程を自動検証して次へ進む');
    end;
  end;
  FToolbar.DisableAlign;
  try
    for var I := 0 to FToolbar.ButtonCount - 1 do begin
      B := FToolbar.Buttons[I]; B.Enabled := True;
      case B.Tag of
        acPng, acPsd, acGroup, acReference, acClassify, acLayerUp, acLayerDown, acReplace, acDeleteLayer: B.Visible := Page = rpLayer;
        acRestoreBone, acHideBone, acResetBone: B.Visible := Page = rpBone;
        acGenerate, acAddVertex, acDeleteVertex: B.Visible := Page = rpMesh;
      end;
      case B.Tag of
        acReference: begin
          B.Enabled := Length(FEditor.Document.ReferencePixels) > 0; B.Down := FShowReference;
          B.Caption := IfThen(FShowReference, '編集画像に戻す', '元画像を表示（任意の比較）'); B.Hint := B.Caption;
        end;
        acClassify: B.Enabled := FEditor.Document.Parts.Count > 0;
        acLayerUp, acLayerDown, acDeleteLayer: B.Enabled := (Layer <> nil) and (Part <> nil) and not Part.Locked;
        acReplace: B.Enabled := (Layer <> nil) and (Layer.Kind = alkImage) and (Part <> nil) and not Part.Locked;
        acHideBone: B.Enabled := (Bone <> nil) and Bone.Visible;
        acResetBone: B.Enabled := Bone <> nil;
        acGenerate: B.Enabled := FEditor.Document.Parts.Count > 0;
        acAddVertex: B.Enabled := (Mesh <> nil) and not Mesh.Locked and (Length(Mesh.Triangles) > 0);
        acDeleteVertex: B.Enabled := (Mesh <> nil) and not Mesh.Locked and (FVertex >= 0) and (FVertex < Length(Mesh.Vertices));
      end;
    end;
    FToolbar.Visible := Page <> rpPreview;
  finally FToolbar.EnableAlign; end;
end;

procedure TRigmEditorForm.RefreshLayerGuide;
var Prefix, Next: string; Missing: Boolean; Page: TRigmPage; Blocking: TRigmIssue;
begin
  Page := FEditor.Document.LastPage;
  FPsdHint.Visible := Page <> rpPreview;
  if not FPsdHint.Visible then Exit;
  if Page <> rpLayer then begin
    Blocking := nil;
    for var Issue in FIssues do if Issue.Error and (Issue.Page <= Page) then begin Blocking := Issue; Break; end;
    if Blocking <> nil then
      FPsdHint.Caption := '次へ進めません: ' + Blocking.Message + sLineBreak +
        '異常リストの項目をダブルクリックして対象を修正してください。'
    else FPsdHint.Caption := PageName(Page) + 'の検証エラーはありません。' +
      '上部の「' + PageName(TRigmPage(Ord(Page) + 1)) + '」アイコン、または右向き矢印で自動検証して進めます。';
    Exit;
  end;
  if FEditor.Document.Parts.Count = 0 then begin
    FPsdHint.Caption := '分解済みPSDを読み込むと、画像生成を省略してレイヤー分類から開始できます。'; Exit;
  end;
  if FEditor.Document.PsdSourceName <> '' then
    Prefix := '分解済みPSD: ' + FEditor.Document.PsdSourceName + '（画像生成を省略）。'
  else Prefix := '';
  Prefix := Prefix + 'RIGM読込時にも未分類を自動推定します。手動指定・ロックは保持します。';
  Missing := False;
  for var Issue in FIssues do
    if (Issue.Page = rpLayer) and Issue.Error and (Issue.Code.StartsWith('required-') or
      (Issue.Code = 'empty') or (Issue.Code = 'missing-image')) then Missing := True;
  if Missing then Next := '次に：異常リストの必須パーツ種別・画像内容を確認してください。名前や親を調整した後は「未分類を再判定」で更新できます。'
  else Next := '上部の「ボーン」アイコン、または右向き矢印で自動検証して進めます。元画像との見た目の比較は任意です。';
  FPsdHint.Caption := Prefix + sLineBreak + Next;
  if FEditor.Document.PsdImportNotes <> '' then FPsdHint.Caption := FPsdHint.Caption + sLineBreak + FEditor.Document.PsdImportNotes;
end;

function TRigmEditorForm.PropertyControl(const Name: string; ControlClass: TControlClass): TControl;
begin
  Result := TControl(FProperties.FindComponent(Name));
  if Result = nil then begin
    Result := ControlClass.Create(FProperties); Result.Name := Name; Result.Parent := FProperties;
  end;
  FUsedProperties.AddOrSetValue(Result, True);
  Result.Visible := True;
end;

procedure TRigmEditorForm.PlaceProperty(Control: TControl; X, Y, Width, Height: Integer);
begin
  Control.SetBounds(ScaleValue(X), ScaleValue(Y) - FProperties.VertScrollBar.Position,
    ScaleValue(Width), ScaleValue(Height));
end;

function TRigmEditorForm.AddEdit(const Key, Caption, Value: string; ReadOnly: Boolean; X, EditWidth: Integer): TEdit;
var LabelControl: TLabel;
begin
  LabelControl := TLabel(PropertyControl('Label' + Key, TLabel)); LabelControl.AutoSize := False;
  LabelControl.Caption := Caption; PlaceProperty(LabelControl, 12, FPropertyY, 335, 20);
  Result := TEdit(PropertyControl('Field' + Key, TEdit));
  PlaceProperty(Result, X, FPropertyY + 22, EditWidth, 25);
  if Result.Text <> Value then Result.Text := Value;
  Result.ReadOnly := ReadOnly;
  FFields.AddOrSetValue(Key, Result); Inc(FPropertyY, 57);
end;

function TRigmEditorForm.AddNumber(const Key, Caption: string; Value: Double; Minimum, Maximum: Integer): TEdit;
var Track: TTrackBar;
begin
  Result := AddEdit(Key, Caption, FloatToStr(Value, TFormatSettings.Invariant), False, 264, 76);
  Track := TTrackBar(PropertyControl('Slider' + Key, TRigmFineTrackBar));
  PlaceProperty(Track, 8, FPropertyY - 36, 252, 30); Track.Min := Minimum; Track.Max := Maximum;
  Track.Position := EnsureRange(Round(Value), Minimum, Maximum); Track.TickStyle := tsNone; Track.OnChange := NumberChanged;
end;

procedure TRigmEditorForm.NumberChanged(Sender: TObject);
var Key: string;
begin
  if FPropertiesUpdating then Exit;
  Key := Copy(TTrackBar(Sender).Name, 7, MaxInt);
  if FFields.ContainsKey(Key) then TEdit(FFields[Key]).Text := IntToStr(TTrackBar(Sender).Position);
end;

function TRigmEditorForm.AddCheck(const Key, Caption: string; Value: Boolean): TCheckBox;
begin
  Result := TCheckBox(PropertyControl('Check' + Key, TCheckBox)); Result.Caption := Caption;
  PlaceProperty(Result, 12, FPropertyY, 328, 26); Result.Checked := Value;
  FFields.AddOrSetValue(Key, Result); Inc(FPropertyY, 34);
end;

function TRigmEditorForm.AddCombo(const Key, Caption: string): TComboBox;
var LabelControl: TLabel;
begin
  LabelControl := TLabel(PropertyControl('Label' + Key, TLabel)); LabelControl.AutoSize := False;
  LabelControl.Caption := Caption; PlaceProperty(LabelControl, 12, FPropertyY, 335, 20);
  Result := TComboBox(PropertyControl('Combo' + Key, TComboBox));
  PlaceProperty(Result, 12, FPropertyY + 22, 328, 25); Result.Style := csDropDownList;
  FFields.AddOrSetValue(Key, Result); Inc(FPropertyY, 57);
end;

procedure TRigmEditorForm.AddBoneCombo(const Key, Caption, Selected: string);
var Combo: TComboBox; Index: Integer;
begin
  Combo := AddCombo(Key, Caption);
  if Combo.Items.Count = 0 then begin
    Combo.Items.BeginUpdate;
    try
      Combo.Items.AddObject('なし / ルート', nil);
      for var Bone in FEditor.Document.Bones do
        Combo.Items.AddObject(Bone.Name + IfThen(Bone.Visible, '', '（非表示）'), Bone);
    finally Combo.Items.EndUpdate; end;
  end;
  Combo.ItemIndex := 0;
  for Index := 1 to Combo.Items.Count - 1 do
    if TRigmBone(Combo.Items.Objects[Index]).Id = Selected then begin Combo.ItemIndex := Index; Break; end;
end;

procedure TRigmEditorForm.AddPartCombo(const Key, Caption, Selected: string; GroupsOnly: Boolean);
var Combo: TComboBox; Index: Integer;
begin
  Combo := AddCombo(Key, Caption);
  if Combo.Items.Count = 0 then begin
    Combo.Items.BeginUpdate;
    try
      Combo.Items.AddObject('なし / 最上位', nil);
      for var Layer in FEditor.Document.Layers do if not GroupsOnly or (Layer.Kind = alkGroup) then
        Combo.Items.AddObject(Layer.Name, Layer);
    finally Combo.Items.EndUpdate; end;
  end;
  Combo.ItemIndex := 0;
  for Index := 1 to Combo.Items.Count - 1 do
    if TArtLayer(Combo.Items.Objects[Index]).Id = Selected then begin Combo.ItemIndex := Index; Break; end;
end;

procedure TRigmEditorForm.BuildProperties;
var L: TArtLayer; P: TRigmPart; B: TRigmBone; M: TRigmMesh; Combo: TComboBox; Memo: TMemo;
    LabelControl: TLabel; Track: TTrackBar; I, Schema: Integer; Lines: TStringList; Angle: Double;
begin
  if FPropertiesUpdating then Exit;
  Inc(FPropertyBuildCount);
  FPropertiesUpdating := True; FProperties.DisableAlign;
  try
  Schema := Ord(FEditor.Document.LastPage) * 4;
  if (FEditor.Document.LastPage = rpBone) and FPreviewMode then Inc(Schema);
  if (FEditor.Document.LastPage = rpPreview) and FDirect then Inc(Schema, 2);
  if not FPropertyLayoutReady or (Schema <> FPropertySchema) then begin
    FFields.Clear; FUsedProperties.Clear;
    while FProperties.ControlCount > 0 do FProperties.Controls[0].Free;
    FProperties.VertScrollBar.Position := 0;
    FPropertySchema := Schema; FPropertyLayoutReady := True;
  end;
  if (FPropertyDocument <> FEditor.Document) or (FPropertyFileId <> FEditor.Document.FileId) or
    (FPropertyRevision <> FEditor.Document.Art.Revision) then begin
    // Candidate commits replace the model objects; do not keep pointers to the old document.
    for I := 0 to FProperties.ControlCount - 1 do
      if FProperties.Controls[I] is TComboBox then TComboBox(FProperties.Controls[I]).Items.Clear;
    FPropertyDocument := FEditor.Document; FPropertyFileId := FEditor.Document.FileId;
    FPropertyRevision := FEditor.Document.Art.Revision;
  end;
  FFields.Clear;
  FUsedProperties.Clear;
  FPropertyY := 12;
  case FEditor.Document.LastPage of
    rpLayer: begin
      L := FEditor.Document.Art.FindLayer(FEditor.SelectedId); if L = nil then Exit; P := FEditor.Document.Part(L.Id);
      AddEdit('name', 'パーツ名', L.Name); AddEdit('id', '固有ID（名称・順序変更でも維持）', L.Id, True);
      Combo := AddCombo('role', 'パーツ種別');
      if Combo.Items.Count = 0 then Combo.Items.AddStrings(['eye : 目', 'brow : 眉', 'mouth : 口', 'hair : 髪', 'face : 顔', 'body : 体', 'accessory : 装飾', 'reference : 比較用', 'fixed : 固定', 'other : その他', 'group : グループ']);
      Combo.ItemIndex := -1;
      for I := 0 to Combo.Items.Count - 1 do if Combo.Items[I].StartsWith(P.Role + ' ') then Combo.ItemIndex := I;
      if FEditor.Document.IsReferencePart(L.Id) then AddEdit('referenceOnly', '比較専用（描画・可動メッシュの対象外）', 'はい', True);
      AddPartCombo('parentId', '親グループ', FEditor.Document.ParentId(L.Id), True);
      AddPartCombo('pairId', '左右対応パーツ', P.PairId); AddBoneCombo('boneId', '追従ボーン', P.BoneId);
      AddNumber('x', 'X（キャンバス中央が0）', P.X, -FEditor.Document.Art.Width, FEditor.Document.Art.Width);
      AddNumber('y', 'Y（下方向が正）', P.Y, -FEditor.Document.Art.Height, FEditor.Document.Art.Height);
      AddNumber('rotation', '回転（度）', P.Rotation, -180, 180);
      AddEdit('scaleX', '拡大率 X', FloatToStr(P.ScaleX, TFormatSettings.Invariant));
      AddEdit('scaleY', '拡大率 Y', FloatToStr(P.ScaleY, TFormatSettings.Invariant));
      AddNumber('opacity', '不透明度（0～255）', L.Opacity, 0, 255);
      AddCheck('visible', '表示', L.Visible); AddCheck('locked', 'ロック', P.Locked);
      AddEdit('tags', '関係・属性（カンマ区切り）', P.Tags);
      AddButton(FProperties, '属性を適用', 'ApplyLayerPropertiesButton', 0, 12, FPropertyY, 158).OnClick := ApplyProperties; Inc(FPropertyY, 40);
      AddButton(FProperties, '上へ', 'LayerUpButton', acLayerUp, 12, FPropertyY, 74);
      AddButton(FProperties, '下へ', 'LayerDownButton', acLayerDown, 94, FPropertyY, 74);
      AddButton(FProperties, '削除', 'DeleteLayerButton', acDeleteLayer, 178, FPropertyY, 74); Inc(FPropertyY, 40);
      AddButton(FProperties, 'PNGで画像を置換', 'ReplacePngButton', acReplace, 12, FPropertyY, 180);
    end;
    rpBone: begin
      B := FEditor.Document.Bone(FEditor.SelectedId); if B = nil then Exit;
      AddEdit('name', 'ボーン名', B.Name); AddEdit('id', '固有ID', B.Id, True);
      AddBoneCombo('parentId', '親ボーン', B.ParentId); AddBoneCombo('pairId', '左右対応ボーン', B.PairId);
      AddNumber('x', 'X', B.X, -FEditor.Document.Art.Width, FEditor.Document.Art.Width);
      AddNumber('y', 'Y', B.Y, -FEditor.Document.Art.Height, FEditor.Document.Art.Height);
      AddNumber('minAngle', '最小角度', B.MinAngle, -180, 180); AddNumber('maxAngle', '最大角度', B.MaxAngle, -180, 180);
      AddCheck('locked', 'ロック', B.Locked); AddCheck('paired', '左右を同時に操作', True);
      AddButton(FProperties, '属性を適用', 'ApplyBonePropertiesButton', 0, 12, FPropertyY, 158).OnClick := ApplyProperties; Inc(FPropertyY, 42);
      if FPreviewMode then begin
        LabelControl := TLabel(PropertyControl('LabelBonePose', TLabel)); LabelControl.AutoSize := False;
        LabelControl.Caption := '選択ボーンのプレビュー角度'; PlaceProperty(LabelControl, 12, FPropertyY, 320, 20);
        Track := TTrackBar(PropertyControl('BonePoseSlider', TRigmFineTrackBar)); Track.Min := Round(B.MinAngle*100); Track.Max := Round(B.MaxAngle*100);
        Angle := 0; FEditor.Pose.BoneAngles.TryGetValue(FEditor.SelectedId, Angle); Track.Position := Round(Angle*100);
        PlaceProperty(Track, 12, FPropertyY + 24, 328, 32); Track.TickStyle := tsNone; Track.Tag := -1; Track.OnChange := ParameterChanged;
        RefreshParameterLabel(Track);
        Inc(FPropertyY, 64);
      end;
    end;
    rpMesh: begin
      M := FEditor.Document.Mesh(FEditor.SelectedId); if M = nil then Exit;
      AddEdit('name', 'メッシュ名', M.Name); AddEdit('id', '固有ID', M.Id, True);
      Combo := AddCombo('role', '役割（表示色）');
      if Combo.Items.Count = 0 then Combo.Items.AddStrings(['normal', 'face', 'eye', 'mouth', 'hair', 'body', 'fixed', 'auxiliary', 'physics', 'special']);
      Combo.ItemIndex := Combo.Items.IndexOf(M.Role);
      AddEdit('strength', '変形強度（0～1）', FloatToStr(M.Strength, TFormatSettings.Invariant));
      AddCheck('visible', 'メッシュ表示', M.Visible); AddCheck('locked', 'ロック', M.Locked); AddCheck('boundaryFixed', '境界を固定', M.BoundaryFixed);
      Combo := AddCombo('vertex', '選択頂点');
      if Combo.Items.Count <> Length(M.Vertices) then begin
        Combo.Items.Clear; for I := 0 to High(M.Vertices) do Combo.Items.Add(IntToStr(I));
      end;
      FVertex := EnsureRange(FVertex, 0, Max(0, High(M.Vertices))); if Combo.Items.Count > 0 then Combo.ItemIndex := FVertex;
      Combo.OnChange := VertexChanged;
      if Length(M.Vertices) > 0 then begin
        AddEdit('x', '頂点 X', FloatToStr(M.Vertices[FVertex].X, TFormatSettings.Invariant)); AddEdit('y', '頂点 Y', FloatToStr(M.Vertices[FVertex].Y, TFormatSettings.Invariant));
        AddEdit('u', 'UV U（0～1）', FloatToStr(M.Vertices[FVertex].U, TFormatSettings.Invariant)); AddEdit('v', 'UV V（0～1）', FloatToStr(M.Vertices[FVertex].V, TFormatSettings.Invariant));
        var Bone1 := ''; var Bone2 := ''; var Weight := 1.0;
        if Length(M.Vertices[FVertex].Weights) > 0 then begin Bone1 := M.Vertices[FVertex].Weights[0].BoneId; Weight := M.Vertices[FVertex].Weights[0].Value; end;
        if Length(M.Vertices[FVertex].Weights) > 1 then Bone2 := M.Vertices[FVertex].Weights[1].BoneId;
        AddBoneCombo('bone1', 'ウェイト ボーン1', Bone1); AddBoneCombo('bone2', 'ウェイト ボーン2', Bone2);
        AddEdit('weight', 'ボーン1のウェイト（残りをボーン2へ）', FloatToStr(Weight, TFormatSettings.Invariant));
      end;
      AddButton(FProperties, '属性・選択頂点を適用', 'ApplyMeshPropertiesButton', 0, 12, FPropertyY, 210).OnClick := ApplyProperties; Inc(FPropertyY, 45);
      Memo := TMemo(PropertyControl('TriangleEditor', TMemo)); PlaceProperty(Memo, 12, FPropertyY, 328, 120); Memo.ScrollBars := ssVertical;
      Lines := TStringList.Create;
      try
        for var Face in M.Triangles do Lines.Add(Format('%d,%d,%d', [Face.A, Face.B, Face.C]));
        if Memo.Lines.Text <> Lines.Text then Memo.Lines.Assign(Lines);
      finally Lines.Free; end;
      FFields.Add('triangles', Memo); Inc(FPropertyY, 128);
      AddButton(FProperties, '面の接続を適用', 'ApplyTrianglesButton', acTriangles, 12, FPropertyY, 175);
    end;
    rpPreview: begin
      if FDirect then begin
        AddEdit('help', 'ダイレクトプレビュー', '目・口・頭・上半身を選択してドラッグ', True);
        AddEdit('gamepad', 'Nintendo Switch Pro Controller（HID）', FGamepad, True);
        AddCheck('gamepadEnabled', 'Proコントローラーで操作する', FGamepadEnabled).OnClick := GamepadOptionsChanged;
        Combo := AddCombo('gamepadTarget', '左スティックの対象（十字キー上下で切替）');
        if Combo.Items.Count = 0 then Combo.Items.AddStrings(['目', '口', '頭', '上半身']); Combo.ItemIndex := Ord(FGamepadPreview.Target);
        Combo.OnChange := GamepadOptionsChanged;
        AddEdit('gamepadHelp1', '操作', '右スティック=顔角度 / R+右=上半身 / L=微調整', True);
        AddEdit('gamepadHelp2', '操作', 'ZR=瞬き / ZL=口 / A=確定 / B=取消 / Y=初期値', True);
      end else for I := 0 to High(FEditor.Document.Parameters) do begin
        var Param := FEditor.Document.Parameters[I];
        LabelControl := TLabel(PropertyControl('LabelParameter' + Param.Id, TLabel)); LabelControl.AutoSize := False; LabelControl.Caption := Param.Name;
        PlaceProperty(LabelControl, 12, FPropertyY, 330, 22); Inc(FPropertyY, 25);
        Track := TTrackBar(PropertyControl('Parameter' + Param.Id, TRigmFineTrackBar));
        PlaceProperty(Track, 8, FPropertyY, 335, 36); Track.Min := Round(Param.Minimum * 100); Track.Max := Round(Param.Maximum * 100);
        Track.Position := Round(FEditor.Pose.Value(Param.Id, Param.Initial) * 100); Track.TickStyle := tsNone; Track.Tag := I;
        Track.OnChange := ParameterChanged; Inc(FPropertyY, 51);
        RefreshParameterLabel(Track);
      end;
    end;
  end;
  finally
    for I := 0 to FProperties.ControlCount - 1 do
      FProperties.Controls[I].Visible := FUsedProperties.ContainsKey(FProperties.Controls[I]);
    FProperties.VertScrollBar.Range := ScaleValue(FPropertyY + 44);
    FProperties.EnableAlign; FPropertiesUpdating := False;
    FPropertySelectedId := FEditor.SelectedId;
  end;
end;

function TRigmEditorForm.FieldText(const Key: string): string;
begin
  Result := ''; if not FFields.ContainsKey(Key) then Exit;
  if FFields[Key] is TEdit then Result := TEdit(FFields[Key]).Text
  else if FFields[Key] is TComboBox then Result := TComboBox(FFields[Key]).Text;
end;

function TRigmEditorForm.FieldNumber(const Key: string): Double;
begin
  if not TryStrToFloat(FieldText(Key), Result, TFormatSettings.Invariant) then raise ERigm.Create('数値を入力してください: ' + Key);
end;

function TRigmEditorForm.FieldChecked(const Key: string): Boolean;
begin Result := FFields.ContainsKey(Key) and TCheckBox(FFields[Key]).Checked; end;

function TRigmEditorForm.ComboId(const Key: string; Bone: Boolean): string;
var Combo: TComboBox; Obj: TObject;
begin
  Result := ''; if not FFields.ContainsKey(Key) then Exit;
  Combo := TComboBox(FFields[Key]); if Combo.ItemIndex < 0 then Exit;
  Obj := Combo.Items.Objects[Combo.ItemIndex]; if Obj = nil then Exit;
  if Bone then Result := TRigmBone(Obj).Id else Result := TArtLayer(Obj).Id;
end;

procedure TRigmEditorForm.ApplyProperties(Sender: TObject);
var Args, Vertex, Weights, Weight, Batch: TJSONObject; ArrayValue: TJSONArray; Command: string;
  procedure Operation(List: TJSONArray; const Name: string; var Arguments: TJSONObject);
  var O: TJSONObject;
  begin O := TJSONObject.Create; List.AddElement(O); O.AddPair('command', Name); O.AddPair('args', Arguments); Arguments := nil; end;
begin
  Args := TJSONObject.Create; Vertex := nil; Weights := nil;
  try
    try
      Args.AddPair('id', FEditor.SelectedId); Args.AddPair('name', FieldText('name')); AddB(Args, 'locked', FieldChecked('locked'));
      case FEditor.Document.LastPage of
        rpLayer: begin
          Command := 'update-layer'; Args.AddPair('role', FieldText('role').Split([' '])[0]); Args.AddPair('pairId', ComboId('pairId', False));
          Args.AddPair('parentId', ComboId('parentId', False)); Args.AddPair('boneId', ComboId('boneId', True)); Args.AddPair('tags', FieldText('tags'));
          for var Key in ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'opacity'] do AddN(Args, Key, FieldNumber(Key)); AddB(Args, 'visible', FieldChecked('visible'));
        end;
        rpBone: begin
          Command := 'update-bone'; Args.AddPair('parentId', ComboId('parentId', True)); Args.AddPair('pairId', ComboId('pairId', True));
          for var Key in ['x', 'y', 'minAngle', 'maxAngle'] do AddN(Args, Key, FieldNumber(Key)); AddB(Args, 'paired', FieldChecked('paired'));
        end;
        rpMesh: begin
          Command := 'update-mesh'; Args.AddPair('role', FieldText('role')); AddN(Args, 'strength', FieldNumber('strength'));
          AddB(Args, 'visible', FieldChecked('visible')); AddB(Args, 'boundaryFixed', FieldChecked('boundaryFixed'));
          if FFields.ContainsKey('x') then begin
            Vertex := TJSONObject.Create; Vertex.AddPair('id', FEditor.SelectedId); AddN(Vertex, 'vertex', FVertex);
            for var Key in ['x', 'y', 'u', 'v'] do AddN(Vertex, Key, FieldNumber(Key));
            Weights := TJSONObject.Create; Weights.AddPair('id', FEditor.SelectedId); AddN(Weights, 'vertex', FVertex);
            ArrayValue := TJSONArray.Create; Weights.AddPair('weights', ArrayValue);
            if ComboId('bone1', True) <> '' then begin
              Weight := TJSONObject.Create; ArrayValue.AddElement(Weight); Weight.AddPair('boneId', ComboId('bone1', True));
              AddN(Weight, 'value', IfThen(ComboId('bone2', True) = '', 1.0, FieldNumber('weight')));
            end;
            if ComboId('bone2', True) <> '' then begin
              Weight := TJSONObject.Create; ArrayValue.AddElement(Weight); Weight.AddPair('boneId', ComboId('bone2', True)); AddN(Weight, 'value', 1 - FieldNumber('weight'));
            end;
          end;
        end;
      else Exit; end;
      Batch := TJSONObject.Create;
      try
        ArrayValue := TJSONArray.Create; Batch.AddPair('operations', ArrayValue);
        if (Vertex <> nil) and FieldChecked('locked') and not FEditor.Document.Mesh(FEditor.SelectedId).Locked then Args.RemovePair('locked').Free;
        Operation(ArrayValue, Command, Args);
        if Vertex <> nil then Operation(ArrayValue, 'update-vertex', Vertex);
        if Weights <> nil then Operation(ArrayValue, 'set-weights', Weights);
        if (FEditor.Document.LastPage = rpMesh) and FieldChecked('locked') and not FEditor.Document.Mesh(FEditor.SelectedId).Locked then begin
          var Lock := TJSONObject.Create; Lock.AddPair('id', FEditor.SelectedId); AddB(Lock, 'locked', True); Operation(ArrayValue, 'update-mesh', Lock);
        end;
        var Reply := FEditor.Execute('batch', Batch); Reply.Free;
      finally Batch.Free; end;
      RefreshView(Self);
    except on E: Exception do begin RefreshView(Self); MessageDlg(E.Message, mtError, [mbOK], 0); end; end;
  finally Args.Free; Vertex.Free; Weights.Free; end;
end;

procedure TRigmEditorForm.SelectionChanged(Sender: TObject);
var Id: string;
begin
  if FUpdating then Exit;
  Id := '';
  if Sender = FLayerList then begin if FLayerList.Selected <> nil then Id := FLayerList.Selected.Id; end
  else if FObjectList.ItemIndex >= 0 then begin
    if FEditor.Document.LastPage = rpBone then Id := TRigmBone(FObjectList.Items.Objects[FObjectList.ItemIndex]).Id
    else Id := TRigmMesh(FObjectList.Items.Objects[FObjectList.ItemIndex]).Id;
  end;
  if (Id = FPropertySelectedId) and (Id = FEditor.SelectedId) then Exit;
  FEditor.SelectedId := Id;
  BuildProperties; RefreshToolbars;
  if FEditor.Document.LastPage <> rpLayer then FPaint.Invalidate;
end;

procedure TRigmEditorForm.LayerRename(Sender: TObject; Layer: TArtLayer; const Name: string);
var Args: TJSONObject;
begin Args := TJSONObject.Create; Args.AddPair('id', Layer.Id); Args.AddPair('name', Name); Execute('update-layer', Args); end;

procedure TRigmEditorForm.LayerAttributes(Sender: TObject; Layer: TArtLayer; Visible: Boolean; Opacity: Byte);
var Args: TJSONObject;
begin Args := TJSONObject.Create; Args.AddPair('id', Layer.Id); AddB(Args, 'visible', Visible); AddN(Args, 'opacity', Opacity); Execute('update-layer', Args); end;

procedure TRigmEditorForm.VertexChanged(Sender: TObject);
begin if FPropertiesUpdating then Exit; FVertex := TComboBox(Sender).ItemIndex; BuildProperties; RefreshToolbars; FPaint.Invalidate; end;

procedure TRigmEditorForm.ParameterChanged(Sender: TObject);
var Track: TTrackBar;
begin
  if FPropertiesUpdating then Exit;
  Track := TTrackBar(Sender);
  if Track.Tag = -1 then FEditor.Pose.BoneAngles.AddOrSetValue(FEditor.SelectedId, Track.Position/100.0)
  else FEditor.Pose.Values.AddOrSetValue(FEditor.Document.Parameters[Track.Tag].Id, Track.Position / 100.0);
  RefreshParameterLabel(Track);
  RefreshPreview;
end;

procedure TRigmEditorForm.RefreshParameterLabel(Track: TTrackBar);
var Name, Caption: string; Control: TComponent;
begin
  if Track.Tag = -1 then begin Name := 'LabelBonePose'; Caption := '選択ボーンのプレビュー角度'; end
  else begin
    if (Track.Tag < 0) or (Track.Tag >= Length(FEditor.Document.Parameters)) then Exit;
    Name := 'LabelParameter' + FEditor.Document.Parameters[Track.Tag].Id;
    Caption := FEditor.Document.Parameters[Track.Tag].Name;
    if FEditor.Document.Parameters[Track.Tag].Id = 'bodyAngle' then begin
      if FEditor.Document.HasUpperBodyRig then Caption := '上半身角度（腰支点）' else Caption := Caption + '（旧構成）';
    end;
  end;
  Control := FProperties.FindComponent(Name);
  if Control is TLabel then TLabel(Control).Caption := Caption + '  ' + FormatFloat('0.00',Track.Position/100.0,TFormatSettings.Invariant);
end;

procedure TRigmEditorForm.ToolbarClick(Sender: TObject);
var Action: Integer; Args, Face: TJSONObject; Dialog: TOpenDialog; SaveDialog: TSaveDialog;
    Command, Name: string; ArrayValue: TJSONArray; Values: TArray<string>;
begin
  if Sender is TMenuItem then Action := TMenuItem(Sender).Tag else Action := TControl(Sender).Tag;
  Args := nil;
  try
    try
    if Action in [acSave, acSaveAs] then begin
      if Action = acSave then SaveCharacter
      else begin
        SaveDialog := TSaveDialog.Create(Self);
        try SaveDialog.Filter := 'RIGM (*.rigm)|*.rigm'; SaveDialog.DefaultExt := 'rigm'; SaveDialog.Options := SaveDialog.Options + [ofOverwritePrompt];
          SaveDialog.FileName := FEditor.FileName; if SaveDialog.Execute then begin FEditor.Save(SaveDialog.FileName); if Assigned(FOnSaved) then FOnSaved(Self); end;
        finally SaveDialog.Free; end;
      end; Exit;
    end;
      if Action = acComplete then begin AdvanceStage; Exit; end;
      if Action = acMovie then begin ShowMovieStudio(Self); Exit; end;
    if Action in [acMode, acBones, acMeshes, acDirect, acResetPose, acReference] then begin
      case Action of
        acMode: FPreviewMode := not FPreviewMode;
        acBones: FShowBones := not FShowBones;
        acMeshes: FShowMeshes := not FShowMeshes;
        acDirect: begin FDirect := not FDirect; FPreviewMode := True; if not FDirect then StopGamepadInput(Self); end;
        acResetPose: begin FGamepadPreview.Release(FEditor.Pose); FEditor.Pose.Reset; end;
        acReference: FShowReference := not FShowReference;
      end;
      RefreshView(Self); Exit;
    end;
    Args := TJSONObject.Create; Args.AddPair('id', FEditor.SelectedId);
    if Action = acPsd then begin
      Dialog := TOpenDialog.Create(Self);
      try
        Dialog.Title := '分解済みPSDからレイヤー分類を開始（画像生成を省略）';
        Dialog.Filter := '分解済みPhotoshop PSD (*.psd)|*.psd'; Dialog.DefaultExt := 'psd';
        Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing, ofNoChangeDir];
        if Dialog.Execute then OpenSeparatedPsd(Dialog.FileName);
      finally Dialog.Free; end;
      Exit;
    end;
    if Action in [acPng, acReplace] then begin
      Dialog := TOpenDialog.Create(Self);
      try
        Dialog.Filter := 'PNG (*.png)|*.png';
        if not Dialog.Execute then Exit; Args.AddPair('path', Dialog.FileName);
      finally Dialog.Free; end;
    end;
    case Action of
      acUndo: Command := 'undo'; acRedo: Command := 'redo'; acPng: Command := 'import-png'; acReplace: Command := 'replace-png';
      acGroup: begin Command := 'add-group'; Name := 'グループ'; if not InputQuery('グループ追加', '名前', Name) then Exit; Args.AddPair('name', Name); end;
      acComplete: Command := 'mark-complete';
      acAddBone: begin Command := 'add-bone'; Args.AddPair('parentId', FEditor.SelectedId); end;
      acHideBone: begin Command := 'hide-bone'; AddB(Args, 'paired', FieldChecked('paired')); end;
      acRestoreBone: begin Command := 'restore-bone'; AddB(Args, 'paired', FieldChecked('paired')); end;
      acResetBone: begin Command := 'reset-bone'; AddB(Args, 'paired', FieldChecked('paired')); end;
      acGenerate: begin Command := 'generate-mesh'; Args.RemovePair('id').Free; Args.AddPair('id', ''); end;
      acAddVertex: begin Command := 'add-vertex'; AddN(Args, 'face', 0); end;
      acDeleteVertex: begin Command := 'delete-vertex'; AddN(Args, 'vertex', FVertex); end;
      acLayerUp: begin Command := 'move-layer'; AddN(Args, 'delta', -1); end;
      acLayerDown: begin Command := 'move-layer'; AddN(Args, 'delta', 1); end;
      acDeleteLayer: Command := 'delete-layer';
      acClassify: Command := 'classify-layers';
      acTriangles: begin
        Command := 'set-triangles'; ArrayValue := TJSONArray.Create; Args.AddPair('triangles', ArrayValue);
        for var Line in TMemo(FFields['triangles']).Lines do if Trim(Line) <> '' then begin
          Values := Line.Split([',', ' '], TStringSplitOptions.ExcludeEmpty); if Length(Values) <> 3 then raise ERigm.Create('面は a,b,c の3頂点で入力してください。');
          Face := TJSONObject.Create; ArrayValue.AddElement(Face); AddN(Face, 'a', StrToInt(Values[0])); AddN(Face, 'b', StrToInt(Values[1])); AddN(Face, 'c', StrToInt(Values[2]));
        end;
      end;
    else Exit; end;
    var Owned := Args; Args := nil; Execute(Command, Owned);
    except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
  finally Args.Free; end;
end;

function TRigmEditorForm.PreviewRect: TRect;
var Scale: Double; W, H: Integer;
begin
  if (FBitmap.Width < 1) or (FBitmap.Height < 1) then Exit(TRect.Empty);
  Scale := Min((FPaint.Width - ScaleValue(48)) / FBitmap.Width, (FPaint.Height - ScaleValue(48)) / FBitmap.Height);
  W := Max(1, Round(FBitmap.Width * Scale)); H := Max(1, Round(FBitmap.Height * Scale));
  Result := Rect((FPaint.Width - W) div 2, (FPaint.Height - H) div 2, (FPaint.Width + W) div 2, (FPaint.Height + H) div 2);
end;

function TRigmEditorForm.ToWorld(X, Y: Integer): TPointF;
var R: TRect;
begin
  R := PreviewRect; if R.Width = 0 then Exit(TPointF.Zero);
  Result := TPointF.Create((X - R.Left) * FEditor.Document.Art.Width / R.Width - FEditor.Document.Art.Width / 2,
    (Y - R.Top) * FEditor.Document.Art.Height / R.Height - FEditor.Document.Art.Height / 2);
end;

function TRigmEditorForm.ToScreen(X, Y: Double): TPoint;
var R: TRect;
begin
  R := PreviewRect; Result := Point(R.Left + Round((X + FEditor.Document.Art.Width / 2) * R.Width / FEditor.Document.Art.Width),
    R.Top + Round((Y + FEditor.Document.Art.Height / 2) * R.Height / FEditor.Document.Art.Height));
end;

procedure TRigmEditorForm.RefreshPreview;
begin
  FPreviewDirty := True; FPaint.Invalidate;
end;

procedure TRigmEditorForm.PreviewResize(Sender: TObject);
begin RefreshPreview; end;

procedure TRigmEditorForm.RenderPreview;
var Pixels: TBytes; W, H, X, Y, Offset, C, Base, A: Integer; Row: PByte; Pose: TRigmPose;
begin
  Pose := nil;
  if FPreviewMode or (FEditor.Document.LastPage = rpPreview) then Pose := FEditor.Pose;
  if FShowReference and (Length(FEditor.Document.ReferencePixels) > 0) then begin
    Pixels := FEditor.Document.ReferencePixels; W := FEditor.Document.Art.Width; H := FEditor.Document.Art.Height;
  end else Pixels := RenderRigm(FEditor.Document, Pose, Min(1024,Max(16,Max(PreviewRect.Width,PreviewRect.Height))), W, H);
  FBitmap.PixelFormat := pf32bit;
  if (FBitmap.Width <> W) or (FBitmap.Height <> H) then FBitmap.SetSize(W, H);
  for Y := 0 to H - 1 do begin
    Row := FBitmap.ScanLine[Y];
    for X := 0 to W - 1 do begin
      Offset := (Y * W + X) * 4; A := Pixels[Offset + 3];
      if ((X div 12 + Y div 12) mod 2) = 0 then Base := 53 else Base := 61;
      for C := 0 to 2 do Row[X * 4 + 2 - C] := (Pixels[Offset + C] * A + Base * (255 - A) + 127) div 255;
      Row[X * 4 + 3] := 255;
    end;
  end;
  FPreviewDirty := False; Inc(FPreviewRenderCount);
end;

procedure TRigmEditorForm.PaintPreview(Sender: TObject);
var R: TRect; A, B, C: TPoint; P, Center: TPointF; Parent, Head: TRigmBone;
    Pose: TRigmPose; Canvas: TCanvas; Context: TRigmRenderContext; Radius: Double; CircleRadius: Integer;
    MeshPoints: TArray<TPoint>;
  function VisiblePart(const Id: string): Boolean;
  var Layer: TArtLayer; ParentId: string;
  begin
    Result := False; Layer := FEditor.Document.Art.FindLayer(Id);
    if (Layer = nil) or not Layer.Visible then Exit;
    ParentId := FEditor.Document.ParentId(Id);
    while ParentId <> '' do begin
      Layer := FEditor.Document.Art.FindLayer(ParentId); if (Layer = nil) or not Layer.Visible then Exit;
      ParentId := FEditor.Document.ParentId(ParentId);
    end;
    Result := True;
  end;
  function MeshColor(const Role: string): TColor;
  begin
    if Role = 'eye' then Result := $00DDBB55
    else if Role = 'brow' then Result := $00DD88EE
    else if Role = 'mouth' then Result := $0088DD55
    else if Role = 'hair' then Result := $0055AADD
    else if Role = 'body' then Result := $00DDDD55
    else if Role = 'fixed' then Result := clGray
    else if Role = 'correction' then Result := $005599EE
    else if Role = 'expression' then Result := $00AA77DD
    else Result := $00DD9955;
  end;
begin
  if (FPaint.Width < 1) or (FPaint.Height < 1) then Exit;
  if FPreviewDirty then RenderPreview;
  if (FPreviewBuffer.Width <> FPaint.Width) or (FPreviewBuffer.Height <> FPaint.Height) then
    FPreviewBuffer.SetSize(FPaint.Width, FPaint.Height);
  Canvas := FPreviewBuffer.Canvas; Canvas.Font.Assign(Font);
  Context := nil;
  // Composite the background, image and overlays before presenting one frame.
  try
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $002A2522; Canvas.FillRect(FPaint.ClientRect);
  R := PreviewRect; if not R.IsEmpty then Canvas.StretchDraw(R, FBitmap);
  if FShowReference then Exit;
  if (FEditor.Document.LastPage = rpPreview) and FDirect then Exit;
  Pose := nil; if FPreviewMode or (FEditor.Document.LastPage = rpPreview) then Pose := FEditor.Pose;
  Context := TRigmRenderContext.Create(FEditor.Document,Pose);
  if FShowMeshes and (FEditor.Document.LastPage in [rpMesh, rpPreview, rpBone]) then begin
    for var Mesh in FEditor.Document.Meshes do begin
      if not Mesh.Visible then Continue;
      if (Mesh.Id <> FEditor.SelectedId) and not VisiblePart(Mesh.PartId) then Continue;
      SetLength(MeshPoints,Length(Mesh.Vertices));
      for var I := 0 to High(Mesh.Vertices) do begin P := Context.VertexPosition(Mesh,I); MeshPoints[I] := ToScreen(P.X,P.Y); end;
      Canvas.Pen.Color := MeshColor(Mesh.Role); Canvas.Pen.Width := ScaleValue(1);
      for var Face in Mesh.Triangles do begin
        if (Face.A < 0) or (Face.B < 0) or (Face.C < 0) or (Face.A >= Length(Mesh.Vertices)) or (Face.B >= Length(Mesh.Vertices)) or (Face.C >= Length(Mesh.Vertices)) then Continue;
        A := MeshPoints[Face.A]; B := MeshPoints[Face.B]; C := MeshPoints[Face.C];
        Canvas.Polyline([A, B, C, A]);
      end;
      if Mesh.Id = FEditor.SelectedId then for var I := 0 to High(Mesh.Vertices) do begin
        A := MeshPoints[I]; if FDragging and (I = FVertex) then A := ToScreen(FDragPoint.X,FDragPoint.Y);
        Canvas.Brush.Color := IfThen(I = FVertex, clWhite, Canvas.Pen.Color);
        Canvas.Ellipse(A.X - ScaleValue(4), A.Y - ScaleValue(4), A.X + ScaleValue(5), A.Y + ScaleValue(5));
      end;
    end;
  end;
  if FShowBones and (FEditor.Document.LastPage in [rpBone, rpPreview]) then begin
    if (FEditor.Document.LastPage = rpBone) and not FPreviewMode then begin
      Head := nil;
      for var Param in FEditor.Document.Parameters do if Param.Id = 'headAngle' then Head := FEditor.Document.Bone(Param.BoneId);
      if (Head <> nil) and Head.Visible then begin
        if not FEditor.Document.FaceGuide(Center,Radius) then begin Center := TPointF.Create(Head.X,Head.Y); Radius := Min(FEditor.Document.Art.Width,FEditor.Document.Art.Height)*0.12; end;
        if FDragging and (FDragId = Head.Id) then Center := Center + FDragPoint - TPointF.Create(Head.X,Head.Y);
        A := ToScreen(Center.X,Center.Y); B := ToScreen(Center.X+Radius,Center.Y);
        CircleRadius := Max(ScaleValue(8),Abs(B.X-A.X)); Canvas.Pen.Color := $00DCCB8A; Canvas.Pen.Width := ScaleValue(1);
        Canvas.Pen.Style := psDot; Canvas.Brush.Style := bsClear;
        Canvas.Ellipse(A.X-CircleRadius,A.Y-CircleRadius,A.X+CircleRadius,A.Y+CircleRadius);
        P := TPointF.Create(Head.X,Head.Y); if FDragging and (FDragId = Head.Id) then P := FDragPoint;
        B := ToScreen(P.X,P.Y); Canvas.MoveTo(B.X,B.Y); Canvas.LineTo(A.X,A.Y);
        Canvas.Font.Color := Canvas.Pen.Color; Canvas.TextOut(A.X-CircleRadius,A.Y-CircleRadius-ScaleValue(18),'顔の位置');
        Canvas.Pen.Style := psSolid; Canvas.Brush.Style := bsSolid;
      end;
    end;
    for var Bone in FEditor.Document.Bones do begin
      if not Bone.Visible then Continue;
      P := Context.BoneMatrix(Bone.Id).Apply(Bone.X,Bone.Y);
      if FDragging and (Bone.Id = FEditor.SelectedId) then P := FDragPoint;
      A := ToScreen(P.X, P.Y); Parent := FEditor.Document.Bone(Bone.ParentId);
      Canvas.Pen.Color := IfThen(Bone.Id = FEditor.SelectedId, clWhite, $00E8AA65); Canvas.Pen.Width := ScaleValue(2);
      if (Parent <> nil) and Parent.Visible then begin
        P := Context.BoneMatrix(Parent.Id).Apply(Parent.X,Parent.Y);
        if FDragging and (Parent.Id = FDragId) then P := FDragPoint;
        B := ToScreen(P.X, P.Y);
        Canvas.Brush.Style := bsClear; Canvas.Polygon([B, Point((A.X + B.X) div 2 - 5, (A.Y + B.Y) div 2), A, Point((A.X + B.X) div 2 + 5, (A.Y + B.Y) div 2)]);
        Canvas.Brush.Style := bsSolid;
      end;
      Canvas.Brush.Color := Canvas.Pen.Color; Canvas.Ellipse(A.X - ScaleValue(5), A.Y - ScaleValue(5), A.X + ScaleValue(6), A.Y + ScaleValue(6));
      if FEditor.Document.LastPage = rpBone then begin
        Canvas.Brush.Style := bsClear; Canvas.Font.Color := Canvas.Pen.Color;
        var Caption := Bone.Name; if Bone.Id = FEditor.Document.WaistBoneId then Caption := Caption + '（腰支点）';
        Canvas.TextOut(A.X+ScaleValue(9),A.Y-ScaleValue(9),Caption); Canvas.Brush.Style := bsSolid;
      end;
    end;
  end;
  finally Context.Free; FPaint.Canvas.Draw(0, 0, FPreviewBuffer); end;
end;

procedure TRigmEditorForm.PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var P, World: TPointF; Best, Distance: Double;
begin
  if Button <> mbLeft then Exit; World := ToWorld(X, Y); Best := 1E30; FDragStart := World;
  if FEditor.Document.LastPage = rpBone then begin
    for var Bone in FEditor.Document.Bones do if Bone.Visible then begin
      Distance := Sqr(Bone.X - World.X) + Sqr(Bone.Y - World.Y);
      if Distance < Best then begin Best := Distance; FEditor.SelectedId := Bone.Id; end;
    end;
  end else if (FEditor.Document.LastPage = rpMesh) then begin
    var Mesh := FEditor.Document.Mesh(FEditor.SelectedId);
    if Mesh <> nil then for var I := 0 to High(Mesh.Vertices) do begin
      P := TPointF.Create(Mesh.Vertices[I].X, Mesh.Vertices[I].Y); Distance := Sqr(P.X - World.X) + Sqr(P.Y - World.Y);
      if Distance < Best then begin Best := Distance; FVertex := I; end;
    end;
  end else if (FEditor.Document.LastPage = rpPreview) and FDirect then begin
    FGamepadPreview.Release(FEditor.Pose);
    for var Layer in FEditor.Document.Layers do if (Layer.Kind = alkImage) and Layer.Visible and
      not FEditor.Document.IsReferencePart(Layer.Id) then begin
      var Part := FEditor.Document.Part(Layer.Id); Distance := Sqr(Part.X - World.X) + Sqr(Part.Y - World.Y);
      if Distance < Best then begin Best := Distance; FEditor.SelectedId := Layer.Id; end;
    end;
  end else Exit;
  if (FEditor.Document.LastPage = rpPreview) and FDirect and (FEditor.SelectedId <> '') then begin
    var SelectedPart := FEditor.Document.Part(FEditor.SelectedId);
    if SelectedPart.Role = 'eye' then FGamepadPreview.Target := gtEyes
    else if SelectedPart.Role = 'mouth' then FGamepadPreview.Target := gtMouth
    else if SelectedPart.Role = 'body' then FGamepadPreview.Target := gtBody
    else FGamepadPreview.Target := gtHead;
  end;
  FDragging := Best < 1E29; FDragOrigin := World;
  if FDragging and (FEditor.Document.LastPage = rpBone) then begin
    var Bone := FEditor.Document.Bone(FEditor.SelectedId);
    FDragOrigin := TPointF.Create(Bone.X, Bone.Y);
    if Bone.Locked and not FPreviewMode then FDragging := False;
  end;
  if FDragging and (FEditor.Document.LastPage = rpMesh) then begin
    var Mesh := FEditor.Document.Mesh(FEditor.SelectedId);
    FDragOrigin := TPointF.Create(Mesh.Vertices[FVertex].X, Mesh.Vertices[FVertex].Y);
    if Mesh.Locked then FDragging := False;
  end;
  FDragId := FEditor.SelectedId; FDragRevision := FEditor.Document.Art.Revision;
  FDragPoint := FDragOrigin; FPaint.MouseCapture := FDragging;
  BuildProperties; RefreshToolbars; FPaint.Invalidate;
end;

procedure TRigmEditorForm.PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var Part: TRigmPart;
begin
  if not FDragging then Exit;
  if (FDragRevision <> FEditor.Document.Art.Revision) or (FDragId <> FEditor.SelectedId) then begin
    FDragging := False; FPaint.MouseCapture := False; FPaint.Invalidate; Exit;
  end;
  var World := ToWorld(X, Y);
  FDragPoint := TPointF.Create(FDragOrigin.X + World.X - FDragStart.X, FDragOrigin.Y + World.Y - FDragStart.Y);
  if (FEditor.Document.LastPage = rpPreview) and FDirect then begin
    Part := FEditor.Document.Part(FEditor.SelectedId);
    if Part.Role = 'eye' then begin
      FEditor.Pose.Values.AddOrSetValue('gazeX', EnsureRange((FDragPoint.X - FDragStart.X) / 25, -1.0, 1.0));
      FEditor.Pose.Values.AddOrSetValue('gazeY', EnsureRange((FDragPoint.Y - FDragStart.Y) / 25, -1.0, 1.0));
    end else if Part.Role = 'mouth' then FEditor.Pose.Values.AddOrSetValue('mouthOpen', EnsureRange((FDragPoint.Y - FDragStart.Y) / 25, 0.0, 1.0))
    else if Part.Role = 'body' then FEditor.Pose.Values.AddOrSetValue('bodyAngle', EnsureRange((FDragPoint.X - FDragStart.X) / 2, -20.0, 20.0))
    else FEditor.Pose.Values.AddOrSetValue('headAngle', EnsureRange((FDragPoint.X - FDragStart.X) / 2, -30.0, 30.0));
    RefreshPreview;
  end else if FPreviewMode and (FEditor.Document.LastPage = rpBone) then begin
    var Bone := FEditor.Document.Bone(FEditor.SelectedId);
    FEditor.Pose.BoneOffsets.AddOrSetValue(Bone.Id, TPointF.Create(FDragPoint.X - Bone.X, FDragPoint.Y - Bone.Y)); RefreshPreview;
  end else FPaint.Invalidate;
end;

procedure TRigmEditorForm.PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var Args: TJSONObject;
begin
  if (Button <> mbLeft) or not FDragging then Exit;
  PreviewMouseMove(Sender, Shift, X, Y);
  if not FDragging then Exit;
  FDragging := False; FPaint.MouseCapture := False; FPaint.Invalidate;
  if FPreviewMode or (FEditor.Document.LastPage = rpPreview) then Exit;
  if SameValue(FDragPoint.X, FDragOrigin.X, 0.00001) and SameValue(FDragPoint.Y, FDragOrigin.Y, 0.00001) then Exit;
  Args := TJSONObject.Create; Args.AddPair('id', FDragId); AddN(Args, 'x', FDragPoint.X); AddN(Args, 'y', FDragPoint.Y);
  if FEditor.Document.LastPage = rpBone then begin AddB(Args, 'paired', FieldChecked('paired')); Execute('update-bone', Args); end
  else begin AddN(Args, 'vertex', FVertex); Execute('update-vertex', Args); end;
end;

procedure TRigmEditorForm.IssueFocus(Sender: TObject);
var Issue: TRigmIssue; Page: TRigmPage;
begin
  if FIssueList.ItemIndex < 0 then Exit; Issue := TRigmIssue(FIssueList.Items.Objects[FIssueList.ItemIndex]);
  Page := Issue.Page;
  if (Page = rpBone) and (FEditor.Document.Art.FindLayer(Issue.TargetId) <> nil) then Page := rpLayer;
  if FEditor.Document.CanOpen(Page) then begin
    var Id := Issue.TargetId; FEditor.SwitchPage(Page); FEditor.SelectedId := Id; RefreshView(Self);
  end else MessageDlg(Issue.Message, mtInformation, [mbOK], 0);
end;

procedure TRigmEditorForm.IssueAction(Sender: TObject);
var Action: Integer; Args: TJSONObject; Issue: TRigmIssue;
begin
  if Sender is TButton then Action := TButton(Sender).Tag else Action := TMenuItem(Sender).Tag;
  if Action >= 100 then begin FLog.Visible := Action = 100; FIssueList.Visible := Action = 101; Exit; end;
  if FIssueList.ItemIndex < 0 then Exit;
  if Action = 2 then begin IssueFocus(Sender); Exit; end;
  Issue := TRigmIssue(FIssueList.Items.Objects[FIssueList.ItemIndex]); Args := TJSONObject.Create; Args.AddPair('issueId', Issue.Id);
  case Action of 0: Execute('autofix', Args); 1: Execute('request-fix', Args); 3: Execute('ignore-issue', Args); end;
end;

procedure TRigmEditorForm.GamepadOptionsChanged(Sender: TObject);
begin
  if FPropertiesUpdating then Exit;
  FGamepadEnabled := FieldChecked('gamepadEnabled');
  if FFields.ContainsKey('gamepadTarget') then
    FGamepadPreview.Target := TRigmGamepadTarget(TComboBox(FFields['gamepadTarget']).ItemIndex);
  if not FGamepadEnabled then StopGamepadInput(Self);
end;

procedure TRigmEditorForm.StopGamepadInput(Sender: TObject);
begin
  if FDragging then begin
    FDragging := False;
    if FPaint <> nil then begin FPaint.MouseCapture := False; FPaint.Invalidate; end;
  end;
  if FGamepadInput <> nil then FGamepadInput.Disconnect;
  if (FGamepadPreview <> nil) and (FEditor <> nil) and FGamepadPreview.Release(FEditor.Pose) then
    if (FBitmap <> nil) and (FPaint <> nil) then RefreshPreview;
  FGamepadWasConnected := False;
end;

procedure TRigmEditorForm.TimerTick(Sender: TObject);
var State: TGamepadState; HaveReport: Boolean;
begin
  FEditor.PollMovie;
  if (FEditor.Document.LastPage <> rpPreview) or not FDirect or not Visible or not Active or not FGamepadEnabled then begin
    if FGamepadWasConnected or FGamepadInput.Connected then StopGamepadInput(Self);
    if not FGamepadEnabled then FGamepad := '操作OFF（チェックで接続）';
    if FFields.ContainsKey('gamepad') then TEdit(FFields['gamepad']).Text := FGamepad;
    Exit;
  end;
  if FDragging then Exit;
  HaveReport := FGamepadInput.Poll(State);
  if FGamepadInput.Connected <> FGamepadWasConnected then begin
    FGamepadPreview.Release(FEditor.Pose); FGamepadWasConnected := FGamepadInput.Connected;
  end;
  if not FGamepadInput.Connected then FGamepad := '未接続（1秒ごとにHIDを再探索）'
  else if not HaveReport then FGamepad := '接続済み・入力レポート待ち'
  else FGamepad := '接続済み・' + GamepadTargetName(FGamepadPreview.Target) + ' / A確定・B取消';
  if FFields.ContainsKey('gamepad') then TEdit(FFields['gamepad']).Text := FGamepad;
  if HaveReport and FGamepadPreview.Apply(State, GetTickCount64, FEditor.Document, FEditor.Pose) then RefreshPreview;
  if FFields.ContainsKey('gamepadTarget') then TComboBox(FFields['gamepadTarget']).ItemIndex := Ord(FGamepadPreview.Target);
end;

procedure TRigmEditorForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  if FEditor.MovieBusy then begin
    FEditor.CancelMovie; FStatus.Caption := '動画ジョブの取消完了後に閉じてください。'; CanClose := False; Exit;
  end;
  if (FMovieForm<>nil) and FMovieForm.Visible then FMovieForm.Close;
  CanClose := True;
  if FEditor.Modified then case MessageDlg('変更を保存しますか？', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: CanClose := SaveCharacter; mrCancel: CanClose := False;
  end;
end;

procedure TRigmEditorForm.Closed(Sender: TObject; var Action: TCloseAction);
begin Action := caFree; end;

procedure TRigmEditorForm.ShowMovieStudio(Sender: TObject);
begin
  if FMovieForm=nil then FMovieForm := TRigmMovieForm.CreateForSession(Self,FEditor.Movie);
  FMovieForm.Show; FMovieForm.BringToFront;
end;

end.
