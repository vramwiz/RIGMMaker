unit RigmAul2AutoGain;

// AutoGain 系の GUI 項目、状態管理、目標音量へ緩やかに寄せる処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddAutoGainItems;
function ProcessAutoGain(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetAutoGainGuiParams(UseAutoGain: Boolean; TargetDb, SpeedMs, MaxGainDb, Mix: Double);

procedure ResetCopiedAutoGain;

implementation

uses Winapi.Windows, System.SysUtils;

type
  TAutoGainChannelState = record
    Envelope: Single; // 入力レベルの平滑値
    Gain    : Single; // 現在の補正ゲイン
  end;

var
  GAutoGainGroup       : TFILTER_ITEM_GROUP;
  GAutoGainUseCheck    : TFILTER_ITEM_CHECK;
  GAutoGainTargetTrack : TFILTER_ITEM_TRACK;
  GAutoGainSpeedTrack  : TFILTER_ITEM_TRACK;
  GAutoGainMaxGainTrack: TFILTER_ITEM_TRACK;
  GAutoGainMixTrack    : TFILTER_ITEM_TRACK;
  GAutoGainChannels    : array of TAutoGainChannelState; // チャンネル別のレベル追従状態
  GAutoGainSampleRate  : Integer;                        // 状態を構築したサンプルレート
  GAutoGainObjectID    : Int64;                          // 状態を構築した対象オブジェクト
  GAutoGainEffectID    : Int64;                          // 状態を構築した対象エフェクト
  GAutoGainNextIndex   : Int64;                          // 連続処理を判定する次のサンプル位置

procedure ClearAutoGainState;
begin
  SetLength(GAutoGainChannels, 0);
  GAutoGainSampleRate := 0;
  GAutoGainObjectID := 0;
  GAutoGainEffectID := 0;
  GAutoGainNextIndex := 0;
end;

procedure ResetAutoGainState(ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  SetLength(GAutoGainChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    GAutoGainChannels[Channel].Envelope := 0.0;
    GAutoGainChannels[Channel].Gain := 1.0;
  end;

  GAutoGainSampleRate := SampleRate;
end;

procedure EnsureAutoGainState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  if (Length(GAutoGainChannels) <> ChannelNum) or
     (GAutoGainSampleRate <> Audio^.Scene^.SampleRate) or
     (GAutoGainObjectID <> ObjectInfo^.ID) or
     (GAutoGainEffectID <> ObjectInfo^.EffectID) or
     (GAutoGainNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetAutoGainState(ChannelNum, Audio^.Scene^.SampleRate);
    GAutoGainObjectID := ObjectInfo^.ID;
    GAutoGainEffectID := ObjectInfo^.EffectID;
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

procedure ApplyAutoGain(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  TargetDb, SpeedMs, MaxGainDb, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  TargetLevel: Single;
  TargetGain: Single;
  MaxGain: Single;
  EnvCoeff: Single;
  GainCoeff: Single;
  State: ^TAutoGainChannelState;
begin
  SpeedMs := ClampSingle(SpeedMs, 20.0, 2000.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  TargetLevel := DbToLinear(TargetDb);
  MaxGain := DbToLinear(MaxGainDb);
  EnvCoeff := 1.0 - Exp(-1.0 / (SampleRate * 0.020));
  GainCoeff := 1.0 - Exp(-1.0 / (SampleRate * SpeedMs / 1000.0));
  State := @GAutoGainChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    State^.Envelope := State^.Envelope + ((Abs(DrySample) - State^.Envelope) * EnvCoeff);

    if State^.Envelope > 0.00001 then
      TargetGain := TargetLevel / State^.Envelope
    else
      TargetGain := 1.0;
    TargetGain := ClampSingle(TargetGain, 0.0, MaxGain);

    State^.Gain := State^.Gain + ((TargetGain - State^.Gain) * GainCoeff);
    WetSample := DrySample * State^.Gain;
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddAutoGainItems;
begin
  AddGroup(GAutoGainGroup, 'AutoGain', 1);
  AddCheck(GAutoGainUseCheck, 'AGain: Use', 0);
  AddTrack(GAutoGainTargetTrack, 'AGain: Target(dB)', -12.0, -36.0, -3.0, 0.1);
  AddTrack(GAutoGainSpeedTrack, 'AGain: Speed(ms)', 400.0, 20.0, 2000.0, 10.0);
  AddTrack(GAutoGainMaxGainTrack, 'AGain: MaxGain(dB)', 12.0, 0.0, 24.0, 0.1);
  AddTrack(GAutoGainMixTrack, 'AGain: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetAutoGainGuiParams(UseAutoGain: Boolean; TargetDb, SpeedMs, MaxGainDb, Mix: Double);
begin
  GAutoGainUseCheck.Value := Byte(UseAutoGain);
  GAutoGainTargetTrack.Value := TargetDb;
  GAutoGainSpeedTrack.Value := SpeedMs;
  GAutoGainMaxGainTrack.Value := MaxGainDb;
  GAutoGainMixTrack.Value := Mix;
  ClearAutoGainState;
end;

function ProcessAutoGain(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  CaptureRequested: Boolean;
  Channel: Integer;
  Buffer: TArray<Single>;
  CorrectionGainSum: Double;
  Denominator: Double;
  InputSum: Double;
  OutputSum: Double;
  Sample: Integer;
begin
  Result := GAutoGainUseCheck.Value <> 0;
  if not Result then
  begin
    ClearAutoGainState;
    Exit;
  end;

  EnsureAutoGainState(Audio, ChannelNum);

  CaptureRequested := False;
InputSum := 0;
  OutputSum := 0;
  CorrectionGainSum := 0;
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);

    ApplyAutoGain(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate,
      GAutoGainTargetTrack.Value, GAutoGainSpeedTrack.Value, GAutoGainMaxGainTrack.Value, GAutoGainMixTrack.Value);

    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  GAutoGainNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedAutoGain;
begin ClearAutoGainState; end;

end.
