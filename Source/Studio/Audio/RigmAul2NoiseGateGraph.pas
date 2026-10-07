unit RigmAul2NoiseGateGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのNoiseGate設定を、音声データへ依存しない入出力特性として描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerNoiseGateGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FAttackMs   : Double;
    FFloorDb    : Double;
    FReleaseMs  : Double;
    FThresholdDb: Double;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のNoiseGate設定を保持し、定常状態の入出力特性を再描画する。
    procedure SetNoiseGate(ThresholdDb, AttackMs, ReleaseMs, FloorDb: Double;
      Active: Boolean);
    property AccentColor: TColor read FAccentColor write SetAccentColor;
  published
    property Font;
    property ParentFont;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.SysUtils,
  System.Types;

const
  GATE_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  GATE_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  GATE_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  GATE_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  GATE_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)
  GATE_INPUT_MIN_DB     = -80.0;
  GATE_INPUT_MAX_DB     = 0.0;
  GATE_OUTPUT_MIN_DB    = -160.0;
  GATE_OUTPUT_MAX_DB    = 0.0;

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

constructor TAul2ControllerNoiseGateGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := GATE_GRAPH_BACKGROUND;
  FAccentColor := RGB(242, 242, 242);
  FActive := True;
  FThresholdDb := -45;
  FAttackMs := 5;
  FReleaseMs := 120;
  FFloorDb := -60;
end;

procedure TAul2ControllerNoiseGateGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerNoiseGateGraph.SetNoiseGate(ThresholdDb, AttackMs,
  ReleaseMs, FloorDb: Double; Active: Boolean);
begin
  FThresholdDb := EnsureRange(ThresholdDb, -80.0, 0.0);
  FAttackMs := EnsureRange(AttackMs, 1.0, 200.0);
  FReleaseMs := EnsureRange(ReleaseMs, 10.0, 1000.0);
  FFloorDb := EnsureRange(FloorDb, -80.0, -6.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerNoiseGateGraph.Paint;
const
  INPUT_GRID_DB: array[0..4] of Integer = (-80, -60, -40, -20, 0);
  OUTPUT_GRID_DB: array[0..4] of Integer = (-160, -120, -80, -40, 0);
var
  AccentColor : TColor;
  CurvePoints : array[0..3] of TPoint;
  FillPoints  : array[0..3] of TPoint;
  FontPPI     : Integer;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  HeaderText  : string;
  LabelLeft   : Integer;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  ReferencePoints: array[0..1] of TPoint;
  TextHeight  : Integer;
  TextWidth   : Integer;
  ThresholdX : Integer;
  X           : Integer;
  Y           : Integer;

  function InputToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, GATE_INPUT_MIN_DB, GATE_INPUT_MAX_DB);
    Result := GraphLeft + Round((Value - GATE_INPUT_MIN_DB) /
      (GATE_INPUT_MAX_DB - GATE_INPUT_MIN_DB) * PlotWidth);
  end;

  function OutputToY(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, GATE_OUTPUT_MIN_DB, GATE_OUTPUT_MAX_DB);
    Result := GraphBottom - Round((Value - GATE_OUTPUT_MIN_DB) /
      (GATE_OUTPUT_MAX_DB - GATE_OUTPUT_MIN_DB) * PlotHeight);
  end;

