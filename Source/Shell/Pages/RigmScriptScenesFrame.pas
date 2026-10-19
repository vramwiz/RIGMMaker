unit RigmScriptScenesFrame;
// 固定sceneIdのコンパクトな入力行。要望・修正指示は1欄、確定は画像下のチェック。
interface
uses System.Classes, System.Generics.Collections, RigmScriptPageFrame, Vcl.Forms,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, RigmWizardWorkspace,
  RigmIconToolbar, RigmScriptTextFrame, RigmBufferedControls, Vcl.ComCtrls;
type
  TRigmScriptScenesFrame = class;
  TRigmSceneImageRow = class(TRigmBufferedPanel)
  public
    SceneId,ImageStamp: string;
    Number: TLabel;
    SceneName: TEdit;
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
    FImageAiPanel: TPanel; FImageAiSelected,FImageAiAll,FImageAiCancel: TButton;
    FImageAiStatus: TLabel; FImageAiProgress: TProgressBar;
    procedure GenerateSelected(Sender: TObject);
    procedure GenerateAll(Sender: TObject);
    procedure StopGeneration(Sender: TObject);
    procedure RefreshImageAi;
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
  RigmScriptScenesModel, RigmMovieModel, RigmMovieImageTransfer, RigmScriptTextModel, RigmMovieChart, RigmScriptThumbnailModel;
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
  SceneName := TEdit.Create(Self); SceneName.Parent := Self; SceneName.Name := 'SceneName'; SceneName.MaxLength := 300;
  SceneName.OnChange := AOwner.Changed; SceneName.OnKeyDown := AOwner.Key; SceneName.OnEnter := AOwner.FocusRow;
  SceneName.Visible := (Id<>RigmCommonBackgroundId) and (Id<>RigmThumbnailId);
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
  // 行の確定した高さに揃え、動的パネル側の初期PPIによる欄のずれを避ける。
  var Gap := Max(1,MulDiv(4,Height,88)); var ComboHeight := MulDiv(24,Height,88);
  Number.SetBounds(Gap,Gap,NumberWidth-Gap*2,ComboHeight);
  SceneName.SetBounds(Gap,ComboHeight+Gap*2,NumberWidth-Gap*2,ComboHeight);
  if (SceneId=RigmCommonBackgroundId) or (SceneId=RigmThumbnailId) then Number.Height := Height-Gap*2;
  Prompt.SetBounds(NumberWidth+Gap,Gap,PromptWidth-Gap*2,Height-Gap*2);
  var X := NumberWidth+PromptWidth+Gap;
  Description.SetBounds(X,Gap,DescriptionWidth-Gap*2,Height-ComboHeight-Gap*3);
  Position.SetBounds(X,Height-ComboHeight-Gap,DescriptionWidth-Gap*2,ComboHeight);
  if (SceneId=RigmCommonBackgroundId) or (SceneId=RigmThumbnailId) then Description.Height := Height-Gap*2;
  X := NumberWidth+PromptWidth+DescriptionWidth+Gap;
  var ApprovalHeight := Max(ComboHeight,MulDiv(24,Approved.CurrentPPI,96));
  Picture.SetBounds(X,Gap,ImageWidth-Gap*2,Max(1,Height-ApprovalHeight-Gap*3));
  Approved.SetBounds(X,Height-ApprovalHeight-Gap,ImageWidth-Gap*2,ApprovalHeight);
