unit RigmScriptClosingFrame;
interface
uses System.Classes, RigmScriptPageFrame, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids,
  RigmWizardWorkspace, RigmScriptTextFrame;
type
  TRigmScriptClosingPreview = class(TCustomControl)
  private FWorkspace: TRigmWizardWorkspace; FMode: TComboBox;
  protected procedure Paint; override;
  public constructor CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace; Mode: TComboBox);
  end;
  TRigmScriptClosingFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing: Boolean;
    FTitle,FEndSeconds,FThumbSeconds: TEdit; FChoice: array[0..2] of TComboBox; FPaths: array[0..2] of TLabel;
    FSpeech: TMemo; FGrid: TStringGrid; FMode: TComboBox; FGuide: TLabel; FPreview: TRigmScriptClosingPreview;
    function Draft: TJSONObject;
    procedure Changed(Sender: TObject);
    procedure GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
    procedure Adopt(Sender: TObject);
    procedure Done(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure AddReserved(Sender: TObject);
    procedure RemoveReserved(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace);
    procedure RefreshState;
    function RequestFinish: Boolean;
  end;
implementation
uses System.Generics.Collections, System.SysUtils, System.Math, System.Types, Vcl.Graphics, Vcl.Dialogs, Vcl.ComCtrls, Winapi.Windows,
  RigmJson, PsdJson, RigmIconToolbar, RigmToolbarIcons, RigmScriptClosingModel, RigmMovieCompositor, RigmMovieEndCards, RigmScriptScenesModel;
{$R *.dfm}
const ImageKeys: array[0..2] of string = ('representative','endImage','thumbnailImage');
const ChoiceKeys: array[0..2] of string = ('representativeChoice','endChoice','thumbnailChoice');
const ImageCaptions: array[0..2] of string = ('代表画像','終了画像','サムネイル');
const AdoptHints: array[0..2] of string = ('締めの代表画像を採用','終了画像を採用','サムネイルを採用');
constructor TRigmScriptClosingPreview.CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace; Mode: TComboBox);
begin inherited Create(AOwner); FWorkspace := W; FMode := Mode; DoubleBuffered := True; end;
procedure TRigmScriptClosingPreview.Paint;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect);
  try var P := FWorkspace.ScriptDraft.Clone;
    try MaterializeScriptClosing(P); P.EnableComposition; var Time := ScriptSceneStart(P,ScriptClosingScene(P))+0.1;
      if FMode.ItemIndex>0 then begin var Kind := 'end'; if FMode.ItemIndex=2 then Kind := 'thumbnail'; var Found := False; Time := P.StoryDuration;
        for var V in P.EndCards do begin var Card := TJSONObject(V); if JS(Card,'kind')=Kind then begin Time := Time+0.1; Found := True; Break; end; Time := Time+JN(Card,'duration'); end;
        if not Found then raise Exception.Create('この画像は省略されています。');
      end;
      var B := RenderComposition(P,Time,nil); try var K := Min(ClientWidth/B.Width,ClientHeight/B.Height); var W := Round(B.Width*K); var H := Round(B.Height*K); var R := Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2); Canvas.StretchDraw(R,B);
        if FMode.ItemIndex=1 then begin Canvas.Brush.Style := bsClear; Canvas.Pen.Color := clYellow; Canvas.Pen.Style := psDash; var D := JO(JO(P.ScriptWizard,'closingData'),'draft');
          for var V in JA(D,'reserved') do begin var O := TJSONObject.Create; try for var Key in ['x','y','width','height'] do AddN(O,Key,StrToFloat(JS(TJSONObject(V),Key),TFormatSettings.Invariant)); var Box := CardRect(O,W,H); OffsetRect(Box,R.Left,R.Top); Canvas.Rectangle(Box); finally O.Free; end; end; Canvas.Pen.Style := psSolid; Canvas.Brush.Style := bsSolid;
        end;
      finally B.Free; end;
    finally P.Free; end;
  except on E: Exception do begin Canvas.Font.Color := clSilver; Canvas.Font.Height := -20; var R := ClientRect; InflateRect(R,-16,-16); DrawText(Canvas.Handle,PChar(E.Message),-1,R,DT_LEFT or DT_WORDBREAK); end; end;
