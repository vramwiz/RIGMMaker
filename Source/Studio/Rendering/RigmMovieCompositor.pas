// 複数キャラクター、場面画像、説明、字幕とチャートを合成する。保存済み素材の読込キャッシュも管理する。
unit RigmMovieCompositor;

interface
uses System.SysUtils, System.JSON, Vcl.Graphics, RigmModel, RigmMovieModel,
  RigmMovieComposition, RigmMovieAudio;
procedure CompositionPose(Project: TRigmMovieProject; Character: TRigmMovieCharacter;
  Document: TRigmDocument; Seconds: Double; Audio: TRigmPcm; Pose: TRigmPose);
function RenderComposition(Project: TRigmMovieProject; Seconds: Double; Audio: TRigmPcm): Vcl.Graphics.TBitmap;
function ExistingExpressions(Document: TRigmDocument): TJSONObject;
procedure ValidateCompositionMaterials(Project: TRigmMovieProject);

implementation
uses System.Classes, System.Types, System.Math, System.IOUtils, System.StrUtils,
  System.Generics.Collections, Winapi.Windows, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  ArtDocument, RigmJson, RigmStorage, RigmSample, RigmRenderer, RigmMovieRendering, RigmMovieActing, RigmMovieChart, RigmMoviePsdRendering;
type
  TActorEntry = class
    Stamp: string;
    Document: TRigmDocument;
    destructor Destroy; override;
  end;
var ActorCache: TObjectDictionary<string,TActorEntry>; CacheLock: TObject;
destructor TActorEntry.Destroy;
begin Document.Free; inherited; end;
function Actor(Project: TRigmMovieProject; const FileName: string): TRigmDocument;
var Entry: TActorEntry;
begin
  var Path := ResolveMoviePath(Project.FileName,FileName); var Stamp := Path;
  if FileName='@sample' then begin Path := '@sample'; Stamp := Path; end
  else begin
    if not FileExists(Path) then raise ERigm.Create('Character file is missing: '+Path);
    Stamp := Path+'|'+TFile.GetSize(Path).ToString+'|'+FloatToStr(TFile.GetLastWriteTimeUtc(Path),TFormatSettings.Invariant);
  end;
  if ActorCache.TryGetValue(Path,Entry) and (Entry.Stamp=Stamp) then Exit(Entry.Document);
  if ActorCache.Count>=16 then ActorCache.Clear;
  Entry := TActorEntry.Create;
  try
    Entry.Stamp := Stamp;
    if FileName='@sample' then begin Entry.Document := TRigmDocument.Create; PopulateRigmSample(Entry.Document); end
    else Entry.Document := LoadRigm(Path);
    Entry.Document.ValidateStructure; ActorCache.AddOrSetValue(Path,Entry); Result := Entry.Document;
  except Entry.Free; raise; end;
end;
function LegacyExpressions(Document: TRigmDocument): TJSONObject;
begin
  Result := TJSONObject.Create;
  if Document=nil then Exit;
  for var G in Document.Layers do if (G.Kind=alkGroup) and (G.Children.Count>1) and not Document.IsReferencePart(G.Id) then begin
    for var L in G.Children do begin
      var N := LowerCase(L.Name.Trim.TrimLeft(['*'])); var Emotion := '';
      if MatchText(N,['通常','normal','default','neutral']) then Emotion := 'neutral'
      else if MatchText(N,['笑顔','笑い','smile','happy']) then Emotion := 'happy'
      else if MatchText(N,['悲しい','悲しみ','sad']) then Emotion := 'sad'
      else if MatchText(N,['怒り','怒る','angry']) then Emotion := 'angry'
      else if MatchText(N,['真剣','serious']) then Emotion := 'serious'
      else if MatchText(N,['穏やか','gentle']) then Emotion := 'gentle';
      if (Emotion='') or Document.IsReferencePart(L.Id) then Continue;
      var Preset := Result.GetValue(Emotion) as TJSONObject;
      if Preset=nil then begin
        Preset := TJSONObject.Create; Preset.AddPair('variants',TJSONArray.Create);
        AddB(Preset,'blinkAnimate',True); AddB(Preset,'mouthAnimate',True); AddB(Preset,'rigSafe',True);
        Preset.AddPair('source','existing PSD differences'); Result.AddPair(Emotion,Preset);
      end;
      var GroupExists := False;
      for var V in JA(Preset,'variants') do if JS(TJSONObject(V),'groupId')=G.Id then GroupExists := True;
      if GroupExists then Continue;
      var V := TJSONObject.Create; V.AddPair('groupId',G.Id); V.AddPair('partId',L.Id); JA(Preset,'variants').AddElement(V);
      var Role := Document.Part(L.Id).Role;
      if (Role='eye') and (Emotion<>'neutral') then begin Preset.RemovePair('blinkAnimate').Free; AddB(Preset,'blinkAnimate',False); end;
      if (Role='mouth') and (Emotion<>'neutral') then begin Preset.RemovePair('mouthAnimate').Free; AddB(Preset,'mouthAnimate',False); end;
      if (Role='body') and (Emotion<>'neutral') then begin Preset.RemovePair('rigSafe').Free; AddB(Preset,'rigSafe',False); end;
    end;
  end;
