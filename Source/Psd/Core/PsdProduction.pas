unit PsdProduction;

// 編集可能な未完成キャラと、新規台本へ追加可能な検査済みキャラを区別する。
interface
uses System.SysUtils, System.JSON, PsdCharacter;

const PSD_PRODUCTION_REQUIREMENTS_VERSION = 1;
  // 必須感情の正確な一覧はユーザー回答待ち。未確定のまま完成を付与しない。
  PSD_EMOTION_REQUIREMENTS_CONFIRMED = False;

function CheckPsdProduction(Character: TPsdCharacter): TJSONObject; // 呼出側所有。
function PsdProductionDigest(Character: TPsdCharacter): string;
function PsdReadyForScript(Character: TPsdCharacter; out Reason: string): Boolean;
procedure ValidateMotionReference(Character: TPsdCharacter; Reference: TJSONObject);

implementation
uses System.Hash, System.Generics.Collections, ArtDocument, PsdJson;

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
var Checks: TJSONArray; Passed: Boolean;
  procedure Check(const Key,Title: string; Action: TProc);
  begin
    var O := TJSONObject.Create; Checks.AddElement(O); O.AddPair('id',Key); O.AddPair('title',Title);
    try Action(); O.AddPair('passed',TJSONBool.Create(True)); O.AddPair('message','確認済み');
    except on E: Exception do begin Passed := False; O.AddPair('passed',TJSONBool.Create(False)); O.AddPair('message',E.Message); end; end;
  end;
begin
  Result := TJSONObject.Create; Passed := True; Checks := TJSONArray.Create; Result.AddPair('checks',Checks);
  Result.AddPair('schemaVersion',TJSONNumber.Create(1)); Result.AddPair('requirementsVersion',TJSONNumber.Create(PSD_PRODUCTION_REQUIREMENTS_VERSION));
  Result.AddPair('checked',TJSONBool.Create(True));
  Check('structure','PSDと登録情報',procedure begin Character.Validate; end);
  Check('blink','目パチの通常・半開き・閉じ',procedure begin
    var Blink := Obj(Obj(Character.Settings,'animation'),'blink'); var GroupId := S(Blink,'groupId');
    for var Key in ['normalPartId','halfOpenPartId','closedPartId'] do ValidatePart(Character,GroupId,S(Blink,Key));
    if (S(Blink,'normalPartId')=S(Blink,'closedPartId')) or (S(Blink,'halfOpenPartId')=S(Blink,'closedPartId')) or
      (S(Blink,'normalPartId')=S(Blink,'halfOpenPartId')) then
      raise Exception.Create('通常・半開き・閉じの切替用画像が必要です。');
    if BytesDigest(Character.Document.FindLayer(S(Blink,'normalPartId')).Pixels)=
      BytesDigest(Character.Document.FindLayer(S(Blink,'closedPartId')).Pixels) then raise Exception.Create('通常目と閉じ目が同じ画像です。');
  end);
  Check('lipSync','音素口パク',procedure begin
    var Lip := Obj(Obj(Character.Settings,'animation'),'lipSync'); var GroupId := S(Lip,'groupId');
    ValidatePart(Character,GroupId,S(Lip,'closedPartId')); var Phones := Obj(Lip,'phonemePartIds');
    for var Phone in ['a','i','u','e','o','N','closed'] do ValidatePart(Character,GroupId,S(Phones,Phone));
    if S(Phones,'a')=S(Lip,'closedPartId') then raise Exception.Create('開口と閉口の切替用画像が必要です。');
  end);
  Check('emotions','最低限の感情差分',procedure begin
    if not PSD_EMOTION_REQUIREMENTS_CONFIRMED then raise Exception.Create('必須感情の一覧が未確定です。完成判定は保留します。');
  end);
  Check('motionReference','ボーン／動き基準設定',procedure begin ValidateMotionReference(Character,Obj(Character.Settings,'motionReference')); end);
  Result.AddPair('requirementsConfirmed',TJSONBool.Create(PSD_EMOTION_REQUIREMENTS_CONFIRMED));
  Result.AddPair('ready',TJSONBool.Create(Passed));
  if Passed then Result.AddPair('stage','complete') else Result.AddPair('stage','draft');
  Result.AddPair('contentDigest',PsdProductionDigest(Character));
end;

function PsdReadyForScript(Character: TPsdCharacter; out Reason: string): Boolean;
begin
  Result := False; Reason := '未完成：キャラ編集画面で仕様を検査してください。';
  try
    if not B(Character.Production,'checked') or not B(Character.Production,'ready') then Exit;
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
