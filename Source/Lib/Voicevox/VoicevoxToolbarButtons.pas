// VOICEVOXの設定ページ選択と確認再生を行う、専用グリフ付き小型ツールバーを提供する。
unit VoicevoxToolbarButtons;

interface

uses
  Winapi.Messages, System.Classes, System.Generics.Collections, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics;

type
  // ツールバーと設定フレームで共有する5種類のページ識別子。
  TVoicevoxToolbarPage = (vtpAccent, vtpIntonation, vtpLength,
    vtpShortcuts, vtpAudioSettings);
  // 排他的なページ選択と、ページを切り替えない再生操作を描き分ける。
  TVoicevoxToolbarButtonKind = (vbkPage, vbkPreview, vbkSend, vbkClose,
    vbkMoveEnd);

  TVoicevoxToolbarButton = class;
  TVoicevoxToolbarSelectEvent = procedure(Sender: TObject;
    const Page: TVoicevoxToolbarPage) of object;

  // 設定ページまたは確認再生のグリフを描画し、ホバー・押下状態を保持するボタン。
  TVoicevoxToolbarButton = class(TCustomControl)
  private
    FBackgroundColor: TColor;
    FCheckedColor: TColor;
    FFontColor: TColor;
    FHot: Boolean;
    FHotColor: TColor;
    FKind: TVoicevoxToolbarButtonKind;
    FOnExecute: TNotifyEvent;
    FOnSelect: TVoicevoxToolbarSelectEvent;
    FPage: TVoicevoxToolbarPage;
    FPressed: Boolean;
    FPressedColor: TColor;
    FPreviewActive: Boolean;
    FSelected: Boolean;
    procedure SetBackgroundColor(const Value: TColor);
    procedure SetCheckedColor(const Value: TColor);
    procedure SetFontColor(const Value: TColor);
    procedure SetHotColor(const Value: TColor);
    procedure SetPressedColor(const Value: TColor);
    procedure SetSelected(const Value: Boolean);
  protected
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    // Pageに対応するグリフを持つ、キーボード操作可能なボタンを生成する。
    constructor CreatePage(AOwner: TComponent;
      const Page: TVoicevoxToolbarPage); reintroduce;
    // ページを切り替えず、確認再生または停止だけを要求するボタンを生成する。
    constructor CreatePreview(AOwner: TComponent); reintroduce;
    // ページを切り替えず、現在のセリフの送信だけを要求するボタンを生成する。
    class function NewSend(AOwner: TComponent): TVoicevoxToolbarButton; static;
    // 入力パネルを閉じるための×印を持つ操作ボタンを生成する。
    class function NewClose(AOwner: TComponent): TVoicevoxToolbarButton; static;
    // セリフ一覧の終了位置へ移動する右向き矢印ボタンを生成する。
    class function NewMoveEnd(AOwner: TComponent): TVoicevoxToolbarButton; static;
    // 選択要求をマウス操作と同じ経路で通知する。
    procedure Execute;
    // 現在選択中の設定ページを表す場合にTrue。
    property Selected: Boolean read FSelected write SetSelected;
    property OnExecute: TNotifyEvent read FOnExecute write FOnExecute;
    property OnSelect: TVoicevoxToolbarSelectEvent read FOnSelect
      write FOnSelect;
  end;

  // 5つのページボタンと右端の再生・送信ボタンを管理し、各操作を呼び出し元へ通知する。
  TVoicevoxToolbarButtons = class(TCustomPanel)
  private
    FActivePage: TVoicevoxToolbarPage;
    FBackgroundColor: TColor;
    FButtons: TObjectList<TVoicevoxToolbarButton>;
    FCheckedColor: TColor;
    FFontColor: TColor;
    FHotColor: TColor;
    FLayouting: Boolean;
    FOnClose: TNotifyEvent;
    FOnMoveEnd: TNotifyEvent;
    FOnPreview: TNotifyEvent;
    FOnSend: TNotifyEvent;
    FOnPageSelected: TVoicevoxToolbarSelectEvent;
    FPressedColor: TColor;
    FPreviewButton: TVoicevoxToolbarButton;
    FSendButton: TVoicevoxToolbarButton;
    FMoveEndButton: TVoicevoxToolbarButton;
    FCloseButton: TVoicevoxToolbarButton;
    procedure ButtonClose(Sender: TObject);
    procedure ButtonMoveEnd(Sender: TObject);
    procedure ButtonPreview(Sender: TObject);
    procedure ButtonSend(Sender: TObject);
    procedure ButtonSelect(Sender: TObject;
      const Page: TVoicevoxToolbarPage);
    procedure LayoutButtons;
    procedure SetBackgroundColor(const Value: TColor);
    procedure SetCheckedColor(const Value: TColor);
    procedure SetFontColor(const Value: TColor);
    procedure SetHotColor(const Value: TColor);
    procedure SetPressedColor(const Value: TColor);
    procedure UpdateButtonColors;
    procedure UpdateSelection;
  protected
    procedure Resize; override;
  public
    // 5つの設定ページと確認再生を左から順に生成し、アクセントを初期選択する。
    constructor Create(AOwner: TComponent); override;
    // 所有するボタン一覧を解放する。各ボタン自体はVCLの所有関係で破棄される。
    destructor Destroy; override;
    // ボタン寸法と配置を現在のモニターDPIに合わせて再計算する。
    procedure ApplyDpi;
    // 台本工程では調整ページと試聴だけを表示し、閉じる・送信・重複案内を除く。
    procedure UseAdjustmentOnly;
    // 指定ページを選択する。Notify=Falseならページ選択イベントを通知しない。
    procedure Activate(const Page: TVoicevoxToolbarPage;
      const Notify: Boolean = True);
    // 再生ボタンを停止マークと選択色へ切り替える。
    procedure SetPreviewActive(const Value: Boolean);
    property ActivePage: TVoicevoxToolbarPage read FActivePage;
    property BackgroundColor: TColor read FBackgroundColor
      write SetBackgroundColor;
    property CheckedColor: TColor read FCheckedColor write SetCheckedColor;
    property FontColor: TColor read FFontColor write SetFontColor;
    property HotColor: TColor read FHotColor write SetHotColor;
    property PressedColor: TColor read FPressedColor write SetPressedColor;
    property OnPageSelected: TVoicevoxToolbarSelectEvent
      read FOnPageSelected write FOnPageSelected;
    // 左端の×ボタンが押されたとき、入力パネルを閉じるよう通知する。
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    // 送信右側の終了位置移動ボタンが押されたとき通知する。
    property OnMoveEnd: TNotifyEvent read FOnMoveEnd write FOnMoveEnd;
    // 右端の再生／停止ボタンが押されたとき、ページを変更せず通知する。
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
    // 再生ボタン右側の送信ボタンが押されたとき、ページを変更せず通知する。
    property OnSend: TNotifyEvent read FOnSend write FOnSend;
  end;

