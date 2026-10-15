unit RigmDotsTransport;

// 成功したDots試験のJSONL輸送。作品モデルは参照せず、要求処理はメインスレッドへ渡す。
interface

uses Winapi.Windows, System.Classes, System.SysUtils;

const RigmDotsMaxFrameBytes = 8 * 1024 * 1024;

type
  TRigmDotsRequest = function(const Request: string): string of object;
  TRigmDotsTransport = class(TThread)
  private
    FPipe, FStop: THandle;
    FName: string;
    FOwnerSid: string;
    FAllowAppContainer: Boolean;
    FRequest: TRigmDotsRequest;
    FError: string;
    function FinishIO(var Operation: TOverlapped; Immediate: Boolean): DWORD;
    procedure Serve;
    procedure CheckClientUser;
  protected
    procedure Execute; override;
  public
    constructor Create(const Name: string; Handler: TRigmDotsRequest; AllowAppContainer: Boolean = False);
    destructor Destroy; override;
    procedure Stop;
    property ErrorText: string read FError;
  end;

implementation

function ConvertStringSecurityDescriptorToSecurityDescriptorW(Text: PWideChar;
  Revision: DWORD; out Descriptor: Pointer; Size: Pointer): BOOL; stdcall;
  external 'advapi32.dll';
function ConvertSidToStringSidW(Sid: Pointer; out Text: PWideChar): BOOL; stdcall;
  external 'advapi32.dll';

function TokenUserSid(Token: THandle): string;
var Size: DWORD; Bytes: TBytes; Sid: PWideChar;
begin
  Size := 0;
  GetTokenInformation(Token, TokenUser, nil, 0, Size);
  if Size = 0 then RaiseLastOSError;
  SetLength(Bytes, Size);
  if not GetTokenInformation(Token, TokenUser, @Bytes[0], Size, Size) then RaiseLastOSError;
  if not ConvertSidToStringSidW(PTokenUser(@Bytes[0]).User.Sid, Sid) then RaiseLastOSError;
  try Result := string(Sid); finally LocalFree(HLOCAL(Sid)); end;
end;

function UserDescriptor(AllowAppContainer: Boolean; out OwnerSid: string): Pointer;
var Token: THandle; Sddl: string;
begin
  Result := nil;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then RaiseLastOSError;
  try
    OwnerSid := TokenUserSid(Token);
    Sddl := 'D:P(A;;GA;;;' + OwnerSid + ')';
    if AllowAppContainer then
      // Package groups accommodate per-run container SIDs. No Everyone grant.
      Sddl := Sddl + '(A;;GRGW;;;S-1-15-2-1)(A;;GRGW;;;S-1-15-2-2)S:(ML;;NW;;;LW)';
    if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PWideChar(Sddl), 1, Result, nil) then RaiseLastOSError;
  finally CloseHandle(Token); end;
end;

