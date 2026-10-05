unit RigmWizardMainForm;

// 新シェルのメインフォームはページ所有・遷移・共通終了だけを扱う。
// 旧シェルの機能移行が完了するまではRIGMWizard.dprの隔離入口を使用する。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, RigmPageNavigation, RigmWizardWorkspace;
type
  TRigmWizardMainForm = class(TForm)
  private
    FRoot: string; FHost: TPanel; FTitle: TLabel;
    FPages: array[TRigmAppPage] of TFrame;
    FCurrentPage: TRigmAppPage;
    FWorkspace: TRigmWizardWorkspace;
    function EnsureWorkspace: TRigmWizardWorkspace;
    procedure CommonKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    function EnsurePage(Page: TRigmAppPage): TFrame;
    procedure NavigationRequested(Sender: TObject; Page: TRigmAppPage; const Path: string);
    procedure ReturnCharacters(Sender: TObject);
    procedure SavedCharacter(Sender: TObject);
    procedure Home(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    procedure NavigateTo(Page: TRigmAppPage; const Path: string = '');
    function CreatedPageCount: Integer;
    function PageInstance(Page: TRigmAppPage): TFrame;
    property CurrentPage: TRigmAppPage read FCurrentPage;
    property DataRoot: string read FRoot;
    property Workspace: TRigmWizardWorkspace read FWorkspace;
  end;
var RigmWizardMain: TRigmWizardMainForm;
implementation
uses System.SysUtils, RigmAppSettings, RigmCharacterEditPage, RigmMovieWorkspaceFrame,
  RigmHomeFrame, RigmCharacterManagerFrame, RigmScriptManagerFrame, RigmScriptCreatorFrame;
constructor TRigmWizardMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner); Caption := 'RIGM Maker：PSD・共通ページ検証版'; Width := 1280; Height := 840;
  Position := poScreenCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 10; OnCloseQuery := Closing;
  KeyPreview := True; OnKeyDown := CommonKey;
  FRoot := RigmDocumentsDirectory;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 44; Header.BevelOuter := bvNone;
  var Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 140; Button.Caption := 'ホームへ戻る'; Button.Name := 'WizardHome'; Button.OnClick := Home;
  FTitle := TLabel.Create(Self); FTitle.Parent := Header; FTitle.Align := alClient; FTitle.Layout := tlCenter; FTitle.Font.Size := 16;
  FHost := TPanel.Create(Self); FHost.Parent := Self; FHost.Align := alClient; FHost.BevelOuter := bvNone;
  NavigateTo(apHome);
end;
function TRigmWizardMainForm.EnsurePage(Page: TRigmAppPage): TFrame;
begin
  if FPages[Page]<>nil then Exit(FPages[Page]);
  case Page of
    apHome: begin
      var Frame := TRigmHomeFrame.Create(Self); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
    end;
    apCharacters: begin
      var Frame := TRigmCharacterManagerFrame.CreateForRoot(Self,FRoot); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
    end;
    apCharacterEdit: begin
      var Frame := TRigmCharacterEditPage.CreateForWorkspace(Self,EnsureWorkspace,FRoot); FPages[Page] := Frame; Frame.OnReturn := ReturnCharacters; Frame.OnSaved := SavedCharacter;
    end;
    apScripts: begin
      var Frame := TRigmScriptManagerFrame.CreateForWorkspace(Self,EnsureWorkspace,FRoot); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
    end;
    apScriptCreate: begin
      FPages[Page] := TRigmScriptCreatorFrame.CreateForWorkspace(Self,EnsureWorkspace,FRoot);
    end;
    apMovieEdit: begin
      FPages[Page] := TRigmMovieWorkspaceFrame.CreateForWorkspace(Self,EnsureWorkspace);
    end;
  end;
  Result := FPages[Page]; Result.Visible := False; Result.Parent := FHost; Result.Align := alClient;
  // Owner=Selfが寿命を管理する。Parentは表示先。ページ切替ではFreeしない。
end;
procedure TRigmWizardMainForm.NavigateTo(Page: TRigmAppPage; const Path: string);
begin
  var Lifecycle: IRigmPageLifecycle;
  var Target := EnsurePage(Page);
  if (Page=apCharacterEdit) and (Path<>'') then TRigmCharacterEditPage(Target).ActivateCharacter(Path);
  var Previous := FPages[FCurrentPage];
  if Previous<>nil then begin if Supports(Previous,IRigmPageLifecycle,Lifecycle) then Lifecycle.SetActive(False); Previous.Visible := False; end;
  FCurrentPage := Page; Target.Visible := True; Target.BringToFront; FTitle.Caption := '  '+RigmPageTitle(Page);
  if Page=apScripts then TRigmScriptManagerFrame(Target).RefreshLibrary;
  if Supports(Target,IRigmPageLifecycle,Lifecycle) then Lifecycle.SetActive(True);
end;
procedure TRigmWizardMainForm.NavigationRequested(Sender: TObject; Page: TRigmAppPage; const Path: string);
begin NavigateTo(Page,Path); end;
procedure TRigmWizardMainForm.ReturnCharacters(Sender: TObject);
begin NavigateTo(apCharacters); end;
procedure TRigmWizardMainForm.SavedCharacter(Sender: TObject);
begin if FPages[apCharacters]<>nil then TRigmCharacterManagerFrame(FPages[apCharacters]).RefreshLibrary(Self); end;
procedure TRigmWizardMainForm.Home(Sender: TObject);
begin NavigateTo(apHome); end;
procedure TRigmWizardMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := False; var Lifecycle: IRigmPageLifecycle;
  for var Page := Low(TRigmAppPage) to High(TRigmAppPage) do if (FPages[Page]<>nil) and
    Supports(FPages[Page],IRigmPageLifecycle,Lifecycle) and not Lifecycle.RequestFinish then Exit;
  if (FWorkspace<>nil) and not FWorkspace.RequestFinish then begin FTitle.Caption := '取消処理の完了後に再度終了してください。'; Exit; end;
  CanClose := True;
end;
function TRigmWizardMainForm.EnsureWorkspace: TRigmWizardWorkspace;
begin
  if FWorkspace=nil then begin FWorkspace := TRigmWizardWorkspace.Create(Self); FWorkspace.OnNavigate := NavigationRequested; end;
  Result := FWorkspace;
end;
procedure TRigmWizardMainForm.CommonKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (FCurrentPage=apMovieEdit) and (TRigmMovieWorkspaceFrame(FPages[apMovieEdit]).CurrentEditor<>nil) then
    TRigmMovieWorkspaceFrame(FPages[apMovieEdit]).CurrentEditor.HandleKey(Key,Shift);
end;
function TRigmWizardMainForm.CreatedPageCount: Integer;
begin Result := 0; for var Page := Low(TRigmAppPage) to High(TRigmAppPage) do if FPages[Page]<>nil then Inc(Result); end;
function TRigmWizardMainForm.PageInstance(Page: TRigmAppPage): TFrame;
begin Result := FPages[Page]; end;
end.
