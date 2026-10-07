unit RigmEffectsPlayback;

// Selected-line audition: PCM stays in memory, so the audio API never sees a filename.
// The owning UI thread polls state; no asynchronous callback refers to a frame/object.
interface

uses System.SysUtils, Winapi.Windows, Winapi.MMSystem;

type
  ERigmEffectsPlayback = class(Exception);

  TRigmEffectsPlaybackBuffer = class
  public
    Handle: HWAVEOUT;
    Header: TWaveHdr;
    Format: TWaveFormatEx;
    Bytes: TBytes;
    Prepared: Boolean;
    function Release(out ErrorCode: MMRESULT): Boolean;
    function Duration: Double;
  end;
  TRigmEffectsPlayback = class
  private
    FBuffer: TRigmEffectsPlaybackBuffer;
    FOwnerThread: DWORD;
    FPath, FLastError: string;
    FActive, FCompleted: Boolean;
    FPosition: Double;
    procedure CheckThread;
    procedure Fail(const Operation: string; Code: MMRESULT);
    function GetPlaying: Boolean;
    function GetPositionSeconds: Double;
    function GetDurationSeconds: Double;
    function GetLoaded: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Open(const Path: string);
    procedure Play;
    procedure Stop;
    procedure Close;
    property Loaded: Boolean read GetLoaded;
    property IsOpen: Boolean read GetLoaded;
    property Path: string read FPath;
    property Playing: Boolean read GetPlaying;
    property PositionSeconds: Double read GetPositionSeconds;
    property DurationSeconds: Double read GetDurationSeconds;
    property LastError: string read FLastError;
  end;

implementation

uses System.Classes, System.Math, System.SyncObjs, System.Generics.Collections;

const
  MaxWaveBytes = 512 * 1024 * 1024;
  MaxWaveSeconds = 600;

var
  RetiredLock: TCriticalSection;
  Retired: TList<TRigmEffectsPlaybackBuffer>;

function WaveError(Code: MMRESULT): string;
var MessageBuffer: array[0..255] of WideChar;
begin
  FillChar(MessageBuffer, SizeOf(MessageBuffer), 0);
  if waveOutGetErrorTextW(Code, @MessageBuffer[0], Length(MessageBuffer)) = MMSYSERR_NOERROR then
    Result := string(PWideChar(@MessageBuffer[0]))
  else
    Result := 'Audio device error';
  Result := Result + ' (' + UIntToStr(Code) + ')';
end;

function TRigmEffectsPlaybackBuffer.Release(out ErrorCode: MMRESULT): Boolean;
var Code: MMRESULT;
begin
  ErrorCode := MMSYSERR_NOERROR;
  if Handle = 0 then Exit(True);
  // Reset returns queued buffers. Neither the header nor PCM may be freed before unprepare.
  Code := waveOutReset(Handle);
  if Code <> MMSYSERR_NOERROR then begin ErrorCode := Code; Exit(False); end;
  if Prepared then
  begin
    Code := waveOutUnprepareHeader(Handle, @Header, SizeOf(Header));
    if Code <> MMSYSERR_NOERROR then begin ErrorCode := Code; Exit(False); end;
    Prepared := False;
  end;
  Code := waveOutClose(Handle);
  if Code <> MMSYSERR_NOERROR then begin ErrorCode := Code; Exit(False); end;
  Handle := 0;
  Result := True;
end;

function TRigmEffectsPlaybackBuffer.Duration: Double;
begin
  Result := Length(Bytes) / Format.nAvgBytesPerSec;
end;

procedure ReapRetired;
var Code: MMRESULT; I: Integer;
begin
  RetiredLock.Acquire;
  try
    for I := Retired.Count - 1 downto 0 do
      if Retired[I].Release(Code) then
      begin
        Retired[I].Free;
        Retired.Delete(I);
      end;
  finally RetiredLock.Release; end;
end;

