// 所有する長いqueryの実ドラッグで、スクロール・原稿・旧音声と再表示回数を調べる。
type
  TAccentRefreshProbe = class
    Previous: TNotifyEvent;
    Count: Integer;
    procedure Changed(Sender: TObject);
  end;
procedure TAccentRefreshProbe.Changed(Sender: TObject);
begin Inc(Count); if Assigned(Previous) then Previous(Sender); end;
procedure CheckVoiceNoticeLayout(Frame: TRigmScriptVoiceFrame; Settings: TFrameSerifVoicevoxSettings);
begin
  var Scroll := Settings.FindComponent('VoicevoxAdjustments') as TScrollBox;
  var Notice := Settings.FindComponent('VoicevoxDetailNotice') as TLabel;
  var Status := Creator.FindComponent('ScriptTitleStatus') as TLabel;
  var Guide := Frame.FindComponent('ScriptVoiceGuide') as TLabel;
  var OldStatus := Status.Caption; var OldGuide := Guide.Caption; var OldNotice := Notice.Caption;
  var OldScroll := Scroll.VertScrollBar.Position;
  Scroll.VertScrollBar.Position := MulDiv(60,Settings.CurrentPPI,96);
  var At := Scroll.VertScrollBar.Position;
  var Controls: TArray<TControl> := [Frame,Settings,Settings.PanelAccent,Settings.PanelIntonation,
    Settings.PanelLength,Settings.PanelVoice,Guide,Frame.FindComponent('ScriptVoiceState') as TControl];
  var Bounds: TArray<TRect>; var Origins: TArray<TPoint>;
  SetLength(Bounds,Length(Controls)); SetLength(Origins,Length(Controls));
  for var I := 0 to High(Controls) do begin
    Bounds[I] := Controls[I].BoundsRect; Origins[I] := Controls[I].ClientToScreen(Point(0,0));
  end;
  var Stable := True;
  try
    for var MessageText in ['VOICEVOX処理中です。終了をお待ちください。',
      StringOfChar('長',600),''] do begin
      Settings.ShowNotice(MessageText); Status.Caption := MessageText; Guide.Caption := MessageText; Main.Update;
      Stable := Stable and (Scroll.VertScrollBar.Position=At) and Notice.Visible;
      for var I := 0 to High(Controls) do Stable := Stable and (Controls[I].BoundsRect=Bounds[I]) and
        (Controls[I].ClientToScreen(Point(0,0))=Origins[I]);
    end;
    Check(Stable,'waiting, long error and empty help keep editor coordinates and scroll at '+Settings.CurrentPPI.ToString+' DPI');
    Check((Settings.PanelAccent.Top<Settings.PanelIntonation.Top) and
      (Settings.PanelIntonation.Top<Settings.PanelLength.Top) and (Settings.PanelLength.Top<Settings.PanelVoice.Top),
      'common voice settings follow all three individual graphs at '+Settings.CurrentPPI.ToString+' DPI');
    var Values: TFrameSerifVoicevoxAudioSettings := nil;
    for var I := 0 to Settings.ComponentCount-1 do
      if Settings.Components[I] is TFrameSerifVoicevoxAudioSettings then Values := Settings.Components[I] as TFrameSerifVoicevoxAudioSettings;
    var First := Values.FindComponent('VoicevoxValue0') as TControl;
    var Last := Values.FindComponent('VoicevoxValue5') as TControl;
    Check((Values.Left=0) and (Values.Width<=MulDiv(420,Settings.CurrentPPI,96)) and
      (First.Width<=MulDiv(70,Settings.CurrentPPI,96)) and (Last.Left+Last.Width<=Values.ClientWidth),
      'six common parameters stay compact and contained at '+Settings.CurrentPPI.ToString+' DPI');
    Scroll.VertScrollBar.Position := Scroll.VertScrollBar.Range;
    Check((Values.ClientToScreen(Point(0,Values.Height)).Y<=Scroll.ClientToScreen(Point(0,Scroll.ClientHeight)).Y) and
      (Values.ClientToScreen(Point(0,0)).Y>=Scroll.ClientToScreen(Point(0,0)).Y),
      'bottom common settings remain fully reachable by scrolling at '+Settings.CurrentPPI.ToString+' DPI');
    Capture('voice-settings-bottom-'+Settings.CurrentPPI.ToString);
  finally
    Settings.ShowNotice(OldNotice); Status.Caption := OldStatus; Guide.Caption := OldGuide;
    Scroll.VertScrollBar.Position := OldScroll;
  end;