end;
function ExistingExpressions(Document: TRigmDocument): TJSONObject;
  function Named(Group: TArtLayer; const Names: array of string): TArtLayer;
  begin
    Result := nil;
    for var Name in Names do for var L in Group.Children do
      if SameText(L.Name.Trim.TrimLeft(['*']),Name) and not Document.IsReferencePart(L.Id) then Exit(L);
  end;
  function GroupRole(Group: TArtLayer): string;
  begin
    Result := '';
    var Name := Group.Name.Trim.TrimLeft(['*']);
    if MatchText(Name,['記号','感情記号','emotion symbols']) then Exit('symbol');
    if MatchText(Name,['顔色','face color']) then Exit('color');
    var AllSame := True;
    for var L in Group.Children do begin
      var Part := Document.Part(L.Id);
      if (Part=nil) or (L.Kind<>alkImage) then Exit('');
      if Result='' then Result := Part.Role else AllSame := AllSame and (Result=Part.Role);
    end;
    if not AllSame or not MatchText(Result,['eye','mouth','brow','body']) then Result := '';
  end;
begin
  Result := LegacyExpressions(Document);
  if Document=nil then Exit;
  for var Emotion in MovieEmotionIds do begin
    var Preset := TJSONObject.Create; var Variants := TJSONArray.Create; Preset.AddPair('variants',Variants);
    var Evidence := Emotion='neutral'; var Blink := True; var Mouth := True; var RigSafe := True;
    for var G in Document.Layers do if (G.Kind=alkGroup) and (G.Children.Count>1) and not Document.IsReferencePart(G.Id) then begin
      var Role := GroupRole(G); if Role='' then Continue;
      var Selected := Named(G,['通常','normal','default','なし','none']); var Difference: TArtLayer := nil;
      if Role='brow' then begin
        if Emotion='happy' then Difference := Named(G,['喜','喜び','happy','smile'])
        else if Emotion='joy' then Difference := Named(G,['楽','楽しさ','joy'])
        else if Emotion='angry' then Difference := Named(G,['怒','怒り','angry'])
        else if Emotion='sad' then Difference := Named(G,['哀','哀しみ','悲しみ','sad'])
        else if MatchText(Emotion,['doubt','confused']) then Difference := Named(G,['困る','困惑','doubt'])
        else if Emotion='gentle' then Difference := Named(G,['楽','穏やか','gentle']);
      end else if Role='symbol' then begin
        if MatchText(Emotion,['happy','joy']) then Difference := Named(G,['喜び（キラキラ）','音符'])
        else if Emotion='angry' then Difference := Named(G,['怒り'])
        else if Emotion='sad' then Difference := Named(G,['哀しみ（涙）'])
        else if Emotion='surprised' then Difference := Named(G,['ビックリ','！'])
        else if Emotion='doubt' then Difference := Named(G,['？'])
        else if Emotion='confused' then Difference := Named(G,['！？','汗']);
      end else if Role='color' then begin
        if Emotion='happy' then Difference := Named(G,['照れ'])
        else if Emotion='angry' then Difference := Named(G,['赤い顔'])
        else if Emotion='sad' then Difference := Named(G,['落ち込み（三本線）'])
        else if MatchText(Emotion,['doubt','confused']) then Difference := Named(G,['汗'])
        else if Emotion='gentle' then Difference := Named(G,['照れ']);
      end else if Role='eye' then begin
        if Emotion='gentle' then Difference := Named(G,['やさしい目','穏やか','gentle']);
      end else if Role='body' then begin
        if Emotion='serious' then Difference := Named(G,['腕組み','serious']);
      end;
      if Difference<>nil then begin Selected := Difference; Evidence := True; end;
      if Selected=nil then Continue;
      var Choice := TJSONObject.Create; Choice.AddPair('groupId',G.Id); Choice.AddPair('partId',Selected.Id); Variants.AddElement(Choice);
      if (Role='eye') and not MatchText(Selected.Name.Trim.TrimLeft(['*']),['通常','normal','default','開き','open']) then Blink := False;
      if (Role='mouth') and not MatchText(Selected.Name.Trim.TrimLeft(['*']),['通常','normal','default','閉じ','closed','ん','開き','open','半開き','half','あ','い','う','え','お']) then Mouth := False;
      if (Role='body') and (Difference<>nil) then RigSafe := False;
    end;
    if Evidence and (Variants.Count>0) then begin
      AddB(Preset,'blinkAnimate',Blink); AddB(Preset,'mouthAnimate',Mouth); AddB(Preset,'rigSafe',RigSafe);
      Preset.AddPair('source','existing PSD differences; semantic combination of real layer names');
      Result.RemovePair(Emotion).Free; Result.AddPair(Emotion,Preset);
    end else Preset.Free;
  end;
