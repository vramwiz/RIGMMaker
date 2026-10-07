unit RigmAul2VolumeControl;

// Controllerで連続値を表示する音響機器風ノブの描画と値表示を担当する。

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls;

const
  VOLUME_VERTICAL_RANGE_PER_PIXEL   = 1.0 / 180.0; // 縦ドラッグ1px当たりの全値域比率（粗調整）。
  VOLUME_HORIZONTAL_RANGE_PER_PIXEL = 1.0 / 600.0; // 横ドラッグ1px当たりの全値域比率（微調整）。
  VOLUME_DRAG_AXIS_THRESHOLD        = 4;           // 縦横の操作軸を確定する最小移動量。

type
  TVolumeDragAxis = (vdaNone, vdaHorizontal, vdaVertical);
  TVolumeValueChangeEvent = procedure(Sender: TObject; const ValueText: string;
    var Accept: Boolean) of object;

  TAul2VolumeControl = class(TCustomControl)
  private
    FAccentColor: TColor;
    FDecimals: Integer;
    FDisplayName: string;
    FDragAxis: TVolumeDragAxis;
    FDragging: Boolean;
    FDragStartPoint: TPoint;
    FDragStartValue: Double;
    FEditStartText: string;
    FMaximum: Double;
    FMinimum: Double;
    FOnValueChange: TVolumeValueChangeEvent;
    FPanelColor: TColor;
    FStep: Double;
    FTextColor: TColor;
    FUnitText: string;
    FValue: Double;
    FValueEdit: TEdit;
    FValueText: string;
    function ScalePx(LogicalPixels: Integer): Integer;
    procedure CommitValueEdit;
    procedure EditEnter(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function FormatValue(Value: Double): string;
    procedure InvalidateKnob;
    procedure LayoutValueEdit;
    function NormalizeValue(Value: Double): Double;
    procedure SetAccentColor(const Value: TColor);
    procedure SetDisplayName(const Value: string);
    procedure SetMaximum(const Value: Double);
    procedure SetMinimum(const Value: Double);
    procedure SetPanelColor(const Value: TColor);
    procedure SetTextColor(const Value: TColor);
    procedure SetEditText(const Value: string);
    procedure SetUnitText(const Value: string);
    procedure SetValue(const Value: Double);
    procedure SetValueText(const Value: string);
    function TryApplyValue(Value: Double; NotifyChange: Boolean): Boolean;
  protected
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure CreateParams(var Params: TCreateParams); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 表示名、値域、刻み、小数桁、単位を一度に設定する。
    procedure Configure(const DisplayName: string; Minimum, Maximum, Step: Double;
      Decimals: Integer; const UnitText: string = '');
    function CommitPendingValue: Boolean; // Explicit save/Next for toolbar buttons that keep edit focus.
    property ValueText: string read FValueText write SetValueText;
  published
    property AccentColor: TColor read FAccentColor write SetAccentColor default $00D88A38;
    property Align;
    property Anchors;
    property Color;
    property DisplayName: string read FDisplayName write SetDisplayName;
    property Enabled;
    property Font;
    property Maximum: Double read FMaximum write SetMaximum;
    property Minimum: Double read FMinimum write SetMinimum;
    property OnValueChange: TVolumeValueChangeEvent read FOnValueChange write FOnValueChange;
    property PanelColor: TColor read FPanelColor write SetPanelColor default $00292522;
    property ParentFont;
    property ShowHint;
    property TextColor: TColor read FTextColor write SetTextColor default $00E8E8E8;
    property UnitText: string read FUnitText write SetUnitText;
    property Value: Double read FValue write SetValue;
    property Visible;
  end;

implementation

uses
  Winapi.Messages,
  Winapi.Windows,
  System.Math,
  System.SysUtils;

function ScaleColor(Color: TColor; Numerator, Denominator: Integer): TColor;
var
  Blue : Integer;
  Green: Integer;
  Red  : Integer;
begin
  Color := ColorToRGB(Color);
  Red := EnsureRange(GetRValue(Color) * Numerator div Denominator, 0, 255);
  Green := EnsureRange(GetGValue(Color) * Numerator div Denominator, 0, 255);
  Blue := EnsureRange(GetBValue(Color) * Numerator div Denominator, 0, 255);
  Result := RGB(Red, Green, Blue);
end;

procedure DrawKnobArc(Canvas: TCanvas; const Center: TPoint; Radius, StartDegree,
  EndDegree: Integer; Color: TColor; Width: Integer);
const
  ARC_SEGMENTS = 18;
var
  Angle       : Double;
  PointIndex  : Integer;
  Points      : array[0..ARC_SEGMENTS] of TPoint;
begin
  for PointIndex := 0 to ARC_SEGMENTS do
  begin
    Angle := DegToRad(StartDegree + (EndDegree - StartDegree) * PointIndex / ARC_SEGMENTS);
    Points[PointIndex] := Point(
      Center.X + Round(Cos(Angle) * Radius),
      Center.Y + Round(Sin(Angle) * Radius));
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := Color;
  Canvas.Pen.Width := Width;
  Canvas.Polyline(Points);
end;

procedure DrawKnobLimitMark(Canvas: TCanvas; const Center: TPoint; Radius,
  Degree, InnerOffset, OuterOffset, LineWidth: Integer);
var
  Angle    : Double;
  InnerPoint: TPoint;
  OuterPoint: TPoint;
begin
  Angle := DegToRad(Degree);
  InnerPoint := Point(
    Center.X + Round(Cos(Angle) * (Radius + InnerOffset)),
    Center.Y + Round(Sin(Angle) * (Radius + InnerOffset)));
  OuterPoint := Point(
    Center.X + Round(Cos(Angle) * (Radius + OuterOffset)),
    Center.Y + Round(Sin(Angle) * (Radius + OuterOffset)));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := LineWidth;
  Canvas.Pen.Color := RGB(118, 122, 127);
  Canvas.MoveTo(InnerPoint.X, InnerPoint.Y);
  Canvas.LineTo(OuterPoint.X, OuterPoint.Y);
end;

constructor TAul2VolumeControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Parent接続や寸法変更でResize/Paintが発火する前に、子Editを完全に構築する。
  FValueEdit := TEdit.Create(Self);
  FValueEdit.ReadOnly := False;
  FValueEdit.TabStop := True;
  FValueEdit.Text := '0';
  FValueEdit.Alignment := taCenter;
  FValueEdit.AutoSize := False;
  FValueEdit.BorderStyle := bsSingle;
  FValueEdit.Color := RGB(19, 21, 24);
  FValueEdit.Font.Color := RGB(248, 248, 248);
  FValueEdit.ParentFont := True;
  FValueEdit.OnEnter := EditEnter;
  FValueEdit.OnExit := EditExit;
  FValueEdit.OnKeyDown := EditKeyDown;

  Width := 72;
  Height := 126;
  Color := RGB(31, 34, 38);
  ParentBackground := False;
  DoubleBuffered := True;
  Cursor := crSizeAll;
  TabStop := True;
  FAccentColor := RGB(56, 138, 216);
  FPanelColor := RGB(34, 37, 41);
  FTextColor := RGB(232, 232, 232);
  FDisplayName := 'Value';
  FMinimum := 0;
  FMaximum := 1;
  FStep := 0.01;
  FDecimals := 2;
  FValue := 0;
  FValueText := '0';
  FValueEdit.Parent := Self;
  LayoutValueEdit;
end;

procedure TAul2VolumeControl.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // 親の再描画では子TEditの領域を除外する。
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

function TAul2VolumeControl.ScalePx(LogicalPixels: Integer): Integer;
var PPI: Integer;
begin
  PPI := CurrentPPI;
  if PPI <= 0 then PPI := 96;
  Result := MulDiv(LogicalPixels, PPI, 96);
end;

procedure TAul2VolumeControl.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited;
  // The inherited DPI change scales fonts/children first. Reapply our logical editor geometry last.
  LayoutValueEdit;
  Invalidate;
end;

procedure TAul2VolumeControl.SetEditText(const Value: string);
begin
  if not Assigned(FValueEdit) or (FValueEdit.Text = Value) then
    Exit;

  if not FValueEdit.HandleAllocated then
  begin
    FValueEdit.Text := Value;
    Exit;
  end;

  // WM_SETTEXT中の背景消去を画面へ出さず、確定した文字列を1回だけ描画する。
  FValueEdit.Perform(WM_SETREDRAW, 0, 0);
  try
    FValueEdit.Text := Value;
  finally
    FValueEdit.Perform(WM_SETREDRAW, 1, 0);
    RedrawWindow(FValueEdit.Handle, nil, 0,
      RDW_INVALIDATE or RDW_UPDATENOW or RDW_NOERASE);
  end;
end;

procedure TAul2VolumeControl.InvalidateKnob;
var
  KnobRect: TRect;
begin
  if not HandleAllocated then
  begin
    Invalidate;
    Exit;
  end;

  // Independent DPI rounding of center/radius/shadow can exceed the scaled base bottom by one pixel.
  KnobRect := Rect(0, ScalePx(26), Width,
    Max(ScalePx(88), ScalePx(57) + ScalePx(27) + ScalePx(4)));
  InvalidateRect(Handle, @KnobRect, False);
end;

procedure TAul2VolumeControl.LayoutValueEdit;
var
  EditHeight: Integer;
  EditRight: Integer;
  EditTop  : Integer;
  UnitWidth: Integer;
begin
  if not Assigned(FValueEdit) then
    Exit;

  // Handle生成前のResize/Configureからも呼ばれるため、Canvasには触れない。
  if FUnitText <> '' then
    UnitWidth := Max(ScalePx(18), ScalePx(Length(FUnitText) * 7 + 5))
  else
    UnitWidth := 0;
  // ClientWidth/ClientHeightはHandleを要求するため、Parent接続前は保存済み寸法を使う。
  // TEditの既定AutoSizeへ任せると、親カードの固定高さと異なる倍率で拡大されて下端が欠ける。
  EditHeight := ScalePx(23);
  EditRight := Width - ScalePx(6) - UnitWidth;
  EditTop := Min(Height - EditHeight - ScalePx(14), ScalePx(89));
  FValueEdit.SetBounds(ScalePx(6), EditTop, Max(ScalePx(24), EditRight - ScalePx(6)), EditHeight);
end;

function TAul2VolumeControl.FormatValue(Value: Double): string;
var
  FormatSettings: TFormatSettings;
  Mask          : string;
begin
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  Mask := '0';
  if FDecimals > 0 then
    Mask := Mask + '.' + StringOfChar('#', FDecimals);
  Result := FormatFloat(Mask, Value, FormatSettings);
end;

function TAul2VolumeControl.NormalizeValue(Value: Double): Double;
begin
  Result := EnsureRange(Value, FMinimum, FMaximum);
  if FStep > 0 then
    Result := FMinimum + Round((Result - FMinimum) / FStep) * FStep;
  Result := EnsureRange(Result, FMinimum, FMaximum);
end;

function TAul2VolumeControl.TryApplyValue(Value: Double; NotifyChange: Boolean): Boolean;
var
  Accept : Boolean;
  NewText: string;
  NewValue: Double;
begin
  NewValue := NormalizeValue(Value);
  NewText := FormatValue(NewValue);
  if SameValue(FValue, NewValue) and (FValueText = NewText) then
  begin
    SetEditText(FValueText);
    Exit(True);
  end;

  Accept := True;
  if NotifyChange and Assigned(FOnValueChange) then
    FOnValueChange(Self, NewText, Accept);
  Result := Accept;
  if not Result then
  begin
    SetEditText(FValueText);
    Exit;
  end;

  FValue := NewValue;
  FValueText := NewText;
  SetEditText(NewText);
  InvalidateKnob;
end;

function TAul2VolumeControl.CommitPendingValue: Boolean;
var N: Double;
begin
  if (FValueEdit<>nil) and (FValueEdit.Text=FValueText) then Exit(True);
  Result := (FValueEdit<>nil) and TryStrToFloat(Trim(FValueEdit.Text),N,TFormatSettings.Invariant);
  if not Result or IsNan(N) or IsInfinite(N) then Exit(False);
  Result := TryApplyValue(N,True);
end;

procedure TAul2VolumeControl.CommitValueEdit;
var
  FormatSettings: TFormatSettings;
  NumberValue   : Double;
begin
  if FValueEdit.Text=FValueText then Exit;
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(FValueEdit.Text), NumberValue, FormatSettings) or IsNan(NumberValue) or IsInfinite(NumberValue) then
  begin
    SetEditText(FValueText);
    Exit;
  end;
  TryApplyValue(NumberValue, True);
