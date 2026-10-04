unit RigmMovieActing;
interface
uses System.JSON, RigmModel;
type
  TRigmMovieActing = class
  public
    MouthMode,BlinkMode,ImageAttention: string;
    MouthGain, LipLead, BlinkStrength, BlinkInterval, BlinkDuration, BlinkPhase: Double;
    HeadGain, BodyGain, Onset, Duration, FadeIn, FadeOut: Double;
    Variants: TJSONArray;
    constructor Create;
    destructor Destroy; override;
    function Json: TJSONObject;
    class function FromJson(O: TJSONObject): TRigmMovieActing; static;
    procedure Validate;
    function Gain(Local, CueDuration: Double): Double;
    procedure ApplyVariants(Document: TRigmDocument; Pose: TRigmPose);
    procedure ApplyFeatureAssets(Document: TRigmDocument; Pose: TRigmPose; Mouth,BlinkOpen: Double;
      MouthEnabled: Boolean=True; BlinkEnabled: Boolean=True);
  end;
function MovieActorAssets(Document: TRigmDocument): TJSONObject;
function MovieBlinkOpen(Seconds,Interval,Duration,Phase,Strength,Gain: Double; Fps: Integer): Double;
implementation
uses System.SysUtils, System.Math, System.StrUtils, System.Generics.Collections, ArtDocument, RigmJson;
function MovieBlinkOpen(Seconds,Interval,Duration,Phase,Strength,Gain: Double; Fps: Integer): Double;
begin
  // A zero-width turning point could be missed between output frames.
  // Hold the fully closed pose for at least 1.5 output frames.
  Interval := Max(0.001,Interval);
  Duration := Min(Interval,Max(Duration,2/Max(1,Fps)));
  var Hold := Min(Duration,Max(Duration*0.4,1.5/Max(1,Fps)));
  var Ramp := Max(0.000001,(Duration-Hold)/2);
  var PhaseTime := Frac((Seconds+Phase)/Interval)*Interval;
  var Closure := 0.0;
  if PhaseTime<Duration then begin
    if PhaseTime<Ramp then Closure := PhaseTime/Ramp
    else if PhaseTime<Ramp+Hold then Closure := 1
    else Closure := (Duration-PhaseTime)/Ramp;
  end;
  Result := EnsureRange(1-Strength*Gain*Closure,0.0,1.0);
end;
constructor TRigmMovieActing.Create;
begin
  inherited; MouthGain := 1; BlinkStrength := 1; BlinkInterval := 4.0; BlinkDuration := 0.16;
  MouthMode := 'auto'; BlinkMode := 'auto'; ImageAttention := 'auto';
  BlinkPhase := 0.73; HeadGain := 1; BodyGain := 1; Duration := -1; Variants := TJSONArray.Create;
end;
destructor TRigmMovieActing.Destroy;
begin Variants.Free; inherited; end;
function TRigmMovieActing.Json: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('mouthMode',MouthMode); Result.AddPair('blinkMode',BlinkMode);
  Result.AddPair('imageAttention',ImageAttention);
  AddN(Result,'mouthGain',MouthGain); AddN(Result,'lipLead',LipLead);
  AddN(Result,'blinkStrength',BlinkStrength); AddN(Result,'blinkInterval',BlinkInterval);
  AddN(Result,'blinkDuration',BlinkDuration); AddN(Result,'blinkPhase',BlinkPhase);
  AddN(Result,'headGain',HeadGain); AddN(Result,'bodyGain',BodyGain);
  AddN(Result,'onset',Onset); AddN(Result,'duration',Duration); AddN(Result,'fadeIn',FadeIn); AddN(Result,'fadeOut',FadeOut);
  Result.AddPair('variants',Variants.Clone as TJSONArray);