end;
procedure CheckAccentEditing;
  function FindPart(Owner: TComponent; Kind: TClass): TComponent;
  begin
    Result := nil;
    for var I := 0 to Owner.ComponentCount-1 do if Owner.Components[I].InheritsFrom(Kind) then Exit(Owner.Components[I]);
  end;
  function RequestCount(const Path: string): Integer;
  begin
    Result := 0; var Log := TPath.Combine(ExtractFilePath(ParamStr(3)),'requests.txt');
    if TFile.Exists(Log) then for var Line in TFile.ReadAllLines(Log) do
      if Line.StartsWith(Path) then Inc(Result);
  end;
  function LongQuery: string;
  begin
    var O := PsdJson.ObjectText('{"accent_phrases":[{"_rigm_display_refresh_test":true,"moras":[],"accent":1,"pause_mora":null,"is_interrogative":false}],"speedScale":1,"pitchScale":0,"intonationScale":1,"volumeScale":1,"prePhonemeLength":0.1,"postPhonemeLength":0.1,"outputSamplingRate":24000,"outputStereo":false}');
    try
      var Moras := JA(TJSONObject(JA(O,'accent_phrases')[0]),'moras');
      for var I := 0 to 99 do Moras.AddElement(PsdJson.ObjectText('{"text":"カ","consonant":"k","consonant_length":0.05,"vowel":"a","vowel_length":0.1,"pitch":5}'));
      Result := O.ToJSON;
    finally O.Free; end;
  end;
