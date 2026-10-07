// 編集中のVOICEVOXセリフについて、アクセント句のモーラと高低線だけを表示する。
unit SerifVoicevoxAccentView;

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.SysUtils, System.Types,
  System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls,
  HorizontalScrollBarControl, RigmVoicevoxUiWorker;

type
  // 描画と編集に必要な、audio_query内の1モーラ分の位置・アクセント情報。
  TSerifVoicevoxAccentMora = record
    // 所属するアクセント句のアクセント核位置。先頭を1とする。
    Accent: Integer;
    // 画面下部へ表示するモーラ表記。
    Text: string;
    // アクセント線を上段へ描画するモーラならTrue。
    High: Boolean;
    // audio_query全体を通したモーラ位置。
    MoraIndex: Integer;
    // accent_phrases配列内の所属位置。
    PhraseIndex: Integer;
    // 所属するアクセント句のモーラ総数。
    PhraseMoraCount: Integer;
    // アクセント句の先頭・末尾を表し、線の接続と編集範囲に使用する。
    PhraseStart: Boolean;
    PhraseEnd: Boolean;
  end;

  TSerifVoicevoxAccentPositionEvent = procedure(Sender: TObject;
    const PhraseIndex, Accent: Integer) of object;
  TSerifVoicevoxAccentQueryEvent = procedure(Sender: TObject;
    const QueryJson: string) of object;
  TSerifVoicevoxReadingEvent = procedure(Sender: TObject;
    const PhraseIndex: Integer; const Reading: string) of object;
  TSerifVoicevoxAccentBoundaryEvent = procedure(Sender: TObject;
    const MoraArrayIndex: Integer; const Connect: Boolean) of object;
  TSerifVoicevoxAccentErrorEvent = procedure(Sender: TObject;
    const ErrorMessage: string) of object;

  TSerifVoicevoxAccentPaintControl = class(TCustomControl)
  private
    FDragging: Boolean;
    FDragPending: Boolean;
    FBoundaryPending: Integer;
    FEditReading: TEdit;
    FEditingPhraseIndex: Integer;
    FFinishingReadingEdit: Boolean;
    FMouseDownPoint: TPoint;
    FHoverBoundary: Integer;
    FMoras: TArray<TSerifVoicevoxAccentMora>;
    FOnAccentPosition: TSerifVoicevoxAccentPositionEvent;
    FOnBoundary: TSerifVoicevoxAccentBoundaryEvent;
    FOnPreview: TNotifyEvent;
    FOnReading: TSerifVoicevoxReadingEvent;
    procedure ApplyDrag(const X, Y: Integer);
    function BoundaryAtPoint(const X, Y: Integer): Integer;
    procedure BeginReadingEdit(const PhraseIndex: Integer);
    procedure EditReadingExit(Sender: TObject);
    procedure EditReadingKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FinishReadingEdit(const Commit: Boolean);
    function GetContentWidth: Integer;
    function GetMoraCenter(const MoraArrayIndex: Integer;
      out Center: TPoint): Boolean;
    function MoraAtPoint(const X, Y: Integer): Integer;
    function MoraAtX(const X: Integer): Integer;
    function PhraseAtTextPoint(const X, Y: Integer): Integer;
    function PhraseBounds(const PhraseIndex: Integer): TRect;
    function PhraseReading(const PhraseIndex: Integer): string;
  protected
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // モーラ表示と編集中の読みを破棄する。
    procedure Clear;
    // 読みのインライン編集を確定せず閉じる。
    procedure CancelReadingEdit;
    procedure CommitReadingEdit;
    // audio_queryからアクセント句を読み取り、描画用のモーラ列へ反映する。
    procedure SetQueryJson(const QueryJson: string);
    function MoraCells: TArray<TRect>; // 実際に描くモーラの列範囲。下段の位置合わせにも使う。
    // 横スクロール範囲へ設定する、全モーラを描画可能な幅。
    property ContentWidth: Integer read GetContentWidth;
    property OnAccentPosition: TSerifVoicevoxAccentPositionEvent
      read FOnAccentPosition write FOnAccentPosition;
    property OnBoundary: TSerifVoicevoxAccentBoundaryEvent
      read FOnBoundary write FOnBoundary;
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
    property OnReading: TSerifVoicevoxReadingEvent
      read FOnReading write FOnReading;
  end;

  TSerifVoicevoxAccentView = class(TScrollBox)
  private const
    QUERY_DELAY_MS = 300;
    QUERY_COMPLETE_MESSAGE = WM_APP + $5722;
    READING_COMPLETE_MESSAGE = WM_APP + $5723;
  private
    FEngineUrl: string;
    FAnalysisUpdate: Boolean;
    FCurrentSpeakerId: Integer;
    FCurrentText: string;
    FHasDisplay: Boolean;
    FNotifyHandle: HWND;
    FOnChange: TSerifVoicevoxAccentQueryEvent;
    FOnError: TSerifVoicevoxAccentErrorEvent;
    FOnPreview: TNotifyEvent;
    FPaintControl: TSerifVoicevoxAccentPaintControl;
    FQueryJson: string;
    FQueryId: Cardinal;
    FQueryThread: TThread;
    FReadingId: Cardinal;
    FReadingPhraseIndex: Integer;
    FReadingRestartPending: Boolean;
    FReadingText: string;
    FReadingThread: TThread;
    FRestartPending: Boolean;
    FScrollBar: THorizontalScrollBarControl;
    FOnScrollChange: TNotifyEvent;
    FTimer: TTimer;
    FWheelRemainder: Integer;
    function GetReadingBusy: Boolean;
    function GetScrollPosition: Integer;
    procedure SetScrollPosition(Value: Integer);
    procedure QueryCompleteWindowProc(var Msg: TMessage);
    procedure AccentPosition(Sender: TObject; const PhraseIndex,
      Accent: Integer);
    procedure BoundaryChange(Sender: TObject; const MoraArrayIndex: Integer;
      const Connect: Boolean);
    function ApplyReading(const PhraseIndex: Integer;
      const AccentPhrasesJson: string): Boolean;
    procedure Preview(Sender: TObject);
    procedure Reading(Sender: TObject; const PhraseIndex: Integer;
      const ReadingText: string);
    procedure ReadingComplete(var Msg: TMessage);
    procedure ScrollPositionChange(Sender: TObject);
    procedure StartReadingQuery;
    procedure StartQuery;
    procedure TimerTimer(Sender: TObject);
    procedure UpdatePaintBounds;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // アクセント描画領域を現在のモニターDPIに合わせて再計算する。
    procedure ApplyDpi;
    // 編集中の本文とstyleを表示対象にする。空文字または未選択styleでは表示を消す。
    procedure ShowText(const Text: string; const SpeakerId: Integer;
      const QueryJson: string = '');
    function RequestFinish: Boolean;
    function MoraCells: TArray<TRect>;
    function ContentWidth: Integer;
    function EditableAt(const ScreenPoint: TPoint): Boolean;
    property ScrollPosition: Integer read GetScrollPosition write SetScrollPosition;
    property OnScrollChange: TNotifyEvent read FOnScrollChange write FOnScrollChange;
    property EngineUrl: string read FEngineUrl write FEngineUrl;
    property AnalysisUpdate: Boolean read FAnalysisUpdate;
    property OnChange: TSerifVoicevoxAccentQueryEvent read FOnChange write FOnChange;
    property OnError: TSerifVoicevoxAccentErrorEvent read FOnError write FOnError;
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
  end;

implementation

uses
  System.JSON, System.Math, AviUtl2StyleColors, SerifVoicevoxApi,
  SerifVoicevoxDebugLog;

const
  MORA_CELL_MIN_WIDTH = 28;
  MORA_CELL_TEXT_PADDING = 6;
  SCROLL_BAR_HEIGHT = 26;
  SCROLL_BAR_TOP_PADDING = 14;
  SCROLL_BAR_TRACK_COLOR = $002C4A66;
  SCROLL_BAR_THUMB_COLOR = $004691DA;

