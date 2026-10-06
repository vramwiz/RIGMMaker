unit PsdAnimation;

// 表情→視線→瞬き→音素を選び、合成後の全体画像へ常時変形を適用する。
interface
uses System.SysUtils, System.JSON, System.Generics.Collections, ArtDocument,
  PsdCharacter, PsdWorkspace;

type
  TPsdFrameState = record
    Seconds: Double; // 作品時刻。瞬き/連番/小動作の共通基準。
    Expression, Gaze, Phoneme, NonFrontId, Motion: string;
    AutoBlink, HasPhoneme: Boolean; // HasPhoneme=falseなら表情の口を維持。
    Strength: Double; // 小動作のピクセル強度。出力FullHDを基準にする。
    Variants: TJSONArray; // 借用。共通台本の部位選択。1回の描画中だけ参照。
    class function Default: TPsdFrameState; static;
  end;
  TPsdRenderer = class
  private
    FCharacter: TPsdCharacter; FWorkspace: TPsdWorkspace; // 借用。
    FDocument: TArtDocument; // 所有。縮小した表示専用文書。保存状態を変更しない。
    FCache: TDictionary<string, TBytes>; // 合成画像を64MB以内で保持。
    FScale: Double;
    function FramePixels(const State: TPsdFrameState; const Source: TBytes; Width,Height: Integer): TBytes;
  public
    constructor Create(Character: TPsdCharacter; Workspace: TPsdWorkspace; MaxHeight: Integer = 960);
    destructor Destroy; override;
    // 呼び出し側所有の辞書。非正面中は顔選択を一切返さない。
    function Choices(const State: TPsdFrameState): TDictionary<string, string>;
    function Composite(const State: TPsdFrameState): TBytes; // 直線alphaのキャラキャンバス。
    function Frame(const State: TPsdFrameState; Width: Integer = 1920; Height: Integer = 1080): TBytes;
    function SelectionFrame(const State: TPsdFrameState; const LayerId: string; Width,Height: Integer): TBytes;
    property Document: TArtDocument read FDocument;
  end;
  TPsdPhonemeTrack = class
  private
    FEvents: TJSONArray; // 所有。秒単位のstart/end/phoneme。
  public
    destructor Destroy; override;
    procedure Load(Events: TJSONArray); // 完全検証後に置換。LABと同じ半開区間。
    procedure LoadLab(Workspace: TPsdWorkspace; const Path: string);
    function Sample(Seconds: Double): string; // 区間外はclosed。
    function Available: Boolean;
  end;

implementation
uses System.Math, System.IOUtils, System.Classes, ArtPng, ArtPsd,
  ArtRasterTransform, PsdJson, PsdProduction, SYNC_Motion_TempoMotion;

class function TPsdFrameState.Default: TPsdFrameState;
begin
  Result := System.Default(TPsdFrameState); Result.Gaze := 'front';
  Result.AutoBlink := True; Result.Motion := 'breathe'; Result.Strength := 16;
end;
constructor TPsdRenderer.Create(Character: TPsdCharacter; Workspace: TPsdWorkspace; MaxHeight: Integer);
  procedure Resize(Layers: TList<TArtLayer>);
  begin
    for var L in Layers do begin
      var Old := L.Bounds;
      if L.HasMask then raise Exception.Create('Managed preview masks require native rendering');
      var W := Max(1, Round(Old.Width * FScale)); var H := Max(1, Round(Old.Height * FScale));
      if L.Kind = alkImage then L.Pixels := ResampleRgba(L.Pixels, Old.Width, Old.Height, TArtBounds.Create(0, 0, Old.Width, Old.Height), W, H);
      L.Bounds := TArtBounds.Create(Round(Old.Left * FScale), Round(Old.Top * FScale), Round(Old.Left * FScale) + W, Round(Old.Top * FScale) + H);
      Resize(L.Children);
    end;
  end;
begin
  inherited Create; FCharacter := Character; FWorkspace := Workspace;
  FCache := TDictionary<string, TBytes>.Create; FDocument := Character.Document.Clone;
  FScale := 1;
  if (MaxHeight > 0) and (FDocument.Height > MaxHeight) then FScale := MaxHeight / FDocument.Height;
  if (FScale <> 1) and (Character.Policy = 'managed') then begin
    Resize(FDocument.Roots); FDocument.Width := Round(FDocument.Width * FScale); FDocument.Height := Round(FDocument.Height * FScale);
  end else FScale := 1;
