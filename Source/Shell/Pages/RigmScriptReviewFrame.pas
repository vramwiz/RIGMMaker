unit RigmScriptReviewFrame;

// 第6段階の作品特定と掘り下げ確認。旧stage=reviewを維持し、原稿は編集しない。
interface
uses System.Classes, System.JSON, System.Generics.Collections, RigmScriptPageFrame,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, RigmWizardWorkspace;
type
  TRigmScriptReviewFrame = class;
  TRigmResearchRow = class(TPanel)
  private
    FPage: TRigmScriptReviewFrame; FId: string;
    FHeader,FBody: TPanel; FToggle,FInfo,FNone,FReset: TButton;
    FName,FSummary,FState: TLabel; FDetails: TMemo;
    procedure Toggle(Sender: TObject);
    procedure Decide(Sender: TObject);
    procedure LayoutRow(Sender: TObject);
  public
    constructor CreateForElement(Page: TRigmScriptReviewFrame; const Id: string);
    procedure RefreshElement(E: TJSONObject; Expanded: Boolean);
    property ElementId: string read FId;
  end;
  TRigmScriptReviewFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FTitle: TEdit; FPhase,FGuide,FType: TLabel; FIdentity: TPanel;
    FCandidates: TListBox; FOverview: TMemo; FConfirmed: TCheckBox;
    FElements: TScrollBox; FRows: TObjectList<TRigmResearchRow>;
    FCandidateIds: TArray<string>;
    procedure TitleChanged(Sender: TObject);
    procedure BeginInput(Sender: TObject);
    procedure EndInput(Sender: TObject);
    procedure CandidateSelected(Sender: TObject);
    procedure WorkConfirmed(Sender: TObject);
    procedure ElementsResized(Sender: TObject);
    procedure Apply(const Action: string; Args: TJSONObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
  end;
implementation
uses System.SysUtils, System.Math, Winapi.Windows, Vcl.Graphics, RigmJson, PsdJson, RigmScriptResearchModel;
{$R *.dfm}
constructor TRigmScriptReviewFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner);
  if AOwner is TWinControl then ScaleForPPI(TWinControl(AOwner).CurrentPPI);
  Align := alClient; FWorkspace := Workspace;
  FRows := TObjectList<TRigmResearchRow>.Create(True);
  var TitlePanel := TPanel.Create(Self); TitlePanel.Parent := Self; TitlePanel.Align := alTop;
  TitlePanel.Height := ScaleValue(86); TitlePanel.BevelOuter := bvNone; TitlePanel.Caption := '';
  TitlePanel.Padding.SetBounds(ScaleValue(8),ScaleValue(4),ScaleValue(8),ScaleValue(4));
  FPhase := TRigmScriptLabel.Create(Self); FPhase.Parent := TitlePanel; FPhase.Align := alTop;
  FPhase.Name := 'ScriptResearchPhase'; FPhase.AutoSize := False; FPhase.Height := ScaleValue(24);
  FType := TRigmScriptLabel.Create(Self); FType.Parent := TitlePanel; FType.Align := alTop;
  FType.AutoSize := False; FType.Height := ScaleValue(22); FType.Name := 'ScriptResearchType';
  FTitle := TEdit.Create(Self); FTitle.Parent := TitlePanel; FTitle.Align := alBottom;
  FTitle.Name := 'ScriptResearchTitle'; FTitle.MaxLength := 256;
  FTitle.OnEnter := BeginInput; FTitle.OnExit := EndInput; FTitle.OnChange := TitleChanged;
  FTitle.Hint := '作品タイトル。変更すると検索結果と確認状態を解除します。'; FTitle.ShowHint := True;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom;
  FGuide.Name := 'ScriptResearchGuide'; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := ScaleValue(54);
  FIdentity := TPanel.Create(Self); FIdentity.Parent := Self; FIdentity.Align := alTop;
  FIdentity.Top := TitlePanel.Height; FIdentity.Height := ScaleValue(218); FIdentity.BevelOuter := bvNone; FIdentity.Caption := '';
  FIdentity.Padding.SetBounds(ScaleValue(8),0,ScaleValue(8),ScaleValue(6));
  FCandidates := TListBox.Create(Self); FCandidates.Parent := FIdentity; FCandidates.Align := alTop;
  FCandidates.Height := ScaleValue(78); FCandidates.Name := 'ScriptResearchCandidates'; FCandidates.OnClick := CandidateSelected;
  FConfirmed := TCheckBox.Create(Self); FConfirmed.Parent := FIdentity; FConfirmed.Align := alTop;
  FConfirmed.Top := FCandidates.Height; FConfirmed.Height := ScaleValue(28);
  FConfirmed.Name := 'ScriptResearchConfirmed'; FConfirmed.Caption := 'この作品で正しい（人間による確認）'; FConfirmed.OnClick := WorkConfirmed;
  FOverview := TMemo.Create(Self); FOverview.Parent := FIdentity; FOverview.Align := alClient;
  FOverview.Name := 'ScriptResearchOverview'; FOverview.ReadOnly := True; FOverview.ScrollBars := ssVertical;
  FElements := TScrollBox.Create(Self); FElements.Parent := Self; FElements.Align := alClient;
  FElements.Name := 'ScriptResearchElements'; FElements.BorderStyle := bsNone; FElements.VertScrollBar.Tracking := True; FElements.OnResize := ElementsResized;
