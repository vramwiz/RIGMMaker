program RigmStarLanternDelivery;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Math,
  Vcl.Graphics, Vcl.Imaging.pngimage, RigmJson, RigmModel, RigmStorage,
  RigmMovieModel, RigmMovieComposition, RigmMovieCompositionCommands,
  RigmMovieCompositor, RigmMovieRendering, RigmMovieAudio;
var Source,Destination,Images: string; P,Q: TRigmMovieProject; Report: TJSONObject;
const SceneIds: array[0..3] of string = ('intro','recommendation','concerns','verdict');
  Titles: array[0..3] of string = ('導入','おすすめ点','気になる点','総評');
  Emotions: array[0..3] of string = ('neutral','happy','serious','gentle');
  Descriptions: array[0..3] of string = (
    '海辺の小さな郵便局を舞台にした架空作品。届かなかった手紙と、そこに残る思いを静かに描きます。',
    '手紙を通じて人と人がつながる温かさ。小さな親切が誰かへ届く場面と、灯りのある美術が魅力です。',
    '謎がほどけるまでの歩みはゆっくり。展開の速さを求めると物足りない場面があります。',
    '派手さより余韻を楽しむ作品。静かな夜に、登場人物の気持ちへ寄り添いたい人に向いています。');
procedure SaveFrame(const Path: string; Seconds: Double; Audio: TRigmPcm);
begin
  var B := RenderMovieFrame(Q,nil,Seconds,Audio); var Image := TPngImage.Create;
  try Image.Assign(B); Image.SaveToFile(Path); finally Image.Free; B.Free; end;
