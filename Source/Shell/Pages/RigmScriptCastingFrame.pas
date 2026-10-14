unit RigmScriptCastingFrame;

// 配役セリフの一覧と番号キー操作。セリフ/音声/字幕の正本はWorkspaceの既存モデル。
interface
uses System.Classes, System.JSON, RigmScriptPageFrame, Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RigmWizardWorkspace, RigmIconToolbar, RigmVoiceConnection;
type
  TRigmScriptCastingFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean; FSelectedCue: string;
    FConnection: TRigmVoiceConnection; FVoiceStyles,FVoiceState: TComboBox;
    FConnectionRow,FVoicePanel: TPanel; FLocate: TButton; FVoiceActor: TLabel;
    FVoiceChoices,FVoiceWait: TPanel; FVoiceWaitText: TLabel; FVoiceProgress: TProgressBar;
    FApplyingVoice: Boolean; FVoiceOperation: string; // 選択反映中だけ選択欄を処理状況へ切り替える。
    FVoicePeopleIndices,FVoiceStateIndices: TArray<Integer>; // 借用カタログへの人物・行別状態の索引。
    FVoiceRole: Integer; FVoiceStatus: TLabel; FVoiceMessage: string;
    FToolbar: TRigmIconToolbar; FList: TListView; FText,FReason: TMemo; FGuide: TLabel;
    FFace: TComboBox; FFacePanel: TPanel; FFaceDetails: TScrollBox; FFaceToggle: TButton;
    FFaceAssets: TJSONObject; // 所有。Workspaceの素材キャッシュから複製する。
    FFaceDetailKey: string;
    FExpressionAiButton,FExpressionAiCancel: TButton;
    FExpressionAiPanel: TPanel; FExpressionAiStatus: TLabel; FExpressionAiProgress: TProgressBar;
    procedure StartExpressionAi(Sender: TObject);
    procedure CancelExpressionAi(Sender: TObject);
    procedure RefreshExpressionAi;
    procedure FaceChanged(Sender: TObject);
    procedure FacePartChanged(Sender: TObject);
    procedure ToggleFaceDetails(Sender: TObject);
    procedure ResetFaceParts(Sender: TObject);
    procedure RefreshFace;
    procedure ConnectionChanged(Sender: TObject);
    procedure LocateEngine(Sender: TObject);
    procedure BindVoice(Sender: TObject);
    procedure StateChanged(Sender: TObject);
    procedure RefreshVoiceBindings;
    procedure RefreshVoiceFeedback;
    procedure BeginVoiceOperation(const Text: string);
    procedure EndVoiceOperation;
    procedure Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RequestCasting(Sender: TObject);
    procedure Accept(Sender: TObject);
    procedure Split(Sender: TObject);
    procedure Merge(Sender: TObject);
    function SelectedId: string;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
  end;
implementation
uses System.SysUtils, System.Generics.Collections, Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  System.Types, Vcl.Graphics, Vcl.Themes, RigmJson, RigmMovieModel, RigmMovieActing, RigmScriptCastingModel, RigmScriptVoiceSelection, RigmScriptPlacementModel, RigmToolbarIcons;
{$R *.dfm}
type
  TRigmCastingListView = class(TListView)
  protected
    procedure CreateWnd; override;
    procedure WndProc(var Message: TMessage); override;
    function IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean; override;
    function CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean; override;
  end;
const CastingSelectionColor = $00D07000; // RGB(0,112,208)。非フォーカス時も明瞭な青を保つ。
procedure TRigmCastingListView.CreateWnd;
begin
  inherited;
  ListView_SetExtendedListViewStyleEx(Handle,LVS_EX_DOUBLEBUFFER,LVS_EX_DOUBLEBUFFER);
end;
procedure TRigmCastingListView.WndProc(var Message: TMessage);
const ManagedStyles = LVS_EX_DOUBLEBUFFER or LVS_EX_INFOTIP or LVS_EX_LABELTIP;
begin
  if Message.Msg=LVM_SETEXTENDEDLISTVIEWSTYLE then begin
    // RowSelect等のResetExStylesでも内部バッファを失わない。全文は下の本文欄で表示する。
    if Message.WParam<>0 then Message.WParam := Message.WParam or ManagedStyles;
    Message.LParam := (Message.LParam and not (LVS_EX_INFOTIP or LVS_EX_LABELTIP)) or LVS_EX_DOUBLEBUFFER;
  end else if Message.Msg=WM_ERASEBKGND then begin
    // 背景もListViewの内部バッファで合成し、ホバー前に画面を空白へ戻さない。
    Message.Result := 1; Exit;
  end;
  inherited;
end;
function TRigmCastingListView.IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean;
begin
  Result := ((Target in [dtControl,dtItem]) and (Stage=cdPrePaint)) or inherited IsCustomDrawn(Target,Stage);
