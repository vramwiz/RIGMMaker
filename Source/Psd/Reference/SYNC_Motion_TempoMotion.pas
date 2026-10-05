unit SYNC_Motion_TempoMotion;

// 拍位置と共通設定からリズム変形を求め、処理対象画像へ適用する。

interface

uses
  AviUtl2FilterTypes;

type
  TRhythmMotionType = (
    rmtNone,
    rmtVerticalJump,
    rmtHorizontalJump,
    rmtShrink,
    rmtPendulum,
    rmtPendulumTwoBeat,
    rmtStep,
    rmtBounce
  );

  TRhythmTransform = record
    OffsetX, OffsetY: Integer; // 元画像の中心位置からの移動量。
    Scale           : Double;  // 1.0を原寸とする中心基準の拡大率。
    VerticalScale   : Double;  // 1.0を原寸とする下端固定の縦方向拡大率。
    AngleDegrees    : Double;  // 正方向を時計回りとする回転角度。
    TopOffsetX      : Double;  // 下端を固定したまま上端を横へ動かす変形量。
    WaistRatio      : Double;  // 下端を0、上端を1とする振り子の腰位置。
    JointFlexibility: Double;  // 0を一様傾斜、1を腰・首の区分変形とする混合率。
  end;

procedure CalculateJumpVector(BeatPosition, Speed, WidthPixels,
  AngleDegrees: Double; out OffsetX, OffsetY: Integer);
procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);
procedure CalculateRhythmTransform(MotionType: TRhythmMotionType;
  BeatPosition, Speed, Strength: Double; out Transform: TRhythmTransform;
  Param1: Double = 50.0; Param2: Double = 50.0);
procedure ApplyRhythmMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, Strength: Double;
  Param1: Double = 50.0; Param2: Double = 50.0);
procedure ApplyRhythmVolumeMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength: Double; Param1: Double = 50.0;
  Param2: Double = 50.0);
procedure ApplyMusicMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength, NoteNumber, PitchEnvelope, BaseNote,
  HighPull, LowSink: Double; Param1: Double = 50.0;
  Param2: Double = 50.0);
function CalculateVolumeScale(Level, Strength: Double): Double;
function CalculatePitchOffset(NoteNumber, Envelope, BaseNote,
  HighPull, LowSink: Double): Integer;
procedure ApplyVolumeMotion(Video: PFILTER_PROC_VIDEO;
  Level, Strength: Double);

implementation

uses
  System.Math,
  System.SysUtils;

type
  TPixelArray = array[0..0] of TPIXEL_RGBA;
  PPixelArray = ^TPixelArray;

function TryCalculateActionProgress(BeatPosition, Speed: Double;
  out Progress: Double): Boolean;
var
  BeatPhase, DurationBeats: Double;
begin
  Result := False;
  Progress := 0;
  if Speed <= 0 then
    Exit;

  DurationBeats := 1.0 / Speed;
  BeatPhase := BeatPosition - Floor(BeatPosition);
  if BeatPhase >= DurationBeats then
    Exit;

  Progress := BeatPhase / DurationBeats;
  Result := True;
end;

function TryCalculateJumpProgress(BeatPosition, Speed: Double;
  out Progress: Double): Boolean;
var
  BeatPhase, DurationBeats: Double;
begin
  Result := False;
  Progress := 0;
  if Speed <= 0 then
    Exit;

  // ジャンプは踏み込みと着地を見せるため、既定の速さ2で1拍を使う。
  // 1拍を超えると次の拍の動作と重なるため、遅い設定でも1拍を上限とする。
  DurationBeats := Min(1.0, 2.0 / Speed);
  BeatPhase := BeatPosition - Floor(BeatPosition);
  if BeatPhase >= DurationBeats then
    Exit;

  Progress := BeatPhase / DurationBeats;
  Result := True;
end;

function SmoothStep(Value: Double): Double;
begin
  Value := EnsureRange(Value, 0.0, 1.0);
  Result := Value * Value * (3.0 - 2.0 * Value);
end;