end;
constructor TRigmScriptScenesFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; Align := alClient; FRows := TObjectList<TRigmSceneImageRow>.Create(True);
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptScenesToolbar';
  FToolbar.AddIcon('ScriptSceneDone','シーン名・要望・補足文の入力を反映（Ctrl+Enter / Esc）。確定チェックとは別です',riSave,0,Done);
  FToolbar.AddIcon('ScriptSceneRequest','外部操作用の画像要求だけを準備。自動生成には下の「画像を生成」ボタンを使います',riRefresh,0,RequestImage);
  FToolbar.AddIcon('ScriptSceneAdopt','選択行へ既存ローカル画像をコピーして採用',riOpen,0,Adopt);
  FToolbar.AddIcon('ScriptSceneCancel','選択行の画像要求を取り消す',riDelete,0,CancelImage);
  FImageAiPanel := TPanel.Create(Self); FImageAiPanel.Parent := Self; FImageAiPanel.Align := alTop;
  FImageAiPanel.Top := FToolbar.Top+FToolbar.Height; FImageAiPanel.Height := ScaleValue(64);
  FImageAiPanel.BevelOuter := bvNone; FImageAiPanel.Caption := '';
  FImageAiStatus := TRigmScriptLabel.Create(Self); FImageAiStatus.Parent := FImageAiPanel;
  FImageAiStatus.Align := alBottom; FImageAiStatus.Height := ScaleValue(28); FImageAiStatus.AutoSize := False;
  FImageAiStatus.WordWrap := True; FImageAiStatus.Layout := tlCenter; FImageAiStatus.Name := 'ScriptSceneAiStatus';
  FImageAiSelected := TButton.Create(Self); FImageAiSelected.Parent := FImageAiPanel; FImageAiSelected.Align := alLeft;
  FImageAiSelected.Width := ScaleValue(210); FImageAiSelected.Caption := '選択行の画像を生成';
  FImageAiSelected.Name := 'ScriptSceneAiSelected'; FImageAiSelected.OnClick := GenerateSelected;
  FImageAiAll := TButton.Create(Self); FImageAiAll.Parent := FImageAiPanel; FImageAiAll.Align := alLeft;
  FImageAiAll.Left := FImageAiSelected.Width; FImageAiAll.Width := ScaleValue(230);
  FImageAiAll.Caption := '未確定画像を順に生成'; FImageAiAll.Name := 'ScriptSceneAiAll'; FImageAiAll.OnClick := GenerateAll;
  FImageAiCancel := TButton.Create(Self); FImageAiCancel.Parent := FImageAiPanel; FImageAiCancel.Align := alRight;
  FImageAiCancel.Width := ScaleValue(80); FImageAiCancel.Caption := '中止'; FImageAiCancel.Name := 'ScriptSceneAiCancel';
  FImageAiCancel.Visible := False; FImageAiCancel.OnClick := StopGeneration;
  FImageAiProgress := TProgressBar.Create(Self); FImageAiProgress.Parent := FImageAiPanel; FImageAiProgress.Align := alRight;
  FImageAiProgress.Width := ScaleValue(120); FImageAiProgress.Style := pbstMarquee; FImageAiProgress.MarqueeInterval := 40;
  FImageAiProgress.Visible := False; FImageAiProgress.Name := 'ScriptSceneAiProgress';
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
  var Captions: TArray<string> := ['シーン名（動画左上）','画像要望・修正指示（Codexへ）','補足文（動画表示）／配置','要求画像'];
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
  var W := Max(ScaleValue(924),FScroll.ClientWidth);
  var Sizes: TArray<Integer> := [ScaleValue(180),0,0,ScaleValue(180)];
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
    if (Sender=Row.SceneName) or (Sender=Row.Prompt) or (Sender=Row.Description) or (Sender=Row.Approved) or (Sender=Row.Position) then Exit(Row);
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
  if SelectedId=RigmCommonBackgroundId then FDialogueCaption.Caption := '共通背景（セリフなし）'
  else if SelectedId=RigmThumbnailId then FDialogueCaption.Caption := 'サムネイル（10秒）'
  else if S=nil then FDialogueCaption.Caption := 'シーンのセリフ'
  else FDialogueCaption.Caption := Format('シーン %d のセリフ',[P.Scenes.IndexOf(S)+1]);
end;
procedure TRigmScriptScenesFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit;
  FGuide.Caption := 'Ctrl+Enter / 入力反映で保存。シーン名は画像確定後も編集できます。画像の修正時は確定チェックを外します。';