end;
constructor TRigmScriptClosingFrame.CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := W;
  var Tools := TRigmIconToolbar.Create(Self); Tools.Parent := Self; Tools.Align := alTop; Tools.Name := 'ScriptClosingToolbar';
  for var I := 0 to 2 do Tools.AddIcon('ScriptClosingAdopt'+I.ToString,AdoptHints[I],riOpen,I,Adopt);
  Tools.AddSeparator; Tools.AddIcon('ScriptClosingDone','途中設定の入力完了',riSave,0,Done); Tools.AddIcon('ScriptClosingReady','画像・表示順・YouTubeの実テンプレートと回避領域を確認完了',riComplete,0,Ready);
  Tools.AddIcon('ScriptClosingAddReserved','YouTube回避領域を追加（最大6）',riGroup,0,AddReserved); Tools.AddIcon('ScriptClosingRemoveReserved','最後の回避領域を外す（最低1）',riDelete,0,RemoveReserved);
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.Height := ScaleValue(70); FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Font.Height := -ScaleValue(17); FGuide.Name := 'ScriptClosingGuide';
  var Left := TPanel.Create(Self); Left.Parent := Self; Left.Align := alLeft; Left.Width := ScaleValue(490); Left.Caption := ''; Left.BevelOuter := bvNone;
  var Options := TPanel.Create(Self); Options.Parent := Left; Options.Align := alTop; Options.Height := ScaleValue(234); Options.Caption := ''; Options.BevelOuter := bvNone;
  FTitle := TEdit.Create(Self); FTitle.Parent := Options; FTitle.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(470),ScaleValue(32)); FTitle.Name := 'ScriptClosingTitle'; FTitle.MaxLength := 128; FTitle.TextHint := '締めに表示する動画題名'; FTitle.OnChange := Changed;
  for var I := 0 to 2 do begin FChoice[I] := TComboBox.Create(Self); FChoice[I].Parent := Options; FChoice[I].SetBounds(ScaleValue(8),ScaleValue(46+I*46),ScaleValue(186),ScaleValue(30)); FChoice[I].Style := csDropDownList; FChoice[I].Items.Add('画像を省略'); FChoice[I].Items.Add('既存画像を採用'); FChoice[I].Name := 'ScriptClosingChoice'+I.ToString; FChoice[I].OnChange := Changed;
    FPaths[I] := TRigmScriptLabel.Create(Self); FPaths[I].Parent := Options; FPaths[I].SetBounds(ScaleValue(200),ScaleValue(46+I*46),ScaleValue(280),ScaleValue(42)); FPaths[I].AutoSize := False; FPaths[I].WordWrap := True; FPaths[I].Name := 'ScriptClosingPath'+I.ToString;
  end;
  var L := TRigmScriptLabel.Create(Self); L.Parent := Options; L.SetBounds(ScaleValue(8),ScaleValue(198),ScaleValue(170),ScaleValue(24)); L.Caption := '終了／最後 秒';
  FEndSeconds := TEdit.Create(Self); FEndSeconds.Parent := Options; FEndSeconds.SetBounds(ScaleValue(184),ScaleValue(192),ScaleValue(130),ScaleValue(32)); FEndSeconds.Name := 'ScriptClosingEndSeconds'; FEndSeconds.MaxLength := 32; FEndSeconds.OnChange := Changed;
  FThumbSeconds := TEdit.Create(Self); FThumbSeconds.Parent := Options; FThumbSeconds.SetBounds(ScaleValue(324),ScaleValue(192),ScaleValue(148),ScaleValue(32)); FThumbSeconds.Name := 'ScriptClosingThumbnailSeconds'; FThumbSeconds.MaxLength := 32; FThumbSeconds.OnChange := Changed;
  FSpeech := TMemo.Create(Self); FSpeech.Parent := Left; FSpeech.Align := alBottom; FSpeech.Height := ScaleValue(70); FSpeech.ReadOnly := True; FSpeech.ScrollBars := ssVertical; FSpeech.Name := 'ScriptClosingSpeech';
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Left; FGrid.Align := alClient; FGrid.Name := 'ScriptClosingRects'; FGrid.ColCount := 5; FGrid.RowCount := 5; FGrid.FixedCols := 1; FGrid.FixedRows := 1; FGrid.DefaultRowHeight := ScaleValue(36); FGrid.ColWidths[0] := ScaleValue(90); for var I := 1 to 4 do FGrid.ColWidths[I] := ScaleValue(92); FGrid.Options := FGrid.Options+[goEditing]; FGrid.Cells[0,0] := '領域'; FGrid.Cells[1,0] := 'X'; FGrid.Cells[2,0] := 'Y'; FGrid.Cells[3,0] := '幅'; FGrid.Cells[4,0] := '高さ'; FGrid.OnSetEditText := GridEdit;
  var Right := TPanel.Create(Self); Right.Parent := Self; Right.Align := alClient; Right.Caption := ''; Right.BevelOuter := bvNone;
  FMode := TComboBox.Create(Self); FMode.Parent := Right; FMode.Align := alTop; FMode.Style := csDropDownList; FMode.Items.AddStrings(['締め（音声・題名・代表画像）','終了画像（点線は回避領域。書き出しに含めない）','最後のサムネイル']); FMode.ItemIndex := 0; FMode.Name := 'ScriptClosingPreviewMode'; FMode.OnChange := ModeChanged;
  FPreview := TRigmScriptClosingPreview.CreateForWorkspace(Self,W,FMode); FPreview.Parent := Right; FPreview.Align := alClient; FPreview.Name := 'ScriptClosingPreview';
end;
function TRigmScriptClosingFrame.Draft: TJSONObject;
  function Row(Index: Integer): TJSONObject;
  begin Result := TJSONObject.Create; var Col := 1; for var Key in ['x','y','width','height'] do begin Result.AddPair(Key,FGrid.Cells[Col,Index]); Inc(Col); end; end;