end;
destructor TPsdRenderer.Destroy;
begin FCache.Free; FDocument.Free; inherited; end;
function TPsdRenderer.Choices(const State: TPsdFrameState): TDictionary<string, string>;
begin
  Result := TDictionary<string, string>.Create;
  try
    if State.NonFrontId <> '' then Exit;
    for var V in Arr(FCharacter.Settings, 'groups') do begin
      var G := TJSONObject(V); Result.Add(S(G, 'id'), S(G, 'defaultPartId'));
    end;
    var BlinkEnabled := State.AutoBlink; var LipEnabled := State.HasPhoneme;
    if State.Expression <> '' then begin
      var V := Obj(FCharacter.Settings, 'expressions').GetValue(State.Expression);
      if not (V is TJSONObject) then raise Exception.Create('Expression unavailable');
      var E := TJSONObject(V);
      BlinkEnabled := BlinkEnabled and B(E, 'blinkAnimate', True); LipEnabled := LipEnabled and B(E, 'mouthAnimate', True);
      for var Item in Arr(E, 'variants') do begin
        var P := TJSONObject(Item); FCharacter.CheckChoice(S(P, 'groupId'), S(P, 'partId'));
        Result.AddOrSetValue(S(P, 'groupId'), S(P, 'partId'));
      end;
    end;
    if State.Variants<>nil then for var Item in State.Variants do begin
      var P := TJSONObject(Item); FCharacter.CheckChoice(S(P,'groupId'),S(P,'partId'));
      Result.AddOrSetValue(S(P,'groupId'),S(P,'partId'));
    end;
    if FCharacter.Settings.GetValue('animation') = nil then Exit;
    var A := Obj(FCharacter.Settings, 'animation'); var Blink := Obj(A, 'blink'); var Lip := Obj(A, 'lipSync');
    // 正面指定は表情の目を優先。欠けた視線を通常目で代用しない。
    if (State.Gaze <> '') and (State.Gaze <> 'front') then begin
      var Id := S(Obj(FCharacter.Settings, 'gaze'), State.Gaze);
      if Id = '' then raise Exception.Create('視線差分が未登録です: ' + State.Gaze);
      Result.AddOrSetValue(S(Blink, 'groupId'), Id);
    end;
    var Phase := State.Seconds - Floor(State.Seconds / 4.0) * 4.0;
    if BlinkEnabled and (Phase >= 3.74) then begin
      var Id := S(Blink, 'halfOpenPartId');
      if (Phase >= 3.82) and (Phase < 3.92) then Id := S(Blink, 'closedPartId');
      Result.AddOrSetValue(S(Blink, 'groupId'), Id);
    end;
    if LipEnabled then begin
      var Id := S(Obj(Lip, 'phonemePartIds'), State.Phoneme);
      if Id = '' then Id := S(Lip, 'closedPartId');
      Result.AddOrSetValue(S(Lip, 'groupId'), Id);
    end;
  except Result.Free; raise; end;
