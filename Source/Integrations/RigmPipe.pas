unit RigmPipe;

interface
uses System.SysUtils, System.Classes, System.JSON, Winapi.Windows, Winapi.Messages,
  RigmModel, RigmEditor, ArtPipeProtocol;

type
  TRigmPipeRequest = procedure(const Request: string; out Response: string) of object;
  TRigmPipeWorker = class(TThread)
  private
    FName: string;
    FWindow: HWND;
    FResponseReady: THandle;
    FRequest, FResponse: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const Name: string; Window: HWND);
    destructor Destroy; override;
    procedure ReleaseWait;
  end;
  TRigmPipeEndpoint = class
  private
    FWorker: TRigmPipeWorker;
    FWindow: HWND;
    FOnRequest: TRigmPipeRequest;
    FOnSent: TNotifyEvent;
    FStopping: Boolean;
    procedure WindowProc(var Message: TMessage);
  public
    constructor Create(const Name: string; Handler: TRigmPipeRequest; OnSent: TNotifyEvent = nil);
    destructor Destroy; override;
  end;
  TRigmPipeHub = class
  private
    FEditor: TRigmEditor;
    FControl, FPage: TRigmPipeEndpoint;
    FControlProtocol, FPageProtocol: TArtPipeProtocol;
    FControlName, FPageName, FDirectory, FConnectionFile: string;
    FActivePage: TRigmPage;
    FEpoch: Cardinal;
    FHandlingPage, FPending: Boolean;
    procedure ControlRequest(const Request: string; out Response: string);
    procedure PageRequest(const Request: string; out Response: string);
    function ControlCommand(const Command: string; Args: TJSONObject): TJSONObject;
    function PageCommand(const Command: string; Args: TJSONObject): TJSONObject;
    procedure PageChanged(Sender: TObject);
    procedure PageSent(Sender: TObject);
    procedure CheckRevision(Args: TJSONObject);
    procedure WriteConnection;
  public
    constructor Create(Editor: TRigmEditor; const ConnectionDirectory: string);
    destructor Destroy; override;
    procedure Sync;
    function Info: TJSONObject;
    property ControlName: string read FControlName;
    property PagePipeName: string read FPageName;
    property ConnectionFile: string read FConnectionFile;
  end;

implementation
uses System.IOUtils, RigmJson;

const WM_RIGM_REQUEST = WM_USER + 171;
      WM_RIGM_SENT = WM_USER + 172;
      MAX_PIPE_BYTES = 60000;

constructor TRigmPipeWorker.Create(const Name: string; Window: HWND);
begin
  inherited Create(True); FName := Name; FWindow := Window;
  FResponseReady := CreateEvent(nil, False, False, nil); FreeOnTerminate := False;
end;

destructor TRigmPipeWorker.Destroy;
begin CloseHandle(FResponseReady); inherited; end;

procedure TRigmPipeWorker.ReleaseWait;
begin SetEvent(FResponseReady); end;

procedure TRigmPipeWorker.Execute;
var Pipe: THandle; Buffer, Reply: TBytes; ReadCount, Written, Mode: DWORD; Name: string;
begin
  Name := '\\.\pipe\' + FName; SetLength(Buffer, 65536);
  while not Terminated do begin
    Mode := PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT or $00000008;
    Pipe := CreateNamedPipe(PChar(Name), PIPE_ACCESS_DUPLEX, Mode, 1, 65536, 65536, 1000, nil);
    if Pipe = INVALID_HANDLE_VALUE then begin Sleep(20); Continue; end;
    try
      if not ConnectNamedPipe(Pipe, nil) and (GetLastError <> ERROR_PIPE_CONNECTED) then Continue;
      if not ReadFile(Pipe, Buffer[0], Length(Buffer), ReadCount, nil) or (ReadCount = 0) then Continue;
      if ReadCount > MAX_PIPE_BYTES then Continue;
      FRequest := TEncoding.UTF8.GetString(Buffer, 0, ReadCount); FResponse := '';
      ResetEvent(FResponseReady); PostMessage(FWindow, WM_RIGM_REQUEST, WPARAM(Self), 0);
      while not Terminated and (WaitForSingleObject(FResponseReady, 50) = WAIT_TIMEOUT) do ;
      if Terminated then Continue;
      Reply := TEncoding.UTF8.GetBytes(FResponse);
      if (Length(Reply) > 0) and WriteFile(Pipe, Reply[0], Length(Reply), Written, nil) then FlushFileBuffers(Pipe);
      PostMessage(FWindow, WM_RIGM_SENT, WPARAM(Self), 0);
    finally DisconnectNamedPipe(Pipe); CloseHandle(Pipe); end;
  end;
