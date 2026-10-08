unit RigmScriptVoiceEffectsFrame;
// Aul2 controller widgets and async per-cue audition, preserving original WAV files.
interface
uses System.Classes, System.Types, System.Generics.Collections, Winapi.Messages, RigmScriptPageFrame,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Buttons, RigmBufferedControls,
  RigmWizardWorkspace, RigmAul2EffectDefinition, RigmAul2VolumeControl, RigmAul2LampSwitch,
  RigmVoiceEffectsPreview, VoicevoxToolbarButtons, RigmEffectsPlayback, RigmEffectsAnalysis,
  RigmEffectsWaveform, RigmAul2OutputGraph;
type
  TRigmScriptVoiceEffectsFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FList: TListView; FSync,FActive,FLoop,FWantPlay: Boolean;
    FEffect: TListBox; FMode,FPreset: TComboBox; FApplyPreset: TButton;
    FEffectStates: TArray<Boolean>; FShownEffect: Integer;
    FLamp: TAul2LampSwitch; FKnobs: TScrollBox;
    FVolumes: TArray<TAul2VolumeControl>; FDefinition: TControllerEffectDefinition;
    FNotice,FHelp,FModeLabel,FGraphLabel,FMeasure,FTransportLabel: TLabel;
    FBody: TScrollBox; FContent: TPanel; FSettingsGraph: TCustomControl;
    FWave: TRigmEffectsWaveform; FMonitor: TAul2ControllerOutputGraph;
    FReadyAnalysis,FPlayingAnalysis: TRigmEffectsAnalysis; FPlayback: TRigmEffectsPlayback;
    FPlay,FLoopPlay,FStop: TVoicevoxToolbarButton; FTimer: TTimer;
    FJob: TRigmVoiceEffectsPreviewJob; FRetired: TObjectList<TRigmVoiceEffectsPreviewJob>;
    FProjectId,FSelectedCue,FShownSettings,FPlaybackKey,FVoiceSourceKey,FReadyKey,FReadyPath: string; FRenderDue: UInt64;
    function SelectedId: string;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Resized(Sender: TObject);
    procedure EffectChanged(Sender: TObject);
    procedure DrawEffect(Sender: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure RefreshEffectStates;
    procedure ApplyPreset(Sender: TObject);
    procedure ParameterChanged(Sender: TObject);
    procedure VolumeChanged(Sender: TObject; const ValueText: string; var Accept: Boolean);
    procedure CommitParameters(ChangedControl: TAul2VolumeControl=nil; const NewText: string='');
    procedure ShowParameters;
    procedure UpdateGraphs;
    procedure UpdateMeasurements;
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
uses System.SysUtils, System.Math, System.JSON, System.IOUtils,
  Winapi.Windows, Winapi.CommCtrl, Vcl.Graphics, Vcl.Themes,
  RigmAul2DelayGraph, RigmAul2EqGraph, RigmAul2CompressorGraph, RigmAul2DistortionGraph,
  RigmAul2BitCrusherGraph, RigmAul2NoiseGateGraph, RigmAul2LimiterGraph, RigmJson, PsdJson, RigmMovieModel, RigmVoiceEffects, RigmVoiceEffectSettings, RigmVoiceEffectPresets, RigmAudioFilePaths;
{$R *.dfm}
type
  TRigmEffectsListView = class(TRigmBufferedListView)
  protected
    function IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean; override;
    function CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean; override;
  end;
function TRigmEffectsListView.IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean;
begin
  Result := ((Target in [dtControl,dtItem]) and (Stage=cdPrePaint)) or inherited IsCustomDrawn(Target,Stage);
end;
function TRigmEffectsListView.CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean;
begin
  if Stage<>cdPrePaint then Exit(inherited CustomDrawItem(Item,State,Stage));
  Result := False;
  var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := ClientWidth;
  var Saved := SaveDC(Canvas.Handle);
  try
    // ネイティブの内部バッファへ背景と文字を一緒に描き、黒い選択文字や空白の行を防ぐ。
    IntersectClipRect(Canvas.Handle,Row.Left,Row.Top,Row.Right,Row.Bottom);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := StyleServices(Self).GetStyleColor(scListView);
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText);
    if Item.Selected then begin Canvas.Brush.Color := $00D07000; Canvas.Font.Color := clWhite; end;
    Canvas.FillRect(Row);
    SetBkMode(Canvas.Handle,TRANSPARENT);
    var Header := ListView_GetHeader(Handle);
    var Padding := MulDiv(6,CurrentPPI,96);
    for var Index := 0 to Columns.Count-1 do begin
      var Cell: TRect; if not Header_GetItemRect(Header,Index,@Cell) then Continue;
      MapWindowPoints(Header,Handle,Cell,2); Cell.Top := Row.Top; Cell.Bottom := Row.Bottom;
      var CellSaved := SaveDC(Canvas.Handle);
      try
        IntersectClipRect(Canvas.Handle,Cell.Left,Cell.Top,Cell.Right,Cell.Bottom);
        Inc(Cell.Left,Padding); Dec(Cell.Right,Padding);
        var Text := Item.Caption;
        if Index>0 then begin
          Text := ''; if Index<=Item.SubItems.Count then Text := Item.SubItems[Index-1];
        end;
        var Flags: Cardinal := DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX;
        case Columns[Index].Alignment of
          taCenter: Flags := Flags or DT_CENTER;
          taRightJustify: Flags := Flags or DT_RIGHT;
        end;
        if Cell.Right>Cell.Left then DrawText(Canvas.Handle,PChar(Text),Length(Text),Cell,Flags);
      finally RestoreDC(Canvas.Handle,CellSaved); end;
    end;
    if Item.Selected then begin
      Canvas.Brush.Color := $00FFC762;
      var Accent := Row; Accent.Right := MulDiv(3,CurrentPPI,96); Canvas.FillRect(Accent);
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;
constructor TRigmScriptVoiceEffectsFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
  function LabelAt(const Name,Text: string): TLabel;
  begin
    Result := TRigmScriptLabel.Create(Self); Result.Parent := FContent;
    Result.Name := Name; Result.AutoSize := False; Result.WordWrap := True; Result.Caption := Text;
  end;
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FRetired := TObjectList<TRigmVoiceEffectsPreviewJob>.Create(True);
  FPlayback := TRigmEffectsPlayback.Create;
  var Guide := TRigmScriptLabel.Create(Self); Guide.Parent := Self; Guide.Align := alTop;
  Guide.AutoSize := False; Guide.Height := ScaleValue(44); Guide.WordWrap := True; Guide.Name := 'ScriptVoiceEffectsGuide';
  Guide.Caption := 'セリフごとの音声エフェクト。ノブ・数値で調整し、再生で波形と処理前後を確認します。'+#13#10+
    '原音声を保持します。ループ中の変更は次の周回、通常再生の変更は次の再生に反映します。';
  var Rows := TRigmBufferedPanel.Create(Self); Rows.Parent := Self; Rows.Align := alLeft;
  Rows.Width := ScaleValue(260); Rows.BevelOuter := bvNone; Rows.Caption := '';
  FList := TRigmEffectsListView.Create(Self); FList.Parent := Rows; FList.Align := alClient;
  FList.Name := 'ScriptVoiceEffectsRows'; FList.ViewStyle := vsReport; FList.RowSelect := True;
  FList.ReadOnly := True; FList.HideSelection := False; FList.OnSelectItem := Selected;
  FList.Columns.Add.Caption := 'セリフ'; FList.Columns[0].Width := ScaleValue(236);
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  Splitter.Left := Rows.Width;
  var Effects := TRigmBufferedPanel.Create(Self); Effects.Parent := Self;
  Effects.Align := alLeft; Effects.Left := Rows.Width+Splitter.Width;
  Effects.Width := ScaleValue(184); Effects.BevelOuter := bvNone; Effects.Caption := '';
  Effects.Name := 'ScriptEffectListPanel';
  var EffectLabel := TRigmScriptLabel.Create(Self); EffectLabel.Parent := Effects; EffectLabel.Align := alTop;
  EffectLabel.AutoSize := False; EffectLabel.Height := ScaleValue(28);
  EffectLabel.Caption := 'エフェクター（緑＝ON）';
  FEffect := TListBox.Create(Self); FEffect.Parent := Effects; FEffect.Align := alClient;
  FEffect.Style := lbOwnerDrawFixed; FEffect.StyleElements := [];
  FEffect.Color := $00202020; FEffect.Font.Color := clWhite;
  FEffect.Name := 'ScriptEffectKind'; FEffect.OnClick := EffectChanged; FEffect.OnDrawItem := DrawEffect;
  SetLength(FEffectStates,CONTROLLER_EFFECT_COUNT);
  for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
    var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D); FEffect.Items.Add(D.DisplayName);
  end;
  FEffect.ItemIndex := 0;
  FBody := TScrollBox.Create(Self); FBody.Parent := Self; FBody.Align := alClient;
  FBody.BorderStyle := bsNone; FBody.VertScrollBar.Tracking := True; FBody.HorzScrollBar.Tracking := True;
  FContent := TRigmBufferedPanel.Create(Self); FContent.Parent := FBody; FContent.BevelOuter := bvNone;
  FContent.Caption := ''; FContent.Name := 'ScriptEffectsContent';
  FPlay := TVoicevoxToolbarButton.CreatePreview(Self); FPlay.Parent := FContent;
  FPlay.Name := 'ScriptEffectsPlay'; FPlay.Hint := '選択したセリフを1回再生'; FPlay.OnExecute := Play;
  FLoopPlay := TVoicevoxToolbarButton.NewLoop(Self); FLoopPlay.Parent := FContent;
  FLoopPlay.Name := 'ScriptEffectsLoop'; FLoopPlay.Hint := '選択したセリフをループ再生'; FLoopPlay.OnExecute := Play;
  FStop := TVoicevoxToolbarButton.NewStop(Self); FStop.Parent := FContent;
  FStop.Name := 'ScriptEffectsStop'; FStop.Hint := '試聴・処理を停止'; FStop.OnExecute := Stop;
  FPlay.UseParentBackground; FLoopPlay.UseParentBackground; FStop.UseParentBackground;
  FTransportLabel := LabelAt('ScriptEffectsTransportLabel','再生　／　ループ　／　停止');
  FTransportLabel.SetBounds(ScaleValue(122),ScaleValue(9),ScaleValue(260),ScaleValue(24));
  FApplyPreset := TButton.Create(Self); FApplyPreset.Parent := FContent;
  FApplyPreset.Name := 'ScriptEffectApplyPreset'; FApplyPreset.Caption := '採用'; FApplyPreset.OnClick := ApplyPreset;
  FApplyPreset.Hint := '選択中のセリフへプリセットを採用。「なし」は全エフェクターを初期値へ戻します。';
  FApplyPreset.ShowHint := True;
  FPreset := TComboBox.Create(Self); FPreset.Parent := FContent; FPreset.Style := csDropDownList;
  FPreset.Name := 'ScriptEffectPreset';
  for var I := 0 to VOICE_EFFECT_PRESET_COUNT-1 do FPreset.Items.Add(VoiceEffectPresetName(I));
  FPreset.ItemIndex := 0; FPreset.Hint := 'プリセットを選び、左の「採用」を押してください。'; FPreset.ShowHint := True;
  FLamp := TAul2LampSwitch.Create(Self); FLamp.Parent := FContent; FLamp.Name := 'ScriptEffectOn'; FLamp.OnClick := ParameterChanged;
  FHelp := LabelAt('ScriptEffectDescription','');
  FModeLabel := LabelAt('ScriptEffectModeLabel','');
  FMode := TComboBox.Create(Self); FMode.Parent := FContent; FMode.Style := csDropDownList;
  FMode.Name := 'ScriptEffectMode'; FMode.OnChange := ParameterChanged;
  FKnobs := TScrollBox.Create(Self); FKnobs.Parent := FContent; FKnobs.BorderStyle := bsNone;
  FKnobs.HorzScrollBar.Visible := False; FKnobs.VertScrollBar.Visible := False;
  FGraphLabel := LabelAt('ScriptEffectGraphLabel','');
  FMonitor := TAul2ControllerOutputGraph.Create(Self); FMonitor.Parent := FContent; FMonitor.Name := 'ScriptEffectsMeasuredLevels';
  FWave := TRigmEffectsWaveform.Create(Self); FWave.Parent := FContent; FWave.Name := 'ScriptEffectsWaveform';
  FMeasure := LabelAt('ScriptEffectsMeasurements','');
  FNotice := LabelAt('ScriptEffectsStatus','再生ボタンで選択行を試聴できます。');
  FTimer := TTimer.Create(Self); FTimer.Interval := 80; FTimer.OnTimer := Tick; FTimer.Enabled := False;
  OnResize := Resized; FBody.OnResize := Resized; Resized(Self);
