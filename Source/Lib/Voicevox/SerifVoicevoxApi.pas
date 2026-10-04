// VOICEVOX Engine APIを呼び出し、既存Analyzerへ渡すwav/txtペアを生成する。
unit SerifVoicevoxApi;

interface

uses
  System.SysUtils, SerifVoicevoxAudioSettings;

type
  TSerifVoicevoxApi = class
  private const
    AUDIO_QUERY_URL = 'http://127.0.0.1:50021/audio_query';
    ACCENT_PHRASES_URL = 'http://127.0.0.1:50021/accent_phrases';
    MORA_DATA_URL = 'http://127.0.0.1:50021/mora_data';
    SYNTHESIS_URL = 'http://127.0.0.1:50021/synthesis';
    HTTP_TIMEOUT_MS = 120000;
    class function RecalculateMoraData(const QueryJson: string;
      const SpeakerId: Integer; out ResultJson,
      ErrorMessage: string): Boolean; static;
  public
    // 指定した本文とstyleから、アクセント句とモーラを含むaudio_query JSONを取得する。
    class function CreateAudioQuery(const Text: string;
      const SpeakerId: Integer; out QueryJson,
      ErrorMessage: string): Boolean; static;
    // 入力した読みから、差し替え用のアクセント句JSON配列を取得する。
    class function CreateAccentPhrases(const Reading: string;
      const SpeakerId: Integer; out AccentPhrasesJson,
      ErrorMessage: string): Boolean; static;
    // 既存AnalyzerがVOICEVOX形式として解釈できる同名のwav/txtペアを一時フォルダへ生成する。
    class function CreateInputFiles(const Text, CharacterName,
      StyleName: string; const SpeakerId: Integer;
      const AudioValues: TSerifVoicevoxAudioValues; out WaveFileName,
      TextFileName, ErrorMessage: string): Boolean; overload; static;
    // 編集済みaudio_queryが有効ならモーラを再計算して手動編集値を戻し、不正なら本文から再生成する。
    class function CreateInputFiles(const Text, CharacterName,
      StyleName: string; const SpeakerId: Integer;
      const AudioValues: TSerifVoicevoxAudioValues;
      const QueryJsonOverride: string; out WaveFileName,
      TextFileName, ErrorMessage: string): Boolean; overload; static;
    // 最終audio_queryの音素長を生成WAVへ合わせたLABも同時に返す。
    class function CreateInputFiles(const Text, CharacterName,
      StyleName: string; const SpeakerId: Integer;
      const AudioValues: TSerifVoicevoxAudioValues;
      const QueryJsonOverride: string; out WaveFileName,
      TextFileName, LabFileName, ErrorMessage: string): Boolean; overload; static;
  end;

implementation

uses
  Winapi.Windows, System.Classes, System.IOUtils, System.Net.HttpClient,
  System.Net.URLClient, System.NetEncoding, System.JSON,
  System.Generics.Collections,
  SerifVoicevoxDebugLog, SoundFileUtilsWave, RigmVoicevoxConfig;

type
  TSerifVoicevoxLabSegment = record
    Duration: Double;
    Phoneme: string;
  end;
  TSerifVoicevoxLabSegments = array of TSerifVoicevoxLabSegment;

function CreateLabFromAudioQuery(const QueryJson, WaveFileName,
  LabFileName: string): Boolean;
var
  AccentPhrases: TJSONArray;
  End100ns: Int64;
  FS: TFormatSettings;
  I: Integer;
  Moras: TJSONArray;
  PhraseIndex: Integer;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  Scale: Double;
  Segments: TSerifVoicevoxLabSegments;
  Start100ns: Int64;
  TextLines: TStringList;
  TotalDuration: Double;
  WaveLength: Double;

  procedure AddSegment(const Duration: Double; const Phoneme: string);
  var
    Index: Integer;
  begin
    if Duration <= 0 then Exit;
    Index := Length(Segments);
    SetLength(Segments, Index + 1);
    Segments[Index].Duration := Duration;
    Segments[Index].Phoneme := Phoneme;
    TotalDuration := TotalDuration + Duration;
  end;

  procedure AddMora(Mora: TJSONObject);
  var
    Value: TJSONValue;
  begin
    if Mora = nil then Exit;
    Value := Mora.GetValue('consonant_length');
    if Value is TJSONNumber then
      AddSegment(Mora.GetValue<Double>('consonant_length'), 'Consonant');
    Value := Mora.GetValue('vowel_length');
    if not (Value is TJSONNumber) then Exit;
    Value := Mora.GetValue('vowel');
    if Value is TJSONString then
      AddSegment(Mora.GetValue<Double>('vowel_length'), Value.Value)
    else
      AddSegment(Mora.GetValue<Double>('vowel_length'), 'Pause');
  end;

  function GetRootNumber(const Name: string): Double;
  var
    Value: TJSONValue;
  begin
    Result := 0;
    Value := RootObject.GetValue(Name);
    if Value is TJSONNumber then Result := RootObject.GetValue<Double>(Name);
  end;
