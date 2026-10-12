unit RigmScriptConfirmationFrame;

// 前段・本題・総評・締めを同じ画面で編集する。正本と保存はWorkspaceへ委譲する。
interface
uses System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, RigmScriptPageFrame,
  RigmScriptTextFrame, RigmWizardWorkspace;
type
  TRigmScriptConfirmationFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FBoxes: array[0..3] of TPanel; FEditors: array[0..3] of TRigmScriptMemo;
    FLabels: array[0..3] of TLabel;
    FBody,FActions,FTitleBar: TPanel; FGuide,FBlocked: TLabel; FRepair: TButton;
    FWorkTitle: TEdit; FCopyTitle: TButton;
    procedure CopyTitle(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure RepairSummary(Sender: TObject);
    procedure LayoutEditors;
  protected
    procedure Resize; override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, RigmJson, RigmScriptTextModel,
  RigmScriptSummaryModel, RigmScriptResearchModel, Vcl.Clipbrd;
{$R *.dfm}
const Ids: array[0..3] of string = ('opening','body','summary','closing');
  Captions: array[0..3] of string = ('前段の台本','本題：ここが台本','総評のセリフ','〆のセリフ');
constructor TRigmScriptConfirmationFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; FSync := True; Align := alClient;
  FTitleBar := TPanel.Create(Self); FTitleBar.Parent := Self; FTitleBar.Align := alTop;
  FTitleBar.Height := ScaleValue(44); FTitleBar.BevelOuter := bvNone; FTitleBar.ShowCaption := False;
  FTitleBar.Padding.SetBounds(ScaleValue(8),ScaleValue(6),ScaleValue(8),ScaleValue(6));
  var TitleLabel := TRigmScriptLabel.Create(Self); TitleLabel.Parent := FTitleBar; TitleLabel.Align := alLeft;
  TitleLabel.AutoSize := False; TitleLabel.Width := ScaleValue(72); TitleLabel.Layout := tlCenter; TitleLabel.Caption := '作品名';
  FCopyTitle := TButton.Create(Self); FCopyTitle.Parent := FTitleBar; FCopyTitle.Align := alRight;
  FCopyTitle.Width := ScaleValue(112); FCopyTitle.Caption := '作品名をコピー';
  FCopyTitle.Name := 'ScriptConfirmationCopyTitle'; FCopyTitle.OnClick := CopyTitle;
  FWorkTitle := TEdit.Create(Self); FWorkTitle.Parent := FTitleBar; FWorkTitle.Align := alClient;
  FWorkTitle.Name := 'ScriptConfirmationWorkTitle'; FWorkTitle.ReadOnly := True;
  FWorkTitle.AlignWithMargins := True; FWorkTitle.Margins.SetBounds(0,0,ScaleValue(8),0);
  FWorkTitle.ShowHint := True;
  FActions := TPanel.Create(Self); FActions.Parent := Self; FActions.Align := alTop;
  FTitleBar.Top := 0; FActions.Top := FTitleBar.Height; FActions.Height := ScaleValue(76); FActions.BevelOuter := bvNone; FActions.ShowCaption := False;
  FActions.Padding.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(8),ScaleValue(8));
  FRepair := TButton.Create(Self); FRepair.Parent := FActions; FRepair.Align := alRight;
  FRepair.Width := ScaleValue(300); FRepair.Name := 'ScriptConfirmationRepairSummary';
  FRepair.Caption := '第8段階の総評チャートを入力する'; FRepair.OnClick := RepairSummary;
  FBlocked := TRigmScriptLabel.Create(Self); FBlocked.Parent := FActions; FBlocked.Align := alClient;
  FBlocked.Name := 'ScriptConfirmationBlockedReason'; FBlocked.AutoSize := False; FBlocked.WordWrap := True;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom;
  FGuide.Height := ScaleValue(54); FGuide.AutoSize := False; FGuide.WordWrap := True;
  FGuide.Name := 'ScriptConfirmationGuide';
  FBody := TPanel.Create(Self); FBody.Parent := Self; FBody.Align := alClient; FBody.BevelOuter := bvNone; FBody.ShowCaption := False;
  for var I := 0 to 3 do begin
    FBoxes[I] := TPanel.Create(Self); FBoxes[I].Parent := FBody; FBoxes[I].BevelOuter := bvNone; FBoxes[I].ShowCaption := False;
    FBoxes[I].Padding.SetBounds(ScaleValue(8),ScaleValue(6),ScaleValue(8),ScaleValue(6));
    var L := TRigmScriptLabel.Create(Self); FLabels[I] := L; L.Parent := FBoxes[I]; L.Align := alTop; L.Caption := Captions[I];
    L.Name := 'ScriptConfirmLabel'+Ids[I];
    L.AutoSize := False; L.Height := ScaleValue(32); L.Font.Size := 12;
    FEditors[I] := TRigmScriptMemo.Create(Self); FEditors[I].Parent := FBoxes[I]; FEditors[I].Align := alClient;
    FEditors[I].Name := 'ScriptConfirm'+Ids[I]; FEditors[I].Tag := I; FEditors[I].ScrollBars := ssVertical;
    FEditors[I].Font.Size := 12; FEditors[I].MaxLength := ScriptSectionLimit;
    if I=2 then FEditors[I].MaxLength := 2000;
    FEditors[I].OnChange := Changed;
  end;
  FSync := False; LayoutEditors;