end;
destructor TRigmScriptVoiceEffectsFrame.Destroy;
begin
  if FTimer<>nil then FTimer.Enabled := False; StopPreview;
  if FTimer<>nil then FTimer.Enabled := False;
  FreeAndNil(FPlayback); FreeAndNil(FRetired); inherited;
end;
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
  if FWave<>nil then FWave.SetData(nil,0);
  try if FPlayback<>nil then FPlayback.Close;
  except on E: Exception do if FNotice<>nil then FNotice.Caption := '停止処理：'+E.Message; end;
  FPlaybackKey := ''; FreeAndNil(FPlayingAnalysis);
  if FPlay<>nil then FPlay.Selected := False;
  if FLoopPlay<>nil then FLoopPlay.Selected := False;
end;
procedure TRigmScriptVoiceEffectsFrame.StopPreview;
begin
  FWantPlay := False; FLoop := False; FRenderDue := 0; FReadyKey := ''; FReadyPath := ''; FVoiceSourceKey := '';
  if FWave<>nil then FWave.SetData(nil,0); if FMonitor<>nil then FMonitor.ClearData;
  ClosePlayback; FreeAndNil(FReadyAnalysis); RetireJob;
  if FMeasure<>nil then FMeasure.Caption := '';
  if FStop<>nil then FStop.Enabled := False;
