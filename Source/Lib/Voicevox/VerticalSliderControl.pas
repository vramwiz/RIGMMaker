// 数値表示と直接入力を備え、マウス操作で値を変更できる共通の縦型スライダーを提供する。
unit VerticalSliderControl;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls;

type
  // PositionはMinimumからMaximumの範囲に制限され、ドラッグとホイール操作ではSmallChange単位に丸める。
  // 数値表示のクリックではTEditへ切り替え、Enter／フォーカス移動で確定し、Escで編集前の値へ戻す。
  TVerticalSliderControl = class(TCustomControl)
  private
    FBackColor: TColor;
    FCaption: string;
    FDecimals: Integer;
    FDragging: Boolean;
    FEdit: TEdit;
    FEditBackColor: TColor;
    FEditOriginalPosition: Double;
    FEditTextColor: TColor;
    FFinishingEdit: Boolean;
    FLargeChange: Double;
    FMaximum: Double;
    FMinimum: Double;
    FOnChange: TNotifyEvent;
    FOnRightClick: TNotifyEvent;
    FPosition: Double;
    FSmallChange: Double;
    FShowValue: Boolean;
    FShowCaption: Boolean;
    FTextColor: TColor;
    FThumbColor: TColor;
    FThumbRadius: Integer;
    FTrackColor: TColor;
    FTrackWidth: Integer;
    FUpperTrackColor: TColor;
    FWheelChangesPosition: Boolean;
    procedure BeginValueEdit;
    procedure CancelValueEdit;
    procedure ChangePosition(const Delta: Double);
    procedure CommitValueEdit;
    procedure DoChange;
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LayoutValueEdit;
    function GetFooterHeight: Integer;
    function GetTrackBounds(out CenterX, TrackTop, TrackBottom: Integer): Boolean;
    function GetValueText: string;
    function PositionToY(const TrackTop, TrackBottom: Integer): Integer;
    function SnapValue(const Value: Double): Double;
    procedure SetBackColor(const Value: TColor);
    procedure SetCaption(const Value: string);
    procedure SetDecimals(const Value: Integer);
    procedure SetEditBackColor(const Value: TColor);
    procedure SetEditTextColor(const Value: TColor);
    procedure SetLargeChange(const Value: Double);
    procedure SetMaximum(const Value: Double);
    procedure SetMinimum(const Value: Double);
    procedure SetPosition(const Value: Double);
    procedure SetSmallChange(const Value: Double);
    procedure SetShowValue(const Value: Boolean);
    procedure SetShowCaption(const Value: Boolean);
    procedure SetTextColor(const Value: TColor);
    procedure SetThumbColor(const Value: TColor);
    procedure SetThumbRadius(const Value: Integer);
    procedure SetTrackColor(const Value: TColor);
    procedure SetTrackWidth(const Value: Integer);
    procedure SetUpperTrackColor(const Value: TColor);
    procedure SetWheelChangesPosition(const Value: Boolean);
    function YToPosition(const Y, TrackTop, TrackBottom: Integer): Double;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    // 既定の範囲と描画色を設定し、数値を直接入力するための子TEditを生成する。
    constructor Create(AOwner: TComponent); override;
    function RequestFinish: Boolean;
  published
    property Align;
    property AlignWithMargins;
    property Anchors;
    property BackColor: TColor read FBackColor write SetBackColor;
    property Caption: string read FCaption write SetCaption;
    property Decimals: Integer read FDecimals write SetDecimals;
    property EditBackColor: TColor read FEditBackColor write SetEditBackColor;
    property EditTextColor: TColor read FEditTextColor write SetEditTextColor;
    property Font;
    // バーをクリックした時に増減する量。負数は0として扱う。
    property LargeChange: Double read FLargeChange write SetLargeChange;
    property Margins;
    property Maximum: Double read FMaximum write SetMaximum;
    property Minimum: Double read FMinimum write SetMinimum;
    // 現在値。実際に値が変化した場合はOnChangeを通知する。
    property Position: Double read FPosition write SetPosition;
    // ホイール操作の増減量であり、ドラッグ位置と直接入力値を丸める最小単位でもある。
    property SmallChange: Double read FSmallChange write SetSmallChange;
    // Falseでは数値表示と直接入力を隠し、キャプションだけを下端へ表示する。
    property ShowValue: Boolean read FShowValue write SetShowValue default True;
    // モーラ名を親の列全体に表示する場合は、個別音素バーの見出し領域を省く。
    property ShowCaption: Boolean read FShowCaption write SetShowCaption default True;
    property TextColor: TColor read FTextColor write SetTextColor;
    property ThumbColor: TColor read FThumbColor write SetThumbColor;
    property ThumbRadius: Integer read FThumbRadius write SetThumbRadius;
    property TrackColor: TColor read FTrackColor write SetTrackColor;
    property TrackWidth: Integer read FTrackWidth write SetTrackWidth;
    // つまみより上側に描画する未到達部分の色。
    property UpperTrackColor: TColor read FUpperTrackColor write SetUpperTrackColor;
    // Falseではホイールを値変更に使わず、親コントロールのスクロール処理へ渡す。
    property WheelChangesPosition: Boolean read FWheelChangesPosition
      write SetWheelChangesPosition default True;
    property Visible;
    property OnDblClick;
    property OnKeyDown;
    property OnMouseWheel;
    // Positionが変更された後に通知する。表示だけを再描画した場合は通知しない。
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // スライダー上で右クリックされた後に通知する。
    property OnRightClick: TNotifyEvent read FOnRightClick write FOnRightClick;
  end;

