program AppContainerPipeClient;

{$APPTYPE CONSOLE}

uses Winapi.Windows, System.SysUtils, System.Classes, System.JSON;

function ConvertSidToStringSidW(Sid: Pointer; out Text: PWideChar): BOOL; stdcall;
  external 'advapi32.dll';

function TokenSid(Token: THandle; Kind: TTokenInformationClass): string;
var Size: DWORD; Bytes: TBytes; Sid: PWideChar;
begin
  Result := ''; Size := 0;
  GetTokenInformation(Token,Kind,nil,0,Size);
  if Size=0 then Exit;
  SetLength(Bytes,Size);
  if not GetTokenInformation(Token,Kind,@Bytes[0],Size,Size) then RaiseLastOSError;
  if not ConvertSidToStringSidW(PPointer(@Bytes[0])^,Sid) then RaiseLastOSError;
  try Result := string(Sid); finally LocalFree(HLOCAL(Sid)); end;
end;

var Pipe, Token: THandle; Report, Request: TJSONObject; Bytes: TBytes;
  Count, Offset, Error: DWORD; Buffer: array[0..4095] of Byte;
  Received: TBytes; Position, OldSize: Integer;
begin
  ExitCode := 1;
  Report := TJSONObject.Create;
  Pipe := INVALID_HANDLE_VALUE;
  try
    try
      if (ParamCount<3) or (ParamCount>4) then raise Exception.Create('Usage: pipeName accessToken testCase [payload]');
      if not OpenProcessToken(GetCurrentProcess,TOKEN_QUERY,Token) then RaiseLastOSError;
      try
        Report.AddPair('appContainerSid',TokenSid(Token,TTokenInformationClass(31)));
        Report.AddPair('integritySid',TokenSid(Token,TokenIntegrityLevel));
      finally CloseHandle(Token); end;
      Pipe := CreateFile(PChar('\\.\pipe\'+ParamStr(1)),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_EXISTING,0,0);
      if Pipe=INVALID_HANDLE_VALUE then begin
        Error := GetLastError;
        Report.AddPair('openError',TJSONNumber.Create(Error));
      end else begin
        Report.AddPair('openError',TJSONNumber.Create(0));
        Request := TJSONObject.Create.AddPair('version',TJSONNumber.Create(1))
          .AddPair('id',TGUID.NewGuid.ToString).AddPair('command','ping').AddPair('args',TJSONObject.Create);
        if (ParamStr(3)='echo') or (ParamStr(3)='upload') or (ParamStr(3)='download') then begin
          Request.RemovePair('command').Free; Request.RemovePair('args').Free;
          if ParamStr(3)='echo' then Request.AddPair('command','echo')
            .AddPair('args',TJSONObject.Create.AddPair('text','Dotsからこんにちは。'+#10+'画像通信の前のテキスト試験'))
          else if ParamStr(3)='upload' then Request.AddPair('command','image.put')
            .AddPair('args',TJSONObject.Create.AddPair('base64',ParamStr(4)))
          else Request.AddPair('command','image.get')
            .AddPair('args',TJSONObject.Create.AddPair('imageId',ParamStr(4)));
        end;
        if ParamStr(2)<>'-' then Request.AddPair('accessToken',ParamStr(2));
        try Bytes := TEncoding.UTF8.GetBytes(Request.ToJSON+#10); finally Request.Free; end;
        Offset := 0;
        while Offset<DWORD(Length(Bytes)) do begin
          if not WriteFile(Pipe,Bytes[Offset],Length(Bytes)-Offset,Count,nil) then RaiseLastOSError;
          if Count=0 then raise Exception.Create('Short write');
          Inc(Offset,Count);
        end;
        Received := nil;
        repeat
          if not ReadFile(Pipe,Buffer[0],SizeOf(Buffer),Count,nil) then RaiseLastOSError;
          if Count=0 then raise Exception.Create('EOF before LF');
          OldSize := Length(Received); SetLength(Received,OldSize+Integer(Count));
          Move(Buffer[0],Received[OldSize],Count); Position := OldSize;
          while (Position<Length(Received)) and (Received[Position]<>10) do Inc(Position);
          if Length(Received)>65536 then raise Exception.Create('Reply too large');
        until Position<Length(Received);
        Report.AddPair('response',TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Received,0,Position)));
      end;
      ExitCode := 0;
    except on E: Exception do Report.AddPair('error',E.Message); end;
  finally
    if Pipe<>INVALID_HANDLE_VALUE then CloseHandle(Pipe);
    try
      Bytes := TEncoding.UTF8.GetBytes(Report.ToJSON);
      if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),Bytes[0],Length(Bytes),Count,nil) then ExitCode := 1;
    finally Report.Free; end;
  end;
end.
