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
    FRole,FKind: TComboBox; FGrid: TStringGrid; FGuide: TLabel; FPreview: TRigmSummaryChartPreview;
    function Draft: System.JSON.TJSONObject;
    procedure Changed(Sender: TObject);
    procedure GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
    procedure Edit(Sender: TObject);
    procedure Done(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure AddAxis(Sender: TObject);
    procedure RemoveAxis(Sender: TObject);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
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
  function Memo(const Name,Caption: string; Top,Height: Integer): TRigmScriptMemo;
  begin var Panel := TPanel.Create(Self); Panel.Parent := FGrid.Parent; Panel.Align := alTop; Panel.Top := ScaleValue(Top); Panel.Height := ScaleValue(Height); Panel.Caption := ''; Panel.BevelOuter := bvNone;
    var L := TRigmScriptLabel.Create(Self); L.Parent := Panel; L.Align := alTop; L.Caption := Caption; L.Font.Height := -ScaleValue(18);
    Result := TRigmScriptMemo.Create(Self); Result.Parent := Panel; Result.Align := alClient; Result.Name := Name; Result.MaxLength := 2000; Result.Font.Height := -ScaleValue(22); Result.ScrollBars := ssVertical; Result.OnChange := Changed; Result.OnKeyDown := Key;
  end;
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  var Tools := TRigmIconToolbar.Create(Self); Tools.Parent := Self; Tools.Align := alTop; Tools.Name := 'ScriptSummaryToolbar';
  Tools.AddIcon('ScriptSummaryEdit','Enter：総評の入力',riEditPreview,0,Edit); Tools.AddIcon('ScriptSummaryDone','入力完了（Ctrl+Enter / Esc）。途中の数値も保存',riComplete,0,Done); Tools.AddIcon('ScriptSummaryReady','人間の総評と値の確認完了',riComplete,0,Ready);
  Tools.AddSeparator; Tools.AddIcon('ScriptSummaryAddAxis','評価要素を追加（最大8）',riGroup,0,AddAxis); Tools.AddIcon('ScriptSummaryRemoveAxis','最後の評価要素を外す（最低3）',riDelete,0,RemoveAxis);
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := ScaleValue(52); FGuide.Font.Height := -ScaleValue(18); FGuide.Name := 'ScriptSummaryGuide';
  var Left := TPanel.Create(Self); Left.Parent := Self; Left.Align := alLeft; Left.Width := ScaleValue(540); Left.Caption := ''; Left.BevelOuter := bvNone; Left.Padding.SetBounds(ScaleValue(6),ScaleValue(4),ScaleValue(8),ScaleValue(4));
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Left; FGrid.Align := alClient; FGrid.Name := 'ScriptSummaryAxes'; FGrid.ColCount := 2; FGrid.RowCount := 4; FGrid.FixedCols := 0; FGrid.FixedRows := 1; FGrid.DefaultRowHeight := ScaleValue(34); FGrid.ColWidths[0] := ScaleValue(340); FGrid.ColWidths[1] := ScaleValue(160); FGrid.Font.Height := -ScaleValue(22); FGrid.Options := FGrid.Options+[goEditing]; FGrid.Cells[0,0] := '評価要素'; FGrid.Cells[1,0] := '今回の値'; FGrid.OnSetEditText := GridEdit; FGrid.OnKeyDown := Key;
  FText := Memo('ScriptSummaryText','人間の総評（音声用。2000文字以内）',0,112);
  FSubtitle := Memo('ScriptSummarySubtitle','表示字幕（音声とは独立。空なら表示なし）',112,88);
  FSubtitle.MaxLength := 3000;
  FReading := Memo('ScriptSummaryReading','読み（空なら上の音声文を使用）',200,88);
  var Options := TPanel.Create(Self); Options.Parent := Left; Options.Align := alTop; Options.Top := ScaleValue(288); Options.Height := ScaleValue(110); Options.Caption := ''; Options.BevelOuter := bvNone;
  FRole := TComboBox.Create(Self); FRole.Parent := Options; FRole.SetBounds(0,0,ScaleValue(300),ScaleValue(36)); FRole.Style := csDropDownList; FRole.Name := 'ScriptSummaryRole'; FRole.OnChange := Changed;
  FKind := TComboBox.Create(Self); FKind.Parent := Options; FKind.SetBounds(ScaleValue(308),0,ScaleValue(190),ScaleValue(36)); FKind.Style := csDropDownList; FKind.Items.Add('レーダー'); FKind.Items.Add('棒'); FKind.Name := 'ScriptSummaryKind'; FKind.OnChange := Changed;
  FTitle := TEdit.Create(Self); FTitle.Parent := Options; FTitle.SetBounds(0,ScaleValue(40),ScaleValue(498),ScaleValue(30)); FTitle.MaxLength := 120; FTitle.TextHint := 'チャート題名'; FTitle.Name := 'ScriptSummaryTitle'; FTitle.OnChange := Changed;
  var LabelMin := TRigmScriptLabel.Create(Self); LabelMin.Parent := Options; LabelMin.SetBounds(0,ScaleValue(78),ScaleValue(90),ScaleValue(28)); LabelMin.Caption := '最小値';
  FMinimum := TEdit.Create(Self); FMinimum.Parent := Options; FMinimum.SetBounds(ScaleValue(90),ScaleValue(76),ScaleValue(135),ScaleValue(30)); FMinimum.MaxLength := 32; FMinimum.Name := 'ScriptSummaryMinimum'; FMinimum.OnChange := Changed;
  var LabelMax := TRigmScriptLabel.Create(Self); LabelMax.Parent := Options; LabelMax.SetBounds(ScaleValue(254),ScaleValue(78),ScaleValue(90),ScaleValue(28)); LabelMax.Caption := '最大値';
  FMaximum := TEdit.Create(Self); FMaximum.Parent := Options; FMaximum.SetBounds(ScaleValue(348),ScaleValue(76),ScaleValue(150),ScaleValue(30)); FMaximum.MaxLength := 32; FMaximum.Name := 'ScriptSummaryMaximum'; FMaximum.OnChange := Changed;
  FPreview := TRigmSummaryChartPreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Self; FPreview.Align := alClient; FPreview.Name := 'ScriptSummaryPreview';
end;
function TRigmScriptSummaryFrame.Draft: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('text',FText.Text); Result.AddPair('subtitle',FSubtitle.Text); Result.AddPair('reading',FReading.Text); var Number := 0; if FRole.ItemIndex>=0 then Number := NativeInt(FRole.Items.Objects[FRole.ItemIndex]); AddN(Result,'role',Number);
  var Kind := 'radar'; if FKind.ItemIndex=1 then Kind := 'bar'; Result.AddPair('kind',Kind); Result.AddPair('title',FTitle.Text); Result.AddPair('minimum',FMinimum.Text); Result.AddPair('maximum',FMaximum.Text);
  var A := TJSONArray.Create; Result.AddPair('items',A); for var I := 1 to FGrid.RowCount-1 do begin var O := TJSONObject.Create; A.AddElement(O); O.AddPair('label',FGrid.Cells[0,I]); O.AddPair('value',FGrid.Cells[1,I]); end;
end;
procedure TRigmScriptSummaryFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit; var D := Draft;
  try try FWorkspace.SetScriptSummaryDraft(D); except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end;
end;
procedure TRigmScriptSummaryFrame.GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
begin if FSync then Exit; FSync := True; try FGrid.Cells[ACol,ARow] := Value; finally FSync := False; end; Changed(Sender); end;
procedure TRigmScriptSummaryFrame.Edit(Sender: TObject);
begin FEditing := True; FWorkspace.BeginScriptTextEdit; RefreshState; FText.SetFocus; end;
function TRigmScriptSummaryFrame.RequestFinish: Boolean;
begin
  if not FEditing then Exit(True); // 表示だけのmemoを再反映して人間/パイプの確認済みdraftを変えない。
  Result := False; var D := Draft; try try FWorkspace.SetScriptSummaryDraft(D); Result := True; except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end;
  if Result then begin FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState; end;
end;
procedure TRigmScriptSummaryFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptSummaryFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteScriptSummary; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptSummaryFrame.AddAxis(Sender: TObject);
begin if FGrid.RowCount>=9 then Exit; FGrid.RowCount := FGrid.RowCount+1; Changed(Sender); end;
procedure TRigmScriptSummaryFrame.RemoveAxis(Sender: TObject);
begin if FGrid.RowCount<=4 then Exit; FGrid.RowCount := FGrid.RowCount-1; Changed(Sender); end;
procedure TRigmScriptSummaryFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Done(Self); Key := 0; end else if (Key=VK_RETURN) and not FEditing then begin Edit(Self); Key := 0; end; end;
procedure TRigmScriptSummaryFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or not(P.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit; var D := JO(JO(P.ScriptWizard,'summaryData'),'draft'); FSync := True;
  try
    if not FEditing or (FLoaded<>P.Id) then begin
      FText.Text := JS(D,'text'); FSubtitle.Text := JS(D,'subtitle'); FReading.Text := JS(D,'reading'); FTitle.Text := JS(D,'title'); FMinimum.Text := JS(D,'minimum'); FMaximum.Text := JS(D,'maximum'); FKind.ItemIndex := 0; if JS(D,'kind')='bar' then FKind.ItemIndex := 1;
      FRole.Items.Clear; for var N := 1 to 9 do begin var Role := CastingRole(P,N); if Role<>nil then FRole.Items.AddObject(N.ToString+' / '+JS(Role,'name'),TObject(NativeInt(N))); end; FRole.ItemIndex := -1; for var I := 0 to FRole.Items.Count-1 do if NativeInt(FRole.Items.Objects[I])=JI(D,'role') then FRole.ItemIndex := I;
      FGrid.RowCount := JA(D,'items').Count+1; for var I := 0 to JA(D,'items').Count-1 do begin var O := TJSONObject(JA(D,'items')[I]); FGrid.Cells[0,I+1] := JS(O,'label'); FGrid.Cells[1,I+1] := JS(O,'value'); end; FLoaded := P.Id;
    end;
    FText.ReadOnly := not FEditing; FSubtitle.ReadOnly := not FEditing; FReading.ReadOnly := not FEditing;
    FGuide.Caption := '人間の評価値を入力し確認完了。左の工程リストで総評の追加音声だけをVOICEVOX工程へ。'; FPreview.Invalidate;
  finally FSync := False; end;
end;
end.
