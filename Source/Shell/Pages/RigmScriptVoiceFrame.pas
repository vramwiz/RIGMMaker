unit RigmScriptVoiceFrame;
// 選択セリフのVOICEVOX調整・感情・試聴に集中する。原稿・字幕・人物は前工程で編集する。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  RigmWizardWorkspace, SerifVoicevoxSettingsFrame, RigmVoiceConnection, RigmBufferedControls;
type
  TRigmScriptVoiceFrame = class(TRigmBufferedFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing,FActive: Boolean;
    FList: TListView; FState: TComboBox; FConnectionRow: TPanel; FLocate: TButton; FConnectionNotice: TLabel;
    FStateIndices: TArray<Integer>; // 選択セリフの人物が持つ状態だけを示す索引。
    FShownReady: Boolean;
    FSettings: TFrameSerifVoicevoxSettings;
    FConnection: TRigmVoiceConnection;
    FShownSource,FShownAudio,FShownCue,FQueryError: string;
    FContinuousButton: TButton;
    FActor,FGuide: TLabel; FReadyButton,FCancelButton: TButton;
    procedure QueryChanged(Sender: TObject; const QueryJson: string);
    procedure QueryError(Sender: TObject; const MessageText: string);
    procedure Continuous(Sender: TObject);
    procedure LocateEngine(Sender: TObject);
    procedure ConnectionChanged(Sender: TObject);
    procedure QueryReady(Sender: TObject);
    procedure ShowDetails;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Changed(Sender: TObject);
    procedure Complete(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure StateChanged(Sender: TObject);
    procedure Preview(Sender: TObject);
    procedure Cancel(Sender: TObject);
    function ApplyCurrent: Boolean;
    function SelectedId: string;
    function Number: Integer;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean; // 未確定の数値を失わず、離脱を止める。
  end;
implementation
uses System.SysUtils, System.JSON, System.Generics.Collections, SerifVoicevoxAudioSettings, Winapi.Windows, RigmJson, RigmMovieModel, RigmScriptCastingModel, RigmScriptVoiceSelection;
{$R *.dfm}
const ValueKeys: array[0..5] of string = ('speedScale','pitchScale','intonationScale','volumeScale','prePhonemeLength','postPhonemeLength');
constructor TRigmScriptVoiceFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; Align := alClient; DoubleBuffered := True;
  var Footer := TRigmBufferedPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 38; Footer.Caption := ''; Footer.BevelOuter := bvNone;
  FReadyButton := TButton.Create(Self); FReadyButton.Parent := Footer; FReadyButton.Align := alRight; FReadyButton.Width := 190; FReadyButton.Caption := '全セリフの音声確認完了'; FReadyButton.Name := 'ScriptVoiceReady'; FReadyButton.OnClick := Ready;
  FCancelButton := TButton.Create(Self); FCancelButton.Parent := Footer; FCancelButton.Align := alRight; FCancelButton.Width := 96; FCancelButton.Caption := '停止・取消'; FCancelButton.Name := 'ScriptVoiceCancel'; FCancelButton.OnClick := Cancel; FCancelButton.Visible := False;
  FGuide := TLabel.Create(Self); FGuide.Parent := Footer; FGuide.Align := alClient; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Name := 'ScriptVoiceGuide';
  var RowsPanel := TRigmBufferedPanel.Create(Self); RowsPanel.Parent := Self; RowsPanel.Align := alLeft; RowsPanel.Width := 300; RowsPanel.Caption := ''; RowsPanel.BevelOuter := bvNone;
  FContinuousButton := TButton.Create(Self); FContinuousButton.Parent := RowsPanel; FContinuousButton.Align := alBottom; FContinuousButton.Height := 38; FContinuousButton.Caption := '連続再生 (Shift+F5)'; FContinuousButton.Name := 'ScriptVoiceContinuous'; FContinuousButton.OnClick := Continuous;
  FList := TRigmBufferedListView.Create(Self); FList.Parent := RowsPanel; FList.Align := alClient; FList.ViewStyle := vsReport; FList.RowSelect := True; FList.ReadOnly := True;
  FList.HideSelection := False; FList.Name := 'ScriptVoiceRows'; FList.OnSelectItem := Selected; FList.OnKeyDown := Key;
  FList.ParentDoubleBuffered := False; FList.DoubleBuffered := False;
  FList.Columns.Add.Caption := '状態'; FList.Columns[0].Width := 112; FList.Columns.Add.Caption := '読み'; FList.Columns[1].Width := 178;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TRigmBufferedPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.Caption := ''; Body.BevelOuter := bvNone; Body.Padding.SetBounds(8,4,8,4);
  FActor := TLabel.Create(Self); FActor.Parent := Body; FActor.Align := alTop; FActor.AutoSize := False; FActor.Height := 34; FActor.Name := 'ScriptVoiceActor';
  FConnectionRow := TRigmBufferedPanel.Create(Self); FConnectionRow.Parent := Body; FConnectionRow.Align := alTop; FConnectionRow.Height := 32; FConnectionRow.Caption := ''; FConnectionRow.BevelOuter := bvNone;
  FLocate := TButton.Create(Self); FLocate.Parent := FConnectionRow; FLocate.Align := alRight; FLocate.Width := 180; FLocate.Caption := 'VOICEVOXを手動設定'; FLocate.Name := 'ScriptVoiceLocateEngine'; FLocate.OnClick := LocateEngine; FLocate.Visible := False;
  FConnectionNotice := TLabel.Create(Self); FConnectionNotice.Parent := FConnectionRow; FConnectionNotice.Align := alClient; FConnectionNotice.AutoSize := False; FConnectionNotice.WordWrap := True;
  var StateRow := TRigmBufferedPanel.Create(Self); StateRow.Parent := Body; StateRow.Align := alTop; StateRow.Height := 34; StateRow.Caption := ''; StateRow.BevelOuter := bvNone;
  var StateLabel := TLabel.Create(Self); StateLabel.Parent := StateRow; StateLabel.Align := alLeft; StateLabel.Width := 150; StateLabel.AutoSize := False; StateLabel.Caption := '感情'; StateLabel.Name := 'ScriptVoiceEmotionLabel';
  FState := TComboBox.Create(Self); FState.Parent := StateRow; FState.Align := alClient; FState.Style := csDropDownList; FState.Name := 'ScriptVoiceState'; FState.OnChange := StateChanged;
  FSettings := TFrameSerifVoicevoxSettings.Create(Self); FSettings.Parent := Body; FSettings.Align := alClient; FSettings.Name := 'ScriptVoiceDetails'; FSettings.UseAdjustmentOnly;
  FSettings.OnQueryReady := QueryReady; FSettings.OnAudioChange := Changed; FSettings.OnAccentChange := QueryChanged; FSettings.OnError := QueryError; FSettings.OnPreview := Preview;
  FActor.Top := 0; FConnectionRow.Top := 34; StateRow.Top := 66;
  FConnection := TRigmVoiceConnection.CreateForWorkspace(Self,FWorkspace); FConnection.OnChanged := ConnectionChanged;
end;
destructor TRigmScriptVoiceFrame.Destroy;
begin FConnection.SetActive(False); if FWorkspace<>nil then FWorkspace.SetVoiceAutoGeneration(False); inherited; end;
function TRigmScriptVoiceFrame.SelectedId: string;
begin Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'voice'),'selectedCue'); end;
function TRigmScriptVoiceFrame.Number: Integer;
begin Result := ScriptCueRole(FWorkspace.ScriptDraft,SelectedId); end;
function TRigmScriptVoiceFrame.ApplyCurrent: Boolean;
begin
  Result := False; var O := TJSONObject.Create;
  try
    var V := FSettings.RowValues;
    AddN(O,'speedScale',V.SpeedScale); AddN(O,'pitchScale',V.PitchScale); AddN(O,'intonationScale',V.IntonationScale);
    AddN(O,'volumeScale',V.VolumeScale); AddN(O,'prePhonemeLength',V.PrePhonemeLength); AddN(O,'postPhonemeLength',V.PostPhonemeLength);
    ValidateVoiceValues(O);
    var C := FWorkspace.ScriptDraft.Cue(SelectedId); var S := FWorkspace.ScriptDraft.Speaker(C.SpeakerId);
    var Defaults: array[0..5] of Double; Defaults[0] := S.Speed; Defaults[1] := S.Pitch; Defaults[2] := S.Intonation; Defaults[3] := S.Volume; Defaults[4] := 0.1; Defaults[5] := 0.1;
    var Different := False;
    for var I := 0 to 5 do if JN(O,ValueKeys[I])<>JN(C.VoiceSettings,ValueKeys[I],Defaults[I]) then Different := True;
    if Different then FWorkspace.EditVoice(SelectedId,C.VoiceReading,O); Result := True;
  except on E: Exception do FGuide.Caption := E.Message; end;
  O.Free;
