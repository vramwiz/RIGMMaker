// キャラクター属性の入力欄生成、再利用、値の読み取りを担当する。
// 文書の置換やrevision変更時には候補一覧の借用参照を解除し、旧文書への参照を残さない。
unit RigmEditorProperties;
interface
uses System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, RigmEditor, RigmModel, RigmGamepadPreview;
type
  TRigmParameterLabelEvent = procedure(Track: TTrackBar) of object;
  TRigmEditorPropertyCallbacks = record
    ApplyProperties      : TNotifyEvent;             // 入力値の適用要求。文書更新はフォームが担当する。
    ToolbarClick         : TNotifyEvent;             // 操作番号を持つ属性ボタンの通知。
    ParameterChanged     : TNotifyEvent;             // 未保存プレビューのパラメータ操作。
    VertexChanged        : TNotifyEvent;             // 編集対象頂点の変更。
    GamepadOptionsChanged: TNotifyEvent;             // ゲームパッド割当の変更。
    RefreshParameterLabel: TRigmParameterLabelEvent; // 実際のパラメータ値から表示名を更新する要求。
  end;
  TRigmEditorProperties = class
  private
    FOwner     : TWinControl;                        // 入力欄のフォント・DPIを参照する借用先。
    FProperties: TScrollBox;                   // 再利用する入力欄の所有者。フォームと共に生存する。
    FEditor    : TRigmEditor;                  // 表示する文書と選択を読む借用先。
    FCallbacks : TRigmEditorPropertyCallbacks;
    FPreviewMode,FDirect,FGamepadEnabled: Boolean;
    FGamepad            : string;
    FGamepadTarget      : TRigmGamepadTarget;
    FVertex             : Integer;
    FFields             : TDictionary<string, TControl>;  // 現在の属性キーから入力欄への非所有索引。
    FUsedProperties     : TDictionary<TControl, Boolean>; // 更新で再利用された欄。残りの欄を非表示にするための集合。
    FPropertiesUpdating : Boolean;                        // 入力値設定中のイベント再入を防ぐ。
    FPropertyLayoutReady: Boolean;
    FPropertySchema     : Integer;                        // 工程と操作モードで決まる欄構成。変更時だけ欄を作り直す。
    FPropertyDocument   : TRigmDocument;                  // 候補一覧が参照する文書。同じアドレスでもFileIdとrevisionを照合する。
    FPropertyFileId     : string;
    FPropertySelectedId : string;
    FPropertyRevision   : UInt64;                         // 候補の借用参照を失効させるArt.Revision。
    FPropertyBuildCount : UInt64;
    FPropertyY          : Integer;
    function PropertyControl(const Name: string; ControlClass: TControlClass): TControl;
    procedure PlaceProperty(Control: TControl; X,Y,Width,Height: Integer);
    function AddEdit(const Key,Caption,Value: string; ReadOnly: Boolean=False; X: Integer=12; EditWidth: Integer=328): TEdit;
    function AddNumber(const Key,Caption: string; Value: Double; Minimum,Maximum: Integer): TEdit;
    function AddCheck(const Key,Caption: string; Value: Boolean): TCheckBox;
    function AddCombo(const Key,Caption: string): TComboBox;
    procedure AddBoneCombo(const Key,Caption,Selected: string);
    procedure AddPartCombo(const Key,Caption,Selected: string; GroupsOnly: Boolean=False);
    function AddButton(Parent: TWinControl; const Caption,Name: string; Tag,X,Y,Width: Integer): TButton;
    procedure NumberChanged(Sender: TObject);
    procedure BuildProperties;
  public
    // Owner、入力パネル、Editorは借用する。欄の索引と参照キャッシュだけを所有する。
    constructor Create(Owner: TWinControl; Panel: TScrollBox; Editor: TRigmEditor; const Callbacks: TRigmEditorPropertyCallbacks);
    // 索引と参照キャッシュを破棄する。借用したフォーム・文書・入力欄は解放しない。
    destructor Destroy; override;
    // 表示用の現在状態で入力欄を更新する。Vertexは有効範囲へ補正し、作品は変更しない。
    procedure Refresh(PreviewMode,Direct,GamepadEnabled: Boolean; const Gamepad: string;
      GamepadTarget: TRigmGamepadTarget; var Vertex: Integer);
    // Keyの入力文字列を返す。欄が存在しない場合は空文字を返す。
    function FieldText(const Key: string): string;
    // 小数点をピリオドとして入力値を読む。数値でなければERigmで適用を中止する。
    function FieldNumber(const Key: string): Double;
    // チェック欄の値を返す。欄が存在しない場合はFalseを返す。
    function FieldChecked(const Key: string): Boolean;
    // 選択候補の安定IDを返す。Bone=Trueはボーン、Falseはレイヤー。未選択は空文字。
    function ComboId(const Key: string; Bone: Boolean): string;
    property Fields: TDictionary<string,TControl> read FFields; // 非所有索引。呼び出し側は欄の有無の確認にのみ使う。
    property Updating: Boolean read FPropertiesUpdating; // True中の変更通知を作品操作として処理しない。
    property SelectedId: string read FPropertySelectedId; // 現在の欄が表示している対象ID。新しい選択とのずれを検出する。
    property BuildCount: UInt64 read FPropertyBuildCount; // Refreshで属性を更新した累計回数。
  end;