end;
function SceneImageBounds(Project: TRigmMovieProject): TRectF;
begin
  Result := RectF(470,100,1450,650);
  if Project.Layout='l' then begin
    if Project.LDirection='left' then Result := RectF(800,120,1860,670)
    else Result := RectF(60,120,1120,670);
  end;
end;
procedure ApplyImageHeadAttention(Project: TRigmMovieProject; Character: TRigmMovieCharacter;
  Cue: TRigmMovieCue; Acting: TRigmMovieActing; Seconds,Local: Double; Pose: TRigmPose);
begin
  if (Cue=nil) or (Cue.SpeakerId<>Character.SpeakerId) or (Acting.ImageAttention='off') then Exit;
  var Start,SceneLocal: Double; var Scene := Project.SceneAt(Seconds,Start,SceneLocal);
  var HasImage := Cue.Background<>'';
  if Scene<>nil then HasImage := HasImage or (Scene.Image<>'');
  if not HasImage then Exit;
  var Explaining := Acting.ImageAttention='head';
  if Acting.ImageAttention='auto' then begin
    if Scene<>nil then Explaining := JB(Scene.Animation,'explainImage');
    for var Phrase in ['この画像','この絵','この写真','こちらの絵','画像をご覧','絵をご覧','右の絵','左の絵'] do
      Explaining := Explaining or ContainsText(Cue.Text,Phrase);
  end;
  if not Explaining then Exit;
  var Bounds := SceneImageBounds(Project);
  var Direction := Sign((Bounds.Left+Bounds.Right)/2-(Character.X+Character.Width/2));
  var InValue := EnsureRange((Local-0.6)/0.5,0.0,1.0);
  var OutValue := EnsureRange((Min(4.2,Project.CueDuration(Cue))-Local)/0.8,0.0,1.0);
  var Gain := InValue*InValue*(3-2*InValue)*OutValue*OutValue*(3-2*OutValue)*
    Acting.Gain(Local,Project.CueDuration(Cue))*Min(1.0,Acting.HeadGain);
  // Whole eye sprites cannot safely provide pupil gaze. This is explicitly
  // a small head tilt towards the rendered image rectangle, not pupil motion.
  Pose.Values.AddOrSetValue('headAngle',EnsureRange(Pose.Value('headAngle')+Direction*2.0*Gain,-30.0,30.0));
end;
procedure CompositionPose(Project: TRigmMovieProject; Character: TRigmMovieCharacter;
  Document: TRigmDocument; Seconds: Double; Audio: TRigmPcm; Pose: TRigmPose);
