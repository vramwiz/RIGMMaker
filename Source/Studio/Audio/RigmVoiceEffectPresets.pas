unit RigmVoiceEffectPresets;
// Aul2AudioFilterの組込みプリセットを、ホストに依存しない行別JSON設定へ変換する。
interface
uses System.JSON;
const VOICE_EFFECT_PRESET_COUNT = 18; // 「なし」を含む選択候補の数。
// Indexはコンボボックスの順序。範囲外は例外。戻り値JSONの所有権は呼出側へ渡す。
function VoiceEffectPresetName(Index: Integer): string;
function CreateVoiceEffectPreset(Index: Integer): TJSONObject;
implementation
uses System.SysUtils, RigmAul2EffectDefinition, RigmVoiceEffectSettings;
const
  PRESET_NAMES: array[0..VOICE_EFFECT_PRESET_COUNT-1] of string = (
    'なし',
    'エコー',
    '反響',
    'ホール',
    '空間',
    'ナレーション',
    '電話',
    '無線',
    '拡声器',
    '劣化',
    '男性',
    '女性',
    'ロボ',
    '恐怖',
    '叫び',
    '水中',
    '壁越し',
    '夢/回想');
procedure CheckIndex(Index: Integer);
begin
  if (Index<0) or (Index>=VOICE_EFFECT_PRESET_COUNT) then
    raise EArgumentOutOfRangeException.Create('Invalid voice effect preset');
end;
function VoiceEffectPresetName(Index: Integer): string;
begin CheckIndex(Index); Result := PRESET_NAMES[Index]; end;
function CreateVoiceEffectPreset(Index: Integer): TJSONObject;
  procedure SetValue(const Name: string; Value: Double);
  begin Result.RemovePair(Name).Free; Result.AddPair(Name,TJSONNumber.Create(Value)); end;
