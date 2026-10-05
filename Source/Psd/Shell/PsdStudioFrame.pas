unit PsdStudioFrame;

// PSD専用の立ち絵編集画面。既存一覧からも独立EXEからも同じセッションを開く。
interface
uses System.Classes, System.SysUtils, System.JSON, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, PsdSession, PsdMotionReferenceForm;
type
  TPsdStudioFrame = class(TFrame)
  private
    FSession: TPsdSession; FTree: TTreeView; FPreview: TPaintBox; FBitmap: TBitmap;
    FExpression, FGaze, FPhone, FBranch, FMotion: TComboBox;
    FStatus: TLabel; FTimer: TTimer; FBlink, FPlay: TCheckBox;
    FStart: UInt64; FTime: Double; FSync: Boolean;
    FOnSaved, FOnReturn: TNotifyEvent;
    FPages: TPageControl; FPreviewHost: TPanel; FReferencePage: TPsdMotionReferencePage;
    FNameEdit, FSupplementEdit: TEdit; FProductionMemo: TMemo; FPrevious,FNext: TButton;
    FLayerX,FLayerY: TEdit;
    FInfoDirty,FPageChanging: Boolean; FUiCharacterId,FSelectedLayerId: string;
    function Args: TJSONObject;
    function Execute(const Command: string; A: TJSONObject): Boolean;
    procedure Refresh(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure ViewChanged(Sender: TObject);
    procedure TreeChoice(Sender: TObject);
    procedure OpenCharacterPath(const Path: string);
    procedure OpenPackage(Sender: TObject);
    procedure ImportPrepared(Sender: TObject);
    procedure ImportPsd(Sender: TObject);
    procedure AddLayer(Sender: TObject);
    procedure AddPose(Sender: TObject);
    procedure AddSequence(Sender: TObject);
    procedure Save(Sender: TObject);
    procedure ExportPsd(Sender: TObject);
    procedure ExportFrame(Sender: TObject);
    procedure LoadLab(Sender: TObject);
    procedure InspectProduction(Sender: TObject);
    procedure EditCharacterInfo(Sender: TObject);
    procedure InfoChanged(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    procedure Navigate(Sender: TObject);
    procedure TreeSelectionChanged(Sender: TObject; Node: TTreeNode);
    function ApplyReference(Sender: TObject): Boolean;
    procedure ReloadReference(Sender: TObject);
    function HasPageDraft: Boolean;

    procedure ReturnToManagement(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateForCharacter(AOwner: TComponent; const Root,Path: string; AutoOpen: Boolean = False);
    destructor Destroy; override;
    procedure CaptureSmoke(const Path: string); // 表示部品をアプリ自身で描画する検証用入口。
    procedure VerifyGuiFlow(const ResultPath: string); // アプリ所有の部品/イベントを使う限定回帰。
    procedure VerifyPageFlow(const ResultPath: string);
    function RequestFinish: Boolean;
    procedure SetActive(Value: Boolean);
    property OnReturn: TNotifyEvent read FOnReturn write FOnReturn;
    property Session: TPsdSession read FSession;
    property OnSaved: TNotifyEvent read FOnSaved write FOnSaved;
    function ActivateCharacter(const Path: string): Boolean;
  end;

implementation
{$R *.dfm}
uses System.IOUtils, System.Hash, System.Math, System.StrUtils, System.UITypes,
  System.Generics.Collections, Winapi.Windows, Winapi.Messages, Vcl.Dialogs, Vcl.Imaging.pngimage,
  ArtDocument, PsdJson, PsdWorkspace, PsdProduction;

constructor TPsdStudioFrame.Create(AOwner: TComponent);
begin
  var Root := PSD_DEFAULT_ROOT;
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--root' then Root := ParamStr(Index + 1);
  CreateForCharacter(AOwner,Root,'');
end;
constructor TPsdStudioFrame.CreateForCharacter(AOwner: TComponent; const Root,Path: string; AutoOpen: Boolean);
  function Button(Parent: TWinControl; const Text: string; Event: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self); Result.Parent := Parent; Result.Caption := Text;
    Result.Align := alTop; Result.Height := 30; Result.OnClick := Event;
  end;
  function Combo(Parent: TWinControl; const LabelText: string): TComboBox;
  begin
    var Row := TPanel.Create(Self); Row.Parent := Parent; Row.Align := alTop; Row.Height := 54; Row.BevelOuter := bvNone;
    var L := TLabel.Create(Self); L.Parent := Row; L.Align := alTop; L.Caption := LabelText; L.Height := 22;
    Result := TComboBox.Create(Self); Result.Parent := Row; Result.Align := alBottom; Result.Style := csDropDownList;
    Result.OnChange := ViewChanged;
  end;
begin
  inherited Create(AOwner); Width := 1280; Height := 820; Align := alClient;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  FSync := True; // 名前付けなどの初期値設定をユーザーの下書き変更として扱わない。
  FSession := PsdSession.TPsdSession.Create(Root); FSession.OnChanged := Refresh; FBitmap := Vcl.Graphics.TBitmap.Create;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 38; Header.BevelOuter := bvNone;
  var ReturnButton := Button(Header,'キャラ管理へ戻る',ReturnToManagement); ReturnButton.Align := alRight; ReturnButton.Width := 170; ReturnButton.Name := 'PsdReturnToManagement';
  var OpenButton := Button(Header,'キャラを開く',OpenPackage); OpenButton.Align := alLeft; OpenButton.Width := 150;
  var SaveButton := Button(Header,'キャラを保存',Save); SaveButton.Align := alLeft; SaveButton.Width := 150;
  var InspectButton := Button(Header,'PSDの必須仕様を検査',InspectProduction); InspectButton.Align := alLeft; InspectButton.Width := 200;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 62; FStatus.WordWrap := True;
  FStatus.Caption := '分離済み素材を登録するか、キャラを開いてください。';
  var Navigation := TPanel.Create(Self); Navigation.Parent := Self; Navigation.Align := alBottom; Navigation.Height := 38; Navigation.BevelOuter := bvNone;
  FNext := Button(Navigation,'次へ',Navigate); FNext.Align := alRight; FNext.Width := 120; FNext.Tag := 1; FNext.Name := 'PsdNext';
  FPrevious := Button(Navigation,'戻る',Navigate); FPrevious.Align := alRight; FPrevious.Width := 120; FPrevious.Tag := -1; FPrevious.Name := 'PsdPrevious';
  FPages := TPageControl.Create(Self); FPages.Parent := Self; FPages.Align := alClient; FPages.Name := 'PsdCharacterPages';
  for var Text in ['レイヤー','表情','ボーン基準','動作確認'] do begin var Page := TTabSheet.Create(Self); Page.PageControl := FPages; Page.Caption := Text; end;
  var Left := TPanel.Create(Self); Left.Parent := FPages.Pages[0]; Left.Align := alLeft; Left.Width := 280; Left.BevelOuter := bvNone;
  var Info := TPanel.Create(Self); Info.Parent := Left; Info.Align := alTop; Info.Height := 126; Info.BevelOuter := bvNone;
  var L := TLabel.Create(Self); L.Parent := Info; L.SetBounds(8,2,250,20); L.Caption := 'キャラ名';
  FNameEdit := TEdit.Create(Self); FNameEdit.Parent := Info; FNameEdit.SetBounds(8,22,264,26); FNameEdit.OnChange := InfoChanged; FNameEdit.Name := 'PsdCharacterName';
  L := TLabel.Create(Self); L.Parent := Info; L.SetBounds(8,50,250,20); L.Caption := '補足名（衣装など）';
  FSupplementEdit := TEdit.Create(Self); FSupplementEdit.Parent := Info; FSupplementEdit.SetBounds(8,70,264,26); FSupplementEdit.OnChange := InfoChanged;
  var ApplyInfo := Button(Info,'基本情報を反映',EditCharacterInfo); ApplyInfo.Align := alBottom; ApplyInfo.Height := 28; ApplyInfo.Name := 'PsdInfoApply';
  var Tools := TPanel.Create(Self); Tools.Parent := Left; Tools.Align := alTop; Tools.Height := 236; Tools.Top := Info.Height; Tools.BevelOuter := bvNone;
  Button(Tools, '分離済み素材のmanifestを登録', ImportPrepared);
  Button(Tools, '外部PSDを参照登録', ImportPsd); Button(Tools, '選択部位に透過PNGを追加', AddLayer);
  Button(Tools, '非正面の全身ポーズを追加', AddPose); Button(Tools, '全身PNG連番を追加（24fps）', AddSequence);
  Button(Tools, 'PSDを書き出す', ExportPsd);
  var Placement := TPanel.Create(Self); Placement.Parent := Tools; Placement.Align := alBottom; Placement.Height := 56; Placement.BevelOuter := bvNone;
  L := TLabel.Create(Self); L.Parent := Placement; L.SetBounds(8,2,250,20); L.Caption := '追加PNGの配置（元キャンバス X / Y）';
  FLayerX := TEdit.Create(Self); FLayerX.Parent := Placement; FLayerX.SetBounds(8,24,124,26); FLayerX.Text := '0';
  FLayerY := TEdit.Create(Self); FLayerY.Parent := Placement; FLayerY.SetBounds(140,24,132,26); FLayerY.Text := '0';
  FTree := TTreeView.Create(Self); FTree.Parent := Left; FTree.Align := alClient; FTree.OnDblClick := TreeChoice; FTree.OnChange := TreeSelectionChanged;
  var Expressions := TPanel.Create(Self); Expressions.Parent := FPages.Pages[1]; Expressions.Align := alRight; Expressions.Width := 360; Expressions.BevelOuter := bvNone;
  FGaze := Combo(Expressions, '視線（画面基準）');
  FPhone := Combo(Expressions, '音素口形（手動確認）'); FPhone.Items.AddStrings(['表情の口', 'a', 'i', 'u', 'e', 'o', 'N', 'closed']); FPhone.ItemIndex := 0;
  FExpression := Combo(Expressions, '表情');
  FBlink := TCheckBox.Create(Self); FBlink.Parent := Expressions; FBlink.Align := alTop; FBlink.Caption := '約4秒ごとに瞬き'; FBlink.Checked := True; FBlink.OnClick := ViewChanged;
  FProductionMemo := TMemo.Create(Self); FProductionMemo.Parent := Expressions; FProductionMemo.Align := alBottom; FProductionMemo.Height := 250;
  FProductionMemo.ReadOnly := True; FProductionMemo.ScrollBars := ssVertical; FProductionMemo.Name := 'PsdProductionResults';
  var Motion := TPanel.Create(Self); Motion.Parent := FPages.Pages[3]; Motion.Align := alRight; Motion.Width := 260; Motion.BevelOuter := bvNone;
  FMotion := Combo(Motion, '小さな動き'); FMotion.Items.AddStrings(['none', 'breathe', 'sway', 'jump']); FMotion.ItemIndex := 1;
  FBranch := Combo(Motion, '正面 / 非正面（全身）');
  FPlay := TCheckBox.Create(Self); FPlay.Parent := Motion; FPlay.Align := alTop; FPlay.Caption := '再生'; FPlay.Checked := True;
  Button(Motion, 'FullHD PNGを書き出す', ExportFrame); Button(Motion, '音素LABを読み込む', LoadLab);
  FPreviewHost := TPanel.Create(Self); FPreviewHost.Parent := FPages.Pages[0]; FPreviewHost.Align := alClient; FPreviewHost.BevelOuter := bvNone;
  FPreview := TPaintBox.Create(Self); FPreview.Parent := FPreviewHost; FPreview.Align := alClient; FPreview.OnPaint := PaintPreview;
  FReferencePage := TPsdMotionReferencePage.CreateForParent(Self,FPages.Pages[2]); FReferencePage.Name := 'PsdMotionReferenceEditor'; FReferencePage.OnApply := ApplyReference; FReferencePage.OnReload := ReloadReference;
  FPages.ActivePageIndex := 0; FPages.OnChange := PageChanged; PageChanged(Self);
  FTimer := TTimer.Create(Self); FTimer.Interval := 33; FTimer.OnTimer := Tick; FStart := GetTickCount64;
  FSync := False;
  if Path<>'' then begin
    if SameText(ExtractFileExt(Path),'.psd') then begin var A := Args; A.AddPair('path',Path); Execute('import-psd',A); end
    else OpenCharacterPath(Path);
  end
  else if AutoOpen then begin
    var Files := TDirectory.GetFiles(FSession.Workspace.Resolve('Characters', False), '*.psdchar',TSearchOption.soAllDirectories);
    if Length(Files) > 0 then OpenCharacterPath(Files[0]);
  end;
end;
destructor TPsdStudioFrame.Destroy;
begin if FTimer <> nil then FTimer.Enabled := False; FSession.Free; FBitmap.Free; inherited; end;
function TPsdStudioFrame.Args: TJSONObject;
begin
  var Status := FSession.Status;
  try
    Result := TJSONObject.Create; Result.AddPair('sessionId', S(Status, 'sessionId')); Result.AddPair('revision', S(Status, 'revision'));
  finally Status.Free; end;
end;
function TPsdStudioFrame.Execute(const Command: string; A: TJSONObject): Boolean;
begin
  Result := False;
  try
    try
      if MatchText(Command,['open','import-prepared','import-psd']) and HasPageDraft then raise Exception.Create('ページ内の編集中の設定を反映してからキャラを切り替えてください。');
      var R := FSession.Command(Command, A); R.Free;
      Result := True;
      if (FSession.SavedPath<>'') and not FSession.Dirty and
        MatchText(Command,['check-production','set-info','set-motion-reference','select-part','set-expression','add-layer-file','add-nonfront-file']) and Assigned(FOnSaved) then FOnSaved(Self);
    except on E: Exception do FStatus.Caption := E.Message; end;
  finally A.Free; end;
end;
procedure TPsdStudioFrame.Refresh(Sender: TObject);
  procedure AddTree(Layers: TList<TArtLayer>; Parent: TTreeNode);
  begin
    for var L in Layers do begin var Node := FTree.Items.AddChildObject(Parent, L.Name, L); AddTree(L.Children, Node); end;
  end;
begin
  FSync := True;
  try
    FTree.Items.Clear; FExpression.Clear; FGaze.Clear; FBranch.Clear;
    if FSession.Character = nil then Exit;
    var C := FSession.Character;
    if (FUiCharacterId<>C.Id) or not FInfoDirty then begin
      FNameEdit.Text := C.Name; FSupplementEdit.Text := C.SupplementName; FInfoDirty := False;
    end;
    FUiCharacterId := C.Id;
    if C.Policy = 'external' then AddTree(C.Document.Roots, nil);
    for var V in Arr(C.Settings, 'groups') do begin
      var G := TJSONObject(V); var Node := FTree.Items.AddObject(nil, S(G, 'name'), C.Document.FindLayer(S(G, 'id')));
      for var P in Arr(G, 'partIds') do begin
        var L := C.Document.FindLayer(P.Value); var Text := L.Name;
        if P.Value = S(G, 'defaultPartId') then Text := Text + ' ✓';
        FTree.Items.AddChildObject(Node, Text, L);
      end;
    end;
    for var Index := 0 to FTree.Items.Count-1 do
      if TArtLayer(FTree.Items[Index].Data).Id=FSelectedLayerId then begin FTree.Selected := FTree.Items[Index]; Break; end;
    FReferencePage.BindCharacter(C,FSession.Workspace,(FPages.ActivePageIndex=2) and Showing);
    FProductionMemo.Clear;
    if C.Production.GetValue('checks') is TJSONArray then for var V in Arr(C.Production,'checks') do begin
      var Check := TJSONObject(V); FProductionMemo.Lines.Add(IfThen(B(Check,'passed'),'○ ','× ')+S(Check,'title')+': '+S(Check,'message'));
    end;
    FExpression.Items.Add('初期設定'); for var P in Obj(C.Settings, 'expressions') do FExpression.Items.Add(P.JsonString.Value);
    FExpression.ItemIndex := Max(0, FExpression.Items.IndexOf(FSession.State.Expression));
    for var Key in ['front', 'left', 'left-up', 'up', 'right-up', 'right'] do
      if Obj(C.Settings, 'gaze').GetValue(Key) <> nil then FGaze.Items.Add(Key);
    if FGaze.Items.Count = 0 then FGaze.Items.Add('front'); FGaze.ItemIndex := Max(0, FGaze.Items.IndexOf(FSession.State.Gaze));
    FBranch.Items.Add('正面');
    for var V in Arr(C.Settings, 'nonFront') do FBranch.Items.Add(S(TJSONObject(V), 'name'));
    FBranch.ItemIndex := 0;
    for var Index := 0 to Arr(C.Settings, 'nonFront').Count - 1 do
      if S(TJSONObject(Arr(C.Settings, 'nonFront')[Index]), 'id') = FSession.State.NonFrontId then FBranch.ItemIndex := Index + 1;
    FMotion.ItemIndex := Max(0, FMotion.Items.IndexOf(FSession.State.Motion));
    FPhone.ItemIndex := 0; if FSession.State.HasPhoneme then FPhone.ItemIndex := Max(0, FPhone.Items.IndexOf(FSession.State.Phoneme));
    FBlink.Checked := FSession.State.AutoBlink;
    var Reason: string; var Ready := PsdReadyForScript(C,Reason);
    Caption := 'PSD立ち絵スタジオ — ' + C.Name+IfThen(C.SupplementName<>'',' / '+C.SupplementName,'')+IfThen(Ready,'（完成）','（未完成）');
    FStatus.Caption := IfThen(FSession.Dirty, '未保存　', '保存済み　') + IfThen(Ready,'完成・台本で選択可','未完成・台本へ新規追加不可')+'　'+ C.Name + #13#10 +
      FSession.SavedPath + #13#10 + '接続: ' + FSession.ConnectionFile;
  finally FSync := False; end;
end;
procedure TPsdStudioFrame.ViewChanged(Sender: TObject);
begin
  if FSync or (FSession.Character = nil) then Exit;
  try
    var V := FSession.State;
    V.Expression := ''; if FExpression.ItemIndex > 0 then V.Expression := FExpression.Text;
    V.Gaze := FGaze.Text; V.Phoneme := FPhone.Text; V.HasPhoneme := FPhone.ItemIndex > 0; V.AutoBlink := FBlink.Checked;
    V.NonFrontId := ''; if FBranch.ItemIndex > 0 then V.NonFrontId := S(TJSONObject(Arr(FSession.Character.Settings, 'nonFront')[FBranch.ItemIndex - 1]), 'id');
    V.Motion := FMotion.Text; FSession.SetView(V);
    var Front := V.NonFrontId = ''; FExpression.Enabled := Front; FGaze.Enabled := Front; FPhone.Enabled := Front; FBlink.Enabled := Front;
  except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
end;
procedure TPsdStudioFrame.TreeChoice(Sender: TObject);
begin
  if (FTree.Selected = nil) or (FTree.Selected.Parent = nil) then Exit;
  if FSession.Character.Policy <> 'managed' then Exit;
  var A := Args; A.AddPair('groupId', TArtLayer(FTree.Selected.Parent.Data).Id); A.AddPair('partId', TArtLayer(FTree.Selected.Data).Id);
  Execute('select-part', A);
end;
procedure TPsdStudioFrame.Tick(Sender: TObject);
begin
  if (FSession.Character = nil) or not Showing then Exit;
  if FPlay.Checked then FTime := (GetTickCount64 - FStart) / 1000 else FStart := GetTickCount64 - UInt64(Round(FTime * 1000));
  try
    var Pixels := FSession.Frame(FTime, 960, 540); FBitmap.PixelFormat := pf32bit; FBitmap.SetSize(960, 540);
    for var Y := 0 to 539 do begin
      // VCLのScanLineは画像上端を0として返す。RGBAの行番号をそのまま対応させる。
      var Row := PByte(FBitmap.ScanLine[Y]);
      for var X := 0 to 959 do begin
        var P := (Y * 960 + X) * 4; var A := Pixels[P + 3]; var BG := 42 + ((X div 16 + Y div 16) mod 2) * 12;
        Row[X * 4] := (Pixels[P + 2] * A + BG * (255 - A)) div 255;
        Row[X * 4 + 1] := (Pixels[P + 1] * A + BG * (255 - A)) div 255;
        Row[X * 4 + 2] := (Pixels[P] * A + BG * (255 - A)) div 255; Row[X * 4 + 3] := 255;
      end;
    end;
    FPreview.Invalidate;
  except on E: Exception do begin FTimer.Enabled := False; MessageDlg(E.Message, mtError, [mbOK], 0); end; end;
end;
procedure TPsdStudioFrame.PaintPreview(Sender: TObject);
begin
  FPreview.Canvas.Brush.Color := RGB(28, 28, 32); FPreview.Canvas.FillRect(FPreview.ClientRect);
  if FBitmap.Empty then Exit; var Scale := Min(FPreview.Width / 960, FPreview.Height / 540);
  var W := Round(960 * Scale); var H := Round(540 * Scale); var X := (FPreview.Width - W) div 2; var Y := (FPreview.Height - H) div 2;
  FPreview.Canvas.StretchDraw(Rect(X, Y, X + W, Y + H), FBitmap);
end;
function ChooseFile(Form: TComponent; const Root, Filter: string): string;
begin
  Result := ''; var Dialog := TOpenDialog.Create(Form);
  try Dialog.InitialDir := Root; Dialog.Filter := Filter; Dialog.Options := [ofFileMustExist, ofPathMustExist]; if Dialog.Execute then Result := Dialog.FileName;
  finally Dialog.Free; end;
end;
procedure TPsdStudioFrame.OpenPackage(Sender: TObject);
begin var Path := ChooseFile(Self, FSession.Workspace.Root + '\Characters', 'PSDキャラ|*.psdchar'); if Path <> '' then ActivateCharacter(Path); end;
procedure TPsdStudioFrame.OpenCharacterPath(const Path: string);
begin var A := Args; A.AddPair('path', Path); Execute('open', A); end;
procedure TPsdStudioFrame.ImportPrepared(Sender: TObject);
begin var Path := ChooseFile(Self, FSession.Workspace.Root + '\Work', '素材manifest|manifest.json'); if Path = '' then Exit; var A := Args; A.AddPair('path', Path); Execute('import-prepared', A); end;
procedure TPsdStudioFrame.ImportPsd(Sender: TObject);
begin var Path := ChooseFile(Self, FSession.Workspace.Root, '外部PSD（参照）|*.psd'); if Path = '' then Exit; var A := Args; A.AddPair('path', Path); Execute('import-psd', A); end;
procedure TPsdStudioFrame.AddLayer(Sender: TObject);
begin
  if (FSession.Character = nil) or (FTree.Selected = nil) then Exit;
  var Node := FTree.Selected; if Node.Parent <> nil then Node := Node.Parent;
  var Path := ChooseFile(Self, FSession.Workspace.Root + '\Exchange', '分離済み透過PNG|*.png'); if Path = '' then Exit;
  var X,Y: Integer;
  if not TryStrToInt(FLayerX.Text,X) or not TryStrToInt(FLayerY.Text,Y) then begin FStatus.Caption := 'PNG配置のXとYを整数で入力してください。'; Exit; end;
  var G := FSession.Character.Group(TArtLayer(Node.Data).Id);
  var A := Args;
  try
    A.AddPair('groupId', S(G, 'id')); A.AddPair('name', TPath.GetFileNameWithoutExtension(Path)); A.AddPair('path', Path);
    A.AddPair('sha256', THashSHA2.GetHashStringFromFile(Path)); A.AddPair('x', TJSONNumber.Create(X)); A.AddPair('y', TJSONNumber.Create(Y));
  except A.Free; raise; end;
  Execute('add-layer-file', A);
end;
procedure TPsdStudioFrame.AddPose(Sender: TObject);
begin
  if FSession.Character = nil then Exit; var Path := ChooseFile(Self, FSession.Workspace.Root + '\Exchange', '非正面の全身透過PNG|*.png'); if Path = '' then Exit;
  var A := Args; A.AddPair('kind', 'pose'); A.AddPair('name', TPath.GetFileNameWithoutExtension(Path)); A.AddPair('path', Path);
  A.AddPair('sha256', THashSHA2.GetHashStringFromFile(Path)); Execute('add-nonfront-file', A);
end;
procedure TPsdStudioFrame.AddSequence(Sender: TObject);
begin
  if FSession.Character = nil then Exit;
  var Dialog := TOpenDialog.Create(Self);
  try
    Dialog.InitialDir := FSession.Workspace.Root + '\Exchange'; Dialog.Filter := '全身PNG連番|*.png';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofAllowMultiSelect]; if not Dialog.Execute then Exit;
    var Files := TStringList.Create; var A := Args;
    try
      Files.Assign(Dialog.Files); Files.Sort; A.AddPair('kind', 'sequence'); A.AddPair('name', TPath.GetFileNameWithoutExtension(Files[0]));
      A.AddPair('fps', TJSONNumber.Create(24)); A.AddPair('loop', TJSONBool.Create(True)); var Frames := TJSONArray.Create; A.AddPair('frames', Frames);
      for var Path in Files do begin
        var O := TJSONObject.Create; Frames.AddElement(O); O.AddPair('path', Path); O.AddPair('sha256', THashSHA2.GetHashStringFromFile(Path));
      end;
      var R := FSession.Command('add-nonfront-file', A); R.Free;
    finally Files.Free; A.Free; end;
  except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
  Dialog.Free;
end;
procedure TPsdStudioFrame.CaptureSmoke(const Path: string);
  procedure Describe(Control: TWinControl; Output: TJSONArray);
  begin
    for var Index := 0 to Control.ControlCount - 1 do begin
      var Child := Control.Controls[Index]; var O := TJSONObject.Create; Output.AddElement(O);
      O.AddPair('class', Child.ClassName); O.AddPair('visible', TJSONBool.Create(Child.Visible));
      O.AddPair('left', TJSONNumber.Create(Child.Left)); O.AddPair('top', TJSONNumber.Create(Child.Top));
      O.AddPair('width', TJSONNumber.Create(Child.Width)); O.AddPair('height', TJSONNumber.Create(Child.Height));
      if Child is TWinControl then begin
        O.AddPair('handleAllocated', TJSONBool.Create(TWinControl(Child).HandleAllocated));
        var Children := TJSONArray.Create; O.AddPair('children', Children); Describe(TWinControl(Child), Children);
      end;
      if Child is TButton then O.AddPair('caption', TButton(Child).Caption);
      if Child is TComboBox then O.AddPair('text', TComboBox(Child).Text);
      if Child is TTreeView then O.AddPair('items', TJSONNumber.Create(TTreeView(Child).Items.Count));
    end;
  end;
  procedure PrintNative(Control: TWinControl; X, Y: Integer; DC: HDC);
  begin
    for var Index := 0 to Control.ControlCount - 1 do begin
      var Child := Control.Controls[Index];
      if not Child.Visible or not (Child is TWinControl) then Continue;
      var Native := TWinControl(Child);
      var Saved := SaveDC(DC);
      try
        SetViewportOrgEx(DC, X + Child.Left, Y + Child.Top, nil);
        // 標準Windows部品はWM_PAINTの外部DCを無視するため、印刷描画を使う。
        Native.Perform(WM_PRINT, WPARAM(DC), PRF_CLIENT or PRF_ERASEBKGND);
      finally RestoreDC(DC, Saved); end;
      PrintNative(Native, X + Child.Left, Y + Child.Top, DC);
    end;
  end;
begin
  // ネイティブ子コントロールも生成・配置してから内部描画を保存する。
  var Host := TForm(GetParentForm(Self)); if Host=nil then raise Exception.Create('Validation host required');
  Host.Position := poDesigned; Host.SetBounds(-1400,-1000,1280,840); Host.WindowState := wsNormal; Host.Show; Host.Update; Application.ProcessMessages;
  Tick(Self); var Image := Vcl.Graphics.TBitmap.Create; var PNG := TPngImage.Create;
  try
    Image.SetSize(ClientWidth, ClientHeight); PaintTo(Image.Canvas.Handle, 0, 0);
    SelectClipRgn(Image.Canvas.Handle, 0);
    PrintNative(Self, 0, 0, Image.Canvas.Handle); PNG.Assign(Image); PNG.SaveToFile(Path);
  finally PNG.Free; Image.Free; end;
  var Controls := TJSONArray.Create;
  try Describe(Self, Controls); TFile.WriteAllText(Path + '.controls.json', Controls.ToJSON, TEncoding.UTF8); finally Controls.Free; end;
end;
procedure TPsdStudioFrame.VerifyGuiFlow(const ResultPath: string);
  procedure Check(Value: Boolean; const Name: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('GUI regression failed: ' + Name); Results.Add(Name); end;
begin
  var Owner := ObjectText(FSession.Workspace.ReadText('gui-validation-owner.json'));
  try
    if S(Owner, 'owner') <> 'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned GUI validation root required');
  finally Owner.Free; end;
  if FSession.Character = nil then raise Exception.Create('GUI validation character required');
  FTimer.Enabled := False; FPlay.Checked := False;
  var Results := TJSONArray.Create; var OriginalId := FSession.Character.Id;
  try
    var Path := FSession.SavedPath;
    OpenCharacterPath(Path);
    Check((FSession.Character.Id = OriginalId) and (FTree.Items.Count > 0) and not FSession.Dirty, 'open populates native tree', Results);
    FExpression.ItemIndex := FExpression.Items.IndexOf('哀しみ'); FExpression.OnChange(FExpression);
    Check(FSession.State.Expression = '哀しみ', 'expression selection uses GUI event', Results);
    FGaze.ItemIndex := FGaze.Items.IndexOf('right'); FGaze.OnChange(FGaze);
    Check(FSession.State.Gaze = 'right', 'gaze selection uses GUI event', Results);
    FBranch.ItemIndex := 1; FBranch.OnChange(FBranch);
    Check((FSession.State.NonFrontId <> '') and not FExpression.Enabled and not FGaze.Enabled and not FPhone.Enabled and not FBlink.Enabled,
      'non-front selection disables facial controls', Results);
    FBranch.ItemIndex := 0; FBranch.OnChange(FBranch);
    Check((FSession.State.NonFrontId = '') and FExpression.Enabled and FGaze.Enabled and FPhone.Enabled and FBlink.Enabled,
      'front selection restores facial controls', Results);
    var G := TJSONObject(Arr(FSession.Character.Settings, 'groups')[0]);
    var GroupId := S(G, 'id');
    var Choice := Arr(G, 'partIds')[Arr(G, 'partIds').Count - 1].Value;
    for var Index := 0 to FTree.Items.Count - 1 do begin
      var Node := FTree.Items[Index];
      if (Node.Parent <> nil) and (TArtLayer(Node.Data).Id = Choice) then begin FTree.Selected := Node; Break; end;
    end;
    TreeChoice(FTree); Check(not FSession.Dirty, 'draft tree selection saves package automatically', Results);
    // 生産データの代わりに、同じ保存イベントで所有検証ルートを保存する。
    Save(Self); Check(not FSession.Dirty and FileExists(Path), 'save event writes package', Results);
    OpenCharacterPath(Path);
    Check(not FSession.Dirty and (S(FSession.Character.Group(GroupId), 'defaultPartId') = Choice),
      'reopen retains selected part', Results);
    var Restarted := TPsdSession.Create(FSession.Workspace.Root, False);
    try
      var Status := Restarted.Status; var A := TJSONObject.Create;
      try A.AddPair('sessionId', S(Status, 'sessionId')); A.AddPair('revision', S(Status, 'revision')); A.AddPair('path', Path);
      finally Status.Free; end;
      try var Reply := Restarted.Command('open', A); Reply.Free; finally A.Free; end;
      Check((Restarted.Character.Id = OriginalId) and (S(Restarted.Character.Group(GroupId), 'defaultPartId') = Choice),
        'new session retains saved selection', Results);
    finally Restarted.Free; end;
    TFile.WriteAllText(ResultPath, Results.ToJSON, TEncoding.UTF8);
  finally Results.Free; end;
end;
procedure TPsdStudioFrame.VerifyPageFlow(const ResultPath: string);
var Results: TJSONArray;
  procedure Check(Value: Boolean; const Text: string);
  begin if not Value then raise Exception.Create('Page regression failed: '+Text); Results.Add(Text); end;
  procedure Page(Index: Integer);
  begin FPages.ActivePageIndex := Index; PageChanged(Self); end;
  procedure ClickPoint(Step: Integer; X,Y: Double);
  begin
    var Canvas := TPaintBox(FReferencePage.FindComponent('MotionReferenceCanvas')); Canvas.OnPaint(Canvas);
    var K := Min((Canvas.Width-24)/FSession.Character.Document.Width,(Canvas.Height-24)/FSession.Character.Document.Height);
    var W := Round(FSession.Character.Document.Width*K); var H := Round(FSession.Character.Document.Height*K);
    TComboBox(FReferencePage.FindComponent('MotionReferenceStep')).ItemIndex := Step;
    Canvas.OnMouseDown(Canvas,mbLeft,[],(Canvas.Width-W) div 2+Round(X*W),(Canvas.Height-H) div 2+Round(Y*H));
  end;
begin
  var Owner := ObjectText(FSession.Workspace.ReadText('gui-validation-owner.json'));
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned page validation root required'); finally Owner.Free; end;
  if FSession.Character=nil then raise Exception.Create('Character required for page validation');
  var Host := TForm(GetParentForm(Self)); if Host=nil then raise Exception.Create('Validation host required');
  Host.Position := poDesigned; Host.SetBounds(-1400,-1000,1280,840); Host.Show; Host.Update; Application.ProcessMessages;
  FTimer.Enabled := False; FPlay.Checked := False; Results := TJSONArray.Create;
  try
    var FormCount := Screen.FormCount; var CharacterId := FSession.Character.Id; var OriginalName := FSession.Character.Name;
    Page(0); FNameEdit.Text := OriginalName+'（ページ検証）';
    var SelectedId := ''; for var Index := 0 to FTree.Items.Count-1 do if FTree.Items[Index].Parent<>nil then begin FTree.Selected := FTree.Items[Index]; SelectedId := FSelectedLayerId; Break; end;
    Page(1); FExpression.ItemIndex := FExpression.Items.IndexOf('哀しみ'); ViewChanged(Self);
    FGaze.ItemIndex := FGaze.Items.IndexOf('right'); ViewChanged(Self);
    Check(FInfoDirty and (FSession.Character.Name=OriginalName),'page changes retain unapplied character information');
    Check((FSession.State.Expression='哀しみ') and (FSession.State.Gaze='right'),'expression and gaze retained by shared session');
    Page(2); TButton(FReferencePage.FindComponent('MotionReferenceReset')).Click; ClickPoint(0,0.35,0.08);
    var Draft := FReferencePage.Reference.ToJSON; Navigate(FPrevious); Page(0);
    Check(FReferencePage.HasDraft and (FReferencePage.Reference.ToJSON=Draft),'back and page changes retain partial motion reference');
    Check((FTree.Selected<>nil) and (FSelectedLayerId=SelectedId),'selected layer survives session refresh and page changes');
    Page(3); Check((FPages.ActivePageIndex=2) and FReferencePage.HasDraft,'invalid reference cannot bypass required step using tabs');
    ClickPoint(0,0.35,0.08); ClickPoint(1,0.65,0.30); ClickPoint(2,0.5,0.32);
    ClickPoint(3,0.3,0.37); ClickPoint(4,0.7,0.37); ClickPoint(5,0.5,0.65);
    Navigate(FNext);
    Check((FPages.ActivePageIndex=3) and not FReferencePage.HasDraft and (FSession.Character.Settings.GetValue('motionReference')<>nil),'next validates and applies reference inside same editor');
    Navigate(FPrevious); Navigate(FPrevious);
    Check((FPages.ActivePageIndex=1) and (FSession.State.Expression='哀しみ') and (FSession.State.Gaze='right') and FInfoDirty,'navigation retains view and independent draft state');
    Save(Self); Check(not FInfoDirty and not FSession.Dirty,'save applies page drafts through existing session');
    InspectProduction(Self); Check((FPages.ActivePageIndex=1) and (FProductionMemo.Lines.Count>0),'inspection result shown in same page');
    Check((FSession.Character.Id=CharacterId) and not B(FSession.Character.Production,'ready'),'page workflow preserves identity and incomplete production stage');
    Check(Screen.FormCount=FormCount,'page workflow creates no additional editor windows');
    TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
procedure TPsdStudioFrame.Save(Sender: TObject);
begin
  if FInfoDirty then begin EditCharacterInfo(Self); if FInfoDirty then Exit; end;
  if FReferencePage.HasDraft and not FReferencePage.TryApply then begin FPages.ActivePageIndex := 2; PageChanged(Self); Exit; end;
  if Execute('save', Args) and not FSession.Dirty and Assigned(FOnSaved) then FOnSaved(Self);
end;
procedure TPsdStudioFrame.InspectProduction(Sender: TObject);
begin
  if FSession.Character=nil then Exit;
  if HasPageDraft then begin Save(Self); if HasPageDraft then Exit; end;
  if Execute('check-production',Args) then begin FPages.ActivePageIndex := 1; PageChanged(Self); end;
end;
procedure TPsdStudioFrame.EditCharacterInfo(Sender: TObject);
begin
  if FSession.Character=nil then Exit;
  var A := Args; A.AddPair('name',FNameEdit.Text); A.AddPair('supplementName',FSupplementEdit.Text);
  if Execute('set-info',A) then FInfoDirty := False;
end;
function TPsdStudioFrame.HasPageDraft: Boolean;
begin Result := FInfoDirty or ((FReferencePage<>nil) and FReferencePage.HasDraft); end;
procedure TPsdStudioFrame.InfoChanged(Sender: TObject);
begin if not FSync then FInfoDirty := True; end;
procedure TPsdStudioFrame.TreeSelectionChanged(Sender: TObject; Node: TTreeNode);
begin
  if FSync or (Node=nil) or (Node.Data=nil) then Exit;
  var L := TArtLayer(Node.Data); FSelectedLayerId := L.Id;
  if L.Kind=alkImage then begin FLayerX.Text := L.Bounds.Left.ToString; FLayerY.Text := L.Bounds.Top.ToString; end;
end;
function TPsdStudioFrame.ApplyReference(Sender: TObject): Boolean;
begin
  Result := False; if FSession.Character=nil then Exit;
  var Saved := ''; if FSession.Character.Settings.GetValue('motionReference') is TJSONObject then Saved := Obj(FSession.Character.Settings,'motionReference').ToJSON;
  if Saved<>FReferencePage.SavedReferenceText then begin FReferencePage.ShowError('他の経路で基準が変更されました。保存済みの基準を確認してから反映してください。'); Exit; end;
  var A := Args; A.AddPair('reference',TJSONValue(FReferencePage.Reference.Clone)); Result := Execute('set-motion-reference',A);
end;
procedure TPsdStudioFrame.ReloadReference(Sender: TObject);
begin if FSession.Character<>nil then FReferencePage.ReloadCharacter(FSession.Character,FSession.Workspace); end;
procedure TPsdStudioFrame.PageChanged(Sender: TObject);
begin
  if FPageChanging then Exit; FPageChanging := True;
  try
    if (FPages.ActivePageIndex=3) and (FSession.Character<>nil) and (FSession.Character.Policy='managed') then begin
      FReferencePage.BindCharacter(FSession.Character,FSession.Workspace);
      if not FReferencePage.TryApply then begin FPages.ActivePageIndex := 2; FStatus.Caption := '動作確認へ進む前にボーン基準を設定してください。'; end;
    end;
    var Index := FPages.ActivePageIndex;
    FPreviewHost.Visible := Index<>2;
    if Index<>2 then FPreviewHost.Parent := FPages.Pages[Index]
    else if FSession.Character<>nil then FReferencePage.BindCharacter(FSession.Character,FSession.Workspace,True);
    FPrevious.Enabled := Index>0; FNext.Enabled := Index<FPages.PageCount-1;
  finally FPageChanging := False; end;
end;
procedure TPsdStudioFrame.Navigate(Sender: TObject);
begin FPages.ActivePageIndex := EnsureRange(FPages.ActivePageIndex+TControl(Sender).Tag,0,FPages.PageCount-1); PageChanged(Self); end;
function TPsdStudioFrame.ActivateCharacter(const Path: string): Boolean;
begin
  if SameText(ExpandFileName(Path),FSession.SavedPath) then Exit(True);
  if FSession.Dirty or HasPageDraft then begin FStatus.Caption := '現在のキャラの編集を保存してから、別のキャラを開いてください。'; Exit(False); end;
  var A := Args; A.AddPair('path',Path);
  if SameText(ExtractFileExt(Path),'.psd') then Result := Execute('import-psd',A) else Result := Execute('open',A);
end;
procedure TPsdStudioFrame.ExportPsd(Sender: TObject);
begin
  if FSession.Character = nil then Exit; var A := Args;
  A.AddPair('path', 'Characters\' + FSession.Character.Id + '-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.psd'); Execute('export-psd', A);
end;
procedure TPsdStudioFrame.ExportFrame(Sender: TObject);
begin var A := Args; A.AddPair('seconds', TJSONNumber.Create(FTime)); A.AddPair('path', 'Exchange\frame-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.png'); Execute('render-file', A); end;
procedure TPsdStudioFrame.LoadLab(Sender: TObject);
begin var Path := ChooseFile(Self, FSession.Workspace.Root + '\Scripts', '音素LAB|*.lab'); if Path = '' then Exit; var A := Args; A.AddPair('path', Path); Execute('load-lab', A); end;
function TPsdStudioFrame.RequestFinish: Boolean;
begin
  Result := True;
  if not FSession.Dirty and not HasPageDraft then Exit;
  if FSession.CompletedEditSession then
    Exit(MessageDlg('明示保存していない変更を破棄して終了しますか？',mtConfirmation,[mbYes,mbNo],0)=mrYes);
  var Choice := MessageDlg('編集中の設定を保存しますか？',mtConfirmation,[mbYes,mbNo,mbCancel],0);
  if Choice=mrYes then Save(Self);
  Result := (Choice=mrNo) or ((Choice=mrYes) and not FSession.Dirty and not HasPageDraft);
end;
procedure TPsdStudioFrame.ReturnToManagement(Sender: TObject);
begin if Assigned(FOnReturn) then FOnReturn(Self); end;
procedure TPsdStudioFrame.SetActive(Value: Boolean);
begin
  FTimer.Enabled := Value;
  if Value then begin FStart := GetTickCount64-UInt64(Round(FTime*1000)); PageChanged(Self); end;
end;
end.
