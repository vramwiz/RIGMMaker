unit RigmMoviePsdRendering;

// 共通作品の時刻・話者・音素をPSD状態に変換する。プレビュー/出力は同じ描画器へ委譲。
interface
uses System.SysUtils, System.JSON, RigmMovieModel, RigmMovieComposition, RigmMovieAudio;
function RenderPsdMovieCharacter(Project: TRigmMovieProject; Character: TRigmMovieCharacter;
  Seconds: Double; Audio: TRigmPcm; Width,Height: Integer): TBytes;
function PsdMovieExpressions(const Path: string): TJSONObject;
procedure ValidatePsdMovieCharacter(Project: TRigmMovieProject; Character: TRigmMovieCharacter);
implementation
uses System.IOUtils, System.Generics.Collections, RigmCharacterCatalog, PsdAnimation, PsdJson,
  RigmJson, RigmMoviePhonemes;
type TSourceEntry = class
  Stamp: string; Asset: TPsdCharacterAsset;
  destructor Destroy; override;
end;
var Sources: TObjectDictionary<string,TSourceEntry>; SourceLock: TObject;
destructor TSourceEntry.Destroy;
begin Asset.Free; inherited; end;
function Source(Project: TRigmMovieProject; Character: TRigmMovieCharacter): TPsdCharacterAsset;
begin
  var Path := ResolveMoviePath(Project.FileName,Character.FileName);
  var Stamp := TFile.GetSize(Path).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(Path),TFormatSettings.Invariant);
  var Entry: TSourceEntry;
  if Sources.TryGetValue(Path,Entry) and (Entry.Stamp=Stamp) then Exit(Entry.Asset);
  if Sources.Count>=8 then Sources.Clear;
  Entry := TSourceEntry.Create;
  try Entry.Stamp := Stamp; Entry.Asset := TPsdCharacterAsset.Create(Path);
    Sources.AddOrSetValue(Path,Entry); Result := Entry.Asset;
  except Entry.Free; raise; end;
end;
function ViewState(Project: TRigmMovieProject; Character: TRigmMovieCharacter; Seconds: Double): TPsdFrameState;
begin
  Result := TPsdFrameState.Default; Result.Seconds := Seconds;
  Result.Expression := JS(Character.PsdView,'expression'); Result.Gaze := JS(Character.PsdView,'gaze','front');
  Result.NonFrontId := JS(Character.PsdView,'nonFrontId'); Result.Motion := JS(Character.PsdView,'motion','breathe');
  Result.Strength := JN(Character.PsdView,'strength',16); Result.AutoBlink := JB(Character.PsdView,'autoBlink',True);
  if not Character.RigSafe then Result.Motion := 'none';
  var Local,Start: Double; var Cue := Project.CueAt(Seconds,Local,Start);
  if (Cue=nil) or (Cue.SpeakerId<>Character.SpeakerId) then Exit;
  var P := Character.Expressions.GetValue(Cue.Emotion) as TJSONObject;
  if P=nil then P := Character.Expressions.GetValue('neutral') as TJSONObject;
  if P<>nil then begin Result.Expression := JS(P,'psdExpression',Result.Expression); Result.Variants := JA(P,'variants'); end;
  if Cue.Acting.Variants.Count>0 then Result.Variants := Cue.Acting.Variants;
  Result.AutoBlink := Result.AutoBlink and (Cue.Acting.BlinkStrength>0);
  if Cue.Motion='still' then Result.Motion := 'none';
  // 共通音素サンプラーの時刻を利用。音声が終わった後は閉じ口へ戻す。
  if Cue.LabFile<>'' then begin
    Result.HasPhoneme := True; Result.Phoneme := 'closed'; var Available: Boolean; var Phone: string;
    var Time := Local+Cue.Acting.LipLead;
    if (Time>=0) and (Time<Cue.AudioSeconds) and (Local<Cue.AudioSeconds) and (Cue.Acting.MouthGain>0) then begin
      MoviePhonemeSample(ResolveMoviePath(Project.FileName,Cue.LabFile),Time,Phone,Available);
      if Available then Result.Phoneme := Phone;
    end;
  end;
end;
function RenderPsdMovieCharacter(Project: TRigmMovieProject; Character: TRigmMovieCharacter;
  Seconds: Double; Audio: TRigmPcm; Width,Height: Integer): TBytes;
begin
  TMonitor.Enter(SourceLock);
  try Result := Source(Project,Character).Renderer.Frame(ViewState(Project,Character,Seconds),Width,Height);
  finally TMonitor.Exit(SourceLock); end;
end;
function PsdMovieExpressions(const Path: string): TJSONObject;
begin var Asset := TPsdCharacterAsset.Create(Path); try Result := Asset.Expressions; finally Asset.Free; end; end;
procedure ValidatePsdMovieCharacter(Project: TRigmMovieProject; Character: TRigmMovieCharacter);
begin
  TMonitor.Enter(SourceLock);
  try
    var Asset := Source(Project,Character); Asset.Character.Validate;
    for var Pair in Character.Expressions do for var V in JA(TJSONObject(Pair.JsonValue),'variants') do
      Asset.Character.CheckChoice(JS(TJSONObject(V),'groupId'),JS(TJSONObject(V),'partId'));
    Asset.Renderer.Composite(ViewState(Project,Character,0));
  finally TMonitor.Exit(SourceLock); end;
end;
initialization
  Sources := TObjectDictionary<string,TSourceEntry>.Create([doOwnsValues]); SourceLock := TObject.Create;
finalization
  Sources.Free; SourceLock.Free;
end.
