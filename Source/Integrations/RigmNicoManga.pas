unit RigmNicoManga;

// ニコニコ漫画の公開検索・作品ページだけを読み取る。UIスレッドでHTTPを実行しない。
interface
uses System.Classes, System.JSON;
function NicoComicUrl(const Value: string): Boolean;
function ParseNicoComic(const Html,Url: string): TJSONObject; // 呼出側所有。
function NicoSearchUrls(const Html: string): TArray<string>;
type
  TRigmNicoSearch = class(TThread)
  protected
    procedure Execute; override;
  public
    Query,ProjectId,ResearchId,Error: string;
    Candidates: TJSONArray;
    constructor Create;
    destructor Destroy; override;
  end;
implementation
uses System.SysUtils, System.RegularExpressions, System.NetEncoding, System.Net.HttpClient,
  System.Generics.Collections;

function NicoComicUrl(const Value: string): Boolean;
begin Result := TRegEx.IsMatch(Value,'^https://manga\.nicovideo\.jp/comic/[0-9]+$',[roIgnoreCase]); end;
function Plain(const Value: string): string;
begin Result := Trim(TRegEx.Replace(TNetEncoding.HTML.Decode(TRegEx.Replace(Value,'<[^>]*>',' ')),'\s+',' ')); end;
function Attribute(const Tag,Name: string): string;
begin
  var M := TRegEx.Match(Tag,'\b'+Name+'\s*=\s*(?:"([^"]*)"|''([^'']*)'')',[roIgnoreCase]);
  Result := ''; if not M.Success then Exit;
  Result := M.Groups[1].Value; if not M.Groups[1].Success then Result := M.Groups[2].Value;
  Result := TNetEncoding.HTML.Decode(Result);
end;
function Meta(const Html,Name: string): string;
begin
  Result := '';
  for var M in TRegEx.Matches(Html,'<meta\b[^>]*>',[roIgnoreCase]) do
    if SameText(Attribute(M.Value,'property'),Name) or SameText(Attribute(M.Value,'name'),Name) then
      Exit(Attribute(M.Value,'content'));
end;
function ParseNicoComic(const Html,Url: string): TJSONObject;
begin
  if not NicoComicUrl(Url) then raise Exception.Create('ニコニコ漫画の作品URLではありません。');
  var LabelText := Meta(Html,'og:title'); var Split := LabelText.LastIndexOf(' / ');
  if Split<1 then raise Exception.Create('ニコニコ漫画の作品名・作者を取得できませんでした。');
  var Name := LabelText.Substring(0,Split); var Author := LabelText.Substring(Split+3);
  var Body := TRegEx.Match(Html,'<div\s+class="description_text"[^>]*>(.*?)</div>',[roIgnoreCase,roSingleLine]);
  var Overview := ''; if Body.Success then Overview := Plain(Body.Groups[1].Value);
  if Overview='' then Overview := Meta(Html,'og:description');
  if (Name='') or (Author='') or (Overview='') then raise Exception.Create('ニコニコ漫画の作品情報が空です。');
  Result := TJSONObject.Create;
  Result.AddPair('id','nico-'+Url.Substring(Url.LastIndexOf('/')+1));
  Result.AddPair('name',Name.Substring(0,256)); Result.AddPair('author',Author.Substring(0,1000));
  Result.AddPair('identity','作者:'+Author.Substring(0,1000));
  Result.AddPair('overview',Overview.Substring(0,3000)); Result.AddPair('niconicoUrl',Url);
  var Sources := TJSONArray.Create; Sources.Add(Url); Result.AddPair('sources',Sources);
end;
function NicoSearchUrls(const Html: string): TArray<string>;
begin
  if not Html.Contains('search_result') then raise Exception.Create('ニコニコ漫画の検索結果を読み取れませんでした。');
  var Items := TList<string>.Create;
  try
    for var M in TRegEx.Matches(Html,'href="/comic/([0-9]+)(?:\?[^"<>]*)?"') do begin
      var Url := 'https://manga.nicovideo.jp/comic/'+M.Groups[1].Value;
      if not Items.Contains(Url) then Items.Add(Url);
      if Items.Count=6 then Break;
    end;
    Result := Items.ToArray;
  finally Items.Free; end;
end;
constructor TRigmNicoSearch.Create;
begin inherited Create(True); FreeOnTerminate := False; Candidates := TJSONArray.Create; end;
destructor TRigmNicoSearch.Destroy;
begin Candidates.Free; inherited; end;
procedure TRigmNicoSearch.Execute;
  function Get(const Url: string): string;
  begin
    var Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := 4000; Client.ResponseTimeout := 6000;
      Client.UserAgent := 'RIGMMaker/1.0';
      var Response := Client.Get(Url);
      if Response.StatusCode<>200 then raise Exception.CreateFmt('ニコニコ漫画の取得に失敗しました（HTTP %d）。',[Response.StatusCode]);
      Result := Response.ContentAsString(TEncoding.UTF8);
      if Length(Result)>4*1024*1024 then raise Exception.Create('ニコニコ漫画の応答が大きすぎます。');
    finally Client.Free; end;
  end;
begin
  try
    var Urls := NicoSearchUrls(Get('https://manga.nicovideo.jp/search/?q='+TNetEncoding.URL.Encode(Query)));
    for var Url in Urls do begin
      if Terminated then Exit;
      Candidates.AddElement(ParseNicoComic(Get(Url),Url));
    end;
  except on E: Exception do Error := E.Message; end;
end;
end.
