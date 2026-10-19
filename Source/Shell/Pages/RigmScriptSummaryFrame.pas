unit RigmScriptSummaryFrame;
interface
uses System.Classes, RigmScriptPageFrame, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids,
  RigmWizardWorkspace, RigmIconToolbar, RigmScriptTextFrame;
type
  TRigmSummaryChartPreview = class(TCustomControl)
  private FWorkspace: TRigmWizardWorkspace;
  protected procedure Paint; override;
  public constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
  end;
  TRigmScriptSummaryFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing: Boolean; FLoaded: string;
    FText,FSubtitle,FReading: TRigmScriptMemo; FTitle,FMinimum,FMaximum: TEdit;
    FKind: TComboBox; FGrid: TStringGrid; FGuide: TLabel; FPreview: TRigmSummaryChartPreview;
    FColumns: TPanel; FTextColumn,FChartColumn: TPanel; FTextBoxes: array[0..2] of TPanel;
    FOptions: TPanel; FMinLabel,FMaxLabel: TLabel;
    procedure LayoutColumns;
    function Draft: System.JSON.TJSONObject;
    procedure Changed(Sender: TObject);
    procedure GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
    procedure Edit(Sender: TObject);
    procedure Done(Sender: TObject);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure Resize; override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    function RequestFinish: Boolean;
  end;
