program MoviePreviewBenchmark;
{$APPTYPE CONSOLE}
// 専用素材だけで連続プレビューと再生時刻更新の処理時間を比較する。DPI変更は行わない。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Diagnostics,
  Winapi.Windows, System.Types, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  RigmModel, RigmSample, RigmStorage, RigmJson, RigmMovieModel, RigmMovieComposition,
  RigmMovieSession, RigmMovieAudio, RigmMovieRendering, RigmMovieJobs
  {$IFDEF PREVIEW_OPTIMIZED}, Vcl.Controls, Vcl.ExtCtrls, RigmMovieEditorFrame, RigmMovieForm,
  RigmMovieCompositor, RigmVoiceEffects, RigmAppSettings{$ENDIF};
var Root,Error: string; Checks: TJSONArray; Report: TJSONObject;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); end;
function Fixture: TRigmMovieProject;
begin
  var B := Vcl.Graphics.TBitmap.Create; var Png := TPngImage.Create; var D := TRigmDocument.Create;
  var Audio := TRigmPcm.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(2048,1536);
    for var Y := 0 to B.Height-1 do begin
      var Row := PByte(B.ScanLine[Y]);
      for var X := 0 to B.Width*4-1 do Row[X] := Byte((X*31+Y*37+(X xor Y)*17) and 255);
    end;
    Png.Assign(B); Png.SaveToFile(TPath.Combine(Root,'owned-image.png'));
    PopulateRigmSample(D); SaveRigm(D,TPath.Combine(Root,'owned-actor.rigm'));
    Audio.Rate := 48000; SetLength(Audio.Samples,24000);
    for var I := 0 to High(Audio.Samples) do Audio.Samples[I] := Round(Sin(I*2*Pi*220/48000)*4000);
    Audio.Save(TPath.Combine(Root,'owned-audio.wav'));
  finally Audio.Free; D.Free; Png.Free; B.Free; end;
  Result := TRigmMovieProject.Create; Result.Width := 1920; Result.Height := 1080;
  Result.CharacterFile := TPath.Combine(Root,'owned-actor.rigm');
  var Actor := TRigmMovieCharacter.Create; Result.Characters.Add(Actor);
  Actor.FileName := Result.CharacterFile; Actor.SpeakerId := Result.Speakers[0].Id;
  Actor.X := 1370; Actor.Y := 130; Actor.Width := 520; Actor.Height := 900;
  for var J := 0 to 7 do begin
    var Scene := TRigmMovieScene.Create; Result.Scenes.Add(Scene); Scene.Title := '専用場面 '+J.ToString;
    Scene.Image := TPath.Combine(Root,'owned-image.png'); Scene.DisplayMode := 'image';
    for var I := 0 to 7 do begin
      var Cue := TRigmMovieCue.Create; Result.Cues.Add(Cue); Cue.SpeakerId := Actor.SpeakerId;
      Cue.Scene := Scene.Id; Cue.Text := '専用音声と字幕のプレビュー '+I.ToString; Cue.Subtitle := Cue.Text;
      Cue.WaveFile := TPath.Combine(Root,'owned-audio.wav'); Cue.AudioSeconds := 0.5; Cue.Pause := 0.3;
      Cue.AudioKey := Result.AudioFingerprint(Cue);
    end;
  end;
  Result.Validate;
end;
function Frame(Session: TRigmMovieSession; Seconds: Double): Vcl.Graphics.TBitmap; forward;
{$IFDEF PREVIEW_OPTIMIZED}
procedure SavePixels(Bitmap: Vcl.Graphics.TBitmap; const Path: string);
begin
  var Stream := TFileStream.Create(Path,fmCreate);
  try for var Y := 0 to Bitmap.Height-1 do Stream.WriteBuffer(Bitmap.ScanLine[Y]^,Bitmap.Width*4);
  finally Stream.Free; end;