end;
function TRigmCastingListView.CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean;
begin
  if Stage<>cdPrePaint then Exit(inherited CustomDrawItem(Item,State,Stage));
  Result := False;
  var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := ClientWidth;
  var Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Row.Left,Row.Top,Row.Right,Row.Bottom);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := StyleServices(Self).GetStyleColor(scListView);
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText);
    if Item.Selected then begin Canvas.Brush.Color := CastingSelectionColor; Canvas.Font.Color := clWhite; end;
    Canvas.FillRect(Row);
    SetBkMode(Canvas.Handle,TRANSPARENT);
    var Header := ListView_GetHeader(Handle);
    var Padding := MulDiv(6,CurrentPPI,96);
    for var Index := 0 to Columns.Count-1 do begin
      var Cell: TRect; if not Header_GetItemRect(Header,Index,@Cell) then Continue;
      // ヘッダー座標から変換し、列の移動・幅変更・横スクロールにも同じクリップを使う。
      MapWindowPoints(Header,Handle,Cell,2); Cell.Top := Row.Top; Cell.Bottom := Row.Bottom;
      var CellSaved := SaveDC(Canvas.Handle);
      try
        IntersectClipRect(Canvas.Handle,Cell.Left,Cell.Top,Cell.Right,Cell.Bottom);
        Inc(Cell.Left,Padding); Dec(Cell.Right,Padding);
        var Text := Item.Caption;
        if Index>0 then begin
          Text := ''; if Index<=Item.SubItems.Count then Text := Item.SubItems[Index-1];
        end;
        var Flags: Cardinal := DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX;
        case Columns[Index].Alignment of
          taCenter: Flags := Flags or DT_CENTER;
          taRightJustify: Flags := Flags or DT_RIGHT;
        end;
        if Cell.Right>Cell.Left then DrawText(Canvas.Handle,PChar(Text),Length(Text),Cell,Flags);
      finally RestoreDC(Canvas.Handle,CellSaved); end;
    end;
    if Item.Selected then begin
      Canvas.Brush.Color := $00FFC762;
      var Accent := Row; Accent.Right := MulDiv(3,CurrentPPI,96); Canvas.FillRect(Accent);
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;
constructor TRigmScriptCastingFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  // 一覧のHWNDが設定中に必要になっても、構築済みの表示先へ接続できるようにする。
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptCastingToolbar';
  FToolbar.AddIcon('ScriptCastingRequest','Codexへ配役を依頼／再依頼する',riRefresh,0,RequestCasting);
  FToolbar.AddIcon('ScriptCastingAccept','Enter：現在のキャラ配役を確認して次のセリフへ（声は別途選択）',riComplete,0,Accept);
  FToolbar.AddSeparator;
  FToolbar.AddIcon('ScriptCastingSplit','選択セリフを本文のカーソル位置で分割する',riEditPreview,0,Split);
  FToolbar.AddIcon('ScriptCastingMerge','同じシーンの次のセリフと結合する',riGroup,0,Merge);
  FVoicePanel := TPanel.Create(Self); FVoicePanel.Parent := Self; FVoicePanel.Align := alTop; FVoicePanel.Caption := ''; FVoicePanel.BevelOuter := bvNone; FVoicePanel.Height := ScaleValue(98);
  FVoiceChoices := TPanel.Create(Self); FVoiceChoices.Parent := FVoicePanel; FVoiceChoices.Align := alClient;
  FVoiceChoices.Caption := ''; FVoiceChoices.ShowCaption := False; FVoiceChoices.BevelOuter := bvNone; FVoiceChoices.Name := 'ScriptCastingVoiceChoices';
  FConnectionRow := TPanel.Create(Self); FConnectionRow.Parent := FVoiceChoices; FConnectionRow.Align := alTop; FConnectionRow.Caption := ''; FConnectionRow.BevelOuter := bvNone; FConnectionRow.Height := ScaleValue(30);
  FLocate := TButton.Create(Self); FLocate.Parent := FConnectionRow; FLocate.Align := alRight; FLocate.Width := ScaleValue(180); FLocate.Caption := 'VOICEVOXを手動設定'; FLocate.Name := 'ScriptCastingLocateEngine'; FLocate.OnClick := LocateEngine; FLocate.Visible := False;
  FVoiceStatus := TRigmScriptLabel.Create(Self); FVoiceStatus.Parent := FConnectionRow; FVoiceStatus.Align := alClient; FVoiceStatus.AutoSize := False; FVoiceStatus.WordWrap := True; FVoiceStatus.Name := 'ScriptCastingVoiceStatus';
  var Choices := TPanel.Create(Self); Choices.Parent := FVoiceChoices; Choices.Align := alTop; Choices.Caption := ''; Choices.BevelOuter := bvNone; Choices.Height := ScaleValue(34);
  FVoiceActor := TRigmScriptLabel.Create(Self); FVoiceActor.Parent := Choices; FVoiceActor.AutoSize := False;
  FVoiceActor.Align := alLeft; FVoiceActor.Width := ScaleValue(220); FVoiceActor.Caption := '声（人物）';
  FVoiceActor.Name := 'ScriptCastingVoiceActor'; FVoiceActor.Layout := tlCenter; FVoiceActor.EllipsisPosition := epEndEllipsis;
  FVoiceStyles := TComboBox.Create(Self); FVoiceStyles.Parent := Choices; FVoiceStyles.Align := alClient; FVoiceStyles.Style := csDropDownList; FVoiceStyles.Name := 'ScriptCastingVoiceStyle'; FVoiceStyles.OnChange := BindVoice;
  var States := TPanel.Create(Self); States.Parent := FVoiceChoices; States.Align := alTop; States.Caption := ''; States.BevelOuter := bvNone; States.Height := ScaleValue(34);
  var StateLabel := TRigmScriptLabel.Create(Self); StateLabel.Parent := States; StateLabel.AutoSize := False;
  StateLabel.Align := alLeft; StateLabel.Width := ScaleValue(220); StateLabel.Caption := '感情（VOICEVOXの声）'; StateLabel.Name := 'ScriptCastingEmotionLabel'; StateLabel.Layout := tlCenter;
  FVoiceState := TComboBox.Create(Self); FVoiceState.Parent := States; FVoiceState.Align := alClient; FVoiceState.Style := csDropDownList; FVoiceState.Name := 'ScriptCastingVoiceState'; FVoiceState.OnChange := StateChanged;
  FToolbar.Top := 0; FVoicePanel.Top := FToolbar.Height; FConnectionRow.Top := 0; Choices.Top := ScaleValue(30); States.Top := ScaleValue(64);
  FVoiceWait := TPanel.Create(Self); FVoiceWait.Parent := FVoicePanel; FVoiceWait.Align := alClient;
  FVoiceWait.Caption := ''; FVoiceWait.ShowCaption := False; FVoiceWait.BevelOuter := bvNone; FVoiceWait.Name := 'ScriptCastingVoiceWait'; FVoiceWait.Visible := False;
  FVoiceWait.Padding.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(8),ScaleValue(8));
  FVoiceWaitText := TRigmScriptLabel.Create(Self); FVoiceWaitText.Parent := FVoiceWait; FVoiceWaitText.AutoSize := False;
  FVoiceWaitText.Align := alTop; FVoiceWaitText.WordWrap := True; FVoiceWaitText.Name := 'ScriptCastingVoiceWaitText';
  FVoiceProgress := TProgressBar.Create(Self); FVoiceProgress.Parent := FVoiceWait; FVoiceProgress.Align := alBottom;
  FVoiceProgress.Height := ScaleValue(12); FVoiceProgress.Style := pbstMarquee; FVoiceProgress.MarqueeInterval := 40;
  FVoiceProgress.Name := 'ScriptCastingVoiceProgress';
  FConnection := TRigmVoiceConnection.CreateForWorkspace(Self,FWorkspace); FConnection.OnChanged := ConnectionChanged;
  FFacePanel := TPanel.Create(Self); FFacePanel.Parent := Self; FFacePanel.Align := alTop;
  FFacePanel.BevelOuter := bvNone; FFacePanel.Caption := ''; FFacePanel.Height := ScaleValue(36);
  FFacePanel.Top := FVoicePanel.Top+FVoicePanel.Height; FFacePanel.Name := 'ScriptCastingFacePanel';
  var FaceLabel := TRigmScriptLabel.Create(Self); FaceLabel.Parent := FFacePanel; FaceLabel.Align := alLeft;
  FaceLabel.AutoSize := False; FaceLabel.Width := ScaleValue(220); FaceLabel.Layout := tlCenter; FaceLabel.Caption := '表情（映像のキャラ）';
  FFaceToggle := TButton.Create(Self); FFaceToggle.Parent := FFacePanel; FFaceToggle.Align := alRight;
  FFaceToggle.Width := ScaleValue(170); FFaceToggle.Caption := '細かい表情を設定'; FFaceToggle.OnClick := ToggleFaceDetails; FFaceToggle.Name := 'ScriptCastingFaceDetailsToggle';
  FFace := TComboBox.Create(Self); FFace.Parent := FFacePanel; FFace.Align := alClient; FFace.Style := csDropDownList;
  FFace.Name := 'ScriptCastingFace'; FFace.OnChange := FaceChanged; FFace.Items.Add('自動（セリフから判定）');
  for var LabelText in MovieEmotionLabels do FFace.Items.Add(LabelText);
  FExpressionAiPanel := TPanel.Create(Self); FExpressionAiPanel.Parent := Self; FExpressionAiPanel.Align := alTop;
  FExpressionAiPanel.BevelOuter := bvNone; FExpressionAiPanel.Caption := ''; FExpressionAiPanel.Height := ScaleValue(48);
  FExpressionAiPanel.Top := FFacePanel.Top+FFacePanel.Height;
  FExpressionAiButton := TButton.Create(Self); FExpressionAiButton.Parent := FExpressionAiPanel; FExpressionAiButton.Align := alLeft;
  FExpressionAiButton.Width := ScaleValue(260); FExpressionAiButton.Caption := 'AIで全セリフの表情を設定';
  FExpressionAiButton.Name := 'ScriptCastingExpressionAi'; FExpressionAiButton.OnClick := StartExpressionAi;
  FExpressionAiCancel := TButton.Create(Self); FExpressionAiCancel.Parent := FExpressionAiPanel; FExpressionAiCancel.Align := alRight;
  FExpressionAiCancel.Width := ScaleValue(80); FExpressionAiCancel.Caption := '中止'; FExpressionAiCancel.Visible := False;
  FExpressionAiCancel.Name := 'ScriptCastingExpressionAiCancel'; FExpressionAiCancel.OnClick := CancelExpressionAi;
  FExpressionAiProgress := TProgressBar.Create(Self); FExpressionAiProgress.Parent := FExpressionAiPanel;
  FExpressionAiProgress.Align := alRight; FExpressionAiProgress.Width := ScaleValue(90);
  FExpressionAiProgress.Style := pbstMarquee; FExpressionAiProgress.MarqueeInterval := 40; FExpressionAiProgress.Visible := False;
  FExpressionAiProgress.Name := 'ScriptCastingExpressionAiProgress';
  FExpressionAiStatus := TRigmScriptLabel.Create(Self); FExpressionAiStatus.Parent := FExpressionAiPanel;
  FExpressionAiStatus.Align := alClient; FExpressionAiStatus.AutoSize := False; FExpressionAiStatus.WordWrap := True;
  FExpressionAiStatus.Layout := tlCenter; FExpressionAiStatus.Name := 'ScriptCastingExpressionAiStatus';
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False;
  FGuide.WordWrap := True; FGuide.Height := ScaleValue(76); FGuide.Name := 'ScriptCastingGuide';
  var Detail := TPanel.Create(Self); Detail.Parent := Self; Detail.Align := alBottom; Detail.Height := ScaleValue(174); Detail.Caption := ''; Detail.BevelOuter := bvNone;
  FReason := TMemo.Create(Self); FReason.Parent := Detail; FReason.Align := alTop; FReason.ReadOnly := True;
  FReason.Height := ScaleValue(60); FReason.ScrollBars := ssVertical; FReason.Name := 'ScriptCastingReason';
  FText := TMemo.Create(Self); FText.Parent := Detail; FText.Align := alClient; FText.ReadOnly := True;
  FText.Font.Size := 13; FText.ScrollBars := ssVertical; FText.Name := 'ScriptCastingText'; FText.OnKeyDown := HandleKey;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alBottom; Splitter.Top := Detail.Top-8; Splitter.Height := ScaleValue(8);
  FFaceDetails := TScrollBox.Create(Self); FFaceDetails.Parent := Self; FFaceDetails.Align := alRight;
  FFaceDetails.Width := ScaleValue(340); FFaceDetails.BorderStyle := bsNone; FFaceDetails.Visible := False;
  FFaceDetails.HorzScrollBar.Visible := False; FFaceDetails.Name := 'ScriptCastingFaceDetails';
  FList := TRigmCastingListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport;
  // 標準ListView内で一度だけ合成する。VCL側の追加バッファは列クリップを壊すため使わない。
  FList.ParentDoubleBuffered := False; FList.DoubleBuffered := False;
  FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False; FList.OnSelectItem := Selected; FList.OnKeyDown := HandleKey;
  FList.Name := 'ScriptCastingRows'; FList.Columns.Add.Caption := '区分'; FList.Columns[0].Width := ScaleValue(90);
  FList.Columns.Add.Caption := '番号 / キャラ'; FList.Columns[1].Width := ScaleValue(270);
  FList.Columns.Add.Caption := '声の感情'; FList.Columns[2].Width := ScaleValue(140);
  FList.Columns.Add.Caption := '表情'; FList.Columns[3].Width := ScaleValue(150);
  FList.Columns.Add.Caption := 'セリフ'; FList.Columns[4].Width := ScaleValue(700);
