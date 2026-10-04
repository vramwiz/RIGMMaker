program RigmMediaVisualTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Math, System.StrUtils, System.Generics.Collections, Vcl.Graphics,
  Vcl.Imaging.pngimage, RigmModel, RigmStorage, RigmRenderer, RigmJson,
  RigmMovieModel, RigmMovieAudio, RigmMovieRendering, RigmMovieCompositor, ArtDocument;
var Root,Source: string; Checks,Frames,Motions,VideoFrames: TJSONArray;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS: '+Name); Flush(Output); end;
procedure SaveRGBA(const Path: string; const Pixels: TBytes; W,H: Integer);
begin
  var Png := TPngImage.CreateBlank(COLOR_RGBALPHA,8,W,H);
  try
    for var Y := 0 to H-1 do begin
      var Row := PByte(Png.Scanline[Y]); var Alpha := PByte(Png.AlphaScanline[Y]);
      for var X := 0 to W-1 do begin var Q := (Y*W+X)*4;
        for var C := 0 to 2 do Row[X*3+2-C] := Pixels[Q+C]; Alpha[X] := Pixels[Q+3];
      end;
    end;
    Png.SaveToFile(Path);
  finally Png.Free; end;
end;
function SaveBitmap(B: TBitmap; const Name: string): string;
begin
  Result := TPath.Combine(Root,Name+'.png'); var Png := TPngImage.Create;
  try Png.Assign(B); Png.SaveToFile(Result); finally Png.Free; end;
