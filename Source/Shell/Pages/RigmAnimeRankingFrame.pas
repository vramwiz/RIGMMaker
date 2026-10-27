unit RigmAnimeRankingFrame;
interface
uses System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.Grids, Vcl.ComCtrls,
  RigmScriptPageFrame, RigmScriptTextFrame, RigmWizardWorkspace;
type
  TRigmAnimeRankingFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FFields: TStringGrid; FSections: TTabControl; FMemo: TRigmScriptMemo; FGuide: TLabel;
    procedure FieldEdited(Sender: TObject; ACol,ARow: Integer; const Value: string);
    procedure SectionChanged(Sender: TObject);
    procedure TextChanged(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
  end;
implementation
uses System.SysUtils, System.JSON, RigmJson, RigmAnimeRankingModel, RigmScriptTextModel;
{$R *.dfm}
constructor TRigmAnimeRankingFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FSync := True;
  FFields := TStringGrid.Create(Self); FFields.Parent := Self; FFields.Align := alTop;
  FFields.Name := 'AnimeRankingFields'; FFields.Height := ScaleValue(244);
  FFields.ColCount := 2; FFields.RowCount := Length(AnimeRankingFields)+1;
  FFields.FixedCols := 1; FFields.FixedRows := 1; FFields.ColWidths[0] := ScaleValue(260); FFields.ColWidths[1] := ScaleValue(500);
  FFields.Options := FFields.Options+[goEditing,goAlwaysShowEditor]; FFields.Col := 1;
  FFields.Cells[0,0] := '作品情報'; FFields.Cells[1,0] := '入力（空欄は未確認。調査結果を推測しません）';
  for var I := 0 to High(AnimeRankingFields) do FFields.Cells[0,I+1] := AnimeRankingFieldNames[I];
  FFields.OnSetEditText := FieldEdited;
  FSections := TTabControl.Create(Self); FSections.Parent := Self; FSections.Align := alTop;
  FSections.Name := 'AnimeRankingSections'; FSections.Height := ScaleValue(38); FSections.Top := FFields.Height;
  for var I := 0 to High(AnimeRankingSections)-1 do FSections.Tabs.Add(AnimeRankingSectionNames[I]);
  FSections.OnChange := SectionChanged;
  FMemo := TRigmScriptMemo.Create(Self); FMemo.Parent := Self; FMemo.Align := alClient;
  FMemo.Name := 'AnimeRankingDialogue'; FMemo.Font.Size := 14; FMemo.ScrollBars := ssVertical;
  FMemo.MaxLength := ScriptSectionLimit; FMemo.OnChange := TextChanged;
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom;
  FGuide.Name := 'AnimeRankingGuide'; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := ScaleValue(70);
  FSync := False;
end;
procedure TRigmAnimeRankingFrame.FieldEdited(Sender: TObject; ACol,ARow: Integer; const Value: string);
begin
  if FSync or (ACol<>1) or (ARow<1) then Exit;
  try FWorkspace.SetAnimeRankingField(AnimeRankingFields[ARow-1],Value);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmAnimeRankingFrame.SectionChanged(Sender: TObject);
begin
  if FSync or (FSections.TabIndex<0) then Exit;
  try FWorkspace.SelectScriptSection(AnimeRankingSections[FSections.TabIndex]); RefreshState;
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmAnimeRankingFrame.TextChanged(Sender: TObject);
begin
  if FSync or (FSections.TabIndex<0) then Exit;
  try FWorkspace.SetScriptText(AnimeRankingSections[FSections.TabIndex],FMemo.Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmAnimeRankingFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or FSync then Exit; FSync := True;
  try
    var O := JO(P.ScriptWizard,'animeRanking');
    for var I := 0 to High(AnimeRankingFields) do FFields.Cells[1,I+1] := JS(O,AnimeRankingFields[I]);
    var Active := JS(JO(P.ScriptWizard,'scriptText'),'activeSection','rank'); var Index := 0;
    for var I := 0 to High(AnimeRankingSections)-1 do if AnimeRankingSections[I]=Active then Index := I;
    FSections.TabIndex := Index;
    var Text := JS(ScriptSection(P,AnimeRankingSections[Index]),'text');
    if NormalizeScriptText(FMemo.Text)<>Text then FMemo.Text := Text;
    FGuide.Caption := '順位 → 作品タイトル・概要（同じ画面）→ 登場人物・制作情報・OP/ED → 作品総評のパートです。'+#13#10+
      'OP/EDの紹介と評価は各タブへ。原作なし・曲なし・未確認も入力できます。総評は次の6項目チャートで入力します。'+#13#10+
      '順位は背景画像・人物なし、黒一色＋大きな白文字。表示：第'+JS(O,'rank')+'位。順位のセリフを手で編集した後は自動変更しないため、表示との一致を確認してください。';
  finally FSync := False; end;
end;
end.
