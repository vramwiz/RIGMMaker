unit RigmScriptVoiceEffectsFrame;
// Aul2 controller widgets and async per-cue audition, preserving original WAV files.
interface
uses System.Classes, System.Generics.Collections, Winapi.Messages, RigmScriptPageFrame,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Buttons, RigmBufferedControls,
  RigmWizardWorkspace, RigmAul2EffectDefinition, RigmAul2VolumeControl, RigmAul2LampSwitch,
  RigmVoiceEffectsPreview;
type
  TRigmScriptVoiceEffectsFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FList: TListView; FSync,FActive,FLoop,FWantPlay: Boolean;
    FEffect,FMode: TComboBox; FLamp: TAul2LampSwitch; FKnobs: TScrollBox;
    FVolumes: TArray<TAul2VolumeControl>; FDefinition: TControllerEffectDefinition;
    FNotice: TLabel; FPlay,FLoopPlay,FStop: TSpeedButton; FTimer: TTimer;
    FJob: TRigmVoiceEffectsPreviewJob; FRetired: TObjectList<TRigmVoiceEffectsPreviewJob>;
    FProjectId,FSelectedCue,FShownSettings,FPlaybackAlias,FPlaybackKey,FVoiceSourceKey,FReadyKey,FReadyPath: string; FRenderDue: UInt64;
    function SelectedId: string;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Resized(Sender: TObject);
    procedure EffectChanged(Sender: TObject);
    procedure ParameterChanged(Sender: TObject);
    procedure VolumeChanged(Sender: TObject; const ValueText: string; var Accept: Boolean);
    procedure CommitParameters(ChangedControl: TAul2VolumeControl=nil; const NewText: string='');
    procedure ShowParameters;
    procedure Play(Sender: TObject);
    procedure Stop(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure EnsurePreview;
    procedure OpenPlayback(const Path,Key: string);
    procedure ClosePlayback;
    procedure RetireJob;
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    procedure StopPreview;
  end;
implementation
uses System.SysUtils, System.Math, System.JSON, System.IOUtils, Winapi.Windows,
  Winapi.MMSystem, RigmJson, PsdJson, RigmMovieModel, RigmVoiceEffects, RigmVoiceEffectSettings;
{$R *.dfm}
procedure EffectMci(const Command: string);
begin
  var E := mciSendString(PChar(Command),nil,0,0);
  if E<>0 then begin var B: array[0..255] of Char; mciGetErrorString(E,B,Length(B)); raise Exception.Create(string(B)); end;
end;
constructor TRigmScriptVoiceEffectsFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FRetired := TObjectList<TRigmVoiceEffectsPreviewJob>.Create(True);
  var Guide := TRigmScriptLabel.Create(Self); Guide.Parent := Self; Guide.Align := alTop;
  Guide.AutoSize := False; Guide.Height := ScaleValue(58); Guide.WordWrap := True; Guide.Name := 'ScriptVoiceEffectsGuide';
  Guide.Caption := 'セリフ1行ごとの音声エフェクト'+#13#10+'ON/OFFランプ・ノブで調整します。原音声を保持し、再生中の変更は次のループから反映します。';
  var Rows := TRigmBufferedPanel.Create(Self); Rows.Parent := Self; Rows.Align := alLeft; Rows.Width := ScaleValue(310); Rows.BevelOuter := bvNone; Rows.Caption := '';
  FList := TRigmBufferedListView.Create(Self); FList.Parent := Rows; FList.Align := alClient;
  FList.Name := 'ScriptVoiceEffectsRows'; FList.ViewStyle := vsReport; FList.RowSelect := True; FList.ReadOnly := True;
  FList.HideSelection := False; FList.OnSelectItem := Selected;
  FList.Columns.Add.Caption := 'セリフ'; FList.Columns[0].Width := ScaleValue(214);
  FList.Columns.Add.Caption := 'エフェクト'; FList.Columns[1].Width := ScaleValue(84);
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TRigmBufferedPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.BevelOuter := bvNone; Body.Caption := '';
  var Controls := TRigmBufferedPanel.Create(Self); Controls.Parent := Body; Controls.Align := alTop; Controls.Height := ScaleValue(40); Controls.Caption := ''; Controls.BevelOuter := bvNone;
  FPlay := TSpeedButton.Create(Self); FPlay.Parent := Controls; FPlay.Align := alLeft; FPlay.Width := ScaleValue(104); FPlay.Caption := '▶ 再生'; FPlay.Name := 'ScriptEffectsPlay'; FPlay.OnClick := Play;
  FLoopPlay := TSpeedButton.Create(Self); FLoopPlay.Parent := Controls; FLoopPlay.Align := alLeft; FLoopPlay.Width := ScaleValue(138); FLoopPlay.Caption := '⟳ ループ再生'; FLoopPlay.Name := 'ScriptEffectsLoop'; FLoopPlay.OnClick := Play;
  FStop := TSpeedButton.Create(Self); FStop.Parent := Controls; FStop.Align := alLeft; FStop.Width := ScaleValue(104); FStop.Caption := '■ 停止'; FStop.Name := 'ScriptEffectsStop'; FStop.OnClick := Stop;
  FPlay.Left := 0; FLoopPlay.Left := FPlay.Width; FStop.Left := FPlay.Width+FLoopPlay.Width;
  var Choice := TRigmBufferedPanel.Create(Self); Choice.Parent := Body; Choice.Align := alTop; Choice.Height := ScaleValue(40); Choice.Caption := ''; Choice.BevelOuter := bvNone;
  FEffect := TComboBox.Create(Self); FEffect.Parent := Choice; FEffect.Align := alLeft; FEffect.Width := ScaleValue(210); FEffect.Style := csDropDownList; FEffect.Name := 'ScriptEffectKind'; FEffect.OnChange := EffectChanged;
  for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D); FEffect.Items.Add(D.DisplayName); end;
  FEffect.ItemIndex := 0;
  FLamp := TAul2LampSwitch.Create(Self); FLamp.Parent := Choice; FLamp.Align := alLeft; FLamp.Width := ScaleValue(154); FLamp.Name := 'ScriptEffectOn'; FLamp.OnClick := ParameterChanged;
  FMode := TComboBox.Create(Self); FMode.Parent := Choice; FMode.Align := alClient; FMode.Style := csDropDownList; FMode.Name := 'ScriptEffectMode'; FMode.OnChange := ParameterChanged;
  FEffect.Left := 0; FLamp.Left := FEffect.Width; FMode.Left := FEffect.Width+FLamp.Width;
  FNotice := TRigmScriptLabel.Create(Self); FNotice.Parent := Body; FNotice.Align := alBottom; FNotice.Height := ScaleValue(68); FNotice.AutoSize := False; FNotice.WordWrap := True; FNotice.Name := 'ScriptEffectsStatus';
  FKnobs := TScrollBox.Create(Self); FKnobs.Parent := Body; FKnobs.Align := alClient; FKnobs.BorderStyle := bsNone;
  FKnobs.HorzScrollBar.Visible := False; FKnobs.VertScrollBar.Tracking := True;
  Controls.Top := 0; Choice.Top := Controls.Height;
  FTimer := TTimer.Create(Self); FTimer.Interval := 80; FTimer.OnTimer := Tick; FTimer.Enabled := False;
  OnResize := Resized;
