unit PsdSession;

// GUIと専用パイプが共有する独立編集セッション。版検査と置換による失敗時保全を担当。
interface
uses System.SysUtils, System.Classes, System.JSON, PsdWorkspace, PsdCharacter,
  PsdAnimation, PsdPipe, ArtPipeProtocol;

type
  TPsdSession = class
  private
    FWorkspace: TPsdWorkspace; FCharacter: TPsdCharacter; FRenderer: TPsdRenderer;
    FTrack: TPsdPhonemeTrack; FState: TPsdFrameState; FId, FPath, FPipeName, FConnection: string;
    FRevision: UInt64; FDirty: Boolean; FEndpoint: TPsdPipeEndpoint; FProtocol: TArtPipeProtocol;
    FCompletedEditSession: Boolean; // 完成済み編集を開始した後は、再検査前も明示保存を維持する。
    FOnChanged: TNotifyEvent;
    procedure Receive(const Request: string; out Response: string);
    procedure CheckRevision(Args: TJSONObject);
    procedure Adopt(Character: TPsdCharacter; const Path: string; Dirty: Boolean; ResetView: Boolean = True);
    function CopyCharacter: TPsdCharacter;
    procedure Changed;
  public
    constructor Create(const Root: string; StartPipe: Boolean = True);
    destructor Destroy; override;
    function Status: TJSONObject; // 呼び出し側所有。
    function Command(const Name: string; Args: TJSONObject): TJSONObject;
    function Frame(Seconds: Double; Width: Integer = 1920; Height: Integer = 1080): TBytes;
    procedure SetView(const State: TPsdFrameState);
    property Character: TPsdCharacter read FCharacter; // 借用。
    property Workspace: TPsdWorkspace read FWorkspace;
    property State: TPsdFrameState read FState;
    property Dirty: Boolean read FDirty;
    property CompletedEditSession: Boolean read FCompletedEditSession;
    property SavedPath: string read FPath;
    property ConnectionFile: string read FConnection;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation
uses System.IOUtils, Winapi.Windows, ArtDocument, ArtPng, PsdJson, PsdImport, PsdPackage, PsdProduction;

constructor TPsdSession.Create(const Root: string; StartPipe: Boolean);
begin
  inherited Create; FId := NewId; FState := TPsdFrameState.Default;
  FWorkspace := TPsdWorkspace.Create(Root); FWorkspace.Initialize; FTrack := TPsdPhonemeTrack.Create;
  if StartPipe then begin
    FPipeName := 'RIGMMaker.Psd.' + GetCurrentProcessId.ToString + '.' + FId;
    FConnection := FWorkspace.Resolve('Exchange\psd-' + GetCurrentProcessId.ToString + '-' + FId + '.json', False);
    FProtocol := TArtPipeProtocol.Create(Command); FEndpoint := TPsdPipeEndpoint.Create(FPipeName, Receive);
    var O := TJSONObject.Create;
    try
      O.AddPair('format', 'RIGMMaker.PsdConnection'); O.AddPair('schemaVersion', TJSONNumber.Create(1));
      O.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId)); O.AddPair('commandPipe', FPipeName);
      O.AddPair('dataRoot', FWorkspace.Root); O.AddPair('sessionId', FId);
      TFile.WriteAllText(FConnection, O.ToJSON, TEncoding.UTF8);
    finally O.Free; end;
  end;
end;
destructor TPsdSession.Destroy;
begin
  FEndpoint.Free; FProtocol.Free;
  if (FConnection <> '') and FileExists(FConnection) then begin
    try
      var Job := FWorkspace.BeginJob;
      try MoveFile(PChar(FConnection), PChar(Job.FilePath('closed-connection.json'))); finally Job.Free; end;
    except end;
  end;
  FTrack.Free; FRenderer.Free; FCharacter.Free; FWorkspace.Free; inherited;
end;
procedure TPsdSession.Receive(const Request: string; out Response: string);
begin FProtocol.Handle(Request, Response); end;
procedure TPsdSession.CheckRevision(Args: TJSONObject);
begin
  var Revision: UInt64;
  if (S(Args, 'sessionId') <> FId) or not TryStrToUInt64(S(Args, 'revision'), Revision) or (Revision <> FRevision) then
    raise Exception.Create('statusから現在のsessionId/revisionを指定してください。');
