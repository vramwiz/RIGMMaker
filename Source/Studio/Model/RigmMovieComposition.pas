// 複数キャラクターと場面の配置・素材・説明を保存するモデル。JSON変換と保存値の検証を担当する。
unit RigmMovieComposition;

interface
uses System.SysUtils, System.JSON, RigmModel;
type
  TRigmMovieCharacter = class
  public
    Id,Name,FileName,SpeakerId,InitialPosition: string;
    RenderFormat: string; // rigm/psd。旧作品は拡張子から補完する。
    PsdView: TJSONObject; // 所有。PSD固有の視線/ポーズ/小動作。共通作品内へ保存。
    X,Y,Width,Height: Double;
    Visible,RigSafe,AllowGeneratedExpressions: Boolean;
    Expressions: TJSONObject;
    Motions: TJSONObject;
    ActiveMotion: string;
    MotionStart,MotionDuration: Double;
    constructor Create;
    destructor Destroy; override;
    function Json: TJSONObject;
    class function FromJson(O: TJSONObject): TRigmMovieCharacter; static;
    procedure Validate;
    function MotionFrame(Seconds: Double; out Image: string): Boolean;
  end;
  TRigmMovieScene = class
  public
    Id,Title,Image,Description,ImagePrompt: string;
    Padding: Double;
    // Reserved timing/animation metadata. No implicit animation is generated.
    Animation,Chart: TJSONObject;
    constructor Create;
    destructor Destroy; override;
    function Json: TJSONObject;
    class function FromJson(O: TJSONObject): TRigmMovieScene; static;
    procedure Validate;
  end;
implementation
uses System.Math, System.StrUtils, RigmJson, RigmMovieChart;
constructor TRigmMovieCharacter.Create;
begin
  inherited; Id := NewRigmId; Name := 'キャラクター'; SpeakerId := 'narrator'; InitialPosition := 'right';
  X := 1370; Y := 130; Width := 520; Height := 900; Visible := True; RigSafe := True;
  RenderFormat := 'rigm'; PsdView := TJSONObject.Create;
  Expressions := TJSONObject.Create;
  Motions := TJSONObject.Create; MotionDuration := -1;
end;
destructor TRigmMovieCharacter.Destroy;
begin PsdView.Free; Motions.Free; Expressions.Free; inherited; end;
function TRigmMovieCharacter.Json: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('id',Id); Result.AddPair('name',Name); Result.AddPair('file',FileName);
  Result.AddPair('renderFormat',RenderFormat); if RenderFormat='psd' then Result.AddPair('psdView',PsdView.Clone as TJSONObject);
  Result.AddPair('speaker',SpeakerId); Result.AddPair('initialPosition',InitialPosition);
  AddN(Result,'x',X); AddN(Result,'y',Y); AddN(Result,'width',Width); AddN(Result,'height',Height);
  AddB(Result,'visible',Visible); AddB(Result,'rigSafe',RigSafe); AddB(Result,'allowGeneratedExpressions',AllowGeneratedExpressions);
  Result.AddPair('expressions',Expressions.Clone as TJSONObject);
  if (Motions.Count>0) or (ActiveMotion<>'') then begin
    Result.AddPair('motions',Motions.Clone as TJSONObject); Result.AddPair('activeMotion',ActiveMotion);
    AddN(Result,'motionStart',MotionStart); AddN(Result,'motionDuration',MotionDuration);
  end;
end;
class function TRigmMovieCharacter.FromJson(O: TJSONObject): TRigmMovieCharacter;
begin
  Result := TRigmMovieCharacter.Create;
  try
    Result.Id := JS(O,'id',Result.Id); Result.Name := JS(O,'name',Result.Name); Result.FileName := JS(O,'file');
    Result.RenderFormat := JS(O,'renderFormat',IfThen(SameText(ExtractFileExt(Result.FileName),'.psdchar'),'psd','rigm'));
    if O.GetValue('psdView')<>nil then begin Result.PsdView.Free; Result.PsdView := JO(O,'psdView').Clone as TJSONObject; end;
    Result.SpeakerId := JS(O,'speaker','narrator'); Result.InitialPosition := JS(O,'initialPosition','right');
    Result.X := JN(O,'x',1370); Result.Y := JN(O,'y',130); Result.Width := JN(O,'width',520); Result.Height := JN(O,'height',900);
    Result.Visible := JB(O,'visible',True); Result.RigSafe := JB(O,'rigSafe',True); Result.AllowGeneratedExpressions := JB(O,'allowGeneratedExpressions');
    if O.GetValue('expressions')<>nil then begin Result.Expressions.Free; Result.Expressions := JO(O,'expressions').Clone as TJSONObject; end;
    if O.GetValue('motions')<>nil then begin Result.Motions.Free; Result.Motions := JO(O,'motions').Clone as TJSONObject; end;
    Result.ActiveMotion := JS(O,'activeMotion'); Result.MotionStart := JN(O,'motionStart'); Result.MotionDuration := JN(O,'motionDuration',-1);
    Result.Validate;
  except Result.Free; raise; end;
