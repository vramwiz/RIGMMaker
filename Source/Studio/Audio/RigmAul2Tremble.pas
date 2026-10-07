unit RigmAul2Tremble;

// Tremble 系の GUI 項目と、細かい音量揺れの音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddTrembleItems;
function ProcessTremble(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetTrembleGuiParams(UseTremble: Boolean; RateHz, Depth, Mix: Double);

procedure ResetCopiedTremble;

implementation

uses Winapi.Windows, System.SysUtils;

var
  GTrembleGroup     : TFILTER_ITEM_GROUP;
  GTrembleUseCheck  : TFILTER_ITEM_CHECK;
  GTrembleRateTrack : TFILTER_ITEM_TRACK;
  GTrembleDepthTrack: TFILTER_ITEM_TRACK;
  GTrembleMixTrack  : TFILTER_ITEM_TRACK;

function ClampSingle(Value, MinValue, MaxValue: Single): Single;
begin
  Result := Value;
  if Result < MinValue then
    Result := MinValue
  else if Result > MaxValue then
    Result := MaxValue;
end;

procedure ApplyTremble(var Buffer: TArray<Single>; SampleNum, SampleRate: Integer; BaseIndex: Int64;
  RateHz, Depth, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  Lfo: Single;
  Gain: Single;
  Phase: Double;
begin
  RateHz := ClampSingle(RateHz, 0.1, 30.0);
  Depth := ClampSingle(Depth, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    Phase := 2.0 * Pi * RateHz * ((BaseIndex + I) / SampleRate);
    Lfo := 0.5 + (0.5 * Sin(Phase));
    Gain := 1.0 - (Depth * Lfo);
    WetSample := DrySample * Gain;
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddTrembleItems;
begin
  AddGroup(GTrembleGroup, 'Tremble', 1);
  AddCheck(GTrembleUseCheck, 'Trem: Use', 0);
  AddTrack(GTrembleRateTrack, 'Trem: Rate(Hz)', 8.0, 0.1, 30.0, 0.1);
  AddTrack(GTrembleDepthTrack, 'Trem: Depth', 0.35, 0.0, 1.0, 0.01);
  AddTrack(GTrembleMixTrack, 'Trem: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetTrembleGuiParams(UseTremble: Boolean; RateHz, Depth, Mix: Double);
begin
  GTrembleUseCheck.Value := Byte(UseTremble);
  GTrembleRateTrack.Value := RateHz;
  GTrembleDepthTrack.Value := Depth;
  GTrembleMixTrack.Value := Mix;
end;

function ProcessTremble(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  RateHz: Single;
  Depth: Single;
  Mix: Single;
  BaseIndex: Int64;
  CaptureRequested: Boolean;
  InputSum: Double;
  OutputSum: Double;
  Sample: Integer;
  Denominator: Double;
  PhaseCycles: Double;
begin
  Result := GTrembleUseCheck.Value <> 0;
  if not Result then
    Exit;

  RateHz := GTrembleRateTrack.Value;
  Depth := GTrembleDepthTrack.Value;
  Mix := GTrembleMixTrack.Value;
  BaseIndex := Audio^.Object_^.SampleIndex;

  CaptureRequested := False;
InputSum := 0;
  OutputSum := 0;
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);

    ApplyTremble(Buffer, SampleNum, Audio^.Scene^.SampleRate, BaseIndex, RateHz, Depth, Mix);

    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

end;

procedure ResetCopiedTremble;
begin end;

end.