end;
class function TRigmMovieActing.FromJson(O: TJSONObject): TRigmMovieActing;
begin
  Result := TRigmMovieActing.Create;
  try
    Result.MouthMode := JS(O,'mouthMode','auto'); Result.BlinkMode := JS(O,'blinkMode','auto');
    Result.ImageAttention := JS(O,'imageAttention','auto');
    Result.MouthGain := JN(O,'mouthGain',1); Result.LipLead := JN(O,'lipLead');
    Result.BlinkStrength := JN(O,'blinkStrength',1); Result.BlinkInterval := JN(O,'blinkInterval',4.0);
    Result.BlinkDuration := JN(O,'blinkDuration',0.16); Result.BlinkPhase := JN(O,'blinkPhase',0.73);
    Result.HeadGain := JN(O,'headGain',1); Result.BodyGain := JN(O,'bodyGain',1);
    Result.Onset := JN(O,'onset'); Result.Duration := JN(O,'duration',-1);
    Result.FadeIn := JN(O,'fadeIn'); Result.FadeOut := JN(O,'fadeOut');
    if O.GetValue('variants')<>nil then begin Result.Variants.Free; Result.Variants := JA(O,'variants').Clone as TJSONArray; end;
    Result.Validate;
  except Result.Free; raise; end;
end;
procedure TRigmMovieActing.Validate;
  procedure Range(const Name: string; Value, Low, High: Double);
  begin if not Finite(Value) or (Value<Low) or (Value>High) then raise ERigm.Create('演技設定が範囲外です: '+Name); end;
var Seen: TDictionary<string,Boolean>;
begin
  if not MatchText(ImageAttention,['auto','off','head']) then raise ERigm.Create('imageAttention must be auto, off or head');
  if not MatchText(MouthMode,['auto','assets','deform']) or not MatchText(BlinkMode,['auto','assets','deform']) then raise ERigm.Create('口パク/瞬き方式はauto、assets、deformです。');
  Range('mouthGain',MouthGain,0,2); Range('lipLead',LipLead,-0.3,0.3);
  Range('blinkStrength',BlinkStrength,0,1); Range('blinkInterval',BlinkInterval,0.3,30);
  Range('blinkDuration',BlinkDuration,0.04,1); Range('blinkPhase',BlinkPhase,0,30);
  if BlinkDuration>BlinkInterval then raise ERigm.Create('瞬き時間は間隔以下にしてください。');
  Range('headGain',HeadGain,0,3); Range('bodyGain',BodyGain,0,3); Range('onset',Onset,0,600);
  Range('duration',Duration,-1,660); if (Duration<0) and (Duration<>-1) then raise ERigm.Create('演技時間は-1（セリフ終端）または0以上です。');
  Range('fadeIn',FadeIn,0,60); Range('fadeOut',FadeOut,0,60);
  if Variants.Count>100 then raise ERigm.Create('素材選択が多すぎます。');
  Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in Variants do begin
      if not (V is TJSONObject) then raise ERigm.Create('素材選択はgroupIdとpartIdのオブジェクトです。');
      var Group := JS(TJSONObject(V),'groupId'); var Part := JS(TJSONObject(V),'partId');
      if (Group='') or (Part='') or (Length(Group)>128) or (Length(Part)>128) or Seen.ContainsKey(Group) then raise ERigm.Create('素材選択IDが空か重複しています。');
      Seen.Add(Group,True);
    end;
  finally Seen.Free; end;
end;
function TRigmMovieActing.Gain(Local, CueDuration: Double): Double;
var Finish: Double;
begin
  Finish := CueDuration; if Duration>=0 then Finish := Min(Finish,Onset+Duration);
  if (Local<Onset) or (Local>=Finish) then Exit(0);
  Result := 1;
  if FadeIn>0 then Result := Min(Result,(Local-Onset)/FadeIn);
  if FadeOut>0 then Result := Min(Result,(Finish-Local)/FadeOut);
  Result := EnsureRange(Result,0.0,1.0);
