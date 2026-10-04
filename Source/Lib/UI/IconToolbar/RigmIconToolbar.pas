unit RigmIconToolbar;

interface

uses System.Classes, Winapi.Messages, Vcl.Controls, Vcl.ComCtrls, Vcl.ImgList,
  ToolBarPanelManager, RigmToolbarIcons;

type
  TRigmIconToolbar = class(TToolBar)
  private
    FIcons, FDisabledIcons: TImageList;
    FRenderer: TToolBarPanelManager;
    FIconPPI: Integer;
    procedure UpdateMetrics;
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function AddIcon(const Name, Caption: string; Icon: TRigmToolbarIcon;
      Action: Integer; Handler: TNotifyEvent; Toggle: Boolean = False): TToolButton;
    procedure AddSeparator;
  end;

implementation

uses System.SysUtils, Winapi.Windows, Vcl.Graphics, Vcl.Themes;

constructor TRigmIconToolbar.Create(AOwner: TComponent);
begin
  inherited;
  FIconPPI := 96;
  FIcons := TImageList.Create(Self); FDisabledIcons := TImageList.Create(Self);
  FRenderer := TToolBarPanelManager.Create; FRenderer.ShowCaptions := False;
end;

procedure TRigmIconToolbar.SetParent(AParent: TWinControl);
begin
  inherited;
  if (AParent = nil) or (FRenderer = nil) then Exit;
  Flat := True; ShowCaptions := False; ShowHint := True; ParentShowHint := False;
  AutoSize := True; Wrapable := True; EdgeBorders := []; DoubleBuffered := True; TabStop := True;
  Images := FIcons; DisabledImages := FDisabledIcons;
  FRenderer.Attach(Self, False);
  FIconPPI := CurrentPPI;
  UpdateMetrics;
end;

destructor TRigmIconToolbar.Destroy;
begin FreeAndNil(FRenderer); inherited; end;

procedure TRigmIconToolbar.UpdateMetrics;
var Size: Integer;
begin
  if (FRenderer = nil) or (Parent = nil) then Exit;
  Size := MulDiv(24, FIconPPI, 96);
  BuildRigmToolbarIcons(FIcons, Size, StyleServices(Self).GetSystemColor(clWindowText));
  BuildRigmToolbarIcons(FDisabledIcons, Size, StyleServices(Self).GetSystemColor(clGrayText));
  FRenderer.ToolBarBackgroundColor := StyleServices(Self).GetSystemColor(clBtnFace);
  FRenderer.ToolBarFontColor := StyleServices(Self).GetSystemColor(clWindowText);
  FRenderer.ToolBarCheckedColor := StyleServices(Self).GetSystemColor(clHighlight);
  FRenderer.ToolBarPressedColor := StyleServices(Self).GetSystemColor(clBtnShadow);
  FRenderer.ToolBarHotColor := StyleServices(Self).GetSystemColor(clBtnHighlight);
  ButtonWidth := MulDiv(40, FIconPPI, 96); ButtonHeight := ButtonWidth;
  for var I := 0 to ButtonCount - 1 do
    if Buttons[I].Style = tbsSeparator then Buttons[I].Width := MulDiv(12, FIconPPI, 96);
  Invalidate;
end;

procedure TRigmIconToolbar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited;
  // Use the scale notification: CurrentPPI can still report the old HWND DPI here.
  if isDpiChange then FIconPPI := M else FIconPPI := MulDiv(FIconPPI, M, D);
  UpdateMetrics;
end;

procedure TRigmIconToolbar.CMStyleChanged(var Message: TMessage);
begin inherited; UpdateMetrics; end;

function TRigmIconToolbar.AddIcon(const Name, Caption: string; Icon: TRigmToolbarIcon;
  Action: Integer; Handler: TNotifyEvent; Toggle: Boolean): TToolButton;
begin
  Result := TToolButton.Create(Self); Result.Name := Name; Result.Caption := Caption;
  Result.Hint := Caption; Result.ShowHint := True; Result.Tag := Action;
  Result.ImageIndex := Ord(Icon);
  Result.Left := ButtonCount * ButtonWidth; Result.Parent := Self;
  if Toggle then begin Result.Style := tbsCheck; Result.AllowAllUp := True; end;
  Result.OnClick := Handler;
end;

procedure TRigmIconToolbar.AddSeparator;
var B: TToolButton;
begin
  B := TToolButton.Create(Self); B.Style := tbsSeparator;
  B.Left := ButtonCount * ButtonWidth; B.Parent := Self;
  B.Width := MulDiv(12, FIconPPI, 96);
end;

end.
