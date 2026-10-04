// 動画フレームの表示、表示倍率・パン、キャラクター配置ハンドルを担当する。
// 表示用の状態を作品の出力寸法や配置データから分離する。
unit RigmMoviePreview;
interface
uses Winapi.Windows, System.SysUtils, System.Classes, System.Types, Vcl.Controls,
  Vcl.Graphics, RigmMovieSession;
type
  TRigmMoviePreview = class(TCustomControl)
  private
    FFrame: TBitmap; // 所有する表示フレーム。描画ワーカーとGDIハンドルを共有しない。
    FPaintCount,FFrameCount: UInt64;
    FSession            : TRigmMovieSession; // 借用する配置・revision・編集リースの参照先。
    FSelectedCharacter  : string;
    FOnCharacterSelected: TNotifyEvent;
    FDragHandle         : Integer;           // 0..7はサイズ変更点、-1は枠全体の移動。
    FDragging           : Boolean;
    FDragRevision       : Integer;           // ドラッグ開始revision。別操作で変わった場合は確定しない。
    FDragProject        : string;
    FDragStart          : TPointF;
    FOriginal,FWorking: TRectF; // ドラッグ開始枠と未確定枠。1920×1080基準の作品座標。
    FZoom: Double; // 作品の出力サイズに影響しない表示倍率。
    FPanning,FLayoutDragging,FViewDirty: Boolean;
    FPanStart,FPanOriginal,FPan: TPoint;
    FViewCache     : TBitmap; // 所有する倍率適用後の表示画像。レイアウトドラッグ中に再利用する。
    FWheelRemainder: Integer; // 120に満たない高精度ホイール入力の持越し量。
    procedure ClampViewport;
    procedure DrawView(Target: TCanvas);
    procedure SetSelectedCharacter(const Value: string);
    function VideoRect: TRect;
  protected
    procedure Paint; override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    // 表示用画像とキャッシュを所有するコントロールを作る。Sessionは後から借用設定する。
    constructor Create(AOwner: TComponent); override;
    // 表示用画像とキャッシュを解放する。借用セッションは解放しない。
    destructor Destroy; override;
    // 32bitの入力フレームを複製して表示を更新する。ワーカー由来のGDIハンドルを共有しない。
    procedure SetFrame(Bitmap: TBitmap);
    // クライアント座標Positionを中心に表示倍率を変更する。作品の出力寸法は変更しない。
    procedure WheelAt(Delta: Integer; const Position: TPoint);
    // 表示倍率とパンを初期位置へ戻す。キャラクターの保存済み配置は変更しない。
    procedure Fit;
    // スプリッタードラッグ中は表示キャッシュを再利用し、解除時に新寸法で再描画する。
    procedure SetLayoutDragging(Value: Boolean);
    property Zoom: Double read FZoom;
    property Frame: TBitmap read FFrame; // 非所有参照。画面への表示や複製に使い、直接変更しない。
    property PaintCount: UInt64 read FPaintCount;
    property FrameCount: UInt64 read FFrameCount;
    property Session: TRigmMovieSession read FSession write FSession; // 借用先。コントロールより長く生存すること。
    property SelectedCharacter: string read FSelectedCharacter write SetSelectedCharacter;
    property OnCharacterSelected: TNotifyEvent read FOnCharacterSelected write FOnCharacterSelected; // マウス操作で対象が選ばれた後の通知。
    // クライアント座標を1920×1080の作品配置座標へ変換する。倍率とパンを反映する。
    function ScreenToBase(X,Y: Integer): TPointF;
    // Idの配置枠をクライアント座標で返す。ドラッグ中は未確定枠、対象なしは空矩形。
    function CharacterBounds(const Id: string): TRect;
    // 枠の操作点を返す。Index=0は左上、1..7は上辺から時計回りの辺・角。
    function HandleRect(const Id: string; Index: Integer): TRect;
  end;