end;
function TRigmScriptCastingFrame.SelectedId: string;
begin Result := ''; if FList.Selected<>nil then Result := FList.Selected.SubItems[4]; end;
destructor TRigmScriptCastingFrame.Destroy;
begin FFaceAssets.Free; inherited; end;
procedure TRigmScriptCastingFrame.FaceChanged(Sender: TObject);
begin
  if FSync or (FFace.ItemIndex<0) then Exit;
  var Id := 'auto'; if FFace.ItemIndex>0 then Id := MovieEmotionIds[FFace.ItemIndex-1];
  try FWorkspace.SetExpression(FSelectedCue,Id); RefreshState;
  except on E: Exception do begin RefreshState; FGuide.Caption := E.Message; end; end;
end;
procedure TRigmScriptCastingFrame.ToggleFaceDetails(Sender: TObject);
begin
  FFaceDetails.Visible := not FFaceDetails.Visible;
  if FFaceDetails.Visible then FFaceToggle.Caption := '細かい表情を閉じる' else FFaceToggle.Caption := '細かい表情を設定';
  FFaceDetailKey := ''; RefreshState;
end;
procedure TRigmScriptCastingFrame.ResetFaceParts(Sender: TObject);
begin
  var A := TJSONArray.Create;
  try
    var Id := 'auto'; if FFace.ItemIndex>0 then Id := MovieEmotionIds[FFace.ItemIndex-1];
    try FWorkspace.SetExpression(FSelectedCue,Id,A); RefreshState;
    except on E: Exception do FGuide.Caption := E.Message; end;
  finally A.Free; end;