implementation
uses System.Generics.Collections, System.SysUtils, System.Types, System.Math, Winapi.Windows, Vcl.Graphics,
  RigmJson, PsdJson, RigmMovieChart, RigmScriptSummaryModel, RigmScriptCastingModel, RigmToolbarIcons;
{$R *.dfm}
constructor TRigmSummaryChartPreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(AOwner); FWorkspace := Workspace; DoubleBuffered := True; end;
procedure TRigmSummaryChartPreview.Paint;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect);
  try var Chart := ScriptSummaryChart(JO(JO(FWorkspace.ScriptDraft.ScriptWizard,'summaryData'),'draft'));
    try var K := Min(ClientWidth/980,ClientHeight/550); var W := Round(980*K); var H := Round(550*K); DrawMovieChart(Canvas,Chart,Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2)); finally Chart.Free; end;
  except on E: Exception do begin Canvas.Font.Color := clSilver; Canvas.Font.Height := -20; var R := ClientRect; InflateRect(R,-16,-16); DrawText(Canvas.Handle,PChar('評価要素と値を人間が入力すると実チャートを表示します。'+#13#10+E.Message),-1,R,DT_LEFT or DT_WORDBREAK); end; end;
end;
constructor TRigmScriptSummaryFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
  function Memo(Index: Integer; const Name,Caption: string): TRigmScriptMemo;
  begin
    var Panel := TPanel.Create(Self); FTextBoxes[Index] := Panel; Panel.Parent := FTextColumn;
    Panel.BevelOuter := bvNone; Panel.ShowCaption := False; Panel.Padding.SetBounds(0,0,ScaleValue(10),ScaleValue(10));
    var L := TRigmScriptLabel.Create(Self); L.Parent := Panel; L.Align := alTop;
    L.AutoSize := False; L.Height := ScaleValue(30); L.Caption := Caption; L.Font.Size := 12;
    Result := TRigmScriptMemo.Create(Self); Result.Parent := Panel; Result.Align := alClient; Result.Name := Name;
    Result.MaxLength := 2000; Result.Font.Size := 12; Result.ScrollBars := ssVertical;
    Result.ReadOnly := False; Result.OnChange := Changed; Result.OnKeyDown := Key;
  end;
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FSync := True;
  var Tools := TRigmIconToolbar.Create(Self); Tools.Parent := Self; Tools.Align := alTop; Tools.Name := 'ScriptSummaryToolbar';
  Tools.AddIcon('ScriptSummaryEdit','総評の入力',riEditPreview,0,Edit);
  Tools.AddIcon('ScriptSummaryDone','入力完了（途中の数値も保存）',riSave,0,Done);
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom;
  FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := ScaleValue(54); FGuide.Name := 'ScriptSummaryGuide';
  FColumns := TPanel.Create(Self); FColumns.Parent := Self; FColumns.Align := alClient;
  FColumns.BevelOuter := bvNone; FColumns.ShowCaption := False; FColumns.Padding.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(8),ScaleValue(8));
  FTextColumn := TPanel.Create(Self); FTextColumn.Parent := FColumns; FTextColumn.Align := alLeft;
  FTextColumn.BevelOuter := bvNone; FTextColumn.ShowCaption := False; FTextColumn.Name := 'ScriptSummaryTextColumn';
  FChartColumn := TPanel.Create(Self); FChartColumn.Parent := FColumns; FChartColumn.Align := alClient;
  FChartColumn.BevelOuter := bvNone; FChartColumn.ShowCaption := False; FChartColumn.Name := 'ScriptSummaryChartColumn';
  FText := Memo(0,'ScriptSummaryText','総評のセリフ（2000文字以内）');
  FSubtitle := Memo(1,'ScriptSummarySubtitle','表示字幕（空ならセリフを使用）'); FSubtitle.MaxLength := 3000;
  FReading := Memo(2,'ScriptSummaryReading','読み（空ならセリフを使用）');
  FOptions := TPanel.Create(Self); FOptions.Parent := FChartColumn; FOptions.Align := alTop;
  FOptions.Height := ScaleValue(100); FOptions.BevelOuter := bvNone; FOptions.ShowCaption := False;
  FKind := TComboBox.Create(Self); FKind.Parent := FOptions; FKind.Style := csDropDownList;
  FKind.Items.Add('レーダー'); FKind.Items.Add('棒'); FKind.Name := 'ScriptSummaryKind'; FKind.OnChange := Changed;
  FTitle := TEdit.Create(Self); FTitle.Parent := FOptions; FTitle.MaxLength := 120;
  FTitle.TextHint := 'チャート題名'; FTitle.Name := 'ScriptSummaryTitle'; FTitle.OnChange := Changed;
  FMinLabel := TRigmScriptLabel.Create(Self); FMinLabel.Parent := FOptions; FMinLabel.AutoSize := False; FMinLabel.Caption := '最小値';
  FMinimum := TEdit.Create(Self); FMinimum.Parent := FOptions; FMinimum.MaxLength := 32; FMinimum.Name := 'ScriptSummaryMinimum'; FMinimum.OnChange := Changed;
  FMaxLabel := TRigmScriptLabel.Create(Self); FMaxLabel.Parent := FOptions; FMaxLabel.AutoSize := False; FMaxLabel.Caption := '最大値';
  FMaximum := TEdit.Create(Self); FMaximum.Parent := FOptions; FMaximum.MaxLength := 32; FMaximum.Name := 'ScriptSummaryMaximum'; FMaximum.OnChange := Changed;
  FGrid := TStringGrid.Create(Self); FGrid.Parent := FChartColumn; FGrid.Align := alTop; FGrid.Top := ScaleValue(100);
  FGrid.Name := 'ScriptSummaryAxes'; FGrid.ColCount := 2; FGrid.RowCount := Length(ScriptSummaryAxisNames)+1; FGrid.FixedCols := 1; FGrid.FixedRows := 1;
  FGrid.DefaultRowHeight := ScaleValue(32); FGrid.Font.Size := 12; FGrid.DoubleBuffered := True; FGrid.Options := (FGrid.Options-[goRangeSelect])+[goEditing,goAlwaysShowEditor,goTabs];
  FGrid.Col := 1; FGrid.Cells[0,0] := '評価項目（固定5項目）'; FGrid.Cells[1,0] := '点数（必須）'; FGrid.OnSetEditText := GridEdit; FGrid.OnKeyDown := Key;
  FPreview := TRigmSummaryChartPreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := FChartColumn; FPreview.Align := alClient;
  FPreview.Name := 'ScriptSummaryPreview'; FSync := False; LayoutColumns;
end;
procedure TRigmScriptSummaryFrame.LayoutColumns;
begin
  if (FColumns=nil) or (FPreview=nil) then Exit;
  FTextColumn.Width := Round((FColumns.ClientWidth-ScaleValue(16))*0.55);
  var H := FTextColumn.ClientHeight; var Y := 0;
  for var I := 0 to 2 do begin
    var Part := Round(H*0.25); if I=0 then Part := H-2*Part;
    FTextBoxes[I].SetBounds(0,Y,FTextColumn.ClientWidth,Part); Inc(Y,Part);
  end;
  var W := FChartColumn.ClientWidth; var Half := W div 2; var Gap := ScaleValue(8); var LabelW := ScaleValue(56);
  FKind.SetBounds(0,0,ScaleValue(130),ScaleValue(30));
  FTitle.SetBounds(ScaleValue(138),0,Max(0,W-ScaleValue(138)),ScaleValue(30));
  FMinLabel.SetBounds(0,ScaleValue(46),LabelW,ScaleValue(26));
  FMinimum.SetBounds(LabelW,ScaleValue(40),Max(0,Half-LabelW-Gap),ScaleValue(30));
  FMaxLabel.SetBounds(Half,ScaleValue(46),LabelW,ScaleValue(26));
  FMaximum.SetBounds(Half+LabelW,ScaleValue(40),Max(0,W-Half-LabelW-Gap),ScaleValue(30));
  FGrid.Height := Min(ScaleValue(300),Max(ScaleValue(160),Round((FChartColumn.ClientHeight-FOptions.Height)*0.45)));
  FGrid.ColWidths[0] := Max(ScaleValue(100),Round(W*0.65)-ScaleValue(12));
  FGrid.ColWidths[1] := Max(ScaleValue(70),W-FGrid.ColWidths[0]-ScaleValue(24));
  FChartColumn.DisableAlign;
  try FOptions.Top := 0; FGrid.Top := FOptions.Height;
  finally FChartColumn.EnableAlign; end;
end;
procedure TRigmScriptSummaryFrame.Resize;
begin inherited; LayoutColumns; end;

function TRigmScriptSummaryFrame.Draft: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('text',FText.Text); Result.AddPair('subtitle',FSubtitle.Text); Result.AddPair('reading',FReading.Text); AddN(Result,'role',JI(JO(JO(FWorkspace.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'role'));
  var Kind := 'radar'; if FKind.ItemIndex=1 then Kind := 'bar'; Result.AddPair('kind',Kind); Result.AddPair('title',FTitle.Text); Result.AddPair('minimum',FMinimum.Text); Result.AddPair('maximum',FMaximum.Text);
  var A := TJSONArray.Create; Result.AddPair('items',A); for var I := 1 to FGrid.RowCount-1 do begin var O := TJSONObject.Create; A.AddElement(O); O.AddPair('label',FGrid.Cells[0,I]); O.AddPair('value',FGrid.Cells[1,I]); end;
end;
procedure TRigmScriptSummaryFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit; var D := Draft;
  try try FWorkspace.SetScriptSummaryDraft(D); except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end;
end;
procedure TRigmScriptSummaryFrame.GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
begin
  if FSync or (ACol<>1) or (ARow<1) then Exit;
  // TStringGridは通知前にCellsへ反映済み。書き戻すと編集中エディタが更新される。
  Changed(Sender);
end;
procedure TRigmScriptSummaryFrame.Edit(Sender: TObject);
begin FEditing := True; FWorkspace.BeginScriptTextEdit; RefreshState; FText.SetFocus; end;
function TRigmScriptSummaryFrame.RequestFinish: Boolean;
begin
  var D := Draft;
  if not FEditing and (D.ToJSON=JO(JO(FWorkspace.ScriptDraft.ScriptWizard,'summaryData'),'draft').ToJSON) then begin D.Free; Exit(True); end;
  Result := False; try try FWorkspace.SetScriptSummaryDraft(D); Result := True; except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end;
  if Result then begin FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState; end;
end;
procedure TRigmScriptSummaryFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptSummaryFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Done(Self); Key := 0; end; end;
procedure TRigmScriptSummaryFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or not(P.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit; var D := ScriptSummaryFixedDraft(JO(JO(P.ScriptWizard,'summaryData'),'draft')); FSync := True;
  try
    if not FEditing or (FLoaded<>P.Id) then begin
      FText.Text := JS(D,'text'); FSubtitle.Text := JS(D,'subtitle'); FReading.Text := JS(D,'reading'); FTitle.Text := JS(D,'title'); FMinimum.Text := JS(D,'minimum'); FMaximum.Text := JS(D,'maximum'); FKind.ItemIndex := 0; if JS(D,'kind')='bar' then FKind.ItemIndex := 1;
      FGrid.RowCount := JA(D,'items').Count+1; for var I := 0 to JA(D,'items').Count-1 do begin var O := TJSONObject(JA(D,'items')[I]); FGrid.Cells[0,I+1] := JS(O,'label'); FGrid.Cells[1,I+1] := JS(O,'value'); end; FLoaded := P.Id;
    end;
    FText.ReadOnly := False; FSubtitle.ReadOnly := False; FReading.ReadOnly := False;
    var Guide := '総評のセリフと、右の固定5項目の点数（初期範囲0～5）を入力してください。字幕・読み・チャート題名は任意です。左の「締め設定」を選ぶと検査・保存して進みます。';
    var Reason := ScriptSummaryDraftReason(D);
    if Reason<>'' then Guide := Guide+#13#10+Reason;
    if FGuide.Caption<>Guide then FGuide.Caption := Guide;
    FPreview.Invalidate;
  finally D.Free; FSync := False; end;
end;
end.
