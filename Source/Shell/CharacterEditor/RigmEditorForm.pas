// キャラクター編集の操作・選択・工程・プレビューを結び付ける。属性入力欄の生成と参照キャッシュは専用部品へ委譲する。
unit RigmEditorForm;

interface
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Menus, RigmModel, RigmEditor, RigmValidation, RigmPipe, ArtDocument, ArtLayerList,
  SwitchProInput, RigmGamepadPreview, RigmPropertyScrollBox, RigmIconToolbar, RigmEditorProperties;

type
  TRigmPreviewPaintBox = class(TPaintBox)
  public
    property MouseCapture;
  end;

  TRigmEditorForm = class(TForm)
  private
    FEditor        : TRigmEditor;                     // 画面が所有する文書・Undo/Redo・操作の入口。
    FPropertyEditor: TRigmEditorProperties;           // 画面が所有する属性部品。文書と入力コントロールは借用する。
    FMovieForm     : TForm;
    FPipe          : TRigmPipeHub;
    FPages         : array[TRigmPage] of TToolButton;
    FHeaderBar, FToolbar: TRigmIconToolbar;
    FRight, FBottom: TPanel;
    FPaint     : TRigmPreviewPaintBox;
    FLayerList : TArtLayerList;
    FObjectList: TListBox;
    FProperties: TScrollBox;
    FViewState : string;
    FLog       : TMemo;
    FIssueList : TListBox;
    FIssues    : TRigmIssues;
    FStatus, FPsdHint: TLabel;
    FBitmap, FPreviewBuffer: TBitmap; // 描画済みキャラクターと、ちらつき防止用の合成バッファ。
    FPreviewDirty      : Boolean; // 再描画時にキャラクター画像の再生成が必要か。
    FPreviewRenderCount: UInt64;
    FPreviewMode, FDirect, FShowBones, FShowMeshes, FUpdating, FShowReference: Boolean;
    FVertex  : Integer; // 属性とドラッグで共有する頂点番号。未選択は-1。
    FDragging: Boolean;
    FDragPoint, FDragStart, FDragOrigin: TPointF;
    FDragId      : string;
    FDragRevision: UInt64; // ドラッグ開始時のrevision。別操作による更新後の確定を拒否する。
    FPopup, FIssuePopup: TPopupMenu;
    FTimer         : TTimer;
    FGamepad       : string;
    FGamepadInput  : TSwitchProInput;
    FGamepadPreview: TRigmGamepadPreview;
    FGamepadEnabled, FGamepadWasConnected: Boolean;
    FUIPage : TRigmPage;
    FOnSaved: TNotifyEvent;
    function GetPropertyBuildCount: UInt64;
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
  public
    // 編集器・パイプ・表示部品を所有する画面を生成し、モニターのDPIへ合わせる。
    constructor Create(AOwner: TComponent); override;
    // 動画子画面と入力監視を閉じ、借用参照を持つ属性部品を文書より先に破棄する。
    destructor Destroy; override;
    // RIGMを開き、推定可能な未分類レイヤーを補完する。失敗時は現在の編集を保持する。
    procedure OpenFile(const FileName: string);
    // Nameの新規文書を作り、明示的にFileNameへ保存する。
    procedure NewCharacter(const Name, FileName: string);
    // 編集可能なサンプルを開く。既存ファイルへは保存しない。
    procedure OpenSample;
    // 分解済みPSDを読み込んだ画面を返す。既存パーツがあれば別画面で開いて現在の文書を保持する。
    function OpenSeparatedPsd(const FileName: string): TRigmEditorForm;
    // 保存先未指定ならダイアログで選ぶ。保存成功時に通知し、取消はFalseを返す。
    function SaveCharacter: Boolean;
    // 現在のキャラクターで動画制作画面を開く。既存の子画面があれば再利用する。
    procedure ShowMovieStudio(Sender: TObject);
    property Editor: TRigmEditor read FEditor; // 借用参照。フォームより長く保持しない。
    property OnSaved: TNotifyEvent read FOnSaved write FOnSaved; // 明示保存の成功後にライブラリ等を更新する通知。
    property PreviewRenderCount: UInt64 read FPreviewRenderCount; // 画像を生成した回数。オーバーレイだけの再描画は含まない。
    property PropertyBuildCount: UInt64 read GetPropertyBuildCount; // 属性欄更新の回数。不要な再構築を検出する計測値。
  end;

