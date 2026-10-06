unit PsdPreviewControl;

// PSDアニメーションの表示面。背景と拡大画像をメモリ上で合成し、一度に転送する。
interface
uses System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.Graphics;
type
  TPsdPreviewOverlayEvent = procedure(Sender: TObject; Canvas: TCanvas; const ImageRect: TRect) of object;
  TPsdPreviewImageClickEvent = procedure(Sender: TObject; X,Y: Integer) of object;
  TPsdPreviewControl = class(TCustomControl)
  private
    FFrame: Vcl.Graphics.TBitmap;   // 借用するUIスレッドの画像。所有元より先に表示面を破棄する。
    FSurface: Vcl.Graphics.TBitmap; // 所有するクライアント寸法の合成バッファ。
    FPaintCount: UInt64;         // 完成した表示面を転送した回数。
    FZoom: Double; FPan,FDragPan: TPointF; // 表示だけの倍率と中心からの移動量。素材へ保存しない。
    FPressPoint: TPoint; FPressed,FDragging: Boolean; FPressButton: TMouseButton;
    FWheelRemainder: Integer; // 120未満のホイール入力を持ち越す。
    FLeftPanEnabled: Boolean; // 部位を直接編集するホストでは中ボタンだけでパンする。
    FOnOverlay: TPsdPreviewOverlayEvent; FOnImageClick: TPsdPreviewImageClickEvent;
    procedure ClampPan;
    procedure CancelDrag;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
  protected
    procedure Paint; override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Bitmapは複製せず借用する。更新後に呼ぶとこのHWNDだけを再描画予約する。
    procedure Present(Bitmap: Vcl.Graphics.TBitmap);
    // クライアント座標Positionを中心に拡大縮小する。文書・編集中の入力を変更しない。
    procedure WheelAt(Delta: Integer; const Position: TPoint);
    // 表示倍率・移動量を画面に収まる状態へ戻す。
    procedure Fit;
    function ImageRect: TRect;
    property PaintCount: UInt64 read FPaintCount;
    property Zoom: Double read FZoom;
    property Pan: TPointF read FPan;
    property LeftPanEnabled: Boolean read FLeftPanEnabled write FLeftPanEnabled;
    property OnOverlay: TPsdPreviewOverlayEvent read FOnOverlay write FOnOverlay;
    property OnImageClick: TPsdPreviewImageClickEvent read FOnImageClick write FOnImageClick;
  end;
implementation
uses System.Math, Winapi.Windows;
constructor TPsdPreviewControl.Create(AOwner: TComponent);
begin
  inherited;
  // クリックとドラッグの区別をMouseUpまで保持するため、キャプチャは自身で解除する。
  ControlStyle := (ControlStyle+[csOpaque])-[csCaptureMouse];
  ParentDoubleBuffered := False; // 親の背景消去・子コントロール合成から表示面を独立させる。
  FSurface := Vcl.Graphics.TBitmap.Create; FSurface.PixelFormat := pf32bit;
  FZoom := 1; FLeftPanEnabled := True; ShowHint := True;
  Hint := 'ホイールで拡大・縮小、左ドラッグで表示を移動。画面に合わせるアイコンで戻せます。';
end;
destructor TPsdPreviewControl.Destroy;
begin FSurface.Free; inherited; end;
procedure TPsdPreviewControl.Present(Bitmap: Vcl.Graphics.TBitmap);
begin FFrame := Bitmap; ClampPan; Invalidate; end;
function TPsdPreviewControl.ImageRect: TRect;
begin
  Result := Rect(0,0,0,0);
  if (FFrame=nil) or FFrame.Empty then Exit;
  var Scale := Min(Max(1,ClientWidth)/FFrame.Width,Max(1,ClientHeight)/FFrame.Height)*FZoom;
  var W := Max(1,Round(FFrame.Width*Scale)); var H := Max(1,Round(FFrame.Height*Scale));
  var X := Round((ClientWidth-W)/2+FPan.X); var Y := Round((ClientHeight-H)/2+FPan.Y);
  Result := Rect(X,Y,X+W,Y+H);
end;
procedure TPsdPreviewControl.ClampPan;
begin
  var R := ImageRect; if R.IsEmpty then Exit;
  // 移動し過ぎても画像の一部が残る範囲に収める。
  var LimitX := Max(0,(ClientWidth+R.Width)/2-ScaleValue(24));
  var LimitY := Max(0,(ClientHeight+R.Height)/2-ScaleValue(24));
  FPan.X := EnsureRange(FPan.X,-LimitX,LimitX); FPan.Y := EnsureRange(FPan.Y,-LimitY,LimitY);
