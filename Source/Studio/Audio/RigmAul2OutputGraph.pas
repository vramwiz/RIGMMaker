unit RigmAul2OutputGraph;
// Adapted from Aul2AudioFilter controller graph. Configuration curves and measured data are separate.

// RIGMMaker audition is mono: show one input/output meter and actual RMS history.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

const
  CONTROLLER_OUTPUT_HISTORY_COUNT = 48;

type
  TControllerOutputHistory = array[0..CONTROLLER_OUTPUT_HISTORY_COUNT - 1] of Single;

  TAul2ControllerOutputGraph = class(TCustomControl)
  private
    FActive: Boolean;
    FDataValid: Boolean;
    FInputPeakL: Single;
    FInputPeakR: Single;
    FOutputPeakL: Single;
    FOutputPeakR: Single;
    FHistoryCount: Integer;
    FInputRmsL: TControllerOutputHistory;
    FInputRmsR: TControllerOutputHistory;
    FOutputRmsL: TControllerOutputHistory;
    FOutputRmsR: TControllerOutputHistory;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearData;
    procedure SetActive(Active: Boolean);
    procedure SetMonitorData(InputPeakL, InputPeakR, OutputPeakL,
      OutputPeakR: Single; const InputRmsL, InputRmsR, OutputRmsL,
      OutputRmsR: TControllerOutputHistory; HistoryCount: Integer);
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
  OUTPUT_GRAPH_BACKGROUND = TColor($0013100E); // RGB(14, 16, 19)
  OUTPUT_GRAPH_BORDER     = TColor($00312C28); // RGB(40, 44, 49)
  OUTPUT_GRAPH_GRID       = TColor($002B2723); // RGB(35, 39, 43)
  OUTPUT_GRAPH_TEXT       = TColor($00F2F0EE); // RGB(238, 240, 242)
  OUTPUT_GRAPH_INPUT      = TColor($007ABE5C); // RGB(92, 190, 122)
  OUTPUT_GRAPH_OUTPUT     = TColor($0048B0E0); // RGB(224, 176, 72)
  OUTPUT_GRAPH_MIN_DB     = -60.0;

function ScaleColor(Color: TColor; Numerator, Denominator: Integer): TColor;
var
  Blue: Integer;
  Green: Integer;
  Red: Integer;
begin
  Color := ColorToRGB(Color);
  Red := EnsureRange(GetRValue(Color) * Numerator div Denominator, 0, 255);
  Green := EnsureRange(GetGValue(Color) * Numerator div Denominator, 0, 255);
  Blue := EnsureRange(GetBValue(Color) * Numerator div Denominator, 0, 255);
  Result := RGB(Red, Green, Blue);
end;

function LevelToRatio(Value: Single): Double;
var
  Db: Double;
begin
  if Value <= 0.000001 then
    Exit(0);
  Db := 20.0 * Log10(Value);
  Result := EnsureRange((Db - OUTPUT_GRAPH_MIN_DB) / -OUTPUT_GRAPH_MIN_DB, 0.0, 1.0);
end;

constructor TAul2ControllerOutputGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  Color := OUTPUT_GRAPH_BACKGROUND;
  FActive := True;
  ClearData;
end;

procedure TAul2ControllerOutputGraph.ClearData;
begin
  FDataValid := False;
  FInputPeakL := 0;
  FInputPeakR := 0;
  FOutputPeakL := 0;
  FOutputPeakR := 0;
  FHistoryCount := 0;
  FillChar(FInputRmsL, SizeOf(FInputRmsL), 0);
  FillChar(FInputRmsR, SizeOf(FInputRmsR), 0);
  FillChar(FOutputRmsL, SizeOf(FOutputRmsL), 0);
  FillChar(FOutputRmsR, SizeOf(FOutputRmsR), 0);
  Invalidate;
end;

procedure TAul2ControllerOutputGraph.SetActive(Active: Boolean);
begin
  if FActive = Active then
    Exit;
  FActive := Active;
  Invalidate;