implementation

uses
  Winapi.Windows, System.Math;

const
  BUTTON_SIZE = 30;
  CLOSE_GLYPH_COLOR = $005050E8;
  PREVIEW_GLYPH_COLOR = $0066D080;
  SEND_GLYPH_COLOR = $00F0B060;

{ TVoicevoxToolbarButton }

constructor TVoicevoxToolbarButton.CreatePage(AOwner: TComponent;
  const Page: TVoicevoxToolbarPage);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csClickEvents, csCaptureMouse];
  FBackgroundColor := clBtnFace;
  FCheckedColor := clHighlight;
  FFontColor := clWindowText;
  FHotColor := clBtnHighlight;
  FKind := vbkPage;
  FPage := Page;
  FPressedColor := clBtnShadow;
  Height := BUTTON_SIZE;
  Width := BUTTON_SIZE;
  ParentShowHint := False;
  ShowHint := True;
  TabStop := True;
end;

constructor TVoicevoxToolbarButton.CreatePreview(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csClickEvents, csCaptureMouse];
  FBackgroundColor := clBtnFace;
  FCheckedColor := clHighlight;
  FFontColor := clWindowText;
  FHotColor := clBtnHighlight;
  FKind := vbkPreview;
  FPressedColor := clBtnShadow;
  Height := BUTTON_SIZE;
  Width := BUTTON_SIZE;
  ParentShowHint := False;
  ShowHint := True;
  TabStop := True;
end;

class function TVoicevoxToolbarButton.NewSend(
  AOwner: TComponent): TVoicevoxToolbarButton;
begin
  Result := TVoicevoxToolbarButton.CreatePreview(AOwner);
  Result.FKind := vbkSend;
end;

class function TVoicevoxToolbarButton.NewClose(
  AOwner: TComponent): TVoicevoxToolbarButton;
