unit RigmEffectsWaveform;
// The Aul2 monitor palette with exact input/output min/max envelopes, not synthetic samples.
interface
uses System.Classes, Vcl.Controls, Vcl.Graphics, RigmEffectsAnalysis;
type
  TRigmEffectsWaveform = class(TCustomControl)
  private
    FAnalysis: TRigmEffectsAnalysis; // Borrowed sealed snapshot, owned by the frame.
    FPosition: Double;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetData(Analysis: TRigmEffectsAnalysis; Position: Double);
  end;
implementation
uses System.SysUtils, System.Math, Winapi.Windows;
const
  BACK = TColor($0013100E); GRID = TColor($00312C28);
  INPUT_COLOR = TColor($007ABE5C); OUTPUT_COLOR = TColor($0048B0E0);
constructor TRigmEffectsWaveform.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ControlStyle := ControlStyle+[csOpaque];
  ParentBackground := False; Color := BACK;
end;
procedure TRigmEffectsWaveform.SetData(Analysis: TRigmEffectsAnalysis; Position: Double);
begin FAnalysis := Analysis; FPosition := Position; Invalidate; end;
procedure TRigmEffectsWaveform.Paint;
var X1,X2,Y,Half,Top,Bottom: Integer;
  function S(Value: Integer): Integer; begin Result := MulDiv(Value,CurrentPPI,96); end;
  procedure Envelope(IsInput: Boolean);
  begin
    if IsInput then Canvas.Pen.Color := INPUT_COLOR else Canvas.Pen.Color := OUTPUT_COLOR;
    for var X := X1 to X2 do begin
      var First := Int64(X-X1)*FAnalysis.WavePointCount div Max(1,X2-X1+1);
      var Last := Min(FAnalysis.WavePointCount-1,Int64(X-X1+1)*FAnalysis.WavePointCount div Max(1,X2-X1+1));
      var Lo := 1.0; var Hi := -1.0;
      for var I := First to Last do begin
        var P := FAnalysis.WavePoint(I);
        if IsInput then begin Lo := Min(Lo,P.InputMin); Hi := Max(Hi,P.InputMax); end
        else begin Lo := Min(Lo,P.OutputMin); Hi := Max(Hi,P.OutputMax); end;
      end;
      Canvas.MoveTo(X,Y-Round(EnsureRange(Hi,-1.0,1.0)*Half));
      Canvas.LineTo(X,Y-Round(EnsureRange(Lo,-1.0,1.0)*Half)+1);
    end;
  end;
begin
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := BACK; Canvas.FillRect(ClientRect); Canvas.Font.Assign(Font);
  Canvas.Font.Color := $00F2F0EE; Canvas.Brush.Style := bsClear;
  Canvas.TextOut(S(10),S(5),'波形（モノラル実測・原音／出力）');
  if (FAnalysis=nil) or not FAnalysis.Ready or (FAnalysis.WavePointCount=0) then begin
    Canvas.TextOut(S(10),S(35),'再生すると処理結果を表示します'); Canvas.Brush.Style := bsSolid; Exit;
  end;
  Canvas.Font.Color := INPUT_COLOR; Canvas.TextOut(S(10),S(25),'緑：原音');
  Canvas.Font.Color := OUTPUT_COLOR; Canvas.TextOut(S(110),S(25),'橙：最終出力');
  var Duration := FAnalysis.SampleCount/FAnalysis.Rate;
  Canvas.Font.Color := $00F2F0EE;
  Canvas.TextOut(Max(S(240),Width-S(160)),S(25),Format('%.2f / %.2f 秒',[FPosition,Duration]));
  X1 := S(10); X2 := Width-S(10); Top := S(50); Bottom := Height-S(10);
  Y := (Top+Bottom) div 2; Half := Max(1,(Bottom-Top) div 2);
  Canvas.Pen.Color := GRID; Canvas.MoveTo(X1,Y); Canvas.LineTo(X2,Y);
  Envelope(True); Envelope(False);
  Canvas.Pen.Color := clWhite;
  var Cursor := X1+Round(EnsureRange(FPosition/Max(0.000001,Duration),0.0,1.0)*(X2-X1));
  Canvas.MoveTo(Cursor,Top); Canvas.LineTo(Cursor,Bottom);
  Canvas.Brush.Style := bsSolid;
end;
end.