implementation
uses System.Math, System.StrUtils, System.IOUtils, System.UITypes, Winapi.Windows,
  Vcl.Dialogs, RigmJson, RigmRenderer, RigmSample, GamepadState, RigmToolbarIcons, RigmMovieForm, RigmEditorActions, RigmCharacterPreviewRendering;

constructor TRigmEditorForm.Create(AOwner: TComponent);
var Callbacks: TRigmEditorPropertyCallbacks;
begin
  inherited CreateScaledNew(AOwner,96);
  var TargetPPI := Monitor.PixelsPerInch;
  Name := 'RigmEditorWindow' + IntToHex(NativeUInt(Self), SizeOf(Pointer) * 2);
  Caption := 'RIGM Maker — 編集';
  Width := 1280; Height := 880; Constraints.MinWidth := 1000; Constraints.MinHeight := 700;
  Position := poScreenCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 10; DoubleBuffered := True;
  FEditor := TRigmEditor.Create; FBitmap := Vcl.Graphics.TBitmap.Create;
  FPreviewBuffer := Vcl.Graphics.TBitmap.Create; FPreviewBuffer.PixelFormat := pf32bit;
  FIssues := TRigmIssues.Create(True);
  FGamepadInput := TSwitchProInput.Create; FGamepadPreview := TRigmGamepadPreview.Create;
  FShowBones := True; FShowMeshes := True; FVertex := -1;
  BuildUI;
  Callbacks.ApplyProperties := ApplyProperties; Callbacks.ToolbarClick := ToolbarClick;
  Callbacks.ParameterChanged := ParameterChanged; Callbacks.VertexChanged := VertexChanged;
  Callbacks.GamepadOptionsChanged := GamepadOptionsChanged; Callbacks.RefreshParameterLabel := RefreshParameterLabel;
  FPropertyEditor := TRigmEditorProperties.Create(Self,FProperties,FEditor,Callbacks);
  ScaleForPPI(TargetPPI);
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
  FPropertyEditor.Free; FIssues.Free; FPreviewBuffer.Free; FBitmap.Free; FEditor.Free; inherited;
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
    if FPropertyEditor.SelectedId <> FEditor.SelectedId then begin
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















function TRigmEditorForm.GetPropertyBuildCount: UInt64;
begin Result := FPropertyEditor.BuildCount; end;
procedure TRigmEditorForm.BuildProperties;
begin
  if FPropertyEditor=nil then Exit;
  FPropertyEditor.Refresh(FPreviewMode,FDirect,FGamepadEnabled,FGamepad,FGamepadPreview.Target,FVertex);
