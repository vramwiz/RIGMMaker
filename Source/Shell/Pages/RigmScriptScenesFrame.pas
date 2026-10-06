unit RigmScriptScenesFrame;
// scene選択・実サムネイル・独立説明文と外部Codex要求。描画と転送はWorkspace所有。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.ImgList,
  RigmWizardWorkspace, RigmIconToolbar, RigmScriptTextFrame;
type
  TRigmScriptScenePreview = class(TCustomControl)
  private FWorkspace: TRigmWizardWorkspace;
  protected procedure Paint; override;
  public constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
  end;
  TRigmScriptScenesFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing,FActive: Boolean; FLoaded,FThumbnailKey: string;
    FList: TListView; FImages: TImageList; FDescription,FPrompt: TRigmScriptMemo; FMode: TComboBox;
    FInfo,FGuide: TLabel; FPreview: TRigmScriptScenePreview; FToolbar: TRigmIconToolbar;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Changed(Sender: TObject);
    procedure Detail(Sender: TObject);
    procedure Done(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
    procedure Adopt(Sender: TObject);
    procedure RequestImage(Sender: TObject);
    procedure CancelImage(Sender: TObject);
    procedure Preview(Sender: TObject);
    procedure RefreshThumbnails;
    function SelectedId: string;
    function ApplyCurrent: Boolean;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, System.Types, System.Generics.Collections, Vcl.Dialogs, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Winapi.Windows,
  RigmJson, RigmToolbarIcons, RigmScriptScenesModel, RigmMovieModel;
{$R *.dfm}
const Modes: array[0..3] of string = ('both','image','text','none');
constructor TRigmScriptScenePreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(AOwner); FWorkspace := Workspace; DoubleBuffered := True; end;
procedure TRigmScriptScenePreview.Paint;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect); var B := FWorkspace.ScenePreview;
  if (B=nil) or (B.Width=0) then begin Canvas.Font.Color := clSilver; Canvas.Font.Height := -20; Canvas.TextOut(16,16,'プレビューを描画中。入力完了後に更新します。'); Exit; end;
  var K := Min(ClientWidth/B.Width,ClientHeight/B.Height); var W := Round(B.Width*K); var H := Round(B.Height*K);
  Canvas.StretchDraw(Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2),B);
