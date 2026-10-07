unit RigmAul2BitCrusherGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのBitCrusher設定を、量子化階段とサンプル保持情報として描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerBitCrusherGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FBitDepth   : Integer;
    FMix        : Double;
    FSampleHold : Integer;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のBitCrusher設定を保持し、DSPと同じ静的な量子化伝達を再描画する。
    procedure SetBitCrusher(BitDepth, SampleHold: Double; Mix: Double;
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
  CRUSH_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  CRUSH_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  CRUSH_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  CRUSH_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  CRUSH_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)

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

constructor TAul2ControllerBitCrusherGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := CRUSH_GRAPH_BACKGROUND;
  FAccentColor := RGB(158, 66, 72);
  FActive := True;
  FBitDepth := 8;
  FSampleHold := 4;
  FMix := 1;
end;

procedure TAul2ControllerBitCrusherGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerBitCrusherGraph.SetBitCrusher(BitDepth,
  SampleHold: Double; Mix: Double; Active: Boolean);
begin
  FBitDepth := EnsureRange(Round(BitDepth), 2, 16);
  FSampleHold := EnsureRange(Round(SampleHold), 1, 64);
  FMix := EnsureRange(Mix, 0.0, 1.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerBitCrusherGraph.Paint;
var
  AccentColor : TColor;
  CurvePoints : array of TPoint;
  DesiredStepPixels: Integer;
  FontPPI     : Integer;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  HeaderText  : string;
  InputValue  : Double;
  LabelLeft   : Integer;
  Level       : Integer;
  LevelCount  : Integer;
  LevelEnd    : Integer;
  LevelStart  : Integer;
  MaxValue    : Integer;
  OutputValue : Double;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  PointCount  : Integer;
  PointIndex  : Integer;
  Quantized   : Double;
  ReferencePoints: array[0..1] of TPoint;
  SegmentLeft : Double;
  SegmentRight: Double;
  TextHeight  : Integer;
  TextWidth   : Integer;
  ViewRange   : Double;
  VisibleHalfSteps: Integer;
  X           : Integer;
  Y           : Integer;

  function ValueToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, -ViewRange, ViewRange);
    Result := GraphLeft + Round((Value + ViewRange) /
      (ViewRange * 2.0) * PlotWidth);
  end;

  function ValueToY(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, -ViewRange, ViewRange);
    Result := GraphBottom - Round((Value + ViewRange) /
      (ViewRange * 2.0) * PlotHeight);
  end;

  function FormatAxisValue(Value: Double): string;
  begin
    if ViewRange < 1.0 then
      Result := IntToStr(Round(Value * MaxValue))
    else if SameValue(Value, 0.0, 0.0000001) then
      Result := '0'
    else if Abs(Value) >= 0.1 then
      Result := FormatFloat('0.###', Value)
    else if Abs(Value) >= 0.01 then
      Result := FormatFloat('0.####', Value)
    else
      Result := FormatFloat('0.#####', Value);
  end;

