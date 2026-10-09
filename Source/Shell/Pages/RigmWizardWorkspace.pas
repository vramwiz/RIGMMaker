unit RigmWizardWorkspace;

// 台本/動画ページ共通の既存Session所有者。UIを作らず、ページより長く生存する。
interface
uses System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Vcl.ExtCtrls,
  RigmMovieSession, RigmMovieModel, RigmPageNavigation, RigmWizardPipe, ArtPipeProtocol, RigmThumbnailCache, RigmMovieJobs, RigmMovieImageTransfer, Vcl.Graphics;
type
  TRigmWizardWorkspace = class(TComponent)
  private
    FSessions: TObjectList<TRigmMovieSession>; FActive: TRigmMovieSession;
    FOnNavigate: TRigmNavigateEvent;
    FTimer: TTimer;
    FPipe: TRigmWizardPipe; FPage: TRigmAppPage; FOnUiCommand: TArtCommandHandler;
    FScriptDrafts: TObjectList<TRigmMovieProject>; FScriptDraft: TRigmMovieProject;
    FOnScriptChanged: TNotifyEvent;
    FScriptSavedHashes: TDictionary<string,string>;
    FThumbnails: TRigmThumbnailCache;
    FScriptViewStage: string; FPlacementEditing: Boolean;
    FVoiceJob: TRigmMovieJob; FVoiceCollected: Boolean; FVoiceCatalog: TJSONArray; FVoiceCatalogUrl,FVoiceError,FPlayVoice,FVoiceTarget: string;
    FVoiceContinuous: Boolean;
    FVoiceSequenceProjectId,FVoiceSequencePhase,FVoiceSequenceStatus: string;
    FVoiceSequenceOrder: TArray<string>; FVoiceSequenceIndex: Integer; FVoicePauseUntil: UInt64;
    FVoicePlaybackAlias,FVoicePlaybackCue,FVoicePlaybackKey: string;
    FVoicePlaybackTempFile: string;
    FVoiceAutoGenerationActive: Boolean; FVoiceAutoGenerationKey: string;
    FVoiceBindings: TJSONObject; FVoiceBindingsHash: string;
    FScriptTransfers: TRigmImageTransfers; FSceneContracts: TObjectDictionary<string,TJSONObject>;
    FSceneJob: TRigmMovieJob; FSceneCollected: Boolean; FSceneRetired: TObjectList<TRigmMovieJob>;
    FSceneBitmap: TBitmap; FSceneJobKey,FSceneFrameKey,FScenePreviewPath,FSceneError: string;
    function GetScriptTextEditing: Boolean;
    procedure PollScriptScenes;
    function ScenePreviewKey: string;
    procedure PollScriptVoice;
    procedure PollVoicePlayback;
    procedure CloseVoicePlayback;
    procedure StartVoicePlayback(const CueId: string);
    procedure AdvanceVoiceContinuous;
    procedure EnsureSelectedVoice;
    procedure EnsureVoiceBindings;
    function RestoreStoredCastingVoices(Project: TRigmMovieProject): Boolean;
    function ScriptResumeView(Project: TRigmMovieProject): string;
    procedure StoreScript(Snapshot: TRigmMovieProject; const ViewStage: string);
    procedure ScriptChanged;
    function ScriptPath(Project: TRigmMovieProject): string;
    procedure CheckScript(Project: TRigmMovieProject);
    function SubtitleAdvanceReason(RequireComplete: Boolean = True): string; // GUIの工程選択は入力確認も行い、外部工程選択は完了済みを要求する。
    procedure Poll(Sender: TObject);
    function CharacterLibrary: TJSONObject;
    function RegisterCharacter(Args: TJSONObject): TJSONObject;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ActiveSession: TRigmMovieSession;
    procedure NewWork;
    procedure OpenWork(const Path: string);
    procedure RequestMovie(Sender: TObject);
    function RequestFinish: Boolean;
    procedure StartPipe(const Root: string);
    function Command(const Name: string; Args: TJSONObject): TJSONObject;
    function ExecuteWorkspace(const Name: string; Args: TJSONObject): TJSONObject;
    function RegisterDroppedCharacter(const Path: string): TJSONObject;
    procedure NewScriptDraft;
    procedure OpenScriptDraft(const Path: string);
    procedure SetScriptTitle(const Value: string);
    procedure SetScriptType(const Value: string); // 固定ID。GUIとパイプの共通更新。
    procedure SetScriptStage(const Value: string);
    procedure SetScriptCharacters(Paths: TJSONArray);
    procedure SetScriptLayout(const Choice, BackgroundTone: string);
    procedure NextScriptDraft;
    function CurrentScriptStage: string;
    procedure SetScriptPlacement(Args: TJSONObject);
    procedure SelectScriptPlacement(const Path: string);
    procedure BeginPlacementEdit;
    procedure EndPlacementEdit;
    property PlacementEditing: Boolean read FPlacementEditing;
    procedure BeginScriptTextEdit;
    procedure EndScriptTextEdit;
    procedure SetScriptText(const Section,Text: string);
    procedure SelectScriptSection(const Section: string);
    function ReadScriptText(Args: TJSONObject): TJSONObject;
    procedure SelectSubtitle(const CueId: string); // 表示対象を共通正本に保持する。
    procedure MoveSubtitle(Delta: Integer);
    procedure EditSubtitle(const CueId,Text,Note: string); // 字幕・メモのみ更新する。
    procedure SetSubtitleBreak(const CueId: string; Offset: Integer);
    procedure MoveSubtitleBreak(const CueId: string; Delta, DefaultOffset: Integer);
    procedure CompleteSubtitles; // 人の入力完了。音声準備とは区別する。
    function ReadSubtitles(Args: TJSONObject): TJSONObject;
    procedure SelectVoice(const CueId: string);
    procedure SetVoiceAutoGeneration(Value: Boolean);
    procedure MoveVoice(Delta: Integer);
    procedure EditVoice(const CueId,Reading: string; Settings: TJSONObject);
    procedure SetVoiceEngine(const Url: string);
    procedure RefreshVoiceCatalog;
    procedure BindVoice(Number,StyleId: Integer; const Uuid: string);
    procedure BindVoicePerson(Number: Integer; const Uuid: string);
    procedure SetVoiceState(const CueId: string; StyleId: Integer);
    procedure SaveCharacterVoice(Number: Integer);
    procedure GenerateVoice(const CueId: string; Play: Boolean; ForSequence: Boolean=False);
    procedure StartVoiceContinuous(const CueId: string);
    procedure PrepareVoiceEngine(const EngineExe: string);
    procedure EditVoiceQuery(const CueId, QueryJson: string);
    function VoicePlaying: Boolean;
    function VoiceContinuous: Boolean;
    procedure CancelVoice;
    procedure StopVoice;
    procedure CompleteVoice;
    function VoiceBusy: Boolean;
    function VoiceStatus: TJSONObject;
    procedure SelectVoiceEffects(const CueId: string);
    procedure EditVoiceEffects(const CueId: string; Settings: TJSONObject);
    procedure NotifyVoiceEffectsPreview;
    function ReadVoiceEffects(Args: TJSONObject): TJSONObject;
    function ReadVoice(Args: TJSONObject): TJSONObject;
    function ReadVoiceCatalog(Args: TJSONObject): TJSONObject;
    function VoiceCatalogReady: Boolean;
    function VoiceConnectionStatus: TJSONObject;
    function CastingAdvanceReason(RequireConnection: Boolean=True): string;
    function VoiceCatalog: TJSONArray; // 借用。実APIの直近一覧。
    procedure SelectScriptScene(const Id: string);
    procedure MoveScriptScene(Delta: Integer);
    procedure EditScriptScene(const Id,Description,Prompt,Mode: string; const Position: string='');
    procedure AdoptScriptSceneImage(const Id,Path: string);
    procedure RequestScriptSceneImage(const Id: string);
    procedure CancelScriptSceneImage(const Id: string);
    procedure UpdateScriptSceneInputs(Inputs: TJSONArray);
    procedure SetScriptSceneApproved(const Id: string; Value: Boolean); // GUI checkbox only; pipes cannot unlock.
      procedure EditScriptSceneFeedback(const Id,Feedback: string);
      procedure DeliverScriptSceneImage(Args: TJSONObject);
      procedure RequestUnapprovedScriptImages;
      function ScriptScenesAdvanceReason: string;
      procedure CompleteScriptScenes;
    procedure SetScriptSceneStart(const CueId: string; Value: Boolean);
    procedure PreviewScriptScene(Force: Boolean=False);
    function ScenePreview: Vcl.Graphics.TBitmap; // 現在の正本に一致する描画だけを借用。
    function ScriptScenePreviewStatus: TJSONObject;
    function ReadScriptScenes(Args: TJSONObject): TJSONObject;
    function ReadScriptSceneAssignment(Args: TJSONObject): TJSONObject;
    function ExecuteScriptImageTransfer(const Name: string; Args: TJSONObject): TJSONObject;
    procedure SetScriptSummaryChoice(const Choice: string);
    procedure SetScriptSummaryDraft(Draft: TJSONObject);
    procedure CompleteScriptSummary;
    function ReadScriptSummary(Args: TJSONObject): TJSONObject;
    procedure SetScriptClosingDraft(Draft: TJSONObject);
    procedure AdoptScriptClosingImage(const Kind,Path: string);
    procedure CompleteScriptClosing;
    procedure FinishScriptToEditor;
    function ReadScriptClosing(Args: TJSONObject): TJSONObject;
    procedure RequestCasting;
    procedure SubmitCasting(Args: TJSONObject);
    procedure AssignCasting(const CueId: string; Number: Integer; Confirm: Boolean);
    procedure SelectCasting(const CueId: string);
    procedure MoveCasting(Delta: Integer);
    procedure SplitCasting(const CueId: string; Offset: Integer);
    procedure MergeCasting(const CueId: string);
    function ReadCasting(Args: TJSONObject): TJSONObject;
    procedure PrepareResearch(Project: TRigmMovieProject);
    procedure UpdateResearch(const Action: string; Args: TJSONObject; Human: Boolean = False);
    function ReadResearch(Args: TJSONObject): TJSONObject;
    procedure RequestReview;
    procedure SubmitReview(Args: TJSONObject);
    procedure DecideReview(const Id,Decision,Text: string);
    procedure EditReviewDraft(const Id,Text: string);
    function ReadReview(Args: TJSONObject): TJSONObject;
    property ScriptTextEditing: Boolean read GetScriptTextEditing;
    function ScriptCharacterLibrary(ValidatePreview: Boolean = True): TJSONObject;
    function Thumbnails: TRigmThumbnailCache; // 両一覧の共有サービス。UIを所有しない。
    procedure SaveScriptDraft(ConfirmTitle: Boolean = False);
    function ScriptStatus: TJSONObject;
    function ScriptLibrary(Offset: Integer = 0; Limit: Integer = 50): TJSONObject;
    property ScriptDraft: TRigmMovieProject read FScriptDraft; // 借用。題名画面とパイプの共通状態。
    property OnScriptChanged: TNotifyEvent read FOnScriptChanged write FOnScriptChanged;
    property CurrentPage: TRigmAppPage read FPage write FPage;
    property Pipe: TRigmWizardPipe read FPipe;
    property OnUiCommand: TArtCommandHandler read FOnUiCommand write FOnUiCommand;
    property Sessions: TObjectList<TRigmMovieSession> read FSessions;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses RigmVoiceEffects, RigmVoiceEffectSettings, System.IOUtils, System.Math, System.DateUtils, System.StrUtils, Winapi.Windows, RigmJson, RigmAppSettings, PsdSession,
  PsdCharacter, PsdJson, PsdPackage, PsdProduction, RigmEditor, PsdImport, RigmStorage,
  System.Hash, ArtDocument, PsdWorkspace, RigmCharacterCatalog, RigmMovieLayout, RigmScriptPlacementModel, RigmScriptNavigationModel, RigmScriptTextModel, RigmScriptReviewModel, RigmScriptResearchModel, RigmScriptCastingModel, RigmScriptSubtitleModel, RigmScriptVoiceModel, RigmScriptVoiceSelection, System.SyncObjs, Winapi.MMSystem, RigmScriptScenesModel, RigmScriptSceneAssignmentModel, RigmScriptSummaryModel, RigmScriptClosingModel, RigmMovieCompositor, RigmMovieWorkspace, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, RigmScriptTypes;
constructor TRigmWizardWorkspace.Create(AOwner: TComponent);
begin
  inherited; FSessions := TObjectList<TRigmMovieSession>.Create(True);
  FScriptDrafts := TObjectList<TRigmMovieProject>.Create(True);
  FScriptSavedHashes := TDictionary<string,string>.Create; FVoiceCatalog := TJSONArray.Create;
  FScriptTransfers := TRigmImageTransfers.Create; FSceneContracts := TObjectDictionary<string,TJSONObject>.Create([doOwnsValues]); FSceneRetired := TObjectList<TRigmMovieJob>.Create(True);
  FTimer := TTimer.Create(Self); FTimer.Interval := 150; FTimer.OnTimer := Poll;