end;
function TPsdRenderer.Composite(const State: TPsdFrameState): TBytes;
begin
  if IsNan(State.Seconds) or IsInfinite(State.Seconds) or (State.Seconds < 0) or (State.Seconds > 86400 * 365.0) then raise Exception.Create('Invalid frame time');
  var Selected := Choices(State); var Key := ''; var NonFront: TJSONObject := nil; var FrameIndex := 0;
  try
    if State.NonFrontId <> '' then begin
      for var V in Arr(FCharacter.Settings, 'nonFront') do if S(TJSONObject(V), 'id') = State.NonFrontId then NonFront := TJSONObject(V);
      if NonFront = nil then raise Exception.Create('Non-front pose/sequence unavailable');
      if S(NonFront, 'kind') = 'sequence' then begin
        var Frames := Arr(NonFront, 'frames'); FrameIndex := Trunc(State.Seconds * N(NonFront, 'fps'));
        if B(NonFront, 'loop', True) then FrameIndex := FrameIndex mod Frames.Count else FrameIndex := Min(FrameIndex, Frames.Count - 1);
      end;
      Key := 'nonFront/' + State.NonFrontId + '/' + FrameIndex.ToString;
    end else begin
      for var V in Arr(FCharacter.Settings, 'groups') do Key := Key + Selected[S(TJSONObject(V), 'id')] + '|';
    end;
    if FCache.TryGetValue(Key, Result) then Exit;
    if FCharacter.Policy = 'external' then Result := RenderPsdLayers(FDocument)
    else begin
      FDocument.FindLayer(S(FCharacter.Settings, 'frontId')).Visible := NonFront = nil;
      var Branch := FDocument.FindLayer(S(FCharacter.Settings, 'nonFrontId')); Branch.Visible := NonFront <> nil;
      for var L in Branch.Children do L.Visible := (NonFront <> nil) and (L.Id = S(NonFront, 'layerId'));
      for var V in Arr(FCharacter.Settings, 'groups') do begin
        var G := TJSONObject(V);
        for var Part in Arr(G, 'partIds') do
          FDocument.FindLayer(Part.Value).Visible := Selected.ContainsKey(S(G, 'id')) and (Selected[S(G, 'id')] = Part.Value);
      end;
      if (NonFront <> nil) and (S(NonFront, 'kind') = 'sequence') then begin
        // 連番フレームだけを透明キャンバスへ置く。正面の顔・髪・体を残さない。
        SetLength(Result, PixelByteCount(FDocument.Width, FDocument.Height, 4));
        var Job := FWorkspace.BeginJob;
        try
          TFile.WriteAllBytes(Job.FilePath('frame.png'), FCharacter.Assets[Arr(NonFront, 'frames')[FrameIndex].Value]);
          var PNG := ReadPng(Job.FilePath('frame.png'));
          var W := Max(1, Round(PNG.Width * FScale)); var H := Max(1, Round(PNG.Height * FScale));
          var Data := ResampleRgba(PNG.Pixels, PNG.Width, PNG.Height, TArtBounds.Create(0, 0, PNG.Width, PNG.Height), W, H);
          var X := Round(I(NonFront, 'x') * FScale); var Y := Round(I(NonFront, 'y') * FScale);
          for var SY := 0 to H - 1 do for var SX := 0 to W - 1 do
            if (SX + X >= 0) and (SX + X < FDocument.Width) and (SY + Y >= 0) and (SY + Y < FDocument.Height) then
              Move(Data[(SY * W + SX) * 4], Result[((SY + Y) * FDocument.Width + SX + X) * 4], 4);
        finally Job.Free; end;
      end else Result := RenderPsdLayers(FDocument);
    end;
    if Int64(FCache.Count + 1) * Length(Result) > 64 * 1024 * 1024 then FCache.Clear;
    FCache.Add(Key, Result);
  finally Selected.Free; end;
end;
function PendulumWeight(H, Waist, Neck, Flex: Double): Double;
  function Smooth(V: Double): Double;
  begin V := EnsureRange(V, 0.0, 1.0); Result := V * V * (3 - 2 * V); end;
begin
  Waist := EnsureRange(Waist, 0.01, 0.9); Neck := EnsureRange(Neck,Waist+0.01,1.0); Flex := EnsureRange(Flex, 0.0, 1.0);
  var Segmented: Double;
  if H < Waist then Segmented := 0.35 * Smooth(H / Waist)
  else if H < Neck then Segmented := 0.35 + 0.65 * Smooth((H - Waist) / (Neck - Waist))
  else Segmented := 1;
  Result := H + (Segmented - H) * Flex;
end;
function TPsdRenderer.Frame(const State: TPsdFrameState; Width, Height: Integer): TBytes;
begin Result := FramePixels(State,Composite(State),Width,Height); end;
function TPsdRenderer.SelectionFrame(const State: TPsdFrameState; const LayerId: string; Width,Height: Integer): TBytes;
  function Isolate(Layers: TList<TArtLayer>): Boolean;
  begin
    Result := False;
    for var L in Layers do begin
      if L.Id=LayerId then L.Visible := True
      else L.Visible := Isolate(L.Children);
      Result := Result or L.Visible;
    end;
  end;