end;
destructor TRigmScriptReviewFrame.Destroy;
begin FRows.Free; inherited; end;
procedure TRigmScriptReviewFrame.BeginInput(Sender: TObject);
begin if not FSync then FWorkspace.BeginScriptTextEdit; end;
procedure TRigmScriptReviewFrame.EndInput(Sender: TObject);
begin FWorkspace.EndScriptTextEdit; end;
procedure TRigmScriptReviewFrame.Apply(const Action: string; Args: TJSONObject);
begin
  try
    try FWorkspace.UpdateResearch(Action,Args,True);
    except on E: Exception do begin FGuide.Caption := E.Message; end; end;
  finally Args.Free; end;
end;
procedure TRigmScriptReviewFrame.TitleChanged(Sender: TObject);
begin
  if FSync then Exit; BeginInput(Sender);
  var Args := TJSONObject.Create; Args.AddPair('title',FTitle.Text); Apply('title',Args);
end;
procedure TRigmScriptReviewFrame.CandidateSelected(Sender: TObject);
begin
  if FSync or (FCandidates.ItemIndex<0) or (FCandidates.ItemIndex>=Length(FCandidateIds)) then Exit;
  EndInput(Sender); var Args := TJSONObject.Create; Args.AddPair('id',FCandidateIds[FCandidates.ItemIndex]); Apply('select',Args);
end;
procedure TRigmScriptReviewFrame.WorkConfirmed(Sender: TObject);
begin
  if FSync then Exit; EndInput(Sender);
  var Args := TJSONObject.Create; Args.AddPair('confirmed',TJSONBool.Create(FConfirmed.Checked));
  Apply('confirm-work',Args); RefreshState;
end;
procedure TRigmScriptReviewFrame.ElementsResized(Sender: TObject);
begin
  if FSync or (FRows=nil) then Exit;
  var Y := -FElements.VertScrollBar.Position;
  FElements.DisableAlign;
  try
    for var Row in FRows do begin
      Row.SetBounds(0,Y,Max(ScaleValue(760),FElements.ClientWidth),Row.Height); Inc(Y,Row.Height);
    end;
  finally FElements.EnableAlign; end;
