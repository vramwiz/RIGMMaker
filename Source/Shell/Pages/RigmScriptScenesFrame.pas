unit RigmScriptScenesFrame;
// 固定sceneIdのコンパクトな入力行。要望・修正指示は1欄、確定は画像下のチェック。
interface
uses System.Classes, System.Generics.Collections, RigmScriptPageFrame, Vcl.Forms,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, RigmWizardWorkspace,
  RigmIconToolbar, RigmScriptTextFrame, RigmBufferedControls;
type
  TRigmScriptScenesFrame = class;
  TRigmSceneImageRow = class(TRigmBufferedPanel)
  public
    SceneId,ImageStamp: string;
    Number: TLabel;
    Prompt,Description: TRigmScriptMemo;
    Picture: TImage;
    Approved: TCheckBox;
    Position: TComboBox;
    constructor CreateRow(AOwner: TRigmScriptScenesFrame; const Id: string);
    procedure Arrange(NumberWidth,PromptWidth,DescriptionWidth,ImageWidth: Integer);
  end;
  TRigmScriptScenesFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace;
    FSync,FEditing,FLayout: Boolean;
    FRows: TObjectList<TRigmSceneImageRow>;
    FScroll: TScrollBox;
    FGuide: TLabel;
    FDialogue: TPanel;
    FDialogueCaption: TLabel;
    FDialogueText: TEdit;
    FToolbar: TRigmIconToolbar;
    FHeader: TPanel;
    FHeaders: TArray<TLabel>;
    procedure LayoutRows;
    procedure LayoutChanged(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure FocusRow(Sender: TObject);
    procedure RefreshDialogue;
    procedure Checked(Sender: TObject);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Done(Sender: TObject);
    procedure Adopt(Sender: TObject);
    procedure RequestImage(Sender: TObject);
    procedure CancelImage(Sender: TObject);
    function RowFor(Sender: TObject): TRigmSceneImageRow;
    function SelectedId: string;
  protected
    procedure Resize; override;
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, System.Types, Vcl.Dialogs,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Winapi.Windows, RigmJson, RigmToolbarIcons,
  RigmScriptScenesModel, RigmMovieModel, RigmMovieImageTransfer, RigmScriptTextModel;
{$R *.dfm}
const
  Positions: array[0..4] of string = ('below-image','image-top','image-center','image-bottom','screen-top');
  PositionNames: array[0..4] of string = ('画像の下','画像の上部','画像の中央','画像の下部','画面上部');
constructor TRigmSceneImageRow.CreateRow(AOwner: TRigmScriptScenesFrame; const Id: string);
  function Memo(const Name: string; Limit: Integer): TRigmScriptMemo;
  begin
    Result := TRigmScriptMemo.Create(Self); Result.Parent := Self; Result.Name := Name;
    Result.MaxLength := Limit; Result.ScrollBars := ssVertical;
    Result.OnChange := AOwner.Changed; Result.OnKeyDown := AOwner.Key; Result.OnEnter := AOwner.FocusRow;
  end;
begin
  inherited Create(AOwner); SceneId := Id; Parent := AOwner.FScroll; Align := alNone;
  Height := MulDiv(88,CurrentPPI,96); BevelOuter := bvLowered; Caption := '';
  Number := TRigmScriptLabel.Create(Self); Number.Parent := Self; Number.AutoSize := False;
  Prompt := Memo('SceneImageInstruction',16004); Description := Memo('SceneDescription',3000);
  Position := TComboBox.Create(Self); Position.Parent := Self; Position.Name := 'SceneDescriptionPosition';
  Position.Style := csDropDownList; for var Text in PositionNames do Position.Items.Add(Text);
  Position.ItemIndex := 0; Position.OnChange := AOwner.Changed; Position.OnEnter := AOwner.FocusRow;
  Picture := TImage.Create(Self); Picture.Parent := Self; Picture.Center := True; Picture.Proportional := True; Picture.Stretch := True;
  Approved := TCheckBox.Create(Self); Approved.Parent := Self; Approved.Name := 'SceneApproved';
  Approved.Caption := '確定'; Approved.OnClick := AOwner.Checked; Approved.OnEnter := AOwner.FocusRow;
end;
procedure TRigmSceneImageRow.Arrange(NumberWidth,PromptWidth,DescriptionWidth,ImageWidth: Integer);
begin
  var Gap := MulDiv(4,CurrentPPI,96); var ComboHeight := MulDiv(24,CurrentPPI,96);
  Number.SetBounds(Gap,Gap,NumberWidth-Gap*2,Height-Gap*2);
  Prompt.SetBounds(NumberWidth+Gap,Gap,PromptWidth-Gap*2,Height-Gap*2);
  var X := NumberWidth+PromptWidth+Gap;
  Description.SetBounds(X,Gap,DescriptionWidth-Gap*2,Height-ComboHeight-Gap*3);
  Position.SetBounds(X,Height-ComboHeight-Gap,DescriptionWidth-Gap*2,ComboHeight);
  X := NumberWidth+PromptWidth+DescriptionWidth+Gap;
  Picture.SetBounds(X,Gap,ImageWidth-Gap*2,Height-ComboHeight-Gap*3);
  Approved.SetBounds(X,Height-ComboHeight-Gap,ImageWidth-Gap*2,ComboHeight);
end;
constructor TRigmScriptScenesFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; Align := alClient; FRows := TObjectList<TRigmSceneImageRow>.Create(True);
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptScenesToolbar';
  FToolbar.AddIcon('ScriptSceneDone','要望・補足文の入力を反映（Ctrl+Enter / Esc）。確定チェックとは別です',riSave,0,Done);
  FToolbar.AddIcon('ScriptSceneRequest','未確定シーンの画像要求を準備。要望入力後、Codexへ作業を指示してください',riRefresh,0,RequestImage);
  FToolbar.AddIcon('ScriptSceneAdopt','選択行へ既存ローカル画像をコピーして採用',riOpen,0,Adopt);
  FToolbar.AddIcon('ScriptSceneCancel','選択行の画像要求を取り消す',riDelete,0,CancelImage);
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True;
  FGuide.Height := ScaleValue(32); FGuide.Name := 'ScriptSceneGuide';
  FDialogue := TRigmBufferedPanel.Create(Self); FDialogue.Parent := Self; FDialogue.BevelOuter := bvNone;
  FDialogue.Caption := ''; FDialogue.Height := ScaleValue(32); FDialogue.Align := alBottom;
  FDialogue.Name := 'ScriptSceneDialogue'; FDialogue.Padding.SetBounds(ScaleValue(4),ScaleValue(4),ScaleValue(4),ScaleValue(4));
  FDialogueCaption := TRigmScriptLabel.Create(Self); FDialogueCaption.Parent := FDialogue;
  FDialogueCaption.AutoSize := False; FDialogueCaption.Width := ScaleValue(144); FDialogueCaption.Align := alLeft;
  FDialogueCaption.Layout := tlCenter; FDialogueCaption.Caption := 'シーンのセリフ';
  FDialogueText := TEdit.Create(Self); FDialogueText.Parent := FDialogue; FDialogueText.Align := alClient;
  FDialogueText.Name := 'ScriptSceneDialogueText'; FDialogueText.ReadOnly := True;
  FDialogueText.TabStop := False; FDialogueText.AutoSelect := False;
  FScroll := TScrollBox.Create(Self); FScroll.Parent := Self; FScroll.Align := alClient; FScroll.BorderStyle := bsNone;
  FScroll.VertScrollBar.Tracking := True; FScroll.HorzScrollBar.Tracking := True; FScroll.Name := 'ScriptSceneRows';
  FScroll.OnResize := LayoutChanged;
  FHeader := TRigmBufferedPanel.Create(Self); FHeader.Parent := FScroll; FHeader.BevelOuter := bvNone; FHeader.Caption := '';
  FHeader.ParentBackground := False; FHeader.ParentColor := False; FHeader.Color := clBlack; FHeader.StyleElements := [];
  FHeader.Name := 'ScriptSceneHeader'; SetLength(FHeaders,4);
  var Captions: TArray<string> := ['シーン','画像要望・修正指示（Codexへ）','補足文（動画表示）／配置','要求画像'];
  for var I := 0 to High(FHeaders) do begin
    FHeaders[I] := TLabel.Create(Self); FHeaders[I].Parent := FHeader;
    FHeaders[I].AutoSize := False; FHeaders[I].Caption := Captions[I];
    FHeaders[I].Transparent := False; FHeaders[I].ParentColor := False;
    FHeaders[I].Color := clBlack; FHeaders[I].Font.Color := clWhite; FHeaders[I].StyleElements := [];
  end;
  LayoutRows;
end;
destructor TRigmScriptScenesFrame.Destroy;
begin FRows.Free; inherited; end;
procedure TRigmScriptScenesFrame.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; LayoutRows; end;
procedure TRigmScriptScenesFrame.Resize;
begin inherited; LayoutRows; end;
procedure TRigmScriptScenesFrame.LayoutChanged(Sender: TObject);
begin LayoutRows; end;
procedure TRigmScriptScenesFrame.LayoutRows;
begin
  if FLayout or (FScroll=nil) or (FHeader=nil) or (Length(FHeaders)<>4) then Exit;
  FLayout := True;
  try
  var W := Max(ScaleValue(800),FScroll.ClientWidth);
  var Sizes: TArray<Integer> := [ScaleValue(56),0,0,ScaleValue(180)];
  Sizes[1] := (W-Sizes[0]-Sizes[3]) div 2; Sizes[2] := W-Sizes[0]-Sizes[1]-Sizes[3];
  var H := ScaleValue(88); var HeaderHeight := ScaleValue(28);
  var X := -FScroll.HorzScrollBar.Position; var Y := -FScroll.VertScrollBar.Position;
  FScroll.DisableAlign;
  try
    FHeader.SetBounds(X,Y,W,HeaderHeight); var Left := 0;
    for var I := 0 to High(FHeaders) do begin
      FHeaders[I].SetBounds(Left+ScaleValue(4),ScaleValue(4),Sizes[I]-ScaleValue(8),HeaderHeight-ScaleValue(4));
      Inc(Left,Sizes[I]);
    end;
    for var I := 0 to FRows.Count-1 do begin
      FRows[I].SetBounds(X,Y+HeaderHeight+I*H,W,H); FRows[I].Arrange(Sizes[0],Sizes[1],Sizes[2],Sizes[3]);
    end;
    FScroll.HorzScrollBar.Range := W; FScroll.VertScrollBar.Range := HeaderHeight+FRows.Count*H;
  finally FScroll.EnableAlign; end;
  finally FLayout := False; end;
end;
function TRigmScriptScenesFrame.SelectedId: string;
begin Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'scenes'),'selectedScene'); end;
function TRigmScriptScenesFrame.RowFor(Sender: TObject): TRigmSceneImageRow;
begin
  Result := nil; for var Row in FRows do
    if (Sender=Row.Prompt) or (Sender=Row.Description) or (Sender=Row.Approved) or (Sender=Row.Position) then Exit(Row);