begin
  Canvas.Brush.Color := CRUSH_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := CRUSH_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(35, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);
  MaxValue := (1 shl (FBitDepth - 1)) - 1;
  LevelCount := MaxValue * 2 + 1;
  // 主線の太さに対して段差が潰れないよう、1段あたり約8pxを確保する。
  DesiredStepPixels := Max(6, MulDiv(8, FontPPI, 96));
  VisibleHalfSteps := Max(4, PlotWidth div (DesiredStepPixels * 2));
  if Odd(VisibleHalfSteps) then
    Dec(VisibleHalfSteps);
  if MaxValue <= VisibleHalfSteps + 2 then
    ViewRange := 1.0
  else
    ViewRange := VisibleHalfSteps / MaxValue;

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := CRUSH_GRAPH_BORDER;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  HeaderText := IntToStr(FBitDepth) + ' bit  Hold x' + IntToStr(FSampleHold);
  Canvas.Font.Color := CRUSH_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Mix ' + IntToStr(Round(FMix * 100)) + '%';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Color := CRUSH_GRAPH_GRID;
  for GridIndex := 0 to 4 do
  begin
    X := GraphLeft + PlotWidth * GridIndex div 4;
    Canvas.MoveTo(X, GraphTop);
    Canvas.LineTo(X, GraphBottom);
    Y := GraphTop + PlotHeight * GridIndex div 4;
    Canvas.MoveTo(GraphLeft, Y);
    Canvas.LineTo(GraphRight, Y);
  end;

  Canvas.Pen.Color := CRUSH_GRAPH_AXIS;
  X := ValueToX(0);
  Canvas.MoveTo(X, GraphTop);
  Canvas.LineTo(X, GraphBottom);
  Y := ValueToY(0);
  Canvas.MoveTo(GraphLeft, Y);
  Canvas.LineTo(GraphRight, Y);

  Canvas.Font.Color := CRUSH_GRAPH_TEXT;
  HeaderText := FormatAxisValue(ViewRange);
  Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
    GraphTop - TextHeight div 2, HeaderText);
  HeaderText := FormatAxisValue(-ViewRange);
  Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
    GraphBottom - TextHeight div 2, HeaderText);
  for GridIndex := 0 to 4 do
  begin
    InputValue := -ViewRange + GridIndex * ViewRange * 0.5;
    HeaderText := FormatAxisValue(InputValue);
    TextWidth := Canvas.TextWidth(HeaderText);
    X := ValueToX(InputValue);
    LabelLeft := EnsureRange(X - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  ReferencePoints[0] := Point(ValueToX(-ViewRange), ValueToY(-ViewRange));
  ReferencePoints[1] := Point(ValueToX(ViewRange), ValueToY(ViewRange));
  Canvas.Pen.Color := CRUSH_GRAPH_AXIS;
  Canvas.Pen.Style := psDash;
  Canvas.Polyline(ReferencePoints);

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));

  // 全域表示では全レベル、高bitの拡大表示では中央約16段だけを正確に描く。
  LevelStart := Max(-MaxValue, Ceil(-ViewRange * MaxValue - 0.5));
  LevelEnd := Min(MaxValue, Floor(ViewRange * MaxValue + 0.5));
  PointCount := (LevelEnd - LevelStart + 1) * 2;
  SetLength(CurvePoints, PointCount);
  PointIndex := 0;
  for Level := LevelStart to LevelEnd do
  begin
    SegmentLeft := Max(-ViewRange, (Level - 0.5) / MaxValue);
    SegmentRight := Min(ViewRange, (Level + 0.5) / MaxValue);
    Quantized := Level / MaxValue;
    OutputValue := (SegmentLeft * (1.0 - FMix)) + (Quantized * FMix);
    CurvePoints[PointIndex] := Point(ValueToX(SegmentLeft), ValueToY(OutputValue));
    Inc(PointIndex);
    OutputValue := (SegmentRight * (1.0 - FMix)) + (Quantized * FMix);
    CurvePoints[PointIndex] := Point(ValueToX(SegmentRight), ValueToY(OutputValue));
    Inc(PointIndex);
  end;
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := CRUSH_GRAPH_TEXT;
  if ViewRange < 1.0 then
    HeaderText := FormatFloat('#,##0', LevelEnd - LevelStart + 1) + ' of ' +
      FormatFloat('#,##0', LevelCount) + ' levels shown'
  else
    HeaderText := FormatFloat('#,##0', LevelCount) + ' levels';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    GraphBottom - TextHeight - MulDiv(3, FontPPI, 96), HeaderText);

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    HeaderText := 'OFF';
    TextWidth := Canvas.TextWidth(HeaderText);
    LabelLeft := (ClientWidth - TextWidth) div 2;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := CRUSH_GRAPH_BACKGROUND;
    Canvas.FillRect(Rect(LabelLeft - 2, GraphTop + MulDiv(3, FontPPI, 96),
      LabelLeft + TextWidth + 2, GraphTop + MulDiv(3, FontPPI, 96) + TextHeight));
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(LabelLeft, GraphTop + MulDiv(3, FontPPI, 96), HeaderText);
  end;
end;

end.