begin
  Result := False;
  RootValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if AccentPhrases = nil then Exit;

    TotalDuration := 0;
    AddSegment(GetRootNumber('prePhonemeLength'), 'Pause');
    for PhraseIndex := 0 to AccentPhrases.Count - 1 do
    begin
      if not (AccentPhrases.Items[PhraseIndex] is TJSONObject) then Exit;
      PhraseObject := TJSONObject(AccentPhrases.Items[PhraseIndex]);
      Moras := PhraseObject.GetValue<TJSONArray>('moras');
      if Moras = nil then Exit;
      for I := 0 to Moras.Count - 1 do
      begin
        if not (Moras.Items[I] is TJSONObject) then Exit;
        AddMora(TJSONObject(Moras.Items[I]));
      end;
      if PhraseObject.GetValue('pause_mora') is TJSONObject then
        AddMora(TJSONObject(PhraseObject.GetValue('pause_mora')));
    end;
    AddSegment(GetRootNumber('postPhonemeLength'), 'Pause');
    if TotalDuration <= 0 then Exit;

    WaveLength := GetWaveLengthSec(WaveFileName);
    if WaveLength <= 0 then Exit;
    Scale := WaveLength / TotalDuration;
    FS := TFormatSettings.Create;
    FS.DecimalSeparator := '.';
    TextLines := TStringList.Create;
    try
      Start100ns := 0;
      for I := 0 to High(Segments) do
      begin
        if I = High(Segments) then
          End100ns := Round(WaveLength * 10000000)
        else
          End100ns := Start100ns +
            Round(Segments[I].Duration * Scale * 10000000);
        if End100ns > Start100ns then
          TextLines.Add(Format('%d %d %s',
            [Start100ns, End100ns, Segments[I].Phoneme], FS));
        Start100ns := End100ns;
      end;
      if TextLines.Count = 0 then Exit;
      TextLines.SaveToFile(LabFileName, TEncoding.UTF8);
      Result := True;
    finally
      TextLines.Free;
    end;
  finally
    RootValue.Free;
  end;
end;

procedure SetJsonNumber(JsonObject: TJSONObject; const Name: string;
  const Value: Double);
var
  Pair: TJSONPair;
begin
  Pair := JsonObject.RemovePair(Name);
  Pair.Free;
  JsonObject.AddPair(Name, TJSONNumber.Create(Value));
end;

class function TSerifVoicevoxApi.CreateAccentPhrases(const Reading: string;
  const SpeakerId: Integer; out AccentPhrasesJson,
  ErrorMessage: string): Boolean;
var
  ApiResponse: IHTTPResponse;
  Client: THTTPClient;
  EmptyStream: TStringStream;
  QueryUrl: string;
  ResponseValue: TJSONValue;
