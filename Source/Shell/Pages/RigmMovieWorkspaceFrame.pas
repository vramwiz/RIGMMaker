unit RigmMovieWorkspaceFrame;
interface
uses System.Classes, System.SysUtils, System.Generics.Collections, Vcl.Forms,
  RigmWizardWorkspace, RigmMovieEditorFrame, RigmMovieSession, RigmPageNavigation;
type
  TRigmMovieWorkspaceFrame = class(TFrame,IRigmPageLifecycle)
  private
    FWorkspace: TRigmWizardWorkspace;
    FViews: TDictionary<TRigmMovieSession,TRigmMovieEditorFrame>; FCurrent: TRigmMovieEditorFrame;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    property CurrentEditor: TRigmMovieEditorFrame read FCurrent;
  end;
implementation
uses Vcl.Controls;
{$R *.dfm}
constructor TRigmMovieWorkspaceFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FViews := TDictionary<TRigmMovieSession,TRigmMovieEditorFrame>.Create; end;
destructor TRigmMovieWorkspaceFrame.Destroy;
begin FViews.Free; inherited; end; // 各ビューはSelfのOwner管理。辞書は借用参照のみ。
procedure TRigmMovieWorkspaceFrame.SetActive(Value: Boolean);
begin
  if not Value then begin if FCurrent<>nil then FCurrent.SetActive(False); Exit; end;
  var Session := FWorkspace.ActiveSession; var View: TRigmMovieEditorFrame;
  if not FViews.TryGetValue(Session,View) then begin
    View := TRigmMovieEditorFrame.CreateForSession(Self,Session,True); View.Parent := Self; View.Align := alClient;
    View.OnOpenWork := FWorkspace.OpenWork; FViews.Add(Session,View);
  end;
  for var Other in FViews.Values do if Other<>View then begin Other.SetActive(False); Other.Visible := False; end;
  FCurrent := View; View.Visible := True; View.BringToFront; View.SetActive(True);
end;
function TRigmMovieWorkspaceFrame.RequestFinish: Boolean;
begin Result := True; for var View in FViews.Values do if not View.RequestFinish then Exit(False); end;
end.
