// 専用キャラ・専用台本だけで映像表情を検証する。DPI変更は行わない。
procedure AddExpressionFixture(Doc: TRigmDocument);
begin
  var G := Doc.Art.AddLayer(alkGroup,'記号',TArtBounds.Create(0,0,24,24));
  var Index := 0;
  for var Name in ['なし','？','！','！？'] do begin
    var P := Doc.Art.AddLayer(alkImage,Name,TArtBounds.Create(0,0,24,24),G);
    SetLength(P.Pixels,24*24*4); P.Visible := Index=0;
    for var I := 0 to 24*24-1 do begin P.Pixels[I*4] := 80+Index*50; P.Pixels[I*4+1] := 10; P.Pixels[I*4+2] := 10; P.Pixels[I*4+3] := 255; end;
    Inc(Index);
  end;
  Doc.SyncParts;
  for var P in G.Children do begin
    Doc.Part(P.Id).BoneId := Doc.Parameters[2].BoneId;
    Doc.GenerateMesh(P.Id,Doc.Part(P.Id).BoneId,2);
  end;
end;
{$IFDEF CHECK_BACKGROUND}
procedure CheckFaceOnlyRendering;
  procedure Group(Doc: TRigmDocument; const Name,Role: string; const Names: array of string; Bounds: TArtBounds);
  begin
    var G := Doc.Art.AddLayer(alkGroup,Name,Bounds); var Index := 0;
    for var ChildName in Names do begin
      var L := Doc.Art.AddLayer(alkImage,'*'+ChildName,Bounds,G); L.Visible := ChildName='通常';
      if Role='brow' then L.Visible := ChildName='楽'; // A saved pose is not the neutral expression.
      SetLength(L.Pixels,Bounds.Width*Bounds.Height*4);
      for var I := 0 to Length(L.Pixels) div 4-1 do begin
        L.Pixels[I*4] := 20+Index*25; L.Pixels[I*4+1] := 210-Index*20;
        L.Pixels[I*4+2] := 50+Index*20; L.Pixels[I*4+3] := 255;
      end;
      Doc.SyncParts; Doc.Part(L.Id).Role := Role; Doc.Part(L.Id).BoneId := Doc.Parameters[2].BoneId;
      Doc.GenerateMesh(L.Id,Doc.Part(L.Id).BoneId,2); Inc(Index);
    end;
  end;
  function Changes(A,B: TBitmap): Integer;
  begin
    Result := 0;
    for var Y := 0 to A.Height-1 do begin
      var RowA := PByteArray(A.ScanLine[Y]); var RowB := PByteArray(B.ScanLine[Y]);
      for var X := 0 to A.Width*4-1 do if RowA[X]<>RowB[X] then Inc(Result);
    end;
  end;
  procedure CaptureFace(Bitmap: TBitmap; const Name: string);
  begin
    var Png := TPngImage.Create;
    try Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,'FaceOnly\'+Name+'.png')); finally Png.Free; end;
  end;
  procedure SelectPart(Doc: TRigmDocument; Variants: TJSONArray; const GroupName,PartName: string);
  begin
    for var G in Doc.Layers do if (G.Kind=alkGroup) and (G.Name=GroupName) then
      for var L in G.Children do if L.Name='*'+PartName then begin
        var V := TJSONObject.Create; V.AddPair('groupId',G.Id); V.AddPair('partId',L.Id); Variants.AddElement(V); Exit;
      end;
    raise Exception.Create('Missing face fixture part: '+GroupName+'/'+PartName);
  end;