end;
function TRigmScriptScenesFrame.RequestFinish: Boolean;
begin
  Result := False; var WasEditing := FEditing; var A := TJSONArray.Create;
  try
    for var Row in FRows do begin
      var S := FWorkspace.ScriptDraft.ImageTarget(Row.SceneId); if S=nil then raise Exception.Create('シーン構成が変わりました。入力を保持しています。');
      if Row.Position.ItemIndex<0 then raise Exception.Create('補足の配置を選択してください。');
      var Prompt := NormalizeScriptText(Row.Prompt.Text); var Description := NormalizeScriptText(Row.Description.Text);
      var Mode := SceneInputDisplayMode(Prompt,Description); var Position := Positions[Row.Position.ItemIndex];
      if MovieChartEnabled(S.Chart) then Mode := S.DisplayMode;
      if Row.SceneId=RigmCommonBackgroundId then begin Description := ''; Mode := SceneInputDisplayMode(Prompt,''); Position := 'below-image'; end;
      if Row.SceneId=RigmThumbnailId then begin Description := ''; Mode := 'image'; Position := 'below-image'; end;
      var NameChanged := (Row.SceneId<>RigmCommonBackgroundId) and (Row.SceneId<>RigmThumbnailId) and (S.Title<>Row.SceneName.Text);
      var ImageChanged := (NormalizeScriptText(SceneImageInstruction(S))<>Prompt) or (S.Description<>Description) or
        (S.DescriptionPosition<>Position) or (not S.ImageApproved and (S.DisplayMode<>Mode));
      if not NameChanged and not ImageChanged then Continue;
      var O := TJSONObject.Create; A.AddElement(O); O.AddPair('id',Row.SceneId);
      if NameChanged then O.AddPair('title',Row.SceneName.Text);
      if ImageChanged then begin
        O.AddPair('prompt',Row.Prompt.Text); O.AddPair('description',Description);
        O.AddPair('feedback',''); O.AddPair('mode',Mode); O.AddPair('descriptionPosition',Position);
      end;
    end;
    FSync := True;
    try FWorkspace.UpdateScriptSceneInputs(A); FEditing := False; FWorkspace.EndScriptTextEdit; finally FSync := False; end;
    if (A.Count>0) or WasEditing then RefreshState;
    Result := True;
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
  // Workspaceの通知が親の工程リストと画像行を一度に更新する。
  try
    FWorkspace.SetScriptSceneApproved(Id,Value);
    if not Assigned(FWorkspace.OnScriptChanged) then RefreshState;
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
procedure TRigmScriptScenesFrame.GenerateSelected(Sender: TObject);
begin
  if not RequestFinish then Exit;
  try FWorkspace.StartSceneImageAi(SelectedId); RefreshState;
  except on E: Exception do begin RefreshState; FImageAiStatus.Caption := E.Message; end; end;
end;
procedure TRigmScriptScenesFrame.GenerateAll(Sender: TObject);
begin
  if not RequestFinish then Exit;
  try FWorkspace.StartSceneImageAi; RefreshState;
  except on E: Exception do begin RefreshState; FImageAiStatus.Caption := E.Message; end; end;
end;
procedure TRigmScriptScenesFrame.StopGeneration(Sender: TObject);
begin FWorkspace.CancelSceneImageAi; RefreshState; end;
procedure TRigmScriptScenesFrame.RefreshImageAi;
begin
  var Busy := FWorkspace.SceneImageAiBusy;
  FImageAiSelected.Enabled := not Busy; FImageAiAll.Enabled := not Busy;
  FImageAiCancel.Visible := Busy; FImageAiProgress.Visible := Busy;
  if Busy then FImageAiProgress.Style := pbstMarquee else FImageAiProgress.Style := pbstNormal;
  FImageAiStatus.Caption := FWorkspace.SceneImageAiMessage;
  if FImageAiStatus.Caption='' then FImageAiStatus.Caption := '要望を入力して生成します。画像を確認した後、各行の「確定」をチェックしてください。';
  FImageAiStatus.Hint := FImageAiStatus.Caption; FImageAiStatus.ShowHint := True;
