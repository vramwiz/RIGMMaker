unit RigmAul2EqGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのEQ設定を、音声データへ依存しない周波数特性カーブとして描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerEqGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FHighCutHz  : Double;
    FLowCutHz   : Double;
    FMix        : Double;
    FMode       : Integer;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のEQ設定を保持し、設定値だけから周波数特性を再描画する。
    procedure SetEq(Mode: Integer; LowCutHz, HighCutHz, Mix: Double; Active: Boolean);
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
  EQ_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  EQ_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  EQ_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  EQ_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  EQ_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)
  EQ_FREQUENCY_MIN    = 20.0;
  EQ_FREQUENCY_MAX    = 20000.0;

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

function FormatFrequency(Frequency: Double): string;
begin
  if Frequency >= 1000 then
  begin
    if SameValue(Frequency / 1000, Round(Frequency / 1000), 0.001) then
      Result := FormatFloat('0', Frequency / 1000) + 'k'
    else
      Result := FormatFloat('0.#', Frequency / 1000) + 'k';
  end
  else
    Result := FormatFloat('0', Frequency);
end;

constructor TAul2ControllerEqGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := EQ_GRAPH_BACKGROUND;
  FAccentColor := RGB(74, 190, 236);
  FActive := True;
  FMode := 0;
  FLowCutHz := 300;
  FHighCutHz := 3400;
  FMix := 1;
end;

procedure TAul2ControllerEqGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerEqGraph.SetEq(Mode: Integer; LowCutHz, HighCutHz, Mix: Double;
  Active: Boolean);
begin
  FMode := EnsureRange(Mode, 0, 2);
  FLowCutHz := EnsureRange(LowCutHz, 20.0, 5000.0);
  FHighCutHz := EnsureRange(HighCutHz, 500.0, 20000.0);
  if (FMode = 2) and (FHighCutHz <= FLowCutHz) then
    FHighCutHz := FLowCutHz + 1.0;
  FMix := EnsureRange(Mix, 0.0, 1.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerEqGraph.Paint;
const
  GRID_FREQUENCIES: array[0..4] of Double = (20, 100, 1000, 10000, 20000);
var
  AccentColor : TColor;
  CurvePoints : array of TPoint;
  CutLabel    : string;
  CutX        : Integer;
  FillPoints  : array of TPoint;
  FontPPI     : Integer;
  Frequency   : Double;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  GridX       : Integer;
  HeaderText  : string;
  HighMagnitude: Double;
  LabelLeft   : Integer;
  LowMagnitude: Double;
  Magnitude   : Double;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  PointIndex  : Integer;
  TextHeight  : Integer;
  TextWidth   : Integer;
  WetMagnitude: Double;
  Y           : Integer;

  function FrequencyToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, EQ_FREQUENCY_MIN, EQ_FREQUENCY_MAX);
    Result := GraphLeft + Round(
      Ln(Value / EQ_FREQUENCY_MIN) / Ln(EQ_FREQUENCY_MAX / EQ_FREQUENCY_MIN) * PlotWidth);
  end;

  function LowPassMagnitude(Value, Cutoff: Double): Double;
  begin
    Result := 1.0 / Sqrt(1.0 + Power(Value / Max(1.0, Cutoff), 4.0));
  end;

  function HighPassMagnitude(Value, Cutoff: Double): Double;
  begin
    Result := 1.0 / Sqrt(1.0 + Power(Max(1.0, Cutoff) / Max(1.0, Value), 4.0));
  end;

  procedure DrawCutoff(Value: Double; const Prefix: string; LabelRow: Integer);
  var
    LabelTop: Integer;
    Padding : Integer;
  begin
    CutX := FrequencyToX(Value);
    Canvas.Pen.Color := ScaleColor(AccentColor, 75, 100);
    Canvas.Pen.Width := 1;
    Canvas.Pen.Style := psDash;
    Canvas.MoveTo(CutX, GraphTop);
    Canvas.LineTo(CutX, GraphBottom);
    Canvas.Pen.Style := psSolid;
    CutLabel := Prefix + FormatFrequency(Value) + ' Hz';
    TextWidth := Canvas.TextWidth(CutLabel);
    if Prefix = 'L ' then
      LabelLeft := CutX - TextWidth - MulDiv(5, FontPPI, 96)
    else if Prefix = 'H ' then
      LabelLeft := CutX + MulDiv(5, FontPPI, 96)
    else
      LabelLeft := CutX - TextWidth div 2;
    LabelLeft := EnsureRange(LabelLeft, GraphLeft, GraphRight - TextWidth);
    LabelTop := GraphTop + LabelRow * (TextHeight + 1);
    Padding := MulDiv(2, FontPPI, 96);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := EQ_GRAPH_BACKGROUND;
    Canvas.FillRect(Rect(LabelLeft - Padding, LabelTop,
      LabelLeft + TextWidth + Padding, LabelTop + TextHeight));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ScaleColor(AccentColor, 125, 100);
    Canvas.TextOut(LabelLeft, LabelTop, CutLabel);
  end;