end;
procedure TRigmScriptCastingFrame.FacePartChanged(Sender: TObject);
begin
  if FSync or (FFaceAssets=nil) then Exit;
  var Choice := Sender as TComboBox; if Choice.ItemIndex<0 then Exit;
  var Group := TJSONObject(JA(FFaceAssets,'groups')[Choice.Tag]);
  var C := FWorkspace.ScriptDraft.Cue(FSelectedCue); if C=nil then Exit;
  var A := C.Acting.Variants.Clone as TJSONArray;
  try
    for var I := A.Count-1 downto 0 do if JS(TJSONObject(A[I]),'groupId')=JS(Group,'id') then A.Remove(I).Free;
    if Choice.ItemIndex>0 then begin
      var V := TJSONObject.Create; V.AddPair('groupId',JS(Group,'id'));
      V.AddPair('partId',JS(TJSONObject(JA(Group,'children')[Choice.ItemIndex-1]),'id')); A.AddElement(V);
    end;
    var Id := 'auto'; if not C.FaceAutomatic then Id := C.Emotion;
    try FWorkspace.SetExpression(FSelectedCue,Id,A); RefreshState;
    except on E: Exception do begin RefreshState; FGuide.Caption := E.Message; end; end;
  finally A.Free; end;
end;
procedure TRigmScriptCastingFrame.RefreshFace;
begin
  var C := FWorkspace.ScriptDraft.Cue(FSelectedCue); FFace.Enabled := C<>nil; if C=nil then Exit;
  var LabelText := C.VisualEmotion;
  for var I := 0 to High(MovieEmotionIds) do if MovieEmotionIds[I]=C.VisualEmotion then LabelText := MovieEmotionLabels[I];
  FFace.Items[0] := '自動（現在：'+LabelText+' / ？は疑問・！は驚き）'; FFace.ItemIndex := 0;
  if not C.FaceAutomatic then for var I := 0 to High(MovieEmotionIds) do if MovieEmotionIds[I]=C.Emotion then FFace.ItemIndex := I+1;
  if not FFaceDetails.Visible then Exit;
  var Key := C.Id+'|'+C.SpeakerId+'|'+C.Acting.Variants.ToJSON;
  if FFaceDetailKey=Key then Exit;
  FFaceDetails.DisableAlign;
  try
    while FFaceDetails.ControlCount>0 do FFaceDetails.Controls[0].Free;
    FFaceAssets.Free; FFaceAssets := nil; FFaceDetailKey := '';
    var Reset := TButton.Create(Self); Reset.Parent := FFaceDetails; Reset.Align := alTop; Reset.Height := ScaleValue(34);
    Reset.Caption := '個別差分をすべて表情に合わせる'; Reset.Name := 'ScriptCastingFaceReset'; Reset.OnClick := ResetFaceParts;
    var HintText := TRigmScriptLabel.Create(Self); HintText.Parent := FFaceDetails; HintText.Align := alTop; HintText.AutoSize := False;
    HintText.Height := ScaleValue(66); HintText.WordWrap := True;
    HintText.Caption := '選択セリフの差分です。「表情に合わせる」は基本表情を使います。選べる差分はキャラの素材によって変わります。'; HintText.Top := Reset.Height;
    try
      var Assets := FWorkspace.CastingExpressionAssets(FSelectedCue); if Assets<>nil then FFaceAssets := Assets.Clone as TJSONObject;
    except on E: Exception do HintText.Caption := '素材の差分を読み込めません: '+E.Message; end;
    var Y := Reset.Height+HintText.Height;
    if FFaceAssets<>nil then begin
      var Groups := JA(FFaceAssets,'groups');
      if Groups.Count=0 then HintText.Caption := 'このキャラには選択できる個別差分がありません。基本表情による動きを使います。';
      for var I := 0 to Groups.Count-1 do begin
        var G := TJSONObject(Groups[I]); var Row := TPanel.Create(Self); Row.Parent := FFaceDetails;
        Row.Align := alTop; Row.Height := ScaleValue(68); Row.Top := Y; Inc(Y,Row.Height); Row.BevelOuter := bvNone; Row.Caption := '';
        var L := TRigmScriptLabel.Create(Self); L.Parent := Row; L.Align := alTop; L.AutoSize := False; L.Height := ScaleValue(30); L.Caption := JS(G,'name');
        var B := TComboBox.Create(Self); B.Parent := Row; B.Align := alClient; B.Style := csDropDownList;
        B.Name := 'ScriptCastingFacePart'+I.ToString; B.Tag := I; B.Items.Add('表情に合わせる'); B.ItemIndex := 0;
        var Parts := JA(G,'children'); for var P in Parts do B.Items.Add(JS(TJSONObject(P),'name'));
        for var V in C.Acting.Variants do if JS(TJSONObject(V),'groupId')=JS(G,'id') then
          for var J := 0 to Parts.Count-1 do if JS(TJSONObject(Parts[J]),'id')=JS(TJSONObject(V),'partId') then B.ItemIndex := J+1;
        B.OnChange := FacePartChanged;
      end;
    end;
    FFaceDetailKey := Key;
  finally FFaceDetails.EnableAlign; end;
