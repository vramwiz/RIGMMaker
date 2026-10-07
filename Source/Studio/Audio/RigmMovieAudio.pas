// VOICEVOX音声の生成・PCM読込・混合・波形抽出を担当する。画面や編集リースを参照しない。
unit RigmMovieAudio;

interface
uses System.SysUtils, System.Classes, System.JSON, RigmMovieModel;

type
  TRigmPcm = class
  public
    Rate: Integer;
    Samples: TArray<SmallInt>;
    SpeechSamples: TArray<SmallInt>; // Separate lip-sync envelope; BGM never drives mouth movement.
    function Duration: Double;
    function Envelope(Seconds: Double): Double;
    class function Load(const FileName: string): TRigmPcm; static;
    procedure Save(const FileName: string);
  end;

function CopyCheckedMovieBgm(const Source,Directory: string): string;
function MixMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean=False): TRigmPcm;
function MovieAudioStamp(Project: TRigmMovieProject): string;
function CachedMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean=False): TRigmPcm;
function MovieWaveform(Project: TRigmMovieProject; Bins: Integer = 2048): TJSONObject;

implementation
uses System.Math, System.IOUtils, System.Hash, System.StrUtils, System.Generics.Collections, Winapi.Windows, RigmModel, RigmJson, RigmVoiceEffects, RigmVoiceEffectsDsp, RigmAudioFilePaths;

var CacheLock: TObject; CacheKey: string; CacheSamples,CacheSpeechSamples: TArray<SmallInt>;

function MovieAudioStamp(Project: TRigmMovieProject): string;
var Key: string;
begin
  Key := Project.Id+'|'+FloatToStr(Project.Duration,TFormatSettings.Invariant);
  for var S in Project.Scenes do Key := Key+'|'+S.Id+'|'+FloatToStr(S.Padding,TFormatSettings.Invariant);
  for var C in Project.Cues do begin
    var FileName := ResolveMoviePath(Project.FileName,C.WaveFile);
    Key := Key+'|'+C.Id+'|'+C.Scene+'|'+FloatToStr(Project.CueStart(C),TFormatSettings.Invariant)+'|'+C.AudioKey+'|'+Project.AudioFingerprint(C)+'|'+CueVoiceEffectsStamp(C)+'|'+
      FloatToStr(C.AudioSeconds,TFormatSettings.Invariant)+'|'+FloatToStr(C.Pause,TFormatSettings.Invariant)+'|'+FileName;
    if AudioFileExists(FileName) then Key := Key+'|'+TFile.GetSize(AudioFilePath(FileName)).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(AudioFilePath(FileName)),TFormatSettings.Invariant);
  end;
  var BgmPath := ResolveMoviePath(Project.FileName,Project.BgmFile);
  Key := Key+'|bgm|'+BgmPath+'|'+FloatToStr(Project.BgmVolume,TFormatSettings.Invariant)+'|'+FloatToStr(Project.BgmFadeOut,TFormatSettings.Invariant);
  if AudioFileExists(BgmPath) then Key := Key+'|'+TFile.GetSize(AudioFilePath(BgmPath)).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(AudioFilePath(BgmPath)),TFormatSettings.Invariant);
  Result := THashSHA2.GetHashString(Key);
end;

