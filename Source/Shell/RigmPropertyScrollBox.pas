unit RigmPropertyScrollBox;

interface

uses System.Classes, System.Types, Winapi.Windows, Vcl.Controls, Vcl.Forms,
  Vcl.AppEvnts, Vcl.ComCtrls;

type
  TRigmFineTrackBar = class(TTrackBar)
  private
    FWheelRemainder: Integer;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    procedure AdjustWheel(Delta: Integer);
  end;

  TRigmPropertyScrollBox = class(TScrollBox)
  private
    FEvents: TApplicationEvents;
    FWheelRemainder: Integer;
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    procedure ScrollWheel(Delta: Integer);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

uses System.Math, Winapi.Messages, Vcl.StdCtrls;

procedure TRigmFineTrackBar.AdjustWheel(Delta: Integer);
var Steps, Value: Integer;
begin
  Inc(FWheelRemainder, Delta); Steps := FWheelRemainder div WHEEL_DELTA;
  FWheelRemainder := FWheelRemainder mod WHEEL_DELTA;
  Value := EnsureRange(Position + Steps, Min, Max);
  if Value <> Position then Position := Value;
end;

function TRigmFineTrackBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := PtInRect(ClientRect, ScreenToClient(MousePos));
  if Result then AdjustWheel(WheelDelta);
end;

constructor TRigmPropertyScrollBox.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  VertScrollBar.Tracking := True;
  FEvents := TApplicationEvents.Create(Self);
  FEvents.OnMessage := ApplicationMessage;
end;

procedure TRigmPropertyScrollBox.ScrollWheel(Delta: Integer);
var Lines: Cardinal; Steps, Pixels: Integer;
begin
  Inc(FWheelRemainder, Delta);
  Steps := FWheelRemainder div WHEEL_DELTA;
  FWheelRemainder := FWheelRemainder mod WHEEL_DELTA;
  if Steps = 0 then Exit;
  Lines := 3;
  SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, @Lines, 0);
  if Lines = WHEEL_PAGESCROLL then Pixels := Max(1, ClientHeight)
  else Pixels := Integer(Lines) * MulDiv(20, CurrentPPI, 96);
  VertScrollBar.Position := EnsureRange(VertScrollBar.Position - Steps * Pixels,
    0, Max(0, VertScrollBar.Range - ClientHeight));
end;

procedure TRigmPropertyScrollBox.ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
var P: TPoint; Hover: HWND; Form: TCustomForm; Control: TWinControl;
begin
  if Handled or (Msg.message <> WM_MOUSEWHEEL) or not HandleAllocated or not Showing or not Enabled then Exit;
  Form := GetParentForm(Self);
  if (Form = nil) or not Form.Enabled then Exit;
  P := Point(SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)));
  Hover := WindowFromPoint(P);
  if (Hover <> Handle) and not IsChild(Handle, Hover) then Exit;
  if not PtInRect(ClientRect, ScreenToClient(P)) then Exit;
  Control := FindControl(Hover);
  if Control is TRigmFineTrackBar then begin
    TRigmFineTrackBar(Control).AdjustWheel(SmallInt(HiWord(Msg.wParam)));
    Handled := True; Exit;
  end;
  // Other child controls keep panel scrolling without editing or stealing focus.
  for var I := 0 to ControlCount - 1 do
    if Controls[I] is TComboBox then TComboBox(Controls[I]).DroppedDown := False;
  ScrollWheel(SmallInt(HiWord(Msg.wParam)));
  Handled := True;
end;

function TRigmPropertyScrollBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  ScrollWheel(WheelDelta);
  Result := True;
end;

end.
