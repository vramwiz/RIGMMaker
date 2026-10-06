unit PsdStudioFrame;

// PSD専用の立ち絵編集画面。既存一覧からも独立EXEからも同じセッションを開く。
interface
uses System.Classes, System.SysUtils, System.JSON, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, PsdSession, PsdMotionReferenceForm,
  PsdPreviewControl, PsdSettingsPanel, RigmIconToolbar;
type
  // 読み込み前後の表示切替をホストへ委譲する。Pathは借用、Loading=Trueが開始。
  TPsdCharacterLoadEvent = procedure(Sender: TObject; const Path: string; Loading: Boolean) of object;
  TPsdStudioFrame = class(TFrame)
  private
    FSession: TPsdSession; FTree: TTreeView; FPreview: TPsdPreviewControl; FBitmap: TBitmap;
    FExpression, FGaze, FPhone, FBranch, FMotion: TComboBox;
    FStatus,FEmptyGuidance: TLabel; FTimer: TTimer; FBlink, FPlay: TCheckBox;
    FStart: UInt64; FTime: Double; FSync: Boolean;
    FOnSaved, FOnReturn: TNotifyEvent;
    FOnCharacterLoad: TPsdCharacterLoadEvent;
    FPages: TPageControl; FPreviewHost: TPanel; FReferencePage: TPsdMotionReferencePage;
    FBody: TPanel; FSettings: array[0..3] of TPsdSettingsPanel;
    FPageToolbar: TRigmIconToolbar; FPageButtons: array[0..3] of TToolButton;
    FNameEdit, FSupplementEdit: TEdit; FProductionMemo: TMemo; FPrevious,FNext: TButton;
    FPresetName: TEdit; FPresetBlink,FPresetMouth: TCheckBox;
    FLayerX,FLayerY: TEdit;
    FInfoDirty,FPageChanging: Boolean; FUiCharacterId,FSelectedLayerId: string;
    FUiBuilds,FPreviewFrames: UInt64;
    FUiRevision: UInt64; FUiInitialized,FPreviewDirty,FActive: Boolean;
    FStageChecks: TJSONObject; FStageRevision,FStageValidations: UInt64; FStageChecked: Boolean;
    FStageReady: array[0..3] of Boolean; FStageReason: array[0..3] of string;
    FNavigationPage: Integer; FStepStatus: TLabel;
    procedure UpdateNavigation(Sender: TObject);
    function CanAdvance(Stage: Integer; out Reason: string): Boolean;
    procedure SyncView;
    procedure RequestPreview;
    procedure PlaybackChanged(Sender: TObject);
    function Args: TJSONObject;
    function Execute(const Command: string; A: TJSONObject): Boolean;
    function RunSessionCommand(const Command: string; A: TJSONObject): TJSONObject;
    procedure RenderPreview;
    procedure Refresh(Sender: TObject);
    procedure Tick(Sender: TObject);
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
    procedure RegisterExpression(Sender: TObject);
    procedure EditCharacterInfo(Sender: TObject);
    procedure InfoChanged(Sender: TObject);
    procedure PageChanged(Sender: TObject);
    procedure SelectPage(Sender: TObject);
    procedure FitPreview(Sender: TObject);
    procedure LayoutBody(Sender: TObject);
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
    property OnCharacterLoad: TPsdCharacterLoadEvent read FOnCharacterLoad write FOnCharacterLoad;
    function ActivateCharacter(const Path: string): Boolean;
    function ExternalCommand(const Name: string; A: TJSONObject): TJSONObject;
    function Diagnostics: TJSONObject;
  end;

implementation
{$R *.dfm}
uses System.IOUtils, System.Hash, System.Math, System.StrUtils, System.UITypes,
  System.Generics.Collections, Winapi.Windows, Winapi.Messages, Vcl.Dialogs, Vcl.Imaging.pngimage,
  ArtDocument, PsdJson, PsdWorkspace, PsdProduction, RigmToolbarIcons;

constructor TPsdStudioFrame.Create(AOwner: TComponent);
begin
  var Root := PSD_DEFAULT_ROOT;
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--root' then Root := ParamStr(Index + 1);
  CreateForCharacter(AOwner,Root,'');
