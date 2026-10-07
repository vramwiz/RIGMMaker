procedure TRigmWizardWorkspace.SelectVoiceEffects(const CueId: string);
begin
  if CurrentScriptStage<>'voice-effects' then raise Exception.Create('音声エフェクト工程で操作してください。');
  if FScriptDraft.Cue(CueId)=nil then raise Exception.Create('音声エフェクトのセリフIDがありません。');
  if JS(JO(FScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue')=CueId then Exit;
  StopVoice; PsdJson.Put(JO(FScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue',CueId);
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.EditVoiceEffects(const CueId: string; Settings: TJSONObject);
begin
  if CurrentScriptStage<>'voice-effects' then raise Exception.Create('音声エフェクト工程で調整してください。');
  EditCueVoiceEffects(FScriptDraft,CueId,Settings); ScriptChanged;
end;
function TRigmWizardWorkspace.ReadVoiceEffects(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで取得してください。');
  var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Cues.Count); var Selected := '';
  var Effects := FScriptDraft.ScriptWizard.GetValue('voiceEffects');
  if Effects is TJSONObject then Selected := JS(TJSONObject(Effects),'selectedCue');
  Result := TJSONObject.Create;
  try
  Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision); Result.AddPair('selectedCue',Selected);
  var A := TJSONArray.Create; Result.AddPair('rows',A);
  for var I := Offset to Min(Offset+10,FScriptDraft.Cues.Count)-1 do begin
    var C := FScriptDraft.Cues[I]; var O := TJSONObject.Create; A.AddElement(O);
    O.AddPair('cueId',C.Id); O.AddPair('settings',C.AudioEffects.Clone as TJSONObject);
    O.AddPair('effectStamp',CueVoiceEffectsStamp(C)); O.AddPair('sourceWaveFile',C.WaveFile);
    O.AddPair('derivedWaveFile',C.EffectWaveFile); AddB(O,'audioReady',FScriptDraft.AudioReady(C));
  end;
  AddN(Result,'nextOffset',Offset+A.Count); AddB(Result,'hasMore',Offset+A.Count<FScriptDraft.Cues.Count);
  except Result.Free; raise; end;
end;

procedure TRigmWizardWorkspace.NotifyVoiceEffectsPreview;
begin ScriptChanged; end;
