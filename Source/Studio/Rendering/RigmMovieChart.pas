// 場面チャートの保存値を検証し、指定された矩形へ描画する。作品の編集状態は変更しない。
unit RigmMovieChart;

interface
uses System.JSON, System.Types, Vcl.Graphics;
procedure ValidateMovieChart(Chart: TJSONObject);
procedure DrawMovieChart(Canvas: TCanvas; Chart: TJSONObject; const Bounds: TRect);
function MovieChartEnabled(Chart: TJSONObject): Boolean;
const MovieChartKinds: array[0..2] of string = ('none','radar','bar');

implementation
uses Winapi.Windows, System.SysUtils, System.Math, System.StrUtils, System.Generics.Collections, RigmModel,
  RigmJson, GraphRadarGeometry;

function MovieChartEnabled(Chart: TJSONObject): Boolean;
begin Result := (Chart<>nil) and not SameText(JS(Chart,'kind','none'),'none'); end;

procedure ValidateMovieChart(Chart: TJSONObject);
begin
  if Chart=nil then Exit;
  var Kind := JS(Chart,'kind','none');
  if not MatchText(Kind,['none','radar','bar']) then raise ERigm.Create('総評チャートは none / radar / bar を指定してください。');
  Kind := LowerCase(Kind);
  if Kind='none' then Exit;
  if Length(JS(Chart,'title'))>120 then raise ERigm.Create('総評チャートの題名は120文字以内です。');
  var Maximum := JN(Chart,'maximum',5);
  var MinimumValue := JN(Chart,'minimum',0); if not Finite(MinimumValue) or (MinimumValue< -10000) or (MinimumValue>=Maximum) then raise ERigm.Create('チャートの最小値は-10000以上、最大値未満です。');
  if not Finite(Maximum) or (Maximum<0.1) or (Maximum>10000) then raise ERigm.Create('チャートの満点は0.1から10000です。');
  var Color := JS(Chart,'color','#5AB8E8'); var Number: Integer;
  if (Length(Color)<>7) or (Color[1]<>'#') or not TryStrToInt('$'+Copy(Color,2,6),Number) then
    raise ERigm.Create('チャートの色は #RRGGBB を指定してください。');
  if not(Chart.GetValue('items') is TJSONArray) then raise ERigm.Create('チャートには項目と値の配列が必要です。');
  var Items := JA(Chart,'items'); var Minimum := 1; if Kind='radar' then Minimum := 3;
  if (Items.Count<Minimum) or (Items.Count>8) then raise ERigm.CreateFmt('チャートの項目数は%dから8です。',[Minimum]);
  for var Item in Items do begin
    if not(Item is TJSONObject) then raise ERigm.Create('チャートの項目はオブジェクトです。');
    var O := TJSONObject(Item); var Value := JN(O,'value',-1); var LabelText := JS(O,'label').Trim;
    if (LabelText='') or (Length(LabelText)>24) then raise ERigm.Create('項目名は1から24文字です。');
    if not Finite(Value) or (Value<MinimumValue) or (Value>Maximum) then raise ERigm.Create('項目の値は最小値以上、最大値以下にしてください。');
  end;
end;

procedure DrawMovieChart(Canvas: TCanvas; Chart: TJSONObject; const Bounds: TRect);
var Scale: Double; Accent: TColor;
  function Px(Value: Double): Integer;
  begin Result := Max(1,Round(Value*Scale)); end;
  procedure Text(const Value: string; const R: TRect; Size: Integer; Center: Boolean);
  begin
    Canvas.Brush.Style := bsClear; Canvas.Font.Name := 'Yu Gothic UI';
    Canvas.Font.Height := -Px(Size); Canvas.Font.Color := $F4F0E9;
    var Box := R; var Flags := DT_NOPREFIX or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS;
    if Center then Flags := Flags or DT_CENTER else Flags := Flags or DT_LEFT;
    DrawText(Canvas.Handle,PChar(Value),Length(Value),Box,Flags);
  end;