begin
  var Frame := StageFrame(TRigmScriptVoiceFrame) as TRigmScriptVoiceFrame;
  Check(Frame<>nil,'accent probe finds the voice stage');
  var Settings := Frame.FindComponent('ScriptVoiceDetails') as TFrameSerifVoicevoxSettings;
  Check(Settings<>nil,'accent probe finds the settings frame');
  var Accent := FindPart(Settings,TSerifVoicevoxAccentView) as TSerifVoicevoxAccentView;
  Check(Accent<>nil,'accent probe finds the accent view');
  var Paint := FindPart(Accent,TSerifVoicevoxAccentPaintControl) as TSerifVoicevoxAccentPaintControl;
  Check(Paint<>nil,'accent probe finds the native graph');
  var C := W.ScriptDraft.Cue(JS(JO(W.ScriptDraft.ScriptWizard,'voice'),'selectedCue'));
  Check(C<>nil,'accent probe has a selected cue');
  var Id := C.Id;
  var Source := C.Text; var Subtitle := C.Subtitle; var Reading := C.VoiceReading; var Scene := C.Scene;
  var Speaker := C.SpeakerId; var BeforeSettings := C.VoiceSettings.ToJSON;
  W.EditVoiceQuery(C.Id,LongQuery);
  Creator.SetActive(True);
  Sleep(250); Application.ProcessMessages; WaitVoice; Frame.RefreshState;
  var Values := Settings.RowValues; var S := W.ScriptDraft.Speaker(C.SpeakerId);
  Settings.ShowRow(C.SpokenText,S.VoiceUuid,W.ScriptDraft.EffectiveStyle(C),Values,C.VoiceQuery,W.ScriptDraft.EngineUrl);
  // 旧WAVの採用状態を作り、編集後もファイルと原稿が保持されることを検査する。
  var Audio := TRigmPcm.Create;
  try Audio.Rate := 48000; SetLength(Audio.Samples,24000); Audio.Save(TPath.Combine(Root,'accent-owned.wav'));
    C.WaveFile := TPath.Combine(Root,'accent-owned.wav'); C.AudioSeconds := Audio.Duration;
    C.AudioKey := W.ScriptDraft.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  finally Audio.Free; end;
  var MoraBefore := RequestCount('/mora_data?'); var SynthesisBefore := RequestCount('/synthesis?');
  var Wave := C.WaveFile; var WaveHash := THashSHA2.GetHashStringFromFile(Wave);
  W.SaveScriptDraft(False); C := W.ScriptDraft.Cue(Id); S := W.ScriptDraft.Speaker(C.SpeakerId);
  Wave := C.WaveFile;
  CheckVoiceNoticeLayout(Frame,Settings);
  Accent.ScrollPosition := MulDiv(220,Accent.CurrentPPI,96); var Scroll := Accent.ScrollPosition;
  var Origin := Paint.ClientToScreen(Point(0,0));
  var Probe := TAccentRefreshProbe.Create; Probe.Previous := W.OnScriptChanged; W.OnScriptChanged := Probe.Changed;
  var Metrics := TJSONObject.Create;
  try
    var BeforeRevision := W.ScriptDraft.Revision; var BeforeQuery := C.VoiceQuery;
    var Cells := Accent.MoraCells; var X := (Cells[20].Left+Cells[20].Right) div 2;
    Paint.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,MulDiv(62,Accent.CurrentPPI,96)));
    var Started := GetTickCount64;
    for var I := 0 to 29 do begin
      X := (Cells[20+(I mod 10)].Left+Cells[20+(I mod 10)].Right) div 2;
      Paint.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    end;
    Paint.Perform(WM_LBUTTONUP,0,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    AddN(Metrics,'dragMs',GetTickCount64-Started); AddN(Metrics,'refreshDuringDrag',Probe.Count);
    AddN(Metrics,'scrollBefore',Scroll); AddN(Metrics,'scrollAfterDrag',Accent.ScrollPosition);
    var QueryAfter := C.VoiceQuery;
    AddN(Metrics,'revisionDelta',W.ScriptDraft.Revision-BeforeRevision);
    var Parsed := PsdJson.ObjectText(QueryAfter);
    try AddN(Metrics,'accentAfter',JI(TJSONObject(JA(Parsed,'accent_phrases')[0]),'accent')); finally Parsed.Free; end;
    Sleep(350); Application.ProcessMessages; Main.Update;
    AddN(Metrics,'refreshAfterIdle',Probe.Count); AddN(Metrics,'scrollAfterIdle',Accent.ScrollPosition);
    AddB(Metrics,'originStable',Paint.ClientToScreen(Point(0,0))=Origin);
    AddN(Metrics,'originBeforeX',Origin.X); AddN(Metrics,'originBeforeY',Origin.Y);
    AddN(Metrics,'originAfterX',Paint.ClientToScreen(Point(0,0)).X); AddN(Metrics,'originAfterY',Paint.ClientToScreen(Point(0,0)).Y);
    AddN(Metrics,'moraRequestsBeforeDelay',RequestCount('/mora_data?')-MoraBefore);
    AddN(Metrics,'scrollAfterSameRow',Accent.ScrollPosition);
    TFile.WriteAllText(TPath.Combine(Root,'accent-editing-metrics.json'),Metrics.ToJSON,TEncoding.UTF8);
    Check((Scroll>0) and (Accent.ScrollPosition=Scroll),'accent drag and same-row refresh preserve the horizontal scroll position');
    Check(JI(Metrics,'refreshDuringDrag')=0,'accent drag updates its query without rebuilding the whole wizard on every move');
    Check(JI(Metrics,'dragMs')<1500,'100-mora native drag completes 30 moves within the interaction budget');
    Check((JI(Metrics,'refreshAfterIdle')=1) and JB(Metrics,'originStable'),'idle refresh is coalesced once and leaves editor coordinates stable');
    Check((QueryAfter<>BeforeQuery) and (W.ScriptDraft.Revision>BeforeRevision) and (C.VoiceQuery=QueryAfter) and W.ScriptDraft.Modified,'native accent drag immediately persists the edited query and revision');
    Check((C.Text=Source) and (C.Subtitle=Subtitle) and (C.VoiceReading=Reading) and (C.Scene=Scene) and
      (C.SpeakerId=Speaker) and (C.VoiceSettings.ToJSON=BeforeSettings),'accent editing preserves source, subtitle, reading, scene, person and basic settings');
    Check((C.WaveFile=Wave) and (THashSHA2.GetHashStringFromFile(ResolveMoviePath(W.ScriptDraft.FileName,Wave))=WaveHash) and not W.ScriptDraft.AudioReady(C),
      'accent edit invalidates approval while keeping the previous stored audio');
    var Deadline := GetTickCount64+5000;
    repeat Application.ProcessMessages; Sleep(10); until (C.VoiceQuery<>QueryAfter) or (GetTickCount64>Deadline);
    Check(C.VoiceQuery<>QueryAfter,'accent idle refresh receives recalculated mora data without playback');
    var Intonation := FindPart(Settings,TFrameSerifVoicevoxIntonation) as TFrameSerifVoicevoxIntonation;
    var Lengths := FindPart(Settings,TFrameSerifVoicevoxLength) as TFrameSerifVoicevoxLength;
    var PitchSlider := FindPart(Intonation,TVerticalSliderControl) as TVerticalSliderControl;
    var LengthSlider := FindPart(Lengths,TVerticalSliderControl) as TVerticalSliderControl;
    Check(SameValue(PitchSlider.Position,4.25,0.001) and SameValue(LengthSlider.Position,0.07,0.001),
      'delayed accent refresh updates both displayed pitch and consonant duration');
    Check((JI(Metrics,'moraRequestsBeforeDelay')=0) and (RequestCount('/mora_data?')=MoraBefore+1) and
      (RequestCount('/synthesis?')=SynthesisBefore),'30 accent moves coalesce into one delayed mora request and no synthesis');
    Check((Accent.ScrollPosition=Scroll) and (Paint.ClientToScreen(Point(0,0))=Origin),
      'recalculated graphs preserve the accent scroll position and editor coordinates');
    QueryAfter := C.VoiceQuery;
    Settings.ShowRow(C.SpokenText,S.VoiceUuid,W.ScriptDraft.EffectiveStyle(C),Values,QueryAfter,W.ScriptDraft.EngineUrl);
    Check(Accent.ScrollPosition=Scroll,'same-row redraw preserves the accent scroll after recalculation');
    W.SaveScriptDraft(False); C := W.ScriptDraft.Cue(Id); S := W.ScriptDraft.Speaker(C.SpeakerId); var Saved := LoadMovie(W.ScriptDraft.FileName);
    try Check(Saved.Cue(C.Id).VoiceQuery=QueryAfter,'edited accent query survives save and reload'); finally Saved.Free; end;
    Capture('voice-accent-edited');
    // 反映待ちの間に手動調整しても最新値を失わず、保留中の読みもEngineの応答から戻す。
    var Pending := PsdJson.ObjectText(C.VoiceQuery);
    try
      PsdJson.Put(TJSONObject(JA(Pending,'accent_phrases')[0]),'_rigm_pending_reading','カカカ');
      Settings.ShowRow(C.SpokenText,S.VoiceUuid,W.ScriptDraft.EffectiveStyle(C),Values,Pending.ToJSON,W.ScriptDraft.EngineUrl);
      Settings.OnAccentChange(Settings,Pending.ToJSON);
    finally Pending.Free; end;
    Cells := Accent.MoraCells; X := (Cells[35].Left+Cells[35].Right) div 2;
    Paint.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,MulDiv(62,Accent.CurrentPPI,96)));
    Paint.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    Paint.Perform(WM_LBUTTONUP,0,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    PitchSlider.Position := 6.25; LengthSlider.Position := 0.23;
    var ManualQuery := C.VoiceQuery; Deadline := GetTickCount64+5000;
    repeat Application.ProcessMessages; Sleep(10); until (C.VoiceQuery<>ManualQuery) or (GetTickCount64>Deadline);
    Check((C.VoiceQuery<>ManualQuery) and SameValue(PitchSlider.Position,6.25,0.001) and
      SameValue(LengthSlider.Position,0.23,0.001),'delayed recalculation keeps manual pitch and duration entered after the accent edit');
    Parsed := PsdJson.ObjectText(C.VoiceQuery);
    try Check(JS(TJSONObject(JA(Parsed,'accent_phrases')[0]),'_rigm_pending_reading')='カカカ',
      'mora refresh preserves deferred reading even when the engine omits its private key'); finally Parsed.Free; end;
    W.SaveScriptDraft(False); C := W.ScriptDraft.Cue(Id); S := W.ScriptDraft.Speaker(C.SpeakerId);
    // HTTP開始後に表示対象を外した場合、古い結果をモデル・表示へ戻さない。
    var RequestsBeforeSwitch := RequestCount('/mora_data?');
    Cells := Accent.MoraCells; X := (Cells[40].Left+Cells[40].Right) div 2;
    Paint.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,MulDiv(62,Accent.CurrentPPI,96)));
    Paint.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    Paint.Perform(WM_LBUTTONUP,0,MakeLParam(X,MulDiv(24,Accent.CurrentPPI,96)));
    Deadline := GetTickCount64+3000;
    repeat Application.ProcessMessages; Sleep(10); until (RequestCount('/mora_data?')>RequestsBeforeSwitch) or (GetTickCount64>Deadline);
    Check(RequestCount('/mora_data?')>RequestsBeforeSwitch,'stale-result probe reaches an active mora request');
    var BeforeSwitch := C.VoiceQuery;
    Settings.ShowRow('','',-1,TSerifVoicevoxAudioValues.Defaults,'','');
    Deadline := GetTickCount64+700;
    repeat Application.ProcessMessages; Sleep(10); until GetTickCount64>Deadline;
    Check((C.VoiceQuery=BeforeSwitch) and not Settings.HasQuery,'switching rows cancels an active request and discards its stale display result');
    Settings.ShowRow(C.SpokenText,S.VoiceUuid,W.ScriptDraft.EffectiveStyle(C),Values,C.VoiceQuery,W.ScriptDraft.EngineUrl);
    if FindCmdLineSwitch('check-dpi') then for var Ppi in [96,144,192] do begin
      Main.Scaled := True; Main.ScaleForPPI(Ppi); Main.Scaled := False;
      Main.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(900,Ppi,96)); Settings.ApplyDpi; Main.Update;
      Accent.ScrollPosition := MulDiv(180,Ppi,96); var At := Accent.ScrollPosition;
      var Rect := Settings.BoundsRect; var PointBefore := Accent.ClientToScreen(Point(0,0));
      for var I := 1 to 10 do Frame.RefreshState;
      Check((Accent.ScrollPosition=At) and (Settings.BoundsRect=Rect) and
        (Accent.ClientToScreen(Point(0,0))=PointBefore),'repeated accent page refresh preserves layout and scroll at '+Ppi.ToString+' DPI');
      CheckVoiceNoticeLayout(Frame,Settings);
      Capture('voice-accent-'+Ppi.ToString);
    end;
  finally W.OnScriptChanged := Probe.Previous; Probe.Free; Metrics.Free; Creator.SetActive(False); end;
  if FindCmdLineSwitch('check-dpi') then begin Main.Scaled := True; Main.ScaleForPPI(96); Main.Scaled := False; Main.SetBounds(0,0,1440,900); end;