begin
  // The user's actor has these eye/brow names and no emotion symbols/colors.
  // Test final pixels with rig motion disabled; changing a pose alone is insufficient.
  var Doc := TRigmDocument.Create; var P := TRigmMovieProject.Create;
  var Neutral: TBitmap := nil; var PreviewNeutral: TBitmap := nil;
  ForceDirectories(TPath.Combine(Root,'FaceOnly'));
  try
    PopulateRigmSample(Doc); for var L in Doc.Layers do L.Visible := False;
    Group(Doc,'目','eye',['通常','閉じ','やや閉じ','笑顔閉じ','半開き','やさしい目'],TArtBounds.Create(64,40,192,100));
    Group(Doc,'眉','brow',['通常','喜','怒','哀','楽','困る','画面左上げ','画面右上げ'],TArtBounds.Create(64,12,192,32));
    var Path := TPath.Combine(Root,'FaceOnly\face-only.rigm'); SaveRigm(Doc,Path);
    var Actor := TRigmMovieCharacter.Create; P.Characters.Add(Actor); Actor.FileName := Path;
    Actor.X := 0; Actor.Y := 0; Actor.Width := 1920; Actor.Height := 1080; Actor.RigSafe := False;
    var Scene := TRigmMovieScene.Create; P.Scenes.Add(Scene); Scene.DisplayMode := 'none';
    var Cue := TRigmMovieCue.Create; P.Cues.Add(Cue); Cue.Scene := Scene.Id; Cue.SpeakerId := Actor.SpeakerId;
    Cue.Text := 'えっ！？'; Cue.AudioSeconds := 1; Cue.Pause := 0; Cue.FaceAutomatic := False;
    Cue.Acting.HeadGain := 0; Cue.Acting.BodyGain := 0; Cue.Acting.BlinkStrength := 0; Cue.Motion := 'still';
    P.Width := 640; P.Height := 360;
    for var Face in MovieEmotionIds do begin
      Cue.Emotion := Face;
      var B := RenderMovieFrame(P,nil,0.2,nil); var Preview := RenderMoviePreview(P,nil,0.2,nil,320,180);
      try
        CaptureFace(B,Face);
        if Face='neutral' then begin
          Neutral := TBitmap.Create; Neutral.Assign(B); PreviewNeutral := TBitmap.Create; PreviewNeutral.Assign(Preview);
        end else begin
          Check(Changes(Neutral,B)>300,'final export pixels reflect face-only expression '+Face);
          Check(Changes(PreviewNeutral,Preview)>75,'bounded preview pixels reflect face-only expression '+Face);
        end;
      finally Preview.Free; B.Free; end;
    end;
    Cue.Emotion := 'unavailable'; var B := RenderMovieFrame(P,nil,0.2,nil);
    try Check(Changes(Neutral,B)=0,'unavailable face falls back to the discovered neutral, not saved source visibility'); finally B.Free; end;
    Cue.FaceAutomatic := True; B := RenderMovieFrame(P,nil,0.2,nil); Cue.FaceAutomatic := False; Cue.Emotion := 'confused';
    var Expected := RenderMovieFrame(P,nil,0.2,nil);
    try Check(Changes(B,Expected)=0,'automatic punctuation selects the same final face pixels as a manual expression');
    finally Expected.Free; B.Free; end;
    // Independently pin the intended real eye/brow assets, not a second call
    // to the resolver being tested. The earlier brow-only implementation fails.
    for var Face in ['happy','sad','doubt','surprised'] do begin
      Cue.Emotion := Face; Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create;
      B := RenderMovieFrame(P,nil,0.2,nil); Cue.Emotion := 'neutral';
      if Face='happy' then begin SelectPart(Doc,Cue.Acting.Variants,'目','笑顔閉じ'); SelectPart(Doc,Cue.Acting.Variants,'眉','喜'); end
      else if Face='sad' then begin SelectPart(Doc,Cue.Acting.Variants,'目','やや閉じ'); SelectPart(Doc,Cue.Acting.Variants,'眉','哀'); end
      else begin
        if Face='doubt' then SelectPart(Doc,Cue.Acting.Variants,'目','半開き') else SelectPart(Doc,Cue.Acting.Variants,'目','通常');
        SelectPart(Doc,Cue.Acting.Variants,'眉','画面左上げ');
      end;
      Expected := RenderMovieFrame(P,nil,0.2,nil);
      try Check(Changes(B,Expected)=0,'final '+Face+' pixels match independently selected real eye and brow parts');
      finally Expected.Free; B.Free; end;
    end;
    Cue.Emotion := 'happy'; Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create;
    SelectPart(Doc,Cue.Acting.Variants,'目','通常'); B := RenderMovieFrame(P,nil,0.2,nil);
    Cue.Emotion := 'neutral'; SelectPart(Doc,Cue.Acting.Variants,'眉','喜'); Expected := RenderMovieFrame(P,nil,0.2,nil);
    try Check(Changes(B,Expected)=0,'manual normal eyes override happy eyes while retaining the happy brow pixels');
    finally Expected.Free; B.Free; end;
  finally PreviewNeutral.Free; Neutral.Free; P.Free; Doc.Free; end;
