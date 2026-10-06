unit RigmScriptCastingFrame;

// 配役セリフの一覧と番号キー操作。セリフ/音声/字幕の正本はWorkspaceの既存モデル。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RigmWizardWorkspace, RigmIconToolbar;
type
  TRigmScriptCastingFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
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
uses System.SysUtils, System.JSON, Winapi.Windows, Winapi.Messages, RigmJson, RigmScriptCastingModel, RigmScriptPlacementModel, RigmToolbarIcons;
{$R *.dfm}
constructor TRigmScriptCastingFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
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
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport;
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
begin
  if (FWorkspace.ScriptDraft=nil) or not (FWorkspace.ScriptDraft.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  var Cast := JO(FWorkspace.ScriptDraft.ScriptWizard,'casting'); FSync := True; FList.Items.BeginUpdate;
  try
    FCharacters.Clear;
    for var V in JA(Cast,'roles') do begin var R := TJSONObject(V); if JB(R,'active') then FCharacters.Lines.Add(JI(R,'number').ToString+' = '+JS(R,'name')); end;
    FCharacters.SelStart := 0; FCharacters.Perform(EM_SCROLLCARET,0,0);
    FList.Items.Clear;
    for var V in JA(Cast,'rows') do begin
      var Row := TJSONObject(V); var C := FWorkspace.ScriptDraft.Cue(JS(Row,'cueId')); var Item := FList.Items.Add;
      Item.Caption := ScriptStageName(JS(Row,'section')); if JS(Row,'section')='opening' then Item.Caption := '出だし'
      else if JS(Row,'section')='body' then Item.Caption := '本文' else if JS(Row,'section')='closing' then Item.Caption := '締め';
      var Role := CastingRole(FWorkspace.ScriptDraft,JI(Row,'role')); var Name := '未割当'; if Role<>nil then Name := JI(Role,'number').ToString+' / '+JS(Role,'name');
      var State := '未割当'; if JS(Row,'origin')='single-default' then State := '単独候補'
      else if JS(Row,'origin')='ai' then State := 'AI案' else if JS(Row,'origin')='human' then State := '人の指定';
      if JB(Row,'confirmed') then State := State+' / 済';
      Item.SubItems.Add(Name); Item.SubItems.Add(State); Item.SubItems.Add(C.Text.Replace(#13#10,' / ')); Item.SubItems.Add(C.Id);
      if C.Id=JS(Cast,'selectedCue') then begin Item.Selected := True; Item.Focused := True; FText.Text := C.Text; FText.SelStart := 0; FReason.Text := JS(Row,'reason'); end;
    end;
    if FList.Selected<>nil then FList.Selected.MakeVisible(False);
    var Summary := ScriptCastingSummary(FWorkspace.ScriptDraft);
    try
      FGuide.Caption := '↑↓：セリフ移動 / 1～9：キャラを指定して次へ / Enter：現在の配役を確認して次へ。'+#13#10+
        '未割当 '+JI(Summary,'unassigned').ToString+' / 未確認 '+JI(Summary,'pending').ToString+'。声の紐付けは後の音声設定で行います。';
    finally Summary.Free; end;
  finally FList.Items.EndUpdate; FSync := False; end;
end;
procedure TRigmScriptCastingFrame.SetActive(Value: Boolean);
begin if Value then RefreshState; end;
end.