end;
constructor TPsdStudioFrame.CreateForCharacter(AOwner: TComponent; const Root,Path: string; AutoOpen: Boolean);
const
  PageIcons: array[0..3] of TRigmToolbarIcon = (riLayer,riSample,riBone,riPreview);
  function Button(Parent: TWinControl; const Text: string; Event: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self); Result.Parent := Parent; Result.Caption := Text;
    Result.Align := alTop; Result.Height := 30; Result.OnClick := Event;
  end;
begin
  inherited Create(AOwner); Width := 1280; Height := 820; Align := alClient; DoubleBuffered := True;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  FSync := True; // 名前付けなどの初期値設定をユーザーの下書き変更として扱わない。
  FSession := PsdSession.TPsdSession.Create(Root); FSession.OnChanged := Refresh; FBitmap := Vcl.Graphics.TBitmap.Create;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 38; Header.BevelOuter := bvNone;
  var ReturnButton := Button(Header,'キャラ管理へ戻る',ReturnToManagement); ReturnButton.Align := alRight; ReturnButton.Width := 170; ReturnButton.Name := 'PsdReturnToManagement';
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 62; FStatus.WordWrap := True;
  FStatus.Caption := '分離済み素材を登録するか、キャラを開いてください。';
  var Navigation := TPanel.Create(Self); Navigation.Parent := Self; Navigation.Align := alBottom; Navigation.Height := 38; Navigation.BevelOuter := bvNone;
  FNext := Button(Navigation,'次へ',Navigate); FNext.Align := alRight; FNext.Width := 120; FNext.Tag := 1; FNext.Name := 'PsdNext';
  FPrevious := Button(Navigation,'戻る',Navigate); FPrevious.Align := alLeft; FPrevious.Width := 120; FPrevious.Tag := -1; FPrevious.Name := 'PsdPrevious';
  FStepStatus := TLabel.Create(Self); FStepStatus.Parent := Navigation; FStepStatus.Align := alClient;
  FStepStatus.AutoSize := False; FStepStatus.WordWrap := True; FStepStatus.Name := 'PsdStepStatus';
  FBody := TPanel.Create(Self); FBody.Parent := Self; FBody.Align := alClient; FBody.BevelOuter := bvNone;
  FBody.Name := 'PsdEditorBody'; FBody.DoubleBuffered := True;
  FPages := TPageControl.Create(Self); FPages.Parent := FBody; FPages.Align := alRight;
  FPages.Width := 400; FPages.Name := 'PsdCharacterPages';
  for var Text in ['レイヤー','表情','ボーン基準','動作確認'] do begin
    var Page := TTabSheet.Create(Self); Page.PageControl := FPages; Page.Caption := Text; Page.TabVisible := False;
  end;
  FPageToolbar := TRigmIconToolbar.Create(Self); FPageToolbar.Name := 'PsdStageToolbar';
  FPageToolbar.Parent := Self; FPageToolbar.Align := alTop; FPageToolbar.Top := Header.Height;
  for var Index := 0 to 3 do begin
    FPageButtons[Index] := FPageToolbar.AddIcon('PsdStage'+Index.ToString,FPages.Pages[Index].Caption,
      PageIcons[Index],Index,SelectPage,True);
    FPageButtons[Index].Grouped := True; FPageButtons[Index].AllowAllUp := False;
  end;
  FPageToolbar.AddSeparator; FPageToolbar.AddIcon('PsdPreviewFit','画面に合わせる',riReset,0,FitPreview);
  for var Index in [0,1,3] do begin
    FSettings[Index] := TPsdSettingsPanel.Create(Self); FSettings[Index].Parent := FPages.Pages[Index];
    FSettings[Index].Name := 'PsdSettings'+Index.ToString;
  end;
  var Layers := FSettings[0];
  FNameEdit := Layers.AddEdit('キャラ名'); FNameEdit.OnChange := InfoChanged; FNameEdit.Name := 'PsdCharacterName';
  FSupplementEdit := Layers.AddEdit('補足名（衣装など）'); FSupplementEdit.OnChange := InfoChanged; FSupplementEdit.Name := 'PsdCharacterSupplement';
  Layers.AddButton('基本情報を反映',EditCharacterInfo).Name := 'PsdInfoApply';
  Layers.AddLabel('レイヤー');
  FEmptyGuidance := Layers.AddLabel('素材はまだありません。Codexにキャラ画像と表情差分の制作・レイヤー分離を依頼し、管理フォルダに保存したmanifestを下のボタンで登録してください。',96);
  FEmptyGuidance.Name := 'PsdEmptyLayerGuidance'; FEmptyGuidance.Parent.Visible := False;
  FTree := TTreeView.Create(Self); FTree.Parent := Layers.AddRow(220); FTree.Align := alClient;
  FTree.OnDblClick := TreeChoice; FTree.OnChange := TreeSelectionChanged;
  Layers.AddButton('分離済み素材のmanifestを登録',ImportPrepared);
  Layers.AddButton('外部PSDを参照登録',ImportPsd); Layers.AddButton('選択部位に透過PNGを追加',AddLayer);
  Layers.AddButton('非正面の全身ポーズを追加',AddPose); Layers.AddButton('全身PNG連番を追加（24fps）',AddSequence);
  Layers.AddButton('PSDを書き出す',ExportPsd);
  FLayerX := Layers.AddEdit('追加PNGの配置 X（元キャンバス）'); FLayerX.Text := '0';
  FLayerY := Layers.AddEdit('追加PNGの配置 Y（元キャンバス）'); FLayerY.Text := '0';
  var Expressions := FSettings[1];
  FExpression := Expressions.AddCombo('表情',ViewChanged);
  FGaze := Expressions.AddCombo('視線（画面基準）',ViewChanged);
  FPhone := Expressions.AddCombo('音素口形（手動確認）',ViewChanged);
  FPhone.Items.AddStrings(['表情の口','a','i','u','e','o','N','closed']); FPhone.ItemIndex := 0;
  FBlink := Expressions.AddCheck('約4秒ごとに瞬き',ViewChanged); FBlink.Checked := True;
  FPresetName := Expressions.AddEdit('選んだ部位を登録する表情名'); FPresetName.Name := 'PsdExpressionName';
  FPresetName.OnChange := UpdateNavigation;
  FPresetName.Text := ''; FPresetName.TextHint := '通常・喜び・怒り・哀しみ・楽しみ等';
  FPresetBlink := Expressions.AddCheck('この表情で瞬き'); FPresetBlink.Checked := True;
  FPresetMouth := Expressions.AddCheck('この表情で口パク'); FPresetMouth.Checked := True;
  Expressions.AddButton('現在の部位選択を登録',RegisterExpression).Name := 'PsdExpressionRegister';
  Expressions.AddLabel('必須仕様の検査結果');
  FProductionMemo := TMemo.Create(Self); FProductionMemo.Parent := Expressions.AddRow(240); FProductionMemo.Align := alClient;
  FProductionMemo.ReadOnly := True; FProductionMemo.ScrollBars := ssVertical; FProductionMemo.Name := 'PsdProductionResults';
  var Motion := FSettings[3];
  FMotion := Motion.AddCombo('小さな動き',ViewChanged); FMotion.Items.AddStrings(['none','breathe','sway','jump']); FMotion.ItemIndex := 1;
  FBranch := Motion.AddCombo('正面 / 非正面（全身）',ViewChanged);
  FPlay := Motion.AddCheck('再生',PlaybackChanged); FPlay.Checked := True; FPlay.Name := 'PsdPlay';
  Motion.AddButton('FullHD PNGを書き出す',ExportFrame); Motion.AddButton('音素LABを読み込む',LoadLab);
  FPreviewHost := TPanel.Create(Self); FPreviewHost.Parent := FBody; FPreviewHost.Align := alClient;
  FPreviewHost.BevelOuter := bvNone; FPreviewHost.DoubleBuffered := True;
  FPreview := TPsdPreviewControl.Create(Self); FPreview.Name := 'PsdPreviewSurface';
  FPreview.Parent := FPreviewHost; FPreview.Align := alClient;
  FReferencePage := TPsdMotionReferencePage.CreateForParent(Self,FPages.Pages[2],FPreviewHost);
  FReferencePage.Name := 'PsdMotionReferenceEditor'; FReferencePage.OnApply := ApplyReference; FReferencePage.OnReload := ReloadReference;
  FReferencePage.OnChanged := UpdateNavigation;
  FSettings[2] := FReferencePage.SettingsPanel;
  FBody.OnResize := LayoutBody; LayoutBody(Self);
  FPages.ActivePageIndex := 0; FPages.OnChange := PageChanged; PageChanged(Self);
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 40; FTimer.OnTimer := Tick; FStart := GetTickCount64;
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
begin
  if FTimer <> nil then FTimer.Enabled := False;
  // 基準の表示面は左ホストへ配置しているため、親ホストより先に所有元を破棄する。
  FReferencePage.Free;
  FStageChecks.Free; FPreview.Free; FSession.Free; FBitmap.Free; inherited;
