// 音声ジョブをページより長く所有する。音声が一致する1cueの結果だけを回収する。
function TRigmWizardWorkspace.VoiceBusy: Boolean;
begin Result := (FVoiceJob<>nil) and not FVoiceJob.Done; end;
function TRigmWizardWorkspace.VoiceCatalog: TJSONArray;
begin Result := FVoiceCatalog; end;
function TRigmWizardWorkspace.VoiceCatalogReady: Boolean;
begin Result := (FScriptDraft<>nil) and (FVoiceCatalogUrl=FScriptDraft.EngineUrl) and (FVoiceCatalog.Count>0); end;
function TRigmWizardWorkspace.VoiceConnectionStatus: TJSONObject;
begin
  Result := TJSONObject.Create; AddB(Result,'busy',VoiceBusy); Result.AddPair('error',FVoiceError);
  AddB(Result,'catalogReady',VoiceCatalogReady); AddN(Result,'catalogCount',FVoiceCatalog.Count); Result.AddPair('catalogUrl',FVoiceCatalogUrl);
  if FVoiceJob<>nil then Result.AddPair('job',FVoiceJob.Status);
end;
function TRigmWizardWorkspace.CastingAdvanceReason(RequireConnection: Boolean): string;
begin
  Result := '';
  if (FScriptDraft=nil) or not (FScriptDraft.ScriptWizard.GetValue('casting') is TJSONObject) then Exit('配役工程でキャラと声を設定してください。');
  var Cast := ScriptCastingSummary(FScriptDraft);
  try
    if (JS(Cast,'state')='stale') or (JS(JO(FScriptDraft.ScriptWizard,'casting'),'sourceFingerprint')<>ScriptFingerprint(FScriptDraft)) then Exit('前工程が変わりました。校正から配役を確認してください。');
    if not JB(Cast,'rolesComplete') then Exit('配役工程で全セリフのキャラ番号を指定・確認してください。');
    if not JB(Cast,'voicesComplete') then Exit('配役工程で、台本で使用するキャラの声の人物を選択してください（未設定 '+JI(Cast,'missingVoices').ToString+'人）。');
    if not RequireConnection then Exit;
    if VoiceBusy then Exit('VOICEVOXの接続・話者一覧取得が終わるまでお待ちください。');
    if not VoiceCatalogReady then Exit('VOICEVOXの確認を待ってください。見つからない場合は実行ファイルを手動設定してください。');
    for var N in JA(Cast,'usedRoles') do begin
      var Role := CastingRole(FScriptDraft,StrToInt(N.Value)); var S := FScriptDraft.Speaker(JS(Role,'speakerId')); var Found := False;
      for var V in FVoiceCatalog do if (JI(TJSONObject(V),'styleId',-1)=S.StyleId) and (JS(TJSONObject(V),'uuid')=S.VoiceUuid) then Found := True;
      if not Found then Exit(JS(Role,'name')+'の声が現在のVOICEVOX一覧にありません。配役工程で選び直してください。');
    end;
    for var V in JA(JO(FScriptDraft.ScriptWizard,'casting'),'rows') do begin
      var C := FScriptDraft.Cue(JS(TJSONObject(V),'cueId')); var S := FScriptDraft.Speaker(C.SpeakerId);
      if FindVoiceStyle(FVoiceCatalog,S.VoiceUuid,FScriptDraft.EffectiveStyle(C))=nil then Exit('セリフの感情がこの人物の一覧にありません。感情を選び直してください。');
    end;
  finally Cast.Free; end;
end;
procedure TRigmWizardWorkspace.StopVoice;
begin
  CloseVoicePlayback; FPlayVoice := '';
  if FVoiceContinuous then begin
    FVoiceContinuous := False; FVoiceSequenceStatus := '連続再生を停止しました。';
    if (FVoiceSequencePhase='generating') and VoiceBusy then FVoiceJob.Cancel;
  end;
  FVoiceSequencePhase := ''; FVoiceSequenceOrder := nil;