end;
procedure TPsdPreviewControl.Fit;
begin
  CancelDrag; FZoom := 1; FPan := PointF(0,0); FWheelRemainder := 0; Invalidate;
end;
procedure TPsdPreviewControl.WheelAt(Delta: Integer; const Position: TPoint);
begin
  if FPressed or (FFrame=nil) or FFrame.Empty then Exit;
  Inc(FWheelRemainder,Delta); var Steps := FWheelRemainder div 120; FWheelRemainder := FWheelRemainder mod 120;
  if Steps=0 then Exit;
  var Old := ImageRect; var U := (Position.X-Old.Left)/Old.Width; var V := (Position.Y-Old.Top)/Old.Height;
  FZoom := EnsureRange(FZoom*Power(1.2,EnsureRange(Steps,-12,12)),0.1,16.0);
  var NewRect := ImageRect;
  FPan.X := FPan.X+Position.X-(NewRect.Left+U*NewRect.Width);
  FPan.Y := FPan.Y+Position.Y-(NewRect.Top+V*NewRect.Height);
  ClampPan; Invalidate;
end;
function TPsdPreviewControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  var P := ScreenToClient(MousePos); Result := PtInRect(ClientRect,P);
  if Result then WheelAt(WheelDelta,P);
end;
procedure TPsdPreviewControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if not (Button in [mbLeft,mbMiddle]) then Exit;
  if (Button=mbLeft) and not FLeftPanEnabled then Exit;
  FPressed := True; FDragging := False; FPressButton := Button;
  FPressPoint := Point(X,Y); FDragPan := FPan; MouseCapture := True;
end;
procedure TPsdPreviewControl.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited; if not FPressed then Exit;
  if not FDragging then FDragging := (Abs(X-FPressPoint.X)>=ScaleValue(4)) or (Abs(Y-FPressPoint.Y)>=ScaleValue(4));
  if not FDragging then Exit;
  Cursor := crHandPoint; FPan := PointF(FDragPan.X+X-FPressPoint.X,FDragPan.Y+Y-FPressPoint.Y);
  ClampPan; Invalidate;
end;
procedure TPsdPreviewControl.CancelDrag;
begin FPressed := False; FDragging := False; MouseCapture := False; Cursor := crDefault; end;
procedure TPsdPreviewControl.WMCaptureChanged(var Message: TMessage);
begin inherited; FPressed := False; FDragging := False; Cursor := crDefault; end;
procedure TPsdPreviewControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited; if not FPressed or (Button<>FPressButton) then Exit;
  var Click := not FDragging and (Button=mbLeft); CancelDrag;
  var R := ImageRect;
  if Click and Assigned(FOnImageClick) and PtInRect(R,Point(X,Y)) then
    FOnImageClick(Self,EnsureRange(Round((X-R.Left)*FFrame.Width/R.Width),0,FFrame.Width-1),
      EnsureRange(Round((Y-R.Top)*FFrame.Height/R.Height),0,FFrame.Height-1));
end;
procedure TPsdPreviewControl.Resize;
begin inherited; ClampPan; Invalidate; end;
procedure TPsdPreviewControl.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Paintが背景を含む全画素を転送するため、途中の空白を画面へ出さない。
  Message.Result := 1;
end;
procedure TPsdPreviewControl.Paint;
begin
  if (ClientWidth<=0) or (ClientHeight<=0) then Exit;
  FSurface.SetSize(ClientWidth,ClientHeight);
  FSurface.Canvas.Brush.Style := bsSolid; FSurface.Canvas.Brush.Color := RGB(28,28,32);
  FSurface.Canvas.FillRect(ClientRect);
  if (FFrame<>nil) and not FFrame.Empty then begin
    var R := ImageRect; FSurface.Canvas.StretchDraw(R,FFrame);
    if Assigned(FOnOverlay) then FOnOverlay(Self,FSurface.Canvas,R);
  end;
  BitBlt(Canvas.Handle,0,0,ClientWidth,ClientHeight,FSurface.Canvas.Handle,0,0,SRCCOPY);
  Inc(FPaintCount);
end;
end.