end;
procedure TRigmMovieActing.ApplyVariants(Document: TRigmDocument; Pose: TRigmPose);
var Choices: TDictionary<string,Boolean>;
  procedure Select(Id: string; Visible: Boolean);
  var Existing: Boolean;
  begin
    if Choices.TryGetValue(Id,Existing) and (Existing<>Visible) then
      raise ERigm.Create('入れ子グループの素材選択が矛盾しています: '+Id);
    Choices.AddOrSetValue(Id,Visible);
  end;
begin
  Choices := TDictionary<string,Boolean>.Create;
  try
    for var V in Variants do begin
      var GroupId := JS(TJSONObject(V),'groupId'); var PartId := JS(TJSONObject(V),'partId');
      var Group := Document.Art.FindLayer(GroupId); var Part := Document.Art.FindLayer(PartId);
      if (Group=nil) or (Part=nil) or (Group.Kind<>alkGroup) or not Group.Children.Contains(Part) or
        Document.IsReferencePart(GroupId) or Document.IsReferencePart(PartId) then
        raise ERigm.Create('選択した素材がキャラクターの同じグループ内にありません: '+PartId);
      for var Child in Group.Children do Select(Child.Id,Child.Id=PartId);
      var Ancestor := GroupId;
      while Ancestor<>'' do begin Select(Ancestor,True); Ancestor := Document.ParentId(Ancestor); end;
    end;
    for var Item in Choices do Pose.PartVisibility.AddOrSetValue(Item.Key,Item.Value);
  finally Choices.Free; end;
end;
procedure TRigmMovieActing.ApplyFeatureAssets(Document: TRigmDocument; Pose: TRigmPose; Mouth,BlinkOpen: Double;
  MouthEnabled,BlinkEnabled: Boolean);
  function Named(G: TArtLayer; const Names: array of string): TArtLayer;
  begin
    Result := nil;
    for var Name in Names do for var L in G.Children do if L.Name.Trim.TrimLeft(['*'])=Name then Exit(L);
  end;
  procedure Apply(const Role,Mode: string; Value: Double);
  var Used: Boolean;
  begin
    if Mode='deform' then Exit; Used := False;
    for var G in Document.Layers do if (G.Kind=alkGroup) and (G.Children.Count>1) then begin
      var Compatible := True; var Visible := True; var Ancestor := G;
      while Ancestor<>nil do begin
        var Effective := Ancestor.Visible; var Override: Boolean;
        if Pose.PartVisibility.TryGetValue(Ancestor.Id,Override) then Effective := Override;
        Visible := Visible and Effective; Ancestor := Document.Art.FindLayer(Document.ParentId(Ancestor.Id));
      end;
      if not Visible then Continue;
      for var L in G.Children do Compatible := Compatible and (L.Kind=alkImage) and (Document.Part(L.Id).Role=Role) and not Document.IsReferencePart(L.Id);
      if not Compatible then Continue;
      var Closed := Named(G,['閉じ','closed','blink','ん']); var DefaultPart: TArtLayer := nil;
      for var L in G.Children do if L.Visible then begin DefaultPart := L; Break; end;
      if DefaultPart=nil then DefaultPart := Named(G,['通常','normal','default']);
      for var V in Variants do if JS(TJSONObject(V),'groupId')=G.Id then DefaultPart := Document.Art.FindLayer(JS(TJSONObject(V),'partId'));
      if DefaultPart=nil then for var L in G.Children do if L.Visible then begin DefaultPart := L; Break; end;
      if (Role='eye') and (DefaultPart<>nil) and
        not MatchText(DefaultPart.Name.Trim.TrimLeft(['*']),['通常','normal','default','開き','open']) then begin
        // Fixed special eye differences are expressions, not blink candidates.
        for var L in G.Children do Pose.PartFeatureAssets.AddOrSetValue(L.Id,True);
        Continue;
      end;
      if Role='mouth' then begin
        var Fixed := False;
        for var V in Variants do if JS(TJSONObject(V),'groupId')=G.Id then
          Fixed := (DefaultPart<>nil) and not MatchText(DefaultPart.Name.Trim.TrimLeft(['*']),
            ['通常','normal','default','閉じ','closed','閉','開き','open','半開き','half','あ','い','う','え','お','ん','a','i','u','e','o','N']);
        if Fixed then begin for var L in G.Children do Pose.PartFeatureAssets.AddOrSetValue(L.Id,True); Continue; end;
        DefaultPart := Named(G,['開き','open','あ','a','通常','normal','default']);
      end;
      if (Closed=nil) or (DefaultPart=nil) then Continue;
      var Half := Named(G,['やや閉じ','半開き','half']); var Selected := DefaultPart;
      if Value<0.15 then Selected := Closed
      else if ((Role='eye') and (Value<0.65)) or ((Role='mouth') and (Value<0.65)) then begin if Half<>nil then Selected := Half; end;
      if (Role='mouth') and (Value>=0.15) then begin
        var Phone := Round(Pose.Value('mouthPhoneme')); var Vowel: TArtLayer := nil;
        case Phone of
          Ord('a'),Ord('A'): Vowel := Named(G,['あ','a']);
          Ord('i'),Ord('I'): Vowel := Named(G,['い','i']);
          Ord('u'),Ord('U'): Vowel := Named(G,['う','u']);
          Ord('e'),Ord('E'): Vowel := Named(G,['え','e']);
          Ord('o'),Ord('O'): Vowel := Named(G,['お','o']);
          Ord('N'): Vowel := Named(G,['ん','N']);
        end;
        if Vowel<>nil then Selected := Vowel;
      end;
      for var L in G.Children do begin Pose.PartVisibility.AddOrSetValue(L.Id,L=Selected); Pose.PartFeatureAssets.AddOrSetValue(L.Id,True); end;
      Used := True;
    end;
    if (Mode='assets') and not Used then raise ERigm.Create('実在する開閉素材のグループがありません: '+Role);
  end;
