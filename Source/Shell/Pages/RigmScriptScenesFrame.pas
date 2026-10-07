unit RigmScriptScenesFrame;
// Stable scene IDs own each row; numbers are display-only. Approval is a separate right-hand checkbox.
interface
uses System.Classes, System.Generics.Collections, RigmScriptPageFrame, Vcl.Forms,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, RigmWizardWorkspace,
  RigmIconToolbar, RigmScriptTextFrame, RigmBufferedControls;
type
  TRigmScriptScenesFrame = class;
  TRigmSceneImageRow = class(TRigmBufferedPanel)
  public
    SceneId,ImageStamp: string;
    Number,Info: TLabel;
    Prompt,Description,Feedback: TRigmScriptMemo;
    Picture: TImage;
    Approved: TCheckBox;
    Mode: TComboBox;
    constructor CreateRow(AOwner: TRigmScriptScenesFrame; const Id: string);
  end;
  TRigmScriptScenePreview = class(TCustomControl)
  private FWorkspace: TRigmWizardWorkspace;
  protected procedure Paint; override;
  public constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
  end;
  TRigmScriptScenesFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace;
    FSync,FEditing,FActive: Boolean;
    FRows: TObjectList<TRigmSceneImageRow>;
    FScroll: TScrollBox;
    FGuide: TLabel;
    FToolbar: TRigmIconToolbar;
    FPreview: TRigmScriptScenePreview;
    FPreviewStamp: string;
    procedure Changed(Sender: TObject);
    procedure FocusRow(Sender: TObject);
    procedure Checked(Sender: TObject);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Done(Sender: TObject);
    procedure Adopt(Sender: TObject);
    procedure RequestImage(Sender: TObject);
    procedure CancelImage(Sender: TObject);
    procedure Preview(Sender: TObject);
    function RowFor(Sender: TObject): TRigmSceneImageRow;
    function SelectedId: string;
  protected
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
const Modes: array[0..3] of string = ('both','image','text','none');
constructor TRigmSceneImageRow.CreateRow(AOwner: TRigmScriptScenesFrame; const Id: string);
  function Column(const Caption: string; Width: Integer): TPanel;
  begin
    Result := TRigmBufferedPanel.Create(Self); Result.Parent := Self; Result.Left := MaxInt; Result.Align := alLeft;
    Result.Width := MulDiv(Width,CurrentPPI,96); Result.BevelOuter := bvNone; Result.Caption := '';
    Result.Padding.SetBounds(6,4,6,4);
    var L := TRigmScriptLabel.Create(Self); L.Parent := Result; L.Align := alTop; L.Caption := Caption;
    L.Font.Height := -MulDiv(16,CurrentPPI,96);
  end;
begin
  inherited Create(AOwner); SceneId := Id; Parent := AOwner.FScroll; Align := alNone; Width := MulDiv(960,CurrentPPI,96);
  Height := MulDiv(210,CurrentPPI,96); BevelOuter := bvLowered; Caption := '';
  var C := Column('シーン',70); Number := TRigmScriptLabel.Create(Self); Number.Parent := C; Number.Align := alTop;
  Number.Font.Height := -MulDiv(22,CurrentPPI,96);
  C := Column('画像要望（Codexへ）',250);
  Feedback := TRigmScriptMemo.Create(Self); Feedback.Parent := C; Feedback.Align := alBottom; Feedback.Height := MulDiv(62,CurrentPPI,96);
  Feedback.MaxLength := 8000; Feedback.ScrollBars := ssVertical; Feedback.OnChange := AOwner.Changed; Feedback.OnKeyDown := AOwner.Key; Feedback.OnEnter := AOwner.FocusRow;
  var L := TRigmScriptLabel.Create(Self); L.Parent := C; L.Align := alBottom; L.Caption := '修正指示（動画には表示しません）';
  Prompt := TRigmScriptMemo.Create(Self); Prompt.Parent := C; Prompt.Align := alClient; Prompt.MaxLength := 8000;
  Prompt.ScrollBars := ssVertical; Prompt.OnChange := AOwner.Changed; Prompt.OnKeyDown := AOwner.Key; Prompt.OnEnter := AOwner.FocusRow;
  C := Column('画像補足テキスト（動画に表示）',250);
  Mode := TComboBox.Create(Self); Mode.Parent := C; Mode.Align := alBottom; Mode.Style := csDropDownList;
  Mode.Items.Add('画像と補足文'); Mode.Items.Add('画像のみ'); Mode.Items.Add('補足文のみ'); Mode.Items.Add('表示なし（画像は保持）'); Mode.ItemIndex := 0;
  Mode.OnChange := AOwner.Changed; Mode.OnEnter := AOwner.FocusRow;
  Description := TRigmScriptMemo.Create(Self); Description.Parent := C; Description.Align := alClient; Description.MaxLength := 3000;
  Description.ScrollBars := ssVertical; Description.OnChange := AOwner.Changed; Description.OnKeyDown := AOwner.Key; Description.OnEnter := AOwner.FocusRow;
  C := Column('要求画像のプレビュー',240);
  Info := TRigmScriptLabel.Create(Self); Info.Parent := C; Info.Align := alBottom; Info.AutoSize := False; Info.Height := MulDiv(46,CurrentPPI,96); Info.WordWrap := True;
  Picture := TImage.Create(Self); Picture.Parent := C; Picture.Align := alClient; Picture.Center := True; Picture.Proportional := True; Picture.Stretch := True;
  C := Column('確定 / 更新を保護',150);
  Approved := TCheckBox.Create(Self); Approved.Parent := C; Approved.Align := alTop; Approved.Height := MulDiv(36,CurrentPPI,96);
  Approved.Caption := 'この画像で確定'; Approved.OnClick := AOwner.Checked;
  L := TRigmScriptLabel.Create(Self); L.Parent := C; L.Align := alClient; L.WordWrap := True; L.AutoSize := False;
  L.Caption := '修正時はチェックを外します。全件確定後、上段Nextで保存して動画編集へ進みます。';