end;
procedure TPsdSession.Changed;
begin Inc(FRevision); if Assigned(FOnChanged) then FOnChanged(Self); end;
procedure TPsdSession.Adopt(Character: TPsdCharacter; const Path: string; Dirty, ResetView: Boolean);
begin
  var Renderer := TPsdRenderer.Create(Character, FWorkspace);
  FRenderer.Free; FCharacter.Free; FCharacter := Character; FRenderer := Renderer;
  FPath := Path; FDirty := Dirty;
  if ResetView then begin FState := TPsdFrameState.Default; FTrack.Free; FTrack := TPsdPhonemeTrack.Create; end;
  Changed;
end;
function TPsdSession.CopyCharacter: TPsdCharacter;
begin
  Result := TPsdCharacter.Create;
  try
    Result.Id := FCharacter.Id; Result.Name := FCharacter.Name; Result.Policy := FCharacter.Policy; Result.Source := FCharacter.Source;
    Result.SupplementName := FCharacter.SupplementName;
    Result.Production.Free; Result.Production := TJSONObject(FCharacter.Production.Clone);
    var D := FCharacter.Document.Clone; Result.Document.Free; Result.Document := D;
    var Settings := TJSONObject(FCharacter.Settings.Clone); Result.Settings.Free; Result.Settings := Settings;
    for var Pair in FCharacter.Assets do Result.Assets.Add(Pair.Key, Pair.Value);
  except Result.Free; raise; end;
end;
function TPsdSession.Status: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('sessionId', FId); Result.AddPair('revision', FRevision.ToString); Result.AddPair('dirty', TJSONBool.Create(FDirty));
  Result.AddPair('dataRoot', FWorkspace.Root); Result.AddPair('savedPath', FPath); Result.AddPair('commandPipe', FPipeName);
  if FCharacter = nil then Exit;
  Result.AddPair('characterId', FCharacter.Id); Result.AddPair('name', FCharacter.Name); Result.AddPair('editPolicy', FCharacter.Policy);
  Result.AddPair('supplementName',FCharacter.SupplementName);
  var Reason: string; var Ready := PsdReadyForScript(FCharacter,Reason);
  Result.AddPair('readyForScript',TJSONBool.Create(Ready)); Result.AddPair('productionReason',Reason);
  Result.AddPair('production',TJSONValue(FCharacter.Production.Clone));
  Result.AddPair('width', TJSONNumber.Create(FCharacter.Document.Width)); Result.AddPair('height', TJSONNumber.Create(FCharacter.Document.Height));
  Result.AddPair('settings', TJSONValue(FCharacter.Settings.Clone));
end;
procedure TPsdSession.SetView(const State: TPsdFrameState);
begin
  if FCharacter = nil then raise Exception.Create('Open a character first');
  // キャッシュされた試験合成が成功した場合だけ表示状態を切替。
  FRenderer.Composite(State); FState := State; if Assigned(FOnChanged) then FOnChanged(Self);
end;
function TPsdSession.Frame(Seconds: Double; Width, Height: Integer): TBytes;
begin
  if FRenderer = nil then begin Result := nil; Exit; end;
  var V := FState; V.Seconds := Seconds;
  if FTrack.Available then begin V.HasPhoneme := True; V.Phoneme := FTrack.Sample(Seconds); end;
  Result := FRenderer.Frame(V, Width, Height);