implementation
uses System.Math, System.JSON, RigmModel, RigmJson;
constructor TRigmMoviePreview.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ControlStyle := ControlStyle+[csOpaque]; FFrame := Vcl.Graphics.TBitmap.Create; FZoom := 1;
  FViewCache := Vcl.Graphics.TBitmap.Create; FViewCache.PixelFormat := pf32bit; FViewDirty := True;
  ShowHint := True; Hint := 'ホイールで表示倍率を変更。中ボタンドラッグで移動。「画面に合わせる」で倍率を戻す。';
end;

destructor TRigmMoviePreview.Destroy;
begin FViewCache.Free; FFrame.Free; inherited; end;

procedure TRigmMoviePreview.SetFrame(Bitmap: Vcl.Graphics.TBitmap);
begin
  Inc(FFrameCount);
  // Do not share a bitmap's cached GDI DC with an exited render thread.
  FFrame.Free; FFrame := Vcl.Graphics.TBitmap.Create; FFrame.PixelFormat := pf32bit;
  FFrame.SetSize(Bitmap.Width,Bitmap.Height); FFrame.AlphaFormat := afIgnored;
  for var Y := 0 to Bitmap.Height-1 do Move(Bitmap.ScanLine[Y]^,FFrame.ScanLine[Y]^,Bitmap.Width*4);
  ClampViewport; FViewDirty := True; Invalidate;
end;

procedure TRigmMoviePreview.SetSelectedCharacter(const Value: string);
begin
  if FSelectedCharacter=Value then Exit;
  FSelectedCharacter := Value; FViewDirty := True; Invalidate;
end;

procedure TRigmMoviePreview.DrawView(Target: TCanvas);
var R: TRect;
begin

  Target.Brush.Color := $181818; Target.FillRect(ClientRect);
  if FFrame.Empty then begin Target.Font.Color := clSilver; Target.Font.Assign(Font); Target.TextOut(ScaleValue(12),ScaleValue(12),'キャラクターと台本を選び、プレビューを開始してください。'); Exit; end;
  R := VideoRect; Target.StretchDraw(R,FFrame);
  if (FSession<>nil) and (FSelectedCharacter<>'') then begin
    Target.Pen.Color := $00FFC060; Target.Pen.Width := ScaleValue(2); Target.Brush.Style := bsClear;
    R := CharacterBounds(FSelectedCharacter); Target.Rectangle(R);
    Target.Brush.Style := bsSolid; Target.Brush.Color := $00FFC060;
    for var I := 0 to 7 do Target.FillRect(HandleRect(FSelectedCharacter,I));
  end;
end;

procedure TRigmMoviePreview.Paint;
begin
  Inc(FPaintCount);
  // Resize during splitter drag reuses the last scaled image. Newly delivered
  // playback frames and explicit zoom/pan still mark the view dirty normally.
  if FViewDirty or FViewCache.Empty or (not FLayoutDragging and
    ((FViewCache.Width<>ClientWidth) or (FViewCache.Height<>ClientHeight))) then begin
    FViewCache.SetSize(Max(1,ClientWidth),Max(1,ClientHeight));
    DrawView(FViewCache.Canvas); FViewDirty := False;
  end;
  Canvas.Brush.Color := $181818; Canvas.FillRect(ClientRect);
  Canvas.Draw(0,0,FViewCache);
end;

function TRigmMoviePreview.VideoRect: TRect;
begin
  var VW := 1920; var VH := 1080;
  if FSession<>nil then begin VW := FSession.Project.Width; VH := FSession.Project.Height; end;
  var AvailableW := Max(1,ClientWidth); var AvailableH := Max(1,ClientHeight);
  var K := Min(AvailableW/Max(1,VW),AvailableH/Max(1,VH))*FZoom;
  var W := Max(1,Round(VW*K)); var H := Max(1,Round(VH*K));
  var X := (AvailableW-W) div 2; var Y := (AvailableH-H) div 2;
  if W>AvailableW then X := -FPan.X;
  if H>AvailableH then Y := -FPan.Y;
  Result := Rect(X,Y,X+W,Y+H);
end;