function AccentScale(const Value, Ppi: Integer): Integer;
begin
  Result := MulDiv(Value, Ppi, 96);
end;

type
  TSerifVoicevoxAccentQueryThread = class(TRigmVoicevoxUiWorker)
  private
    FErrorMessage: string;
    FNotifyHandle: HWND;
    FQueryId: Cardinal;
    FQueryJson: string;
    FSpeakerId: Integer;
    FSuccess: Boolean;
    FText: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const NotifyHandle: HWND; const QueryId: Cardinal;
      const Text: string; const SpeakerId: Integer);
    property ErrorMessage: string read FErrorMessage;
    property QueryId: Cardinal read FQueryId;
    property QueryJson: string read FQueryJson;
    property Success: Boolean read FSuccess;
  end;

  TSerifVoicevoxReadingQueryThread = class(TRigmVoicevoxUiWorker)
  private
    FAccentPhrasesJson: string;
    FErrorMessage: string;
    FNotifyHandle: HWND;
    FPhraseIndex: Integer;
    FReadingId: Cardinal;
    FReadingText: string;
    FSpeakerId: Integer;
    FSuccess: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const NotifyHandle: HWND; const ReadingId: Cardinal;
      const PhraseIndex: Integer; const ReadingText: string;
      const SpeakerId: Integer);
    property AccentPhrasesJson: string read FAccentPhrasesJson;
    property ErrorMessage: string read FErrorMessage;
    property PhraseIndex: Integer read FPhraseIndex;
    property ReadingId: Cardinal read FReadingId;
    property Success: Boolean read FSuccess;
  end;

constructor TSerifVoicevoxAccentPaintControl.Create(AOwner: TComponent);
begin
  inherited;
  TabStop := True;
  Color := A2SCPanelBackground;
  Cursor := crDefault;
  Font.Color := A2SCPanelText;
  Font.Height := -14;
  FBoundaryPending := -1;
  FEditingPhraseIndex := -1;
  FHoverBoundary := -1;

  FEditReading := TEdit.Create(Self);
  FEditReading.Parent := Self;
  FEditReading.ParentColor := False;
  FEditReading.Color := A2SCEditBackground;
  FEditReading.Font.Assign(Font);
  FEditReading.Font.Color := A2SCEditText;
  FEditReading.Visible := False;
  FEditReading.OnExit := EditReadingExit;
  FEditReading.OnKeyDown := EditReadingKeyDown;
end;

procedure TSerifVoicevoxAccentPaintControl.CMMouseLeave(
  var Message: TMessage);
begin
  inherited;
  if not FDragging then Cursor := crDefault;
  if FHoverBoundary >= 0 then
  begin
    FHoverBoundary := -1;
    Invalidate;
  end;
end;

function TSerifVoicevoxAccentPaintControl.BoundaryAtPoint(
  const X, Y: Integer): Integer;
const
  MORA_AREA_BOTTOM = 74;
  MORA_AREA_TOP = 8;
var
  DX: Integer;
  HitLeft: Integer;
  HitRight: Integer;
  I: Integer;
  P1: TPoint;
  P2: TPoint;
begin
  Result := -1;
  // 音高にかかわらず、モーラ描画領域内ではX座標だけで境界を判定する。
  if (Y < AccentScale(MORA_AREA_TOP, CurrentPPI)) or
    (Y >= AccentScale(MORA_AREA_BOTTOM, CurrentPPI)) then Exit;
  for I := 0 to High(FMoras) - 1 do
  begin
    if not GetMoraCenter(I, P1) or not GetMoraCenter(I + 1, P2) then
      Continue;
    DX := P2.X - P1.X;
    if DX <= 0 then Continue;
    // 両端のノード付近だけは従来の上下ドラッグへ残す。
    HitLeft := P1.X + Round(DX * 0.18);
    HitRight := P1.X + Round(DX * 0.82);
    if (X >= HitLeft) and (X <= HitRight) then Exit(I);
  end;
end;

procedure TSerifVoicevoxAccentPaintControl.ApplyDrag(const X, Y: Integer);
const
  LEVEL_MIDDLE_Y = 43;
var
  Accent: Integer;
  I: Integer;
  Mora: TSerifVoicevoxAccentMora;
  MoraArrayIndex: Integer;
begin
  MoraArrayIndex := MoraAtX(X);
  if MoraArrayIndex < 0 then Exit;
  Mora := FMoras[MoraArrayIndex];
  if Y <= AccentScale(LEVEL_MIDDLE_Y, CurrentPPI) then
  begin
    if Mora.MoraIndex = 0 then Accent := 1
    else Accent := Mora.MoraIndex + 1;
  end
  else if Mora.MoraIndex = 0 then
    Accent := Min(2, Mora.PhraseMoraCount)
  else
    Accent := Mora.MoraIndex;
  Accent := EnsureRange(Accent, 1, Mora.PhraseMoraCount);
  if Mora.Accent = Accent then Exit;

  for I := 0 to High(FMoras) do
    if FMoras[I].PhraseIndex = Mora.PhraseIndex then
    begin
      FMoras[I].Accent := Accent;
      if Accent = 1 then FMoras[I].High := FMoras[I].MoraIndex = 0
      else FMoras[I].High := (FMoras[I].MoraIndex > 0) and
        (FMoras[I].MoraIndex < Accent);
    end;
  Invalidate;
  if Assigned(FOnAccentPosition) then
    FOnAccentPosition(Self, Mora.PhraseIndex, Accent);
end;

procedure TSerifVoicevoxAccentPaintControl.BeginReadingEdit(
  const PhraseIndex: Integer);
var
  EditBounds: TRect;
begin
  if PhraseIndex < 0 then Exit;
  if FEditReading.Visible and (FEditingPhraseIndex = PhraseIndex) then Exit;
  if FEditReading.Visible then FinishReadingEdit(True);

  EditBounds := PhraseBounds(PhraseIndex);
  if IsRectEmpty(EditBounds) then Exit;
  FEditingPhraseIndex := PhraseIndex;
  FEditReading.Color := A2SCEditBackground;
  FEditReading.Font.Assign(Font);
  FEditReading.Font.Color := A2SCEditText;
  FEditReading.Text := PhraseReading(PhraseIndex);
  FEditReading.SetBounds(EditBounds.Left, EditBounds.Top,
    Max(AccentScale(100, CurrentPPI), EditBounds.Width), EditBounds.Height);
  FEditReading.Visible := True;
  FEditReading.BringToFront;
  FEditReading.SetFocus;
  FEditReading.SelectAll;
end;

procedure TSerifVoicevoxAccentPaintControl.CancelReadingEdit;
begin
  FinishReadingEdit(False);
end;

procedure TSerifVoicevoxAccentPaintControl.Clear;
begin
  CancelReadingEdit;
  FBoundaryPending := -1;
  FHoverBoundary := -1;
  SetLength(FMoras, 0);
  Invalidate;
end;

function TSerifVoicevoxAccentPaintControl.GetMoraCenter(
  const MoraArrayIndex: Integer; out Center: TPoint): Boolean;
const
  HIGH_Y = 24;
  LOW_Y = 62;
var
  CellWidth: Integer;
  I: Integer;
  LeftPos: Integer;
