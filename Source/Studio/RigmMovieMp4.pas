unit RigmMovieMp4;

interface
uses System.SysUtils;
type TRigmEncoderProgress = reference to procedure(Seconds: Double; PrivateBytes,WorkingBytes: UInt64; ProcessId: Cardinal; Exited: Boolean);
procedure EncodeMovieMp4(const Executable, InputFile, OutputFile: string; Cancelled: TFunc<Boolean>;
  const Profile: string='balanced'; Progress: TRigmEncoderProgress=nil);

implementation
uses System.IOUtils, System.Math, System.Classes, Winapi.Windows, Winapi.PsAPI, RigmModel, RigmMovieOutput;

function Quoted(const Value: string): string;
begin
  if (Pos('"',Value)>0) or (Pos(#10,Value)>0) or (Pos(#13,Value)>0) then
    raise ERigm.Create('FFmpegのファイル名が不正です。');
  Result := '"'+Value+'"';
end;

procedure EncodeMovieMp4(const Executable, InputFile, OutputFile: string; Cancelled: TFunc<Boolean>;
  const Profile: string; Progress: TRigmEncoderProgress);
var Startup: TStartupInfo; Process: TProcessInformation; Security: TSecurityAttributes;
  LogHandle, InputHandle: THandle; Command, LogFile, Detail: string; Code: Cardinal;
  procedure Report(Exited: Boolean=False);
  var Counters: TProcessMemoryCountersEx; Seconds: Double;
  begin
    if not Assigned(Progress) then Exit;
    Seconds := 0; Counters := Default(TProcessMemoryCountersEx); Counters.cb := SizeOf(Counters);
    GetProcessMemoryInfo(Process.hProcess,@Counters,SizeOf(Counters));
    var Stream := TFileStream.Create(LogFile,fmOpenRead or fmShareDenyNone);
    try
      var Data: TBytes; SetLength(Data,Min(Stream.Size,65536)); Stream.Position := Max(0,Stream.Size-Length(Data));
      if Length(Data)>0 then Stream.ReadBuffer(Data[0],Length(Data));
      for var Line in TEncoding.UTF8.GetString(Data).Split([#10]) do
        if Line.StartsWith('out_time_us=') then Seconds := StrToInt64Def(Trim(Line.Substring(12)),0)/1000000.0;
    finally Stream.Free; end;
    Progress(Seconds,Counters.PrivateUsage,Counters.WorkingSetSize,Process.dwProcessId,Exited);
  end;
begin
  if not FileExists(Executable) or not SameText(ExtractFileName(Executable),'ffmpeg.exe') then
    raise ERigm.Create('MP4出力には、既存のffmpeg.exeを設定してください。');
  if FileExists(OutputFile) then raise ERigm.Create('MP4の一時出力先が存在します。');
  LogFile := OutputFile+'.log';
  Security := Default(TSecurityAttributes); Security.nLength := SizeOf(Security); Security.bInheritHandle := True;
  LogHandle := CreateFile(PChar(LogFile),GENERIC_WRITE,FILE_SHARE_READ,@Security,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  if LogHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
  InputHandle := INVALID_HANDLE_VALUE;
  try
    InputHandle := CreateFile('NUL',GENERIC_READ,FILE_SHARE_READ or FILE_SHARE_WRITE,@Security,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
    if InputHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
    Startup := Default(TStartupInfo); Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW; Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := InputHandle; Startup.hStdOutput := LogHandle; Startup.hStdError := LogHandle;
    Process := Default(TProcessInformation);
    Command := Quoted(Executable)+' -hide_banner -nostdin -n -i '+Quoted(InputFile)+
      ' -map 0:v:0 -map 0:a:0 -c:v libx264 '+MovieEncoderOptions(Profile)+' -threads 4 -pix_fmt yuv420p'+
      ' -progress pipe:1 -nostats'+
      ' -c:a aac -b:a 160k -movflags +faststart -f mp4 '+Quoted(OutputFile);
    UniqueString(Command);
    if not CreateProcess(PChar(Executable),PChar(Command),nil,nil,True,CREATE_NO_WINDOW,nil,nil,Startup,Process) then RaiseLastOSError;
    try
      repeat
        Report;
        if Assigned(Cancelled) and Cancelled() then begin
          // Only this job's child process is stopped; no existing application is targeted.
          TerminateProcess(Process.hProcess,ERROR_CANCELLED); WaitForSingleObject(Process.hProcess,5000);
          raise EAbort.Create('MP4出力を取消しました。');
        end;
      until WaitForSingleObject(Process.hProcess,100)=WAIT_OBJECT_0;
      Report;
      if not GetExitCodeProcess(Process.hProcess,Code) then RaiseLastOSError;
      if (Code<>0) or not FileExists(OutputFile) or (TFile.GetSize(OutputFile)=0) then begin
        CloseHandle(LogHandle); LogHandle := INVALID_HANDLE_VALUE;
        Detail := TFile.ReadAllText(LogFile,TEncoding.UTF8);
        raise ERigm.Create('FFmpeg MP4出力に失敗しました: '+Copy(Detail,System.Math.Max(1,Length(Detail)-2000),2001));
      end;
    finally
      if WaitForSingleObject(Process.hProcess,0)<>WAIT_OBJECT_0 then begin
        TerminateProcess(Process.hProcess,ERROR_CANCELLED); WaitForSingleObject(Process.hProcess,5000);
      end;
      try Report(True); finally CloseHandle(Process.hThread); CloseHandle(Process.hProcess); end;
    end;
  finally
    if InputHandle<>INVALID_HANDLE_VALUE then CloseHandle(InputHandle);
    if LogHandle<>INVALID_HANDLE_VALUE then CloseHandle(LogHandle);
    if FileExists(LogFile) then TFile.Delete(LogFile);
  end;
end;
end.
