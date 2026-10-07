unit RigmAul2NoiseGate;

// NoiseGate 系の GUI 項目、状態管理、小さい音を抑える処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddNoiseGateItems;
function ProcessNoiseGate(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetNoiseGateGuiParams(UseNoiseGate: Boolean; ThresholdDb, AttackMs, ReleaseMs, FloorDb: Double);

procedure ResetCopiedNoiseGate;

implementation

type
  TNoiseGateChannelState = record
    Envelope: Single; // 入力レベルの平滑値
    Gain    : Single; // 現在のゲートゲイン
  end;

var
  GNoiseGateGroup      : TFILTER_ITEM_GROUP;
  GNoiseGateUseCheck   : TFILTER_ITEM_CHECK;
  GGateThresholdTrack  : TFILTER_ITEM_TRACK;
  GGateAttackTrack     : TFILTER_ITEM_TRACK;
  GGateReleaseTrack    : TFILTER_ITEM_TRACK;
  GGateFloorTrack      : TFILTER_ITEM_TRACK;
  GNoiseGateChannels   : array of TNoiseGateChannelState; // チャンネル別のゲート状態
  GNoiseGateSampleRate : Integer;                         // 状態を構築したサンプルレート
  GNoiseGateObjectID   : Int64;                           // 状態を構築した対象オブジェクト
  GNoiseGateEffectID   : Int64;                           // 状態を構築した対象エフェクト
  GNoiseGateNextIndex  : Int64;                           // 連続処理を判定する次のサンプル位置

procedure ClearNoiseGateState;
begin
  SetLength(GNoiseGateChannels, 0);
  GNoiseGateSampleRate := 0;
  GNoiseGateObjectID := 0;
  GNoiseGateEffectID := 0;
  GNoiseGateNextIndex := 0;
end;

procedure ResetNoiseGateState(ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  SetLength(GNoiseGateChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    GNoiseGateChannels[Channel].Envelope := 0.0;
    GNoiseGateChannels[Channel].Gain := 1.0;
  end;

  GNoiseGateSampleRate := SampleRate;
end;

procedure EnsureNoiseGateState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  if (Length(GNoiseGateChannels) <> ChannelNum) or
     (GNoiseGateSampleRate <> Audio^.Scene^.SampleRate) or
     (GNoiseGateObjectID <> ObjectInfo^.ID) or
     (GNoiseGateEffectID <> ObjectInfo^.EffectID) or
     (GNoiseGateNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetNoiseGateState(ChannelNum, Audio^.Scene^.SampleRate);
    GNoiseGateObjectID := ObjectInfo^.ID;
    GNoiseGateEffectID := ObjectInfo^.EffectID;
  end;
end;

function ClampSingle(Value, MinValue, MaxValue: Single): Single;
begin
  Result := Value;
  if Result < MinValue then
    Result := MinValue
  else if Result > MaxValue then
    Result := MaxValue;
end;

function DbToLinear(ValueDb: Single): Single;
begin
  Result := Power(10.0, ValueDb / 20.0);
end;

function TimeCoeff(TimeMs: Single; SampleRate: Integer): Single;
begin
  TimeMs := ClampSingle(TimeMs, 1.0, 1000.0);
  Result := 1.0 - Exp(-1.0 / (SampleRate * TimeMs / 1000.0));
end;

procedure ApplyNoiseGate(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  ThresholdDb, AttackMs, ReleaseMs, FloorDb: Single);
var
  I: Integer;
  TargetGain: Single;
  Threshold: Single;
  FloorGain: Single;
  EnvCoeff: Single;
  AttackCoeff: Single;
  ReleaseCoeff: Single;
  State: ^TNoiseGateChannelState;
begin
  Threshold := DbToLinear(ThresholdDb);
  FloorGain := DbToLinear(FloorDb);
  EnvCoeff := TimeCoeff(5.0, SampleRate);
  AttackCoeff := TimeCoeff(AttackMs, SampleRate);
  ReleaseCoeff := TimeCoeff(ReleaseMs, SampleRate);
  State := @GNoiseGateChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    State^.Envelope := State^.Envelope + ((Abs(Buffer[I]) - State^.Envelope) * EnvCoeff);
    if State^.Envelope >= Threshold then
      TargetGain := 1.0
    else
      TargetGain := FloorGain;

    if TargetGain > State^.Gain then
      State^.Gain := State^.Gain + ((TargetGain - State^.Gain) * AttackCoeff)
    else
      State^.Gain := State^.Gain + ((TargetGain - State^.Gain) * ReleaseCoeff);

    Buffer[I] := Buffer[I] * State^.Gain;
  end;
end;

procedure AddNoiseGateItems;
begin
  AddGroup(GNoiseGateGroup, 'NoiseGate', 1);
  AddCheck(GNoiseGateUseCheck, 'Gate: Use', 0);
  AddTrack(GGateThresholdTrack, 'Gate: Threshold(dB)', -45.0, -80.0, 0.0, 0.1);
  AddTrack(GGateAttackTrack, 'Gate: Attack(ms)', 5.0, 1.0, 200.0, 1.0);
  AddTrack(GGateReleaseTrack, 'Gate: Release(ms)', 120.0, 10.0, 1000.0, 10.0);
  AddTrack(GGateFloorTrack, 'Gate: Floor(dB)', -60.0, -80.0, -6.0, 1.0);
end;

procedure SetNoiseGateGuiParams(UseNoiseGate: Boolean; ThresholdDb, AttackMs, ReleaseMs, FloorDb: Double);
begin
  GNoiseGateUseCheck.Value := Byte(UseNoiseGate);
  GGateThresholdTrack.Value := ThresholdDb;
  GGateAttackTrack.Value := AttackMs;
  GGateReleaseTrack.Value := ReleaseMs;
  GGateFloorTrack.Value := FloorDb;
  ClearNoiseGateState;
end;

function ProcessNoiseGate(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
begin
  Result := GNoiseGateUseCheck.Value <> 0;
  if not Result then
  begin
    ClearNoiseGateState;
    Exit;
  end;

  EnsureNoiseGateState(Audio, ChannelNum);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyNoiseGate(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate,
      GGateThresholdTrack.Value, GGateAttackTrack.Value, GGateReleaseTrack.Value, GGateFloorTrack.Value);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

  GNoiseGateNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedNoiseGate;
begin ClearNoiseGateState; end;

end.