end;
procedure TRigmScriptVoiceFrame.Changed(Sender: TObject);
begin if FSync or not FEditing then Exit; FWorkspace.BeginScriptTextEdit; if ApplyCurrent then ShowDetails; end;
function TRigmScriptVoiceFrame.RequestFinish: Boolean;
begin
  if FEditing and not FSettings.RequestFinish then begin FGuide.Caption := '調整中の数値を確認してください。'; Exit(False); end;
  Result := not FEditing or ApplyCurrent; if not Result then Exit;
  FWorkspace.EndScriptTextEdit; RefreshState;
end;
procedure TRigmScriptVoiceFrame.Complete(Sender: TObject);
begin if RequestFinish then FGuide.Caption := '入力を保存しました。↑↓で移動、F5で生成・試聴できます。'; end;
procedure TRigmScriptVoiceFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteVoice; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  if FSync or not Value then Exit; var Id := Item.SubItems[1];
  if not RequestFinish then begin FSync := True; try for var Entry in FList.Items do Entry.Selected := Entry.SubItems[1]=SelectedId; finally FSync := False; end; Exit; end;
  FWorkspace.SelectVoice(Id); RefreshState;
end;
procedure TRigmScriptVoiceFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key=VK_F5 then begin if ssShift in Shift then Continuous(Self) else Preview(Self); Key := 0; end
  else if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Complete(Self); Key := 0; end
  else if (Key=VK_UP) or (Key=VK_DOWN) then begin if RequestFinish then if Key=VK_UP then FWorkspace.MoveVoice(-1) else FWorkspace.MoveVoice(1); Key := 0; end;
