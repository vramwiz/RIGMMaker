program BundledMp4Check;
{$APPTYPE CONSOLE}
// 専用PCMと色付きフレームを同梱DLLで出力・全フレーム復号する。通常アプリと実作品は使わない。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Types,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage, RigmFFmpegApi, RigmFFmpegTypes, RigmFFmpegWriter,
  RigmMovieModel, RigmMovieComposition, RigmMovieAudio, RigmMovieMp4, RigmMovieJobs,
  RigmMoviePreparation, RigmMovieSession, RigmJson, RigmScriptScenesModel,
  RigmScriptCastingModel, RigmScriptReviewModel, RigmScriptTextModel;
type
  TDecoded = record
    VideoFrames,AudioSamples: Integer;
    Width,Height: Integer;
    TopY,BottomY: Byte;
    Peak: Single;
    AudioDuration: Double;
  end;
var Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); Writeln('PASS ',Message); end;
function StreamAt(Context: PAVFormatContext; Index: Integer): PAVStream;
begin Result := PAVStream(PPointer(NativeUInt(Context^.streams)+NativeUInt(Index)*SizeOf(Pointer))^); end;
procedure Receive(Api: TRigmFFmpegApi; Context: PAVCodecContext; Frame: PAVFrame; Video: Boolean; var Decoded: TDecoded);
begin
  while True do begin
    var Code := Api.avcodec_receive_frame(Context,Frame);
    if (Code=AVERROR_EAGAIN) or (Code=AVERROR_EOF) then Exit;
    Api.Check(Code,'decode frame');
    if Video then begin
      Inc(Decoded.VideoFrames); Decoded.Width := Frame^.width; Decoded.Height := Frame^.height;
      if Decoded.VideoFrames=1 then begin
        Decoded.TopY := PByte(NativeUInt(Frame^.data[0])+NativeUInt(Frame^.linesize[0])*4+4)^;
        Decoded.BottomY := PByte(NativeUInt(Frame^.data[0])+NativeUInt(Frame^.linesize[0])*(Frame^.height-5)+4)^;
      end;
    end else begin
      Inc(Decoded.AudioSamples,Frame^.nb_samples);
      for var I := 0 to Frame^.nb_samples-1 do
        Decoded.Peak := Max(Decoded.Peak,Abs(PSingle(NativeUInt(Frame^.data[0])+NativeUInt(I)*SizeOf(Single))^));
    end;
  end;
end;
function Decode(const Path: string): TDecoded;
var Format: PAVFormatContext; Packet: PAVPacket; Frame: PAVFrame;
  Video,Audio: PAVCodecContext; VideoIndex,AudioIndex: Integer;
