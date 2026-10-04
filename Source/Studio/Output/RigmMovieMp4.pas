// 既存FFmpegで映像・音声をMP4へ出力する。子プロセスの終了・取消・進捗回収を担当する。
unit RigmMovieMp4;

interface
uses System.SysUtils, RigmMovieModel, RigmModel, RigmMovieAudio;
type TRigmEncoderProgress = reference to procedure(Seconds: Double; PrivateBytes,WorkingBytes: UInt64; ProcessId: Cardinal; Exited: Boolean);
     TRigmStreamFrameProgress = reference to procedure(Current,Total: Integer; StagingBytes: UInt64);
procedure EncodeMovieMp4(const Executable, InputFile, OutputFile: string; Cancelled: TFunc<Boolean>;
  const Profile: string='balanced'; Progress: TRigmEncoderProgress=nil);
procedure StreamMovieMp4(Project: TRigmMovieProject; Document: TRigmDocument; Audio: TRigmPcm;
  const OutputFile: string; Cancelled: TFunc<Boolean>; Frames: TRigmStreamFrameProgress;
  Finishing: TProc; Progress: TRigmEncoderProgress);

implementation
uses System.IOUtils, System.Math, System.Classes, System.SyncObjs, Winapi.Windows, Winapi.PsAPI,
  Vcl.Graphics, RigmMovieOutput, RigmMovieRendering;

type
  TRigmFramePipeWriter = class(TThread)
  private
    FPipe: THandle;
    FReady,FComplete: TEvent;
    FData: TBytes;
    FError: Cardinal;
  protected
    procedure Execute; override;
  public
    constructor Create(Pipe: THandle);
    destructor Destroy; override;
    procedure Submit(const Data: TBytes);
    function Completed: Boolean;
    property Error: Cardinal read FError;
  end;

constructor TRigmFramePipeWriter.Create(Pipe: THandle);
begin
  inherited Create(True); FreeOnTerminate := False; FPipe := Pipe;
  FReady := TEvent.Create(nil,False,False,''); FComplete := TEvent.Create(nil,True,False,'');
end;
destructor TRigmFramePipeWriter.Destroy;
begin
  Terminate; FReady.SetEvent; CancelSynchronousIo(Handle); WaitFor;
  FData := nil; FReady.Free; FComplete.Free; inherited;
end;
procedure TRigmFramePipeWriter.Submit(const Data: TBytes);
begin
  // The producer never reuses this one-frame buffer before completion.
  FComplete.ResetEvent; FData := Data; FError := 0; FReady.SetEvent;
end;
function TRigmFramePipeWriter.Completed: Boolean;
begin Result := FComplete.WaitFor(50)=wrSignaled; end;
procedure TRigmFramePipeWriter.Execute;
begin
  while not Terminated do begin
    FReady.WaitFor(INFINITE); if Terminated then Exit;
    var Position := 0;
    while (Position<Length(FData)) and not Terminated do begin
      var Written: Cardinal := 0; var Count := Min(65536,Length(FData)-Position);
      if not WriteFile(FPipe,FData[Position],Count,Written,nil) then begin FError := GetLastError; Break; end;
      if Written=0 then begin FError := ERROR_WRITE_FAULT; Break; end;
      Inc(Position,Written);
    end;
    FComplete.SetEvent;
  end;
end;

