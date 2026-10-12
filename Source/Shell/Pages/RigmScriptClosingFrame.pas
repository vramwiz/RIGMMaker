unit RigmScriptClosingFrame;
interface
uses System.Classes, RigmScriptPageFrame, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
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
    FTitle: TEdit; FChoice: array[0..2] of TComboBox; FPaths,FImageLabels: array[0..2] of TLabel;
    FAdopt: array[0..2] of TButton; FTitleLabel: TLabel;
    FBody,FSettings,FOptions,FPreviewColumn: TPanel;
    FSpeech: TMemo; FMode: TComboBox; FGuide: TLabel; FPreview: TRigmScriptClosingPreview;
    function Draft: TJSONObject;
    procedure LayoutControls;
    procedure Changed(Sender: TObject);
    procedure Adopt(Sender: TObject);
    procedure Done(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
    procedure SpeechChanged(Sender: TObject);
  protected
    procedure Resize; override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace);
    procedure RefreshState;
    function RequestFinish: Boolean;
  end;
implementation
uses System.SysUtils, System.Math, System.Types, Vcl.Graphics, Vcl.Dialogs, Winapi.Windows,
  RigmJson, PsdJson, RigmScriptClosingModel, RigmMovieCompositor, RigmScriptScenesModel, RigmScriptTextModel, RigmMovieModel, RigmMovieComposition;
{$R *.dfm}
const ImageKeys: array[0..2] of string = ('representative','endImage','thumbnailImage');
const ChoiceKeys: array[0..2] of string = ('representativeChoice','endChoice','thumbnailChoice');
const ImageCaptions: array[0..2] of string = ('締めの代表画像','終了画像','最後のサムネイル');
const ImageLabels: array[0..2] of string = ('締めの代表画像（セリフと一緒に表示）','終了画像（締めの後に表示）','最後のサムネイル（動画の末尾に表示）');
const AdoptHints: array[0..2] of string = ('締めの代表画像を採用','終了画像を採用','サムネイルを採用');
constructor TRigmScriptClosingPreview.CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace; Mode: TComboBox);
begin inherited Create(AOwner); FWorkspace := W; FMode := Mode; DoubleBuffered := True; end;
procedure TRigmScriptClosingPreview.Paint;
  procedure Message(const Text: string);
  begin
    Canvas.Font.Assign(Font); Canvas.Font.Color := clSilver; Canvas.Brush.Style := bsClear;
    var R := ClientRect; InflateRect(R,-ScaleValue(16),-ScaleValue(16));
    DrawText(Canvas.Handle,PChar(Text),-1,R,DT_LEFT or DT_WORDBREAK or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect);
  if (FWorkspace.ScriptDraft=nil) or (ClientWidth<1) or (ClientHeight<1) then Exit;
  try var P := FWorkspace.ScriptDraft.Clone;
    try
      var D := JO(JO(P.ScriptWizard,'closingData'),'draft'); var Index := Max(0,FMode.ItemIndex);
      if JS(D,ChoiceKeys[Index])='' then begin Message(ImageCaptions[Index]+#13#10+'「画像を省略」または「既存画像を採用」を選んでください。'); Exit; end;
      if (JS(D,ChoiceKeys[Index])='use') and (JS(D,ImageKeys[Index])='') then begin Message(ImageCaptions[Index]+#13#10+'「画像を選ぶ」から表示する画像を選んでください。'); Exit; end;
      if (Index>0) and (JS(D,ChoiceKeys[Index])='none') then begin Message(ImageCaptions[Index]+'は省略します。'); Exit; end;
      // 未選択の別画像はプレビュー用コピーだけで省略し、現在の画像を確認できるようにする。
      for var Key in ChoiceKeys do if JS(D,Key)='' then PsdJson.Put(D,Key,'none');
      MaterializeScriptClosing(P); var ClosingScene := ScriptClosingScene(P); var Time := 0.1;
      if ClosingScene<>'' then Time := ScriptSceneStart(P,ClosingScene)+0.1
      else if FMode.ItemIndex=0 then begin
        // 配役前のプレビュー専用コピー。正本へシーンや無音セリフは追加しない。
        var Scene := TRigmMovieScene.Create; Scene.Title := ''; Scene.DisplayMode := 'none'; P.Scenes.Add(Scene);
        var Cue := TRigmMovieCue.Create; Cue.Scene := Scene.Id; Cue.Text := JS(ScriptSection(P,'closing'),'text'); Cue.Subtitle := Cue.Text; P.Cues.Add(Cue);
        var Card := TJSONObject.Create;
        Card.AddPair('title',JS(D,'title')); Card.AddPair('representativeChoice',JS(D,'representativeChoice')); Card.AddPair('image',JS(D,'representative'));
        PsdJson.Put(Scene.Animation,'closingCard',Card);
      end;
      P.EnableComposition;
      if FMode.ItemIndex>0 then begin var Kind := 'end'; if FMode.ItemIndex=2 then Kind := 'thumbnail'; var Found := False; Time := P.StoryDuration;
        for var V in P.EndCards do begin var Card := TJSONObject(V); if JS(Card,'kind')=Kind then begin Time := Time+0.1; Found := True; Break; end; Time := Time+JN(Card,'duration'); end;
        if not Found then raise Exception.Create('この画像は省略されています。');
      end;
      var B := RenderComposition(P,Time,nil); try var K := Min(ClientWidth/B.Width,ClientHeight/B.Height); var W := Round(B.Width*K); var H := Round(B.Height*K); var R := Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2); Canvas.StretchDraw(R,B);
      finally B.Free; end;
    finally P.Free; end;
  except on E: Exception do Message(E.Message); end;
end;
constructor TRigmScriptClosingFrame.CreateForWorkspace(AOwner: TComponent; W: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := W; FSync := True;
  var Actions := TPanel.Create(Self); Actions.Parent := Self; Actions.Align := alTop; Actions.Height := ScaleValue(48); Actions.ShowCaption := False; Actions.BevelOuter := bvNone;
  var Apply := TButton.Create(Self); Apply.Parent := Actions; Apply.Name := 'ScriptClosingDone'; Apply.Caption := '入力を反映'; Apply.SetBounds(ScaleValue(8),ScaleValue(4),ScaleValue(120),ScaleValue(34)); Apply.OnClick := Done;
  var Confirm := TButton.Create(Self); Confirm.Parent := Actions; Confirm.Name := 'ScriptClosingReady'; Confirm.Caption := '締めの設定を確認完了'; Confirm.SetBounds(ScaleValue(136),ScaleValue(4),ScaleValue(204),ScaleValue(34)); Confirm.OnClick := Ready;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Align := alBottom; FGuide.Height := ScaleValue(56); FGuide.Name := 'ScriptClosingGuide';
  FBody := TPanel.Create(Self); FBody.Parent := Self; FBody.Align := alClient; FBody.ShowCaption := False; FBody.BevelOuter := bvNone; FBody.Padding.SetBounds(ScaleValue(8),0,ScaleValue(8),ScaleValue(8));
  FSettings := TPanel.Create(Self); FSettings.Parent := FBody; FSettings.Align := alLeft; FSettings.ShowCaption := False; FSettings.BevelOuter := bvNone; FSettings.Padding.Right := ScaleValue(16); FSettings.Name := 'ScriptClosingSettings';
  FOptions := TPanel.Create(Self); FOptions.Parent := FSettings; FOptions.Align := alTop; FOptions.ShowCaption := False; FOptions.BevelOuter := bvNone;
  FTitleLabel := TRigmScriptLabel.Create(Self); FTitleLabel.Parent := FOptions; FTitleLabel.AutoSize := False; FTitleLabel.Caption := '締めに表示する題名'; FTitleLabel.Name := 'ScriptClosingTitleLabel';
  FTitle := TEdit.Create(Self); FTitle.Parent := FOptions; FTitle.Name := 'ScriptClosingTitle'; FTitle.MaxLength := 128; FTitle.TextHint := '空欄なら題名を表示しません'; FTitle.OnChange := Changed;
  for var I := 0 to 2 do begin
    // 固定幅の説明はAutoSizeを先に止め、空Captionで幅が縮むことを防ぐ。
    FImageLabels[I] := TRigmScriptLabel.Create(Self); FImageLabels[I].Parent := FOptions; FImageLabels[I].AutoSize := False; FImageLabels[I].Caption := ImageLabels[I]; FImageLabels[I].Name := 'ScriptClosingImageLabel'+I.ToString;
    FChoice[I] := TComboBox.Create(Self); FChoice[I].Parent := FOptions; FChoice[I].Style := csDropDownList; FChoice[I].Items.AddStrings(['画像を省略','既存画像を採用','採用・省略を選んでください']); FChoice[I].ItemIndex := 2; FChoice[I].Name := 'ScriptClosingChoice'+I.ToString; FChoice[I].OnChange := Changed;
    FAdopt[I] := TButton.Create(Self); FAdopt[I].Parent := FOptions; FAdopt[I].Caption := '画像を選ぶ'; FAdopt[I].Name := 'ScriptClosingAdopt'+I.ToString; FAdopt[I].Hint := AdoptHints[I]; FAdopt[I].ShowHint := True; FAdopt[I].Tag := I; FAdopt[I].OnClick := Adopt;
    FPaths[I] := TRigmScriptLabel.Create(Self); FPaths[I].Parent := FOptions; FPaths[I].AutoSize := False; FPaths[I].EllipsisPosition := epPathEllipsis; FPaths[I].Name := 'ScriptClosingPath'+I.ToString; FPaths[I].ShowHint := True;
  end;
  var Speech := TPanel.Create(Self); Speech.Parent := FSettings; Speech.Align := alClient; Speech.ShowCaption := False; Speech.BevelOuter := bvNone;
  var SpeechLabel := TRigmScriptLabel.Create(Self); SpeechLabel.Parent := Speech; SpeechLabel.AutoSize := False; SpeechLabel.Align := alTop; SpeechLabel.Height := ScaleValue(30); SpeechLabel.Caption := '締めのセリフ（空欄なら発話なし）'; SpeechLabel.Name := 'ScriptClosingSpeechLabel';
  FSpeech := TMemo.Create(Self); FSpeech.Parent := Speech; FSpeech.Align := alClient; FSpeech.ReadOnly := False; FSpeech.Font.Size := 12; FSpeech.ScrollBars := ssVertical; FSpeech.Name := 'ScriptClosingSpeech'; FSpeech.MaxLength := ScriptSectionLimit; FSpeech.OnChange := SpeechChanged;
  FPreviewColumn := TPanel.Create(Self); FPreviewColumn.Parent := FBody; FPreviewColumn.Align := alClient; FPreviewColumn.ShowCaption := False; FPreviewColumn.BevelOuter := bvNone;
  var PreviewLabel := TRigmScriptLabel.Create(Self); PreviewLabel.Parent := FPreviewColumn; PreviewLabel.AutoSize := False; PreviewLabel.Align := alTop; PreviewLabel.Height := ScaleValue(26); PreviewLabel.Caption := 'プレビュー'; PreviewLabel.Name := 'ScriptClosingPreviewLabel';
  FMode := TComboBox.Create(Self); FMode.Parent := FPreviewColumn; FMode.Top := ScaleValue(26); FMode.Align := alTop; FMode.Style := csDropDownList; FMode.Items.AddStrings(['締め（セリフ・題名・代表画像）','終了画像','最後のサムネイル']); FMode.ItemIndex := 0; FMode.Name := 'ScriptClosingPreviewMode'; FMode.OnChange := ModeChanged;
  FPreview := TRigmScriptClosingPreview.CreateForWorkspace(Self,W,FMode); FPreview.Parent := FPreviewColumn; FPreview.Align := alClient; FPreview.Name := 'ScriptClosingPreview';
  FChoice[2].Visible := False; FAdopt[2].Visible := False; FImageLabels[2].Visible := False; FPaths[2].Visible := False;
  FMode.Items.Delete(2);
  LayoutControls; FSync := False;
end;
procedure TRigmScriptClosingFrame.LayoutControls;
begin
  if FPreview=nil then Exit;
  FSettings.Width := Min(ScaleValue(560),Max(ScaleValue(390),Round(FBody.ClientWidth*0.46)));
  var W := Max(0,FOptions.ClientWidth); var Gap := ScaleValue(8); var ButtonW := ScaleValue(116);
  FOptions.Height := ScaleValue(278);
  FTitleLabel.SetBounds(0,0,W,ScaleValue(24)); FTitle.SetBounds(0,ScaleValue(26),W,ScaleValue(30));
  for var I := 0 to 2 do begin
    var Y := ScaleValue(70+I*100); FImageLabels[I].SetBounds(0,Y,W,ScaleValue(24));
    FChoice[I].SetBounds(0,Y+ScaleValue(26),Max(0,W-ButtonW-Gap),ScaleValue(32));
    FAdopt[I].SetBounds(Max(0,W-ButtonW),Y+ScaleValue(26),ButtonW,ScaleValue(32));
    FPaths[I].SetBounds(0,Y+ScaleValue(64),W,ScaleValue(28));
  end;
end;
procedure TRigmScriptClosingFrame.Resize;
begin inherited; LayoutControls; end;
function TRigmScriptClosingFrame.Draft: TJSONObject;
begin
  // 秒数・配置・回避領域は既存作品の値を保持し、この画面の編集対象にしない。
  Result := JO(JO(FWorkspace.ScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject; PsdJson.Put(Result,'title',FTitle.Text);
  for var I := 0 to 1 do begin var Choice := ''; if FChoice[I].ItemIndex=0 then Choice := 'none' else if FChoice[I].ItemIndex=1 then Choice := 'use'; PsdJson.Put(Result,ChoiceKeys[I],Choice); end;
end;
procedure TRigmScriptClosingFrame.Changed(Sender: TObject);
begin if FSync then Exit; FEditing := True; FWorkspace.BeginScriptTextEdit; var D := Draft; try try FWorkspace.SetScriptClosingDraft(D); except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end; end;
function TRigmScriptClosingFrame.RequestFinish: Boolean;
begin if not FEditing then Exit(True); Result := False; var D := Draft; try try FWorkspace.SetScriptClosingDraft(D); Result := True; except on E: Exception do FGuide.Caption := E.Message; end; finally D.Free; end; if Result then begin FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState; end; end;
procedure TRigmScriptClosingFrame.Done(Sender: TObject);
begin RequestFinish; end;
procedure TRigmScriptClosingFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteScriptClosing; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptClosingFrame.Adopt(Sender: TObject);
begin if not RequestFinish then Exit; var Dialog := TOpenDialog.Create(Self); try Dialog.Title := AdoptHints[TButton(Sender).Tag]; Dialog.Filter := '既存画像|*.png;*.jpg;*.jpeg;*.bmp'; if Dialog.Execute then try FWorkspace.AdoptScriptClosingImage(ImageKeys[TButton(Sender).Tag],Dialog.FileName); except on E: Exception do FGuide.Caption := E.Message; end; finally Dialog.Free; end; end;
procedure TRigmScriptClosingFrame.ModeChanged(Sender: TObject);
begin FPreview.Invalidate; end;
procedure TRigmScriptClosingFrame.SpeechChanged(Sender: TObject);
begin
  if FSync then Exit;
  try FWorkspace.SetScriptText('closing',FSpeech.Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptClosingFrame.RefreshState;
begin
  if (FWorkspace.ScriptDraft=nil) or not(FWorkspace.ScriptDraft.ScriptWizard.GetValue('closingData') is TJSONObject) then Exit; var P := FWorkspace.ScriptDraft; var D := JO(JO(P.ScriptWizard,'closingData'),'draft'); FSync := True;
  try if not FEditing then begin
    FTitle.Text := JS(D,'title');
    for var I := 0 to 2 do begin FChoice[I].ItemIndex := 2; if JS(D,ChoiceKeys[I])='none' then FChoice[I].ItemIndex := 0 else if JS(D,ChoiceKeys[I])='use' then FChoice[I].ItemIndex := 1; end;
    var Speech := JS(ScriptSection(P,'closing'),'text'); if NormalizeScriptText(FSpeech.Text)<>Speech then FSpeech.Text := Speech;
  end;
  for var I := 0 to 2 do begin
    var Path := JS(D,ImageKeys[I]); FPaths[I].Hint := Path;
    if JS(D,ChoiceKeys[I])='none' then FPaths[I].Caption := 'この画像は表示しません。'
    else if Path<>'' then FPaths[I].Caption := '画像を選択済み（プレビューで確認できます）'
    else if JS(D,ChoiceKeys[I])='use' then FPaths[I].Caption := '「画像を選ぶ」から画像を指定してください。'
    else FPaths[I].Caption := '採用するか、省略するかを選んでください。';
  end;
  FGuide.Caption := '締めの代表・終了画像を選び、設定を確認完了してください。必須サムネイルは第16段階の最後に作成します。'; FPreview.Invalidate;
  finally FSync := False; end;
end;
end.