end;
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
      var R := RunSessionCommand(Command, A); R.Free;
      Result := True;
      if (FSession.SavedPath<>'') and not FSession.Dirty and
        MatchText(Command,['check-production','set-info','set-motion-reference','select-part','set-expression','add-layer-file','add-nonfront-file']) and Assigned(FOnSaved) then FOnSaved(Self);
    except on E: Exception do FStatus.Caption := E.Message; end;
  finally A.Free; end;
end;
function TPsdStudioFrame.RunSessionCommand(const Command: string; A: TJSONObject): TJSONObject;
begin
  var Loading := MatchText(Command,['open','import-prepared','import-psd']);
  if Loading and HasPageDraft then
    raise Exception.Create('ページ内の編集中の設定を反映してからキャラを切り替えてください。');
  var Notify := Loading and Assigned(FOnCharacterLoad);
  var Path := S(A,'path');
  if Notify then FOnCharacterLoad(Self,Path,True);
  try
    Result := FSession.Command(Command,A);
    try
      // 最初の画像も案内表示中に用意し、編集画面へ空白のプレビューを出さない。
      if Loading then RenderPreview;
    except Result.Free; raise; end;
  finally
    if Notify then FOnCharacterLoad(Self,Path,False);
  end;
end;
function TPsdStudioFrame.ExternalCommand(const Name: string; A: TJSONObject): TJSONObject;
begin
  Result := RunSessionCommand(Name,A);
  if MatchText(Name,['save','check-production','set-info','set-motion-reference','select-part','set-expression','add-layer-file','add-nonfront-file']) and
    (FSession.SavedPath<>'') and not FSession.Dirty and Assigned(FOnSaved) then FOnSaved(Self);
