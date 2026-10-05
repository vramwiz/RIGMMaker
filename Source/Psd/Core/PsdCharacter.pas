unit PsdCharacter;

// PSD文書・差分設定・全身連番を所有する独立キャラモデル。
interface
uses System.SysUtils, System.JSON, System.Generics.Collections, ArtDocument;

type
  TPsdCharacter = class
  public
    Id, Name, SupplementName, Policy, Source: string; // Policyはmanaged/external。元PSDの場所と無関係に保持。
    Production: TJSONObject; // 所有。仕様検査の結果。旧パッケージは未検査/未完成。
    Document: TArtDocument; // 所有。通常表示の初期状態を保存する。
    Settings: TJSONObject; // 所有。グループID・差分ID・音素と連番を保持。
    Assets: TDictionary<string, TBytes>; // 所有。ZIP内のPNG連番。外部パスは格納しない。
    constructor Create;
    destructor Destroy; override;
    procedure RequireManaged;
    procedure Validate;
    function Group(const GroupId: string): TJSONObject; // 借用。不存在なら例外。
    procedure CheckChoice(const GroupId, PartId: string);
    procedure SetDefault(const GroupId, PartId: string);
    function Front: TArtLayer;
    function NonFront: TArtLayer;
  end;

implementation
uses PsdJson;

constructor TPsdCharacter.Create;
begin
  inherited; Id := NewId; Policy := 'managed'; Document := TArtDocument.Create;
  Settings := TJSONObject.Create; Production := TJSONObject.Create; Assets := TDictionary<string, TBytes>.Create;
  Production.AddPair('stage', 'draft'); Production.AddPair('checked', TJSONBool.Create(False));
  Settings.AddPair('groups', TJSONArray.Create); Settings.AddPair('expressions', TJSONObject.Create);
  Settings.AddPair('gaze', TJSONObject.Create); Settings.AddPair('nonFront', TJSONArray.Create);
end;
destructor TPsdCharacter.Destroy;
begin Assets.Free; Production.Free; Settings.Free; Document.Free; inherited; end;
procedure TPsdCharacter.RequireManaged;
begin if Policy <> 'managed' then raise Exception.Create('外部PSDは画像追加・加工・構造変更を許可しません。'); end;
function TPsdCharacter.Front: TArtLayer;
begin Result := Document.FindLayer(S(Settings, 'frontId')); end;
function TPsdCharacter.NonFront: TArtLayer;
begin Result := Document.FindLayer(S(Settings, 'nonFrontId')); end;
function TPsdCharacter.Group(const GroupId: string): TJSONObject;
begin
  for var V in Arr(Settings, 'groups') do
    if S(TJSONObject(V), 'id') = GroupId then Exit(TJSONObject(V));
  raise Exception.Create('Unknown group: ' + GroupId);
end;
procedure TPsdCharacter.CheckChoice(const GroupId, PartId: string);
begin
  var G := Group(GroupId); var L := Document.FindLayer(PartId);
  if (L = nil) or (L.Kind <> alkImage) then raise Exception.Create('Unknown image layer');
  for var V in Arr(G, 'partIds') do if V.Value = PartId then Exit;
  raise Exception.Create('Part is outside exclusive group');
end;
procedure TPsdCharacter.SetDefault(const GroupId, PartId: string);
begin
  CheckChoice(GroupId, PartId); var G := Group(GroupId);
  Put(G, 'defaultPartId', PartId);
  for var V in Arr(G, 'partIds') do Document.FindLayer(V.Value).Visible := V.Value = PartId;
end;
procedure TPsdCharacter.Validate;
begin
  if (Id = '') or (Name = '') or ((Policy <> 'managed') and (Policy <> 'external')) then raise Exception.Create('Invalid character identity/policy');
  PixelByteCount(Document.Width, Document.Height, 4);
  if (Document.Width < 1) or (Document.Height < 1) then raise Exception.Create('Empty canvas');
  if Policy = 'managed' then
    if (Front = nil) or (NonFront = nil) or (Front.Kind <> alkGroup) or (NonFront.Kind <> alkGroup) then
      raise Exception.Create('正面/非正面の枝が必要です。');
  var AssetBytes: Int64 := 0;
  for var Pair in Assets do begin
    Inc(AssetBytes, Length(Pair.Value));
    if (AssetBytes > 256 * 1024 * 1024) or not Pair.Key.StartsWith('motions/') or (Pos('..', Pair.Key) > 0) or
      (Pos('\', Pair.Key) > 0) or (Pos(':', Pair.Key) > 0) then raise Exception.Create('Motion package asset limit/path');
  end;
  var Seen := TDictionary<string, Boolean>.Create;
  try
    for var V in Arr(Settings, 'groups') do begin
      var G := TJSONObject(V); var GroupId := S(G, 'id');
      if Seen.ContainsKey(GroupId) then raise Exception.Create('Duplicate group ID'); Seen.Add(GroupId, True);
      var L := Document.FindLayer(GroupId);
      if (L = nil) or (L.Kind <> alkGroup) then raise Exception.Create('Missing PSD group');
      var Parts := Arr(G, 'partIds'); if Parts.Count = 0 then raise Exception.Create('Empty selection group');
      for var P in Parts do begin
        CheckChoice(GroupId, P.Value);
        if not L.Children.Contains(Document.FindLayer(P.Value)) then raise Exception.Create('PSD group membership mismatch');
      end;
      CheckChoice(GroupId, S(G, 'defaultPartId'));
    end;
    for var Pair in Obj(Settings, 'expressions') do begin
      for var V in Arr(TJSONObject(Pair.JsonValue), 'variants') do
        CheckChoice(S(TJSONObject(V), 'groupId'), S(TJSONObject(V), 'partId'));
    end;
    if Settings.GetValue('animation') <> nil then begin
      var A := Obj(Settings, 'animation'); var Blink := Obj(A, 'blink'); var Lip := Obj(A, 'lipSync');
      for var Key in ['normalPartId', 'halfOpenPartId', 'closedPartId'] do CheckChoice(S(Blink, 'groupId'), S(Blink, Key));
      for var Pair in Obj(Lip, 'phonemePartIds') do CheckChoice(S(Lip, 'groupId'), Pair.JsonValue.Value);
      for var Pair in Obj(Settings, 'gaze') do CheckChoice(S(Blink, 'groupId'), Pair.JsonValue.Value);
    end;
    for var V in Arr(Settings, 'nonFront') do begin
      var O := TJSONObject(V); var Kind := S(O, 'kind');
      if Kind = 'pose' then begin
        var L := Document.FindLayer(S(O, 'layerId'));
        if (L = nil) or not NonFront.Children.Contains(L) then raise Exception.Create('Missing non-front pose');
      end else if Kind = 'sequence' then begin
        if (N(O, 'fps') <= 0) or (N(O, 'fps') > 120) or (Arr(O, 'frames').Count = 0) then raise Exception.Create('Invalid sequence timing');
        for var F in Arr(O, 'frames') do if not Assets.ContainsKey(F.Value) then raise Exception.Create('Missing sequence frame');
      end else raise Exception.Create('Invalid non-front kind');
    end;
  finally Seen.Free; end;
end;
end.
