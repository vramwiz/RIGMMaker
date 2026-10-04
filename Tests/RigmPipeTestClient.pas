unit RigmPipeTestClient;
interface
uses System.JSON;
function PipeCall(const PipeName, Command: string; Args: TJSONObject): TJSONObject;
function LastPipeReplyMs: UInt64;
implementation
uses System.SysUtils, System.Classes, Winapi.Windows, Vcl.Forms, RigmJson, RigmModel;
var ReplyElapsed: UInt64;
function LastPipeReplyMs: UInt64;
begin Result := ReplyElapsed; end;
function PipeCall(const PipeName, Command: string; Args: TJSONObject): TJSONObject;
var Client: TThread; Request, Reply, Failure: string; Envelope: TJSONObject; Start,ReplyAt: UInt64;
begin
  Envelope := TJSONObject.Create;
  try
    AddN(Envelope, 'schemaVersion', 1); Envelope.AddPair('requestId', NewRigmId);
    Envelope.AddPair('command', Command); Envelope.AddPair('args', Args); Request := Envelope.ToJSON;
  finally Envelope.Free; end;
  Client := TThread.CreateAnonymousThread(procedure
    var Handle: THandle; Data, Buffer: TBytes; Count, Written, Mode, Error: DWORD; Name: string; Deadline: UInt64;
    begin
      try
        Name := '\\.\pipe\' + PipeName; Deadline := GetTickCount64 + 3000;
        while not WaitNamedPipe(PChar(Name), 100) do begin
          Error := GetLastError;
          if not (Error in [ERROR_FILE_NOT_FOUND, ERROR_PIPE_BUSY, ERROR_SEM_TIMEOUT]) or (GetTickCount64 >= Deadline) then
            begin SetLastError(Error); RaiseLastOSError; end;
          Sleep(5);
        end;
        Handle := CreateFile(PChar(Name), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
        if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
        try
          Mode := PIPE_READMODE_MESSAGE; if not SetNamedPipeHandleState(Handle, Mode, nil, nil) then RaiseLastOSError;
          Data := TEncoding.UTF8.GetBytes(Request); SetLength(Buffer, 65536);
          if not WriteFile(Handle, Data[0], Length(Data), Written, nil) then RaiseLastOSError;
          if not ReadFile(Handle, Buffer[0], Length(Buffer), Count, nil) then RaiseLastOSError;
          Reply := TEncoding.UTF8.GetString(Buffer, 0, Count);
          ReplyAt := GetTickCount64;
        finally CloseHandle(Handle); end;
      except on E: Exception do Failure := E.Message; end;
    end);
  Client.FreeOnTerminate := False; Client.Start; Start := GetTickCount64;
  while WaitForSingleObject(Client.Handle, 1) = WAIT_TIMEOUT do begin
    Application.ProcessMessages;
    if (GetTickCount64 - Start > 10000) and (WaitForSingleObject(Client.Handle,0)=WAIT_TIMEOUT) then begin CancelSynchronousIo(Client.Handle); Client.Terminate; Client.WaitFor; Client.Free; raise Exception.Create('Pipe test timed out: '+Command+'; replyAt='+UIntToStr(ReplyAt)+'; '+Failure); end;
  end;
  Client.Free; ReplyElapsed := ReplyAt-Start; Application.ProcessMessages;
  if Failure <> '' then raise Exception.Create(Failure);
  Result := ParseObject(Reply);
end;
end.
