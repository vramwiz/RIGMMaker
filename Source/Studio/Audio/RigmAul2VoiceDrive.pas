unit RigmAul2VoiceDrive;

// VoiceDrive 系の GUI 項目、状態管理、声向けサチュレーション処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddVoiceDriveItems;
function ProcessVoiceDrive(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetVoiceDriveGuiParams(UseVoiceDrive: Boolean; DriveDb, Body, LevelDb, Mix: Double);

procedure ResetCopiedVoiceDrive;

implementation

uses Winapi.Windows, System.SysUtils;

type
  TVoiceDriveChannelState = record
    LowSample: Single; // 声の太さを作るための低域側状態
  end;

var
  GVoiceDriveGroup      : TFILTER_ITEM_GROUP;
  GVoiceDriveUseCheck   : TFILTER_ITEM_CHECK;
  GVoiceDriveDriveTrack : TFILTER_ITEM_TRACK;
  GVoiceDriveBodyTrack  : TFILTER_ITEM_TRACK;
  GVoiceDriveLevelTrack : TFILTER_ITEM_TRACK;
  GVoiceDriveMixTrack   : TFILTER_ITEM_TRACK;
  GVoiceDriveChannels   : array of TVoiceDriveChannelState; // チャンネル別の低域状態
  GVoiceDriveSampleRate : Integer;                          // 状態を構築したサンプルレート
  GVoiceDriveObjectID   : Int64;                            // 状態を構築した対象オブジェクト
  GVoiceDriveEffectID   : Int64;                            // 状態を構築した対象エフェクト
  GVoiceDriveNextIndex  : Int64;                            // 連続処理を判定する次のサンプル位置

procedure ClearVoiceDriveState;
begin
  SetLength(GVoiceDriveChannels, 0);
  GVoiceDriveSampleRate := 0;
  GVoiceDriveObjectID := 0;
  GVoiceDriveEffectID := 0;
  GVoiceDriveNextIndex := 0;
end;

procedure ResetVoiceDriveState(ChannelNum, SampleRate: Integer);
var
  Channel: Integer;
begin
  SetLength(GVoiceDriveChannels, ChannelNum);

  for Channel := 0 to ChannelNum - 1 do
    GVoiceDriveChannels[Channel].LowSample := 0.0;

  GVoiceDriveSampleRate := SampleRate;
end;

procedure EnsureVoiceDriveState(Audio: PFILTER_PROC_AUDIO; ChannelNum: Integer);
var
  ObjectInfo: POBJECT_INFO;
begin
  ObjectInfo := Audio^.Object_;

  // 低域状態が別素材へ混ざらないよう、処理対象や連続位置が変わったら作り直す。
  if (Length(GVoiceDriveChannels) <> ChannelNum) or
     (GVoiceDriveSampleRate <> Audio^.Scene^.SampleRate) or
     (GVoiceDriveObjectID <> ObjectInfo^.ID) or
     (GVoiceDriveEffectID <> ObjectInfo^.EffectID) or
     (GVoiceDriveNextIndex <> ObjectInfo^.SampleIndex) then
  begin
    ResetVoiceDriveState(ChannelNum, Audio^.Scene^.SampleRate);
    GVoiceDriveObjectID := ObjectInfo^.ID;
    GVoiceDriveEffectID := ObjectInfo^.EffectID;
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

procedure ApplyVoiceDrive(var Buffer: TArray<Single>; Channel, SampleNum, SampleRate: Integer;
  DriveDb, Body, LevelDb, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  Drive: Single;
  Level: Single;
  BodyMix: Single;
  LowCoeff: Single;
  DrivenInput: Single;
  Normalizer: Single;
  State: ^TVoiceDriveChannelState;
begin
  BodyMix := ClampSingle(Body, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  Drive := DbToLinear(DriveDb);
  Level := DbToLinear(LevelDb);
  LowCoeff := 1.0 - Exp(-2.0 * Pi * 700.0 / SampleRate);
  Normalizer := Tanh(Drive);
  if Normalizer <= 0.0 then
    Normalizer := 1.0;

  State := @GVoiceDriveChannels[Channel];

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];
    State^.LowSample := State^.LowSample + ((DrySample - State^.LowSample) * LowCoeff);
    DrivenInput := (DrySample * (1.0 - (BodyMix * 0.35))) + (State^.LowSample * BodyMix * 0.35);
    WetSample := (Tanh(DrivenInput * Drive) / Normalizer) * Level;
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddVoiceDriveItems;
begin
  AddGroup(GVoiceDriveGroup, 'VoiceDrive', 1);
  AddCheck(GVoiceDriveUseCheck, 'Drive: Use', 0);
  AddTrack(GVoiceDriveDriveTrack, 'Drive: Drive(dB)', 9.0, 0.0, 30.0, 0.1);
  AddTrack(GVoiceDriveBodyTrack, 'Drive: Body', 0.45, 0.0, 1.0, 0.01);
  AddTrack(GVoiceDriveLevelTrack, 'Drive: Level(dB)', -6.0, -24.0, 6.0, 0.1);
  AddTrack(GVoiceDriveMixTrack, 'Drive: Mix', 0.6, 0.0, 1.0, 0.01);
end;

procedure SetVoiceDriveGuiParams(UseVoiceDrive: Boolean; DriveDb, Body, LevelDb, Mix: Double);
begin
  GVoiceDriveUseCheck.Value := Byte(UseVoiceDrive);
  GVoiceDriveDriveTrack.Value := DriveDb;
  GVoiceDriveBodyTrack.Value := Body;
  GVoiceDriveLevelTrack.Value := LevelDb;
  GVoiceDriveMixTrack.Value := Mix;
  ClearVoiceDriveState;
end;

function ProcessVoiceDrive(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  DriveDb: Single;

Body: Single;
  LevelDb: Single;
  Mix: Single;
  OutputCount: Integer;

SampleCount: Integer;
  CaptureRequested: Boolean;
begin
  Result := GVoiceDriveUseCheck.Value <> 0;
  if not Result then
  begin
    ClearVoiceDriveState;
    Exit;
  end;

  DriveDb := GVoiceDriveDriveTrack.Value;
  Body := GVoiceDriveBodyTrack.Value;
  LevelDb := GVoiceDriveLevelTrack.Value;
  Mix := GVoiceDriveMixTrack.Value;

  CaptureRequested := False;
EnsureVoiceDriveState(Audio, ChannelNum);

  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyVoiceDrive(Buffer, Channel, SampleNum, Audio^.Scene^.SampleRate, DriveDb, Body, LevelDb, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;


  GVoiceDriveNextIndex := Audio^.Object_^.SampleIndex + SampleNum;
end;

procedure ResetCopiedVoiceDrive;
begin ClearVoiceDriveState; end;

end.