end;
begin
  for var I := 1 to ParamCount do begin
    if ParamStr(I).StartsWith('--source=') then Source := ParamStr(I).Substring(9);
    if ParamStr(I).StartsWith('--destination=') then Destination := ParamStr(I).Substring(14);
    if ParamStr(I).StartsWith('--images=') then Images := ParamStr(I).Substring(9);
  end;
  P := nil; Q := nil; Report := TJSONObject.Create;
  try
    try
      if not FileExists(Source) or (Destination='') or (Images='') then raise Exception.Create('Specify source work, new destination, and image folder');
      ForceDirectories(Destination); var OriginalHash := THashSHA2.GetHashStringFromFile(Source);
      var Target := TPath.Combine(Destination,'星灯り郵便局-編集版.rigmovie');
      if SameText(ExpandFileName(Target),ExpandFileName(Source)) then raise Exception.Create('Edited work must use a new destination');
      P := LoadMovie(Source); var SourceId := P.Id; P.Id := NewRigmId; P.Title := '星灯り郵便局・シーン編集版';
      P.EnableComposition;
      if (P.Scenes.Count<>4) or (P.Cues.Count<>4) or (P.Characters.Count<>1) then raise Exception.Create('Unexpected original work structure');
      P.Layout := 'theme'; P.BackgroundColor := $302218;
      P.Characters[0].Name := '東北きりたん'; P.Characters[0].X := 1480; P.Characters[0].Y := 100;
      P.Characters[0].Width := 400; P.Characters[0].Height := 810; P.Characters[0].InitialPosition := 'right';
      P.Characters[0].AllowGeneratedExpressions := False;
      var A := TJSONObject.Create;
      try ApplyCompositionCommand(P,'analyze-script',A); finally A.Free; end;
      var Accepted := 0; var ImageRecords := TJSONArray.Create; Report.AddPair('images',ImageRecords);
      for var I := 0 to 3 do begin
        var OldId := P.Scenes[I].Id; P.Scenes[I].Id := SceneIds[I]; P.Scenes[I].Title := Titles[I]; P.Scenes[I].Description := Descriptions[I];
        for var C in P.Cues do if C.Scene=OldId then begin C.Scene := SceneIds[I]; C.Emotion := Emotions[I]; C.Acting.BlinkInterval := 4; end;
        var Path := TPath.Combine(Images,'hoshiakari_'+SceneIds[I]+'.png');
        var Entry := TJSONObject.Create; Entry.AddPair('sceneId',SceneIds[I]); Entry.AddPair('expectedPath',Path); AddB(Entry,'exists',FileExists(Path)); ImageRecords.AddElement(Entry);
        if FileExists(Path) then begin
          var Pic := TPngImage.Create;
          try Pic.LoadFromFile(Path); AddN(Entry,'width',Pic.Width); AddN(Entry,'height',Pic.Height); if (Pic.Width<1) or (Pic.Height<1) then raise Exception.Create('Empty scene image'); finally Pic.Free; end;
          P.Scenes[I].Image := Path; Inc(Accepted); Entry.AddPair('sha256',THashSHA2.GetHashStringFromFile(Path));
        end;
      end;
      var Common := TPath.Combine(Images,'hoshiakari_common.png');
      if FileExists(Common) then begin P.ThemeBackground := Common; Inc(Accepted); end;
      var Voices := TJSONArray.Create; Report.AddPair('voices',Voices);
      for var C in P.Cues do begin
        if not P.AudioReady(C) then raise Exception.Create('Original stored speech is not ready: '+C.Id);
        var Entry := TJSONObject.Create; Entry.AddPair('cueId',C.Id);
        Entry.AddPair('waveSha256',THashSHA2.GetHashStringFromFile(ResolveMoviePath(P.FileName,C.WaveFile)));
        Entry.AddPair('labSha256',THashSHA2.GetHashStringFromFile(ResolveMoviePath(P.FileName,C.LabFile))); Voices.AddElement(Entry);
      end;
      ValidateCompositionMaterials(P); P.Changed; SaveMovie(P,Target); Q := LoadMovie(Target);
      ValidateCompositionMaterials(Q); var Audio := MixMovieAudio(Q);
      try
        var Start := 0.0;
        for var I := 0 to Q.Scenes.Count-1 do begin SaveFrame(TPath.Combine(Destination,'preview-'+SceneIds[I]+'.png'),Start+0.8,Audio); Start := Start+Q.SceneDuration(Q.Scenes[I]); end;
      finally Audio.Free; end;
      for var I := 0 to Q.Cues.Count-1 do begin
        var Entry := TJSONObject(Voices[I]);
        AddB(Entry,'waveUnchanged',JS(Entry,'waveSha256')=THashSHA2.GetHashStringFromFile(ResolveMoviePath(Q.FileName,Q.Cues[I].WaveFile)));
        AddB(Entry,'labUnchanged',JS(Entry,'labSha256')=THashSHA2.GetHashStringFromFile(ResolveMoviePath(Q.FileName,Q.Cues[I].LabFile)));
        if not JB(Entry,'waveUnchanged') or not JB(Entry,'labUnchanged') then raise Exception.Create('Stored speech changed');
      end;
      AddB(Report,'success',True); AddB(Report,'complete',Accepted=5); AddB(Report,'imagesIntegrated',Accepted=5); AddN(Report,'acceptedImages',Accepted);
      AddB(Report,'sourceUnchanged',OriginalHash=THashSHA2.GetHashStringFromFile(Source));
      AddB(Report,'reopened',True); AddB(Report,'newSpeechGenerated',False); AddB(Report,'motionMaterialVerified',False); AddB(Report,'humanVisualVerification',False);
      Report.AddPair('sourceProjectId',SourceId); Report.AddPair('editedProjectId',Q.Id); Report.AddPair('path',Target); AddN(Report,'durationSeconds',Q.Duration);
      Report.AddPair('credit','VOICEVOX:東北きりたん');
      Writeln('Edited work saved and reloaded; existing real WAV/LAB preserved. Images ',Accepted,'/5.');
    except on E: Exception do begin AddB(Report,'success',False); Report.AddPair('error',E.ClassName+': '+E.Message); Writeln(E.Message); ExitCode := 1; end; end;
    if Destination<>'' then TFile.WriteAllText(TPath.Combine(Destination,'edited-verification.json'),Report.ToJSON,TEncoding.UTF8);
  finally Q.Free; P.Free; Report.Free; end;
end.
