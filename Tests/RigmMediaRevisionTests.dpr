program RigmMediaRevisionTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.Math, System.StrUtils,
  System.Types, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, Winapi.Windows,
  RigmMovieModel, RigmMovieSession, RigmMovieTimeline, RigmMovieWorkspace, RigmAppSettings,
  RigmMovieRendering, RigmMovieAudio, RigmStorage, RigmModel, RigmJson, ArtDocument,
  RigmMovieMotionLibrary, RigmMovieCompositor, RigmMoviePhonemes;
var Checks: TJSONArray; Source,Root,Target: string; Session: TRigmMovieSession;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS: '+Name); Flush(Output); end;
function Run(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try Args.AddPair('projectId',Session.Project.Id); AddN(Args,'revision',Session.Project.Revision); Result := Session.Execute(Name,Args); finally Args.Free; end;
end;
procedure Seek(Time: Double);
begin var O := TJSONObject.Create; AddN(O,'time',Time); var R := Run('seek',O); R.Free; end;
procedure Test;
begin
  var SourceHash := THashSHA2.GetHashStringFromFile(Source);
  var Project := LoadMovie(Source); Session.SetProject(Project);
  Check(Project.Scenes.Count=4,'edited work has four actual scenes');
  Check(Project.Characters.Count=1,'edited work retains its real character');
  var FirstImage := ResolveMoviePath(Project.FileName,Project.Scenes[0].Image);
  var Theme := Project.ThemeBackground;
  Seek(Project.Duration-0.2);
  Session.AdoptImage(Project.Scenes[0].Id,FirstImage);
  Check(Session.Time=0,'image adoption displays the selected scene from its start');
  Check(Session.Project.Modified,'image adoption remains unsaved');
  Check(Session.Project.ThemeBackground=Theme,'scene image adoption keeps common background separate');
  var Stored := Session.Project.Scenes[0].Image;
  Check(FileExists(Stored) and (THashSHA2.GetHashStringFromFile(Stored)=THashSHA2.GetHashStringFromFile(FirstImage)),'adopted image is a verified copy in the work folder');
  var O := Run('timeline'); var Wave := TJSONObject.Create; var Host := TForm.Create(nil); var Timeline := TRigmMovieTimeline.Create(Host); var Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Timeline.Parent := Host; Timeline.SetBounds(0,0,950,210); Timeline.SetData(O,Wave); Host.HandleNeeded; Timeline.HandleNeeded;
    Bitmap.SetSize(950,210); Timeline.PaintTo(Bitmap.Canvas.Handle,0,0);
    Check(Timeline.ThumbnailCount>=4,'timeline builds actual image thumbnails');
    var Builds := Timeline.StaticBuildCount; var Thumbnails := Timeline.ThumbnailCount;
    for var I := 1 to 50 do begin Seek(I/50*Session.Project.Duration); Timeline.SetTime(Session.Time); Timeline.PaintTo(Bitmap.Canvas.Handle,0,0); end;
    Check((Builds=Timeline.StaticBuildCount) and (Thumbnails=Timeline.ThumbnailCount),'seeking never rebuilds thumbnails or static timeline');
    var Png := TPngImage.Create; try Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,'timeline.png')); finally Png.Free; end;
    var Before := Session.Time; O.Free; O := Run('status'); Check(Session.Time=Before,'read-only status keeps the current cursor');
  finally Bitmap.Free; Host.Free; O.Free; Wave.Free; end;
  Project := Session.Project;
  var Motions := BuildCharacterMotions(ResolveMoviePath(Project.FileName,Project.Characters[0].FileName));
  try
    Check(Motions.Count=4,'four emotional whole-character motions use the real stored character');
    Project.Characters[0].Motions.Free; Project.Characters[0].Motions := Motions.Clone as TJSONObject;
    var Loaded := LoadCharacterMotions(ResolveMoviePath(Project.FileName,Project.Characters[0].FileName));
    try Check(Loaded.ToJSON=Motions.ToJSON,'character motion library reloads independently for another work'); finally Loaded.Free; end;
    Project.Characters[0].ActiveMotion := 'happy'; Project.Characters[0].MotionStart := 1; Project.Characters[0].MotionDuration := 1.5;
  finally Motions.Free; end;
  Project.FfmpegExe := GetEnvironmentVariable('RIGMMAKER_MEDIA_FFMPEG');
  Project.OutputTarget := TPath.Combine(TPath.Combine(ExtractFileDir(Target),'Exports'),'星灯り郵便局.mp4');
  SaveMovie(Project,Target,True);
  Check(not Project.Modified,'explicit organized save clears modified state');
  for var Folder in ['Images','Audio','Characters','Exports'] do Check(DirectoryExists(TPath.Combine(ExtractFileDir(Target),Folder)),'work folder contains '+Folder);
  var Reopened := LoadMovie(Target);
  try
    for var S in Reopened.Scenes do Check(not TPath.IsPathRooted(S.Image) and FileExists(ResolveMoviePath(Target,S.Image)),'saved scene image has a valid relative reference '+S.Id);
    for var C in Reopened.Cues do Check(FileExists(ResolveMoviePath(Target,C.WaveFile)) and FileExists(ResolveMoviePath(Target,C.LabFile)),'stored speech and LAB survive the organized copy');
    var Doc := LoadRigm(ResolveMoviePath(Target,Reopened.Characters[0].FileName)); var Audio := MixMovieAudio(Reopened);
    var Pose := TRigmPose.Create;
    try
      var MouthGroup: TArtLayer := nil;
      for var G in Doc.Layers do if (G.Kind=alkGroup) and (G.Name='口') then MouthGroup := G;
      Check(MouthGroup<>nil,'real character contains its mouth sprite group');
      CompositionPose(Reopened,Reopened.Characters[0],Doc,1.2,Audio,Pose);
      Check((Pose.Value('mouthOpen')=0) and (Pose.Value('headAngle')=0) and (Pose.Value('bodyAngle')=0) and (Pose.Value('eyeOpen')=1),
        'whole-character motion suspends mouth blinking and rig assistance');
      var Seen := TStringList.Create; var Cue := Reopened.Cues[0]; var Lines := TStringList.Create;
      try
        Lines.Text := TFile.ReadAllText(ResolveMoviePath(Target,Cue.LabFile),TEncoding.UTF8);
        Cue.Acting.Variants.Free; Cue.Acting.Variants := TJSONArray.Create; Cue.Emotion := 'neutral';
        for var Line in Lines do begin
          var Fields := Line.Trim.Split([' ',#9],TStringSplitOptions.ExcludeEmpty); if Length(Fields)<>3 then Continue;
          if not MatchText(Fields[2],['a','i','u','e','o']) then Continue;
          var Time := (StrToInt64(Fields[0])+StrToInt64(Fields[1]))/20000000.0;
          var Phone: string; var Available: Boolean;
          MoviePhonemeSample(ResolveMoviePath(Target,Cue.LabFile),Time,Phone,Available);
          Check(Available and SameText(Phone,Fields[2]),'LAB lookup retains exact vowel '+Fields[2]+' at '+Time.ToString);
          MoviePose(Reopened,Doc,Time,Audio,Pose);
          Check(Pose.Value('mouthPhoneme')=Ord(Phone[1]),'render pose retains LAB vowel identity');
          var Count := 0; var Name := '';
          for var L in MouthGroup.Children do begin var Visible: Boolean; if Pose.PartVisibility.TryGetValue(L.Id,Visible) and Visible then begin Inc(Count); Name := L.Name; end; end;
          Check(Count=1,'LAB vowel selects exactly one rendered mouth sprite '+Fields[2]+' -> '+Name);
          if Seen.IndexOf(Name)<0 then Seen.Add(Name);
          if Seen.Count=5 then Break;
        end;
        Check(Seen.Count=5,'actual speech LAB switches all five real vowel mouth sprites');
      finally Lines.Free; Seen.Free; end;
    finally Pose.Free; Audio.Free; Doc.Free; end;
  finally Reopened.Free; end;
  AppSettings.RecordMovie(Project,Project.Duration,Project.Cues[3].Id);
  O := TJSONObject.Create; O.AddPair('path',Target); var Reply := Run('open',O); Reply.Free;
  Check(Session.Time=0,'saved history opens the organized work at zero');
  Check(Session.ResumeCue=Session.Project.Cues[0].Id,'saved history selects the first cue');
  Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'original edited work remains byte-identical');
  if FindCmdLineSwitch('export') or (ParamStr(4)='--export') then begin
    Reply := Run('export'); Reply.Free;
    var Deadline := GetTickCount64+1200000;
    while Session.Busy and (GetTickCount64<Deadline) do begin Sleep(50); Session.Poll; end;
    Reply := Run('job-status');
    try Check(JS(Reply,'state')='succeeded','real speech and images export to MP4'); finally Reply.Free; end;
    Check(FileExists(Session.Project.OutputTarget),'MP4 export file exists');
    SaveMovie(Session.Project,Target,True);
  end;
  O := TJSONObject.Create;
  try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('source',Source); O.AddPair('target',Target); O.AddPair('export',Session.Project.OutputTarget); O.AddPair('checks',Checks.Clone as TJSONArray);
    TFile.WriteAllText(TPath.Combine(Root,'results.json'),O.ToJSON,TEncoding.UTF8);
  finally O.Free; end;
end;
begin
  Application.Initialize; Source := ParamStr(1); Root := ParamStr(2); Target := ParamStr(3); ForceDirectories(Root);
  Checks := TJSONArray.Create; Session := TRigmMovieSession.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); Flush(Output); ExitCode := 1; end; end;
  finally Session.Free; Checks.Free; end;
end.
