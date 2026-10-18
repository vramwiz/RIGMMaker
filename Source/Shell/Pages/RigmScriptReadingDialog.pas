unit RigmScriptReadingDialog;

interface
uses System.Classes, RigmWizardWorkspace;
procedure ShowScriptReadingCheck(Owner: TComponent; Workspace: TRigmWizardWorkspace);
implementation
uses System.SysUtils, System.JSON, Winapi.Windows, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, RigmMovieModel, RigmJson,
  RigmScriptReadingModel, RigmScriptVoiceModel;
type
  TScriptReadingDialog = class(TForm)
  private
    FWorkspace: TRigmWizardWorkspace; FSnapshot: TRigmMovieProject;
    FDictionary: TMemo; FRows: TListView; FState: TLabel; FApply: TButton;
    FColumns: array[0..2] of TPanel; FDetails: array[0..2] of TMemo;
    FEntries, FCandidates: TJSONArray;
    procedure DictionaryChanged(Sender: TObject);
    procedure Rebuild(Sender: TObject);
    procedure SelectRow(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ResizeDetails(Sender: TObject);
    procedure Apply(Sender: TObject);
  public
    constructor CreateForWorkspace(Owner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
  end;

constructor TScriptReadingDialog.CreateForWorkspace(Owner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited CreateNew(Owner); FWorkspace := Workspace; FSnapshot := Workspace.ScriptDraft.Clone;
  Caption := '字幕を保持して読みを確認'; Name := 'ScriptReadingCheckDialog';
  Position := poMainFormCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 11;
  Width := MulDiv(1100,Screen.PixelsPerInch,96); Height := MulDiv(720,Screen.PixelsPerInch,96);
  Constraints.MinWidth := MulDiv(760,Screen.PixelsPerInch,96); Constraints.MinHeight := MulDiv(520,Screen.PixelsPerInch,96);
  var Guide := TLabel.Create(Self); Guide.Parent := Self; Guide.Align := alTop; Guide.AutoSize := False;
  Guide.Height := MulDiv(54,Screen.PixelsPerInch,96); Guide.WordWrap := True;
  Guide.Caption := '字幕は変更しません。辞書に該当する語だけを現在の読みから補正します。反映する行にチェックを入れてください。'+#13#10+
    '適用した行の音声・アクセント・再生確認はやり直します。変更しない行の調整は保持します。';
  var Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := MulDiv(76,Screen.PixelsPerInch,96); Footer.BevelOuter := bvNone;
  FState := TLabel.Create(Self); FState.Parent := Footer; FState.Align := alTop; FState.AutoSize := False;
  FState.Height := MulDiv(36,Screen.PixelsPerInch,96); FState.WordWrap := True;
  var Cancel := TButton.Create(Self); Cancel.Parent := Footer; Cancel.Align := alRight; Cancel.Width := MulDiv(100,Screen.PixelsPerInch,96);
  Cancel.Caption := '取消'; Cancel.Cancel := True; Cancel.ModalResult := mrCancel;
  FApply := TButton.Create(Self); FApply.Parent := Footer; FApply.Align := alRight; FApply.Width := MulDiv(300,Screen.PixelsPerInch,96);
  FApply.Caption := '辞書を保存・チェックした読みを適用'; FApply.Name := 'ScriptReadingApply'; FApply.OnClick := Apply;
  var Left := TPanel.Create(Self); Left.Parent := Self; Left.Align := alLeft; Left.Width := MulDiv(260,Screen.PixelsPerInch,96); Left.BevelOuter := bvNone;
  var LabelText := TLabel.Create(Self); LabelText.Parent := Left; LabelText.Align := alTop; LabelText.AutoSize := False;
  LabelText.Height := MulDiv(54,Screen.PixelsPerInch,96); LabelText.WordWrap := True;
  LabelText.Caption := '作品の読み辞書（1行に 表記＝読み）'+#13#10+'読みはひらがな・カタカナ。削除も可能。';
  var Update := TButton.Create(Self); Update.Parent := Left; Update.Align := alBottom; Update.Caption := '辞書から候補を更新';
  Update.Height := MulDiv(36,Screen.PixelsPerInch,96); Update.OnClick := Rebuild; Update.Name := 'ScriptReadingRebuild';
  FDictionary := TMemo.Create(Self); FDictionary.Parent := Left; FDictionary.Align := alClient;
  FDictionary.ScrollBars := ssBoth; FDictionary.WordWrap := False; FDictionary.Name := 'ScriptReadingDictionary'; FDictionary.MaxLength := 100000;
  var Entries := ScriptReadingDictionary(FSnapshot);
  try for var V in Entries do FDictionary.Lines.Add(JS(TJSONObject(V),'word')+'＝'+JS(TJSONObject(V),'reading'));
  finally Entries.Free; end;
  FDictionary.OnChange := DictionaryChanged;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Right := TPanel.Create(Self); Right.Parent := Self; Right.Align := alClient; Right.BevelOuter := bvNone;
  FRows := TListView.Create(Self); FRows.Parent := Right; FRows.Align := alTop; FRows.Height := MulDiv(220,Screen.PixelsPerInch,96);
  FRows.ViewStyle := vsReport; FRows.ReadOnly := True; FRows.RowSelect := True; FRows.HideSelection := False; FRows.Checkboxes := True;
  FRows.Name := 'ScriptReadingCandidates'; FRows.OnSelectItem := SelectRow;
  FRows.Columns.Add.Caption := 'セリフ'; FRows.Columns[0].Width := MulDiv(76,Screen.PixelsPerInch,96);
  FRows.Columns.Add.Caption := '字幕（変更なし）'; FRows.Columns[1].Width := MulDiv(300,Screen.PixelsPerInch,96);
  FRows.Columns.Add.Caption := '補正後の読み'; FRows.Columns[2].Width := MulDiv(340,Screen.PixelsPerInch,96);
  var Details := TPanel.Create(Self); Details.Parent := Right; Details.Align := alClient; Details.BevelOuter := bvNone;
  Details.OnResize := ResizeDetails;
  for var I := 0 to 2 do begin
    FColumns[I] := TPanel.Create(Self); FColumns[I].Parent := Details; FColumns[I].BevelOuter := bvNone;
    FColumns[I].Left := I*300; FColumns[I].Width := 300;
    if I<2 then FColumns[I].Align := alLeft else FColumns[I].Align := alClient;
    var DetailLabel := TLabel.Create(Self); DetailLabel.Parent := FColumns[I]; DetailLabel.Align := alTop;
    case I of 0: DetailLabel.Caption := '字幕（変更しません）'; 1: DetailLabel.Caption := '現在の読み'; 2: DetailLabel.Caption := '補正後の読み'; end;
    FDetails[I] := TMemo.Create(Self); FDetails[I].Parent := FColumns[I]; FDetails[I].Align := alClient;
    FDetails[I].ReadOnly := True; FDetails[I].ScrollBars := ssVertical;
  end;
  ResizeDetails(Details); Rebuild(Self);
end;
destructor TScriptReadingDialog.Destroy;
begin FCandidates.Free; FEntries.Free; FSnapshot.Free; inherited; end;

procedure TScriptReadingDialog.ResizeDetails(Sender: TObject);
begin
  if (FColumns[0]=nil) or (FColumns[1]=nil) then Exit;
  var Width := TWinControl(Sender).ClientWidth div 3;
  FColumns[0].Width := Width; FColumns[1].Width := Width;
end;
procedure TScriptReadingDialog.DictionaryChanged(Sender: TObject);
begin
  FApply.Enabled := False; FRows.Items.Clear;
  for var Memo in FDetails do if Memo<>nil then Memo.Clear;
  FState.Caption := '辞書を変更しました。「辞書から候補を更新」で確認し直してください。';
end;
procedure TScriptReadingDialog.Rebuild(Sender: TObject);
begin
  FApply.Enabled := False; FRows.Items.Clear;
  for var Memo in FDetails do Memo.Clear;
  FreeAndNil(FCandidates); FreeAndNil(FEntries); FEntries := TJSONArray.Create;
  try
    for var Raw in FDictionary.Lines do begin
      var Line := Raw.Trim; if Line='' then Continue;
      var Position := Pos('＝',Line); var Ascii := Pos('=',Line);
      if (Position=0) or ((Ascii>0) and (Ascii<Position)) then Position := Ascii;
      if Position=0 then raise Exception.Create('辞書は1行に「神獣＝しんじゅう」のように入力してください。');
      FEntries.AddElement(TJSONObject.Create.AddPair('word',Line.Substring(0,Position-1).Trim)
        .AddPair('reading',Line.Substring(Position).Trim));
    end;
    FCandidates := ScriptReadingCorrections(FSnapshot,FEntries);
    for var V in FCandidates do begin
      var O := TJSONObject(V); var Item := FRows.Items.Add;
      Item.Caption := JI(O,'number').ToString; Item.SubItems.Add(JS(O,'subtitle'));
      Item.SubItems.Add(JS(O,'after')); Item.Checked := True;
    end;
    FState.Caption := Format('補正候補 %d行。チェックを外した行は変更しません。0行なら辞書だけ保存します。',[FCandidates.Count]);
    FApply.Enabled := True;
    if FRows.Items.Count>0 then FRows.Items[0].Selected := True;
  except on E: Exception do FState.Caption := E.Message; end;
end;
procedure TScriptReadingDialog.SelectRow(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected or (FCandidates=nil) or (Item.Index>=FCandidates.Count) then Exit;
  var O := TJSONObject(FCandidates[Item.Index]); FDetails[0].Text := JS(O,'subtitle');
  FDetails[1].Text := JS(O,'before'); FDetails[2].Text := JS(O,'after');
end;
procedure TScriptReadingDialog.Apply(Sender: TObject);
begin
  if not FApply.Enabled or (FCandidates=nil) then Exit;
  var Selected := TJSONArray.Create;
  try
    for var Item in FRows.Items do if Item.Checked then Selected.AddElement(FCandidates[Item.Index].Clone as TJSONObject);
    try
      FWorkspace.ApplyReadingCorrections(FSnapshot.Id,FSnapshot.Revision,FEntries,Selected);
      ModalResult := mrOk;
    except on E: Exception do FState.Caption := E.Message; end;
  finally Selected.Free; end;
end;
procedure ShowScriptReadingCheck(Owner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  RequireCurrentVoice(Workspace.ScriptDraft);
  if Workspace.VoiceBusy or Workspace.VoiceContinuous then raise Exception.Create('音声の生成・連続再生を終了してから読みを確認してください。');
  Workspace.StopVoice;
  var Dialog := TScriptReadingDialog.CreateForWorkspace(Owner,Workspace);
  try Dialog.ShowModal; finally Dialog.Free; end;
end;
end.