begin
  // 保存文書には触れない。管理素材は既存の排他的な部位選択合成を使う。
  var V := State; V.Motion := 'none'; V.NonFrontId := '';
  if FCharacter.Policy='external' then begin
    var D := FDocument.Clone;
    try Isolate(D.Roots); Result := FramePixels(V,RenderPsdLayers(D),Width,Height);
    finally D.Free; end;
    Exit;
  end;
  var GroupId := ''; var PartId := LayerId;
  for var Item in Arr(FCharacter.Settings,'groups') do begin
    var G := TJSONObject(Item);
    if S(G,'id')=LayerId then begin GroupId := LayerId; PartId := S(G,'defaultPartId'); Break; end;
    for var P in Arr(G,'partIds') do if P.Value=LayerId then begin GroupId := S(G,'id'); Break; end;
    if GroupId<>'' then Break;
  end;
  if GroupId='' then Exit(Frame(State,Width,Height));
  var Selected := Choices(V); var Variants := TJSONArray.Create;
  try
    Selected.AddOrSetValue(GroupId,PartId);
    for var Pair in Selected do begin
      var O := TJSONObject.Create; O.AddPair('groupId',Pair.Key); O.AddPair('partId',Pair.Value); Variants.AddElement(O);
    end;
    V.Expression := ''; V.Gaze := 'front'; V.AutoBlink := False; V.HasPhoneme := False; V.Variants := Variants;
    Result := Frame(V,Width,Height);
  finally Variants.Free; Selected.Free; end;
end;
function TPsdRenderer.FramePixels(const State: TPsdFrameState; const Source: TBytes; Width,Height: Integer): TBytes;
begin
  if (Width < 1) or (Height < 1) then raise Exception.Create('Frame size required');
  SetLength(Result, PixelByteCount(Width, Height, 4));
  var W := FDocument.Width; var H := FDocument.Height;
  var Fit := Min(Width * 0.9 / W, Height * 0.9 / H);
  var T: TRhythmTransform; CalculateRhythmTransform(rmtNone, 0, 2, 0, T);
  if IsNan(State.Strength) or IsInfinite(State.Strength) or (Abs(State.Strength) > 100) then raise Exception.Create('Motion strength limit');
  var Strength := State.Strength / (Fit * 1080 / Height);
  if State.Motion = 'sway' then CalculateRhythmTransform(rmtPendulumTwoBeat, State.Seconds / 2, 2, Strength, T)
  else if State.Motion = 'jump' then CalculateRhythmTransform(rmtVerticalJump, State.Seconds / 2, 2, Strength, T)
  else if State.Motion = 'breathe' then T.VerticalScale := 1 + State.Strength / 2000 * Sin(State.Seconds * Pi / 2)
  else if (State.Motion <> '') and (State.Motion <> 'none') then raise Exception.Create('Unknown small motion');
  var Reference: TJSONObject := nil;
  if (State.NonFrontId='') and (FCharacter.Settings.GetValue('motionReference') is TJSONObject) then begin
    try
      var Candidate := Obj(FCharacter.Settings,'motionReference'); ValidateMotionReference(FCharacter,Candidate); Reference := Candidate;
    except on E: Exception do Reference := nil; end; // 保存済み作品は以前の全体変形へフォールバックする。
  end;
  var NeckRatio := Min(0.9,T.WaistRatio+0.3); var NeckY := 0.0; var BodyBottom := 0.0;
  if Reference<>nil then begin
    NeckY := N(Obj(Reference,'neck'),'y')*FScale; BodyBottom := N(Reference,'upperBodyBottomY')*FScale;
    T.WaistRatio := (H-BodyBottom)/Max(1,H); NeckRatio := (H-NeckY)/Max(1,H);
  end;
  var CX := Width / 2.0; var Bottom := Height * 0.95;
  var Angle := DegToRad(T.AngleDegrees); var C := Cos(Angle); var Sn := Sin(Angle);
  // 余白を含むFullHDへ逆写像。alphaを重みにした補間で縁の色漏れを防ぐ。
  var Left := Max(0, Floor(CX - W * Fit / 2 - Abs(T.TopOffsetX * Fit) - 120 * Height / 1080));
  var Right := Min(Width - 1, Ceil(CX + W * Fit / 2 + Abs(T.TopOffsetX * Fit) + 120 * Height / 1080));
  for var DY := Max(0, Floor(Bottom - H * Fit * 1.15 - 120 * Height / 1080)) to Min(Height - 1, Ceil(Bottom + 100 * Height / 1080)) do
    for var DX := Left to Right do begin
      var X := (DX + 0.5 - CX) / Fit - T.OffsetX; var Y := (DY + 0.5 - Bottom) / Fit - T.OffsetY;
      var SY := H + (-Sn * X + C * Y) / (T.Scale * T.VerticalScale) - 0.5;
      if (Reference<>nil) and (State.Motion='breathe') then begin
        var RawY := H+(-Sn*X+C*Y)/T.Scale-0.5;
        var MovedNeck := BodyBottom+(NeckY-BodyBottom)*T.VerticalScale;
        if RawY<MovedNeck then SY := RawY+NeckY-MovedNeck
        else if RawY<BodyBottom then SY := BodyBottom+(RawY-BodyBottom)/T.VerticalScale
        else SY := RawY;
      end;
      var Ratio := EnsureRange((H - 1 - SY) / Max(1, H - 1), 0.0, 1.0);
      var SX := W / 2 + (C * X + Sn * Y) / T.Scale - T.TopOffsetX * PendulumWeight(Ratio, T.WaistRatio, NeckRatio, T.JointFlexibility) - 0.5;
      var IX := Floor(SX); var IY := Floor(SY); var FX := SX - IX; var FY := SY - IY;
      var Values: array[0..3] of Double; FillChar(Values, SizeOf(Values), 0);
      for var J := 0 to 1 do for var K := 0 to 1 do begin
        if (IX + K < 0) or (IX + K >= W) or (IY + J < 0) or (IY + J >= H) then Continue;
        var Weight := IfThen(K = 0, 1 - FX, FX) * IfThen(J = 0, 1 - FY, FY);
        var P := ((IY + J) * W + IX + K) * 4; var Alpha := Source[P + 3] * Weight;
        for var Channel := 0 to 2 do Values[Channel] := Values[Channel] + Source[P + Channel] * Alpha;
        Values[3] := Values[3] + Alpha;
      end;
      var P := (DY * Width + DX) * 4; Result[P + 3] := EnsureRange(Round(Values[3]), 0, 255);
      if Values[3] > 0 then for var Channel := 0 to 2 do Result[P + Channel] := EnsureRange(Round(Values[Channel] / Values[3]), 0, 255);
    end;