function Quoted(const Value: string): string;
begin
  if (Pos('"',Value)>0) or (Pos(#10,Value)>0) or (Pos(#13,Value)>0) then
    raise ERigm.Create('FFmpegのファイル名が不正です。');
  Result := '"'+Value+'"';
end;

procedure StreamMovieMp4(Project: TRigmMovieProject; Document: TRigmDocument; Audio: TRigmPcm;
  const OutputFile: string; Cancelled: TFunc<Boolean>; Frames: TRigmStreamFrameProgress;
  Finishing: TProc; Progress: TRigmEncoderProgress);
var Startup: TStartupInfo; Process: TProcessInformation; Security: TSecurityAttributes;
  LogHandle,PipeRead,PipeWrite: THandle; Writer: TRigmFramePipeWriter;
  LogFile,WaveFile,Command: string; Buffer: TBytes; Started,Success: Boolean; ReportAt: UInt64;
  procedure CheckCancel;
  begin if Assigned(Cancelled) and Cancelled() then raise EAbort.Create('MP4出力を中止しました。'); end;
  function StagingBytes: UInt64;
  begin
    Result := 0;
    for var Path in [WaveFile,LogFile,OutputFile] do
      if FileExists(Path) then Result := Result+UInt64(TFile.GetSize(Path));
  end;
  function Detail: string;
  begin
    var Stream := TFileStream.Create(LogFile,fmOpenRead or fmShareDenyNone);
    try
      var Data: TBytes; SetLength(Data,Min(Int64(4096),Stream.Size));
      Stream.Position := Stream.Size-Length(Data);
      if Length(Data)>0 then Stream.ReadBuffer(Data[0],Length(Data));
      Result := TEncoding.UTF8.GetString(Data);
    finally Stream.Free; end;
  end;
  procedure Report(Force: Boolean=False);
  begin
    if not Started or not Assigned(Progress) then Exit;
    if not Force and (GetTickCount64<ReportAt) then Exit; ReportAt := GetTickCount64+200;
    var Counters := Default(TProcessMemoryCountersEx); Counters.cb := SizeOf(Counters);
    GetProcessMemoryInfo(Process.hProcess,@Counters,SizeOf(Counters));
    var Seconds := 0.0;
    var Stream := TFileStream.Create(LogFile,fmOpenRead or fmShareDenyNone);
    try
      var Data: TBytes; SetLength(Data,Min(Int64(65536),Stream.Size));
      Stream.Position := Stream.Size-Length(Data);
      if Length(Data)>0 then Stream.ReadBuffer(Data[0],Length(Data));
      for var Line in TEncoding.UTF8.GetString(Data).Split([#10]) do
        if Line.StartsWith('out_time_us=') then Seconds := StrToInt64Def(Trim(Line.Substring(12)),0)/1000000.0;
    finally Stream.Free; end;
    Progress(Seconds,Counters.PrivateUsage,Counters.WorkingSetSize,Process.dwProcessId,
      WaitForSingleObject(Process.hProcess,0)=WAIT_OBJECT_0);
  end;
begin
  if not FileExists(Project.FfmpegExe) or not SameText(ExtractFileName(Project.FfmpegExe),'ffmpeg.exe') then
    raise ERigm.Create('MP4出力には既存のffmpeg.exeを設定してください。');
  if FileExists(OutputFile) then raise ERigm.Create('既存のMP4出力は上書きできません。');
  WaveFile := OutputFile+'.audio.wav'; LogFile := OutputFile+'.log';
  if FileExists(WaveFile) or FileExists(LogFile) then raise ERigm.Create('一時出力が既に存在します。');
  LogHandle := INVALID_HANDLE_VALUE; PipeRead := INVALID_HANDLE_VALUE; PipeWrite := INVALID_HANDLE_VALUE;
  Writer := nil; Started := False; Success := False; ReportAt := 0; Process := Default(TProcessInformation);
  try
    CheckCancel; Audio.Save(WaveFile); CheckCancel;
    Security := Default(TSecurityAttributes); Security.nLength := SizeOf(Security); Security.bInheritHandle := True;
    LogHandle := CreateFile(PChar(LogFile),GENERIC_WRITE,FILE_SHARE_READ,@Security,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
    if LogHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
    var ReadHandle,WriteHandle: THandle;
    if not CreatePipe(ReadHandle,WriteHandle,@Security,65536) then RaiseLastOSError;
    PipeRead := ReadHandle; PipeWrite := WriteHandle;
    if not SetHandleInformation(PipeWrite,HANDLE_FLAG_INHERIT,0) then RaiseLastOSError;
    Startup := Default(TStartupInfo); Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW; Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := PipeRead; Startup.hStdOutput := LogHandle; Startup.hStdError := LogHandle;
    Command := Quoted(Project.FfmpegExe)+' -hide_banner -nostdin -n'+
      ' -f rawvideo -pixel_format bgra -video_size '+Project.Width.ToString+'x'+Project.Height.ToString+
      ' -framerate '+Project.Fps.ToString+' -i pipe:0 -i '+Quoted(WaveFile)+
      ' -map 0:v:0 -map 1:a:0 -c:v libx264 '+MovieEncoderOptions(Project.EncodeProfile)+
      ' -threads 4 -pix_fmt yuv420p -progress pipe:1 -nostats -c:a aac -b:a 160k'+
      ' -movflags +faststart -f mp4 '+Quoted(OutputFile);
    UniqueString(Command);
    if not CreateProcess(PChar(Project.FfmpegExe),PChar(Command),nil,nil,True,CREATE_NO_WINDOW,nil,nil,Startup,Process) then RaiseLastOSError;
    Started := True;
    // Only the child owns the read end. Its exit then unblocks the writer.
    CloseHandle(PipeRead); PipeRead := INVALID_HANDLE_VALUE;
    Writer := TRigmFramePipeWriter.Create(PipeWrite); Writer.Start;
    var Total := Ceil(Project.Duration*Project.Fps);
    SetLength(Buffer,Project.Width*Project.Height*4); Report(True);
    for var I := 0 to Total-1 do begin
      CheckCancel;
      var Bitmap := RenderMovieFrame(Project,Document,I/Project.Fps,Audio);
      try
        if (Bitmap.Width<>Project.Width) or (Bitmap.Height<>Project.Height) then raise ERigm.Create('MP4フレーム寸法が一致しません。');
        Bitmap.PixelFormat := pf32bit; GdiFlush;
        for var Y := 0 to Project.Height-1 do Move(Bitmap.ScanLine[Y]^,Buffer[Y*Project.Width*4],Project.Width*4);
      finally Bitmap.Free; end;
      Writer.Submit(Buffer);
      while not Writer.Completed do begin
        CheckCancel; Report;
        if WaitForSingleObject(Process.hProcess,0)=WAIT_OBJECT_0 then raise ERigm.Create('FFmpegがフレーム受信中に終了しました: '+Detail);
      end;
      CheckCancel;
      if Writer.Error<>0 then raise ERigm.Create('FFmpegへのフレーム送信に失敗しました: '+SysErrorMessage(Writer.Error)+sLineBreak+Detail);
      if Assigned(Frames) then Frames(I+1,Total,StagingBytes);
      Report;
    end;
    FreeAndNil(Writer); CloseHandle(PipeWrite); PipeWrite := INVALID_HANDLE_VALUE;
    if Assigned(Finishing) then Finishing;
    repeat CheckCancel; Report; until WaitForSingleObject(Process.hProcess,100)=WAIT_OBJECT_0;
    Report(True); var Code: Cardinal;
    if not GetExitCodeProcess(Process.hProcess,Code) then RaiseLastOSError;
    if (Code<>0) or not FileExists(OutputFile) or (TFile.GetSize(OutputFile)=0) then
      raise ERigm.Create('FFmpeg MP4出力に失敗しました: '+Detail);
    Success := True;
  finally
    if Started and (WaitForSingleObject(Process.hProcess,0)<>WAIT_OBJECT_0) then begin
      // Cancellation targets only this encoder, including a blocked pipe write.
      TerminateProcess(Process.hProcess,ERROR_CANCELLED); WaitForSingleObject(Process.hProcess,5000);
    end;
    Writer.Free;
    if PipeRead<>INVALID_HANDLE_VALUE then CloseHandle(PipeRead);
    if PipeWrite<>INVALID_HANDLE_VALUE then CloseHandle(PipeWrite);
    if Started then try Report(True); finally CloseHandle(Process.hThread); CloseHandle(Process.hProcess); end;
    if LogHandle<>INVALID_HANDLE_VALUE then CloseHandle(LogHandle);
    if FileExists(LogFile) then TFile.Delete(LogFile);
    if FileExists(WaveFile) then TFile.Delete(WaveFile);
    if not Success and FileExists(OutputFile) then TFile.Delete(OutputFile);
  end;
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