end;
procedure TRigmScriptCastingFrame.Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  // 選択解除でも独自描画した行の全幅を更新する。初期同期中も余白の残像を残さない。
  if Item<>nil then begin
    var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := FList.ClientWidth;
    InvalidateRect(FList.Handle,@Row,False);
  end;
  if FSync or not Selected then Exit;
  try FWorkspace.SelectCasting(SelectedId);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptCastingFrame.HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift<>[] then Exit;
  try
    if Key=VK_UP then FWorkspace.MoveCasting(-1) else if Key=VK_DOWN then FWorkspace.MoveCasting(1)
    else if Key=VK_RETURN then Accept(Self)
    else if (Key>=Ord('1')) and (Key<=Ord('9')) then FWorkspace.AssignCasting(SelectedId,Key-Ord('0'),False)
    else if (Key>=VK_NUMPAD1) and (Key<=VK_NUMPAD9) then FWorkspace.AssignCasting(SelectedId,Key-VK_NUMPAD0,False)
    else Exit;
  except on E: Exception do FGuide.Caption := E.Message; end;
  Key := 0;
end;
procedure TRigmScriptCastingFrame.RequestCasting(Sender: TObject);
begin try FWorkspace.RequestCasting; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptCastingFrame.Accept(Sender: TObject);
begin
  var Row := CastingRow(FWorkspace.ScriptDraft,SelectedId); if Row=nil then Exit;
  try FWorkspace.AssignCasting(SelectedId,JI(Row,'role'),True);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptCastingFrame.Split(Sender: TObject);