end;
destructor TRigmScriptVoiceEffectsFrame.Destroy;
begin if FTimer<>nil then FTimer.Enabled := False; StopPreview; if FTimer<>nil then FTimer.Enabled := False; FreeAndNil(FRetired); inherited; end;
function TRigmScriptVoiceEffectsFrame.SelectedId: string;
begin Result := ''; if FWorkspace.ScriptDraft<>nil then Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue'); end;
procedure TRigmScriptVoiceEffectsFrame.CMShowingChanged(var Message: TMessage);
begin inherited; if not Showing then StopPreview; end;
procedure TRigmScriptVoiceEffectsFrame.SetActive(Value: Boolean);
begin FActive := Value; if not Value then StopPreview; FTimer.Enabled := Value or (FRetired.Count>0); if Value then RefreshState; end;
function TRigmScriptVoiceEffectsFrame.RequestFinish: Boolean;
begin
  Result := False;
  for var V in FVolumes do if not V.CommitPendingValue then begin FNotice.Caption := '数値を確認してから保存・Nextを実行してください。'; Exit; end;
  StopPreview; Result := True;
end;
procedure TRigmScriptVoiceEffectsFrame.RetireJob;
begin if FJob<>nil then begin FJob.Terminate; FRetired.Add(FJob); FJob := nil; FTimer.Enabled := True; end; end;
procedure TRigmScriptVoiceEffectsFrame.ClosePlayback;
begin
  if FPlaybackAlias<>'' then begin mciSendString(PChar('stop '+FPlaybackAlias),nil,0,0); mciSendString(PChar('close '+FPlaybackAlias),nil,0,0); end;
  FPlaybackAlias := ''; FPlaybackKey := '';