procedure TRigmMoviePreview.ClampViewport;
begin
  var R := VideoRect;
  FPan.X := EnsureRange(FPan.X,0,Max(0,R.Width-Max(1,ClientWidth)));
  FPan.Y := EnsureRange(FPan.Y,0,Max(0,R.Height-Max(1,ClientHeight)));
end;

procedure TRigmMoviePreview.Resize;
begin
  inherited; ClampViewport;
  if not FLayoutDragging then begin FViewDirty := True; Invalidate; end;
end;

procedure TRigmMoviePreview.SetLayoutDragging(Value: Boolean);
begin
  if FLayoutDragging=Value then Exit;
  FLayoutDragging := Value;
  if not Value then begin ClampViewport; FViewDirty := True; Invalidate; end;
end;

procedure TRigmMoviePreview.Fit;
begin
  FZoom := 1; FPan := Point(0,0);
  ClampViewport; FViewDirty := True; Invalidate;
end;

procedure TRigmMoviePreview.WheelAt(Delta: Integer; const Position: TPoint);
begin
  if FDragging or FPanning then Exit;
  Inc(FWheelRemainder,Delta); var Steps := FWheelRemainder div 120; FWheelRemainder := FWheelRemainder mod 120;
  if Steps=0 then Exit;
  var R := VideoRect; var X := (Position.X-R.Left)/Max(1,R.Width); var Y := (Position.Y-R.Top)/Max(1,R.Height);
  FZoom := EnsureRange(FZoom*Power(1.2,EnsureRange(Steps,-12,12)),0.1,16.0);
  ClampViewport; R := VideoRect;
  FPan.X := EnsureRange(Round(X*R.Width-Position.X),0,Max(0,R.Width-Max(1,ClientWidth)));
  FPan.Y := EnsureRange(Round(Y*R.Height-Position.Y),0,Max(0,R.Height-Max(1,ClientHeight)));
  FViewDirty := True; Invalidate;
end;

function TRigmMoviePreview.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin Result := PtInRect(ClientRect,ScreenToClient(MousePos)); if Result then WheelAt(WheelDelta,ScreenToClient(MousePos)); end;

function TRigmMoviePreview.ScreenToBase(X,Y: Integer): TPointF;
begin var R := VideoRect; Result := PointF((X-R.Left)*1920/Max(1,R.Width),(Y-R.Top)*1080/Max(1,R.Height)); end;

function TRigmMoviePreview.CharacterBounds(const Id: string): TRect;
begin
  Result := Rect(0,0,0,0); if FSession=nil then Exit;
  var C := FSession.Project.Character(Id); if C=nil then Exit;
  var B := RectF(C.X,C.Y,C.X+C.Width,C.Y+C.Height);
  if FDragging and (Id=FSelectedCharacter) then B := FWorking;
  var R := VideoRect;
  Result := Rect(R.Left+Round(B.Left*R.Width/1920),R.Top+Round(B.Top*R.Height/1080),
    R.Left+Round(B.Right*R.Width/1920),R.Top+Round(B.Bottom*R.Height/1080));
end;

function TRigmMoviePreview.HandleRect(const Id: string; Index: Integer): TRect;
begin
  var R := CharacterBounds(Id); var X := R.Left; var Y := R.Top;
  case Index of
    1: X := (R.Left+R.Right) div 2;
    2: X := R.Right;
    3: begin X := R.Right; Y := (R.Top+R.Bottom) div 2; end;
    4: begin X := R.Right; Y := R.Bottom; end;
    5: begin X := (R.Left+R.Right) div 2; Y := R.Bottom; end;
    6: Y := R.Bottom;
    7: Y := (R.Top+R.Bottom) div 2;
  end;
  var Size := ScaleValue(5); Result := Rect(X-Size,Y-Size,X+Size+1,Y+Size+1);
end;