end;
procedure Test;
begin
  var Before := THashSHA2.GetHashStringFromFile(Source); var P := LoadMovie(Source);
  var D := LoadRigm(ResolveMoviePath(Source,P.Characters[0].FileName)); var Audio := MixMovieAudio(P); var Pose := TRigmPose.Create;
  var Neutral := P.Clone;
  try
    Neutral.Characters[0].ActiveMotion := ''; Neutral.Characters[0].Expressions.Free; Neutral.Characters[0].Expressions := TJSONObject.Create;
    for var C in Neutral.Cues do begin C.Motion := 'still'; C.Acting.HeadGain := 0; C.Acting.BodyGain := 0; C.Acting.BlinkStrength := 0; C.Emotion := 'neutral'; end;
    var Seen := TStringList.Create; var Lines := TStringList.Create; var PixelsByPhone := TDictionary<string,TBytes>.Create;
    try
      var Cue := Neutral.Cues[0]; Lines.Text := TFile.ReadAllText(ResolveMoviePath(Source,Cue.LabFile),TEncoding.UTF8);
      for var Line in Lines do begin
        var Fields := Line.Trim.TrimLeft([#$FEFF]).Split([' ',#9],TStringSplitOptions.ExcludeEmpty); if Length(Fields)<>3 then Continue;
        var Phone := LowerCase(Fields[2]); if not MatchText(Phone,['a','i','u','e','o']) or (Seen.IndexOf(Phone)>=0) then Continue;
        var Time := (StrToInt64(Fields[0])+StrToInt64(Fields[1]))/20000000.0;
        MoviePose(Neutral,D,Time,Audio,Pose); Pose.Values.AddOrSetValue('headAngle',0); Pose.Values.AddOrSetValue('bodyAngle',0); Pose.Values.AddOrSetValue('eyeOpen',1);
        var W,H: Integer; var Pixels := RenderRigm(D,Pose,1000,W,H); PixelsByPhone.Add(Phone,Pixels);
        var Path := TPath.Combine(Root,'mouth-'+Phone+'.png'); SaveRGBA(Path,Pixels,W,H);
        var O := TJSONObject.Create; O.AddPair('phoneme',Phone); AddN(O,'time',Time); O.AddPair('path',Path); O.AddPair('sha256',THashSHA2.GetHashStringFromFile(Path)); Frames.AddElement(O);
        var B := RenderComposition(Neutral,Time,Audio); try SaveBitmap(B,'composition-mouth-'+Phone); finally B.Free; end;
        Seen.Add(Phone); if Seen.Count=5 then Break;
      end;
      Check(Seen.Count=5,'actual LAB supplies rendered images for all five vowel mouth shapes');
      for var A in PixelsByPhone do for var B in PixelsByPhone do if CompareStr(A.Key,B.Key)<0 then begin
        var Difference := 0;
        for var I := 0 to High(A.Value) do if A.Value[I]<>B.Value[I] then Inc(Difference);
        Check(Difference>100,'rendered vowel sprites have distinct pixels '+A.Key+'/'+B.Key+' '+Difference.ToString);
      end;
      // A special eye selection must preserve the ordinary LAB mouth choice.
      var Eye: TArtLayer := nil;
      for var G in D.Layers do if (G.Kind=alkGroup) and (G.Name='目') then Eye := G;
      if Eye<>nil then for var L in Eye.Children do if L.Name.Contains('やさしい目') then begin
        var Choice := TJSONObject.Create; Choice.AddPair('groupId',Eye.Id); Choice.AddPair('partId',L.Id); Cue.Acting.Variants.AddElement(Choice);
        MoviePose(Neutral,D,0.36853485,Audio,Pose);
        Check(Round(Pose.Value('mouthPhoneme'))=Ord('i'),'special eye selection retains exact ordinary LAB mouth phoneme');
        Break;
      end;
    finally PixelsByPhone.Free; Lines.Free; Seen.Free; end;
    Audio.Save(TPath.Combine(Root,'reference-real-speech.wav'));
    var Phones := TStringList.Create; var Lab := TStringList.Create;
    try
      var Cue := P.Cues[0]; Lab.Text := TFile.ReadAllText(ResolveMoviePath(Source,Cue.LabFile),TEncoding.UTF8);
      for var Line in Lab do begin
        var F := Line.Trim.TrimLeft([#$FEFF]).Split([' ',#9],TStringSplitOptions.ExcludeEmpty); if Length(F)<>3 then Continue;
        var Phone := LowerCase(F[2]); if not MatchText(Phone,['a','i','u','e','o']) or (Phones.IndexOf(Phone)>=0) then Continue;
        var A := StrToInt64(F[0])/10000000.0; var Z := StrToInt64(F[1])/10000000.0;
        var Index := Round((A+Z)/2*P.Fps); var Time := Index/P.Fps;
        if (Time<A+0.001) or (Time>Z-0.001) then Continue;
        var Image: string; if P.Characters[0].MotionFrame(Time,Image) then Continue;
        CompositionPose(P,P.Characters[0],D,Time,Audio,Pose);
        Check(Round(Pose.Value('mouthPhoneme'))=Ord(F[2][1]),'export frame uses its actual LAB phoneme '+Phone);
        var Selected: TArtLayer := nil;
        for var L in D.Layers do if D.Part(L.Id).Role='mouth' then begin var Visible: Boolean;
          if Pose.PartVisibility.TryGetValue(L.Id,Visible) and Visible then Selected := L;
        end;
        Check(Selected<>nil,'export frame selects a real mouth sprite '+Phone);
        var W := Round(P.Characters[0].Height*P.Height/1080); var Scale := Min(1.0,W/Max(D.Art.Width,D.Art.Height));
        var RW := Max(1,Round(D.Art.Width*Scale)); var RH := Max(1,Round(D.Art.Height*Scale));
        var BoxW := P.Characters[0].Width*P.Width/1920; var BoxH := P.Characters[0].Height*P.Height/1080;
        var K := Min(BoxW/RW,BoxH/RH); var TW := Round(RW*K); var TH := Round(RH*K);
        var Left := P.Characters[0].X*P.Width/1920+(BoxW-TW)/2;
        var Top := P.Characters[0].Y*P.Height/1080+BoxH-TH;
        var Crop := TJSONObject.Create;
        AddN(Crop,'x',Max(0,Floor(Left+(Selected.Bounds.Left-50)*TW/D.Art.Width)));
        AddN(Crop,'y',Max(0,Floor(Top+(Selected.Bounds.Top-50)*TH/D.Art.Height)));
        AddN(Crop,'width',Max(8,Ceil((Selected.Bounds.Width+100)*TW/D.Art.Width)));
        AddN(Crop,'height',Max(8,Ceil((Selected.Bounds.Height+100)*TH/D.Art.Height)));
        var B := RenderComposition(P,Time,Audio);
        try
          var Path := SaveBitmap(B,'video-reference-'+Phone); var O := TJSONObject.Create;
          O.AddPair('phoneme',Phone); AddN(O,'frame',Index); AddN(O,'time',Time); O.AddPair('mouthPart',Selected.Name); O.AddPair('path',Path); O.AddPair('mouthCrop',Crop); VideoFrames.AddElement(O);
        finally B.Free; end;
        Phones.Add(Phone); if Phones.Count=5 then Break;
      end;
      Check(Phones.Count=5,'five independent MP4 reference frames exclude the whole-character motion interval');
    finally Lab.Free; Phones.Free; end;
    for var Pair in P.Characters[0].Motions do begin
      var Definition := Pair.JsonValue as TJSONObject; var Images := JA(Definition,'frames'); var MinX,MaxX,MinY,MaxY: Double;
      MinX := MaxDouble; MinY := MaxDouble; MaxX := -MaxDouble; MaxY := -MaxDouble;
      for var Index := 0 to Images.Count-1 do begin
        var Path := ResolveMoviePath(Source,JS(TJSONObject(Images[Index]),'image')); var Png := TPngImage.Create;
        try
          Png.LoadFromFile(Path); Check(Png.TransparencyMode=ptmPartial,'motion frame preserves native alpha '+Pair.JsonString.Value+'/'+Index.ToString);
          var Sum,WtX,WtY: Double; Sum := 0; WtX := 0; WtY := 0;
          for var Y := 0 to Png.Height-1 do begin var Alpha := PByte(Png.AlphaScanline[Y]);
            for var X := 0 to Png.Width-1 do begin Sum := Sum+Alpha[X]; WtX := WtX+Alpha[X]*X; WtY := WtY+Alpha[X]*Y; end;
          end;
          Check(Sum>0,'motion contains actual opaque character pixels '+Pair.JsonString.Value+'/'+Index.ToString);
          MinX := Min(MinX,WtX/Sum); MaxX := Max(MaxX,WtX/Sum); MinY := Min(MinY,WtY/Sum); MaxY := Max(MaxY,WtY/Sum);
          if Index in [0,3,6,9] then TFile.Copy(Path,TPath.Combine(Root,'motion-'+Pair.JsonString.Value+'-'+Index.ToString+'.png'),True);
        finally Png.Free; end;
      end;
      Check((MaxX-MinX>10) or (MaxY-MinY>10),'whole-character motion has visible pixel travel '+Pair.JsonString.Value);
      var O := TJSONObject.Create; O.AddPair('name',Pair.JsonString.Value); AddN(O,'xTravelPixels',MaxX-MinX); AddN(O,'yTravelPixels',MaxY-MinY); AddN(O,'frameCount',Images.Count); Motions.AddElement(O);
    end;
    var SceneStart := 0.0;
    var Baseline := P.Clone;
    try
      Baseline.Characters[0].Expressions.Free; Baseline.Characters[0].Expressions := TJSONObject.Create;
      for var C in Baseline.Cues do begin C.Motion := 'still'; C.Emotion := 'neutral'; C.LabFile := ''; C.Acting.HeadGain := 0; C.Acting.BodyGain := 0; C.Acting.BlinkStrength := 0; end;
      Baseline.Characters[0].ActiveMotion := '';
      var Normal := RenderComposition(Baseline,1,nil);
      try
        Baseline.Characters[0].ActiveMotion := 'happy'; Baseline.Characters[0].MotionStart := 1;
        var Motion := RenderComposition(Baseline,1,nil);
        try
          SaveBitmap(Normal,'normal-baseline'); SaveBitmap(Motion,'motion-baseline');
          var Difference: Double := 0; var Samples := 0;
          for var Y := 150 to 850 do for var X := 1450 to 1850 do begin
            var A := PByte(Normal.ScanLine[Y]); var B := PByte(Motion.ScanLine[Y]);
            for var C := 0 to 2 do begin Difference := Difference+Abs(Integer(A[X*4+C])-Integer(B[X*4+C])); Inc(Samples); end;
          end;
          Check(Difference/Samples<12,'whole-character motion starts at the normal rendered actor size and baseline');
        finally Motion.Free; end;
      finally Normal.Free; end;
    finally Baseline.Free; end;
    for var Scene in P.Scenes do begin
      var B := RenderComposition(P,SceneStart+Min(3.0,P.SceneDuration(Scene)/2),Audio);
      try var Path := SaveBitmap(B,'scene-'+Scene.Id); Check(FileExists(Path),'actual scene and shared background render '+Scene.Id); finally B.Free; end;
      SceneStart := SceneStart+P.SceneDuration(Scene);
    end;
    Check(THashSHA2.GetHashStringFromFile(Source)=Before,'visual verification leaves the delivered work unchanged');
    var O := TJSONObject.Create;
    try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('source',Source); O.AddPair('mouthFrames',Frames.Clone as TJSONArray); O.AddPair('motions',Motions.Clone as TJSONArray); O.AddPair('videoFrames',VideoFrames.Clone as TJSONArray); O.AddPair('checks',Checks.Clone as TJSONArray);
      AddB(O,'humanDesktopVerification',False); O.AddPair('method','native renderer pixel differences and PNG alpha/centroid measurements');
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally Neutral.Free; Pose.Free; Audio.Free; D.Free; P.Free; end;
end;
begin
  Source := ParamStr(1); Root := ParamStr(2); ForceDirectories(Root); Checks := TJSONArray.Create; Frames := TJSONArray.Create; Motions := TJSONArray.Create; VideoFrames := TJSONArray.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally VideoFrames.Free; Motions.Free; Frames.Free; Checks.Free; end;
end.
