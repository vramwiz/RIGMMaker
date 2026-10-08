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
    FId,FProject,FProjectFile,FScene,FHash,FDirectory,FStage,FPath,FState,FError,FSceneKey: string;
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
function CheckedMovieImageHash(const Path: string; Force: Boolean=False): string;
function CopyCheckedMovieImage(const Source,Directory: string; const ExpectedHash: string=''): string;

implementation
uses System.ZLib, System.IOUtils, System.Hash, System.NetEncoding, System.Math, Winapi.Windows,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, System.StrUtils, PsdJson, RigmJson, RigmModel, RigmAppSettings;

type
  TCheckedImage = record Stamp,Hash: string; end;
var ImageChecks: TDictionary<string,TCheckedImage>;
    ImageCheckLock: TObject;

function LocalImagePath(const Path: string): string;
begin
  var P := Path.Replace('/','\');
  if (Length(P)<4) or (P[2]<>':') or (P[3]<>'\') or P.StartsWith('\\') then raise ERigm.Create('Local absolute image path required');
  if (Pos(#0,P)>0) or (Pos('*',P)>0) or (Pos('?',P)>0) or (Pos(':',P.Substring(2))>0) then raise ERigm.Create('Invalid image path');
  for var Part in P.Substring(3).Split(['\']) do begin
    if (Part='') or (Part='.') or (Part='..') or Part.EndsWith('.') or Part.EndsWith(' ') then raise ERigm.Create('Ambiguous image path component');
    var Device := UpperCase(Part.Split(['.'])[0]);
    if MatchStr(Device,['CON','PRN','AUX','NUL']) or
      ((Length(Device)=4) and (Device.StartsWith('COM') or Device.StartsWith('LPT')) and CharInSet(Device[4],['0'..'9'])) then raise ERigm.Create('Reserved image path');
  end;
  Result := TPath.GetFullPath(P);
end;
procedure HoldImageDirectories(const Directory: string; Held: TList<THandle>; CreateMissing: Boolean);
begin
  // Keep D:\ rooted: D: would resolve relative to that drive's current directory.
  var Root := TPath.GetPathRoot(Directory); var Current := Root;
  for var Part in Directory.Substring(Length(Root)).Split(['\']) do begin
    if Part='' then Continue; Current := TPath.Combine(Current,Part);
    if CreateMissing and not DirectoryExists(Current) and not CreateDir(Current) then RaiseLastOSError;
    var H := CreateFile(PChar(Current),FILE_READ_ATTRIBUTES,FILE_SHARE_READ or FILE_SHARE_WRITE,nil,
      OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT,0);
    if H=INVALID_HANDLE_VALUE then RaiseLastOSError; Held.Add(H);
    var Info: TByHandleFileInformation; if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
    if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('Image path contains a reparse point');
  end;
end;
procedure CheckPngPixels(Data: TMemoryStream; W,H,Depth,Color: Integer);
begin
  var Channels := 1; case Color of 2: Channels := 3; 4: Channels := 2; 6: Channels := 4; end;
  var RowBytes := (Int64(W)*Channels*Depth+7) div 8+1; var Expected := RowBytes*H;
  if Data.Size=0 then raise ERigm.Create('PNG pixel data is missing');
  var Z: z_stream; Z := Default(z_stream); Z.next_in := Data.Memory; Z.avail_in := Data.Size;
  if inflateInit(Z)<>Z_OK then raise ERigm.Create('PNG zlib initialization failed');
  try
    var Buffer: array[0..65535] of Byte; var Total: Int64 := 0; var Status := Z_OK;
    repeat
      var BeforeIn := Z.total_in; var BeforeOut := Z.total_out;
      Z.next_out := @Buffer[0]; Z.avail_out := SizeOf(Buffer); Status := inflate(Z,Z_NO_FLUSH);
      var Produced := SizeOf(Buffer)-Integer(Z.avail_out);
      if Total+Produced>Expected then raise ERigm.Create('PNG expands beyond declared pixels');
      for var I := 0 to Produced-1 do if ((Total+I) mod RowBytes=0) and (Buffer[I]>4) then raise ERigm.Create('Invalid PNG scanline filter');
      Inc(Total,Produced);
      if (Status<>Z_OK) and (Status<>Z_STREAM_END) then raise ERigm.Create('Invalid or incomplete PNG zlib stream');
      if (Status=Z_OK) and (BeforeIn=Z.total_in) and (BeforeOut=Z.total_out) then raise ERigm.Create('PNG decompression made no progress');
    until Status=Z_STREAM_END;
    if (Total<>Expected) or (Z.avail_in<>0) then raise ERigm.Create('PNG pixels or compressed stream extent differs from header');
  finally inflateEnd(Z); end;
end;
procedure ImageHeader(Stream: TStream; const Extension: string);
  procedure Dimensions(W,H: Int64);
  begin if (W<1) or (H<1) or (W>8192) or (H>8192) or (W*H>16777216) then raise ERigm.Create('Image exceeds 8192 per dimension or 16 megapixels'); end;
  function BE32(const B: array of Byte; Offset: Integer): UInt64;
  begin Result := UInt64(B[Offset])*16777216+UInt64(B[Offset+1])*65536+UInt64(B[Offset+2])*256+B[Offset+3]; end;
begin
  if (Stream.Size<1) or (Stream.Size>RigmImageMaxBytes) then raise ERigm.Create('Image must be 1..33554432 bytes');
  Stream.Position := 0;
  if Extension='.png' then begin
    var Header: array[0..32] of Byte; Stream.ReadBuffer(Header,SizeOf(Header));
    if (Header[0]<>137) or (Header[1]<>80) or (Header[2]<>78) or (Header[3]<>71) or
      (Header[4]<>13) or (Header[5]<>10) or (Header[6]<>26) or (Header[7]<>10) or
      (BE32(Header,8)<>13) or (Header[12]<>73) or (Header[13]<>72) or (Header[14]<>68) or (Header[15]<>82) then raise ERigm.Create('Invalid PNG header');
    Dimensions(BE32(Header,16),BE32(Header,20));
    var Depth := Header[24]; var Color := Header[25];
    if not (((Color=0) and (Depth in [1,2,4,8,16])) or ((Color=2) and (Depth in [8,16])) or
      ((Color=3) and (Depth in [1,2,4,8])) or ((Color in [4,6]) and (Depth in [8,16]))) or
      (Header[26]<>0) or (Header[27]<>0) or (Header[28]<>0) then raise ERigm.Create('Unsupported PNG encoding');
    Stream.Position := 8; var EndFound := False; var HeaderFound := False; var Chunks := 0;
    var IdatSeen := False; var IdatEnded := False; var PaletteSeen := False; var TransparencySeen := False;
    var Pixels := TMemoryStream.Create;
    try
    while Stream.Position<Stream.Size do begin
      Inc(Chunks); if Chunks>4096 then raise ERigm.Create('PNG has too many chunks');
      var B: array[0..7] of Byte; if Stream.Size-Stream.Position<12 then raise ERigm.Create('Truncated PNG chunk'); Stream.ReadBuffer(B,8);
      var Count := BE32(B,0); if Count>UInt64(Stream.Size-Stream.Position-4) then raise ERigm.Create('PNG chunk exceeds file');
      var Kind := string(Char(B[4]))+Char(B[5])+Char(B[6])+Char(B[7]);
      if Kind='IHDR' then begin
        if HeaderFound or (Chunks<>1) or (Count<>13) then raise ERigm.Create('Duplicate or misplaced PNG header'); HeaderFound := True;
      // caBX is opaque provenance metadata in generated PNGs. Preserve it, check
      // its bounds and CRC below, and never interpret or decompress its payload.
      end else if not MatchStr(Kind,['PLTE','IDAT','IEND','tRNS','gAMA','cHRM','sRGB','pHYs','tEXt','sBIT','bKGD','tIME','caBX']) then
        raise ERigm.Create('Unsupported PNG chunk: '+Kind+' (animated/compressed metadata is excluded)');
      if (Kind='PLTE') and ((Count=0) or (Count>768) or (Count mod 3<>0)) then raise ERigm.Create('Invalid PNG palette');
      if (Kind='tRNS') and (Count>256) then raise ERigm.Create('Invalid PNG transparency');
      if ((Kind='gAMA') and (Count<>4)) or ((Kind='cHRM') and (Count<>32)) or ((Kind='sRGB') and (Count<>1)) or
        ((Kind='pHYs') and (Count<>9)) or ((Kind='sBIT') and (Count>4)) or ((Kind='bKGD') and (Count>6)) or
        ((Kind='tIME') and (Count<>7)) then raise ERigm.Create('Invalid PNG metadata');
      if Kind='PLTE' then begin
        if PaletteSeen or IdatSeen then raise ERigm.Create('Duplicate or misplaced PNG palette'); PaletteSeen := True;
      end;
      if Kind='tRNS' then begin
        if TransparencySeen or IdatSeen then raise ERigm.Create('Duplicate or misplaced PNG transparency'); TransparencySeen := True;
      end;
      if Kind='IDAT' then begin
        if IdatEnded then raise ERigm.Create('PNG IDAT chunks must be consecutive'); IdatSeen := True;
        if (Color=3) and not PaletteSeen then raise ERigm.Create('Indexed PNG palette is missing');
      end else if IdatSeen then IdatEnded := True;
      var CRC := System.ZLib.crc32(0,@B[4],4); var Remaining := Count;
      var Buffer: array[0..32767] of Byte;
      while Remaining>0 do begin
        var N := Integer(Min(Remaining,UInt64(SizeOf(Buffer)))); Stream.ReadBuffer(Buffer,N);
        CRC := System.ZLib.crc32(CRC,@Buffer[0],N);
        if Kind='IDAT' then Pixels.WriteBuffer(Buffer,N); Dec(Remaining,N);
      end;
      var StoredCRC: array[0..3] of Byte; Stream.ReadBuffer(StoredCRC,4);
      if CRC<>BE32(StoredCRC,0) then raise ERigm.Create('PNG chunk CRC mismatch');
      if Kind='IEND' then begin if (Count<>0) or (Stream.Position<>Stream.Size) then raise ERigm.Create('Invalid PNG end'); EndFound := True; Break; end;
    end;
    if not EndFound then raise ERigm.Create('PNG end is missing');
    CheckPngPixels(Pixels,BE32(Header,16),BE32(Header,20),Depth,Color);
    finally Pixels.Free; end;
  end else if Extension='.bmp' then begin
    var Header: array[0..53] of Byte; Stream.ReadBuffer(Header,SizeOf(Header));
    var HeaderSize := PCardinal(@Header[14])^;
    if (Header[0]<>66) or (Header[1]<>77) or not ((HeaderSize=40) or (HeaderSize=52) or (HeaderSize=56)) or
      (Int64(HeaderSize)+14>Stream.Size) or (PWord(@Header[26])^<>1) or not (PWord(@Header[28])^ in [1,4,8,16,24,32]) then raise ERigm.Create('Supported Windows BMP header required');
    Dimensions(PInteger(@Header[18])^,Abs(Int64(PInteger(@Header[22])^)));
    var Bits := PWord(@Header[28])^; var Compression := PCardinal(@Header[30])^; var Colors := PCardinal(@Header[46])^;
    if (Colors>256) or ((Bits<=8) and (Colors>Cardinal(1 shl Bits))) or
      not ((Compression=0) or ((Compression=3) and (Bits in [16,32]))) then raise ERigm.Create('Unsupported BMP compression or palette');
    var Palette := Int64(Colors); if (Bits<=8) and (Palette=0) then Palette := 1 shl Bits;
    var Masks := 0; if (Compression=3) and (HeaderSize=40) then Masks := 12;
    var Offset := Int64(PCardinal(@Header[10])^);
    var PixelBytes := ((Int64(PInteger(@Header[18])^)*Bits+31) div 32)*4*Abs(Int64(PInteger(@Header[22])^));
    if (Offset<14+Int64(HeaderSize)+Masks+Palette*4) or (Offset+PixelBytes>Stream.Size) or
      ((PCardinal(@Header[34])^<>0) and (PCardinal(@Header[34])^<>PixelBytes)) or
      ((PCardinal(@Header[2])^<>0) and (PCardinal(@Header[2])^<>Stream.Size)) then raise ERigm.Create('Invalid BMP pixel extent');
  end else if MatchStr(Extension,['.jpg','.jpeg']) then begin
    var B: Byte; Stream.ReadBuffer(B,1); if B<>$FF then raise ERigm.Create('Invalid JPEG'); Stream.ReadBuffer(B,1); if B<>$D8 then raise ERigm.Create('Invalid JPEG');
    var Found := False;
    while Stream.Position<Stream.Size do begin
      Stream.ReadBuffer(B,1); if B<>$FF then raise ERigm.Create('Invalid JPEG marker');
      repeat Stream.ReadBuffer(B,1); until B<>$FF;
      if (B=$D9) or (B=$DA) then Break;
      if (B=$01) or ((B>=$D0) and (B<=$D7)) then Continue;
      var Len: array[0..1] of Byte; Stream.ReadBuffer(Len,2); var Count := Integer(Len[0])*256+Len[1];
      if (Count<2) or (Count-2>Stream.Size-Stream.Position) then raise ERigm.Create('Truncated JPEG segment');
      if B in [$C0,$C1,$C2] then begin
        if Count<8 then raise ERigm.Create('Invalid JPEG dimensions');
        var Size: array[0..4] of Byte; Stream.ReadBuffer(Size,5);
        Dimensions(Integer(Size[3])*256+Size[4],Integer(Size[1])*256+Size[2]); Found := True; Break;
      end;
      Stream.Position := Stream.Position+Count-2;
    end;
    if not Found then raise ERigm.Create('Supported JPEG dimensions missing');
    Stream.Position := Stream.Size-2; var EndBytes: array[0..1] of Byte; Stream.ReadBuffer(EndBytes,2);
    if (EndBytes[0]<>$FF) or (EndBytes[1]<>$D9) then raise ERigm.Create('JPEG end marker is missing');
  end else raise ERigm.Create('PNG/JPEG/BMP required');
  Stream.Position := 0;
end;
function CheckedMovieImageHash(const Path: string; Force: Boolean): string;
begin
  var Full := LocalImagePath(Path); var Held := TList<THandle>.Create; var H := INVALID_HANDLE_VALUE;
  try
    HoldImageDirectories(ExtractFileDir(Full),Held,False);
    H := CreateFile(PChar(Full),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
    var Info: TByHandleFileInformation; if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
    if (Info.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY))<>0 then raise ERigm.Create('Regular image file required');
    var Stamp := Info.dwVolumeSerialNumber.ToString+'|'+Info.nFileIndexHigh.ToString+'|'+Info.nFileIndexLow.ToString+'|'+
      Info.nFileSizeHigh.ToString+'|'+Info.nFileSizeLow.ToString+'|'+Info.ftLastWriteTime.dwHighDateTime.ToString+'|'+Info.ftLastWriteTime.dwLowDateTime.ToString;
    var Check: TCheckedImage;
    TMonitor.Enter(ImageCheckLock);
    try if not Force and ImageChecks.TryGetValue(Full,Check) and (Check.Stamp=Stamp) then Exit(Check.Hash); finally TMonitor.Exit(ImageCheckLock); end;
    var Stream := TFileStream.Create(Full,fmOpenRead or fmShareDenyWrite);
    try
      var Ext := LowerCase(ExtractFileExt(Full)); ImageHeader(Stream,Ext);
      if Ext='.png' then begin
        var Png := TPngImage.Create; try Png.CheckCRC := True; Png.LoadFromStream(Stream); finally Png.Free; end;
      end else begin
        var Picture := TPicture.Create; var Bitmap := Vcl.Graphics.TBitmap.Create;
        try Picture.LoadFromFile(Full); if (Picture.Width<1) or (Picture.Height<1) then raise ERigm.Create('Image decode failed');
          Bitmap.Assign(Picture.Graphic); // Force JPEG entropy decoding, not only header parsing.
          if (Bitmap.Width<>Picture.Width) or (Bitmap.Height<>Picture.Height) then raise ERigm.Create('Decoded image dimensions differ');
        finally Bitmap.Free; Picture.Free; end;
      end;
      Result := THashSHA2.GetHashStringFromFile(Full);
    finally Stream.Free; end;
    Check.Stamp := Stamp; Check.Hash := Result;
    TMonitor.Enter(ImageCheckLock);
    try if ImageChecks.Count>=512 then ImageChecks.Clear; ImageChecks.AddOrSetValue(Full,Check); finally TMonitor.Exit(ImageCheckLock); end;
  finally if H<>INVALID_HANDLE_VALUE then CloseHandle(H); for var Dir in Held do CloseHandle(Dir); Held.Free; end;
end;
function CopyCheckedMovieImage(const Source,Directory,ExpectedHash: string): string;
begin
  var Full := LocalImagePath(Source); var TargetDirectory := LocalImagePath(Directory);
  var Held := TList<THandle>.Create; var H := INVALID_HANDLE_VALUE; var Pending := '';
  try
    HoldImageDirectories(ExtractFileDir(Full),Held,False);
    H := CreateFile(PChar(Full),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
    var Hash := CheckedMovieImageHash(Full,True);
    if (ExpectedHash<>'') and not SameText(Hash,ExpectedHash) then raise ERigm.Create('Image SHA-256 differs from delivery metadata');
    HoldImageDirectories(TargetDirectory,Held,True);
    Result := TPath.Combine(TargetDirectory,Hash+LowerCase(ExtractFileExt(Full)));
    if not FileExists(Result) then begin
      Pending := TPath.Combine(TargetDirectory,TGUID.NewGuid.ToString.Trim(['{','}'])+'.pending');
      var OutHandle := CreateFile(PChar(Pending),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
      if OutHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
      try
        var Input := TFileStream.Create(Full,fmOpenRead or fmShareDenyWrite); var Output := THandleStream.Create(OutHandle);
        try Output.CopyFrom(Input,0); if not FlushFileBuffers(OutHandle) then RaiseLastOSError; finally Output.Free; Input.Free; end;
      finally CloseHandle(OutHandle); end;
      if not MoveFileEx(PChar(Pending),PChar(Result),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      Pending := '';
    end;
    if CheckedMovieImageHash(Result,True)<>Hash then raise ERigm.Create('Existing image asset differs; it will not be overwritten');
  finally
    try if (Pending<>'') and FileExists(Pending) then TFile.Delete(Pending);
    finally if H<>INVALID_HANDLE_VALUE then CloseHandle(H); for var Dir in Held do CloseHandle(Dir); Held.Free; end;
  end;
end;

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

function TransferSceneKey(Project: TRigmMovieProject; const Id: string): string;
begin
  var S := Project.Scene(Id); if S=nil then raise ERigm.Create('Scene is missing'); var O := S.Json;
  try
    if S.Image<>'' then begin var Path := ResolveMoviePath(Project.FileName,S.Image); if FileExists(Path) then PsdJson.Put(O,'image','sha256:'+CheckedMovieImageHash(Path)); end;
    var A := TJSONArray.Create; O.AddPair('cues',A); for var C in Project.Cues do if C.Scene=Id then begin var V := TJSONObject.Create; V.AddPair('id',C.Id); V.AddPair('text',C.Text); A.AddElement(V); end;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
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
  if Project.Scene(FScene).ImageApproved then raise ERigm.Create('Approved scene image is locked');
  FSceneKey := TransferSceneKey(Project,FScene);
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
    try if (Pending<>'') and FileExists(Pending) then TFile.Delete(Pending);
    finally if Pinned<>INVALID_HANDLE_VALUE then CloseHandle(Pinned); for var H in Held do CloseHandle(H); Held.Free; end;
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
      ImageHeader(Stream,'.png'); CheckCancel; var Image := TPngImage.Create; Image.CheckCRC := True;
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
    if (Project.Scene(FScene)=nil) or Project.Scene(FScene).ImageApproved then raise ERigm.Create('Scene was removed or approved before adoption');
    if FSceneKey<>TransferSceneKey(Project,FScene) then raise ERigm.Create('Scene context changed before image adoption');
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
initialization
  ImageCheckLock := TObject.Create; ImageChecks := TDictionary<string,TCheckedImage>.Create;
finalization
  ImageChecks.Free; ImageCheckLock.Free;
end.
