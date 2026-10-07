unit RigmScriptPageFrame;

// 台本の動的画面は表示先のDPIへ先に接続し、固定寸法をScaleValueで設定する。
interface
uses System.Classes, Vcl.Controls, Vcl.StdCtrls, RigmBufferedControls;
type
  TRigmScriptPageFrame = class(TRigmBufferedFrame)
  public
    constructor Create(AOwner: TComponent); override;
  end;
  TRigmScriptLabel = class(TLabel)
  private
    FMeasuring: Boolean;
  protected
    procedure AdjustBounds; override;
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
  public
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
  end;
implementation
uses System.Math, System.Types, Winapi.Windows;
constructor TRigmScriptPageFrame.Create(AOwner: TComponent);
begin
  inherited;
  ParentFont := False; Font.PixelsPerInch := 96; Font.IsDPIRelated := True;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  // ラジオボタン・一覧がHWNDを要求する前に接続する。以後の寸法は現在の倍率で設定する。
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
end;
procedure TRigmScriptLabel.AdjustBounds;
begin
  if FMeasuring then Exit;
  if (Parent=nil) or not (Align in [alTop,alBottom]) then begin inherited; Exit; end;
  FMeasuring := True;
  var DC := GetDC(0);
  try
    Canvas.Handle := DC; Canvas.Font.Assign(Font);
    var R := Rect(0,0,Max(1,Width),0);
    var Flags := DT_CALCRECT or DT_EXPANDTABS;
    if WordWrap then Flags := Flags or DT_WORDBREAK;
    DoDrawText(R,Flags);
    Height := Max(R.Height,Canvas.TextHeight('Hg'))+MulDiv(6,CurrentPPI,96);
  finally Canvas.Handle := 0; ReleaseDC(0,DC); FMeasuring := False; end;
end;
procedure TRigmScriptLabel.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  var WidthChanged := Width<>AWidth;
  inherited;
  if WidthChanged then AdjustBounds;
end;
procedure TRigmScriptLabel.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; AdjustBounds; end;
end.
