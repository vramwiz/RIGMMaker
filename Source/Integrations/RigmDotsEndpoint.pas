unit RigmDotsEndpoint;

// DotsのJSONLと既存Workspace命令の境界。認証・再送・画像一時配置を所有する。
interface
uses System.SysUtils, System.JSON, System.Generics.Collections, ArtPipeProtocol,
  RigmDotsTransport, RigmDotsImages;
type
  TRigmDotsEndpoint = class
  private
    FTransport: TRigmDotsTransport;
    FHandler: TArtCommandHandler;
    FImages: TRigmDotsImages;
    FName,FToken,FRoot,FConnection,FRunDirectory: string;
    FRequests,FReplies: TDictionary<string,string>;
    FOrder: TQueue<string>;
    FCacheChars: Integer;
    FHandling: Boolean;
    function Receive(const Request: string): string;
    function Execute(const Command: string; Args: TJSONObject): TJSONObject;
  public
    constructor Create(const Root: string; Handler: TArtCommandHandler);
    destructor Destroy; override;
    function Info: TJSONObject; // 接続トークンは含めない。ファイルにだけ保存。
    property ConnectionFile: string read FConnection;
  end;
implementation
uses System.IOUtils, System.Hash, Winapi.Windows, RigmCommunication;
function TextOf(O: TJSONObject; const Key: string): string;
begin Result := ''; if O.GetValue(Key) is TJSONString then Result := O.GetValue(Key).Value; end;
procedure ValidateObject(Value: TJSONValue; Depth: Integer);
var Names: TDictionary<string,Boolean>;
begin
  if Depth>32 then raise Exception.Create('nesting_limit');
  if Value is TJSONObject then begin
    Names := TDictionary<string,Boolean>.Create;
    try
      for var Pair in TJSONObject(Value) do begin
        if Names.ContainsKey(Pair.JsonString.Value) then raise Exception.Create('duplicate_field');
        Names.Add(Pair.JsonString.Value,True); ValidateObject(Pair.JsonValue,Depth+1);
      end;
    finally Names.Free; end;
  end else if Value is TJSONArray then for var Item in TJSONArray(Value) do ValidateObject(Item,Depth+1);