end;

constructor TRigmPipeEndpoint.Create(const Name: string; Handler: TRigmPipeRequest; OnSent: TNotifyEvent);
begin
  inherited Create; FOnRequest := Handler; FOnSent := OnSent; FWindow := AllocateHWnd(WindowProc);
  FWorker := TRigmPipeWorker.Create(Name, FWindow); FWorker.Start;
end;

destructor TRigmPipeEndpoint.Destroy;
var PendingMessage: TMsg;
begin
  FStopping := True;
  if FWorker <> nil then begin
    FWorker.Terminate; FWorker.ReleaseWait;
    while WaitForSingleObject(FWorker.Handle, 10) = WAIT_TIMEOUT do begin
      CancelSynchronousIo(FWorker.Handle); FWorker.ReleaseWait;
    end;
    FWorker.Free;
  end;
  if FWindow <> 0 then begin
    while PeekMessage(PendingMessage, FWindow, WM_RIGM_REQUEST, WM_RIGM_SENT, PM_REMOVE) do ;
    DeallocateHWnd(FWindow);
  end;
  inherited;
end;

procedure TRigmPipeEndpoint.WindowProc(var Message: TMessage);
begin
  if (Message.WParam = WPARAM(FWorker)) and (Message.Msg = WM_RIGM_REQUEST) then begin
    try
      if not FStopping then FOnRequest(FWorker.FRequest, FWorker.FResponse);
    finally FWorker.ReleaseWait; end;
    Message.Result := 0;
  end else if (Message.WParam = WPARAM(FWorker)) and (Message.Msg = WM_RIGM_SENT) then begin
    if not FStopping and Assigned(FOnSent) then FOnSent(Self); Message.Result := 0;
  end else Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;

constructor TRigmPipeHub.Create(Editor: TRigmEditor; const ConnectionDirectory: string);
begin
  inherited Create; FEditor := Editor; FDirectory := ConnectionDirectory;
  FControlName := 'RIGMMaker.' + IntToStr(GetCurrentProcessId) + '.' + NewRigmId + '.control';
  ForceDirectories(FDirectory); FConnectionFile := TPath.Combine(FDirectory, FControlName + '.json');
  FControlProtocol := TArtPipeProtocol.Create(ControlCommand); FPageProtocol := TArtPipeProtocol.Create(PageCommand);
  FControl := TRigmPipeEndpoint.Create(FControlName, ControlRequest);
  FEditor.OnPageChanged := PageChanged; Sync;
end;

destructor TRigmPipeHub.Destroy;
begin
  if FEditor <> nil then FEditor.OnPageChanged := nil;
  FPage.Free; FControl.Free; FPageProtocol.Free; FControlProtocol.Free;
  if FileExists(FConnectionFile) then TFile.Delete(FConnectionFile); inherited;
end;

procedure TRigmPipeHub.CheckRevision(Args: TJSONObject);
var Revision: UInt64;
begin
  if (JS(Args, 'documentId') <> FEditor.Document.FileId) or
    not TryStrToUInt64(JS(Args, 'revision'), Revision) or (Revision <> FEditor.Document.Art.Revision) then
    raise ERigm.Create('現在の文書ID・版をstatusから取得して指定してください。');
end;

function TRigmPipeHub.Info: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('controlPipe', FControlName);
  Result.AddPair('commandPipe', FControlName); Result.AddPair('routing', 'common-command'); AddN(Result, 'apiVersion', 2);
  if FActivePage = FEditor.Document.LastPage then Result.AddPair('pagePipe', FPageName)
  else Result.AddPair('pagePipe', '');
  Result.AddPair('page', PageName(FEditor.Document.LastPage)); AddN(Result, 'epoch', FEpoch);
  Result.AddPair('connectionFile', FConnectionFile);
end;