begin try FWorkspace.SplitCasting(SelectedId,FText.SelStart); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptCastingFrame.Merge(Sender: TObject);
begin try FWorkspace.MergeCasting(SelectedId); except on E: Exception do FGuide.Caption := E.Message; end; end;
function TRigmScriptCastingFrame.RequestFinish: Boolean;
begin
  FWorkspace.EndScriptTextEdit; Result := True;
end;
procedure TRigmScriptCastingFrame.ConnectionChanged(Sender: TObject);
begin
  FVoiceMessage := ''; RefreshState;
  if Showing and FVoiceWait.Visible then RedrawWindow(Handle,nil,0,RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN);
end;
procedure TRigmScriptCastingFrame.LocateEngine(Sender: TObject);
begin if RequestFinish then FConnection.Locate; end;
procedure TRigmScriptCastingFrame.BindVoice(Sender: TObject);
begin
  if FSync or (FVoiceStyles.ItemIndex<=0) or (FVoiceRole=0) or not RequestFinish then Exit;
  var Index := FVoicePeopleIndices[FVoiceStyles.ItemIndex-1];
  var O := TJSONObject(FWorkspace.VoiceCatalog[Index]); var Uuid := JS(O,'uuid');
  BeginVoiceOperation(JS(O,'name')+'の声を配役へ反映しています。');
  try
    try FVoiceMessage := ''; FWorkspace.BindVoicePerson(FVoiceRole,Uuid);
    except on E: Exception do FVoiceMessage := E.Message; end;
  finally EndVoiceOperation; end;
end;
procedure TRigmScriptCastingFrame.StateChanged(Sender: TObject);
begin
  if FSync or (FVoiceState.ItemIndex<0) or (FVoiceState.ItemIndex>=Length(FVoiceStateIndices)) or not RequestFinish then Exit;
  var Index := FVoiceStateIndices[FVoiceState.ItemIndex];
  var O := TJSONObject(FWorkspace.VoiceCatalog[Index]); var StyleId := JI(O,'styleId',-1);
  BeginVoiceOperation('選択したセリフの感情「'+JS(O,'style')+'」を反映しています。');
  try
    try FVoiceMessage := ''; FWorkspace.SetVoiceState(FSelectedCue,StyleId);
    except on E: Exception do FVoiceMessage := E.Message; end;
  finally EndVoiceOperation; end;
end;
procedure TRigmScriptCastingFrame.BeginVoiceOperation(const Text: string);
begin
  FApplyingVoice := True; FVoiceOperation := Text; RefreshVoiceFeedback;
  // 描画だけを先に完了する。ProcessMessagesで入力・パイプ更新を再入させない。
  if Showing then RedrawWindow(Handle,nil,0,RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN);
end;
procedure TRigmScriptCastingFrame.EndVoiceOperation;
begin FApplyingVoice := False; FVoiceOperation := ''; RefreshState; end;
procedure TRigmScriptCastingFrame.RefreshVoiceFeedback;
begin
  var Waiting := FApplyingVoice or FConnection.Waiting;
  FVoiceChoices.Visible := not Waiting; FVoiceWait.Visible := Waiting;
  if Waiting then begin
    var Text := FConnection.MessageText; if Text='' then Text := 'VOICEVOXの接続を準備しています。';
    if FApplyingVoice then Text := FVoiceOperation;
    FVoiceWaitText.Caption := Text; FVoiceWait.BringToFront;
    FVoicePanel.Height := ScaleValue(96);
  end else begin
    FVoicePanel.Height := ScaleValue(68); if FConnectionRow.Visible then FVoicePanel.Height := FVoicePanel.Height+FConnectionRow.Height;
  end;
  if Waiting then FVoiceProgress.Style := pbstMarquee else FVoiceProgress.Style := pbstNormal;