end;
destructor TPsdPhonemeTrack.Destroy;
begin FEvents.Free; inherited; end;
procedure TPsdPhonemeTrack.Load(Events: TJSONArray);
begin
  if Events.Count > 20000 then raise Exception.Create('Phoneme count limit');
  var Previous := 0.0;
  for var V in Events do begin
    if not (V is TJSONObject) then raise Exception.Create('Phoneme object required'); var O := TJSONObject(V);
    if (N(O, 'start') < Previous) or (N(O, 'end') <= N(O, 'start')) or (Length(S(O, 'phoneme')) > 32) or
      (S(O, 'phoneme') = '') then raise Exception.Create('Invalid/overlapping phoneme interval');
    Previous := N(O, 'end');
  end;
  var Copy := TJSONArray(Events.Clone); FEvents.Free; FEvents := Copy;
end;
procedure TPsdPhonemeTrack.LoadLab(Workspace: TPsdWorkspace; const Path: string);
begin
  var Lines := TStringList.Create; var Events := TJSONArray.Create;
  try
    Lines.Text := Workspace.ReadText(Path);
    for var Line in Lines do begin
      var Fields := Line.Trim.TrimLeft([#$FEFF]).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      if Length(Fields) = 0 then Continue; var A, B: Int64;
      if (Length(Fields) <> 3) or not TryStrToInt64(Fields[0], A) or not TryStrToInt64(Fields[1], B) then raise Exception.Create('Invalid LAB record');
      var O := TJSONObject.Create; Events.AddElement(O);
      O.AddPair('start', TJSONNumber.Create(A / 10000000.0)); O.AddPair('end', TJSONNumber.Create(B / 10000000.0)); O.AddPair('phoneme', Fields[2]);
    end;
    Load(Events);
  finally Events.Free; Lines.Free; end;
end;
function TPsdPhonemeTrack.Available: Boolean;
begin Result := (FEvents <> nil) and (FEvents.Count > 0); end;
function TPsdPhonemeTrack.Sample(Seconds: Double): string;
begin
  Result := 'closed'; if not Available then Exit;
  var First := 0; var Last := FEvents.Count - 1;
  while First <= Last do begin
    var Middle := (First + Last) div 2; var O := TJSONObject(FEvents[Middle]);
    if Seconds < N(O, 'start') then Last := Middle - 1
    else if Seconds >= N(O, 'end') then First := Middle + 1
    else Exit(S(O, 'phoneme'));
  end;
end;
end.
