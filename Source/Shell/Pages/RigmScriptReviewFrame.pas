unit RigmScriptReviewFrame;

// 外部Codexの校正を一覧・本文位置・編集案で確認する。Workspaceを借用する。
interface
uses System.Classes, RigmScriptPageFrame, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  RigmWizardWorkspace, RigmIconToolbar, RigmScriptTextFrame;
type
  TRigmScriptReviewFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean; FLoadedId: string;
    FList: TListView; FContext: TMemo; FProposal: TRigmScriptMemo;
    FReason: TMemo; FGuide: TLabel; FToolbar: TRigmIconToolbar;
    procedure Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure RequestReview(Sender: TObject);
    procedure Decide(Sender: TObject);
    procedure BeginInput(Sender: TObject);
    procedure EndInput(Sender: TObject);
    procedure Changed(Sender: TObject);
    function SelectedId: string;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
  end;
implementation
uses System.SysUtils, System.JSON, RigmJson, RigmScriptReviewModel, RigmScriptTextModel, RigmToolbarIcons;
{$R *.dfm}
constructor TRigmScriptReviewFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptReviewToolbar';
  FToolbar.AddIcon('ScriptReviewRequest','Codexへ校正を依頼／再依頼する',riRefresh,0,RequestReview);
  FToolbar.AddSeparator;
  FToolbar.AddIcon('ScriptReviewAI','AI案を採用',riComplete,0,Decide).Tag := 0;
  FToolbar.AddIcon('ScriptReviewHuman','現在の文章を採用',riSave,0,Decide).Tag := 1;
  FToolbar.AddIcon('ScriptReviewEdited','編集した案を採用',riEditPreview,0,Decide).Tag := 2;
  FToolbar.AddIcon('ScriptReviewHold','保留する',riLayer,0,Decide).Tag := 3;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom;
  FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := ScaleValue(76); FGuide.Name := 'ScriptReviewGuide';
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := ScaleValue(320);
  FList.Name := 'ScriptReviewItems'; FList.ViewStyle := vsReport; FList.ReadOnly := True;
  FList.RowSelect := True; FList.HideSelection := False; FList.OnSelectItem := Selected;
  FList.Columns.Add.Caption := '区分・指摘'; FList.Columns[0].Width := ScaleValue(200);
  FList.Columns.Add.Caption := '採否'; FList.Columns[1].Width := ScaleValue(95);
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.BevelOuter := bvNone; Body.Caption := '';
  Body.Padding.SetBounds(ScaleValue(12),ScaleValue(8),ScaleValue(12),ScaleValue(8));
  var Detail := TPanel.Create(Self); Detail.Parent := Body; Detail.Align := alBottom; Detail.Height := ScaleValue(200); Detail.BevelOuter := bvNone; Detail.Caption := '';
  FReason := TMemo.Create(Self); FReason.Parent := Detail; FReason.Align := alTop; FReason.ReadOnly := True;
  FReason.WordWrap := True; FReason.ScrollBars := ssVertical; FReason.Height := ScaleValue(76); FReason.Name := 'ScriptReviewReason';
  var Vertical := TSplitter.Create(Self); Vertical.Parent := Body; Vertical.Align := alBottom; Vertical.Top := Detail.Top-8; Vertical.Height := ScaleValue(8);
  FProposal := TRigmScriptMemo.Create(Self); FProposal.Parent := Detail; FProposal.Align := alClient;
  FProposal.Name := 'ScriptReviewProposal'; FProposal.Font.Size := 14; FProposal.ScrollBars := ssVertical;
  FProposal.MaxLength := 4096; FProposal.OnEnter := BeginInput; FProposal.OnBeginInput := BeginInput; FProposal.OnExit := EndInput;
  FProposal.OnChange := Changed;
  FContext := TMemo.Create(Self); FContext.Parent := Body; FContext.Align := alClient;
  FContext.Name := 'ScriptReviewContext'; FContext.ReadOnly := True; FContext.Font.Size := 14;
  FContext.ScrollBars := ssVertical; FContext.HideSelection := False;
