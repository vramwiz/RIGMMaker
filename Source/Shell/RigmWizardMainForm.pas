unit RigmWizardMainForm;

// 新シェルのメインフォームはページ所有・遷移・共通終了だけを扱う。
// 旧シェルの機能移行が完了するまではRIGMWizard.dprの隔離入口を使用する。
interface
uses System.Classes, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, RigmPageNavigation;
type
  TRigmWizardMainForm = class(TForm)
  private
    FRoot: string; FHost: TPanel; FTitle: TLabel;
    FPages: array[TRigmAppPage] of TFrame;
    FCurrentPage: TRigmAppPage;
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
  end;
var RigmWizardMain: TRigmWizardMainForm;
implementation
uses System.SysUtils, Vcl.Controls, RigmAppSettings, PsdStudioFrame,
  RigmHomeFrame, RigmCharacterManagerFrame, RigmPendingFrame;
constructor TRigmWizardMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner); Caption := 'RIGM Maker：PSD・共通ページ検証版'; Width := 1280; Height := 840;
  Position := poScreenCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 10; OnCloseQuery := Closing;
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
      var Frame := TPsdStudioFrame.CreateForCharacter(Self,FRoot,''); FPages[Page] := Frame; Frame.OnReturn := ReturnCharacters; Frame.OnSaved := SavedCharacter;
    end;
    apScripts,apScriptCreate,apMovieEdit: begin
      var Frame := TRigmPendingFrame.CreateForPage(Self,Page); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
    end;
  end;
  Result := FPages[Page]; Result.Visible := False; Result.Parent := FHost; Result.Align := alClient;
  // Owner=Selfが寿命を管理する。Parentは表示先。ページ切替ではFreeしない。
end;
procedure TRigmWizardMainForm.NavigateTo(Page: TRigmAppPage; const Path: string);
begin
  var Target := EnsurePage(Page);
  if (Page=apCharacterEdit) and (Path<>'') then TPsdStudioFrame(Target).ActivateCharacter(Path);
  var Previous := FPages[FCurrentPage];
  if Previous<>nil then begin if Previous is TPsdStudioFrame then TPsdStudioFrame(Previous).SetActive(False); Previous.Visible := False; end;
  FCurrentPage := Page; Target.Visible := True; Target.BringToFront; FTitle.Caption := '  '+RigmPageTitle(Page);
  if Target is TPsdStudioFrame then TPsdStudioFrame(Target).SetActive(True);
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
begin CanClose := (FPages[apCharacterEdit]=nil) or TPsdStudioFrame(FPages[apCharacterEdit]).RequestFinish; end;
function TRigmWizardMainForm.CreatedPageCount: Integer;
begin Result := 0; for var Page := Low(TRigmAppPage) to High(TRigmAppPage) do if FPages[Page]<>nil then Inc(Result); end;
function TRigmWizardMainForm.PageInstance(Page: TRigmAppPage): TFrame;
begin Result := FPages[Page]; end;
end.
