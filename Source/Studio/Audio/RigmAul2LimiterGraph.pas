unit RigmAul2LimiterGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのLimiter設定を、音声データへ依存しない入出力特性として描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerLimiterGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FCeilingDb  : Double;
    FMix        : Double;
    FReleaseMs  : Double;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のLimiter設定を保持し、定常状態の入出力特性を再描画する。
    procedure SetLimiter(CeilingDb, ReleaseMs, Mix: Double; Active: Boolean);
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
  LIMITER_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  LIMITER_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  LIMITER_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  LIMITER_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  LIMITER_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)
  LIMITER_MIN_DB           = -60.0;
  LIMITER_MAX_DB           = 12.0;

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

constructor TAul2ControllerLimiterGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := LIMITER_GRAPH_BACKGROUND;
  FAccentColor := RGB(242, 242, 242);
  FActive := True;
  FCeilingDb := -1;
  FReleaseMs := 50;
  FMix := 1;
end;

procedure TAul2ControllerLimiterGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerLimiterGraph.SetLimiter(CeilingDb, ReleaseMs,
  Mix: Double; Active: Boolean);
begin
  FCeilingDb := EnsureRange(CeilingDb, -24.0, 0.0);
  FReleaseMs := EnsureRange(ReleaseMs, 1.0, 1000.0);
  FMix := EnsureRange(Mix, 0.0, 1.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerLimiterGraph.Paint;
const
  GRID_DB: array[0..4] of Integer = (-60, -40, -20, 0, 12);
var
  AccentColor : TColor;
  CeilingGain : Double;
  CeilingIndex: Integer;
  CeilingX    : Integer;
  CurvePoints : array of TPoint;
  FillPoints  : array of TPoint;
  FontPPI     : Integer;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  HeaderText  : string;
  InputDb     : Double;
  InputGain   : Double;
  LabelLeft   : Integer;
  OutputDb    : Double;
  OutputGain  : Double;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  PointIndex  : Integer;
  ReferencePoints: array[0..1] of TPoint;
  TextHeight  : Integer;
  TextWidth   : Integer;
  WetGain     : Double;
  X           : Integer;
  Y           : Integer;

  function DbToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, LIMITER_MIN_DB, LIMITER_MAX_DB);
    Result := GraphLeft + Round((Value - LIMITER_MIN_DB) /
      (LIMITER_MAX_DB - LIMITER_MIN_DB) * PlotWidth);
  end;

  function DbToY(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, LIMITER_MIN_DB, LIMITER_MAX_DB);
    Result := GraphBottom - Round((Value - LIMITER_MIN_DB) /
      (LIMITER_MAX_DB - LIMITER_MIN_DB) * PlotHeight);
  end;

  function FormatDb(Value: Integer): string;
  begin
    if Value > 0 then
      Result := '+' + IntToStr(Value)
    else
      Result := IntToStr(Value);
  end;

