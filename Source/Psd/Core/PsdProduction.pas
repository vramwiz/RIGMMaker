unit PsdProduction;

// 編集可能な未完成キャラと、新規台本へ追加可能な検査済みキャラを区別する。
interface
uses System.SysUtils, System.JSON, PsdCharacter;

const PSD_PRODUCTION_REQUIREMENTS_VERSION = 2;
  PSD_EMOTION_REQUIREMENTS_CONFIRMED = True; // 通常＋喜怒哀楽。ユーザーが2026-10-05に確定。

function CheckPsdProduction(Character: TPsdCharacter): TJSONObject; // 呼出側所有。
function PsdProductionDigest(Character: TPsdCharacter): string;
function PsdReadyForScript(Character: TPsdCharacter; out Reason: string): Boolean;
procedure ValidateMotionReference(Character: TPsdCharacter; Reference: TJSONObject);

implementation
uses System.Hash, System.Generics.Collections, System.Classes, ArtDocument, PsdJson, PsdAnimation;

function RequiredExpression(Character: TPsdCharacter; Index: Integer): string;
const Aliases: array[0..4] of string = ('通常','喜び,喜','怒り,怒','哀しみ,悲しみ,哀','楽しみ,楽しい,楽');
begin
  Result := '';
  for var Name in Aliases[Index].Split([',']) do
    if Obj(Character.Settings,'expressions').GetValue(Name) is TJSONObject then Exit(Name);
end;
function RenderDigest(Renderer: TPsdRenderer; const State: TPsdFrameState): string;
begin
  var Pixels := Renderer.Composite(State); var Visible := False;
  for var I := 0 to Length(Pixels) div 4-1 do if Pixels[I*4+3]<>0 then begin Visible := True; Break; end;
  if not Visible then raise Exception.Create('合成結果が全透明です。');
  var Hash := THashSHA2.Create; Hash.Update(Pixels); Result := Hash.HashAsString;
end;

function BytesDigest(const Bytes: TBytes): string;
begin
  var Hash := THashSHA2.Create; Hash.Update(Bytes); Result := LowerCase(Hash.HashAsString);
end;

procedure ValidateMotionReference(Character: TPsdCharacter; Reference: TJSONObject);
  procedure Point(const Key: string; out X,Y: Double);
  begin
    var P := Obj(Reference,Key); X := N(P,'x',-1); Y := N(P,'y',-1);
    if (X<0) or (Y<0) or (X>=Character.Document.Width) or (Y>=Character.Document.Height) then
      raise Exception.Create('動き基準の点がキャンバス外です: '+Key);
  end;
begin
  if I(Reference,'schemaVersion')<>1 then raise Exception.Create('動き基準の形式が未対応です。');
  var F := Obj(Reference,'faceBounds'); var L := N(F,'left',-1); var T := N(F,'top',-1);
  var R := N(F,'right',-1); var Btm := N(F,'bottom',-1);
  if (L<0) or (T<0) or (R<=L) or (Btm<=T) or (R>Character.Document.Width) or (Btm>Character.Document.Height) then
    raise Exception.Create('顔の範囲をキャンバス内に指定してください。');
  var NX,NY,LX,LY,RX,RY: Double;
  Point('neck',NX,NY); Point('screenLeftShoulder',LX,LY); Point('screenRightShoulder',RX,RY);
  var Bottom := N(Reference,'upperBodyBottomY',-1);
  if (LX>=RX) or (NX<LX) or (NX>RX) or (Bottom<=NY) or (Bottom<=LY) or (Bottom<=RY) or
    (Bottom<Btm) or (Bottom>=Character.Document.Height) then
    raise Exception.Create('左右の肩、首元、上半身下端の位置関係を確認してください。');
end;

function PsdProductionDigest(Character: TPsdCharacter): string;
var Hash: THashSHA2;
  procedure Add(const Text: string);
  begin Hash.Update(TEncoding.UTF8.GetBytes(Text)); Hash.Update(TBytes.Create(0)); end;
  procedure Layers(List: TList<TArtLayer>);
  begin
    Add(List.Count.ToString);
    for var L in List do begin
      Add(L.Id); Add(L.Name); Add(Ord(L.Kind).ToString);
      Add(Format('%d,%d,%d,%d,%d,%d,%s,%d', [L.Bounds.Left,L.Bounds.Top,L.Bounds.Right,L.Bounds.Bottom,
        L.Opacity,Ord(L.Visible),string(L.BlendKey),L.Clipping]));
      Add(BytesDigest(L.Pixels)); Add(Ord(L.HasMask).ToString);
      if L.HasMask then begin
        Add(Format('%d,%d,%d,%d,%d,%d,%d', [L.MaskBounds.Left,L.MaskBounds.Top,L.MaskBounds.Right,L.MaskBounds.Bottom,
          L.MaskDefault,Ord(L.MaskDisabled),Ord(L.MaskInvert)])); Add(BytesDigest(L.MaskPixels));
      end;
      Layers(L.Children);
    end;
  end;
