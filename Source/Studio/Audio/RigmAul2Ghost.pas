unit RigmAul2Ghost;

// ReverseReverb/Ghost 系の GUI 項目、状態管理、幽霊的な残響影を作る処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddGhostItems;
function ProcessGhost(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetGhostGuiParams(UseGhost: Boolean; SizeMs, Feedback, Wet, Mix: Double);

procedure ResetCopiedGhost;

implementation

uses Winapi.Windows, System.SysUtils;

type
  TGhostChannelState = record
    Buffer  : TArray<Single>; // ゴースト残響用の履歴バッファ
    Position: Integer;        // 次に書き込む位置
    Smear   : Single;         // 残響影の平滑状態
  end;

var
  GGhostGroup     : TFILTER_ITEM_GROUP;
  GGhostUseCheck  : TFILTER_ITEM_CHECK;
  GGhostSizeTrack : TFILTER_ITEM_TRACK;
  GGhostFeedbackTrack: TFILTER_ITEM_TRACK;
  GGhostWetTrack  : TFILTER_ITEM_TRACK;
  GGhostMixTrack  : TFILTER_ITEM_TRACK;
  GGhostChannels  : array of TGhostChannelState; // チャンネル別の残響状態
  GGhostSamples   : Integer;                     // 現在確保している履歴長
  GGhostObjectID  : Int64;                       // 状態を構築した対象オブジェクト
  GGhostEffectID  : Int64;                       // 状態を構築した対象エフェクト
  GGhostNextIndex : Int64;                       // 連続処理を判定する次サンプル位置

procedure ClearGhostState;
begin
  SetLength(GGhostChannels, 0);
  GGhostSamples := 0;
  GGhostObjectID := 0;
  GGhostEffectID := 0;
  GGhostNextIndex := 0;
end;

procedure ResetGhostState(ChannelNum, BufferSamples: Integer);
var
  Channel: Integer;
begin
  SetLength(GGhostChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    SetLength(GGhostChannels[Channel].Buffer, BufferSamples);
    FillChar(GGhostChannels[Channel].Buffer[0], BufferSamples * SizeOf(Single), 0);
    GGhostChannels[Channel].Position := 0;
    GGhostChannels[Channel].Smear := 0.0;
  end;

  GGhostSamples := BufferSamples;
end;

procedure EnsureGhostState(Audio: PFILTER_PROC_AUDIO; ChannelNum, BufferSamples: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  if (Length(GGhostChannels) <> ChannelNum) or
     (GGhostSamples <> BufferSamples) or
     (GGhostObjectID <> ObjectInfo^.ID) or
     (GGhostEffectID <> ObjectInfo^.EffectID) or
     (GGhostNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetGhostState(ChannelNum, BufferSamples);
    GGhostObjectID := ObjectInfo^.ID;
    GGhostEffectID := ObjectInfo^.EffectID;
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

procedure ApplyGhost(var Buffer: TArray<Single>; Channel, SampleNum: Integer;
  Feedback, Wet, Mix: Single; CaptureAdded: Boolean; var AddedSum: Double);
var
  AddedSample: Single;
  I: Integer;
  DrySample: Single;
  TapSample: Single;
  GhostSample: Single;
  ReadPos: Integer;
  State: ^TGhostChannelState;
begin
  Feedback := ClampSingle(Feedback, 0.0, 0.95);
  Wet := ClampSingle(Wet, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  State := @GGhostChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    ReadPos := State^.Position + (GGhostSamples div 2);
    if ReadPos >= GGhostSamples then
      Dec(ReadPos, GGhostSamples);

    TapSample := State^.Buffer[ReadPos];
    State^.Smear := (State^.Smear * 0.985) + (TapSample * 0.015);
    GhostSample := State^.Smear * Wet;
    State^.Buffer[State^.Position] := DrySample + (GhostSample * Feedback);
    AddedSample := GhostSample * Mix;
    if CaptureAdded then
      AddedSum := AddedSum + Double(AddedSample) * AddedSample;
    Buffer[I] := DrySample + AddedSample;

    Inc(State^.Position);
    if State^.Position >= GGhostSamples then
      State^.Position := 0;
  end;
end;

procedure AddGhostItems;
begin
  AddGroup(GGhostGroup, 'ReverseReverb/Ghost', 1);
  AddCheck(GGhostUseCheck, 'Ghost: Use', 0);
  AddTrack(GGhostSizeTrack, 'Ghost: Size(ms)', 420.0, 80.0, 1500.0, 10.0);
  AddTrack(GGhostFeedbackTrack, 'Ghost: Feedback', 0.45, 0.0, 0.95, 0.01);
  AddTrack(GGhostWetTrack, 'Ghost: Wet', 0.35, 0.0, 1.0, 0.01);
  AddTrack(GGhostMixTrack, 'Ghost: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetGhostGuiParams(UseGhost: Boolean; SizeMs, Feedback, Wet, Mix: Double);
begin
  GGhostUseCheck.Value := Byte(UseGhost);
  GGhostSizeTrack.Value := SizeMs;
  GGhostFeedbackTrack.Value := Feedback;
  GGhostWetTrack.Value := Wet;
  GGhostMixTrack.Value := Mix;
  ClearGhostState;
end;

function ProcessGhost(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  AddedSum: Double;
  Channel: Integer;
  BufferSamples: Integer;
  Buffer: TArray<Single>;
  CaptureRequested: Boolean;
  Denominator: Double;
begin
  Result := GGhostUseCheck.Value <> 0;
  if not Result then
  begin
    ClearGhostState;
    Exit;
  end;

  BufferSamples := Ceil(Audio^.Scene^.SampleRate * GGhostSizeTrack.Value / 1000.0);
  if BufferSamples < 4 then
    BufferSamples := 4;

  EnsureGhostState(Audio, ChannelNum, BufferSamples);

  CaptureRequested := False;
AddedSum := 0;
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyGhost(Buffer, Channel, SampleNum, GGhostFeedbackTrack.Value,
      GGhostWetTrack.Value, GGhostMixTrack.Value, CaptureRequested, AddedSum);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  GGhostNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedGhost;
begin ClearGhostState; end;

end.