end;

procedure TAul2VolumeControl.EditEnter(Sender: TObject);
begin
  FEditStartText := FValueText;
  FValueEdit.SelectAll;
end;

procedure TAul2VolumeControl.EditExit(Sender: TObject);
begin
  CommitValueEdit;
end;

procedure TAul2VolumeControl.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        CommitValueEdit;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        SetEditText(FEditStartText);
        Key := 0;
      end;
  end;
end;

procedure TAul2VolumeControl.Configure(const DisplayName: string; Minimum, Maximum, Step: Double;
  Decimals: Integer; const UnitText: string);
begin
  FDisplayName := DisplayName;
  FMinimum := Minimum;
  FMaximum := Maximum;
  FStep := Step;
  FDecimals := Max(0, Decimals);
  FUnitText := UnitText;
  FValue := NormalizeValue(FValue);
  FValueText := FormatValue(FValue);
  SetEditText(FValueText);
  LayoutValueEdit;
  Invalidate;
end;

procedure TAul2VolumeControl.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2VolumeControl.SetDisplayName(const Value: string);
begin
  if FDisplayName = Value then
    Exit;
  FDisplayName := Value;
  Invalidate;
end;

procedure TAul2VolumeControl.SetMaximum(const Value: Double);
begin
  if SameValue(FMaximum, Value) then
    Exit;
  FMaximum := Max(Value, FMinimum);
  SetValue(FValue);
  Invalidate;