begin
  if MouthEnabled then Apply('mouth',MouthMode,EnsureRange(Mouth,0.0,1.0))
  else for var L in Document.Layers do if Document.Part(L.Id).Role='mouth' then Pose.PartFeatureAssets.AddOrSetValue(L.Id,True);
  if BlinkEnabled then Apply('eye',BlinkMode,EnsureRange(BlinkOpen,0.0,1.0))
  else for var L in Document.Layers do if Document.Part(L.Id).Role='eye' then Pose.PartFeatureAssets.AddOrSetValue(L.Id,True);
end;
function MovieActorAssets(Document: TRigmDocument): TJSONObject;
begin
  Result := TJSONObject.Create; var Groups := TJSONArray.Create; Result.AddPair('groups',Groups);
  var Parameters := TJSONArray.Create; Result.AddPair('parameters',Parameters);
  if Document=nil then Exit;
  Result.AddPair('documentId',Document.FileId); Result.AddPair('name',Document.Name);
  for var P in Document.Parameters do begin
    var O := TJSONObject.Create; O.AddPair('id',P.Id); O.AddPair('name',P.Name); O.AddPair('role',P.Role);
    AddN(O,'minimum',P.Minimum); AddN(O,'maximum',P.Maximum); Parameters.AddElement(O);
  end;
  for var L in Document.Layers do if (L.Kind=alkGroup) and not Document.IsReferencePart(L.Id) then begin
    var O := TJSONObject.Create; O.AddPair('id',L.Id); O.AddPair('name',L.Name); var Children := TJSONArray.Create; O.AddPair('children',Children);
    for var Child in L.Children do if not Document.IsReferencePart(Child.Id) then begin
      var Item := TJSONObject.Create; Item.AddPair('id',Child.Id); Item.AddPair('name',Child.Name);
      Item.AddPair('role',Document.Part(Child.Id).Role); Item.AddPair('kind',IfThen(Child.Kind=alkGroup,'group','image'));
      AddB(Item,'visible',Child.Visible); Children.AddElement(Item);
    end;
    if Children.Count>1 then Groups.AddElement(O) else O.Free;
  end;
end;
end.
