// 動画作品の保存モデル、区間時刻、素材パスと音声の有効性を定義する。GUIやジョブの実行状態は持たない。
unit RigmMovieModel;

interface

uses System.SysUtils, System.JSON, System.Generics.Collections, RigmModel, RigmMovieActing, RigmMovieComposition;

type
  TRigmMovieSpeaker = class
  public
    Id, Name, VoiceUuid, VoiceName, StyleName: string;
    StyleId: Integer;
    Speed, Pitch, Intonation, Volume: Double;
    constructor Create;
    function Json: TJSONObject;
  end;
  TRigmMovieCue = class
  public
    Id, Scene, SpeakerId, Text, Subtitle, Expression, Motion, Background, Emotion: string;
    VoiceQuery, VoiceQueryKey: string; // 選択行の詳細queryと、その入力元の指紋。
    VoiceReading: string; VoiceSettings: TJSONObject; // 空の読みは元の音声文。個別query値は任意。
    SubtitleNote: string; // 表示字幕のメモ。音声キーには含めない。
    VoiceStyleId: Integer;
    WaveFile, LabFile, AudioKey: string;
    VoiceHeardKey: string; // 最後まで再生した音声の指紋。入力変更後は一致しなくなる。
    AudioEffects: TJSONObject; // Per stable cue ID; source WAV remains immutable.
    EffectWaveFile,EffectAudioKey: string; // Derived preview cache only.
    AudioEffect: string; // 将来の音声エフェクト種別。現段階はnone（なし）。
    Pause, AudioSeconds: Double;
    Parameters: TJSONObject;
    Acting: TRigmMovieActing;
    constructor Create;
    destructor Destroy; override;
    function Json: TJSONObject;
    function SpokenText: string; // 実際に合成へ送る文。字幕・原稿は変更しない。
    class function FromJson(O: TJSONObject): TRigmMovieCue; static; // 既存保存値の再利用・複製。呼出側所有。
  end;
  TRigmMovieProject = class
  public
    Id, Title, CharacterFile, EngineUrl, FileName, FfmpegExe,EncodeProfile,OutputTarget: string;
    Width, Height, Fps: Integer;
    BackgroundColor: Cardinal;
    BgmFile: string; // Managed PCM16 WAV; original audio is never modified.
    BgmVolume, BgmFadeOut: Double; // Independent gain and requested end fade seconds.
    Revision: Integer;
    Modified: Boolean;
    ScriptWizard: TJSONObject; // 任意の段階式台本情報。旧作品ではnilのまま。
    EndCards: TJSONArray; // 発話sceneの後の独立した無音画像区間。
    WorkflowStage, PreviewKey, PreviewPath, PreviewHash, VideoKey, VideoPath, VideoHash: string;
    Layout,ThemeBackground,LDirection: string;
    Characters: TObjectList<TRigmMovieCharacter>;
    Scenes: TObjectList<TRigmMovieScene>;
    Speakers: TObjectList<TRigmMovieSpeaker>;
    Cues: TObjectList<TRigmMovieCue>;
    constructor Create;
    destructor Destroy; override;
    function Speaker(const SpeakerId: string): TRigmMovieSpeaker;
    function Cue(const CueId: string): TRigmMovieCue;
    function Character(const Id: string): TRigmMovieCharacter;
    function Scene(const Id: string): TRigmMovieScene;
    function SceneAt(Seconds: Double; out Start,Local: Double): TRigmMovieScene;
    function SceneDuration(S: TRigmMovieScene): Double;
    function CueStart(C: TRigmMovieCue): Double;
    function HasStoredAudio(C: TRigmMovieCue): Boolean;
    function EffectiveStyle(C: TRigmMovieCue): Integer;
    procedure EnableComposition;
    function Placement(const Path: string): TJSONObject;
    procedure BindCharacterPlacements;
    function Json: TJSONObject;
    function Clone: TRigmMovieProject;
    class function FromJson(O: TJSONObject): TRigmMovieProject; static;
    class function FromText(const Script: string): TRigmMovieProject; static;
    function VoiceQuerySourceKey(C: TRigmMovieCue): string;
    function EffectiveVoiceQuery(C: TRigmMovieCue): string;
    function AudioFingerprint(C: TRigmMovieCue): string;
    function AudioReady(C: TRigmMovieCue): Boolean;
    function AudioHeard(C: TRigmMovieCue): Boolean;
    function CueDuration(C: TRigmMovieCue): Double;
    function Duration: Double;
    function StoryDuration: Double;
    function CueAt(Seconds: Double; out LocalTime, Start: Double): TRigmMovieCue;
    procedure Changed;
    procedure Validate;
  end;

procedure ValidateVoiceQuery(const QueryJson: string);
procedure ValidateVoiceValues(Settings: TJSONObject); // 個別queryパラメータの範囲。
procedure ValidateVoiceReading(const Text: string); // UTF16と音声上限。
procedure SaveMovie(Project: TRigmMovieProject; const FileName: string; Organized: Boolean=False);
function LoadMovie(const FileName: string): TRigmMovieProject;
function MovieSchema: TJSONObject;
function ResolveMoviePath(const BaseFile, Path: string): string;

implementation

uses System.IOUtils, System.Math, System.StrUtils, System.Hash, Winapi.Windows, RigmJson, RigmMovieOutput, RigmMovieEndCards, RigmMovieTransitions, RigmVoiceEffectSettings;

constructor TRigmMovieSpeaker.Create;
begin inherited; Id := 'narrator'; Name := 'ナレーター'; StyleId := -1; Speed := 1; Intonation := 1; Volume := 1; end;
function TRigmMovieSpeaker.Json: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('id',Id); Result.AddPair('name',Name);
  AddN(Result,'styleId',StyleId); AddN(Result,'speed',Speed); AddN(Result,'pitch',Pitch);
  AddN(Result,'intonation',Intonation); AddN(Result,'volume',Volume);
  if VoiceUuid<>'' then begin Result.AddPair('voiceUuid',VoiceUuid); Result.AddPair('voiceName',VoiceName); Result.AddPair('styleName',StyleName); end;
end;
constructor TRigmMovieCue.Create;
begin
  inherited; Id := NewRigmId; Scene := 'scene1'; SpeakerId := 'narrator';
  AudioEffects := TJSONObject.Create; VoiceSettings := TJSONObject.Create; VoiceStyleId := -1; AudioEffect := 'none'; Emotion := 'neutral'; Pause := 0.3; Expression := 'neutral'; Motion := 'idle'; Parameters := TJSONObject.Create; Acting := TRigmMovieActing.Create;