end;
procedure TRigmScriptCastingFrame.RefreshVoiceBindings;
begin
    var P := FWorkspace.ScriptDraft; var Row := CastingRow(P,FSelectedCue); FVoiceRole := 0;
    if Row<>nil then FVoiceRole := JI(Row,'role');
    FVoicePeopleIndices := VoicePersonIndices(FWorkspace.VoiceCatalog);
    FVoiceStyles.Items.Clear; FVoiceStyles.Items.Add('声の人物を選択してください');
    for var I in FVoicePeopleIndices do FVoiceStyles.Items.Add(JS(TJSONObject(FWorkspace.VoiceCatalog[I]),'name'));
    FVoiceStyles.ItemIndex := 0;
    var Role := CastingRole(P,FVoiceRole);
    FVoiceActor.Caption := '声（人物）';
    if Role<>nil then begin var S := P.Speaker(JS(Role,'speakerId'));
      FVoiceActor.Caption := '声（人物）  '+JS(Role,'name');
      for var I := 0 to High(FVoicePeopleIndices) do if JS(TJSONObject(FWorkspace.VoiceCatalog[FVoicePeopleIndices[I]]),'uuid')=S.VoiceUuid then FVoiceStyles.ItemIndex := I+1;
    end;
    FVoiceActor.Hint := FVoiceActor.Caption; FVoiceActor.ShowHint := True;
    // 実際の感情だけを並べる。ノーマルの追加候補を作らず、未取得時は未選択にする。
    FVoiceState.Items.Clear; FVoiceState.ItemIndex := -1; FVoiceStateIndices := nil;
    var Cue := P.Cue(FSelectedCue);
    if Cue<>nil then begin var S := P.Speaker(Cue.SpeakerId);
      FVoiceStateIndices := VoiceStateIndices(FWorkspace.VoiceCatalog,S.VoiceUuid);
      for var I := 0 to High(FVoiceStateIndices) do begin var O := TJSONObject(FWorkspace.VoiceCatalog[FVoiceStateIndices[I]]);
        FVoiceState.Items.Add(JS(O,'style')); if JI(O,'styleId',-1)=P.EffectiveStyle(Cue) then FVoiceState.ItemIndex := I;
      end;
    end;
    FVoiceStyles.Enabled := FWorkspace.VoiceCatalogReady and not FWorkspace.VoiceBusy and (Role<>nil);
    FVoiceState.Enabled := FWorkspace.VoiceCatalogReady and not FWorkspace.VoiceBusy and (Role<>nil) and (Length(FVoiceStateIndices)>0);
    FLocate.Visible := FConnection.NeedsLocate and not FWorkspace.VoiceBusy;
    FConnectionRow.Visible := not FWorkspace.VoiceCatalogReady or (FVoiceMessage<>'');
    FVoiceStatus.Caption := FConnection.MessageText;
    if FConnection.NeedsLocate and (FVoiceStatus.Caption='') then FVoiceStatus.Caption := 'VOICEVOXを確認できません。実行ファイルを指定してください。';
    if FVoiceMessage<>'' then FVoiceStatus.Caption := FVoiceMessage;
    RefreshVoiceFeedback;
end;
procedure TRigmScriptCastingFrame.RefreshState;
  procedure SetSubItem(Item: TListItem; Index: Integer; const Value: string);
  begin if Item.SubItems[Index]<>Value then Item.SubItems[Index] := Value; end;