function CalculateVerticalJumpCurve(Progress: Double): Double;
const
  ANTICIPATION_END = 0.15;
  TAKEOFF_END      = 0.45;
  APEX_END         = 0.58;
  LANDING_END      = 0.85;
  ANTICIPATION     = 0.08;
  LANDING_DIP      = 0.06;
var
  Phase: Double;
begin
  Progress := EnsureRange(Progress, 0.0, 1.0);
  if Progress < ANTICIPATION_END then
  begin
    Phase := Progress / ANTICIPATION_END;
    Result := ANTICIPATION * SmoothStep(Phase);
  end
  else if Progress < TAKEOFF_END then
  begin
    Phase := (Progress - ANTICIPATION_END) /
      (TAKEOFF_END - ANTICIPATION_END);
    Result := ANTICIPATION + (-1.0 - ANTICIPATION) * SmoothStep(Phase);
  end
  else if Progress < APEX_END then
    Result := -1.0
  else if Progress < LANDING_END then
  begin
    Phase := (Progress - APEX_END) / (LANDING_END - APEX_END);
    Result := -1.0 + (1.0 + LANDING_DIP) * SmoothStep(Phase);
  end
  else
  begin
    Phase := (Progress - LANDING_END) / (1.0 - LANDING_END);
    Result := LANDING_DIP * (1.0 - SmoothStep(Phase));
  end;
end;

function CalculateTwoBeatPendulumSwing(BeatPosition, Speed: Double): Double;
var
  Phase: Double;
begin
  if Speed <= 0 then
    Exit(0);

  // 既定の速さ2では、移動と保持を各半拍ずつ行い、2拍で1周期とする。
  Phase := BeatPosition * Speed;
  Phase := Phase - Floor(Phase / 4.0) * 4.0;
  if Phase < 1.0 then
    Result := -Cos(Phase * Pi)
  else if Phase < 2.0 then
    Result := 1.0
  else if Phase < 3.0 then
    Result := Cos((Phase - 2.0) * Pi)
  else
    Result := -1.0;
end;

procedure CalculateJumpVector(BeatPosition, Speed, WidthPixels,
  AngleDegrees: Double; out OffsetX, OffsetY: Integer);
var
  BeatPhase, Distance, DurationBeats, Radians: Double;
begin
  OffsetX := 0;
  OffsetY := 0;
  if (Speed <= 0) or (WidthPixels <= 0) then
    Exit;

  DurationBeats := 1.0 / Speed;
  BeatPhase := BeatPosition - Floor(BeatPosition);
  if BeatPhase >= DurationBeats then
    Exit;

  Distance := WidthPixels * (1.0 - BeatPhase / DurationBeats);
  Radians := DegToRad(AngleDegrees);
  // 角度0を上方向とし、正方向へ回すと右、下、左の順になる。
  OffsetX := Round(Distance * Sin(Radians));
  OffsetY := -Round(Distance * Cos(Radians));
end;

procedure CalculateRhythmTransform(MotionType: TRhythmMotionType;
  BeatPosition, Speed, Strength: Double; out Transform: TRhythmTransform;
  Param1, Param2: Double);
var
  Curve, Progress, Swing: Double;