end;
procedure Regression;
begin
  var S := TRigmMovieSession.Create;
  try
    S.SetProject(Fixture);
    var P := S.Project; var Before := P.Json;
    try
      var B := Frame(S,0.1);
      try Check((B.Width=960) and (B.Height=540),'interactive frame uses requested display resolution'); finally B.Free; end;
      var Mixed := CachedMovieAudio(P,True);
      try
        for var Index in [0,1,40,63] do begin
          var Time := P.CueStart(P.Cues[Index])+0.1; var A := PreviewMovieAudio(P,Time);
          try
            Check((A<>nil) and (Length(A.Samples)=25201),'preview holds one cue plus envelope padding, index '+Index.ToString);
            Check(Abs(A.Envelope(Time)-Mixed.Envelope(Time))<0.000001,'cue lip envelope matches export at '+Index.ToString);
            Check(Abs(A.Envelope(Time+0.39)-Mixed.Envelope(Time+0.39))<0.000001,'speech ending envelope matches export at '+Index.ToString);
          finally A.Free; end;
        end;
      finally Mixed.Free; end;
      var BgmVolume := P.BgmVolume;
      P.BgmFile := P.Cues[0].WaveFile; P.BgmVolume := 1; P.BgmFadeOut := 3;
      var MixClock := TStopwatch.StartNew; Mixed := CachedMovieAudio(P,True); MixClock.Stop;
      AddN(Report,'bgmFade51SecondsMs',MixClock.Elapsed.TotalMilliseconds);
      var A := PreviewMovieAudio(P,0.1);
      try
        Check(Abs(A.Envelope(0.1)-Mixed.Envelope(0.1))<0.000001,'BGM does not drive preview mouth movement');
        var Index := Length(Mixed.Samples)-6001;
        var Source := TRigmPcm.Load(P.BgmFile);
        try
          var Expected := Round(Source.Samples[Index mod Length(Source.Samples)]*(P.Duration-Index/Mixed.Rate)/P.BgmFadeOut);
          Check(Abs(Mixed.Samples[Index]-Expected)<=1,'BGM fade retains correct final sample gain');
        finally Source.Free; end;
      finally A.Free; Mixed.Free; P.BgmFile := ''; P.BgmVolume := BgmVolume; P.BgmFadeOut := 0; end;
      // Preserve immutable sources for comparison with the pre-change renderer/DCUs.
      var ReferenceRoot := TPath.Combine(Root,'Reference'); ForceDirectories(ReferenceRoot);
      var Reference := P.Clone;
      try
        for var Name in ['owned-actor.rigm','owned-image.png','owned-audio.wav'] do
          TFile.Copy(TPath.Combine(Root,Name),TPath.Combine(ReferenceRoot,Name));
        var Picture := TPicture.Create; var Jpeg := TJPEGImage.Create; var Alpha := TPngImage.CreateBlank(COLOR_RGBALPHA,8,320,240);
        var Bitmap := Vcl.Graphics.TBitmap.Create;
        try
          Picture.LoadFromFile(TPath.Combine(ReferenceRoot,'owned-image.png')); Bitmap.Assign(Picture.Graphic);
          Jpeg.Assign(Bitmap); Jpeg.SaveToFile(TPath.Combine(ReferenceRoot,'owned-image.jpg'));
          for var Y := 0 to Alpha.Height-1 do begin
            var Row := PByte(Alpha.Scanline[Y]); var Mask := PByte(Alpha.AlphaScanline[Y]);
            for var X := 0 to Alpha.Width-1 do begin Row[X*3] := 160; Row[X*3+1] := Byte(X and 255); Row[X*3+2] := 240; Mask[X] := Byte((X+Y) and 255); end;
          end;
          Alpha.SaveToFile(TPath.Combine(ReferenceRoot,'owned-alpha.png'));
        finally Bitmap.Free; Alpha.Free; Jpeg.Free; Picture.Free; end;
        Reference.CharacterFile := TPath.Combine(ReferenceRoot,'owned-actor.rigm'); Reference.Characters[0].FileName := Reference.CharacterFile;
        for var Scene in Reference.Scenes do Scene.Image := TPath.Combine(ReferenceRoot,'owned-image.png');
        for var Cue in Reference.Cues do Cue.WaveFile := TPath.Combine(ReferenceRoot,'owned-audio.wav');
        var Json := Reference.Json;
        try TFile.WriteAllText(TPath.Combine(ReferenceRoot,'project.rigmovie'),Json.ToJSON,TEncoding.UTF8); finally Json.Free; end;
        var Audio := CachedMovieAudio(Reference,True);
        try
          for var I := 0 to 4 do begin
            if I=1 then Reference.Scenes[0].Image := TPath.Combine(ReferenceRoot,'owned-image.jpg');
            if I>=2 then Reference.Scenes[0].Image := TPath.Combine(ReferenceRoot,'owned-alpha.png');
            if I=3 then Reference.Scenes[0].Animation.AddPair('enter','fade');
            if I=4 then Reference.Scenes[0].Image := TPath.Combine(ReferenceRoot,'owned-image.jpg');
            // Keep the sample inside scene zero for the image/alpha/fade comparisons.
            B := RenderMovieFrame(Reference,nil,0.1+I*0.08,Audio);
            try SavePixels(B,TPath.Combine(ReferenceRoot,'new-'+I.ToString+'.bgra')); finally B.Free; end;
          end;
        finally Audio.Free; end;
      finally Reference.Free; end;
      // Changing duration to > 16 minutes must not allocate a full movie PCM mix.
      P.Scenes.Last.Padding := 500; P.Scenes[P.Scenes.Count-2].Padding := 500;
      A := PreviewMovieAudio(P,0.1);
      try Check((P.Duration>1000) and (Length(A.Samples)=25201),'long movie preview still contains one cue only'); finally A.Free; end;
      B := Frame(S,0.1); B.Free; P.Scenes.Last.Padding := 0; P.Scenes[P.Scenes.Count-2].Padding := 0;
      var After := P.Json;
      try Check(Before.ToJSON=After.ToJSON,'resolution and long movie previews preserve project data'); finally After.Free; end;
      // Effect edits and on-disk replacements invalidate the cue cache.
      var Old := PreviewMovieAudio(P,0.1); var Settings := ParseObject('{"Out: Use":1,"Out: Gain(dB)":-12}');
      try
        EditCueVoiceEffects(P,P.Cues[0].Id,Settings); A := PreviewMovieAudio(P,0.1);
        try Check(A.Envelope(0.1)<Old.Envelope(0.1),'effect edits invalidate preview PCM'); finally A.Free; end;
        Settings.Free; Settings := TJSONObject.Create; EditCueVoiceEffects(P,P.Cues[0].Id,Settings);
        var Silence := TRigmPcm.Create;
        try Silence.Rate := 48000; SetLength(Silence.Samples,24000); Silence.Save(P.Cues[0].WaveFile); finally Silence.Free; end;
        TFile.SetLastWriteTimeUtc(P.Cues[0].WaveFile,Now+1/24);
        A := PreviewMovieAudio(P,0.1);
        try Check((A.Envelope(0.1)=0) and (Old.Envelope(0.1)>0),'file replacement invalidates PCM while prior immutable result survives'); finally A.Free; end;
      finally Settings.Free; Old.Free; end;
      // A decoded image cache refreshes even when its path and project revision stay the same.
      var Bitmap := Vcl.Graphics.TBitmap.Create; var Png := TPngImage.Create;
      try
        Bitmap.SetSize(2048,1536); Bitmap.Canvas.Brush.Color := clRed; Bitmap.Canvas.FillRect(Rect(0,0,2048,1536));
        Png.Assign(Bitmap); Png.SaveToFile(P.Scenes[0].Image); TFile.SetLastWriteTimeUtc(P.Scenes[0].Image,Now+2/24);
        B := RenderComposition(P,0.1,nil);
        try Check(ColorToRGB(B.Canvas.Pixels[960,400])=ColorToRGB(clRed),'image replacement invalidates decoded cache'); finally B.Free; end;
        Bitmap.Canvas.Brush.Color := clBlue; Bitmap.Canvas.FillRect(Rect(0,0,2048,1536));
        Png.Assign(Bitmap); Png.SaveToFile(P.Scenes[0].Image); TFile.SetLastWriteTimeUtc(P.Scenes[0].Image,Now+3/24);
        B := Frame(S,0.1);
        try Check(ColorToRGB(B.Canvas.Pixels[480,200])=ColorToRGB(clBlue),'successive worker sees updated image pixels'); finally B.Free; end;
      finally Png.Free; Bitmap.Free; end;
      Sleep(1100); B := Frame(S,0.1); B.Free;
      var Status := S.Status;
      try Check(JB(JO(JO(Status,'workflow'),'results'),'previewCurrent'),'automatic preview periodically refreshes external material fingerprint'); finally Status.Free; end;
      var Image := P.Scenes[0].Image; P.Scenes[0].Image := TPath.Combine(Root,'missing-owned.png');
      var Failed := False;
      try B := RenderMoviePreview(P,nil,0.1,nil,960,540); B.Free; except on E: Exception do Failed := True; end;
      Check(Failed and (P.Width=1920) and (P.Height=1080),'failed preview restores output dimensions'); P.Scenes[0].Image := Image;
      var Args := TJSONObject.Create; Args.AddPair('path',TPath.Combine(Root,'explicit.png')); AddN(Args,'time',0.1);
      try var Reply := S.Execute('preview',Args); Reply.Free; finally Args.Free; end;
      var Started := GetTickCount64;
      while S.Busy do begin if GetTickCount64-Started>15000 then raise Exception.Create('Explicit preview timeout'); Sleep(1); end;
      S.Poll; B := S.TakeFrame;
      try Check((B<>nil) and (B.Width=1920) and (B.Height=1080),'explicit PNG preview retains full output resolution'); finally B.Free; end;
      Check(FileExists(TPath.Combine(Root,'explicit.png')),'explicit preview writes requested PNG');
      var Saved := S.Project.Clone; var History := TRigmAppSettings.Create(TPath.Combine(Root,'HistorySettings'));
      try
        SaveMovie(Saved,TPath.Combine(Root,'history-work.rigmovie'));
        History.RecordMovie(Saved,4.4,Saved.Cues[0].Id);
        var HistoryPath := TPath.Combine(History.Root,'settings.json'); var Bytes := TFile.ReadAllBytes(HistoryPath);
        History.RememberPosition(Saved,4.4,Saved.Cues[0].Id);
        var AfterBytes := TFile.ReadAllBytes(HistoryPath);
        Check((Length(Bytes)=Length(AfterBytes)) and CompareMem(@Bytes[0],@AfterBytes[0],Length(Bytes)),'unchanged resume position does not rewrite history');
        History.RecordMovie(Saved,1.2,Saved.Cues[1].Id); // another save/window changed the MRU
        History.RememberPosition(Saved,4.4,Saved.Cues[0].Id);
        var RecentAfterSave := History.Recent;
        try Check((Abs(JN(TJSONObject(RecentAfterSave[0]),'time')-4.4)<0.000001) and
          (JS(TJSONObject(RecentAfterSave[0]),'cueId')=Saved.Cues[0].Id),'position record refreshes after another save changed history');
        finally RecentAfterSave.Free; end;
        var CueId: string; var Time := History.ResumeMovie(Saved,CueId);
        Check((Time=0) and (CueId=Saved.Cues[0].Id),'opening work retains existing start-from-beginning policy');
        Saved.Cues[0].Subtitle := '保存していない変更'; Saved.Changed;
        History.RememberPosition(Saved,6.6,Saved.Cues[2].Id);
        var Recent := History.Recent;
        try Check(Abs(JN(TJSONObject(Recent[0]),'time')-4.4)<0.000001,'unsaved content cannot overwrite saved resume position'); finally Recent.Free; end;
      finally History.Free; Saved.Free; end;
    finally Before.Free; end;
  finally S.Free; end;