begin
  Result := False;
  Center := Point(0, 0);
  if (MoraArrayIndex < 0) or (MoraArrayIndex > High(FMoras)) then Exit;
  Canvas.Font.Assign(Font);
  LeftPos := AccentScale(10, CurrentPPI);
  for I := 0 to MoraArrayIndex do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(LeftPos, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    if I = MoraArrayIndex then
    begin
      Center.X := LeftPos + (CellWidth div 2);
      if FMoras[I].High then Center.Y := AccentScale(HIGH_Y, CurrentPPI)
      else Center.Y := AccentScale(LOW_Y, CurrentPPI);
      Exit(True);
    end;
    Inc(LeftPos, CellWidth);
  end;
end;

procedure TSerifVoicevoxAccentPaintControl.EditReadingExit(Sender: TObject);
begin
  FinishReadingEdit(True);
end;

procedure TSerifVoicevoxAccentPaintControl.EditReadingKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        FinishReadingEdit(True);
        SetFocus;
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        FinishReadingEdit(False);
        SetFocus;
      end;
    VK_F5:
      begin
        Key := 0;
        if Assigned(FOnPreview) then FOnPreview(Self);
      end;
  end;
end;

procedure TSerifVoicevoxAccentPaintControl.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  inherited;
  if Key = VK_F5 then
  begin
    Key := 0;
    if Assigned(FOnPreview) then FOnPreview(Self);
  end;
end;

procedure TSerifVoicevoxAccentPaintControl.FinishReadingEdit(
  const Commit: Boolean);
var
  PhraseIndex: Integer;
  Reading: string;
begin
  if FFinishingReadingEdit or not Assigned(FEditReading) or
    not FEditReading.Visible then Exit;
  FFinishingReadingEdit := True;
  try
    PhraseIndex := FEditingPhraseIndex;
    Reading := Trim(FEditReading.Text);
    FEditingPhraseIndex := -1;
    FEditReading.Visible := False;
    if Commit and (Reading <> '') and Assigned(FOnReading) then
      FOnReading(Self, PhraseIndex, Reading);
  finally
    FFinishingReadingEdit := False;
  end;
end;

function TSerifVoicevoxAccentPaintControl.GetContentWidth: Integer;
var
  I: Integer;
begin
  Canvas.Font.Assign(Font);
  Result := AccentScale(20, CurrentPPI);
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(Result, AccentScale(12, CurrentPPI));
    Inc(Result, Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI)));
  end;
  Inc(Result, AccentScale(10, CurrentPPI));
end;

function TSerifVoicevoxAccentPaintControl.MoraCells: TArray<TRect>;
begin
  SetLength(Result,Length(FMoras)); Canvas.Font.Assign(Font);
  var X := AccentScale(10,CurrentPPI);
  for var I := 0 to High(FMoras) do begin
    if FMoras[I].PhraseStart and (I>0) then Inc(X,AccentScale(12,CurrentPPI));
    var W := Max(AccentScale(MORA_CELL_MIN_WIDTH,CurrentPPI),Canvas.TextWidth(FMoras[I].Text)+AccentScale(MORA_CELL_TEXT_PADDING,CurrentPPI));
    Result[I] := Rect(X,0,X+W,AccentScale(104,CurrentPPI)); Inc(X,W);
  end;
end;

function TSerifVoicevoxAccentPaintControl.MoraAtX(const X: Integer): Integer;
var
  CellWidth: Integer;
  I: Integer;
  LeftPos: Integer;
