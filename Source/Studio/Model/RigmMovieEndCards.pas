unit RigmMovieEndCards;
// 発話sceneに偽の無音セリフを追加せず、独立した末尾カードを保持する。
interface
uses System.JSON, System.Types;
procedure ValidateMovieEndCards(Cards: TJSONArray);
procedure ValidateCardRect(O: TJSONObject);
function MovieEndCardsDuration(Cards: TJSONArray): Double;
function MovieEndCardAt(Cards: TJSONArray; Seconds: Double): TJSONObject;
function CardRect(O: TJSONObject; Width,Height: Integer): TRect;
implementation
uses System.SysUtils, System.Math, RigmJson, RigmModel;
procedure ValidateCardRect(O: TJSONObject);
begin
  for var Key in ['x','y','width','height'] do if not(O.GetValue(Key) is TJSONNumber) or not Finite(JN(O,Key)) then raise ERigm.Create('画像と回避領域は有限の割合座標です。');
  if (JN(O,'x')<0) or (JN(O,'y')<0) or (JN(O,'width')<=0) or (JN(O,'height')<=0) or (JN(O,'x')+JN(O,'width')>1.000001) or (JN(O,'y')+JN(O,'height')>1.000001) then raise ERigm.Create('画像と回避領域は0～1の画面内に収めてください。');
end;
function CardRect(O: TJSONObject; Width,Height: Integer): TRect;
begin Result := Rect(Round(JN(O,'x')*Width),Round(JN(O,'y')*Height),Round((JN(O,'x')+JN(O,'width'))*Width),Round((JN(O,'y')+JN(O,'height'))*Height)); end;
procedure ValidateMovieEndCards(Cards: TJSONArray);
begin
  if Cards=nil then Exit; if Cards.Count>2 then raise ERigm.Create('末尾カードは終了画像・サムネイルの2枚以内です。'); var Previous := '';
  for var V in Cards do begin
    if not(V is TJSONObject) then raise ERigm.Create('末尾カードの形式が不正です。'); var O := TJSONObject(V); var Kind := JS(O,'kind');
    if not((Kind='end') or (Kind='thumbnail')) or (Previous='thumbnail') or (Kind=Previous) then raise ERigm.Create('末尾カードは終了画像→サムネイルの順です。'); Previous := Kind;
    if not(O.GetValue('image') is TJSONString) or (JS(O,'image')='') or (Length(JS(O,'image'))>32760) or not(O.GetValue('duration') is TJSONNumber) or not Finite(JN(O,'duration')) or (JN(O,'duration')<0.5) or (JN(O,'duration')>30) then raise ERigm.Create('末尾カードには既存画像と0.5～30秒の長さが必要です。');
    if not(O.GetValue('rect') is TJSONObject) then raise ERigm.Create('画像配置がありません。'); ValidateCardRect(JO(O,'rect'));
    if Kind='end' then begin
      if not(O.GetValue('reserved') is TJSONArray) or (JA(O,'reserved').Count<1) or (JA(O,'reserved').Count>6) then raise ERigm.Create('YouTubeテンプレートの回避領域を1～6個指定してください。');
      var Image := JO(O,'rect'); for var R in JA(O,'reserved') do begin if not(R is TJSONObject) then raise ERigm.Create('回避領域の形式が不正です。'); var Region := TJSONObject(R); ValidateCardRect(Region);
        if (JN(Image,'x')<JN(Region,'x')+JN(Region,'width')-0.000001) and (JN(Image,'x')+JN(Image,'width')>JN(Region,'x')+0.000001) and (JN(Image,'y')<JN(Region,'y')+JN(Region,'height')-0.000001) and (JN(Image,'y')+JN(Image,'height')>JN(Region,'y')+0.000001) then raise ERigm.Create('終了画像の配置がYouTube回避領域と重なっています。');
      end;
    end;
  end;
end;
function MovieEndCardsDuration(Cards: TJSONArray): Double;
begin Result := 0; if Cards<>nil then for var V in Cards do Result := Result+JN(TJSONObject(V),'duration'); end;
function MovieEndCardAt(Cards: TJSONArray; Seconds: Double): TJSONObject;
begin Result := nil; if (Cards=nil) or (Seconds<0) then Exit; var Start := 0.0; for var V in Cards do begin var O := TJSONObject(V); if Seconds<Start+JN(O,'duration') then Exit(O); Start := Start+JN(O,'duration'); end; end;
end.
