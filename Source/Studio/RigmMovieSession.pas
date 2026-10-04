unit RigmMovieSession;

interface
uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, Vcl.Graphics,
  RigmMovieModel, RigmMovieJobs;

type
  TRigmMovieSession = class
  private
    FProject: TRigmMovieProject;
    FJob: TRigmMovieJob;
    FDiagnosticJob: TRigmMovieJob;
    FDiagnostics: TJSONObject;
    FDiagnosticCollected: Boolean;
    FPreviewRevision: Integer;
    FPreviewRenderKey,FRejectedJobId: string;
    FCollected: Boolean;
    FUndo,FRedo: TObjectList<TRigmMovieProject>;
    FObsoletePreviews: TObjectList<TRigmMovieJob>;
    FFinishedJobs: TObjectDictionary<string,TJSONObject>;
    FFinishedOrder: TList<string>;
    FCatalog: TJSONArray;
    FCatalogUrl: string;
    FAssets, FWaveform: TJSONObject;
    FFrame: TBitmap;
    FTime, FFrameTime: Double;
    FResumeCue: string;
    FLastKind,FLastOutput: string;
    FLastTime: Double;
    FPlaying,FRetryPending,FAutomaticPreview: Boolean;
    FOnChanged: TNotifyEvent;
    FProductions: TObjectDictionary<string,TJSONObject>;
    FProductionOrder: TList<string>;
    FProductionKey: string;
    FEditToken,FEditState: string;
    FEditDeadline: UInt64;
    FEditEpoch: Integer;
    procedure RetireAutomaticPreview;
    procedure RememberJob;
    function EditStatus: TJSONObject;
    function ProductionStatus(const Key: string): TJSONObject;
    function Produce(Args: TJSONObject; Resume: Boolean): TJSONObject;
    procedure CollectProduction(JobStatus: TJSONObject);
    procedure RequireRevision(Args: TJSONObject);
    procedure Commit(Project: TRigmMovieProject);
    function StartJob(const Kind,Output: string; Seconds: Double): TJSONObject;
    function JobStatus: TJSONObject;
    function Timeline: TJSONObject;
    function Preparation(const OutputPath: string=''): TJSONObject;
    function WorkflowStatus: TJSONObject;
    function WorkflowCommand(const Command: string; Args: TJSONObject): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(const Command: string; Args: TJSONObject): TJSONObject;
    function PreviewFrame(Seconds: Double): TJSONObject;
    procedure AdoptImage(const SceneId,Path: string; Theme: Boolean=False);
    function Status: TJSONObject;
    procedure Poll;
    function Busy: Boolean;
    function CanEdit: Boolean;
    function TakeFrame: Vcl.Graphics.TBitmap;
    procedure SetProject(Project: TRigmMovieProject);
    property Project: TRigmMovieProject read FProject;
    property Time: Double read FTime;
    property FrameTime: Double read FFrameTime;
    property ResumeCue: string read FResumeCue;
    function GuiLocked: Boolean;
    property Playing: Boolean read FPlaying;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation
uses System.Math, System.IOUtils, System.StrUtils, RigmJson, RigmModel, RigmMovieAudio,
  RigmMovieOutput, RigmMoviePreparation, RigmMovieProduction, RigmMovieWorkflow, RigmAppSettings, RigmMovieCompositionCommands, RigmMovieComposition, RigmMovieWorkspace, Winapi.Windows;

constructor TRigmMovieSession.Create;
begin
  inherited; FProject := TRigmMovieProject.Create; FUndo := TObjectList<TRigmMovieProject>.Create(True);
  FRedo := TObjectList<TRigmMovieProject>.Create(True); FCatalog := TJSONArray.Create;
  FObsoletePreviews := TObjectList<TRigmMovieJob>.Create(True);
  FFinishedJobs := TObjectDictionary<string,TJSONObject>.Create([doOwnsValues]); FFinishedOrder := TList<string>.Create;
  FAssets := TJSONObject.Create; FWaveform := TJSONObject.Create;
  FDiagnostics := TJSONObject.Create;
  FProductions := TObjectDictionary<string,TJSONObject>.Create([doOwnsValues]);
  FProductionOrder := TList<string>.Create;