end;
procedure Pump(Milliseconds: Cardinal);
begin
  var Started := GetTickCount64;
  while GetTickCount64-Started<Milliseconds do begin Application.ProcessMessages; Sleep(1); end;
end;
procedure NativePlayback(Standalone: Boolean);
begin
  var S := TRigmMovieSession.Create; var Host: TForm := nil; var Editor: TRigmMovieEditorFrame := nil;
  var Context := 'embedded'; if Standalone then Context := 'standalone';
  try
    var Project := Fixture; Project.EngineUrl := 'http://127.0.0.1:1';
    for var C in Project.Cues do C.AudioKey := Project.AudioFingerprint(C);
    // Silent owned PCM prevents test playback from producing speech or tones.
    var Audio := TRigmPcm.Create;
    try Audio.Rate := 48000; SetLength(Audio.Samples,24000); Audio.Save(Project.Cues[0].WaveFile); finally Audio.Free; end;
    TFile.SetLastWriteTimeUtc(Project.Cues[0].WaveFile,Now+4/24); S.SetProject(Project);
    if Standalone then Host := TRigmMovieForm.CreateForSession(nil,S)
    else begin Host := TForm.CreateNew(nil); Editor := TRigmMovieEditorFrame.CreateForSession(Host,S,True); end;
    Host.SetBounds(0,0,1440,900); ShowWindow(Host.Handle,SW_SHOWNOACTIVATE); Host.Visible := True;
    // The first HTTP diagnostics can finish asynchronously. Measure idle only
    // after its legitimate transition to a final result has reached the UI.
    var DiagnosticStarted := GetTickCount64;
    repeat
      Pump(50); var Args := TJSONObject.Create; Args.AddPair('scope','diagnostics');
      var Done := False;
      try
        var Job := S.Execute('job-status',Args);
        try Done := (JS(Job,'state')<>'none') and JB(Job,'done'); finally Job.Free; end;
      finally Args.Free; end;
      if Done then Break;
      if GetTickCount64-DiagnosticStarted>15000 then raise Exception.Create(Context+' diagnostics timeout');
    until False;
    Pump(1200);
    var ViewCount: Integer; var StaticCount: Integer; var Frames: UInt64;
    if Standalone then begin ViewCount := TRigmMovieForm(Host).ViewRefreshCount; StaticCount := TRigmMovieForm(Host).StaticUiUpdates; Frames := TRigmMovieForm(Host).PreviewControl.FrameCount; end
    else begin ViewCount := Editor.ViewRefreshCount; StaticCount := Editor.StaticUiUpdates; Frames := Editor.PreviewControl.FrameCount; end;
    Pump(1200);
    if Standalone then begin
      Check(TRigmMovieForm(Host).ViewRefreshCount=ViewCount,Context+' idle does not rebuild editor');
      Check(TRigmMovieForm(Host).StaticUiUpdates=StaticCount,Context+' idle does not rebuild preparation');
      TRigmMovieForm(Host).InvokeAction(12);
    end else begin
      Check(Editor.ViewRefreshCount=ViewCount,Context+' idle does not rebuild editor');
      Check(Editor.StaticUiUpdates=StaticCount,Context+' idle does not rebuild preparation'); Editor.InvokeAction(12);
    end;
    Pump(2200);
    Check(S.Playing and (S.Time>1),Context+' playback clock advances with prepared silent audio');
    if Standalone then begin
      Check(TRigmMovieForm(Host).PreviewControl.FrameCount>=Frames+5,Context+' playback publishes changing preview frames');
      Check(TRigmMovieForm(Host).PreviewControl.Frame.Height<=720,Context+' UI requests bounded preview size');
      TRigmMovieForm(Host).InvokeAction(12);
    end else begin
      Check(Editor.PreviewControl.FrameCount>=Frames+5,Context+' playback publishes changing preview frames');
      Check(Editor.PreviewControl.Frame.Height<=720,Context+' UI requests bounded preview size'); Editor.InvokeAction(12);
    end;
    var Time := S.Time; Pump(300);
    Check(not S.Playing and (Abs(S.Time-Time)<0.001),Context+' stop freezes playback clock');
    S.SeekTo(12.3); Check(Abs(S.Time-12.3)<0.000001,Context+' stopped playback can seek');
    Check((S.Project.Width=1920) and (S.Project.Height=1080),Context+' playback keeps export resolution');
  finally Host.Free; S.Free; end;