begin
  Hash := THashSHA2.Create; Add(Character.Policy); Add(Character.Document.Width.ToString); Add(Character.Document.Height.ToString);
  Add(Character.Settings.ToJSON); Layers(Character.Document.Roots);
  var Keys := TList<string>.Create;
  try
    for var Key in Character.Assets.Keys do Keys.Add(Key); Keys.Sort;
    for var Key in Keys do begin Add(Key); Add(BytesDigest(Character.Assets[Key])); end;
  finally Keys.Free; end;
  Result := LowerCase(Hash.HashAsString);
end;

procedure ValidatePart(Character: TPsdCharacter; const GroupId,PartId: string);
begin
  Character.CheckChoice(GroupId,PartId); var L := Character.Document.FindLayer(PartId);
  var HasPixels := False;
  if (L.Bounds.Width<1) or (L.Bounds.Height<1) or (Length(L.Pixels)<>PixelByteCount(L.Bounds.Width,L.Bounds.Height,4)) then
    raise Exception.Create('差分画像の寸法またはRGBAデータが不正です。');
  if L.Opacity=0 then raise Exception.Create('不透明度0の差分です。');
  for var Index := 0 to Length(L.Pixels) div 4-1 do if L.Pixels[Index*4+3]<>0 then begin HasPixels := True; Break; end;
  if not HasPixels then raise Exception.Create('空または全透明の差分です。');
end;
function CheckPsdProduction(Character: TPsdCharacter): TJSONObject;
const EmotionLabels: array[0..4] of string = ('通常','喜','怒','哀','楽');
var Checks: TJSONArray; Passed: Boolean; Renderer: TPsdRenderer; Render: TFunc<TPsdFrameState,string>;
  procedure Check(const Key,Title: string; Action: TProc);
  begin
    var O := TJSONObject.Create; Checks.AddElement(O); O.AddPair('id',Key); O.AddPair('title',Title);
    try Action(); O.AddPair('passed',TJSONBool.Create(True)); O.AddPair('message','確認済み');
    except on E: Exception do begin Passed := False; O.AddPair('passed',TJSONBool.Create(False)); O.AddPair('message',E.Message); end; end;
  end;