begin
  if (FWorkspace.ScriptDraft=nil) or not (FWorkspace.ScriptDraft.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  var Cast := JO(FWorkspace.ScriptDraft.ScriptWizard,'casting'); var Rows := JA(Cast,'rows');
  var Rebuild := FList.Items.Count<>Rows.Count;
  if not Rebuild then for var I := 0 to Rows.Count-1 do
    if (FList.Items[I].SubItems.Count<>5) or (FList.Items[I].SubItems[4]<>JS(TJSONObject(Rows[I]),'cueId')) then begin Rebuild := True; Break; end;
  var SelectionChanged := FSelectedCue<>JS(Cast,'selectedCue');
  // Cue(id)を行ごとに線形検索しない。選択変更時も一覧更新を線形に抑える。
  var Cues := TDictionary<string,TRigmMovieCue>.Create;
  try
    for var C in FWorkspace.ScriptDraft.Cues do Cues.Add(C.Id,C);
    FSync := True;
    // BeginUpdate/EndUpdateは一覧全体を無効化するため、行構成が変わった時だけ使う。
    if Rebuild then FList.Items.BeginUpdate;
    try
      if Rebuild then FList.Items.Clear;
      for var I := 0 to Rows.Count-1 do begin
        var Row := TJSONObject(Rows[I]); var C := Cues[JS(Row,'cueId')]; var Item: TListItem;
        if Rebuild then begin Item := FList.Items.Add; for var J := 0 to 4 do Item.SubItems.Add(''); end
        else Item := FList.Items[I];
        var Section := ScriptStageName(JS(Row,'section')); if JS(Row,'section')='summary' then Section := '総評' else if JS(Row,'section')='opening' then Section := '出だし'
        else if JS(Row,'section')='body' then Section := '本文' else if JS(Row,'section')='closing' then Section := '締め';
        if Item.Caption<>Section then Item.Caption := Section;
        var Role := CastingRole(FWorkspace.ScriptDraft,JI(Row,'role')); var Name := '未割当'; if Role<>nil then Name := JI(Role,'number').ToString+' / '+JS(Role,'name');
        var Speaker := FWorkspace.ScriptDraft.Speaker(C.SpeakerId);
        var Emotion := '未設定';
        var VoiceState := FindVoiceStyle(FWorkspace.VoiceCatalog,Speaker.VoiceUuid,FWorkspace.ScriptDraft.EffectiveStyle(C));
        if VoiceState<>nil then Emotion := JS(VoiceState,'style')
        else if (Speaker.VoiceUuid<>'') and (Speaker.StyleId>=0) then begin
          Emotion := '未取得'; if (C.VoiceStyleId<0) and (Speaker.StyleName<>'') then Emotion := Speaker.StyleName;
        end;
        var FaceText := C.VisualEmotion;
        for var J := 0 to High(MovieEmotionIds) do if MovieEmotionIds[J]=C.VisualEmotion then FaceText := MovieEmotionLabels[J];
        if C.FaceAutomatic then FaceText := '自動：'+FaceText;
        SetSubItem(Item,0,Name); SetSubItem(Item,1,Emotion); SetSubItem(Item,2,FaceText);
        SetSubItem(Item,3,C.Text.Replace(#13#10,' / ')); SetSubItem(Item,4,C.Id);
        if C.Id=JS(Cast,'selectedCue') then begin
          if not Item.Selected then Item.Selected := True;
          if not Item.Focused then Item.Focused := True;
          if FText.Text<>C.Text then FText.Text := C.Text;
          if SelectionChanged then FText.SelStart := 0;
          if FReason.Text<>JS(Row,'reason') then FReason.Text := JS(Row,'reason');
        end;
      end;
      if (Rebuild or SelectionChanged) and (FList.Selected<>nil) then FList.Selected.MakeVisible(False);
      FSelectedCue := JS(Cast,'selectedCue'); RefreshVoiceBindings; RefreshFace; RefreshExpressionAi;
      var Summary := ScriptCastingSummary(FWorkspace.ScriptDraft);
      try
        var Guide := '↑↓：セリフ移動 / 1～9：キャラを指定して次へ / Enter：現在の配役を確認して次へ。'+#13#10+
          '未割当 '+JI(Summary,'unassigned').ToString+' / 配役未確認 '+JI(Summary,'pending').ToString+' / 声未設定 '+JI(Summary,'missingVoices').ToString+'。声の感情と映像の表情は別々に設定できます。'+#13#10+
          '配役と声が揃うと左に「字幕」が表示されます。選択すると現在の全配役を確認して進みます。';
        if FGuide.Caption<>Guide then FGuide.Caption := Guide;
      finally Summary.Free; end;
    finally
      try if Rebuild then FList.Items.EndUpdate;
      finally FSync := False; end;
    end;
  finally Cues.Free; end;
end;
procedure TRigmScriptCastingFrame.SetActive(Value: Boolean);
begin FConnection.SetActive(Value); if Value then RefreshState; end;
procedure TRigmScriptCastingFrame.StartExpressionAi(Sender: TObject);
begin
  try if RequestFinish then FWorkspace.StartExpressionAi;
  except on E: Exception do begin RefreshState; FExpressionAiStatus.Caption := E.Message; Exit; end; end;
  RefreshState;
end;
procedure TRigmScriptCastingFrame.CancelExpressionAi(Sender: TObject);
begin FWorkspace.CancelExpressionAi; RefreshState; end;
procedure TRigmScriptCastingFrame.RefreshExpressionAi;
begin
  var Busy := FWorkspace.ExpressionAiBusy;
  FExpressionAiButton.Enabled := not Busy and (FList.Items.Count>0);
  FExpressionAiCancel.Visible := Busy; FExpressionAiProgress.Visible := Busy;
  if Busy then FExpressionAiProgress.Style := pbstMarquee else FExpressionAiProgress.Style := pbstNormal;
  FExpressionAiStatus.Caption := FWorkspace.ExpressionAiMessage;
  if FExpressionAiStatus.Caption='' then FExpressionAiStatus.Caption := '映像の表情だけを一括設定します。声・音声は保持します。';
  FExpressionAiStatus.Hint := FExpressionAiStatus.Caption; FExpressionAiStatus.ShowHint := True;
  FFace.Enabled := not Busy and (FWorkspace.ScriptDraft.Cue(FSelectedCue)<>nil); FFaceDetails.Enabled := not Busy;
end;
end.
