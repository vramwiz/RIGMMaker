unit RigmCharacterCatalog;

// 共通一覧から形式を判別し、PSDの所有モデル/描画器へ委譲する。原画像は変更しない。
interface
uses System.SysUtils, System.JSON, PsdWorkspace, PsdCharacter, PsdAnimation;
type
  TPsdCharacterAsset = class
  public
    Workspace: TPsdWorkspace; Character: TPsdCharacter; Renderer: TPsdRenderer; // 所有。
    constructor Create(const Path: string; MaxHeight: Integer = 960);
    destructor Destroy; override;
    function Expressions: TJSONObject; // 呼出側所有。共通台本の感情IDへの別名を含む。
  end;
function CharacterFormat(const Path: string): string;
function CharacterFormatLabel(const Path: string): string;
function CharacterDataRoot(const Path: string): string;
function ReadCharacterThumbnail(const Path: string; out Name: string; out Width,Height: Integer): TBytes;
function ReadPsdActorAssets(const Path: string): TJSONObject;
function CharacterReadyForNewScript(const Path: string; out Reason: string): Boolean;
implementation
uses System.IOUtils, PsdPackage, PsdJson, PsdProduction, RigmStorage, RigmAppSettings;
function CharacterFormat(const Path: string): string;
begin if SameText(ExtractFileExt(Path), '.psdchar') then Result := 'psd' else Result := 'rigm'; end;
function CharacterFormatLabel(const Path: string): string;
begin if CharacterFormat(Path)='psd' then Result := 'PSD' else Result := 'RIGM'; end;
function CharacterReadyForNewScript(const Path: string; out Reason: string): Boolean;
begin
  Reason := ''; if CharacterFormat(Path)<>'psd' then Exit(True);
  Result := False; var W := TPsdWorkspace.Create(CharacterDataRoot(Path)); var C: TPsdCharacter := nil;
  try
    try W.Initialize; C := LoadCharacter(W,ExpandFileName(Path)); Result := PsdReadyForScript(C,Reason);
    except on E: Exception do Reason := 'PSDを検査できません: '+E.Message; end;
  finally C.Free; W.Free; end;
end;
function CharacterDataRoot(const Path: string): string;
begin
  var Root := ExcludeTrailingPathDelimiter(ExpandFileName(RigmDocumentsDirectory));
  if ExpandFileName(Path).StartsWith(IncludeTrailingPathDelimiter(Root),True) then Exit(Root);
  // 隔離検証や外部パッケージは、そのフォルダだけに作業領域を限定する。
  Result := ExtractFileDir(ExpandFileName(Path));
  if SameText(ExtractFileName(Result),'Characters') then Result := ExtractFileDir(Result);
end;
constructor TPsdCharacterAsset.Create(const Path: string; MaxHeight: Integer);
begin
  inherited Create; Workspace := TPsdWorkspace.Create(CharacterDataRoot(Path)); Workspace.Initialize;
  Character := LoadCharacter(Workspace,ExpandFileName(Path)); Renderer := TPsdRenderer.Create(Character,Workspace,MaxHeight);
end;
destructor TPsdCharacterAsset.Destroy;
begin Renderer.Free; Character.Free; Workspace.Free; inherited; end;
function TPsdCharacterAsset.Expressions: TJSONObject;
const Keys: array[0..9] of string = ('neutral','happy','joy','angry','sad','surprised','doubt','confused','serious','gentle');
      Names: array[0..9] of string = ('通常','喜び','喜び','怒り','哀しみ','驚き','疑問','困惑','解説','通常');
begin
  Result := TJSONObject.Create;
  for var Index := 0 to High(Keys) do begin
    var P := Obj(Character.Settings,'expressions').GetValue(Names[Index]); if P=nil then Continue;
    var O := TJSONObject(P.Clone); O.AddPair('psdExpression',Names[Index]); Result.AddPair(Keys[Index],O);
  end;
end;
function ReadCharacterThumbnail(const Path: string; out Name: string; out Width,Height: Integer): TBytes;
begin
  if CharacterFormat(Path)<>'psd' then Exit(ReadRigmThumbnail(Path,Name,Width,Height));
  var Asset := TPsdCharacterAsset.Create(Path,240);
  try
    Name := Asset.Character.Name; var State := TPsdFrameState.Default; State.AutoBlink := False; State.Motion := 'none';
    Result := Asset.Renderer.Composite(State); Width := Asset.Renderer.Document.Width; Height := Asset.Renderer.Document.Height;
  finally Asset.Free; end;
end;
function ReadPsdActorAssets(const Path: string): TJSONObject;
begin
  var Asset := TPsdCharacterAsset.Create(Path,240);
  try
    Result := TJSONObject.Create; Result.AddPair('documentId',Asset.Character.Id); Result.AddPair('name',Asset.Character.Name); Result.AddPair('renderFormat','psd');
    var Groups := TJSONArray.Create; Result.AddPair('groups',Groups); Result.AddPair('parameters',TJSONArray.Create);
    for var V in Arr(Asset.Character.Settings,'groups') do begin
      var G := TJSONObject(V); var O := TJSONObject.Create; Groups.AddElement(O); O.AddPair('id',S(G,'id')); O.AddPair('name',S(G,'name'));
      var Parts := TJSONArray.Create; O.AddPair('children',Parts);
      for var P in Arr(G,'partIds') do begin
        var L := Asset.Character.Document.FindLayer(P.Value); var Item := TJSONObject.Create; Parts.AddElement(Item);
        Item.AddPair('id',L.Id); Item.AddPair('name',L.Name); Item.AddPair('role',''); Item.AddPair('kind','image'); Item.AddPair('visible',TJSONBool.Create(L.Visible));
      end;
    end;
    var Caps := TJSONObject.Create; Result.AddPair('capabilities',Caps);
    Caps.AddPair('headBodyMotion',TJSONBool.Create(True)); Caps.AddPair('mouthAssets',TJSONBool.Create(Asset.Character.Settings.GetValue('animation')<>nil));
    Caps.AddPair('blinkAssets',TJSONBool.Create(Asset.Character.Settings.GetValue('animation')<>nil)); Caps.AddPair('naturalFaceDirections',TJSONBool.Create(False));
    Caps.AddPair('smallMotionMethod','post-composite'); Caps.AddPair('safeMouthMode','auto'); Caps.AddPair('safeBlinkMode','auto');
  finally Asset.Free; end;
end;
end.
