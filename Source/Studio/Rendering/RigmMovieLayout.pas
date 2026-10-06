unit RigmMovieLayout;

// 既存合成のFHD構図を比率で共有する。キャラの実配置はここでは作らない。
interface
uses System.Types, System.JSON;
type
  TRigmLayoutRegions = record
    Image, Description, Subtitle, LeftCharacters, RightCharacters, Supplement: TRectF;
  end;
function MovieLayoutRegions(const Layout, Direction: string): TRigmLayoutRegions;
function ScaleLayoutRect(const Ratio: TRectF; Width, Height: Integer): TRect;
function MovieLayoutGuide(const Choice: string; Width, Height: Integer): TJSONObject;
function LayoutChoice(const Layout, Direction: string): string;
procedure DecodeLayoutChoice(const Choice: string; out Layout, Direction: string);
function LayoutBackgroundColor(const Tone: string): Cardinal;

implementation
uses System.SysUtils, RigmJson;
function RatioRect(L,T,R,B: Single): TRectF;
begin Result := RectF(L/1920,T/1080,R/1920,B/1080); end;
function MovieLayoutRegions(const Layout, Direction: string): TRigmLayoutRegions;
begin
  Result := Default(TRigmLayoutRegions);
  Result.Image := RatioRect(470,100,1450,650);
  Result.Description := RatioRect(500,670,1420,800);
  Result.Subtitle := RatioRect(40,855,1880,1045);
  if Layout='l' then begin
    if Direction='left' then begin
      Result.Image := RatioRect(800,120,1860,670);
      Result.Description := RatioRect(830,690,1830,820);
      Result.LeftCharacters := RatioRect(40,300,720,820);
      Result.Supplement := RatioRect(40,120,720,270);
    end else begin
      Result.Image := RatioRect(60,120,1120,670);
      Result.Description := RatioRect(90,690,1090,820);
      Result.RightCharacters := RatioRect(1200,300,1880,820);
      Result.Supplement := RatioRect(1200,120,1880,270);
    end;
  end else begin
    Result.LeftCharacters := RatioRect(40,180,430,820);
    Result.RightCharacters := RatioRect(1490,180,1880,820);
  end;
end;
function ScaleLayoutRect(const Ratio: TRectF; Width, Height: Integer): TRect;
begin Result := Rect(Round(Ratio.Left*Width),Round(Ratio.Top*Height),Round(Ratio.Right*Width),Round(Ratio.Bottom*Height)); end;
function LayoutChoice(const Layout, Direction: string): string;
begin
  Result := 'theme';
  if Layout='l' then if Direction='left' then Result := 'l-left' else Result := 'l-right';
end;
procedure DecodeLayoutChoice(const Choice: string; out Layout, Direction: string);
begin
  Layout := 'theme'; Direction := 'right';
  if Choice='l-left' then begin Layout := 'l'; Direction := 'left'; end
  else if Choice='l-right' then Layout := 'l'
  else if Choice<>'theme' then raise Exception.Create('中央型・L字型・逆L字型から選んでください。');
end;
function LayoutBackgroundColor(const Tone: string): Cardinal;
begin
  if Tone='dark' then Result := $302820
  else if Tone='light' then Result := $EDE6DD
  else if Tone='blue' then Result := $60422D
  else raise Exception.Create('共通背景色はdark・light・blueから選んでください。');
end;
function MovieLayoutGuide(const Choice: string; Width, Height: Integer): TJSONObject;
  procedure AddRegion(const Name: string; const R: TRectF);
  begin
    if R.IsEmpty then Exit;
    var O := TJSONObject.Create; AddN(O,'left',R.Left); AddN(O,'top',R.Top);
    AddN(O,'right',R.Right); AddN(O,'bottom',R.Bottom); Result.AddPair(Name,O);
  end;
begin
  var Layout,Direction: string; DecodeLayoutChoice(Choice,Layout,Direction);
  var R := MovieLayoutRegions(Layout,Direction);
  Result := TJSONObject.Create;
  Result.AddPair('choice',Choice); Result.AddPair('coordinateSpace','ratio');
  AddN(Result,'referenceWidth',1920); AddN(Result,'referenceHeight',1080);
  AddN(Result,'videoWidth',Width); AddN(Result,'videoHeight',Height);
  Result.AddPair('hasCommonBackground',TJSONBool.Create(Layout='theme'));
  AddRegion('image',R.Image); AddRegion('description',R.Description); AddRegion('subtitle',R.Subtitle);
  AddRegion('leftCharacters',R.LeftCharacters); AddRegion('rightCharacters',R.RightCharacters); AddRegion('supplement',R.Supplement);
end;
end.
