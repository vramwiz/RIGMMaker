// 共通パイプのPNGチャンクを受信・検証し、作品用資産として公開する。作品への採用はセッションの明示操作で行う。
unit RigmMovieImageTransfer;

interface
uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, RigmMovieModel;
const RigmImageChunkBytes = 16384;
      RigmImageMaxBytes = 32*1024*1024;
type
  TRigmImageTransfer = class(TThread)
  private
    FLock: TObject;
    FWake: TEvent;
    FQueue: TQueue<TBytes>;
    FChunkHashes: TList<string>;
    FId,FProject,FProjectFile,FScene,FHash,FDirectory,FStage,FPath,FState,FError: string;
    FExpected,FAccepted,FReceived,FLastActivity: Int64;
    FFinish,FAdopted: Boolean;
    FCancel: Integer;
    FReadyHandle: NativeUInt;
    FWidth,FHeight: Integer;
    procedure CheckCancel;
    procedure Publish;
  protected
    procedure Execute; override;
  public
    constructor Create(Project: TRigmMovieProject; Args: TJSONObject);
    destructor Destroy; override;
    procedure Chunk(Args: TJSONObject);
    procedure Finish;
    procedure Cancel;
    function Status: TJSONObject;
    function ReadyPath(Project: TRigmMovieProject): string;
    procedure Adopted;
    function Terminal: Boolean;
    property Id: string read FId;
    property Scene: string read FScene;
  end;
  TRigmImageTransfers = class
  private
    FItems: TObjectDictionary<string,TRigmImageTransfer>;
    FOrder: TList<string>;
    function Item(const Id: string): TRigmImageTransfer;
  public
    constructor Create;
    destructor Destroy; override;
    function BeginTransfer(Project: TRigmMovieProject; Args: TJSONObject): TJSONObject;
    function Execute(const Command: string; Args: TJSONObject): TJSONObject;
    function ReadyPath(Project: TRigmMovieProject; Args: TJSONObject; out Scene: string): string;
    procedure Adopted(Args: TJSONObject);
    procedure CancelAll;
  end;
function MovieImageTransferSchema: TJSONObject;

implementation
uses System.IOUtils, System.Hash, System.NetEncoding, System.Math, Winapi.Windows,
  Vcl.Imaging.pngimage, RigmJson, RigmModel, RigmAppSettings;

function MovieImageTransferSchema: TJSONObject;
begin
  Result := ParseObject('{"image-transfer-begin":{"sceneId":"existing scene","byteCount":"1..33554432","sha256":"64 hex characters","mimeType":"image/png"},'+
    '"image-transfer-chunk":{"transferId":"returned ID","offset":"next accepted byte offset","data":"canonical base64; at most 16384 decoded bytes"},'+
    '"image-transfer-finish":{"transferId":"ID; starts asynchronous hash/decode/publication"},'+
    '"image-transfer-status":{"transferId":"ID; state, acceptedBytes, receivedBytes, nextOffset, path"},'+
    '"image-transfer-cancel":{"transferId":"ID; asynchronous cancellation; completed valid assets retained"},'+
    '"image-transfer-adopt":{"transferId":"ready ID; latest projectId/revision required; no project autosave"}}');
end;

function HexHash(const Value: string): Boolean;
begin
  Result := Length(Value)=64;
  for var C in Value do if not CharInSet(C,['0'..'9','a'..'f','A'..'F']) then Exit(False);
end;