end;
procedure TRigmScriptVoiceEffectsFrame.Stop(Sender: TObject);
begin
  FWantPlay := False; FLoop := False; FRenderDue := 0; FVoiceSourceKey := '';
  ClosePlayback; RetireJob; FStop.Enabled := False; UpdateMeasurements;
  FNotice.Caption := '試聴を停止しました。';
end;
procedure TRigmScriptVoiceEffectsFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  // Repaint both the old and new selection, including model-driven changes.
  if Item<>nil then begin
    var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := FList.ClientWidth;
    InvalidateRect(FList.Handle,@Row,False);
  end;
  if FSync or not Value then Exit;
  StopPreview; FWorkspace.SelectVoiceEffects(Item.SubItems[0]); RefreshState;
end;
procedure TRigmScriptVoiceEffectsFrame.Resized(Sender: TObject);
begin
  if FEffect<>nil then FEffect.ItemHeight := ScaleValue(26);
  if FList<>nil then FList.Columns[0].Width := Max(ScaleValue(120),FList.ClientWidth-ScaleValue(24));
  if (FContent=nil) or (FNotice=nil) then Exit;
  var W := Max(ScaleValue(340),FBody.ClientWidth-ScaleValue(18)); var Gap := ScaleValue(6);
  FContent.Width := W;
  FPlay.SetBounds(Gap,0,ScaleValue(34),ScaleValue(34));
  FLoopPlay.SetBounds(ScaleValue(42),0,ScaleValue(34),ScaleValue(34));
  FStop.SetBounds(ScaleValue(78),0,ScaleValue(34),ScaleValue(34));
  FTransportLabel.SetBounds(ScaleValue(122),ScaleValue(9),W-ScaleValue(128),ScaleValue(24));
  FApplyPreset.SetBounds(Gap,ScaleValue(40),ScaleValue(64),ScaleValue(28));
  FPreset.SetBounds(ScaleValue(76),ScaleValue(40),W-ScaleValue(82),ScaleValue(28));
  FLamp.SetBounds(Gap,ScaleValue(74),ScaleValue(78),ScaleValue(30));
  FHelp.SetBounds(ScaleValue(90),ScaleValue(74),W-ScaleValue(96),ScaleValue(40));
  var Y := ScaleValue(116);
  FModeLabel.SetBounds(Gap,Y,ScaleValue(96),ScaleValue(28));
  FMode.SetBounds(ScaleValue(104),Y,W-ScaleValue(110),ScaleValue(28));
  if FMode.Visible then Inc(Y,ScaleValue(34));
  var Cols := Max(1,(W-Gap) div ScaleValue(90));
  var Rows := Max(1,(Length(FVolumes)+Cols-1) div Cols);
  FKnobs.SetBounds(Gap,Y,W-Gap*2,Rows*ScaleValue(126));
  for var I := 0 to High(FVolumes) do
    FVolumes[I].SetBounds((I mod Cols)*ScaleValue(90),(I div Cols)*ScaleValue(126),ScaleValue(84),ScaleValue(122));
  Inc(Y,FKnobs.Height+Gap);
  FGraphLabel.SetBounds(Gap,Y,W-Gap*2,ScaleValue(44)); Inc(Y,ScaleValue(46));
  var GraphWidth := (W-Gap*3) div 2;
  if FSettingsGraph<>nil then begin
    if W>=ScaleValue(640) then begin
      FSettingsGraph.SetBounds(Gap,Y,GraphWidth,ScaleValue(150));
      FMonitor.SetBounds(GraphWidth+Gap*2,Y,GraphWidth,ScaleValue(150)); Inc(Y,ScaleValue(156));
    end else begin
      FSettingsGraph.SetBounds(Gap,Y,W-Gap*2,ScaleValue(150)); Inc(Y,ScaleValue(156));
      FMonitor.SetBounds(Gap,Y,W-Gap*2,ScaleValue(150)); Inc(Y,ScaleValue(156));
    end;
  end else begin FMonitor.SetBounds(Gap,Y,W-Gap*2,ScaleValue(150)); Inc(Y,ScaleValue(156)); end;
  FWave.SetBounds(Gap,Y,W-Gap*2,ScaleValue(150)); Inc(Y,ScaleValue(156));
  FMeasure.SetBounds(Gap,Y,W-Gap*2,ScaleValue(80)); Inc(Y,ScaleValue(84));
  FNotice.SetBounds(Gap,Y,W-Gap*2,ScaleValue(58)); FContent.Height := Y+ScaleValue(64);