end;
destructor TRigmWizardWorkspace.Destroy;
begin FTimer.Enabled := False; StopVoice; FSceneJob.Free; FSceneRetired.Free; FSceneBitmap.Free; FSceneContracts.Free; FScriptTransfers.Free; FVoiceJob.Free; FVoiceBindings.Free; FVoiceCatalog.Free; FThumbnails.Free; FPipe.Free; FScriptSavedHashes.Free; FScriptDrafts.Free; FSessions.Free; inherited; end;
procedure TRigmWizardWorkspace.StartPipe(const Root: string);
begin if FPipe=nil then FPipe := TRigmWizardPipe.Create(Root,Command); end;
function TRigmWizardWorkspace.Command(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Name.StartsWith('app-') then Result := ExecuteWorkspace(Name.Substring(4),Args)
  else if Name.StartsWith('movie-') then begin
    if (Name='movie-open-ui') or (Name='movie-play') then RequestMovie(Self);
    if Name='movie-open-ui' then Result := ActiveSession.Status else Result := ActiveSession.Execute(Name.Substring(6),Args);
  end else if (Name='status') or (Name='schema') then Result := ExecuteWorkspace(Name,Args)
  else if Assigned(FOnUiCommand) then Result := FOnUiCommand(Name,Args)
  else raise Exception.Create('Editor command route is unavailable');
  if FPipe<>nil then Result.AddPair('pipes',FPipe.Info);
end;
function TRigmWizardWorkspace.ExecuteWorkspace(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if (FPlacementEditing or ScriptTextEditing) and MatchText(Name,['script-new','script-open']) then
    raise Exception.Create('GUIで入力・配置を操作中です。操作完了後に再取得してください。');
  if Name='script-status' then Exit(ScriptStatus);
  if Name='script-summary' then Exit(ReadScriptSummary(Args));
  if Name='script-closing' then Exit(ReadScriptClosing(Args));
  if Name='script-list' then Exit(ScriptLibrary(JI(Args,'offset',0),JI(Args,'limit',50)));
  if Name='script-character-library' then Exit(ScriptCharacterLibrary);
  if Name='script-text' then Exit(ReadScriptText(Args));
  if Name='script-research' then Exit(ReadResearch(Args));
  if Name='script-review' then Exit(ReadReview(Args));
  if Name='script-casting' then Exit(ReadCasting(Args));
  if Name='script-subtitles' then Exit(ReadSubtitles(Args));
  if Name='script-voice-effects' then Exit(ReadVoiceEffects(Args));
  if Name='script-voice' then Exit(ReadVoice(Args));
  if Name='script-voice-catalog' then Exit(ReadVoiceCatalog(Args));
  if Name='script-scenes' then Exit(ReadScriptScenes(Args));
  if Name='script-scene-assignment' then Exit(ReadScriptSceneAssignment(Args));
  if Name.StartsWith('script-image-transfer-') then Exit(ExecuteScriptImageTransfer(Name.Substring(7),Args));
  if Name='script-new' then begin NewScriptDraft; if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit(ScriptStatus); end;
  if Name='script-open' then begin OpenWork(FPipe.Workspace.Resolve(JS(Args,'path'))); Exit(ScriptStatus); end;
  if MatchText(Name,['script-set-title','script-set-type','script-save','script-set-stage','script-set-characters','script-set-layout','script-next','script-set-placement','script-select-placement','script-set-text','script-select-section','script-research-title','script-research-candidates','script-research-select','script-research-definitions','script-research-add','script-research-element','script-research-expand','script-research-confirm-work','script-request-review','script-submit-review','script-request-casting','script-submit-casting','script-select-casting','script-split-casting','script-merge-casting','script-select-subtitle','script-edit-subtitle','script-set-subtitle-break','script-select-voice','script-edit-voice','script-select-voice-effects','script-edit-voice-effects','script-set-voice-engine','script-refresh-voice','script-bind-voice','script-bind-voice-person','script-set-voice-state','script-save-character-voice','script-generate-voice','script-cancel-voice','script-set-scene-start','script-select-scene','script-edit-scene','script-adopt-scene-image','script-request-unapproved-images','script-request-scene-image','script-cancel-scene-image','script-complete-scenes','script-preview-scene','script-set-summary-choice','script-set-summary','script-complete-summary','script-set-closing','script-adopt-closing-image','script-complete-closing']) then begin
    if VoiceContinuous and (Name<>'script-cancel-voice') then raise Exception.Create('連続再生を停止してから変更してください。');
    if FPlacementEditing or ScriptTextEditing then raise Exception.Create('配置のドラッグ操作を完了してから再取得してください。');
    if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
      raise Exception.Create('script-statusの現在のprojectId/revisionを指定してください。');
    if Name.StartsWith('script-research-') then UpdateResearch(Name.Substring(16),Args)
    else if Name='script-set-scene-start' then begin
      if not (Args.GetValue('startsScene') is TJSONBool) then raise Exception.Create('startsSceneを真偽値で指定してください。');
      SetScriptSceneStart(JS(Args,'cueId'),JB(Args,'startsScene'));
    end
    else if Name='script-select-scene' then SelectScriptScene(JS(Args,'sceneId'))
    else if Name='script-edit-scene' then begin
      var S := FScriptDraft.Scene(JS(Args,'sceneId')); if S=nil then raise Exception.Create('シーンがありません。');
      var Description := JS(Args,'description',S.Description); var Prompt := JS(Args,'prompt',S.ImagePrompt);
      EditScriptScene(S.Id,Description,Prompt,JS(Args,'displayMode',SceneInputDisplayMode(Prompt,Description)),JS(Args,'descriptionPosition',S.DescriptionPosition));
      if Args.GetValue('feedback')<>nil then EditScriptSceneFeedback(S.Id,JS(Args,'feedback'));
    end
    else if Name='script-adopt-scene-image' then DeliverScriptSceneImage(Args)
    else if Name='script-request-unapproved-images' then RequestUnapprovedScriptImages
    else if Name='script-request-scene-image' then RequestScriptSceneImage(JS(Args,'sceneId'))
    else if Name='script-cancel-scene-image' then CancelScriptSceneImage(JS(Args,'sceneId'))
    else if Name='script-complete-scenes' then CompleteScriptScenes
    else if Name='script-preview-scene' then PreviewScriptScene(True)
    else if Name='script-set-summary-choice' then SetScriptSummaryChoice(JS(Args,'choice'))
    else if Name='script-set-summary' then SetScriptSummaryDraft(JO(Args,'draft'))
    else if Name='script-complete-summary' then CompleteScriptSummary
    else if Name='script-set-closing' then SetScriptClosingDraft(JO(Args,'draft'))
    else if Name='script-adopt-closing-image' then AdoptScriptClosingImage(JS(Args,'kind'),FPipe.Workspace.Resolve(JS(Args,'path')))
    else if Name='script-complete-closing' then CompleteScriptClosing
    else if Name='script-select-voice' then SelectVoice(JS(Args,'cueId'))
    else if Name='script-edit-voice' then begin
      if not (Args.GetValue('reading') is TJSONString) or not (Args.GetValue('settings') is TJSONObject) then raise Exception.Create('reading文字列とsettingsを指定してください。');
      EditVoice(JS(Args,'cueId'),JS(Args,'reading'),JO(Args,'settings'));
    end
    else if Name='script-select-voice-effects' then SelectVoiceEffects(JS(Args,'cueId'))
    else if Name='script-edit-voice-effects' then begin
      if not (Args.GetValue('settings') is TJSONObject) then raise Exception.Create('settingsオブジェクトを指定してください。');
      EditVoiceEffects(JS(Args,'cueId'),JO(Args,'settings'));
    end
    else if Name='script-set-voice-engine' then SetVoiceEngine(JS(Args,'engineUrl'))
    else if Name='script-refresh-voice' then RefreshVoiceCatalog
    else if Name='script-bind-voice' then BindVoice(JI(Args,'role'),JI(Args,'styleId',-1),JS(Args,'uuid'))
    else if Name='script-bind-voice-person' then BindVoicePerson(JI(Args,'role'),JS(Args,'uuid'))
    else if Name='script-set-voice-state' then SetVoiceState(JS(Args,'cueId'),JI(Args,'styleId',-1))
    else if Name='script-save-character-voice' then SaveCharacterVoice(JI(Args,'role'))
    else if Name='script-generate-voice' then GenerateVoice(JS(Args,'cueId'),JB(Args,'play'))
    else if Name='script-cancel-voice' then CancelVoice
    else if Name='script-select-subtitle' then SelectSubtitle(JS(Args,'cueId'))
    else if Name='script-edit-subtitle' then begin
      var Cue := FScriptDraft.Cue(JS(Args,'cueId')); if Cue=nil then raise Exception.Create('字幕のセリフがありません。');
      EditSubtitle(Cue.Id,JS(Args,'subtitle'),JS(Args,'note',Cue.SubtitleNote));
    end
    else if Name='script-set-subtitle-break' then SetSubtitleBreak(JS(Args,'cueId'),JI(Args,'offset',-1))
    else if Name='script-request-casting' then RequestCasting
    else if Name='script-submit-casting' then SubmitCasting(Args)
    else if Name='script-select-casting' then SelectCasting(JS(Args,'cueId'))
    else if Name='script-split-casting' then SplitCasting(JS(Args,'cueId'),JI(Args,'offset',-1))
    else if Name='script-merge-casting' then MergeCasting(JS(Args,'cueId'))
    else if Name='script-request-review' then RequestReview
    else if Name='script-submit-review' then SubmitReview(Args)
    else if Name='script-set-title' then SetScriptTitle(JS(Args,'title'))
    else if Name='script-set-type' then begin
      if not (Args.GetValue('scriptType') is TJSONString) then raise Exception.Create('scriptTypeは文字列で指定してください。');
      SetScriptType(JS(Args,'scriptType'));
    end
    else if Name='script-set-stage' then SetScriptStage(JS(Args,'stage'))
    else if Name='script-set-layout' then SetScriptLayout(JS(Args,'choice'),JS(Args,'backgroundTone'))
    else if Name='script-next' then NextScriptDraft
    else if Name='script-set-placement' then SetScriptPlacement(Args)
    else if Name='script-select-placement' then SelectScriptPlacement(JS(Args,'path'))
    else if Name='script-select-section' then SelectScriptSection(JS(Args,'section'))
    else if Name='script-set-text' then begin
      if not (Args.GetValue('text') is TJSONString) or (Length(JS(Args,'text'))>ScriptTextChunkLimit) then
        raise Exception.Create('textは4096文字以内の文字列で指定してください。長文はoffset/removeCountで分割更新できます。');
      var Section := ScriptSection(FScriptDraft,JS(Args,'section')); if Section=nil then raise Exception.Create('台本区分がありません。');
      var Text := JS(Args,'text');
      if Args.GetValue('offset')<>nil then begin
        var Old := JS(Section,'text'); var Offset := JI(Args,'offset',-1); var Count := JI(Args,'removeCount',0);
        if (Offset<0) or (Count<0) or (Offset>Length(Old)) or (Count>Length(Old)-Offset) then raise Exception.Create('文章の更新範囲が不正です。');
        if not ScriptTextBoundary(Old,Offset) or not ScriptTextBoundary(Old,Offset+Count) then raise Exception.Create('文字の途中を区切らず更新してください。');
        Text := Old.Substring(0,Offset)+Text+Old.Substring(Offset+Count);
      end;
      SetScriptText(JS(Args,'section'),Text);
    end
    else if Name='script-set-characters' then begin
      if not (Args.GetValue('paths') is TJSONArray) then raise Exception.Create('paths配列を指定してください。');
      SetScriptCharacters(TJSONArray(Args.GetValue('paths')));
    end else SaveScriptDraft(False);
    Exit(ScriptStatus);
  end;
  if Name='library' then Exit(CharacterLibrary);
  if Name='register-character' then Exit(RegisterCharacter(Args));
  if Name='schema' then begin
    Result := PsdJson.ObjectText('{"workspaceCommandPrefix":"app-","movieCommandPrefix":"movie-","psdCommandPrefix":"psd-","workspace":{"status":{},"library":{},"switch-page":{"page":"home|preview|create|characters|scripts|character-edit","propertyPage":"optional"},"open-work":{"path":".rigmovie"},"edit-character":{"path":".psdchar|.psd|.rigm"},"register-character":{"path":"file within dataRoot","name":"optional"}}}');
    var ScriptSchema := PsdJson.ObjectText('{"script-status":{},"script-list":{"offset":0,"limit":50},"script-new":{},"script-open":{"path":"Projects/<UID>/project.rigmovie"},"script-set-title":{"projectId":"from script-status","revision":"from script-status","title":"<=128 characters"},"script-save":{"projectId":"from script-status","revision":"from script-status"}}');
    ScriptSchema.AddPair('script-character-library',TJSONObject.Create);
    ScriptSchema.AddPair('script-set-type',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","scriptType":"ID from scriptTypes; empty clears classification"}'));
    ScriptSchema.AddPair('scriptTypes',ScriptTypesJson);
    ScriptSchema.AddPair('script-set-stage',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","stage":"title|characters|layout|placement|text|review|casting|subtitles (backward only)"}'));
    ScriptSchema.AddPair('script-subtitles',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-select-subtitle',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from subtitles"}'));
    ScriptSchema.AddPair('script-edit-subtitle',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"required","subtitle":"<=3000 UTF16","note":"optional <=2048"}'));
    ScriptSchema.AddPair('script-set-subtitle-break',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"required","offset":"UTF16 offset after removing first CRLF; remaining CRLF preserved"}'));
    ScriptSchema.AddPair('script-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-scenes',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1,"sourceCuesLimit":10,"unapprovedOnly":"optional true"}'));
    ScriptSchema.AddPair('script-scene-assignment',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":50}'));
    ScriptSchema.AddPair('script-set-scene-start',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from scene-assignment; first row fixed","startsScene":"required boolean"}'));
    for var CommandName in ['script-select-scene','script-request-scene-image','script-cancel-scene-image'] do ScriptSchema.AddPair(CommandName,PsdJson.ObjectText('{"projectId":"required","revision":"required","sceneId":"from scenes"}'));
    ScriptSchema.AddPair('script-edit-scene',PsdJson.ObjectText('{"projectId":"required","revision":"required","sceneId":"from scenes","description":"optional <=3000 UTF16","prompt":"image instructions including corrections <=16004 UTF16","displayMode":"optional both/image/text/none; omitted infers from prompt/description","descriptionPosition":"below-image/image-top/image-center/image-bottom/screen-top","feedback":"legacy corrections <=8000 UTF16; combined with prompt for requests"}'));
    ScriptSchema.AddPair('script-adopt-scene-image',PsdJson.ObjectText('{"projectId":"required","revision":"required","sceneId":"from scenes","path":"local PNG/JPEG/BMP inside data root (no bytes)","requestId":"current pending request required","sha256":"required 64 hex","provenance":"external-generated/existing-material/test-fixture"}'));
    for var CommandName in ['script-complete-scenes','script-preview-scene','script-request-unapproved-images'] do ScriptSchema.AddPair(CommandName,PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-set-summary-choice',PsdJson.ObjectText('{"projectId":"required","revision":"required","choice":"none/yes; no chart values invented"}'));
    ScriptSchema.AddPair('script-summary',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-set-summary',PsdJson.ObjectText('{"projectId":"required","revision":"required","draft":{"text":"human <=2000","subtitle":"independent, blank hides","reading":"independent, blank uses text","role":"active 1..9; draft may be 0","kind":"radar/bar","title":"<=120","minimum":"numeric text","maximum":"numeric text","items":"3..8 objects label/value as text, incomplete strings retained"}}'));
    ScriptSchema.AddPair('script-complete-summary',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-closing',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-set-closing',PsdJson.ObjectText('{"projectId":"required","revision":"required","draft":"complete human draft from script-closing; numeric text retained"}'));
    ScriptSchema.AddPair('script-adopt-closing-image',PsdJson.ObjectText('{"projectId":"required","revision":"required","kind":"representative|endImage|thumbnailImage","path":"existing workspace image"}'));
    ScriptSchema.AddPair('script-complete-closing',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    var ImageSchema := MovieImageTransferSchema;
    try for var Pair in ImageSchema do ScriptSchema.AddPair('script-'+Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONObject); finally ImageSchema.Free; end;
    PsdJson.Put(JO(ScriptSchema,'script-image-transfer-begin'),'requestId','from current external image request');
    PsdJson.Put(JO(ScriptSchema,'script-image-transfer-begin'),'provenance','external-generated/existing-material/test-fixture');
    PsdJson.Put(JO(ScriptSchema,'script-image-transfer-adopt'),'requestId','from original transfer contract');
    ScriptSchema.AddPair('script-voice-catalog',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"pageSize":20}'));
    ScriptSchema.AddPair('script-set-voice-engine',PsdJson.ObjectText('{"projectId":"required","revision":"required","engineUrl":"local engine URL"}'));
    ScriptSchema.AddPair('script-refresh-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-bind-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","role":1,"styleId":"from live catalog","uuid":"from live catalog"}'));
    ScriptSchema.AddPair('script-bind-voice-person',PsdJson.ObjectText('{"projectId":"required","revision":"required","role":1,"uuid":"from live catalog"}'));
    ScriptSchema.AddPair('script-set-voice-state',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"required","styleId":"from selected person"}'));
    ScriptSchema.AddPair('script-save-character-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","role":1}'));
    ScriptSchema.AddPair('script-voice-effects',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0}'));
    ScriptSchema.AddPair('script-select-voice-effects',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"stable cue ID"}'));
    ScriptSchema.AddPair('script-edit-voice-effects',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"stable cue ID","settings":"object: sparse numeric Aul2 controller keys; {} clears all effects"}'));
    ScriptSchema.AddPair('script-select-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from voice"}'));
    ScriptSchema.AddPair('script-edit-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from voice","reading":"<=2000 UTF16; empty restores original","settings":{"speedScale":1,"pitchScale":0,"intonationScale":1,"volumeScale":1,"prePhonemeLength":0.1,"postPhonemeLength":0.1}}'));
    ScriptSchema.AddPair('script-generate-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"selected only","play":false}'));
    ScriptSchema.AddPair('script-cancel-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-request-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-submit-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required","requestId":"from casting","fingerprint":"from casting","items":[{"cueId":"from casting","role":1,"reason":"<=2048"}],"complete":true}'));
    ScriptSchema.AddPair('script-select-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from casting"}'));
    ScriptSchema.AddPair('script-split-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from casting","offset":"UTF16 offset inside this cue"}'));
    ScriptSchema.AddPair('script-merge-casting',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"merge with next within same scene and section"}'));
    ScriptSchema.AddPair('script-research',PsdJson.ObjectText('{"projectId":"required","revision":"required","section":"summary/candidates/candidate/elements/element/integration","id":"optional","offset":0,"limit":20}'));
    for var Action in ['title','candidates','select','definitions','add','element','expand'] do
      ScriptSchema.AddPair('script-research-'+Action,PsdJson.ObjectText('{"projectId":"required","revision":"required","researchId":"from script-research","workId":"selectedCandidateId for element updates"}'));
    ScriptSchema.AddPair('researchContract',PsdJson.ObjectText('{"title":"title <=256","candidates":"candidates array of id/name/overview/identity/details/sources; resets human approval","select":"id","definitions":"scriptType + elements array of id/label; replaces definitions, archives old results","add":"id/label after all elements confirmed","element":"id/workId + name/summary/details/sources/state","expand":"id or empty to collapse","states":["unconfirmed","checking","confirmed-info","confirmed-none"],"humanWorkApproval":"GUI only; no auto approval","integration":"confirmed-info only; full details via section=element"}'));
    ScriptSchema.AddPair('script-review',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-request-review',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-submit-review',PsdJson.ObjectText('{"projectId":"required","revision":"required","requestId":"from review","fingerprint":"from review","items":[{"id":"unique <=64","section":"body","offset":0,"original":"<=4096 UTF16","proposed":"<=4096 UTF16","reason":"<=2048"}],"complete":true}'));
    ScriptSchema.AddPair('script-text',PsdJson.ObjectText('{"section":"opening|body|closing","offset":0,"limit":4096,"projectId":"optional consistent read","revision":"optional consistent read"}'));
    ScriptSchema.AddPair('script-set-text',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","section":"opening|body|closing","text":"<=4096 chars","offset":"optional zero-based UTF16 patch position","removeCount":"optional patch length"}'));
    ScriptSchema.AddPair('script-select-section',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","section":"opening|body|closing"}'));
    ScriptSchema.AddPair('script-set-layout',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","choice":"theme|l-left|l-right","backgroundTone":"optional: dark|light|blue"}'));
    ScriptSchema.AddPair('script-next',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status"}'));
    ScriptSchema.AddPair('script-set-placement',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","path":"selected character path","x":0.1,"y":0.2,"width":0.15,"height":0.5,"flipX":false,"coordinateSpace":"ratio"}'));
    ScriptSchema.AddPair('script-select-placement',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","path":"selected character path"}'));
    ScriptSchema.AddPair('script-set-characters',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","paths":["path from script-character-library"]}'));
    try for var Pair in ScriptSchema do JO(Result,'workspace').AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
    finally ScriptSchema.Free; end;
    try Result.AddPair('movie',ActiveSession.Execute('schema',Args)); except Result.Free; raise; end; Exit;
  end;
  if Name='open-work' then OpenWork(JS(Args,'path'))
  else if Name='switch-page' then begin
    var Page := JS(Args,'page'); var Target: TRigmAppPage;
    if Page='home' then Target := apHome else if Page='preview' then Target := apMovieEdit
    else if Page='create' then Target := apScriptCreate else if Page='characters' then Target := apCharacters
    else if Page='scripts' then Target := apScripts else if Page='character-edit' then Target := apCharacterEdit
    else raise Exception.Create('Unknown workspace page');
    if Assigned(FOnNavigate) then FOnNavigate(Self,Target,'');
    if JS(Args,'propertyPage')<>'' then begin
      if Target<>apMovieEdit then raise Exception.Create('Property pages belong to movie editing');
      if Assigned(FOnUiCommand) then begin var R := FOnUiCommand('select-property-page',Args); R.Free; end;
    end;
  end else if Name='edit-character' then begin
    var Path := FPipe.Workspace.Resolve(JS(Args,'path'));
    if Assigned(FOnNavigate) then FOnNavigate(Self,apCharacterEdit,Path);
    Result := TJSONObject.Create; Result.AddPair('path',Path);
    if SameText(ExtractFileExt(Path),'.psdchar') or SameText(ExtractFileExt(Path),'.psd') then begin
      Result.AddPair('renderFormat','psd'); Result.AddPair('editorClass','TPsdStudioFrame');
    end else begin Result.AddPair('renderFormat','rigm'); Result.AddPair('editorClass','TRigmLegacyEditorFrame'); end; Exit;
  end else if Name<>'status' then raise Exception.Create('Unknown workspace operation');
  Result := TJSONObject.Create; AddN(Result,'openDocuments',FSessions.Count);
  Result.AddPair('page',RigmPageKey(FPage)); Result.AddPair('pageTitle',RigmPageTitle(FPage));
  Result.AddPair('dataRoot',FPipe.Workspace.Root);
  if FActive<>nil then Result.AddPair('movie',FActive.Status);
  if FScriptDraft<>nil then Result.AddPair('script',ScriptStatus);
end;
function TRigmWizardWorkspace.CharacterLibrary: TJSONObject;
begin
  Result := TJSONObject.Create; var Entries := TJSONArray.Create; Result.AddPair('characters',Entries);
  try
    var W := FPipe.Workspace;
    for var Path in TDirectory.GetFiles(W.Resolve('Characters',False),'*.psdchar',TSearchOption.soAllDirectories) do begin
      var C := LoadCharacter(W,Path);
      try
        var O := TJSONObject.Create; Entries.AddElement(O); O.AddPair('name',C.Name); O.AddPair('path',Path); O.AddPair('renderFormat','psd');
        var Reason: string; O.AddPair('readyForScript',TJSONBool.Create(PsdReadyForScript(C,Reason))); O.AddPair('productionReason',Reason);
      finally C.Free; end;
    end;
    var Root := W.Resolve('RIGM',False);
    if DirectoryExists(Root) then for var Path in TDirectory.GetFiles(Root,'*.rigm') do begin
      W.Resolve(Path); var O := TJSONObject.Create; Entries.AddElement(O);
      O.AddPair('name',TPath.GetFileNameWithoutExtension(Path)); O.AddPair('path',Path); O.AddPair('renderFormat','rigm');
    end;
  except Result.Free; raise; end;
end;
function TRigmWizardWorkspace.RegisterDroppedCharacter(const Path: string): TJSONObject;
begin
  var W := FPipe.Workspace;
  var External := TPsdWorkspace.Create(ExtractFileDir(ExpandFileName(Path)));
  var Job: TPsdWorkJob := nil;
  try
    var Input := External.Resolve(Path); var Ext := LowerCase(ExtractFileExt(Input));
    if (Ext<>'.psdchar') and (Ext<>'.psd') and (Ext<>'.rigm') then raise Exception.Create('PSD・PSDキャラ・RIGMをドロップしてください。');
    Job := W.BeginJob; var Snapshot := Job.FilePath('drop'+Ext);
    var Stream := TFileStream.Create(Input,fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size>ART_MAX_BYTES then raise Exception.Create('キャラファイルの容量上限を超えています。');
      var Output := TFileStream.Create(Snapshot,fmCreate);
      try Output.CopyFrom(Stream,0); finally Output.Free; end;
    finally Stream.Free; end;
    var Hash := THashSHA2.GetHashStringFromFile(Snapshot); var Id := '';
    if Ext='.rigm' then begin var D := LoadRigm(Snapshot); try Id := D.FileId; finally D.Free; end; end
    else begin
      var C: TPsdCharacter;
      if Ext='.psdchar' then C := LoadCharacter(W,Snapshot) else C := ImportExternalPsd(W,Snapshot);
      try if Ext='.psdchar' then Id := C.Id; finally C.Free; end;
    end;
    var Existing := '';
    var Folder := W.Resolve('Characters',False); var Pattern := '*.psdchar';
    if Ext='.rigm' then begin Folder := W.Resolve('RIGM',False); Pattern := '*.rigm'; end;
    if DirectoryExists(Folder) then for var Candidate in TDirectory.GetFiles(Folder,Pattern,TSearchOption.soAllDirectories) do begin
      try
        if SameText(Candidate,Input) or SameText(THashSHA2.GetHashStringFromFile(Candidate),Hash) then Existing := Candidate
        else if Ext='.rigm' then begin
          var D := LoadRigm(Candidate); try if (Id<>'') and SameText(D.FileId,Id) then Existing := Candidate; finally D.Free; end;
        end else begin
          var C := LoadCharacter(W,Candidate);
          try
            if ((Id<>'') and SameText(C.Id,Id)) or ((Ext='.psd') and SameText(C.Source,Input)) or
              ((S(C.Settings,'registrationSourceFormat')=Ext) and SameText(S(C.Settings,'registrationSourceSha256'),Hash)) then Existing := Candidate;
          finally C.Free; end;
        end;
      except on E: Exception do Continue; end; // 壊れた既存項目は保全して正常な登録を妨げない。
      if Existing<>'' then Break;
    end;
    if Existing<>'' then begin
      Result := TJSONObject.Create; Result.AddPair('path',Existing); Result.AddPair('duplicate',TJSONBool.Create(True)); Exit;
    end;
    var A := TJSONObject.Create; Result := nil;
    try
      try
        A.AddPair('path',Snapshot); A.AddPair('registrationSource',Input); A.AddPair('registrationHash',Hash);
        Result := RegisterCharacter(A); Result.AddPair('duplicate',TJSONBool.Create(False));
      except Result.Free; raise; end;
    finally A.Free; end;
  finally Job.Free; External.Free; end;
end;
function TRigmWizardWorkspace.RegisterCharacter(Args: TJSONObject): TJSONObject;
begin
  var W := FPipe.Workspace; var Path := W.Resolve(JS(Args,'path')); var Ext := LowerCase(ExtractFileExt(Path));
  if (Ext='.psdchar') or (Ext='.psd') then begin
    var Job := W.BeginJob;
    var Session := TPsdSession.Create(W.Root,False);
    try
      var Input := Job.FilePath('input'+Ext); TFile.Copy(Path,Input,False);
      var A := Session.Status;
      try A.AddPair('path',Input); var R: TJSONObject;
        if Ext='.psdchar' then R := Session.Command('open',A) else R := Session.Command('import-psd',A); R.Free;
      finally A.Free; end;
      var Target := W.Resolve('Characters\'+PsdJson.NewId+'\character.psdchar',False);
      if JS(Args,'name')<>'' then begin
        A := Session.Status;
        try A.AddPair('name',JS(Args,'name')); var R := Session.Command('set-info',A); R.Free; finally A.Free; end;
      end;
      if JS(Args,'registrationSource')<>'' then begin
        var Reason: string; var Verified := Session.ReadyForScript(Reason);
        if Ext='.psd' then Session.Character.Source := JS(Args,'registrationSource');
        Put(Session.Character.Settings,'registrationSourceFormat',Ext);
        Put(Session.Character.Settings,'registrationSourceSha256',JS(Args,'registrationHash'));
        if Verified then Put(Session.Character.Production,'contentDigest',PsdProductionDigest(Session.Character));
      end;
      A := Session.Status;
      try A.AddPair('path',Target); var R := Session.Command('save',A); R.Free; finally A.Free; end;
      Result := TJSONObject.Create; Result.AddPair('path',Target); Result.AddPair('name',Session.Character.Name); Result.AddPair('renderFormat','psd');
    finally Session.Free; Job.Free; end;
  end else if Ext='.rigm' then begin
    var Editor := TRigmEditor.Create;
    try
      Editor.Open(Path); if JS(Args,'name')<>'' then Editor.Document.Name := JS(Args,'name');
      var Target := W.Resolve('RIGM\character-'+PsdJson.NewId+'.rigm',False); ForceDirectories(ExtractFileDir(Target)); Editor.Save(Target);
      Result := TJSONObject.Create; Result.AddPair('path',Target); Result.AddPair('name',Editor.Document.Name); Result.AddPair('renderFormat','rigm');
    finally Editor.Free; end;
  end else raise Exception.Create('Character registration accepts .psdchar, .psd or .rigm');
end;
function ScriptUtcNow: string;
begin Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now),True); end;
procedure TRigmWizardWorkspace.ScriptChanged;
begin if Assigned(FOnScriptChanged) then FOnScriptChanged(Self); end;
procedure TRigmWizardWorkspace.CheckScript(Project: TRigmMovieProject);
begin
  if (Project.ScriptWizard=nil) or (JS(Project.ScriptWizard,'format')<>'RIGMMaker.ScriptWizard') or
    (JI(Project.ScriptWizard,'schemaVersion')<>1) or (ScriptStageIndex(JS(Project.ScriptWizard,'stage'))<0) then
    raise Exception.Create('対応する台本ウィザードではありません。従来作品は動画編集から開いてください。');
  if not MatchText(JS(Project.ScriptWizard,'titleStatus'),['in-progress','complete']) or
    (Length(JS(Project.ScriptWizard,'titleInput'))>128) or (JS(Project.ScriptWizard,'createdAt')='') or
    (JS(Project.ScriptWizard,'updatedAt')='') or ((Project.ScriptWizard.GetValue('casting')=nil) and ((Project.Cues.Count<>0) or (Project.Scenes.Count<>0))) then
    raise Exception.Create('台本工程の状態が不正です。元ファイルは変更しません。');
  Project.BindCharacterPlacements;
  ValidateScriptType(Project);
  for var C in Project.Characters do if (C.PlacementRef='') or (Project.Placement(C.PlacementRef)=nil) then
    raise Exception.Create('台本工程のキャラは共通配置への参照が必要です。');
  if Project.ScriptWizard.GetValue('scriptText')<>nil then ValidateScriptText(JO(Project.ScriptWizard,'scriptText'))
  else if ScriptStageIndex(JS(Project.ScriptWizard,'stage'))>=4 then raise Exception.Create('台本入力データがありません。');
  if Project.ScriptWizard.GetValue('voice')<>nil then ValidateScriptVoice(Project) else if JS(Project.ScriptWizard,'stage')='voice' then raise Exception.Create('音声工程の保存状態がありません。');
  if Project.ScriptWizard.GetValue('voiceEffects')<>nil then ValidateScriptVoiceEffects(Project) else if JS(Project.ScriptWizard,'stage')='voice-effects' then raise Exception.Create('音声エフェクト工程の保存状態がありません。');
  if Project.ScriptWizard.GetValue('scenes')<>nil then ValidateScriptScenes(Project) else if MatchText(JS(Project.ScriptWizard,'stage'),['scene-assignment','scenes','summary']) then raise Exception.Create('シーン工程の保存状態がありません。');
  if (Project.ScriptWizard.GetValue('summaryChoice')<>nil) and not MatchStr(JS(Project.ScriptWizard,'summaryChoice'),['','none','yes']) then raise Exception.Create('総評の選択状態が不正です。');
  if Project.ScriptWizard.GetValue('summaryData')<>nil then ValidateScriptSummary(Project) else if JS(Project.ScriptWizard,'stage')='summary-edit' then raise Exception.Create('総評入力がありません。');
  if Project.ScriptWizard.GetValue('closingData')<>nil then ValidateScriptClosing(Project);
  if Project.ScriptWizard.GetValue('subtitles')<>nil then ValidateScriptSubtitles(Project)
  else if JS(Project.ScriptWizard,'stage')='subtitles' then raise Exception.Create('字幕データがありません。');
  if Project.ScriptWizard.GetValue('casting')<>nil then ValidateScriptCasting(Project)
  else if JS(Project.ScriptWizard,'stage')='casting' then raise Exception.Create('配役データがありません。');
  if Project.ScriptWizard.GetValue('review')<>nil then ValidateScriptReview(Project)
  else if (JS(Project.ScriptWizard,'stage')='review') and (ScriptResearch(Project)=nil) then
    raise Exception.Create('作品情報または旧校正データがありません。');
  if ScriptResearch(Project)<>nil then ValidateScriptResearch(Project);
  if (Project.ScriptWizard.GetValue('selectedCharacters')<>nil) and
    not (Project.ScriptWizard.GetValue('selectedCharacters') is TJSONArray) then raise Exception.Create('キャラ選択の状態が不正です。');
  if (Project.ScriptWizard.GetValue('charactersStatus')<>nil) and
    not MatchText(JS(Project.ScriptWizard,'charactersStatus'),['in-progress','complete']) then raise Exception.Create('キャラ工程の状態が不正です。');
  if Project.ScriptWizard.GetValue('layoutChoice')<>nil then begin
    var Layout,Direction: string; DecodeLayoutChoice(JS(Project.ScriptWizard,'layoutChoice'),Layout,Direction);
    if (Project.Layout<>Layout) or (Project.LDirection<>Direction) or
      not MatchText(JS(Project.ScriptWizard,'layoutStatus'),['in-progress','complete']) or
      (Project.BackgroundColor<>LayoutBackgroundColor(JS(Project.ScriptWizard,'backgroundTone'))) then
      raise Exception.Create('レイアウト工程の状態が不正です。元ファイルは変更しません。');
  end else if ScriptStageIndex(JS(Project.ScriptWizard,'stage'))>=2 then raise Exception.Create('レイアウトが未選択です。');
  if Project.ScriptWizard.GetValue('placements')<>nil then begin
    if not (Project.ScriptWizard.GetValue('placements') is TJSONArray) then raise Exception.Create('配置配列が不正です。');
    var Seen := TDictionary<string,Boolean>.Create;
    try
      for var V in JA(Project.ScriptWizard,'placements') do begin
        if not (V is TJSONObject) then raise Exception.Create('配置項目が不正です。');
        var Item := TJSONObject(V); ValidatePlacement(Item);
        var Path := LowerCase(JS(Item,'path')); var Found := False;
        for var C in JA(Project.ScriptWizard,'selectedCharacters') do if SameText(JS(TJSONObject(C),'path'),Path) then Found := True;
        if not Found or Seen.ContainsKey(Path) then raise Exception.Create('配置キャラの選択が不正です。'); Seen.Add(Path,True);
      end;
    finally Seen.Free; end;
  end else if JS(Project.ScriptWizard,'stage')='placement' then raise Exception.Create('配置情報がありません。');
  if Project.ScriptWizard.GetValue('selectedCharacters')<>nil then for var V in JA(Project.ScriptWizard,'selectedCharacters') do begin
    if not (V is TJSONObject) then raise Exception.Create('キャラ選択の形式が不正です。');
    if not MatchText(JS(TJSONObject(V),'renderFormat'),['psd','rigm']) or (JS(TJSONObject(V),'path')='') then
      raise Exception.Create('キャラ選択の形式が不正です。');
    var Path := FPipe.Workspace.Resolve(JS(TJSONObject(V),'path'),False);
    if not (Path.StartsWith(IncludeTrailingPathDelimiter(FPipe.Workspace.Resolve('Characters',False)),True) or
      Path.StartsWith(IncludeTrailingPathDelimiter(FPipe.Workspace.Resolve('RIGM',False)),True)) or
      not MatchText(ExtractFileExt(Path),['.psdchar','.rigm']) then raise Exception.Create('キャラの登録先が不正です。');
  end;
end;
function TRigmWizardWorkspace.ScriptPath(Project: TRigmMovieProject): string;
begin
  var Id: TGUID;
  try Id := StringToGUID(Project.Id); except on E: Exception do raise Exception.Create('台本UIDが不正です。'); end;
  Result := FPipe.Workspace.Resolve('Projects\'+GUIDToString(Id)+'\project.rigmovie',False);
  var Folder := ExtractFileDir(Result);
  while Length(Folder)>=Length(FPipe.Workspace.Root) do begin
    if FileExists(TPath.Combine(Folder,'.rigmignore')) then raise Exception.Create('除外されたフォルダの台本は変更しません。');
    if SameText(Folder,FPipe.Workspace.Root) then Break;
    Folder := ExtractFileDir(Folder);
  end;
end;
procedure TRigmWizardWorkspace.NewScriptDraft;
begin
  if VoiceBusy then raise Exception.Create('音声ジョブを終了してから作品を切り替えてください。'); StopVoice;
  if (FScriptDraft<>nil) and ((FPage=apScriptCreate) or (FScriptDraft.FileName='')) then begin
    if FScriptDraft.FileName='' then SaveScriptDraft(False);
    ScriptChanged; Exit;
  end;
  if (FScriptDraft<>nil) and FScriptDraft.Modified then SaveScriptDraft(False);
  var P := TRigmMovieProject.Create;
  P.Title := '題名未入力'; P.ScriptWizard := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptWizard","schemaVersion":1,"stage":"title","titleStatus":"in-progress","titleInput":"","scriptType":"","charactersStatus":"in-progress","selectedCharacters":[]}');
  var Time := ScriptUtcNow; P.ScriptWizard.AddPair('createdAt',Time); P.ScriptWizard.AddPair('updatedAt',Time);
  if FileExists(ScriptPath(P)) then begin P.Free; raise Exception.Create('UIDの保存先が既に存在します。'); end;
  P.Modified := True; FScriptDrafts.Add(P); FScriptDraft := P; FScriptViewStage := 'title';
  SaveScriptDraft(False); ScriptChanged;
end;
procedure TRigmWizardWorkspace.OpenScriptDraft(const Path: string);
begin
  if VoiceBusy then raise Exception.Create('音声ジョブを終了してから作品を切り替えてください。'); StopVoice;
  var FullPath := FPipe.Workspace.Resolve(Path);
  var P := LoadMovie(FullPath);
  try
    CheckScript(P);
    if not SameText(FullPath,ScriptPath(P)) then raise Exception.Create('UIDフォルダと台本ファイルの保存先が一致しません。');
    if (FScriptDraft<>nil) and FScriptDraft.Modified then SaveScriptDraft(False);
    var Hash := THashSHA2.GetHashStringFromFile(FullPath);
    for var Existing in FScriptDrafts do if SameText(Existing.FileName,FullPath) then begin
      var OldHash: string;
      if FScriptSavedHashes.TryGetValue(Existing.Id,OldHash) and SameText(OldHash,Hash) then begin
        FScriptDraft := Existing; FScriptViewStage := ScriptResumeView(Existing); if (FScriptViewStage='review') and (ScriptResearch(Existing)=nil) then begin PrepareResearch(Existing); Existing.Changed; end; if FScriptViewStage='closing' then PrepareScriptClosing(Existing);
        if FScriptViewStage='casting' then begin var Upgraded := UpgradeScriptCastingLines(Existing); var Restored := RestoreStoredCastingVoices(Existing); if Upgraded or Restored then Existing.Changed; end;
        ScriptChanged; Exit;
      end;
    end;
    if JS(P.ScriptWizard,'stage')='closing' then PrepareScriptClosing(P); P.Modified := False;
    if (ScriptResumeView(P)='review') and (ScriptResearch(P)=nil) then begin PrepareResearch(P); P.Changed; end;
    if ScriptResumeView(P)='casting' then begin
      var Upgraded := UpgradeScriptCastingLines(P); var Restored := RestoreStoredCastingVoices(P); if Upgraded or Restored then P.Changed;
    end;
    FScriptDrafts.Add(P); FScriptDraft := P; FScriptViewStage := ScriptResumeView(P); P := nil;
    FScriptSavedHashes.AddOrSetValue(FScriptDraft.Id,Hash); ScriptChanged;
  finally P.Free; end;
end;
procedure TRigmWizardWorkspace.SetScriptTitle(const Value: string);
begin
  if FScriptDraft=nil then raise Exception.Create('台本を新規作成または再開してください。');
  if Length(Value)>128 then raise Exception.Create('題名は128文字以内で入力してください。');
  for var Ch in Value do if Ord(Ch)<32 then raise Exception.Create('題名に改行・制御文字は使えません。');
  if JS(FScriptDraft.ScriptWizard,'titleInput')=Value then Exit;
  PsdJson.Put(FScriptDraft.ScriptWizard,'titleInput',Value); PsdJson.Put(FScriptDraft.ScriptWizard,'titleStatus','in-progress');
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptType(const Value: string);
begin
  if FScriptDraft=nil then raise Exception.Create('台本を新規作成または再開してください。');
  if (Value<>'') and (ScriptTypeIndex(Value)<0) then raise Exception.Create('対応していない台本種類です。');
  if ProjectScriptType(FScriptDraft)=Value then Exit;
  PsdJson.Put(FScriptDraft.ScriptWizard,'scriptType',Value); ChangeResearchType(FScriptDraft);
  FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.Thumbnails: TRigmThumbnailCache;
begin
  if FThumbnails=nil then FThumbnails := TRigmThumbnailCache.Create(FPipe.Workspace.Root);
  Result := FThumbnails;
end;
function TRigmWizardWorkspace.ScriptCharacterLibrary(ValidatePreview: Boolean): TJSONObject;
  procedure Collect(const Folder: string; Entries: TJSONArray);
  begin
    if not DirectoryExists(Folder) or FileExists(TPath.Combine(Folder,'.rigmignore')) or
      ((GetFileAttributes(PChar(Folder)) and FILE_ATTRIBUTE_REPARSE_POINT)<>0) then Exit;
    for var Path in TDirectory.GetFiles(Folder) do begin
      if not MatchText(ExtractFileExt(Path),['.psdchar','.rigm']) then Continue;
      var O := TJSONObject.Create; Entries.AddElement(O);
      var Key := Path.Substring(Length(IncludeTrailingPathDelimiter(FPipe.Workspace.Root)));
      O.AddPair('path',Key); O.AddPair('renderFormat',CharacterFormat(Path)); O.AddPair('name',TPath.GetFileNameWithoutExtension(Path));
      EnsureVoiceBindings; var Binding := FVoiceBindings.GetValue(LowerCase(Key)) as TJSONObject;
      if Binding<>nil then begin O.AddPair('voiceBindingStatus','registered'); O.AddPair('voiceBinding',Binding.Clone as TJSONObject); end else O.AddPair('voiceBindingStatus','unassigned');
      try
        var Entry := Thumbnails.Request(Path);
        if Entry=nil then begin
          O.AddPair('loading',TJSONBool.Create(True)); O.AddPair('readyForScript',TJSONBool.Create(False));
          O.AddPair('productionReason','サムネイルと完成状態を準備中です。');
        end else begin
          for var Pair in Entry.Metadata do PsdJson.Put(O,Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
          O.AddPair('loading',TJSONBool.Create(False));
        end;
      except on E: Exception do begin
        O.AddPair('readyForScript',TJSONBool.Create(False)); O.AddPair('productionReason','読込不可: '+E.Message);
      end; end;
    end;
    for var Child in TDirectory.GetDirectories(Folder) do begin
      if MatchText(ExtractFileName(Child),['Documents','Temp','Work','Recovery','Exports']) then Continue;
      Collect(Child,Entries);
    end;
  end;
begin
  Result := TJSONObject.Create; var Entries := TJSONArray.Create; Result.AddPair('characters',Entries);
  try
    if FileExists(TPath.Combine(FPipe.Workspace.Root,'.rigmignore')) then Exit;
    Collect(FPipe.Workspace.Resolve('Characters',False),Entries);
    Collect(FPipe.Workspace.Resolve('RIGM',False),Entries);
  except Result.Free; raise; end;
end;
procedure TRigmWizardWorkspace.SetScriptStage(const Value: string);
begin
  if FScriptDraft=nil then raise Exception.Create('台本を新規作成または再開してください。');
  var Reached := Max(ScriptStageIndex(JS(FScriptDraft.ScriptWizard,'furthestStage',JS(FScriptDraft.ScriptWizard,'stage'))),ScriptStageIndex(CurrentScriptStage));
  if (ScriptStageIndex(Value)<0) or (ScriptStageIndex(Value)>Reached) then
    raise Exception.Create('次工程へは左の工程リストで保存して進んでください。');
  if CurrentScriptStage=Value then Exit;
  if (ScriptStageIndex(Value)>ScriptStageIndex('scenes')) and (FScriptDraft.ScriptWizard.GetValue('scenes')<>nil) then begin
    var Reason := ScriptScenesAdvanceReason; if Reason<>'' then raise Exception.Create(Reason);
  end;
  if (CurrentScriptStage='scene-assignment') and (ScriptStageIndex(Value)>ScriptStageIndex('scene-assignment')) then
    raise Exception.Create('シーン割当を左の工程リストで保存してから進んでください。');
  if ScriptStageIndex(Value)>ScriptStageIndex('casting') then begin
    var Reason := CastingAdvanceReason(CurrentScriptStage='casting'); if Reason<>'' then raise Exception.Create(Reason);
  end;
  // 訪問済みの後工程アイコンでも、字幕の未完了・不整合を飛び越えない。
  if (CurrentScriptStage='subtitles') and (ScriptStageIndex(Value)>ScriptStageIndex('subtitles')) then begin
    if ScriptTextEditing then raise Exception.Create('字幕の入力操作を完了してください。');
    var Reason := SubtitleAdvanceReason; if Reason<>'' then raise Exception.Create(Reason);
  end;
  if (ScriptResearch(FScriptDraft)<>nil) and (ScriptStageIndex(Value)>ScriptStageIndex('review')) and
    (ResearchAdvanceReason(FScriptDraft)<>'') then raise Exception.Create(ResearchAdvanceReason(FScriptDraft));
  if (Value='review') and (ScriptResearch(FScriptDraft)=nil) then begin PrepareResearch(FScriptDraft); FScriptDraft.Changed; end;
  if (Value='casting') and RestoreStoredCastingVoices(FScriptDraft) then FScriptDraft.Changed;
  if (Value='voice-effects') and (FScriptDraft.ScriptWizard.GetValue('voiceEffects')=nil) then begin PrepareScriptVoiceEffects(FScriptDraft); FScriptDraft.Changed; end;
  SaveScriptDraft(False); FScriptViewStage := Value; FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptCharacters(Paths: TJSONArray);
begin
  if (FScriptDraft=nil) or (CurrentScriptStage<>'characters') then
    raise Exception.Create('キャラ選択工程で操作してください。');
  if Paths.Count>100 then raise Exception.Create('キャラは100人以内にしてください。');
  var Catalog := ScriptCharacterLibrary(False); var Selected := TJSONArray.Create;
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in Paths do begin
      if not (V is TJSONString) then raise Exception.Create('キャラの登録パスを指定してください。');
      var FullPath := FPipe.Workspace.Resolve(V.Value);
      var Key := FullPath.Substring(Length(IncludeTrailingPathDelimiter(FPipe.Workspace.Root)));
      if Seen.ContainsKey(LowerCase(Key)) then raise Exception.Create('同じキャラを重複選択できません。');
      Seen.Add(LowerCase(Key),True); var Found: TJSONObject := nil;
      for var Entry in JA(Catalog,'characters') do
        if SameText(JS(TJSONObject(Entry),'path'),Key) then begin Found := TJSONObject(Entry); Break; end;
      if Found=nil then raise Exception.Create('登録済みキャラを選んでください。');
      if not JB(Found,'readyForScript') then raise Exception.Create(JS(Found,'name')+': '+JS(Found,'productionReason'));
      var Saved: TJSONObject := nil;
      if FScriptDraft.ScriptWizard.GetValue('selectedCharacters')<>nil then
        for var Old in JA(FScriptDraft.ScriptWizard,'selectedCharacters') do
          if SameText(JS(TJSONObject(Old),'path'),Key) then begin Saved := TJSONObject(Old); Break; end;
      if Saved<>nil then Selected.AddElement(Saved.Clone as TJSONObject)
      else begin
        var Item := TJSONObject.Create; Selected.AddElement(Item);
        Item.AddPair('path',Key); Item.AddPair('name',JS(Found,'name')); Item.AddPair('renderFormat',JS(Found,'renderFormat'));
        Item.AddPair('voiceBindingStatus',JS(Found,'voiceBindingStatus','unassigned'));
        if Found.GetValue('voiceBinding')<>nil then Item.AddPair('voiceBinding',JO(Found,'voiceBinding').Clone as TJSONObject);
      end;
    end;
    if (FScriptDraft.ScriptWizard.GetValue('selectedCharacters')<>nil) and
      (JA(FScriptDraft.ScriptWizard,'selectedCharacters').ToJSON=Selected.ToJSON) then Exit;
    PsdJson.Put(FScriptDraft.ScriptWizard,'selectedCharacters',Selected); Selected := nil; InvalidateScriptCasting(FScriptDraft);
    if FScriptDraft.ScriptWizard.GetValue('placements')<>nil then begin
      var Retained := TJSONArray.Create;
      for var Old in JA(FScriptDraft.ScriptWizard,'placements') do
        for var C in JA(FScriptDraft.ScriptWizard,'selectedCharacters') do
          if SameText(JS(TJSONObject(Old),'path'),JS(TJSONObject(C),'path')) then Retained.AddElement(Old.Clone as TJSONObject);
      PsdJson.Put(FScriptDraft.ScriptWizard,'placements',Retained);
      PsdJson.Put(FScriptDraft.ScriptWizard,'placementStatus','in-progress');
      for var I := FScriptDraft.Characters.Count-1 downto 0 do
        if FScriptDraft.Placement(FScriptDraft.Characters[I].PlacementRef)=nil then FScriptDraft.Characters.Delete(I);
      FScriptDraft.BindCharacterPlacements;
    end;
    if FScriptDraft.ScriptWizard.GetValue('layoutChoice')<>nil then
      PsdJson.Put(FScriptDraft.ScriptWizard,'layoutStatus','in-progress');
    PsdJson.Put(FScriptDraft.ScriptWizard,'charactersStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
  finally Seen.Free; Selected.Free; Catalog.Free; end;
end;
procedure TRigmWizardWorkspace.SetScriptLayout(const Choice, BackgroundTone: string);
begin
  if (FScriptDraft=nil) or (CurrentScriptStage<>'layout') then
    raise Exception.Create('レイアウト工程で操作してください。');
  var Layout,Direction: string; DecodeLayoutChoice(Choice,Layout,Direction);
  var Tone := BackgroundTone; if Tone='' then Tone := JS(FScriptDraft.ScriptWizard,'backgroundTone','dark');
  var Color := LayoutBackgroundColor(Tone);
  if (JS(FScriptDraft.ScriptWizard,'layoutChoice')=Choice) and
    (JS(FScriptDraft.ScriptWizard,'backgroundTone')=Tone) then Exit;
  FScriptDraft.Layout := Layout; FScriptDraft.LDirection := Direction; FScriptDraft.BackgroundColor := Color;
  PsdJson.Put(FScriptDraft.ScriptWizard,'layoutChoice',Choice); PsdJson.Put(FScriptDraft.ScriptWizard,'backgroundTone',Tone);
  if FScriptDraft.ScriptWizard.GetValue('placements')<>nil then PsdJson.Put(FScriptDraft.ScriptWizard,'placementStatus','in-progress');
  PsdJson.Put(FScriptDraft.ScriptWizard,'layoutStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.CurrentScriptStage: string;
begin
  Result := FScriptViewStage;
  if (Result='') and (FScriptDraft<>nil) then Result := JS(FScriptDraft.ScriptWizard,'stage');
  if (Result='scenes') and (FScriptDraft<>nil) and (JS(FScriptDraft.ScriptWizard,'scene-assignmentStatus')<>'complete') then Result := 'scene-assignment';
end;
procedure TRigmWizardWorkspace.SetScriptSceneStart(const CueId: string; Value: Boolean);
begin
  if CurrentScriptStage<>'scene-assignment' then raise Exception.Create('セリフのシーン割当画面で操作してください。');
  if VoiceBusy or VoicePlaying or VoiceContinuous then raise Exception.Create('音声生成・再生を停止してからシーンを割り当ててください。');
  RigmScriptSceneAssignmentModel.SetScriptSceneStart(FScriptDraft,CueId,Value);
  FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ReadScriptSceneAssignment(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
    raise Exception.Create('最新projectId/revisionでセリフのシーン割当を取得してください。');
  ValidateScriptSceneAssignment(FScriptDraft);
  Result := TJSONObject.Create; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  AddN(Result,'count',FScriptDraft.Cues.Count); AddN(Result,'sceneCount',FScriptDraft.Scenes.Count);
  var Rows := TJSONArray.Create; Result.AddPair('rows',Rows);
  var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Cues.Count); var Count := EnsureRange(JI(Args,'limit',50),1,200);
  for var I := Offset to Min(Offset+Count,FScriptDraft.Cues.Count)-1 do begin
    var C := FScriptDraft.Cues[I]; var O := TJSONObject.Create; Rows.AddElement(O);
    O.AddPair('cueId',C.Id); AddN(O,'line',I+1); O.AddPair('text',C.Text); O.AddPair('sceneId',C.Scene);
    AddN(O,'sceneNumber',ScriptSceneNumber(FScriptDraft,C.Scene)); AddB(O,'startsScene',ScriptSceneStartsAt(FScriptDraft,I)); AddB(O,'editable',ScriptSceneStartEditable(FScriptDraft,I));
  end;
  AddN(Result,'nextOffset',Offset+Rows.Count); AddB(Result,'hasMore',Offset+Rows.Count<FScriptDraft.Cues.Count);
end;
procedure TRigmWizardWorkspace.BeginPlacementEdit;
begin
  if FPlacementEditing or (CurrentScriptStage<>'placement') then raise Exception.Create('配置操作を開始できません。');
  FPlacementEditing := True;
end;
procedure TRigmWizardWorkspace.EndPlacementEdit;
begin FPlacementEditing := False; end;
procedure TRigmWizardWorkspace.SelectScriptPlacement(const Path: string);
begin
  if (CurrentScriptStage<>'placement') or (Placement(FScriptDraft,Path)=nil) then raise Exception.Create('配置キャラを選んでください。');
  if JS(FScriptDraft.ScriptWizard,'placementSelected')=Path then Exit;
  PsdJson.Put(FScriptDraft.ScriptWizard,'placementSelected',Path); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptPlacement(Args: TJSONObject);
begin
  if FPlacementEditing or (CurrentScriptStage<>'placement') then raise Exception.Create('配置操作が完了してから変更してください。');
  if (JS(Args,'coordinateSpace','ratio')<>'ratio') then raise Exception.Create('配置座標はratioで指定してください。');
  var Old := Placement(FScriptDraft,JS(Args,'path')); if Old=nil then raise Exception.Create('選択済みキャラの配置を指定してください。');
  var O := Old.Clone as TJSONObject;
  try
    for var Name in ['x','y','width','height','flipX'] do begin
      if Args.GetValue(Name)<>nil then PsdJson.Put(O,Name,Args.GetValue(Name).Clone as TJSONValue);
    end;
    ValidatePlacement(O); var B := PlacementRect(O); var Area := PlacementArea(FScriptDraft);
    if (B.Left<Area.Left-0.01) or (B.Top<Area.Top-0.01) or (B.Right>Area.Right+0.01) or (B.Bottom>Area.Bottom+0.01) then
      raise Exception.Create('L字型ではキャラ側のガイド領域内へ配置してください。');
    if Old.ToJSON=O.ToJSON then Exit;
    for var Pair in O do PsdJson.Put(Old,Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
    PsdJson.Put(FScriptDraft.ScriptWizard,'placementSelected',JS(Old,'path'));
    PsdJson.Put(FScriptDraft.ScriptWizard,'placementStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
  finally O.Free; end;
end;
procedure TRigmWizardWorkspace.StoreScript(Snapshot: TRigmMovieProject; const ViewStage: string);
begin
  if Snapshot.ScriptWizard.GetValue('scenes')<>nil then SyncScriptScenesStatus(Snapshot);
  CheckScript(Snapshot);
  var Path := ScriptPath(FScriptDraft); var SavedHash: string;
  if FileExists(Path) and (not FScriptSavedHashes.TryGetValue(FScriptDraft.Id,SavedHash) or
    not SameText(SavedHash,THashSHA2.GetHashStringFromFile(Path))) then
    raise Exception.Create('台本が別の操作で更新されました。現在の入力を保持しています。外部の変更を確認してください。');
  var Title := Trim(JS(Snapshot.ScriptWizard,'titleInput')); Snapshot.Title := Title;
  if Title='' then Snapshot.Title := '題名未入力';
  PsdJson.Put(Snapshot.ScriptWizard,'updatedAt',ScriptUtcNow);
  SaveMovie(Snapshot,Path,False);
  // ここより前は原稿・画面を変更しない。遷移と入力が同じ保存成功で確定する。
  FScriptDraft.Title := Snapshot.Title; FScriptDraft.FileName := Snapshot.FileName; FScriptDraft.Revision := Snapshot.Revision;
  FScriptDraft.Layout := Snapshot.Layout; FScriptDraft.LDirection := Snapshot.LDirection;
  FScriptDraft.BackgroundColor := Snapshot.BackgroundColor; FScriptDraft.WorkflowStage := Snapshot.WorkflowStage;
  FScriptDraft.ScriptWizard.Free; FScriptDraft.ScriptWizard := Snapshot.ScriptWizard.Clone as TJSONObject;
  var OldCues := FScriptDraft.Cues; FScriptDraft.Cues := Snapshot.Cues; Snapshot.Cues := OldCues;
  var OldScenes := FScriptDraft.Scenes; FScriptDraft.Scenes := Snapshot.Scenes; Snapshot.Scenes := OldScenes;
  var OldSpeakers := FScriptDraft.Speakers; FScriptDraft.Speakers := Snapshot.Speakers; Snapshot.Speakers := OldSpeakers;
  var OldCharacters := FScriptDraft.Characters; FScriptDraft.Characters := Snapshot.Characters; Snapshot.Characters := OldCharacters;
  var OldCards := FScriptDraft.EndCards; FScriptDraft.EndCards := Snapshot.EndCards; Snapshot.EndCards := OldCards;
  FScriptDraft.BindCharacterPlacements;
  FScriptDraft.Modified := False; FScriptViewStage := ViewStage;
  FScriptSavedHashes.AddOrSetValue(FScriptDraft.Id,THashSHA2.GetHashStringFromFile(Path)); ScriptChanged;
end;
procedure TRigmWizardWorkspace.SaveScriptDraft(ConfirmTitle: Boolean);
begin
  if (FScriptDraft=nil) or (not FScriptDraft.Modified and not ConfirmTitle) then Exit;
  var Snapshot := FScriptDraft.Clone;
  try
    // 旧所有検証の呼出し互換。通常のSaveは途中保存、Nextが工程を確定する。
    if ConfirmTitle then begin
      var Key := CurrentScriptStage+'Status'; if Key='charactersStatus' then Key := 'charactersStatus';
      if Key='subtitlesStatus' then begin
        if ScriptTextEditing then raise Exception.Create('字幕の入力操作を完了してください。');
        RequireCurrentSubtitles(Snapshot);
      end;
      PsdJson.Put(Snapshot.ScriptWizard,Key,'complete'); Snapshot.Changed;
    end;
    StoreScript(Snapshot,CurrentScriptStage);
  finally Snapshot.Free; end;
end;
function TRigmWizardWorkspace.SubtitleAdvanceReason(RequireComplete: Boolean): string;
begin
  Result := ScriptSubtitleBlockReason(FScriptDraft,RequireComplete); if Result<>'' then Exit;
  if FPlacementEditing or (RequireComplete and ScriptTextEditing) then Exit('表示字幕・改行・メモの入力を完了してから左の工程リストで進んでください。');
  if VoiceBusy or VoicePlaying or VoiceContinuous then Exit('音声生成・再生を停止してから左の工程リストで進んでください。');
  try
    if Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))='' then Exit('題名を入力してから左の工程リストで進んでください。');
    var Characters := JA(FScriptDraft.ScriptWizard,'selectedCharacters');
    if Characters.Count=0 then Exit('完成済みキャラを1人以上選んでください。');
    for var V in Characters do begin
      var Path := FPipe.Workspace.Resolve(JS(TJSONObject(V),'path'));
      if not FileExists(Path) then Exit('選択キャラが見つかりません：'+JS(TJSONObject(V),'path'));
    end;
  except on E: Exception do Result := E.Message; end;
end;
procedure TRigmWizardWorkspace.NextScriptDraft;
begin
  if VoiceBusy or VoicePlaying or VoiceContinuous then raise Exception.Create('音声生成・再生を停止してから左の工程リストで進んでください。');
  if (FScriptDraft=nil) or FPlacementEditing or ScriptTextEditing then raise Exception.Create('入力操作を完了してから左の工程リストで進んでください。');
  var Stage := CurrentScriptStage; var Next := ScriptNextStage(Stage,FScriptDraft.ScriptWizard);
  if (ScriptStageIndex(Stage)>=ScriptStageIndex('review')) and (ScriptResearch(FScriptDraft)<>nil) and
    (ResearchAdvanceReason(FScriptDraft)<>'') then raise Exception.Create(ResearchAdvanceReason(FScriptDraft));
  if Next='editor' then begin FinishScriptToEditor; Exit; end;
  if Next='' then raise Exception.Create('次の工程を決めるために入力を確認してください。');
  if Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))='' then raise Exception.Create('題名を入力してから左の工程リストで進んでください。');
  if (Stage<>'voice-effects') and (ScriptStageIndex(Stage)>=ScriptStageIndex('casting')) then begin var Reason := CastingAdvanceReason(Stage='casting'); if Reason<>'' then raise Exception.Create(Reason); end;
  if Stage='subtitles' then begin
    var Reason := SubtitleAdvanceReason; if Reason<>'' then raise Exception.Create(Reason);
  end;
  var Snapshot := FScriptDraft.Clone;
  try
    if Snapshot.ScriptWizard.GetValue('selectedCharacters')=nil then Snapshot.ScriptWizard.AddPair('selectedCharacters',TJSONArray.Create);
    if Snapshot.ScriptWizard.GetValue('charactersStatus')=nil then Snapshot.ScriptWizard.AddPair('charactersStatus','in-progress');
    // 字幕→音声は配役とセリフを扱う。確認済みキャラをサムネイルの未準備で止めない。
    if (Stage<>'title') and (Stage<>'subtitles') and (Stage<>'voice-effects') then begin
      if JA(Snapshot.ScriptWizard,'selectedCharacters').Count=0 then raise Exception.Create('完成済みキャラを1人以上選んでください。');
      var Catalog := ScriptCharacterLibrary(False);
      try
        for var V in JA(Snapshot.ScriptWizard,'selectedCharacters') do begin
          var Ready := False;
          for var C in JA(Catalog,'characters') do
            if SameText(JS(TJSONObject(C),'path'),JS(TJSONObject(V),'path')) then Ready := JB(TJSONObject(C),'readyForScript');
          if not Ready then raise Exception.Create('選択キャラの検査が完了し、完成済みであることを確認してください。');
        end;
      finally Catalog.Free; end;
    end;
    if (Next='layout') and (Snapshot.ScriptWizard.GetValue('layoutChoice')=nil) then begin
      PsdJson.Put(Snapshot.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(Snapshot.ScriptWizard,'backgroundTone','dark');
      PsdJson.Put(Snapshot.ScriptWizard,'layoutStatus','in-progress'); Snapshot.Layout := 'theme'; Snapshot.LDirection := 'right';
      Snapshot.BackgroundColor := LayoutBackgroundColor('dark');
    end;
    if Next='placement' then PreparePlacements(Snapshot,Thumbnails);
    if Next='text' then PrepareScriptText(Snapshot);
    if Next='review' then begin
      var HasText := False;
      for var V in JA(JO(Snapshot.ScriptWizard,'scriptText'),'sections') do HasText := HasText or (Trim(JS(TJSONObject(V),'text'))<>'');
      if not HasText then raise Exception.Create('台本文を入力してから作品情報の確認へ進んでください。');
      PrepareResearch(Snapshot);
    end;
    if Next='casting' then begin
      var Reason := ResearchAdvanceReason(Snapshot); if Reason<>'' then raise Exception.Create(Reason);
      PsdJson.Put(Snapshot.ScriptWizard,'researchIntegration',ResearchIntegrationData(Snapshot));
      DisableScriptSummary(Snapshot); // 再配役で補助セリフが除かれる前に人間入力と実音声を保管する。
      PrepareScriptCasting(Snapshot); RestoreStoredCastingVoices(Snapshot);
    end;
    if Next='subtitles' then PrepareScriptSubtitles(Snapshot);
    if (Next='voice') and (Stage<>'summary-edit') then PrepareScriptVoice(Snapshot);
    if Next='voice-effects' then begin
      if JS(Snapshot.ScriptWizard,'voiceStatus')<>'complete' then raise Exception.Create('全セリフの音声を最後まで再生してください。');
      for var C in Snapshot.Cues do if not Snapshot.AudioHeard(C) then raise Exception.Create('未再生または変更後のセリフを最後まで再生してください。');
      PrepareScriptVoiceEffects(Snapshot);
    end;
    if Next='summary-edit' then PrepareScriptSummary(Snapshot);
    if Stage='summary-edit' then begin
      if JS(JO(Snapshot.ScriptWizard,'summaryData'),'status')<>'complete' then raise Exception.Create('総評の確認完了を押してください。');
      MaterializeScriptSummary(Snapshot); PsdJson.Put(JO(Snapshot.ScriptWizard,'voice'),'selectedCue',ScriptSummaryCue(Snapshot).Id); PsdJson.Put(Snapshot.ScriptWizard,'voiceStatus','in-progress'); PsdJson.Put(Snapshot.ScriptWizard,'voiceReturnStage','closing');
    end;
    if Next='closing' then begin
      PrepareScriptClosing(Snapshot);
      if (Stage='voice') and (JS(Snapshot.ScriptWizard,'voiceStatus')<>'complete') then raise Exception.Create('総評の音声を確認してください。');
      if Stage<>'voice-effects' then for var C in Snapshot.Cues do if not Snapshot.AudioReady(C) then raise Exception.Create('音声の変更を確認してください。');
      Snapshot.ScriptWizard.RemovePair('voiceReturnStage').Free;
    end;
    if Next='scene-assignment' then PrepareScriptScenes(Snapshot,Stage<>'voice-effects');
    if Next='scenes' then begin ValidateScriptSceneAssignment(Snapshot); PsdJson.Put(Snapshot.ScriptWizard,'scene-assignmentStatus','complete'); end;
    if Next='summary' then begin
      if not ScriptScenesReady(Snapshot,True) then raise Exception.Create('シーンの確認完了を押してから進んでください。');
      for var C in Snapshot.Cues do if not Snapshot.AudioReady(C) then raise Exception.Create('音声の変更を確認してから進んでください。');
      if Snapshot.ScriptWizard.GetValue('summaryChoice')=nil then PsdJson.Put(Snapshot.ScriptWizard,'summaryChoice','');
    end;
    if Snapshot.ScriptWizard.GetValue('scenes')<>nil then begin if Snapshot.Scene(JS(JO(Snapshot.ScriptWizard,'scenes'),'selectedScene'))=nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'scenes'),'selectedScene',Snapshot.Scenes[0].Id); end;
    if Snapshot.ScriptWizard.GetValue('voice')<>nil then begin if Snapshot.Cue(JS(JO(Snapshot.ScriptWizard,'voice'),'selectedCue'))=nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'voice'),'selectedCue',Snapshot.Cues[0].Id); end;
    if Snapshot.ScriptWizard.GetValue('subtitles')<>nil then begin
      if Snapshot.Cue(JS(JO(Snapshot.ScriptWizard,'subtitles'),'selectedCue'))=nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'subtitles'),'selectedCue',Snapshot.Cues[0].Id);
    end;
    var Reached := JS(Snapshot.ScriptWizard,'furthestStage',JS(Snapshot.ScriptWizard,'stage',Stage)); if ScriptStageIndex(Next)>ScriptStageIndex(Reached) then Reached := Next;
    PsdJson.Put(Snapshot.ScriptWizard,'furthestStage',Reached); PsdJson.Put(Snapshot.ScriptWizard,Stage+'Status','complete'); PsdJson.Put(Snapshot.ScriptWizard,'stage',Next); Snapshot.Changed;
    StoreScript(Snapshot,Next);
  finally Snapshot.Free; end;
end;
function TRigmWizardWorkspace.GetScriptTextEditing: Boolean;
begin
  // 台本制作ではフォーカス・キー・IME入力による通信ロックを設けない。
  // 既存フレームとパイプの互換性のため、公開状態は常にFalseを返す。
  Result := False;
end;
procedure TRigmWizardWorkspace.BeginScriptTextEdit;
begin
  // 旧フレームの呼出しは互換維持。入力値の検証と人間の確定は各工程が担当する。
end;
procedure TRigmWizardWorkspace.EndScriptTextEdit;
begin
  // 入力終了を待たず、現在のrevisionでパイプ通信を受け付ける。
end;
procedure TRigmWizardWorkspace.SelectScriptSection(const Section: string);
begin
  if (CurrentScriptStage<>'text') or (ScriptSection(FScriptDraft,Section)=nil) then raise Exception.Create('台本入力工程で区分を選んでください。');
  var O := JO(FScriptDraft.ScriptWizard,'scriptText'); if JS(O,'activeSection')=Section then Exit;
  PsdJson.Put(O,'activeSection',Section); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptText(const Section,Text: string);
begin
  if (FScriptDraft=nil) or (CurrentScriptStage<>'text') then raise Exception.Create('台本入力工程で操作してください。');
  var O := ScriptSection(FScriptDraft,Section); if O=nil then raise Exception.Create('台本区分がありません。');
  var Value := NormalizeScriptText(Text);
  if Length(Value)>ScriptSectionLimit then raise Exception.Create('1区分は100000文字以内にしてください。');
  for var C in Value do if (Ord(C)<32) and not CharInSet(C,[#9,#10,#13]) then raise Exception.Create('台本に無効な制御文字が含まれています。');
  if JS(O,'text')=Value then Exit;
  if FScriptDraft.ScriptWizard.GetValue('subtitles')<>nil then PsdJson.Put(FScriptDraft.ScriptWizard,'subtitlesStatus','in-progress');
  PsdJson.Put(O,'text',Value); InvalidateScriptReview(FScriptDraft); InvalidateScriptCasting(FScriptDraft); PsdJson.Put(FScriptDraft.ScriptWizard,'textStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SelectSubtitle(const CueId: string);
begin
  if CurrentScriptStage<>'subtitles' then raise Exception.Create('字幕工程で操作してください。');
  if JS(JO(FScriptDraft.ScriptWizard,'subtitles'),'selectedCue')=CueId then Exit;
  RigmScriptSubtitleModel.SelectSubtitle(FScriptDraft,CueId); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveSubtitle(Delta: Integer);
begin if CurrentScriptStage<>'subtitles' then Exit; RigmScriptSubtitleModel.MoveSubtitle(FScriptDraft,Delta); FScriptDraft.Changed; ScriptChanged; end;
procedure TRigmWizardWorkspace.EditSubtitle(const CueId,Text,Note: string);
begin
  if CurrentScriptStage<>'subtitles' then raise Exception.Create('字幕工程で操作してください。');
  RigmScriptSubtitleModel.EditSubtitle(FScriptDraft,CueId,Text,Note);
  SyncSummarySubtitle(FScriptDraft,CueId);
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetSubtitleBreak(const CueId: string; Offset: Integer);
begin
  if CurrentScriptStage<>'subtitles' then raise Exception.Create('字幕工程で操作してください。');
  RigmScriptSubtitleModel.SetSubtitleBreak(FScriptDraft,CueId,Offset); SyncSummarySubtitle(FScriptDraft,CueId); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveSubtitleBreak(const CueId: string; Delta, DefaultOffset: Integer);
begin
  if CurrentScriptStage<>'subtitles' then Exit;
  RigmScriptSubtitleModel.MoveSubtitleBreak(FScriptDraft,CueId,Delta,DefaultOffset); SyncSummarySubtitle(FScriptDraft,CueId); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteSubtitles;
begin
  if CurrentScriptStage<>'subtitles' then raise Exception.Create('字幕工程で操作してください。');
  RequireCurrentSubtitles(FScriptDraft); EndScriptTextEdit;
  PsdJson.Put(FScriptDraft.ScriptWizard,'subtitlesStatus','complete'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ReadSubtitles(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新のprojectId/revisionで取得してください。');
  Result := ScriptSubtitleSummary(FScriptDraft); Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  var A := TJSONArray.Create; Result.AddPair('rows',A); var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Cues.Count);
  if Offset<FScriptDraft.Cues.Count then begin
    var C := FScriptDraft.Cues[Offset]; var O := TJSONObject.Create; A.AddElement(O);
    O.AddPair('cueId',C.Id); O.AddPair('subtitle',C.Subtitle); O.AddPair('voiceText',C.Text); O.AddPair('note',C.SubtitleNote); O.AddPair('sceneId',C.Scene);
    var RoleNumber := ScriptCueRole(FScriptDraft,C.Id); AddN(O,'role',RoleNumber); O.AddPair('character',JS(CastingRole(FScriptDraft,RoleNumber),'name')); AddN(O,'breakOffset',C.Subtitle.IndexOf(#13#10));
  end;
  AddN(Result,'nextOffset',Offset+A.Count); AddB(Result,'hasMore',Offset+A.Count<FScriptDraft.Cues.Count);
end;
procedure TRigmWizardWorkspace.RequestCasting;
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程で依頼してください。');
  RequestScriptCasting(FScriptDraft); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SubmitCasting(Args: TJSONObject);
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程で提案してください。');
  SubmitScriptCasting(FScriptDraft,Args); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.AssignCasting(const CueId: string; Number: Integer; Confirm: Boolean);
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程でキャラ番号を選んでください。');
  AssignScriptCasting(FScriptDraft,CueId,Number,Confirm); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SelectCasting(const CueId: string);
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程でセリフを選んでください。');
  if JS(JO(FScriptDraft.ScriptWizard,'casting'),'selectedCue')=CueId then Exit;
  SelectCastingRow(FScriptDraft,CueId); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveCasting(Delta: Integer);
begin
  if CurrentScriptStage<>'casting' then Exit;
  MoveCastingRow(FScriptDraft,Delta); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SplitCasting(const CueId: string; Offset: Integer);
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程で分割してください。');
  var Snapshot := FScriptDraft.Clone;
  try SplitCastingRow(Snapshot,CueId,Offset); Snapshot.Changed; StoreScript(Snapshot,CurrentScriptStage);
  finally Snapshot.Free; end;
end;
procedure TRigmWizardWorkspace.MergeCasting(const CueId: string);
begin
  if CurrentScriptStage<>'casting' then raise Exception.Create('配役工程で結合してください。');
  var Snapshot := FScriptDraft.Clone;
  try MergeCastingRow(Snapshot,CueId); Snapshot.Changed; StoreScript(Snapshot,CurrentScriptStage);
  finally Snapshot.Free; end;
end;
function TRigmWizardWorkspace.ReadCasting(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
    raise Exception.Create('最新のprojectId/revisionで配役を取得してください。');
  Result := ScriptCastingSummary(FScriptDraft); Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  var A := TJSONArray.Create; Result.AddPair('rows',A); var Cast := FScriptDraft.ScriptWizard.GetValue('casting') as TJSONObject;
  if Cast=nil then Exit; var Rows := JA(Cast,'rows'); var Offset := EnsureRange(JI(Args,'offset'),0,Rows.Count);
  if Offset<Rows.Count then begin
    var R := TJSONObject(Rows[Offset]).Clone as TJSONObject; A.AddElement(R); var C := FScriptDraft.Cue(JS(R,'cueId'));
    R.AddPair('text',C.Text); R.AddPair('subtitle',C.Subtitle); R.AddPair('sceneId',C.Scene);
  end;
  AddN(Result,'nextOffset',Offset+A.Count); Result.AddPair('hasMore',TJSONBool.Create(Offset+A.Count<Rows.Count));
end;
procedure TRigmWizardWorkspace.RequestReview;
begin
  if CurrentScriptStage<>'review' then raise Exception.Create('校正工程で依頼してください。');
  RequestScriptReview(FScriptDraft); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SubmitReview(Args: TJSONObject);
begin
  if CurrentScriptStage<>'review' then raise Exception.Create('校正工程で提案を送ってください。');
  SubmitScriptReview(FScriptDraft,Args); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.DecideReview(const Id,Decision,Text: string);
begin
  if CurrentScriptStage<>'review' then raise Exception.Create('校正工程で採否を選んでください。');
  var Before := ScriptFingerprint(FScriptDraft); DecideScriptReview(FScriptDraft,Id,Decision,Text);
  if Before<>ScriptFingerprint(FScriptDraft) then begin
    InvalidateScriptCasting(FScriptDraft); if FScriptDraft.ScriptWizard.GetValue('subtitles')<>nil then PsdJson.Put(FScriptDraft.ScriptWizard,'subtitlesStatus','in-progress');
  end; FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.EditReviewDraft(const Id,Text: string);
begin
  if CurrentScriptStage<>'review' then raise Exception.Create('校正工程で案を編集してください。');
  var O := ReviewItem(FScriptDraft,Id);
  if (O=nil) or not MatchText(JS(O,'decision'),['pending','hold']) or
    (JS(JO(FScriptDraft.ScriptWizard,'review'),'state')<>'ready') then raise Exception.Create('未確定の提案を選んでください。');
  var Value := NormalizeScriptText(Text);
  if Length(Value)>4096 then raise Exception.Create('修正案は4096文字以内で入力してください。');
  for var C in Value do if (Ord(C)<32) and not CharInSet(C,[#9,#10,#13]) then raise Exception.Create('修正案に無効な制御文字があります。');
  if JS(O,'editedDraft',JS(O,'proposed'))=Value then Exit;
  PsdJson.Put(O,'editedDraft',Value); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ReadReview(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
    raise Exception.Create('最新のprojectId/revisionで校正を取得してください。');
  Result := ScriptReviewSummary(FScriptDraft);
  Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  if ScriptResearch(FScriptDraft)<>nil then AddB(Result,'researchReady',ResearchAdvanceReason(FScriptDraft)='');
  var A := TJSONArray.Create; Result.AddPair('items',A);
  var R := FScriptDraft.ScriptWizard.GetValue('review') as TJSONObject; if R=nil then Exit;
  var Offset := EnsureRange(JI(Args,'offset'),0,JA(R,'items').Count); var Count := 1;
  for var I := Offset to Min(Offset+Count,JA(R,'items').Count)-1 do A.AddElement(JA(R,'items').Items[I].Clone as TJSONObject);
  AddN(Result,'nextOffset',Offset+A.Count); Result.AddPair('hasMore',TJSONBool.Create(Offset+A.Count<JA(R,'items').Count));
end;
function TRigmWizardWorkspace.ReadScriptText(Args: TJSONObject): TJSONObject;
begin
  if FScriptDraft=nil then raise Exception.Create('台本を開いてください。');
  if (Args.GetValue('projectId')<>nil) and (JS(Args,'projectId')<>FScriptDraft.Id) then raise Exception.Create('台本が切り替わりました。最新状態から読み直してください。');
  if (Args.GetValue('revision')<>nil) and (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('台本が変更されました。最新状態から読み直してください。');
  var O := ScriptSection(FScriptDraft,JS(Args,'section')); if O=nil then raise Exception.Create('台本区分がありません。');
  var Text := JS(O,'text'); var Offset := JI(Args,'offset',0); var Count := EnsureRange(JI(Args,'limit',ScriptTextChunkLimit),1,ScriptTextChunkLimit);
  if (Offset<0) or (Offset>Length(Text)) then raise Exception.Create('文章の取得範囲が不正です。');
  if not ScriptTextBoundary(Text,Offset) then raise Exception.Create('文字の途中を区切らず取得してください。');
  Count := Min(Count,Length(Text)-Offset);
  if not ScriptTextBoundary(Text,Offset+Count) then begin if Count=1 then Inc(Count) else Dec(Count); end;
  Result := TJSONObject.Create; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  Result.AddPair('section',JS(O,'id')); Result.AddPair('scope',JS(O,'scope')); Result.AddPair('text',Text.Substring(Offset,Count));
  AddN(Result,'offset',Offset); AddN(Result,'nextOffset',Offset+Count); AddN(Result,'length',Length(Text));
  Result.AddPair('hasMore',TJSONBool.Create(Offset+Count<Length(Text)));
end;
function TRigmWizardWorkspace.ScriptStatus: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('hasProject',TJSONBool.Create(FScriptDraft<>nil));
  Result.AddPair('implementedStage','closing-editor'); Result.AddPair('placementEditing',TJSONBool.Create(FPlacementEditing));
  Result.AddPair('textEditing',TJSONBool.Create(ScriptTextEditing));
  var Advance := False; var CanConfirmVoice := False; var CanConfirmSubtitles := False;
  if FScriptDraft<>nil then Advance := not FPlacementEditing and not ScriptTextEditing and (Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))<>'') and
    ((CurrentScriptStage='title') or (((CurrentScriptStage='characters') or (CurrentScriptStage='layout') or (CurrentScriptStage='placement') or (CurrentScriptStage='text') or (CurrentScriptStage='review') or (CurrentScriptStage='casting')) and
    (FScriptDraft.ScriptWizard.GetValue('selectedCharacters')<>nil) and (JA(FScriptDraft.ScriptWizard,'selectedCharacters').Count>0)));
  if (FScriptDraft<>nil) and (CurrentScriptStage='subtitles') then begin
    var Reason := SubtitleAdvanceReason;
    Advance := (Reason=''); Result.AddPair('advanceBlockedReason',Reason);
    CanConfirmSubtitles := SubtitleAdvanceReason(False)='';
  end;
  if (FScriptDraft<>nil) and (CurrentScriptStage='voice') then begin
    if RefreshScriptVoiceCompletion(FScriptDraft) then FScriptDraft.Changed;
    var Reason := '';
    if VoiceBusy or VoicePlaying or VoiceContinuous then Reason := '音声生成・再生の終了後に左の工程リストで進んでください。'
    else for var C in FScriptDraft.Cues do if not FScriptDraft.AudioReady(C) then begin
      Reason := '未生成または変更後のセリフをF5で確認してください。'; Break;
    end;
    if Reason='' then for var C in FScriptDraft.Cues do if not FScriptDraft.AudioHeard(C) then begin
      Reason := '未再生のセリフを最後まで再生してください（F5／Shift+F5）。'; Break;
    end;
    // 再生履歴が揃った時だけGUIの音声確定を許す。外部工程選択にも確認済み状態を要求する。
    CanConfirmVoice := (Reason='') and (FScriptDraft.Cues.Count>0);
    Advance := CanConfirmVoice and not ScriptTextEditing and (JS(FScriptDraft.ScriptWizard,'voiceStatus')='complete');
    Result.AddPair('advanceBlockedReason',Reason);
  end;
  if (FScriptDraft<>nil) and (CurrentScriptStage='voice-effects') then Advance := True;
  if (FScriptDraft<>nil) and (CurrentScriptStage='scene-assignment') then begin
    var Reason := '';
    try ValidateScriptSceneAssignment(FScriptDraft); except on E: Exception do Reason := E.Message; end;
    if VoiceBusy or VoicePlaying or VoiceContinuous then Reason := '音声生成・再生を停止してから左の工程リストで進んでください。';
    Advance := not ScriptTextEditing and (Reason=''); Result.AddPair('advanceBlockedReason',Reason);
  end;
    if (FScriptDraft<>nil) and (CurrentScriptStage='scenes') then begin var Reason := ScriptScenesAdvanceReason; Advance := Reason=''; PsdJson.Put(Result,'advanceBlockedReason',Reason); end;
  if (FScriptDraft<>nil) and (CurrentScriptStage='summary') then Advance := not ScriptTextEditing and MatchStr(JS(FScriptDraft.ScriptWizard,'summaryChoice'),['none','yes']);
  if (FScriptDraft<>nil) and (CurrentScriptStage='summary-edit') then Advance := not ScriptTextEditing and (JS(JO(FScriptDraft.ScriptWizard,'summaryData'),'status')='complete');
  if (FScriptDraft<>nil) and (CurrentScriptStage='closing') then Advance := not ScriptTextEditing and not VoiceBusy and (JS(JO(FScriptDraft.ScriptWizard,'closingData'),'status')='complete');
  if (FScriptDraft<>nil) and (CurrentScriptStage='review') then begin
    var Reason := ResearchAdvanceReason(FScriptDraft); Advance := Advance and (Reason='');
    PsdJson.Put(Result,'advanceBlockedReason',Reason);
  end;
  if (FScriptDraft<>nil) and (CurrentScriptStage='casting') then begin
    var Reason := CastingAdvanceReason; Advance := not ScriptTextEditing and (Reason=''); Result.AddPair('advanceBlockedReason',Reason);
  end;
  if (FScriptDraft<>nil) and (CurrentScriptStage<>'voice-effects') and (ScriptStageIndex(CurrentScriptStage)>ScriptStageIndex('casting')) then begin
    var Reason := CastingAdvanceReason(False); if Reason<>'' then begin Advance := False; CanConfirmVoice := False; CanConfirmSubtitles := False; PsdJson.Put(Result,'advanceBlockedReason',Reason); end;
  end;
  if Advance and MatchStr(CurrentScriptStage,['characters','layout','placement','text','review']) then begin
    var Catalog := ScriptCharacterLibrary(False);
    try
      for var V in JA(FScriptDraft.ScriptWizard,'selectedCharacters') do begin
        var Ready := False;
        for var C in JA(Catalog,'characters') do
          if SameText(JS(TJSONObject(C),'path'),JS(TJSONObject(V),'path')) then Ready := JB(TJSONObject(C),'readyForScript');
        if not Ready then begin
          Advance := False; PsdJson.Put(Result,'advanceBlockedReason','選択キャラの検査が完了し、完成済みであることを確認してください。'); Break;
        end;
      end;
    finally Catalog.Free; end;
    if (CurrentScriptStage='text') and Advance then begin
      var HasText := False;
      for var V in JA(JO(FScriptDraft.ScriptWizard,'scriptText'),'sections') do HasText := HasText or (Trim(JS(TJSONObject(V),'text'))<>'');
      Advance := HasText;
      if not HasText then PsdJson.Put(Result,'advanceBlockedReason','台本文を入力してから作品情報の確認へ進んでください。');
    end;
  end;
  if (FScriptDraft<>nil) and (ScriptResearch(FScriptDraft)<>nil) and
    (ScriptStageIndex(CurrentScriptStage)>=ScriptStageIndex('review')) then begin
    var Reason := ResearchAdvanceReason(FScriptDraft);
    if Reason<>'' then begin Advance := False; CanConfirmVoice := False; CanConfirmSubtitles := False;
      PsdJson.Put(Result,'advanceBlockedReason',Reason); end;
  end;
  if VoiceBusy or VoicePlaying or VoiceContinuous then begin Advance := False; CanConfirmVoice := False; CanConfirmSubtitles := False; end;
  Result.AddPair('canAdvance',TJSONBool.Create(Advance));
  AddB(Result,'canConfirmVoice',CanConfirmVoice);
  AddB(Result,'canConfirmSubtitles',CanConfirmSubtitles);
  if FScriptDraft=nil then begin if (FActive<>nil) and (FActive.Project.ScriptWizard<>nil) and (JS(FActive.Project.ScriptWizard,'stage')='editor') then begin Result.AddPair('editorProjectId',FActive.Project.Id); Result.AddPair('editorPath',FActive.Project.FileName); end; Exit; end;
  Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  if ScriptResearch(FScriptDraft)<>nil then AddB(Result,'researchReady',ResearchAdvanceReason(FScriptDraft)='');
  Result.AddPair('title',JS(FScriptDraft.ScriptWizard,'titleInput')); Result.AddPair('savedTitle',FScriptDraft.Title);
  Result.AddPair('scriptType',ProjectScriptType(FScriptDraft));
  Result.AddPair('scriptTypeName',ScriptTypeName(ProjectScriptType(FScriptDraft)));
  Result.AddPair('scriptTypes',ScriptTypesJson);
  Result.AddPair('path',FScriptDraft.FileName); Result.AddPair('modified',TJSONBool.Create(FScriptDraft.Modified));
  Result.AddPair('resumeStage',ScriptResumeView(FScriptDraft));
  var Wizard := TJSONObject.Create;
  for var Pair in FScriptDraft.ScriptWizard do if not MatchText(Pair.JsonString.Value,['research','researchArchives','researchIntegration','scriptText','review','casting','castingArchives','sceneAssignmentArchives','subtitles','voice','scenes','summaryData','closingData']) then
    Wizard.AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
  if FScriptDraft.ScriptWizard.GetValue('summaryData') is TJSONObject then begin var O := JO(FScriptDraft.ScriptWizard,'summaryData'); var Brief := TJSONObject.Create; Brief.AddPair('status',JS(O,'status')); AddB(Brief,'materialized',JB(O,'materialized')); AddN(Brief,'axisCount',JA(JO(O,'draft'),'items').Count); Wizard.AddPair('summaryData',Brief); end;
  if FScriptDraft.ScriptWizard.GetValue('scriptText')<>nil then Wizard.AddPair('scriptText',ScriptTextSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('subtitles')<>nil then Wizard.AddPair('subtitles',ScriptSubtitleSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('casting')<>nil then begin
    var Cast := ScriptCastingSummary(FScriptDraft); Wizard.AddPair('casting',Cast);
    var Ready := CastingAdvanceReason(CurrentScriptStage='casting')=''; AddB(Result,'castingReady',Ready);
    if Ready then PsdJson.Put(Wizard,'castingStatus','complete') else PsdJson.Put(Wizard,'castingStatus','in-progress');
  end else AddB(Result,'castingReady',False);
  if FScriptDraft.ScriptWizard.GetValue('review')<>nil then Wizard.AddPair('review',ScriptReviewSummary(FScriptDraft));
  if ScriptResearch(FScriptDraft)<>nil then Wizard.AddPair('research',ResearchSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('voice')<>nil then Wizard.AddPair('voice',VoiceStatus);
  if FScriptDraft.ScriptWizard.GetValue('scenes')<>nil then Wizard.AddPair('scenes',ScriptScenesSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('closingData')<>nil then begin var Brief := TJSONObject.Create; Brief.AddPair('status',JS(JO(FScriptDraft.ScriptWizard,'closingData'),'status')); Wizard.AddPair('closingData',Brief); end;
  if Wizard.GetValue('selectedCharacters')=nil then Wizard.AddPair('selectedCharacters',TJSONArray.Create);
  if Wizard.GetValue('charactersStatus')=nil then Wizard.AddPair('charactersStatus','in-progress');
  PsdJson.Put(Wizard,'stage',CurrentScriptStage);
  if Wizard.GetValue('layoutChoice')<>nil then
    Result.AddPair('layoutGuide',MovieLayoutGuide(JS(Wizard,'layoutChoice'),FScriptDraft.Width,FScriptDraft.Height));
  Result.AddPair('wizard',Wizard);
end;
function TRigmWizardWorkspace.ScriptLibrary(Offset,Limit: Integer): TJSONObject;
  procedure Collect(const Folder: string; Paths: TStrings);
  begin
    if not DirectoryExists(Folder) or FileExists(TPath.Combine(Folder,'.rigmignore')) or
      SameText(ExtractFileName(Folder),'Documents') or ((GetFileAttributes(PChar(Folder)) and FILE_ATTRIBUTE_REPARSE_POINT)<>0) then Exit;
    for var Path in TDirectory.GetFiles(Folder,'*.rigmovie') do Paths.Add(Path);
    for var Child in TDirectory.GetDirectories(Folder) do
      if not MatchText(ExtractFileName(Child),['Documents','Characters','Images','Audio','Exports','Temp','Work','Recovery']) then Collect(Child,Paths);
  end;
begin
  if (Offset<0) or (Limit<1) or (Limit>100) then raise Exception.Create('一覧のoffset/limitが不正です。');
  Result := TJSONObject.Create; var Entries := TJSONArray.Create; Result.AddPair('scripts',Entries);
  var Paths := TStringList.Create;
  try
    try
    Paths.Sorted := True; Paths.Duplicates := dupIgnore;
    var W := FPipe.Workspace;
    if not FileExists(TPath.Combine(W.Root,'.rigmignore')) then begin
      Collect(W.Resolve('Projects',False),Paths); Collect(W.Resolve('Scripts',False),Paths);
      for var Path in TDirectory.GetFiles(W.Root,'*.rigmovie') do Paths.Add(Path);
    end;
    AddN(Result,'total',Paths.Count); AddN(Result,'offset',Offset);
    for var I := Offset to Min(Paths.Count-1,Offset+Limit-1) do begin
      var Entry := TJSONObject.Create; Entries.AddElement(Entry); Entry.AddPair('path',Paths[I]);
      Entry.AddPair('title',TPath.GetFileNameWithoutExtension(Paths[I])); Entry.AddPair('kind','legacy');
      try
        var P := LoadMovie(W.Resolve(Paths[I]));
        try
          PsdJson.Put(Entry,'title',P.Title); Entry.AddPair('projectId',P.Id);
          Entry.AddPair('scriptType',ProjectScriptType(P)); Entry.AddPair('scriptTypeName',ScriptTypeName(ProjectScriptType(P)));
          if P.ScriptWizard<>nil then begin
            if JS(P.ScriptWizard,'stage')<>'editor' then CheckScript(P); if not SameText(Paths[I],ScriptPath(P)) then raise Exception.Create('UIDと保存先が一致しません。');
            PsdJson.Put(Entry,'kind','wizard'); Entry.AddPair('stage',JS(P.ScriptWizard,'stage'));
            var StateKey := 'titleStatus'; if JS(P.ScriptWizard,'stage')='characters' then StateKey := 'charactersStatus';
            if JS(P.ScriptWizard,'stage')='layout' then StateKey := 'layoutStatus';
            if JS(P.ScriptWizard,'stage')='placement' then StateKey := 'placementStatus';
            if JS(P.ScriptWizard,'stage')='text' then StateKey := 'textStatus';
            Entry.AddPair('state',JS(P.ScriptWizard,StateKey)); Entry.AddPair('updatedAt',JS(P.ScriptWizard,'updatedAt'));
          end else begin Entry.AddPair('stage','legacy'); Entry.AddPair('state','従来作品'); end;
        finally P.Free; end;
      except on E: Exception do begin PsdJson.Put(Entry,'kind','unreadable'); Entry.AddPair('error',E.Message); end; end;
    end;
    AddN(Result,'nextOffset',Offset+Entries.Count);
    except Result.Free; raise; end;
  finally Paths.Free; end;
end;
procedure TRigmWizardWorkspace.Poll(Sender: TObject);
begin PollScriptVoice; PollVoicePlayback; EnsureSelectedVoice; PollScriptScenes; for var Session in FSessions do if Session.Busy then Session.Poll; end;
function TRigmWizardWorkspace.ActiveSession: TRigmMovieSession;
begin if FActive=nil then NewWork; Result := FActive; end;
procedure TRigmWizardWorkspace.NewWork;
begin FActive := TRigmMovieSession.Create; FSessions.Add(FActive); end;
procedure TRigmWizardWorkspace.OpenWork(const Path: string);
begin
  var FullPath := ExpandFileName(Path);
  for var Session in FSessions do if SameText(Session.Project.FileName,FullPath) then begin
    if (Session.Project.ScriptWizard<>nil) and (JS(Session.Project.ScriptWizard,'stage')<>'editor') then begin OpenScriptDraft(FullPath); if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit; end;
    FActive := Session; if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,''); Exit;
  end;
  var Loaded := LoadMovie(FullPath); // 失敗する入力で現在の作品を置き換えない。
  try
    if (Loaded.ScriptWizard<>nil) and (JS(Loaded.ScriptWizard,'stage')<>'editor') then begin OpenScriptDraft(FullPath); if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit; end;
  finally Loaded.Free; end;
  var Session := TRigmMovieSession.Create;
  try
    var A := TJSONObject.Create;
    try A.AddPair('path',FullPath); A.AddPair('projectId',Session.Project.Id); AddN(A,'revision',Session.Project.Revision);
      var R := Session.Execute('open',A); R.Free;
    finally A.Free; end;
    FSessions.Add(Session); FActive := Session; Session := nil;
  finally Session.Free; end;
  if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,'');
end;
procedure TRigmWizardWorkspace.RequestMovie(Sender: TObject);
begin if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,''); end;
function TRigmWizardWorkspace.RequestFinish: Boolean;
begin
  StopVoice; PollScriptVoice; if VoiceBusy then begin CancelVoice; Exit(False); end;
  Result := True;
  try SaveScriptDraft(False); except on E: Exception do Exit(False); end;
  for var Session in FSessions do begin
    Session.Poll;
    if Session.Busy then begin
      var A := TJSONObject.Create; try var R := Session.Execute('job-cancel',A); R.Free; finally A.Free; end;
      Result := False;
    end;
  end;
  if not Result then Exit;
  for var Session in FSessions do if Session.Project.Modified then begin
    var Snapshot := Session.Project.Clone;
    try SaveMovie(Snapshot,TPath.Combine(AppSettings.Root,'Recovery\recovery-'+Snapshot.Id.Replace('{','').Replace('}','')+'.rigmovie'));
      AppSettings.RecordRecovery(Session.Project,Snapshot.FileName,Session.Time,Session.ResumeCue);
    finally Snapshot.Free; end;
  end;
end;
{$I RigmScriptVoiceWorkspace.inc}
{$I RigmScriptVoiceEffectsWorkspace.inc}
{$I RigmScriptScenesWorkspace.inc}
{$I RigmScriptClosingWorkspace.inc}
{$I RigmScriptResearchWorkspace.inc}
end.
