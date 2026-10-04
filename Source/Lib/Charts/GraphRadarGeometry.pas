unit GraphRadarGeometry;

// 回転後のN角形の外接範囲を編集枠へ合わせ、描画と演出の座標を共有する。
interface
uses System.Types;
type
  TGraphRadarGeometry=record
    Center:TPointF;
    ScaleX,ScaleY:Single;
    class function Fit(const Bounds:TRectF; Rows:Integer; Rotation:Single):TGraphRadarGeometry; static;
    function PointAt(Degrees,Fraction:Double):TPointF;
  end;
implementation
uses System.Math, System.SysUtils;
class function TGraphRadarGeometry.Fit(const Bounds:TRectF; Rows:Integer;
  Rotation:Single):TGraphRadarGeometry;
var I:Integer; Angle,X,Y,MinX,MaxX,MinY,MaxY:Double;
begin
  if Rows<3 then raise EConvertError.Create('レーダーチャートは要素数を3以上にしてください。');
  MinX:=1; MaxX:=-1; MinY:=1; MaxY:=-1;
  for I:=0 to Rows-1 do
  begin
    Angle:=DegToRad(-90+Rotation+I*360/Rows);
    X:=Cos(Angle); Y:=Sin(Angle);
    MinX:=Min(MinX,X); MaxX:=Max(MaxX,X);
    MinY:=Min(MinY,Y); MaxY:=Max(MaxY,Y);
  end;
  Result.ScaleX:=Bounds.Width/(MaxX-MinX);
  Result.ScaleY:=Bounds.Height/(MaxY-MinY);
  Result.Center:=PointF(Bounds.Left-MinX*Result.ScaleX,
    Bounds.Top-MinY*Result.ScaleY);
end;
function TGraphRadarGeometry.PointAt(Degrees,Fraction:Double):TPointF;
begin
  Result:=PointF(Center.X+Cos(DegToRad(Degrees))*ScaleX*Fraction,
    Center.Y+Sin(DegToRad(Degrees))*ScaleY*Fraction);
end;
end.