end;
constructor TRigmDotsEndpoint.Create(const Root: string; Handler: TArtCommandHandler);
var Discovery: TJSONObject; Id: string;
begin
  inherited Create;
  if RigmCommunicationMode<>rcDots then raise Exception.Create('Dots mode is not selected');
  FHandler := Handler; FRoot := TPath.GetFullPath(Root);
  Id := TGUID.NewGuid.ToString.Replace('{','').Replace('}','');
  FToken := Id.Replace('-','')+TGUID.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','');
  FName := 'RIGMMaker.Dots.'+GetCurrentProcessId.ToString+'.'+Id;
  FConnection := TPath.Combine(FRoot,'Exchange\dots-'+GetCurrentProcessId.ToString+'-'+Id+'.json');
  FRunDirectory := TPath.Combine(FRoot,'Exchange\Dots\'+Id);
  ForceDirectories(FRunDirectory);
  FRequests := TDictionary<string,string>.Create; FReplies := TDictionary<string,string>.Create;
  FOrder := TQueue<string>.Create;
  FImages := TRigmDotsImages.Create(TPath.Combine(FRunDirectory,'Images'));
  FTransport := TRigmDotsTransport.Create(FName,Receive,True);
  Discovery := Info;
  try
    Discovery.AddPair('accessToken',FToken);
    TFile.WriteAllText(FConnection+'.tmp',Discovery.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(FConnection+'.tmp'),PChar(FConnection),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally Discovery.Free; end;
  FTransport.Start;
end;
destructor TRigmDotsEndpoint.Destroy;
begin
  FreeAndNil(FTransport);
  if (FConnection<>'') and FileExists(FConnection) then TFile.Delete(FConnection);
  FImages.Free; FRequests.Free; FReplies.Free; FOrder.Free;
  inherited;
end;
function TRigmDotsEndpoint.Info: TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('format','RIGMMaker.DotsConnection')
    .AddPair('protocol','rigm-maker-dots/1').AddPair('version',TJSONNumber.Create(1))
    .AddPair('communicationMode','dots').AddPair('accessMode','appcontainer-test')
    .AddPair('requiresAccessToken',TJSONBool.Create(True))
    .AddPair('pid',TJSONNumber.Create(GetCurrentProcessId)).AddPair('processId',TJSONNumber.Create(GetCurrentProcessId))
    .AddPair('pipeName',FName).AddPair('commandPipe',FName).AddPair('connectionFile',FConnection)
    .AddPair('transport','windows-named-pipe-jsonl').AddPair('encoding','utf-8')
    .AddPair('maxFrameBytes',TJSONNumber.Create(RigmDotsMaxFrameBytes)).AddPair('dataRoot',FRoot)
    .AddPair('routing','common-command').AddPair('codexPipeEnabled',TJSONBool.Create(False));
end;
function TRigmDotsEndpoint.Execute(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command='ping' then Exit(TJSONObject.Create.AddPair('message','pong').AddPair('communicationMode','dots'));
  if Command='echo' then begin
    if not (Args.GetValue('text') is TJSONString) then raise Exception.Create('invalid_text');
    Exit(TJSONObject.Create.AddPair('text',TextOf(Args,'text')));
  end;
  if Command='image.put' then Exit(FImages.PutImage(Args));
  if Command='image.get' then Exit(FImages.GetImage(Args));
  Result := FHandler(Command,Args);
end;
function TRigmDotsEndpoint.Receive(const Request: string): string;
var Parsed: TJSONValue; Value,Reply,Data: TJSONObject; Id,Command,Key,Previous: string;
  procedure CacheReply;
  begin
    if (Id='') or (Key='') or FRequests.ContainsKey(Id) then Exit;
    while (FOrder.Count>0) and ((FOrder.Count>=256) or (FCacheChars+Length(Result)>16*1024*1024)) do begin
      var Old := FOrder.Dequeue;
      Dec(FCacheChars,Length(FReplies[Old])); FRequests.Remove(Old); FReplies.Remove(Old);
    end;
    FRequests.Add(Id,Key); FReplies.Add(Id,Result); FOrder.Enqueue(Id); Inc(FCacheChars,Length(Result));
  end;
begin
  Id := ''; Key := ''; Command := ''; Parsed := nil; Reply := nil;
  try
    try
      Parsed := TJSONObject.ParseJSONValue(Request);
      if not (Parsed is TJSONObject) then raise Exception.Create('invalid_json');
      ValidateObject(Parsed,0); Value := TJSONObject(Parsed); Id := TextOf(Value,'id');
      if TextOf(Value,'accessToken')<>FToken then raise Exception.Create('unauthorized');
      if RigmCommunicationMode<>rcDots then raise Exception.Create('communication_mode_mismatch');
      if FHandling then raise Exception.Create('communication_busy');
      if not (Value.GetValue('version') is TJSONNumber) or (Value.GetValue('version').Value<>'1') then raise Exception.Create('invalid_version');
      if (Id='') or (Length(Id)>128) then raise Exception.Create('invalid_id');
      if not (Value.GetValue('args') is TJSONObject) then raise Exception.Create('invalid_args');
      Command := TextOf(Value,'command');
      if (Command='') or (Length(Command)>128) then raise Exception.Create('invalid_command');
      Value.RemovePair('accessToken').Free; Key := THashSHA2.GetHashString(Value.ToJSON);
      if FRequests.TryGetValue(Id,Previous) then begin
        if Key<>Previous then raise Exception.Create('id_conflict');
        Exit(FReplies[Id]);
      end;
      FHandling := True;
      try Data := Execute(Command,TJSONObject(Value.GetValue('args'))); finally FHandling := False; end;
      Reply := TJSONObject.Create.AddPair('version',TJSONNumber.Create(1)).AddPair('id',Id)
        .AddPair('ok',TJSONBool.Create(True)).AddPair('data',Data);
      if Length(TEncoding.UTF8.GetBytes(Reply.ToJSON))>=RigmDotsMaxFrameBytes then raise Exception.Create('response_limit');
    except on E: Exception do begin
      FreeAndNil(Reply);
      Reply := TJSONObject.Create.AddPair('version',TJSONNumber.Create(1)).AddPair('id',Id)
        .AddPair('ok',TJSONBool.Create(False)).AddPair('error',TJSONObject.Create
          .AddPair('code',E.Message.Split([':',' '])[0]).AddPair('message',E.Message));
    end; end;
    Result := Reply.ToJSON; CacheReply;
    TFile.AppendAllText(TPath.Combine(FRunDirectory,'pipe.log'),FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)
      +' id='+Id.Replace(#13,'').Replace(#10,'')+' command='+Command.Replace(#13,'').Replace(#10,'')
      +' ok='+Reply.GetValue('ok').Value+sLineBreak,TEncoding.UTF8);
  finally Parsed.Free; Reply.Free; end;
end;
end.