end;
procedure CheckPsdCastingExpression;
begin
  var Workspace := TPsdWorkspace.Create(TPath.Combine(Root,'PsdFace')); var Character := TPsdCharacter.Create;
  var Path := TPath.Combine(Root,'PsdFace\Characters\face.psdchar');
  var Parts := TJSONArray.Create;
  try
    Workspace.Initialize; Character.Name := '専用のPSD表情'; Character.Document.Width := 64; Character.Document.Height := 64;
    var Front := Character.Document.AddLayer(alkGroup,'正面',TArtBounds.Create(0,0,64,64));
    var NonFront := Character.Document.AddLayer(alkGroup,'非正面',TArtBounds.Create(0,0,64,64)); NonFront.Visible := False;
    PsdJson.Put(Character.Settings,'frontId',Front.Id); PsdJson.Put(Character.Settings,'nonFrontId',NonFront.Id);
    var Neutral := TJSONObject.Create; var Surprise := TJSONObject.Create;
    var NV := TJSONArray.Create; Neutral.AddPair('variants',NV); var SV := TJSONArray.Create; Surprise.AddPair('variants',SV);
    JO(Character.Settings,'expressions').AddPair('通常',Neutral); JO(Character.Settings,'expressions').AddPair('驚き',Surprise);
    for var GIndex := 0 to 1 do begin
      var G := Character.Document.AddLayer(alkGroup,'部位'+GIndex.ToString,TArtBounds.Create(GIndex*32,0,GIndex*32+32,64),Front);
      var Group := TJSONObject.Create; Group.AddPair('id',G.Id); Group.AddPair('name',G.Name);
      var Ids := TJSONArray.Create; Group.AddPair('partIds',Ids); JA(Character.Settings,'groups').AddElement(Group);
      for var PIndex := 0 to 1 do begin
        var P := Character.Document.AddLayer(alkImage,'差分'+PIndex.ToString,G.Bounds,G); SetLength(P.Pixels,32*64*4); P.Visible := PIndex=0;
        for var I := 0 to 32*64-1 do begin P.Pixels[I*4] := 40+PIndex*180; P.Pixels[I*4+1] := GIndex*150; P.Pixels[I*4+2] := 60; P.Pixels[I*4+3] := 255; end;
        Ids.Add(P.Id); var V := TJSONObject.Create; V.AddPair('groupId',G.Id); V.AddPair('partId',P.Id);
        if PIndex=0 then begin NV.AddElement(V); Group.AddPair('defaultPartId',P.Id); if GIndex=0 then Parts.AddElement(V.Clone as TJSONObject); end
        else SV.AddElement(V);
      end;
    end;
    SaveCharacter(Character,Workspace,Path);
  finally Character.Free; Workspace.Free; end;
  var Assets := ReadCastingExpressionAssets(Path);
  var Project := TRigmMovieProject.Create; var Cue := TRigmMovieCue.Create; var Actor := TRigmMovieCharacter.Create;
  try
    Check(JA(Assets,'groups').Count=2,'PSD face choices expose the actual selection groups');
    Project.Cues.Add(Cue); Project.Characters.Add(Actor); Cue.Text := '驚いた！'; Cue.SpeakerId := 'narrator';
    Actor.SpeakerId := Cue.SpeakerId; Actor.FileName := Path; Actor.RenderFormat := 'psd'; Actor.RigSafe := False;
    Cue.Acting.Variants.Free; Cue.Acting.Variants := Parts.Clone as TJSONArray;
    var Asset := TPsdCharacterAsset.Create(Path); var State := TPsdFrameState.Default;
    try
      State.Seconds := 0.1; State.Expression := '驚き'; State.Motion := 'none'; State.AutoBlink := True; State.Variants := Parts;
      var Expected := Asset.Renderer.Frame(State,64,64);
      var Actual := RenderPsdMovieCharacter(Project,Actor,0.1,nil,64,64);
      Check((Length(Expected)=Length(Actual)) and CompareMem(@Expected[0],@Actual[0],Length(Expected)),
        'PSD automatic surprise keeps other preset groups when one part is manually overridden');
      Cue.FaceAutomatic := False; Cue.Emotion := 'neutral'; State.Expression := '通常'; Expected := Asset.Renderer.Frame(State,64,64);
      Actual := RenderPsdMovieCharacter(Project,Actor,0.1,nil,64,64);
      Check(CompareMem(@Expected[0],@Actual[0],Length(Expected)),'PSD manual neutral takes priority over an exclamation');
    finally Asset.Free; end;
  finally Assets.Free; Project.Free; Parts.Free; end;