constructor TRigmDotsTransport.Create(const Name: string; Handler: TRigmDotsRequest; AllowAppContainer: Boolean);
var Security: TSecurityAttributes; Descriptor: Pointer;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPipe := INVALID_HANDLE_VALUE;
  FName := Name; FRequest := Handler; FAllowAppContainer := AllowAppContainer;
  FStop := CreateEvent(nil, True, False, nil);
  if FStop = 0 then RaiseLastOSError;
  Descriptor := UserDescriptor(AllowAppContainer, FOwnerSid);
  try
    ZeroMemory(@Security, SizeOf(Security));
    Security.nLength := SizeOf(Security); Security.lpSecurityDescriptor := Descriptor;
    FPipe := CreateNamedPipe(PChar('\\.\pipe\' + FName),
      PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED or FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or $00000008,
      1, 65536, 65536, 0, @Security); // PIPE_REJECT_REMOTE_CLIENTS
    if FPipe = INVALID_HANDLE_VALUE then RaiseLastOSError;
  finally LocalFree(HLOCAL(Descriptor)); end;
end;

procedure TRigmDotsTransport.CheckClientUser;
var Token: THandle; ClientSid: string;
begin
  if not FAllowAppContainer then Exit;
  // Read first: impersonation identifies the sender of the bytes just received.
  if not ImpersonateNamedPipeClient(FPipe) then RaiseLastOSError;
  try
    if not OpenThreadToken(GetCurrentThread, TOKEN_QUERY, True, Token) then RaiseLastOSError;
    try ClientSid := TokenUserSid(Token); finally CloseHandle(Token); end;
  finally
    if not RevertToSelf then begin
      // Never continue the listener or invoke the UI under a client identity.
      Terminate;
      RaiseLastOSError;
    end;
  end;
  if ClientSid <> FOwnerSid then raise Exception.Create('client_user_mismatch');
end;

procedure TRigmDotsTransport.Stop;
begin
  Terminate;
  if FStop <> 0 then SetEvent(FStop);
end;

destructor TRigmDotsTransport.Destroy;
begin
  Stop;
  if Suspended then Start;
  WaitFor; // Delphi services queued Synchronize calls while the UI waits here.
  if FPipe <> INVALID_HANDLE_VALUE then CloseHandle(FPipe);
  if FStop <> 0 then CloseHandle(FStop);
  inherited;
end;

function TRigmDotsTransport.FinishIO(var Operation: TOverlapped; Immediate: Boolean): DWORD;
var Handles: array[0..1] of THandle; Error, WaitResult: DWORD;
begin
  if not Immediate then begin
    Error := GetLastError;
    if Error <> ERROR_IO_PENDING then RaiseLastOSError(Error);
    Handles[0] := FStop; Handles[1] := Operation.hEvent;
    WaitResult := WaitForMultipleObjects(2, @Handles[0], False, 15000);
    if WaitResult <> WAIT_OBJECT_0 + 1 then begin
      CancelIoEx(FPipe, @Operation);
      GetOverlappedResult(FPipe, Operation, Result, True);
      if Terminated then raise EAbort.Create('Stopped');
      raise Exception.Create('Pipe I/O timeout');
    end;
  end;
  if not GetOverlappedResult(FPipe, Operation, Result, False) then RaiseLastOSError;
end;

procedure TRigmDotsTransport.Serve;
var Operation: TOverlapped; Buffer: array[0..16383] of Byte;
  Incoming: TBytes; Count, Written: DWORD; Position, OldSize: Integer;
  RequestText, ResponseText: string; Reply: TBytes; Offset: Integer;
begin
  ZeroMemory(@Operation, SizeOf(Operation));
  Operation.hEvent := CreateEvent(nil, True, False, nil);
  if Operation.hEvent = 0 then RaiseLastOSError;
  try
    // Connect has no idle timeout; Stop always wakes it.
    if not ConnectNamedPipe(FPipe, @Operation) then begin
      var Error := GetLastError;
      if Error = ERROR_IO_PENDING then begin
        var Handles: array[0..1] of THandle;
        Handles[0] := FStop; Handles[1] := Operation.hEvent;
        if WaitForMultipleObjects(2, @Handles[0], False, INFINITE) <> WAIT_OBJECT_0 + 1 then begin
          CancelIoEx(FPipe, @Operation);
          GetOverlappedResult(FPipe, Operation, Count, True);
          Exit;
        end;
        if not GetOverlappedResult(FPipe, Operation, Count, False) then RaiseLastOSError;
      end else if Error <> ERROR_PIPE_CONNECTED then RaiseLastOSError(Error);
    end;
    Incoming := nil;
    repeat
      ResetEvent(Operation.hEvent);
      Count := FinishIO(Operation, ReadFile(FPipe, Buffer[0], SizeOf(Buffer), Count, @Operation));
      if Count = 0 then Exit;
      OldSize := Length(Incoming);
      if OldSize + Integer(Count) > RigmDotsMaxFrameBytes then raise Exception.Create('Frame too large');
      SetLength(Incoming, OldSize + Integer(Count));
      Move(Buffer[0], Incoming[OldSize], Count);
      Position := OldSize;
      while (Position < Length(Incoming)) and (Incoming[Position] <> 10) do Inc(Position);
    until Position < Length(Incoming);
    CheckClientUser;
    RequestText := TEncoding.UTF8.GetString(Incoming, 0, Position);
    ResponseText := '';
    Synchronize(procedure begin
      if not Terminated then ResponseText := FRequest(RequestText);
    end);
    if Terminated then Exit;
    Reply := TEncoding.UTF8.GetBytes(ResponseText + #10);
    if Length(Reply) > RigmDotsMaxFrameBytes then raise Exception.Create('Response too large');
    Offset := 0;
    while Offset < Length(Reply) do begin
      ResetEvent(Operation.hEvent);
      Written := FinishIO(Operation, WriteFile(FPipe, Reply[Offset], Length(Reply)-Offset, Written, @Operation));
      if Written = 0 then Exit;
      Inc(Offset, Integer(Written));
    end;
    // Keep the response buffered until the client acknowledges receipt by closing.
    // Avoid FlushFileBuffers: an unresponsive reader must not block shutdown.
    ResetEvent(Operation.hEvent);
    FinishIO(Operation, ReadFile(FPipe, Buffer[0], 1, Count, @Operation));
  finally CloseHandle(Operation.hEvent); end;
end;

procedure TRigmDotsTransport.Execute;
begin
  while not Terminated do begin
    try Serve;
    except on E: Exception do begin
      // Connection errors are confined to this client; the listener remains usable.
      TMonitor.Enter(Self); try FError := E.Message; finally TMonitor.Exit(Self); end;
    end; end;
    DisconnectNamedPipe(FPipe);
  end;
end;

end.
