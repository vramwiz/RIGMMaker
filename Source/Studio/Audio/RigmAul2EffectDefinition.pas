unit RigmAul2EffectDefinition;

// Controllerで使うエフェクター名、配色、GUI項目を一元管理する。

interface

uses
  Vcl.Graphics;

const
  CONTROLLER_EFFECT_COUNT = 20;
  CONTROLLER_MAX_VOLUME_COUNT = 7;

type
  TControllerSelectDefinition = record
    Visible    : Boolean;
    DisplayName: string;
    ItemName   : string;
    Items      : TArray<string>;
  end;

  TControllerVolumeDefinition = record
    DisplayName: string;
    ItemName   : string;
    Minimum    : Double;
    Maximum    : Double;
    Step       : Double;
    Decimals   : Integer;
    UnitText   : string;
  end;

  TControllerEffectDefinition = record
    DisplayName    : string;
    LampCaption    : string;
    UseItemName    : string;
    ThemeColor     : TColor;
    BackgroundColor: TColor;
    VolumeColor    : TColor;
    IndicatorColor : TColor;
    TextColor      : TColor;
    SelectControl  : TControllerSelectDefinition;
    Volumes        : TArray<TControllerVolumeDefinition>;
  end;

// コンボボックス順のエフェクター定義を返す。
function GetControllerEffectDefinition(Index: Integer;
  out Definition: TControllerEffectDefinition): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils;

type
  TControllerEffectColors = record
    PedalColor    : TColor;
    VolumeColor   : TColor;
    IndicatorColor: TColor;
    TextColor     : TColor;
  end;