end;

procedure TAul2VolumeControl.SetMinimum(const Value: Double);
begin
  if SameValue(FMinimum, Value) then
    Exit;
  FMinimum := Min(Value, FMaximum);
  SetValue(FValue);
  Invalidate;
end;

procedure TAul2VolumeControl.SetPanelColor(const Value: TColor);
begin
  if FPanelColor = Value then
    Exit;
  FPanelColor := Value;
  Invalidate;
end;

procedure TAul2VolumeControl.SetTextColor(const Value: TColor);
begin
  if FTextColor = Value then
    Exit;
  FTextColor := Value;
  Invalidate;
end;

procedure TAul2VolumeControl.SetUnitText(const Value: string);
begin
  if FUnitText = Value then
    Exit;
  FUnitText := Value;
  LayoutValueEdit;
  Invalidate;
end;

procedure TAul2VolumeControl.SetValue(const Value: Double);
begin
  TryApplyValue(Value, False);
end;

procedure TAul2VolumeControl.SetValueText(const Value: string);
var
  FormatSettings: TFormatSettings;
  NumberValue   : Double;
begin
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  if TryStrToFloat(Trim(Value), NumberValue, FormatSettings) then
  begin
    // 外部読込値は元の表示文字列を保ち、ノブ角度だけを値域内へ制限する。
    FValue := EnsureRange(NumberValue, FMinimum, FMaximum);
    FValueText := Value;
    SetEditText(Value);
    InvalidateKnob;
  end
  else if Assigned(FValueEdit) then
    SetEditText(FValueText);