end;
procedure TRigmScriptVoiceEffectsFrame.ShowParameters;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit; var C := P.Cue(SelectedId); if C=nil then Exit;
  FSync := True;
  try
    GetControllerEffectDefinition(FEffect.ItemIndex,FDefinition);
    FShownEffect := FEffect.ItemIndex;
    FLamp.Checked := VoiceEffectValue(C.AudioEffects,FDefinition.UseItemName)<>0;
    FLamp.PanelColor := FDefinition.VolumeColor; FLamp.TextColor := FDefinition.TextColor;
    FContent.Color := FDefinition.BackgroundColor; FKnobs.Color := FDefinition.BackgroundColor;
    FHelp.Caption := FDefinition.LampCaption;
    // Keep explanation readable regardless of effect palette or active VCL style.
    FHelp.ParentColor := False; FHelp.ParentFont := False; FHelp.StyleElements := [];
    FHelp.Transparent := False; FHelp.Color := clBlack; FHelp.Font.Color := clWhite;
    FModeLabel.Transparent := False; FModeLabel.Color := FDefinition.VolumeColor; FModeLabel.Font.Color := FDefinition.TextColor;
    FGraphLabel.Font.Color := $00F2F0EE; FMeasure.Font.Color := $00F2F0EE; FNotice.Font.Color := $00F2F0EE;
    FModeLabel.Caption := FDefinition.SelectControl.DisplayName; FModeLabel.Visible := FDefinition.SelectControl.Visible;
    FMode.Visible := FDefinition.SelectControl.Visible; FMode.Items.Clear;
    for var S in FDefinition.SelectControl.Items do FMode.Items.Add(S);
    if FMode.Visible then FMode.ItemIndex := Round(VoiceEffectValue(C.AudioEffects,FDefinition.SelectControl.ItemName));
    for var V in FVolumes do V.Free; SetLength(FVolumes,Length(FDefinition.Volumes));
    for var I := 0 to High(FVolumes) do begin
      var D := FDefinition.Volumes[I]; var V := TAul2VolumeControl.Create(Self); FVolumes[I] := V;
      V.Parent := FKnobs; V.Name := 'ScriptEffectValue'+I.ToString;
      V.ParentFont := False; V.Font.Assign(Font); V.Font.Size := 9; // Aul2 compact controller font; avoids inherited Yu Gothic clipping.
      V.Configure(D.DisplayName,D.Minimum,D.Maximum,D.Step,D.Decimals,D.UnitText);
      V.PanelColor := FDefinition.VolumeColor; V.Color := FDefinition.ThemeColor; V.AccentColor := FDefinition.IndicatorColor;
      V.TextColor := FDefinition.TextColor; V.ValueText := FloatToStr(VoiceEffectValue(C.AudioEffects,D.ItemName),TFormatSettings.Invariant); V.OnValueChange := VolumeChanged;
    end;
    FShownSettings := CueVoiceEffectsStamp(C); RefreshEffectStates; UpdateGraphs; Resized(Self); UpdateMeasurements;
  finally FSync := False; end;