begin
  Result := TVoicevoxToolbarButton.CreatePreview(AOwner);
  Result.FKind := vbkClose;
end;

class function TVoicevoxToolbarButton.NewMoveEnd(
  AOwner: TComponent): TVoicevoxToolbarButton;
begin
  Result := TVoicevoxToolbarButton.CreatePreview(AOwner);
  Result.FKind := vbkMoveEnd;
end;

procedure TVoicevoxToolbarButton.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  if FHot then Exit;
  FHot := True;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if not FHot then Exit;
  FHot := False;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.Execute;
begin
  if not Enabled then Exit;
  if FKind in [vbkPreview, vbkSend, vbkClose, vbkMoveEnd] then
  begin
    if Assigned(FOnExecute) then FOnExecute(Self);
  end
  else if Assigned(FOnSelect) then
    FOnSelect(Self, FPage);
end;

procedure TVoicevoxToolbarButton.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  inherited;
  if Enabled and (Key in [VK_SPACE, VK_RETURN]) then
  begin
    Key := 0;
    Execute;
  end;
end;

procedure TVoicevoxToolbarButton.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not Enabled then Exit;
  SetFocus;
  FPressed := True;
  MouseCapture := True;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  RequestSelection: Boolean;
begin
  inherited;
  if (Button <> mbLeft) or not FPressed then Exit;
  RequestSelection := Enabled and PtInRect(ClientRect, Point(X, Y));
  FPressed := False;
  MouseCapture := False;
  Invalidate;
  if RequestSelection then Execute;
end;

procedure TVoicevoxToolbarButton.Paint;
var
  Angle: Double;
  BackColor: TColor;
  CenterX: Integer;
  CenterY: Integer;
  GearPoints: array[0..15] of TPoint;
  GlyphColor: TColor;
  I: Integer;
  R: Integer;
  Radius: Integer;

  function GlyphScale(const Value: Integer): Integer;
  begin
    // ボタン外形よりグリフを一回り小さくし、200%でも詰まって見えないようにする。
    Result := MulDiv(Value, Min(ClientWidth, ClientHeight) * 4,
      BUTTON_SIZE * 5);
  end;

  procedure Dot(const X, Y: Integer);
  begin
    Canvas.Brush.Color := FFontColor;
    Canvas.Ellipse(X - R, Y - R, X + R + 1, Y + R + 1);
  end;

