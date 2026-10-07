unit RigmAul2LampSwitch;

// ControllerのエフェクターON/OFFを示す発光LED付きスイッチを担当する。

interface

uses
  Winapi.Messages,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2LampSwitch = class(TCustomControl)
  private
    FChecked: Boolean;
    FHover: Boolean;
    FPanelColor: TColor;
    FPressed: Boolean;
    FTextColor: TColor;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure SetChecked(Value: Boolean);
    procedure SetPanelColor(const Value: TColor);
    procedure SetTextColor(const Value: TColor);
    procedure Toggle;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property Anchors;
    property Checked: Boolean read FChecked write SetChecked default False;
    property Color;
    property Enabled;
    property Font;
    property OnClick;
    property PanelColor: TColor read FPanelColor write SetPanelColor default $00292522;
    property ParentFont;
    property ShowHint;
    property TabStop default True;
    property TextColor: TColor read FTextColor write SetTextColor default $00ECECEC;
    property Visible;
  end;

implementation

uses
  Winapi.Windows,
  System.Types;

constructor TAul2LampSwitch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 180;
  Height := 28;
  Color := RGB(28, 30, 33);
  ParentBackground := False;
  DoubleBuffered := True;
  Cursor := crHandPoint;
  TabStop := True;
  FPanelColor := RGB(34, 37, 41);
  FTextColor := RGB(236, 236, 236);
end;

procedure TAul2LampSwitch.SetChecked(Value: Boolean);
begin
  if FChecked = Value then
    Exit;
  FChecked := Value;
  Invalidate;
end;

procedure TAul2LampSwitch.SetPanelColor(const Value: TColor);
begin
  if FPanelColor = Value then
    Exit;
  FPanelColor := Value;
  Invalidate;
end;

procedure TAul2LampSwitch.SetTextColor(const Value: TColor);
begin
  if FTextColor = Value then
    Exit;
  FTextColor := Value;
  Invalidate;
end;

procedure TAul2LampSwitch.Toggle;
begin
  if not Enabled then
    Exit;
  Checked := not Checked;
  Click;
end;

procedure TAul2LampSwitch.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FHover := True;
  Invalidate;
end;

procedure TAul2LampSwitch.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHover := False;
  FPressed := False;
  Invalidate;
end;

procedure TAul2LampSwitch.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not Enabled then
    Exit;
  if CanFocus then
    SetFocus;
  FPressed := True;
  MouseCapture := True;
  Invalidate;
end;

procedure TAul2LampSwitch.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ShouldToggle: Boolean;
begin
  inherited;
  if (Button <> mbLeft) or not FPressed then
    Exit;
  ShouldToggle := PtInRect(ClientRect, Point(X, Y));
  FPressed := False;
  MouseCapture := False;
  Invalidate;
  if ShouldToggle then
    Toggle;
end;

procedure TAul2LampSwitch.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if Key in [VK_SPACE, VK_RETURN] then
  begin
    Toggle;
    Key := 0;
  end;
end;

procedure TAul2LampSwitch.Paint;
var
  BodyRect: TRect;
  LedCenter: TPoint;
  StateText: string;
  TextRect: TRect;
begin
  inherited;
  // 前回の文字描画で透明にしたブラシを戻し、再描画時の黒抜けを防ぐ。
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  BodyRect := Rect(1, 1, ClientWidth - 1, ClientHeight - 1);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  if FHover then
    Canvas.Pen.Color := RGB(88, 92, 98)
  else
    Canvas.Pen.Color := RGB(55, 59, 64);
  // 押下中もエフェクター固有の面色を維持し、黒い点滅に見せない。
  Canvas.Brush.Color := FPanelColor;
  Canvas.RoundRect(BodyRect.Left, BodyRect.Top, BodyRect.Right, BodyRect.Bottom, 7, 7);

  LedCenter := Point(17, ClientHeight div 2);
  Canvas.Pen.Style := psClear;
  if FChecked and Enabled then
  begin
    Canvas.Brush.Color := RGB(67, 13, 16);
    Canvas.Ellipse(LedCenter.X - 12, LedCenter.Y - 12, LedCenter.X + 12, LedCenter.Y + 12);
    Canvas.Brush.Color := RGB(126, 17, 23);
    Canvas.Ellipse(LedCenter.X - 10, LedCenter.Y - 10, LedCenter.X + 10, LedCenter.Y + 10);
    Canvas.Brush.Color := RGB(92, 94, 97);
    Canvas.Ellipse(LedCenter.X - 8, LedCenter.Y - 8, LedCenter.X + 8, LedCenter.Y + 8);
    Canvas.Brush.Color := RGB(255, 25, 31);
    Canvas.Ellipse(LedCenter.X - 7, LedCenter.Y - 7, LedCenter.X + 7, LedCenter.Y + 7);
    Canvas.Brush.Color := RGB(255, 154, 158);
    Canvas.Ellipse(LedCenter.X - 3, LedCenter.Y - 5, LedCenter.X + 1, LedCenter.Y - 1);
  end
  else
  begin
    Canvas.Brush.Color := RGB(79, 82, 86);
    Canvas.Ellipse(LedCenter.X - 9, LedCenter.Y - 9, LedCenter.X + 9, LedCenter.Y + 9);
    Canvas.Brush.Color := RGB(42, 12, 14);
    Canvas.Ellipse(LedCenter.X - 7, LedCenter.Y - 7, LedCenter.X + 7, LedCenter.Y + 7);
    Canvas.Brush.Color := RGB(91, 38, 40);
    Canvas.Ellipse(LedCenter.X - 4, LedCenter.Y - 5, LedCenter.X, LedCenter.Y - 1);
  end;

  Canvas.Font.Assign(Font);
  Canvas.Font.Style := [fsBold];
  if Enabled then
    Canvas.Font.Color := FTextColor
  else
    Canvas.Font.Color := RGB(126, 126, 126);
  Canvas.Brush.Style := bsClear;
  if FChecked then
    StateText := 'ON'
  else
    StateText := 'OFF';
  TextRect := Rect(36, 1, ClientWidth - 8, ClientHeight - 1);
  DrawText(Canvas.Handle, PChar(StateText), -1, TextRect,
    DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS or DT_VCENTER);
end;

end.
