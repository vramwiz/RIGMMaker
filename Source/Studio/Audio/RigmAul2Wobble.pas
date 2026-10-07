unit RigmAul2Wobble;

// Wobble 系の GUI 項目、状態管理、ゆっくりした可変ディレイ処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddWobbleItems;
function ProcessWobble(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetWobbleGuiParams(UseWobble: Boolean; DelayMs, DepthMs, RateHz, Mix: Double);

procedure ResetCopiedWobble;

implementation

uses Winapi.Windows, System.SysUtils;

type
  TWobbleChannelState = record
    Buffer  : TArray<Single>; // Wobble 用の履歴バッファ
    Position: Integer;        // 次に書き込む位置
  end;

var
  GWobbleGroup     : TFILTER_ITEM_GROUP;
  GWobbleUseCheck  : TFILTER_ITEM_CHECK;
  GWobbleDelayTrack: TFILTER_ITEM_TRACK;
  GWobbleDepthTrack: TFILTER_ITEM_TRACK;
  GWobbleRateTrack : TFILTER_ITEM_TRACK;
  GWobbleMixTrack  : TFILTER_ITEM_TRACK;
  GWobbleChannels  : array of TWobbleChannelState; // チャンネル別の遅延状態
  GWobbleSamples   : Integer;                      // 現在確保している履歴長
  GWobbleObjectID  : Int64;                        // 状態を構築した対象オブジェクト
  GWobbleEffectID  : Int64;                        // 状態を構築した対象エフェクト
  GWobbleNextIndex : Int64;                        // 連続処理を判定する次サンプル位置

procedure ClearWobbleState;
begin
  SetLength(GWobbleChannels, 0);
  GWobbleSamples := 0;
  GWobbleObjectID := 0;
  GWobbleEffectID := 0;
  GWobbleNextIndex := 0;
end;

procedure ResetWobbleState(ChannelNum, BufferSamples: Integer);
var
  Channel: Integer;
begin
  SetLength(GWobbleChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    SetLength(GWobbleChannels[Channel].Buffer, BufferSamples);
    FillChar(GWobbleChannels[Channel].Buffer[0], BufferSamples * SizeOf(Single), 0);
    GWobbleChannels[Channel].Position := 0;
  end;

  GWobbleSamples := BufferSamples;
end;

procedure EnsureWobbleState(Audio: PFILTER_PROC_AUDIO; ChannelNum, BufferSamples: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  // 可変ディレイは過去サンプルを読むため、不連続な呼び出しでは履歴を破棄する。
  if (Length(GWobbleChannels) <> ChannelNum) or
     (GWobbleSamples <> BufferSamples) or
     (GWobbleObjectID <> ObjectInfo^.ID) or
     (GWobbleEffectID <> ObjectInfo^.EffectID) or
     (GWobbleNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetWobbleState(ChannelNum, BufferSamples);
    GWobbleObjectID := ObjectInfo^.ID;
    GWobbleEffectID := ObjectInfo^.EffectID;
  end;
end;

function ReadWobbleDelaySample(const State: TWobbleChannelState; DelaySamples: Double): Single;
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

  Result := State.Buffer[Index0] * (1.0 - Frac) + State.Buffer[Index1] * Frac;
end;

procedure ApplyWobble(var Buffer: TArray<Single>; Channel, SampleNum: Integer;
  SampleRate, SampleIndex: Int64; BaseDelayMs, DepthMs, RateHz, Mix: Single);
var
  I: Integer;
  InputSample: Single;
  DelayMs: Double;
  DelaySamples: Double;
  Phase: Double;
  DelayedSample: Single;
  State: ^TWobbleChannelState;
begin
  State := @GWobbleChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    InputSample := Buffer[I];
    Phase := 2.0 * Pi * RateHz * ((SampleIndex + I) / SampleRate);
    DelayMs := BaseDelayMs + (Sin(Phase) * DepthMs);
    if DelayMs < 0.0 then
      DelayMs := 0.0;

    DelaySamples := SampleRate * DelayMs / 1000.0;
    DelayedSample := ReadWobbleDelaySample(State^, DelaySamples);
    State^.Buffer[State^.Position] := InputSample;
    Buffer[I] := (InputSample * (1.0 - Mix)) + (DelayedSample * Mix);

    Inc(State^.Position);
    if State^.Position >= GWobbleSamples then
      State^.Position := 0;
  end;
end;

procedure AddWobbleItems;
begin
  AddGroup(GWobbleGroup, 'Wobble', 1);
  AddCheck(GWobbleUseCheck, 'Wob: Use', 0);
  AddTrack(GWobbleDelayTrack, 'Wob: Delay(ms)', 24.0, 1.0, 120.0, 0.1);
  AddTrack(GWobbleDepthTrack, 'Wob: Depth(ms)', 12.0, 0.0, 80.0, 0.1);
  AddTrack(GWobbleRateTrack, 'Wob: Rate(Hz)', 1.2, 0.05, 8.0, 0.01);
  AddTrack(GWobbleMixTrack, 'Wob: Mix', 0.65, 0.0, 1.0, 0.01);
end;

procedure SetWobbleGuiParams(UseWobble: Boolean; DelayMs, DepthMs, RateHz, Mix: Double);
begin
  GWobbleUseCheck.Value := Byte(UseWobble);
  GWobbleDelayTrack.Value := DelayMs;
  GWobbleDepthTrack.Value := DepthMs;
  GWobbleRateTrack.Value := RateHz;
  GWobbleMixTrack.Value := Mix;
  ClearWobbleState;
end;

function ProcessWobble(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  CaptureRequested: Boolean;
  Channel: Integer;
  BufferSamples: Integer;
  Buffer: TArray<Single>;
  BaseDelayMs: Single;
  DepthMs: Single;
  RateHz: Single;
  Mix: Single;
  CurrentDelayMs: Double;
  PhaseCycles: Double;
begin
  Result := GWobbleUseCheck.Value <> 0;
  if not Result then
  begin
    ClearWobbleState;
    Exit;
  end;

  BaseDelayMs := GWobbleDelayTrack.Value;
  DepthMs := GWobbleDepthTrack.Value;
  RateHz := GWobbleRateTrack.Value;
  Mix := GWobbleMixTrack.Value;

  CaptureRequested := False;
BufferSamples := Ceil(Audio^.Scene^.SampleRate * (BaseDelayMs + DepthMs) / 1000.0) + 4;
  if BufferSamples < 4 then
    BufferSamples := 4;

  EnsureWobbleState(Audio, ChannelNum, BufferSamples);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyWobble(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate,
      Audio^.Object_^.SampleIndex, BaseDelayMs, DepthMs, RateHz, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  GWobbleNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedWobble;
begin ClearWobbleState; end;

end.
