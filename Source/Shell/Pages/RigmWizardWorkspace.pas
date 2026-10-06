unit RigmWizardWorkspace;

// 台本/動画ページ共通の既存Session所有者。UIを作らず、ページより長く生存する。
interface
uses System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Vcl.ExtCtrls,
  RigmMovieSession, RigmMovieModel, RigmPageNavigation, RigmWizardPipe, ArtPipeProtocol, RigmThumbnailCache, RigmMovieJobs;
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
    FScriptViewStage: string; FPlacementEditing,FScriptTextEditing: Boolean;
    FVoiceJob: TRigmMovieJob; FVoiceCollected: Boolean; FVoiceCatalog: TJSONArray; FVoiceCatalogUrl,FVoiceError,FPlayVoice,FVoiceTarget: string;
    FVoiceBindings: TJSONObject; FVoiceBindingsHash: string;
    procedure PollScriptVoice;
    procedure EnsureVoiceBindings;
    procedure StoreScript(Snapshot: TRigmMovieProject; const ViewStage: string);
    procedure ScriptChanged;
    function ScriptPath(Project: TRigmMovieProject): string;
    procedure CheckScript(Project: TRigmMovieProject);
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
    procedure MoveVoice(Delta: Integer);
    procedure EditVoice(const CueId,Reading: string; Settings: TJSONObject);
    procedure SetVoiceEngine(const Url: string);
    procedure RefreshVoiceCatalog;
    procedure BindVoice(Number,StyleId: Integer; const Uuid: string);
    procedure SaveCharacterVoice(Number: Integer);
    procedure GenerateVoice(const CueId: string; Play: Boolean);
    procedure CancelVoice;
    procedure StopVoice;
    procedure CompleteVoice;
    function VoiceBusy: Boolean;
    function VoiceStatus: TJSONObject;
    function ReadVoice(Args: TJSONObject): TJSONObject;
    function ReadVoiceCatalog(Args: TJSONObject): TJSONObject;
    function VoiceCatalog: TJSONArray; // 借用。実APIの直近一覧。
    procedure RequestCasting;
    procedure SubmitCasting(Args: TJSONObject);
    procedure AssignCasting(const CueId: string; Number: Integer; Confirm: Boolean);
    procedure SelectCasting(const CueId: string);
    procedure MoveCasting(Delta: Integer);
    procedure SplitCasting(const CueId: string; Offset: Integer);
    procedure MergeCasting(const CueId: string);
    function ReadCasting(Args: TJSONObject): TJSONObject;
    procedure RequestReview;
    procedure SubmitReview(Args: TJSONObject);
    procedure DecideReview(const Id,Decision,Text: string);
    procedure EditReviewDraft(const Id,Text: string);
    function ReadReview(Args: TJSONObject): TJSONObject;
    property ScriptTextEditing: Boolean read FScriptTextEditing;
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
uses System.IOUtils, System.Math, System.DateUtils, System.StrUtils, Winapi.Windows, RigmJson, RigmAppSettings, PsdSession,
  PsdCharacter, PsdJson, PsdPackage, PsdProduction, RigmEditor, PsdImport, RigmStorage,
  System.Hash, ArtDocument, PsdWorkspace, RigmCharacterCatalog, RigmMovieLayout, RigmScriptPlacementModel, RigmScriptTextModel, RigmScriptReviewModel, RigmScriptCastingModel, RigmScriptSubtitleModel, RigmScriptVoiceModel, System.SyncObjs, Winapi.MMSystem;
constructor TRigmWizardWorkspace.Create(AOwner: TComponent);
begin
  inherited; FSessions := TObjectList<TRigmMovieSession>.Create(True);
  FScriptDrafts := TObjectList<TRigmMovieProject>.Create(True);
  FScriptSavedHashes := TDictionary<string,string>.Create; FVoiceCatalog := TJSONArray.Create;
  FTimer := TTimer.Create(Self); FTimer.Interval := 150; FTimer.OnTimer := Poll;