end;
function TPsdSession.Command(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Name = 'status' then Exit(Status);
  if Name = 'document' then begin
    Result := Status; Exit;
  end;
  CheckRevision(Args);
  if (Name = 'open') or (Name = 'import-prepared') or (Name = 'import-psd') then begin
    if FDirty and not B(Args, 'discardChanges') then raise Exception.Create('未保存の変更を保存してください。');
    var C: TPsdCharacter; var Path := '';
    if Name = 'open' then begin Path := FWorkspace.Resolve(S(Args, 'path')); C := LoadCharacter(FWorkspace, Path); end
    else if Name = 'import-prepared' then C := ImportPrepared(FWorkspace, S(Args, 'path'))
    else C := ImportExternalPsd(FWorkspace, S(Args, 'path'));
    var Reason: string; var Completed := (Name='open') and PsdReadyForScript(C,Reason);
    try Adopt(C, Path, Name <> 'open'); FCompletedEditSession := Completed; C := nil; finally C.Free; end;
    Exit(Status);
  end;
  if FCharacter = nil then raise Exception.Create('Open a character first');
  if Name = 'save' then begin
    var Path := S(Args, 'path', FPath);
    if Path = '' then Path := 'Characters\' + FCharacter.Id + '.psdchar';
    Path := FWorkspace.Resolve(Path, False);
    if FDirty or (Path <> FPath) then SaveCharacter(FCharacter, FWorkspace, Path);
    FPath := Path; FDirty := False;
    var Reason: string; if PsdReadyForScript(FCharacter,Reason) then FCompletedEditSession := True;
    if Assigned(FOnChanged) then FOnChanged(Self); Exit(Status);
  end;
  if Name = 'export-psd' then begin ExportPsd(FCharacter, FWorkspace, S(Args, 'path')); Exit(Status); end;
  if Name = 'render-file' then begin
    var Path := FWorkspace.Resolve(S(Args, 'path'), False);
    if FileExists(Path) or not SameText(ExtractFileExt(Path), '.png') then raise Exception.Create('New PNG output required');
    var Pixels := Frame(N(Args, 'seconds')); ForceDirectories(ExtractFileDir(Path)); WriteRgbaPng(Path, 1920, 1080, Pixels);
    Result := TJSONObject.Create; Result.AddPair('path', Path); Exit;
  end;
  if Name = 'set-view' then begin
    var V := FState; V.Expression := S(Args, 'expression', V.Expression); V.Gaze := S(Args, 'gaze', V.Gaze);
    V.NonFrontId := S(Args, 'nonFrontId', V.NonFrontId); V.Motion := S(Args, 'motion', V.Motion);
    V.Phoneme := S(Args, 'phoneme', V.Phoneme); V.HasPhoneme := B(Args, 'hasPhoneme', V.HasPhoneme);
    V.AutoBlink := B(Args, 'autoBlink', V.AutoBlink); V.Strength := N(Args, 'strength', V.Strength);
    SetView(V); Exit(Status);
  end;
  if Name = 'load-lab' then begin FTrack.LoadLab(FWorkspace, S(Args, 'path')); Exit(Status); end;
  if Name = 'set-phonemes' then begin
    // 60KBを超える時刻情報もデータルートのJSONファイル参照で受信できる。
    if S(Args, 'path') <> '' then begin
      var V := Parse(FWorkspace.ReadText(S(Args, 'path')));
      try if not (V is TJSONArray) then raise Exception.Create('Phoneme array required'); FTrack.Load(TJSONArray(V)); finally V.Free; end;
    end else FTrack.Load(Arr(Args, 'events'));
    Exit(Status);
  end;
  if (Name <> 'add-layer-file') and (Name <> 'add-nonfront-file') and (Name <> 'select-part') and (Name <> 'set-expression') and
    (Name <> 'check-production') and (Name <> 'set-info') and (Name <> 'set-motion-reference') then
    raise Exception.Create('Unknown command: ' + Name);
  FCharacter.RequireManaged; var C := CopyCharacter;
  try
    if Name = 'add-layer-file' then AddFrontLayer(C, FWorkspace, Args)
    else if Name = 'add-nonfront-file' then AddNonFront(C, FWorkspace, Args)
    else if Name = 'select-part' then C.SetDefault(S(Args, 'groupId'), S(Args, 'partId'))
    else if Name = 'set-info' then begin
      C.Name := S(Args,'name',C.Name).Trim; C.SupplementName := S(Args,'supplementName',C.SupplementName).Trim;
      if (C.Name='') or (Length(C.Name)>128) or (Length(C.SupplementName)>128) then raise Exception.Create('キャラ名・補足名は128文字以内で指定してください。');
    end
    else if Name = 'set-motion-reference' then begin
      ValidateMotionReference(C,Obj(Args,'reference')); Put(C.Settings,'motionReference',TJSONValue(Obj(Args,'reference').Clone));
    end
    else if Name = 'check-production' then begin
      C.Production.Free; C.Production := nil; C.Production := CheckPsdProduction(C);
    end
    else begin
      if S(Args, 'name') = '' then raise Exception.Create('Expression name required');
      Put(Obj(C.Settings, 'expressions'), S(Args, 'name'), TJSONValue(Obj(Args, 'preset').Clone));
    end;
    if Name <> 'check-production' then begin
      C.Production.Free; C.Production := ObjectText('{"stage":"draft","checked":false}');
    end;
    C.Validate;
    // 制作中の編集は、検証・保存まで成功してから画面へ採用する。
    // 完成済み編集は従来どおり明示保存。完成を変更した時点で再検査を要求する。
    var Path := FPath;
    if not FCompletedEditSession then begin
      if Path='' then Path := FWorkspace.Resolve('Characters\'+C.Id+'\character.psdchar',False);
      SaveCharacter(C,FWorkspace,Path); Adopt(C,Path,False,False);
    end else Adopt(C,Path,True,False);
    var Reason: string; if not FDirty and PsdReadyForScript(C,Reason) then FCompletedEditSession := True;
    C := nil;
  finally C.Free; end;
  Result := Status;
end;
end.