end;
procedure TRigmScriptVoiceFrame.StateChanged(Sender: TObject);
begin
  if FSync or (FState.ItemIndex<0) or (FState.ItemIndex>=Length(FStateIndices)) then Exit; var Index := FStateIndices[FState.ItemIndex];
  if not RequestFinish then Exit;
  try FWorkspace.SetVoiceState(SelectedId,JI(TJSONObject(FWorkspace.VoiceCatalog[Index]),'styleId',-1)); except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptVoiceFrame.Preview(Sender: TObject);
begin if GetKeyState(VK_SHIFT)<0 then begin Continuous(Self); Exit; end; if FWorkspace.VoicePlaying or FWorkspace.VoiceContinuous then begin Cancel(Self); Exit; end; if not RequestFinish then Exit; try FWorkspace.GenerateVoice(SelectedId,True); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Cancel(Sender: TObject);
begin FWorkspace.CancelVoice; RefreshState; end;
procedure TRigmScriptVoiceFrame.SetActive(Value: Boolean);
begin
  if FActive=Value then Exit;
  if not Value and FActive then begin FWorkspace.StopVoice; FSettings.ShowRow('','',-1,TSerifVoicevoxAudioValues.Defaults,'',''); FShownSource := ''; FShownAudio := ''; end;
  FActive := Value; FEditing := Value; FConnection.SetActive(Value); FWorkspace.SetVoiceAutoGeneration(Value);
end;
procedure TRigmScriptVoiceFrame.ShowDetails;
begin
  var P := FWorkspace.ScriptDraft; var C := P.Cue(SelectedId); if C=nil then Exit;
  var Source := P.VoiceQuerySourceKey(C); var Audio := P.AudioFingerprint(C);
  var Ready := FWorkspace.VoiceCatalogReady;
  if (FShownSource=Source) and (FShownCue=C.Id) and (FShownReady=Ready) and (FWorkspace.ScriptTextEditing or (FShownAudio=Audio)) then Exit;
  var S := P.Speaker(C.SpeakerId); var V := TSerifVoicevoxAudioValues.Defaults;
  V.SpeedScale := JN(C.VoiceSettings,'speedScale',S.Speed); V.PitchScale := JN(C.VoiceSettings,'pitchScale',S.Pitch);
  V.IntonationScale := JN(C.VoiceSettings,'intonationScale',S.Intonation); V.VolumeScale := JN(C.VoiceSettings,'volumeScale',S.Volume);
  V.PrePhonemeLength := JN(C.VoiceSettings,'prePhonemeLength',0.1); V.PostPhonemeLength := JN(C.VoiceSettings,'postPhonemeLength',0.1);
  var WasSync := FSync; FSync := True;
  try
    FQueryError := ''; var Style := P.EffectiveStyle(C); var Query := P.EffectiveVoiceQuery(C);
    if not Ready and (Query='') then Style := -1;
    FSettings.ShowRow(C.SpokenText,S.VoiceUuid,Style,V,Query,P.EngineUrl);
    FShownSource := Source; FShownAudio := Audio; FShownCue := C.Id; FShownReady := Ready;
  finally FSync := WasSync; end;
