unit RigmAul2Distortion;

// Distortion / Saturation 系の GUI 項目、音声処理を担当する。

// Adapted from Aul2AudioFilter: offline mono PCM; no AviUtl shared-memory telemetry.
interface

uses System.Math, RigmAul2Adapter;

procedure AddDistortionItems;
function ProcessDistortion(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
procedure SetDistortionGuiParams(UseDistortion: Boolean; HardClip: Boolean;
  DriveDb, Tone, LevelDb, Mix: Double);

procedure ResetCopiedDistortion;

implementation

const
  DISTORTION_MODE_SOFT_CLIP = 0;
  DISTORTION_MODE_HARD_CLIP = 1;

var
  GDistortionGroup     : TFILTER_ITEM_GROUP;
  GDistortionUseCheck  : TFILTER_ITEM_CHECK;
  GDistortionModeSelect: TFILTER_ITEM_SELECT;
  GDistortionModeList  : array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  GDriveTrack          : TFILTER_ITEM_TRACK;
  GToneTrack           : TFILTER_ITEM_TRACK;
  GLevelTrack          : TFILTER_ITEM_TRACK;
  GDistortionMixTrack  : TFILTER_ITEM_TRACK;

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

function SoftClip(Value: Single): Single;
begin
  Result := Tanh(Value);
end;

function HardClip(Value: Single): Single;
begin
  Result := ClampSingle(Value, -1.0, 1.0);
end;

procedure ApplyDistortion(var Buffer: TArray<Single>; SampleNum, Mode: Integer;
  DriveDb, Tone, LevelDb, Mix: Single);
var
  I: Integer;
  DrySample: Single;
  WetSample: Single;
  DriveGain: Single;
  OutputGain: Single;
begin
  Tone := ClampSingle(Tone, 0.0, 1.0);
  Mix := ClampSingle(Mix, 0.0, 1.0);
  DriveGain := DbToLinear(DriveDb);
  OutputGain := DbToLinear(LevelDb);

  for I := 0 to SampleNum - 1 do
  begin
    DrySample := Buffer[I];

    case Mode of
      DISTORTION_MODE_HARD_CLIP:
        WetSample := HardClip(DrySample * DriveGain);
    else
      WetSample := SoftClip(DrySample * DriveGain);
    end;

    // Tone は歪み音の強さを元音へ少し戻す簡易的な明るさ調整として扱う。
    WetSample := (WetSample * Tone) + (DrySample * (1.0 - Tone));
    WetSample := WetSample * OutputGain;
    Buffer[I] := (DrySample * (1.0 - Mix)) + (WetSample * Mix);
  end;
end;

procedure AddDistortionItems;
begin
  AddGroup(GDistortionGroup, 'Distortion', 1);
  AddCheck(GDistortionUseCheck, 'Dist: Use', 0);
  GDistortionModeList[0].Name := 'Soft Clip';
  GDistortionModeList[0].Value := DISTORTION_MODE_SOFT_CLIP;
  GDistortionModeList[1].Name := 'Hard Clip';
  GDistortionModeList[1].Value := DISTORTION_MODE_HARD_CLIP;
  GDistortionModeList[2].Name := nil;
  GDistortionModeList[2].Value := 0;
  AddSelect(GDistortionModeSelect, 'Dist: Mode', DISTORTION_MODE_SOFT_CLIP, @GDistortionModeList[0]);
  AddTrack(GDriveTrack, 'Dist: Drive(dB)', 6.0, 0.0, 36.0, 0.1);
  AddTrack(GToneTrack, 'Dist: Tone', 1.0, 0.0, 1.0, 0.01);
  AddTrack(GLevelTrack, 'Dist: Level(dB)', -6.0, -24.0, 12.0, 0.1);
  AddTrack(GDistortionMixTrack, 'Dist: Mix', 1.0, 0.0, 1.0, 0.01);
end;

procedure SetDistortionGuiParams(UseDistortion: Boolean; HardClip: Boolean;
  DriveDb, Tone, LevelDb, Mix: Double);
begin
  GDistortionUseCheck.Value := Byte(UseDistortion);
  if HardClip then
    GDistortionModeSelect.Value := DISTORTION_MODE_HARD_CLIP
  else
    GDistortionModeSelect.Value := DISTORTION_MODE_SOFT_CLIP;
  GDriveTrack.Value := DriveDb;
  GToneTrack.Value := Tone;
  GLevelTrack.Value := LevelDb;
  GDistortionMixTrack.Value := Mix;
end;

function ProcessDistortion(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
var
  Channel: Integer;
  Buffer: TArray<Single>;
  Mode: Integer;
  DriveDb: Single;
  Tone: Single;
  LevelDb: Single;
  Mix: Single;
begin
  Result := GDistortionUseCheck.Value <> 0;
  if not Result then
    Exit;

  Mode := GDistortionModeSelect.Value;
  DriveDb := GDriveTrack.Value;
  Tone := GToneTrack.Value;
  LevelDb := GLevelTrack.Value;
  Mix := GDistortionMixTrack.Value;

  SetLength(Buffer, SampleNum);

  for Channel := 0 to ChannelNum - 1 do
  begin
    Audio^.GetSampleData(@Buffer[0], Channel);
    ApplyDistortion(Buffer, SampleNum, Mode, DriveDb, Tone, LevelDb, Mix);
    Audio^.SetSampleData(@Buffer[0], Channel);
  end;
end;

procedure ResetCopiedDistortion;
begin end;

end.
