unit RigmVoiceEffectSettings;
// Sparse numeric settings use the same item names and ranges as Aul2AudioFilter.
interface
uses System.JSON;
procedure ValidateVoiceEffectSettings(Settings: TJSONObject);
function VoiceEffectValue(Settings: TJSONObject; const Name: string): Double;
function VoiceEffectSettingsStamp(Settings: TJSONObject): string;
function VoiceEffectsEnabled(Settings: TJSONObject): Boolean;
implementation
uses System.SysUtils, System.Math, System.Hash, System.Generics.Collections, RigmJson, RigmAul2EffectDefinition;
{$I RigmVoiceEffectDefaults.inc}
function VoiceEffectValue(Settings: TJSONObject; const Name: string): Double;
begin
  if (Settings<>nil) and (Settings.GetValue(Name) is TJSONNumber) then Exit(TJSONNumber(Settings.GetValue(Name)).AsDouble);
  Result := EffectDefault(Name);
end;
procedure ValidateVoiceEffectSettings(Settings: TJSONObject);
begin
  if Settings=nil then raise Exception.Create('Audio effect settings are missing');
  if Settings.Count>100 then raise Exception.Create('Too many audio effect settings');
  var Seen := TDictionary<string,Boolean>.Create;
  try
  for var Pair in Settings do begin
    var K := Pair.JsonString.Value; var Found := False;
    if Seen.ContainsKey(K) then raise Exception.Create('Duplicate audio effect parameter: '+K);
    Seen.Add(K,True);
    if not (Pair.JsonValue is TJSONNumber) then raise Exception.Create('Effect values must be numeric: '+K);
    var V := TJSONNumber(Pair.JsonValue).AsDouble;
    if IsNan(V) or IsInfinite(V) then raise Exception.Create('Effect values must be finite: '+K);
    for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
      var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D);
      if K=D.UseItemName then begin Found := True; if not ((V=0) or (V=1)) then raise Exception.Create('Effect switch must be 0 or 1'); end;
      if D.SelectControl.Visible and (K=D.SelectControl.ItemName) then begin
        Found := True; if (V<>Trunc(V)) or (V<0) or (V>=Length(D.SelectControl.Items)) then raise Exception.Create('Invalid effect mode');
      end;
      for var Range in D.Volumes do if K=Range.ItemName then begin
        Found := True; if (V<Range.Minimum) or (V>Range.Maximum) then raise Exception.Create('Effect value outside allowed range: '+K);
      end;
    end;
    if not Found then raise Exception.Create('Unsupported audio effect setting: '+K);
  end;
  finally Seen.Free; end;
end;
function VoiceEffectSettingsStamp(Settings: TJSONObject): string;
begin
  ValidateVoiceEffectSettings(Settings); var Key := 'RIGMMaker.Aul2CueEffects.v1';
  for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
    var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D);
    Key := Key+'|'+D.UseItemName+'='+FloatToStr(VoiceEffectValue(Settings,D.UseItemName),TFormatSettings.Invariant);
    if D.SelectControl.Visible then Key := Key+'|'+D.SelectControl.ItemName+'='+FloatToStr(VoiceEffectValue(Settings,D.SelectControl.ItemName),TFormatSettings.Invariant);
    for var V in D.Volumes do Key := Key+'|'+V.ItemName+'='+FloatToStr(VoiceEffectValue(Settings,V.ItemName),TFormatSettings.Invariant);
  end;
  Result := THashSHA2.GetHashString(Key);
end;
function VoiceEffectsEnabled(Settings: TJSONObject): Boolean;
begin
  Result := False;
  for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
    var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D);
    if VoiceEffectValue(Settings,D.UseItemName)<>0 then Exit(True);
  end;
end;
end.
