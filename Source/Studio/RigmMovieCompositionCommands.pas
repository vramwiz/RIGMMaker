unit RigmMovieCompositionCommands;

interface
uses System.JSON, RigmMovieModel;
function IsCompositionCommand(const Name: string): Boolean;
procedure ApplyCompositionCommand(Project: TRigmMovieProject; const Name: string; Args: TJSONObject; AvailableStyles: TJSONArray=nil);
function CompositionRequests(Project: TRigmMovieProject): TJSONObject;

implementation
uses System.SysUtils, System.IOUtils, System.Math, System.StrUtils,
  RigmJson, RigmModel, RigmMovieComposition, RigmMovieCompositor, RigmStorage, RigmSample, RigmMovieMotionLibrary;
function IsCompositionCommand(const Name: string): Boolean;
begin
  Result := MatchText(Name,['composition-enable','add-character','update-character','delete-character','add-scene','update-scene',
    'delete-scene','move-scene','resize-scene','register-expression','analyze-script','update-subtitle','update-dialogue',
    'register-motion','select-motion','stop-motion']);
end;
procedure ApplyCompositionCommand(Project: TRigmMovieProject; const Name: string; Args: TJSONObject; AvailableStyles: TJSONArray);
  procedure StringValue(var Value: string; const Key: string);
  begin if Args.GetValue(Key)<>nil then Value := JS(Args,Key); end;
  procedure NumberValue(var Value: Double; const Key: string);
  begin if Args.GetValue(Key)<>nil then Value := JN(Args,Key); end;
  function RequiredScene: TRigmMovieScene;
  begin Result := Project.Scene(JS(Args,'id')); if Result=nil then raise ERigm.Create('Scene identifier not found'); end;
  function RequiredCharacter: TRigmMovieCharacter;
  begin Result := Project.Character(JS(Args,'id')); if Result=nil then raise ERigm.Create('Character identifier not found'); end;
  procedure SelectEmotionVoice(C: TRigmMovieCue);
  begin
    if AvailableStyles=nil then Exit;
    var Speaker := Project.Speaker(C.SpeakerId); var UUID := '';
    for var V in AvailableStyles do if JI(TJSONObject(V),'styleId')=Speaker.StyleId then UUID := JS(TJSONObject(V),'uuid');
    if UUID='' then Exit;
    var Selected := -1;
    for var V in AvailableStyles do begin
      var O := TJSONObject(V); if JS(O,'uuid')<>UUID then Continue;
      var Style := JS(O,'style'); var Matches := False;
      if C.Emotion='happy' then Matches := MatchText(Style,['喜び','嬉しい','明るい','ハッピー'])
      else if C.Emotion='sad' then Matches := MatchText(Style,['悲しみ','悲しい','しょんぼり'])
      else if C.Emotion='serious' then Matches := MatchText(Style,['真面目','シリアス'])
      else if C.Emotion='angry' then Matches := MatchText(Style,['怒り','怒る','ぷんぷん'])
      else if C.Emotion='gentle' then Matches := MatchText(Style,['ささやき','囁き','やさしい','優しい']);
      if Matches then begin Selected := JI(O,'styleId',-1); Break; end;
    end;
    C.VoiceStyleId := Selected;
  end;