var Local,Start: Double;
begin
  var MotionImage: string;
  if Character.MotionFrame(Seconds,MotionImage) then begin
    Pose.Reset; Pose.Values.AddOrSetValue('mouthOpen',0); Pose.Values.AddOrSetValue('eyeOpen',1);
    Pose.Values.AddOrSetValue('headAngle',0); Pose.Values.AddOrSetValue('bodyAngle',0); Exit;
  end;
  var C := Project.CueAt(Seconds,Local,Start);
  if (C<>nil) and (C.SpeakerId=Character.SpeakerId) then MoviePose(Project,Document,Seconds,Audio,Pose)
  else begin
    Pose.Reset; Pose.Values.AddOrSetValue('mouthOpen',0);
    var Eyes := MovieBlinkOpen(Seconds,4.0,0.16,0.73,1,1,Project.Fps);
    Pose.Values.AddOrSetValue('eyeOpen',Eyes);
  end;
  var Preset: TJSONObject := nil;
  if (C<>nil) and (C.SpeakerId=Character.SpeakerId) then Preset := Character.Expressions.GetValue(C.Emotion) as TJSONObject;
  if Preset=nil then Preset := Character.Expressions.GetValue('neutral') as TJSONObject;
  var Acting := TRigmMovieActing.Create;
  try
    if (C<>nil) and (C.SpeakerId=Character.SpeakerId) then begin
      var ActingJson := C.Acting.Json;
      try Acting.Free; Acting := nil; Acting := TRigmMovieActing.FromJson(ActingJson); finally ActingJson.Free; end;
    end;
    var BlinkEnabled := True; var MouthEnabled := True; var RigSafe := Character.RigSafe;
    if Preset<>nil then begin
      if Preset.GetValue('variants')<>nil then begin
        var Merged := JA(Preset,'variants').Clone as TJSONArray;
        // Explicit cue choices take precedence over the emotion's defaults.
        for var V in Acting.Variants do begin
          var GroupId := JS(TJSONObject(V),'groupId');
          for var I := Merged.Count-1 downto 0 do
            if JS(TJSONObject(Merged[I]),'groupId')=GroupId then Merged.Remove(I).Free;
          Merged.AddElement(V.Clone as TJSONObject);
        end;
        Acting.Variants.Free; Acting.Variants := Merged;
      end;
      BlinkEnabled := JB(Preset,'blinkAnimate',True); MouthEnabled := JB(Preset,'mouthAnimate',True);
      RigSafe := RigSafe and JB(Preset,'rigSafe',True);
    end;
    if (C<>nil) and (C.SpeakerId=Character.SpeakerId) then for var V in C.Acting.Variants do begin
      var Part := Document.Art.FindLayer(JS(TJSONObject(V),'partId')); if Part=nil then Continue;
      var Role := Document.Part(Part.Id).Role; var Name := Part.Name.Trim.TrimLeft(['*']);
      if Role='eye' then BlinkEnabled := MatchText(Name,['通常','normal','default','開き','open'])
      else if Role='mouth' then MouthEnabled := MatchText(Name,['通常','normal','default','閉じ','closed','ん','開き','open','半開き','half','あ','い','う','え','お'])
      else if (Role='body') and not MatchText(Name,['通常','normal','default']) then RigSafe := False;
    end;
    // Difference selection precedes independent feature animation and small rig motion.
    Pose.PartVisibility.Clear; Pose.PartFeatureAssets.Clear; Acting.ApplyVariants(Document,Pose);
    if not BlinkEnabled then Pose.Values.AddOrSetValue('eyeOpen',1);
    if not MouthEnabled then begin
      var Mouth := 0.0;
      if (C<>nil) and (C.SpeakerId=Character.SpeakerId) and (Local<C.AudioSeconds) then Mouth := 0.45;
      Pose.Values.AddOrSetValue('mouthOpen',Mouth);
    end;
    Acting.ApplyFeatureAssets(Document,Pose,Pose.Value('mouthOpen'),Pose.Value('eyeOpen'),MouthEnabled,BlinkEnabled);
    if not RigSafe then begin Pose.Values.AddOrSetValue('headAngle',0); Pose.Values.AddOrSetValue('bodyAngle',0); end
    else ApplyImageHeadAttention(Project,Character,C,Acting,Seconds,Local,Pose);
  finally Acting.Free; end;