implementation

uses
  Winapi.Windows, System.Math, System.SysUtils;

const
  CAPTION_HEIGHT = 20;
  VALUE_HEIGHT = 20;
  TRACK_HIT_RADIUS = 8;
  TRACK_MARGIN = 5;

function SliderScale(const Value, Ppi: Integer): Integer;
begin
  Result := MulDiv(Value, Ppi, 96);
end;

constructor TVerticalSliderControl.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Width := 48;
  Height := 120;
  FBackColor := clBtnFace;
  FCaption := '';
  FDecimals := 2;
  FDragging := False;
  FEditBackColor := clWindow;
  FEditTextColor := clWindowText;
  FFinishingEdit := False;
  FLargeChange := 10;
  FMinimum := 0;
  FMaximum := 100;
  FPosition := 50;
  FSmallChange := 1;
  FShowValue := True;
  FShowCaption := True;
  FTextColor := clWindowText;
  FTrackColor := $0097C981;
  FUpperTrackColor := $00647A68;
  FThumbColor := $0097C981;
  FTrackWidth := 2;
  FThumbRadius := 5;
  FWheelChangesPosition := True;
  Cursor := crHandPoint;
  TabStop := True;

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.AutoSelect := True;
  FEdit.Color := FEditBackColor;
  FEdit.Font.Color := FEditTextColor;
  FEdit.Visible := False;
  FEdit.OnExit := EditExit;
  FEdit.OnKeyDown := EditKeyDown;
end;

procedure TVerticalSliderControl.BeginValueEdit;
begin
  if FEdit.Visible then Exit;
  FEditOriginalPosition := FPosition;
  FEdit.Font.Assign(Font);
  FEdit.Font.Height := -SliderScale(14, CurrentPPI);
  FEdit.Font.Color := FEditTextColor;
  FEdit.Text := GetValueText;
  LayoutValueEdit;
  FEdit.Visible := True;
  FEdit.BringToFront;
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end;
end;

procedure TVerticalSliderControl.CancelValueEdit;
begin
  if not FEdit.Visible or FFinishingEdit then Exit;
  FFinishingEdit := True;
  try
    FPosition := FEditOriginalPosition;
    FEdit.Visible := False;
    Invalidate;
  finally
    FFinishingEdit := False;
  end;
end;

procedure TVerticalSliderControl.ChangePosition(const Delta: Double);
begin
  SetPosition(SnapValue(FPosition + Delta));
end;

