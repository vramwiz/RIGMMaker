unit RigmWizardPipe;
interface
uses System.SysUtils, System.JSON, RigmPipe, ArtPipeProtocol, PsdWorkspace;
type
  TRigmWizardPipe = class
  private
    FEndpoint: TRigmPipeEndpoint; FProtocol: TArtPipeProtocol;
    FWorkspace: TPsdWorkspace; FName,FConnection: string;
    procedure Receive(const Request: string; out Response: string);
  public
    constructor Create(const Root: string; Handler: TArtCommandHandler);
    destructor Destroy; override;
    function Info: TJSONObject;
    property Workspace: TPsdWorkspace read FWorkspace;
  end;
implementation
uses System.Classes, System.IOUtils, Winapi.Windows, PsdJson;
constructor TRigmWizardPipe.Create(const Root: string; Handler: TArtCommandHandler);
begin
  inherited Create; FWorkspace := TPsdWorkspace.Create(Root); FWorkspace.Initialize;
  FName := 'RIGMMaker.Workspace.'+GetCurrentProcessId.ToString+'.'+NewId;
  FConnection := FWorkspace.Resolve('Exchange\workspace-'+GetCurrentProcessId.ToString+'.json',False);
  FProtocol := TArtPipeProtocol.Create(Handler); FEndpoint := TRigmPipeEndpoint.Create(FName,Receive);
  var O := Info;
  try TFile.WriteAllText(FConnection,O.ToJSON,TEncoding.UTF8); finally O.Free; end;
end;
destructor TRigmWizardPipe.Destroy;
begin
  FEndpoint.Free; FProtocol.Free;
  if (FWorkspace<>nil) and FileExists(FConnection) then begin
    var Job := FWorkspace.BeginJob;
    try
      if not MoveFile(PChar(FConnection),PChar(Job.FilePath('closed-workspace-connection.json'))) then RaiseLastOSError;
    finally Job.Free; end;
  end;
  FWorkspace.Free; inherited;
end;
procedure TRigmWizardPipe.Receive(const Request: string; out Response: string);
begin
  FProtocol.Handle(Request,Response);
  if Length(TEncoding.UTF8.GetBytes(Response))>60000 then begin
    var O := ObjectText(Response); var Reply := TJSONObject.Create;
    try
      Reply.AddPair('schemaVersion',TJSONNumber.Create(1)); Reply.AddPair('requestId',S(O,'requestId'));
      Reply.AddPair('ok',TJSONBool.Create(False));
      Reply.AddPair('error',ObjectText('{"code":"response_limit","message":"Response exceeds 60KB; request a smaller section."}'));
      Response := Reply.ToJSON;
    finally O.Free; Reply.Free; end;
  end;
end;
function TRigmWizardPipe.Info: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('format','RIGMMaker.WorkspaceConnection');
  Result.AddPair('schemaVersion',TJSONNumber.Create(1)); Result.AddPair('apiVersion',TJSONNumber.Create(2));
  Result.AddPair('pid',TJSONNumber.Create(GetCurrentProcessId)); Result.AddPair('commandPipe',FName);
  Result.AddPair('controlPipe',FName); Result.AddPair('dataRoot',FWorkspace.Root);
  Result.AddPair('connectionFile',FConnection); Result.AddPair('routing','common-command');
end;
end.
