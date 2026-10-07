unit RigmAul2Whisper;

// Whisper/Breath 系の GUI 項目、状態管理、息成分の音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddWhisperItems;
function ProcessWhisper(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetWhisperGuiParams(UseWhisper: Boolean; LevelDb, Tone, Mix: Double);

procedure ResetCopiedWhisper;

implementation

type
  TWhisperChannelState = record
    Seed    : UInt32; // 疑似乱数の現在値
    Envelope: Single; // 入力音量に追従する息成分の量
    LowNoise: Single; // ノイズの低域成分
  end;

var
  GWhisperGroup      : TFILTER_ITEM_GROUP;
  GWhisperUseCheck   : TFILTER_ITEM_CHECK;
  GWhisperLevelTrack : TFILTER_ITEM_TRACK;
  GWhisperToneTrack  : TFILTER_ITEM_TRACK;
  GWhisperMixTrack   : TFILTER_ITEM_TRACK;
  GWhisperChannels   : array of TWhisperChannelState; // チャンネル別のノイズ生成状態
  GWhisperSampleRate : Integer;                        // 状態を構築したサンプルレート
  GWhisperObjectID   : Int64;                          // 状態を構築した対象オブジェクト
  GWhisperEffectID   : Int64;                          // 状態を構築した対象エフェクト
  GWhisperNextIndex  : Int64;                          // 連続処理を判定する次のサンプル位置

procedure ClearWhisperState;
begin
  SetLength(GWhisperChannels, 0);
  GWhisperSampleRate := 0;
  GWhisperObjectID := 0;
  GWhisperEffectID := 0;
  GWhisperNextIndex := 0;
end;

procedure ResetWhisperState(ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  SetLength(GWhisperChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    GWhisperChannels[Channel].Seed := UInt32($6D2B79F5 + Cardinal(Channel * 977));
    GWhisperChannels[Channel].Envelope := 0.0;
    GWhisperChannels[Channel].LowNoise := 0.0;
  end;

  GWhisperSampleRate := SampleRate;
end;

procedure EnsureWhisperState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  // 息成分の状態が別素材へ混ざらないよう、処理対象や連続位置が変わったら作り直す。
  if (Length(GWhisperChannels) <> ChannelNum) or
     (GWhisperSampleRate <> Audio^.Scene^.SampleRate) or
     (GWhisperObjectID <> ObjectInfo^.ID) or
     (GWhisperEffectID <> ObjectInfo^.EffectID) or
     (GWhisperNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetWhisperState(ChannelNum, Audio^.Scene^.SampleRate);
    GWhisperObjectID := ObjectInfo^.ID;
    GWhisperEffectID := ObjectInfo^.EffectID;
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

function NextNoise(var Seed: UInt32): Single;
begin
  Seed := Seed xor (Seed shl 13);
  Seed := Seed xor (Seed shr 17);
  Seed := Seed xor (Seed shl 5);
  Result := (Integer(Seed and $00FFFFFF) / $7FFFFF) - 1.0;
end;

procedure ApplyWhisper(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  LevelDb, Tone, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  Level: Single;
  Noise: Single;
  Breath: Single;
  LowCoeff: Single;
  EnvAttack: Single;
  EnvRelease: Single;
  State: ^TWhisperChannelState;
begin
  Tone := ClampSingle(Tone, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  Level := DbToLinear(LevelDb);
  LowCoeff := 1.0 - Exp(-2.0 * Pi * (900.0 + (Tone * 4200.0)) / SampleRate);
  EnvAttack := 1.0 - Exp(-1.0 / (SampleRate * 0.005));
  EnvRelease := Exp(-1.0 / (SampleRate * 0.080));
  State := @GWhisperChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];

    if Abs(DrySample) > State^.Envelope then
      State^.Envelope := State^.Envelope + ((Abs(DrySample) - State^.Envelope) * EnvAttack)
    else
      State^.Envelope := State^.Envelope * EnvRelease;

    Noise := NextNoise(State^.Seed);
    State^.LowNoise := State^.LowNoise + ((Noise - State^.LowNoise) * LowCoeff);
    Breath := Noise - State^.LowNoise;
    WetSample := DrySample + (Breath * State^.Envelope * Level);
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddWhisperItems;
begin
  AddGroup(GWhisperGroup, 'Whisper/Breath', 1);
  AddCheck(GWhisperUseCheck, 'Breath: Use', 0);
  AddTrack(GWhisperLevelTrack, 'Breath: Level(dB)', -18.0, -48.0, 0.0, 0.1);
  AddTrack(GWhisperToneTrack, 'Breath: Tone', 0.65, 0.0, 1.0, 0.01);
  AddTrack(GWhisperMixTrack, 'Breath: Mix', 0.5, 0.0, 1.0, 0.01);
end;

procedure SetWhisperGuiParams(UseWhisper: Boolean; LevelDb, Tone, Mix: Double);
begin
  GWhisperUseCheck.Value := Byte(UseWhisper);
  GWhisperLevelTrack.Value := LevelDb;
  GWhisperToneTrack.Value := Tone;
  GWhisperMixTrack.Value := Mix;
  ClearWhisperState;
end;

function ProcessWhisper(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  LevelDb: Single;
  Tone: Single;
  Mix: Single;
begin
  Result := GWhisperUseCheck.Value <> 0;
  if not Result then
  begin
    ClearWhisperState;
    Exit;
  end;

  LevelDb := GWhisperLevelTrack.Value;
  Tone := GWhisperToneTrack.Value;
  Mix := GWhisperMixTrack.Value;

  EnsureWhisperState(Audio, ChannelNum);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyWhisper(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate, LevelDb, Tone, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

  GWhisperNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedWhisper;
begin ClearWhisperState; end;

end.
