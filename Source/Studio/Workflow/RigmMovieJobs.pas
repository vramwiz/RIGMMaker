// 作品のスナップショットで音声・描画・出力などを非同期実行する。進捗と結果の公開を担当する。
unit RigmMovieJobs;

interface
uses System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient, Vcl.Graphics, RigmMovieModel;

type
  TRigmMovieJob = class(TThread)
  private
    FLock: TObject;
    FDone, FCancel, FCancelCallMs, FCancelWorkerMs: Integer;
    FCancelAt: UInt64;
    FState, FError: string;
    FProgress, FTotal: Integer;
    FProject: TRigmMovieProject;
    FFrame: TBitmap;
    FKind, FOutput, FCatalog: string;
    FTarget: string;
    FTime: Double;
    FStarted,FPhaseStarted,FFinished: UInt64;
    FPhase,FExportBackend: string;
    FPhaseCompleted,FPhaseTotal: Double;
    FEncoderPrivate,FEncoderWorking,FStagingPeak: UInt64;
    FEncoderPid: Cardinal;
    FEncoderExited: Boolean;
    FRequest: IHTTPRequest;
    FProductionOptions: TJSONObject;
    FProductionReport: string;
    procedure RequestChanged(Request: IHTTPRequest);
    procedure Report(Current,Total: Integer);
    procedure SetPhase(const Name: string; Total: Double);
    procedure CheckCancel;
    procedure GenerateAudio;
    procedure ExportVideo;
    procedure LoadCatalog;
    procedure Preview;
    procedure PlaybackAudio;
    procedure ActorAssets;
    procedure Waveform;
    procedure Diagnostics;
    procedure Produce;
    procedure PublishProduction(Report: TJSONObject);
    function Cancelled: Boolean;
  protected
    procedure Execute; override;
  public
    Id: string;
    constructor Create(Project: TRigmMovieProject; const Kind,Output: string; Seconds: Double;
      Options: TJSONObject = nil);
    destructor Destroy; override;
    procedure Cancel;
    function Done: Boolean;
    function Status: TJSONObject;
    function TakeFrame: TBitmap;
    property Project: TRigmMovieProject read FProject;
    property Kind: string read FKind;
    property Catalog: string read FCatalog;
    property Output: string read FOutput;
    property Seconds: Double read FTime;
  end;

implementation
uses System.IOUtils, System.Math, System.SyncObjs, Winapi.Windows, Winapi.ActiveX,
  Vcl.Imaging.pngimage, RigmModel, RigmJson, RigmSample, RigmStorage,
  RigmMovieAudio, RigmMovieRendering, RigmMovieAvi, RigmMovieMp4, RigmMovieActing, RigmMovieOutput,
  SerifVoicevoxApi, SerifVoicevoxSpeakerCatalog, SerifVoicevoxAudioSettings, RigmVoicevoxConfig,
  RigmMoviePreparation, RigmMovieProduction, RigmMovieCompositor, RigmCharacterCatalog;

constructor TRigmMovieJob.Create(Project: TRigmMovieProject; const Kind,Output: string; Seconds: Double;
  Options: TJSONObject);
