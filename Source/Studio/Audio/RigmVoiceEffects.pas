unit RigmVoiceEffects;
interface
uses System.JSON, RigmMovieModel;
function CueVoiceEffectsStamp(Cue: TRigmMovieCue): string;
function CueEffectSourceStamp(Project: TRigmMovieProject; Cue: TRigmMovieCue): string;
function CueEffectPreviewKey(Project: TRigmMovieProject; Cue: TRigmMovieCue): string;
procedure EditCueVoiceEffects(Project: TRigmMovieProject; const CueId: string; Settings: TJSONObject);
implementation
uses System.SysUtils, System.IOUtils, System.Hash, RigmVoiceEffectSettings, RigmModel;
function CueVoiceEffectsStamp(Cue: TRigmMovieCue): string;
begin Result := VoiceEffectSettingsStamp(Cue.AudioEffects); end;
function CueEffectSourceStamp(Project: TRigmMovieProject; Cue: TRigmMovieCue): string;
begin
  var FileName := ResolveMoviePath(Project.FileName,Cue.WaveFile);
  var Key := Project.Id+'|'+Cue.Id+'|'+Cue.AudioKey+'|'+Project.AudioFingerprint(Cue)+'|'+FileName;
  if FileExists(FileName) then Key := Key+'|'+TFile.GetSize(FileName).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(FileName),TFormatSettings.Invariant);
  Result := THashSHA2.GetHashString(Key);
end;
function CueEffectPreviewKey(Project: TRigmMovieProject; Cue: TRigmMovieCue): string;
begin Result := THashSHA2.GetHashString(CueEffectSourceStamp(Project,Cue)+'|'+CueVoiceEffectsStamp(Cue)); end;
procedure EditCueVoiceEffects(Project: TRigmMovieProject; const CueId: string; Settings: TJSONObject);
begin
  var C := Project.Cue(CueId); if C=nil then raise Exception.Create('Audio effects cue does not exist');
  ValidateVoiceEffectSettings(Settings);
  if VoiceEffectSettingsStamp(Settings)=CueVoiceEffectsStamp(C) then Exit;
  var Copy := Settings.Clone as TJSONObject; C.AudioEffects.Free; C.AudioEffects := Copy;
  C.AudioEffect := 'none'; if VoiceEffectsEnabled(C.AudioEffects) then C.AudioEffect := 'aul2-chain';
  // Previous derived files remain available. A stale key cannot authorize their reuse.
  C.EffectAudioKey := ''; Project.Changed;
end;
end.