begin
  if FPressed then
    BackColor := FPressedColor
  else if FSelected then
    BackColor := FCheckedColor
  else if FHot then
    BackColor := FHotColor
  else
    BackColor := FBackgroundColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := BackColor;
  Canvas.Pen.Color := BackColor;
  Canvas.Rectangle(ClientRect);

  CenterX := ClientWidth div 2;
  CenterY := ClientHeight div 2;
  R := Max(2, Min(ClientWidth, ClientHeight) div 14);
  case FKind of
    vbkClose: GlyphColor := CLOSE_GLYPH_COLOR;
    vbkPreview: GlyphColor := PREVIEW_GLYPH_COLOR;
    vbkSend, vbkMoveEnd: GlyphColor := SEND_GLYPH_COLOR;
  else
    GlyphColor := FFontColor;
  end;
  Canvas.Pen.Color := GlyphColor;
  Canvas.Pen.Width := Max(1, Min(ClientWidth, ClientHeight) div 16);
  Canvas.Brush.Color := GlyphColor;
  if FKind = vbkClose then
  begin
    Canvas.Pen.Width := Max(1, GlyphScale(2));
    Canvas.MoveTo(CenterX - GlyphScale(7), CenterY - GlyphScale(7));
    Canvas.LineTo(CenterX + GlyphScale(7), CenterY + GlyphScale(7));
    Canvas.MoveTo(CenterX + GlyphScale(7), CenterY - GlyphScale(7));
    Canvas.LineTo(CenterX - GlyphScale(7), CenterY + GlyphScale(7));
  end
  else if FKind = vbkPreview then
  begin
    if FPreviewActive then
      Canvas.Rectangle(CenterX - GlyphScale(5), CenterY - GlyphScale(5),
        CenterX + GlyphScale(6), CenterY + GlyphScale(6))
    else
      Canvas.Polygon([Point(CenterX - GlyphScale(5),
        CenterY - GlyphScale(8)), Point(CenterX - GlyphScale(5),
        CenterY + GlyphScale(8)), Point(CenterX + GlyphScale(8), CenterY)]);
  end
  else if FKind = vbkSend then
  begin
    // 送信操作を直感的に示す、右上へ飛ぶ紙飛行機の輪郭と折り目を描く。
    Canvas.Pen.Width := Max(1, GlyphScale(2));
    Canvas.Brush.Style := bsClear;
    Canvas.Polygon([
      Point(CenterX - GlyphScale(10), CenterY - GlyphScale(3)),
      Point(CenterX + GlyphScale(10), CenterY - GlyphScale(9)),
      Point(CenterX + GlyphScale(4), CenterY + GlyphScale(10)),
      Point(CenterX - GlyphScale(1), CenterY + GlyphScale(2))]);
    Canvas.MoveTo(CenterX - GlyphScale(10), CenterY - GlyphScale(3));
    Canvas.LineTo(CenterX - GlyphScale(1), CenterY + GlyphScale(2));
    Canvas.LineTo(CenterX + GlyphScale(10), CenterY - GlyphScale(9));
    Canvas.Brush.Style := bsSolid;
  end
  else if FKind = vbkMoveEnd then
  begin
    // 旧送信アイコンを再利用し、右向き矢印と終了位置の縦線を描く。
    Canvas.Pen.Width := Max(1, GlyphScale(2));
    Canvas.MoveTo(CenterX - GlyphScale(9), CenterY);
    Canvas.LineTo(CenterX + GlyphScale(5), CenterY);
    Canvas.MoveTo(CenterX + GlyphScale(5), CenterY);
    Canvas.LineTo(CenterX, CenterY - GlyphScale(5));
    Canvas.MoveTo(CenterX + GlyphScale(5), CenterY);
    Canvas.LineTo(CenterX, CenterY + GlyphScale(5));
    Canvas.Pen.Width := Max(1, GlyphScale(1));
    Canvas.MoveTo(CenterX + GlyphScale(9), CenterY - GlyphScale(8));
    Canvas.LineTo(CenterX + GlyphScale(9), CenterY + GlyphScale(8));
  end
  else case FPage of
    vtpAccent:
      begin
        Canvas.MoveTo(CenterX - GlyphScale(10), CenterY + GlyphScale(5));
        Canvas.LineTo(CenterX - GlyphScale(3), CenterY - GlyphScale(5));
        Canvas.LineTo(CenterX + GlyphScale(4), CenterY - GlyphScale(5));
        Canvas.LineTo(CenterX + GlyphScale(10), CenterY + GlyphScale(4));
        Dot(CenterX - GlyphScale(10), CenterY + GlyphScale(5));
        Dot(CenterX - GlyphScale(3), CenterY - GlyphScale(5));
        Dot(CenterX + GlyphScale(4), CenterY - GlyphScale(5));
        Dot(CenterX + GlyphScale(10), CenterY + GlyphScale(4));
      end;
    vtpIntonation:
      begin
        Canvas.Pen.Width := Max(1, GlyphScale(1));
        Canvas.MoveTo(CenterX - GlyphScale(8), CenterY - GlyphScale(9));
        Canvas.LineTo(CenterX - GlyphScale(8), CenterY + GlyphScale(10));
        Canvas.MoveTo(CenterX, CenterY - GlyphScale(9));
        Canvas.LineTo(CenterX, CenterY + GlyphScale(10));
        Canvas.MoveTo(CenterX + GlyphScale(8), CenterY - GlyphScale(9));
        Canvas.LineTo(CenterX + GlyphScale(8), CenterY + GlyphScale(10));
        Dot(CenterX - GlyphScale(8), CenterY + GlyphScale(3));
        Dot(CenterX, CenterY - GlyphScale(5));
        Dot(CenterX + GlyphScale(8), CenterY);
      end;
    vtpLength:
      begin
        Canvas.Pen.Width := Max(1, GlyphScale(1));
        Canvas.MoveTo(CenterX - GlyphScale(10), CenterY - GlyphScale(9));
        Canvas.LineTo(CenterX - GlyphScale(10), CenterY + GlyphScale(9));
        Canvas.MoveTo(CenterX + GlyphScale(10), CenterY - GlyphScale(9));
        Canvas.LineTo(CenterX + GlyphScale(10), CenterY + GlyphScale(9));
        Canvas.Pen.Width := Max(1, GlyphScale(2));
        Canvas.MoveTo(CenterX - GlyphScale(8), CenterY);
        Canvas.LineTo(CenterX + GlyphScale(8), CenterY);
        Canvas.MoveTo(CenterX - GlyphScale(8), CenterY);
        Canvas.LineTo(CenterX - GlyphScale(4), CenterY - GlyphScale(4));
        Canvas.MoveTo(CenterX - GlyphScale(8), CenterY);
        Canvas.LineTo(CenterX - GlyphScale(4), CenterY + GlyphScale(4));
        Canvas.MoveTo(CenterX + GlyphScale(8), CenterY);
        Canvas.LineTo(CenterX + GlyphScale(4), CenterY - GlyphScale(4));
        Canvas.MoveTo(CenterX + GlyphScale(8), CenterY);
        Canvas.LineTo(CenterX + GlyphScale(4), CenterY + GlyphScale(4));
      end;
    vtpShortcuts:
      begin
        // キーボードショートカットを表す、キー枠と稲妻を描く。
        Canvas.Pen.Width := Max(1, GlyphScale(1));
        Canvas.Brush.Style := bsClear;
        Canvas.RoundRect(CenterX - GlyphScale(10), CenterY - GlyphScale(8),
          CenterX + GlyphScale(10), CenterY + GlyphScale(8),
          GlyphScale(3), GlyphScale(3));
        Canvas.Brush.Style := bsSolid;
        Canvas.Polygon([
          Point(CenterX + GlyphScale(1), CenterY - GlyphScale(7)),
          Point(CenterX - GlyphScale(5), CenterY + GlyphScale(1)),
          Point(CenterX - GlyphScale(1), CenterY + GlyphScale(1)),
          Point(CenterX - GlyphScale(3), CenterY + GlyphScale(7)),
          Point(CenterX + GlyphScale(6), CenterY - GlyphScale(2)),
          Point(CenterX + GlyphScale(2), CenterY - GlyphScale(2))]);
      end;
    vtpAudioSettings:
      begin
        for I := 0 to High(GearPoints) do
        begin
          Angle := -Pi / 2 + I * Pi / 8;
          if Odd(I) then
            Radius := GlyphScale(7)
          else
            Radius := GlyphScale(11);
          GearPoints[I] := Point(CenterX + Round(Cos(Angle) * Radius),
            CenterY + Round(Sin(Angle) * Radius));
        end;
        Canvas.Pen.Width := Max(1, GlyphScale(1));
        Canvas.Pen.Color := FFontColor;
        Canvas.Brush.Color := FFontColor;
        Canvas.Polygon(GearPoints);
        Canvas.Pen.Color := BackColor;
        Canvas.Brush.Color := BackColor;
        Canvas.Ellipse(CenterX - GlyphScale(3), CenterY - GlyphScale(3),
          CenterX + GlyphScale(4), CenterY + GlyphScale(4));
      end;
  end;
  Canvas.Pen.Width := Max(1, GlyphScale(1));
  if Focused then DrawFocusRect(Canvas.Handle,
    Rect(GlyphScale(2), GlyphScale(2), ClientWidth - GlyphScale(2),
      ClientHeight - GlyphScale(2)));