end;
destructor TRigmMovieCue.Destroy;
begin AudioEffects.Free; VoiceSettings.Free; Acting.Free; Parameters.Free; inherited; end;
function TRigmMovieCue.SpokenText: string;
begin Result := VoiceReading; if Result='' then Result := Text; end;
function TRigmMovieCue.Json: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('id',Id); Result.AddPair('scene',Scene);
  Result.AddPair('speaker',SpeakerId); Result.AddPair('text',Text); Result.AddPair('subtitle',Subtitle); if SubtitleNote<>'' then Result.AddPair('subtitleNote',SubtitleNote);
  Result.AddPair('expression',Expression); Result.AddPair('motion',Motion); Result.AddPair('background',Background);
  AddN(Result,'pause',Pause); AddN(Result,'audioSeconds',AudioSeconds);
  Result.AddPair('waveFile',WaveFile); Result.AddPair('labFile',LabFile); Result.AddPair('audioKey',AudioKey);
  if VoiceHeardKey<>'' then Result.AddPair('voiceHeardKey',VoiceHeardKey);
  Result.AddPair('audioEffect',AudioEffect); Result.AddPair('audioEffects',AudioEffects.Clone as TJSONObject);
  Result.AddPair('effectWaveFile',EffectWaveFile); Result.AddPair('effectAudioKey',EffectAudioKey);
  if VoiceQuery<>'' then begin Result.AddPair('voiceQuery',VoiceQuery); Result.AddPair('voiceQueryKey',VoiceQueryKey); end;
  if VoiceReading<>'' then Result.AddPair('voiceReading',VoiceReading);
  if VoiceSettings.Count>0 then Result.AddPair('voiceSettings',VoiceSettings.Clone as TJSONObject);
  Result.AddPair('parameters',Parameters.Clone as TJSONObject);
  Result.AddPair('acting',Acting.Json);
  if Emotion<>'neutral' then Result.AddPair('emotion',Emotion);
  if VoiceStyleId>=0 then AddN(Result,'voiceStyleId',VoiceStyleId);
end;
class function TRigmMovieCue.FromJson(O: TJSONObject): TRigmMovieCue;
begin
  Result := TRigmMovieCue.Create; var C := Result;
  try
      var Q := O; C.Id := JS(Q,'id',C.Id); C.Scene := JS(Q,'scene',C.Scene);
      C.SpeakerId := JS(Q,'speaker','narrator'); C.Text := JS(Q,'text'); C.Subtitle := JS(Q,'subtitle',C.Text); C.SubtitleNote := JS(Q,'subtitleNote');
      if (Q.GetValue('voiceReading')<>nil) and not (Q.GetValue('voiceReading') is TJSONString) then raise ERigm.Create('読みの保存形式が不正です。');
      C.VoiceReading := JS(Q,'voiceReading');
      for var K in ['voiceQuery','voiceQueryKey'] do
        if (Q.GetValue(K)<>nil) and not (Q.GetValue(K) is TJSONString) then raise ERigm.Create('詳細queryの保存形式が不正です。');
      C.VoiceQuery := JS(Q,'voiceQuery'); C.VoiceQueryKey := JS(Q,'voiceQueryKey');
      if Q.GetValue('voiceSettings')<>nil then begin
        if not (Q.GetValue('voiceSettings') is TJSONObject) then raise ERigm.Create('音声query値の保存形式が不正です。');
        var Values := JO(Q,'voiceSettings').Clone as TJSONObject; C.VoiceSettings.Free; C.VoiceSettings := Values;
      end;
      C.Emotion := JS(Q,'emotion','neutral'); C.VoiceStyleId := JI(Q,'voiceStyleId',-1); C.Expression := JS(Q,'expression','neutral'); C.Motion := JS(Q,'motion','idle'); C.Background := JS(Q,'background');
      C.Pause := JN(Q,'pause',0.3); C.AudioSeconds := JN(Q,'audioSeconds');
      C.WaveFile := JS(Q,'waveFile'); C.LabFile := JS(Q,'labFile'); C.AudioKey := JS(Q,'audioKey');
      for var K in ['voiceHeardKey','audioEffect','effectWaveFile','effectAudioKey'] do
        if (Q.GetValue(K)<>nil) and not (Q.GetValue(K) is TJSONString) then raise ERigm.Create('音声再生・エフェクトの保存形式が不正です。');
      C.VoiceHeardKey := JS(Q,'voiceHeardKey'); C.AudioEffect := JS(Q,'audioEffect','none');
      C.EffectWaveFile := JS(Q,'effectWaveFile'); C.EffectAudioKey := JS(Q,'effectAudioKey');
      if Q.GetValue('audioEffects')<>nil then begin
        if not (Q.GetValue('audioEffects') is TJSONObject) then raise ERigm.Create('Audio effects must be an object');
        var Effects := JO(Q,'audioEffects').Clone as TJSONObject; C.AudioEffects.Free; C.AudioEffects := Effects;
      end;
      if Q.GetValue('parameters') <> nil then begin C.Parameters.Free; C.Parameters := JO(Q,'parameters').Clone as TJSONObject; end;
      if Q.GetValue('acting')<>nil then begin C.Acting.Free; C.Acting := TRigmMovieActing.FromJson(JO(Q,'acting')); end;
  except Result.Free; raise; end;
end;
constructor TRigmMovieProject.Create;
begin
  inherited; Id := NewRigmId; Title := '新しい解説動画'; EngineUrl := 'http://127.0.0.1:50021';
  MoviePresetDimensions('fullhd',Width,Height,Fps); BackgroundColor := $302820;
  WorkflowStage := 'script'; Layout := 'theme'; LDirection := 'right';
  Characters := TObjectList<TRigmMovieCharacter>.Create(True); Scenes := TObjectList<TRigmMovieScene>.Create(True);
  EncodeProfile := 'balanced'; BgmVolume := 0.25;
  EndCards := TJSONArray.Create;
  Speakers := TObjectList<TRigmMovieSpeaker>.Create(True); Cues := TObjectList<TRigmMovieCue>.Create(True);
  Speakers.Add(TRigmMovieSpeaker.Create); Revision := 1;
