unit RigmMovieAvi;

interface
uses System.SysUtils, System.Classes, System.Generics.Collections, Vcl.Graphics, RigmMovieAudio;

type
  TRigmAviIndex = packed record Code,Flags,Offset,Size: Cardinal; end;
  TRigmMovieAvi = class
  private
    FStream: TFileStream;
    FIndex: TList<TRigmAviIndex>;
    FMotionStart, FMotionSize: Int64;
    FWidth,FHeight,FFps,FFrames,FExpected,FQuality: Integer;
    procedure U32(Value: Cardinal);
    procedure Four(const Value: AnsiString);
    procedure Patch(Position: Int64; Value: Cardinal);
    function BeginList(const Kind: AnsiString): Int64;
    procedure EndList(Position: Int64);
    procedure DataChunk(const Code: AnsiString; Data: Pointer; Size: Cardinal; Flags: Cardinal);
  public
    constructor Create(const FileName: string; Width,Height,Fps,Frames: Integer; Quality: Integer=90);
    destructor Destroy; override;
    procedure AddFrame(Bitmap: Vcl.Graphics.TBitmap; Audio: TRigmPcm);
    procedure Finish;
  end;

implementation
uses System.Math, Winapi.Windows, Winapi.MMSystem, Vcl.Imaging.jpeg, RigmModel;

type TMovieBitmapHeader = packed record
  biSize: Cardinal; biWidth,biHeight: Integer; biPlanes,biBitCount: Word;
  biCompression,biSizeImage: Cardinal; biXPelsPerMeter,biYPelsPerMeter: Integer;
  biClrUsed,biClrImportant: Cardinal;
end;

function Code32(const Text: AnsiString): Cardinal;
begin Move(Text[1],Result,4); end;
procedure TRigmMovieAvi.U32(Value: Cardinal);
begin FStream.WriteBuffer(Value,4); end;
procedure TRigmMovieAvi.Four(const Value: AnsiString);
begin FStream.WriteBuffer(Value[1],4); end;
procedure TRigmMovieAvi.Patch(Position: Int64; Value: Cardinal);
var Saved: Int64;
begin Saved := FStream.Position; FStream.Position := Position; U32(Value); FStream.Position := Saved; end;
function TRigmMovieAvi.BeginList(const Kind: AnsiString): Int64;
begin Four('LIST'); Result := FStream.Position; U32(0); Four(Kind); end;
procedure TRigmMovieAvi.EndList(Position: Int64);
begin Patch(Position,FStream.Position-Position-4); end;
constructor TRigmMovieAvi.Create(const FileName: string; Width,Height,Fps,Frames: Integer; Quality: Integer);
var Header,StreamList: Int64; Video: TMovieBitmapHeader; Wave: TWaveFormatEx;
  procedure StreamHeader(const Kind,Handler: AnsiString; Scale,Rate,LengthValue,SampleSize: Cardinal; VideoStream: Boolean);
  var R: array[0..3] of SmallInt; Z: Word;
  begin
    Four('strh'); U32(56); Four(Kind); Four(Handler); U32(0); Z := 0; FStream.WriteBuffer(Z,2); FStream.WriteBuffer(Z,2);
    U32(0); U32(Scale); U32(Rate); U32(0); U32(LengthValue); U32(Width*Height*4); U32($FFFFFFFF); U32(SampleSize);
    R[0] := 0; R[1] := 0; R[2] := 0; R[3] := 0;
    if VideoStream then begin R[2] := Width; R[3] := Height; end; FStream.WriteBuffer(R,8);
  end;