end;
destructor TRigmWizardWorkspace.Destroy;
begin FTimer.Enabled := False; StopVoice; FVoiceJob.Free; FVoiceBindings.Free; FVoiceCatalog.Free; FThumbnails.Free; FPipe.Free; FScriptSavedHashes.Free; FScriptDrafts.Free; FSessions.Free; inherited; end;
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
  if (FPlacementEditing or FScriptTextEditing) and MatchText(Name,['script-new','script-open']) then
    raise Exception.Create('GUIで入力・配置を操作中です。操作完了後に再取得してください。');
  if Name='script-status' then Exit(ScriptStatus);
  if Name='script-list' then Exit(ScriptLibrary(JI(Args,'offset',0),JI(Args,'limit',50)));
  if Name='script-character-library' then Exit(ScriptCharacterLibrary);
  if Name='script-text' then Exit(ReadScriptText(Args));
  if Name='script-review' then Exit(ReadReview(Args));
  if Name='script-casting' then Exit(ReadCasting(Args));
  if Name='script-subtitles' then Exit(ReadSubtitles(Args));
  if Name='script-voice' then Exit(ReadVoice(Args));
  if Name='script-voice-catalog' then Exit(ReadVoiceCatalog(Args));
  if Name='script-new' then begin NewScriptDraft; if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit(ScriptStatus); end;
  if Name='script-open' then begin OpenScriptDraft(JS(Args,'path')); if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit(ScriptStatus); end;
  if MatchText(Name,['script-set-title','script-save','script-set-stage','script-set-characters','script-set-layout','script-next','script-set-placement','script-select-placement','script-set-text','script-select-section','script-request-review','script-submit-review','script-request-casting','script-submit-casting','script-select-casting','script-split-casting','script-merge-casting','script-select-subtitle','script-edit-subtitle','script-set-subtitle-break','script-select-voice','script-edit-voice','script-set-voice-engine','script-refresh-voice','script-bind-voice','script-save-character-voice','script-generate-voice','script-cancel-voice']) then begin
    if FPlacementEditing or FScriptTextEditing then raise Exception.Create('GUIで入力中です。入力完了アイコンを押してから再取得してください。');
    if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
      raise Exception.Create('script-statusの現在のprojectId/revisionを指定してください。');
    if Name='script-select-voice' then SelectVoice(JS(Args,'cueId'))
    else if Name='script-edit-voice' then begin
      if not (Args.GetValue('reading') is TJSONString) or not (Args.GetValue('settings') is TJSONObject) then raise Exception.Create('reading文字列とsettingsを指定してください。');
      EditVoice(JS(Args,'cueId'),JS(Args,'reading'),JO(Args,'settings'));
    end
    else if Name='script-set-voice-engine' then SetVoiceEngine(JS(Args,'engineUrl'))
    else if Name='script-refresh-voice' then RefreshVoiceCatalog
    else if Name='script-bind-voice' then BindVoice(JI(Args,'role'),JI(Args,'styleId',-1),JS(Args,'uuid'))
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
    ScriptSchema.AddPair('script-set-stage',PsdJson.ObjectText('{"projectId":"from script-status","revision":"from script-status","stage":"title|characters|layout|placement|text|review|casting|subtitles (backward only)"}'));
    ScriptSchema.AddPair('script-subtitles',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-select-subtitle',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"from subtitles"}'));
    ScriptSchema.AddPair('script-edit-subtitle',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"required","subtitle":"<=3000 UTF16","note":"optional <=2048"}'));
    ScriptSchema.AddPair('script-set-subtitle-break',PsdJson.ObjectText('{"projectId":"required","revision":"required","cueId":"required","offset":"UTF16 offset after removing first CRLF; remaining CRLF preserved"}'));
    ScriptSchema.AddPair('script-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"limit":1}'));
    ScriptSchema.AddPair('script-voice-catalog',PsdJson.ObjectText('{"projectId":"required","revision":"required","offset":0,"pageSize":20}'));
    ScriptSchema.AddPair('script-set-voice-engine',PsdJson.ObjectText('{"projectId":"required","revision":"required","engineUrl":"local engine URL"}'));
    ScriptSchema.AddPair('script-refresh-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required"}'));
    ScriptSchema.AddPair('script-bind-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","role":1,"styleId":"from live catalog","uuid":"from live catalog"}'));
    ScriptSchema.AddPair('script-save-character-voice',PsdJson.ObjectText('{"projectId":"required","revision":"required","role":1}'));
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
  for var C in Project.Characters do if (C.PlacementRef='') or (Project.Placement(C.PlacementRef)=nil) then
    raise Exception.Create('台本工程のキャラは共通配置への参照が必要です。');
  if Project.ScriptWizard.GetValue('scriptText')<>nil then ValidateScriptText(JO(Project.ScriptWizard,'scriptText'))
  else if ScriptStageIndex(JS(Project.ScriptWizard,'stage'))>=4 then raise Exception.Create('台本入力データがありません。');
  if Project.ScriptWizard.GetValue('voice')<>nil then ValidateScriptVoice(Project) else if JS(Project.ScriptWizard,'stage')='voice' then raise Exception.Create('音声工程の保存状態がありません。');
  if Project.ScriptWizard.GetValue('subtitles')<>nil then ValidateScriptSubtitles(Project)
  else if JS(Project.ScriptWizard,'stage')='subtitles' then raise Exception.Create('字幕データがありません。');
  if Project.ScriptWizard.GetValue('casting')<>nil then ValidateScriptCasting(Project)
  else if JS(Project.ScriptWizard,'stage')='casting' then raise Exception.Create('配役データがありません。');
  if Project.ScriptWizard.GetValue('review')<>nil then ValidateScriptReview(Project)
  else if JS(Project.ScriptWizard,'stage')='review' then raise Exception.Create('校正依頼データがありません。');
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
  P.Title := '題名未入力'; P.ScriptWizard := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptWizard","schemaVersion":1,"stage":"title","titleStatus":"in-progress","titleInput":"","charactersStatus":"in-progress","selectedCharacters":[]}');
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
        FScriptDraft := Existing; FScriptViewStage := JS(Existing.ScriptWizard,'stage'); ScriptChanged; Exit;
      end;
    end;
    P.Modified := False; FScriptDrafts.Add(P); FScriptDraft := P; FScriptViewStage := JS(P.ScriptWizard,'stage'); P := nil;
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
  if (ScriptStageIndex(Value)<0) or (ScriptStageIndex(Value)>ScriptStageIndex(CurrentScriptStage)) then
    raise Exception.Create('次工程へはNextで保存して進んでください。');
  if CurrentScriptStage=Value then Exit;
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
  FScriptDraft.BackgroundColor := Snapshot.BackgroundColor;
  FScriptDraft.ScriptWizard.Free; FScriptDraft.ScriptWizard := Snapshot.ScriptWizard.Clone as TJSONObject;
  var OldCues := FScriptDraft.Cues; FScriptDraft.Cues := Snapshot.Cues; Snapshot.Cues := OldCues;
  var OldScenes := FScriptDraft.Scenes; FScriptDraft.Scenes := Snapshot.Scenes; Snapshot.Scenes := OldScenes;
  var OldSpeakers := FScriptDraft.Speakers; FScriptDraft.Speakers := Snapshot.Speakers; Snapshot.Speakers := OldSpeakers;
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
      PsdJson.Put(Snapshot.ScriptWizard,Key,'complete'); Snapshot.Changed;
    end;
    StoreScript(Snapshot,CurrentScriptStage);
  finally Snapshot.Free; end;
