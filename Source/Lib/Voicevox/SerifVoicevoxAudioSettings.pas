// キャラUUIDと感情のstyle IDごとに、固定規定値と異なるVOICEVOX音声設定だけを保存・復元する。
unit SerifVoicevoxAudioSettings;

interface

uses
  System.Generics.Collections;

type
  TSerifVoicevoxAudioValues = record
    // VOICEVOX audio_queryのspeedScaleへ渡す話速倍率。1.0が規定値。
    SpeedScale: Double;
    // VOICEVOX audio_queryのpitchScaleへ渡す音高補正値。0.0が規定値。
    PitchScale: Double;
    // VOICEVOX audio_queryのintonationScaleへ渡す抑揚倍率。1.0が規定値。
    IntonationScale: Double;
    // VOICEVOX audio_queryのvolumeScaleへ渡す音量倍率。1.0が規定値。
    VolumeScale: Double;
    // VOICEVOX audio_queryのprePhonemeLengthへ渡す発話前の無音秒数。
    PrePhonemeLength: Double;
    // VOICEVOX audio_queryのpostPhonemeLengthへ渡す発話後の無音秒数。
    PostPhonemeLength: Double;
    // 未設定のキャラ＋感情へ適用する固定規定値一式を返す。
    class function Defaults: TSerifVoicevoxAudioValues; static;
    // 全項目が固定規定値と等しく、INIへ保存する必要がない場合にTrueを返す。
    function IsDefault: Boolean;
  end;

  // 現在のAviUtl2プロジェクトに属する変更値をメモリ上で管理し、VOICEVOX.iniへ保存する。
  TSerifVoicevoxAudioSettings = class
  private const
    FILE_NAME = 'VOICEVOX.ini';
    SECTION_PREFIX = 'Style.';
  private
    FDirty: Boolean;
    FFileName: string;
    FItems: TDictionary<string, TSerifVoicevoxAudioValues>;
    class function MakeKey(const SpeakerUUID: string;
      const StyleId: Integer): string; static;
    procedure Load;
  public
    // プロジェクト未選択の空の設定ストアを生成する。
    constructor Create;
    // 未保存の変更を保存してから設定ストアを破棄する。
    destructor Destroy; override;
    // 指定したキャラ＋感情の値を返す。変更値がない組み合わせには固定規定値を返す。
    function GetValues(const SpeakerUUID: string; const StyleId: Integer): TSerifVoicevoxAudioValues;
    // 変更中の旧プロジェクトを保存してから、指定フォルダの設定へ切り替える。空文字は選択解除を表す。
    procedure OpenProject(const ProjectFolder: string);
    // 変更がある場合だけINIを更新する。保存失敗時は変更状態を保持し、次回の保存で再試行する。
    procedure Save;
    // 指定したキャラ＋感情の値を更新する。固定規定値なら保存対象から取り除く。
    procedure SetValues(const SpeakerUUID: string; const StyleId: Integer;
      const Values: TSerifVoicevoxAudioValues);
  end;

implementation

uses
  System.Classes, System.IniFiles, System.IOUtils, System.Math,
  System.SysUtils;

class function TSerifVoicevoxAudioValues.Defaults: TSerifVoicevoxAudioValues;
begin
  Result.SpeedScale := 1.0;
  Result.PitchScale := 0.0;
  Result.IntonationScale := 1.0;
  Result.VolumeScale := 1.0;
  Result.PrePhonemeLength := 0.1;
  Result.PostPhonemeLength := 0.1;
end;

function TSerifVoicevoxAudioValues.IsDefault: Boolean;
var
  DefaultValues: TSerifVoicevoxAudioValues;
begin
  DefaultValues := Defaults;
  Result := SameValue(SpeedScale, DefaultValues.SpeedScale) and
    SameValue(PitchScale, DefaultValues.PitchScale) and
    SameValue(IntonationScale, DefaultValues.IntonationScale) and
    SameValue(VolumeScale, DefaultValues.VolumeScale) and
    SameValue(PrePhonemeLength, DefaultValues.PrePhonemeLength) and
    SameValue(PostPhonemeLength, DefaultValues.PostPhonemeLength);
end;

constructor TSerifVoicevoxAudioSettings.Create;
begin
  inherited;
  FItems := TDictionary<string, TSerifVoicevoxAudioValues>.Create;
end;

destructor TSerifVoicevoxAudioSettings.Destroy;
begin
  Save;
  FItems.Free;
  inherited;
end;

function TSerifVoicevoxAudioSettings.GetValues(const SpeakerUUID: string;
  const StyleId: Integer): TSerifVoicevoxAudioValues;
begin
  if not FItems.TryGetValue(MakeKey(SpeakerUUID, StyleId), Result) then
    Result := TSerifVoicevoxAudioValues.Defaults;
end;

procedure TSerifVoicevoxAudioSettings.Load;
var
  DefaultValues: TSerifVoicevoxAudioValues;
  Ini: TMemIniFile;
  Section: string;
  Sections: TStringList;
  SeparatorPos: Integer;
  SpeakerUUID: string;
  StyleId: Integer;
  Values: TSerifVoicevoxAudioValues;