begin
  inherited Create; FWidth := Width; FHeight := Height; FFps := Fps; FExpected := Frames;
  FQuality := EnsureRange(Quality,50,100);
  FIndex := TList<TRigmAviIndex>.Create; FStream := TFileStream.Create(FileName,fmCreate);
  Four('RIFF'); U32(0); Four('AVI '); Header := BeginList('hdrl');
  Four('avih'); U32(56); U32(Round(1000000/Fps)); U32(0); U32(0); U32($110);
  U32(Frames); U32(0); U32(2); U32(Width*Height*4); U32(Width); U32(Height);
  for var I := 1 to 4 do U32(0);
  StreamList := BeginList('strl'); StreamHeader('vids','MJPG',1,Fps,Frames,0,True);
  Video := Default(TMovieBitmapHeader); Video.biSize := SizeOf(Video); Video.biWidth := Width; Video.biHeight := Height;
  Video.biPlanes := 1; Video.biBitCount := 24; Video.biCompression := Code32('MJPG'); Video.biSizeImage := Width*Height*3;
  Four('strf'); U32(SizeOf(Video)); FStream.WriteBuffer(Video,SizeOf(Video)); EndList(StreamList);
  StreamList := BeginList('strl'); StreamHeader('auds',#0#0#0#0,1,48000,Round(Frames*48000.0/Fps),2,False);
  Wave := Default(TWaveFormatEx); Wave.wFormatTag := 1; Wave.nChannels := 1; Wave.nSamplesPerSec := 48000;
  Wave.nAvgBytesPerSec := 96000; Wave.nBlockAlign := 2; Wave.wBitsPerSample := 16;
  Four('strf'); U32(16); FStream.WriteBuffer(Wave,16); EndList(StreamList); EndList(Header);
  FMotionSize := BeginList('movi'); FMotionStart := FMotionSize+4;
end;
destructor TRigmMovieAvi.Destroy;
begin FStream.Free; FIndex.Free; inherited; end;
procedure TRigmMovieAvi.DataChunk(const Code: AnsiString; Data: Pointer; Size: Cardinal; Flags: Cardinal);
var Entry: TRigmAviIndex; Pad: Byte;
begin
  if FStream.Position+Size+8+FIndex.Count*16>2000000000 then raise ERigm.Create('AVIの2GB安全上限です。解像度かfpsを下げるか台本を分割してください。');
  Entry.Code := Code32(Code); Entry.Flags := Flags; Entry.Offset := FStream.Position-FMotionStart; Entry.Size := Size;
  FIndex.Add(Entry); Four(Code); U32(Size); if Size>0 then FStream.WriteBuffer(Data^,Size);
  if Odd(Size) then begin Pad := 0; FStream.WriteBuffer(Pad,1); end;
end;
procedure TRigmMovieAvi.AddFrame(Bitmap: Vcl.Graphics.TBitmap; Audio: TRigmPcm);
var Jpeg: TJpegImage; Stream: TMemoryStream; Buffer: TArray<SmallInt>; First, Last: Integer;
begin
  if (FFrames>=FExpected) or (Bitmap.Width<>FWidth) or (Bitmap.Height<>FHeight) or (Audio.Rate<>48000) then raise ERigm.Create('AVIフレーム寸法・件数・音声レートが不正です。');
  Jpeg := TJpegImage.Create; Stream := TMemoryStream.Create;
  try
    Jpeg.Assign(Bitmap); Jpeg.CompressionQuality := FQuality; Jpeg.SaveToStream(Stream);
    DataChunk('00dc',Stream.Memory,Stream.Size,$10);
  finally Stream.Free; Jpeg.Free; end;
  First := Round(FFrames*48000.0/FFps); Last := Round((FFrames+1)*48000.0/FFps);
  SetLength(Buffer,Last-First);
  for var I := First to Last-1 do if I<Length(Audio.Samples) then Buffer[I-First] := Audio.Samples[I];
  DataChunk('01wb',@Buffer[0],Length(Buffer)*2,$10); Inc(FFrames);
end;
procedure TRigmMovieAvi.Finish;
begin
  if FFrames<>FExpected then raise ERigm.Create('AVIフレーム数が不足しています。');
  EndList(FMotionSize); Four('idx1'); U32(FIndex.Count*SizeOf(TRigmAviIndex));
  for var Entry in FIndex do FStream.WriteBuffer(Entry,SizeOf(Entry)); Patch(4,FStream.Size-8);
end;
end.