begin
  Transform.OffsetX := 0;
  Transform.OffsetY := 0;
  Transform.Scale := 1.0;
  Transform.VerticalScale := 1.0;
  Transform.AngleDegrees := 0;
  Transform.TopOffsetX := 0;
  Transform.WaistRatio := 0.475;
  Transform.JointFlexibility := 0.5;
  if (MotionType = rmtNone) or SameValue(Strength, 0) then
    Exit;

  if MotionType = rmtBounce then
  begin
    if Speed <= 0 then
      Exit;
    // 着地で縦に沈み、拍の中間で小さく浮きながらわずかに伸びる。
    Progress := BeatPosition * Speed / 2.0;
    Curve := Sqr(Sin(Progress * Pi));
    Transform.OffsetY := -Round(Strength * 0.25 * Curve);
    Transform.VerticalScale := 1.0 - Abs(Strength) / 500.0 *
      (1.0 - Curve) + Abs(Strength) / 1250.0 * Curve;
    Transform.VerticalScale := EnsureRange(Transform.VerticalScale,
      0.5, 1.5);
    Exit;
  end;

  if MotionType = rmtStep then
  begin
    if Speed <= 0 then
      Exit;
    // 左右の着地間を1拍で移動し、中央通過時に少し浮かせる。
    Progress := BeatPosition * Speed / 2.0;
    Swing := -Cos(Progress * Pi);
    Transform.OffsetX := Round(Strength * Swing);
    Transform.OffsetY := -Round(Abs(Strength) * 0.2 *
      Abs(Sin(Progress * Pi)));
    // 下半身を着地側へ動かしつつ頭側を元位置付近へ残し、明確な重心変形を作る。
    Transform.TopOffsetX := -Strength * Swing;
    Transform.WaistRatio := 0.35 +
      EnsureRange(Param1, 0.0, 100.0) * 0.0025;
    Transform.JointFlexibility :=
      EnsureRange(Param2, 0.0, 100.0) / 100.0;
    Exit;
  end;

  if MotionType in [rmtPendulum, rmtPendulumTwoBeat] then
  begin
    if MotionType = rmtPendulumTwoBeat then
      Swing := CalculateTwoBeatPendulumSwing(BeatPosition, Speed)
    else
      // 既定の速さ2では1拍で1往復し、4分の1拍ごとに中央と左右の最大点を通る。
      Swing := Sin(BeatPosition * Speed * Pi);
    Transform.TopOffsetX := Strength * Swing;
    Transform.WaistRatio := 0.35 + EnsureRange(Param1, 0.0, 100.0) * 0.0025;
    Transform.JointFlexibility := EnsureRange(Param2, 0.0, 100.0) / 100.0;
    Exit;
  end;

  case MotionType of
    rmtVerticalJump:
      begin
        if not TryCalculateJumpProgress(BeatPosition, Speed, Progress) then
          Exit;
        Transform.OffsetY := Round(Strength *
          CalculateVerticalJumpCurve(Progress));
      end;
    rmtShrink:
      begin
        if not TryCalculateActionProgress(BeatPosition, Speed, Progress) then
          Exit;
        Curve := 4.0 * Progress * (1.0 - Progress);
        Transform.Scale := 1.0 - Strength * Curve / 400.0;
      end;
  end;
end;

function IsIdentityTransform(const Transform: TRhythmTransform): Boolean;
begin
  Result := (Transform.OffsetX = 0) and (Transform.OffsetY = 0) and
    SameValue(Transform.Scale, 1.0) and
    SameValue(Transform.VerticalScale, 1.0) and
    SameValue(Transform.AngleDegrees, 0) and
    SameValue(Transform.TopOffsetX, 0);
end;

function CalculatePendulumWeight(HeightRatio, WaistRatio,
  JointFlexibility: Double): Double;
const
  WAIST_MOVEMENT_RATIO = 0.35;
var
  NeckRatio, SegmentedWeight: Double;
begin
  HeightRatio := EnsureRange(HeightRatio, 0.0, 1.0);
  WaistRatio := EnsureRange(WaistRatio, 0.2, 0.75);
  JointFlexibility := EnsureRange(JointFlexibility, 0.0, 1.0);
  NeckRatio := Min(0.9, WaistRatio + 0.3);

  if HeightRatio <= WaistRatio then
    SegmentedWeight := WAIST_MOVEMENT_RATIO *
      SmoothStep(HeightRatio / WaistRatio)
  else if HeightRatio < NeckRatio then
    SegmentedWeight := WAIST_MOVEMENT_RATIO +
      (1.0 - WAIST_MOVEMENT_RATIO) *
      SmoothStep((HeightRatio - WaistRatio) / (NeckRatio - WaistRatio))
  else
    // 首より上は同じ量だけ動かし、顔と頭部の形を保つ。
    SegmentedWeight := 1.0;

  Result := HeightRatio +
    (SegmentedWeight - HeightRatio) * JointFlexibility;