function TVerticalSliderControl.RequestFinish: Boolean;
var NewValue: Double;
begin
  Result := True;
  if not FEdit.Visible or FFinishingEdit then Exit;
  Result := TryStrToFloat(Trim(FEdit.Text),NewValue);
  if Result then Result := not IsNan(NewValue) and not IsInfinite(NewValue) and (NewValue>=FMinimum) and (NewValue<=FMaximum);
  if not Result then begin
    FEdit.Hint := '範囲内の数値を入力してください。'; FEdit.ShowHint := True;
    if FEdit.CanFocus then FEdit.SetFocus; Exit;
  end;
  FFinishingEdit := True;
  try SetPosition(SnapValue(NewValue)); FEdit.Visible := False; Invalidate;
  finally FFinishingEdit := False; end;
end;
procedure TVerticalSliderControl.CommitValueEdit;
begin RequestFinish; end;

procedure TVerticalSliderControl.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TVerticalSliderControl.EditExit(Sender: TObject);
begin
  CommitValueEdit;
end;

procedure TVerticalSliderControl.EditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        CommitValueEdit;
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        CancelValueEdit;
      end;
  end;
end;

function TVerticalSliderControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if not FWheelChangesPosition then
  begin
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
    Exit;
  end;
  if WheelDelta > 0 then
    ChangePosition(FSmallChange)
  else if WheelDelta < 0 then
    ChangePosition(-FSmallChange);
  Result := WheelDelta <> 0;
  if not Result then
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVerticalSliderControl.GetTrackBounds(out CenterX, TrackTop,
  TrackBottom: Integer): Boolean;
var
  ThumbRadius: Integer;
begin
  CenterX := ClientWidth div 2;
  ThumbRadius := SliderScale(FThumbRadius, CurrentPPI);
  TrackTop := ThumbRadius + SliderScale(TRACK_MARGIN, CurrentPPI);
  TrackBottom := ClientHeight - GetFooterHeight - ThumbRadius -
    SliderScale(TRACK_MARGIN, CurrentPPI);
  if TrackBottom < TrackTop then TrackBottom := TrackTop;
  Result := TrackBottom > TrackTop;
end;

function TVerticalSliderControl.GetFooterHeight: Integer;
begin
  Result := 0; if FShowCaption then Result := SliderScale(CAPTION_HEIGHT, CurrentPPI);
  if FShowValue then Inc(Result, SliderScale(VALUE_HEIGHT, CurrentPPI));
end;

function TVerticalSliderControl.GetValueText: string;
var
  FormatMask: string;
begin
  FormatMask := '0';
  if FDecimals > 0 then
    FormatMask := FormatMask + '.' + StringOfChar('0', FDecimals);
  Result := FormatFloat(FormatMask, FPosition);
end;

procedure TVerticalSliderControl.LayoutValueEdit;
const
  EDIT_MARGIN = 2;
var
  EditMargin: Integer;
  ValueHeight: Integer;
begin
  if not FShowValue or not Assigned(FEdit) or not HandleAllocated then Exit;
  EditMargin := SliderScale(EDIT_MARGIN, CurrentPPI);
  ValueHeight := SliderScale(VALUE_HEIGHT, CurrentPPI);
  FEdit.SetBounds(EditMargin, ClientHeight - ValueHeight,
    Max(ClientWidth - EditMargin * 2, 1), ValueHeight);
end;

procedure TVerticalSliderControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  CenterX: Integer;
  HitRadius: Integer;
  ThumbRadius: Integer;
  ThumbY: Integer;
  TrackBottom: Integer;
  TrackTop: Integer;
begin
  inherited;
  if Button <> mbLeft then Exit;
  if FShowValue and
    (Y >= ClientHeight - SliderScale(VALUE_HEIGHT, CurrentPPI)) then
  begin
    BeginValueEdit;
    Exit;
  end;
  if CanFocus then SetFocus;
  if not GetTrackBounds(CenterX, TrackTop, TrackBottom) then Exit;

  ThumbY := PositionToY(TrackTop, TrackBottom);
  ThumbRadius := SliderScale(FThumbRadius, CurrentPPI);
  HitRadius := ThumbRadius + SliderScale(3, CurrentPPI);
  if Sqr(X - CenterX) + Sqr(Y - ThumbY) <= Sqr(HitRadius) then
  begin
    FDragging := True;
    MouseCapture := True;
  end
  else if (Abs(X - CenterX) <=
    SliderScale(TRACK_HIT_RADIUS, CurrentPPI)) and
    InRange(Y, TrackTop, TrackBottom) and (Y < ThumbY) then
    ChangePosition(FLargeChange)
  else if (Abs(X - CenterX) <=
    SliderScale(TRACK_HIT_RADIUS, CurrentPPI)) and
    InRange(Y, TrackTop, TrackBottom) and (Y > ThumbY) then
    ChangePosition(-FLargeChange);
