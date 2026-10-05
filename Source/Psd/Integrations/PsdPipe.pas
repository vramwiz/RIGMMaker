unit PsdPipe;

// RigmPipeのメッセージパイプ部分だけをコピー。旧GUI/編集モデルへの依存は持たない。
interface
uses System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages;
type
  TPsdPipeRequest = procedure(const Request: string; out Response: string) of object;
  TPsdPipeWorker = class(TThread)
  private
    FName: string; FWindow: HWND; FReady: THandle; FRequest, FResponse: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const Name: string; Window: HWND);
    destructor Destroy; override;
  end;
  TPsdPipeEndpoint = class
  private
    FWorker: TPsdPipeWorker; // 所有。先に停止してから通知ウィンドウを破棄。
    FWindow: HWND; FHandler: TPsdPipeRequest; FStopping: Boolean;
    procedure WindowProc(var Message: TMessage);
  public
    constructor Create(const Name: string; Handler: TPsdPipeRequest);
    destructor Destroy; override;
  end;
implementation
const WM_PSD_REQUEST = WM_USER + 271;
constructor TPsdPipeWorker.Create(const Name: string; Window: HWND);
begin inherited Create(True); FName := Name; FWindow := Window; FReady := CreateEvent(nil, False, False, nil); end;
destructor TPsdPipeWorker.Destroy;
begin CloseHandle(FReady); inherited; end;
procedure TPsdPipeWorker.Execute;
begin
  var Name := '\\.\pipe\' + FName; var Buffer: TBytes; SetLength(Buffer, 65536);
  while not Terminated do begin
    var Pipe := CreateNamedPipe(PChar(Name), PIPE_ACCESS_DUPLEX, PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT or $8,
      1, 65536, 65536, 1000, nil); // $8=PIPE_REJECT_REMOTE_CLIENTS。
    if Pipe = INVALID_HANDLE_VALUE then begin Sleep(20); Continue; end;
    try
      if not ConnectNamedPipe(Pipe, nil) and (GetLastError <> ERROR_PIPE_CONNECTED) then Continue;
      var ReadCount, Written: DWORD;
      if not ReadFile(Pipe, Buffer[0], Length(Buffer), ReadCount, nil) or (ReadCount = 0) or (ReadCount > 60000) then Continue;
      FRequest := TEncoding.UTF8.GetString(Buffer, 0, ReadCount); FResponse := ''; ResetEvent(FReady);
      PostMessage(FWindow, WM_PSD_REQUEST, WPARAM(Self), 0);
      while not Terminated and (WaitForSingleObject(FReady, 50) = WAIT_TIMEOUT) do ;
      if Terminated then Continue;
      var Reply := TEncoding.UTF8.GetBytes(FResponse);
      if (Length(Reply) > 0) and (Length(Reply) <= 60000) and WriteFile(Pipe, Reply[0], Length(Reply), Written, nil) then FlushFileBuffers(Pipe);
    finally DisconnectNamedPipe(Pipe); CloseHandle(Pipe); end;
  end;
end;
constructor TPsdPipeEndpoint.Create(const Name: string; Handler: TPsdPipeRequest);
begin
  inherited Create; FHandler := Handler; FWindow := AllocateHWnd(WindowProc);
  FWorker := TPsdPipeWorker.Create(Name, FWindow); FWorker.Start;
end;
destructor TPsdPipeEndpoint.Destroy;
begin
  FStopping := True;
  if FWorker <> nil then begin
    FWorker.Terminate; SetEvent(FWorker.FReady);
    while WaitForSingleObject(FWorker.Handle, 10) = WAIT_TIMEOUT do begin CancelSynchronousIo(FWorker.Handle); SetEvent(FWorker.FReady); end;
    FWorker.Free;
  end;
  if FWindow <> 0 then begin
    var Pending: TMsg; while PeekMessage(Pending, FWindow, WM_PSD_REQUEST, WM_PSD_REQUEST, PM_REMOVE) do ;
    DeallocateHWnd(FWindow);
  end;
  inherited;
end;
procedure TPsdPipeEndpoint.WindowProc(var Message: TMessage);
begin
  if (Message.Msg = WM_PSD_REQUEST) and (Message.WParam = WPARAM(FWorker)) then begin
    try if not FStopping then FHandler(FWorker.FRequest, FWorker.FResponse); finally SetEvent(FWorker.FReady); end;
    Message.Result := 0;
  end else Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;
end.
