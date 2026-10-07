unit RigmScriptCastingFrame;

// 配役セリフの一覧と番号キー操作。セリフ/音声/字幕の正本はWorkspaceの既存モデル。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RigmWizardWorkspace, RigmIconToolbar;
type
  TRigmScriptCastingFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean; FSelectedCue: string;
    FToolbar: TRigmIconToolbar; FList: TListView; FText,FCharacters,FReason: TMemo; FGuide: TLabel;
    procedure Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RequestCasting(Sender: TObject);
    procedure Accept(Sender: TObject);
    procedure Split(Sender: TObject);
    procedure Merge(Sender: TObject);
    function SelectedId: string;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
  end;
implementation
uses System.SysUtils, System.JSON, System.Generics.Collections, Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  System.Types, Vcl.Graphics, Vcl.Themes, RigmJson, RigmMovieModel, RigmScriptCastingModel, RigmScriptPlacementModel, RigmToolbarIcons;
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
  FToolbar.AddIcon('ScriptCastingAccept','Enter：現在の配役を確認して次へ',riComplete,0,Accept);
  FToolbar.AddSeparator;
  FToolbar.AddIcon('ScriptCastingSplit','選択セリフを本文のカーソル位置で分割する',riEditPreview,0,Split);
  FToolbar.AddIcon('ScriptCastingMerge','同じシーンの次のセリフと結合する',riGroup,0,Merge);
  FCharacters := TMemo.Create(Self); FCharacters.Parent := Self; FCharacters.Align := alTop;
  FCharacters.ReadOnly := True; FCharacters.Height := 82; FCharacters.ScrollBars := ssVertical; FCharacters.Name := 'ScriptCastingRoles';
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False;
  FGuide.WordWrap := True; FGuide.Height := 76; FGuide.Name := 'ScriptCastingGuide';
  var Detail := TPanel.Create(Self); Detail.Parent := Self; Detail.Align := alBottom; Detail.Height := 174; Detail.Caption := ''; Detail.BevelOuter := bvNone;
  FReason := TMemo.Create(Self); FReason.Parent := Detail; FReason.Align := alTop; FReason.ReadOnly := True;
  FReason.Height := 60; FReason.ScrollBars := ssVertical; FReason.Name := 'ScriptCastingReason';
  FText := TMemo.Create(Self); FText.Parent := Detail; FText.Align := alClient; FText.ReadOnly := True;
  FText.Font.Size := 13; FText.ScrollBars := ssVertical; FText.Name := 'ScriptCastingText'; FText.OnKeyDown := HandleKey;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alBottom; Splitter.Top := Detail.Top-8; Splitter.Height := 8;
  FList := TRigmCastingListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport;
  // 標準ListView内で一度だけ合成する。VCL側の追加バッファは列クリップを壊すため使わない。
  FList.ParentDoubleBuffered := False; FList.DoubleBuffered := False;
  FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False; FList.OnSelectItem := Selected; FList.OnKeyDown := HandleKey;
  FList.Name := 'ScriptCastingRows'; FList.Columns.Add.Caption := '区分'; FList.Columns[0].Width := 90;
  FList.Columns.Add.Caption := '番号 / キャラ'; FList.Columns[1].Width := 270;
  FList.Columns.Add.Caption := '状態'; FList.Columns[2].Width := 120;
  FList.Columns.Add.Caption := 'セリフ'; FList.Columns[3].Width := 700;
end;
function TRigmScriptCastingFrame.SelectedId: string;
begin Result := ''; if FList.Selected<>nil then Result := FList.Selected.SubItems[3]; end;
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
procedure TRigmScriptCastingFrame.RefreshState;
  procedure SetSubItem(Item: TListItem; Index: Integer; const Value: string);
  begin if Item.SubItems[Index]<>Value then Item.SubItems[Index] := Value; end;