function CachedMovieAudio(Project: TRigmMovieProject; AllowStale: Boolean): TRigmPcm;
var Key: string;
begin
  Key := MovieAudioStamp(Project)+'|'+BoolToStr(AllowStale,True);
  TMonitor.Enter(CacheLock);
  try
    if Key=CacheKey then begin Result := TRigmPcm.Create; Result.Rate := 48000; Result.Samples := CacheSamples; Result.SpeechSamples := CacheSpeechSamples; Exit; end;
  finally TMonitor.Exit(CacheLock); end;
  Result := MixMovieAudio(Project,AllowStale);
  // Keep one immutable mix, bounded at 64 MiB including the separate speech envelope. Workers retain their own array reference.
  if Length(Result.Samples)+Length(Result.SpeechSamples)<=32*1024*1024 then begin
    TMonitor.Enter(CacheLock);
    try CacheKey := Key; CacheSamples := Result.Samples; CacheSpeechSamples := Result.SpeechSamples; finally TMonitor.Exit(CacheLock); end;
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
  var EnvelopeSamples := Samples; if Length(SpeechSamples)>0 then EnvelopeSamples := SpeechSamples;
  First := Round(Seconds*Rate); Last := Min(High(EnvelopeSamples),First+Rate div 40); Sum := 0;
  if (First<0) or (First>Last) then Exit(0);
  for var I := First to Last do Sum := Sum+Sqr(EnvelopeSamples[I]/32768.0);
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
    Stream := TFileStream.Create(AudioFilePath(FileName),fmOpenRead or fmShareDenyWrite);
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
  S := TFileStream.Create(AudioFilePath(FileName),fmCreate);
  try
    Four('RIFF'); U32(36+Length(Samples)*2); Four('WAVE'); Four('fmt '); U32(16);
    U16(1); U16(1); U32(Rate); U32(Rate*2); U16(2); U16(16); Four('data'); U32(Length(Samples)*2);
    if Length(Samples)>0 then S.WriteBuffer(Samples[0],Length(Samples)*2);
  finally S.Free; end;