procedure TRigmPipeHub.WriteConnection;
var O: TJSONObject;
begin
  O := Info;
  try
    AddN(O, 'schemaVersion', 1); AddN(O, 'pid', GetCurrentProcessId);
    O.AddPair('documentId', FEditor.Document.FileId); O.AddPair('revision', FEditor.Document.Art.Revision.ToString);
    TFile.WriteAllText(FConnectionFile + '.tmp', O.ToJSON, TEncoding.UTF8);
    if not MoveFileEx(PChar(FConnectionFile + '.tmp'), PChar(FConnectionFile), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally O.Free; end;
end;

procedure TRigmPipeHub.Sync;
begin
  if FHandlingPage then begin FPending := True; Exit; end;
  FreeAndNil(FPage); Inc(FEpoch); FActivePage := FEditor.Document.LastPage; FPageName := '';
  if FActivePage <> rpPreview then begin
    FPageName := FControlName.Replace('.control', '.' + PageName(FActivePage) + '.' + IntToStr(FEpoch));
    FPage := TRigmPipeEndpoint.Create(FPageName, PageRequest, PageSent);
  end;
  FPending := False; WriteConnection;
end;

procedure TRigmPipeHub.PageChanged(Sender: TObject);
begin if FHandlingPage then FPending := True else Sync; end;

procedure TRigmPipeHub.PageSent(Sender: TObject);
begin if FPending then Sync; end;

function TRigmPipeHub.ControlCommand(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command.StartsWith('app-') then begin
    if not Assigned(FEditor.OnWorkspaceCommand) then raise ERigm.Create('Workspace pages are available in the main application');
    Result := FEditor.OnWorkspaceCommand(Command.Substring(4),Args); Result.AddPair('pipes',Info); Exit;
  end;
  if Command.StartsWith('movie-') then begin
    if (Command='movie-open-ui') or (Command='movie-play') then FEditor.RequestMovieUI;
    if Command='movie-open-ui' then begin Result := FEditor.Movie.Status; Result.AddPair('pipes',Info); Exit; end;
    Result := FEditor.Movie.Execute(Command.Substring(6),Args); Result.AddPair('pipes',Info); Exit;
  end;
  if (Command <> 'status') and (Command <> 'schema') and (Command <> 'document') and
    (Command <> 'validate') and (Command <> 'export') then begin
    CheckRevision(Args);
  end;
  Result := FEditor.Execute(Command, Args);
  if Command='schema' then begin
    var MovieArgs := TJSONObject.Create;
    try Result.AddPair('movie',FEditor.Movie.Execute('schema',MovieArgs)); finally MovieArgs.Free; end;
    Result.AddPair('movieCommandPrefix','movie-');
    if Assigned(FEditor.OnWorkspaceCommand) then begin
      Result.AddPair('workspaceCommandPrefix','app-');
      Result.AddPair('workspace',ParseObject('{"status":{},"switch-page":{"page":"preview|create|characters","propertyPage":"optional: dialogue|scene|acting|audio|diagnostics"},"library":{},"register-character":{"path":"existing .rigm or .psd; original preserved","name":"optional display name"},"open-work":{"path":".rigmovie; current unsaved work retained"}}'));
    end;
  end;
  Result.AddPair('pipes', Info); WriteConnection;
end;

function TRigmPipeHub.PageCommand(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if (FActivePage = rpPreview) or (FActivePage <> FEditor.Document.LastPage) then raise ERigm.Create('このページの接続は失効しています。');
  if not FEditor.IsAllowed(FActivePage, Command) then raise ERigm.Create('ページに適合しない命令です。');
  if (Command <> 'status') and (Command <> 'schema') and (Command <> 'document') and (Command <> 'validate') and (Command <> 'export') then CheckRevision(Args);
  Result := FEditor.Execute(Command, Args); Result.AddPair('pipes', Info); WriteConnection;
end;

procedure LimitReply(var Response: string);
var O, Error, Reply: TJSONObject;
begin
  if Length(TEncoding.UTF8.GetBytes(Response)) <= MAX_PIPE_BYTES then Exit;
  O := ParseObject(Response); Reply := TJSONObject.Create;
  try
    AddN(Reply, 'schemaVersion', 1); Reply.AddPair('requestId', JS(O, 'requestId')); AddB(Reply, 'ok', False);
    Error := TJSONObject.Create; Reply.AddPair('error', Error); Error.AddPair('code', 'response_limit');
    Error.AddPair('message', '応答が60KBを超えました。対象を絞ってください。'); Response := Reply.ToJSON;
  finally O.Free; Reply.Free; end;
end;

procedure TRigmPipeHub.ControlRequest(const Request: string; out Response: string);
begin FControlProtocol.Handle(Request, Response); LimitReply(Response); end;

procedure TRigmPipeHub.PageRequest(const Request: string; out Response: string);
begin
  FHandlingPage := True;
  try FPageProtocol.Handle(Request, Response); LimitReply(Response);
  finally FHandlingPage := False; end;
end;

end.