end;
procedure TRigmScriptConfirmationFrame.LayoutEditors;
begin
  if (FBody=nil) or (FBoxes[3]=nil) then Exit;
  var W := FBody.ClientWidth div 2; var H := FBody.ClientHeight div 2;
  for var I := 0 to 3 do FBoxes[I].SetBounds((I mod 2)*W,(I div 2)*H,
    W+(I mod 2)*(FBody.ClientWidth-2*W),H+(I div 2)*(FBody.ClientHeight-2*H));
end;
procedure TRigmScriptConfirmationFrame.Resize;
begin inherited; LayoutEditors; end;
procedure TRigmScriptConfirmationFrame.Changed(Sender: TObject);
begin
  if FSync then Exit;
  try FWorkspace.SetScriptText(Ids[TControl(Sender).Tag],TRigmScriptMemo(Sender).Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptConfirmationFrame.CopyTitle(Sender: TObject);
begin
  if FWorkTitle.Text='' then Exit;
  try Clipboard.AsText := FWorkTitle.Text;
  except on E: Exception do FGuide.Caption := '作品名をコピーできませんでした：'+E.Message; end;
end;
procedure TRigmScriptConfirmationFrame.RepairSummary(Sender: TObject);
begin
  try FWorkspace.SetScriptStage('summary-edit');
  except on E: Exception do FBlocked.Caption := E.Message; end;
end;
procedure TRigmScriptConfirmationFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit; FSync := True;
  try
    var Title := '';
    var Research := ScriptResearch(P);
    if Research<>nil then begin
      var Candidate := ResearchCandidate(Research,JS(Research,'selectedCandidateId'));
      if Candidate<>nil then Title := JS(Candidate,'name');
      if Trim(Title)='' then Title := JS(Research,'title');
    end;
    if Trim(Title)='' then Title := P.Title;
    if FWorkTitle.Text<>Title then FWorkTitle.Text := Title;
    FWorkTitle.Hint := Title; FCopyTitle.Enabled := Trim(Title)<>'';
    for var I := 0 to 3 do begin
      var Section := ScriptSection(P,Ids[I]); var Text := '';
      if Section<>nil then Text := JS(Section,'text');
      if NormalizeScriptText(FEditors[I].Text)<>Text then FEditors[I].Text := Text;
      if I=2 then begin
        FEditors[I].Enabled := True; FEditors[I].ReadOnly := False;
        FLabels[I].Caption := Captions[I]; FEditors[I].TextHint := '総評のセリフを入力してください';
        if JS(P.ScriptWizard,'summaryChoice')='none' then begin
          FLabels[I].Caption := '総評のセリフ（総評なし・下書きを保存）';
          FEditors[I].TextHint := '入力は下書きとして保存し、動画には使用しません';
        end;
      end;
    end;
    var Guide := '各欄でセリフを確認・編集してください。左の工程リストで保存して配役へ進みます。';
    if JS(P.ScriptWizard,'summaryChoice')<>'yes' then Guide := Guide+#13#10+
      '総評の選択は入力で変わりません。総評を動画に入れる場合は、第7段階で「総評あり」を選んでください。';
    if FGuide.Caption<>Guide then FGuide.Caption := Guide;
    var State := FWorkspace.ScriptStatus;
    try
      FBlocked.Caption := JS(State,'advanceBlockedReason'); FActions.Visible := FBlocked.Caption<>'';
      FRepair.Visible := (JS(P.ScriptWizard,'summaryChoice')='yes') and
        (P.ScriptWizard.GetValue('summaryData') is TJSONObject) and
        (ScriptSummaryDraftReason(JO(JO(P.ScriptWizard,'summaryData'),'draft'))<>'');
    finally State.Free; end;
  finally FSync := False; end;
end;
end.
