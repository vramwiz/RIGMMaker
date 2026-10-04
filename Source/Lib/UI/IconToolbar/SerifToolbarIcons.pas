// セリフ画面のページ選択ツールバーで使う、DPI対応の線画グリフを生成する。
unit SerifToolbarIcons;

interface

uses
  Vcl.Graphics, Vcl.ImgList;

type
  TSerifToolbarIcon = (stiProject, stiScenario, stiSerif, stiInput,
    stiChara, stiWatch, stiConfig, stiNewText, stiText, stiBoard);

// メインツールバーでも同じ形状を再利用できるよう、単体グリフ描画を公開する。
procedure DrawSerifToolbarIcon(Canvas: TCanvas; Kind: TSerifToolbarIcon;
  Size: Integer; GlyphColor: TColor);

// ボタンのImageIndexと同じ順序で、透過背景のアイコンをImageListへ構築する。
procedure BuildSerifToolbarIcons(Images: TCustomImageList; IconSize: Integer;
  GlyphColor: TColor);

implementation

uses
  System.Math, System.Types, Winapi.Windows;

const
  BASE_SIZE = 24;
  MASK_COLOR = TColor($00FF00FF);

procedure DrawSerifToolbarIcon(Canvas: TCanvas; Kind: TSerifToolbarIcon;
  Size: Integer; GlyphColor: TColor);
var
  Angle: Double;
  Center: Integer;
  GearPoints: array[0..15] of TPoint;
  Index: Integer;
  Radius: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, Size, BASE_SIZE);
  end;

