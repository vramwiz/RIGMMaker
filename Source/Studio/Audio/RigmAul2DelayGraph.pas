unit RigmAul2DelayGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// ControllerのDelay設定を、音声データへ依存しない時間・反射グラフとして描画する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAul2ControllerDelayGraph = class(TCustomControl)
  private
    FAccentColor: TColor;
    FActive     : Boolean;
    FDry        : Double;
    FFeedback   : Double;
    FPingPong   : Boolean;
    FTimeMs     : Double;
    FWet        : Double;
    procedure SetAccentColor(const Value: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // 現在のDelay設定を保持し、設定値だけから反射図を再描画する。
    procedure SetDelay(TimeMs, Dry, Wet, Feedback: Double; PingPong, Active: Boolean);
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
  DELAY_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  DELAY_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  DELAY_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  DELAY_GRAPH_AXIS       = TColor($00645E58); // RGB(88, 94, 100)
  DELAY_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)

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

constructor TAul2ControllerDelayGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := DELAY_GRAPH_BACKGROUND;
  FAccentColor := RGB(74, 190, 236);
  FActive := True;
  FTimeMs := 250;
  FDry := 1;
  FWet := 0.5;
  FFeedback := 0.4;
  FPingPong := False;
end;

procedure TAul2ControllerDelayGraph.SetAccentColor(const Value: TColor);
begin
  if FAccentColor = Value then
    Exit;
  FAccentColor := Value;
  Invalidate;
end;

procedure TAul2ControllerDelayGraph.SetDelay(TimeMs, Dry, Wet, Feedback: Double;
  PingPong, Active: Boolean);
begin
  FTimeMs := EnsureRange(TimeMs, 1.0, 1000.0);
  FDry := EnsureRange(Dry, 0.0, 2.0);
  FWet := EnsureRange(Wet, 0.0, 2.0);
  FFeedback := EnsureRange(Feedback, 0.0, 0.95);
  FPingPong := PingPong;
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerDelayGraph.Paint;
var
  ArrowY       : Integer;
  BaselineY    : Integer;
  DiagramLeft  : Integer;
  DiagramRight : Integer;
  DiagramWidth : Integer;
  DryColor     : TColor;
  DryTextColor : TColor;
  EchoColor    : TColor;
  EchoCount    : Integer;
  EchoIndex    : Integer;
  EchoLevel    : Double;
  EchoPoints   : array of TPoint;
  EchoText     : string;
  EchoTextColor: TColor;
  FontPPI      : Integer;
  GridIndex    : Integer;
  GridY        : Integer;
  HeaderText   : string;
  LabelLeft    : Integer;
  LabelTop     : Integer;
  MaximumEchoes: Integer;
  PlotHeight   : Integer;
  PlotTop      : Integer;
  PulseWidth   : Integer;
  Spacing      : Integer;
  TextHeight   : Integer;
  TextValue    : string;
  TextWidth    : Integer;

  procedure DrawRightText(const Text: string; Right, Top: Integer);
  begin
    Canvas.TextOut(Right - Canvas.TextWidth(Text), Top, Text);
  end;

  function DrawPulse(X: Integer; Level: Double; LineColor: TColor): TPoint;
  var
    LineTop: Integer;
  begin
    Level := EnsureRange(Level, 0.0, 2.0);
    LineTop := BaselineY - Round(Level / 2.0 * PlotHeight);
    Canvas.Pen.Color := LineColor;
    Canvas.Pen.Width := PulseWidth;
    Canvas.Pen.Style := psSolid;
    Canvas.MoveTo(X, BaselineY);
    Canvas.LineTo(X, LineTop);
    Result := Point(X, LineTop);
  end;

  procedure DrawArrow(Left, Right, Y: Integer);
  var
    ArrowSize: Integer;
  begin
    ArrowSize := Max(3, MulDiv(4, FontPPI, 96));
    Canvas.Pen.Color := DELAY_GRAPH_AXIS;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Style := psSolid;
    Canvas.MoveTo(Left, Y);
    Canvas.LineTo(Right, Y);
    Canvas.MoveTo(Left, Y);
    Canvas.LineTo(Left + ArrowSize, Y - ArrowSize div 2);
    Canvas.MoveTo(Left, Y);
    Canvas.LineTo(Left + ArrowSize, Y + ArrowSize div 2);
    Canvas.MoveTo(Right, Y);
    Canvas.LineTo(Right - ArrowSize, Y - ArrowSize div 2);
    Canvas.MoveTo(Right, Y);
    Canvas.LineTo(Right - ArrowSize, Y + ArrowSize div 2);
  end;