end;

procedure TAul2ControllerOutputGraph.SetMonitorData(InputPeakL, InputPeakR,
  OutputPeakL, OutputPeakR: Single; const InputRmsL, InputRmsR, OutputRmsL,
  OutputRmsR: TControllerOutputHistory; HistoryCount: Integer);
begin
  FInputPeakL := Max(0.0, InputPeakL);
  FInputPeakR := Max(0.0, InputPeakR);
  FOutputPeakL := Max(0.0, OutputPeakL);
  FOutputPeakR := Max(0.0, OutputPeakR);
  FInputRmsL := InputRmsL;
  FInputRmsR := InputRmsR;
  FOutputRmsL := OutputRmsL;
  FOutputRmsR := OutputRmsR;
  FHistoryCount := EnsureRange(HistoryCount, 0, CONTROLLER_OUTPUT_HISTORY_COUNT);
  FDataValid := True;
  Invalidate;
end;

procedure TAul2ControllerOutputGraph.Paint;
var
  BarBottom: Integer;
  BarColors: array[0..3] of TColor;
  BarLeft: Integer;
  BarRect: TRect;
  BarTop: Integer;
  BarWidth: Integer;
  FontPPI: Integer;
  GridDb: Integer;
  HistoryBottom: Integer;
  HistoryLeft: Integer;
  HistoryRect: TRect;
  HistoryRight: Integer;
  HistoryTop: Integer;
  Index: Integer;
  Levels: array[0..3] of Single;
  OutputColor: TColor;
  PointCount: Integer;
  Points: array of TPoint;
  TextHeight: Integer;
  X: Integer;
  Y: Integer;

  procedure DrawHistory(const Values: TControllerOutputHistory; Color: TColor);
  var
    HistoryIndex: Integer;
  begin
    PointCount := Min(FHistoryCount, Length(Values));
    if PointCount <= 0 then
      Exit;
    if PointCount = 1 then
    begin
      Y := HistoryBottom - Round(LevelToRatio(Values[0]) *
        (HistoryBottom - HistoryTop));
      Canvas.Pen.Color := Color;
      Canvas.Pen.Width := 1;
      Canvas.MoveTo(HistoryLeft, Y);
      Canvas.LineTo(HistoryRight, Y);
      Exit;
    end;
    SetLength(Points, PointCount);
    for HistoryIndex := 0 to PointCount - 1 do
    begin
      X := HistoryLeft + Round(HistoryIndex * (HistoryRight - HistoryLeft) /
        Max(1, PointCount - 1));
      Y := HistoryBottom - Round(LevelToRatio(Values[HistoryIndex]) *
        (HistoryBottom - HistoryTop));
      Points[HistoryIndex] := Point(X, Y);
    end;
    Canvas.Pen.Color := Color;
    Canvas.Pen.Width := 1;
    Canvas.Polyline(Points);
  end;