begin
  VoicevoxDebugLog(Format('API /accent_phrases begin speaker=%d readingLength=%d',
    [SpeakerId, Length(Reading)]));
  Result := False;
  AccentPhrasesJson := '';
  ErrorMessage := '';
  if Trim(Reading) = '' then
  begin
    ErrorMessage := #$8AAD#$307F#$3092#$5165#$529B#$3057#$3066 +
      #$304F#$3060#$3055#$3044;
    Exit;
  end;
  if SpeakerId < 0 then
  begin
    ErrorMessage := 'VOICEVOX speaker is not selected';
    Exit;
  end;

  Client := THTTPClient.Create; ConfigureVoicevoxClient(Client);
  try
    Client.ConnectionTimeout := 3000;
    Client.ResponseTimeout := HTTP_TIMEOUT_MS;
    QueryUrl := Format('%s?text=%s&speaker=%d',
      [VoicevoxEndpoint(ACCENT_PHRASES_URL), TNetEncoding.URL.Encode(Trim(Reading)),
       SpeakerId]);
    EmptyStream := TStringStream.Create('', TEncoding.UTF8);
    try
      ApiResponse := CheckedVoicevoxPost(Client,QueryUrl, EmptyStream);
      VoicevoxDebugLog(Format('API /accent_phrases HTTP=%d',
        [ApiResponse.StatusCode]));
      if ApiResponse.StatusCode <> 200 then
        raise Exception.CreateFmt('accent_phrases HTTP %d',
          [ApiResponse.StatusCode]);
      AccentPhrasesJson := ApiResponse.ContentAsString(TEncoding.UTF8);
      ResponseValue := TJSONObject.ParseJSONValue(AccentPhrasesJson);
      try
        if not (ResponseValue is TJSONArray) or
          (TJSONArray(ResponseValue).Count = 0) then
          raise Exception.Create('accent_phrases returned invalid JSON');
      finally
        ResponseValue.Free;
      end;
      Result := True;
    finally
      EmptyStream.Free;
    end;
  except
    on E: Exception do
    begin
      AccentPhrasesJson := '';
      ErrorMessage := E.Message;
      VoicevoxDebugLog('API /accent_phrases error=' + E.ClassName + ': ' +
        E.Message);
    end;
  end;
  Client.Free;
  VoicevoxDebugLog(Format('API /accent_phrases end success=%s',
    [BoolToStr(Result, True)]));
end;

class function TSerifVoicevoxApi.RecalculateMoraData(
  const QueryJson: string; const SpeakerId: Integer; out ResultJson,
  ErrorMessage: string): Boolean;
var
  AccentPair: TJSONPair;
  AccentPhrases: TJSONArray;
  ApiResponse: IHTTPResponse;
  Client: THTTPClient;
  Headers: TNetHeaders;
  MoraValue: TJSONValue;
  QueryObject: TJSONObject;
  QueryStream: TStringStream;
  QueryValue: TJSONValue;
begin
  VoicevoxDebugLog(Format('API /mora_data begin speaker=%d queryBytes=%d',
    [SpeakerId, Length(QueryJson)]));
  Result := False;
  ResultJson := '';
  ErrorMessage := '';
  QueryValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (QueryValue is TJSONObject) then
      raise Exception.Create('audio_query JSON is invalid');
    QueryObject := TJSONObject(QueryValue);
    AccentPhrases := QueryObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(AccentPhrases) then
      raise Exception.Create('accent_phrases is missing');

    SetLength(Headers, 1);
    Headers[0].Name := 'Content-Type';
    Headers[0].Value := 'application/json';
    Client := THTTPClient.Create; ConfigureVoicevoxClient(Client);
    try
      Client.ConnectionTimeout := 3000;
      Client.ResponseTimeout := HTTP_TIMEOUT_MS;
      QueryStream := TStringStream.Create(AccentPhrases.ToJSON,
        TEncoding.UTF8);
      try
        ApiResponse := CheckedVoicevoxPost(Client,Format('%s?speaker=%d',
          [VoicevoxEndpoint(MORA_DATA_URL), SpeakerId]), QueryStream, nil, Headers);
        VoicevoxDebugLog(Format('API /mora_data HTTP=%d',
          [ApiResponse.StatusCode]));
        if ApiResponse.StatusCode <> 200 then
          raise Exception.CreateFmt('mora_data HTTP %d',
            [ApiResponse.StatusCode]);
        MoraValue := TJSONObject.ParseJSONValue(
          ApiResponse.ContentAsString(TEncoding.UTF8));
        if not (MoraValue is TJSONArray) then
        begin
          MoraValue.Free;
          raise Exception.Create('mora_data returned invalid JSON');
        end;
        AccentPair := QueryObject.RemovePair('accent_phrases');
        AccentPair.Free;
        QueryObject.AddPair('accent_phrases', MoraValue);
        ResultJson := QueryObject.ToJSON;
        Result := True;
      finally
        QueryStream.Free;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      VoicevoxDebugLog('API /mora_data error=' + E.ClassName + ': ' +
        E.Message);
    end;
  end;
  QueryValue.Free;
  VoicevoxDebugLog(Format('API /mora_data end success=%s',
    [BoolToStr(Result, True)]));
end;

class function TSerifVoicevoxApi.CreateAudioQuery(const Text: string;
  const SpeakerId: Integer; out QueryJson, ErrorMessage: string): Boolean;