begin
  if Name='composition-enable' then begin Project.EnableComposition; Exit; end;
  if MatchText(Name,['update-subtitle','update-dialogue']) then begin
    var C := Project.Cue(JS(Args,'id')); if C=nil then raise ERigm.Create('Cue identifier not found');
    if Name='update-subtitle' then C.Subtitle := JS(Args,'subtitle') else C.Text := JS(Args,'text');
    Exit; // Speech and display text never overwrite each other.
  end;
  if Name='add-character' then begin
    var C := TRigmMovieCharacter.FromJson(JO(Args,'character')); Project.Characters.Add(C);
    var Motions := LoadCharacterMotions(ResolveMoviePath(Project.FileName,C.FileName));
    try for var Pair in Motions do if C.Motions.GetValue(Pair.JsonString.Value)=nil then C.Motions.AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue); finally Motions.Free; end;
    if Project.Speaker(C.SpeakerId)=nil then begin var S := TRigmMovieSpeaker.Create; S.Id := C.SpeakerId; S.Name := C.Name; Project.Speakers.Add(S); end;
    Exit;
  end;
  if Name='delete-character' then begin Project.Characters.Remove(RequiredCharacter); Exit; end;
  if Name='update-character' then begin
    var C := RequiredCharacter;
    StringValue(C.Name,'name'); StringValue(C.FileName,'file'); StringValue(C.SpeakerId,'speaker'); StringValue(C.InitialPosition,'initialPosition');
    NumberValue(C.X,'x'); NumberValue(C.Y,'y'); NumberValue(C.Width,'width'); NumberValue(C.Height,'height');
    if Args.GetValue('visible')<>nil then C.Visible := JB(Args,'visible');
    if Args.GetValue('rigSafe')<>nil then C.RigSafe := JB(Args,'rigSafe');
    if Args.GetValue('allowGeneratedExpressions')<>nil then C.AllowGeneratedExpressions := JB(Args,'allowGeneratedExpressions');
    if Args.GetValue('styleId')<>nil then begin
      var S := Project.Speaker(C.SpeakerId); if S=nil then raise ERigm.Create('Character speaker is missing');
      S.StyleId := JI(Args,'styleId',-1);
    end;
    C.Validate; Exit;
  end;
  if Name='register-expression' then begin
    var C := RequiredCharacter; var Preset := JO(Args,'preset'); var Emotion := JS(Args,'emotion');
    if not MatchText(Emotion,['neutral','happy','sad','serious','angry','gentle']) then raise ERigm.Create('Unknown expression emotion');
    if JB(Preset,'generated') and not C.AllowGeneratedExpressions then raise ERigm.Create('Original PSD modification and generated character expressions are not enabled');
    var Image := JS(Preset,'image');
    if (Image<>'') and not FileExists(ResolveMoviePath(Project.FileName,Image)) then raise ERigm.Create('Expression image does not exist');
    C.Expressions.RemovePair(Emotion).Free; C.Expressions.AddPair(Emotion,Preset.Clone as TJSONObject); C.Validate; Exit;
  end;
  if Name='register-motion' then begin
    var C := RequiredCharacter; var Motion := JO(Args,'motion'); var Key := JS(Args,'name');
    for var V in JA(Motion,'frames') do
      if not FileExists(ResolveMoviePath(Project.FileName,JS(TJSONObject(V),'image'))) then raise ERigm.Create('Motion frame image does not exist');
    C.Motions.RemovePair(Key).Free; C.Motions.AddPair(Key,Motion.Clone as TJSONObject); C.Validate; Exit;
  end;
  if MatchText(Name,['select-motion','stop-motion']) then begin
    var C := RequiredCharacter;
    if Name='stop-motion' then C.ActiveMotion := '' else begin
      C.ActiveMotion := JS(Args,'name'); C.MotionStart := JN(Args,'start'); C.MotionDuration := JN(Args,'duration',-1);
    end;
    C.Validate; Exit;
  end;
  if Name='add-scene' then begin
    var S := TRigmMovieScene.FromJson(JO(Args,'scene')); Project.Scenes.Insert(EnsureRange(JI(Args,'index',Project.Scenes.Count),0,Project.Scenes.Count),S);
    var C := TRigmMovieCue.Create; C.Scene := S.Id; C.SpeakerId := Project.Speakers[0].Id; C.Text := JS(Args,'text'); C.Subtitle := JS(Args,'subtitle',C.Text);
    Project.Cues.Add(C); Exit;
  end;
  if Name='update-scene' then begin
    if Args.GetValue('animation')<>nil then begin
      var Animation := JO(Args,'animation').Clone as TJSONObject;
      var Scene := RequiredScene; Scene.Animation.Free; Scene.Animation := Animation;
    end;
    var S := RequiredScene; StringValue(S.Title,'title'); StringValue(S.Image,'image'); StringValue(S.Description,'description'); StringValue(S.ImagePrompt,'imagePrompt');
    if Args.GetValue('duration')<>nil then begin
      var Natural := Project.SceneDuration(S)-S.Padding;
      if JN(Args,'duration')<Natural then raise ERigm.Create('Scene duration cannot truncate stored speech');
      S.Padding := JN(Args,'duration')-Natural;
    end;
    NumberValue(S.Padding,'padding'); S.Validate; Exit;
  end;
  if Name='resize-scene' then begin
    var S := RequiredScene; var Spoken := Project.SceneDuration(S)-S.Padding; var Duration := JN(Args,'duration');
    if Duration<Spoken then raise ERigm.CreateFmt('Scene contains %.3f seconds of speech/subtitles; shorten pauses or edit dialogue before trimming further',[Spoken]);
    S.Padding := Duration-Spoken; S.Validate; Exit;
  end;
  if Name='delete-scene' then begin
    var S := RequiredScene;
    for var I := Project.Cues.Count-1 downto 0 do if Project.Cues[I].Scene=S.Id then Project.Cues.Delete(I);
    Project.Scenes.Remove(S); Exit;
  end;
  if Name='move-scene' then begin
    var S := Project.Scenes.Extract(RequiredScene); Project.Scenes.Insert(EnsureRange(JI(Args,'index'),0,Project.Scenes.Count),S); Exit;
  end;
  if Name='analyze-script' then begin
    for var Character in Project.Characters do begin
      var D: TRigmDocument := nil;
      try
        if Character.FileName='@sample' then begin D := TRigmDocument.Create; PopulateRigmSample(D); end
        else D := LoadRigm(ResolveMoviePath(Project.FileName,Character.FileName));
        var Presets := ExistingExpressions(D);
        var Motions := LoadCharacterMotions(ResolveMoviePath(Project.FileName,Character.FileName));
        try for var Pair in Motions do if Character.Motions.GetValue(Pair.JsonString.Value)=nil then Character.Motions.AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue); finally Motions.Free; end;
        try for var P in Presets do if Character.Expressions.GetValue(P.JsonString.Value)=nil then
          Character.Expressions.AddPair(P.JsonString.Value,P.JsonValue.Clone as TJSONValue);
        finally Presets.Free; end;
      finally D.Free; end;
    end;
    for var C in Project.Cues do begin
      if (JS(Args,'id')<>'') and (JS(Args,'id')<>C.Id) then Continue;
      var Text := C.Text;
      C.Emotion := 'neutral';
      if ContainsText(Text,'ありがとう') or ContainsText(Text,'おすすめ') or ContainsText(Text,'良い') or ContainsText(Text,'嬉し') then C.Emotion := 'happy';
      if ContainsText(Text,'気になる') or ContainsText(Text,'不安') or ContainsText(Text,'残念') then C.Emotion := 'serious';
      if ContainsText(Text,'悲し') or ContainsText(Text,'寂し') then C.Emotion := 'sad';
      if ContainsText(Text,'静か') or ContainsText(Text,'心温ま') then C.Emotion := 'gentle';
      if ContainsText(Text,'怒り') or ContainsText(Text,'怒っ') then C.Emotion := 'angry';
      SelectEmotionVoice(C); // Select only styles in the connected engine's real catalog.
    end;
    Exit;
  end;
  raise ERigm.Create('Unsupported composition operation');
end;
function CompositionRequests(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  var Images := TJSONArray.Create; Result.AddPair('sceneImages',Images);
  for var S in Project.Scenes do if S.Image='' then begin
    var O := S.Json; AddN(O,'width',1280); AddN(O,'height',720);
    O.AddPair('registerCommand','movie-update-scene'); Images.AddElement(O);
  end;
  var Expressions := TJSONArray.Create; Result.AddPair('expressions',Expressions);
  for var C in Project.Cues do for var Character in Project.Characters do if (Character.SpeakerId=C.SpeakerId) and
    (Character.Expressions.GetValue(C.Emotion)=nil) and (C.Emotion<>'neutral') then begin
    var O := TJSONObject.Create; O.AddPair('characterId',Character.Id); O.AddPair('emotion',C.Emotion);
    AddB(O,'generationAllowed',Character.AllowGeneratedExpressions); O.AddPair('sourcePolicy','existing PSD differences first; never modify original PSD');
    O.AddPair('registerCommand','movie-register-expression'); Expressions.AddElement(O);
  end;
end;
end.