begin
  CheckIndex(Index); Result := TJSONObject.Create;
  try
    // 全100項目を既定値から作り、以前のプリセットや手動調整の残りを除く。
    for var I := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
      var D: TControllerEffectDefinition; GetControllerEffectDefinition(I,D);
      SetValue(D.UseItemName,VoiceEffectValue(nil,D.UseItemName));
      if D.SelectControl.Visible then SetValue(D.SelectControl.ItemName,VoiceEffectValue(nil,D.SelectControl.ItemName));
      for var V in D.Volumes do SetValue(V.ItemName,VoiceEffectValue(nil,V.ItemName));
    end;
    // 出所: D:\DelphiProg\test\Aul2AudioFilter\Source\Aul2AudioFilterPluginPreset.pas
    // ApplyPresetToObjectItemsの数値と、AddPresetItemsの公開候補を保持する。
    case Index of
      1: begin // エコー
        SetValue('Dly: Use',1);
        SetValue('Dly: Time(ms)',250);
        SetValue('Dly: Wet',0.55);
        SetValue('Dly: Feedback',0.35);
      end;
      2: begin // 反響
        SetValue('Dly: Use',1);
        SetValue('Dly: Stereo Mode',1);
        SetValue('Dly: Time(ms)',320);
        SetValue('Dly: Wet',0.55);
        SetValue('Dly: Feedback',0.30);
      end;
      3: begin // ホール
        SetValue('Rev: Use',1);
        SetValue('Rev: Type',1);
        SetValue('Rev: RoomSize',0.90);
        SetValue('Rev: Damping',0.20);
        SetValue('Rev: Dry',0.85);
        SetValue('Rev: Wet',0.95);
      end;
      4: begin // 空間
        SetValue('Cho: Use',1);
        SetValue('Cho: Stereo Mode',1);
        SetValue('Cho: Delay(ms)',18);
        SetValue('Cho: Depth(ms)',7);
        SetValue('Cho: Rate(Hz)',0.45);
        SetValue('Cho: Mix',0.45);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',4);
        SetValue('Lim: Use',1);
      end;
      5: begin // ナレーション
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',140);
        SetValue('EQ: HighCut(Hz)',8500);
        SetValue('Comp: Use',1);
        SetValue('Comp: Threshold(dB)',-26);
        SetValue('Comp: Ratio',4.5);
        SetValue('Comp: Attack(ms)',3);
        SetValue('Comp: Release(ms)',90);
        SetValue('Comp: Makeup(dB)',5);
        SetValue('Drive: Use',1);
        SetValue('Drive: Drive(dB)',7);
        SetValue('Drive: Body',0.35);
        SetValue('Drive: Level(dB)',-2);
        SetValue('Drive: Mix',0.40);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',3);
        SetValue('Lim: Use',1);
      end;
      6: begin // 電話
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',500);
        SetValue('EQ: HighCut(Hz)',2600);
        SetValue('Dist: Use',1);
        SetValue('Dist: Drive(dB)',8);
        SetValue('Dist: Tone',0.80);
        SetValue('Dist: Level(dB)',-3);
        SetValue('Dist: Mix',0.50);
        SetValue('Crush: Use',1);
        SetValue('Crush: BitDepth',9);
        SetValue('Crush: SampleHold',1);
        SetValue('Crush: Mix',0.50);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',4);
        SetValue('Lim: Use',1);
      end;
      7: begin // 無線
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',700);
        SetValue('EQ: HighCut(Hz)',2300);
        SetValue('Dist: Use',1);
        SetValue('Dist: Drive(dB)',14);
        SetValue('Dist: Tone',1);
        SetValue('Dist: Level(dB)',-5);
        SetValue('Dist: Mix',0.75);
        SetValue('Noise: Use',0);
        SetValue('Noise: Mode',0);
        SetValue('Noise: Level(dB)',-36);
        SetValue('Noise: Mix',0);
        SetValue('Crush: Use',1);
        SetValue('Crush: BitDepth',7);
        SetValue('Crush: SampleHold',3);
        SetValue('Crush: Mix',0.70);
        SetValue('Lim: Use',1);
        SetValue('Lim: Release(ms)',40);
      end;
      8: begin // 拡声器
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',550);
        SetValue('EQ: HighCut(Hz)',4800);
        SetValue('Comp: Use',1);
        SetValue('Comp: Threshold(dB)',-28);
        SetValue('Comp: Ratio',6);
        SetValue('Comp: Attack(ms)',2);
        SetValue('Comp: Release(ms)',80);
        SetValue('Comp: Makeup(dB)',6);
        SetValue('Drive: Use',1);
        SetValue('Drive: Drive(dB)',12);
        SetValue('Drive: Body',0.55);
        SetValue('Drive: Level(dB)',-3);
        SetValue('Drive: Mix',0.65);
        SetValue('Dist: Use',1);
        SetValue('Dist: Mode',1);
        SetValue('Dist: Drive(dB)',18);
        SetValue('Dist: Level(dB)',-7);
        SetValue('Dist: Mix',0.85);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',-2.2);
        SetValue('Lim: Use',1);
        SetValue('Lim: Release(ms)',35);
      end;
      9: begin // 劣化
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',300);
        SetValue('EQ: HighCut(Hz)',4200);
        SetValue('Dist: Use',1);
        SetValue('Dist: Drive(dB)',8);
        SetValue('Dist: Tone',0.85);
        SetValue('Dist: Level(dB)',-4);
        SetValue('Dist: Mix',0.45);
        SetValue('Noise: Use',0);
        SetValue('Noise: Level(dB)',-45);
        SetValue('Noise: Mix',0);
        SetValue('Crush: Use',1);
        SetValue('Crush: BitDepth',5);
        SetValue('Crush: SampleHold',10);
        SetValue('Crush: Mix',0.85);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',3);
        SetValue('Lim: Use',1);
      end;
      10: begin // 男性
        SetValue('Pitch: Use',1);
        SetValue('Pitch: Mode',0);
        SetValue('Pitch: Semitone',-2);
        SetValue('Pitch: Window(ms)',110);
        SetValue('Pitch: Formant',-2.5);
        SetValue('Pitch: Amount',0.6);
        SetValue('Pitch: Mix',0.60);
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',90);
        SetValue('EQ: HighCut(Hz)',7600);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',5);
        SetValue('Lim: Use',1);
      end;
      11: begin // 女性
        SetValue('Pitch: Use',1);
        SetValue('Pitch: Mode',0);
        SetValue('Pitch: Semitone',2);
        SetValue('Pitch: Window(ms)',100);
        SetValue('Pitch: Formant',2.5);
        SetValue('Pitch: Amount',0.6);
        SetValue('Pitch: Mix',0.60);
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',150);
        SetValue('EQ: HighCut(Hz)',9000);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',5);
        SetValue('Lim: Use',1);
      end;
      12: begin // ロボ
        SetValue('Ring: Use',1);
        SetValue('Ring: Frequency(Hz)',95);
        SetValue('Ring: Depth',1);
        SetValue('Ring: Mix',0.90);
        SetValue('Pitch: Use',1);
        SetValue('Pitch: Mode',3);
        SetValue('Pitch: Window(ms)',90);
        SetValue('Pitch: Step(semi)',3);
        SetValue('Pitch: Rate(Hz)',7);
        SetValue('Pitch: Mix',0.45);
        SetValue('Crush: Use',1);
        SetValue('Crush: BitDepth',6);
        SetValue('Crush: SampleHold',3);
        SetValue('Crush: Mix',0.65);
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',220);
        SetValue('EQ: HighCut(Hz)',4800);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',10);
        SetValue('Lim: Use',1);
        SetValue('Lim: Release(ms)',45);
      end;
      13: begin // 恐怖
        SetValue('Trem: Use',1);
        SetValue('Trem: Rate(Hz)',11);
        SetValue('Trem: Depth',0.75);
        SetValue('Trem: Mix',1);
        SetValue('Wob: Use',1);
        SetValue('Wob: Delay(ms)',35);
        SetValue('Wob: Depth(ms)',28);
        SetValue('Wob: Rate(Hz)',0.70);
        SetValue('Wob: Mix',0.75);
        SetValue('Pitch: Use',1);
        SetValue('Pitch: Mode',0);
        SetValue('Pitch: Semitone',-1.5);
        SetValue('Pitch: Window(ms)',100);
        SetValue('Pitch: Formant',-2);
        SetValue('Pitch: Amount',0.5);
        SetValue('Pitch: Mix',0.55);
        SetValue('Muffle: Use',1);
        SetValue('Muffle: Cutoff(Hz)',2600);
        SetValue('Muffle: Amount',0.45);
        SetValue('Muffle: Mix',0.60);
        SetValue('Ghost: Use',1);
        SetValue('Ghost: Size(ms)',650);
        SetValue('Ghost: Feedback',0.55);
        SetValue('Ghost: Wet',0.45);
        SetValue('Ghost: Mix',1);
        SetValue('Rev: Use',1);
        SetValue('Rev: Type',1);
        SetValue('Rev: RoomSize',0.70);
        SetValue('Rev: Damping',0.40);
        SetValue('Rev: Wet',0.45);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',3);
        SetValue('Lim: Use',1);
        SetValue('Lim: Release(ms)',60);
      end;
      14: begin // 叫び
        SetValue('Comp: Use',1);
        SetValue('Comp: Threshold(dB)',-30);
        SetValue('Comp: Ratio',8);
        SetValue('Comp: Attack(ms)',1.5);
        SetValue('Comp: Release(ms)',70);
        SetValue('Comp: Makeup(dB)',7);
        SetValue('Drive: Use',1);
        SetValue('Drive: Drive(dB)',18);
        SetValue('Drive: Body',0.65);
        SetValue('Drive: Level(dB)',-4);
        SetValue('Drive: Mix',0.85);
        SetValue('Dist: Use',1);
        SetValue('Dist: Mode',1);
        SetValue('Dist: Drive(dB)',10);
        SetValue('Dist: Tone',1);
        SetValue('Dist: Level(dB)',-8);
        SetValue('Dist: Mix',0.35);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',5);
        SetValue('Lim: Use',1);
        SetValue('Lim: Release(ms)',25);
      end;
      15: begin // 水中
        SetValue('Muffle: Use',1);
        SetValue('Muffle: Cutoff(Hz)',850);
        SetValue('Muffle: Amount',0.95);
        SetValue('Wob: Use',1);
        SetValue('Wob: Delay(ms)',35);
        SetValue('Wob: Depth(ms)',22);
        SetValue('Wob: Rate(Hz)',0.75);
        SetValue('Wob: Mix',0.55);
        SetValue('Cho: Use',1);
        SetValue('Cho: Stereo Mode',1);
        SetValue('Cho: Delay(ms)',22);
        SetValue('Cho: Depth(ms)',9);
        SetValue('Cho: Rate(Hz)',0.35);
        SetValue('Cho: Mix',0.35);
        SetValue('Rev: Use',1);
        SetValue('Rev: RoomSize',0.45);
        SetValue('Rev: Damping',0.75);
        SetValue('Rev: Wet',0.25);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',14);
        SetValue('Lim: Use',1);
      end;
      16: begin // 壁越し
        SetValue('Muffle: Use',1);
        SetValue('Muffle: Cutoff(Hz)',650);
        SetValue('Muffle: Amount',1);
        SetValue('EQ: Use',1);
        SetValue('EQ: LowCut(Hz)',120);
        SetValue('EQ: HighCut(Hz)',1800);
        SetValue('Rev: Use',1);
        SetValue('Rev: RoomSize',0.25);
        SetValue('Rev: Damping',0.7);
        SetValue('Rev: Wet',0.12);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',6);
        SetValue('Lim: Use',1);
      end;
      17: begin // 夢/回想
        SetValue('Wob: Use',1);
        SetValue('Wob: Delay(ms)',34);
        SetValue('Wob: Depth(ms)',24);
        SetValue('Wob: Rate(Hz)',0.38);
        SetValue('Wob: Mix',0.62);
        SetValue('Cho: Use',1);
        SetValue('Cho: Stereo Mode',1);
        SetValue('Cho: Delay(ms)',28);
        SetValue('Cho: Depth(ms)',13);
        SetValue('Cho: Rate(Hz)',0.22);
        SetValue('Cho: Mix',0.58);
        SetValue('Ghost: Use',1);
        SetValue('Ghost: Size(ms)',760);
        SetValue('Ghost: Feedback',0.52);
        SetValue('Ghost: Wet',0.42);
        SetValue('Ghost: Mix',1);
        SetValue('Rev: Use',1);
        SetValue('Rev: Type',1);
        SetValue('Rev: RoomSize',0.72);
        SetValue('Rev: Damping',0.42);
        SetValue('Rev: Wet',0.48);
        SetValue('Out: Use',1);
        SetValue('Out: Gain(dB)',6);
        SetValue('Lim: Use',1);
      end;
    end;
    ValidateVoiceEffectSettings(Result);
  except Result.Free; raise; end;
end;
end.