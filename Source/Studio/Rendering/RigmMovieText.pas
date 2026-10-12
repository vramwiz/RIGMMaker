unit RigmMovieText;
// 動画内の文字は黒い縁取りを共通の既定とする。文字輪郭を一度だけ描き、通常の文字を重ねる。
interface
uses System.Types, Vcl.Graphics;
function DrawMovieText(Canvas: TCanvas; const Value: string; const Bounds: TRect; Flags: Cardinal): Integer;
// チャプター名と補足文用。文字量に合わせた65%の黒い半透明背景を付ける。
function DrawMovieLabel(Canvas: TCanvas; const Value: string; const Bounds: TRect; Flags: Cardinal): Integer;
implementation
uses System.SysUtils, System.Math, Winapi.Windows;
procedure TextGdiCheck(Success: Boolean; const Operation: string);
begin
  if Success then Exit;
  var Code := GetLastError;
  var E := EOSError.CreateFmt('映像文字描画 %s に失敗しました (Windows %d; GDI=%d): %s',
    [Operation,Code,GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS),SysErrorMessage(Code)]);
  E.ErrorCode := Code; raise E;
end;
function DrawMovieText(Canvas: TCanvas; const Value: string; const Bounds: TRect; Flags: Cardinal): Integer;
begin
  Result := 0; if Value='' then Exit;
  // VCLのメッセージ処理によるFreeMemoryContextsから、GDI呼出中のDCを守る。
  Canvas.Lock;
  try
    Canvas.TextHeight('M'); // VCLのフォントをDCへ選択してからGDIを使う。
    var DC := Canvas.Handle; SetLastError(0); var Saved := SaveDC(DC); TextGdiCheck(Saved<>0,'SaveDC');
    var Pen: HPEN := 0;
    try
      SetBkMode(DC,TRANSPARENT); SetTextColor(DC,ColorToRGB(Canvas.Font.Color));
      var Radius := Max(1,Round(Abs(Canvas.Font.Height)/18));
      var Brush: TLogBrush; Brush.lbStyle := BS_SOLID; Brush.lbColor := RGB(0,0,0); Brush.lbHatch := 0;
      SetLastError(0);
      Pen := ExtCreatePen(PS_GEOMETRIC or PS_SOLID or PS_JOIN_ROUND or PS_ENDCAP_ROUND,Radius*2,Brush,0,nil);
      TextGdiCheck(Pen<>0,'ExtCreatePen');
      SetLastError(0); var Previous := SelectObject(DC,Pen);
      TextGdiCheck((Previous<>0) and (Previous<>HGDIOBJ(-1)),'SelectObject(text pen)');
      var R := Bounds; SetLastError(0); TextGdiCheck(BeginPath(DC),'BeginPath');
      try
        DrawText(DC,PChar(Value),Length(Value),R,Flags or DT_NOPREFIX);
        SetLastError(0); TextGdiCheck(EndPath(DC),'EndPath');
        SetLastError(0); TextGdiCheck(StrokePath(DC),'StrokePath');
      finally AbortPath(DC); end;
      // 通常描画を最後に重ね、細い文字の白い内部とフォントの描画品質を維持する。
      R := Bounds; Result := DrawText(DC,PChar(Value),Length(Value),R,Flags or DT_NOPREFIX);
    finally
      RestoreDC(DC,Saved); if Pen<>0 then DeleteObject(Pen);
    end;
  finally Canvas.Unlock; end;
end;
function DrawMovieLabel(Canvas: TCanvas; const Value: string; const Bounds: TRect; Flags: Cardinal): Integer;
begin
  Result := 0; if (Value='') or Bounds.IsEmpty then Exit;
  Canvas.Lock;
  try
    if Trim(Value)='' then Exit(DrawMovieText(Canvas,Value,Bounds,Flags));
    Canvas.TextHeight('M');
    var Measured := Rect(0,0,Bounds.Width,Bounds.Height);
    if DrawText(Canvas.Handle,PChar(Value),Length(Value),Measured,Flags or DT_CALCRECT or DT_NOPREFIX)=0 then Exit;
    var W := Min(Bounds.Width,Measured.Width); var H := Min(Bounds.Height,Measured.Height);
    var L := Bounds.Left; var T := Bounds.Top;
    if (Flags and DT_CENTER)<>0 then Inc(L,(Bounds.Width-W) div 2)
    else if (Flags and DT_RIGHT)<>0 then Inc(L,Bounds.Width-W);
    if (Flags and DT_SINGLELINE)<>0 then begin
      if (Flags and DT_VCENTER)<>0 then Inc(T,(Bounds.Height-H) div 2)
      else if (Flags and DT_BOTTOM)<>0 then Inc(T,Bounds.Height-H);
    end;
    var Backdrop := Rect(L,T,L+W,T+H);
    InflateRect(Backdrop,Max(2,Abs(Canvas.Font.Height) div 3),Max(2,Abs(Canvas.Font.Height) div 6));
    var Clip := Canvas.ClipRect;
    if IntersectRect(Backdrop,Backdrop,Clip) then begin
      var Black := Vcl.Graphics.TBitmap.Create;
      try
        Black.PixelFormat := pf32bit; Black.SetSize(1,1);
        // Source HDC must stay valid from Handle acquisition through AlphaBlend.
        // Locking only the destination leaves the worker's black bitmap vulnerable.
        Black.Canvas.Lock;
        try
          Black.Canvas.Brush.Color := clBlack; Black.Canvas.FillRect(Rect(0,0,1,1));
          var Blend := Default(TBlendFunction); Blend.BlendOp := AC_SRC_OVER; Blend.SourceConstantAlpha := 166;
          SetLastError(0);
          TextGdiCheck(AlphaBlend(Canvas.Handle,Backdrop.Left,Backdrop.Top,Backdrop.Width,Backdrop.Height,
            Black.Canvas.Handle,0,0,1,1,Blend),'AlphaBlend(label backdrop)');
        finally Black.Canvas.Unlock; end;
      finally Black.Free; end;
    end;
    Result := DrawMovieText(Canvas,Value,Bounds,Flags);
  finally Canvas.Unlock; end;
end;
end.