unit RigmAul2DistortionGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのDistortion設定を、音声データへ依存しない振幅伝達カーブとして描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerDistortionGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FDriveDb    : Double;
    FLevelDb    : Double;
    FMix        : Double;
    FMode       : Integer;
    FTone       : Double;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のDistortion設定を保持し、DSPと同じ静的な振幅伝達を再描画する。
    procedure SetDistortion(Mode: Integer; DriveDb, Tone, LevelDb, Mix: Double;
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
  DIST_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  DIST_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  DIST_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  DIST_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  DIST_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)

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

constructor TAul2ControllerDistortionGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := DIST_GRAPH_BACKGROUND;
  FAccentColor := RGB(242, 115, 33);
  FActive := True;
  FMode := 0;
  FDriveDb := 6;
  FTone := 1;
  FLevelDb := -6;
  FMix := 1;
end;

procedure TAul2ControllerDistortionGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerDistortionGraph.SetDistortion(Mode: Integer; DriveDb,
  Tone, LevelDb, Mix: Double; Active: Boolean);
begin
  FMode := EnsureRange(Mode, 0, 1);
  FDriveDb := EnsureRange(DriveDb, 0.0, 36.0);
  FTone := EnsureRange(Tone, 0.0, 1.0);
  FLevelDb := EnsureRange(LevelDb, -24.0, 12.0);
  FMix := EnsureRange(Mix, 0.0, 1.0);
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerDistortionGraph.Paint;
var
  AccentColor : TColor;
  ClipInput   : Double;
  CurvePoints : array of TPoint;
  DriveGain   : Double;
  FontPPI     : Integer;
  GraphBottom : Integer;
  GraphLeft   : Integer;
  GraphRight  : Integer;
  GraphTop    : Integer;
  GridIndex   : Integer;
  HeaderText  : string;
  InputValue  : Double;
  LabelLeft   : Integer;
  LevelGain   : Double;
  OutputRange : Double;
  OutputValue : Double;
  PlotHeight  : Integer;
  PlotWidth   : Integer;
  PointIndex  : Integer;
  ReferencePoints: array[0..1] of TPoint;
  TextHeight  : Integer;
  TextWidth   : Integer;
  X           : Integer;
  Y           : Integer;

  function InputToX(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, -1.0, 1.0);
    Result := GraphLeft + Round((Value + 1.0) * 0.5 * PlotWidth);
  end;

  function OutputToY(Value: Double): Integer;
  begin
    Value := EnsureRange(Value, -OutputRange, OutputRange);
    Result := GraphBottom - Round((Value + OutputRange) /
      (OutputRange * 2.0) * PlotHeight);
  end;

  function Distort(Value: Double): Double;
  var
    ShapedValue: Double;
  begin
    if FMode = 1 then
      ShapedValue := EnsureRange(Value * DriveGain, -1.0, 1.0)
    else
      ShapedValue := Tanh(Value * DriveGain);
    ShapedValue := (ShapedValue * FTone) + (Value * (1.0 - FTone));
    ShapedValue := ShapedValue * LevelGain;
    Result := (Value * (1.0 - FMix)) + (ShapedValue * FMix);
  end;

  procedure DrawClipGuide(Value: Double);
  begin
    if (Value <= -1.0) or (Value >= 1.0) then
      Exit;
    X := InputToX(Value);
    Canvas.MoveTo(X, GraphTop);
    Canvas.LineTo(X, GraphBottom);
  end;

