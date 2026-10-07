unit RigmAul2Limiter;

// Limiter 系の GUI 項目、状態管理、音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.SysUtils, System.Math, RigmAul2Adapter, RigmAul2Context;

procedure AddLimiterItems;
function ProcessLimiter(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetLimiterGuiParams(UseLimiter: Boolean; CeilingDb, ReleaseMs, Mix: Double);

procedure ResetCopiedLimiter;

implementation

type
  TLimiterChannelState = record
    Gain: Single; // 現在適用しているピーク抑制ゲイン
  end;

  TLimiterContext = class(TAul2AudioFilterContextItem)
  public
    Channels  : array of TLimiterChannelState;
    SampleRate: Integer;
    NextIndex : Int64;
  end;

var
  GLimiterGroup      : TFILTER_ITEM_GROUP;
  GLimiterUseCheck   : TFILTER_ITEM_CHECK;
  GCeilingTrack      : TFILTER_ITEM_TRACK;
  GReleaseTrack      : TFILTER_ITEM_TRACK;
  GLimiterMixTrack   : TFILTER_ITEM_TRACK;
  GLimiterContexts   : TAul2AudioFilterContextList<TLimiterContext>;
  GLimiterContext    : TLimiterContext;

procedure ClearLimiterState;
begin
  FreeAndNil(GLimiterContexts);
  GLimiterContext := nil;
end;

function LimiterContexts: TAul2AudioFilterContextList<TLimiterContext>;
begin
  if GLimiterContexts = nil then
    GLimiterContexts := TAul2AudioFilterContextList<TLimiterContext>.Create;
  Result := GLimiterContexts;
end;

function CurrentLimiterContext: TLimiterContext;
begin
  Result := GLimiterContext;
end;

procedure ResetLimiterState(Context: TLimiterContext; ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  if Context = nil then
    Exit;

  SetLength(Context.Channels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
    Context.Channels[Channel].Gain := 1.0;

  Context.SampleRate := SampleRate;
end;

procedure EnsureLimiterState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
  Context: TLimiterContext;
begin
  ObjectInfo := Audio^.Object_;
  GLimiterContext := LimiterContexts.GetContext(Audio);
  Context := GLimiterContext;
  if Context = nil then
    Exit;

  // ゲイン状態が別素材へ混ざらないよう、処理対象や連続位置が変わったら作り直す。
  if (Length(Context.Channels) <> ChannelNum) or
     (Context.SampleRate <> Audio^.Scene^.SampleRate) or
     (Context.NextIndex <> ObjectInfo^.SampleIndex) then
    ResetLimiterState(Context, ChannelNum, Audio^.Scene^.SampleRate);
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

function ReleaseCoeff(ReleaseMs: Single; SampleRate: Integer): Single;
begin
  ReleaseMs := ClampSingle(ReleaseMs, 1.0, 1000.0);
  Result := Exp(-1.0 / (SampleRate * ReleaseMs / 1000.0));
end;

procedure ApplyLimiter(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  CeilingDb, ReleaseMs, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  Level: Single;
  TargetGain: Single;
  Ceiling: Single;
  Release: Single;
  State: ^TLimiterChannelState;
  Context: TLimiterContext;
begin
  Context := CurrentLimiterContext;
  if Context = nil then
    Exit;

  Mix := ClampSingle(Mix, 0.0, 1.0);
  Ceiling := DbToLinear(CeilingDb);
  Release := ReleaseCoeff(ReleaseMs, SampleRate);
  State := @Context.Channels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    Level := Abs(DrySample);

    if Level > Ceiling then
      TargetGain := Ceiling / Level
    else
      TargetGain := 1.0;

    if TargetGain < State^.Gain then
      State^.Gain := TargetGain
    else
      State^.Gain := 1.0 - ((1.0 - State^.Gain) * Release);

    WetSample := DrySample * State^.Gain;
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddLimiterItems;
begin
  AddGroup(GLimiterGroup, 'Limiter', 1);
  AddCheck(GLimiterUseCheck, 'Lim: Use', 0);
  AddTrack(GCeilingTrack, 'Lim: Ceiling(dB)', -1.0, -24.0, 0.0, 0.1);
  AddTrack(GReleaseTrack, 'Lim: Release(ms)', 50.0, 1.0, 1000.0, 1.0);
  AddTrack(GLimiterMixTrack, 'Lim: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetLimiterGuiParams(UseLimiter: Boolean; CeilingDb, ReleaseMs, Mix: Double);
begin
  GLimiterUseCheck.Value := Byte(UseLimiter);
  GCeilingTrack.Value := CeilingDb;
  GReleaseTrack.Value := ReleaseMs;
  GLimiterMixTrack.Value := Mix;
  ClearLimiterState;
end;

function ProcessLimiter(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  CeilingDb: Single;
  ReleaseMs: Single;
  Mix: Single;
  Context: TLimiterContext;
begin
  Result := GLimiterUseCheck.Value <> 0;
  if not Result then
    Exit;

  CeilingDb := GCeilingTrack.Value;
  ReleaseMs := GReleaseTrack.Value;
  Mix := GLimiterMixTrack.Value;

  EnsureLimiterState(Audio, ChannelNum);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyLimiter(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate, CeilingDb, ReleaseMs, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

  Context := CurrentLimiterContext;
  if Context <> nil then
    Context.NextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedLimiter;
begin ClearLimiterState; end;

end.
