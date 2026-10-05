unit RigmScriptManagerFrame;
interface
uses System.Classes, Vcl.Forms, Vcl.ComCtrls, Vcl.StdCtrls, RigmWizardWorkspace, RigmPageNavigation;
type
  TRigmScriptManagerFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FRoot: string; FList: TListView; FStatus: TLabel; FOnNavigate: TRigmNavigateEvent;
    procedure OpenWork(Sender: TObject);
    procedure NewWork(Sender: TObject);
    procedure ChooseWork(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    procedure RefreshLibrary;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.SysUtils, System.IOUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Dialogs, RigmMovieModel;
{$R *.dfm}
constructor TRigmScriptManagerFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FRoot := Root;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 40; Header.BevelOuter := bvNone;
  var Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '新しい台本・作品'; Button.Name := 'ScriptNew'; Button.OnClick := NewWork;
  Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '選択作品を再開'; Button.Name := 'ScriptResume'; Button.OnClick := OpenWork;
  Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 180; Button.Caption := '別の作品を開く'; Button.OnClick := ChooseWork;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 48; FStatus.WordWrap := True;
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport; FList.RowSelect := True; FList.ReadOnly := True; FList.Name := 'ScriptLibrary';
  FList.Columns.Add.Caption := '台本・作品'; FList.Columns[0].Width := 420; FList.Columns.Add.Caption := '保存先'; FList.Columns[1].Width := 780; FList.OnDblClick := OpenWork;
  RefreshLibrary;
end;
procedure TRigmScriptManagerFrame.RefreshLibrary;
begin
  FList.Items.Clear;
  if DirectoryExists(FRoot) then for var Path in TDirectory.GetFiles(FRoot,'*.rigmovie',TSearchOption.soAllDirectories) do begin
    var Item := FList.Items.Add; Item.Caption := TPath.GetFileNameWithoutExtension(Path); Item.SubItems.Add(Path);
    try var Project := LoadMovie(Path); try Item.Caption := Project.Title; finally Project.Free; end;
    except on E: Exception do Item.Caption := Item.Caption+'（読込不可）'; end;
  end;
  FStatus.Caption := '既存のrigmovieに台本と作品設定を保存します。未保存の作品はページ移動後も保持します。';
end;
procedure TRigmScriptManagerFrame.OpenWork(Sender: TObject);
begin
  if FList.Selected=nil then Exit;
  try FWorkspace.OpenWork(FList.Selected.SubItems[0]); except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TRigmScriptManagerFrame.NewWork(Sender: TObject);
begin FWorkspace.NewWork; if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,''); end;
procedure TRigmScriptManagerFrame.ChooseWork(Sender: TObject);
begin
  var Dialog := TOpenDialog.Create(Self);
  try Dialog.Filter := '台本・動画作品|*.rigmovie'; Dialog.InitialDir := FRoot; if Dialog.Execute then
    try FWorkspace.OpenWork(Dialog.FileName); except on E: Exception do FStatus.Caption := E.Message; end;
  finally Dialog.Free; end;
end;
end.