begin
  Result := TJSONObject.Create; Passed := True; Checks := TJSONArray.Create; Result.AddPair('checks',Checks);
  Renderer := nil;
  Render := function(State: TPsdFrameState): string begin
    if Renderer=nil then Renderer := TPsdRenderer.Create(Character,nil,0);
    Result := RenderDigest(Renderer,State);
  end;
  try
  Result.AddPair('schemaVersion',TJSONNumber.Create(1)); Result.AddPair('requirementsVersion',TJSONNumber.Create(PSD_PRODUCTION_REQUIREMENTS_VERSION));
  Result.AddPair('checked',TJSONBool.Create(True));
  Check('structure','PSDと登録情報',procedure begin Character.Validate; end);
  Check('frontImage','正面の表示素材',procedure begin
    var State := TPsdFrameState.Default; State.Motion := 'none'; State.AutoBlink := False; Render(State);
  end);
  Check('blink','目パチの通常・半開き・閉じ',procedure begin
    var Blink := Obj(Obj(Character.Settings,'animation'),'blink'); var GroupId := S(Blink,'groupId');
    for var Key in ['normalPartId','halfOpenPartId','closedPartId'] do ValidatePart(Character,GroupId,S(Blink,Key));
    if (S(Blink,'normalPartId')=S(Blink,'closedPartId')) or (S(Blink,'halfOpenPartId')=S(Blink,'closedPartId')) or
      (S(Blink,'normalPartId')=S(Blink,'halfOpenPartId')) then
      raise Exception.Create('通常・半開き・閉じの切替用画像が必要です。');
    if BytesDigest(Character.Document.FindLayer(S(Blink,'normalPartId')).Pixels)=
      BytesDigest(Character.Document.FindLayer(S(Blink,'closedPartId')).Pixels) then raise Exception.Create('通常目と閉じ目が同じ画像です。');
    var State := TPsdFrameState.Default; State.Expression := RequiredExpression(Character,0); State.Motion := 'none';
    var Open := Render(State); State.Seconds := 3.78; var Half := Render(State);
    State.Seconds := 3.86; var Closed := Render(State);
    if (Open=Half) or (Open=Closed) or (Half=Closed) then raise Exception.Create('正面の実合成で通常・半開き・閉じが切り替わりません。非表示・遮蔽・表情設定を確認してください。');
  end);
  Check('lipSync','音素口パク',procedure begin
    var Lip := Obj(Obj(Character.Settings,'animation'),'lipSync'); var GroupId := S(Lip,'groupId');
    ValidatePart(Character,GroupId,S(Lip,'closedPartId')); var Phones := Obj(Lip,'phonemePartIds');
    for var Phone in ['a','i','u','e','o','N','closed'] do ValidatePart(Character,GroupId,S(Phones,Phone));
    if S(Phones,'a')=S(Lip,'closedPartId') then raise Exception.Create('開口と閉口の切替用画像が必要です。');
    var State := TPsdFrameState.Default; State.Expression := RequiredExpression(Character,0); State.Motion := 'none'; State.AutoBlink := False; State.HasPhoneme := True;
    var Digests := TDictionary<string,string>.Create;
    try
      for var Phone in ['closed','a','i','u','e','o'] do begin
        State.Phoneme := Phone; var Digest := Render(State); var Previous: string;
        if Digests.TryGetValue(Digest,Previous) then raise Exception.Create('正面の実合成で口形が同じです: '+Previous+' / '+Phone);
        Digests.Add(Digest,Phone);
      end;
    finally Digests.Free; end;
  end);
  Check('emotions','最低限の感情差分',procedure begin
    var Missing := TStringList.Create; var Digests := TDictionary<string,string>.Create;
    try
      for var Index := 0 to 4 do if RequiredExpression(Character,Index)='' then
        Missing.Add(EmotionLabels[Index]);
      if Missing.Count>0 then raise Exception.Create('必須感情が未登録です: '+StringReplace(Trim(Missing.Text),sLineBreak,' / ',[rfReplaceAll]));
      for var Index := 0 to 4 do begin
        var Name := RequiredExpression(Character,Index); var Expression := Obj(Obj(Character.Settings,'expressions'),Name);
        if Arr(Expression,'variants').Count=0 then raise Exception.Create('部位の登録がない表情です: '+Name);
        for var V in Arr(Expression,'variants') do begin var Choice := TJSONObject(V); Character.CheckChoice(S(Choice,'groupId'),S(Choice,'partId')); end;
        var State := TPsdFrameState.Default; State.Expression := Name; State.AutoBlink := False; State.Motion := 'none';
        var Digest := Render(State); var Previous: string;
        if Digests.TryGetValue(Digest,Previous) then raise Exception.Create('実合成が同じ必須感情です: '+Previous+' / '+Name);
        Digests.Add(Digest,Name);
      end;
    finally Digests.Free; Missing.Free; end;
  end);
  Check('motionReference','ボーン／動き基準設定',procedure begin ValidateMotionReference(Character,Obj(Character.Settings,'motionReference')); end);
  Result.AddPair('requirementsConfirmed',TJSONBool.Create(PSD_EMOTION_REQUIREMENTS_CONFIRMED));
  Result.AddPair('ready',TJSONBool.Create(Passed));
  if Passed then Result.AddPair('stage','complete') else Result.AddPair('stage','draft');
  Result.AddPair('contentDigest',PsdProductionDigest(Character));
  finally Renderer.Free; end;
end;

function PsdReadyForScript(Character: TPsdCharacter; out Reason: string): Boolean;
begin
  Result := False; Reason := '未完成：キャラ編集画面で仕様を検査してください。';
  try
    if not B(Character.Production,'checked') then Exit;
    if not B(Character.Production,'ready') then begin
      Reason := '未完成：';
      for var V in Arr(Character.Production,'checks') do begin var O := TJSONObject(V); if not B(O,'passed') then Reason := Reason+#13#10+S(O,'title')+': '+S(O,'message'); end;
      Exit;
    end;
    if not PSD_EMOTION_REQUIREMENTS_CONFIRMED or (I(Character.Production,'requirementsVersion')<>PSD_PRODUCTION_REQUIREMENTS_VERSION) then begin
      Reason := '未完成：現在の必須仕様による再検査が必要です。'; Exit;
    end;
    if S(Character.Production,'contentDigest')<>PsdProductionDigest(Character) then begin
      Reason := '未完成：検査後に素材または設定が変わっています。再検査してください。'; Exit;
    end;
    var Check := CheckPsdProduction(Character);
    try Result := B(Check,'ready'); finally Check.Free; end;
    if Result then Reason := '';
  except on E: Exception do Reason := '未完成：'+E.Message; end;
end;
end.
