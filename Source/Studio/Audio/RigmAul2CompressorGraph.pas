unit RigmAul2CompressorGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのCompressor設定を、音声データへ依存しない入出力特性として描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerCompressorGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FAttackMs   : Double;
    FMakeupDb   : Double;
    FMix        : Double;
    FRatio      : Double;
    FReleaseMs  : Double;
    FThresholdDb: Double;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のCompressor設定を保持し、定常状態の入出力特性を再描画する。
    procedure SetCompressor(ThresholdDb, Ratio, AttackMs, ReleaseMs,
      MakeupDb, Mix: Double; Active: Boolean);
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
  COMP_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  COMP_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  COMP_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  COMP_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  COMP_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)
  COMP_INPUT_MIN_DB     = -60.0;
  COMP_INPUT_MAX_DB     = 0.0;
  COMP_OUTPUT_MIN_DB    = -60.0;
  COMP_OUTPUT_MAX_DB    = 24.0;

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

function LinearToDb(Value: Double): Double;
begin
  if Value <= 0.000001 then
    Result := -120.0
  else
    Result := 20.0 * Log10(Value);
end;

constructor TAul2ControllerCompressorGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := COMP_GRAPH_BACKGROUND;
  FAccentColor := RGB(95, 161, 216);
  FActive := True;
  FThresholdDb := -18;
  FRatio := 4;
  FAttackMs := 10;
  FReleaseMs := 120;
  FMakeupDb := 0;
  FMix := 1;
end;

procedure TAul2ControllerCompressorGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerCompressorGraph.SetCompressor(ThresholdDb, Ratio,
  AttackMs, ReleaseMs, MakeupDb, Mix: Double; Active: Boolean);
begin
  FThresholdDb := EnsureRange(ThresholdDb, -60.0, 0.0);
  FRatio := EnsureRange(Ratio, 1.0, 20.0);
  FAttackMs := EnsureRange(AttackMs, 0.1, 200.0);
  FReleaseMs := EnsureRange(ReleaseMs, 5.0, 1000.0);
  FMakeupDb := EnsureRange(MakeupDb, -24.0, 24.0);
  FMix := EnsureRange(Mix, 0.0, 1.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerCompressorGraph.Paint;
const
  INPUT_GRID_DB: array[0..3] of Integer = (-60, -40, -20, 0);
  OUTPUT_GRID_DB: array[0..3] of Integer = (-60, -40, -20, 0);
var
  AccentColor : TColor;
  CurvePoints : array of TPoint;
  FontPPI     : Integer;
  GainDb      : Double;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  GridValue   : Integer;
  HeaderText  : string;
  InputDb     : Double;
  LabelLeft   : Integer;
  OutputDb    : Double;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  PointIndex  : Integer;
  ReferencePoints: array[0..1] of TPoint;
  TextHeight  : Integer;
  TextWidth   : Integer;
  ThresholdX : Integer;
  WetGain     : Double;
  X           : Integer;
  Y           : Integer;

  function InputToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, COMP_INPUT_MIN_DB, COMP_INPUT_MAX_DB);
    Result := GraphLeft + Round((Value - COMP_INPUT_MIN_DB) /
      (COMP_INPUT_MAX_DB - COMP_INPUT_MIN_DB) * PlotWidth);
  end;

  function OutputToY(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, COMP_OUTPUT_MIN_DB, COMP_OUTPUT_MAX_DB);
    Result := GraphBottom - Round((Value - COMP_OUTPUT_MIN_DB) /
      (COMP_OUTPUT_MAX_DB - COMP_OUTPUT_MIN_DB) * PlotHeight);
  end;