end;
procedure ValidateCompositionMaterials(Project: TRigmMovieProject);
begin
  TMonitor.Enter(CacheLock);
  try
    for var C in Project.Characters do if C.Visible then begin
      if C.RenderFormat='psd' then begin ValidatePsdMovieCharacter(Project,C); Continue; end;
      var D := Actor(Project,C.FileName); var P := TRigmPose.Create;
      try
        CompositionPose(Project,C,D,0,nil,P);
        for var Pair in C.Expressions do begin
          var Preset := Pair.JsonValue as TJSONObject; var A := TRigmMovieActing.Create;
          try
            if Preset.GetValue('variants')<>nil then begin A.Variants.Free; A.Variants := JA(Preset,'variants').Clone as TJSONArray; end;
            P.Reset; A.ApplyVariants(D,P);
            if (JS(Preset,'image')<>'') and not FileExists(ResolveMoviePath(Project.FileName,JS(Preset,'image'))) then raise ERigm.Create('Expression image is missing');
          finally A.Free; end;
        end;
        for var Pair in C.Motions do for var V in JA(TJSONObject(Pair.JsonValue),'frames') do
          if not FileExists(ResolveMoviePath(Project.FileName,JS(TJSONObject(V),'image'))) then raise ERigm.Create('Motion frame image is missing');
      finally P.Free; end;
    end;
    for var S in Project.Scenes do if (S.Image<>'') and not FileExists(ResolveMoviePath(Project.FileName,S.Image)) then
      raise ERigm.Create('Scene image is missing: '+S.Image);
    if (Project.Layout='theme') and (Project.ThemeBackground<>'') and not FileExists(ResolveMoviePath(Project.FileName,Project.ThemeBackground)) then
      raise ERigm.Create('Theme image is missing: '+Project.ThemeBackground);
  finally TMonitor.Exit(CacheLock); end;
end;
function RenderComposition(Project: TRigmMovieProject; Seconds: Double; Audio: TRigmPcm): Vcl.Graphics.TBitmap;
var Info: TBitmapInfo; DC: HDC; Dib,Previous: HGDIOBJ; Bits: Pointer; Canvas: TCanvas;
  procedure Image(const Path: string; R: TRect; Cover: Boolean);
  begin
    if Path='' then Exit;
    var Picture := TPicture.Create;
    try
      Picture.LoadFromFile(ResolveMoviePath(Project.FileName,Path));
      if (Picture.Width<1) or (Picture.Height<1) then raise ERigm.Create('Empty image: '+Path);
      var K := Min(R.Width/Picture.Width,R.Height/Picture.Height);
      if Cover then K := Max(R.Width/Picture.Width,R.Height/Picture.Height);
      var W := Round(Picture.Width*K); var H := Round(Picture.Height*K);
      Canvas.StretchDraw(Rect(R.Left+(R.Width-W) div 2,R.Top+(R.Height-H) div 2,R.Left+(R.Width+W) div 2,R.Top+(R.Height+H) div 2),Picture.Graphic);
    finally Picture.Free; end;
  end;
  function BaseRect(L,T,R,B: Double): TRect;
  begin Result := Rect(Round(L*Project.Width/1920),Round(T*Project.Height/1080),Round(R*Project.Width/1920),Round(B*Project.Height/1080)); end;
  procedure Text(const Value: string; R: TRect; Size: Integer; Flags: Cardinal);
  begin
    Canvas.Font.Name := 'Yu Gothic UI'; Canvas.Font.Height := -Max(12,Round(Size*Project.Height/1080));
    Canvas.Font.Color := clWhite; Canvas.Brush.Style := bsClear;
    // Select the VCL font into the DC before calling DrawText directly.
    Canvas.TextHeight('M');
    SetTextColor(DC,RGB(255,255,255)); SetBkMode(DC,TRANSPARENT);
    if Value<>'' then DrawText(DC,PChar(Value),Length(Value),R,Flags or DT_NOPREFIX);
  end;