end;
procedure TPsdStudioFrame.Refresh(Sender: TObject);
  procedure AddTree(Layers: TList<TArtLayer>; Parent: TTreeNode);
  begin
    for var L in Layers do begin var Node := FTree.Items.AddChildObject(Parent, L.Name, L); AddTree(L.Children, Node); end;
  end;
begin
  if FSession.Character=nil then Exit;
  if FUiInitialized and (FUiRevision=FSession.Revision) then begin SyncView; Exit; end;
  Inc(FUiBuilds);
  FSync := True;
  FTree.Items.BeginUpdate;
  DisableAlign;
  try
    FTree.Items.Clear; FExpression.Clear; FGaze.Clear; FBranch.Clear;
    if FSession.Character = nil then Exit;
    var C := FSession.Character;
    if (FUiCharacterId<>C.Id) and (C.Policy='managed') and (Arr(C.Settings,'groups').Count=0) then
      FPages.ActivePageIndex := 0;
    FEmptyGuidance.Parent.Visible := (C.Policy='managed') and (Arr(C.Settings,'groups').Count=0);
    if FUiCharacterId<>C.Id then FPreview.Fit;
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
    var Reason: string; var Ready := FSession.ReadyForScript(Reason);
    Caption := 'PSD立ち絵スタジオ — ' + C.Name+IfThen(C.SupplementName<>'',' / '+C.SupplementName,'')+IfThen(Ready,'（完成）','（未完成）');
    FStatus.Caption := IfThen(FSession.Dirty, '未保存　', '保存済み　') + IfThen(Ready,'完成・台本で選択可','未完成・台本へ新規追加不可')+'　'+ C.Name + #13#10 +
      FSession.SavedPath + #13#10 + '接続: ' + FSession.ConnectionFile;
    FUiRevision := FSession.Revision; FUiInitialized := True;
  finally EnableAlign; FTree.Items.EndUpdate; FSync := False; end;
  SyncView;
  UpdateNavigation(Self);
