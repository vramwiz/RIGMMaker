unit RigmAul2Muffle;

// Muffle 系の GUI 項目、状態管理、こもった音色を作るローパス処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddMuffleItems;
function ProcessMuffle(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetMuffleGuiParams(UseMuffle: Boolean; CutoffHz, Amount, Mix: Double);

procedure ResetCopiedMuffle;

implementation

type
  TMuffleChannelState = record
    Low1: Single; // 1段目ローパス状態
    Low2: Single; // 2段目ローパス状態
  end;

var
  GMuffleGroup     : TFILTER_ITEM_GROUP;
  GMuffleUseCheck  : TFILTER_ITEM_CHECK;
  GMuffleCutoffTrack: TFILTER_ITEM_TRACK;
  GMuffleAmountTrack: TFILTER_ITEM_TRACK;
  GMuffleMixTrack  : TFILTER_ITEM_TRACK;
  GMuffleChannels  : array of TMuffleChannelState; // チャンネル別のローパス状態
  GMuffleSampleRate: Integer;                      // 状態を構築したサンプルレート
  GMuffleObjectID  : Int64;                        // 状態を構築した対象オブジェクト
  GMuffleEffectID  : Int64;                        // 状態を構築した対象エフェクト
  GMuffleNextIndex : Int64;                        // 連続処理を判定する次のサンプル位置

procedure ClearMuffleState;
begin
  SetLength(GMuffleChannels, 0);
  GMuffleSampleRate := 0;
  GMuffleObjectID := 0;
  GMuffleEffectID := 0;
  GMuffleNextIndex := 0;
end;

procedure ResetMuffleState(ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  SetLength(GMuffleChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    GMuffleChannels[Channel].Low1 := 0.0;
    GMuffleChannels[Channel].Low2 := 0.0;
  end;

  GMuffleSampleRate := SampleRate;
end;

procedure EnsureMuffleState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  if (Length(GMuffleChannels) <> ChannelNum) or
     (GMuffleSampleRate <> Audio^.Scene^.SampleRate) or
     (GMuffleObjectID <> ObjectInfo^.ID) or
     (GMuffleEffectID <> ObjectInfo^.EffectID) or
     (GMuffleNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetMuffleState(ChannelNum, Audio^.Scene^.SampleRate);
    GMuffleObjectID := ObjectInfo^.ID;
    GMuffleEffectID := ObjectInfo^.EffectID;
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

procedure ApplyMuffle(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  CutoffHz, Amount, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  Coeff: Single;
  State: ^TMuffleChannelState;
begin
  CutoffHz := ClampSingle(CutoffHz, 80.0, 8000.0);
  Amount := ClampSingle(Amount, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  Coeff := 1.0 - Exp(-2.0 * Pi * CutoffHz / SampleRate);
  State := @GMuffleChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    State^.Low1 := State^.Low1 + ((DrySample - State^.Low1) * Coeff);
    State^.Low2 := State^.Low2 + ((State^.Low1 - State^.Low2) * Coeff);
    WetSample := (DrySample * (1.0 - Amount)) + (State^.Low2 * Amount);
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddMuffleItems;
begin
  AddGroup(GMuffleGroup, 'Muffle', 1);
  AddCheck(GMuffleUseCheck, 'Muffle: Use', 0);
  AddTrack(GMuffleCutoffTrack, 'Muffle: Cutoff(Hz)', 1200.0, 80.0, 8000.0, 10.0);
  AddTrack(GMuffleAmountTrack, 'Muffle: Amount', 0.8, 0.0, 1.0, 0.01);
  AddTrack(GMuffleMixTrack, 'Muffle: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetMuffleGuiParams(UseMuffle: Boolean; CutoffHz, Amount, Mix: Double);
begin
  GMuffleUseCheck.Value := Byte(UseMuffle);
  GMuffleCutoffTrack.Value := CutoffHz;
  GMuffleAmountTrack.Value := Amount;
  GMuffleMixTrack.Value := Mix;
  ClearMuffleState;
end;

function ProcessMuffle(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
begin
  Result := GMuffleUseCheck.Value <> 0;
  if not Result then
  begin
    ClearMuffleState;
    Exit;
  end;

  EnsureMuffleState(Audio, ChannelNum);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyMuffle(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate,
      GMuffleCutoffTrack.Value, GMuffleAmountTrack.Value, GMuffleMixTrack.Value);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;

  GMuffleNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedMuffle;
begin ClearMuffleState; end;

end.