end;
procedure TRigmWizardWorkspace.CancelVoice;
begin
  StopVoice; if FVoiceJob<>nil then FVoiceJob.Cancel;
  // 音声欄だけでなく上段Nextにも、停止後の再生・生成状態を通知する。
  ScriptChanged;
end;
procedure TRigmWizardWorkspace.PollScriptVoice;
begin
  if (FVoiceJob=nil) or not FVoiceJob.Done or FVoiceCollected then Exit; FVoiceCollected := True;
  var State := FVoiceJob.Status; var AcceptedAudio := False;
  try
    FVoiceError := JS(State,'error');
    if (FScriptDraft<>nil) and (FScriptDraft.Id=FVoiceJob.Project.Id) and (JS(State,'state')='succeeded') then begin
      if ((FVoiceJob.Kind='speakers') or (FVoiceJob.Kind='voice-engine')) and (FScriptDraft.EngineUrl=FVoiceJob.Project.EngineUrl) then begin
        FVoiceCatalog.Free; FVoiceCatalog := TJSONObject.ParseJSONValue(FVoiceJob.Catalog) as TJSONArray; FVoiceCatalogUrl := FScriptDraft.EngineUrl;
        if NormalizeVoicePeople(FScriptDraft,FVoiceCatalog) then FScriptDraft.Changed;
      end;
      if (FVoiceJob.Kind='audio') then begin
        var Valid := True; try RequireCurrentVoice(FScriptDraft); except on E: Exception do Valid := False; end;
        if Valid then for var C in FVoiceJob.Project.Cues do begin
          if C.Id<>FVoiceTarget then Continue;
          var Target := FScriptDraft.Cue(C.Id);
          if (Target<>nil) and (C.AudioKey<>FScriptDraft.AudioFingerprint(Target)) then FVoiceError := '入力が変わったため古い音声結果は採用しません。旧音声は保持しています。';
          if (Target<>nil) and FVoiceJob.Project.AudioReady(C) and (C.AudioKey=FScriptDraft.AudioFingerprint(Target)) then begin
            AcceptedAudio := True; Target.WaveFile := C.WaveFile; Target.LabFile := C.LabFile; Target.AudioSeconds := C.AudioSeconds; Target.AudioKey := C.AudioKey; Target.VoiceHeardKey := ''; RefreshScriptVoiceCompletion(FScriptDraft); FScriptDraft.Changed;
          end;
        end;
        if FPlayVoice<>'' then begin
          var C := FScriptDraft.Cue(FPlayVoice);
          if Valid and (C<>nil) and FScriptDraft.AudioReady(C) then
            try StartVoicePlayback(C.Id); except on E: Exception do FVoiceError := E.Message; end;
        end;
      end;
    end;
    FPlayVoice := '';
    if FVoiceContinuous and (FVoiceSequencePhase='generating') then begin
      var C := FScriptDraft.Cue(FVoiceTarget);
      if AcceptedAudio and (FScriptDraft.Id=FVoiceSequenceProjectId) and (CurrentScriptStage='voice') and (JS(State,'state')='succeeded') and (FVoiceError='') and (C<>nil) and FScriptDraft.AudioReady(C) then
        try StartVoicePlayback(C.Id); except on E: Exception do begin FVoiceError := E.Message; StopVoice; end; end
      else begin if FVoiceError='' then FVoiceError := '選択行の音声結果を採用できないため連続再生を停止しました。'; StopVoice; end;
    end;
    ScriptChanged;
  finally State.Free; end;