end;

procedure ShiftImage(Source, Dest: PPixelArray;
  Width, Height, OffsetX, OffsetY: Integer);
var
  CopyWidth, DestX, DestY, SourceX, SourceY: Integer;
  CopyBytes: NativeUInt;
begin
  if OffsetX >= 0 then
  begin
    SourceX := 0;
    DestX := OffsetX;
    CopyWidth := Width - OffsetX;
  end
  else
  begin
    SourceX := -OffsetX;
    DestX := 0;
    CopyWidth := Width + OffsetX;
  end;
  if CopyWidth <= 0 then
    Exit;

  CopyBytes := NativeUInt(CopyWidth) * SizeOf(TPIXEL_RGBA);
  for DestY := 0 to Height - 1 do
  begin
    SourceY := DestY - OffsetY;
    if (SourceY >= 0) and (SourceY < Height) then
      Move(Source^[SourceY * Width + SourceX],
        Dest^[DestY * Width + DestX], CopyBytes);
  end;
end;

procedure TransformImage(Source, Dest: PPixelArray; Width, Height: Integer;
  const Transform: TRhythmTransform);
var
  BottomY, CenterX, CenterY, CosAngle, DestCenterX, DestCenterY: Double;
  DeformedCenterX, DeformedCenterY, HeightRatio, InverseScale: Double;
  Radians, SinAngle, SourcePositionX, SourcePositionY: Double;
  DestX, DestY, SourceX, SourceY: Integer;
begin
  CenterX := (Width - 1) / 2.0;
  CenterY := (Height - 1) / 2.0;
  BottomY := Height - 1;
  Radians := DegToRad(Transform.AngleDegrees);
  CosAngle := Cos(Radians);
  SinAngle := Sin(Radians);
  InverseScale := 1.0 / Transform.Scale;

  for DestY := 0 to Height - 1 do
  begin
    for DestX := 0 to Width - 1 do
    begin
      DestCenterX := DestX - CenterX - Transform.OffsetX;
      DestCenterY := DestY - CenterY - Transform.OffsetY;
      DeformedCenterX := (CosAngle * DestCenterX +
        SinAngle * DestCenterY) * InverseScale;
      DeformedCenterY := (-SinAngle * DestCenterX +
        CosAngle * DestCenterY) * InverseScale;
      SourcePositionY := CenterY + DeformedCenterY;
      if Height > 1 then
        SourcePositionY := BottomY +
          (SourcePositionY - BottomY) / Transform.VerticalScale;
      if Height > 1 then
      begin
        HeightRatio := EnsureRange((Height - 1 - SourcePositionY) /
          (Height - 1), 0.0, 1.0);
        SourcePositionX := CenterX + DeformedCenterX -
          Transform.TopOffsetX * CalculatePendulumWeight(HeightRatio,
            Transform.WaistRatio, Transform.JointFlexibility);
      end
      else
        SourcePositionX := CenterX + DeformedCenterX;
      SourceX := Round(SourcePositionX);
      SourceY := Round(SourcePositionY);
      if (SourceX >= 0) and (SourceX < Width) and
        (SourceY >= 0) and (SourceY < Height) then
        Dest^[DestY * Width + DestX] := Source^[SourceY * Width + SourceX];
    end;
  end;
end;

procedure ApplyTransform(Video: PFILTER_PROC_VIDEO;
  const Transform: TRhythmTransform);
var
  BufferSize: NativeUInt;
  Height, Width: Integer;
  Dest, Source: PPixelArray;