end;
procedure TRigmScriptVoiceFrame.QueryChanged(Sender: TObject; const QueryJson: string);
begin
  if FSync or not FEditing or not FActive then Exit;
  var C := FWorkspace.ScriptDraft.Cue(SelectedId);
  if (C=nil) or (FShownCue<>C.Id) or (FShownSource<>FWorkspace.ScriptDraft.VoiceQuerySourceKey(C)) then Exit;
  try FWorkspace.BeginScriptTextEdit; FWorkspace.EditVoiceQuery(C.Id,QueryJson); FShownAudio := FWorkspace.ScriptDraft.AudioFingerprint(C);
  except on E: Exception do begin FQueryError := E.Message; FGuide.Caption := E.Message; end; end;
end;
procedure TRigmScriptVoiceFrame.QueryError(Sender: TObject; const MessageText: string);
begin if not FActive then Exit; FQueryError := MessageText; RefreshState; end;
procedure TRigmScriptVoiceFrame.Continuous(Sender: TObject);
begin
  if FWorkspace.VoiceContinuous then begin Cancel(Self); Exit; end;
  if not RequestFinish then Exit;
  try FWorkspace.StartVoiceContinuous(SelectedId); except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptVoiceFrame.LocateEngine(Sender: TObject);
begin if not RequestFinish then Exit; FConnection.Locate; end;
procedure TRigmScriptVoiceFrame.ConnectionChanged(Sender: TObject);
begin RefreshState; end;
procedure TRigmScriptVoiceFrame.QueryReady(Sender: TObject);
begin if not FActive then Exit; FQueryError := ''; RefreshState; end;
procedure TRigmScriptVoiceFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('voice')=nil) then Exit; var Id := SelectedId; var C := P.Cue(Id); if C=nil then Exit;
  var Rebuild := FList.Items.Count<>P.Cues.Count;
  if not Rebuild then for var I := 0 to P.Cues.Count-1 do
    if (FList.Items[I].SubItems.Count<>2) or (FList.Items[I].SubItems[1]<>P.Cues[I].Id) then begin Rebuild := True; Break; end;
  var SelectionChanged := (FList.Selected=nil) or (FList.Selected.SubItems[1]<>Id);
  // 更新のたびに全行を消さない。構成が変わった時だけ一覧全体の描画を止める。
  FSync := True; if Rebuild then FList.Items.BeginUpdate;
  try
    if Rebuild then FList.Items.Clear;
    for var I := 0 to P.Cues.Count-1 do begin
      var Cue := P.Cues[I]; var Item: TListItem;
      if Rebuild then begin Item := FList.Items.Add; Item.SubItems.Add(''); Item.SubItems.Add(Cue.Id); end else Item := FList.Items[I];
      var Status := '未生成'; if P.AudioHeard(Cue) then Status := '再生済' else if P.AudioReady(Cue) then Status := '未再生' else if P.HasStoredAudio(Cue) then Status := '旧音声';
      if FWorkspace.VoiceContinuous and (Cue.Id=Id) then Status := '▶連続再生';
      if Item.Caption<>Status then Item.Caption := Status;
      if Item.SubItems[0]<>Cue.SpokenText then Item.SubItems[0] := Cue.SpokenText;
      if Item.Selected<>(Cue.Id=Id) then Item.Selected := Cue.Id=Id;
    end;
    if (Rebuild or SelectionChanged) and (FList.Selected<>nil) then FList.Selected.MakeVisible(False);
    var S := P.Speaker(C.SpeakerId); var Actor := JS(CastingRole(P,Number),'name')+' / 声：';
    if (S.StyleId>=0) and (S.VoiceUuid<>'') then Actor := Actor+S.VoiceName else Actor := Actor+'未割当';
    if FActor.Caption<>Actor then FActor.Caption := Actor;
    FStateIndices := VoiceStateIndices(FWorkspace.VoiceCatalog,S.VoiceUuid);
    var ReplaceChoices := FState.Items.Count<>Length(FStateIndices);
    if not ReplaceChoices then for var I := 0 to High(FStateIndices) do
      if FState.Items[I]<>JS(TJSONObject(FWorkspace.VoiceCatalog[FStateIndices[I]]),'style') then begin ReplaceChoices := True; Break; end;
    if ReplaceChoices then begin
      FState.Items.BeginUpdate;
      try FState.Items.Clear; for var Index in FStateIndices do FState.Items.Add(JS(TJSONObject(FWorkspace.VoiceCatalog[Index]),'style'));
      finally FState.Items.EndUpdate; end;
    end;
    var SelectedEmotion := -1;
    for var I := 0 to High(FStateIndices) do begin var O := TJSONObject(FWorkspace.VoiceCatalog[FStateIndices[I]]);
      if JI(O,'styleId',-1)=P.EffectiveStyle(C) then SelectedEmotion := I;
    end;
    if FState.ItemIndex<>SelectedEmotion then FState.ItemIndex := SelectedEmotion;
    ShowDetails;
    var CanEdit := FActive and FWorkspace.VoiceCatalogReady and not FWorkspace.VoiceBusy and not FWorkspace.VoiceContinuous and not FWorkspace.VoicePlaying;
    FSettings.SetEditingEnabled(CanEdit); FState.Enabled := CanEdit and (Length(FStateIndices)>0);
    FConnectionRow.Visible := not FWorkspace.VoiceCatalogReady;
    FLocate.Visible := FConnection.NeedsLocate and not FWorkspace.VoiceBusy;
    var ConnectionNotice := 'VOICEVOXを確認しています。';
    if FConnection.NeedsLocate and not FWorkspace.VoiceBusy then ConnectionNotice := 'VOICEVOXを確認できません。実行ファイルを指定してください。';
    if FConnectionNotice.Caption<>ConnectionNotice then FConnectionNotice.Caption := ConnectionNotice;
    FReadyButton.Enabled := not FWorkspace.VoiceBusy and not FWorkspace.VoicePlaying and not FWorkspace.VoiceContinuous;
    FCancelButton.Visible := FWorkspace.VoiceBusy or FWorkspace.VoicePlaying or FWorkspace.VoiceContinuous;
    FSettings.SetPreviewActive(FWorkspace.VoicePlaying or FWorkspace.VoiceContinuous);
    if FWorkspace.VoiceContinuous then FContinuousButton.Caption := '連続再生を停止' else FContinuousButton.Caption := '連続再生 (Shift+F5)';
    FContinuousButton.Enabled := FWorkspace.VoiceContinuous or not FWorkspace.VoiceBusy;
    var State := FWorkspace.VoiceStatus;
    try
      var Notice := '';
      if FWorkspace.VoiceBusy then Notice := 'VOICEVOX処理中です。接続・話者一覧取得や音声生成の終了をお待ちください。'
      else if JS(State,'error')<>'' then Notice := JS(State,'error')
      else if not FWorkspace.VoiceCatalogReady then Notice := ''
      else if (S.VoiceUuid='') or (S.StyleId<0) then Notice := '配役画面で声の人物を選択してください。'
      else if FState.ItemIndex<0 then Notice := 'このセリフの感情が現在の一覧にありません。選択した人物の感情を選び直してください。'
      else if FQueryError<>'' then Notice := 'アクセントを解析できませんでした: '+FQueryError
      else if C.SpokenText='' then Notice := 'この行には音声用の読みがありません。'
      else if not FSettings.HasQuery then Notice := '選択した声でアクセントを解析中です。'
      else Notice := '';
      FSettings.ShowNotice(Notice);
      var Guide := '↑↓：行ごとに生成 / F5：試聴 / Shift+F5：連続再生　再生済み '+JI(State,'heard').ToString+' / '+P.Cues.Count.ToString;
      if FWorkspace.VoiceContinuous then Guide := Guide+'　連続 '+JI(State,'sequenceIndex').ToString+' / '+JI(State,'sequenceTotal').ToString+' ('+JS(State,'sequencePhase')+')'
      else if JS(State,'sequenceStatus')<>'' then Guide := Guide+'　'+JS(State,'sequenceStatus');
      if FWorkspace.VoiceBusy then Guide := Guide+'　処理中（取消可）'; if JS(State,'error')<>'' then Guide := Guide+#13#10+JS(State,'error');
      if not FWorkspace.VoiceBusy and not FWorkspace.VoicePlaying and not FWorkspace.VoiceContinuous and (JI(State,'heard')=P.Cues.Count) then
        Guide := Guide+#13#10+'全行を最後まで再生しました。上部Next（チェック）で音声エフェクトへ進めます。';
      if FGuide.Caption<>Guide then FGuide.Caption := Guide;
    finally State.Free; end;
  finally if Rebuild then FList.Items.EndUpdate; FSync := False; end;
end;
end.