end;
procedure TRigmWizardWorkspace.SelectVoice(const CueId: string);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。');
  if FScriptDraft.Cue(CueId)=nil then raise Exception.Create('音声セリフがありません。');
  if JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue')=CueId then Exit;
  StopVoice; FVoiceAutoGenerationKey := ''; PsdJson.Put(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue',CueId); FScriptDraft.Changed; ScriptChanged; EnsureSelectedVoice;
end;
procedure TRigmWizardWorkspace.SetVoiceAutoGeneration(Value: Boolean);
begin
  if FVoiceAutoGenerationActive=Value then Exit;
  FVoiceAutoGenerationActive := Value; FVoiceAutoGenerationKey := '';
end;
procedure TRigmWizardWorkspace.EnsureSelectedVoice;
begin
  if not FVoiceAutoGenerationActive or (FScriptDraft=nil) or (CurrentScriptStage<>'voice') or
    FScriptTextEditing or VoiceBusy or VoicePlaying or VoiceContinuous or not VoiceCatalogReady then Exit;
  var C := FScriptDraft.Cue(JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue'));
  if (C=nil) or FScriptDraft.AudioReady(C) or (C.SpokenText='') then Exit;
  var Key := FScriptDraft.Id+'|'+C.Id+'|'+FScriptDraft.AudioFingerprint(C);
  if FVoiceAutoGenerationKey=Key then Exit; FVoiceAutoGenerationKey := Key;
  try GenerateVoice(C.Id,False); except on E: Exception do begin FVoiceError := E.Message; ScriptChanged; end; end;
end;
procedure TRigmWizardWorkspace.MoveVoice(Delta: Integer);
begin var C := FScriptDraft.Cue(JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue')); SelectVoice(FScriptDraft.Cues[EnsureRange(FScriptDraft.Cues.IndexOf(C)+Delta,0,FScriptDraft.Cues.Count-1)].Id); end;
procedure TRigmWizardWorkspace.EditVoice(const CueId,Reading: string; Settings: TJSONObject);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。');
  EditScriptVoice(FScriptDraft,CueId,Reading,Settings);
  if FScriptDraft.Cue(CueId)=ScriptSummaryCue(FScriptDraft) then begin var O := JO(FScriptDraft.ScriptWizard,'summaryData'); PsdJson.Put(JO(O,'draft'),'reading',FScriptDraft.Cue(CueId).VoiceReading); PsdJson.Put(JO(O,'appliedDraft'),'reading',FScriptDraft.Cue(CueId).VoiceReading); end;
  StopVoice; FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetVoiceEngine(const Url: string);
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) or VoiceBusy then raise Exception.Create('配役・音声工程のジョブ終了後に接続先を変更してください。');
  var Copy := FScriptDraft.Clone;
  try Copy.EngineUrl := Url.Trim; Copy.Validate; FScriptDraft.EngineUrl := Copy.EngineUrl; finally Copy.Free; end;
  StopVoice; FVoiceCatalog.Free; FVoiceCatalog := TJSONArray.Create; FVoiceCatalogUrl := ''; FVoiceError := '';
  PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.RefreshVoiceCatalog;
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) or VoiceBusy or VoiceContinuous then raise Exception.Create('配役・音声工程のジョブ終了後に一覧を取得してください。');
  StopVoice;
  FreeAndNil(FVoiceJob); FVoiceCollected := False; FVoiceError := ''; FVoiceCatalog.Free; FVoiceCatalog := TJSONArray.Create; FVoiceCatalogUrl := '';
  FVoiceJob := TRigmMovieJob.Create(FScriptDraft,'speakers','',0); FVoiceJob.Start; ScriptChanged;
end;
procedure TRigmWizardWorkspace.PrepareVoiceEngine(const EngineExe: string);
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) or VoiceBusy then raise Exception.Create('配役・音声工程のジョブ終了後にVOICEVOXを準備してください。');
  StopVoice; FreeAndNil(FVoiceJob); FVoiceCollected := False; FVoiceError := '';
  FVoiceCatalog.Free; FVoiceCatalog := TJSONArray.Create; FVoiceCatalogUrl := '';
  var O := TJSONObject.Create;
  try O.AddPair('engineExe',EngineExe); FVoiceJob := TRigmMovieJob.Create(FScriptDraft,'voice-engine','',0,O); finally O.Free; end;
  FVoiceJob.Start; ScriptChanged;
end;
procedure TRigmWizardWorkspace.EditVoiceQuery(const CueId, QueryJson: string);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。');
  RequireCurrentVoice(FScriptDraft); var C := FScriptDraft.Cue(CueId);
  if C=nil then raise Exception.Create('詳細queryを保存する行がありません。');
  ValidateVoiceQuery(QueryJson); var Key := FScriptDraft.VoiceQuerySourceKey(C);
  if (C.VoiceQuery=QueryJson) and (C.VoiceQueryKey=Key) then Exit;
  StopVoice; C.VoiceQuery := QueryJson; C.VoiceQueryKey := Key;
  PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.BindVoice(Number,StyleId: Integer; const Uuid: string);