begin
  Result := JO(JO(FWorkspace.ScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject; PsdJson.Put(Result,'title',FTitle.Text); PsdJson.Put(Result,'endSeconds',FEndSeconds.Text); PsdJson.Put(Result,'thumbnailSeconds',FThumbSeconds.Text);
  for var I := 0 to 2 do begin var Choice := ''; if FChoice[I].ItemIndex=0 then Choice := 'none' else if FChoice[I].ItemIndex=1 then Choice := 'use'; PsdJson.Put(Result,ChoiceKeys[I],Choice); end;
  PsdJson.Put(Result,'rect',Row(1)); var A := TJSONArray.Create; for var I := 2 to FGrid.RowCount-1 do A.AddElement(Row(I)); PsdJson.Put(Result,'reserved',A);
end;
procedure TRigmScriptClosingFrame.Changed(Sender: TObject);
begin if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit; var D := Draft; try try FWorkspace.SetScriptClosingDraft(D); except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end; end;
procedure TRigmScriptClosingFrame.GridEdit(Sender: TObject; ACol,ARow: Integer; const Value: string);
begin if FSync then Exit; FSync := True; try FGrid.Cells[ACol,ARow] := Value; finally FSync := False; end; Changed(Sender); end;
function TRigmScriptClosingFrame.RequestFinish: Boolean;
begin if not FEditing then Exit(True); Result := False; var D := Draft; try try FWorkspace.SetScriptClosingDraft(D); Result := True; except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end; if Result then begin FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState; end; end;
procedure TRigmScriptClosingFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptClosingFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteScriptClosing; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptClosingFrame.Adopt(Sender: TObject);
begin if not RequestFinish then Exit; var Dialog := TOpenDialog.Create(Self); try Dialog.Filter := '既存画像|*.png;*.jpg;*.jpeg;*.bmp'; if Dialog.Execute then try FWorkspace.AdoptScriptClosingImage(ImageKeys[TToolButton(Sender).Tag],Dialog.FileName); except on E: Exception do FGuide.Caption := E.Message; end; finally Dialog.Free; end; end;
procedure TRigmScriptClosingFrame.AddReserved(Sender: TObject);
begin if FGrid.RowCount>=8 then Exit; FGrid.RowCount := FGrid.RowCount+1; for var I := 1 to 4 do FGrid.Cells[I,FGrid.RowCount-1] := ''; Changed(Sender); end;
procedure TRigmScriptClosingFrame.RemoveReserved(Sender: TObject);
begin if FGrid.RowCount<=3 then Exit; FGrid.RowCount := FGrid.RowCount-1; Changed(Sender); end;
procedure TRigmScriptClosingFrame.ModeChanged(Sender: TObject);
begin FPreview.Invalidate; end;
procedure TRigmScriptClosingFrame.RefreshState;
begin
  if (FWorkspace.ScriptDraft=nil) or not(FWorkspace.ScriptDraft.ScriptWizard.GetValue('closingData') is TJSONObject) then Exit; var P := FWorkspace.ScriptDraft; var D := JO(JO(P.ScriptWizard,'closingData'),'draft'); FSync := True;
  try if not FEditing then begin
    FTitle.Text := JS(D,'title'); FEndSeconds.Text := JS(D,'endSeconds'); FThumbSeconds.Text := JS(D,'thumbnailSeconds');
    for var I := 0 to 2 do begin FChoice[I].ItemIndex := -1; if JS(D,ChoiceKeys[I])='none' then FChoice[I].ItemIndex := 0 else if JS(D,ChoiceKeys[I])='use' then FChoice[I].ItemIndex := 1; var Path := JS(D,ImageKeys[I]); FPaths[I].Caption := ImageCaptions[I]+'：未採用'; if Path<>'' then FPaths[I].Caption := ImageCaptions[I]+'：'+ExtractFileName(Path); FPaths[I].Hint := Path; FPaths[I].ShowHint := True; end;
    FGrid.RowCount := JA(D,'reserved').Count+2; for var Row := 1 to FGrid.RowCount-1 do begin var O := JO(D,'rect'); if Row>1 then O := TJSONObject(JA(D,'reserved')[Row-2]); FGrid.Cells[0,Row] := '画像'; if Row>1 then FGrid.Cells[0,Row] := '回避'+(Row-1).ToString; var Col := 1; for var Key in ['x','y','width','height'] do begin FGrid.Cells[Col,Row] := JS(O,Key); Inc(Col); end; end;
    FSpeech.Clear; for var V in JA(JO(P.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='closing' then FSpeech.Lines.Add(P.Cue(JS(TJSONObject(V),'cueId')).Text); FSpeech.SelStart := 0; FSpeech.Perform(183,0,0);
  end;
  FGuide.Caption := '座標は画面割合0～1。回避領域は仮配置です。YouTubeで使う実テンプレートに合わせ確認してください。クリック要素は作りません。締めセリフの変更は台本入力へ。左の工程リストで完成内容を保存して動画編集へ。'; FPreview.Invalidate;
  finally FSync := False; end;
end;
end.