end;
procedure TRigmScriptVoiceEffectsFrame.StopPreview;
begin FWantPlay := False; FLoop := False; FRenderDue := 0; FReadyKey := ''; FReadyPath := ''; FVoiceSourceKey := ''; ClosePlayback; RetireJob; end;
procedure TRigmScriptVoiceEffectsFrame.Stop(Sender: TObject);
begin StopPreview; FNotice.Caption := '試聴を停止しました。'; end;
procedure TRigmScriptVoiceEffectsFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin if FSync or not Value then Exit; StopPreview; FWorkspace.SelectVoiceEffects(Item.SubItems[1]); RefreshState; end;
procedure TRigmScriptVoiceEffectsFrame.Resized(Sender: TObject);
begin
  if FList<>nil then FList.Columns[0].Width := Max(ScaleValue(120),FList.ClientWidth-FList.Columns[1].Width-ScaleValue(24));
  if FKnobs<>nil then for var I := 0 to High(FVolumes) do begin
    var W := Max(ScaleValue(128),FKnobs.ClientWidth div 3); var H := ScaleValue(190);
    FVolumes[I].SetBounds((I mod 3)*W,(I div 3)*H,W-ScaleValue(8),H-ScaleValue(8));
  end;
end;
procedure TRigmScriptVoiceEffectsFrame.ShowParameters;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit; var C := P.Cue(SelectedId); if C=nil then Exit;
  FSync := True;
  try
    GetControllerEffectDefinition(FEffect.ItemIndex,FDefinition);
    FLamp.Checked := VoiceEffectValue(C.AudioEffects,FDefinition.UseItemName)<>0;
    FLamp.PanelColor := FDefinition.BackgroundColor; FLamp.TextColor := FDefinition.TextColor;
    FMode.Visible := FDefinition.SelectControl.Visible; FMode.Items.Clear;
    for var S in FDefinition.SelectControl.Items do FMode.Items.Add(S);
    if FMode.Visible then FMode.ItemIndex := Round(VoiceEffectValue(C.AudioEffects,FDefinition.SelectControl.ItemName));
    for var V in FVolumes do V.Free; SetLength(FVolumes,Length(FDefinition.Volumes));
    for var I := 0 to High(FVolumes) do begin
      var D := FDefinition.Volumes[I]; var V := TAul2VolumeControl.Create(Self); FVolumes[I] := V;
      V.Parent := FKnobs; V.Name := 'ScriptEffectValue'+I.ToString;
      V.Configure(D.DisplayName,D.Minimum,D.Maximum,D.Step,D.Decimals,D.UnitText);
      V.PanelColor := FDefinition.VolumeColor; V.AccentColor := FDefinition.ThemeColor;
      V.TextColor := FDefinition.TextColor; V.ValueText := FloatToStr(VoiceEffectValue(C.AudioEffects,D.ItemName),TFormatSettings.Invariant); V.OnValueChange := VolumeChanged;
    end;
    FShownSettings := CueVoiceEffectsStamp(C); Resized(Self);
  finally FSync := False; end;
end;
procedure TRigmScriptVoiceEffectsFrame.EffectChanged(Sender: TObject);
begin if not FSync then ShowParameters; end;
procedure TRigmScriptVoiceEffectsFrame.ParameterChanged(Sender: TObject);
begin CommitParameters; end;
procedure TRigmScriptVoiceEffectsFrame.VolumeChanged(Sender: TObject; const ValueText: string; var Accept: Boolean);
begin
  Accept := False;
  try CommitParameters(TAul2VolumeControl(Sender),ValueText); Accept := True;
  except on E: Exception do FNotice.Caption := E.Message; end;