begin
  // 旧パイプのstyleIdは人物の所属確認だけに使う。行別状態はSetVoiceStateで設定する。
  if FindVoiceStyle(FVoiceCatalog,Uuid,StyleId)=nil then raise Exception.Create('実話者一覧のUUIDとstyleIdを選んでください。');
  BindVoicePerson(Number,Uuid);
end;
procedure TRigmWizardWorkspace.BindVoicePerson(Number: Integer; const Uuid: string);
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) or VoiceBusy or VoiceContinuous then raise Exception.Create('配役・音声工程の処理終了後に人物を選択してください。'); RequireCurrentVoice(FScriptDraft);
  if not VoiceCatalogReady then raise Exception.Create('現在の接続先から実話者一覧を取得してください。');
  if not BindScriptVoicePerson(FScriptDraft,FVoiceCatalog,Number,Uuid) then Exit;
  RefreshScriptCastingStatus(FScriptDraft); StopVoice; PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetVoiceState(const CueId: string; StyleId: Integer);
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) or VoiceBusy or VoiceContinuous then raise Exception.Create('配役・音声工程の処理終了後に感情を選択してください。'); RequireCurrentVoice(FScriptDraft);
  if not VoiceCatalogReady then raise Exception.Create('現在の接続先から実話者一覧を取得してください。');
  if not SetScriptVoiceState(FScriptDraft,FVoiceCatalog,CueId,StyleId) then Exit;
  StopVoice; PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.GenerateVoice(const CueId: string; Play: Boolean; ForSequence: Boolean);