end;
procedure TRigmScriptScenesFrame.FocusRow(Sender: TObject);
begin
  if FSync then Exit; var Row := RowFor(Sender); if Row=nil then Exit;
  try FWorkspace.SelectScriptScene(Row.SceneId); RefreshDialogue; except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptScenesFrame.RefreshDialogue;
begin
  var P := FWorkspace.ScriptDraft; var S := P.Scene(SelectedId);
  var Text := TStringBuilder.Create;
  try
    if S<>nil then for var C in P.Cues do if C.Scene=S.Id then begin
      if Text.Length>0 then Text.Append(' ');
      Text.Append(C.Text.Replace(#13#10,' ').Replace(#13,' ').Replace(#10,' '));
    end;
    var Value := Text.ToString;
    if FDialogueText.Text<>Value then FDialogueText.Text := Value;
  finally Text.Free; end;
  if S=nil then FDialogueCaption.Caption := 'シーンのセリフ'
  else FDialogueCaption.Caption := Format('シーン %d のセリフ',[P.Scenes.IndexOf(S)+1]);
end;
procedure TRigmScriptScenesFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit;
  FGuide.Caption := 'Ctrl+Enter / 入力反映で保存。画像下の「確定」で入力を保護し、修正時はチェックを外します。';
end;
function TRigmScriptScenesFrame.RequestFinish: Boolean;
begin
  Result := False; var A := TJSONArray.Create;
  try
    for var Row in FRows do begin
      var S := FWorkspace.ScriptDraft.Scene(Row.SceneId); if S=nil then raise Exception.Create('シーン構成が変わりました。入力を保持しています。');
      if Row.Position.ItemIndex<0 then raise Exception.Create('補足の配置を選択してください。');
      var Prompt := NormalizeScriptText(Row.Prompt.Text); var Description := NormalizeScriptText(Row.Description.Text);
      var Mode := SceneInputDisplayMode(Prompt,Description); var Position := Positions[Row.Position.ItemIndex];
      if (NormalizeScriptText(SceneImageInstruction(S))=Prompt) and (S.Description=Description) and
        (S.DescriptionPosition=Position) and (S.ImageApproved or (S.DisplayMode=Mode)) then Continue;
      var O := TJSONObject.Create; A.AddElement(O); O.AddPair('id',Row.SceneId); O.AddPair('prompt',Row.Prompt.Text); O.AddPair('description',Row.Description.Text);
      O.AddPair('feedback',''); O.AddPair('mode',Mode); O.AddPair('descriptionPosition',Position);
    end;
    FSync := True;
    try FWorkspace.UpdateScriptSceneInputs(A); FEditing := False; FWorkspace.EndScriptTextEdit; finally FSync := False; end;
    RefreshState; Result := True;
  except on E: Exception do FGuide.Caption := E.Message; end;
  A.Free;
end;
procedure TRigmScriptScenesFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptScenesFrame.Checked(Sender: TObject);
begin
  if FSync then Exit; var Row := RowFor(Sender); if Row=nil then Exit;
  var Id := Row.SceneId; var Value := Row.Approved.Checked;
  if not RequestFinish then begin RefreshState; Exit; end;
  try FWorkspace.SetScriptSceneApproved(Id,Value); RefreshState;
  except on E: Exception do begin RefreshState; FGuide.Caption := E.Message; end; end;
end;
procedure TRigmScriptScenesFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin RequestFinish; Key := 0; end; end;
procedure TRigmScriptScenesFrame.Adopt(Sender: TObject);
begin
  if not RequestFinish then Exit; var Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := '画像|*.png;*.jpg;*.jpeg;*.bmp'; Dialog.Options := [ofFileMustExist,ofPathMustExist,ofDontAddToRecent];
    if Dialog.Execute then FWorkspace.AdoptScriptSceneImage(SelectedId,Dialog.FileName);
  except on E: Exception do FGuide.Caption := E.Message; end; Dialog.Free;
end;
procedure TRigmScriptScenesFrame.RequestImage(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.RequestUnapprovedScriptImages; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.CancelImage(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CancelScriptSceneImage(SelectedId); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.RefreshState;
begin
  if FSync then Exit; var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('scenes')=nil) then Exit;
  FSync := True;
  try
    var Rebuild := FRows.Count<>P.Scenes.Count;
    if not Rebuild then for var I := 0 to P.Scenes.Count-1 do if FRows[I].SceneId<>P.Scenes[I].Id then begin Rebuild := True; Break; end;
    if Rebuild then begin
      if FEditing then Exit; FScroll.DisableAlign;
      try FRows.Clear; for var S in P.Scenes do begin var Row := TRigmSceneImageRow.CreateRow(Self,S.Id); FRows.Add(Row); end;
      finally FScroll.EnableAlign; end;
      LayoutRows;
    end;
    var Ready := 0;
    for var I := 0 to FRows.Count-1 do begin
      var Row := FRows[I]; var S := P.Scene(Row.SceneId); if S=nil then Continue;
      Row.Number.Caption := (I+1).ToString;
      if not FEditing then begin
        var Prompt := SceneImageInstruction(S); if Row.Prompt.Text<>Prompt then Row.Prompt.Text := Prompt;
        if Row.Description.Text<>S.Description then Row.Description.Text := S.Description;
        for var M := 0 to High(Positions) do if Positions[M]=S.DescriptionPosition then Row.Position.ItemIndex := M;
      end;
      Row.Prompt.ReadOnly := S.ImageApproved; Row.Description.ReadOnly := S.ImageApproved;
      Row.Position.Enabled := not S.ImageApproved; Row.Approved.Checked := S.ImageApproved;
      var Stamp := ''; var Path := ResolveMoviePath(P.FileName,S.Image);
      try
        Row.Picture.Hint := ''; Row.Picture.ShowHint := False;
        if S.Image<>'' then Stamp := Path+'|'+CheckedMovieImageHash(Path);
        if Stamp<>Row.ImageStamp then begin
          Row.Picture.Picture.Assign(nil); if Stamp<>'' then Row.Picture.Picture.LoadFromFile(Path); Row.ImageStamp := Stamp;
        end;
      except on E: Exception do begin Row.Picture.Picture.Assign(nil); Row.ImageStamp := ''; Row.Picture.Hint := '画像読込失敗：'+E.Message; Row.Picture.ShowHint := True; end; end;
      if ScriptSceneReady(P,S) then Inc(Ready);
    end;
    RefreshDialogue;
    if not FEditing then FGuide.Caption := Format('確定 %d / %d。要望のある未確定行を要求します。全件確定後、左の工程リストで動画編集へ。',[Ready,P.Scenes.Count]);
  finally FSync := False; end;
end;
procedure TRigmScriptScenesFrame.SetActive(Value: Boolean);
begin if Value then RefreshState; end;
end.
