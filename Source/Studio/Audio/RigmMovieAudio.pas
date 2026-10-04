// VOICEVOX音声の生成・PCM読込・混合・波形抽出を担当する。画面や編集リースを参照しない。
unit RigmMovieAudio;

interface
uses System.SysUtils, System.Classes, System.JSON, RigmMovieModel;

type
  TRigmPcm = class
  public
    Rate: Integer;
    Samples: TArray<SmallInt>;
    function Duration: Double;
    function Envelope(Seconds: Double): Double;
    class function Load(const FileName: string): TRigmPcm; static;
    procedure Save(const FileName: string);
  end;

function MixMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean=False): TRigmPcm;
function MovieAudioStamp(Project: TRigmMovieProject): string;
function CachedMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean=False): TRigmPcm;
function MovieWaveform(Project: TRigmMovieProject; Bins: Integer = 2048): TJSONObject;

implementation
uses System.Math, System.IOUtils, System.Hash, RigmModel, RigmJson;

var CacheLock: TObject; CacheKey: string; CacheSamples: TArray<SmallInt>;

function MovieAudioStamp(Project: TRigmMovieProject): string;
var Key: string;
begin
  Key := Project.Id+'|'+FloatToStr(Project.Duration,TFormatSettings.Invariant);
  for var S in Project.Scenes do Key := Key+'|'+S.Id+'|'+FloatToStr(S.Padding,TFormatSettings.Invariant);
  for var C in Project.Cues do begin
    var FileName := ResolveMoviePath(Project.FileName,C.WaveFile);
    Key := Key+'|'+C.Id+'|'+C.AudioKey+'|'+Project.AudioFingerprint(C)+'|'+
      FloatToStr(C.AudioSeconds,TFormatSettings.Invariant)+'|'+FloatToStr(C.Pause,TFormatSettings.Invariant)+'|'+FileName;
    if FileExists(FileName) then Key := Key+'|'+TFile.GetSize(FileName).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(FileName),TFormatSettings.Invariant);
  end;
  Result := THashSHA2.GetHashString(Key);
end;

function CachedMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean): TRigmPcm;
var Key: string;
begin
  Key := MovieAudioStamp(Project)+'|'+BoolToStr(AllowStale,True);
  TMonitor.Enter(CacheLock);
  try
    if Key=CacheKey then begin Result := TRigmPcm.Create; Result.Rate := 48000; Result.Samples := CacheSamples; Exit; end;
  finally TMonitor.Exit(CacheLock); end;
  Result := MixMovieAudio(Project,AllowStale);
  // Keep one immutable mix, bounded at 32 MiB. Workers retain their own array reference.
  if Length(Result.Samples)<=16*1024*1024 then begin
    TMonitor.Enter(CacheLock);
    try CacheKey := Key; CacheSamples := Result.Samples; finally TMonitor.Exit(CacheLock); end;
  end;
end;

function MovieWaveform(Project: TRigmMovieProject; Bins: Integer): TJSONObject;
var Audio: TRigmPcm;
begin
  Bins := EnsureRange(Bins,64,4096); Audio := CachedMovieAudio(Project);
  try
    Result := TJSONObject.Create; Result.AddPair('audioStamp',MovieAudioStamp(Project)); AddN(Result,'duration',Audio.Duration); AddN(Result,'sampleRate',Audio.Rate); AddN(Result,'sampleCount',Length(Audio.Samples)); AddN(Result,'amplitudeScale',32768);
    var Peaks := TJSONArray.Create; Result.AddPair('peaks',Peaks);
    for var I := 0 to Bins-1 do begin
      var First := Int64(I)*Length(Audio.Samples) div Bins; var Last := Int64(I+1)*Length(Audio.Samples) div Bins-1;
      var Minimum := 0; var Maximum := 0;
      for var J := First to Last do begin Minimum := Min(Minimum,Audio.Samples[J]); Maximum := Max(Maximum,Audio.Samples[J]); end;
      var Pair := TJSONArray.Create; Pair.Add(Minimum); Pair.Add(Maximum); Peaks.AddElement(Pair);
    end;
  finally Audio.Free; end;
end;

function TRigmPcm.Duration: Double;
begin Result := Length(Samples)/Rate; end;
function TRigmPcm.Envelope(Seconds: Double): Double;
var First, Last: Integer; Sum: Double;
begin
  First := Round(Seconds*Rate); Last := Min(High(Samples),First+Rate div 40); Sum := 0;
  if (First<0) or (First>Last) then Exit(0);
  for var I := First to Last do Sum := Sum+Sqr(Samples[I]/32768.0);
  Result := EnsureRange(Sqrt(Sum/(Last-First+1))*7,0.0,1.0);
end;
class function TRigmPcm.Load(const FileName: string): TRigmPcm;
var Stream: TFileStream; Code: array[0..3] of AnsiChar; Size, RiffSize: Cardinal;
  Format, Channels, Bits, Align: Word; Rate, ByteRate: Cardinal;
  Data: TBytes; FoundFmt, FoundData: Boolean; Limit, Next: Int64;