end;
constructor TRigmScriptScenesFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptScenesToolbar';
  FToolbar.AddIcon('ScriptSceneEdit','Enter：説明文とCodexへの画像指示を編集',riEditPreview,0,Detail);
  FToolbar.AddIcon('ScriptSceneDone','入力完了（Ctrl+Enter / Esc）',riComplete,0,Done);
  FToolbar.AddIcon('ScriptSceneReady','全シーンの画像・説明文確認完了',riComplete,0,Ready);
  FToolbar.AddSeparator; FToolbar.AddIcon('ScriptSceneAdopt','既存ローカル画像をコピーして採用',riOpen,0,Adopt);
  FToolbar.AddIcon('ScriptSceneRequest','選択シーンの画像を外部Codexへ要求（生成そのものは外部工程）',riRefresh,0,RequestImage);
  FToolbar.AddIcon('ScriptSceneCancel','画像要求を取り消す（現在の画像は保持）',riDelete,0,CancelImage);
  FToolbar.AddIcon('ScriptScenePreview','選択シーンを共通描画で確認',riPreview,0,Preview);
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := 64; FGuide.Font.Height := -20; FGuide.Name := 'ScriptSceneGuide';
  FImages := TImageList.Create(Self); FImages.Width := 96; FImages.Height := 54; FImages.ColorDepth := cd32Bit;
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := 300; FList.ViewStyle := vsReport; FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False;
  FList.SmallImages := FImages; FList.Name := 'ScriptSceneRows'; FList.OnSelectItem := Selected; FList.OnKeyDown := Key;
  FList.Columns.Add.Caption := 'シーン'; FList.Columns[0].Width := 164; FList.Columns.Add.Caption := '状態'; FList.Columns[1].Width := 125;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.BevelOuter := bvNone; Body.Caption := ''; Body.Padding.SetBounds(8,4,8,4);
  FInfo := TLabel.Create(Self); FInfo.Parent := Body; FInfo.Align := alTop; FInfo.AutoSize := False; FInfo.Height := 36; FInfo.Font.Height := -22; FInfo.Name := 'ScriptSceneInfo';
  FMode := TComboBox.Create(Self); FMode.Parent := Body; FMode.Align := alTop; FMode.Style := csDropDownList; FMode.Items.Add('画像と説明文'); FMode.Items.Add('画像のみ'); FMode.Items.Add('説明文のみ'); FMode.Items.Add('表示なし（素材は保持）'); FMode.OnChange := ModeChanged; FMode.Name := 'ScriptSceneMode';
  var PromptPanel := TPanel.Create(Self); PromptPanel.Parent := Body; PromptPanel.Align := alBottom; PromptPanel.Height := 84; PromptPanel.Caption := ''; PromptPanel.BevelOuter := bvNone;
  var L := TLabel.Create(Self); L.Parent := PromptPanel; L.Align := alTop; L.Caption := 'Codexへの画像指示（外部要求用）'; L.Font.Height := -18;
  FPrompt := TRigmScriptMemo.Create(Self); FPrompt.Parent := PromptPanel; FPrompt.Align := alClient; FPrompt.MaxLength := 8000; FPrompt.Font.Height := -20; FPrompt.ScrollBars := ssVertical; FPrompt.Name := 'ScriptScenePrompt'; FPrompt.OnChange := Changed; FPrompt.OnKeyDown := Key;
  var DescriptionPanel := TPanel.Create(Self); DescriptionPanel.Parent := Body; DescriptionPanel.Align := alBottom; DescriptionPanel.Top := 0; DescriptionPanel.Height := 124; DescriptionPanel.Caption := ''; DescriptionPanel.BevelOuter := bvNone;
  L := TLabel.Create(Self); L.Parent := DescriptionPanel; L.Align := alTop; L.Caption := '説明文（字幕・音声とは独立。シーン全体で表示）'; L.Font.Height := -18;
  FDescription := TRigmScriptMemo.Create(Self); FDescription.Parent := DescriptionPanel; FDescription.Align := alClient; FDescription.MaxLength := 3000; FDescription.Font.Height := -24; FDescription.ScrollBars := ssVertical; FDescription.Name := 'ScriptSceneDescription'; FDescription.OnChange := Changed; FDescription.OnKeyDown := Key;
  FPreview := TRigmScriptScenePreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Body; FPreview.Align := alClient; FPreview.Name := 'ScriptScenePreviewControl';
  FInfo.Top := 0; FMode.Top := 36;
end;
function TRigmScriptScenesFrame.SelectedId: string;
begin Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'scenes'),'selectedScene'); end;
function TRigmScriptScenesFrame.ApplyCurrent: Boolean;
begin Result := False; try FWorkspace.EditScriptScene(SelectedId,FDescription.Text,FPrompt.Text,Modes[FMode.ItemIndex]); Result := True; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.Changed(Sender: TObject);
begin if FSync or not FEditing then Exit; FWorkspace.BeginScriptTextEdit; ApplyCurrent; end;
procedure TRigmScriptScenesFrame.Detail(Sender: TObject);
begin FEditing := True; FWorkspace.BeginScriptTextEdit; RefreshState; FDescription.SetFocus; end;
function TRigmScriptScenesFrame.RequestFinish: Boolean;
begin Result := not FEditing or ApplyCurrent; if not Result then Exit; FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState; end;
procedure TRigmScriptScenesFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptScenesFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteScriptScenes; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  if FSync or not Value then Exit; var Id := Item.SubItems[1];
  if not RequestFinish then begin FSync := True; try for var Entry in FList.Items do Entry.Selected := Entry.SubItems[1]=SelectedId; finally FSync := False; end; Exit; end;
  FWorkspace.SelectScriptScene(Id);
end;
procedure TRigmScriptScenesFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FEditing then begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Done(Self); Key := 0; end; end
  else if Key=VK_RETURN then begin Detail(Self); Key := 0; end
  else if (Key=VK_UP) or (Key=VK_DOWN) then begin if RequestFinish then if Key=VK_UP then FWorkspace.MoveScriptScene(-1) else FWorkspace.MoveScriptScene(1); Key := 0; end;