end;
procedure TPsdStudioFrame.SyncView;
begin
  FSync := True;
  try
    FExpression.ItemIndex := Max(0,FExpression.Items.IndexOf(FSession.State.Expression));
    FGaze.ItemIndex := Max(0,FGaze.Items.IndexOf(FSession.State.Gaze));
    FBranch.ItemIndex := 0;
    for var Index := 0 to Arr(FSession.Character.Settings,'nonFront').Count-1 do
      if S(TJSONObject(Arr(FSession.Character.Settings,'nonFront')[Index]),'id')=FSession.State.NonFrontId then FBranch.ItemIndex := Index+1;
    FMotion.ItemIndex := Max(0,FMotion.Items.IndexOf(FSession.State.Motion));
    FPhone.ItemIndex := 0; if FSession.State.HasPhoneme then FPhone.ItemIndex := Max(0,FPhone.Items.IndexOf(FSession.State.Phoneme));
    FBlink.Checked := FSession.State.AutoBlink;
    var Front := FSession.State.NonFrontId='';
    FExpression.Enabled := Front; FGaze.Enabled := Front; FPhone.Enabled := Front; FBlink.Enabled := Front;
  finally FSync := False; end;
  RequestPreview;
end;
procedure TPsdStudioFrame.RequestPreview;
begin
  FPreviewDirty := True;
  if FTimer<>nil then FTimer.Enabled := FActive and (FPages.ActivePageIndex<>2);
end;
procedure TPsdStudioFrame.PlaybackChanged(Sender: TObject);
begin
  FStart := GetTickCount64-UInt64(Round(FTime*1000)); RequestPreview;
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
  if Execute('select-part', A) then begin
    var V := FSession.State; V.Expression := ''; V.Gaze := 'front'; V.HasPhoneme := False; FSession.SetView(V);
  end;
end;
procedure TPsdStudioFrame.RegisterExpression(Sender: TObject);
begin
  if FSession.Character=nil then Exit;
  var ExpressionName: string := FPresetName.Text; ExpressionName := Trim(ExpressionName);
  if (ExpressionName='') or (Length(ExpressionName)>128) then begin FStatus.Caption := '表情名を128文字以内で入力してください。'; Exit; end;
  if (Obj(FSession.Character.Settings,'expressions').GetValue(ExpressionName)<>nil) and
    (MessageDlg('同じ名前の表情を現在の部位選択で更新しますか？',mtConfirmation,[mbYes,mbNo],0)<>mrYes) then Exit;
  var A := Args; A.AddPair('name',ExpressionName); var Preset := TJSONObject.Create; A.AddPair('preset',Preset);
  var Choices := TJSONArray.Create; Preset.AddPair('variants',Choices);
  for var Item in Arr(FSession.Character.Settings,'groups') do begin
    var G := TJSONObject(Item); var Choice := TJSONObject.Create; Choices.AddElement(Choice);
    Choice.AddPair('groupId',S(G,'id')); Choice.AddPair('partId',S(G,'defaultPartId'));
  end;
  Preset.AddPair('blinkAnimate',TJSONBool.Create(FPresetBlink.Checked)); Preset.AddPair('mouthAnimate',TJSONBool.Create(FPresetMouth.Checked));
  if Execute('set-expression',A) then begin
    FPresetName.Clear; var V := FSession.State; V.Expression := ExpressionName; V.Gaze := 'front'; V.HasPhoneme := False; FSession.SetView(V);
  end;
end;
procedure TPsdStudioFrame.Tick(Sender: TObject);
begin
  if (FSession.Character = nil) or not Showing or not FPreview.Showing then Exit;
  if not FPlay.Checked and not FPreviewDirty then Exit;
  if FPlay.Checked then FTime := (GetTickCount64 - FStart) / 1000 else FStart := GetTickCount64 - UInt64(Round(FTime * 1000));
  try
    RenderPreview;
    if not FPlay.Checked then FTimer.Enabled := False;
  except on E: Exception do begin FTimer.Enabled := False; MessageDlg(E.Message, mtError, [mbOK], 0); end; end;
end;
procedure TPsdStudioFrame.RenderPreview;
begin
  if FSession.Character=nil then Exit;
  var Pixels := FSession.Frame(FTime, 960, 540); Inc(FPreviewFrames); FBitmap.PixelFormat := pf32bit; FBitmap.SetSize(960, 540);
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
  FPreview.Present(FBitmap);
  FPreviewDirty := False;