begin
  Result := Default(TDecoded); Format := nil; Packet := nil; Frame := nil; Video := nil; Audio := nil;
  var Api := TRigmFFmpegApi.Create;
  try
    var Name := UTF8String(Path); Api.Check(Api.avformat_open_input(@Format,PAnsiChar(Name),nil,nil),'open MP4');
    Api.Check(Api.avformat_find_stream_info(Format,nil),'find streams');
    Check(Format^.nb_streams=2,'MP4 contains video and audio'); VideoIndex := -1; AudioIndex := -1;
    for var I := 0 to Integer(Format^.nb_streams)-1 do begin
      var Stream := StreamAt(Format,I); var Codec := Api.avcodec_find_decoder(Stream^.codecpar^.codec_id);
      if Stream^.codecpar^.codec_type=AVMEDIA_TYPE_VIDEO then begin
        Check(Stream^.codecpar^.codec_id=27,'video codec is H.264'); VideoIndex := I;
        Video := Api.avcodec_alloc_context3(Codec); Api.Check(Api.avcodec_parameters_to_context(Video,Stream^.codecpar),'video parameters');
        Api.Check(Api.avcodec_open2(Video,Codec,nil),'video decoder');
      end else if Stream^.codecpar^.codec_type=AVMEDIA_TYPE_AUDIO then begin
        Check(Stream^.codecpar^.codec_id=86018,'audio codec is AAC'); AudioIndex := I;
        Check((Stream^.codecpar^.sample_rate=48000) and (Stream^.codecpar^.ch_layout.nb_channels=1),'AAC is 48000 Hz mono');
        Result.AudioDuration := Stream^.duration*Stream^.time_base.num/Stream^.time_base.den;
        Audio := Api.avcodec_alloc_context3(Codec); Api.Check(Api.avcodec_parameters_to_context(Audio,Stream^.codecpar),'audio parameters');
        Api.Check(Api.avcodec_open2(Audio,Codec,nil),'audio decoder');
      end;
    end;
    Check((Video<>nil) and (Audio<>nil),'both decoders opened');
    Packet := Api.av_packet_alloc(); Frame := Api.av_frame_alloc();
    while Api.av_read_frame(Format,Packet)>=0 do begin
      if Packet^.stream_index=VideoIndex then begin Api.Check(Api.avcodec_send_packet(Video,Packet),'video packet'); Receive(Api,Video,Frame,True,Result); end;
      if Packet^.stream_index=AudioIndex then begin Api.Check(Api.avcodec_send_packet(Audio,Packet),'audio packet'); Receive(Api,Audio,Frame,False,Result); end;
      Api.av_packet_unref(Packet);
    end;
    Api.Check(Api.avcodec_send_packet(Video,nil),'flush decoder'); Receive(Api,Video,Frame,True,Result);
    Api.Check(Api.avcodec_send_packet(Audio,nil),'flush audio decoder'); Receive(Api,Audio,Frame,False,Result);
  finally
    if Frame<>nil then Api.av_frame_free(@Frame); if Packet<>nil then Api.av_packet_free(@Packet);
    if Video<>nil then Api.avcodec_free_context(@Video); if Audio<>nil then Api.avcodec_free_context(@Audio);
    if Format<>nil then Api.avformat_close_input(@Format); Api.Free;
  end;
end;
function FixtureAudio: TRigmPcm;
begin
  Result := TRigmPcm.Create; Result.Rate := 48000; SetLength(Result.Samples,48013);
  for var I := 0 to High(Result.Samples) do Result.Samples[I] := Round(Sin(I*2*Pi*440/48000)*12000);
end;
procedure LowLevel;
begin
  var Path := TPath.Combine(Root,'日本語 folder\映像 と 音声.mp4'); ForceDirectories(ExtractFilePath(Path));
  var Audio := FixtureAudio; var Bitmap := Vcl.Graphics.TBitmap.Create;
  var Mask := GetExceptionMask;
  try
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(160,120);
    Bitmap.Canvas.Brush.Color := clRed; Bitmap.Canvas.FillRect(Rect(0,0,160,60));
    Bitmap.Canvas.Brush.Color := clBlue; Bitmap.Canvas.FillRect(Rect(0,60,160,120));
    for var Profile in ['fast','balanced','quality'] do begin
      var Target := Path; if Profile<>'fast' then Target := ChangeFileExt(Path,'-'+Profile+'.mp4');
      var Writer := TRigmFFmpegWriter.Create(Target,160,120,15,48000,Profile);
      try
        var Position := 0;
        for var I := 0 to 14 do begin
          Writer.AddVideo(Bitmap);
          while (Position+Writer.AudioFrameSamples<=Length(Audio.Samples)) and (Position<(I+1)*48000 div 15) do begin
            Writer.AddAudio(Audio.Samples,Position,Writer.AudioFrameSamples); Inc(Position,Writer.AudioFrameSamples);
          end;
        end;
        if Position<Length(Audio.Samples) then Writer.AddAudio(Audio.Samples,Position,Length(Audio.Samples)-Position);
        Writer.Finish;
      finally Writer.Free; end;
      Check(GetExceptionMask=Mask,'encoder restores floating-point mask '+Profile);
      var Decoded := Decode(Target);
      Check((Decoded.VideoFrames=15) and (Decoded.Width=160) and (Decoded.Height=120),'all video frames decoded '+Profile);
      Check(Decoded.TopY>Decoded.BottomY+15,'top and bottom preserve orientation '+Profile);
      Check((Decoded.AudioSamples>=48013) and (Decoded.Peak>0.2),'audio contains nonzero fixture '+Profile);
      Check(Abs(Decoded.AudioDuration-48013/48000)<0.03,'audio duration retains final partial frame '+Profile);
    end;
    var Before := TFile.ReadAllBytes(Path); var Rejected := False;
    try var Writer := TRigmFFmpegWriter.Create(Path,160,120,15,48000,'fast'); Writer.Free; except on E: Exception do Rejected := True; end;
    var After := TFile.ReadAllBytes(Path);
    Check(Rejected and (Length(Before)=Length(After)) and CompareMem(@Before[0],@After[0],Length(Before)),'existing MP4 is preserved');
    var Partial := TPath.Combine(Root,'cancelled-writer.mp4'); var Writer := TRigmFFmpegWriter.Create(Partial,160,120,15,48000,'fast');
    Writer.AddVideo(Bitmap); Writer.Free; Check(not FileExists(Partial),'unfinished writer removes only its own file');
  finally Bitmap.Free; Audio.Free; end;
