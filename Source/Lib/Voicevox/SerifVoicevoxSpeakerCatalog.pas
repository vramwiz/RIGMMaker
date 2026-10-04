// VOICEVOX Engineのspeakers APIから、話者とstyleの選択用カタログを構築する。
unit SerifVoicevoxSpeakerCatalog;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  // VOICEVOXが公開する1つのstyle。IDは音声合成APIのspeakerパラメーターへ渡す。
  TSerifVoicevoxStyle = class
  public
    // Engine内でstyleを一意に識別する数値ID。
    Id: Integer;
    // 感情など、メニューへ表示するstyle名。
    Name: string;
  end;

  TSerifVoicevoxSpeaker = class
  private
    FStyles: TObjectList<TSerifVoicevoxStyle>;
  public
    // メニューへ表示するキャラクター名。
    Name: string;
    // 音声設定の保存キーとして使う、Engineが返した話者UUID。
    UUID: string;
    // 所有するstyle一覧を空で生成する。
    constructor Create;
    destructor Destroy; override;
    // 指定IDのstyleを返す。見つからない場合はnil。
    function FindStyle(const StyleId: Integer): TSerifVoicevoxStyle;
    // この話者が所有し、破棄時に解放するstyle一覧。
    property Styles: TObjectList<TSerifVoicevoxStyle> read FStyles;
  end;

  TSerifVoicevoxSpeakerCatalog = class
  private const
    SPEAKERS_URL = 'http://127.0.0.1:50021/speakers';
    DEFAULT_STYLE_ID = 3;
  private
    FSpeakers: TObjectList<TSerifVoicevoxSpeaker>;
  public
    // 話者を所有する空のカタログを生成する。
    constructor Create;
    destructor Destroy; override;
    // style IDを全話者から検索し、所属話者とstyleを返す。
    function FindStyle(const StyleId: Integer;
      out Speaker: TSerifVoicevoxSpeaker;
      out Style: TSerifVoicevoxStyle): Boolean;
    // 規定style IDを優先し、存在しなければ先頭の話者・styleを返す。
    function GetDefault(out Speaker: TSerifVoicevoxSpeaker;
      out Style: TSerifVoicevoxStyle): Boolean;
    // speakers APIを読み込んでカタログ全体を置き換える。失敗理由はErrorMessageへ返す。
    function LoadFromApi(out ErrorMessage: string): Boolean;
    // カタログが所有する、APIの表示順を維持した話者一覧。
    property Speakers: TObjectList<TSerifVoicevoxSpeaker> read FSpeakers;
  end;

implementation

uses
  System.JSON, System.Net.HttpClient, SerifVoicevoxDebugLog, RigmVoicevoxConfig;

