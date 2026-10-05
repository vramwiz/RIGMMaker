unit RigmScriptCreatorFrame;
interface
uses System.Classes, Vcl.Forms, RigmWizardWorkspace, RigmMovieCreator, RigmMovieSession, RigmPageNavigation;
type
  TRigmScriptCreatorFrame = class(TFrame,IRigmPageLifecycle)
  private
    FWorkspace: TRigmWizardWorkspace; FCreator: TRigmMovieCreator; FBound: TRigmMovieSession; FRoot: string;
    procedure Movie(Sender: TObject);
    procedure NewWork(Sender: TObject);
    procedure SaveWork(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    property Creator: TRigmMovieCreator read FCreator;
  end;
implementation
uses System.SysUtils, System.JSON, System.IOUtils, System.UITypes, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Dialogs, RigmJson;
{$R *.dfm}
constructor TRigmScriptCreatorFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FRoot := Root;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 40; Header.BevelOuter := bvNone;
  var Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '動画編集へ'; Button.Name := 'CreationGoMovie'; Button.OnClick := Movie;
  Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '新しい作品'; Button.Name := 'CreationNewWork'; Button.OnClick := NewWork;
  Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '作品を保存'; Button.OnClick := SaveWork;
  FCreator := TRigmMovieCreator.CreateForWorkspace(Self,TPath.Combine(Root,'RIGM')); FCreator.Parent := Self; FCreator.Align := alClient;
end;
procedure TRigmScriptCreatorFrame.SetActive(Value: Boolean);
begin
  if Value then begin
    var Session := FWorkspace.ActiveSession;
    if FBound<>Session then begin FBound := Session; FCreator.Bind(Session,nil); end;
  end;
  FCreator.SetActive(Value);
end;
procedure TRigmScriptCreatorFrame.Movie(Sender: TObject);
begin FWorkspace.RequestMovie(Self); end;
procedure TRigmScriptCreatorFrame.NewWork(Sender: TObject);
begin FWorkspace.NewWork; SetActive(True); end;
procedure TRigmScriptCreatorFrame.SaveWork(Sender: TObject);
begin
  var Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := '台本・動画作品|*.rigmovie'; Dialog.DefaultExt := 'rigmovie'; Dialog.FileName := FWorkspace.ActiveSession.Project.FileName;
    if Dialog.FileName='' then begin Dialog.InitialDir := FRoot; Dialog.FileName := '作品.rigmovie'; end;
    if not Dialog.Execute then Exit;
    var Session := FWorkspace.ActiveSession; var A := TJSONObject.Create;
    try A.AddPair('path',Dialog.FileName); A.AddPair('projectId',Session.Project.Id); AddN(A,'revision',Session.Project.Revision); var R := Session.Execute('save',A); R.Free;
    finally A.Free; end;
  finally Dialog.Free; end;
end;
function TRigmScriptCreatorFrame.RequestFinish: Boolean;
begin Result := not FCreator.HasInputDraft or (MessageDlg('台本作成の未適用入力を破棄して終了しますか？',mtConfirmation,[mbYes,mbNo],0)=mrYes); end;
end.
