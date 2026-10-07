unit RigmScriptVoiceModel;
// 読みと個別queryを字幕・元原稿から分離する。ジョブ・再生・登録先書込はWorkspace所有。
interface
uses System.JSON, RigmMovieModel;
procedure RequireCurrentVoice(Project: TRigmMovieProject);
procedure PrepareScriptVoice(Project: TRigmMovieProject);
procedure ValidateScriptVoice(Project: TRigmMovieProject);
procedure EditScriptVoice(Project: TRigmMovieProject; const CueId,Reading: string; Settings: TJSONObject);
function ScriptVoiceSummary(Project: TRigmMovieProject): TJSONObject;
function RefreshScriptVoiceCompletion(Project: TRigmMovieProject): Boolean;
function MarkScriptVoiceHeard(Project: TRigmMovieProject; const CueId,AudioKey: string): Boolean;
procedure PrepareScriptVoiceEffects(Project: TRigmMovieProject);
procedure ValidateScriptVoiceEffects(Project: TRigmMovieProject);
implementation
uses System.SysUtils, RigmJson, PsdJson, RigmScriptTextModel, RigmScriptCastingModel, RigmScriptReviewModel;
procedure RequireCurrentVoice(Project: TRigmMovieProject);
begin
  if (Project=nil) or (Project.ScriptWizard=nil) or (Project.ScriptWizard.GetValue('casting')=nil) then raise Exception.Create('配役を準備してください。');
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'sourceFingerprint')<>ScriptFingerprint(Project)) or (JS(Cast,'fingerprint')<>CastingFingerprint(Project)) then
    raise Exception.Create('前工程が変わりました。校正と配役から確認してください。');
end;
procedure PrepareScriptVoice(Project: TRigmMovieProject);
begin
  RequireCurrentVoice(Project); var Cast := ScriptCastingSummary(Project);
  try if (JI(Cast,'pending')<>0) or (JI(Cast,'unassigned')<>0) or (JI(Cast,'missingVoices')<>0) or (JS(Project.ScriptWizard,'subtitlesStatus')<>'complete') then
    raise Exception.Create('配役を確定し、字幕入力を完了してから音声へ進んでください。'); finally Cast.Free; end;
  if Project.ScriptWizard.GetValue('voice')=nil then begin
    var O := TJSONObject.Create; O.AddPair('format','RIGMMaker.ScriptVoice'); AddN(O,'schemaVersion',1); O.AddPair('selectedCue',Project.Cues[0].Id); Project.ScriptWizard.AddPair('voice',O);
  end;
  var O := JO(Project.ScriptWizard,'voice'); if Project.Cue(JS(O,'selectedCue'))=nil then PsdJson.Put(O,'selectedCue',Project.Cues[0].Id);
  ApplyScriptVoiceDefaults(Project);
  if Project.ScriptWizard.GetValue('voiceStatus')=nil then PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
  ValidateScriptVoice(Project);
end;
procedure ValidateScriptVoice(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'voice');
  if (JS(O,'format')<>'RIGMMaker.ScriptVoice') or (JI(O,'schemaVersion')<>1) or (Project.Cue(JS(O,'selectedCue'))=nil) then raise Exception.Create('音声工程の保存状態が不正です。');
end;
procedure EditScriptVoice(Project: TRigmMovieProject; const CueId,Reading: string; Settings: TJSONObject);
begin
  RequireCurrentVoice(Project); var C := Project.Cue(CueId); if C=nil then raise Exception.Create('読みを編集するセリフがありません。');
  var Text := NormalizeScriptText(Reading); ValidateVoiceReading(Text); ValidateVoiceValues(Settings);
  // 検査完了後に両値を反映する。既存WAV/LAB/秒数は保持し、指紋が異なる場合だけ古い状態になる。
  var Values := Settings.Clone as TJSONObject; var OldReading := C.SpokenText; C.VoiceReading := Text;
  if C.SpokenText<>OldReading then begin C.VoiceQuery := ''; C.VoiceQueryKey := ''; end; C.VoiceSettings.Free; C.VoiceSettings := Values;
  PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
end;
function ScriptVoiceSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('engineUrl',Project.EngineUrl); Result.AddPair('selectedCue',JS(JO(Project.ScriptWizard,'voice'),'selectedCue'));
  var Ready := 0; var Heard := 0; var Stored := 0; var Unbound := 0;
  for var C in Project.Cues do begin if Project.AudioReady(C) then Inc(Ready); if Project.AudioHeard(C) then Inc(Heard); if Project.HasStoredAudio(C) then Inc(Stored); if Project.EffectiveStyle(C)<0 then Inc(Unbound); end;
  AddN(Result,'count',Project.Cues.Count); AddN(Result,'ready',Ready); AddN(Result,'stored',Stored); AddN(Result,'unbound',Unbound);
  AddN(Result,'heard',Heard);
  Result.AddPair('state',JS(Project.ScriptWizard,'voiceStatus','in-progress'));
end;
function RefreshScriptVoiceCompletion(Project: TRigmMovieProject): Boolean;
begin
  Result := False; if (Project=nil) or (Project.ScriptWizard=nil) or (Project.ScriptWizard.GetValue('voice')=nil) then Exit;
  var Complete := Project.Cues.Count>0;
  for var C in Project.Cues do Complete := Complete and Project.AudioHeard(C);
  var State := 'in-progress'; if Complete then State := 'complete';
  Result := JS(Project.ScriptWizard,'voiceStatus')<>State;
  if Result then PsdJson.Put(Project.ScriptWizard,'voiceStatus',State);
end;
function MarkScriptVoiceHeard(Project: TRigmMovieProject; const CueId,AudioKey: string): Boolean;
begin
  Result := False; var C := Project.Cue(CueId);
  if (C=nil) or not Project.AudioReady(C) or (AudioKey<>Project.AudioFingerprint(C)) or (C.VoiceHeardKey=AudioKey) then Exit;
  C.VoiceHeardKey := AudioKey; RefreshScriptVoiceCompletion(Project); Result := True;
end;
procedure PrepareScriptVoiceEffects(Project: TRigmMovieProject);
begin
  if Project.ScriptWizard.GetValue('voiceEffects')=nil then begin
    var O := TJSONObject.Create; O.AddPair('format','RIGMMaker.ScriptVoiceEffects'); AddN(O,'schemaVersion',1);
    Project.ScriptWizard.AddPair('voiceEffects',O);
  end;
  var O := JO(Project.ScriptWizard,'voiceEffects');
  if Project.Cue(JS(O,'selectedCue'))=nil then PsdJson.Put(O,'selectedCue',Project.Cues[0].Id);
  for var C in Project.Cues do if C.AudioEffect='' then C.AudioEffect := 'none';
  ValidateScriptVoiceEffects(Project);
end;
procedure ValidateScriptVoiceEffects(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'voiceEffects');
  if (JS(O,'format')<>'RIGMMaker.ScriptVoiceEffects') or (JI(O,'schemaVersion')<>1) or (Project.Cue(JS(O,'selectedCue'))=nil) then raise Exception.Create('音声エフェクト工程の保存状態が不正です。');
end;
end.