end;
procedure TRigmWizardWorkspace.NextScriptDraft;
begin
  if (FScriptDraft=nil) or FPlacementEditing or FScriptTextEditing then raise Exception.Create('入力操作を完了してからNextで進んでください。');
  var Stage := CurrentScriptStage; var Next := '';
  if Stage='title' then Next := 'characters' else if Stage='characters' then Next := 'layout'
  else if Stage='layout' then Next := 'placement' else if Stage='placement' then Next := 'text' else if Stage='text' then Next := 'review' else if Stage='review' then Next := 'casting' else if Stage='casting' then Next := 'subtitles' else if Stage='subtitles' then Next := 'voice'
  else raise Exception.Create('シーン工程は準備中です。音声調整は戻る・終了時に保存します。');
  if Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))='' then raise Exception.Create('題名を入力してからNextで進んでください。');
  var Snapshot := FScriptDraft.Clone;
  try
    if Snapshot.ScriptWizard.GetValue('selectedCharacters')=nil then Snapshot.ScriptWizard.AddPair('selectedCharacters',TJSONArray.Create);
    if Snapshot.ScriptWizard.GetValue('charactersStatus')=nil then Snapshot.ScriptWizard.AddPair('charactersStatus','in-progress');
    if Stage<>'title' then begin
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
      if not HasText then raise Exception.Create('台本文を入力してから校正へ進んでください。');
      if not (Snapshot.ScriptWizard.GetValue('review') is TJSONObject) or
        (JS(JO(Snapshot.ScriptWizard,'review'),'state')='stale') or
        (JS(JO(Snapshot.ScriptWizard,'review'),'fingerprint')<>ScriptFingerprint(Snapshot)) then RequestScriptReview(Snapshot);
    end;
    if Next='casting' then begin
      var Review := ScriptReviewSummary(Snapshot);
      try
        if (JS(Review,'state')<>'ready') or (JI(Review,'pending')>0) or (JI(Review,'held')>0) or (JI(Review,'stale')>0) then
          raise Exception.Create('校正を受信し、未確定・保留・要再確認の指摘を解決してから配役へ進んでください。');
      finally Review.Free; end;
      PrepareScriptCasting(Snapshot);
    end;
    if Next='subtitles' then PrepareScriptSubtitles(Snapshot);
    if Next='voice' then PrepareScriptVoice(Snapshot);
    if Snapshot.ScriptWizard.GetValue('voice')<>nil then begin if Snapshot.Cue(JS(JO(Snapshot.ScriptWizard,'voice'),'selectedCue'))=nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'voice'),'selectedCue',Snapshot.Cues[0].Id); end;
    if Snapshot.ScriptWizard.GetValue('subtitles')<>nil then begin
      if Snapshot.Cue(JS(JO(Snapshot.ScriptWizard,'subtitles'),'selectedCue'))=nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'subtitles'),'selectedCue',Snapshot.Cues[0].Id);
    end;
    PsdJson.Put(Snapshot.ScriptWizard,Stage+'Status','complete'); PsdJson.Put(Snapshot.ScriptWizard,'stage',Next); Snapshot.Changed;
    StoreScript(Snapshot,Next);
  finally Snapshot.Free; end;