end;
procedure TRigmScriptReviewFrame.RefreshState;
begin
  var R := ScriptResearch(FWorkspace.ScriptDraft); if R=nil then Exit;
  FSync := True;
  try
    if FTitle.Text<>JS(R,'title') then FTitle.Text := JS(R,'title');
    var Summary := ResearchSummary(FWorkspace.ScriptDraft);
    try
      var Ready := ResearchWorkReady(R);
      if Ready then FPhase.Caption := '第2段階  掘り下げ情報の確認'
      else FPhase.Caption := '第1段階  作品の特定';
      FType.Caption := '作品タイトル  ／ 台本の種類：'+JS(Summary,'scriptTypeName');
      var Reason := JS(Summary,'advanceBlockedReason');
      if Reason='' then FGuide.Caption := 'すべての項目が確定しました。左の工程リストで次の工程へ進めます。さらに掘り下げたい場合は、Codexへの指示で項目を追加できます。'
      else if not Ready then FGuide.Caption := 'Codex側で作品検索を指示してください。候補の概要を確認し、正しい作品だけにチェックしてください。'
      else FGuide.Caption := Reason;
      FConfirmed.Checked := JB(R,'humanConfirmed');
      FConfirmed.Enabled := ResearchCandidate(R,JS(R,'selectedCandidateId'))<>nil;
      FCandidates.Visible := not Ready;
      if Ready then FIdentity.Height := ScaleValue(112) else FIdentity.Height := ScaleValue(218);
      FCandidates.Items.BeginUpdate;
      try
        FCandidates.Clear; SetLength(FCandidateIds,JA(R,'candidates').Count);
        for var I := 0 to High(FCandidateIds) do begin
          var C := TJSONObject(JA(R,'candidates')[I]); FCandidateIds[I] := JS(C,'id');
          FCandidates.Items.Add(JS(C,'name')+'  '+ResearchSingleLine(JS(C,'identity')));
          if FCandidateIds[I]=JS(R,'selectedCandidateId') then FCandidates.ItemIndex := I;
        end;
      finally FCandidates.Items.EndUpdate; end;
      var Candidate := ResearchCandidate(R,JS(R,'selectedCandidateId'));
      if Candidate=nil then FOverview.Text := '検索候補を選択すると作品の概要を表示します。'
      else begin
        var Text := JS(Candidate,'name')+#13#10+JS(Candidate,'identity')+#13#10+JS(Candidate,'overview');
        if JS(Candidate,'details')<>'' then Text := Text+#13#10+JS(Candidate,'details');
        if Candidate.GetValue('sources')<>nil then for var V in JA(Candidate,'sources') do Text := Text+#13#10+V.Value;
        if FOverview.Text<>Text then FOverview.Text := Text;
      end;
      FElements.Visible := Ready;
      var Items := JA(R,'elements'); var Rebuild := FRows.Count<>Items.Count;
      if not Rebuild then for var I := 0 to Items.Count-1 do
        if FRows[I].ElementId<>JS(TJSONObject(Items[I]),'id') then begin Rebuild := True; Break; end;
      FElements.DisableAlign;
      try
        if Rebuild then begin
          FRows.Clear;
          for var V in Items do FRows.Add(TRigmResearchRow.CreateForElement(Self,JS(TJSONObject(V),'id')));
        end;
        var Y := -FElements.VertScrollBar.Position;
        for var I := 0 to Items.Count-1 do begin
          var Row := FRows[I]; Row.RefreshElement(TJSONObject(Items[I]),JS(R,'expandedElementId')=Row.ElementId);
          Row.SetBounds(0,Y,Max(ScaleValue(760),FElements.ClientWidth),Row.Height); Inc(Y,Row.Height);
        end;
      finally FElements.EnableAlign; end;
    finally Summary.Free; end;
  finally FSync := False; end;
end;
function TRigmScriptReviewFrame.RequestFinish: Boolean;
begin
  Result := False;
  if FTitle.Text<>JS(ScriptResearch(FWorkspace.ScriptDraft),'title') then begin
    FGuide.Caption := '作品タイトルを確認してください。入力を保持しています。'; Exit;
  end;
  FWorkspace.EndScriptTextEdit; Result := True;
end;
procedure TRigmScriptReviewFrame.SetActive(Value: Boolean);
begin if Value then RefreshState else if FWorkspace.CurrentScriptStage='review' then FWorkspace.EndScriptTextEdit; end;
constructor TRigmResearchRow.CreateForElement(Page: TRigmScriptReviewFrame; const Id: string);
begin
  inherited Create(Page); FPage := Page; FId := Id; Parent := Page.FElements;
  BevelOuter := bvNone; Caption := ''; ParentBackground := True;
  FHeader := TPanel.Create(Self); FHeader.Parent := Self; FHeader.Align := alTop;
  FHeader.Height := MulDiv(34,Page.CurrentPPI,96); FHeader.BevelOuter := bvNone; FHeader.Caption := '';
  FHeader.OnResize := LayoutRow;
  FToggle := TButton.Create(Self); FToggle.Parent := FHeader; FToggle.OnClick := Toggle;
  FName := TLabel.Create(Self); FName.Parent := FHeader; FName.AutoSize := False; FName.Layout := tlCenter;
  FSummary := TLabel.Create(Self); FSummary.Parent := FHeader; FSummary.AutoSize := False; FSummary.Layout := tlCenter;
  FState := TLabel.Create(Self); FState.Parent := FHeader; FState.AutoSize := False; FState.Layout := tlCenter;
  FBody := TPanel.Create(Self); FBody.Parent := Self; FBody.Align := alClient; FBody.BevelOuter := bvNone; FBody.Caption := '';
  var Actions := TPanel.Create(Self); Actions.Parent := FBody; Actions.Align := alBottom;
  Actions.Height := MulDiv(34,Page.CurrentPPI,96); Actions.BevelOuter := bvNone; Actions.Caption := '';
  FInfo := TButton.Create(Self); FInfo.Parent := Actions; FInfo.Align := alLeft; FInfo.Width := MulDiv(134,Page.CurrentPPI,96);
  FInfo.Caption := '情報ありで確定'; FInfo.Tag := 0; FInfo.OnClick := Decide;
  FNone := TButton.Create(Self); FNone.Parent := Actions; FNone.Align := alLeft; FNone.Left := FInfo.Width;
  FNone.Width := MulDiv(134,Page.CurrentPPI,96); FNone.Caption := '情報なしで確定'; FNone.Tag := 1; FNone.OnClick := Decide;
  FReset := TButton.Create(Self); FReset.Parent := Actions; FReset.Align := alLeft; FReset.Left := FInfo.Width+FNone.Width;
  FReset.Width := MulDiv(100,Page.CurrentPPI,96); FReset.Caption := '確定を解除'; FReset.Tag := 2; FReset.OnClick := Decide;
  FDetails := TMemo.Create(Self); FDetails.Parent := FBody; FDetails.Align := alClient;
  FDetails.ReadOnly := True; FDetails.ScrollBars := ssVertical;
