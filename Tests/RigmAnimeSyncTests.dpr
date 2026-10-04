program RigmAnimeSyncTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Math,
  Vcl.Graphics, Vcl.Imaging.pngimage, RigmMovieModel, RigmMovieAudio,
  RigmMovieRendering, RigmModel, RigmStorage, RigmJson;
var Project: TRigmMovieProject; Doc: TRigmDocument; Audio: TRigmPcm;
  Pose: TRigmPose; Checks: TJSONArray; Root,ProjectPath: string;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
procedure Frame(const Name: string; Time: Double);
begin var B := RenderMovieFrame(Project,Doc,Time,Audio); var P := TPngImage.Create;
  try P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png')); finally P.Free; B.Free; end;
end;
begin
  ProjectPath := ParamStr(1); Root := ParamStr(2); ForceDirectories(Root);
  Checks := TJSONArray.Create; var Report := TJSONObject.Create;
  try
    try
      var Original := THashSHA2.GetHashStringFromFile(ProjectPath);
      Project := LoadMovie(ProjectPath); Doc := LoadRigm(ResolveMoviePath(Project.FileName,Project.CharacterFile));
      Audio := MixMovieAudio(Project); Pose := TRigmPose.Create;
      Check((Project.Cues.Count=4) and (Project.Speakers[0].StyleId=108),'saved real Kiritan preview supplies four dialogue sections');
      var TalkTime := 0.2; var Peak := 0.0;
      for var I := 5 to Floor(Project.Cues[0].AudioSeconds*40)-1 do begin
        var Level := Audio.Envelope(I/40.0); if Level>Peak then begin Peak := Level; TalkTime := I/40.0; end;
      end;
      Check(Peak>0.1,'actual dialogue provides varying speech envelope for synchronization');
      MoviePose(Project,Doc,TalkTime,Audio,Pose); AddN(Report,'talkTime',TalkTime); AddN(Report,'talkMouth',Pose.Value('mouthOpen'));
      Check(Pose.Value('mouthOpen')>0.1,'real speech opens character mouth at measured audio timestamp'); Frame('real-speech-mouth',TalkTime);
      var PauseTime := Project.Cues[0].AudioSeconds+Project.Cues[0].Pause/2;
      MoviePose(Project,Doc,PauseTime,Audio,Pose); AddN(Report,'pauseTime',PauseTime); AddN(Report,'pauseMouth',Pose.Value('mouthOpen'));
      Check(SameValue(Pose.Value('mouthOpen'),0),'inter-cue silence closes character mouth'); Frame('real-speech-pause',PauseTime);
      var Acting := Project.Cues[0].Acting;
      var BlinkTime := Acting.BlinkInterval+Acting.BlinkDuration/2-Acting.BlinkPhase;
      MoviePose(Project,Doc,BlinkTime,Audio,Pose); var BlinkEye := Pose.Value('eyeOpen'); AddN(Report,'blinkEye',BlinkEye);
      MoviePose(Project,Doc,BlinkTime+Acting.BlinkDuration,Audio,Pose); AddN(Report,'openEye',Pose.Value('eyeOpen'));
      Check(Pose.Value('eyeOpen')>BlinkEye+0.2,'character blink returns to open eyes on the same timeline'); Frame('real-speech-blink',BlinkTime);
      Check((Project.Width=1920) and (Project.Height=1080) and (Project.Fps=30),'synchronization inspection retains FullHD source settings');
      Check(THashSHA2.GetHashStringFromFile(ProjectPath)=Original,'read-only synchronization inspection preserves saved user project');
      AddB(Report,'success',True);
    except on E: Exception do begin AddB(Report,'success',False); Report.AddPair('error',E.Message); Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
    AddN(Report,'passed',Checks.Count); Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('project',ProjectPath); Report.AddPair('directory',Root);
    AddB(Report,'subjectiveListeningVerified',False);
    TFile.WriteAllText(TPath.Combine(Root,'sync-results.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; Checks.Free; Pose.Free; Audio.Free; Doc.Free; Project.Free; end;
end.