end;
{$ENDIF}
function Frame(Session: TRigmMovieSession; Seconds: Double): Vcl.Graphics.TBitmap;
begin
  {$IFDEF PREVIEW_OPTIMIZED}
  var Reply := Session.PreviewFrame(Seconds,960,540);
  {$ELSE}
  var Reply := Session.PreviewFrame(Seconds);
  {$ENDIF}
  Reply.Free;
  var Start := GetTickCount64;
  while Session.Busy do begin
    if GetTickCount64-Start>15000 then raise Exception.Create('Owned preview timeout');
    Sleep(1);
  end;
  Session.Poll; Result := Session.TakeFrame;
  if Result=nil then raise Exception.Create('No preview frame');
end;
procedure Benchmark;
begin
  var S := TRigmMovieSession.Create;
  try
    S.SetProject(Fixture); var Before := S.Project.Json;
    try
      var B := Frame(S,0.1); B.Free; // caches warmed equally; initial work is excluded
      var Clock := TStopwatch.StartNew;
      for var I := 1 to 100 do begin
        {$IFDEF PREVIEW_OPTIMIZED}
        S.SeekTo(I*0.02);
        {$ELSE}
        var A := TJSONObject.Create; AddN(A,'time',I*0.02);
        try var O := S.Execute('seek',A); O.Free; finally A.Free; end;
        {$ENDIF}
      end;
      Clock.Stop; AddN(Report,'seek100Ms',Clock.Elapsed.TotalMilliseconds);
      Clock := TStopwatch.StartNew;
      for var I := 1 to 100 do begin
        {$IFDEF PREVIEW_OPTIMIZED}
        var O := S.TransportStatus;
        {$ELSE}
        var O := S.Status;
        {$ENDIF}
        O.Free;
      end;
      Clock.Stop; AddN(Report,'status100Ms',Clock.Elapsed.TotalMilliseconds);
      Clock := TStopwatch.StartNew;
      for var I := 0 to 23 do begin B := Frame(S,0.1+I*0.1); B.Free; end;
      Clock.Stop; AddN(Report,'preview24Ms',Clock.Elapsed.TotalMilliseconds);
      var After := S.Project.Json;
      try Check(Before.ToJSON=After.ToJSON,'playback timing and previews preserve authored project'); finally After.Free; end;
      Check(Abs(S.Time-2.4)<0.00001,'preview keeps requested timeline time');
      Check((S.Project.Width=1920) and (S.Project.Height=1080),'output resolution remains Full HD');
    finally Before.Free; end;
  finally S.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1); Checks := TJSONArray.Create; Report := TJSONObject.Create;
  try
    if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh owned root required');
    Benchmark;
    {$IFDEF PREVIEW_OPTIMIZED}
    Regression; NativePlayback(False); NativePlayback(True);
    {$ENDIF}
  except on E: Exception do begin Error := E.ClassName+': '+E.Message; ExitCode := 1; end; end;
  Report.AddPair('checks',Checks); Report.AddPair('error',Error);
  TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  Writeln(Report.ToJSON); Report.Free;
end.
