unit RigmCharacterEditPage;
interface
uses System.Classes, Vcl.Forms, PsdStudioFrame, RigmLegacyEditorFrame, RigmWizardWorkspace, RigmPageNavigation;
type
  TRigmCharacterEditPage = class(TFrame,IRigmPageLifecycle)
  private
    FRoot: string; FWorkspace: TRigmWizardWorkspace;
    FPsd: TPsdStudioFrame; FLegacy: TRigmLegacyEditorFrame; FCurrent: TFrame;
    FOnReturn,FOnSaved: TNotifyEvent;
    procedure Return(Sender: TObject);
    procedure Saved(Sender: TObject);
    procedure SelectPsd(Sender: TObject);
    procedure SelectLegacy(Sender: TObject);
    function EnsurePsd: TPsdStudioFrame;
    function EnsureLegacy: TRigmLegacyEditorFrame;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    function ActivateCharacter(const Path: string): Boolean;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    property OnReturn: TNotifyEvent read FOnReturn write FOnReturn;
    property OnSaved: TNotifyEvent read FOnSaved write FOnSaved;
    property PsdEditor: TPsdStudioFrame read FPsd;
    property LegacyEditor: TRigmLegacyEditorFrame read FLegacy;
  end;
implementation
uses System.SysUtils, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls;
{$R *.dfm}
constructor TRigmCharacterEditPage.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FRoot := Root; FWorkspace := Workspace;
  var Bar := TPanel.Create(Self); Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 38; Bar.BevelOuter := bvNone;
  var Button := TButton.Create(Self); Button.Parent := Bar; Button.Align := alLeft; Button.Width := 180; Button.Caption := 'キャラ管理へ戻る'; Button.OnClick := Return;
  Button := TButton.Create(Self); Button.Parent := Bar; Button.Align := alLeft; Button.Width := 180; Button.Caption := 'PSD編集'; Button.Name := 'CharacterPsdEditor'; Button.OnClick := SelectPsd;
  Button := TButton.Create(Self); Button.Parent := Bar; Button.Align := alLeft; Button.Width := 180; Button.Caption := '既存RIGM / Live2D編集'; Button.Name := 'CharacterLegacyEditor'; Button.OnClick := SelectLegacy;
end;
function TRigmCharacterEditPage.EnsurePsd: TPsdStudioFrame;
begin
  if FPsd=nil then begin FPsd := TPsdStudioFrame.CreateForCharacter(Self,FRoot,''); FPsd.Parent := Self; FPsd.Align := alClient; FPsd.OnReturn := Return; FPsd.OnSaved := Saved; end;
  Result := FPsd;
end;
function TRigmCharacterEditPage.EnsureLegacy: TRigmLegacyEditorFrame;
begin
  if FLegacy=nil then begin
    FLegacy := TRigmLegacyEditorFrame.CreateForRoot(Self,FRoot); FLegacy.Parent := Self; FLegacy.Align := alClient;
    FLegacy.Editor.OnGetMovie := FWorkspace.ActiveSession; FLegacy.OnMovieRequested := FWorkspace.RequestMovie; FLegacy.OnSaved := Saved;
  end;
  Result := FLegacy;
end;
function TRigmCharacterEditPage.ActivateCharacter(const Path: string): Boolean;
begin
  SetActive(False);
  if (Path='') or SameText(ExtractFileExt(Path),'.psdchar') or SameText(ExtractFileExt(Path),'.psd') then begin
    FCurrent := EnsurePsd; Result := (Path='') or FPsd.ActivateCharacter(Path);
  end else begin FCurrent := EnsureLegacy; Result := FLegacy.ActivateCharacter(Path); end;
  if FPsd<>nil then FPsd.Visible := FCurrent=FPsd;
  if FLegacy<>nil then FLegacy.Visible := FCurrent=FLegacy;
  FCurrent.BringToFront;
end;
procedure TRigmCharacterEditPage.SetActive(Value: Boolean);
begin
  if Value and (FCurrent=nil) then ActivateCharacter('');
  if FPsd<>nil then FPsd.SetActive(Value and (FCurrent=FPsd));
  if FLegacy<>nil then FLegacy.SetActive(Value and (FCurrent=FLegacy));
end;
function TRigmCharacterEditPage.RequestFinish: Boolean;
begin Result := ((FPsd=nil) or FPsd.RequestFinish) and ((FLegacy=nil) or FLegacy.RequestFinish); end;
procedure TRigmCharacterEditPage.Return(Sender: TObject);
begin if Assigned(FOnReturn) then FOnReturn(Self); end;
procedure TRigmCharacterEditPage.Saved(Sender: TObject);
begin if Assigned(FOnSaved) then FOnSaved(Self); end;
procedure TRigmCharacterEditPage.SelectPsd(Sender: TObject);
begin ActivateCharacter(''); SetActive(True); end;
procedure TRigmCharacterEditPage.SelectLegacy(Sender: TObject);
begin
  SetActive(False); FCurrent := EnsureLegacy; FLegacy.Visible := True; if FPsd<>nil then FPsd.Visible := False;
  FLegacy.BringToFront; SetActive(True);
end;
end.