end;
procedure AppendEditorOperation(List: TJSONArray; const Name: string; var Arguments: TJSONObject);
var O: TJSONObject;
begin O := TJSONObject.Create; List.AddElement(O); O.AddPair('command',Name); O.AddPair('args',Arguments); Arguments := nil; end;
procedure TRigmEditorForm.ApplyProperties(Sender: TObject);
var Args, Vertex, Weights, Weight, Batch: TJSONObject; ArrayValue: TJSONArray; Command: string;
begin
  Args := TJSONObject.Create; Vertex := nil; Weights := nil;
  try
    try
      Args.AddPair('id', FEditor.SelectedId); Args.AddPair('name', FPropertyEditor.FieldText('name')); AddB(Args, 'locked', FPropertyEditor.FieldChecked('locked'));
      case FEditor.Document.LastPage of
        rpLayer: begin
          Command := 'update-layer'; Args.AddPair('role', FPropertyEditor.FieldText('role').Split([' '])[0]); Args.AddPair('pairId', FPropertyEditor.ComboId('pairId', False));
          Args.AddPair('parentId', FPropertyEditor.ComboId('parentId', False)); Args.AddPair('boneId', FPropertyEditor.ComboId('boneId', True)); Args.AddPair('tags', FPropertyEditor.FieldText('tags'));
          for var Key in ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'opacity'] do AddN(Args, Key, FPropertyEditor.FieldNumber(Key)); AddB(Args, 'visible', FPropertyEditor.FieldChecked('visible'));
        end;
        rpBone: begin
          Command := 'update-bone'; Args.AddPair('parentId', FPropertyEditor.ComboId('parentId', True)); Args.AddPair('pairId', FPropertyEditor.ComboId('pairId', True));
          for var Key in ['x', 'y', 'minAngle', 'maxAngle'] do AddN(Args, Key, FPropertyEditor.FieldNumber(Key)); AddB(Args, 'paired', FPropertyEditor.FieldChecked('paired'));
        end;
        rpMesh: begin
          Command := 'update-mesh'; Args.AddPair('role', FPropertyEditor.FieldText('role')); AddN(Args, 'strength', FPropertyEditor.FieldNumber('strength'));
          AddB(Args, 'visible', FPropertyEditor.FieldChecked('visible')); AddB(Args, 'boundaryFixed', FPropertyEditor.FieldChecked('boundaryFixed'));
          if FPropertyEditor.Fields.ContainsKey('x') then begin
            Vertex := TJSONObject.Create; Vertex.AddPair('id', FEditor.SelectedId); AddN(Vertex, 'vertex', FVertex);
            for var Key in ['x', 'y', 'u', 'v'] do AddN(Vertex, Key, FPropertyEditor.FieldNumber(Key));
            Weights := TJSONObject.Create; Weights.AddPair('id', FEditor.SelectedId); AddN(Weights, 'vertex', FVertex);
            ArrayValue := TJSONArray.Create; Weights.AddPair('weights', ArrayValue);
            if FPropertyEditor.ComboId('bone1', True) <> '' then begin
              Weight := TJSONObject.Create; ArrayValue.AddElement(Weight); Weight.AddPair('boneId', FPropertyEditor.ComboId('bone1', True));
              AddN(Weight, 'value', IfThen(FPropertyEditor.ComboId('bone2', True) = '', 1.0, FPropertyEditor.FieldNumber('weight')));
            end;
            if FPropertyEditor.ComboId('bone2', True) <> '' then begin
              Weight := TJSONObject.Create; ArrayValue.AddElement(Weight); Weight.AddPair('boneId', FPropertyEditor.ComboId('bone2', True)); AddN(Weight, 'value', 1 - FPropertyEditor.FieldNumber('weight'));
            end;
          end;
        end;
      else Exit; end;
      Batch := TJSONObject.Create;
      try
        ArrayValue := TJSONArray.Create; Batch.AddPair('operations', ArrayValue);
        if (Vertex <> nil) and FPropertyEditor.FieldChecked('locked') and not FEditor.Document.Mesh(FEditor.SelectedId).Locked then Args.RemovePair('locked').Free;
        AppendEditorOperation(ArrayValue, Command, Args);
        if Vertex <> nil then AppendEditorOperation(ArrayValue, 'update-vertex', Vertex);
        if Weights <> nil then AppendEditorOperation(ArrayValue, 'set-weights', Weights);
        if (FEditor.Document.LastPage = rpMesh) and FPropertyEditor.FieldChecked('locked') and not FEditor.Document.Mesh(FEditor.SelectedId).Locked then begin
          var Lock := TJSONObject.Create; Lock.AddPair('id', FEditor.SelectedId); AddB(Lock, 'locked', True); AppendEditorOperation(ArrayValue, 'update-mesh', Lock);
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
  if (Id = FPropertyEditor.SelectedId) and (Id = FEditor.SelectedId) then Exit;
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
begin if FPropertyEditor.Updating then Exit; FVertex := TComboBox(Sender).ItemIndex; BuildProperties; RefreshToolbars; FPaint.Invalidate; end;