begin
  Canvas.Brush.Color := DELAY_GRAPH_BACKGROUND;
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
  Canvas.Font.Color := DELAY_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');

  DiagramLeft := MulDiv(18, FontPPI, 96);
  DiagramRight := ClientWidth - MulDiv(12, FontPPI, 96);
  PlotTop := MulDiv(34, FontPPI, 96);
  BaselineY := ClientHeight - MulDiv(31, FontPPI, 96);
  DiagramWidth := Max(1, DiagramRight - DiagramLeft);
  PlotHeight := Max(1, BaselineY - PlotTop);
  PulseWidth := Max(3, MulDiv(4, FontPPI, 96));

  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := DELAY_GRAPH_BORDER;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);

  HeaderText := 'Delay ' + FormatFloat('0', FTimeMs) + ' ms';
  Canvas.Font.Color := DELAY_GRAPH_TEXT;
  Canvas.TextOut(DiagramLeft, MulDiv(7, FontPPI, 96), HeaderText);
  HeaderText := 'Feedback ' + IntToStr(Round(FFeedback * 100)) + '%';
  DrawRightText(HeaderText, DiagramRight, MulDiv(7, FontPPI, 96));

  // 補助線と減衰線は1pxに固定し、反射を表す主線との強弱を明確にする。
  Canvas.Pen.Color := DELAY_GRAPH_GRID;
  Canvas.Pen.Width := 1;
  for GridIndex := 1 to 3 do
  begin
    GridY := PlotTop + PlotHeight * GridIndex div 4;
    Canvas.MoveTo(DiagramLeft, GridY);
    Canvas.LineTo(DiagramRight, GridY);
  end;

  Canvas.Pen.Color := DELAY_GRAPH_AXIS;
  Canvas.MoveTo(DiagramLeft, BaselineY);
  Canvas.LineTo(DiagramRight, BaselineY);

  DryColor := RGB(238, 112, 80);
  EchoColor := FAccentColor;
  DryTextColor := ScaleColor(DryColor, 125, 100);
  EchoTextColor := ScaleColor(EchoColor, 125, 100);
  if not FActive then
  begin
    DryColor := ScaleColor(DryColor, 65, 100);
    EchoColor := ScaleColor(EchoColor, 65, 100);
  end;

  MaximumEchoes := EnsureRange(DiagramWidth div Max(1, MulDiv(46, FontPPI, 96)), 1, 6);
  EchoCount := 1;
  while EchoCount < MaximumEchoes do
  begin
    EchoLevel := FWet * Power(FFeedback, EchoCount);
    if EchoLevel < 0.03 then
      Break;
    Inc(EchoCount);
  end;
  Spacing := DiagramWidth div EchoCount;
  SetLength(EchoPoints, EchoCount + 1);
  EchoPoints[0] := DrawPulse(DiagramLeft, FDry, DryColor);
  for EchoIndex := 1 to EchoCount do
  begin
    EchoLevel := FWet * Power(FFeedback, EchoIndex - 1);
    if FPingPong and not Odd(EchoIndex) then
      EchoPoints[EchoIndex] := DrawPulse(DiagramLeft + Spacing * EchoIndex,
        EchoLevel, ScaleColor(EchoColor, 125, 100))
    else
      EchoPoints[EchoIndex] := DrawPulse(DiagramLeft + Spacing * EchoIndex,
        EchoLevel, EchoColor);
  end;

  Canvas.Pen.Color := ScaleColor(EchoColor, 78, 100);
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psDash;
  Canvas.MoveTo(EchoPoints[0].X, EchoPoints[0].Y);
  for EchoIndex := 1 to EchoCount do
    Canvas.LineTo(EchoPoints[EchoIndex].X, EchoPoints[EchoIndex].Y);
  Canvas.Pen.Style := psSolid;

  Canvas.Font.Color := DryTextColor;
  TextValue := 'Dry ' + FormatFloat('0.00', FDry);
  LabelTop := Max(PlotTop, EchoPoints[0].Y - TextHeight - MulDiv(3, FontPPI, 96));
  Canvas.TextOut(EchoPoints[0].X, LabelTop, TextValue);
  Canvas.Font.Color := EchoTextColor;
  if FPingPong then
    EchoText := 'Echo L '
  else
    EchoText := 'Echo ';
  TextValue := EchoText + FormatFloat('0.00', FWet);
  LabelTop := Max(PlotTop, EchoPoints[1].Y - TextHeight - MulDiv(3, FontPPI, 96));
  TextWidth := Canvas.TextWidth(TextValue);
  LabelLeft := EnsureRange(EchoPoints[1].X - TextWidth div 2,
    DiagramLeft, DiagramRight - TextWidth);
  Canvas.TextOut(LabelLeft, LabelTop, TextValue);

  ArrowY := BaselineY + MulDiv(18, FontPPI, 96);
  DrawArrow(DiagramLeft + PulseWidth, EchoPoints[1].X - PulseWidth, ArrowY);
  TextValue := FormatFloat('0', FTimeMs) + ' ms';
  TextWidth := Canvas.TextWidth(TextValue);
  Canvas.Font.Color := DELAY_GRAPH_TEXT;
  Canvas.TextOut(DiagramLeft + (Spacing - TextWidth) div 2,
    BaselineY + MulDiv(2, FontPPI, 96), TextValue);
  TextValue := IntToStr(Round(FTimeMs * EchoCount)) + ' ms';
  DrawRightText(TextValue, DiagramRight, BaselineY + MulDiv(2, FontPPI, 96));

  if FPingPong and (EchoCount >= 2) and (Spacing >= MulDiv(42, FontPPI, 96)) then
  begin
    TextValue := 'R';
    TextWidth := Canvas.TextWidth(TextValue);
    Canvas.Font.Color := EchoTextColor;
    Canvas.TextOut(EchoPoints[2].X - TextWidth div 2,
      Max(PlotTop, EchoPoints[2].Y - TextHeight - MulDiv(3, FontPPI, 96)), TextValue);
  end;

  if not FActive then
  begin
    Canvas.Font.Color := RGB(220, 126, 104);
    TextValue := 'OFF';
    TextWidth := Canvas.TextWidth(TextValue);
    Canvas.TextOut((ClientWidth - TextWidth) div 2, MulDiv(7, FontPPI, 96), TextValue);
  end;
end;

end.