end;

procedure TVoicevoxToolbarButton.SetBackgroundColor(const Value: TColor);
begin
  if FBackgroundColor = Value then Exit;
  FBackgroundColor := Value;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.SetCheckedColor(const Value: TColor);
begin
  if FCheckedColor = Value then Exit;
  FCheckedColor := Value;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.SetFontColor(const Value: TColor);
begin
  if FFontColor = Value then Exit;
  FFontColor := Value;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.SetHotColor(const Value: TColor);
begin
  if FHotColor = Value then Exit;
  FHotColor := Value;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.SetPressedColor(const Value: TColor);
begin
  if FPressedColor = Value then Exit;
  FPressedColor := Value;
  Invalidate;
end;

procedure TVoicevoxToolbarButton.SetSelected(const Value: Boolean);
begin
  if FSelected = Value then Exit;
  FSelected := Value;
  Invalidate;
end;

{ TVoicevoxToolbarButtons }

constructor TVoicevoxToolbarButtons.Create(AOwner: TComponent);
const
  HINTS: array[TVoicevoxToolbarPage] of string = (
    'アクセント', 'イントネーション', '長さ', 'ショートカット', '音声設定');
var
  Button: TVoicevoxToolbarButton;
  Page: TVoicevoxToolbarPage;
begin
  inherited;
  ControlStyle := ControlStyle - [csSetCaption]; Caption := '';
  BevelOuter := bvNone;
  ParentBackground := False;
  Height := BUTTON_SIZE;
  FBackgroundColor := clBtnFace;
  FCheckedColor := clHighlight;
  FFontColor := clWindowText;
  FHotColor := clBtnHighlight;
  FPressedColor := clBtnShadow;
  FActivePage := vtpAccent;
  FButtons := TObjectList<TVoicevoxToolbarButton>.Create(False);
  FCloseButton := TVoicevoxToolbarButton.NewClose(Self);
  FCloseButton.Parent := Self;
  FCloseButton.Left := 0;
  FCloseButton.Top := 0;
  FCloseButton.Hint := '入力を閉じる';
  FCloseButton.OnExecute := ButtonClose;
  FButtons.Add(FCloseButton);
  for Page := Low(TVoicevoxToolbarPage) to High(TVoicevoxToolbarPage) do
  begin
    Button := TVoicevoxToolbarButton.CreatePage(Self, Page);
    Button.Parent := Self;
    Button.Left := (Ord(Page) + 1) * BUTTON_SIZE;
    Button.Top := 0;
    Button.Hint := HINTS[Page];
    Button.OnSelect := ButtonSelect;
    FButtons.Add(Button);
  end;
  FPreviewButton := TVoicevoxToolbarButton.CreatePreview(Self);
  FPreviewButton.Parent := Self;
  FPreviewButton.Left := (Ord(High(TVoicevoxToolbarPage)) + 2) * BUTTON_SIZE;
  FPreviewButton.Top := 0;
  FPreviewButton.Hint := '再生 (F5)';
  FPreviewButton.OnExecute := ButtonPreview;
  FButtons.Add(FPreviewButton);
  FSendButton := TVoicevoxToolbarButton.NewSend(Self);
  FSendButton.Parent := Self;
  FSendButton.Left := (Ord(High(TVoicevoxToolbarPage)) + 3) * BUTTON_SIZE;
  FSendButton.Top := 0;
  FSendButton.Hint := '入力完了 (Ctrl+Enter / Esc)';
  FSendButton.OnExecute := ButtonSend;
  FButtons.Add(FSendButton);
  FMoveEndButton := TVoicevoxToolbarButton.NewMoveEnd(Self);
  FMoveEndButton.Parent := Self;
  FMoveEndButton.Left := (Ord(High(TVoicevoxToolbarPage)) + 4) * BUTTON_SIZE;
  FMoveEndButton.Top := 0;
  FMoveEndButton.Hint := '終了位置へ移動';
  FMoveEndButton.OnExecute := ButtonMoveEnd;
  FButtons.Add(FMoveEndButton);
  UpdateButtonColors;
  UpdateSelection;
  ApplyDpi;
