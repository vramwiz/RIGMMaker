unit RigmNativeSaveDialog;

interface

uses System.SysUtils;

procedure SelectOwnedSavePath(const Target: string; const Action: TProc);

implementation

uses System.Classes, Winapi.Windows, Winapi.Messages, Vcl.Dialogs;

type
  TSaveDialogDriver = class(TThread)
    Target: string;
    Window: HWND;
    SawDialog, Filled: Boolean;
    procedure Execute; override;
  end;

function FindOwnedDialog(W: HWND; Param: LPARAM): BOOL; stdcall;
begin
  Result := True;
  var Pid: DWORD;
  GetWindowThreadProcessId(W,@Pid);
  var Name: array[0..127] of Char;
  GetClassName(W,Name,Length(Name));
  if (Pid=GetCurrentProcessId) and IsWindowVisible(W) and (string(Name)='#32770') then
  begin
    TSaveDialogDriver(Param).Window := W;
    Result := False;
  end;
end;

procedure TSaveDialogDriver.Execute;
begin
  var Deadline := GetTickCount64+10000;
  repeat
    Window := 0;
    EnumWindows(@FindOwnedDialog,LPARAM(Self));
    if Window<>0 then
    begin
      SawDialog := True;
      var Edit := GetDlgItem(Window,1152);
      if Edit=0 then Edit := GetDlgItem(Window,1148);
      if Edit<>0 then
      begin
        SendMessage(Edit,WM_SETTEXT,0,LPARAM(PChar(Target)));
        Filled := True;
        PostMessage(Window,WM_COMMAND,IDOK,0);
      end
      else PostMessage(Window,WM_COMMAND,IDCANCEL,0);
      Exit;
    end;
    Sleep(20);
  until GetTickCount64>Deadline;
end;

procedure SelectOwnedSavePath(const Target: string; const Action: TProc);
begin
  // The compatibility dialog is enabled only in this owned GUI test process.
  var Previous := UseLatestCommonDialogs;
  var Driver := TSaveDialogDriver.Create(True);
  Driver.Target := Target;
  try
    UseLatestCommonDialogs := False;
    Driver.Start;
    Action();
    Driver.WaitFor;
    if not Driver.SawDialog then raise Exception.Create('Owned GUI export did not open the native save dialog');
    if not Driver.Filled then raise Exception.Create('Owned native save dialog did not accept the requested path');
  finally
    UseLatestCommonDialogs := Previous;
    Driver.Free;
  end;
end;

end.