end;
procedure TRigmScriptVoiceEffectsFrame.CommitParameters(ChangedControl: TAul2VolumeControl; const NewText: string);
begin
  if FSync then Exit; var P := FWorkspace.ScriptDraft; if (P=nil) or (P.Cue(SelectedId)=nil) then Exit;
  var Settings := P.Cue(SelectedId).AudioEffects.Clone as TJSONObject;
  try
    Settings.RemovePair(FDefinition.UseItemName).Free; Settings.AddPair(FDefinition.UseItemName,TJSONNumber.Create(Ord(FLamp.Checked)));
    if FMode.Visible then begin Settings.RemovePair(FDefinition.SelectControl.ItemName).Free; Settings.AddPair(FDefinition.SelectControl.ItemName,TJSONNumber.Create(FMode.ItemIndex)); end;
    for var I := 0 to High(FVolumes) do begin
      var V := FVolumes[I].Value;
      // Copied knob callback fires before Value updates; take its new text directly.
      if FVolumes[I]=ChangedControl then V := StrToFloat(NewText,TFormatSettings.Invariant);
      var Name := FDefinition.Volumes[I].ItemName; Settings.RemovePair(Name).Free; Settings.AddPair(Name,TJSONNumber.Create(V));
    end;
    FShownSettings := VoiceEffectSettingsStamp(Settings); // Prevent reentrant refresh replacing active knob.
    FWorkspace.EditVoiceEffects(SelectedId,Settings);
    if FWantPlay and (FLoop or (FJob<>nil)) then begin
      FRenderDue := GetTickCount64+280;
      if FLoop then FNotice.Caption := '調整を保存しました。処理後、次のループから反映します。'
      else FNotice.Caption := '調整を保存しました。最新設定で試聴を準備します。';
    end
    else FNotice.Caption := '調整を保存しました。次回の再生・動画出力に反映します。';
  finally Settings.Free; end;
end;
procedure TRigmScriptVoiceEffectsFrame.Play(Sender: TObject);
begin
  try
    for var V in FVolumes do if not V.CommitPendingValue then raise Exception.Create('試聴前に数値を確認してください。');
    StopPreview; FWorkspace.StopVoice; FLoop := Sender=FLoopPlay; FWantPlay := True;
    FVoiceSourceKey := CueEffectSourceStamp(FWorkspace.ScriptDraft,FWorkspace.ScriptDraft.Cue(SelectedId)); EnsurePreview;
  except on E: Exception do begin StopPreview; FNotice.Caption := E.Message; end; end;
end;
procedure TRigmScriptVoiceEffectsFrame.OpenPlayback(const Path,Key: string);
begin
  ClosePlayback; FPlaybackAlias := 'rigm_effect_'+IntToHex(NativeUInt(Self),SizeOf(Pointer)*2);
  try
    EffectMci('open "'+Path+'" type waveaudio alias '+FPlaybackAlias);
    EffectMci('play '+FPlaybackAlias+' from 0'); FPlaybackKey := Key;
    FNotice.Caption := '選択行を再生中'; if FLoop then FNotice.Caption := '選択行をループ再生中（変更は次のループで反映）';
  except ClosePlayback; raise; end;
end;
procedure TRigmScriptVoiceEffectsFrame.EnsurePreview;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then raise Exception.Create('台本がありません。'); var C := P.Cue(SelectedId);
  if (C=nil) or not P.AudioReady(C) then raise Exception.Create('先に選択行の音声を生成・確認してください。');
  if (C.AudioSeconds<=0) or (C.WaveFile='') then raise Exception.Create('音声を持たない字幕行は試聴できません。');
  var Key := CueEffectPreviewKey(P,C); if (FJob<>nil) and (FJob.Key=Key) then Exit; RetireJob;
  // A cancelled worker may still be loading PCM. Wait asynchronously before allocating the latest job.
  if FRetired.Count>0 then begin FRenderDue := GetTickCount64+80; Exit; end;
  if (FReadyKey=Key) and FileExists(FReadyPath) then begin
    if FPlaybackAlias='' then OpenPlayback(FReadyPath,Key); Exit;
  end;
  FJob := TRigmVoiceEffectsPreviewJob.Create(P,C.Id); FJob.Start; FTimer.Enabled := True;
  FNotice.Caption := '選択行の派生音声を準備しています…';