var
  ApiResponse: IHTTPResponse;
  Client: THTTPClient;
  EmptyStream: TStringStream;
  QueryUrl: string;
begin
  VoicevoxDebugLog(Format('API /audio_query begin speaker=%d textLength=%d',
    [SpeakerId, Length(Text)]));
  Result := False;
  QueryJson := '';
  ErrorMessage := '';
  if Trim(Text) = '' then
  begin
    ErrorMessage := 'text is empty';
    Exit;
  end;
  if SpeakerId < 0 then
  begin
    ErrorMessage := 'VOICEVOX speaker is not selected';
    Exit;
  end;

  Client := THTTPClient.Create; ConfigureVoicevoxClient(Client);
  try
    Client.ConnectionTimeout := 3000;
    Client.ResponseTimeout := HTTP_TIMEOUT_MS;
    QueryUrl := Format('%s?text=%s&speaker=%d',
      [VoicevoxEndpoint(AUDIO_QUERY_URL), TNetEncoding.URL.Encode(Text), SpeakerId]);
    EmptyStream := TStringStream.Create('', TEncoding.UTF8);
    try
      ApiResponse := CheckedVoicevoxPost(Client,QueryUrl, EmptyStream);
      VoicevoxDebugLog(Format('API /audio_query HTTP=%d',
        [ApiResponse.StatusCode]));
      if ApiResponse.StatusCode <> 200 then
        raise Exception.CreateFmt('audio_query HTTP %d',
          [ApiResponse.StatusCode]);
      QueryJson := ApiResponse.ContentAsString(TEncoding.UTF8);
      Result := True;
    finally
      EmptyStream.Free;
    end;
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      VoicevoxDebugLog('API /audio_query error=' + E.ClassName + ': ' +
        E.Message);
    end;
  end;
  Client.Free;
  VoicevoxDebugLog(Format('API /audio_query end success=%s',
    [BoolToStr(Result, True)]));
end;

function ApplyAudioValues(const QueryJson: string;
  const AudioValues: TSerifVoicevoxAudioValues): string;
var
  JsonObject: TJSONObject;
  JsonValue: TJSONValue;
begin
  JsonValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (JsonValue is TJSONObject) then
      raise Exception.Create('audio_query returned invalid JSON');
    JsonObject := TJSONObject(JsonValue);
    SetJsonNumber(JsonObject, 'speedScale', AudioValues.SpeedScale);
    SetJsonNumber(JsonObject, 'pitchScale', AudioValues.PitchScale);
    SetJsonNumber(JsonObject, 'intonationScale', AudioValues.IntonationScale);
    SetJsonNumber(JsonObject, 'volumeScale', AudioValues.VolumeScale);
    SetJsonNumber(JsonObject, 'prePhonemeLength',
      AudioValues.PrePhonemeLength);
    SetJsonNumber(JsonObject, 'postPhonemeLength',
      AudioValues.PostPhonemeLength);
    Result := JsonObject.ToJSON;
  finally
    JsonValue.Free;
  end;
end;

// /mora_data後のモーラ列へ手動pitchを戻し、VOICEVOXへ送らない内部情報を除去する。
function ApplyIntonationValues(const QueryJson: string): string;
const
  META_NAME = '_syncroh2_intonation';
var
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  Meta: TJSONArray;
  MetaValue: TJSONValue;
  MetaIndex: Integer;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MoraCount: Integer;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  ValidMeta: Boolean;

  function MoraSignature(const Mora: TJSONObject): string;
  var
    Value: TJSONValue;
  begin
    Result := Mora.GetValue<string>('text');
    Value := Mora.GetValue('consonant');
    if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
    Value := Mora.GetValue('vowel');
    if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
  end;