begin
  Center := Size div 2;
  Canvas.Pen.Color := GlyphColor;
  Canvas.Pen.Width := Max(1, S(2));
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Color := GlyphColor;
  Canvas.Brush.Style := bsClear;

  case Kind of
    stiProject:
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Polygon([Point(S(2), S(7)), Point(S(9), S(7)),
          Point(S(11), S(5)), Point(S(16), S(5)), Point(S(18), S(8)),
          Point(S(22), S(8)), Point(S(20), S(20)), Point(S(2), S(20))]);
      end;
    stiScenario:
      begin
        // 中央で開いた本。
        Canvas.Pen.Width := Max(1, S(1));
        Canvas.Polyline([Point(S(2), S(5)), Point(S(7), S(4)),
          Point(S(12), S(7)), Point(S(12), S(21)), Point(S(7), S(18)),
          Point(S(2), S(19)), Point(S(2), S(5))]);
        Canvas.Polyline([Point(S(22), S(5)), Point(S(17), S(4)),
          Point(S(12), S(7)), Point(S(12), S(21)), Point(S(17), S(18)),
          Point(S(22), S(19)), Point(S(22), S(5))]);
      end;
    stiSerif:
      begin
        // セリフを表す吹き出し。
        Canvas.RoundRect(S(2), S(3), S(22), S(17), S(5), S(5));
        Canvas.Polyline([Point(S(8), S(17)), Point(S(6), S(22)),
          Point(S(13), S(17))]);
      end;
    stiInput:
      begin
        // 入力・修正用の鉛筆。
        Canvas.Pen.Width := Max(1, S(2));
        Canvas.Polyline([Point(S(4), S(18)), Point(S(6), S(12)),
          Point(S(16), S(2)), Point(S(22), S(8)), Point(S(12), S(18)),
          Point(S(4), S(20)), Point(S(4), S(18))]);
        Canvas.MoveTo(S(7), S(12));
        Canvas.LineTo(S(12), S(17));
      end;
    stiChara:
      begin
        // 頭部と肩で配役を示す上半身。
        Canvas.Ellipse(S(8), S(2), S(16), S(10));
        Canvas.Polyline([Point(S(3), S(22)), Point(S(4), S(18)),
          Point(S(8), S(13)), Point(S(16), S(13)), Point(S(20), S(18)),
          Point(S(21), S(22))]);
      end;
    stiWatch:
      begin
        // 監視状態を表す目。
        Canvas.Polygon([Point(S(2), S(12)), Point(S(6), S(7)),
          Point(S(12), S(5)), Point(S(18), S(7)), Point(S(22), S(12)),
          Point(S(18), S(17)), Point(S(12), S(19)), Point(S(6), S(17))]);
        Canvas.Brush.Style := bsSolid;
        Canvas.Ellipse(S(9), S(9), S(15), S(15));
      end;
    stiConfig:
      begin
        // VOICEVOX設定と同系統の歯車。
        for Index := 0 to High(GearPoints) do
        begin
          Angle := -Pi / 2 + Index * Pi / 8;
          if Odd(Index) then
            Radius := S(7)
          else
            Radius := S(11);
          GearPoints[Index] := Point(Center + Round(Cos(Angle) * Radius),
            Center + Round(Sin(Angle) * Radius));
        end;
        Canvas.Brush.Style := bsSolid;
        Canvas.Polygon(GearPoints);
        Canvas.Pen.Color := MASK_COLOR;
        Canvas.Brush.Color := MASK_COLOR;
        Canvas.Ellipse(Center - S(3), Center - S(3),
          Center + S(3) + 1, Center + S(3) + 1);
      end;
    stiNewText:
      begin
        // 新セリフ表示を、小型のAと右上の輝きで表す。
        Canvas.Pen.Width := Max(1, S(2));
        Canvas.Polyline([Point(S(3), S(21)), Point(S(10), S(5)),
          Point(S(17), S(21))]);
        Canvas.MoveTo(S(6), S(15));
        Canvas.LineTo(S(14), S(15));
        Canvas.Pen.Width := Max(1, S(1));
        Canvas.MoveTo(S(19), S(2));
        Canvas.LineTo(S(19), S(10));
        Canvas.MoveTo(S(15), S(6));
        Canvas.LineTo(S(23), S(6));
        Canvas.MoveTo(S(16), S(3));
        Canvas.LineTo(S(22), S(9));
        Canvas.MoveTo(S(22), S(3));
        Canvas.LineTo(S(16), S(9));
      end;
    stiText:
      begin
        // セリフ表示を表す大文字のA。
        Canvas.Pen.Width := Max(1, S(2));
        Canvas.Polyline([Point(S(4), S(21)), Point(S(12), S(3)),
          Point(S(20), S(21))]);
        Canvas.MoveTo(S(7), S(15));
        Canvas.LineTo(S(17), S(15));
      end;
    stiBoard:
      begin
        // セリフ枠を表す二重の角丸矩形。
        Canvas.RoundRect(S(2), S(3), S(22), S(21), S(4), S(4));
        Canvas.Pen.Width := Max(1, S(1));
        Canvas.RoundRect(S(5), S(6), S(19), S(18), S(3), S(3));
      end;
  end;
end;

procedure BuildSerifToolbarIcons(Images: TCustomImageList; IconSize: Integer;
  GlyphColor: TColor);
var
  Bitmap: Vcl.Graphics.TBitmap;
  Kind: TSerifToolbarIcon;
begin
  if not Assigned(Images) or (IconSize <= 0) then Exit;
  Images.Clear;
  Images.Width := IconSize;
  Images.Height := IconSize;
  Images.Masked := True;
  Images.BkColor := clNone;

  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.PixelFormat := pf24bit;
    Bitmap.SetSize(IconSize, IconSize);
    for Kind := Low(TSerifToolbarIcon) to High(TSerifToolbarIcon) do
    begin
      Bitmap.Canvas.Brush.Style := bsSolid;
      Bitmap.Canvas.Brush.Color := MASK_COLOR;
      Bitmap.Canvas.FillRect(Rect(0, 0, IconSize, IconSize));
      DrawSerifToolbarIcon(Bitmap.Canvas, Kind, IconSize, GlyphColor);
      Images.AddMasked(Bitmap, MASK_COLOR);
    end;
  finally
    Bitmap.Free;
  end;
end;

end.