begin
  if (Video = nil) or (Video^.Object_ = nil) or
    not Assigned(Video^.GetImageData) or
    not Assigned(Video^.SetImageData) then
    Exit;

  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;
  if NativeUInt(Width) > High(NativeUInt) div NativeUInt(Height) div
    SizeOf(TPIXEL_RGBA) then
    Exit;
  if (Transform.Scale <= 0) or (Transform.VerticalScale <= 0) or
    IsIdentityTransform(Transform) then
    Exit;

  BufferSize := NativeUInt(Width) * NativeUInt(Height) * SizeOf(TPIXEL_RGBA);
  GetMem(Source, BufferSize);
  GetMem(Dest, BufferSize);
  try
    Video^.GetImageData(PPIXEL_RGBA(Source));
    FillChar(Dest^, BufferSize, 0);
    if SameValue(Transform.Scale, 1.0) and
      SameValue(Transform.VerticalScale, 1.0) and
      SameValue(Transform.AngleDegrees, 0) and
      SameValue(Transform.TopOffsetX, 0) then
      ShiftImage(Source, Dest, Width, Height, Transform.OffsetX,
        Transform.OffsetY)
    else
      TransformImage(Source, Dest, Width, Height, Transform);
    Video^.SetImageData(PPIXEL_RGBA(Dest), Width, Height);
  finally
    FreeMem(Dest);
    FreeMem(Source);
  end;
end;

procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);
var
  Transform: TRhythmTransform;
begin
  Transform.Scale := 1.0;
  Transform.VerticalScale := 1.0;
  Transform.AngleDegrees := 0;
  Transform.TopOffsetX := 0;
  Transform.WaistRatio := 0.475;
  Transform.JointFlexibility := 0.5;
  CalculateJumpVector(BeatPosition, Speed, WidthPixels, AngleDegrees,
    Transform.OffsetX, Transform.OffsetY);
  ApplyTransform(Video, Transform);
end;

procedure ApplyRhythmMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, Strength, Param1,
  Param2: Double);
begin
  ApplyRhythmVolumeMotion(Video, MotionType, BeatPosition, Speed, Strength,
    0, 0, Param1, Param2);
end;

procedure ApplyRhythmVolumeMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength, Param1, Param2: Double);
begin
  ApplyMusicMotion(Video, MotionType, BeatPosition, Speed, RhythmStrength,
    VolumeLevel, VolumeStrength, 0, 0, 60, 0, 0, Param1, Param2);
end;

procedure ApplyMusicMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength, NoteNumber, PitchEnvelope, BaseNote,
  HighPull, LowSink, Param1, Param2: Double);
var
  Transform: TRhythmTransform;
begin
  CalculateRhythmTransform(MotionType, BeatPosition, Speed, RhythmStrength,
    Transform, Param1, Param2);
  Transform.Scale := Transform.Scale *
    CalculateVolumeScale(VolumeLevel, VolumeStrength);
  Inc(Transform.OffsetY, CalculatePitchOffset(NoteNumber, PitchEnvelope,
    BaseNote, HighPull, LowSink));
  ApplyTransform(Video, Transform);
end;

function CalculateVolumeScale(Level, Strength: Double): Double;
begin
  Result := 1.0 + EnsureRange(Level, 0.0, 1.0) * Strength / 200.0;
  Result := EnsureRange(Result, 0.01, 2.0);
end;

function CalculatePitchOffset(NoteNumber, Envelope, BaseNote,
  HighPull, LowSink: Double): Integer;
var
  Distance: Double;
begin
  Distance := EnsureRange((NoteNumber - BaseNote) / 12.0, -1.0, 1.0);
  Envelope := EnsureRange(Envelope, 0.0, 1.0);
  if Distance > 0 then
    Result := -Round(HighPull * Distance * Envelope)
  else if Distance < 0 then
    Result := Round(LowSink * -Distance * Envelope)
  else
    Result := 0;
end;

procedure ApplyVolumeMotion(Video: PFILTER_PROC_VIDEO;
  Level, Strength: Double);
var
  Transform: TRhythmTransform;
begin
  Transform.OffsetX := 0;
  Transform.OffsetY := 0;
  Transform.Scale := CalculateVolumeScale(Level, Strength);
  Transform.VerticalScale := 1.0;
  Transform.AngleDegrees := 0;
  Transform.TopOffsetX := 0;
  Transform.WaistRatio := 0.475;
  Transform.JointFlexibility := 0.5;
  ApplyTransform(Video, Transform);
end;

end.