begin
  Canvas.Font.Assign(Font);
  Result := -1;
  LeftPos := AccentScale(10, CurrentPPI);
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(LeftPos, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    if (X >= LeftPos) and (X < LeftPos + CellWidth) then Exit(I);
    Inc(LeftPos, CellWidth);
  end;
end;

function TSerifVoicevoxAccentPaintControl.MoraAtPoint(
  const X, Y: Integer): Integer;
const
  HIGH_Y = 24;
  HIT_HALF_HEIGHT = 12;
  LOW_Y = 62;
var
  MoraY: Integer;
begin
  Result := MoraAtX(X);
  if Result < 0 then Exit;
  if FMoras[Result].High then MoraY := AccentScale(HIGH_Y, CurrentPPI)
  else MoraY := AccentScale(LOW_Y, CurrentPPI);
  if Abs(Y - MoraY) > AccentScale(HIT_HALF_HEIGHT, CurrentPPI) then
    Result := -1;
end;

function TSerifVoicevoxAccentPaintControl.PhraseAtTextPoint(
  const X, Y: Integer): Integer;
var
  MoraIndex: Integer;
begin
  Result := -1;
  if (Y < AccentScale(74, CurrentPPI)) or
    (Y >= AccentScale(104, CurrentPPI)) then Exit;
  MoraIndex := MoraAtX(X);
  if MoraIndex >= 0 then Result := FMoras[MoraIndex].PhraseIndex;
end;

function TSerifVoicevoxAccentPaintControl.PhraseBounds(
  const PhraseIndex: Integer): TRect;
var
  CellWidth: Integer;
  I: Integer;
  LeftPos: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  LeftPos := AccentScale(10, CurrentPPI);
  Canvas.Font.Assign(Font);
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(LeftPos, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    if FMoras[I].PhraseIndex = PhraseIndex then
    begin
      if IsRectEmpty(Result) then Result := Rect(LeftPos,
        AccentScale(75, CurrentPPI), 0, AccentScale(101, CurrentPPI));
      Result.Right := LeftPos + CellWidth;
    end;
    Inc(LeftPos, CellWidth);
  end;
end;

function TSerifVoicevoxAccentPaintControl.PhraseReading(
  const PhraseIndex: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FMoras) do
    if FMoras[I].PhraseIndex = PhraseIndex then
      Result := Result + FMoras[I].Text;
end;

procedure TSerifVoicevoxAccentPaintControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  BoundaryIndex: Integer;
begin
  inherited;
  if (Button = mbLeft) and CanFocus then SetFocus;
  if (Button = mbLeft) and (PhraseAtTextPoint(X, Y) >= 0) then
  begin
    BeginReadingEdit(PhraseAtTextPoint(X, Y));
    Exit;
  end;
  BoundaryIndex := BoundaryAtPoint(X, Y);
  if (Button = mbLeft) and (BoundaryIndex >= 0) then
  begin
    FBoundaryPending := BoundaryIndex;
    MouseCapture := True;
    Exit;
  end;
  if (Button <> mbLeft) or (MoraAtPoint(X, Y) < 0) then Exit;
  FDragging := False;
  FDragPending := True;
  FMouseDownPoint := Point(X, Y);
  MouseCapture := True;
end;

procedure TSerifVoicevoxAccentPaintControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  BoundaryIndex: Integer;
begin
  inherited;
  BoundaryIndex := BoundaryAtPoint(X, Y);
  if BoundaryIndex <> FHoverBoundary then
  begin
    FHoverBoundary := BoundaryIndex;
    Invalidate;
  end;
  if BoundaryIndex >= 0 then
  begin
    if FMoras[BoundaryIndex + 1].PhraseStart then Cursor := crHandPoint
    else Cursor := crCross;
  end
  else if PhraseAtTextPoint(X, Y) >= 0 then Cursor := crIBeam
  else if FDragging or (MoraAtPoint(X, Y) >= 0) then Cursor := crSizeNS
  else Cursor := crDefault;
  if FBoundaryPending >= 0 then Exit;
  if not (ssLeft in Shift) then Exit;
  if FDragPending and not FDragging and
    ((Abs(X - FMouseDownPoint.X) >= GetSystemMetrics(SM_CXDRAG)) or
     (Abs(Y - FMouseDownPoint.Y) >= GetSystemMetrics(SM_CYDRAG))) then
    FDragging := True;
  if FDragging then ApplyDrag(X, Y);
end;

procedure TSerifVoicevoxAccentPaintControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  BoundaryIndex: Integer;
  Connect: Boolean;
begin
  inherited;
  if Button = mbRight then
  begin
    if Assigned(FOnPreview) then FOnPreview(Self);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  if FBoundaryPending >= 0 then
  begin
    BoundaryIndex := FBoundaryPending;
    FBoundaryPending := -1;
    MouseCapture := False;
    if (BoundaryAtPoint(X, Y) = BoundaryIndex) and
      (BoundaryIndex < High(FMoras)) and Assigned(FOnBoundary) then
    begin
      Connect := FMoras[BoundaryIndex + 1].PhraseStart;
      FOnBoundary(Self, BoundaryIndex, Connect);
    end;
    Exit;
  end;
  if FDragging then ApplyDrag(X, Y);
  FDragging := False;
  FDragPending := False;
  MouseCapture := False;
end;

procedure TSerifVoicevoxAccentPaintControl.Paint;
const
  HIGH_Y = 24;
  LOW_Y = 62;
  TEXT_Y = 78;
var
  CellWidth: Integer;
  CenterX: Integer;
  CurrentY: Integer;
  GuideLeft: Integer;
  GuideRight: Integer;
  IconRadius: Integer;
  I: Integer;
  MarkColor: TColor;
  MidPoint: TPoint;
  NodeRadius: Integer;
  P1: TPoint;
  P2: TPoint;
  PreviousX: Integer;
  PreviousY: Integer;
  TextRect: TRect;
  X: Integer;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if Length(FMoras) = 0 then Exit;

  Canvas.Font.Assign(Font);
  // 高・低の2段と各モーラの中心を先にガイド描画し、アクセント線を読みやすくする。
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := RGB(96, 96, 96);
  Canvas.Pen.Width := Max(1, AccentScale(1, CurrentPPI));
  GuideLeft := -1;
  GuideRight := -1;
  X := AccentScale(10, CurrentPPI);
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(X, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    CenterX := X + (CellWidth div 2);
    if GuideLeft < 0 then GuideLeft := CenterX;
    GuideRight := CenterX;
    Canvas.MoveTo(CenterX, AccentScale(HIGH_Y, CurrentPPI));
    Canvas.LineTo(CenterX, AccentScale(LOW_Y, CurrentPPI));
    Inc(X, CellWidth);
  end;

  Canvas.Pen.Color := RGB(120, 120, 120);
  Canvas.Pen.Width := Max(1, AccentScale(1, CurrentPPI));
  if (GuideLeft >= 0) and (GuideRight > GuideLeft) then
  begin
    Canvas.MoveTo(GuideLeft, AccentScale(HIGH_Y, CurrentPPI));
    Canvas.LineTo(GuideRight, AccentScale(HIGH_Y, CurrentPPI));
    Canvas.MoveTo(GuideLeft, AccentScale(LOW_Y, CurrentPPI));
    Canvas.LineTo(GuideRight, AccentScale(LOW_Y, CurrentPPI));
  end;

  Canvas.Pen.Color := RGB(156, 176, 162);
  Canvas.Pen.Width := Max(1, AccentScale(2, CurrentPPI));
  X := AccentScale(10, CurrentPPI);
  PreviousX := 0;
  PreviousY := 0;
  // 先に接続線をすべて描き、後段のノードで線の端を覆う。
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(X, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    CenterX := X + (CellWidth div 2);
    if FMoras[I].High then CurrentY := AccentScale(HIGH_Y, CurrentPPI)
    else CurrentY := AccentScale(LOW_Y, CurrentPPI);

    if not FMoras[I].PhraseStart then
    begin
      Canvas.MoveTo(PreviousX, PreviousY);
      Canvas.LineTo(CenterX, CurrentY);
    end;
    PreviousX := CenterX;
    PreviousY := CurrentY;
    Inc(X, CellWidth);
  end;

  if (FHoverBoundary >= 0) and (FHoverBoundary < High(FMoras)) and
    GetMoraCenter(FHoverBoundary, P1) and
    GetMoraCenter(FHoverBoundary + 1, P2) then
  begin
    if FMoras[FHoverBoundary + 1].PhraseStart then
    begin
      MarkColor := RGB(112, 142, 122);
      Canvas.Pen.Style := psDot;
      Canvas.Pen.Width := 1;
    end
    else
    begin
      MarkColor := RGB(224, 112, 104);
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := Max(1, AccentScale(2, CurrentPPI));
    end;
    Canvas.Pen.Color := MarkColor;
    Canvas.MoveTo(P1.X, P1.Y);
    Canvas.LineTo(P2.X, P2.Y);
    Canvas.Pen.Style := psSolid;
  end;

  // 線の上へノードと文字を描くことで、円内へ入り込んだ線を見えなくする。
  X := AccentScale(10, CurrentPPI);
  for I := 0 to High(FMoras) do
  begin
    if FMoras[I].PhraseStart and (I > 0) then
      Inc(X, AccentScale(12, CurrentPPI));
    CellWidth := Max(AccentScale(MORA_CELL_MIN_WIDTH, CurrentPPI),
      Canvas.TextWidth(FMoras[I].Text) +
      AccentScale(MORA_CELL_TEXT_PADDING, CurrentPPI));
    CenterX := X + (CellWidth div 2);
    if FMoras[I].High then CurrentY := AccentScale(HIGH_Y, CurrentPPI)
    else CurrentY := AccentScale(LOW_Y, CurrentPPI);
    if FMoras[I].PhraseStart or FMoras[I].PhraseEnd then
      NodeRadius := AccentScale(5, CurrentPPI)
    else NodeRadius := AccentScale(4, CurrentPPI);
    Canvas.Brush.Color := RGB(166, 216, 178);
    Canvas.Pen.Color := RGB(166, 216, 178);
    Canvas.Ellipse(CenterX - NodeRadius, CurrentY - NodeRadius,
      CenterX + NodeRadius, CurrentY + NodeRadius);
    Canvas.Pen.Color := RGB(156, 176, 162);

    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := A2SCPanelText;
    TextRect := Rect(X, AccentScale(TEXT_Y, CurrentPPI), X + CellWidth,
      ClientHeight);
    DrawText(Canvas.Handle, PChar(FMoras[I].Text), Length(FMoras[I].Text),
      TextRect, DT_CENTER or DT_TOP or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    Inc(X, CellWidth);
  end;

  if (FHoverBoundary >= 0) and (FHoverBoundary < High(FMoras)) and
    GetMoraCenter(FHoverBoundary, P1) and
    GetMoraCenter(FHoverBoundary + 1, P2) then
  begin
    MidPoint := Point((P1.X + P2.X) div 2, (P1.Y + P2.Y) div 2);
    if FMoras[FHoverBoundary + 1].PhraseStart then
      MarkColor := RGB(112, 142, 122)
    else
      MarkColor := RGB(224, 112, 104);
    IconRadius := AccentScale(6, CurrentPPI);
    Canvas.Brush.Color := Color;
    Canvas.Pen.Color := Color;
    Canvas.Ellipse(MidPoint.X - IconRadius, MidPoint.Y - IconRadius,
      MidPoint.X + IconRadius + 1, MidPoint.Y + IconRadius + 1);
    Canvas.Pen.Color := MarkColor;
    Canvas.Pen.Width := Max(1, AccentScale(2, CurrentPPI));
    IconRadius := AccentScale(4, CurrentPPI);
    if FMoras[FHoverBoundary + 1].PhraseStart then
    begin
      Canvas.MoveTo(MidPoint.X - IconRadius, MidPoint.Y);
      Canvas.LineTo(MidPoint.X + IconRadius + 1, MidPoint.Y);
      Canvas.MoveTo(MidPoint.X, MidPoint.Y - IconRadius);
      Canvas.LineTo(MidPoint.X, MidPoint.Y + IconRadius + 1);
    end
    else
    begin
      Canvas.MoveTo(MidPoint.X - IconRadius, MidPoint.Y - IconRadius);
      Canvas.LineTo(MidPoint.X + IconRadius + 1,
        MidPoint.Y + IconRadius + 1);
      Canvas.MoveTo(MidPoint.X - IconRadius, MidPoint.Y + IconRadius);
      Canvas.LineTo(MidPoint.X + IconRadius + 1,
        MidPoint.Y - IconRadius - 1);
    end;
  end;
end;

procedure TSerifVoicevoxAccentPaintControl.SetQueryJson(
  const QueryJson: string);
var
  Accent: Integer;
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  MoraCount: Integer;
  MoraIndex: Integer;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
begin
  FBoundaryPending := -1;
  FHoverBoundary := -1;
  SetLength(FMoras, 0);
  RootValue := TJSONObject.ParseJSONValue(QueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(AccentPhrases) then Exit;

    MoraCount := 0;
    for I := 0 to AccentPhrases.Count - 1 do
    begin
      PhraseObject := AccentPhrases.Items[I] as TJSONObject;
      Moras := PhraseObject.GetValue<TJSONArray>('moras');
      if Assigned(Moras) then Inc(MoraCount, Moras.Count);
    end;
    SetLength(FMoras, MoraCount);

    MoraIndex := 0;
    for I := 0 to AccentPhrases.Count - 1 do
    begin
      PhraseObject := AccentPhrases.Items[I] as TJSONObject;
      Moras := PhraseObject.GetValue<TJSONArray>('moras');
      if not Assigned(Moras) then Continue;
      Accent := PhraseObject.GetValue<Integer>('accent');
      for J := 0 to Moras.Count - 1 do
      begin
        MoraObject := Moras.Items[J] as TJSONObject;
        FMoras[MoraIndex].Accent := Accent;
        FMoras[MoraIndex].Text := MoraObject.GetValue<string>('text');
        if Accent = 1 then FMoras[MoraIndex].High := J = 0
        else FMoras[MoraIndex].High := (J > 0) and (J < Accent);
        FMoras[MoraIndex].PhraseStart := J = 0;
        FMoras[MoraIndex].PhraseEnd := J = Moras.Count - 1;
        FMoras[MoraIndex].MoraIndex := J;
        FMoras[MoraIndex].PhraseIndex := I;
        FMoras[MoraIndex].PhraseMoraCount := Moras.Count;
        Inc(MoraIndex);
      end;
    end;
  finally
    RootValue.Free;
  end;
  Invalidate;
end;

constructor TSerifVoicevoxAccentQueryThread.Create(const NotifyHandle: HWND;
  const QueryId: Cardinal; const Text: string; const SpeakerId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FNotifyHandle := NotifyHandle;
  FQueryId := QueryId;
  FText := Text;
  FSpeakerId := SpeakerId;
end;

procedure TSerifVoicevoxAccentQueryThread.Execute;
begin
  PrepareApi;
  try
  try
    if not Terminated then
      FSuccess := TSerifVoicevoxApi.CreateAudioQuery(FText, FSpeakerId,
        FQueryJson, FErrorMessage);
  except
    on E: Exception do
    begin
      FSuccess := False;
      FErrorMessage := E.Message;
    end;
  end;
  finally FinishApi; end;
  PostMessage(FNotifyHandle,
    TSerifVoicevoxAccentView.QUERY_COMPLETE_MESSAGE, WPARAM(FQueryId), 0);
end;

constructor TSerifVoicevoxReadingQueryThread.Create(const NotifyHandle: HWND;
  const ReadingId: Cardinal; const PhraseIndex: Integer;
  const ReadingText: string; const SpeakerId: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FNotifyHandle := NotifyHandle;
  FReadingId := ReadingId;
  FPhraseIndex := PhraseIndex;
  FReadingText := ReadingText;
  FSpeakerId := SpeakerId;
end;

procedure TSerifVoicevoxReadingQueryThread.Execute;
begin
  PrepareApi;
  try
  try
    if not Terminated then
      FSuccess := TSerifVoicevoxApi.CreateAccentPhrases(FReadingText,
        FSpeakerId, FAccentPhrasesJson, FErrorMessage);
  except
    on E: Exception do
    begin
      FSuccess := False;
      FErrorMessage := E.Message;
    end;
  end;
  finally FinishApi; end;
  PostMessage(FNotifyHandle,
    TSerifVoicevoxAccentView.READING_COMPLETE_MESSAGE,
    WPARAM(FReadingId), 0);
end;

procedure TSerifVoicevoxAccentView.AccentPosition(Sender: TObject;
  const PhraseIndex, Accent: Integer);
var
  AccentPair: TJSONPair;
  AccentPhrases: TJSONArray;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
begin
  RootValue := TJSONObject.ParseJSONValue(FQueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(AccentPhrases) or (PhraseIndex < 0) or
      (PhraseIndex >= AccentPhrases.Count) then Exit;
    PhraseObject := AccentPhrases.Items[PhraseIndex] as TJSONObject;
    AccentPair := PhraseObject.RemovePair('accent');
    AccentPair.Free;
    PhraseObject.AddPair('accent', TJSONNumber.Create(Accent));
    FQueryJson := RootObject.ToJSON;
  finally
    RootValue.Free;
  end;
  if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
end;

procedure TSerifVoicevoxAccentView.BoundaryChange(Sender: TObject;
  const MoraArrayIndex: Integer; const Connect: Boolean);
var
  AccentPair: TJSONPair;
  AccentPhrases: TJSONArray;
  BoundaryMora: TSerifVoicevoxAccentMora;
  I: Integer;
  LeftAccent: Integer;
  LeftMoras: TJSONArray;
  LeftPhrase: TJSONObject;
  MergedMoras: TJSONArray;
  MergedPhrase: TJSONObject;
  NewAccentPhrases: TJSONArray;
  OldAccent: Integer;
  PhraseIndex: Integer;
  RightAccent: Integer;
  RightMoras: TJSONArray;
  RightPhrase: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  SourceMoras: TJSONArray;
  SourcePhrase: TJSONObject;
  SplitAfter: Integer;

  function CloneObject(const Source: TJSONObject): TJSONObject;
  var
    Value: TJSONValue;
  begin
    Result := nil;
    if not Assigned(Source) then Exit;
    Value := TJSONObject.ParseJSONValue(Source.ToJSON);
    if Value is TJSONObject then Result := TJSONObject(Value)
    else Value.Free;
  end;

  function CloneMoras(const Source: TJSONArray; const First,
    Last: Integer): TJSONArray;
  var
    EffectiveFirst: Integer;
    EffectiveLast: Integer;
    J: Integer;
  begin
    Result := TJSONArray.Create;
    if not Assigned(Source) or (Source.Count = 0) then Exit;
    EffectiveFirst := Max(0, First);
    EffectiveLast := Min(Last, Source.Count - 1);
    if EffectiveFirst > EffectiveLast then Exit;
    for J := EffectiveFirst to EffectiveLast do
      Result.AddElement(TJSONObject.ParseJSONValue(Source.Items[J].ToJSON));
  end;

  procedure ReplaceMoras(const Phrase: TJSONObject; Moras: TJSONArray);
  var
    Pair: TJSONPair;
  begin
    Pair := Phrase.RemovePair('moras');
    Pair.Free;
    Phrase.AddPair('moras', Moras);
  end;

  procedure ReplaceAccent(const Phrase: TJSONObject; const Accent: Integer);
  var
    Pair: TJSONPair;
  begin
    Pair := Phrase.RemovePair('accent');
    Pair.Free;
    Phrase.AddPair('accent', TJSONNumber.Create(Accent));
  end;

  procedure SetPhraseSuffix(const Source, Destination: TJSONObject);
  var
    Pair: TJSONPair;
    Value: TJSONValue;
  begin
    Pair := Destination.RemovePair('pause_mora');
    Pair.Free;
    Value := Source.GetValue('pause_mora');
    if Assigned(Value) then
      Destination.AddPair('pause_mora',
        TJSONObject.ParseJSONValue(Value.ToJSON))
    else
      Destination.AddPair('pause_mora', TJSONNull.Create);

    Pair := Destination.RemovePair('is_interrogative');
    Pair.Free;
    Value := Source.GetValue('is_interrogative');
    if Assigned(Value) then
      Destination.AddPair('is_interrogative',
        TJSONObject.ParseJSONValue(Value.ToJSON))
    else
      Destination.AddPair('is_interrogative', TJSONBool.Create(False));
  end;

  procedure ClearPhraseSuffix(const Phrase: TJSONObject);
  var
    Pair: TJSONPair;
  begin
    Pair := Phrase.RemovePair('pause_mora');
    Pair.Free;
    Phrase.AddPair('pause_mora', TJSONNull.Create);
    Pair := Phrase.RemovePair('is_interrogative');
    Pair.Free;
    Phrase.AddPair('is_interrogative', TJSONBool.Create(False));
  end;

begin
  if (MoraArrayIndex < 0) or
    (MoraArrayIndex >= High(FPaintControl.FMoras)) or
    (FQueryJson = '') then Exit;
  BoundaryMora := FPaintControl.FMoras[MoraArrayIndex];
  PhraseIndex := BoundaryMora.PhraseIndex;
  RootValue := TJSONObject.ParseJSONValue(FQueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(AccentPhrases) or (PhraseIndex < 0) or
      (PhraseIndex >= AccentPhrases.Count) then Exit;

    NewAccentPhrases := TJSONArray.Create;
    try
      if Connect then
      begin
        if (PhraseIndex + 1 >= AccentPhrases.Count) or
          not FPaintControl.FMoras[MoraArrayIndex + 1].PhraseStart then Exit;
        LeftPhrase := AccentPhrases.Items[PhraseIndex] as TJSONObject;
        RightPhrase := AccentPhrases.Items[PhraseIndex + 1] as TJSONObject;
        MergedPhrase := CloneObject(LeftPhrase);
        if not Assigned(MergedPhrase) then Exit;
        MergedMoras := CloneMoras(LeftPhrase.GetValue<TJSONArray>('moras'),
          0, MaxInt);
        SourceMoras := RightPhrase.GetValue<TJSONArray>('moras');
        for I := 0 to SourceMoras.Count - 1 do
          MergedMoras.AddElement(TJSONObject.ParseJSONValue(
            SourceMoras.Items[I].ToJSON));
        ReplaceMoras(MergedPhrase, MergedMoras);
        SetPhraseSuffix(RightPhrase, MergedPhrase);

        for I := 0 to AccentPhrases.Count - 1 do
          if I = PhraseIndex then NewAccentPhrases.AddElement(MergedPhrase)
          else if I <> PhraseIndex + 1 then
            NewAccentPhrases.AddElement(TJSONObject.ParseJSONValue(
              AccentPhrases.Items[I].ToJSON));
      end
      else
      begin
        if BoundaryMora.PhraseEnd then Exit;
        SourcePhrase := AccentPhrases.Items[PhraseIndex] as TJSONObject;
        SourceMoras := SourcePhrase.GetValue<TJSONArray>('moras');
        SplitAfter := BoundaryMora.MoraIndex;
        if not Assigned(SourceMoras) or (SplitAfter < 0) or
          (SplitAfter >= SourceMoras.Count - 1) then Exit;
        OldAccent := SourcePhrase.GetValue<Integer>('accent');
        if OldAccent > SplitAfter then LeftAccent := SplitAfter + 1
        else LeftAccent := OldAccent;
        if OldAccent > SplitAfter + 1 then
          RightAccent := OldAccent - SplitAfter - 1
        else RightAccent := 1;

        LeftPhrase := CloneObject(SourcePhrase);
        RightPhrase := CloneObject(SourcePhrase);
        if not Assigned(LeftPhrase) or not Assigned(RightPhrase) then
        begin
          LeftPhrase.Free;
          RightPhrase.Free;
          Exit;
        end;
        LeftMoras := CloneMoras(SourceMoras, 0, SplitAfter);
        RightMoras := CloneMoras(SourceMoras, SplitAfter + 1,
          SourceMoras.Count - 1);
        ReplaceMoras(LeftPhrase, LeftMoras);
        ReplaceMoras(RightPhrase, RightMoras);
        ReplaceAccent(LeftPhrase, LeftAccent);
        ReplaceAccent(RightPhrase, RightAccent);
        ClearPhraseSuffix(LeftPhrase);

        for I := 0 to AccentPhrases.Count - 1 do
          if I = PhraseIndex then
          begin
            NewAccentPhrases.AddElement(LeftPhrase);
            NewAccentPhrases.AddElement(RightPhrase);
          end
          else
            NewAccentPhrases.AddElement(TJSONObject.ParseJSONValue(
              AccentPhrases.Items[I].ToJSON));
      end;

      AccentPair := RootObject.RemovePair('accent_phrases');
      AccentPair.Free;
      RootObject.AddPair('accent_phrases', NewAccentPhrases);
      NewAccentPhrases := nil;
      FQueryJson := RootObject.ToJSON;
    finally
      NewAccentPhrases.Free;
    end;
  finally
    RootValue.Free;
  end;

  FPaintControl.SetQueryJson(FQueryJson);
  UpdatePaintBounds;
  if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
end;

function TSerifVoicevoxAccentView.ApplyReading(const PhraseIndex: Integer;
  const AccentPhrasesJson: string): Boolean;
var
  AccentPair: TJSONPair;
  I: Integer;
  J: Integer;
  NewAccentPhrases: TJSONArray;
  NewPhrase: TJSONObject;
  OldAccentPhrases: TJSONArray;
  OldPhrase: TJSONObject;
  OldValue: TJSONValue;
  ReplacementPhrases: TJSONArray;
  ReplacementValue: TJSONValue;
  RootObject: TJSONObject;
  RootValue: TJSONValue;

  procedure CopyPhraseSuffix(const Source, Destination: TJSONObject);
  var
    Pair: TJSONPair;
    Value: TJSONValue;
  begin
    Pair := Destination.RemovePair('pause_mora');
    Pair.Free;
    Value := Source.GetValue('pause_mora');
    if Assigned(Value) then
      Destination.AddPair('pause_mora',
        TJSONObject.ParseJSONValue(Value.ToJSON));

    Pair := Destination.RemovePair('is_interrogative');
    Pair.Free;
    Value := Source.GetValue('is_interrogative');
    if Assigned(Value) then
      Destination.AddPair('is_interrogative',
        TJSONObject.ParseJSONValue(Value.ToJSON));
  end;

begin
  Result := False;
  RootValue := TJSONObject.ParseJSONValue(FQueryJson);
  ReplacementValue := TJSONObject.ParseJSONValue(AccentPhrasesJson);
  try
    if not (RootValue is TJSONObject) or
      not (ReplacementValue is TJSONArray) then Exit;
    RootObject := TJSONObject(RootValue);
    ReplacementPhrases := TJSONArray(ReplacementValue);
    OldAccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(OldAccentPhrases) or
      (PhraseIndex < 0) or (PhraseIndex >= OldAccentPhrases.Count) or
      (ReplacementPhrases.Count = 0) then Exit;

    OldPhrase := OldAccentPhrases.Items[PhraseIndex] as TJSONObject;
    NewAccentPhrases := TJSONArray.Create;
    try
      for I := 0 to OldAccentPhrases.Count - 1 do
        if I <> PhraseIndex then
          NewAccentPhrases.AddElement(TJSONObject.ParseJSONValue(
            OldAccentPhrases.Items[I].ToJSON))
        else
          for J := 0 to ReplacementPhrases.Count - 1 do
          begin
            OldValue := TJSONObject.ParseJSONValue(
              ReplacementPhrases.Items[J].ToJSON);
            if not (OldValue is TJSONObject) then
            begin
              OldValue.Free;
              Exit;
            end;
            NewPhrase := TJSONObject(OldValue);
            if J = ReplacementPhrases.Count - 1 then
              CopyPhraseSuffix(OldPhrase, NewPhrase);
            NewAccentPhrases.AddElement(NewPhrase);
          end;

      AccentPair := RootObject.RemovePair('accent_phrases');
      AccentPair.Free;
      RootObject.AddPair('accent_phrases', NewAccentPhrases);
      NewAccentPhrases := nil;
      FQueryJson := RootObject.ToJSON;
      Result := True;
    finally
      NewAccentPhrases.Free;
    end;
  finally
    ReplacementValue.Free;
    RootValue.Free;
  end;
end;

procedure TSerifVoicevoxAccentView.Preview(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

procedure TSerifVoicevoxAccentView.Reading(Sender: TObject;
  const PhraseIndex: Integer; const ReadingText: string);
begin
  VoicevoxDebugLog(Format('AccentView.Reading phrase=%d length=%d queryReady=%s speaker=%d',
    [PhraseIndex, Length(ReadingText), BoolToStr(FQueryJson <> '', True),
     FCurrentSpeakerId]));
  if (FQueryJson = '') or (FCurrentSpeakerId < 0) then Exit;
  Inc(FReadingId);
  if FReadingId = 0 then Inc(FReadingId);
  FReadingPhraseIndex := PhraseIndex;
  FReadingText := ReadingText;
  StartReadingQuery;
end;

constructor TSerifVoicevoxAccentView.Create(AOwner: TComponent);
begin
  VoicevoxDebugLog('AccentView.Create enter');
  inherited;
  BorderStyle := bsNone;
  Color := A2SCPanelBackground;
  AutoScroll := False;
  HorzScrollBar.Visible := False;
  VertScrollBar.Visible := False;
  FCurrentSpeakerId := -1;
  FNotifyHandle := AllocateHWnd(QueryCompleteWindowProc);

  FPaintControl := TSerifVoicevoxAccentPaintControl.Create(Self);
  FPaintControl.Parent := Self;
  FPaintControl.OnAccentPosition := AccentPosition;
  FPaintControl.OnBoundary := BoundaryChange;
  FPaintControl.OnPreview := Preview;
  FPaintControl.OnReading := Reading;
  // 親フレームへ接続される前はClientWidthを取得せず、Resizeまで仮サイズで保持する。
  FPaintControl.SetBounds(0, 0, 1, 104);

  FScrollBar := THorizontalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Align := alBottom;
  FScrollBar.Height := SCROLL_BAR_HEIGHT;
  FScrollBar.TopPadding := SCROLL_BAR_TOP_PADDING;
  FScrollBar.BackgroundColor := A2SCPanelBackground;
  FScrollBar.TrackColor := SCROLL_BAR_TRACK_COLOR;
  FScrollBar.ThumbColor := SCROLL_BAR_THUMB_COLOR;
  FScrollBar.OnChange := ScrollPositionChange;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := QUERY_DELAY_MS;
  FTimer.OnTimer := TimerTimer;
  VoicevoxDebugLog('AccentView.Create leave (no API request)');
end;

procedure TSerifVoicevoxAccentPaintControl.CommitReadingEdit;
begin FinishReadingEdit(True); end;
function TSerifVoicevoxAccentView.GetReadingBusy: Boolean;
begin Result := Assigned(FReadingThread) or FReadingRestartPending; end;
function TSerifVoicevoxAccentView.RequestFinish: Boolean;
begin FPaintControl.CommitReadingEdit; Result := not GetReadingBusy; end;

procedure TSerifVoicevoxAccentView.ApplyDpi;
begin
  UpdatePaintBounds;
end;

destructor TSerifVoicevoxAccentView.Destroy;
begin
  FTimer.Enabled := False;
  if Assigned(FQueryThread) then
  begin
    TRigmVoicevoxUiWorker(FQueryThread).Cancel;
    FQueryThread.WaitFor;
    FreeAndNil(FQueryThread);
  end;
  if Assigned(FReadingThread) then
  begin
    TRigmVoicevoxUiWorker(FReadingThread).Cancel;
    FReadingThread.WaitFor;
    FreeAndNil(FReadingThread);
  end;
  if FNotifyHandle <> 0 then
  begin
    DeallocateHWnd(FNotifyHandle);
    FNotifyHandle := 0;
  end;
  inherited;
end;

function TSerifVoicevoxAccentView.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Steps: Integer;
begin
  if not Assigned(FScrollBar) or (FScrollBar.Maximum <= 0) then
  begin
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
    Exit;
  end;

  Inc(FWheelRemainder, WheelDelta);
  Steps := FWheelRemainder div WHEEL_DELTA;
  FWheelRemainder := FWheelRemainder mod WHEEL_DELTA;
  if Steps <> 0 then
    FScrollBar.Position := FScrollBar.Position -
      (Steps * AccentScale(48, CurrentPPI));
  Result := True;
end;

procedure TSerifVoicevoxAccentView.QueryCompleteWindowProc(var Msg: TMessage);
var
  ErrorMessage: string;
  QueryId: Cardinal;
  QueryJson: string;
  QueryThread: TSerifVoicevoxAccentQueryThread;
  Success: Boolean;
begin
  if Msg.Msg = READING_COMPLETE_MESSAGE then
  begin
    ReadingComplete(Msg);
    Exit;
  end;
  if Msg.Msg <> QUERY_COMPLETE_MESSAGE then
  begin
    Msg.Result := DefWindowProc(FNotifyHandle, Msg.Msg, Msg.WParam,
      Msg.LParam);
    Exit;
  end;

  Msg.Result := 0;
  if not Assigned(FQueryThread) then Exit;
  QueryThread := TSerifVoicevoxAccentQueryThread(FQueryThread);
  if Cardinal(Msg.WParam) <> QueryThread.QueryId then Exit;
  QueryThread.WaitFor;
  QueryId := QueryThread.QueryId;
  QueryJson := QueryThread.QueryJson;
  ErrorMessage := QueryThread.ErrorMessage;
  Success := QueryThread.Success and not QueryThread.Terminated;
  FQueryThread := nil;
  QueryThread.Free;

  if Success and (QueryId = FQueryId) then
  begin
    VoicevoxDebugLog(Format('AccentView audio_query complete id=%d accepted=True',
      [QueryId]));
    FQueryJson := QueryJson;
    FPaintControl.SetQueryJson(FQueryJson);
    FPaintControl.Enabled := True;
    FHasDisplay := True;
    UpdatePaintBounds;
    // 初回解析は表示共有だけ。保存WAVを無用に無効化しない。
    FAnalysisUpdate := True;
    try if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
    finally FAnalysisUpdate := False; end;
  end;

  if (QueryId = FQueryId) and not Success and not FRestartPending then
  begin
    FPaintControl.Enabled := True;
    FPaintControl.Clear;
    FHasDisplay := False;
    UpdatePaintBounds;
    if (ErrorMessage <> '') and Assigned(FOnError) then
      FOnError(Self, ErrorMessage);
  end;

  if not Success then
    VoicevoxDebugLog(Format('AccentView audio_query complete id=%d success=False',
      [QueryId]));

  if FRestartPending then
  begin
    FRestartPending := False;
    StartQuery;
  end;
end;

procedure TSerifVoicevoxAccentView.ReadingComplete(var Msg: TMessage);
var
  AccentPhrasesJson: string;
  ErrorMessage: string;
  PhraseIndex: Integer;
  ReadingId: Cardinal;
  ReadingThread: TSerifVoicevoxReadingQueryThread;
  Success: Boolean;
begin
  Msg.Result := 0;
  if not Assigned(FReadingThread) then Exit;
  ReadingThread := TSerifVoicevoxReadingQueryThread(FReadingThread);
  if Cardinal(Msg.WParam) <> ReadingThread.ReadingId then Exit;
  ReadingThread.WaitFor;
  AccentPhrasesJson := ReadingThread.AccentPhrasesJson;
  ErrorMessage := ReadingThread.ErrorMessage;
  PhraseIndex := ReadingThread.PhraseIndex;
  ReadingId := ReadingThread.ReadingId;
  Success := ReadingThread.Success and not ReadingThread.Terminated;
  FReadingThread := nil;
  ReadingThread.Free;

  if Success and (ReadingId = FReadingId) and
    ApplyReading(PhraseIndex, AccentPhrasesJson) then
  begin
    VoicevoxDebugLog(Format('AccentView reading complete id=%d phrase=%d accepted=True',
      [ReadingId, PhraseIndex]));
    FPaintControl.SetQueryJson(FQueryJson);
    UpdatePaintBounds;
    if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
  end
  else if (ReadingId = FReadingId) and (ErrorMessage <> '') and
    Assigned(FOnError) then
    FOnError(Self, ErrorMessage);
  if not Success then
    VoicevoxDebugLog(Format('AccentView reading complete id=%d success=False error=%s',
      [ReadingId, ErrorMessage]));

  if FReadingRestartPending then
  begin
    FReadingRestartPending := False;
    StartReadingQuery;
  end;
end;

procedure TSerifVoicevoxAccentView.Resize;
begin
  inherited;
  UpdatePaintBounds;
end;

procedure TSerifVoicevoxAccentView.ScrollPositionChange(Sender: TObject);
begin
  if Assigned(FPaintControl) and Assigned(FScrollBar) then
    FPaintControl.Left := -FScrollBar.Position;
  if Assigned(FOnScrollChange) then FOnScrollChange(Self);
end;

function TSerifVoicevoxAccentView.MoraCells: TArray<TRect>;
begin Result := FPaintControl.MoraCells; end;
function TSerifVoicevoxAccentView.ContentWidth: Integer;
begin Result := FPaintControl.ContentWidth; end;
function TSerifVoicevoxAccentView.GetScrollPosition: Integer;
begin Result := FScrollBar.Position; end;
procedure TSerifVoicevoxAccentView.SetScrollPosition(Value: Integer);
begin FScrollBar.Position := Value; end;
function TSerifVoicevoxAccentView.EditableAt(const ScreenPoint: TPoint): Boolean;
begin
  var P := FPaintControl.ScreenToClient(ScreenPoint);
  Result := (FPaintControl.MoraAtPoint(P.X,P.Y)>=0) or
    (FPaintControl.PhraseAtTextPoint(P.X,P.Y)>=0) or (FPaintControl.BoundaryAtPoint(P.X,P.Y)>=0);
end;

procedure TSerifVoicevoxAccentView.ShowText(const Text: string;
  const SpeakerId: Integer; const QueryJson: string);
var
  KeepDisplay: Boolean;
  NewText: string;
  SameTarget: Boolean;
  SpeakerOnlyChange: Boolean;
begin
  VoicevoxDebugLog(Format('AccentView.ShowText textLength=%d speaker=%d queryOverride=%s',
    [Length(Trim(Text)), SpeakerId, BoolToStr(QueryJson <> '', True)]));
  NewText := Trim(Text);
  SameTarget := (FCurrentText = NewText) and
    (FCurrentSpeakerId = SpeakerId);
  SpeakerOnlyChange := (FCurrentText = NewText) and
    (FCurrentSpeakerId >= 0) and (SpeakerId >= 0) and
    (FCurrentSpeakerId <> SpeakerId);
  KeepDisplay := SpeakerOnlyChange and FHasDisplay;
  FCurrentText := NewText;
  FCurrentSpeakerId := SpeakerId;
  // 編集中のクエリ再反映では現在位置を保ち、対象そのものの変更だけ先頭へ戻す。
  if not SameTarget and Assigned(FScrollBar) then FScrollBar.Position := 0;
  Inc(FQueryId);
  if FQueryId = 0 then Inc(FQueryId);
  FTimer.Enabled := False;
  FRestartPending := False;
  Inc(FReadingId);
  if FReadingId = 0 then Inc(FReadingId);
  FReadingRestartPending := False;
  if Assigned(FReadingThread) then TRigmVoicevoxUiWorker(FReadingThread).Cancel;
  FQueryJson := '';
  if KeepDisplay then
    FPaintControl.Enabled := False
  else
  begin
    FPaintControl.Enabled := True;
    FPaintControl.Clear;
    FHasDisplay := False;
  end;
  UpdatePaintBounds;

  if Assigned(FQueryThread) then TRigmVoicevoxUiWorker(FQueryThread).Cancel;
  if (FCurrentText = '') or (FCurrentSpeakerId < 0) then
  begin
    VoicevoxDebugLog('AccentView.ShowText no target -> no API request');
    FRestartPending := False;
    FPaintControl.Enabled := True;
    Exit;
  end;
  if QueryJson <> '' then
  begin
    VoicevoxDebugLog('AccentView.ShowText using existing query -> no API request');
    FQueryJson := QueryJson;
    FPaintControl.SetQueryJson(FQueryJson);
    FPaintControl.Enabled := True;
    FHasDisplay := True;
    UpdatePaintBounds;
    Exit;
  end;
  if SpeakerOnlyChange then
  begin
    VoicevoxDebugLog('AccentView.ShowText speaker changed -> audio_query immediately');
    StartQuery;
  end
  else
  begin
    FTimer.Enabled := True;
    VoicevoxDebugLog('AccentView.ShowText scheduled audio_query after debounce');
  end;
end;

procedure TSerifVoicevoxAccentView.StartReadingQuery;
begin
  if Assigned(FReadingThread) then
  begin
    TRigmVoicevoxUiWorker(FReadingThread).Cancel;
    FReadingRestartPending := True;
    Exit;
  end;
  if (FReadingText = '') or (FCurrentSpeakerId < 0) or
    (FReadingPhraseIndex < 0) then Exit;

  FReadingThread := TSerifVoicevoxReadingQueryThread.Create(FNotifyHandle,
    FReadingId, FReadingPhraseIndex, FReadingText, FCurrentSpeakerId);
  TRigmVoicevoxUiWorker(FReadingThread).EngineUrl := FEngineUrl;
  FReadingThread.Start;
end;

procedure TSerifVoicevoxAccentView.StartQuery;
begin
  if Assigned(FQueryThread) then
  begin
    TRigmVoicevoxUiWorker(FQueryThread).Cancel;
    FRestartPending := True;
    Exit;
  end;
  if (FCurrentText = '') or (FCurrentSpeakerId < 0) then Exit;

  VoicevoxDebugLog(Format('AccentView.StartQuery worker start id=%d speaker=%d textLength=%d',
    [FQueryId, FCurrentSpeakerId, Length(FCurrentText)]));
  FQueryThread := TSerifVoicevoxAccentQueryThread.Create(FNotifyHandle,
    FQueryId, FCurrentText, FCurrentSpeakerId);
  TRigmVoicevoxUiWorker(FQueryThread).EngineUrl := FEngineUrl;
  FQueryThread.Start;
end;

procedure TSerifVoicevoxAccentView.TimerTimer(Sender: TObject);
begin
  FTimer.Enabled := False;
  StartQuery;
end;

procedure TSerifVoicevoxAccentView.UpdatePaintBounds;
var
  ContentHeight: Integer;
  ContentWidth: Integer;
  ScrollPosition: Integer;
begin
  if not Assigned(FPaintControl) or not Assigned(FScrollBar) then Exit;
  ScrollPosition := FScrollBar.Position;
  // 200%時の28pxを基準に、グラフ寸法と同じDPI比率で文字も拡縮する。
  FPaintControl.Font.Height := -AccentScale(14, CurrentPPI);
  FScrollBar.Height := AccentScale(SCROLL_BAR_HEIGHT, CurrentPPI);
  FScrollBar.TopPadding := AccentScale(SCROLL_BAR_TOP_PADDING, CurrentPPI);
  ContentWidth := Max(ClientWidth, FPaintControl.ContentWidth);
  FScrollBar.SetRange(ContentWidth, ClientWidth,
    AccentScale(48, CurrentPPI));
  FScrollBar.Position := ScrollPosition;
  ContentHeight := ClientHeight;
  if FScrollBar.Visible then Dec(ContentHeight, FScrollBar.Height);
  // Width/Heightはハンドルを要求しないため、親ウィンドウ接続途中のResizeでも安全。
  FPaintControl.SetBounds(-FScrollBar.Position, 0, ContentWidth,
    Max(ContentHeight, AccentScale(104, CurrentPPI)));
end;

end.