procedure TRigmEditorForm.ParameterChanged(Sender: TObject);
var Track: TTrackBar;
begin
  if FPropertyEditor.Updating then Exit;
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
      acHideBone: begin Command := 'hide-bone'; AddB(Args, 'paired', FPropertyEditor.FieldChecked('paired')); end;
      acRestoreBone: begin Command := 'restore-bone'; AddB(Args, 'paired', FPropertyEditor.FieldChecked('paired')); end;
      acResetBone: begin Command := 'reset-bone'; AddB(Args, 'paired', FPropertyEditor.FieldChecked('paired')); end;
      acGenerate: begin Command := 'generate-mesh'; Args.RemovePair('id').Free; Args.AddPair('id', ''); end;
      acAddVertex: begin Command := 'add-vertex'; AddN(Args, 'face', 0); end;
      acDeleteVertex: begin Command := 'delete-vertex'; AddN(Args, 'vertex', FVertex); end;
      acLayerUp: begin Command := 'move-layer'; AddN(Args, 'delta', -1); end;
      acLayerDown: begin Command := 'move-layer'; AddN(Args, 'delta', 1); end;
      acDeleteLayer: Command := 'delete-layer';
      acClassify: Command := 'classify-layers';
      acTriangles: begin
        Command := 'set-triangles'; ArrayValue := TJSONArray.Create; Args.AddPair('triangles', ArrayValue);
        for var Line in TMemo(FPropertyEditor.Fields['triangles']).Lines do if Trim(Line) <> '' then begin
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
var State: TRigmCharacterPreviewState;
begin
  if (FPaint.Width<1) or (FPaint.Height<1) then Exit;
  if FPreviewDirty then RenderPreview;
  if (FPreviewBuffer.Width<>FPaint.Width) or (FPreviewBuffer.Height<>FPaint.Height) then
    FPreviewBuffer.SetSize(FPaint.Width,FPaint.Height);
  FPreviewBuffer.Canvas.Font.Assign(Font);
  State.Document := FEditor.Document; State.Pose := FEditor.Pose;
  State.ImageRect := PreviewRect; State.PPI := ScaleValue(96); State.SelectedId := FEditor.SelectedId;
  State.PreviewMode := FPreviewMode; State.Direct := FDirect; State.ShowReference := FShowReference;
  State.ShowMeshes := FShowMeshes; State.ShowBones := FShowBones; State.Dragging := FDragging;
  State.Vertex := FVertex; State.DragId := FDragId; State.DragPoint := FDragPoint;
  try PaintCharacterPreview(FPreviewBuffer.Canvas,FPaint.ClientRect,FBitmap,State);
  finally FPaint.Canvas.Draw(0,0,FPreviewBuffer); end;
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
  if FEditor.Document.LastPage = rpBone then begin AddB(Args, 'paired', FPropertyEditor.FieldChecked('paired')); Execute('update-bone', Args); end
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
  if FPropertyEditor.Updating then Exit;
  FGamepadEnabled := FPropertyEditor.FieldChecked('gamepadEnabled');
  if FPropertyEditor.Fields.ContainsKey('gamepadTarget') then
    FGamepadPreview.Target := TRigmGamepadTarget(TComboBox(FPropertyEditor.Fields['gamepadTarget']).ItemIndex);
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
    if FPropertyEditor.Fields.ContainsKey('gamepad') then TEdit(FPropertyEditor.Fields['gamepad']).Text := FGamepad;
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
  if FPropertyEditor.Fields.ContainsKey('gamepad') then TEdit(FPropertyEditor.Fields['gamepad']).Text := FGamepad;
  if HaveReport and FGamepadPreview.Apply(State, GetTickCount64, FEditor.Document, FEditor.Pose) then RefreshPreview;
  if FPropertyEditor.Fields.ContainsKey('gamepadTarget') then TComboBox(FPropertyEditor.Fields['gamepadTarget']).ItemIndex := Ord(FGamepadPreview.Target);
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