end;

procedure TVerticalSliderControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  CenterX: Integer;
  TrackBottom: Integer;
  TrackTop: Integer;
begin
  inherited;
  if not FDragging then Exit;
  if GetTrackBounds(CenterX, TrackTop, TrackBottom) then
    SetPosition(SnapValue(YToPosition(Y, TrackTop, TrackBottom)));
end;

procedure TVerticalSliderControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbRight then
  begin
    if Assigned(FOnRightClick) then FOnRightClick(Self);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  FDragging := False;
  MouseCapture := False;
end;

procedure TVerticalSliderControl.Paint;
var
  CaptionRect: TRect;
  CenterX: Integer;
  ThumbY: Integer;
  TrackBottom: Integer;
  TrackTop: Integer;
  ThumbRadius: Integer;
  ValueString: string;
  ValueRect: TRect;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  GetTrackBounds(CenterX, TrackTop, TrackBottom);
  ThumbY := PositionToY(TrackTop, TrackBottom);

  Canvas.Pen.Width := Max(SliderScale(FTrackWidth, CurrentPPI), 1);
  Canvas.Pen.Color := FUpperTrackColor;
  Canvas.MoveTo(CenterX, TrackTop);
  Canvas.LineTo(CenterX, ThumbY + 1);
  Canvas.Pen.Color := FTrackColor;
  Canvas.MoveTo(CenterX, ThumbY);
  Canvas.LineTo(CenterX, TrackBottom + 1);

  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := FThumbColor;
  ThumbRadius := SliderScale(FThumbRadius, CurrentPPI);
  Canvas.Ellipse(CenterX - ThumbRadius, ThumbY - ThumbRadius,
    CenterX + ThumbRadius + 1, ThumbY + ThumbRadius + 1);
  Canvas.Pen.Style := psSolid;

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  // VOICEVOX入力上段と同じ14px基準で、DPIに比例して文字を拡縮する。
  Canvas.Font.Height := -SliderScale(14, CurrentPPI);
  Canvas.Font.Color := FTextColor;
  if FShowCaption then begin
  CaptionRect := Rect(0, ClientHeight - GetFooterHeight, ClientWidth,
    ClientHeight - IfThen(FShowValue,
      SliderScale(VALUE_HEIGHT, CurrentPPI), 0));
  DrawText(Canvas.Handle, PChar(FCaption), -1, CaptionRect,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  end;

  if FShowValue then
  begin
    Canvas.Font.Height := -SliderScale(14, CurrentPPI);
    ValueRect := Rect(0,
      ClientHeight - SliderScale(VALUE_HEIGHT, CurrentPPI), ClientWidth,
      ClientHeight);
    ValueString := GetValueText;
    DrawText(Canvas.Handle, PChar(ValueString), -1, ValueRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  end;
end;

procedure TVerticalSliderControl.Resize;
begin
  inherited;
  LayoutValueEdit;
end;

function TVerticalSliderControl.PositionToY(const TrackTop,
  TrackBottom: Integer): Integer;
var
  PositionRatio: Double;
begin
  if FMaximum > FMinimum then
    PositionRatio := (EnsureRange(FPosition, FMinimum, FMaximum) - FMinimum) /
      (FMaximum - FMinimum)
  else
    PositionRatio := 0;
  Result := TrackBottom - Round(PositionRatio * (TrackBottom - TrackTop));
end;

function TVerticalSliderControl.SnapValue(const Value: Double): Double;
begin
  if FSmallChange > 0 then
    Result := FMinimum + Round((Value - FMinimum) / FSmallChange) * FSmallChange
  else
    Result := Value;
  if FMaximum >= FMinimum then
    Result := EnsureRange(Result, FMinimum, FMaximum);
end;

procedure TVerticalSliderControl.SetBackColor(const Value: TColor);
begin
  if FBackColor = Value then Exit;
  FBackColor := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetCaption(const Value: string);
begin
  if FCaption = Value then Exit;
  FCaption := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetDecimals(const Value: Integer);
begin
  if FDecimals = Value then Exit;
  FDecimals := EnsureRange(Value, 0, 8);
  Invalidate;
end;

procedure TVerticalSliderControl.SetEditBackColor(const Value: TColor);
begin
  if FEditBackColor = Value then Exit;
  FEditBackColor := Value;
  FEdit.Color := Value;
end;

procedure TVerticalSliderControl.SetEditTextColor(const Value: TColor);
begin
  if FEditTextColor = Value then Exit;
  FEditTextColor := Value;
  FEdit.Font.Color := Value;
end;

procedure TVerticalSliderControl.SetLargeChange(const Value: Double);
begin
  if SameValue(FLargeChange, Value) then Exit;
  FLargeChange := Max(Value, 0);
end;

procedure TVerticalSliderControl.SetMaximum(const Value: Double);
begin
  if SameValue(FMaximum, Value) then Exit;
  FMaximum := Value;
  SetPosition(FPosition);
  Invalidate;
end;

procedure TVerticalSliderControl.SetMinimum(const Value: Double);
begin
  if SameValue(FMinimum, Value) then Exit;
  FMinimum := Value;
  SetPosition(FPosition);
  Invalidate;
end;

procedure TVerticalSliderControl.SetPosition(const Value: Double);
var
  NewValue: Double;
begin
  if FMaximum >= FMinimum then
    NewValue := EnsureRange(Value, FMinimum, FMaximum)
  else
    NewValue := Value;
  if SameValue(FPosition, NewValue) then Exit;
  FPosition := NewValue;
  Invalidate;
  DoChange;
end;

procedure TVerticalSliderControl.SetSmallChange(const Value: Double);
begin
  if SameValue(FSmallChange, Value) then Exit;
  FSmallChange := Max(Value, 0);
end;

procedure TVerticalSliderControl.SetShowValue(const Value: Boolean);
begin
  if FShowValue = Value then Exit;
  FShowValue := Value;
  if not FShowValue then FEdit.Visible := False;
  LayoutValueEdit;
  Invalidate;
end;

procedure TVerticalSliderControl.SetShowCaption(const Value: Boolean);
begin
  if FShowCaption=Value then Exit; FShowCaption := Value;
  LayoutValueEdit; Invalidate;
end;

procedure TVerticalSliderControl.SetTextColor(const Value: TColor);
begin
  if FTextColor = Value then Exit;
  FTextColor := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetThumbColor(const Value: TColor);
begin
  if FThumbColor = Value then Exit;
  FThumbColor := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetThumbRadius(const Value: Integer);
begin
  if FThumbRadius = Value then Exit;
  FThumbRadius := Max(Value, 1);
  Invalidate;
end;

procedure TVerticalSliderControl.SetTrackColor(const Value: TColor);
begin
  if FTrackColor = Value then Exit;
  FTrackColor := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetTrackWidth(const Value: Integer);
begin
  if FTrackWidth = Value then Exit;
  FTrackWidth := Max(Value, 1);
  Invalidate;
end;

procedure TVerticalSliderControl.SetUpperTrackColor(const Value: TColor);
begin
  if FUpperTrackColor = Value then Exit;
  FUpperTrackColor := Value;
  Invalidate;
end;

procedure TVerticalSliderControl.SetWheelChangesPosition(
  const Value: Boolean);
begin
  FWheelChangesPosition := Value;
end;

function TVerticalSliderControl.YToPosition(const Y, TrackTop,
  TrackBottom: Integer): Double;
var
  PositionRatio: Double;
begin
  if (TrackBottom <= TrackTop) or (FMaximum <= FMinimum) then
    Exit(FMinimum);
  PositionRatio := (TrackBottom - EnsureRange(Y, TrackTop, TrackBottom)) /
    (TrackBottom - TrackTop);
  Result := FMinimum + PositionRatio * (FMaximum - FMinimum);
end;

end.
