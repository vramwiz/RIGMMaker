unit RigmDotsImages;

// Dotsから受け取った画像の一時配置。作品への採用は既存の要求ID・版照合を通す。
interface
uses System.SysUtils, System.JSON, System.Generics.Collections;
type
  TRigmDotsImages = class
  private
    FDirectory: string;
    FPaths: TDictionary<string,string>;
  public
    constructor Create(const Directory: string);
    destructor Destroy; override;
    function PutImage(Args: TJSONObject): TJSONObject;
    function GetImage(Args: TJSONObject): TJSONObject;
  end;
implementation
uses System.IOUtils, System.NetEncoding, RigmMovieImageTransfer, Vcl.Graphics,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;
const ImageLimit = 4*1024*1024;
function TextOf(O: TJSONObject; const Key: string): string;
begin Result := ''; if O.GetValue(Key) is TJSONString then Result := O.GetValue(Key).Value; end;
constructor TRigmDotsImages.Create(const Directory: string);
begin inherited Create; FDirectory := Directory; FPaths := TDictionary<string,string>.Create; end;
destructor TRigmDotsImages.Destroy;
begin FPaths.Free; inherited; end;
function TRigmDotsImages.PutImage(Args: TJSONObject): TJSONObject;
var Data,Ext,Id,Path: string; Bytes: TBytes; Info: TJSONObject;
begin
  Data := TextOf(Args,'base64');
  if (Data='') or (Length(Data)>((ImageLimit+2) div 3)*4) then raise Exception.Create('invalid_image_data');
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(Data);
  if (Length(Bytes)<4) or (Length(Bytes)>ImageLimit) then raise Exception.Create('image_size_limit');
  Ext := '';
  if (Bytes[0]=$89) and (Bytes[1]=$50) and (Bytes[2]=$4e) and (Bytes[3]=$47) then Ext := '.png'
  else if (Bytes[0]=$ff) and (Bytes[1]=$d8) and (Bytes[2]=$ff) then Ext := '.jpg'
  else if (Bytes[0]=$42) and (Bytes[1]=$4d) then Ext := '.bmp';
  if Ext='' then raise Exception.Create('unsupported_image');
  ForceDirectories(FDirectory);
  Id := TGUID.NewGuid.ToString.Replace('{','').Replace('}','');
  Path := TPath.Combine(FDirectory,Id+Ext);
  TFile.WriteAllBytes(Path,Bytes);
  try
    CheckedMovieImageHash(Path,True);
    FPaths.Add(Id,Path);
    Info := TJSONObject.Create.AddPair('imageId',Id);
    try Result := GetImage(Info); finally Info.Free; end;
    Result.RemovePair('base64').Free;
  except
    FPaths.Remove(Id);
    TFile.Delete(Path);
    raise;
  end;
end;
function TRigmDotsImages.GetImage(Args: TJSONObject): TJSONObject;
var Id,Path,Hash: string; Bytes: TBytes; Picture: TPicture;
begin
  Id := TextOf(Args,'imageId');
  if not FPaths.TryGetValue(Id,Path) then raise Exception.Create('unknown_image');
  if TFile.GetSize(Path)>ImageLimit then raise Exception.Create('image_size_limit');
  // The content validator and renderer are shared with existing production transfers.
  Hash := CheckedMovieImageHash(Path,True);
  Bytes := TFile.ReadAllBytes(Path); Picture := TPicture.Create;
  try
    Picture.LoadFromFile(Path);
    Result := TJSONObject.Create.AddPair('imageId',Id).AddPair('path',Path)
      .AddPair('width',TJSONNumber.Create(Picture.Width)).AddPair('height',TJSONNumber.Create(Picture.Height))
      .AddPair('bytes',TJSONNumber.Create(Length(Bytes))).AddPair('sha256',LowerCase(Hash))
      .AddPair('base64',TNetEncoding.Base64.EncodeBytesToString(Bytes).Replace(#13,'').Replace(#10,''));
  finally Picture.Free; end;
end;
end.