end;
constructor TRigmScriptScenePreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(AOwner); FWorkspace := Workspace; DoubleBuffered := True; end;
procedure TRigmScriptScenePreview.Paint;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect); var B := FWorkspace.ScenePreview;
  if (B=nil) or (B.Width=0) then begin Canvas.Font.Color := clSilver; Canvas.TextOut(10,10,'選択シーンの動画配置プレビュー'); Exit; end;
  var K := Min(ClientWidth/B.Width,ClientHeight/B.Height); var W := Round(B.Width*K); var H := Round(B.Height*K);
  Canvas.StretchDraw(Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2),B);
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
  FToolbar.AddIcon('ScriptScenePreview','選択行の動画配置プレビューを更新',riPreview,0,Preview);
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True;
  FGuide.Height := ScaleValue(54); FGuide.Name := 'ScriptSceneGuide';
  FPreview := TRigmScriptScenePreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Self; FPreview.Align := alBottom; FPreview.Height := ScaleValue(128);
  FScroll := TScrollBox.Create(Self); FScroll.Parent := Self; FScroll.Align := alClient; FScroll.BorderStyle := bsNone;
  FScroll.VertScrollBar.Tracking := True; FScroll.HorzScrollBar.Tracking := True; FScroll.HorzScrollBar.Range := ScaleValue(960); FScroll.Name := 'ScriptSceneRows';
end;
destructor TRigmScriptScenesFrame.Destroy;
begin FRows.Free; inherited; end;
procedure TRigmScriptScenesFrame.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; if FScroll<>nil then begin FScroll.HorzScrollBar.Range := ScaleValue(960); for var I := 0 to FRows.Count-1 do FRows[I].SetBounds(0,I*ScaleValue(210),ScaleValue(960),ScaleValue(210)); end; end;
function TRigmScriptScenesFrame.SelectedId: string;
begin Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'scenes'),'selectedScene'); end;
function TRigmScriptScenesFrame.RowFor(Sender: TObject): TRigmSceneImageRow;
begin
  Result := nil; for var Row in FRows do
    if (Sender=Row.Prompt) or (Sender=Row.Description) or (Sender=Row.Feedback) or (Sender=Row.Approved) or (Sender=Row.Mode) then Exit(Row);
end;
procedure TRigmScriptScenesFrame.FocusRow(Sender: TObject);
begin
  if FSync then Exit; var Row := RowFor(Sender); if Row=nil then Exit;
  try FWorkspace.SelectScriptScene(Row.SceneId); except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptScenesFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit;
  FGuide.Caption := '入力中。Ctrl+Enter / Esc または入力反映アイコンで反映します。画像確定は右端チェックです。';
