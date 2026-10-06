// 音声ジョブをページより長く所有する。音声が一致する1cueの結果だけを回収する。
function TRigmWizardWorkspace.VoiceBusy: Boolean;
begin Result := (FVoiceJob<>nil) and not FVoiceJob.Done; end;
function TRigmWizardWorkspace.VoiceCatalog: TJSONArray;
begin Result := FVoiceCatalog; end;
procedure TRigmWizardWorkspace.StopVoice;
begin PlaySound(nil,0,0); FPlayVoice := ''; end;
procedure TRigmWizardWorkspace.CancelVoice;
begin StopVoice; if FVoiceJob<>nil then FVoiceJob.Cancel; end;
procedure TRigmWizardWorkspace.PollScriptVoice;
begin
  if (FVoiceJob=nil) or not FVoiceJob.Done or FVoiceCollected then Exit; FVoiceCollected := True;
  var State := FVoiceJob.Status;
  try
    FVoiceError := JS(State,'error');
    if (FScriptDraft<>nil) and (FScriptDraft.Id=FVoiceJob.Project.Id) and (JS(State,'state')='succeeded') then begin
      if (FVoiceJob.Kind='speakers') and (FScriptDraft.EngineUrl=FVoiceJob.Project.EngineUrl) then begin
        FVoiceCatalog.Free; FVoiceCatalog := TJSONObject.ParseJSONValue(FVoiceJob.Catalog) as TJSONArray; FVoiceCatalogUrl := FScriptDraft.EngineUrl;
      end;
      if (FVoiceJob.Kind='audio') then begin
        var Valid := True; try RequireCurrentVoice(FScriptDraft); except on E: Exception do Valid := False; end;
        if Valid then for var C in FVoiceJob.Project.Cues do begin
          if C.Id<>FVoiceTarget then Continue;
          var Target := FScriptDraft.Cue(C.Id);
          if (Target<>nil) and (C.AudioKey<>FScriptDraft.AudioFingerprint(Target)) then FVoiceError := '入力が変わったため古い音声結果は採用しません。旧音声は保持しています。';
          if (Target<>nil) and FVoiceJob.Project.AudioReady(C) and (C.AudioKey=FScriptDraft.AudioFingerprint(Target)) and (Target.WaveFile<>C.WaveFile) then begin
            Target.WaveFile := C.WaveFile; Target.LabFile := C.LabFile; Target.AudioSeconds := C.AudioSeconds; Target.AudioKey := C.AudioKey; FScriptDraft.Changed;
          end;
        end;
        if FPlayVoice<>'' then begin
          var C := FScriptDraft.Cue(FPlayVoice);
          if Valid and (C<>nil) and FScriptDraft.AudioReady(C) then PlaySound(PChar(ResolveMoviePath(FScriptDraft.FileName,C.WaveFile)),0,SND_FILENAME or SND_ASYNC or SND_NODEFAULT);
        end;
      end;
    end;
    FPlayVoice := ''; ScriptChanged;
  finally State.Free; end;