end;

procedure TVoicevoxToolbarButtons.ApplyDpi;
begin
  LayoutButtons;
end;

procedure TVoicevoxToolbarButtons.LayoutButtons;
var
  AvailableWidth: Integer;
  Button: TVoicevoxToolbarButton;
  ButtonSize: Integer;
  ButtonsPerRow: Integer;
  I, VisibleCount, Position: Integer;
  RowCount: Integer;
begin
  if FLayouting or not Assigned(FButtons) or (FButtons.Count = 0) then Exit;
  FLayouting := True;
  try
    ButtonSize := MulDiv(BUTTON_SIZE, CurrentPPI, 96);
    // 親へ接続される前のコンストラクタからも呼ばれるため、ハンドルを要求する
    // ClientWidthではなく、生成途中でも参照できるWidthを使う。
    AvailableWidth := Max(Width, ButtonSize);
    VisibleCount := 0; for Button in FButtons do if Button.Visible then Inc(VisibleCount);
    if VisibleCount=0 then Exit;
    ButtonsPerRow := EnsureRange(AvailableWidth div ButtonSize, 1,
      VisibleCount);
    RowCount := (VisibleCount + ButtonsPerRow - 1) div ButtonsPerRow;
    Position := 0;
    for I := 0 to FButtons.Count - 1 do
    begin
      Button := FButtons[I];
      if not Button.Visible then Continue;
      Button.SetBounds((Position mod ButtonsPerRow) * ButtonSize,
        (Position div ButtonsPerRow) * ButtonSize, ButtonSize, ButtonSize);
      Inc(Position);
      Button.Invalidate;
    end;
    if Height <> RowCount * ButtonSize then Height := RowCount * ButtonSize;
  finally
    FLayouting := False;
  end;
