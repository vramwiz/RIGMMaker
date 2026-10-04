program RigmCompositionTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math,
  System.Types, System.Hash, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RIGMMakerMainForm, RigmMovieModel, RigmMovieSession, RigmMovieComposition,
  RigmMovieCompositionCommands, RigmMovieForm, RigmMovieCreator, RigmMovieAudio,
  RigmMovieRendering, RigmMovieCompositor, RigmMoviePhonemes, RigmModel, RigmStorage,
  RigmMoviePreparation,
  RigmSample, RigmJson, RigmPipeTestClient, ArtDocument;
type TErrorSink = class
  procedure Handle(Sender: TObject; E: Exception);
end;
var Root,Fixture,Pipes,LibraryDir,PipeName,AsyncError: string; Checks: TJSONArray; Main: TMainForm; ErrorSink: TErrorSink;
  Session: TRigmMovieSession; AId,BId,CueId,ExpectedJobId: string;
function CaptureStack(Skip,Count: DWORD; Trace,Hash: Pointer): Word; stdcall;
  external 'kernel32.dll' name 'RtlCaptureStackBackTrace';
function InstallTrace(First: Cardinal; Handler: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'AddVectoredExceptionHandler';
function FaultTrace(Info: PExceptionPointers): Longint; stdcall;
var Addresses: array[0..15] of Pointer;
begin
  Result := 0; if Info.ExceptionRecord.ExceptionCode<>$C0000005 then Exit;
  var Count := CaptureStack(0,Length(Addresses),@Addresses,nil);
  for var I := 0 to Count-1 do Writeln('AVTRACE ',IntToHex(NativeUInt(Addresses[I])-NativeUInt(GetModuleHandle(nil)),16));
  Flush(Output);
end;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); Flush(Output); end;
procedure TErrorSink.Handle(Sender: TObject; E: Exception);
begin AsyncError := E.ClassName+': '+E.Message; Writeln('ASYNC ERROR: '+AsyncError); Flush(Output); end;
function Find(P: TWinControl; const Name: string): TControl;
begin Result := nil; for var I := 0 to P.ControlCount-1 do begin var C := P.Controls[I]; if C.Name=Name then Exit(C); if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end; end; end;
function Studio(P: TWinControl): TRigmMovieForm;
begin Result := nil; for var I := 0 to P.ControlCount-1 do begin var C := P.Controls[I]; if (C is TRigmMovieForm) and C.Visible then Exit(TRigmMovieForm(C)); if C is TWinControl then begin Result := Studio(TWinControl(C)); if Result<>nil then Exit; end; end; end;
procedure Pump(Ms: Cardinal=180);
begin var UntilTick := GetTickCount64+Ms; repeat Application.ProcessMessages; if AsyncError<>'' then raise Exception.Create(AsyncError); if Session<>nil then Session.Poll; Sleep(5); until GetTickCount64>=UntilTick; end;
function Call(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  if Args.GetValue('projectId')=nil then Args.AddPair('projectId',Session.Project.Id);
  if Args.GetValue('revision')=nil then AddN(Args,'revision',Session.Project.Revision);
  var Reply := PipeCall(PipeName,Name,Args);
  try if not JB(Reply,'ok') then raise Exception.Create(Reply.ToJSON); Result := JO(Reply,'data').Clone as TJSONObject; finally Reply.Free; end;
end;
procedure Run(const Name: string; const Json: string='{}');
begin var O := Call(Name,ParseObject(Json)); try if Name='movie-audio-generate' then ExpectedJobId := JS(O,'jobId'); finally O.Free; end; end;
procedure Job(const Expected: string='succeeded');
begin
  var UntilTick := GetTickCount64+15000;
  repeat Pump(20); var A := TJSONObject.Create; A.AddPair('jobId',ExpectedJobId); var O := Call('movie-job-status',A); try if JB(O,'done') then begin Check((JS(O,'kind')='audio') and (JS(O,'state')=Expected),'requested audio job outcome '+Expected+': '+JS(O,'error')); Exit; end; finally O.Free; end; until GetTickCount64>=UntilTick;
  raise Exception.Create('Worker timeout');
end;
function Tone(const Name: string; Seconds: Double): string;
begin
  Result := TPath.Combine(Root,Name); var A := TRigmPcm.Create;
  try A.Rate := 48000; SetLength(A.Samples,Round(Seconds*A.Rate)); for var I := 0 to High(A.Samples) do A.Samples[I] := Round(Sin(I*2*Pi*220/A.Rate)*8000); A.Save(Result); finally A.Free; end;
end;
procedure SavePng(B: Vcl.Graphics.TBitmap; const Name: string);
begin var P := TPngImage.Create; try P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name)); finally P.Free; end; end;
function FixtureImage: string;
begin
  Result := TPath.Combine(Root,'TEST-ONLY-scene.png'); var B := Vcl.Graphics.TBitmap.Create;
  try B.SetSize(800,400); B.Canvas.Brush.Color := clNavy; B.Canvas.FillRect(Rect(0,0,800,400)); B.Canvas.Font.Color := clWhite; B.Canvas.TextOut(20,20,'TEST FIXTURE - NOT A GENERATED SCENE'); SavePng(B,'TEST-ONLY-scene.png'); finally B.Free; end;
