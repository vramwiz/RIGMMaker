unit RigmThumbnailCache;

// 永続サムネイルは作業Tempと分離。ワーカーはUIを参照せず、UI側から結果を回収する。
interface
uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.SyncObjs,
  PsdWorkspace;
type
  TRigmThumbnailEntry = class
  public
    Signature: string; Metadata: TJSONObject; Pixels: TBytes; Width,Height: Integer; RetryAfter: UInt64;
    constructor Create;
    destructor Destroy; override;
  end;
  TRigmThumbnailJob = class
  public
    Path,Signature,Key: string; Entry: TRigmThumbnailEntry;
    destructor Destroy; override;
  end;
  TRigmThumbnailCache = class;
  TRigmThumbnailWorker = class(TThread)
  private
    FOwner: TRigmThumbnailCache;
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TRigmThumbnailCache);
  end;
  TRigmThumbnailCache = class
  private
    FWorkspace: TPsdWorkspace;
    FLock: TCriticalSection; FWake: TEvent; FWorker: TRigmThumbnailWorker;
    FQueue,FCompleted: TQueue<TRigmThumbnailJob>; FPending: TDictionary<string,Boolean>;
    FEntries: TObjectDictionary<string,TRigmThumbnailEntry>;
    FPackageReads,FGenerated,FDiskHits: Integer;
    function KeyFor(const Path: string): string;
    function LoadDisk(const Path,Signature,Key: string): TRigmThumbnailEntry;
    procedure SaveDisk(const Path,Key: string; Entry: TRigmThumbnailEntry);
    procedure Generate(Job: TRigmThumbnailJob);
    procedure Drain;
  public
    constructor Create(const Root: string);
    destructor Destroy; override;
    function Request(const Path: string): TRigmThumbnailEntry; // 借用。nilはバックグラウンド処理中。
    function Stats: TJSONObject;
    function CachePath(const Path: string): string;
  end;
function CharacterSourceSignature(const Path: string): string;
implementation
uses Winapi.Windows, Winapi.ActiveX, System.IOUtils, System.Hash, System.StrUtils,
  RigmCharacterCatalog, RigmStorage, RigmJson, PsdJson, PsdPackage, PsdCharacter, PsdAnimation, PsdProduction;
type
  TSourceBasicInfo = record
    CreationTime,LastAccessTime,LastWriteTime,ChangeTime: Int64;
    Attributes: DWORD;
  end;
function ThumbnailFileInformationEx(Handle: THandle; InfoClass: Integer; Buffer: Pointer; Size: DWORD): BOOL; stdcall;
  external kernel32 name 'GetFileInformationByHandleEx';