begin
  Canvas.Brush.Color := LIMITER_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := LIMITER_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(38, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);
  CeilingGain := Power(10.0, FCeilingDb / 20.0);

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := LIMITER_GRAPH_BORDER;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  HeaderText := 'Ceiling ' + FormatFloat('0.#', FCeilingDb) + ' dB';
  Canvas.Font.Color := LIMITER_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Mix ' + IntToStr(Round(FMix * 100)) + '%';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Color := LIMITER_GRAPH_GRID;
  for GridIndex := Low(GRID_DB) to High(GRID_DB) do
  begin
    X := DbToX(GRID_DB[GridIndex]);
    Canvas.MoveTo(X, GraphTop);
    Canvas.LineTo(X, GraphBottom);
    Y := DbToY(GRID_DB[GridIndex]);
    Canvas.MoveTo(GraphLeft, Y);
    Canvas.LineTo(GraphRight, Y);
  end;

  Canvas.Pen.Color := LIMITER_GRAPH_AXIS;
  Canvas.MoveTo(GraphLeft, GraphTop);
  Canvas.LineTo(GraphLeft, GraphBottom);
  Canvas.LineTo(GraphRight, GraphBottom);

  Canvas.Font.Color := LIMITER_GRAPH_TEXT;
  for GridIndex := Low(GRID_DB) to High(GRID_DB) do
  begin
    HeaderText := FormatDb(GRID_DB[GridIndex]);
    Y := DbToY(GRID_DB[GridIndex]);
    Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
      Y - TextHeight div 2, HeaderText);
    TextWidth := Canvas.TextWidth(HeaderText);
    X := DbToX(GRID_DB[GridIndex]);
    LabelLeft := EnsureRange(X - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  ReferencePoints[0] := Point(DbToX(LIMITER_MIN_DB), DbToY(LIMITER_MIN_DB));
  ReferencePoints[1] := Point(DbToX(LIMITER_MAX_DB), DbToY(LIMITER_MAX_DB));
  Canvas.Pen.Color := LIMITER_GRAPH_AXIS;
  Canvas.Pen.Style := psDash;
  Canvas.Polyline(ReferencePoints);

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);

  SetLength(CurvePoints, PlotWidth + 1);
  for PointIndex := 0 to PlotWidth do
  begin
    InputDb := LIMITER_MIN_DB +
      (LIMITER_MAX_DB - LIMITER_MIN_DB) * PointIndex / PlotWidth;
    InputGain := Power(10.0, InputDb / 20.0);
    WetGain := Min(InputGain, CeilingGain);
    OutputGain := (InputGain * (1.0 - FMix)) + (WetGain * FMix);
    OutputDb := LinearToDb(OutputGain);
    CurvePoints[PointIndex] := Point(GraphLeft + PointIndex, DbToY(OutputDb));
  end;

  CeilingIndex := EnsureRange(DbToX(FCeilingDb) - GraphLeft, 0, PlotWidth);
  SetLength(FillPoints, PlotWidth - CeilingIndex + 3);
  for PointIndex := CeilingIndex to PlotWidth do
    FillPoints[PointIndex - CeilingIndex] := CurvePoints[PointIndex];
  FillPoints[High(FillPoints) - 1] := Point(GraphRight, DbToY(LIMITER_MAX_DB));
  FillPoints[High(FillPoints)] := Point(DbToX(FCeilingDb), DbToY(FCeilingDb));
  Canvas.Brush.Style := bsSolid;
  // Ceiling超過時に削られる領域を、小型表示でも判別できる明るさにする。
  Canvas.Brush.Color := ScaleColor(AccentColor, 38, 100);
  Canvas.Pen.Style := psClear;
  Canvas.Polygon(FillPoints);

  CeilingX := DbToX(FCeilingDb);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psDash;
  Canvas.Pen.Color := ScaleColor(AccentColor, 75, 100);
  Canvas.Pen.Width := 1;
  Canvas.MoveTo(CeilingX, GraphTop);
  Canvas.LineTo(CeilingX, GraphBottom);

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := ScaleColor(AccentColor, 125, 100);
  HeaderText := 'C ' + FormatFloat('0.#', FCeilingDb);
  TextWidth := Canvas.TextWidth(HeaderText);
  LabelLeft := EnsureRange(CeilingX - TextWidth div 2, GraphLeft,
    GraphRight - TextWidth);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := LIMITER_GRAPH_BACKGROUND;
  Canvas.FillRect(Rect(LabelLeft - 2, GraphTop, LabelLeft + TextWidth + 2,
    GraphTop + TextHeight));
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(LabelLeft, GraphTop, HeaderText);

  Canvas.Font.Color := LIMITER_GRAPH_TEXT;
  HeaderText := 'Release ' + FormatFloat('0', FReleaseMs) + ' ms';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    GraphBottom - TextHeight - MulDiv(3, FontPPI, 96), HeaderText);

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    HeaderText := 'OFF';
    TextWidth := Canvas.TextWidth(HeaderText);
    LabelLeft := (ClientWidth - TextWidth) div 2;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := LIMITER_GRAPH_BACKGROUND;
    Canvas.FillRect(Rect(LabelLeft - 2, GraphTop + MulDiv(3, FontPPI, 96),
      LabelLeft + TextWidth + 2, GraphTop + MulDiv(3, FontPPI, 96) + TextHeight));
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(LabelLeft, GraphTop + MulDiv(3, FontPPI, 96), HeaderText);
  end;
end;

end.
