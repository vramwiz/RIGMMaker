unit RigmWizardWorkspace;

// 台本/動画ページ共通の既存Session所有者。UIを作らず、ページより長く生存する。
interface
uses System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Vcl.ExtCtrls,
  RigmMovieSession, RigmPageNavigation, RigmWizardPipe, ArtPipeProtocol;
type
  TRigmWizardWorkspace = class(TComponent)
  private
    FSessions: TObjectList<TRigmMovieSession>; FActive: TRigmMovieSession;
    FOnNavigate: TRigmNavigateEvent;
    FTimer: TTimer;
    FPipe: TRigmWizardPipe; FPage: TRigmAppPage; FOnUiCommand: TArtCommandHandler;
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
    property CurrentPage: TRigmAppPage read FPage write FPage;
    property Pipe: TRigmWizardPipe read FPipe;
    property OnUiCommand: TArtCommandHandler read FOnUiCommand write FOnUiCommand;
    property Sessions: TObjectList<TRigmMovieSession> read FSessions;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.IOUtils, RigmMovieModel, RigmJson, RigmAppSettings, PsdSession,
  PsdCharacter, PsdJson, PsdPackage, PsdProduction, RigmEditor, PsdImport, RigmStorage,
  System.Hash, ArtDocument, PsdWorkspace;
constructor TRigmWizardWorkspace.Create(AOwner: TComponent);
begin
  inherited; FSessions := TObjectList<TRigmMovieSession>.Create(True);
  FTimer := TTimer.Create(Self); FTimer.Interval := 150; FTimer.OnTimer := Poll;
end;
destructor TRigmWizardWorkspace.Destroy;
begin FTimer.Enabled := False; FPipe.Free; FSessions.Free; inherited; end;
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
  if Name='library' then Exit(CharacterLibrary);
  if Name='register-character' then Exit(RegisterCharacter(Args));
  if Name='schema' then begin
    Result := PsdJson.ObjectText('{"workspaceCommandPrefix":"app-","movieCommandPrefix":"movie-","psdCommandPrefix":"psd-","workspace":{"status":{},"library":{},"switch-page":{"page":"home|preview|create|characters|scripts|character-edit","propertyPage":"optional"},"open-work":{"path":".rigmovie"},"edit-character":{"path":".psdchar|.psd|.rigm"},"register-character":{"path":"file within dataRoot","name":"optional"}}}');
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
procedure TRigmWizardWorkspace.Poll(Sender: TObject);
begin for var Session in FSessions do if Session.Busy then Session.Poll; end;
function TRigmWizardWorkspace.ActiveSession: TRigmMovieSession;
begin if FActive=nil then NewWork; Result := FActive; end;
procedure TRigmWizardWorkspace.NewWork;
begin FActive := TRigmMovieSession.Create; FSessions.Add(FActive); end;
procedure TRigmWizardWorkspace.OpenWork(const Path: string);
begin
  var FullPath := ExpandFileName(Path);
  for var Session in FSessions do if SameText(Session.Project.FileName,FullPath) then begin
    FActive := Session; if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,''); Exit;
  end;
  var Loaded := LoadMovie(FullPath); Loaded.Free; // 失敗する入力で現在の作品を置き換えない。
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
  Result := True;
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
end.