end;
function CopyCheckedMovieBgm(const Source,Directory: string): string;
  function LocalPath(const Value: string): string;
  begin
    var P := Value.Replace('/','\');
    if (Length(P)<4) or (P[2]<>':') or (P[3]<>'\') or P.StartsWith('\\') or
      (Pos(#0,P)>0) or (Pos('*',P)>0) or (Pos('?',P)>0) or (Pos(':',P.Substring(2))>0) then raise ERigm.Create('BGM requires an unambiguous local absolute path');
    for var Part in P.Substring(3).Split(['\']) do begin
      if (Part='') or (Part='.') or (Part='..') or Part.EndsWith('.') or Part.EndsWith(' ') then raise ERigm.Create('Ambiguous BGM path');
      var Device := UpperCase(Part.Split(['.'])[0]);
      if MatchStr(Device,['CON','PRN','AUX','NUL']) or ((Length(Device)=4) and
        (Device.StartsWith('COM') or Device.StartsWith('LPT')) and CharInSet(Device[4],['0'..'9'])) then raise ERigm.Create('Reserved BGM path');
    end;
    Result := TPath.GetFullPath(P);
  end;
  procedure HoldDirectories(const Path: string; Held: TList<THandle>; CreateMissing: Boolean);
  begin
    var Root := TPath.GetPathRoot(Path); var Current := ExcludeTrailingPathDelimiter(Root);
    for var Part in Path.Substring(Length(Root)).Split(['\']) do begin
      if Part='' then Continue; Current := TPath.Combine(Current,Part);
      if CreateMissing and not DirectoryExists(Current) and not CreateDir(Current) then RaiseLastOSError;
      var H := CreateFile(PChar(Current),FILE_READ_ATTRIBUTES,FILE_SHARE_READ or FILE_SHARE_WRITE,nil,OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT,0);
      if H=INVALID_HANDLE_VALUE then RaiseLastOSError; Held.Add(H);
      var Info: TByHandleFileInformation; if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
      if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT)<>0 then raise ERigm.Create('BGM directory contains a reparse point');
    end;
  end;
begin
  var Full := LocalPath(Source); var TargetDirectory := LocalPath(Directory);
  if not SameText(ExtractFileExt(Full),'.wav') then raise ERigm.Create('BGM supports PCM16 mono/stereo WAV');
  var Held := TList<THandle>.Create; var H := INVALID_HANDLE_VALUE; var Pending := '';
  try
    HoldDirectories(ExtractFileDir(Full),Held,False);
    H := CreateFile(PChar(Full),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
    var Info: TByHandleFileInformation; if not GetFileInformationByHandle(H,Info) then RaiseLastOSError;
    if (Info.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY))<>0 then raise ERigm.Create('BGM requires a regular WAV file');
    if (TFile.GetSize(Full)<44) or (TFile.GetSize(Full)>128*1024*1024) then raise ERigm.Create('BGM WAV must be 44 bytes..128 MiB');
    var Audio := TRigmPcm.Load(Full); try if Audio.Duration>3600 then raise ERigm.Create('BGM must be at most one hour'); finally Audio.Free; end;
    var Hash := THashSHA2.GetHashStringFromFile(Full); HoldDirectories(TargetDirectory,Held,True);
    Result := TPath.Combine(TargetDirectory,Hash+'.wav');
    if not FileExists(Result) then begin
      Pending := TPath.Combine(TargetDirectory,TGUID.NewGuid.ToString.Trim(['{','}'])+'.pending');
      var OutHandle := CreateFile(PChar(Pending),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
      if OutHandle=INVALID_HANDLE_VALUE then RaiseLastOSError;
      try
        var Input := TFileStream.Create(Full,fmOpenRead or fmShareDenyWrite); var Output := THandleStream.Create(OutHandle);
        try Output.CopyFrom(Input,0); if not FlushFileBuffers(OutHandle) then RaiseLastOSError; finally Output.Free; Input.Free; end;
      finally CloseHandle(OutHandle); end;
      if THashSHA2.GetHashStringFromFile(Pending)<>Hash then raise ERigm.Create('BGM copy verification failed');
      if not MoveFileEx(PChar(Pending),PChar(Result),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError; Pending := '';
    end;
    var Target := CreateFile(PChar(Result),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,0);
    if Target=INVALID_HANDLE_VALUE then RaiseLastOSError;
    try
      if not GetFileInformationByHandle(Target,Info) then RaiseLastOSError;
      if (Info.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY))<>0 then raise ERigm.Create('BGM asset was replaced');
      if THashSHA2.GetHashStringFromFile(Result)<>Hash then raise ERigm.Create('Existing BGM asset differs; it will not be overwritten');
    finally CloseHandle(Target); end;
  finally
    try if (Pending<>'') and FileExists(Pending) then TFile.Delete(Pending);
    finally if H<>INVALID_HANDLE_VALUE then CloseHandle(H); for var Dir in Held do CloseHandle(Dir); Held.Free; end;
  end;
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
          ApplyCueVoiceEffects(C,Source.Rate,Source.Samples);
          var Offset := Round(Position*Result.Rate);
          for var I := 0 to Ceil(Source.Duration*Result.Rate)-1 do begin
            var Q := Double(I)*Source.Rate/Result.Rate; var A := Min(High(Source.Samples),Floor(Q)); var B := Min(High(Source.Samples),A+1);
            if Offset+I<Length(Result.Samples) then Result.Samples[Offset+I] := Round(Source.Samples[A]+(Source.Samples[B]-Source.Samples[A])*Frac(Q));
          end;
        finally Source.Free; end;
      end;
    end;
    if Project.BgmFile<>'' then begin
      Result.SpeechSamples := Copy(Result.Samples);
      Source := TRigmPcm.Load(ResolveMoviePath(Project.FileName,Project.BgmFile));
      try
        var Fade := Min(Project.BgmFadeOut,Project.Duration);
        for var I := 0 to High(Result.Samples) do begin
          var Q := Double(I)*Source.Rate/Result.Rate; var A := Int64(Floor(Q)) mod Length(Source.Samples);
          var B := (A+1) mod Length(Source.Samples);
          var Gain := Project.BgmVolume;
          if (Fade>0) and (I/Result.Rate>Project.Duration-Fade) then
            Gain := Gain*EnsureRange((Project.Duration-I/Result.Rate)/Fade,0.0,1.0);
          var Value := Source.Samples[A]+(Source.Samples[B]-Source.Samples[A])*Frac(Q);
          Result.Samples[I] := EnsureRange(Round(Result.Samples[I]+Value*Gain),-32768,32767);
        end;
      finally Source.Free; end;
    end;
  except Result.Free; raise; end;
end;
initialization
  CacheLock := TObject.Create;
finalization
  CacheLock.Free;
end.
