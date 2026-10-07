unit RigmAul2Reverb;

// Reverb 系の GUI 項目、状態、音声処理を担当する。
interface

uses System.SysUtils, System.Math, RigmAul2Adapter, RigmAul2Context;

procedure AddReverbItems;
function ProcessReverb(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetReverbGuiParams(UseReverb: Boolean; ReverbType: Integer;
  RoomSize, Damping, Dry, Wet: Double);

procedure ResetCopiedReverb;

implementation

uses Winapi.Windows;

const
  REVERB_COMB_COUNT = 4; // 並列に使う comb delay の本数
  REVERB_TYPE_ROOM  = 0;
  REVERB_TYPE_HALL  = 1;
  REVERB_TYPE_PLATE = 2;

  REVERB_ROOM_DELAY_MS_L : array[0..REVERB_COMB_COUNT - 1] of Double = (19.9, 23.9, 29.7, 31.1);
  REVERB_ROOM_DELAY_MS_R : array[0..REVERB_COMB_COUNT - 1] of Double = (20.9, 25.1, 28.3, 33.1);
  REVERB_HALL_DELAY_MS_L : array[0..REVERB_COMB_COUNT - 1] of Double = (29.7, 37.1, 41.1, 43.7);
  REVERB_HALL_DELAY_MS_R : array[0..REVERB_COMB_COUNT - 1] of Double = (31.1, 35.3, 39.7, 45.1);
  REVERB_PLATE_DELAY_MS_L: array[0..REVERB_COMB_COUNT - 1] of Double = (17.3, 19.7, 23.1, 29.9);
  REVERB_PLATE_DELAY_MS_R: array[0..REVERB_COMB_COUNT - 1] of Double = (18.1, 21.1, 24.7, 31.7);

type
  TReverbCombState = record
    Buffer  : TArray<Single>; // 1 本の comb filter 用 feedback delay line
    Position: Integer;        // 次に読み書きするリングバッファ位置
    Filter  : Single;         // Damping 用 one-pole low-pass の前回値
  end;

  TReverbChannelState = record
    Combs: array[0..REVERB_COMB_COUNT - 1] of TReverbCombState;
  end;

  TReverbContext = class(TAul2AudioFilterContextItem)
  public
    Channels  : array of TReverbChannelState;
    SampleRate: Integer;
    ReverbType: Integer;
    NextIndex : Int64;
  end;

var
  GReverbGroup     : TFILTER_ITEM_GROUP;
  GReverbUseCheck  : TFILTER_ITEM_CHECK;
  GReverbTypeSelect: TFILTER_ITEM_SELECT;
  GReverbTypeList  : array[0..3] of TFILTER_ITEM_SELECT_ITEM;
  GRoomSizeTrack   : TFILTER_ITEM_TRACK;
  GDampingTrack    : TFILTER_ITEM_TRACK;
  GReverbDryTrack  : TFILTER_ITEM_TRACK;
  GReverbWetTrack  : TFILTER_ITEM_TRACK;
  GReverbContexts  : TAul2AudioFilterContextList<TReverbContext>;
  GReverbContext   : TReverbContext;

procedure ClearReverbState;
begin
  FreeAndNil(GReverbContexts);
  GReverbContext := nil;
end;

function ClampReverbType(Value: Integer): Integer;
begin
  Result := Value;
  if (Result < REVERB_TYPE_ROOM) or (Result > REVERB_TYPE_PLATE) then
    Result := REVERB_TYPE_ROOM;
end;

function GetReverbDelayMs(ReverbType, Channel, CombIndex: Integer): Double;
begin
  case ClampReverbType(ReverbType) of
    REVERB_TYPE_HALL:
      begin
        if Odd(Channel) then
          Result := REVERB_HALL_DELAY_MS_R[CombIndex]
        else
          Result := REVERB_HALL_DELAY_MS_L[CombIndex];
      end;
    REVERB_TYPE_PLATE:
      begin
        if Odd(Channel) then
          Result := REVERB_PLATE_DELAY_MS_R[CombIndex]
        else
          Result := REVERB_PLATE_DELAY_MS_L[CombIndex];
      end;
  else
    begin
      if Odd(Channel) then
        Result := REVERB_ROOM_DELAY_MS_R[CombIndex]
      else
        Result := REVERB_ROOM_DELAY_MS_L[CombIndex];
    end;
  end;
end;

function GetReverbDelaySamples(SampleRate, ReverbType, Channel, CombIndex: Integer): Integer;
var
  DelayMs: Double;
begin
  // L/R と Type で遅延時間を変え、同じ RoomSize でも質感差が出るようにする。
  DelayMs := GetReverbDelayMs(ReverbType, Channel, CombIndex);
  Result := Round(SampleRate * DelayMs / 1000.0);
  if Result < 1 then
    Result := 1;
end;

function ReverbContexts: TAul2AudioFilterContextList<TReverbContext>;
begin
  if GReverbContexts = nil then
    GReverbContexts := TAul2AudioFilterContextList<TReverbContext>.Create;
  Result := GReverbContexts;
end;

function CurrentReverbContext: TReverbContext;
begin
  Result := GReverbContext;
end;

procedure ResetReverbState(Context: TReverbContext; ChannelNum, SampleRate, ReverbType: Integer);
var
  Channel: Integer;
  Comb: Integer;
  DelaySamples: Integer;
begin
  if Context = nil then
    Exit;

  SetLength(Context.Channels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    for Comb := 0 to REVERB_COMB_COUNT - 1 do
    begin
      DelaySamples := GetReverbDelaySamples(SampleRate, ReverbType, Channel, Comb);
      SetLength(Context.Channels[Channel].Combs[Comb].Buffer, DelaySamples);
      FillChar(Context.Channels[Channel].Combs[Comb].Buffer[0], DelaySamples * SizeOf(Single), 0);
      Context.Channels[Channel].Combs[Comb].Position := 0;
      Context.Channels[Channel].Combs[Comb].Filter := 0.0;
    end;
  end;

  Context.SampleRate := SampleRate;
  Context.ReverbType := ClampReverbType(ReverbType);
end;

procedure EnsureReverbState(Audio: PFILTER_PROC_AUDIO; ChannelNum, ReverbType: Integer);
var
  ObjectInfo: POBJECT_INFO;
  Context: TReverbContext;
begin
  ObjectInfo := Audio^.Object_;
  GReverbContext := ReverbContexts.GetContext(Audio);
  Context := GReverbContext;
  if Context = nil then
    Exit;

  // 残響は過去状態を強く使うため、別オブジェクトや不連続位置では必ずリセットする。
  if (Length(Context.Channels) <> ChannelNum) or
     (Context.SampleRate <> Audio^.Scene^.SampleRate) or
     (Context.ReverbType <> ClampReverbType(ReverbType)) or
     (Context.NextIndex <> ObjectInfo^.SampleIndex) then
    ResetReverbState(Context, ChannelNum, Audio^.Scene^.SampleRate, ReverbType);
end;

function ClampUnit(Value: Single): Single;
begin
  Result := Value;
  if Result < 0.0 then
    Result := 0.0
  else if Result > 1.0 then
    Result := 1.0;
end;

function GetReverbFeedback(ReverbType: Integer; RoomSize: Single): Single;
begin
  case ClampReverbType(ReverbType) of
    REVERB_TYPE_HALL:
      Result := 0.24 + (RoomSize * 0.68);
    REVERB_TYPE_PLATE:
      Result := 0.18 + (RoomSize * 0.62);
  else
    Result := 0.16 + (RoomSize * 0.55);
  end;

  if Result > 0.92 then
    Result := 0.92;
end;

function GetReverbDamping(ReverbType: Integer; Damping: Single): Single;
begin
  case ClampReverbType(ReverbType) of
    REVERB_TYPE_PLATE:
      Result := Damping * 0.45;
    REVERB_TYPE_ROOM:
      Result := Damping * 1.10;
  else
    Result := Damping;
  end;

  Result := ClampUnit(Result);
end;

procedure ApplyReverb(var Buffer: TArray<Single>; Channel, SampleNum: Integer;
  ReverbType: Integer; RoomSize, Damping, Dry, Wet: Single;
  CaptureWet: Boolean; var WetSum: Double);
var
  I: Integer;
  Comb: Integer;
  InputSample: Single;
  DelayedSample: Single;
  FilteredSample: Single;
  ReverbSample: Single;
  WetSample: Single;
  Feedback: Single;
  CombState: ^TReverbCombState;
  Context: TReverbContext;
begin
  Context := CurrentReverbContext;
  if Context = nil then
    Exit;

  RoomSize := ClampUnit(RoomSize);
  Damping := GetReverbDamping(ReverbType, Damping);
  Feedback := GetReverbFeedback(ReverbType, RoomSize);

  for I := 0 to SampleNum - 1 do
  begin
    InputSample := Buffer[I];
    ReverbSample := 0.0;

    for Comb := 0 to REVERB_COMB_COUNT - 1 do
    begin
      CombState := @Context.Channels[Channel].Combs[Comb];
      DelayedSample := CombState^.Buffer[CombState^.Position];
      FilteredSample := (DelayedSample * (1.0 - Damping)) + (CombState^.Filter * Damping);
      CombState^.Filter := FilteredSample;
      CombState^.Buffer[CombState^.Position] := InputSample + (FilteredSample * Feedback);
      ReverbSample := ReverbSample + FilteredSample;

      Inc(CombState^.Position);
      if CombState^.Position >= Length(CombState^.Buffer) then
        CombState^.Position := 0;
    end;

    WetSample := (ReverbSample / REVERB_COMB_COUNT) * Wet;
    if CaptureWet then
      WetSum := WetSum + Double(WetSample) * WetSample;
    Buffer[I] := (InputSample * Dry) + WetSample;
  end;
end;

procedure AddReverbItems;
begin
  AddGroup(GReverbGroup, 'Reverb', 1);
  AddCheck(GReverbUseCheck, 'Rev: Use', 0);
  GReverbTypeList[0].Name := 'Room';
  GReverbTypeList[0].Value := REVERB_TYPE_ROOM;
  GReverbTypeList[1].Name := 'Hall';
  GReverbTypeList[1].Value := REVERB_TYPE_HALL;
  GReverbTypeList[2].Name := 'Plate';
  GReverbTypeList[2].Value := REVERB_TYPE_PLATE;
  GReverbTypeList[3].Name := nil;
  GReverbTypeList[3].Value := 0;
  AddSelect(GReverbTypeSelect, 'Rev: Type', REVERB_TYPE_ROOM, @GReverbTypeList[0]);
  AddTrack(GRoomSizeTrack, 'Rev: RoomSize', 0.5, 0.0, 1.0, 0.01);
  AddTrack(GDampingTrack, 'Rev: Damping', 0.4, 0.0, 1.0, 0.01);
  AddTrack(GReverbDryTrack, 'Rev: Dry', 1.0, 0.0, 2.0, 0.01);
  AddTrack(GReverbWetTrack, 'Rev: Wet', 0.3, 0.0, 2.0, 0.01);
end;

procedure SetReverbGuiParams(UseReverb: Boolean; ReverbType: Integer;
  RoomSize, Damping, Dry, Wet: Double);
begin
  GReverbUseCheck.Value := Byte(UseReverb);
  GReverbTypeSelect.Value := ClampReverbType(ReverbType);
  GRoomSizeTrack.Value := RoomSize;
  GDampingTrack.Value := Damping;
  GReverbDryTrack.Value := Dry;
  GReverbWetTrack.Value := Wet;
  ClearReverbState;
end;

function ProcessReverb(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  CaptureRequested: Boolean;
  Channel: Integer;
  Buffer: TArray<Single>;
  ReverbType: Integer;
  RoomSize: Single;
  Damping: Single;
  Dry: Single;
  Wet: Single;
  Context: TReverbContext;
  Denominator: Double;
  WetSum: Double;
begin
  Result := GReverbUseCheck.Value <> 0;
  if not Result then
    Exit;

  ReverbType := ClampReverbType(GReverbTypeSelect.Value);
  RoomSize := GRoomSizeTrack.Value;
  Damping := GDampingTrack.Value;
  Dry := GReverbDryTrack.Value;
  Wet := GReverbWetTrack.Value;

  CaptureRequested := False;
WetSum := 0;

  EnsureReverbState(Audio, ChannelNum, ReverbType);
  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyReverb(Buffer, Channel, SampleNum, ReverbType, RoomSize, Damping, Dry,
      Wet, CaptureRequested, WetSum);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  Context := CurrentReverbContext;
  if Context <> nil then
    Context.NextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedReverb;
begin ClearReverbState; end;

end.