implementation
uses System.Math, System.StrUtils, ArtDocument, RigmPropertyScrollBox, RigmEditorActions;
constructor TRigmEditorProperties.Create(Owner: TWinControl; Panel: TScrollBox; Editor: TRigmEditor;
  const Callbacks: TRigmEditorPropertyCallbacks);
begin
  inherited Create; FOwner := Owner; FProperties := Panel; FEditor := Editor; FCallbacks := Callbacks;
  FFields := TDictionary<string,TControl>.Create; FUsedProperties := TDictionary<TControl,Boolean>.Create;
end;
destructor TRigmEditorProperties.Destroy;
begin FUsedProperties.Free; FFields.Free; inherited; end;
procedure TRigmEditorProperties.Refresh(PreviewMode,Direct,GamepadEnabled: Boolean; const Gamepad: string;
  GamepadTarget: TRigmGamepadTarget; var Vertex: Integer);
begin
  FPreviewMode := PreviewMode; FDirect := Direct; FGamepadEnabled := GamepadEnabled;
  FGamepad := Gamepad; FGamepadTarget := GamepadTarget; FVertex := Vertex;
  try BuildProperties; finally Vertex := FVertex; end;
end;
function TRigmEditorProperties.AddButton(Parent: TWinControl; const Caption, Name: string; Tag, X, Y, Width: Integer): TButton;
begin
  if Parent = FProperties then begin
    Result := TButton(PropertyControl(Name, TButton));
    Result.Caption := Caption; Result.Tag := Tag;
    PlaceProperty(Result, X, Y, Width, 30); Result.OnClick := FCallbacks.ToolbarClick;
    Exit;
  end;
  Result := TButton.Create(FOwner); Result.Parent := Parent; Result.Caption := Caption; Result.Name := Name;
  Result.Tag := Tag; Result.SetBounds(X, Y, Width, 30); Result.OnClick := FCallbacks.ToolbarClick;
end;
function TRigmEditorProperties.PropertyControl(const Name: string; ControlClass: TControlClass): TControl;
begin
  Result := TControl(FProperties.FindComponent(Name));
  if Result = nil then begin
    Result := ControlClass.Create(FProperties); Result.Name := Name; Result.Parent := FProperties;
  end;
  FUsedProperties.AddOrSetValue(Result, True);
  Result.Visible := True;
end;

procedure TRigmEditorProperties.PlaceProperty(Control: TControl; X, Y, Width, Height: Integer);
begin
  Control.SetBounds(FOwner.ScaleValue(X), FOwner.ScaleValue(Y) - FProperties.VertScrollBar.Position,
    FOwner.ScaleValue(Width), FOwner.ScaleValue(Height));
end;

function TRigmEditorProperties.AddEdit(const Key, Caption, Value: string; ReadOnly: Boolean; X, EditWidth: Integer): TEdit;
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

function TRigmEditorProperties.AddNumber(const Key, Caption: string; Value: Double; Minimum, Maximum: Integer): TEdit;
var Track: TTrackBar;
begin
  Result := AddEdit(Key, Caption, FloatToStr(Value, TFormatSettings.Invariant), False, 264, 76);
  Track := TTrackBar(PropertyControl('Slider' + Key, TRigmFineTrackBar));
  PlaceProperty(Track, 8, FPropertyY - 36, 252, 30); Track.Min := Minimum; Track.Max := Maximum;
  Track.Position := EnsureRange(Round(Value), Minimum, Maximum); Track.TickStyle := tsNone; Track.OnChange := NumberChanged;