end;
procedure ModelTests;
begin
  var P := TRigmMovieProject.FromText('# alpha'+#10+'narrator:first'+#10+'narrator:second'+#10+'# beta'+#10+'b:third');
  var D := TRigmDocument.Create; var Pose := TRigmPose.Create;
  try
    PopulateRigmSample(D); SaveRigm(D,TPath.Combine(LibraryDir,'fixture-character.rigm'));
    P.CharacterFile := '@sample'; P.EngineUrl := 'http://127.0.0.1:51238'; P.Width := 640; P.Height := 360; P.Fps := 10;
    for var S in P.Speakers do S.StyleId := 101;
    for var I := 0 to P.Cues.Count-1 do begin
      var C := P.Cues[I]; C.Pause := 0.2; C.AudioSeconds := 0.5; if I=1 then C.AudioSeconds := 0.7;
      C.WaveFile := Tone('TEST-TONE-'+I.ToString+'.wav',C.AudioSeconds); C.AudioKey := P.AudioFingerprint(C);
      C.LabFile := TPath.Combine(Root,'TEST-PHONEMES-'+I.ToString+'.lab');
      TFile.WriteAllText(C.LabFile,'0 1000000 Pause'+#10+'1000000 2000000 a'+#10+'2000000 3000000 i'+#10+'3000000 5000000 o',TEncoding.UTF8);
    end;
    var Key := P.Cues[0].AudioKey; P.EnableComposition;
    Check((P.Scenes.Count=2) and (P.Cues[0].Scene=P.Cues[1].Scene),'legacy labels convert into a scene containing two cues');
    Check(P.AudioReady(P.Cues[0]) and (P.Cues[0].AudioKey=Key),'composition preserves stored voice fingerprint');
    var First := P.Scenes[0]; var Second := P.Scenes[1]; First.Description := 'Scene description persists across both cues'; First.Image := FixtureImage;
    First.Padding := 1.25; Check(SameValue(P.CueStart(P.Cues[2]),2.85),'scene tail padding shifts later speech and subtitles');
    var Local,Start: Double; Check((P.SceneAt(2.2,Start,Local)=First) and (P.CueAt(2.2,Local,Start)=nil),'scene persists throughout tail padding independently from speech');
    var O := ParseObject('{"id":"'+Second.Id+'","index":0}'); try ApplyCompositionCommand(P,'move-scene',O); finally O.Free; end;
    Check(SameValue(P.CueStart(P.Cues[2]),0) and SameValue(P.CueStart(P.Cues[0]),0.7),'reordering moves an entire scene and all its internal cues');
    O := ParseObject('{"id":"'+First.Id+'","index":0}'); try ApplyCompositionCommand(P,'move-scene',O); finally O.Free; end;
    var Actor := TRigmMovieCharacter.Create; Actor.Name := 'Second fixture'; Actor.FileName := TPath.Combine(LibraryDir,'fixture-character.rigm'); Actor.SpeakerId := 'b'; P.Characters.Add(Actor);
    P.Characters[0].X := 60; P.Characters[0].Name := 'First fixture';
    var Available: Boolean; Check(SameValue(MoviePhonemeMouth(P.Cues[0].LabFile,0.199999,Available),1) and Available,'LAB phoneme a is open immediately before exact boundary');
    Check(SameValue(MoviePhonemeMouth(P.Cues[0].LabFile,0.2,Available),0.4),'LAB boundary switches directly to i without smoothing');
    Check(SameValue(MoviePhonemeMouth(P.Cues[0].LabFile,0.02,Available),0),'LAB pause closes mouth');
    P.Cues[0].Acting.BlinkInterval := 4; P.Cues[0].Acting.BlinkPhase := 3.93;
    CompositionPose(P,P.Characters[0],D,0.15,nil,Pose);
    Check((Pose.Value('eyeOpen')<0.05) and (Pose.Value('mouthOpen')>0.9),'blink and phoneme mouth animate independently');
    P.Characters[0].Expressions.AddPair('neutral',ParseObject('{"blinkAnimate":false,"mouthAnimate":true}'));
    CompositionPose(P,P.Characters[0],D,0.15,nil,Pose);
    Check((Pose.Value('eyeOpen')=1) and (Pose.Value('mouthOpen')>0.9),'special eyes disable blink while normal mouth keeps lip sync');
    P.Characters[0].Expressions.RemovePair('neutral').Free; P.Characters[0].Expressions.AddPair('neutral',ParseObject('{"blinkAnimate":true,"mouthAnimate":false,"rigSafe":false}'));
    CompositionPose(P,P.Characters[0],D,0.15,nil,Pose);
    Check((Pose.Value('eyeOpen')<0.05) and SameValue(Pose.Value('mouthOpen'),0.45),'special mouth freezes moderately during speech while blink remains independent');
    Check((Pose.Value('headAngle')=0) and (Pose.Value('bodyAngle')=0),'large pose disables original rig deformation');
    P.Characters[0].Expressions.RemovePair('neutral').Free;
    var B := RenderMovieFrame(P,nil,0.15); try SavePng(B,'two-characters.png'); Check((B.Width=640) and (B.Height=360),'composition renders to output coordinates independent of screen DPI'); finally B.Free; end;
    var OldCaption := P.Cues[0].Subtitle; P.Cues[0].Text := 'edited speech';
    Check(not P.AudioReady(P.Cues[0]) and P.HasStoredAudio(P.Cues[0]) and (P.Cues[0].Subtitle=OldCaption),'speech edit marks pending and keeps previous WAV and custom subtitle');
    var Mix := MixMovieAudio(P,True); try Check(SameValue(Mix.Duration,P.Duration,0.00003),'pending speech preview uses old voice duration and scene clock'); finally Mix.Free; end;
    var Bad := False; try Mix := MixMovieAudio(P); Mix.Free; except Bad := True; end; Check(Bad,'export rejects pending voice rather than claiming it is regenerated');
    P.Cues[0].Text := 'first'; P.Cues[0].Subtitle := 'CUSTOM SUBTITLE';
    Check(P.AudioReady(P.Cues[0]),'custom subtitle does not invalidate voice');
    SaveMovie(P,TPath.Combine(Root,'portable.rigmovie'));
    var Q := LoadMovie(P.FileName); try Check((Q.Characters.Count=2) and (Q.Scenes.Count=2) and Q.AudioReady(Q.Cues[0]),'portable multi-character work reopens with existing WAV'); finally Q.Free; end;
    AId := P.Characters[0].Id; BId := P.Characters[1].Id; CueId := P.Cues[0].Id;
  finally Pose.Free; D.Free; P.Free; end;
end;
procedure AdditionalModelTests;
begin
  var P := LoadMovie(TPath.Combine(Root,'portable.rigmovie')); var D := TRigmDocument.Create;
  try
    PopulateRigmSample(D); D.Meshes.Clear; D.Bones.Clear;
    for var Part in D.Parts do Part.Value.BoneId := '';
    for var I := 0 to High(D.Parameters) do D.Parameters[I].BoneId := '';
    D.BoneComplete := False; D.MeshComplete := False; D.ValidateStructure;
    var StaticPath := TPath.Combine(Root,'TEST-ONLY-no-rig.rigm'); SaveRigm(D,StaticPath);
    P.Characters[0].FileName := StaticPath; P.Characters[0].RigSafe := False;
    ValidateCompositionMaterials(P);
    var B := RenderMovieFrame(P,nil,0.15); B.Free;
    var Caps := MovieCapabilities(D);
    try Check(not JB(Caps,'headBodyMotion') and (JI(Caps,'drawableImages')>0),'PSD difference actor renders without bone/mesh completion'); finally Caps.Free; end;
    var C := P.Cues[0]; var Spoken := C.Text; C.Text := 'ありがとう、うれしい紹介です';
    var Catalog := TJSONArray.Create;
    var O := TJSONObject.Create;
    try
      Catalog.AddElement(ParseObject('{"uuid":"fixture","style":"ノーマル","styleId":101}'));
      Catalog.AddElement(ParseObject('{"uuid":"other","style":"喜び","styleId":999}'));
      Catalog.AddElement(ParseObject('{"uuid":"fixture","style":"喜び","styleId":102}'));
      O.AddPair('id',C.Id); ApplyCompositionCommand(P,'analyze-script',O,Catalog);
      Check((C.Emotion='happy') and (C.VoiceStyleId=102),'emotion analysis selects a real style belonging to the same engine speaker');
      Catalog.Remove(2).Free; ApplyCompositionCommand(P,'analyze-script',O,Catalog);
      Check(C.VoiceStyleId=-1,'unsupported emotion keeps base voice and never borrows another speaker');
    finally O.Free; Catalog.Free; end;
    C.Text := Spoken; C.Emotion := 'neutral'; C.VoiceStyleId := -1;
    C.Acting.Onset := 0.3; var Pose := TRigmPose.Create;
    try CompositionPose(P,P.Characters[0],D,0.15,nil,Pose); Check(Pose.Value('mouthOpen')=0,'direct LAB lip sync respects explicit acting onset'); finally Pose.Free; end;
    C.Acting.Onset := 0;
    var Image := TPath.Combine(Root,'TEST-ONLY-scene.png'); O := TJSONObject.Create;
    O.AddPair('id',P.Characters[0].Id); O.AddPair('emotion','happy'); var Preset := TJSONObject.Create; Preset.AddPair('image',Image); AddB(Preset,'generated',True); O.AddPair('preset',Preset);
    try
      var Rejected := False; try ApplyCompositionCommand(P,'register-expression',O); except Rejected := True; end;
      Check(Rejected,'generated expression is rejected until character permission is explicit');
      Preset.RemovePair('generated').Free; AddB(Preset,'generated',False); ApplyCompositionCommand(P,'register-expression',O);
    finally O.Free; end;
    SaveMovie(P,TPath.Combine(Root,'portable-expression.rigmovie'));
    var Q := LoadMovie(P.FileName);
    try
      var Sprite := JS(JO(Q.Characters[0].Expressions,'happy'),'image');
      Check(FileExists(ResolveMoviePath(Q.FileName,Sprite)) and not TPath.IsPathRooted(Sprite),'expression image is copied into portable work assets');
      Q.Cues[0].Emotion := 'happy'; B := RenderMovieFrame(Q,nil,0.15); try SavePng(B,'TEST-ONLY-expression-render.png'); finally B.Free; end;
    finally Q.Free; end;
    C.Text := ''; Check(not P.AudioReady(C) and P.HasStoredAudio(C),'empty spoken draft retains cached voice and remains pending until explicit regeneration');
    O := TJSONObject.Create; O.AddPair('id',P.Scenes[0].Id); AddN(O,'duration',0.1);
    try var Rejected := False; try ApplyCompositionCommand(P,'resize-scene',O); except Rejected := True; end; Check(Rejected,'scene trimming cannot truncate existing speech'); finally O.Free; end;
    C.Text := Spoken;
    B := Vcl.Graphics.TBitmap.Create;
    try B.SetSize(64,64); B.Canvas.Brush.Color := clRed; B.Canvas.FillRect(B.Canvas.ClipRect); SavePng(B,'TEST-ONLY-motion-red.png');
      B.Canvas.Brush.Color := clLime; B.Canvas.FillRect(B.Canvas.ClipRect); SavePng(B,'TEST-ONLY-motion-green.png');
    finally B.Free; end;
    var Red := TPath.Combine(Root,'TEST-ONLY-motion-red.png'); var Green := TPath.Combine(Root,'TEST-ONLY-motion-green.png');
    O := ParseObject('{"id":"'+P.Characters[0].Id+'","name":"TEST ONLY loop","motion":{"loop":true,"frames":[{"image":"'+Red.Replace('\','\\')+'","duration":0.1},{"image":"'+Green.Replace('\','\\')+'","duration":0.2}]}}');
    try ApplyCompositionCommand(P,'register-motion',O); finally O.Free; end;
    O := ParseObject('{"id":"'+P.Characters[0].Id+'","name":"TEST ONLY loop","start":0,"duration":1}');
    try ApplyCompositionCommand(P,'select-motion',O); finally O.Free; end;
    var MotionImage: string; var Character := P.Characters[0];
    Check(Character.MotionFrame(0.099999,MotionImage) and (MotionImage=Red),'whole-character motion retains first frame up to exact frame boundary');
    Check(Character.MotionFrame(0.1,MotionImage) and (MotionImage=Green),'whole-character motion honors each frame duration');
    Check(Character.MotionFrame(0.3,MotionImage) and (MotionImage=Red),'whole-character motion loops exactly from last frame to first');
    Check(Character.MotionFrame(0.95,MotionImage) and (MotionImage=Red),'motion seek resolves phase deterministically across multiple loops');
    Pose := TRigmPose.Create;
    try CompositionPose(P,Character,D,0.15,nil,Pose);
      Check((Pose.Value('mouthOpen')=0) and (Pose.Value('eyeOpen')=1) and (Pose.Value('headAngle')=0) and (Pose.Value('bodyAngle')=0),'motion suppresses lip sync, blink, and auxiliary rig deformation');
      CompositionPose(P,Character,D,1.0,nil,Pose); Check(not Character.MotionFrame(1.0,MotionImage),'finite motion duration returns to normal actor display');
    finally Pose.Free; end;
    var Before := RenderMovieFrame(P,nil,0.05); var Loop := RenderMovieFrame(P,nil,0.35);
    try Check(Before.Canvas.Pixels[106,190]=Loop.Canvas.Pixels[106,190],'rendered actor pixels repeat at a seeked loop boundary'); finally Before.Free; Loop.Free; end;
    SaveMovie(P,TPath.Combine(Root,'portable-motion.rigmovie')); Q := LoadMovie(P.FileName);
    try
      Check(Q.Characters[0].MotionFrame(0.3,MotionImage) and FileExists(ResolveMoviePath(Q.FileName,MotionImage)),'motion frames, timing, selection, and images survive portable save/reload');
      O := ParseObject('{"id":"'+Q.Characters[0].Id+'"}'); try ApplyCompositionCommand(Q,'stop-motion',O); finally O.Free; end;
      Check(not Q.Characters[0].MotionFrame(0.15,MotionImage),'explicit motion stop restores normal differences');
      var Motion := JO(Q.Characters[0].Motions,'TEST ONLY loop'); Motion.RemovePair('loop').Free; AddB(Motion,'loop',False);
      Q.Characters[0].ActiveMotion := 'TEST ONLY loop'; Q.Characters[0].MotionDuration := -1;
      Check(not Q.Characters[0].MotionFrame(0.3,MotionImage),'non-looping motion ends after its frame sequence');
    finally Q.Free; end;
  finally D.Free; P.Free; end;
end;
procedure UiTests;
begin
  Writeln('STEP: construct workspace'); Flush(Output);
  Main := TMainForm.Create(nil); Main.Show; Session := Studio(Main).Session; Pump;
  var C := ParseObject(TFile.ReadAllText(TDirectory.GetFiles(Pipes,'*.control.json')[0],TEncoding.UTF8)); try PipeName := JS(C,'commandPipe'); finally C.Free; end;
  var O := Call('app-status'); try Check(JS(O,'page')='preview','normal main starts at video preview/edit page'); finally O.Free; end;
  TToolButton(Find(Main,'WorkspaceCreate')).Click; O := Call('app-status'); try Check(JS(O,'page')='create','creation icon selects separate video creation page'); finally O.Free; end;
  Run('app-switch-page','{"page":"characters"}'); O := Call('app-status'); try Check(JS(O,'page')='characters','common pipe switches character registration page'); finally O.Free; end;
  O := Call('app-open-work',ParseObject('{"path":"'+TPath.Combine(Root,'portable.rigmovie').Replace('\','\\')+'"}')); O.Free;
  Session := Studio(Main).Session; Pump(250);
  O := Call('movie-timeline'); try
    Check((JA(O,'scenes').Count=2) and SameValue(JN(TJSONObject(JA(O,'cues')[2]),'start'),2.85),'shared pipe timeline includes scene order and padding');
  finally O.Free; end;
  Run('app-switch-page','{"page":"create"}'); Pump;
  var List := TListView(Find(Main,'CreationCharacters')); Check(List.Checkboxes and (List.SmallImages<>nil),'creation offers thumbnail checkbox membership');
  var Checked := 0; for var I := 0 to List.Items.Count-1 do if List.Items[I].Checked then Inc(Checked);
  Check((Checked=2) and (Session.Project.Characters.Count=2),'opened character membership remains separate from settings selection');
  List.Items[0].Selected := True; Pump;
  for var I := 0 to List.Items.Count-1 do if TCreationEntry(List.Items[I].Data).CharacterId=BId then List.Items[I].Selected := True;
  Pump;
  Check(Session.Project.Characters.Count=2,'selecting another settings target does not remove checked actors');
  var RedMotion := TPath.Combine(Root,'TEST-ONLY-motion-red.png').Replace('\','\\');
  var GreenMotion := TPath.Combine(Root,'TEST-ONLY-motion-green.png').Replace('\','\\');
  Run('movie-register-motion','{"id":"'+AId+'","name":"TEST ONLY loop","motion":{"loop":true,"frames":[{"image":"'+RedMotion+'","duration":0.1},{"image":"'+GreenMotion+'","duration":0.2}]}}');
  Run('movie-select-motion','{"id":"'+AId+'","name":"TEST ONLY loop","start":0}'); Run('movie-seek','{"time":0.3}');
  var MotionImage: string;
  Check(Session.Project.Character(AId).MotionFrame(Session.Time,MotionImage) and MotionImage.EndsWith('TEST-ONLY-motion-red.png'),'common pipe registers/selects whole-character motion and supports seeking');
  Pump; TButton(Find(Main,'CreationStopMotion')).Click;
  // The settings target is the second actor; choose the first actor to stop its motion.
  for var I := 0 to List.Items.Count-1 do if TCreationEntry(List.Items[I].Data).CharacterId=AId then List.Items[I].Selected := True;
  TButton(Find(Main,'CreationStopMotion')).Click;
  Check(not Session.Project.Character(AId).MotionFrame(0.3,MotionImage),'GUI motion stop shares the pipe model and restores normal display');
  for var I := 0 to List.Items.Count-1 do if TCreationEntry(List.Items[I].Data).CharacterId=BId then List.Items[I].Selected := True;
  var Name := TEdit(Find(Main,'CreationName')); Name.Text := 'pending actor name';
  Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"PIPE SUBTITLE"}'); Pump;
  Check(Name.Text='pending actor name','creator preserves typed actor settings after pipe revision');
  TButton(Find(Main,'CreationApplyCharacter')).Click;
  Check(Session.Project.Characters[1].Name<>'pending actor name','stale actor draft cannot overwrite newer model');
  TButton(Find(Main,'CreationReloadFields')).Click; Pump;
  var Preview := TRigmMoviePreview(Find(Main,'CreationPreview')); Preview.SelectedCharacter := AId;
  for var PPI in [96,120,144,192] do begin
    Main.ScaleForPPI(PPI); Main.Width := MulDiv(1500,PPI,96); Main.Height := MulDiv(950,PPI,96); Pump(30);
    var R := Preview.CharacterBounds(AId); var Base := Preview.ScreenToBase(R.Left,R.Top);
    Check(Abs(Base.X-Session.Project.Character(AId).X)<8,'preview FullHD mapping at DPI '+PPI.ToString);
    for var I := 0 to 7 do Check(Preview.HandleRect(AId,I).Width=2*MulDiv(5,PPI,96)+1,'resize handle '+I.ToString+' DPI '+PPI.ToString);
  end;
  Main.ScaleForPPI(96); Main.Width := 1500; Main.Height := 950; Pump;
  var R := Preview.CharacterBounds(AId); var X := (R.Left+R.Right) div 2; var Y := (R.Top+R.Bottom) div 2;
  var OldX := Session.Project.Character(AId).X;
  Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,Y)); Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X+30,Y+20)); Preview.Perform(WM_LBUTTONUP,0,MakeLParam(X+30,Y+20));
  Check((Session.Project.Character(AId).X<>OldX) and (Round(Session.Project.Character(AId).X) mod 10=0),'native drag commits snapped base coordinates');
  Pump; R := Preview.HandleRect(AId,4); X := (R.Left+R.Right) div 2; Y := (R.Top+R.Bottom) div 2;
  var OldWidth := Session.Project.Character(AId).Width;
  Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,Y)); Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X+25,Y+25)); Preview.Perform(WM_LBUTTONUP,0,MakeLParam(X+25,Y+25));
  Check(Session.Project.Character(AId).Width>OldWidth,'native corner handle resizes selected actor'); Pump;
  R := Preview.CharacterBounds(AId); X := (R.Left+R.Right) div 2; Y := (R.Top+R.Bottom) div 2; OldX := Session.Project.Character(AId).X;
  Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,Y));
  Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"revision during drag"}');
  Preview.Perform(WM_LBUTTONUP,0,MakeLParam(X+30,Y));
  Check(Session.Project.Character(AId).X=OldX,'drag started before pipe edit cannot overwrite newer revision');
  Run('movie-update-project','{"layout":"L","lDirection":"left"}');
  for var Actor in Session.Project.Characters do Check(Actor.X+Actor.Width/2<=720,'L left groups actors on selected side');
  Run('movie-update-project','{"layout":"L","lDirection":"right"}');
  for var Actor in Session.Project.Characters do Check(Actor.X+Actor.Width/2>=1200,'mirrored L groups actors on right side');
  Run('app-switch-page','{"page":"preview"}'); Pump;
  var M := Studio(Main); var Spoken := Session.Project.Cue(CueId).Text; var Subtitle := TMemo(Find(M,'MovieCueSubtitle'));
  Subtitle.Text := 'GUI CUSTOM CAPTION'; Pump(350);
  Check((Session.Project.Cue(CueId).Subtitle='GUI CUSTOM CAPTION') and (Session.Project.Cue(CueId).Text=Spoken),'GUI subtitle becomes shared model without altering speech');
  var Voice := Session.Project.Cue(CueId).WaveFile;
  TMemo(Find(M,'MovieCueText')).Text := 'changed spoken line'; Pump(350);
  Check((Session.Project.Cue(CueId).Text='changed spoken line') and (Session.Project.Cue(CueId).WaveFile=Voice) and (Session.Project.Cue(CueId).Subtitle='GUI CUSTOM CAPTION'),'GUI dialogue retains old WAV and custom caption without synthesis');
  var Token := Call('movie-edit-begin'); var EditToken := JS(Token,'editToken'); var Epoch := JI(Token,'epoch'); Token.Free; Pump(250);
  Check(Subtitle.ReadOnly,'Codex edit lock makes GUI text read-only');
  var Bad := False; try Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"unauthorized GUI write"}'); except Bad := True; end;
  Check(Bad and (Session.Project.Cue(CueId).Subtitle='GUI CUSTOM CAPTION'),'active edit lock rejects unowned mutation');
  Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"CODEX CAPTION","editToken":"'+EditToken+'","editEpoch":'+Epoch.ToString+'}');
  Run('movie-edit-end','{"editToken":"'+EditToken+'"}'); Pump(250); Check(not Subtitle.ReadOnly,'edit end releases GUI controls');
  Bad := False; try Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"late old token","editToken":"'+EditToken+'"}'); except Bad := True; end;
  Check(Bad and (Session.Project.Cue(CueId).Subtitle='CODEX CAPTION'),'old edit token cannot overwrite after release');
  Run('movie-audio-generate'); Job; Check((Session.Project.Cue(CueId).WaveFile<>Voice) and (Session.Project.Cue(CueId).Subtitle='CODEX CAPTION'),'explicit fixture voice replacement preserves custom subtitle');
  var OldVoice := Session.Project.Cue(CueId).WaveFile; Run('movie-update-dialogue','{"id":"'+CueId+'","text":"must retain on failure"}');
  var Count := StrToInt(TFile.ReadAllText(TPath.Combine(Fixture,'synthesis-count.txt')).Trim);
  TFile.WriteAllText(TPath.Combine(Fixture,'fail-synthesis-number.txt'),(Count+1).ToString); Run('movie-audio-generate'); Job('failed');
  Check((Session.Project.Cue(CueId).WaveFile=OldVoice) and not Session.Project.AudioReady(Session.Project.Cue(CueId)),'failed regeneration retains previous audio and pending state');
  TFile.Delete(TPath.Combine(Fixture,'fail-synthesis-number.txt')); Run('movie-audio-generate'); Job;
  Check(StrToInt(TFile.ReadAllText(TPath.Combine(Fixture,'synthesis-count.txt')).Trim)=Count+2,'regeneration visits only affected cue');
  var Generated := Count+2; Run('movie-update-dialogue','{"id":"'+CueId+'","text":""}');
  Run('movie-audio-generate'); Job;
  Check((Session.Project.Cue(CueId).WaveFile='') and Session.Project.AudioReady(Session.Project.Cue(CueId)) and
    (StrToInt(TFile.ReadAllText(TPath.Combine(Fixture,'synthesis-count.txt')).Trim)=Generated),'explicit regeneration clears an empty speech draft without making a synthesis request');
  Check(Session.Project.Cue(CueId).Subtitle='CODEX CAPTION','clearing speech never erases independent subtitle');
  Token := Call('movie-edit-begin'); EditToken := JS(Token,'editToken'); Token.Free;
  Run('movie-edit-fail','{"editToken":"'+EditToken+'"}');
  O := Call('movie-edit-status'); try Check(not JB(O,'locked') and (JS(O,'state')='failed'),'Codex edit failure releases GUI lock'); finally O.Free; end;
  Token := Call('movie-edit-begin'); EditToken := JS(Token,'editToken'); Token.Free; Pump(150);
  TToolButton(Find(Main,'CreationUnlock')).Click;
  O := Call('movie-edit-status'); try Check(not JB(O,'locked'),'manual GUI unlock releases an abandoned edit session'); finally O.Free; end;
  Bad := False; try Run('movie-update-subtitle','{"id":"'+CueId+'","subtitle":"late after manual unlock","editToken":"'+EditToken+'"}'); except Bad := True; end;
  Check(Bad and (Session.Project.Cue(CueId).Subtitle='CODEX CAPTION'),'manual unlock rejects late results using the former token');
  Token := Call('movie-edit-begin',ParseObject('{"leaseSeconds":10}')); EditToken := JS(Token,'editToken'); Token.Free;
  Pump(10300); O := Call('movie-edit-status'); try Check(not JB(O,'locked') and (JS(O,'state')='disconnected'),'missed heartbeat expires lock and restores GUI'); finally O.Free; end;
  Run('movie-save','{"path":"'+TPath.Combine(Root,'edited-test.rigmovie').Replace('\','\\')+'"}');
  O := Call('app-open-work',ParseObject('{"path":"'+TPath.Combine(Root,'edited-test.rigmovie').Replace('\','\\')+'"}')); try Check(JI(O,'openDocuments')>=3,'open retains previous workspace documents and their drafts'); finally O.Free; end;
  Session := Studio(Main).Session; Pump;
  Check((Session.Project.Characters.Count=2) and (Session.Project.Scenes.Count=2) and (Session.Project.Cue(CueId).Subtitle='CODEX CAPTION'),'saved composition reopens with actor layout and independent subtitle');
  Main.Free; Main := nil; Session := nil;
end;
begin
  Checks := TJSONArray.Create;
  for var I := 1 to ParamCount do begin
    if ParamStr(I).StartsWith('--composition-dir=') then Root := ParamStr(I).Substring(18);
    if ParamStr(I).StartsWith('--fixture-dir=') then Fixture := ParamStr(I).Substring(14);
    if ParamStr(I).StartsWith('--pipe-dir=') then Pipes := ParamStr(I).Substring(11);
    if ParamStr(I).StartsWith('--data-dir=') then LibraryDir := ParamStr(I).Substring(11);
  end;
  ForceDirectories(Root); ForceDirectories(LibraryDir); Application.Initialize;
  ErrorSink := TErrorSink.Create; Application.OnException := ErrorSink.Handle;
  InstallTrace(1,@FaultTrace);
  try
    try ModelTests; AdditionalModelTests; UiTests; except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
    var O := TJSONObject.Create;
    try AddB(O,'success',ExitCode=0); AddN(O,'passed',Checks.Count); O.AddPair('checks',Checks.Clone as TJSONArray); O.AddPair('directory',Root);
      O.AddPair('audioVerification','controlled TEST TONE fixture, not VOICEVOX speech'); AddB(O,'humanVisualVerification',False);
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'composition-results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally Main.Free; Application.OnException := nil; ErrorSink.Free; Checks.Free; end;
end.
