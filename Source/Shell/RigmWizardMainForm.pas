unit RigmWizardMainForm;

// 新シェルのメインフォームはページ所有・遷移・共通終了だけを扱う。
// 通常のRIGMMaker.dprと検証用RIGMWizard.dprが同じメインフォームを使用する。
interface
uses System.Classes, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, RigmPageNavigation, RigmWizardWorkspace;
type
  TRigmWizardMainForm = class(TForm)
  private
    FRoot: string; FHost: TPanel; FTitle: TLabel;
    FPages: array[TRigmAppPage] of TFrame;
    FCurrentPage: TRigmAppPage;
    FWorkspace: TRigmWizardWorkspace;
    function EnsureWorkspace: TRigmWizardWorkspace;
    function ExecuteUiCommand(const Command: string; Args: TJSONObject): TJSONObject;
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
uses System.SysUtils, Winapi.Windows, RigmAppSettings, RigmCharacterEditPage, RigmMovieWorkspaceFrame,
  RigmHomeFrame, RigmCharacterManagerFrame, RigmScriptManagerFrame, RigmScriptCreatorFrame;
constructor TRigmWizardMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner); Caption := 'RIGM Maker'; Width := 1280; Height := 840;
  // CreateNewは通常のメインフォーム生成フラグを通らないため、タスクバー表示を明示する。
  ShowInTaskBar := True; Icon.Assign(Application.Icon);
  Position := poScreenCenter; Font.Name := 'Yu Gothic UI'; Font.Size := 10; OnCloseQuery := Closing;
  KeyPreview := True; OnKeyDown := CommonKey;
  FRoot := RigmDocumentsDirectory;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 44; Header.BevelOuter := bvNone;
  var Button := TButton.Create(Self); Button.Parent := Header; Button.Align := alLeft; Button.Width := 140; Button.Caption := 'ホームへ戻る'; Button.Name := 'WizardHome'; Button.OnClick := Home;
  FTitle := TLabel.Create(Self); FTitle.Parent := Header; FTitle.Align := alClient; FTitle.Layout := tlCenter; FTitle.Font.Size := 16;
  FHost := TPanel.Create(Self); FHost.Parent := Self; FHost.Align := alClient; FHost.BevelOuter := bvNone;
  EnsureWorkspace; NavigateTo(apHome);
end;
function TRigmWizardMainForm.EnsurePage(Page: TRigmAppPage): TFrame;
begin
  if FPages[Page]<>nil then Exit(FPages[Page]);
  case Page of
    apHome: begin
      var Frame := TRigmHomeFrame.Create(Self); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
    end;
    apCharacters: begin
      var Frame := TRigmCharacterManagerFrame.CreateForRoot(Self,FRoot,EnsureWorkspace); FPages[Page] := Frame; Frame.OnNavigate := NavigationRequested;
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
  var Loading := False;
  if Page=apCharacterEdit then Loading := (Path<>'') or
    ((TRigmCharacterEditPage(Target).PsdEditor=nil) and (TRigmCharacterEditPage(Target).LegacyEditor=nil));
  if Loading then TRigmCharacterEditPage(Target).BeginCharacterLoad(Path);
  var Previous := FPages[FCurrentPage];
  if Previous<>nil then begin if Supports(Previous,IRigmPageLifecycle,Lifecycle) then Lifecycle.SetActive(False); Previous.Visible := False; end;
  FCurrentPage := Page; Target.Visible := True; Target.BringToFront; FTitle.Caption := '  '+RigmPageTitle(Page);
  if FWorkspace<>nil then FWorkspace.CurrentPage := Page;
  try
    if Loading then begin
      // 読み込み前に新画面と案内のWM_PAINTだけを処理する。入力・パイプの再入を起こさない。
      RedrawWindow(Handle,nil,0,RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN);
      if (Path<>'') and not TRigmCharacterEditPage(Target).ActivateCharacter(Path) then
        raise Exception.Create('キャラを開けません。編集中の入力とファイルを確認してください。');
    end;
    if Page=apScripts then TRigmScriptManagerFrame(Target).RefreshLibrary;
  finally
    try
      if Supports(Target,IRigmPageLifecycle,Lifecycle) then Lifecycle.SetActive(True);
    finally
      if Loading then TRigmCharacterEditPage(Target).EndCharacterLoad;
    end;
  end;
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
  if FWorkspace=nil then begin
    FWorkspace := TRigmWizardWorkspace.Create(Self); FWorkspace.OnNavigate := NavigationRequested;
    FWorkspace.OnUiCommand := ExecuteUiCommand; FWorkspace.StartPipe(FRoot);
  end;
  Result := FWorkspace;
end;
function TRigmWizardMainForm.ExecuteUiCommand(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command='select-property-page' then begin
    var Movie := TRigmMovieWorkspaceFrame(EnsurePage(apMovieEdit));
    Movie.CurrentEditor.SelectPropertyPage(Args.GetValue<string>('propertyPage'));
    Result := TJSONObject.Create; Result.AddPair('propertyPage',Movie.CurrentEditor.PropertyPageName); Exit;
  end;
  var Edit := TRigmCharacterEditPage(EnsurePage(apCharacterEdit));
  if Command.StartsWith('psd-') then begin
    Edit.ActivateCharacter(''); NavigateTo(apCharacterEdit);
    Exit(Edit.PsdEditor.ExternalCommand(Command.Substring(4),Args));
  end;
  Edit.ActivateLegacyEditor; NavigateTo(apCharacterEdit);
  var Name := Command; if Name.StartsWith('legacy-') then Name := Name.Substring(7);
  Result := Edit.LegacyEditor.Editor.Execute(Name,Args);
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