begin
  if (FWorkspace.ScriptDraft=nil) or not (FWorkspace.ScriptDraft.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  var Cast := JO(FWorkspace.ScriptDraft.ScriptWizard,'casting'); var Rows := JA(Cast,'rows');
  var Rebuild := FList.Items.Count<>Rows.Count;
  if not Rebuild then for var I := 0 to Rows.Count-1 do
    if (FList.Items[I].SubItems.Count<>4) or (FList.Items[I].SubItems[3]<>JS(TJSONObject(Rows[I]),'cueId')) then begin Rebuild := True; Break; end;
  var SelectionChanged := FSelectedCue<>JS(Cast,'selectedCue');
  // Cue(id)を行ごとに線形検索しない。選択変更時も一覧更新を線形に抑える。
  var Cues := TDictionary<string,TRigmMovieCue>.Create;
  try
    for var C in FWorkspace.ScriptDraft.Cues do Cues.Add(C.Id,C);
    FSync := True;
    // BeginUpdate/EndUpdateは一覧全体を無効化するため、行構成が変わった時だけ使う。
    if Rebuild then FList.Items.BeginUpdate;
    try
      var RolesText := '';
      for var V in JA(Cast,'roles') do begin var R := TJSONObject(V); if JB(R,'active') then RolesText := RolesText+JI(R,'number').ToString+' = '+JS(R,'name')+#13#10; end;
      if FCharacters.Text<>RolesText then begin FCharacters.Text := RolesText; FCharacters.SelStart := 0; FCharacters.Perform(EM_SCROLLCARET,0,0); end;
      if Rebuild then FList.Items.Clear;
      for var I := 0 to Rows.Count-1 do begin
        var Row := TJSONObject(Rows[I]); var C := Cues[JS(Row,'cueId')]; var Item: TListItem;
        if Rebuild then begin Item := FList.Items.Add; for var J := 0 to 3 do Item.SubItems.Add(''); end
        else Item := FList.Items[I];
        var Section := ScriptStageName(JS(Row,'section')); if JS(Row,'section')='opening' then Section := '出だし'
        else if JS(Row,'section')='body' then Section := '本文' else if JS(Row,'section')='closing' then Section := '締め';
        if Item.Caption<>Section then Item.Caption := Section;
        var Role := CastingRole(FWorkspace.ScriptDraft,JI(Row,'role')); var Name := '未割当'; if Role<>nil then Name := JI(Role,'number').ToString+' / '+JS(Role,'name');
        var State := '未割当'; if JS(Row,'origin')='single-default' then State := '単独候補'
        else if JS(Row,'origin')='ai' then State := 'AI案' else if JS(Row,'origin')='human' then State := '人の指定';
        if JB(Row,'confirmed') then State := State+' / 済';
        SetSubItem(Item,0,Name); SetSubItem(Item,1,State); SetSubItem(Item,2,C.Text.Replace(#13#10,' / ')); SetSubItem(Item,3,C.Id);
        if C.Id=JS(Cast,'selectedCue') then begin
          if not Item.Selected then Item.Selected := True;
          if not Item.Focused then Item.Focused := True;
          if FText.Text<>C.Text then FText.Text := C.Text;
          if SelectionChanged then FText.SelStart := 0;
          if FReason.Text<>JS(Row,'reason') then FReason.Text := JS(Row,'reason');
        end;
      end;
      if (Rebuild or SelectionChanged) and (FList.Selected<>nil) then FList.Selected.MakeVisible(False);
      FSelectedCue := JS(Cast,'selectedCue');
      var Summary := ScriptCastingSummary(FWorkspace.ScriptDraft);
      try
        var Guide := '↑↓：セリフ移動 / 1～9：キャラを指定して次へ / Enter：現在の配役を確認して次へ。'+#13#10+
          '未割当 '+JI(Summary,'unassigned').ToString+' / 未確認 '+JI(Summary,'pending').ToString+'。声の紐付けは後の音声設定で行います。';
        if FGuide.Caption<>Guide then FGuide.Caption := Guide;
      finally Summary.Free; end;
    finally
      try if Rebuild then FList.Items.EndUpdate;
      finally FSync := False; end;
    end;
  finally Cues.Free; end;
end;
procedure TRigmScriptCastingFrame.SetActive(Value: Boolean);
begin if Value then RefreshState; end;
end.