end;
{$ENDIF}
procedure CheckCastingExpressions;
begin
  var Frame := StageFrame(TRigmScriptCastingFrame) as TRigmScriptCastingFrame; Frame.RefreshState;
  var Face := Frame.FindComponent('ScriptCastingFace') as TComboBox;
  Check(Face.Enabled and (Face.Items.Count=11),'visual face choices work independently of the VOICEVOX catalog');
  var Selected := JS(JO(W.ScriptDraft.ScriptWizard,'casting'),'selectedCue');
  var C := W.ScriptDraft.Cue(Selected); var VoiceKey := W.ScriptDraft.AudioFingerprint(C);
  var Fingerprint := CastingFingerprint(W.ScriptDraft); var Style := C.VoiceStyleId;
  Face.ItemIndex := 8; Face.OnChange(Face);
  Check(not C.FaceAutomatic and (C.VisualEmotion='doubt'),'native face control applies a manual question expression');
  Check((W.ScriptDraft.AudioFingerprint(C)=VoiceKey) and (C.VoiceStyleId=Style) and
    (CastingFingerprint(W.ScriptDraft)=Fingerprint),'face editing keeps voice fingerprints, styles and casting prerequisites');
  var List := Frame.FindComponent('ScriptCastingRows') as TListView;
  Check((List.Columns.Count=5) and (List.Selected.SubItems[2]='疑問') and
    (List.Selected.SubItems[4]=C.Id),'casting list shows separate voice and face columns while retaining cue selection');
  var Saved := C.Json; var Reopened := TRigmMovieCue.FromJson(Saved);
  try Check(not Reopened.FaceAutomatic and (Reopened.VisualEmotion='doubt'),'manual face survives cue serialization');
  finally Reopened.Free; Saved.Free; end;
  Face.ItemIndex := 0; Face.OnChange(Face);
  var Clone := W.ScriptDraft.Clone;
  try
    var Cue := Clone.Cue(Selected);
    for var Text in ['本当？','本当?','驚いた！','驚いた!','えっ！？','えっ?!','えっ⁉','通常のセリフ。'] do begin
      Cue.Text := Text; var Expected := 'neutral';
      if Text.Contains('本当') then Expected := 'doubt' else if Text.Contains('驚いた') then Expected := 'surprised'
      else if Text.Contains('えっ') then Expected := 'confused';
      Check(Cue.FaceAutomatic and (Cue.VisualEmotion=Expected),'automatic punctuation expression: '+Text);
    end;
    Cue.Text := '本当？'; SetCastingExpression(Clone,Cue.Id,'happy',nil,nil);
    Check(Cue.VisualEmotion='happy','manual face takes precedence over punctuation');
    SetCastingExpression(Clone,Cue.Id,'neutral',nil,nil);
    Saved := Cue.Json; Reopened := TRigmMovieCue.FromJson(Saved);
    try Check(not Reopened.FaceAutomatic and (Reopened.VisualEmotion='neutral'),'explicit neutral remains manual after reopening a question');
    finally Reopened.Free; Saved.Free; end;
    Saved := ParseObject('{"text":"本当？","emotion":"sad"}'); Reopened := TRigmMovieCue.FromJson(Saved);
    try Check(not Reopened.FaceAutomatic and (Reopened.VisualEmotion='sad'),'legacy authored emotion is preserved without a new automatic flag');
    finally Reopened.Free; Saved.Free; end;
    Saved := ParseObject('{"text":"本当？"}'); Reopened := TRigmMovieCue.FromJson(Saved);
    try Check(Reopened.FaceAutomatic and (Reopened.VisualEmotion='doubt'),'legacy unconfigured dialogue gains punctuation detection');
    finally Reopened.Free; Saved.Free; end;
    Cue.Text := C.Text; Cue.Subtitle := C.Subtitle;
    Cue.AudioKey := Clone.AudioFingerprint(Cue); Cue.VoiceHeardKey := Cue.AudioKey;
    var Before := Cue.AudioKey; SetCastingExpression(Clone,Cue.Id,'angry',nil,nil);
    Check((Clone.AudioFingerprint(Cue)=Before) and (Cue.VoiceHeardKey=Before),'changing only the face retains heard voice approval');
    var Offset := Length(Cue.Text) div 2; SplitCastingRow(Clone,Cue.Id,Offset);
    var Next := Clone.Cues[Clone.Cues.IndexOf(Cue)+1];
    Check(not Next.FaceAutomatic and (Next.Emotion='angry'),'split dialogue retains manually chosen visual face');
  finally Clone.Free; end;
  // 配役番号を持つ行を使い、実際の素材から個別差分を選択する。
  var Role := ScriptCueRole(W.ScriptDraft,Selected); if Role=0 then W.AssignCasting(Selected,1,False);
  W.SelectCasting(Selected); Frame.RefreshState;
  TButton(Frame.FindComponent('ScriptCastingFaceDetailsToggle')).Click;
  var Part := Frame.FindComponent('ScriptCastingFacePart0') as TComboBox;
  Check((Part<>nil) and (Part.Items.Count=5),'fine expression choices come from the actual character group');
  Part.ItemIndex := 2; Part.OnChange(Part);
  C := W.ScriptDraft.Cue(Selected);
  Check(C.FaceAutomatic and (C.Acting.Variants.Count=1),'fine difference override is independent of automatic basic face');
  var Assets := W.CastingExpressionAssets(Selected); var Group := TJSONObject(JA(Assets,'groups')[0]);
  Check(JS(TJSONObject(C.Acting.Variants[0]),'partId')=JS(TJSONObject(JA(Group,'children')[1]),'id'),'actual question asset ID is saved per dialogue');
  var Bad := ParseObject('{"variants":[{"groupId":"missing","partId":"missing"}]}');
  Saved := C.Json;
  try
    var Rejected := False;
    try W.SetExpression(Selected,'sad',JA(Bad,'variants')); except on E: Exception do Rejected := True; end;
    Check(Rejected and (C.Json.ToJSON=Saved.ToJSON),'invalid face asset is rejected atomically without changing the face');
  finally Saved.Free; Bad.Free; end;
  {$IFDEF CHECK_BACKGROUND}
  var Doc := LoadRigm(TPath.Combine(Root,'OwnedData\RIGM\fixture.rigm')); var Pose := TRigmPose.Create;
  Clone := W.ScriptDraft.Clone;
  try
    var Cue := Clone.Cue(Selected); var Actor := TRigmMovieCharacter.Create; Clone.Characters.Add(Actor);
    Actor.FileName := TPath.Combine(Root,'OwnedData\RIGM\fixture.rigm'); Actor.SpeakerId := Cue.SpeakerId;
    Actor.Expressions.Free; Actor.Expressions := ExistingExpressions(Doc);
    var G := Doc.Art.FindLayer(JS(Group,'id')); Cue.Emotion := 'surprised'; Cue.FaceAutomatic := False;
    CompositionPose(Clone,Actor,Doc,Clone.CueStart(Cue)+0.1,nil,Pose);
    Check(Pose.PartVisibility[G.Children[1].Id] and not Pose.PartVisibility[G.Children[2].Id],
      'explicit question difference overrides the surprised preset during composition');
    Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create;
    CompositionPose(Clone,Actor,Doc,Clone.CueStart(Cue)+0.1,nil,Pose);
    Check(Pose.PartVisibility[G.Children[2].Id],'clearing the difference restores the surprised preset asset');
    Actor.Expressions.Free; Actor.Expressions := TJSONObject.Create;
    var Bitmap := RenderComposition(Clone,Clone.CueStart(Cue)+0.1,nil);
    try Check((Bitmap.Width=Clone.Width) and (Bitmap.Height=Clone.Height),'unregistered character presets are discovered through the cached render source'); finally Bitmap.Free; end;
    var Args := TJSONObject.Create; Args.AddPair('id',Cue.Id);
    try ApplyCompositionCommand(Clone,'analyze-script',Args);
      Check(not Cue.FaceAutomatic and (Cue.Emotion='surprised'),'reanalyzing the movie keeps an explicitly chosen face');
    finally Args.Free; end;
  finally Clone.Free; Pose.Free; Doc.Free; end;
  {$ENDIF}
  W.SaveScriptDraft(False); C := W.ScriptDraft.Cue(Selected); var Loaded := LoadMovie(W.ScriptDraft.FileName);
  try Check(Loaded.Cue(Selected).FaceAutomatic and (Loaded.Cue(Selected).Acting.Variants.ToJSON=C.Acting.Variants.ToJSON),
    'project save and reopen retain automatic face plus fine overrides'); finally Loaded.Free; end;
  Face.ItemIndex := 8; Face.OnChange(Face); Frame.RefreshState; Capture('casting-face-details');
  TButton(Frame.FindComponent('ScriptCastingFaceReset')).Click;
  Check(C.Acting.Variants.Count=0,'fine face reset removes only explicit asset overrides');
  TButton(Frame.FindComponent('ScriptCastingFaceDetailsToggle')).Click;
  Face.ItemIndex := 0; Face.OnChange(Face); W.SelectCasting(Selected);
  {$IFDEF CHECK_BACKGROUND} CheckPsdCastingExpression; CheckFaceOnlyRendering; {$ENDIF}
end;
