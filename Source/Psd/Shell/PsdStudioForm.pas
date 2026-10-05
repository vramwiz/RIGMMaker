unit PsdStudioForm;

// 独立検証入口と旧シェル用の薄い互換ホスト。新メインフォームはFrameを直接所有する。
interface
uses System.Classes, Vcl.Forms, PsdSession, PsdStudioFrame;
type
  TPsdStudioForm = class(TForm)
  private
    FEditor: TPsdStudioFrame;
    function GetSession: TPsdSession;
    function GetOnSaved: TNotifyEvent;
    procedure SetOnSaved(Value: TNotifyEvent);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure Closed(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateForCharacter(AOwner: TComponent; const Root,Path: string);
    function FindComponent(const AName: string): TComponent; reintroduce;
    function ActivateCharacter(const Path: string): Boolean;
    procedure CaptureSmoke(const Path: string);
    procedure VerifyGuiFlow(const ResultPath: string);
    procedure VerifyPageFlow(const ResultPath: string);
    property Session: TPsdSession read GetSession;
    property OnSaved: TNotifyEvent read GetOnSaved write SetOnSaved;
  end;
var PsdStudioWindow: TPsdStudioForm;
implementation
uses System.SysUtils, PsdWorkspace;
constructor TPsdStudioForm.Create(AOwner: TComponent);
begin
  var Root := PSD_DEFAULT_ROOT;
  for var Index := 1 to ParamCount-1 do if ParamStr(Index)='--root' then Root := ParamStr(Index+1);
  CreateForCharacter(AOwner,Root,'');
end;
constructor TPsdStudioForm.CreateForCharacter(AOwner: TComponent; const Root,Path: string);
begin
  inherited CreateNew(AOwner); Caption := 'PSD立ち絵スタジオ'; Width := 1280; Height := 840;
  Position := poScreenCenter; OnCloseQuery := Closing; OnClose := Closed;
  FEditor := TPsdStudioFrame.CreateForCharacter(Self,Root,Path,True); FEditor.Parent := Self;
end;
function TPsdStudioForm.GetSession: TPsdSession;
begin Result := FEditor.Session; end;
function TPsdStudioForm.GetOnSaved: TNotifyEvent;
begin Result := FEditor.OnSaved; end;
procedure TPsdStudioForm.SetOnSaved(Value: TNotifyEvent);
begin FEditor.OnSaved := Value; end;
function TPsdStudioForm.FindComponent(const AName: string): TComponent;
begin Result := inherited FindComponent(AName); if (Result=nil) and (FEditor<>nil) then Result := FEditor.FindComponent(AName); end;
function TPsdStudioForm.ActivateCharacter(const Path: string): Boolean;
begin Result := FEditor.ActivateCharacter(Path); end;
procedure TPsdStudioForm.CaptureSmoke(const Path: string);
begin FEditor.CaptureSmoke(Path); end;
procedure TPsdStudioForm.VerifyGuiFlow(const ResultPath: string);
begin FEditor.VerifyGuiFlow(ResultPath); end;
procedure TPsdStudioForm.VerifyPageFlow(const ResultPath: string);
begin FEditor.VerifyPageFlow(ResultPath); end;
procedure TPsdStudioForm.Closing(Sender: TObject; var CanClose: Boolean);
begin CanClose := FEditor.RequestFinish; end;
procedure TPsdStudioForm.Closed(Sender: TObject; var Action: TCloseAction);
begin Action := caFree; end;
end.
