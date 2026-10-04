unit RigmMovieNotification;

interface
uses System.Classes, Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Vcl.ExtCtrls;

type
  TRigmMovieNotification = class(TComponent)
  private
    FWindow: HWND;
    FRegistered: Boolean;
    FTimer: TTimer;
    FRequests,FShown: Integer;
    procedure WindowProc(var Message: TMessage);
    procedure Hide(Sender: TObject);
    function IconData: TNotifyIconData;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ExportFinished(const Path: string): Boolean;
    property Requests: Integer read FRequests;
    property Shown: Integer read FShown;
  end;

implementation
uses System.SysUtils, Vcl.Forms;
const NotificationMessage = WM_APP+$347;

constructor TRigmMovieNotification.Create(AOwner: TComponent);
begin
  inherited;
  FWindow := AllocateHWnd(WindowProc);
  FTimer := TTimer.Create(Self); FTimer.Enabled := False;
  FTimer.Interval := 30000; FTimer.OnTimer := Hide;
end;

destructor TRigmMovieNotification.Destroy;
begin
  Hide(nil); DeallocateHWnd(FWindow); inherited;
end;

function TRigmMovieNotification.IconData: TNotifyIconData;
begin
  Result := Default(TNotifyIconData);
  Result.cbSize := SizeOf(Result); Result.Wnd := FWindow; Result.uID := 1;
end;

procedure TRigmMovieNotification.Hide(Sender: TObject);
begin
  FTimer.Enabled := False;
  if FRegistered then begin
    var Data := IconData; Shell_NotifyIcon(NIM_DELETE,@Data); FRegistered := False;
  end;
end;

procedure TRigmMovieNotification.WindowProc(var Message: TMessage);
begin
  if Message.Msg=NotificationMessage then begin
    if Message.LParam=NIN_BALLOONSHOW then Inc(FShown);
    Message.Result := 0;
  end else Message.Result := DefWindowProc(FWindow,Message.Msg,Message.WParam,Message.LParam);
end;

function TRigmMovieNotification.ExportFinished(const Path: string): Boolean;
begin
  Result := False;
  if not FileExists(Path) then Exit;
  var Data := IconData;
  if not FRegistered then begin
    Data.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
    Data.uCallbackMessage := NotificationMessage; Data.hIcon := Application.Icon.Handle;
    if Data.hIcon=0 then Data.hIcon := LoadIcon(0,IDI_APPLICATION);
    StrPLCopy(Data.szTip,'RIGMMaker',Length(Data.szTip)-1);
    FRegistered := Shell_NotifyIcon(NIM_ADD,@Data);
    if not FRegistered then Exit;
  end;
  Data := IconData; Data.uFlags := NIF_INFO; Data.dwInfoFlags := NIIF_INFO;
  Data.uTimeout := 10000;
  StrPLCopy(Data.szInfoTitle,'RIGMMaker — 動画の書き出しが完了しました',Length(Data.szInfoTitle)-1);
  StrPLCopy(Data.szInfo,ExtractFileName(Path)+sLineBreak+ExtractFileDir(Path),Length(Data.szInfo)-1);
  Result := Shell_NotifyIcon(NIM_MODIFY,@Data);
  if Result then Inc(FRequests);
  FTimer.Enabled := True;
end;
end.