begin
  inherited;
  Canvas.Brush.Color := OUTPUT_GRAPH_BACKGROUND;
  Canvas.FillRect(ClientRect);
  if (ClientWidth <= 20) or (ClientHeight <= 20) then
    Exit;

  FontPPI := Max(96, CurrentPPI);
  Canvas.Font.Assign(Font);
  Canvas.Font.Height := -MulDiv(9, FontPPI, 72);
  Canvas.Font.Color := OUTPUT_GRAPH_TEXT;
  Canvas.Brush.Style := bsClear;
  TextHeight := Canvas.TextHeight('0');
  OutputColor := OUTPUT_GRAPH_OUTPUT;
  if not FActive then
    OutputColor := ScaleColor(OutputColor, 45, 100);

  Canvas.Pen.Color := OUTPUT_GRAPH_BORDER;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(ClientRect);
  Canvas.TextOut(MulDiv(8, FontPPI, 96), MulDiv(5, FontPPI, 96),
    'Input / Output');
  Canvas.Font.Color := ScaleColor(OUTPUT_GRAPH_TEXT, 70, 100);
  Canvas.TextOut(ClientWidth - Canvas.TextWidth('Peak + RMS') -
    MulDiv(8, FontPPI, 96), MulDiv(5, FontPPI, 96), 'Peak + RMS');

  BarTop := MulDiv(35, FontPPI, 96);
  BarBottom := ClientHeight - MulDiv(25, FontPPI, 96);
  BarWidth := Max(MulDiv(7, FontPPI, 96),
    (ClientWidth * 34 div 100) div 7);
  BarLeft := MulDiv(12, FontPPI, 96);
  Levels[0] := FInputPeakL;
  Levels[1] := FOutputPeakL;
  Levels[2] := FOutputPeakL;
  Levels[3] := FOutputPeakR;
  BarColors[0] := OUTPUT_GRAPH_INPUT;
  BarColors[1] := OutputColor;
  BarColors[2] := OutputColor;
  BarColors[3] := OutputColor;

  for Index := 0 to 1 do
  begin
    BarRect := Rect(BarLeft + Index * (BarWidth + MulDiv(5, FontPPI, 96)),
      BarTop, BarLeft + Index * (BarWidth + MulDiv(5, FontPPI, 96)) + BarWidth,
      BarBottom);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := OUTPUT_GRAPH_GRID;
    Canvas.FillRect(BarRect);
    if FDataValid then
    begin
      Y := BarRect.Bottom - Round(LevelToRatio(Levels[Index]) * BarRect.Height);
      Canvas.Brush.Color := BarColors[Index];
      Canvas.FillRect(Rect(BarRect.Left, Y, BarRect.Right, BarRect.Bottom));
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ScaleColor(OUTPUT_GRAPH_TEXT, 65, 100);
    Canvas.TextOut(BarRect.Left + (BarWidth - Canvas.TextWidth('M')) div 2,
      BarBottom + 2, 'M');
  end;

  Canvas.Font.Color := OUTPUT_GRAPH_INPUT;
  Canvas.TextOut(BarLeft, BarTop - TextHeight - 2, 'In');
  Canvas.Font.Color := OutputColor;
  Canvas.TextOut(BarLeft + (BarWidth + MulDiv(5, FontPPI, 96)),
    BarTop - TextHeight - 2, 'Out');

  HistoryLeft := ClientWidth * 43 div 100;
  HistoryRight := ClientWidth - MulDiv(10, FontPPI, 96);
  HistoryTop := BarTop;
  HistoryBottom := BarBottom;
  HistoryRect := Rect(HistoryLeft, HistoryTop, HistoryRight, HistoryBottom);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ScaleColor(OUTPUT_GRAPH_BACKGROUND, 120, 100);
  Canvas.FillRect(HistoryRect);
  Canvas.Pen.Color := OUTPUT_GRAPH_GRID;
  for GridDb in [-60, -40, -20, 0] do
  begin
    Y := HistoryBottom - Round((GridDb - OUTPUT_GRAPH_MIN_DB) /
      -OUTPUT_GRAPH_MIN_DB * (HistoryBottom - HistoryTop));
    Canvas.MoveTo(HistoryLeft, Y);
    Canvas.LineTo(HistoryRight, Y);
  end;

  if FDataValid then
  begin
    DrawHistory(FInputRmsL, ScaleColor(OUTPUT_GRAPH_INPUT, 80, 100));

    DrawHistory(FOutputRmsL, OutputColor);

  end
  else
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ScaleColor(OUTPUT_GRAPH_TEXT, 55, 100);
    Canvas.TextOut(HistoryLeft + (HistoryRight - HistoryLeft -
      Canvas.TextWidth('no audio data')) div 2,
      HistoryTop + (HistoryBottom - HistoryTop - TextHeight) div 2,
      'no audio data');
  end;

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ScaleColor(OUTPUT_GRAPH_TEXT, 55, 100);
  Canvas.TextOut(HistoryLeft, HistoryBottom + 2, 'RMS history');
end;

end.