begin
  Canvas.Brush.Color := COMP_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := COMP_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(38, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := COMP_GRAPH_BORDER;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  if ClientWidth >= MulDiv(250, FontPPI, 96) then
    HeaderText := 'Threshold ' + FormatFloat('0.#', FThresholdDb) + ' dB'
  else
    HeaderText := 'T ' + FormatFloat('0.#', FThresholdDb) + ' dB';
  Canvas.Font.Color := COMP_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  if ClientWidth >= MulDiv(250, FontPPI, 96) then
    HeaderText := FormatFloat('0.#', FRatio) + ':1  Mix ' +
      IntToStr(Round(FMix * 100)) + '%'
  else
    HeaderText := FormatFloat('0.#', FRatio) + ':1  ' +
      IntToStr(Round(FMix * 100)) + '%';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := COMP_GRAPH_GRID;
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

  Canvas.Pen.Color := COMP_GRAPH_AXIS;
  Canvas.MoveTo(GraphLeft, GraphTop);
  Canvas.LineTo(GraphLeft, GraphBottom);
  Canvas.LineTo(GraphRight, GraphBottom);

  Canvas.Font.Color := COMP_GRAPH_TEXT;
  for GridIndex := Low(OUTPUT_GRID_DB) to High(OUTPUT_GRID_DB) do
  begin
    GridValue := OUTPUT_GRID_DB[GridIndex];
    HeaderText := IntToStr(GridValue);
    Y := OutputToY(GridValue);
    Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
      Y - TextHeight div 2, HeaderText);
  end;
  HeaderText := '+24';
  Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
    GraphTop - TextHeight div 2, HeaderText);
  for GridIndex := Low(INPUT_GRID_DB) to High(INPUT_GRID_DB) do
  begin
    HeaderText := IntToStr(INPUT_GRID_DB[GridIndex]);
    TextWidth := Canvas.TextWidth(HeaderText);
    X := InputToX(INPUT_GRID_DB[GridIndex]);
    LabelLeft := EnsureRange(X - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  // 無加工時の入出力を基準線として残し、圧縮とMakeupの変化を比較しやすくする。
  ReferencePoints[0] := Point(InputToX(COMP_INPUT_MIN_DB), OutputToY(COMP_INPUT_MIN_DB));
  ReferencePoints[1] := Point(InputToX(COMP_INPUT_MAX_DB), OutputToY(COMP_INPUT_MAX_DB));
  Canvas.Pen.Color := COMP_GRAPH_AXIS;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psDash;
  Canvas.Polyline(ReferencePoints);

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);

  ThresholdX := InputToX(FThresholdDb);
  Canvas.Pen.Color := ScaleColor(AccentColor, 75, 100);
  Canvas.MoveTo(ThresholdX, GraphTop);
  Canvas.LineTo(ThresholdX, GraphBottom);
  Canvas.Pen.Style := psSolid;

  SetLength(CurvePoints, PlotWidth + 1);
  for PointIndex := 0 to PlotWidth do
  begin
    InputDb := COMP_INPUT_MIN_DB +
      (COMP_INPUT_MAX_DB - COMP_INPUT_MIN_DB) * PointIndex / PlotWidth;
    if InputDb > FThresholdDb then
      GainDb := FThresholdDb + ((InputDb - FThresholdDb) / FRatio) - InputDb
    else
      GainDb := 0;
    WetGain := Power(10.0, (GainDb + FMakeupDb) / 20.0);
    OutputDb := InputDb + LinearToDb((1.0 - FMix) + FMix * WetGain);
    CurvePoints[PointIndex] := Point(GraphLeft + PointIndex, OutputToY(OutputDb));
  end;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := ScaleColor(AccentColor, 125, 100);
  HeaderText := 'T ' + FormatFloat('0.#', FThresholdDb);
  TextWidth := Canvas.TextWidth(HeaderText);
  LabelLeft := EnsureRange(ThresholdX - TextWidth div 2, GraphLeft,
    GraphRight - TextWidth);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := COMP_GRAPH_BACKGROUND;
  Canvas.FillRect(Rect(LabelLeft - 2, GraphTop, LabelLeft + TextWidth + 2,
    GraphTop + TextHeight));
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(LabelLeft, GraphTop, HeaderText);

  Canvas.Font.Color := COMP_GRAPH_TEXT;
  if ClientWidth >= MulDiv(250, FontPPI, 96) then
    HeaderText := 'Makeup ' + FormatFloat('+0.0;-0.0;0.0', FMakeupDb) +
      ' dB  A ' + FormatFloat('0.#', FAttackMs) + ' / R ' +
      FormatFloat('0', FReleaseMs) + ' ms'
  else
    HeaderText := 'M ' + FormatFloat('+0.0;-0.0;0.0', FMakeupDb) +
      '  A/R ' + FormatFloat('0.#', FAttackMs) + '/' +
      FormatFloat('0', FReleaseMs) + ' ms';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    GraphBottom - TextHeight - MulDiv(3, FontPPI, 96), HeaderText);

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    HeaderText := 'OFF';
    Canvas.TextOut((ClientWidth - Canvas.TextWidth(HeaderText)) div 2,
      MulDiv(7, FontPPI, 96), HeaderText);
  end;
end;

end.