end;
procedure CheckCommonVoiceSettings;
begin
  var Frame := StageFrame(TRigmScriptVoiceFrame) as TRigmScriptVoiceFrame;
  var Settings := Frame.FindComponent('ScriptVoiceDetails') as TFrameSerifVoicevoxSettings;
  var Toolbar := Settings.FindComponent('VoicevoxPages') as TVoicevoxToolbarButtons;
  var Values: TFrameSerifVoicevoxAudioSettings := nil;
  for var I := 0 to Settings.ComponentCount-1 do
    if Settings.Components[I] is TFrameSerifVoicevoxAudioSettings then Values := Settings.Components[I] as TFrameSerifVoicevoxAudioSettings;
  var Id := JS(JO(W.ScriptDraft.ScriptWizard,'voice'),'selectedCue');
  var SelectedQuery := W.ScriptDraft.Cue(Id).VoiceQuery;
  var Queries: TArray<string>; SetLength(Queries,W.ScriptDraft.Cues.Count);
  var Files: TArray<string>; SetLength(Files,W.ScriptDraft.Cues.Count);
  var Source := ScriptFingerprint(W.ScriptDraft);
  for var I := 0 to W.ScriptDraft.Cues.Count-1 do begin
    var C := W.ScriptDraft.Cues[I]; Queries[I] := C.VoiceQuery;
    C.WaveFile := TPath.Combine(Root,'accent-owned.wav'); C.AudioSeconds := 0.5; Files[I] := C.WaveFile;
    C.AudioKey := W.ScriptDraft.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  end;
  W.ScriptDraft.Changed; W.SaveScriptDraft(False); Creator.SetActive(True);
  for var I := 0 to W.ScriptDraft.Cues.Count-1 do Files[I] := W.ScriptDraft.Cues[I].WaveFile;
  Check(Settings.PanelVoice.Showing and Settings.PanelAccent.Showing and
    (Settings.PanelVoice.Parent=Settings.PanelAccent.Parent),'common settings and accent stay together on one page');
  var Visible := 0; for var I := 0 to Toolbar.ControlCount-1 do if Toolbar.Controls[I].Visible then Inc(Visible);
  Check((Visible=2) and (Toolbar.ActivePage=vtpAccent),'voice toolbar keeps playback controls and removes page switching');
  var Slider := Values.FindComponent('VoicevoxValue0') as TVerticalSliderControl;
  var Rect := Settings.BoundsRect; var Origin := Settings.PanelAccent.ClientToScreen(Point(0,0));
  var Requests := TPath.Combine(ExtractFileDir(ParamStr(3)),'requests.txt'); var BeforeRequests := TFile.ReadAllText(Requests);
  var Revision := W.ScriptDraft.Revision; Slider.Position := 1.25;
  Check((W.ScriptDraft.Revision=Revision+1) and (JN(JO(JO(W.ScriptDraft.ScriptWizard,'voice'),'commonSettings'),'speedScale')=1.25),
    'native basic slider saves one common value immediately');
  var Invalid := True; var Retained := True; var Common := True;
  for var I := 0 to W.ScriptDraft.Cues.Count-1 do begin
    var C := W.ScriptDraft.Cues[I];
    Common := Common and (JN(W.ScriptDraft.EffectiveVoiceSettings(C),'speedScale')=1.25);
    Invalid := Invalid and not W.ScriptDraft.AudioReady(C) and not W.ScriptDraft.AudioHeard(C) and (C.AudioKey='') and (C.VoiceHeardKey='');
    Retained := Retained and (C.VoiceQuery=Queries[I]) and (C.WaveFile=Files[I]) and FileExists(ResolveMoviePath(W.ScriptDraft.FileName,C.WaveFile));
  end;
  Check(Common and Invalid,'common setting invalidates generated and heard approval for every cue');
  Check(Retained and (ScriptFingerprint(W.ScriptDraft)=Source),'common change preserves individual accent queries, stored files and script');
  Sleep(350); Application.ProcessMessages; Main.Update;
  Check(not W.VoiceBusy and (TFile.ReadAllText(Requests)=BeforeRequests) and Slider.Enabled,
    'common parameter editing leaves controls enabled and starts no VOICEVOX request');
  Check((Settings.BoundsRect=Rect) and (Settings.PanelAccent.ClientToScreen(Point(0,0))=Origin) and Settings.PanelVoice.Showing,
    'common setting refresh keeps the accent page and its coordinates');
  W.SelectVoice(W.ScriptDraft.Cues[1].Id);
  Check(Abs(Settings.RowValues.SpeedScale-1.25)<0.0001,'selecting another cue displays the same common settings');
  var C := W.ScriptDraft.Cue(Id); var Before := W.ScriptDraft.Revision;
  var Bad := TJSONObject.Create;
  try
    AddN(Bad,'speedScale',9); var Rejected := False;
    try W.EditVoice(Id,'上書き',Bad); except on E: Exception do Rejected := True; end;
    Check(Rejected and (W.ScriptDraft.Revision=Before) and (JN(W.ScriptDraft.EffectiveVoiceSettings(C),'speedScale')=1.25),
      'invalid common setting is rejected before reading or project state changes');
  finally Bad.Free; end;
  W.SaveScriptDraft(False); var Saved := LoadMovie(W.ScriptDraft.FileName);
  try
    Common := True; for var Cue in Saved.Cues do Common := Common and (JN(Saved.EffectiveVoiceSettings(Cue),'speedScale')=1.25);
    Check(Common and (Saved.Cue(Id).VoiceQuery=SelectedQuery),'common values and individual accent edits survive save and reload');
    var NewCue := TRigmMovieCue.Create;
    try Check(JN(Saved.EffectiveVoiceSettings(NewCue),'speedScale')=1.25,'new cues inherit the project common settings'); finally NewCue.Free; end;
  finally Saved.Free; end;
  Capture('voice-common-settings'); Creator.SetActive(False);
end;