const
  // 筐体、ボリュームカード、ノブ位置線、文字の色。TColorは$00BBGGRR形式。
  EFFECT_COLORS: array[0..CONTROLLER_EFFECT_COUNT - 1] of TControllerEffectColors = (
    (PedalColor: $00BED2D8; VolumeColor: $001C1C1C; IndicatorColor: $00DDEBF0; TextColor: $00F2F2F2), // Delay
    (PedalColor: $00C5CED2; VolumeColor: $00D1E1E9; IndicatorColor: $00DCE4E8; TextColor: $00171717), // EQ
    (PedalColor: $00A85C07; VolumeColor: $00EEEEEE; IndicatorColor: $00D8A15F; TextColor: $00171717), // Compressor
    (PedalColor: $004F00C0; VolumeColor: $00191717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Voice Drive
    (PedalColor: $002173F3; VolumeColor: $00171717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Distortion
    (PedalColor: $00D0CDC9; VolumeColor: $00EDEDED; IndicatorColor: $00E7E5E2; TextColor: $00171717), // Noise
    (PedalColor: $0048429E; VolumeColor: $00252525; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Bit Crusher
    (PedalColor: $00888B19; VolumeColor: $00171717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Tremble
    (PedalColor: $0095B8C5; VolumeColor: $00202020; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Wobble
    (PedalColor: $00A97628; VolumeColor: $00171717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Pitch
    (PedalColor: $00A53769; VolumeColor: $00171717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Ring Mod
    (PedalColor: $00246955; VolumeColor: $00171717; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Muffle
    (PedalColor: $00A85407; VolumeColor: $001C1816; IndicatorColor: $00F2F2F2; TextColor: $00F2F2F2), // Whisper
    (PedalColor: $003E8728; VolumeColor: $00EEEEEE; IndicatorColor: $00387828; TextColor: $00171717), // Auto Gain
    (PedalColor: $00D7B994; VolumeColor: $00E5DCE1; IndicatorColor: $00EEDABF; TextColor: $00171717), // Noise Gate
    (PedalColor: $00627D2A; VolumeColor: $00171717; IndicatorColor: $00C8F0DC; TextColor: $00F2F2F2), // Ghost
    (PedalColor: $00D0AE9B; VolumeColor: $00EAEAEA; IndicatorColor: $00EAD4C8; TextColor: $00171717), // Chorus
    (PedalColor: $00913643; VolumeColor: $001F1D1D; IndicatorColor: $00E4D6F2; TextColor: $00F2F2F2), // Reverb
    (PedalColor: $00198491; VolumeColor: $001C1C1C; IndicatorColor: $0061DCEC; TextColor: $00F2F2F2), // Output
    (PedalColor: $00E1C408; VolumeColor: $00F2F2F2; IndicatorColor: $00ECDC61; TextColor: $00171717)  // Limiter
  );
  THEME_MAX_BRIGHTNESS      = 96;
  BACKGROUND_MAX_BRIGHTNESS = 112;
  DARK_BASE_RED            = 24;
  DARK_BASE_GREEN          = 26;
  DARK_BASE_BLUE           = 29;

function ToneDownPedalColor(Color: TColor; MaxBrightness: Integer): TColor;
var
  BaseBrightness: Integer;
  Brightness: Integer;
  SourceWeight: Integer;
begin
  Color := ColorToRGB(Color);
  Brightness := (GetRValue(Color) * 299 + GetGValue(Color) * 587 +
    GetBValue(Color) * 114) div 1000;
  if Brightness <= MaxBrightness then
    Exit(Color);

  BaseBrightness := (DARK_BASE_RED * 299 + DARK_BASE_GREEN * 587 +
    DARK_BASE_BLUE * 114) div 1000;
  SourceWeight := (MaxBrightness - BaseBrightness) * 100 div
    (Brightness - BaseBrightness);
  Result := RGB(
    (GetRValue(Color) * SourceWeight + DARK_BASE_RED * (100 - SourceWeight)) div 100,
    (GetGValue(Color) * SourceWeight + DARK_BASE_GREEN * (100 - SourceWeight)) div 100,
    (GetBValue(Color) * SourceWeight + DARK_BASE_BLUE * (100 - SourceWeight)) div 100);
end;

procedure SetEffectBase(out Definition: TControllerEffectDefinition;
  const DisplayName, LampCaption, UseItemName: string; EffectIndex: Integer);
begin
  Definition := Default(TControllerEffectDefinition);
  Definition.DisplayName := DisplayName;
  Definition.LampCaption := LampCaption;
  Definition.UseItemName := UseItemName;
  Definition.ThemeColor := ToneDownPedalColor(
    EFFECT_COLORS[EffectIndex].PedalColor, THEME_MAX_BRIGHTNESS);
  Definition.BackgroundColor := ToneDownPedalColor(
    EFFECT_COLORS[EffectIndex].PedalColor, BACKGROUND_MAX_BRIGHTNESS);
  Definition.VolumeColor := EFFECT_COLORS[EffectIndex].VolumeColor;
  Definition.IndicatorColor := EFFECT_COLORS[EffectIndex].IndicatorColor;
  Definition.TextColor := EFFECT_COLORS[EffectIndex].TextColor;
end;

procedure SetSelect(var Definition: TControllerEffectDefinition;
  const DisplayName, ItemName: string; const Items: array of string);
var
  Index: Integer;
begin
  Definition.SelectControl.Visible := True;
  Definition.SelectControl.DisplayName := DisplayName;
  Definition.SelectControl.ItemName := ItemName;
  SetLength(Definition.SelectControl.Items, Length(Items));
  for Index := 0 to High(Items) do
    Definition.SelectControl.Items[Index] := Items[Index];
end;

procedure SetVolume(var Definition: TControllerEffectDefinition; Index: Integer;
  const DisplayName, ItemName: string; Minimum, Maximum, Step: Double;
  Decimals: Integer; const UnitText: string = '');
begin
  if (Index < 0) or (Index >= CONTROLLER_MAX_VOLUME_COUNT) then
    raise ERangeError.Create('Controller volume definition index is out of range');
  if Length(Definition.Volumes) <= Index then
    SetLength(Definition.Volumes, Index + 1);

  Definition.Volumes[Index].DisplayName := DisplayName;
  Definition.Volumes[Index].ItemName := ItemName;
  Definition.Volumes[Index].Minimum := Minimum;
  Definition.Volumes[Index].Maximum := Maximum;
  Definition.Volumes[Index].Step := Step;
  Definition.Volumes[Index].Decimals := Decimals;
  Definition.Volumes[Index].UnitText := UnitText;
end;

procedure BuildDelayDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Delay', '遅延音を加える', 'Dly: Use',
    0);
  SetSelect(Definition, 'Stereo Mode', 'Dly: Stereo Mode',
    ['Normal', 'Ping-Pong']);
  SetVolume(Definition, 0, 'Time', 'Dly: Time(ms)', 1, 1000, 1, 0, 'ms');
  SetVolume(Definition, 1, 'Dry', 'Dly: Dry', 0, 2, 0.01, 2);
  SetVolume(Definition, 2, 'Wet', 'Dly: Wet', 0, 2, 0.01, 2);
  SetVolume(Definition, 3, 'Feedback', 'Dly: Feedback', 0, 0.95, 0.01, 2);
end;

procedure BuildEqDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'EQ', '音域を整える', 'EQ: Use',
    1);
  SetSelect(Definition, 'Mode', 'EQ: Mode',
    ['Low Cut', 'High Cut', 'Band Pass']);
  SetVolume(Definition, 0, 'Low Cut', 'EQ: LowCut(Hz)', 20, 5000, 1, 0, 'Hz');
  SetVolume(Definition, 1, 'High Cut', 'EQ: HighCut(Hz)', 500, 20000, 1, 0, 'Hz');
  SetVolume(Definition, 2, 'Mix', 'EQ: Mix', 0, 1, 0.01, 2);
end;

procedure BuildCompressorDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Compressor', '音量差を整える', 'Comp: Use',
    2);
  SetVolume(Definition, 0, 'Threshold', 'Comp: Threshold(dB)', -60, 0, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Ratio', 'Comp: Ratio', 1, 20, 0.1, 1);
  SetVolume(Definition, 2, 'Attack', 'Comp: Attack(ms)', 0.1, 200, 0.1, 1, 'ms');
  SetVolume(Definition, 3, 'Release', 'Comp: Release(ms)', 5, 1000, 1, 0, 'ms');
  SetVolume(Definition, 4, 'Makeup', 'Comp: Makeup(dB)', -24, 24, 0.1, 1, 'dB');
  SetVolume(Definition, 5, 'Mix', 'Comp: Mix', 0, 1, 0.01, 2);
end;

procedure BuildVoiceDriveDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Voice Drive', '声に厚みを加える', 'Drive: Use',
    3);
  SetVolume(Definition, 0, 'Drive', 'Drive: Drive(dB)', 0, 30, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Body', 'Drive: Body', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Level', 'Drive: Level(dB)', -24, 6, 0.1, 1, 'dB');
  SetVolume(Definition, 3, 'Mix', 'Drive: Mix', 0, 1, 0.01, 2);
end;

procedure BuildDistortionDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Distortion', '音を歪ませる', 'Dist: Use', 4);
  SetSelect(Definition, 'Mode', 'Dist: Mode', ['Soft Clip', 'Hard Clip']);
  SetVolume(Definition, 0, 'Drive', 'Dist: Drive(dB)', 0, 36, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Tone', 'Dist: Tone', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Level', 'Dist: Level(dB)', -24, 12, 0.1, 1, 'dB');
  SetVolume(Definition, 3, 'Mix', 'Dist: Mix', 0, 1, 0.01, 2);
end;

procedure BuildNoiseDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Noise', 'ノイズを加える', 'Noise: Use', 5);
  SetSelect(Definition, 'Mode', 'Noise: Mode', ['White', 'Crackle']);
  SetVolume(Definition, 0, 'Level', 'Noise: Level(dB)', -80, -6, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Mix', 'Noise: Mix', 0, 1, 0.01, 2);
end;

procedure BuildBitCrusherDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Bit Crusher', '音を粗くする', 'Crush: Use', 6);
  SetVolume(Definition, 0, 'Bit Depth', 'Crush: BitDepth', 2, 16, 1, 0, 'bit');
  SetVolume(Definition, 1, 'Sample Hold', 'Crush: SampleHold', 1, 64, 1, 0);
  SetVolume(Definition, 2, 'Mix', 'Crush: Mix', 0, 1, 0.01, 2);
end;

procedure BuildTrembleDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Tremble', '音量を揺らす', 'Trem: Use', 7);
  SetVolume(Definition, 0, 'Rate', 'Trem: Rate(Hz)', 0.1, 30, 0.1, 1, 'Hz');
  SetVolume(Definition, 1, 'Depth', 'Trem: Depth', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Mix', 'Trem: Mix', 0, 1, 0.01, 2);
end;

procedure BuildWobbleDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Wobble', '音程を揺らす', 'Wob: Use', 8);
  SetVolume(Definition, 0, 'Delay', 'Wob: Delay(ms)', 1, 120, 0.1, 1, 'ms');
  SetVolume(Definition, 1, 'Depth', 'Wob: Depth(ms)', 0, 80, 0.1, 1, 'ms');
  SetVolume(Definition, 2, 'Rate', 'Wob: Rate(Hz)', 0.05, 8, 0.01, 2, 'Hz');
  SetVolume(Definition, 3, 'Mix', 'Wob: Mix', 0, 1, 0.01, 2);
end;

procedure BuildPitchDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Pitch', '音程を変える', 'Pitch: Use', 9);
  SetSelect(Definition, 'Mode', 'Pitch: Mode',
    ['Natural', 'Pitch Only', 'Formant Only', 'Step']);
  SetVolume(Definition, 0, 'Semitone', 'Pitch: Semitone', -12, 12, 0.1, 1, 'semi');
  SetVolume(Definition, 1, 'Window', 'Pitch: Window(ms)', 20, 120, 1, 0, 'ms');
  SetVolume(Definition, 2, 'Formant', 'Pitch: Formant', -12, 12, 0.1, 1, 'semi');
  SetVolume(Definition, 3, 'Amount', 'Pitch: Amount', 0, 1, 0.01, 2);
  SetVolume(Definition, 4, 'Step', 'Pitch: Step(semi)', 0, 12, 0.1, 1, 'semi');
  SetVolume(Definition, 5, 'Rate', 'Pitch: Rate(Hz)', 0.25, 20, 0.25, 2, 'Hz');
  SetVolume(Definition, 6, 'Mix', 'Pitch: Mix', 0, 1, 0.01, 2);
end;

procedure BuildRingModDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Ring Mod', '金属的な響きを加える', 'Ring: Use', 10);
  SetVolume(Definition, 0, 'Frequency', 'Ring: Frequency(Hz)', 1, 2000, 1, 0, 'Hz');
  SetVolume(Definition, 1, 'Depth', 'Ring: Depth', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Mix', 'Ring: Mix', 0, 1, 0.01, 2);
end;

procedure BuildMuffleDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Muffle', '音をこもらせる', 'Muffle: Use', 11);
  SetVolume(Definition, 0, 'Cutoff', 'Muffle: Cutoff(Hz)', 80, 8000, 10, 0, 'Hz');
  SetVolume(Definition, 1, 'Amount', 'Muffle: Amount', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Mix', 'Muffle: Mix', 0, 1, 0.01, 2);
end;

procedure BuildWhisperDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Whisper', 'ささやき声にする', 'Breath: Use', 12);
  SetVolume(Definition, 0, 'Level', 'Breath: Level(dB)', -48, 0, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Tone', 'Breath: Tone', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Mix', 'Breath: Mix', 0, 1, 0.01, 2);
end;

procedure BuildAutoGainDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Auto Gain', '音量を自動調整する', 'AGain: Use', 13);
  SetVolume(Definition, 0, 'Target', 'AGain: Target(dB)', -36, -3, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Speed', 'AGain: Speed(ms)', 20, 2000, 10, 0, 'ms');
  SetVolume(Definition, 2, 'Max Gain', 'AGain: MaxGain(dB)', 0, 24, 0.1, 1, 'dB');
  SetVolume(Definition, 3, 'Mix', 'AGain: Mix', 0, 1, 0.01, 2);
end;

procedure BuildNoiseGateDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Noise Gate', '小さな音を抑える', 'Gate: Use', 14);
  SetVolume(Definition, 0, 'Threshold', 'Gate: Threshold(dB)', -80, 0, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Attack', 'Gate: Attack(ms)', 1, 200, 1, 0, 'ms');
  SetVolume(Definition, 2, 'Release', 'Gate: Release(ms)', 10, 1000, 10, 0, 'ms');
  SetVolume(Definition, 3, 'Floor', 'Gate: Floor(dB)', -80, -6, 1, 0, 'dB');
end;

procedure BuildGhostDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Ghost', '残響を重ねる', 'Ghost: Use', 15);
  SetVolume(Definition, 0, 'Size', 'Ghost: Size(ms)', 80, 1500, 10, 0, 'ms');
  SetVolume(Definition, 1, 'Feedback', 'Ghost: Feedback', 0, 0.95, 0.01, 2);
  SetVolume(Definition, 2, 'Wet', 'Ghost: Wet', 0, 1, 0.01, 2);
  SetVolume(Definition, 3, 'Mix', 'Ghost: Mix', 0, 1, 0.01, 2);
end;

procedure BuildChorusDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Chorus', '音に広がりを加える', 'Cho: Use', 16);
  SetSelect(Definition, 'Stereo Mode', 'Cho: Stereo Mode', ['Normal', 'Wide']);
  SetVolume(Definition, 0, 'Delay', 'Cho: Delay(ms)', 1, 50, 0.1, 1, 'ms');
  SetVolume(Definition, 1, 'Depth', 'Cho: Depth(ms)', 0, 20, 0.1, 1, 'ms');
  SetVolume(Definition, 2, 'Rate', 'Cho: Rate(Hz)', 0.01, 10, 0.01, 2, 'Hz');
  SetVolume(Definition, 3, 'Mix', 'Cho: Mix', 0, 1, 0.01, 2);
end;

procedure BuildReverbDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Reverb', '残響を加える', 'Rev: Use', 17);
  SetSelect(Definition, 'Type', 'Rev: Type', ['Room', 'Hall', 'Plate']);
  SetVolume(Definition, 0, 'Room Size', 'Rev: RoomSize', 0, 1, 0.01, 2);
  SetVolume(Definition, 1, 'Damping', 'Rev: Damping', 0, 1, 0.01, 2);
  SetVolume(Definition, 2, 'Dry', 'Rev: Dry', 0, 2, 0.01, 2);
  SetVolume(Definition, 3, 'Wet', 'Rev: Wet', 0, 2, 0.01, 2);
end;

procedure BuildOutputDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Output', '出力音量を調整する', 'Out: Use', 18);
  SetVolume(Definition, 0, 'Gain', 'Out: Gain(dB)', -24, 24, 0.1, 1, 'dB');
end;

procedure BuildLimiterDefinition(out Definition: TControllerEffectDefinition);
begin
  SetEffectBase(Definition, 'Limiter', '音割れを防ぐ', 'Lim: Use', 19);
  SetVolume(Definition, 0, 'Ceiling', 'Lim: Ceiling(dB)', -24, 0, 0.1, 1, 'dB');
  SetVolume(Definition, 1, 'Release', 'Lim: Release(ms)', 1, 1000, 1, 0, 'ms');
  SetVolume(Definition, 2, 'Mix', 'Lim: Mix', 0, 1, 0.01, 2);
end;

function GetControllerEffectDefinition(Index: Integer;
  out Definition: TControllerEffectDefinition): Boolean;
begin
  Result := (Index >= 0) and (Index < CONTROLLER_EFFECT_COUNT);
  if not Result then
  begin
    Definition := Default(TControllerEffectDefinition);
    Exit;
  end;

  case Index of
    0: BuildDelayDefinition(Definition);
    1: BuildEqDefinition(Definition);
    2: BuildCompressorDefinition(Definition);
    3: BuildVoiceDriveDefinition(Definition);
    4: BuildDistortionDefinition(Definition);
    5: BuildNoiseDefinition(Definition);
    6: BuildBitCrusherDefinition(Definition);
    7: BuildTrembleDefinition(Definition);
    8: BuildWobbleDefinition(Definition);
    9: BuildPitchDefinition(Definition);
    10: BuildRingModDefinition(Definition);
    11: BuildMuffleDefinition(Definition);
    12: BuildWhisperDefinition(Definition);
    13: BuildAutoGainDefinition(Definition);
    14: BuildNoiseGateDefinition(Definition);
    15: BuildGhostDefinition(Definition);
    16: BuildChorusDefinition(Definition);
    17: BuildReverbDefinition(Definition);
    18: BuildOutputDefinition(Definition);
    19: BuildLimiterDefinition(Definition);
  else
    Definition := Default(TControllerEffectDefinition);
  end;
end;

end.
