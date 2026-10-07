unit RigmAul2BitCrusher;

// BitCrusher 系の GUI 項目、状態管理、音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddBitCrusherItems;
function ProcessBitCrusher(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetBitCrusherGuiParams(UseBitCrusher: Boolean; BitDepth, SampleHold, Mix: Double);

procedure ResetCopiedBitCrusher;

implementation

type
  TBitCrusherChannelState = record
    HoldCounter: Integer; // 次に入力サンプルを取り直すまでの残りサンプル数
    HeldSample : Single;  // SampleHold 中に出力し続けるサンプル値
  end;

var
  GBitCrusherGroup      : TFILTER_ITEM_GROUP;
  GBitCrusherUseCheck   : TFILTER_ITEM_CHECK;
  GBitDepthTrack        : TFILTER_ITEM_TRACK;
  GSampleHoldTrack      : TFILTER_ITEM_TRACK;
  GBitCrusherMixTrack   : TFILTER_ITEM_TRACK;
  GBitCrusherChannels   : array of TBitCrusherChannelState; // チャンネル別の SampleHold 状態
  GBitCrusherObjectID   : Int64;                            // 状態を構築した対象オブジェクト
  GBitCrusherEffectID   : Int64;                            // 状態を構築した対象エフェクト
  GBitCrusherNextIndex  : Int64;                            // 連続処理を判定する次のサンプル位置

procedure ClearBitCrusherState;
begin
  SetLength(GBitCrusherChannels, 0);
  GBitCrusherObjectID := 0;
  GBitCrusherEffectID := 0;
  GBitCrusherNextIndex := 0;
end;

procedure ResetBitCrusherState(ChannelNum: Integer);
var
  Channel: Integer;
begin
  SetLength(GBitCrusherChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    GBitCrusherChannels[Channel].HoldCounter := 0;
    GBitCrusherChannels[Channel].HeldSample := 0.0;
  end;
end;

procedure EnsureBitCrusherState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  // SampleHold の状態が別素材へ混ざらないよう、処理対象や連続位置が変わったら作り直す。
  if (Length(GBitCrusherChannels) <> ChannelNum) or
     (GBitCrusherObjectID <> ObjectInfo^.ID) or
     (GBitCrusherEffectID <> ObjectInfo^.EffectID) or
     (GBitCrusherNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetBitCrusherState(ChannelNum);
    GBitCrusherObjectID := ObjectInfo^.ID;
    GBitCrusherEffectID := ObjectInfo^.EffectID;
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

function QuantizeSample(Value: Single; BitDepth: Integer): Single;
var
  MaxValue: Integer;
begin
  if BitDepth < 2 then
    BitDepth := 2
  else if BitDepth > 16 then
    BitDepth := 16;

  MaxValue := (1 shl (BitDepth - 1)) - 1;
  Result := Round(ClampSingle(Value, -1.0, 1.0) * MaxValue) / MaxValue;
end;

procedure ApplyBitCrusher(var Buffer: TArray<Single>; Channel, SampleNum, BitDepth, SampleHold: Integer;
  Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  State: ^TBitCrusherChannelState;
begin
  if SampleHold < 1 then
    SampleHold := 1;

  Mix := ClampSingle(Mix, 0.0, 1.0);
  State := @GBitCrusherChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];

    if State^.HoldCounter <= 0 then
    begin
      State^.HeldSample := QuantizeSample(DrySample, BitDepth);
      State^.HoldCounter := SampleHold;
    end;

    WetSample := State^.HeldSample;
    Dec(State^.HoldCounter);
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddBitCrusherItems;
begin
  AddGroup(GBitCrusherGroup, 'BitCrusher', 1);
  AddCheck(GBitCrusherUseCheck, 'Crush: Use', 0);
  AddTrack(GBitDepthTrack, 'Crush: BitDepth', 8.0, 2.0, 16.0, 1.0);
  AddTrack(GSampleHoldTrack, 'Crush: SampleHold', 4.0, 1.0, 64.0, 1.0);
  AddTrack(GBitCrusherMixTrack, 'Crush: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetBitCrusherGuiParams(UseBitCrusher: Boolean; BitDepth, SampleHold, Mix: Double);
begin
  GBitCrusherUseCheck.Value := Byte(UseBitCrusher);
  GBitDepthTrack.Value := BitDepth;
  GSampleHoldTrack.Value := SampleHold;
  GBitCrusherMixTrack.Value := Mix;
  ClearBitCrusherState;
end;

function ProcessBitCrusher(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  BitDepth: Integer;
  SampleHold: Integer;
  Mix: Single;
begin
  Result := GBitCrusherUseCheck.Value <> 0;
  if not Result then
  begin
    ClearBitCrusherState;
    Exit;
  end;

  BitDepth := Round(GBitDepthTrack.Value);
  SampleHold := Round(GSampleHoldTrack.Value);
  Mix := GBitCrusherMixTrack.Value;

  EnsureBitCrusherState(Audio, ChannelNum);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyBitCrusher(Buffer, Channel, SampleNum, BitDepth, SampleHold, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

  GBitCrusherNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedBitCrusher;
begin ClearBitCrusherState; end;

end.
