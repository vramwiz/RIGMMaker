unit RigmAul2Chorus;

// Chorus 系の GUI 項目、状態、音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.SysUtils, System.Math, RigmAul2Adapter, RigmAul2Context;

procedure AddChorusItems;
function ProcessChorus(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetChorusGuiParams(UseChorus: Boolean; Wide: Boolean; DelayMs, DepthMs, RateHz, Mix: Double);

procedure ResetCopiedChorus;

implementation

uses Winapi.Windows;

const
  CHORUS_STEREO_NORMAL = 0;
  CHORUS_STEREO_WIDE = 1;

type
  TChorusChannelState = record
    Buffer  : TArray<Single>; // コーラス用の短い履歴バッファ
    Position: Integer;        // 次に書き込む位置
  end;

  TChorusContext = class(TAul2AudioFilterContextItem)
  public
    Channels : array of TChorusChannelState;
    Samples  : Integer;
    NextIndex: Int64;
  end;

var
  GChorusGroup     : TFILTER_ITEM_GROUP;
  GChorusUseCheck  : TFILTER_ITEM_CHECK;
  GChorusStereoMode: TFILTER_ITEM_SELECT;
  GChorusModeList  : array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  GChorusDelayTrack: TFILTER_ITEM_TRACK;
  GChorusDepthTrack: TFILTER_ITEM_TRACK;
  GChorusRateTrack : TFILTER_ITEM_TRACK;
  GChorusMixTrack  : TFILTER_ITEM_TRACK;
  GChorusContexts  : TAul2AudioFilterContextList<TChorusContext>;
  GChorusContext   : TChorusContext;

procedure ClearChorusState;
begin
  FreeAndNil(GChorusContexts);
  GChorusContext := nil;
end;

function ChorusContexts: TAul2AudioFilterContextList<TChorusContext>;
begin
  if GChorusContexts = nil then
    GChorusContexts := TAul2AudioFilterContextList<TChorusContext>.Create;
  Result := GChorusContexts;
end;

function CurrentChorusContext: TChorusContext;
begin
  Result := GChorusContext;
end;

procedure ResetChorusState(Context: TChorusContext; ChannelNum, BufferSamples: Integer);
var
  Channel: Integer;
begin
  if Context = nil then
    Exit;

  SetLength(Context.Channels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    SetLength(Context.Channels[Channel].Buffer, BufferSamples);
    FillChar(Context.Channels[Channel].Buffer[0], BufferSamples * SizeOf(Single), 0);
    Context.Channels[Channel].Position := 0;
  end;

  Context.Samples := BufferSamples;
end;

procedure EnsureChorusState(Audio: PFILTER_PROC_AUDIO; ChannelNum, BufferSamples: Integer);
var
  ObjectInfo: POBJECT_INFO;
  Context: TChorusContext;
begin
  ObjectInfo := Audio^.Object_;
  GChorusContext := ChorusContexts.GetContext(Audio);
  Context := GChorusContext;
  if Context = nil then
    Exit;

  // 可変ディレイは過去サンプルを読むため、不連続な呼び出しでは履歴を破棄する。
  if (Length(Context.Channels) <> ChannelNum) or
     (Context.Samples <> BufferSamples) or
     (Context.NextIndex <> ObjectInfo^.SampleIndex) then
    ResetChorusState(Context, ChannelNum, BufferSamples);
end;

function ReadChorusDelaySample(const State: TChorusChannelState; DelaySamples: Double): Single;
var
  ReadPos: Double;
  Index0: Integer;
  Index1: Integer;
  Frac: Double;
  BufferLen: Integer;
begin
  BufferLen := Length(State.Buffer);
  if BufferLen <= 0 then
    Exit(0.0);

  ReadPos := State.Position - DelaySamples;
  while ReadPos < 0 do
    ReadPos := ReadPos + BufferLen;
  while ReadPos >= BufferLen do
    ReadPos := ReadPos - BufferLen;

  Index0 := Floor(ReadPos);
  Index1 := Index0 + 1;
  if Index1 >= BufferLen then
    Index1 := 0;
  Frac := ReadPos - Index0;

  // 小数サンプル位置を読むことで LFO による揺れを滑らかにする。
  Result := State.Buffer[Index0] * (1.0 - Frac) + State.Buffer[Index1] * Frac;
end;

procedure ApplyChorus(var Buffer: TArray<Single>; Channel, SampleNum: Integer;
  SampleRate, SampleIndex: Int64; BaseDelayMs, DepthMs, RateHz, Mix: Single;
  StereoMode: Integer);
var
  I: Integer;
  InputSample: Single;
  DelayMs: Double;
  DelaySamples: Double;
  Phase: Double;
  DelayedSample: Single;
  State: ^TChorusChannelState;
  Context: TChorusContext;
begin
  Context := CurrentChorusContext;
  if Context = nil then
    Exit;

  State := @Context.Channels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    InputSample := Buffer[I];
    Phase := 2.0 * Pi * RateHz * ((SampleIndex + I) / SampleRate);
    if (StereoMode = CHORUS_STEREO_WIDE) and (Channel = 1) then
      // Wide は右チャンネルの LFO 位相を反転させて左右差を作る。
      Phase := Phase + Pi;

    DelayMs := BaseDelayMs + (Sin(Phase) * DepthMs);
    if DelayMs < 0.0 then
      DelayMs := 0.0;

    DelaySamples := SampleRate * DelayMs / 1000.0;
    DelayedSample := ReadChorusDelaySample(State^, DelaySamples);
    State^.Buffer[State^.Position] := InputSample;

    Buffer[I] := (InputSample * (1.0 - Mix)) + (DelayedSample * Mix);

    Inc(State^.Position);
    if State^.Position >= Context.Samples then
      State^.Position := 0;
  end;
end;

procedure AddChorusItems;
begin
  AddGroup(GChorusGroup, 'Chorus', 1);
  AddCheck(GChorusUseCheck, 'Cho: Use', 0);
  GChorusModeList[0].Name := 'Normal';
  GChorusModeList[0].Value := CHORUS_STEREO_NORMAL;
  GChorusModeList[1].Name := 'Wide';
  GChorusModeList[1].Value := CHORUS_STEREO_WIDE;
  GChorusModeList[2].Name := nil;
  GChorusModeList[2].Value := 0;
  AddSelect(GChorusStereoMode, 'Cho: Stereo Mode', CHORUS_STEREO_NORMAL, @GChorusModeList[0]);
  AddTrack(GChorusDelayTrack, 'Cho: Delay(ms)', 15.0, 1.0, 50.0, 0.1);
  AddTrack(GChorusDepthTrack, 'Cho: Depth(ms)', 5.0, 0.0, 20.0, 0.1);
  AddTrack(GChorusRateTrack, 'Cho: Rate(Hz)', 0.5, 0.01, 10.0, 0.01);
  AddTrack(GChorusMixTrack, 'Cho: Mix', 0.5, 0.0, 1.0, 0.01);
end;

procedure SetChorusGuiParams(UseChorus: Boolean; Wide: Boolean; DelayMs, DepthMs, RateHz, Mix: Double);
begin
  GChorusUseCheck.Value := Byte(UseChorus);
  if Wide then
    GChorusStereoMode.Value := CHORUS_STEREO_WIDE
  else
    GChorusStereoMode.Value := CHORUS_STEREO_NORMAL;
  GChorusDelayTrack.Value := DelayMs;
  GChorusDepthTrack.Value := DepthMs;
  GChorusRateTrack.Value := RateHz;
  GChorusMixTrack.Value := Mix;
  ClearChorusState;
end;

function ProcessChorus(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  CaptureRequested: Boolean;
  Channel: Integer;
  BufferSamples: Integer;
  Buffer: TArray<Single>;
  BaseDelayMs: Single;
  DepthMs: Single;
  RateHz: Single;
  Mix: Single;
  StereoMode: Integer;
  Context: TChorusContext;
  Correlation: Double;
  CorrelationValid: Boolean;
  CurrentDelayL: Double;
  CurrentDelayR: Double;
  LeftOutput: TArray<Single>;
  PhaseCycles: Double;
  Sample: Integer;
  SumL2: Double;
  SumLR: Double;
  SumR2: Double;
begin
  Result := GChorusUseCheck.Value <> 0;
  if not Result then
    Exit;

  BaseDelayMs := GChorusDelayTrack.Value;
  DepthMs := GChorusDepthTrack.Value;
  RateHz := GChorusRateTrack.Value;
  Mix := GChorusMixTrack.Value;
  StereoMode := GChorusStereoMode.Value;

  CaptureRequested := False;
Correlation := 0;
  CorrelationValid := False;
  SumL2 := 0;
  SumR2 := 0;
  SumLR := 0;

  BufferSamples := Ceil(Audio^.Scene^.SampleRate * (BaseDelayMs + DepthMs) / 1000.0) + 4;
  if BufferSamples < 4 then
    BufferSamples := 4;

  // 最大ディレイより少し長く確保し、線形補間の次サンプル参照に余裕を持たせる。
  EnsureChorusState(Audio, ChannelNum, BufferSamples);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyChorus(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate,
      Audio^.Object_^.SampleIndex, BaseDelayMs, DepthMs, RateHz, Mix, StereoMode);

    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  Context := CurrentChorusContext;
  if Context <> nil then
    Context.NextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedChorus;
begin ClearChorusState; end;

end.