end;
procedure TRigmScriptVoiceEffectsFrame.Tick(Sender: TObject);
begin
  for var I := FRetired.Count-1 downto 0 do if FRetired[I].Done then FRetired.Delete(I);
  if not FActive or not Showing or (FWorkspace.ScriptDraft=nil) or (FWorkspace.CurrentScriptStage<>'voice-effects') then begin StopPreview; FTimer.Enabled := FRetired.Count>0; Exit; end;
  try
    var P := FWorkspace.ScriptDraft; var C := P.Cue(SelectedId);
    if (P.Id<>FProjectId) or (SelectedId<>FSelectedCue) or (C=nil) then begin StopPreview; RefreshState; Exit; end;
    if FWantPlay and (not P.AudioReady(C) or (FVoiceSourceKey<>CueEffectSourceStamp(P,C))) then begin StopPreview; FNotice.Caption := '原音声が変わったため試聴を停止しました。'; Exit; end;
    if (FRenderDue<>0) and (GetTickCount64>=FRenderDue) then begin FRenderDue := 0; EnsurePreview; end;
    if (FJob<>nil) and FJob.Done then begin
      var Job := FJob; FJob := nil;
      try
        if (Job.Key=CueEffectPreviewKey(P,C)) and (Job.FileName<>'') and FileExists(Job.FileName) then begin
          C.EffectWaveFile := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(P.FileName)),Job.FileName);
          C.EffectAudioKey := Job.Key; P.Changed;
          FReadyKey := Job.Key; FReadyPath := Job.FileName;
          FWorkspace.NotifyVoiceEffectsPreview;
          if FWantPlay and (FPlaybackAlias='') then OpenPlayback(Job.FileName,Job.Key);
        end else if (Job.Key=CueEffectPreviewKey(P,C)) and (Job.Error<>'') then begin StopPreview; FNotice.Caption := Job.Error; end;
      finally Job.Free; end;
    end;
    if FPlaybackAlias<>'' then begin
      var B: array[0..63] of Char; var E := mciSendString(PChar('status '+FPlaybackAlias+' mode'),B,Length(B),0);
      if E<>0 then raise Exception.Create('試聴の再生状態を取得できません。');
      if not SameText(string(B),'playing') then begin
        ClosePlayback;
        if FLoop and FWantPlay then EnsurePreview else begin FWantPlay := False; FNotice.Caption := '選択行の試聴が終了しました。'; end;
      end;
    end;
    FStop.Enabled := FWantPlay or (FJob<>nil); FTimer.Enabled := FActive or (FRetired.Count>0);
  except on E: Exception do begin StopPreview; FNotice.Caption := E.Message; end; end;
end;
procedure TRigmScriptVoiceEffectsFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('voiceEffects')=nil) then Exit;
  var Id := SelectedId;
  if (FProjectId<>P.Id) or (FSelectedCue<>Id) then begin StopPreview; FProjectId := P.Id; FSelectedCue := Id; FShownSettings := ''; end;
  var Rebuild := FList.Items.Count<>P.Cues.Count;
  if not Rebuild then for var I := 0 to P.Cues.Count-1 do
    if (FList.Items[I].SubItems.Count<>2) or (FList.Items[I].SubItems[1]<>P.Cues[I].Id) then begin Rebuild := True; Break; end;
  FSync := True; FList.Items.BeginUpdate;
  try
    if Rebuild then FList.Items.Clear;
    for var I := 0 to P.Cues.Count-1 do begin
      var C := P.Cues[I]; var Item: TListItem;
      if Rebuild then begin Item := FList.Items.Add; Item.SubItems.Add(''); Item.SubItems.Add(C.Id); end else Item := FList.Items[I];
      Item.Caption := C.SpokenText; var Effect := 'なし'; if VoiceEffectsEnabled(C.AudioEffects) then Effect := '設定あり';
      Item.SubItems[0] := Effect; Item.Selected := C.Id=Id;
    end;
  finally FList.Items.EndUpdate; FSync := False; end;
  var C := P.Cue(Id);
  if C<>nil then begin
    if FShownSettings<>CueVoiceEffectsStamp(C) then begin ShowParameters; if FWantPlay and (FLoop or (FJob<>nil)) then FRenderDue := GetTickCount64+280; end;
    FPlay.Enabled := P.AudioReady(C) and (C.AudioSeconds>0) and (C.WaveFile<>''); FLoopPlay.Enabled := FPlay.Enabled;
    if (C.AudioSeconds<=0) or (C.WaveFile='') then FNotice.Caption := '音声を持たない字幕行です。試聴はありません。';
  end;
end;
end.
