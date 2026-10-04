program RigmCritiqueFeatureTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses Winapi.Windows, System.SysUtils, System.Classes, System.Types, System.JSON,
  System.IOUtils, System.Hash, System.Math, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Themes, Vcl.Styles,
  RigmJson, RigmModel, RigmStorage, RigmMovieModel, RigmMovieSession, RigmMovieForm,
  RigmMovieCompositor, RigmMovieAudio, RigmMovieActing, RigmMovieChart, ArtDocument;
var Source,Rig,Root: string; Checks: TJSONArray;
const PhoneIds: array[0..4] of string = ('a','i','u','e','o');
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS '+Name); Flush(Output); end;
procedure Pump(Ms: Cardinal);
begin var Deadline := GetTickCount64+Ms; repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=Deadline; end;
function Find(P: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if C.Name=Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end;
  end;
end;
procedure SaveBitmap(B: Vcl.Graphics.TBitmap; const Name: string);
begin
  var P := TPngImage.Create;
  try P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png')); finally P.Free; end;
end;
procedure Capture(C: TWinControl; const Name: string);
begin
  var B := Vcl.Graphics.TBitmap.Create;
  try B.SetSize(C.Width,C.Height); C.PaintTo(B.Canvas,0,0); SaveBitmap(B,Name); finally B.Free; end;
end;
function Named(D: TRigmDocument; const GroupName,PartName: string): TArtLayer;
begin
  Result := nil;
  for var G in D.Layers do if (G.Kind=alkGroup) and (G.Name=GroupName) then
    for var L in G.Children do if L.Name.Trim.TrimLeft(['*'])=PartName then Exit(L);
end;
function Visible(Pose: TRigmPose; Layer: TArtLayer): Boolean;
begin
  Result := False; if Layer=nil then Exit;
  if not Pose.PartVisibility.TryGetValue(Layer.Id,Result) then Result := Layer.Visible;
end;
procedure Test;
begin
  var Before := THashSHA2.GetHashStringFromFile(Source); var RigHash := THashSHA2.GetHashStringFromFile(Rig);
  var D := LoadRigm(Rig); var P := LoadMovie(Source); var Audio: TRigmPcm := nil;
  try
    Check(D.Usable and not D.SourceMatched and (D.Bones.Count=6) and (D.Meshes.Count>40),'updated PSD rig advances through usable without a human source confirmation');
    Check(P.Characters.Count=1,'owned actual speech project has one character');
    var Character := P.Characters[0]; Character.FileName := Rig; P.CharacterFile := Rig; Character.ActiveMotion := '';
    Character.Expressions.Free; Character.Expressions := ExistingExpressions(D);
    Check(Character.Expressions.Count=10,'real PSD differences provide ten semantic emotion presets');
    Audio := MixMovieAudio(P);
    var Cue := P.Cues[0]; Cue.Acting.HeadGain := 0.2; Cue.Acting.BodyGain := 0.1;
    for var Emotion in MovieEmotionIds do begin
      Cue.Emotion := Emotion; P.Validate;
      var B := RenderComposition(P,0.8,Audio);
      try SaveBitmap(B,'emotion-'+Emotion); finally B.Free; end;
      Check(Character.Expressions.GetValue(Emotion)<>nil,'actual render accepts existing PSD emotion '+Emotion);
    end;
    Cue.Emotion := 'happy';
    var Pose := TRigmPose.Create;
    try
      CompositionPose(P,Character,D,3.35,Audio,Pose);
      Check(Visible(Pose,Named(D,'目','閉じ')),'happy eye closes fully at the four-second blink interval');
      var Choice := TJSONObject.Create; Choice.AddPair('groupId',D.ParentId(Named(D,'目','笑顔閉じ').Id));
      Choice.AddPair('partId',Named(D,'目','笑顔閉じ').Id); Cue.Acting.Variants.AddElement(Choice);
      CompositionPose(P,Character,D,0.8,Audio,Pose);
      Check(Visible(Pose,Named(D,'目','笑顔閉じ')),'manual special eye choice overrides emotion defaults');
      CompositionPose(P,Character,D,3.35,Audio,Pose);
      Check(Visible(Pose,Named(D,'目','笑顔閉じ')),'fixed special eye is not replaced by automatic blinking');
      Character.SpeakerId := 'inactive-speaker';
      try
        CompositionPose(P,Character,D,3.35,Audio,Pose);
        Check(Visible(Pose,Named(D,'目','閉じ')),'another speaker cue does not disable this character automatic blinking');
      finally Character.SpeakerId := Cue.SpeakerId; end;
      Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create; Cue.Emotion := 'gentle';
      CompositionPose(P,Character,D,3.35,Audio,Pose);
      Check(Visible(Pose,Named(D,'目','やさしい目')),'gentle special eye remains fixed while speaking');
      var Motion := TJSONObject.Create; var Frames := TJSONArray.Create; var Frame := TJSONObject.Create;
      Frame.AddPair('image',TPath.Combine(Root,'emotion-neutral.png')); AddN(Frame,'duration',1);
      Frames.AddElement(Frame); Motion.AddPair('frames',Frames); Character.Motions.AddPair('test',Motion);
      Character.ActiveMotion := 'test'; Character.MotionStart := 0; Character.MotionDuration := 1;
      try
        CompositionPose(P,Character,D,0.8,Audio,Pose);
        Check((Pose.Value('mouthOpen')=0) and (Pose.Value('eyeOpen')=1) and
          (Pose.Value('headAngle')=0) and (Pose.Value('bodyAngle')=0),'whole-character motion suppresses lip, blink and auxiliary rig animation');
      finally Character.ActiveMotion := ''; Character.Motions.RemovePair('test').Free; end;
      var Acting := TRigmMovieActing.Create;
      try
        for var Phone in PhoneIds do begin
          Pose.Reset; Pose.Values.AddOrSetValue('mouthPhoneme',Ord(Phone[1]));
          Acting.ApplyFeatureAssets(D,Pose,0.8,0.0);
          var Vowel := '';
          case Phone[1] of 'a': Vowel := 'あ'; 'i': Vowel := 'い'; 'u': Vowel := 'う'; 'e': Vowel := 'え'; 'o': Vowel := 'お'; end;
          Check(Visible(Pose,Named(D,'口',Vowel)) and Visible(Pose,Named(D,'目','閉じ')),'vowel '+Phone+' remains independently selected during a closed-eye blink');
        end;
      finally Acting.Free; end;
    finally Pose.Free; end;
    Cue.Emotion := 'neutral'; var S := TRigmMovieSession.Create;
    try
      P.Modified := False; S.SetProject(P); P := nil;
      var M := TRigmMovieForm.CreateForSession(nil,S);
      try
        M.Show; ShowWindow(M.Handle,SW_SHOWNOACTIVATE); M.Width := 1500; M.Height := 950; Pump(200);
        M.SelectPropertyPage('scene');
        var Kind := TComboBox(Find(M,'MovieSceneChartKind')); Kind.ItemIndex := 1; Kind.OnChange(Kind);
        var SceneTitle := TEdit(Find(M,'MovieSceneTitle'));
        var ChartTitle := TEdit(Find(M,'MovieSceneChartTitle'));
        var ChartItems := TMemo(Find(M,'MovieSceneChartItems'));
        SceneTitle.Text := '未適用の場面見出し'; ChartTitle.Text := '総評（架空作品の評価例）';
        TEdit(Find(M,'MovieSceneChartMaximum')).Text := '5';
        ChartItems.Text := '物語 = 4.2'+sLineBreak+'人物 = 4.5'+sLineBreak+'演出 = 4.0'+sLineBreak+'テンポ = 3.5'+sLineBreak+'余韻 = 4.4';
        M.InvokeAction(44);
        Check(SceneTitle.Text='未適用の場面見出し','applying chart preserves unrelated scene text drafts');
        var Scene := S.Project.Scene(S.Project.Cues[0].Scene);
        Check(MovieChartEnabled(Scene.Chart) and (JA(Scene.Chart,'items').Count=5),'GUI applies a real five-axis summary chart');
        M.InvokeAction(41);
        Scene := S.Project.Scene(S.Project.Cues[0].Scene);
        Check(Scene.Title='未適用の場面見出し','remaining scene draft applies after the chart');
        ChartTitle.Text := 'チャートの未適用題名'; SceneTitle.Text := '新しい場面見出し'; M.InvokeAction(41);
        Check(ChartTitle.Text='チャートの未適用題名','applying scene metadata preserves chart drafts');
        M.SelectPropertyPage('acting'); M.SelectPropertyPage('scene');
        Check(ChartTitle.Text='チャートの未適用題名','property page switching preserves chart input');
        M.InvokeAction(44); Scene := S.Project.Scene(S.Project.Cues[0].Scene);
        Check(JS(Scene.Chart,'title')='チャートの未適用題名','remaining chart draft applies after scene metadata');
        M.SelectPropertyPage('acting');
        var EmotionBox := TComboBox(Find(M,'MovieCueEmotion')); var Found := False;
        for var I := 0 to EmotionBox.Items.Count-1 do if MovieEmotionIds[NativeInt(EmotionBox.Items.Objects[I])]='surprised' then begin
          EmotionBox.ItemIndex := I; Found := True; Break;
        end;
        Check(Found,'GUI lists surprise only from the registered real PSD preset');
        EmotionBox.OnChange(EmotionBox); M.InvokeAction(16);
        Check(S.Project.Cues[0].Emotion='surprised','GUI emotion selection updates the shared movie data');
        Check(S.Project.AudioReady(S.Project.Cues[0]),'visual emotion edits preserve existing real speech readiness');
        var B := RenderComposition(S.Project,0.8,Audio);
        try SaveBitmap(B,'radar-composition'); finally B.Free; end;
        M.SelectPropertyPage('scene'); Kind.ItemIndex := 2; Kind.OnChange(Kind); M.InvokeAction(44);
        Scene := S.Project.Scene(S.Project.Cues[0].Scene);
        B := RenderComposition(S.Project,0.8,Audio);
        try SaveBitmap(B,'bar-composition'); finally B.Free; end;
        Check(JS(Scene.Chart,'kind')='bar','same GUI can switch the saved chart to horizontal bars');
        Capture(M,'chart-editor');
        var Args := TJSONObject.Create; Args.AddPair('path',TPath.Combine(Root,'chart-emotions.rigmovie'));
        try var Reply := S.Execute('save',Args); Reply.Free; finally Args.Free; end;
        var Reopened := LoadMovie(TPath.Combine(Root,'chart-emotions.rigmovie'));
        try
          Check((Reopened.Cues[0].Emotion='surprised') and (JS(Reopened.Scenes[0].Chart,'kind')='bar') and (JA(Reopened.Scenes[0].Chart,'items').Count=5),'save and reopen retain emotion, chart type, labels and values');
          Check(Reopened.AudioReady(Reopened.Cues[0]),'saved copy retains genuine audio assets and fingerprint');
        finally Reopened.Free; end;
        var Revision := S.Project.Revision; var ExistingChart := Scene.Chart.ToJSON;
        Args := TJSONObject.Create; Args.AddPair('id',Scene.Id); Args.AddPair('projectId',S.Project.Id); AddN(Args,'revision',Revision);
        Args.AddPair('chart',ParseObject('{"kind":"radar","maximum":0,"items":[]}'));
        var Rejected := False;
        try try var Reply := S.Execute('update-scene',Args); Reply.Free; except on E: Exception do Rejected := E.Message<>''; end; finally Args.Free; end;
        Check(Rejected and (S.Project.Revision=Revision) and (S.Project.Scene(Scene.Id).Chart.ToJSON=ExistingChart),'invalid chart is rejected without changing the existing project');
      finally M.Free; end;
    finally S.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Source)=Before,'actual user speech project is unchanged');
    Check(THashSHA2.GetHashStringFromFile(Rig)=RigHash,'prepared source rig is unchanged');
    var Report := TJSONObject.Create;
    try AddB(Report,'success',True); AddN(Report,'passed',Checks.Count); Report.AddPair('checks',Checks.Clone as TJSONArray);
      AddB(Report,'humanDesktopVerification',False); Report.AddPair('rig',Rig); Report.AddPair('source',Source);
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  finally Audio.Free; P.Free; D.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows');
  Source := ParamStr(1); Rig := ParamStr(2); Root := ParamStr(3); ForceDirectories(Root); Checks := TJSONArray.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; end;
end.