end;

procedure TRigmEditorProperties.NumberChanged(Sender: TObject);
var Key: string;
begin
  if FPropertiesUpdating then Exit;
  Key := Copy(TTrackBar(Sender).Name, 7, MaxInt);
  if FFields.ContainsKey(Key) then TEdit(FFields[Key]).Text := IntToStr(TTrackBar(Sender).Position);
end;

function TRigmEditorProperties.AddCheck(const Key, Caption: string; Value: Boolean): TCheckBox;
begin
  Result := TCheckBox(PropertyControl('Check' + Key, TCheckBox)); Result.Caption := Caption;
  PlaceProperty(Result, 12, FPropertyY, 328, 26); Result.Checked := Value;
  FFields.AddOrSetValue(Key, Result); Inc(FPropertyY, 34);
end;

function TRigmEditorProperties.AddCombo(const Key, Caption: string): TComboBox;
var LabelControl: TLabel;
begin
  LabelControl := TLabel(PropertyControl('Label' + Key, TLabel)); LabelControl.AutoSize := False;
  LabelControl.Caption := Caption; PlaceProperty(LabelControl, 12, FPropertyY, 335, 20);
  Result := TComboBox(PropertyControl('Combo' + Key, TComboBox));
  PlaceProperty(Result, 12, FPropertyY + 22, 328, 25); Result.Style := csDropDownList;
  FFields.AddOrSetValue(Key, Result); Inc(FPropertyY, 57);
end;

procedure TRigmEditorProperties.AddBoneCombo(const Key, Caption, Selected: string);
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

procedure TRigmEditorProperties.AddPartCombo(const Key, Caption, Selected: string; GroupsOnly: Boolean);
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