begin
  Canvas.Brush.Color := DIST_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := DIST_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  GraphLeft := MulDiv(35, FontPPI, 96);
  GraphRight := ClientWidth - MulDiv(10, FontPPI, 96);
  GraphTop := MulDiv(32, FontPPI, 96);
  GraphBottom := ClientHeight - MulDiv(24, FontPPI, 96);
  PlotWidth := Max(1, GraphRight - GraphLeft);
  PlotHeight := Max(1, GraphBottom - GraphTop);
  DriveGain := Power(10.0, FDriveDb / 20.0);
  LevelGain := Power(10.0, FLevelDb / 20.0);

  // Levelで大きく増幅した時だけ軸を広げ、通常設定のカーブは大きく保つ。
  OutputRange := Max(1.0, Max(Abs(Distort(-1.0)), Abs(Distort(1.0))) * 1.08);
  if OutputRange > 2.0 then
    OutputRange := 4.0
  else if OutputRange > 1.0 then
    OutputRange := 2.0
  else
    OutputRange := 1.0;

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := DIST_GRAPH_BORDER;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  if FMode = 1 then
    HeaderText := 'Hard Clip'
  else
    HeaderText := 'Soft Clip';
  Canvas.Font.Color := DIST_GRAPH_TEXT;
  Canvas.TextOut(GraphLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Drive ' + FormatFloat('0.#', FDriveDb) + ' dB  ' +
    IntToStr(Round(FMix * 100)) + '%';
  Canvas.TextOut(GraphRight - Canvas.TextWidth(HeaderText),
    MulDiv(7, FontPPI, 96), HeaderText);

  Canvas.Pen.Color := DIST_GRAPH_GRID;
  for GridIndex := 0 to 4 do
  begin
    X := GraphLeft + PlotWidth * GridIndex div 4;
    Canvas.MoveTo(X, GraphTop);
    Canvas.LineTo(X, GraphBottom);
    Y := GraphTop + PlotHeight * GridIndex div 4;
    Canvas.MoveTo(GraphLeft, Y);
    Canvas.LineTo(GraphRight, Y);
  end;

  Canvas.Pen.Color := DIST_GRAPH_AXIS;
  X := InputToX(0);
  Canvas.MoveTo(X, GraphTop);
  Canvas.LineTo(X, GraphBottom);
  Y := OutputToY(0);
  Canvas.MoveTo(GraphLeft, Y);
  Canvas.LineTo(GraphRight, Y);

  Canvas.Font.Color := DIST_GRAPH_TEXT;
  HeaderText := FormatFloat('0.#', OutputRange);
  Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
    GraphTop - TextHeight div 2, HeaderText);
  HeaderText := FormatFloat('-0.#', OutputRange);
  Canvas.TextOut(GraphLeft - Canvas.TextWidth(HeaderText) - MulDiv(4, FontPPI, 96),
    GraphBottom - TextHeight div 2, HeaderText);
  for GridIndex := 0 to 4 do
  begin
    InputValue := -1.0 + GridIndex * 0.5;
    HeaderText := FormatFloat('0.#', InputValue);
    TextWidth := Canvas.TextWidth(HeaderText);
    X := InputToX(InputValue);
    LabelLeft := EnsureRange(X - TextWidth div 2, 1, ClientWidth - TextWidth - 1);
    Canvas.TextOut(LabelLeft, GraphBottom + MulDiv(4, FontPPI, 96), HeaderText);
  end;

  ReferencePoints[0] := Point(InputToX(-1), OutputToY(-1));
  ReferencePoints[1] := Point(InputToX(1), OutputToY(1));
  Canvas.Pen.Color := DIST_GRAPH_AXIS;
  Canvas.Pen.Style := psDash;
  Canvas.Polyline(ReferencePoints);

  AccentColor := FAccentColor;
  if not FActive then
    AccentColor := ScaleColor(AccentColor, 65, 100);
  ClipInput := 1.0 / DriveGain;
  Canvas.Pen.Color := ScaleColor(AccentColor, 65, 100);
  Canvas.Pen.Style := psDot;
  DrawClipGuide(-ClipInput);
  DrawClipGuide(ClipInput);

  SetLength(CurvePoints, PlotWidth + 1);
  for PointIndex := 0 to PlotWidth do
  begin
    InputValue := -1.0 + 2.0 * PointIndex / PlotWidth;
    OutputValue := Distort(InputValue);
    CurvePoints[PointIndex] := Point(GraphLeft + PointIndex, OutputToY(OutputValue));
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := AccentColor;
  Canvas.Pen.Width := Max(2, MulDiv(3, FontPPI, 96));
  Canvas.Polyline(CurvePoints);

  Canvas.Font.Color := DIST_GRAPH_TEXT;
  HeaderText := 'Tone ' + IntToStr(Round(FTone * 100)) + '%  Level ' +
    FormatFloat('+0.0;-0.0;0.0', FLevelDb) + ' dB';
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