end;
procedure TRigmScriptScenesFrame.ModeChanged(Sender: TObject);
begin if FSync or (FMode.ItemIndex<0) then Exit; var Mode := Modes[FMode.ItemIndex]; if not RequestFinish then Exit; try var S := FWorkspace.ScriptDraft.Scene(SelectedId); FWorkspace.EditScriptScene(S.Id,S.Description,S.ImagePrompt,Mode); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.Adopt(Sender: TObject);
begin if not RequestFinish then Exit; var Dialog := TOpenDialog.Create(Self); try Dialog.Filter := '画像|*.png;*.jpg;*.jpeg;*.bmp'; Dialog.Options := [ofFileMustExist,ofPathMustExist,ofDontAddToRecent]; if Dialog.Execute then FWorkspace.AdoptScriptSceneImage(SelectedId,Dialog.FileName); except on E: Exception do FGuide.Caption := E.Message; end; Dialog.Free; end;
procedure TRigmScriptScenesFrame.RequestImage(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.RequestScriptSceneImage(SelectedId); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.CancelImage(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CancelScriptSceneImage(SelectedId); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.Preview(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.PreviewScriptScene(True); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptScenesFrame.RefreshThumbnails;
begin
  var P := FWorkspace.ScriptDraft; var Stamp := P.Id; for var S in P.Scenes do Stamp := Stamp+'|'+S.Image;
  if Stamp=FThumbnailKey then Exit; FImages.Clear;
  for var S in P.Scenes do begin
    var B := Vcl.Graphics.TBitmap.Create; var Picture := TPicture.Create;
    try B.SetSize(96,54); B.Canvas.Brush.Color := clBlack; B.Canvas.FillRect(Rect(0,0,96,54));
      if (S.Image<>'') and FileExists(ResolveMoviePath(P.FileName,S.Image)) then begin
        try Picture.LoadFromFile(ResolveMoviePath(P.FileName,S.Image)); var K := Min(96/Picture.Width,54/Picture.Height); var W := Round(Picture.Width*K); var H := Round(Picture.Height*K); B.Canvas.StretchDraw(Rect((96-W) div 2,(54-H) div 2,(96+W) div 2,(54+H) div 2),Picture.Graphic); except on E: Exception do begin B.Canvas.Font.Color := clSilver; B.Canvas.TextOut(2,16,'読込不可'); end; end;
      end;
      FImages.Add(B,nil);
    finally Picture.Free; B.Free; end;
  end;
  FThumbnailKey := Stamp;
end;
procedure TRigmScriptScenesFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('scenes')=nil) then Exit; var S := P.Scene(SelectedId); if S=nil then Exit;
  FSync := True;
  try
    if not FEditing then begin
      RefreshThumbnails; FList.Items.BeginUpdate;
      try FList.Items.Clear; for var I := 0 to P.Scenes.Count-1 do begin var Scene := P.Scenes[I]; var Item := FList.Items.Add; Item.Caption := (I+1).ToString; Item.ImageIndex := I; var State := '未確認'; if ScriptSceneReady(P,Scene) then State := '準備済'; var R := ScriptSceneRequest(P,Scene.Id); if (R<>nil) and (JS(R,'state')='pending') then if JS(R,'fingerprint')=ScriptSceneFingerprint(P,Scene.Id) then State := '要求中' else State := '要求変更'; Item.SubItems.Add(State); Item.SubItems.Add(Scene.Id); Item.Selected := Scene.Id=S.Id; end;
      finally FList.Items.EndUpdate; end;
    end;
    if not FEditing or (FLoaded<>S.Id) then begin FDescription.Text := S.Description; FPrompt.Text := S.ImagePrompt; FLoaded := S.Id; for var I := 0 to 3 do if Modes[I]=S.DisplayMode then FMode.ItemIndex := I; end;
    FDescription.ReadOnly := not FEditing; FPrompt.ReadOnly := not FEditing;
    FInfo.Caption := 'シーン '+ScriptSceneNumber(P,S.Id).ToString+' / '+P.Scenes.Count.ToString+'　'+FormatFloat('0.00',ScriptSceneStart(P,S.Id))+'秒〜　'+FormatFloat('0.00',P.SceneDuration(S))+'秒';
    FGuide.Caption := '↑↓：シーン選択 / Enter：説明・画像指示を編集。画像要求はCodexの外部工程です。';
    if FActive and not FEditing then try FWorkspace.PreviewScriptScene; except on E: Exception do FGuide.Caption := E.Message; end;
    var State := FWorkspace.ScriptScenePreviewStatus; try if JS(State,'error')<>'' then FGuide.Caption := FGuide.Caption+#13#10+JS(State,'error'); finally State.Free; end;
    FPreview.Invalidate;
  finally FSync := False; end;
end;
procedure TRigmScriptScenesFrame.SetActive(Value: Boolean);
begin FActive := Value; end;
end.