begin
  inherited Create(True); FreeOnTerminate := False; FLock := TObject.Create;
  FProject := Project.Clone; FKind := Kind; FOutput := Output; FTime := Seconds;
  if Options<>nil then FProductionOptions := Options.Clone as TJSONObject
  else FProductionOptions := TJSONObject.Create;
  Id := NewRigmId; FState := 'queued';
  if (FKind='playback-audio') and (FOutput='') then FOutput := TPath.Combine(TPath.GetTempPath,'RIGMMaker\MoviePlayback\'+Id+'.wav');
  if FOutput<>'' then FOutput := ExpandFileName(FOutput);
  FTarget := FOutput;
end;
destructor TRigmMovieJob.Destroy;
begin
  Cancel; inherited; FProductionOptions.Free; FFrame.Free; FProject.Free; FLock.Free;
end;
procedure TRigmMovieJob.Report(Current,Total: Integer);
begin TMonitor.Enter(FLock); try FProgress := Current; FTotal := Total; if (FPhase='render') or (FPhase='audio') or (FPhase='preview') then FPhaseCompleted := Current; finally TMonitor.Exit(FLock); end; end;
procedure TRigmMovieJob.SetPhase(const Name: string; Total: Double);
begin TMonitor.Enter(FLock); try FPhase := Name; FPhaseTotal := Total; FPhaseCompleted := 0; FPhaseStarted := GetTickCount64; finally TMonitor.Exit(FLock); end; end;
function TRigmMovieJob.Cancelled: Boolean;
begin Result := TInterlocked.CompareExchange(FCancel,0,0)<>0; end;
procedure TRigmMovieJob.CheckCancel;
begin if Cancelled then raise EAbort.Create('取消しました。'); end;
procedure TRigmMovieJob.Cancel;
var Request: IHTTPRequest; Started: UInt64;
begin
  Started := GetTickCount64;
  TMonitor.Enter(FLock);
  try if not Cancelled then FCancelAt := Started; TInterlocked.Exchange(FCancel,1); Request := FRequest;
  finally TMonitor.Exit(FLock); end;
  if Request<>nil then Request.Cancel;
  TInterlocked.Exchange(FCancelCallMs,GetTickCount64-Started);
end;
procedure TRigmMovieJob.RequestChanged(Request: IHTTPRequest);
begin TMonitor.Enter(FLock); try FRequest := Request; finally TMonitor.Exit(FLock); end; end;
function TRigmMovieJob.Done: Boolean;
begin Result := TInterlocked.CompareExchange(FDone,0,0)<>0; end;
function TRigmMovieJob.Status: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    Result := TJSONObject.Create; Result.AddPair('jobId',Id); Result.AddPair('kind',FKind);
    Result.AddPair('snapshotProjectId',FProject.Id); AddN(Result,'snapshotRevision',FProject.Revision);
    Result.AddPair('state',FState); Result.AddPair('error',FError); AddN(Result,'completed',FProgress); AddN(Result,'total',FTotal);
    AddB(Result,'done',Done); AddB(Result,'cancelRequested',Cancelled); AddN(Result,'cancelCallMs',TInterlocked.CompareExchange(FCancelCallMs,0,0));
    AddN(Result,'cancelWorkerMs',TInterlocked.CompareExchange(FCancelWorkerMs,0,0));
    if FKind='production' then Result.AddPair('output',FTarget) else Result.AddPair('output',FOutput);
    Result.AddPair('phase',FPhase); AddN(Result,'phaseCompleted',FPhaseCompleted); AddN(Result,'phaseTotal',FPhaseTotal);
    if FExportBackend<>'' then Result.AddPair('exportBackend',FExportBackend);
    if FProductionReport<>'' then Result.AddPair('production',ParseObject(FProductionReport));
    var Tick := GetTickCount64; if Done then Tick := FFinished;
    var Elapsed := 0.0; if FStarted>0 then Elapsed := (Tick-FStarted)/1000.0;
    var Remaining := -1.0; if (FPhaseCompleted>0) and (FPhaseTotal>FPhaseCompleted) then Remaining := (GetTickCount64-FPhaseStarted)/1000.0*(FPhaseTotal-FPhaseCompleted)/FPhaseCompleted;
    if Done then Remaining := 0;
    AddN(Result,'elapsedSeconds',Elapsed); AddN(Result,'remainingSeconds',Remaining); Result.AddPair('remainingScope','current phase estimate; rendering then encoding');
    AddN(Result,'encoderPeakPrivateBytes',FEncoderPrivate); AddN(Result,'encoderPeakWorkingSetBytes',FEncoderWorking); AddN(Result,'exportStagingPeakBytes',FStagingPeak);
    AddN(Result,'encoderProcessId',FEncoderPid); AddB(Result,'encoderExited',FEncoderExited);
    Result.AddPair('cancelPolicy','cancels active HTTP request; retry requested during cancellation queues once; export stops between frames or stops its own FFmpeg child');
  finally TMonitor.Exit(FLock); end;
end;
function TRigmMovieJob.TakeFrame: Vcl.Graphics.TBitmap;
begin Result := FFrame; FFrame := nil; end;
procedure TRigmMovieJob.Execute;
begin
  CoInitializeEx(nil,COINIT_MULTITHREADED);
  VoicevoxBaseUrl := FProject.EngineUrl; VoicevoxCancelled := Cancelled; VoicevoxRequestChanged := RequestChanged;
  TMonitor.Enter(FLock); try FState := 'running'; FStarted := GetTickCount64; finally TMonitor.Exit(FLock); end;
  try
    try
      CheckCancel;
      if FKind='audio' then GenerateAudio
      else if FKind='export' then ExportVideo
      else if FKind='speakers' then LoadCatalog
      else if FKind='preview' then Preview
      else if FKind='playback-audio' then PlaybackAudio
      else if FKind='assets' then ActorAssets
      else if FKind='waveform' then Waveform
      else if FKind='diagnostics' then Diagnostics
      else if FKind='production' then Produce
      else raise ERigm.Create('不明な動画ジョブです。');
      CheckCancel;
      TMonitor.Enter(FLock); try if FState='running' then FState := 'succeeded'; finally TMonitor.Exit(FLock); end;
    except
      on E: Exception do begin
        TMonitor.Enter(FLock);
        try if Cancelled or (E is EAbort) then FState := 'cancelled' else FState := 'failed'; FError := E.Message;
        finally TMonitor.Exit(FLock); end;
      end;
    end;
  finally
    VoicevoxCancelled := nil; VoicevoxRequestChanged := nil; VoicevoxBaseUrl := ''; CoUninitialize;
    if Cancelled then TInterlocked.Exchange(FCancelWorkerMs,GetTickCount64-FCancelAt);
    FFinished := GetTickCount64;
    TInterlocked.Exchange(FDone,1);
  end;
end;
procedure TRigmMovieJob.PlaybackAudio;
var Audio: TRigmPcm; Temporary: string;
begin
  Report(0,1); Audio := CachedMovieAudio(FProject,FProject.Scenes.Count>0);
  try
    CheckCancel; Audio.Samples := Copy(Audio.Samples,Min(Length(Audio.Samples),Round(FTime*Audio.Rate)),MaxInt);
    ForceDirectories(ExtractFilePath(FOutput)); Temporary := FOutput+'.part';
    try
      Audio.Save(Temporary); CheckCancel;
      if not MoveFileEx(PChar(Temporary),PChar(FOutput),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    finally if FileExists(Temporary) then TFile.Delete(Temporary); end;
    Report(1,1);
  finally Audio.Free; end;
end;
procedure TRigmMovieJob.LoadCatalog;
var Catalog: TSerifVoicevoxSpeakerCatalog; Error: string; A: TJSONArray;
begin
  Catalog := TSerifVoicevoxSpeakerCatalog.Create;
  try
    Report(0,1); if not Catalog.LoadFromApi(Error) then raise ERigm.Create('VOICEVOX接続: '+Error);
    A := TJSONArray.Create;
    try
      for var S in Catalog.Speakers do for var Style in S.Styles do begin
        var O := TJSONObject.Create; O.AddPair('name',S.Name); O.AddPair('uuid',S.UUID);
        O.AddPair('style',Style.Name); AddN(O,'styleId',Style.Id); A.AddElement(O);
      end;
      FCatalog := A.ToJSON;
    finally A.Free; end;
    Report(1,1);
  finally Catalog.Free; end;
end;
procedure TRigmMovieJob.GenerateAudio;
var Values: TSerifVoicevoxAudioValues; Wave,TextFile,Lab,Error,Directory: string; Pcm: TRigmPcm;
begin
  Directory := FOutput; if Directory='' then Directory := TPath.Combine(TPath.GetTempPath,'RIGMMaker\MovieAudio\'+FProject.Id);
  Directory := ExpandFileName(Directory);
  var Selected := JS(FProductionOptions,'cueId');
  if (Selected<>'') and (FProject.Cue(Selected)=nil) then raise ERigm.Create('生成対象のセリフがありません。');
  var Total := FProject.Cues.Count; if Selected<>'' then Total := 1;
  var Completed := 0; ForceDirectories(Directory); Report(0,Total);
  for var I := 0 to FProject.Cues.Count-1 do begin
    CheckCancel; var C := FProject.Cues[I]; if (Selected<>'') and (C.Id<>Selected) then Continue;
    if (C.SpokenText='') and not FProject.AudioReady(C) then begin
      C.WaveFile := ''; C.LabFile := ''; C.AudioSeconds := 0; C.AudioKey := FProject.AudioFingerprint(C);
    end;
    if (C.SpokenText<>'') and not FProject.AudioReady(C) then begin
      var S := FProject.Speaker(C.SpeakerId);
      if FProject.EffectiveStyle(C)<0 then raise ERigm.Create('VOICEVOX話者一覧から音声を選択してください: '+S.Name);
      Values := TSerifVoicevoxAudioValues.Defaults; Values.SpeedScale := S.Speed; Values.PitchScale := S.Pitch;
      Values.IntonationScale := S.Intonation; Values.VolumeScale := S.Volume;
      Values.SpeedScale := JN(C.VoiceSettings,'speedScale',Values.SpeedScale); Values.PitchScale := JN(C.VoiceSettings,'pitchScale',Values.PitchScale);
      Values.IntonationScale := JN(C.VoiceSettings,'intonationScale',Values.IntonationScale); Values.VolumeScale := JN(C.VoiceSettings,'volumeScale',Values.VolumeScale);
      Values.PrePhonemeLength := JN(C.VoiceSettings,'prePhonemeLength',Values.PrePhonemeLength); Values.PostPhonemeLength := JN(C.VoiceSettings,'postPhonemeLength',Values.PostPhonemeLength);
      if not TSerifVoicevoxApi.CreateInputFiles(C.SpokenText,S.Name,IntToStr(FProject.EffectiveStyle(C)),FProject.EffectiveStyle(C),Values,'',Wave,TextFile,Lab,Error) then
        raise ERigm.Create('音声生成 '+C.Id+': '+Error);
      try
        CheckCancel; Pcm := TRigmPcm.Load(Wave);
        try
          var Token := NewRigmId; var Target := TPath.Combine(Directory,Token+'.wav');
          var TargetLab := TPath.Combine(Directory,Token+'.lab');
          TFile.Copy(Wave,Target,False); TFile.Copy(Lab,TargetLab,False);
          C.WaveFile := Target; C.LabFile := TargetLab; C.AudioSeconds := Pcm.Duration; C.AudioKey := FProject.AudioFingerprint(C);
        finally Pcm.Free; end;
      finally
        if FileExists(Wave) then TFile.Delete(Wave); if FileExists(TextFile) then TFile.Delete(TextFile); if FileExists(Lab) then TFile.Delete(Lab);
      end;
    end;
    Inc(Completed); Report(Completed,Total);
  end;
end;
function LoadActor(Project: TRigmMovieProject): TRigmDocument;
begin
  var Path := Project.CharacterFile;
  if Project.Characters.Count>0 then begin Path := ''; for var C in Project.Characters do if C.Visible then begin Path := C.FileName; Break; end; end;
  if Path='@sample' then begin Result := TRigmDocument.Create; PopulateRigmSample(Result); end
  else if Path='' then Result := nil
  else if CharacterFormat(Path)='psd' then Result := nil
  else Result := LoadRigm(ResolveMoviePath(Project.FileName,Path));
end;
function SourceActorAssets(Project: TRigmMovieProject; Document: TRigmDocument): TJSONObject;
begin
  var Path := Project.CharacterFile;
  if Project.Characters.Count>0 then begin Path := ''; for var C in Project.Characters do if C.Visible then begin Path := C.FileName; Break; end; end;
  if CharacterFormat(Path)='psd' then Exit(ReadPsdActorAssets(ResolveMoviePath(Project.FileName,Path)));
  Result := MovieActorAssets(Document); Result.AddPair('capabilities',MovieCapabilities(Document));
end;
procedure TRigmMovieJob.Preview;
var Document: TRigmDocument; Audio: TRigmPcm; Ready: Boolean;
begin
  Report(0,1); Document := LoadActor(FProject); Audio := nil;
  try
    Ready := True; for var C in FProject.Cues do if not FProject.AudioReady(C) and not ((FProject.Scenes.Count>0) and FProject.HasStoredAudio(C)) then Ready := False;
    if Ready and (FProject.Cues.Count>0) then Audio := CachedMovieAudio(FProject,FProject.Scenes.Count>0);
    CheckCancel; FFrame := RenderMovieFrame(FProject,Document,FTime,Audio); CheckCancel;
    if FOutput<>'' then begin
      var Image := TPngImage.Create; var Temporary := FOutput+'.'+Id+'.tmp';
      try
        Image.Assign(FFrame); Image.SaveToFile(Temporary); CheckCancel;
        if not MoveFileEx(PChar(Temporary),PChar(FOutput),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      finally Image.Free; if FileExists(Temporary) then TFile.Delete(Temporary); end;
    end;
    Report(1,1);
  finally Audio.Free; Document.Free; end;
end;
procedure TRigmMovieJob.ExportVideo;
var Document: TRigmDocument; Audio: TRigmPcm; Writer: TRigmMovieAvi; Frame: Vcl.Graphics.TBitmap;
  Temporary, Encoded: string; Frames: Integer; Mp4: Boolean;
begin
  if FProject.Cues.Count=0 then raise ERigm.Create('台本が空です。');
  if (FOutput='') or FileExists(FOutput) then raise ERigm.Create('新しい動画出力先を指定してください。既存ファイルは上書きしません。');
  Mp4 := SameText(ExtractFileExt(FOutput),'.mp4');
  if not Mp4 and not SameText(ExtractFileExt(FOutput),'.avi') then raise ERigm.Create('動画形式はAVIまたはMP4です。');
  if Mp4 and not FileExists(FProject.FfmpegExe) then raise ERigm.Create('MP4には既存のffmpeg.exeの設定が必要です。');
  ForceDirectories(ExtractFilePath(ExpandFileName(FOutput))); Temporary := FOutput+'.'+Id+'.part';
  Encoded := Temporary+'.mp4'; Document := nil; Audio := nil; Writer := nil;
  try
    SetPhase('prepare-character',1); Document := LoadActor(FProject);
    CheckCancel; SetPhase('prepare-audio',1); Audio := CachedMovieAudio(FProject);
    Frames := Ceil(FProject.Duration*FProject.Fps); SetPhase('render',Frames); Report(0,Frames+Ord(Mp4));
      if Mp4 then begin
        TMonitor.Enter(FLock); try FExportBackend := 'ffmpeg-raw-bgra-pipe'; finally TMonitor.Exit(FLock); end;
        StreamMovieMp4(FProject,Document,Audio,Encoded,Cancelled,
          procedure(Current,Total: Integer; StagingBytes: UInt64)
          begin
            Report(Current,Total+1);
            TMonitor.Enter(FLock); try FStagingPeak := Max(FStagingPeak,StagingBytes); finally TMonitor.Exit(FLock); end;
          end,
          procedure begin SetPhase('encode',FProject.Duration); end,
          procedure(Seconds: Double; PrivateBytes,WorkingBytes: UInt64; ProcessId: Cardinal; Exited: Boolean)
          begin
            TMonitor.Enter(FLock);
            try
              if FPhase='encode' then FPhaseCompleted := Max(FPhaseCompleted,Min(FProject.Duration,Seconds));
              FEncoderPrivate := Max(FEncoderPrivate,PrivateBytes);
              FEncoderWorking := Max(FEncoderWorking,WorkingBytes);
              FEncoderPid := ProcessId; FEncoderExited := Exited;
          finally TMonitor.Exit(FLock); end;
        end); CheckCancel;
      if not MoveFileEx(PChar(Encoded),PChar(FOutput),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      Report(Frames+1,Frames+1);
      end else begin
        TMonitor.Enter(FLock); try FExportBackend := 'legacy-mjpeg-avi'; finally TMonitor.Exit(FLock); end;
        Writer := TRigmMovieAvi.Create(Temporary,FProject.Width,FProject.Height,FProject.Fps,Frames,MovieJpegQuality(FProject.EncodeProfile));
        for var I := 0 to Frames-1 do begin
          CheckCancel; Frame := RenderMovieFrame(FProject,Document,I/FProject.Fps,Audio);
          try Writer.AddFrame(Frame,Audio); finally Frame.Free; end; Report(I+1,Frames);
          TMonitor.Enter(FLock); try FStagingPeak := Max(FStagingPeak,UInt64(TFile.GetSize(Temporary))); finally TMonitor.Exit(FLock); end;
        end;
        CheckCancel; Writer.Finish; FreeAndNil(Writer);
        if not MoveFileEx(PChar(Temporary),PChar(FOutput),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
      end;
  finally Writer.Free; Audio.Free; Document.Free; if FileExists(Temporary) then TFile.Delete(Temporary);
    if FileExists(Encoded) then TFile.Delete(Encoded); end;
end;
procedure TRigmMovieJob.PublishProduction(Report: TJSONObject);
begin
  TMonitor.Enter(FLock);
  try FProductionReport := Report.ToJSON; finally TMonitor.Exit(FLock); end;
end;

procedure TRigmMovieJob.Produce;
var Outcome, D, Preparation, DiagnosticStatus: TJSONObject; Target, PreviewTarget: string;
  procedure RefreshPreparation;
  begin
    FreeAndNil(Preparation); Preparation := MoviePreparation(FProject,D,DiagnosticStatus,Target,False);
    Outcome.RemovePair('preparation').Free;
    Outcome.AddPair('preparation',Preparation.Clone as TJSONObject);
    Outcome.RemovePair('needs').Free;
    Outcome.AddPair('needs',MovieProductionNeeds(Preparation,JS(FProductionOptions,'deliver','video'),FProject));
    PublishProduction(Outcome);
  end;
  function Blocked: Boolean;
  begin
    Result := JA(Outcome,'needs').Count>0;
    if Result then begin
      TMonitor.Enter(FLock); try FState := 'blocked'; finally TMonitor.Exit(FLock); end;
    end;
  end;
begin
  Outcome := ParseObject('{"needs":[],"result":{},"completedSteps":[],"canResume":true,"realSpeechVerified":false}');
  D := nil; Preparation := nil; DiagnosticStatus := ParseObject('{"done":true,"state":"succeeded"}');
  Target := FOutput;
  PreviewTarget := JS(FProductionOptions,'previewPath');
  if PreviewTarget='' then PreviewTarget := Target+'.preview-'+Id+'.png';
  try
    PublishProduction(Outcome); Diagnostics; D := ParseObject(FCatalog);
    JA(Outcome,'completedSteps').Add('diagnostics');
    RefreshPreparation;
    if FileExists(PreviewTarget) then begin
      var Need := ParseObject('{"code":"preview_exists","blocking":true,"scope":"output","nextAction":"production-resume","subjectId":"previewPath"}');
      Need.AddPair('message','Preview output already exists; choose a new previewPath.'); JA(Outcome,'needs').AddElement(Need);
      PublishProduction(Outcome);
    end;
    if Blocked then Exit;
    SetPhase('audio',FProject.Cues.Count);
    try
      FOutput := Target+'.audio'; GenerateAudio; JA(Outcome,'completedSteps').Add('audio');
    finally FOutput := Target; end;
    CheckCancel; RefreshPreparation; if Blocked then Exit;
    ForceDirectories(ExtractFilePath(PreviewTarget)); SetPhase('preview',1);
    try
      FOutput := PreviewTarget; FTime := EnsureRange(JN(FProductionOptions,'previewTime',0.2),0.0,FProject.Duration);
      Preview; JA(Outcome,'completedSteps').Add('preview');
    finally FOutput := Target; end;
    JO(Outcome,'result').AddPair('previewPath',PreviewTarget); PublishProduction(Outcome);
    CheckCancel;
    if JS(FProductionOptions,'deliver','video')='video' then begin
      ExportVideo; JO(Outcome,'result').AddPair('videoPath',Target); JA(Outcome,'completedSteps').Add('export');
    end;
    Outcome.RemovePair('canResume').Free; AddB(Outcome,'canResume',False);
    SetPhase('complete',1); Report(1,1);
  finally
    var AudioFiles := TJSONArray.Create; var AudioTotal := 0;
    for var C in FProject.Cues do if FProject.AudioReady(C) then begin
      Inc(AudioTotal); if AudioFiles.Count>=100 then Continue;
      var A := TJSONObject.Create; A.AddPair('cueId',C.Id); A.AddPair('wavePath',ResolveMoviePath(FProject.FileName,C.WaveFile));
      A.AddPair('labPath',ResolveMoviePath(FProject.FileName,C.LabFile)); AudioFiles.AddElement(A);
    end;
    JO(Outcome,'result').AddPair('audioFiles',AudioFiles); AddN(JO(Outcome,'result'),'audioTotal',AudioTotal);
    AddN(JO(Outcome,'result'),'durationSeconds',FProject.Duration);
    FOutput := Target; PublishProduction(Outcome);
    DiagnosticStatus.Free; Preparation.Free; D.Free; Outcome.Free;
  end;
end;

procedure TRigmMovieJob.ActorAssets;
var Document: TRigmDocument; O: TJSONObject;
begin
  Report(0,1); Document := LoadActor(FProject);
  try CheckCancel; O := SourceActorAssets(FProject,Document); try FCatalog := O.ToJSON; finally O.Free; end; Report(1,1);
  finally Document.Free; end;
end;
procedure TRigmMovieJob.Waveform;
var O: TJSONObject;
begin
  Report(0,1); CheckCancel; O := MovieWaveform(FProject,2048);
  try CheckCancel; FCatalog := O.ToJSON; finally O.Free; end; Report(1,1);
end;
procedure TRigmMovieJob.Diagnostics;
var O: TJSONObject; Document: TRigmDocument; Pose: TRigmPose;
begin
  O := TJSONObject.Create; Document := nil; Pose := nil;
  try
    O.AddPair('key',MoviePreparationKey(FProject)); O.AddPair('engineUrl',FProject.EngineUrl);
    SetPhase('diagnostics',2); Report(0,2);
    try LoadCatalog; O.AddPair('speakers',TJSONObject.ParseJSONValue(FCatalog)); AddB(O,'engineConnected',True);
    except on E: Exception do begin CheckCancel; AddB(O,'engineConnected',False); O.AddPair('engineError',E.Message); end; end;
    CheckCancel; Report(1,2);
    try
      if FProject.Characters.Count>0 then ValidateCompositionMaterials(FProject);
      Document := LoadActor(FProject);
      if Document<>nil then Document.ValidateStructure;
      var Assets := SourceActorAssets(FProject,Document); O.AddPair('assets',Assets);
      if Document<>nil then begin
        Pose := TRigmPose.Create; Pose.Reset;
        try
          for var C in FProject.Cues do begin
            CheckCancel; C.Acting.ApplyVariants(Document,Pose);
            C.Acting.ApplyFeatureAssets(Document,Pose,0,1); Pose.Reset;
          end;
        except on E: Exception do begin CheckCancel; O.AddPair('actingError',E.Message); end; end;
      end;
    except on E: Exception do begin CheckCancel; O.AddPair('materialError',E.Message); end; end;
    CheckCancel; FCatalog := O.ToJSON; Report(2,2);
  finally Pose.Free; Document.Free; O.Free; end;
end;
end.