procedure TRigmMoviePreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if Button=mbMiddle then begin
    FPanStart := Point(X,Y); FPanOriginal := FPan;
    FPanning := True; MouseCapture := True; Exit;
  end;
  if (Button<>mbLeft) or (FSession=nil) or FSession.GuiLocked or not FSession.CanEdit then Exit;
  FDragHandle := -1;
  if FSelectedCharacter<>'' then for var I := 0 to 7 do if PtInRect(HandleRect(FSelectedCharacter,I),Point(X,Y)) then FDragHandle := I;
  if FDragHandle<0 then begin
    FSelectedCharacter := '';
    for var I := FSession.Project.Characters.Count-1 downto 0 do begin
      var C := FSession.Project.Characters[I];
      if C.Visible and PtInRect(CharacterBounds(C.Id),Point(X,Y)) then begin FSelectedCharacter := C.Id; Break; end;
    end;
  end;
  var C := FSession.Project.Character(FSelectedCharacter);
  if C=nil then begin FViewDirty := True; Invalidate; Exit; end;
  if Assigned(FOnCharacterSelected) then FOnCharacterSelected(Self);
  FOriginal := RectF(C.X,C.Y,C.X+C.Width,C.Y+C.Height); FWorking := FOriginal;
  FDragStart := ScreenToBase(X,Y); FDragging := True; MouseCapture := True; FViewDirty := True; Invalidate;
  FDragRevision := FSession.Project.Revision; FDragProject := FSession.Project.Id;
end;

procedure TRigmMoviePreview.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if FPanning then begin
    FPan := Point(FPanOriginal.X+FPanStart.X-X,FPanOriginal.Y+FPanStart.Y-Y);
    ClampViewport; FViewDirty := True; Invalidate; Exit;
  end;
  if not FDragging then Exit;
  var P := ScreenToBase(X,Y); var DX := P.X-FDragStart.X; var DY := P.Y-FDragStart.Y;
  FWorking := FOriginal;
  if FDragHandle<0 then begin FWorking.Offset(DX,DY); end else begin
    if FDragHandle in [0,6,7] then FWorking.Left := FOriginal.Left+DX;
    if FDragHandle in [2,3,4] then FWorking.Right := FOriginal.Right+DX;
    if FDragHandle in [0,1,2] then FWorking.Top := FOriginal.Top+DY;
    if FDragHandle in [4,5,6] then FWorking.Bottom := FOriginal.Bottom+DY;
  end;
  FWorking.Left := Round(FWorking.Left/10)*10; FWorking.Top := Round(FWorking.Top/10)*10;
  FWorking.Right := Max(FWorking.Left+20,Round(FWorking.Right/10)*10);
  FWorking.Bottom := Max(FWorking.Top+20,Round(FWorking.Bottom/10)*10);
  if FSession.Project.Layout='l' then begin
    var Center := (FWorking.Left+FWorking.Right)/2;
    if (FSession.Project.LDirection='left') and (Center>720) then FWorking.Offset(720-Center,0);
    if (FSession.Project.LDirection='right') and (Center<1200) then FWorking.Offset(1200-Center,0);
  end;
  FViewDirty := True; Invalidate;
end;

procedure TRigmMoviePreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if FPanning then begin FPanning := False; MouseCapture := False; Exit; end;
  if (Button<>mbLeft) or not FDragging then Exit;
  MouseMove(Shift,X,Y); FDragging := False; MouseCapture := False;
  if FSession.GuiLocked or not FSession.CanEdit or (FSession.Project.Revision<>FDragRevision) or (FSession.Project.Id<>FDragProject) then begin FViewDirty := True; Invalidate; Exit; end;
  var O := TJSONObject.Create;
  try
    O.AddPair('id',FSelectedCharacter); O.AddPair('projectId',FDragProject); AddN(O,'revision',FDragRevision);
    AddN(O,'x',FWorking.Left); AddN(O,'y',FWorking.Top); AddN(O,'width',FWorking.Width); AddN(O,'height',FWorking.Height);
    var Reply := FSession.Execute('update-character',O); Reply.Free;
  finally O.Free; FViewDirty := True; Invalidate; end;
end;
end.