end;
function ProjectFixture: TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create; Result.Width := 640; Result.Height := 360; Result.Fps := 15; Result.EncodeProfile := 'fast';
  var Cue := TRigmMovieCue.Create; Result.Cues.Add(Cue); Cue.SpeakerId := Result.Speakers[0].Id;
  Cue.Text := 'MP4の独立出力を確認します。'; Cue.Subtitle := Cue.Text; Cue.Pause := 0;
  var Audio := FixtureAudio;
  try Cue.AudioSeconds := Audio.Duration; Cue.WaveFile := TPath.Combine(Root,'fixture.wav'); Audio.Save(Cue.WaveFile); finally Audio.Free; end;
  Cue.AudioKey := Result.AudioFingerprint(Cue); Result.Validate;
end;
procedure Integrated;
begin
  var Project := ProjectFixture;
  try
    var WaveBefore := TFile.ReadAllBytes(Project.Cues[0].WaveFile);
    Check(Project.FfmpegExe='','fixture has no external encoder path');
    var Target := TPath.Combine(Root,'project-output.mp4');
    var Diagnostics := TJSONObject.Create; var DiagnosticJob := TJSONObject.Create;
    try
      var Preparation := MoviePreparation(Project,Diagnostics,DiagnosticJob,Target);
      try Check(JB(Preparation,'ffmpegConfigured'),'preparation accepts bundled DLLs');
        Check(JS(JO(Preparation,'estimate'),'backend')='ffmpeg-shared-h264-aac','preparation identifies shared DLL backend');
      finally Preparation.Free; end;
    finally DiagnosticJob.Free; Diagnostics.Free; end;
    var Before := Project.Json;
    try
      var Job := TRigmMovieJob.Create(Project,'export',Target,0);
      try
        Job.Start; Job.WaitFor; var Status := Job.Status;
        try
          TFile.WriteAllText(TPath.Combine(Root,'export-job.json'),Status.ToJSON,TEncoding.UTF8);
          Check(JS(Status,'state')='succeeded','export job succeeds: '+JS(Status,'error'));
          Check(JS(Status,'exportBackend')='ffmpeg-shared-h264-aac','job reports DLL backend');
          Check(JB(Status,'encoderExited') and (JI(Status,'encoderProcessId')=0),'completion requires released native writer');
        finally Status.Free; end;
      finally Job.Free; end;
      var After := Project.Json; try Check(Before.ToJSON=After.ToJSON,'export preserves source project'); finally After.Free; end;
    finally Before.Free; end;
    var Decoded := Decode(Target);
    Writeln('Project duration=',FloatToStr(Project.Duration,TFormatSettings.Invariant),' fps=',Project.Fps,' decoded=',Decoded.VideoFrames,' expected=',Ceil(Project.Duration*Project.Fps));
    Check(Decoded.VideoFrames=Ceil(Project.Duration*Project.Fps),'project output decodes every rendered frame');
    var CancelTarget := TPath.Combine(Root,'cancelled-stream.mp4'); var Cancel := False; var Rejected := False;
    var Audio := FixtureAudio;
    try
      try
        StreamMovieMp4(Project,nil,Audio,CancelTarget,function: Boolean begin Result := Cancel; end,
          procedure(Current,Total: Integer; Staging: UInt64) begin Cancel := Current>=2; end,nil,nil);
      except on E: EAbort do Rejected := True; end;
    finally Audio.Free; end;
    Check(Rejected and not FileExists(CancelTarget),'stream cancellation removes partial MP4');
    // Pauseだけを延ばし、元WAVの長さを偽らずに非同期出力の取消を試す。
    Project.Cues[0].Pause := 30;
    var CancelJobTarget := TPath.Combine(Root,'cancelled-job.mp4');
    var Job := TRigmMovieJob.Create(Project,'export',CancelJobTarget,0);
    try
      Job.Start; var Deadline := GetTickCount64+10000; var Rendering := False;
      repeat
        var Status := Job.Status;
        try Rendering := (JS(Status,'phase')='render') and (JI(Status,'phaseCompleted')>=1);
          if JB(Status,'done') then Break;
        finally Status.Free; end;
        if not Rendering then Sleep(10);
      until Rendering or (GetTickCount64>=Deadline);
      Job.Cancel; Job.WaitFor;
      var Status := Job.Status;
      try Check(Rendering and (JS(Status,'state')='cancelled') and not FileExists(CancelJobTarget),'asynchronous export cancellation preserves final target');
      finally Status.Free; end;
    finally Job.Free; end;
    var WaveAfter := TFile.ReadAllBytes(Project.Cues[0].WaveFile);
    Check((Length(WaveBefore)=Length(WaveAfter)) and CompareMem(@WaveBefore[0],@WaveAfter[0],Length(WaveBefore)),'encoding and cancellation preserve source WAV');
    Check(Length(TDirectory.GetFiles(Root,'*.part*',TSearchOption.soAllDirectories))=0,'no abandoned part files');
    Check(MovieMp4Available('Z:\missing\ffmpeg.exe'),'stale optional path falls back to bundled DLLs');
  finally Project.Free; end;