procedure RetireBuffer(Buffer: TRigmEffectsPlaybackBuffer);
begin
  // A malfunctioning driver can reject reset/close. Retain its memory instead of a use-after-free.
  RetiredLock.Acquire;
  try Retired.Add(Buffer); finally RetiredLock.Release; end;
end;

function ExtendedReadPath(const Path: string; out FullPath: string): string;
var Required, Written: DWORD; FilePart: PWideChar;
begin
  if (Path = '') or (Pos(#0, Path) > 0) or Path.StartsWith('\\.\') then
    raise ERigmEffectsPlayback.Create('Invalid WAV path.');
  if Path.StartsWith('\\?\') then
    FullPath := Path
  else
  begin
    FilePart := nil;
    Required := GetFullPathNameW(PWideChar(Path), 0, nil, FilePart);
    if Required = 0 then RaiseLastOSError;
    if Required > 32767 then raise ERigmEffectsPlayback.Create('WAV path is too long.');
    SetLength(FullPath, Required);
    Written := GetFullPathNameW(PWideChar(Path), Required, PWideChar(FullPath), FilePart);
    if (Written = 0) or (Written >= Required) then RaiseLastOSError;
    SetLength(FullPath, Written);
  end;
  if FullPath.StartsWith('\\?\') then Result := FullPath
  else if FullPath.StartsWith('\\') then Result := '\\?\UNC\' + Copy(FullPath, 3, MaxInt)
  else Result := '\\?\' + FullPath;
  if Length(Result) > 32767 then raise ERigmEffectsPlayback.Create('WAV path is too long.');
end;

function ReadWave(const Path: string; out FullPath: string): TRigmEffectsPlaybackBuffer;
var
  FileHandle: THandle; Stream: THandleStream; FileSize: Int64;
  RiffLimit, ChunkEnd, NextChunk, DataOffset: Int64;
  RiffSize, ChunkSize, DataSize: Cardinal;
  Id: array[0..3] of AnsiChar;
  HasFormat, HasData: Boolean;
  ReadPath: string;
  procedure ReadId;
  begin Stream.ReadBuffer(Id, SizeOf(Id)); end;
  function IsId(const Expected: AnsiString): Boolean;
  begin Result := CompareMem(@Id[0], PAnsiChar(Expected), 4); end;
  procedure Invalid(const Reason: string);
  begin raise ERigmEffectsPlayback.Create('Invalid audition WAV: ' + Reason); end;
begin
  Result := nil;
  ReadPath := ExtendedReadPath(Path, FullPath);
  // A read-only handle also prevents an external writer replacing this file while it is loaded.
  FileHandle := CreateFileW(PWideChar(ReadPath), GENERIC_READ, FILE_SHARE_READ,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  Stream := nil;
  try
    if not GetFileSizeEx(FileHandle, FileSize) then RaiseLastOSError;
    if (FileSize < 44) or (FileSize > MaxWaveBytes) then
      raise ERigmEffectsPlayback.Create('Audition WAV size must be 44 bytes to 512 MiB.');
    Stream := THandleStream.Create(FileHandle);
    Result := TRigmEffectsPlaybackBuffer.Create;
    try
      ReadId; if not IsId('RIFF') then Invalid('RIFF header missing.');
      Stream.ReadBuffer(RiffSize, SizeOf(RiffSize));
      RiffLimit := Int64(RiffSize) + 8;
      if (RiffLimit < 12) or (RiffLimit > FileSize) then Invalid('truncated RIFF payload.');
      ReadId; if not IsId('WAVE') then Invalid('WAVE header missing.');
      HasFormat := False; HasData := False; DataOffset := 0; DataSize := 0;
      while Stream.Position < RiffLimit do
      begin
        if RiffLimit - Stream.Position < 8 then Invalid('truncated chunk header.');
        ReadId; Stream.ReadBuffer(ChunkSize, SizeOf(ChunkSize));
        ChunkEnd := Stream.Position + Int64(ChunkSize);
        NextChunk := ChunkEnd + (ChunkSize and 1);
        if (ChunkEnd > RiffLimit) or (NextChunk > RiffLimit) then Invalid('truncated chunk payload.');
        if IsId('fmt ') then
        begin
          if HasFormat or (ChunkSize < 16) then Invalid('duplicate or short format chunk.');
          FillChar(Result.Format, SizeOf(Result.Format), 0);
          Stream.ReadBuffer(Result.Format, 16);
          HasFormat := True;
        end
        else if IsId('data') then
        begin
          if HasData or (ChunkSize = 0) then Invalid('duplicate or empty data chunk.');
          DataOffset := Stream.Position; DataSize := ChunkSize; HasData := True;
        end;
        Stream.Position := NextChunk;
      end;
      if not HasFormat or not HasData then Invalid('format/data chunk missing.');
      with Result.Format do
      begin
        if (wFormatTag <> WAVE_FORMAT_PCM) or (wBitsPerSample <> 16) or
           not (nChannels in [1, 2]) or (nSamplesPerSec < 8000) or (nSamplesPerSec > 192000) then
          Invalid('only PCM16 mono/stereo, 8 to 192 kHz is supported.');
        if (nBlockAlign <> nChannels * 2) or
           (nAvgBytesPerSec <> nSamplesPerSec * nBlockAlign) then
          Invalid('inconsistent PCM byte rate/block alignment.');
        if DataSize mod nBlockAlign <> 0 then
          Invalid('inconsistent PCM byte rate/block alignment.');
        if DataSize / nAvgBytesPerSec > MaxWaveSeconds then Invalid('duration exceeds 10 minutes.');
      end;
      SetLength(Result.Bytes, DataSize);
      Stream.Position := DataOffset;
      Stream.ReadBuffer(Result.Bytes[0], DataSize);
      FillChar(Result.Header, SizeOf(Result.Header), 0);
      Result.Header.lpData := PAnsiChar(@Result.Bytes[0]);
      Result.Header.dwBufferLength := Length(Result.Bytes);
    except Result.Free; Result := nil; raise; end;
  finally
    Stream.Free;
    CloseHandle(FileHandle);
  end;
end;

constructor TRigmEffectsPlayback.Create;
begin
  inherited;
  FOwnerThread := GetCurrentThreadId;
  ReapRetired;
end;

destructor TRigmEffectsPlayback.Destroy;
var Code: MMRESULT;
begin
  if FBuffer <> nil then
  begin
    if FBuffer.Release(Code) then FBuffer.Free else RetireBuffer(FBuffer);
    FBuffer := nil;
  end;
  inherited;
end;

procedure TRigmEffectsPlayback.CheckThread;
begin
  if GetCurrentThreadId <> FOwnerThread then
    raise ERigmEffectsPlayback.Create('Audition playback must be used by its owning UI thread.');
end;

procedure TRigmEffectsPlayback.Fail(const Operation: string; Code: MMRESULT);
begin
  FLastError := Operation + ': ' + WaveError(Code);
  raise ERigmEffectsPlayback.Create(FLastError);
end;

procedure TRigmEffectsPlayback.Open(const Path: string);
var Buffer: TRigmEffectsPlaybackBuffer; FullPath: string; Code: MMRESULT;
begin
  CheckThread;
  Buffer := nil;
  try
    try
      Buffer := ReadWave(Path, FullPath);
      Close;
      Code := waveOutOpen(@Buffer.Handle, WAVE_MAPPER, @Buffer.Format, 0, 0, CALLBACK_NULL);
      if Code <> MMSYSERR_NOERROR then Fail('Open audio device', Code);
      FBuffer := Buffer; Buffer := nil;
      FPath := FullPath; FActive := False; FCompleted := False; FPosition := 0; FLastError := '';
    except
      on E: Exception do begin FLastError := E.Message; raise; end;
    end;
  finally
    if Buffer <> nil then
      if Buffer.Release(Code) then Buffer.Free else RetireBuffer(Buffer);
  end;
end;

procedure TRigmEffectsPlayback.Play;
var Code: MMRESULT;
begin
  CheckThread;
  if FBuffer = nil then begin FLastError := 'Load a WAV before playing.'; raise ERigmEffectsPlayback.Create(FLastError); end;
  Stop;
  if not FBuffer.Prepared then
  begin
    Code := waveOutPrepareHeader(FBuffer.Handle, @FBuffer.Header, SizeOf(FBuffer.Header));
    if Code <> MMSYSERR_NOERROR then Fail('Prepare audio buffer', Code);
    FBuffer.Prepared := True;
  end;
  Code := waveOutWrite(FBuffer.Handle, @FBuffer.Header, SizeOf(FBuffer.Header));
  if Code <> MMSYSERR_NOERROR then Fail('Play audio buffer', Code);
  FActive := True; FCompleted := False; FPosition := 0; FLastError := '';
end;

procedure TRigmEffectsPlayback.Stop;
var Code: MMRESULT;
begin
  CheckThread;
  if FBuffer <> nil then
  begin
    Code := waveOutReset(FBuffer.Handle);
    if Code <> MMSYSERR_NOERROR then Fail('Stop audio playback', Code);
  end;
  FActive := False; FCompleted := False; FPosition := 0;
end;

procedure TRigmEffectsPlayback.Close;
var Code: MMRESULT;
begin
  CheckThread;
  if FBuffer <> nil then
  begin
    if not FBuffer.Release(Code) then Fail('Close audio playback', Code);
    FreeAndNil(FBuffer);
  end;
  FPath := ''; FActive := False; FCompleted := False; FPosition := 0;
  ReapRetired;
end;

function TRigmEffectsPlayback.GetLoaded: Boolean;
begin
  Result := FBuffer <> nil;
end;

function TRigmEffectsPlayback.GetPlaying: Boolean;
begin
  CheckThread;
  if FActive and ((FBuffer = nil) or ((FBuffer.Header.dwFlags and WHDR_DONE) <> 0)) then
  begin
    FActive := False; FCompleted := True; FPosition := GetDurationSeconds;
  end;
  Result := FActive;
end;

function TRigmEffectsPlayback.GetDurationSeconds: Double;
begin
  if FBuffer = nil then Result := 0 else Result := FBuffer.Duration;
end;

function TRigmEffectsPlayback.GetPositionSeconds: Double;
var Info: TMMTime; Code: MMRESULT; Position: Double;
begin
  CheckThread;
  if GetPlaying then
  begin
    FillChar(Info, SizeOf(Info), 0); Info.wType := TIME_SAMPLES;
    Code := waveOutGetPosition(FBuffer.Handle, @Info, SizeOf(Info));
    if Code = MMSYSERR_NOERROR then
    begin
      case Info.wType of
        TIME_SAMPLES: Position := Info.sample / FBuffer.Format.nSamplesPerSec;
        TIME_BYTES: Position := Info.cb / FBuffer.Format.nAvgBytesPerSec;
        TIME_MS: Position := Info.ms / 1000;
      else Position := FPosition; end;
      FPosition := EnsureRange(Max(FPosition, Position), 0.0, GetDurationSeconds);
    end
    else FLastError := 'Read audio position: ' + WaveError(Code);
  end;
  if FCompleted then FPosition := GetDurationSeconds;
  Result := FPosition;
end;

initialization
  RetiredLock := TCriticalSection.Create;
  Retired := TList<TRigmEffectsPlaybackBuffer>.Create;
finalization
  ReapRetired;
  // If a driver still owns a header, process teardown is safer than freeing that memory.
  Retired.Free;
  RetiredLock.Free;
end.
