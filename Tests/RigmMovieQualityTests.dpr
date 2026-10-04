program RigmMovieQualityTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Math,
  System.Generics.Collections, Vcl.Graphics, Vcl.Imaging.pngimage, Winapi.Windows,
  RigmModel, RigmStorage, RigmMovieModel, RigmMovieAudio, RigmMovieRendering,
  RigmMovieActing, RigmJson, ArtDocument;
var Root,Input,Mode: string; Doc: TRigmDocument; Project: TRigmMovieProject; Audio: TRigmPcm; Checks: TJSONArray;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Group(const Name: string): TArtLayer;
begin Result := nil; for var L in Doc.Layers do if (L.Kind=alkGroup) and (L.Name=Name) then Exit(L); end;
procedure Select(const Name,ChildName: string);
begin
  var G := Group(Name); if G=nil then raise Exception.Create('No group '+Name);
  for var C in G.Children do if C.Name=ChildName then begin
    var O := TJSONObject.Create; O.AddPair('groupId',G.Id); O.AddPair('partId',C.Id); Project.Cues[0].Acting.Variants.AddElement(O); Exit;
  end;
  raise Exception.Create('No child '+Name+' / '+ChildName);
end;
procedure Parameters(Head,Body,Eye,Mouth: Double);
begin
  var C := Project.Cues[0]; C.Parameters.Free; C.Parameters := TJSONObject.Create;
  AddN(C.Parameters,'headAngle',Head); AddN(C.Parameters,'bodyAngle',Body); AddN(C.Parameters,'eyeOpen',Eye); AddN(C.Parameters,'mouthOpen',Mouth);
end;
procedure Frame(const Name: string; Time: Double);
var B: Vcl.Graphics.TBitmap; Png: TPngImage; Started: UInt64;
begin
  Started := GetTickCount64; B := RenderMovieFrame(Project,Doc,Time,Audio); Png := TPngImage.Create;
  try Png.Assign(B); Png.SaveToFile(TPath.Combine(Root,Mode+'-'+Name+'.png'));
  finally Png.Free; B.Free; end;
  Writeln('FRAME ',Name,' ms=',GetTickCount64-Started);
end;
procedure Run;
begin
  var Before := THashSHA2.GetHashStringFromFile(Input); Doc := LoadRigm(Input);
  Check(Length(Doc.Layers)=44,'stored Kiritan supplies actual forty-four layers');
  if Doc.Bones.Count=0 then begin
    Doc.SeedBones;
    for var L in Doc.Layers do if (L.Kind=alkImage) and not Doc.IsReferencePart(L.Id) then begin
      var P := Doc.Part(L.Id); if P.Role='body' then P.BoneId := Doc.UpperBodyBoneId else P.BoneId := Doc.Parameters[2].BoneId;
      Doc.GenerateMesh(L.Id,P.BoneId,5);
    end;
  end;
  SaveRigm(Doc,TPath.Combine(Root,'Kiritan-prepared-copy.rigm'));
  Project := TRigmMovieProject.FromText('narrator:保存済み素材による品質検証。'); Project.Width := 1920; Project.Height := 1080; Project.Fps := 30;
  Project.CharacterFile := TPath.Combine(Root,'Kiritan-prepared-copy.rigm');
  var Cue := Project.Cues[0]; Cue.Motion := 'still'; Cue.Pause := 0.2; Cue.AudioSeconds := 2.8;
  Audio := TRigmPcm.Create; Audio.Rate := 48000; SetLength(Audio.Samples,134400);
  for var I := 2400 to 131999 do Audio.Samples[I] := Round(Sin(I*2*Pi*220/Audio.Rate)*10000);
  Audio.Save(TPath.Combine(Root,'EXPLICIT-TEST-TONE.wav')); Cue.WaveFile := TPath.Combine(Root,'EXPLICIT-TEST-TONE.wav'); Cue.AudioKey := Project.AudioFingerprint(Cue);
  SaveMovie(Project,TPath.Combine(Root,'quality.rigmovie'));
  var O := MovieActorAssets(Doc); try TFile.WriteAllText(TPath.Combine(Root,'actual-assets.json'),O.ToJSON,TEncoding.UTF8); finally O.Free; end;
  Parameters(0,0,1,0); Frame('rest',0.1);
  Parameters(18,0,0.2,1); Frame('head-blink-mouth',0.1);
  Parameters(0,8,1,0); Frame('upperbody',0.1);
  Parameters(-8,-4,1,1); Frame('combined',0.1);
  Select('目','*やさしい目'); Select('眉','*困る'); Select('口','*え'); Select('体（ポーズ）','*左上を指さす');
  Parameters(0,0,1,0); Frame('selected-pose',0.1);
  var Pose := TRigmPose.Create;
  try
    MoviePose(Project,Doc,0.1,Audio,Pose);
    for var V in Cue.Acting.Variants do begin
      var G := Doc.Art.FindLayer(JS(TJSONObject(V),'groupId')); var Count := 0;
      for var C in G.Children do if Pose.PartVisibility[C.Id] then Inc(Count);
      Check(Count=1,'exclusive actual variant group '+G.Name);
    end;
  finally Pose.Free; end;
  Cue.Parameters.Free; Cue.Parameters := TJSONObject.Create; Cue.Motion := 'nod'; Cue.Acting.BlinkPhase := 0;
  Frame('voice',0.4); Frame('blink',0.08); Frame('pause',2.9);
  Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create;
  Cue.Acting.MouthMode := 'assets'; Cue.Acting.BlinkMode := 'assets';
  Pose := TRigmPose.Create;
  try
    for var Step := 0 to 2 do begin
      Parameters(18,0,Step/2,Step/2); MoviePose(Project,Doc,0.4,Audio,Pose);
      for var Role in ['eye','mouth'] do begin
        var Selected: TArtLayer := nil; var VisibleCount := 0;
        for var G in Doc.Layers do if (G.Kind=alkGroup) and (G.Children.Count>1) and (Doc.Part(G.Children[0].Id).Role=Role) then
          for var L in G.Children do if Pose.PartVisibility[L.Id] then begin Selected := L; Inc(VisibleCount); end;
        Check((VisibleCount=1) and (Selected<>nil),'real '+Role+' assets remain exclusive at openness '+Step.ToString);
        Check(Pose.PartFeatureAssets[Selected.Id],'real '+Role+' animation uses native sprite geometry at openness '+Step.ToString);
        if Step=0 then Check(Selected.Name.Contains('閉じ'),'zero openness chooses existing closed '+Role+' sprite');
        if Step=2 then Check(not Selected.Name.Contains('閉じ'),'full openness retains an existing open '+Role+' sprite');
      end;
    end;
  finally Pose.Free; end;
  Check(THashSHA2.GetHashStringFromFile(Input)=Before,'read-only original material copy bytes preserved');
  O := TJSONObject.Create;
  try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('input',Input); O.AddPair('directory',Root); O.AddPair('mode',Mode); O.AddPair('prepared',TPath.Combine(Root,'Kiritan-prepared-copy.rigm'));
    O.AddPair('checks',Checks.Clone as TJSONArray); TFile.WriteAllText(TPath.Combine(Root,Mode+'-results.json'),O.ToJSON,TEncoding.UTF8);
  finally O.Free; end;
end;
begin
  Input := ParamStr(1); Root := ParamStr(2); Mode := ParamStr(3); ForceDirectories(Root); Checks := TJSONArray.Create;
  try try Run; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; Audio.Free; Project.Free; Doc.Free; end;
end.