end;
function TRigmScriptReviewFrame.SelectedId: string;
begin Result := ''; if FList.Selected<>nil then Result := FList.Selected.SubItems[1]; end;
procedure TRigmScriptReviewFrame.BeginInput(Sender: TObject);
begin if not FSync then FWorkspace.BeginScriptTextEdit; end;
procedure TRigmScriptReviewFrame.EndInput(Sender: TObject);
begin FWorkspace.EndScriptTextEdit; end;
procedure TRigmScriptReviewFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; BeginInput(Sender);
  try FWorkspace.EditReviewDraft(SelectedId,FProposal.Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptReviewFrame.Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSync or not Selected then Exit; FWorkspace.EndScriptTextEdit;
  var O := ReviewItem(FWorkspace.ScriptDraft,SelectedId); if O=nil then Exit;
  FSync := True;
  try
    var S := ScriptSection(FWorkspace.ScriptDraft,JS(O,'section')); FContext.Text := JS(S,'text');
    FContext.SelStart := JI(O,'offset'); FContext.SelLength := Length(JS(O,'original'));
    FContext.Perform($00B7,0,0); // EM_SCROLLCARET: 指摘対象を本文内へスクロールする。
    FProposal.Text := JS(O,'editedDraft',JS(O,'proposed')); FLoadedId := SelectedId;
    FReason.Text := 'AI修正案（編集できます）'+#13#10+JS(O,'reason');
    FProposal.Enabled := (JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'review'),'state')='ready') and
      ((JS(O,'decision')='pending') or (JS(O,'decision')='hold'));
  finally FSync := False; end;
end;
procedure TRigmScriptReviewFrame.RequestReview(Sender: TObject);
begin
  FWorkspace.EndScriptTextEdit;
  try FWorkspace.RequestReview; except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptReviewFrame.Decide(Sender: TObject);
const Decisions: array[0..3] of string = ('ai','human','edited','hold');
begin
  FWorkspace.EndScriptTextEdit;
  try FWorkspace.DecideReview(SelectedId,Decisions[TToolButton(Sender).Tag],FProposal.Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptReviewFrame.RefreshState;
begin
  if FWorkspace.ScriptDraft=nil then Exit;
  var Summary := ScriptReviewSummary(FWorkspace.ScriptDraft);
  try
    var State := JS(Summary,'state');
    if State='requested' then FGuide.Caption := 'Codexの校正待ちです。Codexへ入力完了を伝えてください。提案はパイプで届きます。'
    else if State='stale' then FGuide.Caption := '原稿が変わりました。校正を再依頼してください。古い提案は採用できません。'
    else FGuide.Caption := '指摘を選ぶと本文の対象位置を表示します。AI案・現在の文章・編集した案の採用、または保留を選べます。';
    FGuide.Caption := FGuide.Caption+#13#10+'未確定 '+JI(Summary,'pending').ToString+' / 保留 '+JI(Summary,'held').ToString+' / 要再確認 '+JI(Summary,'stale').ToString;
    var Id := SelectedId; FSync := True; FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      if FWorkspace.ScriptDraft.ScriptWizard.GetValue('review')<>nil then
        for var V in JA(JO(FWorkspace.ScriptDraft.ScriptWizard,'review'),'items') do begin
          var O := TJSONObject(V); var Item := FList.Items.Add;
          Item.Caption := JS(O,'section')+' '+JS(O,'original').Replace(#13#10,' ').Substring(0,24);
          var Decision := JS(O,'decision');
          if Decision='pending' then Decision := '未確定' else if Decision='hold' then Decision := '保留'
          else if Decision='ai' then Decision := 'AI採用' else if Decision='human' then Decision := '現文採用'
          else if Decision='edited' then Decision := '編集採用' else if Decision='stale' then Decision := '要再確認';
          Item.SubItems.Add(Decision); Item.SubItems.Add(JS(O,'id'));
          if JS(O,'id')=Id then Item.Selected := True;
        end;
      if (FList.Selected=nil) and (FList.Items.Count>0) then FList.Items[0].Selected := True;
    finally FList.Items.EndUpdate; FSync := False; end;
    if SelectedId<>FLoadedId then Selected(Self,FList.Selected,True)
    else if not FWorkspace.ScriptTextEditing then Selected(Self,FList.Selected,True);
    if FList.Items.Count=0 then begin
      FSync := True;
      try FLoadedId := ''; FContext.Clear; FProposal.Clear; FProposal.Enabled := False; FReason.Clear;
      finally FSync := False; end;
    end;
  finally Summary.Free; end;
end;
procedure TRigmScriptReviewFrame.SetActive(Value: Boolean);
begin if Value then RefreshState else if FWorkspace.CurrentScriptStage='review' then FWorkspace.EndScriptTextEdit; end;
end.