end;

procedure TVoicevoxToolbarButtons.UseAdjustmentOnly;
begin
  for var Button in FButtons do begin
    Button.Visible := (Button.FKind=vbkPreview) or ((Button.FKind=vbkPage) and (Button.FPage in [vtpAccent,vtpAudioSettings]));
    if (Button.FKind=vbkPage) and (Button.FPage=vtpAccent) then Button.Hint := 'アクセント・音高・音素長';
  end;
  if not (FActivePage in [vtpAccent,vtpAudioSettings]) then Activate(vtpAccent);
  LayoutButtons;
end;

procedure TVoicevoxToolbarButtons.ButtonPreview(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

procedure TVoicevoxToolbarButtons.ButtonClose(Sender: TObject);
begin
  if Assigned(FOnClose) then FOnClose(Self);
end;

procedure TVoicevoxToolbarButtons.ButtonMoveEnd(Sender: TObject);
begin
  if Assigned(FOnMoveEnd) then FOnMoveEnd(Self);
end;

procedure TVoicevoxToolbarButtons.ButtonSend(Sender: TObject);
begin
  if Assigned(FOnSend) then FOnSend(Self);
end;

destructor TVoicevoxToolbarButtons.Destroy;
begin
  FButtons.Free;
  inherited;
end;

procedure TVoicevoxToolbarButtons.Resize;
begin
  inherited;
  LayoutButtons;
end;

procedure TVoicevoxToolbarButtons.Activate(
  const Page: TVoicevoxToolbarPage; const Notify: Boolean);
begin
  FActivePage := Page;
  UpdateSelection;
  if Notify and Assigned(FOnPageSelected) then
    FOnPageSelected(Self, Page);
end;

procedure TVoicevoxToolbarButtons.ButtonSelect(Sender: TObject;
  const Page: TVoicevoxToolbarPage);
begin
  Activate(Page);
end;

procedure TVoicevoxToolbarButtons.SetBackgroundColor(const Value: TColor);
begin
  if FBackgroundColor = Value then Exit;
  FBackgroundColor := Value;
  Color := Value;
  UpdateButtonColors;
end;

procedure TVoicevoxToolbarButtons.SetCheckedColor(const Value: TColor);
begin
  if FCheckedColor = Value then Exit;
  FCheckedColor := Value;
  UpdateButtonColors;
end;

procedure TVoicevoxToolbarButtons.SetFontColor(const Value: TColor);
begin
  if FFontColor = Value then Exit;
  FFontColor := Value;
  UpdateButtonColors;
end;

procedure TVoicevoxToolbarButtons.SetHotColor(const Value: TColor);
begin
  if FHotColor = Value then Exit;
  FHotColor := Value;
  UpdateButtonColors;
end;

procedure TVoicevoxToolbarButtons.SetPressedColor(const Value: TColor);
begin
  if FPressedColor = Value then Exit;
  FPressedColor := Value;
  UpdateButtonColors;
end;

procedure TVoicevoxToolbarButtons.SetPreviewActive(const Value: Boolean);
begin
  if not Assigned(FPreviewButton) or
    (FPreviewButton.FPreviewActive = Value) then Exit;
  FPreviewButton.FPreviewActive := Value;
  FPreviewButton.Selected := Value;
  if Value then FPreviewButton.Hint := '停止 (F5)'
  else FPreviewButton.Hint := '再生 (F5)';
  FPreviewButton.Invalidate;
end;

procedure TVoicevoxToolbarButtons.UpdateButtonColors;
var
  Button: TVoicevoxToolbarButton;
begin
  for Button in FButtons do
  begin
    Button.FBackgroundColor := FBackgroundColor;
    Button.FCheckedColor := FCheckedColor;
    Button.FFontColor := FFontColor;
    Button.FHotColor := FHotColor;
    Button.FPressedColor := FPressedColor;
    Button.Invalidate;
  end;
end;

procedure TVoicevoxToolbarButtons.UpdateSelection;
var
  Button: TVoicevoxToolbarButton;
begin
  for Button in FButtons do
    if Button.FKind = vbkPage then
      Button.Selected := Button.FPage = FActivePage;
end;

end.