end;
procedure TRigmScriptScenesFrame.RefreshState;
begin
  if FSync then Exit; var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('scenes')=nil) then Exit;
  FSync := True;
  try
    var Rebuild := FRows.Count<>P.Scenes.Count+2;
    if not Rebuild then begin
      Rebuild := FRows[0].SceneId<>RigmCommonBackgroundId;
      if FRows.Last.SceneId<>RigmThumbnailId then Rebuild := True;
      for var I := 0 to P.Scenes.Count-1 do if FRows[I+1].SceneId<>P.Scenes[I].Id then begin Rebuild := True; Break; end;
    end;
    if Rebuild then begin
      if FEditing then Exit; FScroll.DisableAlign;
      try
        FRows.Clear; FRows.Add(TRigmSceneImageRow.CreateRow(Self,RigmCommonBackgroundId));
        for var S in P.Scenes do begin var Row := TRigmSceneImageRow.CreateRow(Self,S.Id); FRows.Add(Row); end;
        FRows.Add(TRigmSceneImageRow.CreateRow(Self,RigmThumbnailId));
      finally FScroll.EnableAlign; end;
      LayoutRows;
    end;
    var Ready := 0;
    for var I := 0 to FRows.Count-1 do begin
      var Row := FRows[I]; var S := P.ImageTarget(Row.SceneId); if S=nil then Continue;
      var IsBackground := Row.SceneId=RigmCommonBackgroundId;
      var IsThumbnail := Row.SceneId=RigmThumbnailId;
      if IsBackground then Row.Number.Caption := '共通'+#13#10+'背景'
      else if IsThumbnail then Row.Number.Caption := '必須'+#13#10+'サムネイル' else Row.Number.Caption := I.ToString;
      if not FEditing then begin
        if Row.SceneName.Text<>S.Title then Row.SceneName.Text := S.Title;
        var Prompt := SceneImageInstruction(S); if Row.Prompt.Text<>Prompt then Row.Prompt.Text := Prompt;
        var Description := S.Description;
        if IsBackground then Description := Format('共通背景画像（任意）  %d × %d'+#13#10+'中央型：全画面。L字型：シーン画像なしのとき。'+#13#10+'縦横比を保ち、表示エリアに合わせて配置します。',[P.Width,P.Height]);
        if IsThumbnail then Description := Format('必須・最後に作成  %d × %d'+#13#10+'ロゴ：%s'+#13#10+'シーン画像＋使用キャラ。末尾10秒、1秒で滑らかに切替。',[P.Width,P.Height,ThumbnailLogo(P)]);
        if Row.Description.Text<>Description then Row.Description.Text := Description;
        for var M := 0 to High(Positions) do if Positions[M]=S.DescriptionPosition then Row.Position.ItemIndex := M;
      end;
      var Busy := FWorkspace.SceneImageAiBusy;
      Row.SceneName.ReadOnly := Busy;
      Row.Prompt.ReadOnly := S.ImageApproved or Busy; Row.Description.ReadOnly := IsBackground or IsThumbnail or S.ImageApproved or Busy;
      Row.Position.Visible := not IsBackground and not IsThumbnail; Row.Position.Enabled := not S.ImageApproved and not Busy;
      var CurrentApproval := ScriptSceneReady(P,S);
      Row.Approved.Checked := S.ImageApproved and CurrentApproval;
      Row.Approved.Caption := '確定';
      if S.ImageApproved and not CurrentApproval then Row.Approved.Caption := '再確認';
      Row.Approved.Hint := ScriptSceneReadinessReason(P,S); Row.Approved.ShowHint := Row.Approved.Hint<>'';
      Row.Approved.Enabled := (not IsBackground or SceneNeedsImage(S) or S.ImageApproved) and not Busy;
      var Stamp := ''; var Path := ResolveMoviePath(P.FileName,S.Image);
      try
        Row.Picture.Hint := ''; Row.Picture.ShowHint := False;
        if S.Image<>'' then Stamp := Path+'|'+CheckedMovieImageHash(Path);
        if Stamp<>Row.ImageStamp then begin
          Row.Picture.Picture.Assign(nil); if Stamp<>'' then Row.Picture.Picture.LoadFromFile(Path); Row.ImageStamp := Stamp;
        end;
      except on E: Exception do begin Row.Picture.Picture.Assign(nil); Row.ImageStamp := ''; Row.Picture.Hint := '画像読込失敗：'+E.Message; Row.Picture.ShowHint := True; end; end;
      if not IsBackground and not IsThumbnail and ScriptSceneReady(P,S) then Inc(Ready);
    end;
    RefreshDialogue;
    RefreshImageAi;
    if not FEditing then begin
      var State := '未確定'; if ScriptSceneReady(P,P.Thumbnail) then State := '確定済み';
      FGuide.Caption := Format('シーン確定 %d / %d。共通背景は任意。最後に必須サムネイルを作成・確定して動画編集へ（%s）。',[Ready,P.Scenes.Count,State]);
    end;
  finally FSync := False; end;
end;
procedure TRigmScriptScenesFrame.SetActive(Value: Boolean);
begin if Value then RefreshState; end;
end.