begin
  RootValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (RootValue is TJSONObject) then
      raise Exception.Create('audio_query returned invalid JSON');
    RootObject := TJSONObject(RootValue);
    MetaValue := RootObject.GetValue(META_NAME);
    if MetaValue is TJSONArray then Meta := TJSONArray(MetaValue)
    else Meta := nil;
    if Assigned(Meta) then
    begin
      AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
      MoraCount := 0;
      if Assigned(AccentPhrases) then
        for I := 0 to AccentPhrases.Count - 1 do
        begin
          PhraseObject := AccentPhrases.Items[I] as TJSONObject;
          Moras := PhraseObject.GetValue<TJSONArray>('moras');
          if Assigned(Moras) then Inc(MoraCount, Moras.Count);
        end;

      ValidMeta := Assigned(AccentPhrases) and (Meta.Count = MoraCount);
      MetaIndex := 0;
      if ValidMeta then
        for I := 0 to AccentPhrases.Count - 1 do
        begin
          PhraseObject := AccentPhrases.Items[I] as TJSONObject;
          Moras := PhraseObject.GetValue<TJSONArray>('moras');
          if not Assigned(Moras) then Continue;
          for J := 0 to Moras.Count - 1 do
          begin
            MoraObject := Moras.Items[J] as TJSONObject;
            if not (Meta.Items[MetaIndex] is TJSONObject) then
            begin
              ValidMeta := False;
              Break;
            end;
            MetaItem := TJSONObject(Meta.Items[MetaIndex]);
            if MetaItem.GetValue<string>('signature') <>
              MoraSignature(MoraObject) then
            begin
              ValidMeta := False;
              Break;
            end;
            Inc(MetaIndex);
          end;
          if not ValidMeta then Break;
        end;

      if ValidMeta then
      begin
        MetaIndex := 0;
        for I := 0 to AccentPhrases.Count - 1 do
        begin
          PhraseObject := AccentPhrases.Items[I] as TJSONObject;
          Moras := PhraseObject.GetValue<TJSONArray>('moras');
          if not Assigned(Moras) then Continue;
          for J := 0 to Moras.Count - 1 do
          begin
            MoraObject := Moras.Items[J] as TJSONObject;
            MetaItem := TJSONObject(Meta.Items[MetaIndex]);
            SetJsonNumber(MoraObject, 'pitch',
              MetaItem.GetValue<Double>('pitch'));
            Inc(MetaIndex);
          end;
        end;
      end;

      MetaPair := RootObject.RemovePair(META_NAME);
      MetaPair.Free;
    end;
    Result := RootObject.ToJSON;
  finally
    RootValue.Free;
  end;
end;

// /mora_data後のモーラ列へ手動の子音長・母音長を戻し、内部情報を除去する。
function ApplyLengthValues(const QueryJson: string): string;
const
  META_NAME = '_syncroh2_length';