procedure TRigmEditorProperties.BuildProperties;
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
      AddButton(FProperties, '属性を適用', 'ApplyLayerPropertiesButton', 0, 12, FPropertyY, 158).OnClick := FCallbacks.ApplyProperties; Inc(FPropertyY, 40);
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
      AddButton(FProperties, '属性を適用', 'ApplyBonePropertiesButton', 0, 12, FPropertyY, 158).OnClick := FCallbacks.ApplyProperties; Inc(FPropertyY, 42);
      if FPreviewMode then begin
        LabelControl := TLabel(PropertyControl('LabelBonePose', TLabel)); LabelControl.AutoSize := False;
        LabelControl.Caption := '選択ボーンのプレビュー角度'; PlaceProperty(LabelControl, 12, FPropertyY, 320, 20);
        Track := TTrackBar(PropertyControl('BonePoseSlider', TRigmFineTrackBar)); Track.Min := Round(B.MinAngle*100); Track.Max := Round(B.MaxAngle*100);
        Angle := 0; FEditor.Pose.BoneAngles.TryGetValue(FEditor.SelectedId, Angle); Track.Position := Round(Angle*100);
        PlaceProperty(Track, 12, FPropertyY + 24, 328, 32); Track.TickStyle := tsNone; Track.Tag := -1; Track.OnChange := FCallbacks.ParameterChanged;
        FCallbacks.RefreshParameterLabel(Track);
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
      Combo.OnChange := FCallbacks.VertexChanged;
      if Length(M.Vertices) > 0 then begin
        AddEdit('x', '頂点 X', FloatToStr(M.Vertices[FVertex].X, TFormatSettings.Invariant)); AddEdit('y', '頂点 Y', FloatToStr(M.Vertices[FVertex].Y, TFormatSettings.Invariant));
        AddEdit('u', 'UV U（0～1）', FloatToStr(M.Vertices[FVertex].U, TFormatSettings.Invariant)); AddEdit('v', 'UV V（0～1）', FloatToStr(M.Vertices[FVertex].V, TFormatSettings.Invariant));
        var Bone1 := ''; var Bone2 := ''; var Weight := 1.0;
        if Length(M.Vertices[FVertex].Weights) > 0 then begin Bone1 := M.Vertices[FVertex].Weights[0].BoneId; Weight := M.Vertices[FVertex].Weights[0].Value; end;
        if Length(M.Vertices[FVertex].Weights) > 1 then Bone2 := M.Vertices[FVertex].Weights[1].BoneId;
        AddBoneCombo('bone1', 'ウェイト ボーン1', Bone1); AddBoneCombo('bone2', 'ウェイト ボーン2', Bone2);
        AddEdit('weight', 'ボーン1のウェイト（残りをボーン2へ）', FloatToStr(Weight, TFormatSettings.Invariant));
      end;
      AddButton(FProperties, '属性・選択頂点を適用', 'ApplyMeshPropertiesButton', 0, 12, FPropertyY, 210).OnClick := FCallbacks.ApplyProperties; Inc(FPropertyY, 45);
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
        AddCheck('gamepadEnabled', 'Proコントローラーで操作する', FGamepadEnabled).OnClick := FCallbacks.GamepadOptionsChanged;
        Combo := AddCombo('gamepadTarget', '左スティックの対象（十字キー上下で切替）');
        if Combo.Items.Count = 0 then Combo.Items.AddStrings(['目', '口', '頭', '上半身']); Combo.ItemIndex := Ord(FGamepadTarget);
        Combo.OnChange := FCallbacks.GamepadOptionsChanged;
        AddEdit('gamepadHelp1', '操作', '右スティック=顔角度 / R+右=上半身 / L=微調整', True);
        AddEdit('gamepadHelp2', '操作', 'ZR=瞬き / ZL=口 / A=確定 / B=取消 / Y=初期値', True);
      end else for I := 0 to High(FEditor.Document.Parameters) do begin
        var Param := FEditor.Document.Parameters[I];
        LabelControl := TLabel(PropertyControl('LabelParameter' + Param.Id, TLabel)); LabelControl.AutoSize := False; LabelControl.Caption := Param.Name;
        PlaceProperty(LabelControl, 12, FPropertyY, 330, 22); Inc(FPropertyY, 25);
        Track := TTrackBar(PropertyControl('Parameter' + Param.Id, TRigmFineTrackBar));
        PlaceProperty(Track, 8, FPropertyY, 335, 36); Track.Min := Round(Param.Minimum * 100); Track.Max := Round(Param.Maximum * 100);
        Track.Position := Round(FEditor.Pose.Value(Param.Id, Param.Initial) * 100); Track.TickStyle := tsNone; Track.Tag := I;
        Track.OnChange := FCallbacks.ParameterChanged; Inc(FPropertyY, 51);
        FCallbacks.RefreshParameterLabel(Track);
      end;
    end;
  end;
  finally
    for I := 0 to FProperties.ControlCount - 1 do
      FProperties.Controls[I].Visible := FUsedProperties.ContainsKey(FProperties.Controls[I]);
    FProperties.VertScrollBar.Range := FOwner.ScaleValue(FPropertyY + 44);
    FProperties.EnableAlign; FPropertiesUpdating := False;
    FPropertySelectedId := FEditor.SelectedId;
  end;
end;

function TRigmEditorProperties.FieldText(const Key: string): string;
begin
  Result := ''; if not FFields.ContainsKey(Key) then Exit;
  if FFields[Key] is TEdit then Result := TEdit(FFields[Key]).Text
  else if FFields[Key] is TComboBox then Result := TComboBox(FFields[Key]).Text;
end;

function TRigmEditorProperties.FieldNumber(const Key: string): Double;
begin
  if not TryStrToFloat(FieldText(Key), Result, TFormatSettings.Invariant) then raise ERigm.Create('数値を入力してください: ' + Key);
end;

function TRigmEditorProperties.FieldChecked(const Key: string): Boolean;
begin Result := FFields.ContainsKey(Key) and TCheckBox(FFields[Key]).Checked; end;

function TRigmEditorProperties.ComboId(const Key: string; Bone: Boolean): string;
var Combo: TComboBox; Obj: TObject;
begin
  Result := ''; if not FFields.ContainsKey(Key) then Exit;
  Combo := TComboBox(FFields[Key]); if Combo.ItemIndex < 0 then Exit;
  Obj := Combo.Items.Objects[Combo.ItemIndex]; if Obj = nil then Exit;
  if Bone then Result := TRigmBone(Obj).Id else Result := TArtLayer(Obj).Id;
end;
end.