begin
  Canvas.Brush.Color := GATE_GRAPH_BACKGROUND;
  Canvas.FillRect(ClientRect);
  if (ClientWidth < 80) or (ClientHeight < 70) then
    Exit;

  FontPPI := Max(96, Font.PixelsPerInch);
  Canvas.Font.Assign(Font);
  if ClientWidth >= MulDiv(240, FontPPI, 96) then
    Canvas.Font.Size := 9
  else
    Canvas.Font.Size := 8;
  Canvas.Font.Quality := fqClearTypeNatural;
  Canvas.Font.Color := GATE_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(42, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := GATE_GRAPH_BORDER;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  HeaderText := 'Threshold ' + FormatFloat('0.#', FThresholdDb) + ' dB';
  Canvas.Font.Color := GATE_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Floor ' + FormatFloat('0', FFloorDb) + ' dB';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Color := GATE_GRAPH_GRID;
  for GridIndex := Low(INPUT_GRID_DB) to High(INPUT_GRID_DB) do
  begin
    X := InputToX(INPUT_GRID_DB[GridIndex]);
    Canvas.MoveTo(X, GraphTop);
    Canvas.LineTo(X, GraphBottom);
  end;
  for GridIndex := Low(OUTPUT_GRID_DB) to High(OUTPUT_GRID_DB) do
  begin
    Y := OutputToY(OUTPUT_GRID_DB[GridIndex]);
    Canvas.MoveTo(GraphLeft, Y);
    Canvas.LineTo(GraphRight, Y);
  end;

  Canvas.Pen.Color := GATE_GRAPH_AXIS;
  Canvas.MoveTo(GraphLeft, GraphTop);
  Canvas.LineTo(GraphLeft, GraphBottom);
  Canvas.LineTo(GraphRight, GraphBottom);

  Canvas.Font.Color := GATE_GRAPH_TEXT;
  for GridIndex := Low(OUTPUT_GRID_DB) to High(OUTPUT_GRID_DB) do
  begin
    HeaderText := IntToStr(OUTPUT_GRID_DB[GridIndex]);
    Y := OutputToY(OUTPUT_GRID_DB[GridIndex]);
    Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
      Y - TextHeight div 2, HeaderText);
  end;
  for GridIndex := Low(INPUT_GRID_DB) to High(INPUT_GRID_DB) do
  begin
    HeaderText := IntToStr(INPUT_GRID_DB[GridIndex]);
    TextWidth := Canvas.TextWidth(HeaderText);
    X := InputToX(INPUT_GRID_DB[GridIndex]);
    LabelLeft := EnsureRange(X - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  ReferencePoints[0] := Point(InputToX(GATE_INPUT_MIN_DB), OutputToY(GATE_INPUT_MIN_DB));
  ReferencePoints[1] := Point(InputToX(GATE_INPUT_MAX_DB), OutputToY(GATE_INPUT_MAX_DB));
  Canvas.Pen.Color := GATE_GRAPH_AXIS;
  Canvas.Pen.Style := psDash;
  Canvas.Polyline(ReferencePoints);

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);

  // 無加工線とゲート閉鎖時の線に挟まれた領域が、抑制される音量を表す。
  FillPoints[0] := Point(InputToX(GATE_INPUT_MIN_DB), OutputToY(GATE_INPUT_MIN_DB));
  FillPoints[1] := Point(InputToX(FThresholdDb), OutputToY(FThresholdDb));
  FillPoints[2] := Point(InputToX(FThresholdDb), OutputToY(FThresholdDb + FFloorDb));
  FillPoints[3] := Point(InputToX(GATE_INPUT_MIN_DB),
    OutputToY(GATE_INPUT_MIN_DB + FFloorDb));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ScaleColor(AccentColor, 20, 100);
  Canvas.Pen.Style := psClear;
  Canvas.Polygon(FillPoints);

  ThresholdX := InputToX(FThresholdDb);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psDash;
  Canvas.Pen.Color := ScaleColor(AccentColor, 75, 100);
  Canvas.Pen.Width := 1;
  Canvas.MoveTo(ThresholdX, GraphTop);
  Canvas.LineTo(ThresholdX, GraphBottom);

  CurvePoints[0] := Point(InputToX(GATE_INPUT_MIN_DB),
    OutputToY(GATE_INPUT_MIN_DB + FFloorDb));
  CurvePoints[1] := Point(ThresholdX, OutputToY(FThresholdDb + FFloorDb));
  CurvePoints[2] := Point(ThresholdX, OutputToY(FThresholdDb));
  CurvePoints[3] := Point(InputToX(GATE_INPUT_MAX_DB), OutputToY(GATE_INPUT_MAX_DB));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := ScaleColor(AccentColor, 125, 100);
  HeaderText := 'T ' + FormatFloat('0.#', FThresholdDb);
  TextWidth := Canvas.TextWidth(HeaderText);
  LabelLeft := EnsureRange(ThresholdX - TextWidth div 2, GraphLeft,
    GraphRight - TextWidth);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := GATE_GRAPH_BACKGROUND;
  Canvas.FillRect(Rect(LabelLeft - 2, GraphTop, LabelLeft + TextWidth + 2,
    GraphTop + TextHeight));
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(LabelLeft, GraphTop, HeaderText);

  Canvas.Font.Color := GATE_GRAPH_TEXT;
  if ClientWidth >= MulDiv(250, FontPPI, 96) then
    HeaderText := 'Attack ' + FormatFloat('0', FAttackMs) + ' ms  Release ' +
      FormatFloat('0', FReleaseMs) + ' ms'
  else
    HeaderText := 'A ' + FormatFloat('0', FAttackMs) + ' / R ' +
      FormatFloat('0', FReleaseMs) + ' ms';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    GraphBottom - TextHeight - MulDiv(3, FontPPI, 96), HeaderText);

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    HeaderText := 'OFF';
    TextWidth := Canvas.TextWidth(HeaderText);
    LabelLeft := (ClientWidth - TextWidth) div 2;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := GATE_GRAPH_BACKGROUND;
    Canvas.FillRect(Rect(LabelLeft - 2, GraphTop + MulDiv(3, FontPPI, 96),
      LabelLeft + TextWidth + 2, GraphTop + MulDiv(3, FontPPI, 96) + TextHeight));
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(LabelLeft, GraphTop + MulDiv(3, FontPPI, 96), HeaderText);
  end;
end;

end.