end;
procedure TRigmMovieCharacter.Validate;
begin
  if (Id='') or (Length(Id)>128) or (Length(Name)>300) or (Length(FileName)>32760) then raise ERigm.Create('Invalid character identity');
  if not MatchText(RenderFormat,['rigm','psd']) or ((RenderFormat='psd')<>SameText(ExtractFileExt(FileName),'.psdchar')) then
    raise ERigm.Create('Character render format does not match its source');
  if not MatchText(InitialPosition,['left','center','right']) then raise ERigm.Create('Invalid initial character position');
  if not Finite(X) or not Finite(Y) or not Finite(Width) or not Finite(Height) or
    (Abs(X)>7680) or (Abs(Y)>4320) or (Width<16) or (Width>7680) or (Height<16) or (Height>4320) then raise ERigm.Create('Character rectangle is outside supported FullHD coordinates');
  if Expressions.Count>100 then raise ERigm.Create('Too many expression presets');
  if (Motions.Count>100) or not Finite(MotionStart) or (MotionStart<0) or (MotionStart>86400) or
    not Finite(MotionDuration) or ((MotionDuration<>-1) and (MotionDuration<0)) or (MotionDuration>86400) then raise ERigm.Create('Invalid whole-character motion timing');
  if (ActiveMotion<>'') and (Motions.GetValue(ActiveMotion)=nil) then raise ERigm.Create('Selected motion does not exist');
  for var Pair in Motions do begin
    if (Pair.JsonString.Value='') or (Length(Pair.JsonString.Value)>128) or not(Pair.JsonValue is TJSONObject) then raise ERigm.Create('Motion preset must have a name and object');
    var Frames := TJSONObject(Pair.JsonValue).GetValue('frames');
    if not(Frames is TJSONArray) then raise ERigm.Create('Motion needs a frame array');
    if (TJSONArray(Frames).Count<1) or (TJSONArray(Frames).Count>1000) then raise ERigm.Create('Motion frame count must be 1..1000');
    for var V in TJSONArray(Frames) do begin
      if not(V is TJSONObject) then raise ERigm.Create('Motion frame must be an object');
      var O := TJSONObject(V); var Duration := JN(O,'duration',-1);
      if (JS(O,'image')='') or (Length(JS(O,'image'))>32760) or not Finite(Duration) or (Duration<0.01) or (Duration>60) then raise ERigm.Create('Each motion frame needs an image and 0.01..60 seconds');
    end;
  end;
  for var Pair in Expressions do begin
    if not(Pair.JsonValue is TJSONObject) then raise ERigm.Create('Expression preset must be an object');
    var O := TJSONObject(Pair.JsonValue);
    if JB(O,'generated') and not AllowGeneratedExpressions then raise ERigm.Create('Generated character expressions are disabled for this source');
    if O.GetValue('variants')<>nil then begin
      if not(O.GetValue('variants') is TJSONArray) then raise ERigm.Create('Expression variants must be an array');
      for var V in JA(O,'variants') do begin
        if not(V is TJSONObject) then raise ERigm.Create('Expression variant must be an object');
        if (JS(TJSONObject(V),'groupId')='') or (JS(TJSONObject(V),'partId')='') then raise ERigm.Create('Expression requires real group and part identifiers');
      end;
    end;
  end;
end;
function TRigmMovieCharacter.MotionFrame(Seconds: Double; out Image: string): Boolean;
begin
  Image := ''; Result := False;
  if (ActiveMotion='') or (Seconds<MotionStart) or ((MotionDuration>=0) and (Seconds>=MotionStart+MotionDuration)) then Exit;
  var Motion := Motions.GetValue(ActiveMotion) as TJSONObject; if Motion=nil then Exit;
  var Frames := JA(Motion,'frames'); var Total: Int64 := 0;
  for var V in Frames do Total := Total+Round(JN(TJSONObject(V),'duration')*1000000);
  if Total<=0 then Exit;
  var Time := Round((Seconds-MotionStart)*1000000);
  if JB(Motion,'loop',True) then Time := Time mod Total else if Time>=Total then Exit;
  for var V in Frames do begin
    var Frame := TJSONObject(V); var Duration := Round(JN(Frame,'duration')*1000000);
    if Time<Duration then begin Image := JS(Frame,'image'); Exit(True); end;
    Time := Time-Duration;
  end;
end;
constructor TRigmMovieScene.Create;
begin inherited; Id := NewRigmId; Title := 'シーン'; Animation := TJSONObject.Create; Chart := TJSONObject.Create; end;
destructor TRigmMovieScene.Destroy;
begin Chart.Free; Animation.Free; inherited; end;
function TRigmMovieScene.Json: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('id',Id); Result.AddPair('title',Title); Result.AddPair('image',Image);
  Result.AddPair('description',Description); Result.AddPair('imagePrompt',ImagePrompt); AddN(Result,'padding',Padding);
  Result.AddPair('animation',Animation.Clone as TJSONObject);
  if Chart.Count>0 then Result.AddPair('chart',Chart.Clone as TJSONObject);
end;
class function TRigmMovieScene.FromJson(O: TJSONObject): TRigmMovieScene;
begin
  Result := TRigmMovieScene.Create;
  try
    Result.Id := JS(O,'id',Result.Id); Result.Title := JS(O,'title','シーン'); Result.Image := JS(O,'image');
    Result.Description := JS(O,'description'); Result.ImagePrompt := JS(O,'imagePrompt'); Result.Padding := JN(O,'padding');
      if O.GetValue('animation')<>nil then begin Result.Animation.Free; Result.Animation := JO(O,'animation').Clone as TJSONObject; end;
      if O.GetValue('chart')<>nil then begin
        if not(O.GetValue('chart') is TJSONObject) then raise ERigm.Create('Scene chart must be an object');
        Result.Chart.Free; Result.Chart := JO(O,'chart').Clone as TJSONObject;
      end;
    Result.Validate;
  except Result.Free; raise; end;
end;
procedure TRigmMovieScene.Validate;
begin
  if (Id='') or (Length(Id)>128) or (Length(Title)>300) or (Length(Description)>3000) or (Length(ImagePrompt)>8000) then raise ERigm.Create('Invalid scene content');
  if not Finite(Padding) or (Padding<0) or (Padding>600) then raise ERigm.Create('Scene padding must be 0..600 seconds');
  ValidateMovieChart(Chart);
end;
end.