function JsonString(JsonObject: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := JsonObject.GetValue(Name);
  if Assigned(Value) then
    Result := Value.Value;
end;

constructor TSerifVoicevoxSpeaker.Create;
begin
  inherited Create;
  FStyles := TObjectList<TSerifVoicevoxStyle>.Create(True);
end;

destructor TSerifVoicevoxSpeaker.Destroy;
begin
  FStyles.Free;
  inherited;
end;

function TSerifVoicevoxSpeaker.FindStyle(
  const StyleId: Integer): TSerifVoicevoxStyle;
var
  Item: TSerifVoicevoxStyle;
begin
  Result := nil;
  for Item in FStyles do
    if Item.Id = StyleId then Exit(Item);
end;

constructor TSerifVoicevoxSpeakerCatalog.Create;
begin
  inherited Create;
  FSpeakers := TObjectList<TSerifVoicevoxSpeaker>.Create(True);
end;

destructor TSerifVoicevoxSpeakerCatalog.Destroy;
begin
  FSpeakers.Free;
  inherited;
end;

function TSerifVoicevoxSpeakerCatalog.FindStyle(const StyleId: Integer;
  out Speaker: TSerifVoicevoxSpeaker;
  out Style: TSerifVoicevoxStyle): Boolean;
var
  SpeakerItem: TSerifVoicevoxSpeaker;
begin
  Speaker := nil;
  Style := nil;
  for SpeakerItem in FSpeakers do
  begin
    Style := SpeakerItem.FindStyle(StyleId);
    if Assigned(Style) then
    begin
      Speaker := SpeakerItem;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSerifVoicevoxSpeakerCatalog.GetDefault(
  out Speaker: TSerifVoicevoxSpeaker;
  out Style: TSerifVoicevoxStyle): Boolean;
begin
  Result := FindStyle(DEFAULT_STYLE_ID, Speaker, Style);
  if Result then Exit;
  Speaker := nil;
  Style := nil;
  if (FSpeakers.Count > 0) and (FSpeakers[0].Styles.Count > 0) then
  begin
    Speaker := FSpeakers[0];
    Style := Speaker.Styles[0];
    Result := True;
  end;
end;

function TSerifVoicevoxSpeakerCatalog.LoadFromApi(
  out ErrorMessage: string): Boolean;
var
  Client: THTTPClient;
  I: Integer;
  J: Integer;
  JsonArray: TJSONArray;
  JsonRoot: TJSONValue;
  Response: IHTTPResponse;
  Speaker: TSerifVoicevoxSpeaker;
  SpeakerObject: TJSONObject;
  Style: TSerifVoicevoxStyle;
  StyleArray: TJSONArray;
  StyleObject: TJSONObject;
  StyleType: string;
begin
  VoicevoxDebugLog('SpeakerCatalog.LoadFromApi GET /speakers begin');
  Result := False;
  ErrorMessage := '';
  FSpeakers.Clear;
  Client := THTTPClient.Create; ConfigureVoicevoxClient(Client);
  try
    Client.ConnectionTimeout := 3000;
    Client.ResponseTimeout := 10000;
    try
      Response := CheckedVoicevoxGet(Client,VoicevoxEndpoint(SPEAKERS_URL));
      VoicevoxDebugLog(Format('SpeakerCatalog.LoadFromApi GET /speakers HTTP=%d',
        [Response.StatusCode]));
      if Response.StatusCode <> 200 then
        raise Exception.CreateFmt('speakers HTTP %d', [Response.StatusCode]);
      JsonRoot := TJSONObject.ParseJSONValue(
        Response.ContentAsString(TEncoding.UTF8));
      try
        if not (JsonRoot is TJSONArray) then
          raise Exception.Create('speakers response is not an array');
        JsonArray := TJSONArray(JsonRoot);
        for I := 0 to JsonArray.Count - 1 do
        begin
          if not (JsonArray.Items[I] is TJSONObject) then Continue;
          SpeakerObject := TJSONObject(JsonArray.Items[I]);
          Speaker := TSerifVoicevoxSpeaker.Create;
          try
            Speaker.Name := JsonString(SpeakerObject, 'name');
            Speaker.UUID := JsonString(SpeakerObject, 'speaker_uuid');
            StyleArray := SpeakerObject.GetValue('styles') as TJSONArray;
            if Assigned(StyleArray) then
              for J := 0 to StyleArray.Count - 1 do
              begin
                if not (StyleArray.Items[J] is TJSONObject) then Continue;
                StyleObject := TJSONObject(StyleArray.Items[J]);
                StyleType := JsonString(StyleObject, 'type');
                if (StyleType <> '') and not SameText(StyleType, 'talk') then
                  Continue;
                Style := TSerifVoicevoxStyle.Create;
                Style.Name := JsonString(StyleObject, 'name');
                Style.Id := StrToIntDef(JsonString(StyleObject, 'id'), -1);
                if Style.Id >= 0 then
                  Speaker.Styles.Add(Style)
                else
                  Style.Free;
              end;
            if (Speaker.Name <> '') and (Speaker.Styles.Count > 0) then
              FSpeakers.Add(Speaker)
            else
              Speaker.Free;
          except
            Speaker.Free;
            raise;
          end;
        end;
      finally
        JsonRoot.Free;
      end;
      if FSpeakers.Count = 0 then
        raise Exception.Create('talk speaker is not available');
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMessage := E.Message;
        VoicevoxDebugLog('SpeakerCatalog.LoadFromApi error=' + E.ClassName +
          ': ' + E.Message);
      end;
    end;
  finally
    Client.Free;
  end;
  VoicevoxDebugLog(Format('SpeakerCatalog.LoadFromApi end success=%s speakers=%d',
    [BoolToStr(Result, True), FSpeakers.Count]));
end;

end.