end;
function TRigmScriptScenesFrame.RequestFinish: Boolean;
begin
  Result := False; var A := TJSONArray.Create;
  try
    for var Row in FRows do begin
      var S := FWorkspace.ScriptDraft.Scene(Row.SceneId); if S=nil then raise Exception.Create('シーン構成が変わりました。入力を保持しています。');
      if (Row.Mode.ItemIndex<0) then raise Exception.Create('表示方法を選択してください。');
      if (S.ImagePrompt=NormalizeScriptText(Row.Prompt.Text)) and (S.Description=NormalizeScriptText(Row.Description.Text)) and (S.ImageFeedback=NormalizeScriptText(Row.Feedback.Text)) and (S.DisplayMode=Modes[Row.Mode.ItemIndex]) then Continue;
      var O := TJSONObject.Create; A.AddElement(O); O.AddPair('id',Row.SceneId); O.AddPair('prompt',Row.Prompt.Text); O.AddPair('description',Row.Description.Text);
      O.AddPair('feedback',Row.Feedback.Text); O.AddPair('mode',Modes[Row.Mode.ItemIndex]);
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
procedure TRigmScriptScenesFrame.Preview(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.PreviewScriptScene(True); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.RefreshState;
begin
  if FSync then Exit; var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('scenes')=nil) then Exit;
  FSync := True;
  try
    var Rebuild := FRows.Count<>P.Scenes.Count;
    if not Rebuild then for var I := 0 to P.Scenes.Count-1 do if FRows[I].SceneId<>P.Scenes[I].Id then begin Rebuild := True; Break; end;
    if Rebuild then begin
      if FEditing then Exit; FScroll.DisableAlign;
      try FRows.Clear; for var S in P.Scenes do begin var Row := TRigmSceneImageRow.CreateRow(Self,S.Id); Row.Top := FRows.Count*ScaleValue(210); FRows.Add(Row); end;
      finally FScroll.EnableAlign; end;
    end;
    var Ready := 0;
    for var I := 0 to FRows.Count-1 do begin
      var Row := FRows[I]; var S := P.Scene(Row.SceneId); if S=nil then Continue;
      Row.Number.Caption := (I+1).ToString;
      if not FEditing then begin
        if Row.Prompt.Text<>S.ImagePrompt then Row.Prompt.Text := S.ImagePrompt;
        if Row.Description.Text<>S.Description then Row.Description.Text := S.Description;
        if Row.Feedback.Text<>S.ImageFeedback then Row.Feedback.Text := S.ImageFeedback;
        for var M := 0 to 3 do if Modes[M]=S.DisplayMode then Row.Mode.ItemIndex := M;
      end;
      Row.Prompt.ReadOnly := S.ImageApproved; Row.Description.ReadOnly := S.ImageApproved; Row.Feedback.ReadOnly := S.ImageApproved;
      Row.Mode.Enabled := not S.ImageApproved; Row.Approved.Checked := S.ImageApproved;
      var Info := '画像なし'; var Stamp := ''; var Path := ResolveMoviePath(P.FileName,S.Image);
      try
        if S.Image<>'' then begin Stamp := Path+'|'+CheckedMovieImageHash(Path); Info := '未確定'; end;
        if (Stamp<>Row.ImageStamp) or (Stamp='') then begin
          Row.Picture.Picture.Assign(nil); if Stamp<>'' then Row.Picture.Picture.LoadFromFile(Path); Row.ImageStamp := Stamp;
        end;
        if ScriptSceneReady(P,S) then begin Info := '確定 / 更新保護中'; Inc(Ready); end
        else if S.ImageApproved then Info := '再確認が必要：チェックを外して再設定';
      except on E: Exception do begin Row.Picture.Picture.Assign(nil); Row.ImageStamp := ''; Info := '画像読込失敗：'+E.Message; end; end;
      if S.Id=SelectedId then Info := '選択中 / '+Info;
      Row.Info.Caption := Info;
    end;
    if not FEditing then FGuide.Caption := Format('確定 %d / %d。要望入力後はCodexへ作業を指示してください。未確定行だけ更新されます。全件確定後、上段Nextで保存して動画編集へ。',[Ready,P.Scenes.Count]);
    if FActive and not FEditing then try FWorkspace.PreviewScriptScene; except on E: Exception do FGuide.Caption := E.Message; end;
    var State := FWorkspace.ScriptScenePreviewStatus;
    try var Stamp := P.Id+'|'+SelectedId+'|'+JS(State,'path')+'|'+JS(State,'error'); if Stamp<>FPreviewStamp then begin FPreviewStamp := Stamp; FPreview.Invalidate; end;
    finally State.Free; end;
  finally FSync := False; end;
end;
procedure TRigmScriptScenesFrame.SetActive(Value: Boolean);
begin FActive := Value; end;
end.