end;
destructor TRigmMovieProject.Destroy;
begin EndCards.Free; ScriptWizard.Free; Scenes.Free; Characters.Free; Cues.Free; Speakers.Free; inherited; end;
procedure TRigmMovieProject.Changed;
begin Inc(Revision); Modified := True; end;
function TRigmMovieProject.Speaker(const SpeakerId: string): TRigmMovieSpeaker;
begin Result := nil; for var S in Speakers do if S.Id = SpeakerId then Exit(S); end;
function TRigmMovieProject.Cue(const CueId: string): TRigmMovieCue;
begin Result := nil; for var C in Cues do if C.Id = CueId then Exit(C); end;
function TRigmMovieProject.Json: TJSONObject;
var A: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format','RIGM-MOVIE'); AddN(Result,'formatVersion',1); Result.AddPair('projectId',Id);
  Result.AddPair('ffmpeg',FfmpegExe); Result.AddPair('title',Title); Result.AddPair('character',CharacterFile); Result.AddPair('engineUrl',EngineUrl);
  AddN(Result,'width',Width); AddN(Result,'height',Height); AddN(Result,'fps',Fps);
  Result.AddPair('outputPreset',MoviePresetId(Width,Height,Fps)); Result.AddPair('encodeProfile',EncodeProfile);
  Result.AddPair('outputTarget',OutputTarget);
  var Bgm := TJSONObject.Create; Bgm.AddPair('file',BgmFile);
  AddN(Bgm,'volume',BgmVolume); AddN(Bgm,'fadeOut',BgmFadeOut); Result.AddPair('bgm',Bgm);
  var Workflow := TJSONObject.Create;
  Workflow.AddPair('stage',WorkflowStage); Workflow.AddPair('previewKey',PreviewKey);
  Workflow.AddPair('previewPath',PreviewPath); Workflow.AddPair('previewHash',PreviewHash);
  Workflow.AddPair('videoKey',VideoKey); Workflow.AddPair('videoPath',VideoPath); Workflow.AddPair('videoHash',VideoHash);
  Result.AddPair('workflow',Workflow);
  if ScriptWizard<>nil then Result.AddPair('scriptWizard',ScriptWizard.Clone as TJSONObject);
  if EndCards.Count>0 then Result.AddPair('endCards',EndCards.Clone as TJSONArray);
  AddN(Result,'backgroundColor',BackgroundColor); AddN(Result,'revision',Revision);
  A := TJSONArray.Create; Result.AddPair('speakers',A); for var S in Speakers do A.AddElement(S.Json);
  A := TJSONArray.Create; Result.AddPair('cues',A); for var C in Cues do A.AddElement(C.Json);
  if (Scenes.Count>0) or (Characters.Count>0) or
    ((ScriptWizard<>nil) and (ScriptWizard.GetValue('layoutChoice')<>nil)) then begin
    Result.AddPair('layout',Layout); Result.AddPair('themeBackground',ThemeBackground); Result.AddPair('lDirection',LDirection);
    A := TJSONArray.Create; Result.AddPair('characters',A); for var Character in Characters do A.AddElement(Character.Json);
    A := TJSONArray.Create; Result.AddPair('scenes',A); for var Scene in Scenes do A.AddElement(Scene.Json);
  end;
end;
function TRigmMovieProject.Clone: TRigmMovieProject;
var O: TJSONObject;
begin O := Json; try Result := FromJson(O); Result.FileName := FileName; Result.Modified := Modified; finally O.Free; end; end;
class function TRigmMovieProject.FromJson(O: TJSONObject): TRigmMovieProject;
var S: TRigmMovieSpeaker;
begin
  Result := TRigmMovieProject.Create;
  try
    if JS(O,'format','RIGM-MOVIE') <> 'RIGM-MOVIE' then raise ERigm.Create('動画プロジェクト形式が違います。');
    if JI(O,'formatVersion',1) <> 1 then raise ERigm.Create('未対応の動画プロジェクト版です。');
    Result.Id := JS(O,'projectId',Result.Id); Result.Title := JS(O,'title',Result.Title);
    if O.GetValue('scriptWizard')<>nil then Result.ScriptWizard := JO(O,'scriptWizard').Clone as TJSONObject;
    if O.GetValue('endCards')<>nil then begin if not(O.GetValue('endCards') is TJSONArray) then raise ERigm.Create('末尾カードは配列です。'); Result.EndCards.Free; Result.EndCards := JA(O,'endCards').Clone as TJSONArray; end;
    Result.FfmpegExe := JS(O,'ffmpeg'); Result.CharacterFile := JS(O,'character'); Result.EngineUrl := JS(O,'engineUrl',Result.EngineUrl);
    var Preset := JS(O,'outputPreset','custom'); var PW,PH,PF: Integer; MoviePresetDimensions(Preset,PW,PH,PF);
    if PW>0 then begin Result.Width := PW; Result.Height := PH; Result.Fps := PF; end;
    Result.Width := JI(O,'width',Result.Width); Result.Height := JI(O,'height',Result.Height); Result.Fps := JI(O,'fps',Result.Fps);
    Result.Layout := LowerCase(JS(O,'layout','theme')); Result.ThemeBackground := JS(O,'themeBackground'); Result.LDirection := LowerCase(JS(O,'lDirection','right'));
    if O.GetValue('characters')<>nil then for var V in JA(O,'characters') do begin if not(V is TJSONObject) then raise ERigm.Create('Character object required'); Result.Characters.Add(TRigmMovieCharacter.FromJson(TJSONObject(V))); end;
    if O.GetValue('scenes')<>nil then for var V in JA(O,'scenes') do begin if not(V is TJSONObject) then raise ERigm.Create('Scene object required'); Result.Scenes.Add(TRigmMovieScene.FromJson(TJSONObject(V))); end;
    Result.EncodeProfile := JS(O,'encodeProfile','balanced');
    Result.OutputTarget := JS(O,'outputTarget');
    if O.GetValue('bgm')<>nil then begin
      var Bgm := JO(O,'bgm');
      if (Bgm.GetValue('file')<>nil) and not (Bgm.GetValue('file') is TJSONString) then raise ERigm.Create('BGM file must be a string');
      for var Key in ['volume','fadeOut'] do if (Bgm.GetValue(Key)<>nil) and not (Bgm.GetValue(Key) is TJSONNumber) then raise ERigm.Create('BGM settings must be numeric');
      Result.BgmFile := JS(Bgm,'file'); Result.BgmVolume := JN(Bgm,'volume',0.25); Result.BgmFadeOut := JN(Bgm,'fadeOut');
    end;
    if O.GetValue('workflow')<>nil then begin
      var Workflow := JO(O,'workflow'); Result.WorkflowStage := JS(Workflow,'stage','script');
      Result.PreviewKey := JS(Workflow,'previewKey'); Result.PreviewPath := JS(Workflow,'previewPath'); Result.PreviewHash := JS(Workflow,'previewHash');
      Result.VideoKey := JS(Workflow,'videoKey'); Result.VideoPath := JS(Workflow,'videoPath'); Result.VideoHash := JS(Workflow,'videoHash');
    end;
    Result.BackgroundColor := JI(O,'backgroundColor',$302820); Result.Revision := Max(1,JI(O,'revision',1));
    if O.GetValue('speakers') <> nil then begin
      Result.Speakers.Clear;
      for var V in JA(O,'speakers') do begin
        if not (V is TJSONObject) then raise ERigm.Create('話者オブジェクトが必要です。');
        S := TRigmMovieSpeaker.Create; Result.Speakers.Add(S);
        S.Id := JS(TJSONObject(V),'id'); S.Name := JS(TJSONObject(V),'name',S.Id);
        S.StyleId := JI(TJSONObject(V),'styleId',-1); S.Speed := JN(TJSONObject(V),'speed',1);
        S.Pitch := JN(TJSONObject(V),'pitch'); S.Intonation := JN(TJSONObject(V),'intonation',1);
        S.Volume := JN(TJSONObject(V),'volume',1); S.VoiceUuid := JS(TJSONObject(V),'voiceUuid'); S.VoiceName := JS(TJSONObject(V),'voiceName'); S.StyleName := JS(TJSONObject(V),'styleName');
      end;
    end;
    if O.GetValue('cues') <> nil then for var V in JA(O,'cues') do begin
      if not (V is TJSONObject) then raise ERigm.Create('セリフオブジェクトが必要です。');
      Result.Cues.Add(TRigmMovieCue.FromJson(TJSONObject(V)));
    end;
    Result.BindCharacterPlacements; Result.Validate;
  except Result.Free; raise; end;