end;
function TPsdStudioFrame.Diagnostics: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uiBuilds',TJSONNumber.Create(FUiBuilds));
  Result.AddPair('previewFrames',TJSONNumber.Create(FPreviewFrames));
  Result.AddPair('previewPaints',TJSONNumber.Create(FPreview.PaintCount));
  Result.AddPair('readinessChecks',TJSONNumber.Create(FSession.ReadinessChecks));
  Result.AddPair('stageValidationChecks',TJSONNumber.Create(FStageValidations));
  Result.AddPair('previewDoubleBuffered',TJSONBool.Create(FPreviewHost.DoubleBuffered));
  Result.AddPair('previewOwnWindow',TJSONBool.Create(FPreview.HandleAllocated));
  Result.AddPair('stageIconCount',TJSONNumber.Create(Length(FPageButtons)));
  Result.AddPair('timerInterval',TJSONNumber.Create(FTimer.Interval));
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
  begin FPageButtons[Index].Click; end;
  procedure ClickPoint(Step: Integer; X,Y: Double);
  begin
    var Canvas := FReferencePage.Preview; var R := Canvas.ImageRect;
    TComboBox(FReferencePage.FindComponent('MotionReferenceStep')).ItemIndex := Step;
    var Position := MakeLParam(R.Left+Round(X*R.Width),R.Top+Round(Y*R.Height));
    Canvas.Perform(WM_LBUTTONDOWN,MK_LBUTTON,Position); Canvas.Perform(WM_LBUTTONUP,0,Position);
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
    Page(3); Check((FPages.ActivePageIndex=2) and FReferencePage.HasDraft and FPageButtons[2].Down and
      not FPageButtons[3].Down,'invalid reference cannot bypass required step using icons');
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
    if Execute('set-info',A) then begin FInfoDirty := False; UpdateNavigation(Self); end;
end;
function TPsdStudioFrame.HasPageDraft: Boolean;
begin Result := FInfoDirty or ((FPresetName<>nil) and (FPresetName.Text<>'')) or ((FReferencePage<>nil) and FReferencePage.HasDraft); end;
procedure TPsdStudioFrame.InfoChanged(Sender: TObject);
begin if not FSync then begin FInfoDirty := True; UpdateNavigation(Self); end; end;
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
    var Reason: string;
    if FPages.ActivePageIndex>FNavigationPage then
      for var Stage := 0 to FPages.ActivePageIndex-1 do if not CanAdvance(Stage,Reason) then begin
        FPages.ActivePageIndex := FNavigationPage; FStepStatus.Caption := Reason; Break;
      end;
    if (FPages.ActivePageIndex=3) and (FSession.Character<>nil) and (FSession.Character.Policy='managed') then begin
      FReferencePage.BindCharacter(FSession.Character,FSession.Workspace);
      if not FReferencePage.TryApply then begin FPages.ActivePageIndex := 2; FStatus.Caption := '動作確認へ進む前にボーン基準を設定してください。'; end;
    end;
    var Index := FPages.ActivePageIndex;
    FNavigationPage := Index;
    for var ButtonIndex := 0 to 3 do FPageButtons[ButtonIndex].Down := ButtonIndex=Index;
    FPreview.Visible := Index<>2; FReferencePage.Preview.Visible := Index=2;
    if (Index=2) and (FSession.Character<>nil) then FReferencePage.BindCharacter(FSession.Character,FSession.Workspace,True);
    FPrevious.Enabled := Index>0; UpdateNavigation(Self);
    RequestPreview;
  finally FPageChanging := False; end;
end;
procedure TPsdStudioFrame.SelectPage(Sender: TObject);
begin FPages.ActivePageIndex := TToolButton(Sender).Tag; PageChanged(Self); end;
procedure TPsdStudioFrame.FitPreview(Sender: TObject);
begin if FPages.ActivePageIndex=2 then FReferencePage.Preview.Fit else FPreview.Fit; end;
procedure TPsdStudioFrame.LayoutBody(Sender: TObject);
begin
  if (FBody=nil) or (FPages=nil) then Exit;
  FPages.Width := Min(ScaleValue(400),Max(ScaleValue(240),FBody.ClientWidth div 2));