end;
procedure TRigmScriptVoiceEffectsFrame.EffectChanged(Sender: TObject);
begin
  if FSync or (FEffect.ItemIndex<0) then Exit;
  for var V in FVolumes do if not V.CommitPendingValue then begin
    FEffect.ItemIndex := FShownEffect;
    FNotice.Caption := '数値を確認してからエフェクターを切り替えてください。'; Exit;
  end;
  ShowParameters;
end;
procedure TRigmScriptVoiceEffectsFrame.RefreshEffectStates;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit;
  var C := P.Cue(SelectedId); if C=nil then Exit;
  var Changed := False;
  for var I := 0 to High(FEffectStates) do begin
    var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D);
    var Enabled := VoiceEffectValue(C.AudioEffects,D.UseItemName)<>0;
    if FEffectStates[I]<>Enabled then begin FEffectStates[I] := Enabled; Changed := True; end;
  end;
  if Changed then FEffect.Invalidate;
end;
procedure TRigmScriptVoiceEffectsFrame.DrawEffect(Sender: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  if (Index<0) or (Index>=Length(FEffectStates)) then Exit;
  var C := FEffect.Canvas; C.Font.Assign(FEffect.Font); C.Brush.Style := bsSolid;
  C.Brush.Color := FEffect.Color; C.Font.Color := clWhite;
  if FEffectStates[Index] then begin C.Brush.Color := $003D5030; C.Font.Color := $0097EDAB; end;
  if Index=FEffect.ItemIndex then begin
    C.Brush.Color := $00D07000;
    if FEffectStates[Index] then C.Brush.Color := $00507628;
  end;
  C.FillRect(Rect); SetBkMode(C.Handle,TRANSPARENT);
  var TextRect := Rect; Inc(TextRect.Left,ScaleValue(6)); Dec(TextRect.Right,ScaleValue(34));
  DrawText(C.Handle,PChar(FEffect.Items[Index]),-1,TextRect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  if FEffectStates[Index] then begin
    TextRect := Rect; TextRect.Right := Min(Rect.Right,FEffect.ClientWidth)-ScaleValue(8);
    TextRect.Left := TextRect.Right-ScaleValue(28);
    DrawText(C.Handle,'ON',2,TextRect,DT_SINGLELINE or DT_VCENTER or DT_RIGHT);
  end;
  if odFocused in State then C.DrawFocusRect(Rect);
end;
procedure TRigmScriptVoiceEffectsFrame.ApplyPreset(Sender: TObject);
begin
  if FSync or (FPreset.ItemIndex<0) then Exit;
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.Cue(SelectedId)=nil) then Exit;
  // 採用は全設定の置換。入力途中のノブ値もプリセット値へ置き換える。
  var Settings := CreateVoiceEffectPreset(FPreset.ItemIndex);
  try
    FWorkspace.EditVoiceEffects(SelectedId,Settings);
    ShowParameters;
    if FWantPlay and (FLoop or (FJob<>nil)) then FRenderDue := GetTickCount64+280;
    FNotice.Caption := '「'+FPreset.Text+'」を選択中のセリフへ採用しました。';
    if FLoop and FWantPlay then FNotice.Caption := FNotice.Caption+' 次のループから反映します。'
    else FNotice.Caption := FNotice.Caption+' 次回の再生・動画出力に反映します。';
  finally Settings.Free; end;
end;
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
    RefreshEffectStates; UpdateGraphs; UpdateMeasurements;
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
  ClosePlayback;
  try
    FPlayback.Open(Path); FPlayback.Play; FPlaybackKey := Key;
    if FReadyAnalysis<>nil then FPlayingAnalysis := FReadyAnalysis.Clone;
    FPlay.Selected := not FLoop; FLoopPlay.Selected := FLoop;
    FNotice.Caption := '選択行を再生中';
    if FLoop then FNotice.Caption := '選択行をループ再生中（変更は次の周回に反映）';
    UpdateMeasurements;
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
  if (FReadyKey=Key) and AudioFileExists(FReadyPath) then begin
    if FPlaybackKey='' then OpenPlayback(FReadyPath,Key); Exit;
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
        if (Job.Key=CueEffectPreviewKey(P,C)) and (Job.FileName<>'') and AudioFileExists(Job.FileName) then begin
          C.EffectWaveFile := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(P.FileName)),Job.FileName);
          C.EffectAudioKey := Job.Key; Job.KeepOutput; P.Changed;
          FReadyKey := Job.Key; FReadyPath := Job.FileName;
          FWave.SetData(nil,0); FreeAndNil(FReadyAnalysis); FReadyAnalysis := Job.DetachAnalysis; UpdateMeasurements;
          FWorkspace.NotifyVoiceEffectsPreview;
          if FWantPlay and (FPlaybackKey='') then OpenPlayback(Job.FileName,Job.Key);
        end else if (Job.Key=CueEffectPreviewKey(P,C)) and (Job.Error<>'') then begin StopPreview; FNotice.Caption := Job.Error; end;
      finally Job.Free; end;
    end;
    if FPlaybackKey<>'' then begin
      if not FPlayback.Playing then begin
        if FLoop and FWantPlay then begin ClosePlayback; EnsurePreview; end
        else begin
          FWantPlay := False; FPlay.Selected := False; FLoopPlay.Selected := False;
          FNotice.Caption := '選択行の試聴が終了しました。';
        end;
      end;
    end;
    UpdateMeasurements;
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
    if (FList.Items[I].SubItems.Count<>1) or (FList.Items[I].SubItems[0]<>P.Cues[I].Id) then begin Rebuild := True; Break; end;
  FSync := True; FList.Items.BeginUpdate;
  try
    if Rebuild then FList.Items.Clear;
    for var I := 0 to P.Cues.Count-1 do begin
      var C := P.Cues[I]; var Item: TListItem;
      if Rebuild then begin Item := FList.Items.Add; Item.SubItems.Add(C.Id); end else Item := FList.Items[I];
      Item.Caption := C.SpokenText; Item.Selected := C.Id=Id;
    end;
  finally FList.Items.EndUpdate; FSync := False; end;
  var C := P.Cue(Id);
  if C<>nil then begin
    if FShownSettings<>CueVoiceEffectsStamp(C) then begin ShowParameters; if FWantPlay and (FLoop or (FJob<>nil)) then FRenderDue := GetTickCount64+280; end;
    FPlay.Enabled := P.AudioReady(C) and (C.AudioSeconds>0) and (C.WaveFile<>''); FLoopPlay.Enabled := FPlay.Enabled;
    if (C.AudioSeconds<=0) or (C.WaveFile='') then FNotice.Caption := '音声を持たない字幕行です。試聴はありません。';
  end;