begin
  Canvas.Brush.Color := EQ_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := EQ_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(35, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := EQ_GRAPH_BORDER;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  case FMode of
    0: HeaderText := 'Low Cut';
    1: HeaderText := 'High Cut';
  else
    HeaderText := 'Band Pass';
  end;
  Canvas.Font.Color := EQ_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Mix ' + IntToStr(Round(FMix * 100)) + '%';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText), MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := EQ_GRAPH_GRID;
  for GridIndex := Low(GRID_FREQUENCIES) to High(GRID_FREQUENCIES) do
  begin
    GridX := FrequencyToX(GRID_FREQUENCIES[GridIndex]);
    Canvas.MoveTo(GridX, GraphTop);
    Canvas.LineTo(GridX, GraphBottom);
  end;
  for GridIndex := 0 to 2 do
  begin
    Y := GraphTop + PlotHeight * GridIndex div 2;
    Canvas.MoveTo(GraphLeft, Y);
    Canvas.LineTo(GraphRight, Y);
  end;

  Canvas.Pen.Color := EQ_GRAPH_AXIS;
  Canvas.MoveTo(GraphLeft, GraphTop);
  Canvas.LineTo(GraphLeft, GraphBottom);
  Canvas.LineTo(GraphRight, GraphBottom);

  Canvas.Font.Color := EQ_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft - Canvas.TextWidth('100') - 4, GraphTop - TextHeight div 2, '100');
  Canvas.TextOut(GraphLeft - Canvas.TextWidth('0') - 4, GraphBottom - TextHeight div 2, '0');
  for GridIndex := Low(GRID_FREQUENCIES) to High(GRID_FREQUENCIES) do
  begin
    HeaderText := FormatFrequency(GRID_FREQUENCIES[GridIndex]);
    TextWidth := Canvas.TextWidth(HeaderText);
    GridX := FrequencyToX(GRID_FREQUENCIES[GridIndex]);
    LabelLeft := EnsureRange(GridX - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);
  SetLength(CurvePoints, PlotWidth + 1);
  for PointIndex := 0 to PlotWidth do
  begin
    Frequency := EQ_FREQUENCY_MIN *
      Exp(Ln(EQ_FREQUENCY_MAX / EQ_FREQUENCY_MIN) * PointIndex / PlotWidth);
    LowMagnitude := HighPassMagnitude(Frequency, FLowCutHz);
    HighMagnitude := LowPassMagnitude(Frequency, FHighCutHz);
    case FMode of
      0: WetMagnitude := LowMagnitude;
      1: WetMagnitude := HighMagnitude;
    else
      WetMagnitude := LowMagnitude * HighMagnitude;
    end;
    Magnitude := EnsureRange((1.0 - FMix) + FMix * WetMagnitude, 0.0, 1.0);
    CurvePoints[PointIndex] := Point(GraphLeft + PointIndex,
      GraphBottom - Round(Magnitude * PlotHeight));
  end;

  SetLength(FillPoints, Length(CurvePoints) + 2);
  FillPoints[0] := Point(GraphLeft, GraphBottom);
  for PointIndex := 0 to High(CurvePoints) do
    FillPoints[PointIndex + 1] := CurvePoints[PointIndex];
  FillPoints[High(FillPoints)] := Point(GraphRight, GraphBottom);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ScaleColor(AccentColor, 24, 100);
  Canvas.Pen.Style := psClear;
  Canvas.Polygon(FillPoints);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := EQ_GRAPH_TEXT;
  case FMode of
    0: DrawCutoff(FLowCutHz, '', 0);
    1: DrawCutoff(FHighCutHz, '', 0);
  else
    begin
      DrawCutoff(FLowCutHz, 'L ', 0);
      if Abs(FrequencyToX(FHighCutHz) - FrequencyToX(FLowCutHz)) < MulDiv(70, FontPPI, 96) then
        DrawCutoff(FHighCutHz, 'H ', 1)
      else
        DrawCutoff(FHighCutHz, 'H ', 0);
    end;
  end;

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    HeaderText := 'OFF';
    Canvas.TextOut((ClientWidth - Canvas.TextWidth(HeaderText)) div 2,
      MulDiv(7, FontPPI, 96), HeaderText);
  end;
end;

end.