function CharacterSourceSignature(const Path: string): string;
begin
  var H := CreateFile(PChar(Path),FILE_READ_ATTRIBUTES,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
  if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    var Info: TByHandleFileInformation;
    if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
    var Basic: TSourceBasicInfo; FillChar(Basic,SizeOf(Basic),0);
    // NTFSのChangeTimeはLastWriteTimeを元に戻した書換えも識別する。
    ThumbnailFileInformationEx(H,0,@Basic,SizeOf(Basic));
    Result := IntToHex(Info.dwVolumeSerialNumber,8)+':'+IntToHex(Info.nFileIndexHigh,8)+IntToHex(Info.nFileIndexLow,8)+':'+
      IntToHex(Info.nFileSizeHigh,8)+IntToHex(Info.nFileSizeLow,8)+':'+
      IntToHex(Info.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Info.ftLastWriteTime.dwLowDateTime,8)+':'+IntToHex(Basic.ChangeTime,16);
  finally CloseHandle(H); end;
end;
constructor TRigmThumbnailEntry.Create;
begin inherited; Metadata := TJSONObject.Create; end;
destructor TRigmThumbnailEntry.Destroy;
begin Metadata.Free; inherited; end;
destructor TRigmThumbnailJob.Destroy;
begin Entry.Free; inherited; end;
constructor TRigmThumbnailWorker.Create(Owner: TRigmThumbnailCache);
begin inherited Create(True); FreeOnTerminate := False; FOwner := Owner; end;
procedure TRigmThumbnailWorker.Execute;
begin
  CoInitialize(nil);
  try
    while not Terminated do begin
      var Job: TRigmThumbnailJob := nil;
      FOwner.FLock.Acquire;
      try if FOwner.FQueue.Count>0 then Job := FOwner.FQueue.Dequeue; finally FOwner.FLock.Release; end;
      if Job=nil then begin FOwner.FWake.WaitFor(200); Continue; end;
      try
        FOwner.Generate(Job);
      except on E: Exception do begin
        Job.Entry.Free; Job.Entry := TRigmThumbnailEntry.Create; Job.Entry.Signature := Job.Signature;
        Job.Entry.RetryAfter := GetTickCount64+2000;
        Job.Entry.Metadata.AddPair('name',TPath.GetFileNameWithoutExtension(Job.Path));
        Job.Entry.Metadata.AddPair('renderFormat',CharacterFormat(Job.Path));
        Job.Entry.Metadata.AddPair('readyForScript',TJSONBool.Create(False));
        Job.Entry.Metadata.AddPair('productionReason','読込不可: '+E.Message);
        Job.Entry.Metadata.AddPair('productionState','読込不可');
      end; end;
      FOwner.FLock.Acquire;
      try FOwner.FPending.Remove(Job.Path); FOwner.FCompleted.Enqueue(Job); finally FOwner.FLock.Release; end;
    end;
  finally CoUninitialize; end;
end;
constructor TRigmThumbnailCache.Create(const Root: string);
begin
  inherited Create; FWorkspace := TPsdWorkspace.Create(Root);
  FLock := TCriticalSection.Create; FWake := TEvent.Create(nil,False,False,'');
  FQueue := TQueue<TRigmThumbnailJob>.Create; FCompleted := TQueue<TRigmThumbnailJob>.Create;
  FPending := TDictionary<string,Boolean>.Create;
  FEntries := TObjectDictionary<string,TRigmThumbnailEntry>.Create([doOwnsValues]);
  FWorker := TRigmThumbnailWorker.Create(Self);
  FWorker.Start;
end;
destructor TRigmThumbnailCache.Destroy;
begin
  if FWorker<>nil then begin FWorker.Terminate; FWake.SetEvent; FWorker.WaitFor; FWorker.Free; end;
  if FQueue<>nil then while FQueue.Count>0 do FQueue.Dequeue.Free;
  if FCompleted<>nil then while FCompleted.Count>0 do FCompleted.Dequeue.Free;
  FEntries.Free; FPending.Free; FQueue.Free; FCompleted.Free; FWake.Free; FLock.Free; FWorkspace.Free; inherited;
end;
function TRigmThumbnailCache.KeyFor(const Path: string): string;
begin
  Result := THashSHA2.GetHashString('RIGMMaker.Thumbnail.v1|'+CharacterFormat(Path)+'|'+
    LowerCase(Path.Substring(Length(IncludeTrailingPathDelimiter(FWorkspace.Root)))));
end;
function TRigmThumbnailCache.CachePath(const Path: string): string;
begin Result := FWorkspace.Resolve('Cache\CharacterThumbnails\v1\'+KeyFor(FWorkspace.Resolve(Path))+'.thumb',False); end;
function TRigmThumbnailCache.LoadDisk(const Path,Signature,Key: string): TRigmThumbnailEntry;
begin
  Result := nil; var FileName := FWorkspace.Resolve('Cache\CharacterThumbnails\v1\'+Key+'.thumb',False);
  if not FileExists(FileName) then Exit;
  var H := CreateFile(PChar(FileName),GENERIC_READ,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
  if H=INVALID_HANDLE_VALUE then Exit;
  var Stream := THandleStream.Create(H); var O: TJSONObject := nil; var Entry: TRigmThumbnailEntry := nil;
  try
    try
      if (Stream.Size<4) or (Stream.Size>8*1024*1024) then Exit;
      var Size: Integer; Stream.ReadBuffer(Size,SizeOf(Size));
      if (Size<1) or (Size>32768) or (Size>Stream.Size-4) then Exit;
      var Header: TBytes; SetLength(Header,Size); Stream.ReadBuffer(Header[0],Size);
      O := PsdJson.ObjectText(TEncoding.UTF8.GetString(Header));
      if (JS(O,'owner')<>'RIGMMaker.CharacterThumbnails.v1') or (JS(O,'key')<>Key) or
        (JS(O,'signature')<>Signature) or (JS(O,'renderFormat')<>CharacterFormat(Path)) then Exit;
      Entry := TRigmThumbnailEntry.Create; Entry.Width := JI(O,'width'); Entry.Height := JI(O,'height');
      if (Entry.Width<1) or (Entry.Height<1) or (Entry.Width>2048) or (Entry.Height>2048) or
        (Int64(Entry.Width)*Entry.Height*4<>Stream.Size-Stream.Position) then Exit;
      SetLength(Entry.Pixels,Entry.Width*Entry.Height*4); Stream.ReadBuffer(Entry.Pixels[0],Length(Entry.Pixels));
      var Hash := THashSHA2.Create; Hash.Update(Entry.Pixels);
      if Hash.HashAsString<>JS(O,'pixelsSha256') then Exit;
      Entry.Metadata.Free; Entry.Metadata := JO(O,'metadata').Clone as TJSONObject; Entry.Signature := Signature;
      if THashSHA2.GetHashString(Entry.Metadata.ToJSON)<>JS(O,'metadataSha256') then Exit;
      if (JS(Entry.Metadata,'sourceId')='') or not (Entry.Metadata.GetValue('readyForScript') is TJSONBool) then Exit;
      Result := Entry; Entry := nil;
      FLock.Acquire; try Inc(FDiskHits); finally FLock.Release; end;
    except Result := nil; end;
  finally Entry.Free; O.Free; Stream.Free; CloseHandle(H); end;
end;
procedure TRigmThumbnailCache.SaveDisk(const Path,Key: string; Entry: TRigmThumbnailEntry);
begin
  var FileName := FWorkspace.Resolve('Cache\CharacterThumbnails\v1\'+Key+'.thumb',False);
  ForceDirectories(ExtractFileDir(FileName)); var O := TJSONObject.Create;
  var Pending := FWorkspace.Resolve('Cache\CharacterThumbnails\v1\'+Key+'.'+PsdJson.NewId+'.pending',False);
  try
    O.AddPair('owner','RIGMMaker.CharacterThumbnails.v1'); O.AddPair('key',Key); O.AddPair('signature',Entry.Signature);
    O.AddPair('sourcePath',Path.Substring(Length(IncludeTrailingPathDelimiter(FWorkspace.Root))));
    O.AddPair('renderFormat',CharacterFormat(Path)); O.AddPair('width',TJSONNumber.Create(Entry.Width)); O.AddPair('height',TJSONNumber.Create(Entry.Height));
    var Hash := THashSHA2.Create; Hash.Update(Entry.Pixels); O.AddPair('pixelsSha256',Hash.HashAsString);
    O.AddPair('metadata',Entry.Metadata.Clone as TJSONObject);
    O.AddPair('metadataSha256',THashSHA2.GetHashString(Entry.Metadata.ToJSON));
    var Header := TEncoding.UTF8.GetBytes(O.ToJSON); var Size: Integer := Length(Header);
    var Stream := TFileStream.Create(Pending,fmCreate);
    try Stream.WriteBuffer(Size,SizeOf(Size)); Stream.WriteBuffer(Header[0],Size); Stream.WriteBuffer(Entry.Pixels[0],Length(Entry.Pixels)); finally Stream.Free; end;
    if not MoveFileEx(PChar(Pending),PChar(FileName),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally O.Free; end; // 失敗した所有pendingもCache内に保持。原本/Temp回収は変更しない。
end;
procedure TRigmThumbnailCache.Generate(Job: TRigmThumbnailJob);
begin
  var Mutex := CreateMutex(nil,False,PChar('Local\RIGMMaker.Thumbnail.'+THashSHA2.GetHashString(FWorkspace.Root+'|'+Job.Key)));
  if Mutex=0 then RaiseLastOSError;
  var Acquired := False;
  try
    while not FWorker.Terminated do begin
      var Wait := WaitForSingleObject(Mutex,200);
      if (Wait=WAIT_OBJECT_0) or (Wait=WAIT_ABANDONED) then begin Acquired := True; Break; end;
      if Wait=WAIT_FAILED then RaiseLastOSError;
    end;
    if not Acquired then Exit;
    if CharacterSourceSignature(Job.Path)<>Job.Signature then raise Exception.Create('素材が変更されました。');
    Job.Entry := LoadDisk(Job.Path,Job.Signature,Job.Key); if Job.Entry<>nil then Exit;
    var SourceJob := FWorkspace.BeginJob;
    try
      if CharacterSourceSignature(Job.Path)<>Job.Signature then raise Exception.Create('素材が変更されました。');
      var Snapshot := SourceJob.FilePath('thumbnail-source'+ExtractFileExt(Job.Path));
      var H := CreateFile(PChar(Job.Path),GENERIC_READ,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
      if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
      var Input := THandleStream.Create(H);
      try
        if Input.Size>256*1024*1024 then raise Exception.Create('Thumbnail source size limit');
        var Output := TFileStream.Create(Snapshot,fmCreate);
        try Output.CopyFrom(Input,0); finally Output.Free; end;
      finally Input.Free; CloseHandle(H); end;
      if CharacterSourceSignature(Job.Path)<>Job.Signature then raise Exception.Create('素材が変更されました。');
      FLock.Acquire; try Inc(FPackageReads); finally FLock.Release; end;
      Job.Entry := TRigmThumbnailEntry.Create; Job.Entry.Signature := Job.Signature;
      var Reason := ''; var Ready: Boolean; var Name,Id,State: string;
      if CharacterFormat(Job.Path)='psd' then begin
        var C := LoadCharacter(FWorkspace,Snapshot);
        try
          Name := C.Name; Id := C.Id; Ready := PsdReadyForScript(C,Reason);
          var Renderer := TPsdRenderer.Create(C,FWorkspace,480);
          try
            var Frame := TPsdFrameState.Default; Frame.AutoBlink := False; Frame.Motion := 'none';
            Job.Entry.Pixels := Renderer.Composite(Frame); Job.Entry.Width := Renderer.Document.Width; Job.Entry.Height := Renderer.Document.Height;
          finally Renderer.Free; end;
        finally C.Free; end;
      end else begin
        var D := LoadRigm(Snapshot);
        try Name := D.Name; Id := D.FileId; Ready := D.Usable; finally D.Free; end;
        if not Ready then Reason := 'RIGMの完成チェックが完了していません。';
        Job.Entry.Pixels := ReadRigmThumbnail(Snapshot,Name,Job.Entry.Width,Job.Entry.Height);
      end;
      State := '未完成'; if Ready then State := '検査済み';
      Job.Entry.Metadata.AddPair('name',Name); Job.Entry.Metadata.AddPair('sourceId',Id);
      Job.Entry.Metadata.AddPair('renderFormat',CharacterFormat(Job.Path));
      Job.Entry.Metadata.AddPair('readyForScript',TJSONBool.Create(Ready)); Job.Entry.Metadata.AddPair('productionReason',Reason);
      Job.Entry.Metadata.AddPair('productionState',State);
      if CharacterSourceSignature(Job.Path)<>Job.Signature then raise Exception.Create('素材が変更されました。');
      try SaveDisk(Job.Path,Job.Key,Job.Entry); except on E: Exception do Job.Entry.Metadata.AddPair('cacheError',E.Message); end;
      FLock.Acquire; try Inc(FGenerated); finally FLock.Release; end;
    finally SourceJob.Free; end;
  finally if Acquired then ReleaseMutex(Mutex); CloseHandle(Mutex); end;
end;
procedure TRigmThumbnailCache.Drain;
begin
  repeat
    var Job: TRigmThumbnailJob := nil; FLock.Acquire;
    try if FCompleted.Count>0 then Job := FCompleted.Dequeue; finally FLock.Release; end;
    if Job=nil then Break;
    try
      if Job.Entry<>nil then begin FEntries.AddOrSetValue(Job.Path,Job.Entry); Job.Entry := nil; end;
    finally Job.Free; end;
  until False;
end;
function TRigmThumbnailCache.Request(const Path: string): TRigmThumbnailEntry;
begin
  Drain; var FullPath := FWorkspace.Resolve(Path); var Signature := CharacterSourceSignature(FullPath);
  if FEntries.TryGetValue(FullPath,Result) and (Result.Signature=Signature) and
    ((Result.RetryAfter=0) or (GetTickCount64<Result.RetryAfter)) then Exit;
  FLock.Acquire;
  try if FPending.ContainsKey(FullPath) then begin Result := nil; Exit; end; finally FLock.Release; end;
  var Key := KeyFor(FullPath); Result := LoadDisk(FullPath,Signature,Key);
  if Result<>nil then begin FEntries.AddOrSetValue(FullPath,Result); Exit; end;
  FLock.Acquire;
  try
    if not FPending.ContainsKey(FullPath) then begin
      var Job := TRigmThumbnailJob.Create; Job.Path := FullPath; Job.Signature := Signature; Job.Key := Key;
      FPending.Add(FullPath,True); FQueue.Enqueue(Job); FWake.SetEvent;
    end;
  finally FLock.Release; end;
  Result := nil;
end;
function TRigmThumbnailCache.Stats: TJSONObject;
begin
  Result := TJSONObject.Create; FLock.Acquire;
  try
    Result.AddPair('packageReads',TJSONNumber.Create(FPackageReads)); Result.AddPair('generated',TJSONNumber.Create(FGenerated));
    Result.AddPair('diskHits',TJSONNumber.Create(FDiskHits)); Result.AddPair('pending',TJSONNumber.Create(FPending.Count));
    Result.AddPair('cacheRoot',FWorkspace.Resolve('Cache\CharacterThumbnails\v1',False));
  finally FLock.Release; end;
end;
end.
