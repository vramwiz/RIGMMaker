unit RigmAul2Output;

// Output 系の GUI 項目と、最終段付近の手動音量調整を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddOutputItems;
function ProcessOutput(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetOutputGuiParams(UseOutput: Boolean; GainDb: Double);

procedure ResetCopiedOutput;

implementation

var
  GOutputGroup    : TFILTER_ITEM_GROUP;
  GOutputUseCheck : TFILTER_ITEM_CHECK;
  GOutputGainTrack: TFILTER_ITEM_TRACK;

function DbToLinear(ValueDb: Single): Single;
begin
  Result := Power(10.0, ValueDb / 20.0);
end;

procedure ApplyOutputGain(var Buffer: TArray<Single>; SampleNum: Integer; Gain: Single);
var
  I: Integer;
begin
  for I := 0 to SampleNum - 1 do
    Buffer[I] := Buffer[I] * Gain;
end;

procedure AddOutputItems;
begin
  AddGroup(GOutputGroup, 'Output', 1);
  AddCheck(GOutputUseCheck, 'Out: Use', 0);
  AddTrack(GOutputGainTrack, 'Out: Gain(dB)', 0.0, -24.0, 24.0, 0.1);
end;

procedure SetOutputGuiParams(UseOutput: Boolean; GainDb: Double);
begin
  GOutputUseCheck.Value := Byte(UseOutput);
  GOutputGainTrack.Value := GainDb;
end;

function ProcessOutput(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  Gain: Single;
begin
  Result := GOutputUseCheck.Value <> 0;
  if not Result then
    Exit;

  Gain := DbToLinear(GOutputGainTrack.Value);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyOutputGain(Buffer, SampleNum, Gain);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;
end;

procedure ResetCopiedOutput;
begin end;

end.