end;

procedure TAul2VolumeControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not Enabled then
    Exit;

  if CanFocus then
    SetFocus;
  FDragging := True;
  FDragAxis := vdaNone;
  FDragStartPoint := Point(X, Y);
  FDragStartValue := FValue;
  MouseCapture := True;
end;

procedure TAul2VolumeControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DeltaPixels: Integer;
  DeltaValue : Double;
  DeltaX     : Integer;
  DeltaY     : Integer;
  ValueRange : Double;
begin
  inherited;
  if not FDragging then
    Exit;

  DeltaX := X - FDragStartPoint.X;
  DeltaY := Y - FDragStartPoint.Y;
  if FDragAxis = vdaNone then
  begin
    if Max(Abs(DeltaX), Abs(DeltaY)) < ScalePx(VOLUME_DRAG_AXIS_THRESHOLD) then
      Exit;
    if Abs(DeltaX) > Abs(DeltaY) then
      FDragAxis := vdaHorizontal
    else
      FDragAxis := vdaVertical;
  end;

  ValueRange := FMaximum - FMinimum;
  if FDragAxis = vdaHorizontal then
  begin
    DeltaPixels := DeltaX;
    DeltaValue := DeltaPixels * ValueRange * VOLUME_HORIZONTAL_RANGE_PER_PIXEL * 96 / ScalePx(96);
  end
  else
  begin
    DeltaPixels := -DeltaY;
    DeltaValue := DeltaPixels * ValueRange * VOLUME_VERTICAL_RANGE_PER_PIXEL * 96 / ScalePx(96);
  end;
  TryApplyValue(FDragStartValue + DeltaValue, True);