end;

procedure TRigmScriptVoiceEffectsFrame.UpdateGraphs;
  function V(I: Integer): Double;
  begin Result := 0; if I<Length(FDefinition.Volumes) then Result := VoiceEffectValue(FWorkspace.ScriptDraft.Cue(SelectedId).AudioEffects,FDefinition.Volumes[I].ItemName); end;
begin
  FreeAndNil(FSettingsGraph);
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.Cue(SelectedId)=nil) then Exit;
  case FEffect.ItemIndex of
    0: begin var G := TAul2ControllerDelayGraph.Create(Self); G.SetDelay(V(0),V(1),V(2),V(3),FMode.ItemIndex=1,FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    1: begin var G := TAul2ControllerEqGraph.Create(Self); G.SetEq(FMode.ItemIndex,V(0),V(1),V(2),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    2: begin var G := TAul2ControllerCompressorGraph.Create(Self); G.SetCompressor(V(0),V(1),V(2),V(3),V(4),V(5),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    4: begin var G := TAul2ControllerDistortionGraph.Create(Self); G.SetDistortion(FMode.ItemIndex,V(0),V(1),V(2),V(3),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    6: begin var G := TAul2ControllerBitCrusherGraph.Create(Self); G.SetBitCrusher(V(0),V(1),V(2),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    14: begin var G := TAul2ControllerNoiseGateGraph.Create(Self); G.SetNoiseGate(V(0),V(1),V(2),V(3),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
    19: begin var G := TAul2ControllerLimiterGraph.Create(Self); G.SetLimiter(V(0),V(1),V(2),FLamp.Checked); G.AccentColor := FDefinition.IndicatorColor; FSettingsGraph := G; end;
  end;
  if FSettingsGraph<>nil then begin
    FSettingsGraph.Parent := FContent; FSettingsGraph.Name := 'ScriptEffectSettingsGraph';
    FGraphLabel.Caption := '特性：設定値から描画 ／ 処理前後レベル・波形：実測（モノラル）';
  end else FGraphLabel.Caption := '選択エフェクトの処理前後（実測・モノラル）';
  Resized(Self);
end;
procedure TRigmScriptVoiceEffectsFrame.UpdateMeasurements;
  function Db(Value: Double): string;
  begin if Value<=0 then Result := '−∞' else Result := FormatFloat('0.0',20*Log10(Value)); end;
begin
  var A := FPlayingAnalysis; var Position := 0.0;
  if (FPlaybackKey<>'') and (FPlayback<>nil) then Position := FPlayback.PositionSeconds;
  if A=nil then A := FReadyAnalysis;
  FWave.SetData(A,Position);
  if (A=nil) or not A.Ready or (A.BlockCount=0) then begin FMonitor.ClearData; FMeasure.Caption := '実測値：再生後に表示'; Exit; end;
  var M := A.EffectAt(FEffect.ItemIndex,Position); var Chain := A.ChainAt(Position);
  var BeforeRms,AfterRms: TControllerOutputHistory;
  FillChar(BeforeRms,SizeOf(BeforeRms),0); FillChar(AfterRms,SizeOf(AfterRms),0);
  var Last := A.BlockIndexAt(Position); var First := Max(0,Last-CONTROLLER_OUTPUT_HISTORY_COUNT+1);
  for var I := First to Last do begin
    var H := A.Block(I).Effects[FEffect.ItemIndex]; BeforeRms[I-First] := H.InputRms; AfterRms[I-First] := H.OutputRms;
  end;
  FMonitor.SetActive(M.Applied);
  FMonitor.SetMonitorData(M.InputPeak,M.InputPeak,M.OutputPeak,M.OutputPeak,BeforeRms,BeforeRms,AfterRms,AfterRms,Last-First+1);
  var State := '実測'; if not M.Applied then State := 'バイパス実測';
  var Current := ''; var P := FWorkspace.ScriptDraft;
  if (P<>nil) and (P.Cue(SelectedId)<>nil) then Current := CueEffectPreviewKey(P,P.Cue(SelectedId));
  var MeasuredKey := FReadyKey; if FPlayingAnalysis<>nil then MeasuredKey := FPlaybackKey;
  if MeasuredKey<>Current then State := State+'（前回の試聴設定。次の再生で更新）';
  FMeasure.Caption := State+'：'+FEffect.Items[FEffect.ItemIndex]+' RMS '+Db(M.InputRms)+' → '+Db(M.OutputRms)+' dBFS / 差分RMS '+Db(M.ResidualRms)+' dBFS'+#13#10+
    '最終出力 Peak '+Db(Chain.OutputPeak)+' dBFS。差分は出力−入力の実測値です。';
end;

end.