end;
destructor TRigmMovieSession.Destroy;
begin FDiagnosticJob.Free; FDiagnostics.Free; FJob.Free; FObsoletePreviews.Free; FFinishedJobs.Free; FFinishedOrder.Free; FProductionOrder.Free; FProductions.Free; FFrame.Free; FAssets.Free; FWaveform.Free; FCatalog.Free; FRedo.Free; FUndo.Free; FProject.Free; inherited; end;
function TRigmMovieSession.Busy: Boolean;
begin Result := (FJob<>nil) and not FJob.Done; end;
function TRigmMovieSession.CanEdit: Boolean;
begin Result := not Busy or (FJob.Kind='preview'); end;
procedure TRigmMovieSession.RequireRevision(Args: TJSONObject);
begin
  if GuiLocked and (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Codex edit session holds the project; use its editToken or release the lock');
  if (Args.GetValue('editToken')<>nil) and ((JS(Args,'editToken')<>FEditToken) or (JI(Args,'editEpoch',FEditEpoch)<>FEditEpoch)) then raise ERigm.Create('Expired Codex edit token');
  if not CanEdit then raise ERigm.Create('ジョブ処理中です。取消または完了後に編集できます。');
  if (JS(Args,'projectId')<>FProject.Id) or (JI(Args,'revision',-1)<>FProject.Revision) then raise ERigm.Create('statusの最新projectIdとrevisionを指定してください。');
end;
procedure TRigmMovieSession.Commit(Project: TRigmMovieProject);
begin
  Project.Validate; Project.Revision := FProject.Revision; Project.Changed;
  FUndo.Add(FProject); FProject := Project; FRedo.Clear; while FUndo.Count>30 do FUndo.Delete(0);
  if Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TRigmMovieSession.SetProject(Project: TRigmMovieProject);
begin
  Poll; RetireAutomaticPreview;
  if Busy then raise ERigm.Create('ジョブ完了後にプロジェクトを開いてください。');
  Project.Validate; Project.Revision := Max(Project.Revision,FProject.Revision+1);
  FreeAndNil(FJob); FCollected := True; FRetryPending := False; FLastKind := ''; FLastOutput := '';
  if FDiagnosticJob<>nil then FDiagnosticJob.Cancel;
  FreeAndNil(FDiagnosticJob); FDiagnosticCollected := True;
  FDiagnostics.Free; FDiagnostics := TJSONObject.Create; FPreviewRevision := -1;
  FCatalog.Free; FCatalog := TJSONArray.Create; FCatalogUrl := '';
  FPreviewRenderKey := ''; FRejectedJobId := '';
  FUndo.Add(FProject); while FUndo.Count>30 do FUndo.Delete(0); FRedo.Clear; FProject := Project; FProject.Modified := False;
  FTime := 0; FResumeCue := ''; FPlaying := False; FreeAndNil(FFrame);
  FAssets.Free; FAssets := TJSONObject.Create; FWaveform.Free; FWaveform := TJSONObject.Create;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;
function TRigmMovieSession.GuiLocked: Boolean;
begin
  if (FEditToken<>'') and (GetTickCount64>=FEditDeadline) then begin
    FEditToken := ''; Inc(FEditEpoch); FEditState := 'disconnected';
    if FJob<>nil then FJob.Cancel;
    // Revision invalidates a worker even if a cancelled HTTP call returns late.
    Inc(FProject.Revision);
  end;
  Result := FEditToken<>'';
end;
function TRigmMovieSession.EditStatus: TJSONObject;
begin
  Result := TJSONObject.Create; AddB(Result,'locked',GuiLocked); Result.AddPair('state',FEditState);
  AddN(Result,'epoch',FEditEpoch); if FEditToken<>'' then AddN(Result,'leaseRemainingMs',Max(0,Int64(FEditDeadline)-Int64(GetTickCount64)));
end;
function TRigmMovieSession.Status: TJSONObject;
var Job: TJSONObject;
begin
  Job := JobStatus;
  Result := TJSONObject.Create; Result.AddPair('projectId',FProject.Id); AddN(Result,'revision',FProject.Revision);
  Result.AddPair('editSession',EditStatus);
  Result.AddPair('title',FProject.Title); Result.AddPair('fileName',FProject.FileName); AddB(Result,'modified',FProject.Modified);
  AddN(Result,'duration',FProject.Duration); AddN(Result,'time',FTime); AddN(Result,'cueCount',FProject.Cues.Count);
  AddB(Result,'retryPending',FRetryPending); AddB(Result,'busy',Busy); AddB(Result,'playing',FPlaying); AddN(Result,'undoCount',FUndo.Count); AddN(Result,'redoCount',FRedo.Count);
  if FJob<>nil then Result.AddPair('job',Job) else Job.Free;
  if FProductionKey<>'' then Result.AddPair('production',ProductionStatus(FProductionKey));
  Result.AddPair('workflow',WorkflowStatus);
end;
function TRigmMovieSession.JobStatus: TJSONObject;
begin
  if FJob=nil then Exit(ParseObject('{"state":"none","done":true}'));
  repeat
    Result := FJob.Status;
    if not JB(Result,'done') or FCollected then Break;
    Result.Free; Poll;
  until False;
  AddB(Result,'collected',FCollected);
  AddB(Result,'staleResult',FRejectedJobId=FJob.Id);
end;
function TRigmMovieSession.TakeFrame: Vcl.Graphics.TBitmap;
begin Result := FFrame; FFrame := nil; end;
function TRigmMovieSession.Preparation(const OutputPath: string): TJSONObject;
begin
  var Job := ParseObject('{"done":true,"state":"none"}');
  try if FDiagnosticJob<>nil then begin Job.Free; Job := FDiagnosticJob.Status; end;
    var Key := MovieRenderKey(FProject);
    var PreviewCurrent := (FPreviewRenderKey<>'') and (FPreviewRenderKey=Key);
    if (FProject.PreviewKey=Key) and (FProject.PreviewPath<>'') and (FProject.PreviewHash<>'') then
      PreviewCurrent := MovieFileIdentity(ResolveMoviePath(FProject.FileName,FProject.PreviewPath))=FProject.PreviewHash;
    Result := MoviePreparation(FProject,FDiagnostics,Job,OutputPath,PreviewCurrent);
  finally Job.Free; end;
end;
procedure TRigmMovieSession.Poll;
var O: TJSONObject; Changed: Boolean; Next: TRigmMovieProject;
begin
  for var I := FObsoletePreviews.Count-1 downto 0 do
    if FObsoletePreviews[I].Done then FObsoletePreviews.Delete(I);
  GuiLocked;
  if (FDiagnosticJob<>nil) and FDiagnosticJob.Done and not FDiagnosticCollected then begin
    FDiagnosticCollected := True; var State := FDiagnosticJob.Status;
    try
      if (JS(State,'state')='succeeded') and (MoviePreparationKey(FDiagnosticJob.Project)=MoviePreparationKey(FProject)) then begin
        FDiagnostics.Free; FDiagnostics := ParseObject(FDiagnosticJob.Catalog);
        if FDiagnostics.GetValue('speakers')<>nil then begin FCatalog.Free; FCatalog := JA(FDiagnostics,'speakers').Clone as TJSONArray; FCatalogUrl := FDiagnosticJob.Project.EngineUrl; end;
        if FDiagnostics.GetValue('speakers')=nil then begin FCatalog.Free; FCatalog := TJSONArray.Create; end;
        FAssets.Free; FAssets := TJSONObject.Create;
        if FDiagnostics.GetValue('assets')<>nil then begin FAssets.Free; FAssets := JO(FDiagnostics,'assets').Clone as TJSONObject; end;
      end;
    finally State.Free; end;
  end;
  if (FJob=nil) or not FJob.Done or FCollected then Exit; FCollected := True;
  O := FJob.Status;
  try
    // A finished snapshot must never replace edits made after it started.
    if (FJob.Project.Id<>FProject.Id) or (FJob.Project.Revision<>FProject.Revision) then begin
      FRejectedJobId := FJob.Id; FRetryPending := False;
      if Assigned(FOnChanged) then FOnChanged(Self);
      Exit;
    end;
    if (FJob.Kind='speakers') and (JS(O,'state')='succeeded') then begin
      FCatalog.Free; FCatalog := TJSONObject.ParseJSONValue(FJob.Catalog) as TJSONArray; FCatalogUrl := FJob.Project.EngineUrl;
    end;
    if MatchText(FJob.Kind,['audio','production']) and (FJob.Project.Id=FProject.Id) then begin
      Changed := False; Next := FProject.Clone;
      try
        // Keep successfully generated cues even if a later request fails or is cancelled.
        for var C in FJob.Project.Cues do begin
          var Target := Next.Cue(C.Id);
          if (Target<>nil) and FJob.Project.AudioReady(C) and (C.AudioKey=Next.AudioFingerprint(Target)) and
            ((Target.AudioKey<>C.AudioKey) or (Target.WaveFile<>C.WaveFile)) then begin
            Target.WaveFile := C.WaveFile; Target.LabFile := C.LabFile; Target.AudioKey := C.AudioKey;
            Target.AudioSeconds := C.AudioSeconds; Changed := True;
          end;
        end;
        if Changed then begin Commit(Next); Next := nil; end;
      finally Next.Free; end;
    end;
    if (FJob.Kind='assets') and (JS(O,'state')='succeeded') and (FJob.Project.CharacterFile=FProject.CharacterFile) and (FJob.Project.FileName=FProject.FileName) then begin
      FAssets.Free; FAssets := ParseObject(FJob.Catalog);
    end;
    if (FJob.Kind='waveform') and (JS(O,'state')='succeeded') and (FJob.Project.Id=FProject.Id) and (MovieAudioStamp(FJob.Project)=MovieAudioStamp(FProject)) then begin
      FWaveform.Free; FWaveform := ParseObject(FJob.Catalog); AddN(FWaveform,'revision',FProject.Revision);
    end;
    if MatchText(FJob.Kind,['preview','production']) and (JS(O,'state')='succeeded') and (FJob.Project.Id=FProject.Id) and
      ((FJob.Kind='production') or (FJob.Project.Revision=FProject.Revision)) then begin
      FFrame.Free; FFrame := FJob.TakeFrame; FFrameTime := FJob.Seconds;
      FPreviewRevision := FProject.Revision;
      FPreviewRenderKey := MovieRenderKey(FProject);
      var PreviewPath := FJob.Output;
      if FJob.Kind='production' then PreviewPath := JS(JO(JO(O,'production'),'result'),'previewPath');
      if (PreviewPath<>'') and FileExists(PreviewPath) then begin
        Next := FProject.Clone;
        try
          Next.PreviewKey := FPreviewRenderKey; Next.PreviewPath := PreviewPath; Next.PreviewHash := MovieFileIdentity(PreviewPath);
          Commit(Next); Next := nil;
        finally Next.Free; end;
      end;
    end;
    if MatchText(FJob.Kind,['export','production']) and (JS(O,'state')='succeeded') then begin
      var VideoPath := FJob.Output;
      if FJob.Kind='production' then VideoPath := JS(JO(JO(O,'production'),'result'),'videoPath');
      if (VideoPath<>'') and FileExists(VideoPath) then begin
        Next := FProject.Clone;
        try Next.VideoKey := MovieRenderKey(FProject); Next.VideoPath := VideoPath; Next.VideoHash := MovieFileIdentity(VideoPath);
          Commit(Next); Next := nil;
        finally Next.Free; end;
      end;
    end;
    if FJob.Kind='production' then CollectProduction(O);
    if Assigned(FOnChanged) then FOnChanged(Self);
  finally O.Free; end;
  if FRetryPending then begin FRetryPending := False; O := StartJob(FLastKind,FLastOutput,FLastTime); O.Free; end;
end;
function TRigmMovieSession.WorkflowStatus: TJSONObject;
begin
  var Ready := Preparation;
  try
    var Key := MovieRenderKey(FProject);
    var VideoCurrent := (FProject.VideoKey=Key) and (FProject.VideoPath<>'') and
      (FProject.VideoHash<>'') and (MovieFileIdentity(ResolveMoviePath(FProject.FileName,FProject.VideoPath))=FProject.VideoHash);
    Result := MovieWorkflow(FProject,Ready,JB(Ready,'previewCurrent'),VideoCurrent,Busy,FRejectedJobId);
  finally Ready.Free; end;
end;
function TRigmMovieSession.WorkflowCommand(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command='workflow-status' then Exit(WorkflowStatus);
  RequireRevision(Args);
  var Stage := MovieStageIndex(FProject.WorkflowStage); var Ready := WorkflowStatus;
  try
    if Command='workflow-next' then begin
      if not JB(Ready,'canNext') then Exit(Ready.Clone as TJSONObject);
      var Next := FProject.Clone;
      try Next.WorkflowStage := MovieStageName(Stage+1); Commit(Next); Next := nil; finally Next.Free; end;
      Exit(WorkflowStatus);
    end;
    if Command='workflow-back' then begin
      var Target := Stage-1;
      if Args.GetValue('stage')<>nil then Target := MovieStageIndex(JS(Args,'stage'));
      if (Target<0) or (Target>=Stage) then raise ERigm.Create('Choose an earlier workflow stage');
      var Next := FProject.Clone;
      try Next.WorkflowStage := MovieStageName(Target); Commit(Next); Next := nil; finally Next.Free; end;
      Exit(WorkflowStatus);
    end;
    if Command='workflow-run' then begin
      case Stage of
        0: Exit(Execute('import-script',Args));
        1: Exit(Execute('diagnostics-refresh',Args));
        2: begin
          var PreparationInfo := Preparation;
          try
            if not JB(PreparationInfo,'canGenerateAudio') and (JI(PreparationInfo,'audioPending')>0) then
              raise ERigm.Create('Audio setup is incomplete; inspect movie-preparation');
          finally PreparationInfo.Free; end;
          Exit(StartJob('audio',JS(Args,'directory'),0));
        end;
        3: begin
          if not JB(JO(Ready,'results'),'audioCurrent') then raise ERigm.Create('Generate changed audio before preview');
          var Path := JS(Args,'path');
          if Path='' then Path := TPath.Combine(TPath.GetTempPath,'RIGMMaker\MoviePreviews\'+FProject.Id+'-'+NewRigmId+'.png');
          if FileExists(Path) then raise ERigm.Create('Choose a new preview path');
          ForceDirectories(ExtractFilePath(Path)); Exit(StartJob('preview',Path,JN(Args,'time',FTime)));
        end;
        4: begin
          if not JB(JO(Ready,'results'),'audioCurrent') or not JB(JO(Ready,'results'),'previewCurrent') then
            raise ERigm.Create('Regenerate changed audio and preview before export');
          Exit(StartJob('export',ResolveMoviePath(FProject.FileName,JS(Args,'path',FProject.OutputTarget)),0));
        end;
      else raise ERigm.Create('Production is complete; return to an earlier stage to adjust');
      end;
    end;
    raise ERigm.Create('Unknown workflow command');
  finally Ready.Free; end;
end;
function TRigmMovieSession.StartJob(const Kind,Output: string; Seconds: Double): TJSONObject;
begin
  Poll;
  RememberJob;
  if Busy and (FJob.Kind='preview') and ((Kind<>'preview') or FAutomaticPreview) then begin
    // Retire the preview asynchronously so an explicit production action starts now.
    // Retired snapshots never publish a frame or write back project state.
    FJob.Cancel; FObsoletePreviews.Add(FJob); FJob := nil;
  end;
  if Busy then raise ERigm.Create('別の制作ジョブが処理中です。');
  FProject.Validate; FreeAndNil(FJob); FJob := TRigmMovieJob.Create(FProject,Kind,Output,Seconds);
  FAutomaticPreview := False;
  FCollected := False; FLastKind := Kind; FLastOutput := Output; FLastTime := Seconds; FJob.Start;
  FRejectedJobId := '';
  Result := FJob.Status;
end;
procedure TRigmMovieSession.RetireAutomaticPreview;
begin
  if not Busy or not FAutomaticPreview then Exit;
  FJob.Cancel; FObsoletePreviews.Add(FJob); FJob := nil; FAutomaticPreview := False;
end;
function TRigmMovieSession.PreviewFrame(Seconds: Double): TJSONObject;
begin
  var Kind := FLastKind; var Output := FLastOutput; var Time := FLastTime;
  try
    FTime := EnsureRange(Seconds,0.0,FProject.Duration);
    Result := StartJob('preview','',FTime); FAutomaticPreview := True;
  finally
    // Rendering the current frame must not replace the author's retry target.
    FLastKind := Kind; FLastOutput := Output; FLastTime := Time;
  end;
end;
procedure TRigmMovieSession.RememberJob;
begin
  if (FJob=nil) or not FJob.Done then Exit;
  if not FFinishedJobs.ContainsKey(FJob.Id) then FFinishedOrder.Add(FJob.Id);
  FFinishedJobs.AddOrSetValue(FJob.Id,JobStatus);
  while FFinishedOrder.Count>30 do begin FFinishedJobs.Remove(FFinishedOrder[0]); FFinishedOrder.Delete(0); end;
end;
procedure TRigmMovieSession.AdoptImage(const SceneId,Path: string; Theme: Boolean);
begin
  if GuiLocked or not CanEdit then raise ERigm.Create('Movie editing is busy');
  var S := FProject.Scene(SceneId); var C := FProject.Cue(SceneId);
  if not Theme and (S=nil) and (C=nil) then raise ERigm.Create('Select a scene first');
  var Image := CopyMovieImage(FProject,Path); var Args := TJSONObject.Create;
  try
    Args.AddPair('projectId',FProject.Id); AddN(Args,'revision',FProject.Revision);
    var Name := 'update-project';
    if Theme then Args.AddPair('themeBackground',Image)
    else if S<>nil then begin Name := 'update-scene'; Args.AddPair('id',S.Id); Args.AddPair('image',Image); end
    else begin Name := 'update-cue'; Args.AddPair('id',C.Id); Args.AddPair('background',Image); end;
    var Reply := Execute(Name,Args); Reply.Free;
  finally Args.Free; end;
  // Seek once after explicit adoption so the selected scene is visible.
  if not Theme then begin
    var Time := 0.0;
    if S<>nil then begin for var Item in FProject.Scenes do begin if Item.Id=SceneId then Break; Time := Time+FProject.SceneDuration(Item); end; end
    else Time := FProject.CueStart(FProject.Cue(SceneId));
    Args := TJSONObject.Create;
    try AddN(Args,'time',Time); var Reply := Execute('seek',Args); Reply.Free; finally Args.Free; end;
  end;
end;
function TRigmMovieSession.Timeline: TJSONObject;
var A: TJSONArray; Start: Double;
begin
  Result := TJSONObject.Create; AddN(Result,'duration',FProject.Duration); AddN(Result,'time',FTime); AddN(Result,'fps',FProject.Fps);
  A := TJSONArray.Create; Result.AddPair('cues',A); Start := 0;
  for var C in FProject.Cues do begin
    Start := FProject.CueStart(C);
    var O := TJSONObject.Create; O.AddPair('id',C.Id); O.AddPair('scene',C.Scene); O.AddPair('speaker',C.SpeakerId);
    O.AddPair('subtitle',C.Subtitle); AddN(O,'start',Start); AddN(O,'duration',FProject.CueDuration(C));
    var Scene := FProject.Scene(C.Scene); var Image := C.Background;
    if Scene<>nil then Image := Scene.Image;
    if Scene<>nil then O.AddPair('sceneTitle',Scene.Title) else O.AddPair('sceneTitle',C.Scene);
    var ImageName := ExtractFileName(Image);
    var Stem := ChangeFileExt(ImageName,''); var InternalName := Length(Stem)=64;
    if InternalName then for var Ch in Stem do
      if not CharInSet(Ch,['0'..'9','a'..'f','A'..'F']) then begin InternalName := False; Break; end;
    if InternalName then begin
      if Scene<>nil then ImageName := Scene.Title+'の画像' else ImageName := 'シーン画像';
    end;
    O.AddPair('imageName',ImageName);
    O.AddPair('image',ResolveMoviePath(FProject.FileName,Image));
    var Speaker := FProject.Speaker(C.SpeakerId); O.AddPair('speakerName',Speaker.Name);
    var CharacterName := ''; var MotionLabel := C.Expression+' / '+C.Motion;
    for var Character in FProject.Characters do if Character.SpeakerId=C.SpeakerId then begin
      if CharacterName<>'' then CharacterName := CharacterName+', '; CharacterName := CharacterName+Character.Name;
      if (Character.ActiveMotion<>'') and (Start+FProject.CueDuration(C)>Character.MotionStart) and
        ((Character.MotionDuration<0) or (Start<Character.MotionStart+Character.MotionDuration)) then MotionLabel := Character.ActiveMotion;
    end;
    if CharacterName='' then CharacterName := Speaker.Name;
    O.AddPair('characterName',CharacterName); O.AddPair('motionLabel',MotionLabel);
    AddB(O,'audioReady',FProject.AudioReady(C)); AddN(O,'audioSeconds',C.AudioSeconds); AddN(O,'pause',C.Pause);
    O.AddPair('text',C.Text); O.AddPair('acting',C.Acting.Json); O.AddPair('expression',C.Expression); O.AddPair('motion',C.Motion); A.AddElement(O);
  end;
  A := TJSONArray.Create; Result.AddPair('scenes',A); Start := 0;
  for var S in FProject.Scenes do begin
    var O := S.Json; AddN(O,'start',Start); AddN(O,'duration',FProject.SceneDuration(S)); A.AddElement(O);
    Start := Start+FProject.SceneDuration(S);
  end;
end;
procedure ReplacePair(O: TJSONObject; const Key: string; Value: TJSONValue);
begin O.RemovePair(Key).Free; O.AddPair(Key,Value); end;
procedure Merge(O,Args: TJSONObject; const Allowed: array of string);
begin
  for var Key in Allowed do if Args.GetValue(Key)<>nil then ReplacePair(O,Key,Args.GetValue(Key).Clone as TJSONValue);
end;
function ProductionNeed(const Key,Code,Message,Subject: string): TJSONObject;
begin
  Result := ParseObject('{"state":"blocked","done":true,"canResume":true,"needs":[],"result":{}}');
  Result.AddPair('requestKey',Key);
  var Need := TJSONObject.Create; Need.AddPair('code',Code); Need.AddPair('message',Message);
  Need.AddPair('subjectId',Subject); Need.AddPair('nextAction','movie-production-resume');
  AddB(Need,'blocking',True); JA(Result,'needs').AddElement(Need);
end;

function TRigmMovieSession.ProductionStatus(const Key: string): TJSONObject;
begin
  var K := Key; if K='' then K := FProductionKey;
  var Entry: TJSONObject;
  if not FProductions.TryGetValue(K,Entry) then Exit(ProductionNeed(K,'request_unknown','Unknown requestKey.','requestKey'));
  if (FJob<>nil) and (JS(Entry,'jobId')=FJob.Id) then begin
    var J := FJob.Status;
    try
      if J.GetValue('production')<>nil then Result := JO(J,'production').Clone as TJSONObject
      else Result := ParseObject('{"needs":[],"result":{},"canResume":true}');
      ReplacePair(Result,'state',TJSONString.Create(JS(J,'state'))); AddB(Result,'done',JB(J,'done'));
      if MatchText(JS(J,'state'),['failed','cancelled']) then begin
        var Need := TJSONObject.Create; Need.AddPair('code','job_'+JS(J,'state'));
        Need.AddPair('message',JS(J,'error')); Need.AddPair('nextAction','movie-production-resume');
        JA(Result,'needs').AddElement(Need);
      end;
      // The report is already at this response's top level; keep job progress compact.
      J.RemovePair('production').Free; Result.AddPair('job',J.Clone as TJSONObject);
    finally J.Free; end;
  end else if Entry.GetValue('status')<>nil then Result := JO(Entry,'status').Clone as TJSONObject
  else Result := ProductionNeed(K,'request_not_started','Request has not started.','requestKey');
  ReplacePair(Result,'requestKey',TJSONString.Create(K));
  ReplacePair(Result,'projectId',TJSONString.Create(JS(Entry,'projectId')));
  ReplacePair(Result,'revision',TJSONNumber.Create(FProject.Revision));
  ReplacePair(Result,'attempt',TJSONNumber.Create(JI(Entry,'attempt')));
  ReplacePair(Result,'busy',TJSONBool.Create(not JB(Result,'done',True)));
  ReplacePair(Result,'idempotenceScope',TJSONString.Create('current session, last 64 requests; existing output files are never overwritten'));
end;

procedure TRigmMovieSession.CollectProduction(JobStatus: TJSONObject);
begin
  var Entry: TJSONObject;
  if not FProductions.TryGetValue(FProductionKey,Entry) or (JS(Entry,'jobId')<>FJob.Id) then Exit;
  var Outcome := ProductionStatus(FProductionKey);
  ReplacePair(Entry,'status',Outcome);
  if FJob.Catalog<>'' then begin
    FDiagnostics.Free; FDiagnostics := ParseObject(FJob.Catalog);
    if FDiagnostics.GetValue('speakers')<>nil then begin FCatalog.Free; FCatalog := JA(FDiagnostics,'speakers').Clone as TJSONArray; end;
    if FDiagnostics.GetValue('assets')<>nil then begin FAssets.Free; FAssets := JO(FDiagnostics,'assets').Clone as TJSONObject; end;
  end;
end;

function TRigmMovieSession.Produce(Args: TJSONObject; Resume: Boolean): TJSONObject;
var Entry: TJSONObject; Next: TRigmMovieProject; Options: TJSONObject;
begin
  var Key := JS(Args,'requestKey');
  if (Key.Trim='') or (Length(Key)>128) then Exit(ProductionNeed(Key,'request_key_invalid','A requestKey of 1 to 128 characters is required.','requestKey'));
  var Exists := FProductions.TryGetValue(Key,Entry);
  if Exists and not Resume then begin
    if JS(Entry,'signature')<>MovieProductionSignature(Args) then
      Exit(ProductionNeed(Key,'request_conflict','requestKey is already used for different instructions.','requestKey'));
    Exit(ProductionStatus(Key));
  end;
  if Resume and not Exists then Exit(ProductionNeed(Key,'request_unknown','Unknown requestKey.','requestKey'));
  if Exists then begin
    var Old := ProductionStatus(Key);
    try
      if (JS(Old,'state')='succeeded') or not JB(Old,'done',True) then Exit(Old.Clone as TJSONObject);
    finally Old.Free; end;
    if JS(Entry,'projectId')<>FProject.Id then Exit(ProductionNeed(Key,'project_changed','The production project was replaced.','projectId'));
  end;
  if Busy then Exit(ProductionNeed(Key,'job_busy','Another job is running.','jobId'));
  if (JS(Args,'projectId')<>FProject.Id) or (JI(Args,'revision',-1)<>FProject.Revision) then
    Exit(ProductionNeed(Key,'revision_stale','Read movie-status and use its current projectId/revision.','revision'));
  if not Exists then begin
    Entry := TJSONObject.Create; Entry.AddPair('signature',MovieProductionSignature(Args));
    Entry.AddPair('arguments',Args.Clone as TJSONObject); Entry.AddPair('projectId',FProject.Id);
    AddN(Entry,'attempt',0); FProductions.Add(Key,Entry); FProductionOrder.Add(Key);
    while FProductionOrder.Count>64 do begin FProductions.Remove(FProductionOrder[0]); FProductionOrder.Delete(0); end;
  end;
  FProductionKey := Key;
  Options := TJSONObject.Create; Next := nil;
  try
    if not Resume then begin Options.Free; Options := JO(Entry,'arguments').Clone as TJSONObject; end
    else begin
      // Resume the current project, including partial audio, and apply only supplied corrections.
      if JI(Entry,'attempt')=0 then begin Options.Free; Options := JO(Entry,'arguments').Clone as TJSONObject; end;
      Merge(Options,JO(Entry,'arguments'),['deliver','previewTime']);
      Merge(Options,Args,['script','scriptPath','format','settings','voices','acting','outputPath','previewPath','deliver','previewTime']);
      if (JI(Entry,'attempt')>0) and (Options.GetValue('outputPath')=nil) then Options.AddPair('outputPath',FProject.OutputTarget);
    end;
    var Deliver := JS(Options,'deliver','video');
    if not MatchText(Deliver,['video','preview']) then begin
      Result := ProductionNeed(Key,'deliver_invalid','deliver must be video or preview.','deliver');
      ReplacePair(Entry,'status',Result.Clone as TJSONObject); Exit;
    end;
    try Next := MovieProductionProject(FProject,Options,Key);
    except on E: Exception do begin
      Result := ProductionNeed(Key,'input_invalid',E.Message,'script/settings/voices/acting');
      ReplacePair(Entry,'status',Result.Clone as TJSONObject); Exit;
    end; end;
    Commit(Next); Next := nil; FPlaying := False;
    FreeAndNil(FJob); FJob := TRigmMovieJob.Create(FProject,'production',FProject.OutputTarget,0,Options);
    ReplacePair(Entry,'jobId',TJSONString.Create(FJob.Id));
    ReplacePair(Entry,'attempt',TJSONNumber.Create(JI(Entry,'attempt')+1));
    // Production retries need their saved options: only production-resume may restart them.
    FLastKind := ''; FRetryPending := False; FCollected := False; FJob.Start;
    Result := ProductionStatus(Key);
  finally Next.Free; Options.Free; end;
end;

function TRigmMovieSession.Execute(const Command: string; Args: TJSONObject): TJSONObject;
var Next: TRigmMovieProject; O: TJSONObject; Cues: TJSONArray;
begin
  Poll;
  if MatchText(Command,['workflow-run','produce','production-resume','audio-generate','job-retry','save','open','undo','redo']) then begin
    if GuiLocked and (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Codex edit session holds the project');
    if (Args.GetValue('editToken')<>nil) and ((JS(Args,'editToken')<>FEditToken) or (JI(Args,'editEpoch',FEditEpoch)<>FEditEpoch)) then raise ERigm.Create('Expired edit token');
  end;
  if MatchText(Command,['workflow-status','workflow-next','workflow-back','workflow-run']) then Exit(WorkflowCommand(Command,Args));
  if Command='produce' then Exit(Produce(Args,False));
  if Command='production-resume' then Exit(Produce(Args,True));
  if Command='production-status' then Exit(ProductionStatus(JS(Args,'requestKey')));
  if Command='production-cancel' then begin
    var Key := JS(Args,'requestKey',FProductionKey); var Entry: TJSONObject;
    if FProductions.TryGetValue(Key,Entry) and (FJob<>nil) and (JS(Entry,'jobId')=FJob.Id) and not FJob.Done then FJob.Cancel;
    Exit(ProductionStatus(Key));
  end;
  if Command='edit-status' then Exit(EditStatus);
  if Command='edit-begin' then begin
    RequireRevision(Args); Inc(FEditEpoch); FEditToken := NewRigmId; FEditState := 'editing';
    FEditDeadline := GetTickCount64+UInt64(EnsureRange(JI(Args,'leaseSeconds',60),10,600))*1000;
    Result := EditStatus; Result.AddPair('editToken',FEditToken); Exit;
  end;
  if Command='edit-heartbeat' then begin
    if not GuiLocked or (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Edit lease expired');
    FEditDeadline := GetTickCount64+UInt64(EnsureRange(JI(Args,'leaseSeconds',60),10,600))*1000; Exit(EditStatus);
  end;
  if MatchText(Command,['edit-end','edit-fail','edit-release']) then begin
    if (Command<>'edit-release') and (not GuiLocked or (JS(Args,'editToken')<>FEditToken)) then raise ERigm.Create('Edit lease expired');
    FEditToken := ''; Inc(FEditEpoch); FEditState := 'released';
    if Command='edit-end' then FEditState := 'completed';
    if Command='edit-fail' then FEditState := 'failed';
    if FJob<>nil then FJob.Cancel; Inc(FProject.Revision); Exit(EditStatus);
  end;
  if Command='composition-requests' then Exit(CompositionRequests(FProject));
  if IsCompositionCommand(Command) then begin
    RequireRevision(Args); Next := FProject.Clone;
    try
      if (Command='select-motion') and (Args.GetValue('start')=nil) then AddN(Args,'start',FTime);
      var Styles: TJSONArray := nil; if FCatalogUrl=Next.EngineUrl then Styles := FCatalog;
      ApplyCompositionCommand(Next,Command,Args,Styles); Commit(Next); Next := nil;
    finally Next.Free; end;
    Exit(Status);
  end;
  if Command='status' then Exit(Status);
  if Command='schema' then begin
    Result := MovieSchema; Result.AddPair('pipeEnvelope','schemaVersion=1, requestId, command, args');
    Result.AddPair('editing','mutations require status.projectId + revision; snapshot job; generated audio is undoable; no RIGM edits');
    Result.AddPair('examples',MovieExamples);
    Result.AddPair('commands',ParseObject('{"status":{},'+
      '"project":{"offset":0,"limit":20},'+
      '"import-script":{"text":"text or JSON","path":"optional local file","format":"text|json"},'+
      '"update-project":{"title":"string","character":"local .rigm or @sample","engineUrl":"loopback URL","width":1920,"height":1080,"fps":30,"outputPreset":"draft|hd|fullhd|custom","encodeProfile":"fast|balanced|quality","backgroundColor":3156000,"ffmpeg":"optional existing local ffmpeg.exe","outputTarget":"new .mp4 or .avi"},'+
      '"update-cue":{"id":"cue id","text":"string","subtitle":"string","pause":0.3,"expression":"neutral|smile|serious|sad","motion":"idle|still|nod|emphasis","background":"local image","parameters":{},"acting":{}},'+
      '"add-cue":{"cue":{},'+
      '"index":0},'+
      '"delete-cue":{"id":"cue id"},'+
      '"move-cue":{"id":"cue id","index":0},'+
      '"update-speaker":{"id":"speaker id","styleId":3,"speed":1,"pitch":0,"intonation":1,"volume":1},'+
      '"speakers-refresh":{},'+
      '"speaker-list":{},'+
      '"audio-generate":{"directory":"optional generated asset directory"},'+
      '"job-status":{"scope":"main (default)|diagnostics"},'+
      '"job-cancel":{"scope":"all (default)|main|diagnostics"},'+
      '"job-retry":{},'+
      '"timeline":{},'+
      '"seek":{"time":0},'+
      '"preview":{"time":0,"path":"optional new PNG"},'+
      '"export":{"path":"new .avi or .mp4"},'+
      '"save":{"path":".rigmovie"},'+
      '"open":{"path":".rigmovie"},'+
      '"undo":{},'+
      '"redo":{},'+
      '"play":{},'+
      '"pause":{},'+
      '"playback-audio":{"time":0,"path":"optional new WAV"},'+
      '"open-ui":{},"assets-refresh":{},"assets":{"offset":0,"limit":20},"waveform-refresh":{},"waveform":{},'+
      '"preparation":{"outputPath":"optional target override; read only"},"diagnostics-refresh":{},'+
      '"produce":{"requestKey":"unique stable key","script":"optional text or JSON object; existing script retained when omitted","scriptPath":"optional local file","settings":{},"voices":{"speakerId":"styleId or voice settings"},"acting":{},"outputPath":"optional new output; default derived from configured location","deliver":"video (default)|preview","previewPath":"optional new PNG","previewTime":0.2},'+
      '"production-status":{"requestKey":"optional; defaults to latest"},'+
      '"production-resume":{"requestKey":"blocked/failed/cancelled key","settings":{},"voices":{},"outputPath":"optional corrected path"},'+
      '"production-cancel":{"requestKey":"optional; defaults to latest"},'+
      '"workflow-status":{},"workflow-next":{},"workflow-back":{"stage":"optional earlier script|setup|audio|preview|export"},'+
      '"workflow-run":{"text":"script stage only","path":"optional new preview/export path","time":"optional preview seconds","directory":"optional audio directory"}}'));
    var Extra := ParseObject('{"composition-enable":{},"add-character":{"character":{"file":".rigm","speaker":"speaker id","x":1370,"y":130,"width":520,"height":900}},'+
      '"update-character":{"id":"character id","x":0,"y":0,"width":520,"height":900,"visible":true,"rigSafe":true},"delete-character":{"id":"character id"},'+
      '"add-scene":{"scene":{"title":"string"},"text":"initial spoken line","subtitle":"display text","index":0},'+
      '"update-scene":{"id":"scene id","image":"local image","description":"persistent scene text","imagePrompt":"generation prompt","animation":{"explainImage":"optional boolean; enables image-direction head support, not pupil gaze"}},'+
      '"delete-scene":{"id":"scene id"},"move-scene":{"id":"scene id","index":0},"resize-scene":{"id":"scene id","duration":"seconds, cannot trim existing speech"},'+
      '"register-expression":{"id":"character id","emotion":"neutral|happy|sad|serious|angry|gentle","preset":{"variants":[],"blinkAnimate":true,"mouthAnimate":true,"rigSafe":true}},'+
      '"register-motion":{"id":"character id","name":"motion name","motion":{"loop":true,"frames":[{"image":"local frame image","duration":0.1}]}},'+
      '"select-motion":{"id":"character id","name":"registered motion name","start":"timeline seconds; default current seek","duration":"-1 until stopped or nonnegative seconds"},"stop-motion":{"id":"character id"},'+
      '"analyze-script":{"id":"optional cue id; deterministic suggestion, explicit generation only"},'+
      '"update-subtitle":{"id":"cue id","subtitle":"display text; never changes speech"},"update-dialogue":{"id":"cue id","text":"spoken text; no auto synthesis"},'+
      '"composition-requests":{},"edit-begin":{"leaseSeconds":60},"edit-status":{},"edit-heartbeat":{"editToken":"token","leaseSeconds":60},'+
      '"edit-end":{"editToken":"token"},"edit-fail":{"editToken":"token"},"edit-release":{"manual":true}}');
    try for var Pair in Extra do JO(Result,'commands').AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue); finally Extra.Free; end;
    Exit;
  end;
  if Command='project' then begin
    Result := FProject.Json; Cues := TJSONArray.Create;
    var Offset := Max(0,JI(Args,'offset')); var Limit := EnsureRange(JI(Args,'limit',20),1,100);
    for var I := Offset to Min(FProject.Cues.Count-1,Offset+Limit-1) do Cues.AddElement(FProject.Cues[I].Json);
    Result.RemovePair('cues').Free; Result.AddPair('cues',Cues); AddN(Result,'total',FProject.Cues.Count); AddN(Result,'offset',Offset);
    Exit;
  end;
  if Command='timeline' then Exit(Timeline);
  if Command='preparation' then Exit(Preparation(JS(Args,'outputPath')));
  if Command='diagnostics-refresh' then begin
    if (FDiagnosticJob<>nil) and not FDiagnosticJob.Done then Exit(FDiagnosticJob.Status);
    FreeAndNil(FDiagnosticJob); FDiagnosticJob := TRigmMovieJob.Create(FProject,'diagnostics','',0);
    FDiagnosticCollected := False; FDiagnosticJob.Start; Exit(FDiagnosticJob.Status);
  end;
  if Command='assets-refresh' then Exit(StartJob('assets','',0));
  if Command='waveform-refresh' then Exit(StartJob('waveform','',0));
  if Command='waveform' then begin
    Result := FWaveform.Clone as TJSONObject; AddB(Result,'current',(FWaveform.GetValue('audioStamp')<>nil) and (JS(FWaveform,'audioStamp')=MovieAudioStamp(FProject))); Exit;
  end;
  if Command='assets' then begin
    Result := FAssets.Clone as TJSONObject;
    if FAssets.GetValue('groups')<>nil then begin
      var Groups := JA(FAssets,'groups'); var A := TJSONArray.Create; var Offset := Max(0,JI(Args,'offset')); var Limit := EnsureRange(JI(Args,'limit',20),1,100);
      for var I := Offset to Min(Groups.Count-1,Offset+Limit-1) do A.AddElement(Groups[I].Clone as TJSONObject);
      Result.RemovePair('groups').Free; Result.AddPair('groups',A); AddN(Result,'total',Groups.Count); AddN(Result,'offset',Offset);
    end;
    Exit;
  end;
  if Command='speaker-list' then begin Result := TJSONObject.Create; Result.AddPair('styles',FCatalog.Clone as TJSONArray); Exit; end;
  if Command='job-status' then begin
    var Id := JS(Args,'jobId');
    if (Id<>'') and ((FJob=nil) or (FJob.Id<>Id)) then begin
      var Saved: TJSONObject;
      if not FFinishedJobs.TryGetValue(Id,Saved) then raise ERigm.Create('Job identifier is no longer available');
      Exit(Saved.Clone as TJSONObject);
    end;
    if JS(Args,'scope')='diagnostics' then begin
      if FDiagnosticJob<>nil then Exit(FDiagnosticJob.Status);
      Exit(ParseObject('{"done":true,"state":"none"}'));
    end;
    Exit(JobStatus);
  end;
  if Command='job-cancel' then begin
    if JS(Args,'scope')<>'diagnostics' then begin FRetryPending := False; if FJob<>nil then FJob.Cancel; end;
    if (JS(Args,'scope')<>'main') and (FDiagnosticJob<>nil) then FDiagnosticJob.Cancel;
    Exit(Status);
  end;
  if Command='job-retry' then begin
    if FLastKind='' then raise ERigm.Create('再試行するジョブがありません。');
    if Busy and FAutomaticPreview then begin
      FJob.Cancel; FObsoletePreviews.Add(FJob); FJob := nil;
      Exit(StartJob(FLastKind,FLastOutput,FLastTime));
    end;
    if Busy then begin
      O := FJob.Status;
      try if not JB(O,'cancelRequested') then raise ERigm.Create('処理中のジョブを取消してから再試行してください。'); finally O.Free; end;
      FRetryPending := True; Exit(Status);
    end;
    Exit(StartJob(FLastKind,FLastOutput,FLastTime));
  end;
  if MatchText(Command,['audio-generate','job-retry','workflow-run','produce','production-resume','save','open','undo','redo']) then begin
    if GuiLocked and (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Codex edit session holds the project');
    if (Args.GetValue('editToken')<>nil) and (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Expired edit token');
  end;
  if Command='speakers-refresh' then Exit(StartJob('speakers','',0));
  if Command='audio-generate' then Exit(StartJob('audio',JS(Args,'directory'),0));
  if Command='playback-audio' then Exit(StartJob('playback-audio',JS(Args,'path'),JN(Args,'time',FTime)));
  if Command='export' then Exit(StartJob('export',ExpandFileName(JS(Args,'path',FProject.OutputTarget)),0));
  if Command='preview' then begin FTime := EnsureRange(JN(Args,'time',FTime),0.0,FProject.Duration); Exit(StartJob('preview',JS(Args,'path'),FTime)); end;
  if Command='seek' then begin FTime := EnsureRange(JN(Args,'time'),0.0,FProject.Duration); Exit(Status); end;
  if Command='play' then begin FPlaying := True; Exit(Status); end;
  if Command='pause' then begin FPlaying := False; Exit(Status); end;
  if Command='save' then begin
    if GuiLocked and (JS(Args,'editToken')<>FEditToken) then raise ERigm.Create('Codex edit session holds the project; use its editToken or release the lock');
  if (Args.GetValue('editToken')<>nil) and ((JS(Args,'editToken')<>FEditToken) or (JI(Args,'editEpoch',FEditEpoch)<>FEditEpoch)) then raise ERigm.Create('Expired Codex edit token');
  RetireAutomaticPreview;
  if Busy then raise ERigm.Create('ジョブ完了後に保存してください。');
    var Path := JS(Args,'path',FProject.FileName); if Path='' then raise ERigm.Create('保存先を指定してください。');
    SaveMovie(FProject,Path,IsMovieWorkPath(Path)); AppSettings.RecordMovie(FProject,FTime,FResumeCue); Exit(Status);
  end;
  RequireRevision(Args);
  if Command='undo' then begin
    if FUndo.Count=0 then raise ERigm.Create('取り消す編集がありません。'); Next := FUndo.Extract(FUndo.Last);
    Next.Revision := FProject.Revision+1; Next.Modified := True; FRedo.Add(FProject); FProject := Next; Exit(Status);
  end;
  if Command='redo' then begin
    if FRedo.Count=0 then raise ERigm.Create('やり直す編集がありません。'); Next := FRedo.Extract(FRedo.Last);
    Next.Revision := FProject.Revision+1; Next.Modified := True; FUndo.Add(FProject); FProject := Next; Exit(Status);
  end;
  if Command='open' then begin
    Next := LoadMovie(JS(Args,'path'));
    try SetProject(Next); Next := nil; finally Next.Free; end;
    FTime := AppSettings.ResumeMovie(FProject,FResumeCue);
    AppSettings.RecordMovie(FProject,FTime,FResumeCue);
    Exit(Status);
  end;
  if Command='import-script' then begin
    var Text := JS(Args,'text'); var Path := JS(Args,'path');
    if Path<>'' then begin if TFile.GetSize(Path)>16*1024*1024 then raise ERigm.Create('台本ファイルが大きすぎます。'); Text := TFile.ReadAllText(Path,TEncoding.UTF8); end;
    var IsJson := JS(Args,'format','text')='json';
    if IsJson then begin
      O := ParseObject(Text);
      try
        var Current := FProject.Json;
        try
          var Character := JS(Current,'character');
          if Character<>'@sample' then ReplacePair(Current,'character',TJSONString.Create(ResolveMoviePath(FProject.FileName,Character)));
          for var Key in ['character','engineUrl','width','height','fps','backgroundColor','ffmpeg','encodeProfile','outputTarget'] do
            if O.GetValue(Key)=nil then O.AddPair(Key,Current.GetValue(Key).Clone as TJSONValue);
          Next := TRigmMovieProject.FromJson(O);
        finally Current.Free; end;
      finally O.Free; end;
    end else Next := TRigmMovieProject.FromText(Text);
    try
      if not IsJson then begin
        Next.CharacterFile := FProject.CharacterFile; Next.EngineUrl := FProject.EngineUrl;
        Next.Width := FProject.Width; Next.Height := FProject.Height; Next.Fps := FProject.Fps;
        Next.BackgroundColor := FProject.BackgroundColor; Next.FfmpegExe := FProject.FfmpegExe;
        Next.EncodeProfile := FProject.EncodeProfile;
        Next.OutputTarget := FProject.OutputTarget;
        Next.Layout := FProject.Layout; Next.ThemeBackground := FProject.ThemeBackground; Next.LDirection := FProject.LDirection;
        for var Character in FProject.Characters do begin
          if Next.Speaker(Character.SpeakerId)=nil then begin
            var ExistingSpeaker := FProject.Speaker(Character.SpeakerId); var Added := TRigmMovieSpeaker.Create;
            Added.Id := ExistingSpeaker.Id; Added.Name := ExistingSpeaker.Name; Added.StyleId := ExistingSpeaker.StyleId;
            Added.Speed := ExistingSpeaker.Speed; Added.Pitch := ExistingSpeaker.Pitch; Added.Intonation := ExistingSpeaker.Intonation; Added.Volume := ExistingSpeaker.Volume;
            Next.Speakers.Add(Added);
          end;
          var CharacterJson := Character.Json;
          try Next.Characters.Add(RigmMovieComposition.TRigmMovieCharacter.FromJson(CharacterJson)); finally CharacterJson.Free; end;
        end;
        if (FProject.Scenes.Count>0) or (FProject.Characters.Count>0) then begin
          Next.EnableComposition;
          for var Scene in Next.Scenes do for var Existing in FProject.Scenes do if Scene.Title=Existing.Title then begin
            Scene.Image := Existing.Image; Scene.Description := Existing.Description; Scene.ImagePrompt := Existing.ImagePrompt; Scene.Padding := Existing.Padding;
            Break;
          end;
        end;
      end else begin
        var Base := FProject.FileName; if Path<>'' then Base := ExpandFileName(Path);
        if Next.CharacterFile<>'@sample' then Next.CharacterFile := ResolveMoviePath(Base,Next.CharacterFile);
        Next.FfmpegExe := ResolveMoviePath(Base,Next.FfmpegExe);
        for var C in Next.Cues do begin
          C.WaveFile := ResolveMoviePath(Base,C.WaveFile); C.LabFile := ResolveMoviePath(Base,C.LabFile); C.Background := ResolveMoviePath(Base,C.Background);
        end;
      end;
      Next.FileName := FProject.FileName; Next.Id := FProject.Id;
      if not IsJson then for var S in Next.Speakers do begin
        var Existing := FProject.Speaker(S.Id);
        if Existing<>nil then begin S.StyleId := Existing.StyleId; S.Speed := Existing.Speed; S.Pitch := Existing.Pitch; S.Intonation := Existing.Intonation; S.Volume := Existing.Volume; end;
      end;
      Commit(Next); Next := nil;
    finally Next.Free; end;
    Exit(Status);
  end;
  O := FProject.Json;
  try
    if Command='update-project' then begin
      if Args.GetValue('outputPreset')<>nil then begin
        var W,H,F: Integer; MoviePresetDimensions(JS(Args,'outputPreset'),W,H,F);
        if W>0 then begin ReplacePair(O,'width',TJSONNumber.Create(W)); ReplacePair(O,'height',TJSONNumber.Create(H)); ReplacePair(O,'fps',TJSONNumber.Create(F)); end;
      end;
      Merge(O,Args,['title','character','engineUrl','width','height','fps','backgroundColor','ffmpeg','encodeProfile','outputTarget','layout','themeBackground','lDirection']);
      if (Args.GetValue('layout')<>nil) and SameText(JS(O,'layout'),'l') and (O.GetValue('characters')<>nil) then begin
        var A := JA(O,'characters'); var Index := 0;
        for var V in A do begin
          var C := TJSONObject(V); var LeftSide := JS(O,'lDirection')='left';
          var BoxWidth := Min(JN(C,'width',520),660.0/Max(1,A.Count));
          var X := 50+Index*BoxWidth; if not LeftSide then X := 1210+Index*BoxWidth;
          ReplacePair(C,'x',TJSONNumber.Create(X)); ReplacePair(C,'width',TJSONNumber.Create(BoxWidth)); Inc(Index);
        end;
      end;
    end
    else if Command='update-cue' then begin
      var Found := False;
      for var V in JA(O,'cues') do if JS(TJSONObject(V),'id')=JS(Args,'id') then begin
        Merge(TJSONObject(V),Args,['scene','speaker','text','subtitle','pause','expression','motion','background','parameters','emotion','voiceStyleId']);
        if Args.GetValue('acting')<>nil then Merge(JO(TJSONObject(V),'acting'),JO(Args,'acting'),
          ['mouthMode','blinkMode','mouthGain','lipLead','blinkStrength','blinkInterval','blinkDuration','blinkPhase','headGain','bodyGain','onset','duration','fadeIn','fadeOut','variants','imageAttention']);
        Found := True; Break;
      end;
      if not Found then raise ERigm.Create('セリフIDがありません。');
    end else if Command='update-speaker' then begin
      var Found := False;
      for var V in JA(O,'speakers') do if JS(TJSONObject(V),'id')=JS(Args,'id') then begin
        Merge(TJSONObject(V),Args,['name','styleId','speed','pitch','intonation','volume']); Found := True; Break;
      end;
      if not Found then raise ERigm.Create('話者IDがありません。');
    end else if Command='add-cue' then begin
      Cues := JA(O,'cues'); var Index := EnsureRange(JI(Args,'index',Cues.Count),0,Cues.Count);
      var A := TJSONArray.Create;
      for var I := 0 to Cues.Count do begin
        if I=Index then A.AddElement(JO(Args,'cue').Clone as TJSONObject);
        if I<Cues.Count then A.AddElement(Cues[I].Clone as TJSONObject);
      end;
      ReplacePair(O,'cues',A);
    end else if MatchText(Command,['delete-cue','move-cue']) then begin
      Cues := JA(O,'cues'); var Index := -1;
      for var I := 0 to Cues.Count-1 do if JS(TJSONObject(Cues[I]),'id')=JS(Args,'id') then Index := I;
      if Index<0 then raise ERigm.Create('セリフIDがありません。');
      var Item := Cues.Remove(Index);
      try
        if Command='move-cue' then begin
          var Target := EnsureRange(JI(Args,'index'),0,Cues.Count); var A := TJSONArray.Create;
          for var I := 0 to Cues.Count do begin
            if I=Target then A.AddElement(Item.Clone as TJSONObject);
            if I<Cues.Count then A.AddElement(Cues[I].Clone as TJSONObject);
          end;
          ReplacePair(O,'cues',A);
        end;
      finally Item.Free; end;
    end else raise ERigm.Create('不明な動画命令です: '+Command);
    Next := TRigmMovieProject.FromJson(O);
    try Next.FileName := FProject.FileName; Commit(Next); Next := nil; finally Next.Free; end;
  finally O.Free; end;
  Result := Status;
end;
end.