end;
procedure TPsdStudioFrame.Navigate(Sender: TObject);
begin
  if TControl(Sender).Tag>0 then begin
    var Reason: string;
    if not CanAdvance(FPages.ActivePageIndex,Reason) then begin FStepStatus.Caption := Reason; Exit; end;
    if FInfoDirty then begin EditCharacterInfo(Self); if FInfoDirty then Exit; end;
    if (FPages.ActivePageIndex>=2) and FReferencePage.HasDraft and not FReferencePage.TryApply then Exit;
    if FPages.ActivePageIndex=3 then begin
      if not Execute('check-production',Args) then Exit;
      if not FSession.ReadyForScript(Reason) then begin FStepStatus.Caption := Reason; Exit; end;
      if not Execute('save',Args) or FSession.Dirty then Exit;
      if Assigned(FOnSaved) then FOnSaved(Self);
      if Assigned(FOnReturn) then FOnReturn(Self);
      Exit;
    end;
  end;
  FPages.ActivePageIndex := EnsureRange(FPages.ActivePageIndex+TControl(Sender).Tag,0,FPages.PageCount-1); PageChanged(Self);
end;
function TPsdStudioFrame.CanAdvance(Stage: Integer; out Reason: string): Boolean;
begin
  Result := False; Reason := '素材と設定を確認してください。';
  if (FSession=nil) or (FSession.Character=nil) or not FStageChecked then Exit;
  if (Trim(FNameEdit.Text)='') or (Length(Trim(FNameEdit.Text))>128) or (Length(Trim(FSupplementEdit.Text))>128) then begin
    Reason := 'キャラ名・補足名を128文字以内で入力してください。'; Exit;
  end;
  if (Stage>=1) and (FPresetName.Text<>'') then begin Reason := '入力中の表情を登録してから進んでください。'; Exit; end;
  Result := FStageReady[Stage]; Reason := FStageReason[Stage];
  if (Stage=2) and FStageReady[1] and FReferencePage.HasDraft then begin
    try ValidateMotionReference(FSession.Character,FReferencePage.Reference); Result := True; Reason := '';
    except on E: Exception do begin Result := False; Reason := E.Message; end; end;
  end;
end;
procedure TPsdStudioFrame.UpdateNavigation(Sender: TObject);
begin
  if FSync or (FNext=nil) or (FSession=nil) then Exit;
  if FSession.Character=nil then begin FNext.Visible := False; Exit; end;
  if not FStageChecked or (FStageRevision<>FSession.Revision) then begin
    Inc(FStageValidations);
    FStageChecked := False; FreeAndNil(FStageChecks);
    var Reason: string;
    if FSession.ReadyForScript(Reason) then FStageChecks := TJSONObject(FSession.Character.Production.Clone)
    else FStageChecks := CheckPsdProduction(FSession.Character);
    for var Index := 0 to 3 do begin FStageReady[Index] := True; FStageReason[Index] := ''; end;
    for var V in Arr(FStageChecks,'checks') do begin
      var O := TJSONObject(V); var Stage := 0; var Id := S(O,'id');
      if MatchText(Id,['blink','lipSync','emotions']) then Stage := 1 else if Id='motionReference' then Stage := 2;
      if not B(O,'passed') then for var Index := Stage to 3 do begin
        FStageReady[Index] := False;
        if FStageReason[Index]='' then FStageReason[Index] := S(O,'title')+': '+S(O,'message');
      end;
    end;
    FProductionMemo.Clear;
    for var V in Arr(FStageChecks,'checks') do begin var O := TJSONObject(V);
      FProductionMemo.Lines.Add(IfThen(B(O,'passed'),'○ ','× ')+S(O,'title')+': '+S(O,'message'));
    end;
    FStageRevision := FSession.Revision; FStageChecked := True;
  end;
  var Reason: string; var Ready := CanAdvance(FPages.ActivePageIndex,Reason);
  FNext.Visible := Ready; FNext.Enabled := Ready;
  FNext.Caption := IfThen(FPages.ActivePageIndex=3,'保存','次へ');
  FStepStatus.Caption := Reason;
  for var Index := 1 to 3 do begin
    var Allowed := True;
    if Index>FPages.ActivePageIndex then for var Stage := 0 to Index-1 do
      if not CanAdvance(Stage,Reason) then begin Allowed := False; Break; end;
    FPageButtons[Index].Enabled := (Index<=FPages.ActivePageIndex) or Allowed;
  end;
end;
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
  FActive := Value; FTimer.Enabled := Value and (FPages.ActivePageIndex<>2);
  if Value then begin FStart := GetTickCount64-UInt64(Round(FTime*1000)); PageChanged(Self); end;
end;
end.
