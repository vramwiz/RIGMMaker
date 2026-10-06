unit RigmPlacementGeometry;
// 配置の作品座標と画面座標、既存プレビューの時計回り8点ハンドルを共有する。
interface
uses System.Types;
function PlacementHandle(const R: TRect; Index, Size: Integer): TRect;
function DragPlacement(const Original, Area: TRectF; Handle: Integer; DX,DY: Double; KeepAspect,Snap: Boolean): TRectF;
implementation
uses System.Math;
function PlacementHandle(const R: TRect; Index, Size: Integer): TRect;
begin
  var X := R.Left; var Y := R.Top;
  case Index of
    1: X := (R.Left+R.Right) div 2;
    2: X := R.Right;
    3: begin X := R.Right; Y := (R.Top+R.Bottom) div 2; end;
    4: begin X := R.Right; Y := R.Bottom; end;
    5: begin X := (R.Left+R.Right) div 2; Y := R.Bottom; end;
    6: Y := R.Bottom;
    7: Y := (R.Top+R.Bottom) div 2;
  end;
  Result := Rect(X-Size,Y-Size,X+Size+1,Y+Size+1);
end;
function DragPlacement(const Original, Area: TRectF; Handle: Integer; DX,DY: Double; KeepAspect,Snap: Boolean): TRectF;
begin
  Result := Original;
  if Handle<0 then begin
    var X := Original.Left+DX; var Y := Original.Top+DY;
    if Snap then begin X := Round(X/10)*10; Y := Round(Y/10)*10; end;
    Result.Offset(X-Original.Left,Y-Original.Top);
  end else begin
    var W: Double := Original.Width; var H: Double := Original.Height;
    if Handle in [0,6,7] then W := W-DX else if Handle in [2,3,4] then W := W+DX;
    if Handle in [0,1,2] then H := H-DY else if Handle in [4,5,6] then H := H+DY;
    W := Max(20,W); H := Max(20,H); var Ratio := Original.Width/Original.Height;
    var HeightDrives := (Handle in [1,5]) or ((Handle in [0,2,4,6]) and (Abs(H/Original.Height-1)>Abs(W/Original.Width-1)));
    if KeepAspect then begin
      if HeightDrives then begin if Snap then H := Max(20,Round(H/10)*10); H := Max(H,20/Ratio); W := H*Ratio; end
      else begin if Snap then W := Max(20,Round(W/10)*10); W := Max(W,20*Ratio); H := W/Ratio; end;
    end else if Snap then begin W := Max(20,Round(W/10)*10); H := Max(20,Round(H/10)*10); end;
    if Handle in [0,6,7] then begin Result.Left := Original.Right-W; Result.Right := Original.Right; end
    else if Handle in [2,3,4] then Result.Right := Result.Left+W
    else begin Result.Left := (Original.Left+Original.Right-W)/2; Result.Right := Result.Left+W; end;
    if Handle in [0,1,2] then begin Result.Top := Original.Bottom-H; Result.Bottom := Original.Bottom; end
    else if Handle in [4,5,6] then Result.Bottom := Result.Top+H
    else begin Result.Top := (Original.Top+Original.Bottom-H)/2; Result.Bottom := Result.Top+H; end;
  end;
  var K := Min(1.0,Min(Area.Width/Result.Width,Area.Height/Result.Height));
  var W := Result.Width*K; var H := Result.Height*K;
  Result.Right := Result.Left+W; Result.Bottom := Result.Top+H;
  Result.Offset(EnsureRange(Result.Left,Area.Left,Area.Right-W)-Result.Left,EnsureRange(Result.Top,Area.Top,Area.Bottom-H)-Result.Top);
end;
end.
