unit RigmMovieEndingDialog;
interface
uses System.Classes, System.JSON, Vcl.Forms, Vcl.StdCtrls, Vcl.Grids, RigmMovieModel;
type
  TRigmMovieEndingDialog = class(TForm)
  private
    FProject: TRigmMovieProject; FSource: TJSONObject; FTitle,FEndSeconds,FThumbSeconds: TEdit;
    FChoice: array[0..2] of TComboBox; FPath: array[0..2] of TEdit; FGrid: TStringGrid;
    procedure Adopt(Sender: TObject);
  public
    constructor CreateForProject(AOwner: TComponent; Project: TRigmMovieProject);
    destructor Destroy; override;
    function Draft: TJSONObject;
  end;
implementation
uses System.Generics.Collections, System.SysUtils, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, RigmJson, PsdJson, RigmScriptClosingModel;
const ImageKeys: array[0..2] of string = ('representative','endImage','thumbnailImage');
const ChoiceKeys: array[0..2] of string = ('representativeChoice','endChoice','thumbnailChoice');
const Captions: array[0..2] of string = ('代表画像','終了画像','サムネイル');
constructor TRigmMovieEndingDialog.CreateForProject(AOwner: TComponent; Project: TRigmMovieProject);
begin
  inherited CreateNew(AOwner); FProject := Project; PrepareScriptClosing(Project); FSource := JO(JO(Project.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  Caption := '締め画像・終了区間'; Position := poOwnerFormCenter; BorderStyle := bsDialog; ClientWidth := 800; ClientHeight := 690;
  FTitle := TEdit.Create(Self); FTitle.Parent := Self; FTitle.SetBounds(12,12,776,30); FTitle.Text := JS(FSource,'title'); FTitle.MaxLength := 128;
  for var I := 0 to 2 do begin
    var LabelText := TLabel.Create(Self); LabelText.Parent := Self; LabelText.SetBounds(12,54+I*54,90,24); LabelText.Caption := Captions[I];
    FChoice[I] := TComboBox.Create(Self); FChoice[I].Parent := Self; FChoice[I].SetBounds(105,50+I*54,120,30); FChoice[I].Style := csDropDownList; FChoice[I].Items.AddStrings(['省略','採用']); FChoice[I].ItemIndex := 0; if JS(FSource,ChoiceKeys[I])='use' then FChoice[I].ItemIndex := 1;
    FPath[I] := TEdit.Create(Self); FPath[I].Parent := Self; FPath[I].SetBounds(234,50+I*54,470,30); FPath[I].ReadOnly := True; FPath[I].Text := JS(FSource,ImageKeys[I]);
    var Button := TButton.Create(Self); Button.Parent := Self; Button.SetBounds(710,50+I*54,78,30); Button.Caption := '画像…'; Button.Tag := I; Button.OnClick := Adopt;
  end;
  var Guide := TLabel.Create(Self); Guide.Parent := Self; Guide.SetBounds(12,250,776,48); Guide.AutoSize := False; Guide.WordWrap := True; Guide.Font.Height := -18;
  Guide.Caption := 'X・Y・幅・高さは画面割合0～1。回避領域はYouTubeの実テンプレートに合わせて変更してください。点線は出力しません。台詞・字幕・音声は通常欄で編集できます。';
  var SecondsLabel := TLabel.Create(Self); SecondsLabel.Parent := Self; SecondsLabel.SetBounds(12,218,460,30); SecondsLabel.Caption := '終了画像／サムネイル 秒';
  FEndSeconds := TEdit.Create(Self); FEndSeconds.Parent := Self; FEndSeconds.SetBounds(480,210,130,30); FEndSeconds.Text := JS(FSource,'endSeconds');
  FThumbSeconds := TEdit.Create(Self); FThumbSeconds.Parent := Self; FThumbSeconds.SetBounds(640,210,140,30); FThumbSeconds.Text := JS(FSource,'thumbnailSeconds');
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Self; FGrid.SetBounds(12,305,776,305); FGrid.ColCount := 5; FGrid.FixedCols := 1; FGrid.FixedRows := 1; FGrid.RowCount := JA(FSource,'reserved').Count+2; FGrid.DefaultColWidth := 150; FGrid.DefaultRowHeight := 38; FGrid.Options := FGrid.Options+[goEditing];
  FGrid.Cells[0,0] := '領域'; FGrid.Cells[1,0] := 'X'; FGrid.Cells[2,0] := 'Y'; FGrid.Cells[3,0] := '幅'; FGrid.Cells[4,0] := '高さ';
  for var R := 1 to FGrid.RowCount-1 do begin var O := JO(FSource,'rect'); if R>1 then O := TJSONObject(JA(FSource,'reserved')[R-2]); FGrid.Cells[0,R] := '終了画像'; if R>1 then FGrid.Cells[0,R] := '回避'+(R-1).ToString; var C := 1; for var Key in ['x','y','width','height'] do begin FGrid.Cells[C,R] := JS(O,Key); Inc(C); end; end;
  var Ok := TButton.Create(Self); Ok.Parent := Self; Ok.SetBounds(600,638,90,32); Ok.Caption := '適用'; Ok.ModalResult := mrOk; Ok.Default := True;
  var Cancel := TButton.Create(Self); Cancel.Parent := Self; Cancel.SetBounds(700,638,90,32); Cancel.Caption := '戻る'; Cancel.ModalResult := mrCancel; Cancel.Cancel := True;
end;
destructor TRigmMovieEndingDialog.Destroy;
begin FSource.Free; inherited; end;
procedure TRigmMovieEndingDialog.Adopt(Sender: TObject);
begin var I := TButton(Sender).Tag; var D := TOpenDialog.Create(Self); try D.Filter := '既存画像|*.png;*.jpg;*.jpeg;*.bmp'; if D.Execute then begin FPath[I].Text := D.FileName; FChoice[I].ItemIndex := 1; end; finally D.Free; end; end;
function TRigmMovieEndingDialog.Draft: TJSONObject;
  function Row(R: Integer): TJSONObject;
  begin Result := TJSONObject.Create; var C := 1; for var Key in ['x','y','width','height'] do begin Result.AddPair(Key,FGrid.Cells[C,R]); Inc(C); end; end;
begin
  Result := FSource.Clone as TJSONObject; PsdJson.Put(Result,'title',FTitle.Text); PsdJson.Put(Result,'endSeconds',FEndSeconds.Text); PsdJson.Put(Result,'thumbnailSeconds',FThumbSeconds.Text);
  for var I := 0 to 2 do begin var Choice := 'none'; if FChoice[I].ItemIndex=1 then Choice := 'use'; PsdJson.Put(Result,ChoiceKeys[I],Choice); PsdJson.Put(Result,ImageKeys[I],FPath[I].Text); end;
  PsdJson.Put(Result,'rect',Row(1)); var A := TJSONArray.Create; for var R := 2 to FGrid.RowCount-1 do A.AddElement(Row(R)); PsdJson.Put(Result,'reserved',A);
end;
end.