var
  AccentPhrases: TJSONArray;
  Meta: TJSONArray;
  MetaIndex: Integer;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MetaValue: TJSONValue;
  Moras: TJSONArray;
  PauseValue: TJSONValue;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  ValidMeta: Boolean;

  function MoraSignature(const Mora: TJSONObject): string;
  var
    Value: TJSONValue;
  begin
    Result := Mora.GetValue<string>('text');
    Value := Mora.GetValue('consonant');
    if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
    Value := Mora.GetValue('vowel');
    if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
  end;

  function HasJsonNumber(const JsonObject: TJSONObject;
    const Name: string): Boolean;
  begin
    Result := JsonObject.GetValue(Name) is TJSONNumber;
  end;

  procedure ProcessSegment(const Mora: TJSONObject;
    const FieldName: string; const ApplyValue: Boolean);
  var
    LengthValue: TJSONValue;
    SignatureValue: TJSONValue;
  begin
    if not ValidMeta or not HasJsonNumber(Mora, FieldName) then Exit;
    if (MetaIndex >= Meta.Count) or
      not (Meta.Items[MetaIndex] is TJSONObject) then
    begin
      ValidMeta := False;
      Exit;
    end;
    MetaItem := TJSONObject(Meta.Items[MetaIndex]);
    SignatureValue := MetaItem.GetValue('signature');
    LengthValue := MetaItem.GetValue('length');
    if not (SignatureValue is TJSONString) or
      not (LengthValue is TJSONNumber) or
      (SignatureValue.Value <> MoraSignature(Mora) + #1 + FieldName) then
    begin
      ValidMeta := False;
      Exit;
    end;
    if ApplyValue then
      SetJsonNumber(Mora, FieldName, MetaItem.GetValue<Double>('length'));
    Inc(MetaIndex);
  end;

  procedure ProcessMora(const Mora: TJSONObject;
    const ApplyValue: Boolean);
  begin
    ProcessSegment(Mora, 'consonant_length', ApplyValue);
    ProcessSegment(Mora, 'vowel_length', ApplyValue);
  end;

  procedure ProcessAll(const ApplyValue: Boolean);
  var
    PhraseIndex: Integer;
    MoraIndex: Integer;
  begin
    MetaIndex := 0;
    for PhraseIndex := 0 to AccentPhrases.Count - 1 do
    begin
      PhraseObject := AccentPhrases.Items[PhraseIndex] as TJSONObject;
      Moras := PhraseObject.GetValue<TJSONArray>('moras');
      for MoraIndex := 0 to Moras.Count - 1 do
      begin
        ProcessMora(Moras.Items[MoraIndex] as TJSONObject, ApplyValue);
        if not ValidMeta then Exit;
      end;
      PauseValue := PhraseObject.GetValue('pause_mora');
      if PauseValue is TJSONObject then
        ProcessMora(TJSONObject(PauseValue), ApplyValue);
      if not ValidMeta then Exit;
    end;
    if MetaIndex <> Meta.Count then ValidMeta := False;
  end;

begin
  RootValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (RootValue is TJSONObject) then
      raise Exception.Create('audio_query returned invalid JSON');
    RootObject := TJSONObject(RootValue);
    MetaValue := RootObject.GetValue(META_NAME);
    if MetaValue is TJSONArray then Meta := TJSONArray(MetaValue)
    else Meta := nil;
    if Assigned(Meta) then
    begin
      AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
      ValidMeta := Assigned(AccentPhrases);
      if ValidMeta then ProcessAll(False);
      if ValidMeta then ProcessAll(True);
      MetaPair := RootObject.RemovePair(META_NAME);
      MetaPair.Free;
    end;
    Result := RootObject.ToJSON;
  finally
    RootValue.Free;
  end;
end;

function SafeFileNamePart(const Value, Fallback: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Value do
    if (Ord(C) < 32) or CharInSet(C, ['\', '/', ':', '*', '?', '"', '<', '>', '|']) then
      Result := Result + '_'
    else
      Result := Result + C;
  Result := Trim(Result);
  if Result = '' then Result := Fallback;
end;

class function TSerifVoicevoxApi.CreateInputFiles(const Text,
  CharacterName, StyleName: string; const SpeakerId: Integer;
  const AudioValues: TSerifVoicevoxAudioValues;
  out WaveFileName, TextFileName, ErrorMessage: string): Boolean;
begin
  Result := CreateInputFiles(Text, CharacterName, StyleName, SpeakerId,
    AudioValues, '', WaveFileName, TextFileName, ErrorMessage);
end;

class function TSerifVoicevoxApi.CreateInputFiles(const Text,
  CharacterName, StyleName: string; const SpeakerId: Integer;
  const AudioValues: TSerifVoicevoxAudioValues;
  const QueryJsonOverride: string;
  out WaveFileName, TextFileName, ErrorMessage: string): Boolean;
var
  LabFileName: string;
begin
  Result := CreateInputFiles(Text, CharacterName, StyleName, SpeakerId,
    AudioValues, QueryJsonOverride, WaveFileName, TextFileName, LabFileName,
    ErrorMessage);
  if TFile.Exists(LabFileName) then TFile.Delete(LabFileName);
end;

class function TSerifVoicevoxApi.CreateInputFiles(const Text,
  CharacterName, StyleName: string; const SpeakerId: Integer;
  const AudioValues: TSerifVoicevoxAudioValues;
  const QueryJsonOverride: string;
  out WaveFileName, TextFileName, LabFileName,
  ErrorMessage: string): Boolean;
var
  ApiResponse: IHTTPResponse;
  Client: THTTPClient;
  Headers: TNetHeaders;
  HasQueryOverride: Boolean;
  QueryJson: string;
  RecalculatedQueryJson: string;
  QueryStream: TStringStream;
  SourceBaseName: string;
  TempFolder: string;
  UniqueFolder: string;
  WaveStream: TFileStream;

  function IsValidAudioQuery(const Value: string): Boolean;
  var
    JsonValue: TJSONValue;
  begin
    JsonValue := TJSONObject.ParseJSONValue(Value);
    try
      Result := (JsonValue is TJSONObject) and
        Assigned(TJSONObject(JsonValue).GetValue<TJSONArray>(
          'accent_phrases'));
    finally
      JsonValue.Free;
    end;
  end;
begin
  VoicevoxDebugLog(Format('API CreateInputFiles begin speaker=%d textLength=%d queryOverride=%s',
    [SpeakerId, Length(Text), BoolToStr(QueryJsonOverride <> '', True)]));
  Result := False;
  WaveFileName := '';
  TextFileName := '';
  LabFileName := '';
  ErrorMessage := '';
  if Trim(Text) = '' then
  begin
    ErrorMessage := 'text is empty';
    Exit;
  end;
  if SpeakerId < 0 then
  begin
    ErrorMessage := 'VOICEVOX speaker is not selected';
    Exit;
  end;

  TempFolder := TPath.Combine(TPath.GetTempPath, 'RIGMMaker\Voicevox');
  UniqueFolder := FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '_' +
    IntToHex(GetTickCount64, 16);
  TempFolder := TPath.Combine(TempFolder, UniqueFolder);
  TDirectory.CreateDirectory(TempFolder);

  SourceBaseName := '001_' + SafeFileNamePart(CharacterName, 'VOICEVOX') +
    #$FF08 + SafeFileNamePart(StyleName, IntToStr(SpeakerId)) +
    #$FF09 + '_RIGMMaker';
  TextFileName := TPath.Combine(TempFolder, SourceBaseName + '.txt');
  WaveFileName := TPath.Combine(TempFolder, SourceBaseName + '.wav');
  LabFileName := TPath.Combine(TempFolder, SourceBaseName + '.lab');

  Client := THTTPClient.Create; ConfigureVoicevoxClient(Client);
  try
    try
      Client.ConnectionTimeout := 3000;
      Client.ResponseTimeout := HTTP_TIMEOUT_MS;
      QueryJson := QueryJsonOverride;
      HasQueryOverride := (QueryJson <> '') and IsValidAudioQuery(QueryJson);
      if (QueryJson <> '') and not HasQueryOverride then
      begin
        VoicevoxDebugLog(
          'API CreateInputFiles discarded invalid query override');
        QueryJson := '';
      end;
      if not HasQueryOverride and
        not CreateAudioQuery(Text, SpeakerId, QueryJson, ErrorMessage) then
        raise Exception.Create(ErrorMessage);
      // const入力とout出力に同じ変数を渡すと、出力初期化で入力JSONまで失われる。
      if HasQueryOverride and
        not RecalculateMoraData(QueryJson, SpeakerId,
        RecalculatedQueryJson,
        ErrorMessage) then
        raise Exception.Create(ErrorMessage);
      if HasQueryOverride then
        QueryJson := RecalculatedQueryJson;

      QueryJson := ApplyIntonationValues(QueryJson);
      QueryJson := ApplyLengthValues(QueryJson);
      QueryJson := ApplyAudioValues(QueryJson, AudioValues);

      SetLength(Headers, 1);
      Headers[0].Name := 'Content-Type';
      Headers[0].Value := 'application/json';
      QueryStream := TStringStream.Create(QueryJson, TEncoding.UTF8);
      try
        WaveStream := TFileStream.Create(WaveFileName, fmCreate);
        try
          ApiResponse := CheckedVoicevoxPost(Client,
            Format('%s?speaker=%d', [VoicevoxEndpoint(SYNTHESIS_URL), SpeakerId]),
            QueryStream, WaveStream, Headers);
          VoicevoxDebugLog(Format('API /synthesis HTTP=%d',
            [ApiResponse.StatusCode]));
          if ApiResponse.StatusCode <> 200 then
            raise Exception.CreateFmt('synthesis HTTP %d',
              [ApiResponse.StatusCode]);
        finally
          WaveStream.Free;
        end;
      finally
        QueryStream.Free;
      end;

      TFile.WriteAllText(TextFileName, Text, TEncoding.UTF8);
      if not CreateLabFromAudioQuery(QueryJson, WaveFileName, LabFileName) then
        raise Exception.Create('VOICEVOX音素LABを生成できませんでした');
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMessage := E.Message;
        VoicevoxDebugLog('API CreateInputFiles error=' + E.ClassName + ': ' +
          E.Message);
      end;
    end;
  finally
    Client.Free;
  end;

  if Result then
  begin
    VoicevoxDebugLog('API CreateInputFiles end success=True');
    Exit;
  end;
  if TFile.Exists(TextFileName) then
    TFile.Delete(TextFileName);
  if TFile.Exists(WaveFileName) then
    TFile.Delete(WaveFileName);
  if TFile.Exists(LabFileName) then
    TFile.Delete(LabFileName);
  if TDirectory.Exists(TempFolder) then
    try
      TDirectory.Delete(TempFolder, False);
    except
      // 一時フォルダの後始末失敗は、元のAPIエラーを上書きしない。
    end;
  VoicevoxDebugLog('API CreateInputFiles end success=False');
end;

end.