end;
class function TRigmMovieProject.FromText(const Script: string): TRigmMovieProject;
var Scene: string; C: TRigmMovieCue; P: Integer;
begin
  Result := TRigmMovieProject.Create;
  try
    Scene := 'scene1';
    for var Raw in Script.Replace(#13,'').Split([#10]) do begin
      var Line := Trim(Raw); if Line = '' then Continue;
      if Line.StartsWith('#') then begin Scene := Trim(Line.Substring(1)); if Scene = '' then Scene := 'scene1'; Continue; end;
      C := TRigmMovieCue.Create; Result.Cues.Add(C); C.Scene := Scene;
      P := Pos(':',Line); if P = 0 then P := Pos('：',Line);
      if (P > 1) and (P < 40) then begin
        C.SpeakerId := Trim(Copy(Line,1,P-1)); C.Text := Trim(Copy(Line,P+1,MaxInt));
        if Result.Speaker(C.SpeakerId) = nil then begin
          var S := TRigmMovieSpeaker.Create; S.Id := C.SpeakerId; S.Name := S.Id; Result.Speakers.Add(S);
        end;
      end else C.Text := Line;
      C.Subtitle := C.Text;
    end;
    Result.Validate; Result.Modified := True;
  except Result.Free; raise; end;
end;
procedure ValidateVoiceQuery(const QueryJson: string);
  procedure CheckTree(V: TJSONValue; Depth: Integer);
  begin
    if Depth>32 then raise ERigm.Create('詳細queryの階層が深すぎます。');
    if V is TJSONNumber then begin
      if not Finite(TJSONNumber(V).AsDouble) then raise ERigm.Create('詳細queryは有限の数値で指定してください。');
    end else if V is TJSONObject then begin
      var Seen := TDictionary<string,Boolean>.Create;
      try for var P in TJSONObject(V) do begin
        if Seen.ContainsKey(P.JsonString.Value) then raise ERigm.Create('詳細queryの項目が重複しています。');
        Seen.Add(P.JsonString.Value,True); CheckTree(P.JsonValue,Depth+1);
      end; finally Seen.Free; end;
    end else if V is TJSONArray then for var Item in TJSONArray(V) do CheckTree(Item,Depth+1);
  end;
  procedure CheckMora(M: TJSONObject);
  begin
    if not (M.GetValue('text') is TJSONString) or not (M.GetValue('vowel') is TJSONString) then raise ERigm.Create('モーラの形式が不正です。');
    for var K in ['pitch','vowel_length','consonant_length'] do begin
      var V := M.GetValue(K); if (K='consonant_length') and ((V=nil) or (V is TJSONNull)) then Continue;
      if not (V is TJSONNumber) or (TJSONNumber(V).AsDouble<0) or (TJSONNumber(V).AsDouble>20) then raise ERigm.Create('モーラの音高・長さが範囲外です。');
    end;
  end;
begin
  if QueryJson='' then Exit;
  if Length(QueryJson)>512*1024 then raise ERigm.Create('詳細queryが大きすぎます。');
  var V := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (V is TJSONObject) then raise ERigm.Create('詳細queryはJSONオブジェクトで指定してください。');
    CheckTree(V,0); var O := TJSONObject(V);
    if not (O.GetValue('accent_phrases') is TJSONArray) then raise ERigm.Create('詳細queryにアクセント句がありません。');
    for var Item in TJSONArray(O.GetValue('accent_phrases')) do begin
      if not (Item is TJSONObject) then raise ERigm.Create('アクセント句の形式が不正です。');
      var Phrase := TJSONObject(Item);
      if not (Phrase.GetValue('moras') is TJSONArray) or not (Phrase.GetValue('accent') is TJSONNumber) then raise ERigm.Create('アクセント句の形式が不正です。');
      var Moras := TJSONArray(Phrase.GetValue('moras')); var Accent := TJSONNumber(Phrase.GetValue('accent')).AsDouble;
      if (Moras.Count=0) or (Accent<>Trunc(Accent)) or (Accent<1) or (Accent>Moras.Count) then raise ERigm.Create('アクセント位置が範囲外です。');
      for var Mora in Moras do begin if not (Mora is TJSONObject) then raise ERigm.Create('モーラの形式が不正です。'); CheckMora(TJSONObject(Mora)); end;
      var Pause := Phrase.GetValue('pause_mora'); if (Pause<>nil) and not (Pause is TJSONNull) then begin
        if not (Pause is TJSONObject) then raise ERigm.Create('句間の形式が不正です。'); CheckMora(TJSONObject(Pause));
      end;
    end;
  finally V.Free; end;
end;
procedure ValidateVoiceValues(Settings: TJSONObject);
begin
  if Settings=nil then raise ERigm.Create('音声query値がありません。');
  for var P in Settings do begin
    if not (P.JsonValue is TJSONNumber) then raise ERigm.Create('音声query値は数値で指定してください。');
    var K := P.JsonString.Value; var V := TJSONNumber(P.JsonValue).AsDouble; var Low := 0.0; var High := 2.0;
    if K='speedScale' then Low := 0.5 else if K='pitchScale' then begin Low := -0.15; High := 0.15; end
    else if MatchStr(K,['prePhonemeLength','postPhonemeLength']) then High := 5
    else if not MatchStr(K,['intonationScale','volumeScale']) then raise ERigm.Create('未対応の音声query値です。');
    if not Finite(V) or (V<Low) or (V>High) then raise ERigm.Create('音声query値が範囲外です。');
  end;
end;
procedure ValidateVoiceReading(const Text: string);
begin
  if Length(Text)>2000 then raise ERigm.Create('読みは2000文字以内です。');
  var I := 1;
  while I<=Length(Text) do begin
    var N := Ord(Text[I]); if (N<32) and not CharInSet(Text[I],[#9,#10,#13]) then raise ERigm.Create('読みの制御文字が不正です。');
    if (N>=$D800) and (N<=$DBFF) then begin
      if (I=Length(Text)) or (Ord(Text[I+1])<$DC00) or (Ord(Text[I+1])>$DFFF) then raise ERigm.Create('読みの文字が途中で切れています。'); Inc(I);
    end else if (N>=$DC00) and (N<=$DFFF) then raise ERigm.Create('読みの文字が途中で切れています。');
    Inc(I);
  end;
end;
procedure TRigmMovieProject.Validate;
var Seen: TDictionary<string,Boolean>;
begin
  BindCharacterPlacements;
  ValidateMovieEndCards(EndCards);
  if not MatchText(WorkflowStage,['script','setup','audio','preview','export','complete']) then raise ERigm.Create('Invalid movie workflow stage');
  MovieEncoderOptions(EncodeProfile);
  if (Width < 160) or (Width > 3840) or Odd(Width) or (Height < 120) or (Height > 2160) or Odd(Height) or
    (Fps < 1) or (Fps > 60) then raise ERigm.Create('動画寸法は偶数160～3840×120～2160、fpsは1～60です。');
  if (Cues.Count > 2000) or (Speakers.Count < 1) or (Speakers.Count > 100) then raise ERigm.Create('台本の件数上限です。');
  // Loopback only: scripts and voice data never leave this computer.
  if not (EngineUrl.StartsWith('http://127.0.0.1:') or EngineUrl.StartsWith('http://localhost:')) or
    (Pos('/',EngineUrl.Substring(7)) > 0) or (Pos('@',EngineUrl) > 0) or (Pos('?',EngineUrl) > 0) then
    raise ERigm.Create('VOICEVOX接続先はローカルHTTPのホストとポートだけを指定してください。');
  var Port := Copy(EngineUrl,LastDelimiter(':',EngineUrl)+1,MaxInt);
  var PortNumber: Integer; if not TryStrToInt(Port,PortNumber) or (PortNumber < 1) or (PortNumber > 65535) then raise ERigm.Create('接続ポートが不正です。');
  Seen := TDictionary<string,Boolean>.Create;
  try
    for var S in Speakers do begin
      if (S.Id = '') or (Length(S.Id)>128) or Seen.ContainsKey(S.Id) then raise ERigm.Create('話者IDが空か重複しています。');
      Seen.Add(S.Id,True);
      if not Finite(S.Speed) or (S.Speed<0.5) or (S.Speed>2) or not Finite(S.Pitch) or (Abs(S.Pitch)>0.15) or
        not Finite(S.Intonation) or (S.Intonation<0) or (S.Intonation>2) or not Finite(S.Volume) or (S.Volume<0) or (S.Volume>2) or
        (S.StyleId < -1) then raise ERigm.Create('話者音声設定が範囲外です。');
    end;
    Seen.Clear;
    if not MatchText(Layout,['theme','l']) or not MatchText(LDirection,['left','right']) then raise ERigm.Create('Invalid composition layout');
    if (Characters.Count>20) or (Scenes.Count>2000) then raise ERigm.Create('Composition exceeds supported item counts');
    for var Character in Characters do begin
      Character.Validate; if Seen.ContainsKey(Character.Id) then raise ERigm.Create('Duplicate character identifier'); Seen.Add(Character.Id,True);
      if Speaker(Character.SpeakerId)=nil then raise ERigm.Create('Character speaker does not exist');
      if (Layout='l') and (Character.PlacementRef='') and Character.Visible and (((LDirection='left') and (Character.X+Character.Width/2>720)) or
        ((LDirection='right') and (Character.X+Character.Width/2<1200))) then raise ERigm.Create('L layout characters must remain on the selected side');
    end;
    Seen.Clear;
    for var Scene in Scenes do begin
      Scene.Validate; ValidateMovieImageTransitions(Scene.Animation); if Seen.ContainsKey(Scene.Id) then raise ERigm.Create('Duplicate scene identifier'); Seen.Add(Scene.Id,True);
      var Count := 0; for var C in Cues do if C.Scene=Scene.Id then Inc(Count);
      if Count=0 then raise ERigm.Create('Each scene needs at least one dialogue or subtitle cue');
    end;
    Seen.Clear;
    for var C in Cues do begin
      C.Acting.Validate; ValidateVoiceEffectSettings(C.AudioEffects);
      if not (Length(C.EffectAudioKey) in [0,64]) or (Length(C.EffectWaveFile)>32760) then raise ERigm.Create('Invalid derived effect audio reference');
      if not (Length(C.VoiceHeardKey) in [0,64]) or (C.AudioEffect='') or (Length(C.AudioEffect)>64) then raise ERigm.Create('音声再生・エフェクトの保存値が不正です。');
      if (Scenes.Count>0) and (Scene(C.Scene)=nil) then raise ERigm.Create('Cue scene does not exist');
    if (C.VoiceStyleId < -1) or not MatchText(C.Emotion,MovieEmotionIds) then raise ERigm.Create('Invalid cue emotion or voice style');
      if (C.Id = '') or Seen.ContainsKey(C.Id) then raise ERigm.Create('セリフIDが空か重複しています。'); Seen.Add(C.Id,True);
      if Speaker(C.SpeakerId) = nil then raise ERigm.Create('セリフの話者がありません: '+C.SpeakerId);
      if (Length(C.Text)>2000) or (Length(C.Subtitle)>3000) or (Length(C.Scene)>300) then raise ERigm.Create('セリフが長すぎます。');
      ValidateVoiceReading(C.VoiceReading); ValidateVoiceValues(C.VoiceSettings); ValidateVoiceQuery(C.VoiceQuery);
      if (C.VoiceQuery<>'') and (Length(C.VoiceQueryKey)<>64) then raise ERigm.Create('詳細queryの入力元指紋が不正です。');
      if not Finite(C.Pause) or (C.Pause<0) or (C.Pause>60) or not Finite(C.AudioSeconds) or (C.AudioSeconds<0) or (C.AudioSeconds>600) then raise ERigm.Create('セリフ時間が範囲外です。');
      if not MatchText(C.Expression,['neutral','smile','serious','sad']) or not MatchText(C.Motion,['idle','still','nod','emphasis']) then raise ERigm.Create('未対応の表情・動作です。');
      for var Pair in C.Parameters do if not (Pair.JsonValue is TJSONNumber) or not Finite(TJSONNumber(Pair.JsonValue).AsDouble) then raise ERigm.Create('演技パラメータには有限の数値を指定してください。');
    end;
  finally Seen.Free; end;
  if not Finite(BgmVolume) or (BgmVolume<0) or (BgmVolume>2) or not Finite(BgmFadeOut) or
    (BgmFadeOut<0) or (BgmFadeOut>3600) or (Length(BgmFile)>32760) or
    ((BgmFile<>'') and not SameText(ExtractFileExt(BgmFile),'.wav')) then raise ERigm.Create('BGM requires WAV, gain 0..2 and fade 0..3600 seconds');
  if Duration > 3600 then raise ERigm.Create('動画は1時間以内にしてください。');
end;
function TRigmMovieProject.VoiceQuerySourceKey(C: TRigmMovieCue): string;
begin Result := THashSHA2.GetHashString(EngineUrl+#10+C.SpokenText+#10+EffectiveStyle(C).ToString+#10+Speaker(C.SpeakerId).VoiceUuid); end;
function TRigmMovieProject.EffectiveVoiceQuery(C: TRigmMovieCue): string;
begin Result := ''; if (C.VoiceQuery<>'') and (C.VoiceQueryKey=VoiceQuerySourceKey(C)) then Result := C.VoiceQuery; end;
function TRigmMovieProject.AudioFingerprint(C: TRigmMovieCue): string;
var O: TJSONObject;
begin
  O := Speaker(C.SpeakerId).Json;
  if C.VoiceStyleId>=0 then begin O.RemovePair('styleId').Free; AddN(O,'styleId',C.VoiceStyleId); end;
  if C.VoiceSettings.Count>0 then O.AddPair('voiceSettings',C.VoiceSettings.Clone as TJSONObject);
  if EffectiveVoiceQuery(C)<>'' then O.AddPair('voiceQuery',EffectiveVoiceQuery(C));
  try Result := THashSHA2.GetHashString(EngineUrl+#10+C.SpokenText+#10+O.ToJSON); finally O.Free; end;
end;
function TRigmMovieProject.AudioReady(C: TRigmMovieCue): Boolean;
begin
  if C.SpokenText='' then Exit(not ((Scenes.Count>0) and (C.WaveFile<>'') and (C.AudioSeconds>0)));
  Result := (C.AudioSeconds>0) and (C.AudioKey=AudioFingerprint(C)) and FileExists(ResolveMoviePath(FileName,C.WaveFile));
end;
function TRigmMovieProject.AudioHeard(C: TRigmMovieCue): Boolean;
begin Result := AudioReady(C) and ((C.SpokenText='') or (C.VoiceHeardKey=AudioFingerprint(C))); end;
function TRigmMovieProject.CueDuration(C: TRigmMovieCue): Double;
begin
  if (Scenes.Count>0) and (C.AudioSeconds>0) and HasStoredAudio(C) then Result := C.AudioSeconds
  else if C.Text = '' then Result := 0 else if AudioReady(C) then Result := C.AudioSeconds else Result := Max(0.8,Length(C.Text)/6.0);
  Result := Result+C.Pause;
end;
function TRigmMovieProject.Character(const Id: string): TRigmMovieCharacter;
begin Result := nil; for var C in Characters do if C.Id=Id then Exit(C); end;
function TRigmMovieProject.Scene(const Id: string): TRigmMovieScene;
begin Result := nil; for var S in Scenes do if S.Id=Id then Exit(S); end;
function TRigmMovieProject.HasStoredAudio(C: TRigmMovieCue): Boolean;
begin Result := (C.Text='') or ((C.AudioSeconds>0) and (C.WaveFile<>'') and FileExists(ResolveMoviePath(FileName,C.WaveFile))); end;
function TRigmMovieProject.EffectiveStyle(C: TRigmMovieCue): Integer;
begin Result := C.VoiceStyleId; if Result<0 then Result := Speaker(C.SpeakerId).StyleId; end;
function TRigmMovieProject.SceneDuration(S: TRigmMovieScene): Double;
begin Result := S.Padding; for var C in Cues do if C.Scene=S.Id then Result := Result+CueDuration(C); end;
function TRigmMovieProject.StoryDuration: Double;
begin
  Result := 0;
  if Scenes.Count>0 then begin for var S in Scenes do Result := Result+SceneDuration(S); end
  else for var C in Cues do Result := Result+CueDuration(C);
end;
function TRigmMovieProject.Duration: Double;
begin Result := StoryDuration+MovieEndCardsDuration(EndCards); end;
function TRigmMovieProject.SceneAt(Seconds: Double; out Start,Local: Double): TRigmMovieScene;
begin
  Result := nil; Start := 0; Local := 0;
  for var S in Scenes do begin if (Seconds>=Start) and (Seconds<Start+SceneDuration(S)) then begin Local := Seconds-Start; Exit(S); end; Start := Start+SceneDuration(S); end;
end;
function TRigmMovieProject.CueStart(C: TRigmMovieCue): Double;
begin
  Result := 0;
  if Scenes.Count>0 then begin
    for var S in Scenes do begin
      if S.Id=C.Scene then begin for var Q in Cues do if Q.Scene=S.Id then begin if Q=C then Exit; Result := Result+CueDuration(Q); end; Exit; end;
      Result := Result+SceneDuration(S);
    end;
  end else for var Q in Cues do begin if Q=C then Exit; Result := Result+CueDuration(Q); end;
end;
function TRigmMovieProject.CueAt(Seconds: Double; out LocalTime, Start: Double): TRigmMovieCue;
begin
  Result := nil; Start := 0; LocalTime := 0;
  if Scenes.Count>0 then begin
    var SceneLocal,SceneStart: Double; var S := SceneAt(Seconds,SceneStart,SceneLocal);
    if S=nil then Exit; Start := SceneStart;
    for var C in Cues do if C.Scene=S.Id then begin
      var D := CueDuration(C);
      if (Seconds>=Start) and (Seconds<Start+D) then begin LocalTime := Seconds-Start; Exit(C); end;
      Start := Start+D;
    end;
  end else for var C in Cues do begin
    var D := CueDuration(C);
    if (Seconds>=Start) and (Seconds<Start+D) then begin LocalTime := Seconds-Start; Exit(C); end;
    Start := Start+D;
  end;
end;
function TRigmMovieProject.Placement(const Path: string): TJSONObject;
begin
  Result := nil; if (ScriptWizard=nil) or not (ScriptWizard.GetValue('placements') is TJSONArray) then Exit;
  for var V in JA(ScriptWizard,'placements') do if (V is TJSONObject) and SameText(JS(TJSONObject(V),'path'),Path) then Exit(TJSONObject(V));
end;
procedure TRigmMovieProject.BindCharacterPlacements;
begin
  for var C in Characters do begin
    C.BindPlacement(nil);
    if C.PlacementRef<>'' then begin
      var O := Placement(C.PlacementRef); if O=nil then raise ERigm.Create('Character placement reference is missing: '+C.PlacementRef);
      C.BindPlacement(O);
    end;
  end;
end;
procedure TRigmMovieProject.EnableComposition;
begin
  if (ScriptWizard<>nil) and (ScriptWizard.GetValue('placements') is TJSONArray) then begin
    if (FileName='') or not SameText(ExtractFileName(ExtractFileDir(FileName)),Id) or
      not SameText(ExtractFileName(ExtractFileDir(ExtractFileDir(FileName))),'Projects') then
      raise ERigm.Create('Wizard composition must use its canonical project folder');
    var Root := ExtractFileDir(ExtractFileDir(ExtractFileDir(FileName)));
    for var V in JA(ScriptWizard,'selectedCharacters') do begin
      var S := TJSONObject(V); var Path := JS(S,'path'); var Found := False;
      if (Path='') or TPath.IsPathRooted(Path) or
        not StartsText(IncludeTrailingPathDelimiter(Root),TPath.GetFullPath(TPath.Combine(Root,Path))) then
        raise ERigm.Create('Wizard character reference must remain within its data root');
      for var C in Characters do if SameText(C.PlacementRef,Path) then Found := True;
      var SpeakerId := 'narrator';
      if ScriptWizard.GetValue('casting') is TJSONObject then for var R in JA(JO(ScriptWizard,'casting'),'roles') do
        if JB(TJSONObject(R),'active') and SameText(JS(TJSONObject(R),'path'),Path) then SpeakerId := JS(TJSONObject(R),'speakerId');
      for var C in Characters do if SameText(C.PlacementRef,Path) then C.SpeakerId := SpeakerId;
      if Found then Continue;
      var C := TRigmMovieCharacter.Create; C.SpeakerId := SpeakerId; C.Name := JS(S,'name'); C.RenderFormat := JS(S,'renderFormat'); C.PlacementRef := Path;
      C.FileName := ExtractRelativePath(ExtractFilePath(FileName),TPath.Combine(Root,Path)); Characters.Add(C);
    end;
    BindCharacterPlacements;
  end;
  if Scenes.Count=0 then for var C in Cues do begin
    var S: TRigmMovieScene := nil;
    for var Existing in Scenes do if Existing.Title=C.Scene then S := Existing;
    if S=nil then begin S := TRigmMovieScene.Create; S.Title := C.Scene; Scenes.Add(S); end;
    C.Scene := S.Id;
  end;
  if (Characters.Count=0) and (CharacterFile<>'') then begin
    var C := TRigmMovieCharacter.Create; C.FileName := CharacterFile; C.Name := 'キャラクター';
    if Cues.Count>0 then C.SpeakerId := Cues[0].SpeakerId;
    Characters.Add(C);
  end;
end;
function ResolveMoviePath(const BaseFile, Path: string): string;
begin
  if Path = '' then Exit(''); if Path='@sample' then Exit(Path); if TPath.IsPathRooted(Path) then Exit(ExpandFileName(Path));
  if BaseFile='' then Result := ExpandFileName(Path) else Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(BaseFile),Path));
end;
procedure SaveMovie(Project: TRigmMovieProject; const FileName: string; Organized: Boolean);
var Temp,TargetFile,AssetDirectory: string; O: TJSONObject; Saved: TRigmMovieProject;
  function Asset(const Path: string): string;
  var Source,Name,Target: string;
  begin
    if (Path='') or (Path='@sample') then Exit(Path);
    Source := ResolveMoviePath(Project.FileName,Path);
    if not FileExists(Source) then Exit(Source);
    Name := THashSHA2.GetHashStringFromFile(Source)+LowerCase(ExtractFileExt(Source));
    var Directory := AssetDirectory;
    if Organized then begin
      var Ext := LowerCase(ExtractFileExt(Source)); var Kind := 'Images';
      if (Ext='.wav') or (Ext='.lab') then Kind := 'Audio'
      else if (Ext='.rigm') or (Ext='.psdchar') then Kind := 'Characters';
      Directory := TPath.Combine(AssetDirectory,Kind);
    end;
    ForceDirectories(Directory); Target := TPath.Combine(Directory,Name);
    if not FileExists(Target) then TFile.Copy(Source,Target,False);
    if THashSHA2.GetHashStringFromFile(Target)<>THashSHA2.GetHashStringFromFile(Source) then raise ERigm.Create('保存資産の検証に失敗しました。');
    Result := ExtractRelativePath(ExtractFilePath(TargetFile),Target);
  end;
begin
  Project.Validate; TargetFile := ExpandFileName(FileName); ForceDirectories(ExtractFilePath(TargetFile));
  AssetDirectory := ChangeFileExt(TargetFile,'.assets');
  if Organized then begin
    AssetDirectory := ExtractFileDir(TargetFile);
    for var Name in ['Images','Audio','Characters','Exports'] do ForceDirectories(TPath.Combine(AssetDirectory,Name));
  end;
  Saved := Project.Clone; O := nil;
  Temp := TargetFile+'.'+NewRigmId+'.tmp';
  try
    Saved.CharacterFile := Asset(Project.CharacterFile);
    Saved.ThemeBackground := Asset(Project.ThemeBackground);
    Saved.BgmFile := Asset(Project.BgmFile);
    for var I := 0 to Saved.Characters.Count-1 do begin
      Saved.Characters[I].FileName := Asset(Project.Characters[I].FileName);
      for var Pair in Saved.Characters[I].Expressions do begin
        var Preset := Pair.JsonValue as TJSONObject;
        if Preset.GetValue('image')<>nil then begin var Image := Asset(JS(Preset,'image')); Preset.RemovePair('image').Free; Preset.AddPair('image',Image); end;
      end;
      for var Pair in Saved.Characters[I].Motions do for var V in JA(TJSONObject(Pair.JsonValue),'frames') do begin
        var Frame := TJSONObject(V); var Image := Asset(JS(Frame,'image')); Frame.RemovePair('image').Free; Frame.AddPair('image',Image);
      end;
    end;
    for var I := 0 to Saved.Scenes.Count-1 do begin
      Saved.Scenes[I].Image := Asset(Project.Scenes[I].Image);
      if Saved.Scenes[I].Animation.GetValue('closingCard') is TJSONObject then begin var Card := JO(Saved.Scenes[I].Animation,'closingCard'); var Path := Asset(JS(Card,'image')); Card.RemovePair('image').Free; Card.AddPair('image',Path); end;
    end;
    for var V in Saved.EndCards do begin var Card := TJSONObject(V); var Path := Asset(JS(Card,'image')); Card.RemovePair('image').Free; Card.AddPair('image',Path); end;
    if (Saved.ScriptWizard<>nil) and (Saved.ScriptWizard.GetValue('closingData') is TJSONObject) then begin var D := JO(JO(Saved.ScriptWizard,'closingData'),'draft'); for var Key in ['representative','endImage','thumbnailImage'] do begin var Path := Asset(JS(D,Key)); D.RemovePair(Key).Free; D.AddPair(Key,Path); end; end;
    Saved.PreviewPath := Asset(Project.PreviewPath);
    Saved.VideoPath := ResolveMoviePath(Project.FileName,Project.VideoPath);
    for var I := 0 to Saved.Cues.Count-1 do begin
      Saved.Cues[I].WaveFile := Asset(Project.Cues[I].WaveFile); Saved.Cues[I].LabFile := Asset(Project.Cues[I].LabFile);
      Saved.Cues[I].Background := Asset(Project.Cues[I].Background);
      Saved.Cues[I].EffectWaveFile := Asset(Project.Cues[I].EffectWaveFile);
    end;
    // 同じ保存後モデルをメモリにも反映する。JSONの親キー順も再開前後で一致させる。
    if (Saved.ScriptWizard<>nil) and (Saved.ScriptWizard.GetValue('closingData') is TJSONObject) then
      begin var Closing := JO(Saved.ScriptWizard,'closingData').Clone as TJSONObject; Saved.ScriptWizard.RemovePair('closingData').Free; Saved.ScriptWizard.AddPair('closingData',Closing); end;
    O := Saved.Json;
    TFile.WriteAllText(Temp,O.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Temp),PChar(TargetFile),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    Project.CharacterFile := Saved.CharacterFile; Project.ThemeBackground := Saved.ThemeBackground; Project.BgmFile := Saved.BgmFile;
    for var I := 0 to Project.Characters.Count-1 do begin
      Project.Characters[I].FileName := Saved.Characters[I].FileName;
      Project.Characters[I].Expressions.Free; Project.Characters[I].Expressions := Saved.Characters[I].Expressions.Clone as TJSONObject;
      Project.Characters[I].Motions.Free; Project.Characters[I].Motions := Saved.Characters[I].Motions.Clone as TJSONObject;
    end;
    for var I := 0 to Project.Scenes.Count-1 do begin Project.Scenes[I].Image := Saved.Scenes[I].Image; Project.Scenes[I].Animation.Free; Project.Scenes[I].Animation := Saved.Scenes[I].Animation.Clone as TJSONObject; end;
    Project.EndCards.Free; Project.EndCards := Saved.EndCards.Clone as TJSONArray;
    if (Saved.ScriptWizard<>nil) and (Saved.ScriptWizard.GetValue('closingData') is TJSONObject) then begin Project.ScriptWizard.RemovePair('closingData').Free; Project.ScriptWizard.AddPair('closingData',JO(Saved.ScriptWizard,'closingData').Clone as TJSONObject); end;
    Project.PreviewPath := Saved.PreviewPath; Project.VideoPath := Saved.VideoPath;
    for var I := 0 to Project.Cues.Count-1 do begin
      Project.Cues[I].EffectWaveFile := Saved.Cues[I].EffectWaveFile;
      Project.Cues[I].WaveFile := Saved.Cues[I].WaveFile; Project.Cues[I].LabFile := Saved.Cues[I].LabFile; Project.Cues[I].Background := Saved.Cues[I].Background;
    end;
    Project.FileName := TargetFile; Project.Modified := False;
  finally O.Free; Saved.Free; if FileExists(Temp) then TFile.Delete(Temp); end;
end;
function LoadMovie(const FileName: string): TRigmMovieProject;
var O: TJSONObject;
begin
  if TFile.GetSize(FileName)>16*1024*1024 then raise ERigm.Create('動画プロジェクトが大きすぎます。');
  O := ParseObject(TFile.ReadAllText(FileName,TEncoding.UTF8));
  try Result := TRigmMovieProject.FromJson(O); Result.FileName := ExpandFileName(FileName); finally O.Free; end;
end;
function MovieSchema: TJSONObject;
begin
  Result := ParseObject('{"format":"RIGM-MOVIE","formatVersion":1,"textSyntax":"# scene title / speaker: text / plain text uses narrator",'+
    '"cueFields":{"id":"stable string","scene":"string","speaker":"speaker id","text":"spoken text <=2000 characters","subtitle":"display text","pause":"seconds 0..60 after audio",'+
    '"expression":"neutral|smile|serious|sad","motion":"idle|still|nod|emphasis","background":"local image file","parameters":"RIGM parameter id -> number","acting":"partial actingFields object"},'+
    '"actingFields":{"mouthMode":"auto|assets|deform","blinkMode":"auto|assets|deform","mouthGain":"0..2","lipLead":"-0.3..0.3 seconds; positive samples later audio","blinkStrength":"0..1","blinkInterval":"0.3..30 seconds","blinkDuration":"0.04..1 seconds, <= interval","blinkPhase":"0..30 seconds",'+
    '"headGain":"0..3","bodyGain":"0..3","imageAttention":"auto|off|head; image-direction head tilt only; no pupil gaze; auto uses scene.animation.explainImage or explicit image-explanation text","onset":"0..600 cue-local seconds","duration":"-1=cue end or 0..660 seconds","fadeIn":"0..60 seconds","fadeOut":"0..60 seconds","variants":"array of actual groupId/partId; direct children only; runtime visibility; no source edits"},'+
    '"speakerFields":{"id":"string","name":"display name","styleId":"from engine speakers catalog; -1 unselected","speed":"0.5..2","pitch":"-0.15..0.15","intonation":"0..2","volume":"0..2"},'+
    '"audioPolicy":"fingerprint invalidation; no synthetic fallback speech","video":"MJPEG + PCM16 mono AVI or optional H264/AAC MP4 via existing ffmpeg.exe; every spoken cue must be ready",'+
    '"coordinates":"character centered in frame; subtitles below; time in seconds"}');
  Result.AddPair('outputPresets',MovieOutputPresets);
  Result.AddPair('bgmFields',ParseObject('{"file":"managed PCM16 mono/stereo WAV; local path input copied and validated","volume":"independent gain 0..2","fadeOut":"0..3600 requested seconds, clamped to video duration; shorter BGM repeats"}'));
  Result.AddPair('imageAnimationFields',ParseObject('{"enter":"none|fade","exit":"none|fade","enterSeconds":"0..60, default 0.5","exitSeconds":"0..60, default 0.5","shortScenePolicy":"proportionally shorten to avoid overlap"}'));
end;
end.