begin
  FItems.Clear;
  FDirty := False;
  if (FFileName = '') or not TFile.Exists(FFileName) then Exit;

  DefaultValues := TSerifVoicevoxAudioValues.Defaults;
  Sections := TStringList.Create;
  Ini := TMemIniFile.Create(FFileName, TEncoding.UTF8);
  try
    Ini.ReadSections(Sections);
    for Section in Sections do
    begin
      if not Section.StartsWith(SECTION_PREFIX, True) then Continue;
      SeparatorPos := LastDelimiter('.', Section);
      if SeparatorPos <= Length(SECTION_PREFIX) then Continue;
      SpeakerUUID := Copy(Section, Length(SECTION_PREFIX) + 1,
        SeparatorPos - Length(SECTION_PREFIX) - 1);
      StyleId := StrToIntDef(Copy(Section, SeparatorPos + 1, MaxInt), -1);
      if (SpeakerUUID = '') or (StyleId < 0) then Continue;

      Values.SpeedScale := Ini.ReadFloat(Section, 'SpeedScale',
        DefaultValues.SpeedScale);
      Values.PitchScale := Ini.ReadFloat(Section, 'PitchScale',
        DefaultValues.PitchScale);
      Values.IntonationScale := Ini.ReadFloat(Section, 'IntonationScale',
        DefaultValues.IntonationScale);
      Values.VolumeScale := Ini.ReadFloat(Section, 'VolumeScale',
        DefaultValues.VolumeScale);
      Values.PrePhonemeLength := Ini.ReadFloat(Section, 'PrePhonemeLength',
        DefaultValues.PrePhonemeLength);
      Values.PostPhonemeLength := Ini.ReadFloat(Section, 'PostPhonemeLength',
        DefaultValues.PostPhonemeLength);
      if not Values.IsDefault then
        FItems.AddOrSetValue(MakeKey(SpeakerUUID, StyleId), Values);
    end;
  finally
    Ini.Free;
    Sections.Free;
  end;
end;

class function TSerifVoicevoxAudioSettings.MakeKey(const SpeakerUUID: string;
  const StyleId: Integer): string;
begin
  Result := LowerCase(Trim(SpeakerUUID)) + '|' + IntToStr(StyleId);
end;

procedure TSerifVoicevoxAudioSettings.OpenProject(
  const ProjectFolder: string);
begin
  Save;
  FItems.Clear;
  FDirty := False;
  FFileName := '';
  if Trim(ProjectFolder) <> '' then
    FFileName := TPath.Combine(ProjectFolder, FILE_NAME);
  Load;
end;

procedure TSerifVoicevoxAudioSettings.Save;
var
  Ini: TMemIniFile;
  Key: string;
  Pair: TPair<string, TSerifVoicevoxAudioValues>;
  Section: string;
  Sections: TStringList;
  SeparatorPos: Integer;
begin
  if not FDirty or (FFileName = '') then Exit;
  try
    if FItems.Count = 0 then
    begin
      if TFile.Exists(FFileName) then TFile.Delete(FFileName);
      FDirty := False;
      Exit;
    end;

    TDirectory.CreateDirectory(TPath.GetDirectoryName(FFileName));
    Sections := TStringList.Create;
    Ini := TMemIniFile.Create(FFileName, TEncoding.UTF8);
    try
      Ini.ReadSections(Sections);
      for Section in Sections do Ini.EraseSection(Section);
      for Pair in FItems do
      begin
        Key := Pair.Key;
        SeparatorPos := LastDelimiter('|', Key);
        if SeparatorPos <= 1 then Continue;
        Section := SECTION_PREFIX + Copy(Key, 1, SeparatorPos - 1) + '.' +
          Copy(Key, SeparatorPos + 1, MaxInt);
        Ini.WriteFloat(Section, 'SpeedScale', Pair.Value.SpeedScale);
        Ini.WriteFloat(Section, 'PitchScale', Pair.Value.PitchScale);
        Ini.WriteFloat(Section, 'IntonationScale',
          Pair.Value.IntonationScale);
        Ini.WriteFloat(Section, 'VolumeScale', Pair.Value.VolumeScale);
        Ini.WriteFloat(Section, 'PrePhonemeLength',
          Pair.Value.PrePhonemeLength);
        Ini.WriteFloat(Section, 'PostPhonemeLength',
          Pair.Value.PostPhonemeLength);
      end;
      Ini.UpdateFile;
      FDirty := False;
    finally
      Ini.Free;
      Sections.Free;
    end;
  except
    // プロジェクト切り替えまたは終了時に再試行できるよう、変更状態は解除しない。
  end;
end;

procedure TSerifVoicevoxAudioSettings.SetValues(const SpeakerUUID: string;
  const StyleId: Integer; const Values: TSerifVoicevoxAudioValues);
var
  Key: string;
begin
  if (Trim(SpeakerUUID) = '') or (StyleId < 0) then Exit;
  Key := MakeKey(SpeakerUUID, StyleId);
  if Values.IsDefault then
    FItems.Remove(Key)
  else
    FItems.AddOrSetValue(Key, Values);
  FDirty := True;
end;

end.
