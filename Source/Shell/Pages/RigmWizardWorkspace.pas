unit RigmWizardWorkspace;

// 台本/動画ページ共通の既存Session所有者。UIを作らず、ページより長く生存する。
interface
uses System.Classes, System.SysUtils, System.Generics.Collections, Vcl.ExtCtrls, RigmMovieSession, RigmPageNavigation;
type
  TRigmWizardWorkspace = class(TComponent)
  private
    FSessions: TObjectList<TRigmMovieSession>; FActive: TRigmMovieSession;
    FOnNavigate: TRigmNavigateEvent;
    FTimer: TTimer;
    procedure Poll(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ActiveSession: TRigmMovieSession;
    procedure NewWork;
    procedure OpenWork(const Path: string);
    procedure RequestMovie(Sender: TObject);
    function RequestFinish: Boolean;
    property Sessions: TObjectList<TRigmMovieSession> read FSessions;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.JSON, System.IOUtils, RigmMovieModel, RigmJson, RigmAppSettings;
constructor TRigmWizardWorkspace.Create(AOwner: TComponent);
begin
  inherited; FSessions := TObjectList<TRigmMovieSession>.Create(True);
  FTimer := TTimer.Create(Self); FTimer.Interval := 150; FTimer.OnTimer := Poll;
end;
destructor TRigmWizardWorkspace.Destroy;
begin FTimer.Enabled := False; FSessions.Free; inherited; end;
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