end;
procedure TRigmResearchRow.LayoutRow(Sender: TObject);
begin
  if FToggle=nil then Exit;
  var Ppi := FPage.CurrentPPI; var H := FHeader.Height; var X := MulDiv(174,Ppi,96);
  FToggle.SetBounds(0,0,X-MulDiv(6,Ppi,96),H); FName.SetBounds(X,0,MulDiv(146,Ppi,96),H);
  Inc(X,FName.Width); var StateWidth := MulDiv(140,Ppi,96);
  FState.SetBounds(Max(X,FHeader.ClientWidth-StateWidth),0,StateWidth,H);
  FSummary.SetBounds(X,0,Max(0,FState.Left-X-MulDiv(8,Ppi,96)),H);
end;
procedure TRigmResearchRow.RefreshElement(E: TJSONObject; Expanded: Boolean);
begin
  FToggle.Caption := '+ '+JS(E,'label'); if Expanded then FToggle.Caption := '− '+JS(E,'label');
  FName.Caption := ResearchSingleLine(JS(E,'name')); FName.Hint := FName.Caption; FName.ShowHint := True;
  FSummary.Caption := ResearchSingleLine(JS(E,'summary')); FSummary.Hint := FSummary.Caption; FSummary.ShowHint := True;
  FState.Caption := ResearchStateName(JS(E,'state')); FState.ParentFont := True;
  if JS(E,'state')='confirmed-info' then FState.Font.Color := clLime
  else if JS(E,'state')='confirmed-none' then FState.Font.Color := $0040CFFF
  else if JS(E,'state')='checking' then FState.Font.Color := $00FFD080;
  var Text := JS(E,'label')+'  '+JS(E,'name')+#13#10+JS(E,'summary')+#13#10+JS(E,'details');
  for var V in JA(E,'sources') do Text := Text+#13#10+V.Value;
  if JS(E,'confirmedBy')='human' then Text := Text+#13#10+'確認結果：人間が確定'
  else if JS(E,'confirmedBy')='codex' then Text := Text+#13#10+'確認結果：Codexが確定';
  if FDetails.Text<>Text then FDetails.Text := Text;
  FBody.Visible := Expanded;
  Height := MulDiv(34,FPage.CurrentPPI,96); if Expanded then Height := MulDiv(216,FPage.CurrentPPI,96);
  LayoutRow(Self);
end;
procedure TRigmResearchRow.Toggle(Sender: TObject);
begin
  var Args := TJSONObject.Create; var Id := FId;
  if JS(ScriptResearch(FPage.FWorkspace.ScriptDraft),'expandedElementId')=FId then Id := '';
  Args.AddPair('id',Id); FPage.Apply('expand',Args);
end;
procedure TRigmResearchRow.Decide(Sender: TObject);
const States: array[0..2] of string = ('confirmed-info','confirmed-none','unconfirmed');
begin
  var Args := TJSONObject.Create; Args.AddPair('id',FId); Args.AddPair('state',States[TButton(Sender).Tag]);
  FPage.Apply('decide',Args);
end;
end.