begin
  Result := TRigmPcm.Create; Stream := nil;
  try
   try
    Stream := TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
    Stream.ReadBuffer(Code,4); if Code<>'RIFF' then raise ERigm.Create('PCM WAVのRIFFヘッダがありません。');
    Stream.ReadBuffer(RiffSize,4); Stream.ReadBuffer(Code,4); if Code<>'WAVE' then raise ERigm.Create('WAVE形式ではありません。');
    Limit := Int64(RiffSize)+8; if (Limit>Stream.Size) or (Limit<12) or (Limit>512*1024*1024) then raise ERigm.Create('WAV長が不正です。');
    FoundFmt := False; FoundData := False; Format := 0; Channels := 0; Bits := 0; Rate := 0; Align := 0; ByteRate := 0;
    while Stream.Position+8<=Limit do begin
      Stream.ReadBuffer(Code,4); Stream.ReadBuffer(Size,4); Next := Stream.Position+Size+(Size and 1);
      if Next>Limit then raise ERigm.Create('WAVチャンクが破損しています。');
      if Code='fmt ' then begin
        if (Size<16) or FoundFmt then raise ERigm.Create('WAV fmtが不正です。');
        Stream.ReadBuffer(Format,2); Stream.ReadBuffer(Channels,2); Stream.ReadBuffer(Rate,4);
        Stream.ReadBuffer(ByteRate,4); Stream.ReadBuffer(Align,2); Stream.ReadBuffer(Bits,2); FoundFmt := True;
      end else if Code='data' then begin
        if FoundData then raise ERigm.Create('WAV dataが重複しています。');
        SetLength(Data,Size); if Size>0 then Stream.ReadBuffer(Data[0],Size); FoundData := True;
      end;
      Stream.Position := Next;
    end;
    if not FoundFmt or not FoundData or (Format<>1) or (Bits<>16) or not (Channels in [1,2]) or
      (Rate<8000) or (Rate>192000) or (Align<>Channels*2) or (ByteRate<>Rate*Align) or
      (Length(Data)=0) or (Length(Data) mod Align<>0) then raise ERigm.Create('PCM16 mono/stereo WAVだけを扱います。');
    Result.Rate := Rate; SetLength(Result.Samples,Length(Data) div Align);
    for var I := 0 to High(Result.Samples) do begin
      var A: SmallInt; Move(Data[I*Align],A,2);
      if Channels=2 then begin var B: SmallInt; Move(Data[I*Align+2],B,2); A := (Integer(A)+B) div 2; end;
      Result.Samples[I] := A;
    end;
   except Result.Free; raise; end;
  finally Stream.Free; end;
end;
procedure TRigmPcm.Save(const FileName: string);
var S: TFileStream; N: Cardinal; W: Word; Code: AnsiString;
  procedure Four(const Value: AnsiString); begin Code := Value; S.WriteBuffer(Code[1],4); end;
  procedure U32(Value: Cardinal); begin N := Value; S.WriteBuffer(N,4); end;
  procedure U16(Value: Word); begin W := Value; S.WriteBuffer(W,2); end;
begin
  S := TFileStream.Create(FileName,fmCreate);
  try
    Four('RIFF'); U32(36+Length(Samples)*2); Four('WAVE'); Four('fmt '); U32(16);
    U16(1); U16(1); U32(Rate); U32(Rate*2); U16(2); U16(16); Four('data'); U32(Length(Samples)*2);
    if Length(Samples)>0 then S.WriteBuffer(Samples[0],Length(Samples)*2);
  finally S.Free; end;
end;
function MixMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean): TRigmPcm;
var Position: Double; Source: TRigmPcm;
begin
  Result := TRigmPcm.Create; Result.Rate := 48000;
  try
    SetLength(Result.Samples,Ceil(Project.Duration*Result.Rate));
    for var C in Project.Cues do begin
      Position := Project.CueStart(C);
      if not Project.AudioReady(C) and not (AllowStale and Project.HasStoredAudio(C)) then raise ERigm.Create('音声が未生成か変更されています: '+C.Id);
      if (C.Text<>'') or (AllowStale and (C.AudioSeconds>0) and (C.WaveFile<>'')) then begin
        Source := TRigmPcm.Load(ResolveMoviePath(Project.FileName,C.WaveFile));
        try
          if Abs(Source.Duration-C.AudioSeconds)>0.002 then raise ERigm.Create('音声ファイルと台本の時間が一致しません: '+C.Id);
          var Offset := Round(Position*Result.Rate);
          for var I := 0 to Ceil(Source.Duration*Result.Rate)-1 do begin
            var Q := Double(I)*Source.Rate/Result.Rate; var A := Min(High(Source.Samples),Floor(Q)); var B := Min(High(Source.Samples),A+1);
            if Offset+I<Length(Result.Samples) then Result.Samples[Offset+I] := Round(Source.Samples[A]+(Source.Samples[B]-Source.Samples[A])*Frac(Q));
          end;
        finally Source.Free; end;
      end;
    end;
  except Result.Free; raise; end;
end;
initialization
  CacheLock := TObject.Create;
finalization
  CacheLock.Free;
end.