constructor TRigmImageTransfer.Create(Project: TRigmMovieProject; Args: TJSONObject);
begin
  inherited Create(True); FreeOnTerminate := False;
  FLock := TObject.Create; FWake := TEvent.Create(nil,False,False,'');
  FQueue := TQueue<TBytes>.Create; FChunkHashes := TList<string>.Create;
  FExpected := JI(Args,'byteCount'); FHash := LowerCase(JS(Args,'sha256'));
  if (FExpected<1) or (FExpected>RigmImageMaxBytes) then raise ERigm.Create('Image transfer byteCount must be 1..33554432');
  if not HexHash(FHash) then raise ERigm.Create('Image transfer requires a SHA-256 hex digest');
  if JS(Args,'mimeType')<>'image/png' then raise ERigm.Create('Image transfer currently accepts static PNG only');
  for var Key in ['path','fileName','directory','outputPath'] do
    if Args.GetValue(Key)<>nil then raise ERigm.Create('Image transfer destination is derived from the project; paths are not accepted');
  FScene := JS(Args,'sceneId');
  if Project.Scene(FScene)=nil then raise ERigm.Create('Image transfer scene does not exist');
  FProject := Project.Id; FProjectFile := Project.FileName;
  FId := TGUID.NewGuid.ToString.Trim(['{','}']);
  if Project.FileName<>'' then
    FDirectory := TPath.Combine(ExtractFileDir(ExpandFileName(Project.FileName)),TPath.GetFileNameWithoutExtension(Project.FileName)+'.assets\ReceivedImages')
  else FDirectory := TPath.Combine(AppSettings.Root,'Projects\ReceivedImages\'+THashSHA2.GetHashString(Project.Id));
  FDirectory := TPath.GetFullPath(FDirectory);
  if FDirectory.StartsWith('\\') then raise ERigm.Create('Image transfer requires a local project directory');
  FStage := TPath.Combine(TPath.GetTempPath,'RIGM-image-'+GetCurrentProcessId.ToString+'-'+FId+'.partial');
  FState := 'receiving'; FLastActivity := GetTickCount64;
end;

destructor TRigmImageTransfer.Destroy;
begin
  Cancel;
  // TThread starts a never-started suspended thread while destroying it; fields remain alive until it exits.
  inherited;
  FQueue.Free; FChunkHashes.Free; FWake.Free; FLock.Free;
end;

procedure TRigmImageTransfer.CheckCancel;
begin
  if TInterlocked.CompareExchange(FCancel,0,0)<>0 then raise EAbort.Create('Image transfer cancelled');
end;
procedure TRigmImageTransfer.Cancel;
begin
  TInterlocked.Exchange(FCancel,1);
  if FLock<>nil then begin
    TMonitor.Enter(FLock);
    try if FReadyHandle<>0 then begin CloseHandle(FReadyHandle); FReadyHandle := 0; end;
    finally TMonitor.Exit(FLock); end;
  end;
  if FWake<>nil then FWake.SetEvent;
end;

procedure TRigmImageTransfer.Chunk(Args: TJSONObject);
begin
  var Encoded := JS(Args,'data');
  if (Length(Encoded)=0) or (Length(Encoded)>((RigmImageChunkBytes+2) div 3)*4) then raise ERigm.Create('Image chunk is empty or exceeds 16384 bytes');
  var Encoding := TBase64Encoding.Create(0); var Bytes: TBytes; var Canonical: string;
  try Bytes := Encoding.DecodeStringToBytes(Encoded); Canonical := Encoding.EncodeBytesToString(Bytes); finally Encoding.Free; end;
  if (Length(Bytes)=0) or (Length(Bytes)>RigmImageChunkBytes) or
    (Canonical<>Encoded) then raise ERigm.Create('Image chunk must be canonical base64');
  var RawOffset := JN(Args,'offset',-1);
  if IsNan(RawOffset) or IsInfinite(RawOffset) or (RawOffset<0) or (RawOffset>RigmImageMaxBytes) or (Frac(RawOffset)<>0) then raise ERigm.Create('Image offset must be an integer in the declared size range');
  var Offset := Trunc(RawOffset); var ChunkHash := THashSHA2.Create; ChunkHash.Update(Bytes); var Hash := ChunkHash.HashAsString;
  TMonitor.Enter(FLock);
  try
    CheckCancel;
    if FState<>'receiving' then raise ERigm.Create('Image transfer is not receiving');
    if (Offset<0) or (Offset mod RigmImageChunkBytes<>0) then raise ERigm.Create('Image chunk offset is invalid');
    if Offset<FAccepted then begin
      var Index := Offset div RigmImageChunkBytes;
      if (Index>=FChunkHashes.Count) or (FChunkHashes[Index]<>Hash) then raise ERigm.Create('Retried chunk differs from the accepted bytes');
      FLastActivity := GetTickCount64; Exit;
    end;
    if FFinish or (Offset<>FAccepted) then raise ERigm.Create('Image chunk is out of order');
    var ExpectedLength := Min(Int64(RigmImageChunkBytes),FExpected-FAccepted);
    if Length(Bytes)<>ExpectedLength then raise ERigm.Create('Image chunk length does not match declared byteCount');
    if FQueue.Count>=8 then raise ERigm.Create('Image transfer queue is busy; retry the same offset');
    FQueue.Enqueue(Bytes); FChunkHashes.Add(Hash); Inc(FAccepted,Length(Bytes)); FLastActivity := GetTickCount64;
  finally TMonitor.Exit(FLock); end;
  FWake.SetEvent;
end;

procedure TRigmImageTransfer.Finish;
begin
  TMonitor.Enter(FLock);
  try
    CheckCancel;
    if FState='ready' then Exit;
    if FFinish then Exit;
    if (FState<>'receiving') or (FAccepted<>FExpected) then raise ERigm.Create('Image transfer is incomplete');
    FFinish := True; FLastActivity := GetTickCount64;
  finally TMonitor.Exit(FLock); end;
  FWake.SetEvent;
end;

procedure TRigmImageTransfer.Publish;
var Held: TList<THandle>; Pending: string; Pinned: THandle;
  procedure LockDirectories;
  begin
    var Root := TPath.GetPathRoot(FDirectory); var Current := Root;
    for var Part in FDirectory.Substring(Length(Root)).Split(['\']) do begin
      if Part='' then Continue;
      Current := TPath.Combine(Current,Part); CheckCancel;
      if not DirectoryExists(Current) and not CreateDir(Current) then RaiseLastOSError;
      var H := CreateFile(PChar(Current),FILE_READ_ATTRIBUTES,FILE_SHARE_READ or FILE_SHARE_WRITE,nil,
        OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT,0);
      if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
      Held.Add(H); var Info: TByHandleFileInformation;
      if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
      if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('Image destination contains a reparse point');
    end;
  end;
begin
  Held := TList<THandle>.Create; Pending := ''; Pinned := INVALID_HANDLE_VALUE;
  try
    LockDirectories; CheckCancel;
    var Path := TPath.Combine(FDirectory,FHash+'.png');
    if FileExists(Path) then begin
      var Asset := CreateFile(PChar(Path),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
      if Asset=INVALID_HANDLE_VALUE then RaiseLastOSError;
      try
        var Info: TByHandleFileInformation;
        if not GetFileInformationByHandle(Asset,Info) then RaiseLastOSError;
        if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('Existing image asset is a reparse point');
        if not SameText(THashSHA2.GetHashStringFromFile(Path),FHash) then raise ERigm.Create('Existing image asset differs; it will not be overwritten');
      finally CloseHandle(Asset); end;
    end else begin
      Pending := TPath.Combine(FDirectory,FId+'.pending');
      var Input := TFileStream.Create(FStage,fmOpenRead or fmShareDenyWrite);
      try
        var Output := TFileStream.Create(Pending,fmCreate or fmShareExclusive);
        try
          var Buffer: array[0..65535] of Byte;
          repeat CheckCancel; var Count := Input.Read(Buffer,SizeOf(Buffer)); if Count=0 then Break; Output.WriteBuffer(Buffer,Count); until False;
        finally Output.Free; end;
      finally Input.Free; end;
      CheckCancel;
      if not MoveFileEx(PChar(Pending),PChar(Path),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      Pending := '';
    end;
    // Keep validated bytes immutable until adoption/cancellation. Hashing stays on the worker.
    Pinned := CreateFile(PChar(Path),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if Pinned=INVALID_HANDLE_VALUE then RaiseLastOSError;
    var Info: TByHandleFileInformation;
    if not GetFileInformationByHandle(Pinned,Info) then RaiseLastOSError;
    if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('Received image asset is a reparse point');
    if not SameText(THashSHA2.GetHashStringFromFile(Path),FHash) then raise ERigm.Create('Received image asset changed before publication');
    TMonitor.Enter(FLock);
    try CheckCancel; FReadyHandle := Pinned; Pinned := INVALID_HANDLE_VALUE; FPath := Path; FState := 'ready';
    finally TMonitor.Exit(FLock); end;
  finally
    if Pinned<>INVALID_HANDLE_VALUE then CloseHandle(Pinned);
    if (Pending<>'') and FileExists(Pending) then TFile.Delete(Pending);
    for var H in Held do CloseHandle(H); Held.Free;
  end;
end;

procedure TRigmImageTransfer.Execute;
var Stream: TFileStream;
begin
  Stream := nil;
  try
    try
      CheckCancel;
      Stream := TFileStream.Create(FStage,fmCreate or fmShareExclusive);
      var Hash := THashSHA2.Create;
      repeat
        CheckCancel; var Data: TBytes := nil; var Finishing := False;
        TMonitor.Enter(FLock);
        try
          if GetTickCount64-UInt64(FLastActivity)>120000 then raise EAbort.Create('Image transfer expired after 120 seconds without data');
          if FQueue.Count>0 then Data := FQueue.Dequeue else Finishing := FFinish;
        finally TMonitor.Exit(FLock); end;
        if Length(Data)>0 then begin
          Stream.WriteBuffer(Data[0],Length(Data)); Hash.Update(Data);
          TMonitor.Enter(FLock); try Inc(FReceived,Length(Data)); finally TMonitor.Exit(FLock); end;
        end else if Finishing then Break else FWake.WaitFor(100);
      until False;
      TMonitor.Enter(FLock); try FState := 'validating'; finally TMonitor.Exit(FLock); end;
      FreeAndNil(Stream); CheckCancel;
      if not SameText(Hash.HashAsString,FHash) then raise ERigm.Create('Image SHA-256 does not match the declared digest');
      var Header: array[0..32] of Byte;
      Stream := TFileStream.Create(FStage,fmOpenRead or fmShareDenyWrite);
      if Stream.Size<SizeOf(Header) then raise ERigm.Create('PNG header is incomplete');
      Stream.ReadBuffer(Header,SizeOf(Header));
      if (Header[0]<>137) or (Header[1]<>80) or (Header[2]<>78) or (Header[3]<>71) or
        (Header[4]<>13) or (Header[5]<>10) or (Header[6]<>26) or (Header[7]<>10) or
        (Header[8]<>0) or (Header[9]<>0) or (Header[10]<>0) or (Header[11]<>13) or
        (Header[12]<>73) or (Header[13]<>72) or (Header[14]<>68) or (Header[15]<>82) then raise ERigm.Create('Image is not a valid PNG');
      var Width := UInt64(Header[16])*16777216+UInt64(Header[17])*65536+UInt64(Header[18])*256+Header[19];
      var Height := UInt64(Header[20])*16777216+UInt64(Header[21])*65536+UInt64(Header[22])*256+Header[23];
      if (Width=0) or (Height=0) or (Width>8192) or (Height>8192) or (Width*Height>16777216) then raise ERigm.Create('PNG exceeds 8192 per dimension or 16 megapixels');
      Stream.Position := 8; var EndFound := False;
      while Stream.Position<Stream.Size do begin
        CheckCancel; var ChunkHeader: array[0..7] of Byte;
        if Stream.Size-Stream.Position<12 then raise ERigm.Create('PNG chunk is truncated');
        Stream.ReadBuffer(ChunkHeader,SizeOf(ChunkHeader));
        var ChunkLength := UInt64(ChunkHeader[0])*16777216+UInt64(ChunkHeader[1])*65536+UInt64(ChunkHeader[2])*256+ChunkHeader[3];
        if ChunkLength>UInt64(Stream.Size-Stream.Position-4) then raise ERigm.Create('PNG chunk exceeds the file');
        var Kind := string(Char(ChunkHeader[4]))+Char(ChunkHeader[5])+Char(ChunkHeader[6])+Char(ChunkHeader[7]);
        if Kind='acTL' then raise ERigm.Create('Animated PNG is not supported by image transfer');
        Stream.Position := Stream.Position+Int64(ChunkLength)+4;
        if Kind='IEND' then begin
          if (ChunkLength<>0) or (Stream.Position<>Stream.Size) then raise ERigm.Create('PNG end chunk is invalid');
          EndFound := True; Break;
        end;
      end;
      if not EndFound then raise ERigm.Create('PNG end chunk is missing');
      Stream.Position := 0; var Image := TPngImage.Create; Image.CheckCRC := True;
      try Image.LoadFromStream(Stream); FWidth := Image.Width; FHeight := Image.Height; finally Image.Free; end;
      FreeAndNil(Stream); CheckCancel; Publish;
    except
      on E: Exception do begin
        TMonitor.Enter(FLock);
        try FError := E.Message; if E is EAbort then FState := 'cancelled' else FState := 'failed';
        finally TMonitor.Exit(FLock); end;
      end;
    end;
  finally
    Stream.Free;
    if FileExists(FStage) then TFile.Delete(FStage);
  end;
end;

function TRigmImageTransfer.Status: TJSONObject;
begin
  Result := TJSONObject.Create; TMonitor.Enter(FLock);
  try
    Result.AddPair('transferId',FId); Result.AddPair('projectId',FProject); Result.AddPair('sceneId',FScene);
    Result.AddPair('state',FState); Result.AddPair('error',FError); Result.AddPair('sha256',FHash);
    AddN(Result,'byteCount',FExpected); AddN(Result,'acceptedBytes',FAccepted); AddN(Result,'receivedBytes',FReceived);
    AddN(Result,'nextOffset',FAccepted); AddN(Result,'chunkBytes',RigmImageChunkBytes); AddN(Result,'queueChunks',FQueue.Count);
    AddN(Result,'width',FWidth); AddN(Result,'height',FHeight); Result.AddPair('path',FPath);
    AddB(Result,'adopted',FAdopted); AddB(Result,'cancelRequested',TInterlocked.CompareExchange(FCancel,0,0)<>0);
    AddB(Result,'workerExited',Finished); AddB(Result,'projectAutosaved',False);
  finally TMonitor.Exit(FLock); end;
end;
function TRigmImageTransfer.ReadyPath(Project: TRigmMovieProject): string;
begin
  TMonitor.Enter(FLock);
  try
    if (FProject<>Project.Id) or not SameText(FProjectFile,Project.FileName) then raise ERigm.Create('Image transfer belongs to another project or save location');
    if FState<>'ready' then raise ERigm.Create('Image transfer is not ready for adoption');
    if FAdopted then raise ERigm.Create('Image transfer was already adopted; undo does not silently re-adopt it');
    CheckCancel;
    if not FileExists(FPath) then raise ERigm.Create('Received image asset is missing');
    var Current := CreateFile(PChar(FPath),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if Current=INVALID_HANDLE_VALUE then RaiseLastOSError;
    try
      var OriginalInfo,CurrentInfo: TByHandleFileInformation;
      if not GetFileInformationByHandle(FReadyHandle,OriginalInfo) or not GetFileInformationByHandle(Current,CurrentInfo) then RaiseLastOSError;
      if (CurrentInfo.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('Received image asset was replaced by a reparse point');
      if (OriginalInfo.dwVolumeSerialNumber<>CurrentInfo.dwVolumeSerialNumber) or
        (OriginalInfo.nFileIndexHigh<>CurrentInfo.nFileIndexHigh) or (OriginalInfo.nFileIndexLow<>CurrentInfo.nFileIndexLow) then
        raise ERigm.Create('Received image asset path changed before adoption');
    finally CloseHandle(Current); end;
    Result := FPath;
  finally TMonitor.Exit(FLock); end;
end;
procedure TRigmImageTransfer.Adopted;
begin
  TMonitor.Enter(FLock);
  try FAdopted := True; if FReadyHandle<>0 then begin CloseHandle(FReadyHandle); FReadyHandle := 0; end;
  finally TMonitor.Exit(FLock); end;
end;
function TRigmImageTransfer.Terminal: Boolean;
begin TMonitor.Enter(FLock); try Result := Finished and ((FState<>'ready') or FAdopted or (TInterlocked.CompareExchange(FCancel,0,0)<>0)); finally TMonitor.Exit(FLock); end; end;

constructor TRigmImageTransfers.Create;
begin inherited; FItems := TObjectDictionary<string,TRigmImageTransfer>.Create([doOwnsValues]); FOrder := TList<string>.Create; end;
destructor TRigmImageTransfers.Destroy;
begin CancelAll; FItems.Free; FOrder.Free; inherited; end;
procedure TRigmImageTransfers.CancelAll;
begin for var Pair in FItems do Pair.Value.Cancel; end;
function TRigmImageTransfers.Item(const Id: string): TRigmImageTransfer;
begin if not FItems.TryGetValue(Id,Result) then raise ERigm.Create('Image transfer ID does not belong to this session'); end;
function TRigmImageTransfers.BeginTransfer(Project: TRigmMovieProject; Args: TJSONObject): TJSONObject;
begin
  for var I := FOrder.Count-1 downto 0 do if Item(FOrder[I]).Terminal then begin FItems.Remove(FOrder[I]); FOrder.Delete(I); end;
  if FItems.Count>=8 then raise ERigm.Create('Too many image transfers; adopt or cancel the ready assets first');
  var Active := 0; for var Pair in FItems do if not Pair.Value.Finished then Inc(Active);
  if Active>=2 then raise ERigm.Create('At most two image transfers may run concurrently');
  var Transfer := TRigmImageTransfer.Create(Project,Args);
  FItems.Add(Transfer.Id,Transfer); FOrder.Add(Transfer.Id); Transfer.Start; Result := Transfer.Status;
end;
function TRigmImageTransfers.Execute(const Command: string; Args: TJSONObject): TJSONObject;
begin
  var Transfer := Item(JS(Args,'transferId'));
  if Command='image-transfer-chunk' then Transfer.Chunk(Args)
  else if Command='image-transfer-finish' then Transfer.Finish
  else if Command='image-transfer-cancel' then Transfer.Cancel
  else if Command<>'image-transfer-status' then raise ERigm.Create('Unknown image transfer command');
  Result := Transfer.Status;
end;
function TRigmImageTransfers.ReadyPath(Project: TRigmMovieProject; Args: TJSONObject; out Scene: string): string;
begin var Transfer := Item(JS(Args,'transferId')); Scene := Transfer.Scene; Result := Transfer.ReadyPath(Project); end;
procedure TRigmImageTransfers.Adopted(Args: TJSONObject);
begin Item(JS(Args,'transferId')).Adopted; end;
end.