begin
  if (CurrentScriptStage<>'voice') or VoiceBusy then raise Exception.Create('音声ジョブの終了後に試聴してください。'); RequireCurrentVoice(FScriptDraft);
  var C := FScriptDraft.Cue(CueId); if C=nil then raise Exception.Create('選択セリフがありません。');
  if FScriptDraft.AudioReady(C) then begin if Play then begin StopVoice; StartVoicePlayback(CueId); ScriptChanged; end; Exit; end;
  var S := FScriptDraft.Speaker(C.SpeakerId); var Found := False;
  if FVoiceCatalogUrl=FScriptDraft.EngineUrl then for var V in FVoiceCatalog do
    if (JI(TJSONObject(V),'styleId',-1)=FScriptDraft.EffectiveStyle(C)) and (JS(TJSONObject(V),'uuid')=S.VoiceUuid) and (S.VoiceUuid<>'') then Found := True;
  if not Found then raise Exception.Create('実一覧から選択セリフのキャラへ声を紐付けてください。');
  if not ForSequence then StopVoice else CloseVoicePlayback; FreeAndNil(FVoiceJob); FVoiceCollected := False; FVoiceError := ''; if Play then FPlayVoice := CueId;
  var O := TJSONObject.Create;
  try O.AddPair('cueId',CueId); FVoiceJob := TRigmMovieJob.Create(FScriptDraft,'audio',TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Audio'),0,O); finally O.Free; end;
  FVoiceTarget := CueId; FVoiceJob.Start; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteVoice;
begin
  EndScriptTextEdit; RequireCurrentVoice(FScriptDraft);
  if VoiceBusy or VoicePlaying or VoiceContinuous then raise Exception.Create('音声生成・再生の終了後に確認してください。');
  for var C in FScriptDraft.Cues do if not FScriptDraft.AudioHeard(C) then raise Exception.Create('未再生または変更後のセリフを最後まで再生してください（F5／Shift+F5）。');
  PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','complete'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.VoiceStatus: TJSONObject;
begin
  PollScriptVoice; Result := ScriptVoiceSummary(FScriptDraft);
  AddB(Result,'playing',VoicePlaying); AddB(Result,'continuous',VoiceContinuous); Result.AddPair('playingCue',FVoicePlaybackCue);
  Result.AddPair('sequenceStatus',FVoiceSequenceStatus); Result.AddPair('sequencePhase',FVoiceSequencePhase); AddN(Result,'sequenceIndex',FVoiceSequenceIndex+1); AddN(Result,'sequenceTotal',Length(FVoiceSequenceOrder)); AddB(Result,'busy',VoiceBusy); Result.AddPair('error',FVoiceError); AddN(Result,'catalogCount',FVoiceCatalog.Count); Result.AddPair('catalogUrl',FVoiceCatalogUrl);
  if FVoiceJob<>nil then Result.AddPair('job',FVoiceJob.Status);
end;
function TRigmWizardWorkspace.ReadVoice(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで音声を取得してください。');
  Result := VoiceStatus; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  var A := TJSONArray.Create; Result.AddPair('rows',A); var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Cues.Count);
  if Offset<FScriptDraft.Cues.Count then begin
    var C := FScriptDraft.Cues[Offset]; var O := TJSONObject.Create; A.AddElement(O); O.AddPair('cueId',C.Id); O.AddPair('sourceText',C.Text); O.AddPair('reading',C.SpokenText); O.AddPair('subtitle',C.Subtitle);
    O.AddPair('query',FScriptDraft.EffectiveVoiceQuery(C));
    AddN(O,'voiceStyleId',C.VoiceStyleId); AddN(O,'effectiveStyleId',FScriptDraft.EffectiveStyle(C));
    O.AddPair('settings',C.VoiceSettings.Clone as TJSONObject); O.AddPair('sceneId',C.Scene); AddN(O,'role',ScriptCueRole(FScriptDraft,C.Id));
    var S := FScriptDraft.Speaker(C.SpeakerId); O.AddPair('speaker',S.Json); AddB(O,'ready',FScriptDraft.AudioReady(C)); AddB(O,'stored',FScriptDraft.HasStoredAudio(C));
    AddB(O,'heard',FScriptDraft.AudioHeard(C)); O.AddPair('audioEffect',C.AudioEffect);
    O.AddPair('waveFile',C.WaveFile); O.AddPair('labFile',C.LabFile); AddN(O,'audioSeconds',C.AudioSeconds); O.AddPair('audioKey',C.AudioKey);
  end;
  AddN(Result,'nextOffset',Offset+A.Count); AddB(Result,'hasMore',Offset+A.Count<FScriptDraft.Cues.Count);
end;
function TRigmWizardWorkspace.ReadVoiceCatalog(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで取得してください。');
  Result := TJSONObject.Create; var A := TJSONArray.Create; Result.AddPair('styles',A); var Offset := EnsureRange(JI(Args,'offset'),0,FVoiceCatalog.Count);
  for var I := Offset to Min(Offset+20,FVoiceCatalog.Count)-1 do A.AddElement(FVoiceCatalog[I].Clone as TJSONObject);
  Result.AddPair('engineUrl',FVoiceCatalogUrl); AddB(Result,'busy',VoiceBusy); AddN(Result,'nextOffset',Offset+A.Count); AddB(Result,'hasMore',Offset+A.Count<FVoiceCatalog.Count);
end;
function TRigmWizardWorkspace.ScriptResumeView(Project: TRigmMovieProject): string;
begin
  Result := JS(Project.ScriptWizard,'stage');
  if (ScriptStageIndex(Result)>ScriptStageIndex('scenes')) and (Result<>'editor') and (Project.ScriptWizard.GetValue('scenes')<>nil) and not ScriptScenesReady(Project) then Result := 'scenes';
  // 旧版のシーン画像画面で保存した台本も、未確認なら先にセリフの割当を表示する。
  if (Result='scenes') and (JS(Project.ScriptWizard,'scene-assignmentStatus')<>'complete') then Result := 'scene-assignment';
  if (ScriptStageIndex(Result)>ScriptStageIndex('casting')) and (Project.ScriptWizard.GetValue('casting') is TJSONObject) and (MissingCastingVoices(Project)>0) then Result := 'casting';
end;
function TRigmWizardWorkspace.RestoreStoredCastingVoices(Project: TRigmMovieProject): Boolean;
begin
  Result := False;
  if (Project=nil) or not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  EnsureVoiceBindings;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'roles') do begin
    var Role := TJSONObject(V); if not JB(Role,'active') then Continue;
    var S := Project.Speaker(JS(Role,'speakerId')); if (S=nil) or (S.StyleId>=0) then Continue;
    var Key := LowerCase(JS(Role,'path')); if not (FVoiceBindings.GetValue(Key) is TJSONObject) then Continue;
    var Binding := JO(FVoiceBindings,Key);
    if (JI(Binding,'styleId',-1)<0) or (JS(Binding,'uuid')='') then Continue;
    S.StyleId := JI(Binding,'styleId'); S.VoiceUuid := JS(Binding,'uuid'); S.VoiceName := JS(Binding,'name'); S.StyleName := JS(Binding,'style'); Result := True;
  end;
  RefreshScriptCastingStatus(Project);
  if Result and (Project.ScriptWizard.GetValue('voice')<>nil) then PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
end;
procedure TRigmWizardWorkspace.EnsureVoiceBindings;
begin
  if FVoiceBindings<>nil then Exit; var Path := FPipe.Workspace.Resolve('CharacterVoiceBindings.json',False);
  FVoiceBindingsHash := ''; FVoiceBindings := TJSONObject.Create;
  if not FileExists(Path) then Exit;
  try
    var Hash := THashSHA2.GetHashStringFromFile(Path);
    var O := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
    try if (JS(O,'format')<>'RIGMMaker.CharacterVoiceBindings') or (JI(O,'schemaVersion')<>1) or not (O.GetValue('bindings') is TJSONObject) then raise Exception.Create('登録キャラの音声設定形式が不正です。');
      if Hash<>THashSHA2.GetHashStringFromFile(Path) then raise Exception.Create('登録音声設定が読込中に変わりました。再取得してください。');
      var Bindings := JO(O,'bindings').Clone as TJSONObject; FVoiceBindings.Free; FVoiceBindings := Bindings; FVoiceBindingsHash := Hash;
    finally O.Free; end;
  except FreeAndNil(FVoiceBindings); raise; end;
end;
procedure TRigmWizardWorkspace.SaveCharacterVoice(Number: Integer);
begin
  if not MatchText(CurrentScriptStage,['casting','voice']) then raise Exception.Create('配役・音声工程で声を保存してください。'); RequireCurrentVoice(FScriptDraft); EnsureVoiceBindings;
  var Role := CastingRole(FScriptDraft,Number); if (Role=nil) or not JB(Role,'active') then raise Exception.Create('登録キャラを選んでください。');
  var S := FScriptDraft.Speaker(JS(Role,'speakerId')); if (S.StyleId<0) or (S.VoiceUuid='') then raise Exception.Create('実一覧から声を紐付けてください。');
  var Path := FPipe.Workspace.Resolve('CharacterVoiceBindings.json',False); var Lock := TMutex.Create(nil,False,'Local\RIGMMaker.VoiceBindings.'+THashSHA2.GetHashString(LowerCase(Path)));
  try if Lock.WaitFor(1000)<>wrSignaled then raise Exception.Create('登録キャラの音声設定を他の操作が保存中です。');
    try
      var Current := ''; if FileExists(Path) then Current := THashSHA2.GetHashStringFromFile(Path);
      if Current<>FVoiceBindingsHash then raise Exception.Create('登録音声設定が外部で変わりました。再起動で再取得してから保存してください。');
      var Next := FVoiceBindings.Clone as TJSONObject; var O := TJSONObject.Create; var Temporary := Path+'.'+PsdJson.NewId+'.pending';
      try
        var B := TJSONObject.Create; B.AddPair('uuid',S.VoiceUuid); B.AddPair('name',S.VoiceName); B.AddPair('style',S.StyleName); AddN(B,'styleId',S.StyleId); B.AddPair('engineUrl',FScriptDraft.EngineUrl);
        PsdJson.Put(Next,LowerCase(JS(Role,'path')),B); O.AddPair('format','RIGMMaker.CharacterVoiceBindings'); AddN(O,'schemaVersion',1); O.AddPair('bindings',Next.Clone as TJSONObject);
        TFile.WriteAllText(Temporary,O.ToJSON,TEncoding.UTF8); var WrittenHash := THashSHA2.GetHashStringFromFile(Temporary);
        if not MoveFileEx(PChar(Temporary),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
        FVoiceBindings.Free; FVoiceBindings := Next; Next := nil; FVoiceBindingsHash := WrittenHash;
      finally if FileExists(Temporary) then TFile.Delete(Temporary); Next.Free; O.Free; end;
    finally Lock.Release; end;
  finally Lock.Free; end;
end;

// MCIの再生終了を監視し、選択行から末尾まで1行ずつ生成・再生する。
function TRigmWizardWorkspace.VoicePlaying: Boolean;
begin Result := FVoicePlaybackAlias<>''; end;
function TRigmWizardWorkspace.VoiceContinuous: Boolean;
begin Result := FVoiceContinuous; end;
procedure TRigmWizardWorkspace.CloseVoicePlayback;
begin
  if FVoicePlaybackAlias<>'' then mciSendString(PChar('close '+FVoicePlaybackAlias),nil,0,0);
  FVoicePlaybackAlias := ''; FVoicePlaybackCue := ''; FVoicePlaybackKey := '';
  if (FVoicePlaybackTempFile<>'') and FileExists(FVoicePlaybackTempFile) then TFile.Delete(FVoicePlaybackTempFile);
  FVoicePlaybackTempFile := '';
end;
procedure TRigmWizardWorkspace.StartVoicePlayback(const CueId: string);
  procedure CheckMci(Code: MCIERROR);
  begin
    if Code<>0 then begin var MessageText: array[0..255] of Char; mciGetErrorString(Code,MessageText,Length(MessageText)); raise Exception.Create('音声再生に失敗しました: '+string(MessageText)); end;
  end;
  procedure Send(const Command: string);
  begin
    CheckMci(mciSendString(PChar(Command),nil,0,0));
  end;
begin
  CloseVoicePlayback;
  var C := FScriptDraft.Cue(CueId);
  if (C=nil) or not FScriptDraft.AudioReady(C) then raise Exception.Create('現在の入力に一致する音声がありません。');
  if C.SpokenText='' then begin FVoiceSequencePhase := 'pause'; FVoicePauseUntil := GetTickCount64+Round(C.Pause*1000); Exit; end;
  var Path := ResolveMoviePath(FScriptDraft.FileName,C.WaveFile);
  if Pos('"',Path)>0 then raise Exception.Create('音声ファイル名に引用符を含められません。');
  FVoicePlaybackAlias := 'RigmVoice'+IntToHex(GetCurrentProcessId,8)+IntToHex(NativeUInt(Self),SizeOf(Pointer)*2);
  try
    // MCI waveaudioの長いファイル名制限は構造体版openでも残る。原本を保持し、再生用コピーだけを所有する。
    if Length(Path)>120 then begin
      FVoicePlaybackTempFile := TPath.Combine(TPath.GetTempPath,'RigmVoice-'+PsdJson.NewId+'.wav');
      TFile.Copy(Path,FVoicePlaybackTempFile,False); Path := FVoicePlaybackTempFile;
    end;
    Send('open "'+Path+'" type waveaudio alias '+FVoicePlaybackAlias);
    Send('set '+FVoicePlaybackAlias+' time format milliseconds');
    Send('play '+FVoicePlaybackAlias);
    FVoicePlaybackCue := CueId; FVoicePlaybackKey := FScriptDraft.AudioFingerprint(C); FVoiceSequencePhase := 'playing';
  except CloseVoicePlayback; raise; end;
end;
procedure TRigmWizardWorkspace.StartVoiceContinuous(const CueId: string);
begin
  if (CurrentScriptStage<>'voice') or VoiceBusy then raise Exception.Create('音声ジョブを終了してから連続再生してください。');
  RequireCurrentVoice(FScriptDraft); var C := FScriptDraft.Cue(CueId);
  if C=nil then raise Exception.Create('連続再生の開始行を選択してください。');
  StopVoice; FVoiceError := ''; FVoiceSequenceProjectId := FScriptDraft.Id; FVoiceSequenceIndex := 0;
  var First := FScriptDraft.Cues.IndexOf(C); SetLength(FVoiceSequenceOrder,FScriptDraft.Cues.Count-First);
  for var I := First to FScriptDraft.Cues.Count-1 do FVoiceSequenceOrder[I-First] := FScriptDraft.Cues[I].Id;
  FVoiceContinuous := True; FVoiceSequenceStatus := '連続再生中';
  try AdvanceVoiceContinuous; except on E: Exception do begin FVoiceError := E.Message; StopVoice; raise; end; end;
end;
procedure TRigmWizardWorkspace.AdvanceVoiceContinuous;
begin
  if not FVoiceContinuous then Exit;
  if FVoiceSequenceIndex>=Length(FVoiceSequenceOrder) then begin
    StopVoice; FVoiceSequenceStatus := '連続再生が最後まで完了しました。'; ScriptChanged; Exit;
  end;
  if (FScriptDraft=nil) or (FScriptDraft.Id<>FVoiceSequenceProjectId) or (CurrentScriptStage<>'voice') then raise Exception.Create('作品または工程が変わったため連続再生を停止しました。');
  RequireCurrentVoice(FScriptDraft);
  var Id := FVoiceSequenceOrder[FVoiceSequenceIndex]; var C := FScriptDraft.Cue(Id);
  if C=nil then raise Exception.Create('連続再生する行が変更されたため停止しました。');
  if JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue')<>Id then begin
    PsdJson.Put(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue',Id); FScriptDraft.Changed;
  end;
  if FScriptDraft.AudioReady(C) then StartVoicePlayback(Id)
  else begin FVoiceSequencePhase := 'generating'; GenerateVoice(Id,False,True); end;
  ScriptChanged;
end;
procedure TRigmWizardWorkspace.PollVoicePlayback;
begin
  if not VoicePlaying and not FVoiceContinuous then Exit;
  try
    if VoicePlaying then begin
      var C := FScriptDraft.Cue(FVoicePlaybackCue);
      if (C=nil) or (FVoicePlaybackKey<>FScriptDraft.AudioFingerprint(C)) then raise Exception.Create('再生中の入力が変わったため停止しました。');
      var Mode: array[0..31] of Char;
      if mciSendString(PChar('status '+FVoicePlaybackAlias+' mode'),Mode,Length(Mode),0)<>0 then raise Exception.Create('再生状態を取得できないため停止しました。');
      if SameText(string(Mode),'playing') then Exit;
      if not SameText(string(Mode),'stopped') then raise Exception.Create('音声再生が中断されたため停止しました。');
      var LengthText,PositionText: array[0..31] of Char; var Duration,Position: Integer;
      if (mciSendString(PChar('status '+FVoicePlaybackAlias+' length'),LengthText,Length(LengthText),0)<>0) or
        (mciSendString(PChar('status '+FVoicePlaybackAlias+' position'),PositionText,Length(PositionText),0)<>0) or
        not TryStrToInt(string(LengthText),Duration) or not TryStrToInt(string(PositionText),Position) or (Position<Duration) then
        raise Exception.Create('音声が最後まで再生されていないため確認完了にしません。');
      if MarkScriptVoiceHeard(FScriptDraft,C.Id,FVoicePlaybackKey) then FScriptDraft.Changed;
      var Pause := C.Pause; CloseVoicePlayback;
      if FVoiceContinuous then begin FVoiceSequencePhase := 'pause'; FVoicePauseUntil := GetTickCount64+Round(Pause*1000); ScriptChanged; end
      else begin FVoiceSequencePhase := ''; ScriptChanged; end;
    end;
    if FVoiceContinuous and (FVoiceSequencePhase='pause') and (GetTickCount64>=FVoicePauseUntil) then begin
      Inc(FVoiceSequenceIndex); AdvanceVoiceContinuous;
    end;
  except on E: Exception do begin FVoiceError := E.Message; StopVoice; ScriptChanged; end; end;
end;