end;

procedure TAul2VolumeControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not FDragging then
    Exit;
  FDragging := False;
  FDragAxis := vdaNone;
  MouseCapture := False;
end;

procedure TAul2VolumeControl.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (Key = VK_ESCAPE) and FDragging then
  begin
    TryApplyValue(FDragStartValue, True);
    FDragging := False;
    FDragAxis := vdaNone;
    MouseCapture := False;
    Key := 0;
  end;
end;

function TAul2VolumeControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  StepCount: Integer;
begin
  if not Enabled or (FStep <= 0) then
    Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));

  StepCount := WheelDelta div WHEEL_DELTA;
  if StepCount = 0 then
    StepCount := Sign(WheelDelta);
  TryApplyValue(FValue + StepCount * FStep, True);
  Result := True;
end;

procedure TAul2VolumeControl.Resize;
begin
  inherited;
  LayoutValueEdit;
end;

procedure TAul2VolumeControl.Paint;
var
  Angle       : Double;
  CardRect    : TRect;
  Center      : TPoint;
  KnobRadius  : Integer;
  LineEnd     : TPoint;
  LineStart   : TPoint;
  Ratio       : Double;
  TextRect    : TRect;
  UnitLeft    : Integer;
begin
  inherited;
  // Text painting leaves bsClear behind; restore a solid brush on every repaint.
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  CardRect := Rect(ScalePx(1), ScalePx(1), ClientWidth - ScalePx(1), ClientHeight - ScalePx(1));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := ScalePx(1);
  Canvas.Pen.Color := RGB(58, 62, 68);
  Canvas.Brush.Color := FPanelColor;
  Canvas.RoundRect(CardRect.Left, CardRect.Top, CardRect.Right, CardRect.Bottom, ScalePx(9), ScalePx(9));

  Canvas.Font.Assign(Font);
  Canvas.Font.Color := FTextColor;
  Canvas.Font.Style := [fsBold];
  Canvas.Brush.Style := bsClear;
  TextRect := Rect(ScalePx(3), ScalePx(7), ClientWidth - ScalePx(3), ScalePx(25));
  DrawText(Canvas.Handle, PChar(FDisplayName), -1, TextRect,
    DT_CENTER or DT_SINGLELINE or DT_END_ELLIPSIS or DT_VCENTER);

  KnobRadius := Min(ClientWidth div 2 - ScalePx(7), ScalePx(27));
  KnobRadius := Max(KnobRadius, ScalePx(18));
  Center := Point(ClientWidth div 2, ScalePx(57));

  DrawKnobLimitMark(Canvas, Center, KnobRadius, 135, ScalePx(2), ScalePx(7), ScalePx(2));
  DrawKnobLimitMark(Canvas, Center, KnobRadius, 405, ScalePx(2), ScalePx(7), ScalePx(2));

  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := RGB(10, 11, 12);
  Canvas.Ellipse(Center.X - KnobRadius + ScalePx(2), Center.Y - KnobRadius + ScalePx(4),
    Center.X + KnobRadius + ScalePx(2), Center.Y + KnobRadius + ScalePx(4));
  Canvas.Brush.Color := RGB(82, 86, 91);
  Canvas.Ellipse(Center.X - KnobRadius, Center.Y - KnobRadius,
    Center.X + KnobRadius, Center.Y + KnobRadius);
  Canvas.Brush.Color := RGB(13, 14, 16);
  Canvas.Ellipse(Center.X - KnobRadius + ScalePx(2), Center.Y - KnobRadius + ScalePx(2),
    Center.X + KnobRadius - ScalePx(2), Center.Y + KnobRadius - ScalePx(2));
  Canvas.Brush.Color := RGB(27, 29, 33);
  Canvas.Ellipse(Center.X - KnobRadius + ScalePx(4), Center.Y - KnobRadius + ScalePx(4),
    Center.X + KnobRadius - ScalePx(4), Center.Y + KnobRadius - ScalePx(4));
  Canvas.Brush.Color := RGB(36, 39, 43);
  Canvas.Ellipse(Center.X - KnobRadius + ScalePx(7), Center.Y - KnobRadius + ScalePx(6),
    Center.X + KnobRadius - ScalePx(7), Center.Y + KnobRadius - ScalePx(8));
  Canvas.Brush.Color := RGB(43, 46, 50);
  Canvas.Ellipse(Center.X - KnobRadius + ScalePx(11), Center.Y - KnobRadius + ScalePx(10),
    Center.X + KnobRadius - ScalePx(10), Center.Y + KnobRadius - ScalePx(12));

  DrawKnobArc(Canvas, Center, KnobRadius - ScalePx(3), 190, 300, RGB(112, 116, 121), ScalePx(2));
  DrawKnobArc(Canvas, Center, KnobRadius - ScalePx(3), 10, 120, RGB(8, 9, 10), ScalePx(2));
  DrawKnobArc(Canvas, Point(Center.X - ScalePx(1), Center.Y - ScalePx(1)), KnobRadius - ScalePx(7),
    205, 290, RGB(64, 68, 73), ScalePx(1));

  if FMaximum > FMinimum then
    Ratio := EnsureRange((FValue - FMinimum) / (FMaximum - FMinimum), 0.0, 1.0)
  else
    Ratio := 0;
  Angle := DegToRad(135 + Ratio * 270);

  LineStart := Point(
    Center.X + Round(Cos(Angle) * (KnobRadius * 0.27)),
    Center.Y + Round(Sin(Angle) * (KnobRadius * 0.27)));
  LineEnd := Point(
    Center.X + Round(Cos(Angle) * (KnobRadius * 0.72)),
    Center.Y + Round(Sin(Angle) * (KnobRadius * 0.72)));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(ScalePx(3), KnobRadius div 6);
  Canvas.Pen.Color := RGB(7, 8, 9);
  Canvas.MoveTo(LineStart.X + ScalePx(1), LineStart.Y + ScalePx(1));
  Canvas.LineTo(LineEnd.X + ScalePx(1), LineEnd.Y + ScalePx(1));
  Canvas.Pen.Color := ScaleColor(FAccentColor, 5, 4);
  Canvas.MoveTo(LineStart.X, LineStart.Y);
  Canvas.LineTo(LineEnd.X, LineEnd.Y);
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := ScaleColor(FAccentColor, 5, 4);
  Canvas.Ellipse(LineEnd.X - ScalePx(2), LineEnd.Y - ScalePx(2), LineEnd.X + ScalePx(3), LineEnd.Y + ScalePx(3));

  if (FUnitText <> '') and Assigned(FValueEdit) then
  begin
    UnitLeft := FValueEdit.Left + FValueEdit.Width + ScalePx(3);
    TextRect := Rect(UnitLeft, FValueEdit.Top, ClientWidth - ScalePx(4),
      FValueEdit.Top + FValueEdit.Height);
    Canvas.Font.Style := [];
    Canvas.Font.Color := FTextColor;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(FUnitText), -1, TextRect,
      DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS or DT_VCENTER);
  end;
end;

end.