end;
procedure MissingRuntime;
begin
  Check(not BundledFFmpegAvailable and not MovieMp4Available(''),'missing runtime cannot fall back to working directory');
  var Mask := GetExceptionMask; var Rejected := False;
  try var Api := TRigmFFmpegApi.Create; Api.Free;
  except on E: Exception do Rejected := Pos(BundledFFmpegDirectory,E.Message)>0; end;
  Check(Rejected,'missing DLL error identifies executable-relative directory');
  Check(GetExceptionMask=Mask,'failed DLL load restores floating-point mask');
end;
procedure WaitExport(Session: TRigmMovieSession);
begin
  var Deadline := GetTickCount64+15000;
  repeat
    Session.Poll;
    if not Session.Busy then Exit;
    Sleep(10);
  until GetTickCount64>=Deadline;
  raise Exception.Create('Owned export timed out');
end;
function SessionExport(Session: TRigmMovieSession; const Path: string; Overwrite: Boolean=False): TJSONObject;
begin
  var Args := TJSONObject.Create;
  try if Path<>'' then Args.AddPair('path',Path); AddB(Args,'overwrite',Overwrite); Result := Session.Execute('export',Args);
  finally Args.Free; end;
end;
procedure OverwriteExport;
begin
  var Target := TPath.Combine(Root,'上書き 確認.mp4'); var Original := '既存の動画を保持';
  TFile.WriteAllText(Target,Original,TEncoding.UTF8);
  var Session := TRigmMovieSession.Create;
  try
    Session.SetProject(ProjectFixture);
    var Reply := SessionExport(Session,Target,True); Reply.Free; WaitExport(Session);
    var Args := TJSONObject.Create;
    try Reply := Session.Execute('job-status',Args);
      try Check(JS(Reply,'state')='succeeded','explicitly confirmed overwrite succeeds'); finally Reply.Free; end;
    finally Args.Free; end;
    var Decoded := Decode(Target);
    Check(Decoded.VideoFrames=Ceil(Session.Project.Duration*Session.Project.Fps),'overwritten target contains a complete decodable movie');
    TFile.WriteAllText(Target,Original,TEncoding.UTF8);
    Session.Project.Cues[0].Pause := 30;
    Reply := SessionExport(Session,Target,True); Reply.Free;
    var Deadline := GetTickCount64+10000; var Rendering := False;
    repeat
      Args := TJSONObject.Create;
      try Reply := Session.Execute('job-status',Args);
        try Rendering := (JS(Reply,'phase')='render') and (JI(Reply,'phaseCompleted')>=1);
          if JB(Reply,'done') then Break;
        finally Reply.Free; end;
      finally Args.Free; end;
      if not Rendering then Sleep(10);
    until Rendering or (GetTickCount64>Deadline);
    Args := TJSONObject.Create;
    try Reply := Session.Execute('job-cancel',Args); Reply.Free; finally Args.Free; end;
    WaitExport(Session);
    Check(Rendering and (TFile.ReadAllText(Target,TEncoding.UTF8)=Original),'cancelling an overwrite preserves the entire previous target');
    Session.Project.Cues[0].Pause := 0;
    var Lock := CreateFile(PChar(Target),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
    if Lock=INVALID_HANDLE_VALUE then RaiseLastOSError;
    try
      Reply := SessionExport(Session,Target,True); Reply.Free; WaitExport(Session);
      Args := TJSONObject.Create;
      try Reply := Session.Execute('job-status',Args);
        try Check(JS(Reply,'state')='failed','locked target reports replacement failure'); finally Reply.Free; end;
      finally Args.Free; end;
    finally CloseHandle(Lock); end;
    Check(TFile.ReadAllText(Target,TEncoding.UTF8)=Original,'replacement failure preserves the entire previous target');
    Reply := Session.PreviewFrame(0); Reply.Free;
    Args := TJSONObject.Create;
    try Reply := Session.Execute('job-retry',Args); Reply.Free; finally Args.Free; end;
    WaitExport(Session);
    Args := TJSONObject.Create;
    try Reply := Session.Execute('job-status',Args);
      try Check(JS(Reply,'state')='succeeded','retry retains confirmed overwrite permission through automatic preview'); finally Reply.Free; end;
    finally Args.Free; end;
    Check(Length(TDirectory.GetFiles(Root,'*.part*',TSearchOption.soAllDirectories))=0,'overwrite cleanup removes only owned staging files');
  finally Session.Free; end;
end;
procedure ConfirmOwnedExportFixture(Project: TRigmMovieProject);
begin
  // 出力先保存の専用fixtureにも、現在の必須サムネイル条件を満たす素材を用意する。
  // 実作品の確定・解除には使用しない。
  PrepareScriptText(Project);
  if Project.Scenes.Count=0 then begin
    var S := TRigmMovieScene.Create; S.Title := ''; S.DisplayMode := 'none';
    Project.Scenes.Add(S); Project.Cues[0].Scene := S.Id;
  end;
  if Project.ScriptWizard.GetValue('casting')=nil then
    Project.ScriptWizard.AddPair('casting',ParseObject('{"state":"requested","roles":[],"rows":[]}'));
  var Cast := JO(Project.ScriptWizard,'casting');
  Cast.RemovePair('sourceFingerprint').Free; Cast.AddPair('sourceFingerprint',ScriptFingerprint(Project));
  Cast.RemovePair('fingerprint').Free; Cast.AddPair('fingerprint',CastingFingerprint(Project));
  PrepareScriptScenes(Project,False);
  SetScriptSceneApproved(Project,Project.Scenes[0].Id,True);
  if Project.Thumbnail.Image='' then begin
    var Path := TPath.Combine(Root,'owned-resume-thumbnail.png');
    var B := TBitmap.Create; var PNG := TPngImage.Create;
    try B.SetSize(160,90); B.Canvas.Brush.Color := clBlue; B.Canvas.FillRect(Rect(0,0,160,90));
      PNG.Assign(B); PNG.SaveToFile(Path);
    finally PNG.Free; B.Free; end;
    Project.Thumbnail.Image := Path;
  end;
  SetScriptSceneApproved(Project,'thumbnail',False);
  SetScriptSceneApproved(Project,'thumbnail',True);
end;
procedure ExportResume;
begin
  var FileName := TPath.Combine(Root,'台本 再開\project.rigmovie');
  var Project := ProjectFixture;
  try
    Project.ScriptWizard := ParseObject('{"format":"RIGMMaker.ScriptWizard","schemaVersion":1,"stage":"editor","titleInput":"元の台本","draftSentinel":"入力を保持"}');
    ConfirmOwnedExportFixture(Project);
    SaveMovie(Project,FileName);
    Check(Project.OutputTarget='','saving an unset output does not invent a filename');
    Project.OutputTarget := 'Exports\旧 出力.mp4';
    var Expected := ResolveMoviePath(FileName,Project.OutputTarget); SaveMovie(Project,FileName);
    var Json := ParseObject(TFile.ReadAllText(FileName,TEncoding.UTF8));
    try Check(JS(Json,'outputTarget')=Expected,'saved JSON records full output path'); finally Json.Free; end;
    SaveMovie(Project,TPath.Combine(Root,'別の保存先\copy.rigmovie'));
    Check(Project.OutputTarget=Expected,'save as retains original absolute output directory');
    Json := Project.Json;
    try Json.RemovePair('outputTarget').Free; Json.AddPair('outputTarget','Exports\旧形式.mp4');
      var Legacy := TPath.Combine(Root,'別の保存先\legacy.rigmovie'); TFile.WriteAllText(Legacy,Json.ToJSON,TEncoding.UTF8);
      var Loaded := LoadMovie(Legacy);
      try Check(Loaded.OutputTarget=ResolveMoviePath(Legacy,'Exports\旧形式.mp4'),'old relative output resolves beside its project'); finally Loaded.Free; end;
    finally Json.Free; end;
  finally Project.Free; end;
  var Session := TRigmMovieSession.Create;
  try
    Session.SetProject(LoadMovie(FileName));
    var Args := TJSONObject.Create; Args.AddPair('projectId',Session.Project.Id); Args.AddPair('revision',TJSONNumber.Create(Session.Project.Revision));
    try Args.AddPair('title','出力時に保存する台本'); var Reply := Session.Execute('update-project',Args); Reply.Free;
    finally Args.Free; end;
    ConfirmOwnedExportFixture(Session.Project);
    var Target := ResolveMoviePath(FileName,'Exports\日本語 と 空白\再開用 動画.mp4');
    var Reply := SessionExport(Session,'Exports\日本語 と 空白\再開用 動画.mp4'); Reply.Free;
    Check(Session.Project.OutputTarget=Target,'export adopts project-relative target as full path');
    var Saved := LoadMovie(FileName);
    try
      Check(Saved.OutputTarget=Target,'target is persisted before export completes');
      Check((Saved.Title='出力時に保存する台本') and (JS(Saved.ScriptWizard,'draftSentinel')='入力を保持'),'export saves applied edits and preserves script metadata');
    finally Saved.Free; end;
    WaitExport(Session); Args := TJSONObject.Create;
    try Reply := Session.Execute('job-status',Args);
      try Check((JS(Reply,'state')='succeeded') and FileExists(Target),'remembered target produces a real MP4');
      finally Reply.Free; end;
    finally Args.Free; end;
    var Reopened := TRigmMovieSession.Create;
    try
      Args := TJSONObject.Create; Args.AddPair('projectId',Reopened.Project.Id); Args.AddPair('revision',TJSONNumber.Create(Reopened.Project.Revision));
      try Args.AddPair('path',FileName); Reply := Reopened.Execute('open',Args); Reply.Free;
      finally Args.Free; end;
      Check(Reopened.Project.OutputTarget=Target,'new session restores target through normal open command');
      var Before := TFile.ReadAllBytes(FileName); var VideoBefore := TFile.ReadAllBytes(Target); var Rejected := False;
      try Reply := SessionExport(Reopened,''); Reply.Free; except on E: Exception do Rejected := True; end;
      var After := TFile.ReadAllBytes(FileName); var VideoAfter := TFile.ReadAllBytes(Target);
      Check(Rejected and not Reopened.Busy and (Length(Before)=Length(After)) and (Length(VideoBefore)=Length(VideoAfter)) and CompareMem(@Before[0],@After[0],Length(Before)) and
        CompareMem(@VideoBefore[0],@VideoAfter[0],Length(VideoBefore)),'restored existing MP4 and project are protected from overwrite');
      Args := TJSONObject.Create; Args.AddPair('projectId',Reopened.Project.Id); Args.AddPair('revision',TJSONNumber.Create(Reopened.Project.Revision));
      try Reply := Reopened.Execute('edit-begin',Args); Reply.Free; finally Args.Free; end;
      Rejected := False;
      try Reply := SessionExport(Reopened,ResolveMoviePath(FileName,'Exports\ロック中.mp4')); Reply.Free;
      except on E: Exception do Rejected := True; end;
      After := TFile.ReadAllBytes(FileName);
      Check(Rejected and not Reopened.Busy and (Length(Before)=Length(After)) and CompareMem(@Before[0],@After[0],Length(Before)),
        'edit lock prevents unauthorized automatic project save');
      Args := TJSONObject.Create; Args.AddPair('manual',TJSONBool.Create(True));
      try Reply := Reopened.Execute('edit-release',Args); Reply.Free; finally Args.Free; end;
      // 台本を他者が開いている場合、原子保存が失敗しても元ファイルを保持して出力を始めない。
      var Lock := CreateFile(PChar(FileName),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
      if Lock=INVALID_HANDLE_VALUE then RaiseLastOSError;
      var FailedTarget := ResolveMoviePath(FileName,'Exports\保存失敗.mp4'); Rejected := False;
      try
        try Reply := SessionExport(Reopened,FailedTarget); Reply.Free; except on E: Exception do Rejected := True; end;
      finally CloseHandle(Lock); end;
      After := TFile.ReadAllBytes(FileName);
      Check(Rejected and not Reopened.Busy and not FileExists(FailedTarget) and
        (Length(Before)=Length(After)) and CompareMem(@Before[0],@After[0],Length(Before)),'save failure preserves original project and starts no export');
      Check(Length(TDirectory.GetFiles(ExtractFilePath(FileName),'*.tmp',TSearchOption.soAllDirectories))=0,'failed automatic save removes temporary JSON');
    finally Reopened.Free; end;
  finally Session.Free; end;
end;
begin
  Root := ParamStr(1); Checks := TJSONArray.Create;
  try
    if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh output required');
    if ParamStr(2)='--missing-runtime' then MissingRuntime
    else begin Check(BundledFFmpegAvailable,'runtime resolves beside relocated EXE'); LowLevel; Integrated; ExportResume; OverwriteExport; end;
  except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  var Result := TJSONObject.Create;
  try Result.AddPair('checks',Checks); Result.AddPair('error',Error); TFile.WriteAllText(TPath.Combine(Root,'result.json'),Result.ToJSON,TEncoding.UTF8);
  finally Result.Free; end;
end.
