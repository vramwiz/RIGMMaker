unit HorizontalScrollBarControl;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Graphics;

type
  // 細いテーマ描画、つまみドラッグ、トラッククリック、ホイール移動を提供する汎用横スクロールバー。
  THorizontalScrollBarControl = class(TCustomControl)
  private
    FBackgroundColor: TColor;
    FDragOffset: Integer;
    FDragging: Boolean;
    FMaximum: Integer;
    FOnChange: TNotifyEvent;
    FPageSize: Integer;
    FPosition: Integer;
    FSmallChange: Integer;
    FThumbColor: TColor;
    FTopPadding: Integer;
    FTrackColor: TColor;
    FWheelRemainder: Integer;
    function ThumbRect: TRect;
    procedure SetBackgroundColor(const Value: TColor);
    procedure SetPosition(const Value: Integer);
    procedure SetThumbColor(const Value: TColor);
    procedure SetTopPadding(const Value: Integer);
    procedure SetTrackColor(const Value: TColor);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // ContentSizeから表示幅を引いた値を最大位置とし、現在位置を有効範囲へ収める。
    procedure SetRange(const ContentSize, PageSize, SmallChange: Integer);
    property Maximum: Integer read FMaximum;
    property PageSize: Integer read FPageSize;
    property Position: Integer read FPosition write SetPosition;
  published
    property Align;
    property Anchors;
    property BackgroundColor: TColor read FBackgroundColor
      write SetBackgroundColor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property ThumbColor: TColor read FThumbColor write SetThumbColor;
    property TopPadding: Integer read FTopPadding write SetTopPadding;
    property TrackColor: TColor read FTrackColor write SetTrackColor;
    property Visible;
  end;

implementation

uses
  Winapi.Windows, System.Math;

function ScrollScale(const Value, Ppi: Integer): Integer;
begin
  Result := MulDiv(Value, Ppi, 96);
end;

constructor THorizontalScrollBarControl.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Cursor := crHandPoint;
  Height := 6;
  FBackgroundColor := clBtnFace;
  FTrackColor := clBtnShadow;
  FThumbColor := clHighlight;
  FSmallChange := 1;
end;

function THorizontalScrollBarControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Steps: Integer;
begin
  Inc(FWheelRemainder, WheelDelta);
  Steps := FWheelRemainder div WHEEL_DELTA;
  FWheelRemainder := FWheelRemainder mod WHEEL_DELTA;
  if Steps <> 0 then Position := Position - Steps * FSmallChange;
  Result := WheelDelta <> 0;
end;

procedure THorizontalScrollBarControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Thumb: TRect;
begin
  inherited;
  if (Button <> mbLeft) or (FMaximum <= 0) then Exit;
  Thumb := ThumbRect;
  if PtInRect(Thumb, Point(X, Y)) then
    FDragOffset := X - Thumb.Left
  else
    FDragOffset := Thumb.Width div 2;
  FDragging := True;
  MouseCapture := True;
  if not PtInRect(Thumb, Point(X, Y)) then MouseMove(Shift, X, Y);
end;

procedure THorizontalScrollBarControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  Thumb: TRect;
  Travel: Integer;
begin
  inherited;
  if not FDragging or (FMaximum <= 0) then Exit;
  Thumb := ThumbRect;
  Travel := Max(ClientWidth - Thumb.Width, 1);
  Position := MulDiv(X - FDragOffset, FMaximum, Travel);
end;

procedure THorizontalScrollBarControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then Exit;
  FDragging := False;
  MouseCapture := False;
end;

procedure THorizontalScrollBarControl.Paint;
var
  Padding: Integer;
  Thumb: TRect;
  TrackY: Integer;
begin
  Canvas.Brush.Color := FBackgroundColor;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := FTrackColor;
  Canvas.MoveTo(0, ClientHeight - 1);
  Canvas.LineTo(ClientWidth, ClientHeight - 1);
  Padding := EnsureRange(FTopPadding, 0, Max(ClientHeight - 1, 0));
  TrackY := Padding + Max((ClientHeight - Padding - 1) div 2, 0);
  Canvas.MoveTo(ScrollScale(3, CurrentPPI), TrackY);
  Canvas.LineTo(ClientWidth - ScrollScale(3, CurrentPPI), TrackY);
  if FMaximum <= 0 then Exit;
  Thumb := ThumbRect;
  Canvas.Brush.Color := FThumbColor;
  Canvas.Pen.Color := FThumbColor;
  Canvas.RoundRect(Thumb.Left, Thumb.Top, Thumb.Right, Thumb.Bottom,
    ScrollScale(3, CurrentPPI), ScrollScale(3, CurrentPPI));
end;

procedure THorizontalScrollBarControl.SetBackgroundColor(const Value: TColor);
begin
  if FBackgroundColor = Value then Exit;
  FBackgroundColor := Value;
  Invalidate;
end;

procedure THorizontalScrollBarControl.SetPosition(const Value: Integer);
var
  NewPosition: Integer;
begin
  NewPosition := EnsureRange(Value, 0, FMaximum);
  if FPosition = NewPosition then Exit;
  FPosition := NewPosition;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure THorizontalScrollBarControl.SetRange(const ContentSize, PageSize,
  SmallChange: Integer);
begin
  if (FPageSize=Max(PageSize,1)) and (FMaximum=Max(ContentSize-Max(PageSize,1),0)) and (FSmallChange=Max(SmallChange,1)) then Exit;
  FPageSize := Max(PageSize, 1);
  FMaximum := Max(ContentSize - FPageSize, 0);
  FSmallChange := Max(SmallChange, 1);
  SetPosition(FPosition);
  Visible := FMaximum > 0;
  Invalidate;
end;

procedure THorizontalScrollBarControl.SetThumbColor(const Value: TColor);
begin
  if FThumbColor = Value then Exit;
  FThumbColor := Value;
  Invalidate;
end;

procedure THorizontalScrollBarControl.SetTopPadding(const Value: Integer);
begin
  if FTopPadding = Max(Value, 0) then Exit;
  FTopPadding := Max(Value, 0);
  Invalidate;
end;

procedure THorizontalScrollBarControl.SetTrackColor(const Value: TColor);
begin
  if FTrackColor = Value then Exit;
  FTrackColor := Value;
  Invalidate;
end;

function THorizontalScrollBarControl.ThumbRect: TRect;
var
  AvailableHeight: Integer;
  Padding: Integer;
  ThumbWidth: Integer;
  TrackHeight: Integer;
  Travel: Integer;
begin
  Padding := EnsureRange(FTopPadding, 0, Max(ClientHeight - 1, 0));
  AvailableHeight := Max(ClientHeight - Padding, 1);
  // 高さを広く取る利用先では、つまみも太くしてドラッグ開始位置を狙いやすくする。
  // 従来の6px高で使う場合は上下1pxを残すため、既存の細い表示を維持する。
  TrackHeight := Min(Max(ScrollScale(6, CurrentPPI), 2),
    Max(AvailableHeight - ScrollScale(2, CurrentPPI), 1));
  ThumbWidth := Max(ScrollScale(20, CurrentPPI),
    MulDiv(ClientWidth, FPageSize, FPageSize + FMaximum));
  ThumbWidth := Min(ThumbWidth, ClientWidth);
  Travel := Max(ClientWidth - ThumbWidth, 0);
  Result.Left := MulDiv(FPosition, Travel, Max(FMaximum, 1));
  Result.Top := Padding + Max((AvailableHeight - TrackHeight - 1) div 2, 0);
  Result.Right := Result.Left + ThumbWidth;
  Result.Bottom := Result.Top + TrackHeight;
end;

end.