end;
procedure TRigmWizardWorkspace.SelectVoice(const CueId: string);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。');
  if FScriptDraft.Cue(CueId)=nil then raise Exception.Create('音声セリフがありません。');
  if JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue')=CueId then Exit;
  StopVoice; PsdJson.Put(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue',CueId); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveVoice(Delta: Integer);
begin var C := FScriptDraft.Cue(JS(JO(FScriptDraft.ScriptWizard,'voice'),'selectedCue')); SelectVoice(FScriptDraft.Cues[EnsureRange(FScriptDraft.Cues.IndexOf(C)+Delta,0,FScriptDraft.Cues.Count-1)].Id); end;
procedure TRigmWizardWorkspace.EditVoice(const CueId,Reading: string; Settings: TJSONObject);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。');
  EditScriptVoice(FScriptDraft,CueId,Reading,Settings); StopVoice; FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetVoiceEngine(const Url: string);
begin
  if (CurrentScriptStage<>'voice') or VoiceBusy then raise Exception.Create('音声工程のジョブ終了後に接続先を変更してください。');
  var Copy := FScriptDraft.Clone;
  try Copy.EngineUrl := Url.Trim; Copy.Validate; FScriptDraft.EngineUrl := Copy.EngineUrl; finally Copy.Free; end;
  StopVoice; FVoiceCatalog.Free; FVoiceCatalog := TJSONArray.Create; FVoiceCatalogUrl := ''; FVoiceError := '';
  PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.RefreshVoiceCatalog;
begin
  if (CurrentScriptStage<>'voice') or VoiceBusy then raise Exception.Create('音声工程のジョブ終了後に一覧を取得してください。');
  FreeAndNil(FVoiceJob); FVoiceCollected := False; FVoiceError := ''; FVoiceCatalog.Free; FVoiceCatalog := TJSONArray.Create; FVoiceCatalogUrl := '';
  FVoiceJob := TRigmMovieJob.Create(FScriptDraft,'speakers','',0); FVoiceJob.Start; ScriptChanged;
end;
procedure TRigmWizardWorkspace.BindVoice(Number,StyleId: Integer; const Uuid: string);
begin
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。'); RequireCurrentVoice(FScriptDraft);
  if FVoiceCatalogUrl<>FScriptDraft.EngineUrl then raise Exception.Create('現在の接続先から実話者一覧を取得してください。');
  var Role := CastingRole(FScriptDraft,Number); if (Role=nil) or not JB(Role,'active') then raise Exception.Create('登録キャラを選んでください。');
  var Found: TJSONObject := nil; for var V in FVoiceCatalog do if (JI(TJSONObject(V),'styleId',-1)=StyleId) and (JS(TJSONObject(V),'uuid')=Uuid) then Found := TJSONObject(V);
  if (Found=nil) or (Uuid='') then raise Exception.Create('実話者一覧のUUIDとstyleIdを選んでください。');
  var S := FScriptDraft.Speaker(JS(Role,'speakerId')); S.StyleId := StyleId; S.VoiceUuid := Uuid; S.VoiceName := JS(Found,'name'); S.StyleName := JS(Found,'style');
  StopVoice; PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.GenerateVoice(const CueId: string; Play: Boolean);
begin
  if (CurrentScriptStage<>'voice') or VoiceBusy then raise Exception.Create('音声ジョブの終了後に試聴してください。'); RequireCurrentVoice(FScriptDraft);
  var C := FScriptDraft.Cue(CueId); if C=nil then raise Exception.Create('選択セリフがありません。');
  if FScriptDraft.AudioReady(C) and Play then begin StopVoice; if C.WaveFile<>'' then PlaySound(PChar(ResolveMoviePath(FScriptDraft.FileName,C.WaveFile)),0,SND_FILENAME or SND_ASYNC or SND_NODEFAULT); Exit; end;
  var S := FScriptDraft.Speaker(C.SpeakerId); var Found := False;
  if FVoiceCatalogUrl=FScriptDraft.EngineUrl then for var V in FVoiceCatalog do
    if (JI(TJSONObject(V),'styleId',-1)=FScriptDraft.EffectiveStyle(C)) and (JS(TJSONObject(V),'uuid')=S.VoiceUuid) and (S.VoiceUuid<>'') then Found := True;
  if not Found then raise Exception.Create('実一覧から選択セリフのキャラへ声を紐付けてください。');
  StopVoice; FreeAndNil(FVoiceJob); FVoiceCollected := False; FVoiceError := ''; if Play then FPlayVoice := CueId;
  var O := TJSONObject.Create;
  try O.AddPair('cueId',CueId); FVoiceJob := TRigmMovieJob.Create(FScriptDraft,'audio',TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Audio'),0,O); finally O.Free; end;
  FVoiceTarget := CueId; FVoiceJob.Start; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteVoice;
begin
  EndScriptTextEdit; RequireCurrentVoice(FScriptDraft);
  if VoiceBusy then raise Exception.Create('音声生成の終了後に確認してください。');
  for var C in FScriptDraft.Cues do if not FScriptDraft.AudioReady(C) then raise Exception.Create('未生成または変更後のセリフをF5で確認してください。');
  PsdJson.Put(FScriptDraft.ScriptWizard,'voiceStatus','complete'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.VoiceStatus: TJSONObject;
begin
  PollScriptVoice; Result := ScriptVoiceSummary(FScriptDraft); AddB(Result,'busy',VoiceBusy); Result.AddPair('error',FVoiceError); AddN(Result,'catalogCount',FVoiceCatalog.Count); Result.AddPair('catalogUrl',FVoiceCatalogUrl);
  if FVoiceJob<>nil then Result.AddPair('job',FVoiceJob.Status);
end;
function TRigmWizardWorkspace.ReadVoice(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで音声を取得してください。');
  Result := VoiceStatus; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  var A := TJSONArray.Create; Result.AddPair('rows',A); var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Cues.Count);
  if Offset<FScriptDraft.Cues.Count then begin
    var C := FScriptDraft.Cues[Offset]; var O := TJSONObject.Create; A.AddElement(O); O.AddPair('cueId',C.Id); O.AddPair('sourceText',C.Text); O.AddPair('reading',C.SpokenText); O.AddPair('subtitle',C.Subtitle);
    O.AddPair('settings',C.VoiceSettings.Clone as TJSONObject); O.AddPair('sceneId',C.Scene); var Row := CastingRow(FScriptDraft,C.Id); AddN(O,'role',JI(Row,'role'));
    var S := FScriptDraft.Speaker(C.SpeakerId); O.AddPair('speaker',S.Json); AddB(O,'ready',FScriptDraft.AudioReady(C)); AddB(O,'stored',FScriptDraft.HasStoredAudio(C));
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
  if CurrentScriptStage<>'voice' then raise Exception.Create('音声工程で操作してください。'); RequireCurrentVoice(FScriptDraft); EnsureVoiceBindings;
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