begin
  Result := Vcl.Graphics.TBitmap.Create; Canvas := nil; DC := 0; Dib := 0; Previous := 0;
  TMonitor.Enter(CacheLock);
  try
    try
      Result.PixelFormat := pf32bit; Result.SetSize(Project.Width,Project.Height);
      DC := CreateCompatibleDC(0); Info := Default(TBitmapInfo); Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
      Info.bmiHeader.biWidth := Project.Width; Info.bmiHeader.biHeight := -Project.Height;
      Info.bmiHeader.biPlanes := 1; Info.bmiHeader.biBitCount := 32;
      Dib := CreateDIBSection(DC,Info,DIB_RGB_COLORS,Bits,0,0);
      if (DC=0) or (Dib=0) or (Bits=nil) then RaiseLastOSError;
      Previous := SelectObject(DC,Dib); Canvas := TCanvas.Create; Canvas.Handle := DC;
      Canvas.Brush.Color := TColor(Project.BackgroundColor); Canvas.FillRect(Rect(0,0,Project.Width,Project.Height));
      if Project.Layout='theme' then Image(Project.ThemeBackground,Rect(0,0,Project.Width,Project.Height),True);
      var SceneStart,SceneLocal,Local,Start: Double; var S := Project.SceneAt(Seconds,SceneStart,SceneLocal);
      var C := Project.CueAt(Seconds,Local,Start); var ImageBounds := SceneImageBounds(Project);
      var ImageRect := BaseRect(ImageBounds.Left,ImageBounds.Top,ImageBounds.Right,ImageBounds.Bottom);
      var DescriptionRect := BaseRect(500,670,1420,800);
      if Project.Layout='l' then begin
        if Project.LDirection='left' then DescriptionRect := BaseRect(830,690,1830,820)
        else DescriptionRect := BaseRect(90,690,1090,820);
      end;
      if S<>nil then begin
        var SceneImage := S.Image;
        if (SceneImage='') and (C<>nil) then SceneImage := C.Background;
        if MovieChartEnabled(S.Chart) then DrawMovieChart(Canvas,S.Chart,ImageRect)
        else Image(SceneImage,ImageRect,False);
        if S.Description<>'' then begin
          Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $302820; Canvas.FillRect(DescriptionRect); InflateRect(DescriptionRect,-12,-8);
          Text(S.Description,DescriptionRect,32,DT_LEFT or DT_WORDBREAK);
        end;
        Text(S.Title,BaseRect(55,20,1850,90),36,DT_LEFT or DT_WORDBREAK);
      end;
      GdiFlush;
      for var Character in Project.Characters do if Character.Visible then begin
        var Box := BaseRect(Character.X,Character.Y,Character.X+Character.Width,Character.Y+Character.Height);
        if Character.RenderFormat='psd' then begin
          var Pixels := RenderPsdMovieCharacter(Project,Character,Seconds,Audio,Max(1,Box.Width),Max(1,Box.Height));
          for var Y := 0 to Box.Height-1 do if (Y+Box.Top>=0) and (Y+Box.Top<Project.Height) then
            for var X := 0 to Box.Width-1 do if (X+Box.Left>=0) and (X+Box.Left<Project.Width) then begin
              var P := (Y*Box.Width+X)*4; var Q := ((Y+Box.Top)*Project.Width+X+Box.Left)*4; var A := Pixels[P+3];
              for var Channel := 0 to 2 do PByte(Bits)[Q+2-Channel] := (Pixels[P+Channel]*A+PByte(Bits)[Q+2-Channel]*(255-A)+127) div 255;
              PByte(Bits)[Q+3] := 255;
            end;
          Continue;
        end;
        var MotionImage: string;
        if Character.MotionFrame(Seconds,MotionImage) then begin
          var MotionBox := Box;
          var Definition := Character.Motions.GetValue(Character.ActiveMotion) as TJSONObject;
          if (JN(Definition,'contentWidth')>0) and (JN(Definition,'contentHeight')>0) and
            (JN(Definition,'canvasWidth')>0) and (JN(Definition,'canvasHeight')>0) then begin
            var K := Min(Box.Width/JN(Definition,'contentWidth'),Box.Height/JN(Definition,'contentHeight'));
            var L := Box.Left+(Box.Width-Round(JN(Definition,'contentWidth')*K)) div 2+
              Round(JN(Definition,'contentWidth')*K/2)-Round(JN(Definition,'anchorX')*K);
            var T := Box.Bottom-Round(JN(Definition,'anchorY')*K);
            MotionBox := Rect(L,T,L+Round(JN(Definition,'canvasWidth')*K),T+Round(JN(Definition,'canvasHeight')*K));
          end else if StartsText('whole-character transforms rendered from existing RIGM',JS(Definition,'provenance')) then begin
            // The stored canvas includes room for rotation. Keep its original
            // content at the normal actor scale and baseline rather than fitting
            // the transparent margin inside the actor's rectangle.
            var Source := Actor(Project,Character.FileName);
            var K := Min(1.0,700/Max(Source.Art.Width,Source.Art.Height));
            var W := Max(1,Round(Source.Art.Width*K)); var H := Max(1,Round(Source.Art.Height*K));
            var Margin := Max(40,Max(W,H) div 8); K := Min(Box.Width/W,Box.Height/H);
            var L := Box.Left+(Box.Width-Round(W*K)) div 2-Round(Margin*K);
            MotionBox := Rect(L,Box.Bottom-Round((H+Margin)*K),L+Round((W+Margin*2)*K),Box.Bottom+Round(Margin*K));
          end;
          Image(MotionImage,MotionBox,False); GdiFlush; Continue;
        end;
        var Preset: TJSONObject := nil;
        if (C<>nil) and (C.SpeakerId=Character.SpeakerId) then Preset := Character.Expressions.GetValue(C.Emotion) as TJSONObject;
        if Preset=nil then Preset := Character.Expressions.GetValue('neutral') as TJSONObject;
        if (Preset<>nil) and (JS(Preset,'image')<>'') then begin
          // A generated complete pose is a separate sprite, without reusing the original rig.
          Image(JS(Preset,'image'),Box,False); GdiFlush; Continue;
        end;
        var D := Actor(Project,Character.FileName); var Pose := TRigmPose.Create;
        try
          CompositionPose(Project,Character,D,Seconds,Audio,Pose);
          var W,H: Integer; var Pixels := RenderRigm(D,Pose,Round(Character.Height*Project.Height/1080),W,H);
          var K := Min(Box.Width/Max(1,W),Box.Height/Max(1,H)); var TW := Max(1,Round(W*K)); var TH := Max(1,Round(H*K));
          var L := Box.Left+(Box.Width-TW) div 2; var T := Box.Bottom-TH;
          for var Y := 0 to TH-1 do if (Y+T>=0) and (Y+T<Project.Height) then
            for var X := 0 to TW-1 do if (X+L>=0) and (X+L<Project.Width) then begin
              var P := (Min(H-1,Y*H div TH)*W+Min(W-1,X*W div TW))*4;
              var Q := ((Y+T)*Project.Width+X+L)*4; var A := Pixels[P+3];
              for var Channel := 0 to 2 do PByte(Bits)[Q+2-Channel] := (Pixels[P+Channel]*A+PByte(Bits)[Q+2-Channel]*(255-A)+127) div 255;
              PByte(Bits)[Q+3] := 255;
            end;
        finally Pose.Free; end;
      end;
      if C<>nil then begin
        var R := BaseRect(40,855,1880,1045); Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $251E18; Canvas.FillRect(R);
        InflateRect(R,-Round(30*Project.Width/1920),-Round(14*Project.Height/1080));
        Canvas.Font.Name := 'Yu Gothic UI'; Canvas.Font.Height := -Max(16,Round(44*Project.Height/1080));
        var Pages: Integer; var Subtitle := MovieSubtitlePage(C.Subtitle,Canvas,R.Width,Max(1,R.Height div Max(1,Canvas.TextHeight('国'))),Local/Max(0.001,Project.CueDuration(C)),Pages);
        Text(Subtitle,R,44,DT_CENTER);
      end;
      GdiFlush;
      for var Y := 0 to Project.Height-1 do Move(PByte(Bits)[Y*Project.Width*4],Result.ScanLine[Y]^,Project.Width*4);
    except Result.Free; raise; end;
  finally
    if Canvas<>nil then begin Canvas.Handle := 0; Canvas.Free; end;
    if Previous<>0 then SelectObject(DC,Previous); if Dib<>0 then DeleteObject(Dib); if DC<>0 then DeleteDC(DC);
    TMonitor.Exit(CacheLock);
  end;
end;
initialization
  CacheLock := TObject.Create; ActorCache := TObjectDictionary<string,TActorEntry>.Create([doOwnsValues]);
finalization
  ActorCache.Free; CacheLock.Free;
end.