begin
  if not MovieChartEnabled(Chart) then Exit;
  ValidateMovieChart(Chart);
  Scale := Min(Bounds.Width/980.0,Bounds.Height/550.0);
  var Number := StrToInt('$'+Copy(JS(Chart,'color','#5AB8E8'),2,6));
  Accent := RGB((Number shr 16) and 255,(Number shr 8) and 255,Number and 255);
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $302820; Canvas.Pen.Color := $75695D;
  Canvas.Pen.Width := Px(2); Canvas.Rectangle(Bounds);
  Text(JS(Chart,'title','総評'),Rect(Bounds.Left+Px(16),Bounds.Top+Px(12),Bounds.Right-Px(16),Bounds.Top+Px(65)),36,True);
  var Items := JA(Chart,'items'); var Maximum := JN(Chart,'maximum',5); var MinimumValue := JN(Chart,'minimum',0); var RangeValue := Maximum-MinimumValue;
  var Plot := Rect(Bounds.Left+Px(24),Bounds.Top+Px(80),Bounds.Right-Px(24),Bounds.Bottom-Px(22));
  if SameText(JS(Chart,'kind'),'bar') then begin
    var RowHeight := Plot.Height div Items.Count; var LabelWidth := Round(Plot.Width*0.26);
    var ValueWidth := Px(110); var StartX := Plot.Left+LabelWidth; var EndX := Plot.Right-ValueWidth;
    for var I := 0 to Items.Count-1 do begin
      var O := TJSONObject(Items[I]); var Y := Plot.Top+I*RowHeight;
      Text(JS(O,'label'),Rect(Plot.Left,Y,StartX-Px(10),Y+RowHeight),29,False);
      var Bar := Rect(StartX,Y+RowHeight div 4,EndX,Y+RowHeight*3 div 4);
      Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $554C43; Canvas.FillRect(Bar);
      Bar.Right := StartX+Round((EndX-StartX)*(JN(O,'value')-MinimumValue)/RangeValue);
      Canvas.Brush.Color := Accent; Canvas.FillRect(Bar);
      Text(FormatFloat('0.#',JN(O,'value'),TFormatSettings.Invariant)+' / '+FormatFloat('0.#',Maximum,TFormatSettings.Invariant),
        Rect(EndX+Px(8),Y,Plot.Right,Y+RowHeight),27,False);
    end;
  end else begin
    var Radius := Min(Plot.Width*0.27,Plot.Height*0.31);
    var Center := PointF((Plot.Left+Plot.Right)/2,(Plot.Top+Plot.Bottom)/2);
    var RadarBounds := RectF(Center.X-Radius,Center.Y-Radius,Center.X+Radius,Center.Y+Radius);
    var Geometry := TGraphRadarGeometry.Fit(RadarBounds,Items.Count,0);
    var Points: TArray<TPoint>; SetLength(Points,Items.Count);
    Canvas.Brush.Style := bsClear;
    for var Ring := 1 to 5 do begin
      for var I := 0 to Items.Count-1 do begin
        var P := Geometry.PointAt(-90+I*360/Items.Count,Ring/5.0); Points[I] := Point(Round(P.X),Round(P.Y));
      end;
      Canvas.Pen.Color := $75695D; Canvas.Pen.Width := Px(1); Canvas.Polygon(Points);
    end;
    for var I := 0 to Items.Count-1 do begin
      var P := Geometry.PointAt(-90+I*360/Items.Count,1);
      Canvas.Pen.Color := $75695D; Canvas.MoveTo(Round(Geometry.Center.X),Round(Geometry.Center.Y)); Canvas.LineTo(Round(P.X),Round(P.Y));
      var O := TJSONObject(Items[I]); P := Geometry.PointAt(-90+I*360/Items.Count,(JN(O,'value')-MinimumValue)/RangeValue);
      Points[I] := Point(Round(P.X),Round(P.Y));
    end;
    Canvas.Pen.Color := Accent; Canvas.Pen.Width := Px(4); Canvas.Brush.Style := bsClear; Canvas.Polygon(Points);
    for var I := 0 to Items.Count-1 do begin
      var P := Geometry.PointAt(-90+I*360/Items.Count,1.35); var O := TJSONObject(Items[I]);
      var R := Rect(Round(P.X)-Px(108),Round(P.Y)-Px(18),Round(P.X)+Px(108),Round(P.Y)+Px(18));
      Text(JS(O,'label'),R,28,True); OffsetRect(R,0,Px(32));
      Text(FormatFloat('0.#',JN(O,'value'),TFormatSettings.Invariant)+' / '+FormatFloat('0.#',Maximum,TFormatSettings.Invariant),R,26,True);
    end;
  end;
  Canvas.Brush.Style := bsSolid; Canvas.Pen.Width := 1;
end;
end.