end;
procedure TRigmWizardWorkspace.BeginScriptTextEdit;
begin if MatchText(CurrentScriptStage,['text','review','subtitles','voice']) then FScriptTextEditing := True; end;
procedure TRigmWizardWorkspace.EndScriptTextEdit;
begin FScriptTextEditing := False; end;
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
  RigmScriptSubtitleModel.EditSubtitle(FScriptDraft,CueId,Text,Note); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetSubtitleBreak(const CueId: string; Offset: Integer);
begin
  if CurrentScriptStage<>'subtitles' then raise Exception.Create('字幕工程で操作してください。');
  RigmScriptSubtitleModel.SetSubtitleBreak(FScriptDraft,CueId,Offset); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveSubtitleBreak(const CueId: string; Delta, DefaultOffset: Integer);
begin
  if CurrentScriptStage<>'subtitles' then Exit;
  RigmScriptSubtitleModel.MoveSubtitleBreak(FScriptDraft,CueId,Delta,DefaultOffset); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteSubtitles;
begin
  if CurrentScriptStage<>'subtitles' then Exit; EndScriptTextEdit;
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
    var Row := CastingRow(FScriptDraft,C.Id); AddN(O,'role',JI(Row,'role')); O.AddPair('character',JS(CastingRole(FScriptDraft,JI(Row,'role')),'name')); AddN(O,'breakOffset',C.Subtitle.IndexOf(#13#10));
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
  Result.AddPair('implementedStage','voice'); Result.AddPair('placementEditing',TJSONBool.Create(FPlacementEditing));
  Result.AddPair('textEditing',TJSONBool.Create(FScriptTextEditing));
  var Advance := False;
  if FScriptDraft<>nil then Advance := not FPlacementEditing and not FScriptTextEditing and (Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))<>'') and
    ((CurrentScriptStage='title') or (((CurrentScriptStage='characters') or (CurrentScriptStage='layout') or (CurrentScriptStage='placement') or (CurrentScriptStage='text') or (CurrentScriptStage='review') or (CurrentScriptStage='casting')) and
    (FScriptDraft.ScriptWizard.GetValue('selectedCharacters')<>nil) and (JA(FScriptDraft.ScriptWizard,'selectedCharacters').Count>0)));
  if (FScriptDraft<>nil) and (CurrentScriptStage='subtitles') then Advance := not FScriptTextEditing and (JS(FScriptDraft.ScriptWizard,'subtitlesStatus')='complete');
  if Advance and (CurrentScriptStage='review') then begin
    var Review := ScriptReviewSummary(FScriptDraft);
    try Advance := (JS(Review,'state')='ready') and (JI(Review,'pending')=0) and
      (JI(Review,'held')=0) and (JI(Review,'stale')=0); finally Review.Free; end;
  end;
  if Advance and (CurrentScriptStage='casting') then begin
    var Cast := ScriptCastingSummary(FScriptDraft);
    try Advance := (JS(Cast,'state')<>'stale') and (JI(Cast,'pending')=0) and (JI(Cast,'unassigned')=0); finally Cast.Free; end;
  end;
  Result.AddPair('canAdvance',TJSONBool.Create(Advance));
  if FScriptDraft=nil then Exit;
  Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  Result.AddPair('title',JS(FScriptDraft.ScriptWizard,'titleInput')); Result.AddPair('savedTitle',FScriptDraft.Title);
  Result.AddPair('path',FScriptDraft.FileName); Result.AddPair('modified',TJSONBool.Create(FScriptDraft.Modified));
  Result.AddPair('resumeStage',JS(FScriptDraft.ScriptWizard,'stage'));
  var Wizard := TJSONObject.Create;
  for var Pair in FScriptDraft.ScriptWizard do if not MatchText(Pair.JsonString.Value,['scriptText','review','casting','castingArchives','subtitles','voice']) then
    Wizard.AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
  if FScriptDraft.ScriptWizard.GetValue('scriptText')<>nil then Wizard.AddPair('scriptText',ScriptTextSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('subtitles')<>nil then Wizard.AddPair('subtitles',ScriptSubtitleSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('casting')<>nil then Wizard.AddPair('casting',ScriptCastingSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('review')<>nil then Wizard.AddPair('review',ScriptReviewSummary(FScriptDraft));
  if FScriptDraft.ScriptWizard.GetValue('voice')<>nil then Wizard.AddPair('voice',VoiceStatus);
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
          if P.ScriptWizard<>nil then begin
            CheckScript(P); if not SameText(Paths[I],ScriptPath(P)) then raise Exception.Create('UIDと保存先が一致しません。');
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
begin PollScriptVoice; for var Session in FSessions do if Session.Busy then Session.Poll; end;
function TRigmWizardWorkspace.ActiveSession: TRigmMovieSession;
begin if FActive=nil then NewWork; Result := FActive; end;
procedure TRigmWizardWorkspace.NewWork;
begin FActive := TRigmMovieSession.Create; FSessions.Add(FActive); end;
procedure TRigmWizardWorkspace.OpenWork(const Path: string);
begin
  var FullPath := ExpandFileName(Path);
  for var Session in FSessions do if SameText(Session.Project.FileName,FullPath) then begin
    if Session.Project.ScriptWizard<>nil then begin OpenScriptDraft(FullPath); if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit; end;
    FActive := Session; if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,''); Exit;
  end;
  var Loaded := LoadMovie(FullPath); // 失敗する入力で現在の作品を置き換えない。
  try
    if Loaded.ScriptWizard<>nil then begin OpenScriptDraft(FullPath); if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); Exit; end;
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
end.
