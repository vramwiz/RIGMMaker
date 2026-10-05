unit PsdImport;

// PNG＋現在のJSON配置からPSDを作る。分離/補完の精度を推測せず既存成果を保持。
interface
uses System.SysUtils, System.JSON, PsdCharacter, PsdWorkspace;

function ImportPrepared(Workspace: TPsdWorkspace; const ManifestPath: string): TPsdCharacter;
function ImportExternalPsd(Workspace: TPsdWorkspace; const Path: string): TPsdCharacter;
// Codexが置いたPNGをハッシュ検証して取り込む。元ファイルは変更しない。
procedure AddFrontLayer(Character: TPsdCharacter; Workspace: TPsdWorkspace; Args: TJSONObject);
procedure AddNonFront(Character: TPsdCharacter; Workspace: TPsdWorkspace; Args: TJSONObject);

implementation
uses System.IOUtils, System.Classes, System.Hash, System.DateUtils, System.Generics.Collections, ArtDocument, ArtPng, ArtPsd, PsdJson;

procedure RecordTransfer(C: TPsdCharacter; W: TPsdWorkspace; const AssetId: string; Args: TJSONObject);
begin
  if C.Settings.GetValue('assetHistory') = nil then C.Settings.AddPair('assetHistory', TJSONArray.Create);
  var O := TJSONObject.Create; Arr(C.Settings, 'assetHistory').AddElement(O);
  O.AddPair('assetId', AssetId); O.AddPair('name', S(Args, 'name'));
  O.AddPair('productionMethod', S(Args, 'productionMethod', 'supplied-separated-PNG'));
  O.AddPair('newDrawing', TJSONBool.Create(B(Args, 'newDrawing')));
  O.AddPair('visualState', S(Args, 'visualState', 'pending-user-review'));
  O.AddPair('path', W.Resolve(S(Args, 'path'))); O.AddPair('sha256', S(Args, 'sha256'));
  O.AddPair('receivedUtc', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
  if S(Args, 'rawSourcePath') <> '' then begin
    O.AddPair('rawSourcePath', W.Resolve(S(Args, 'rawSourcePath'))); O.AddPair('rawSourceSha256', S(Args, 'rawSourceSha256'));
  end;
end;

function ReadValue(Workspace: TPsdWorkspace; const Path: string): TJSONValue;
begin Result := Parse(Workspace.ReadText(Path)); end;
procedure AddExistingCombination(C: TPsdCharacter; const Name, Mouth, Brows, Body: string);
begin
  if Obj(C.Settings, 'expressions').GetValue(Name) <> nil then Exit;
  var E := TJSONObject.Create;
  try
    var Variants := TJSONArray.Create; E.AddPair('variants', Variants); var Matched := 0;
    for var V in Arr(C.Settings, 'groups') do begin
      var G := TJSONObject(V); var Id := S(G, 'defaultPartId'); var Choice := '';
      if S(G, 'name') = '口' then Choice := Mouth else if S(G, 'name') = '眉' then Choice := Brows
      else if S(G, 'name') = '体' then Choice := Body;
      if Choice <> '' then begin
        Id := '';
        for var P in Arr(G, 'partIds') do if C.Document.FindLayer(P.Value).Name = '*' + Choice then Id := P.Value;
        if Id = '' then Exit; Inc(Matched);
      end;
      var Item := TJSONObject.Create; Variants.AddElement(Item); Item.AddPair('groupId', S(G, 'id')); Item.AddPair('partId', Id);
    end;
    if Matched <> 3 then Exit;
    E.AddPair('mouthAnimate', TJSONBool.Create(True)); E.AddPair('blinkAnimate', TJSONBool.Create(True));
    E.AddPair('productionMethod', 'existing-layer-combination'); Put(Obj(C.Settings, 'expressions'), Name, E); E := nil;
  finally E.Free; end;
end;
function ImportPrepared(Workspace: TPsdWorkspace; const ManifestPath: string): TPsdCharacter;
var M: TJSONObject; Groups, Parts: TJSONValue;
begin
  M := ObjectText(Workspace.ReadText(ManifestPath)); Groups := nil; Parts := nil; Result := nil;
  try
   try
    if (S(M, 'format') <> 'RIGMMaker.Exchange') or (I(M, 'schemaVersion') <> 1) then raise Exception.Create('Unsupported prepared manifest');
    var Base := ExtractFileDir(Workspace.Resolve(ManifestPath)); var Files := Obj(M, 'files');
    Groups := ReadValue(Workspace, TPath.Combine(Base, S(Files, 'groups')));
    Parts := ReadValue(Workspace, TPath.Combine(Base, S(Files, 'parts')));
    if not (Groups is TJSONArray) or not (Parts is TJSONArray) then raise Exception.Create('Parts/groups arrays required');
    Result := TPsdCharacter.Create;
    var C := Obj(M, 'character'); var Canvas := Obj(C, 'canvas');
    Result.Name := S(C, 'name'); Result.Source := Workspace.Resolve(ManifestPath);
    Result.Document.Width := I(Canvas, 'width'); Result.Document.Height := I(Canvas, 'height');
    PixelByteCount(Result.Document.Width, Result.Document.Height, 4);
    var Bounds := TArtBounds.Create(0, 0, Result.Document.Width, Result.Document.Height);
    var Front := Result.Document.AddLayer(alkGroup, '*正面', Bounds);
    var NonFront := Result.Document.AddLayer(alkGroup, '*非正面・全身ポーズと連番', Bounds); NonFront.Visible := False;
    Put(Result.Settings, 'frontId', Front.Id); Put(Result.Settings, 'nonFrontId', NonFront.Id);
    Put(Result.Settings, 'groups', TJSONValue(Groups.Clone));
    // 入力のgroup配列は手前順。PSDも同じ順序を維持する。
    for var V in TJSONArray(Groups) do begin
      var G := TJSONObject(V); var L := Result.Document.AddLayer(alkGroup, S(G, 'name'), Bounds, Front);
      L.Id := S(G, 'id'); L.Visible := B(G, 'visible', True); L.Opacity := I(G, 'opacityByte', 255);
    end;
    for var V in TJSONArray(Parts) do begin
      var P := TJSONObject(V); var Placement := Obj(P, 'placement');
      if (N(Placement, 'scaleX', 1) <> 1) or (N(Placement, 'scaleY', 1) <> 1) or (N(Placement, 'rotationDegrees') <> 0) then
        raise Exception.Create('Prepared image transform requires explicit raster conversion');
      var PNG := ReadPng(Workspace.Resolve(TPath.Combine(Base, S(P, 'file'))));
      if (PNG.Width <> I(P, 'width')) or (PNG.Height <> I(P, 'height')) then raise Exception.Create('PNG dimensions mismatch');
      var X := N(Placement, 'left'); var Y := N(Placement, 'top');
      if (Frac(X) <> 0) or (Frac(Y) <> 0) or (Abs(X) > 30000) or (Abs(Y) > 30000) then raise Exception.Create('Integer PSD placement required');
      var Parent: TArtLayer := nil;
      if not B(P, 'referenceOnly') then begin
        Parent := Result.Document.FindLayer(S(P, 'groupId')); if Parent = nil then raise Exception.Create('Missing parent group');
      end;
      var L := Result.Document.AddLayer(alkImage, S(P, 'name'), TArtBounds.Create(Round(X), Round(Y), Round(X) + PNG.Width, Round(Y) + PNG.Height), Parent);
      if Result.Document.FindLayer(S(P, 'id')) <> nil then raise Exception.Create('Duplicate input layer ID');
      L.Id := S(P, 'id'); L.Pixels := PNG.Pixels; L.Opacity := I(Placement, 'opacityByte', 255);
      L.Visible := B(P, 'defaultVisible') and not B(P, 'referenceOnly');
      // 入力はpaintOrder昇順（後ろから手前）。PSDの子は手前を先頭へ置く。
      if Parent <> nil then begin Parent.Children.Remove(L); Parent.Children.Insert(0, L); end;
    end;
    Put(Result.Settings, 'expressions', ReadValue(Workspace, TPath.Combine(Base, S(Files, 'expressions'))));
    Put(Result.Settings, 'animation', ReadValue(Workspace, TPath.Combine(Base, S(Files, 'animation'))));
    Put(Result.Settings, 'symbols', ReadValue(Workspace, TPath.Combine(Base, S(Files, 'symbols'))));
    Put(Result.Settings, 'provenance', ReadValue(Workspace, TPath.Combine(Base, S(Files, 'provenance'))));
    var A := Obj(Result.Settings, 'animation'); Put(Obj(Result.Settings, 'gaze'), 'front', S(Obj(A, 'blink'), 'normalPartId'));
    for var V in Arr(Result.Settings, 'groups') do begin var G := TJSONObject(V); Result.SetDefault(S(G, 'id'), S(G, 'defaultPartId')); end;
    AddExistingCombination(Result, '哀しみ', '悲しい', '哀', '通常');
    AddExistingCombination(Result, '解説', '通常', '通常', '手のひらで紹介');
    Result.Validate;
  except Result.Free; Result := nil; raise;
   end;
  finally M.Free; Groups.Free; Parts.Free; end;
end;
function ImportExternalPsd(Workspace: TPsdWorkspace; const Path: string): TPsdCharacter;
begin
  Result := TPsdCharacter.Create;
  try
    Result.Policy := 'external'; Result.Source := Workspace.Resolve(Path);
    Result.Name := TPath.GetFileNameWithoutExtension(Result.Source);
    Result.Document.Free; Result.Document := nil; Result.Document := ReadPsd(Result.Source);
    Result.Validate;
  except Result.Free; raise; end;
end;
function ReceivePng(Workspace: TPsdWorkspace; const Path, Digest: string): TArtPngData;
begin
  if Length(Digest) <> 64 then raise Exception.Create('Expected SHA-256 is required');
  var Input := Workspace.Resolve(Path);
  if not SameText(ExtractFileExt(Input), '.png') then raise Exception.Create('PNG file required');
  var Job := Workspace.BeginJob;
  try
    // 入力を共有読み取りで開き、変更を拒否したまま専用ジョブにスナップショット化する。
    var Stream := TFileStream.Create(Input, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size > 128 * 1024 * 1024 then raise Exception.Create('Transfer file size limit');
      var CopyStream := TFileStream.Create(Job.FilePath('received.png'), fmCreate);
      try CopyStream.CopyFrom(Stream, 0); finally CopyStream.Free; end;
    finally Stream.Free; end;
    if not SameText(THashSHA2.GetHashStringFromFile(Job.FilePath('received.png')), Digest) then raise Exception.Create('PNG SHA-256 mismatch');
    Result := ReadPng(Job.FilePath('received.png'));
  finally Job.Free; end;
end;
procedure AddFrontLayer(Character: TPsdCharacter; Workspace: TPsdWorkspace; Args: TJSONObject);
begin
  Character.RequireManaged; var G := Character.Group(S(Args, 'groupId'));
  var Parent := Character.Document.FindLayer(S(G, 'id'));
  if not Character.Front.Children.Contains(Parent) then raise Exception.Create('正面の既存部位グループを指定してください。');
  var Gaze := S(Args, 'gaze');
  if Gaze <> '' then begin
    if (Gaze <> 'front') and (Gaze <> 'left') and (Gaze <> 'left-up') and (Gaze <> 'up') and (Gaze <> 'right-up') and (Gaze <> 'right') then
      raise Exception.Create('Screen-space gaze required');
    if S(Obj(Obj(Character.Settings, 'animation'), 'blink'), 'groupId') <> Parent.Id then raise Exception.Create('Gaze belongs to eyes group');
  end;
  var X := I(Args, 'x'); var Y := I(Args, 'y');
  if (Abs(Int64(X)) > 30000) or (Abs(Int64(Y)) > 30000) or (S(Args, 'name') = '') then raise Exception.Create('Invalid layer placement/name');
  var PNG := ReceivePng(Workspace, S(Args, 'path'), S(Args, 'sha256'));
  var L := Character.Document.AddLayer(alkImage, '*' + S(Args, 'name'), TArtBounds.Create(X, Y, X + PNG.Width, Y + PNG.Height), Parent);
  L.Pixels := PNG.Pixels; L.Visible := False; Arr(G, 'partIds').Add(L.Id);
  if Gaze <> '' then Put(Obj(Character.Settings, 'gaze'), Gaze, L.Id);
  RecordTransfer(Character, Workspace, L.Id, Args);
end;
procedure AddNonFront(Character: TPsdCharacter; Workspace: TPsdWorkspace; Args: TJSONObject);
begin
  Character.RequireManaged; var Kind := S(Args, 'kind'); var Name := S(Args, 'name');
  if (Name = '') or ((Kind <> 'pose') and (Kind <> 'sequence')) then raise Exception.Create('Pose/sequence name required');
  var X := I(Args, 'x'); var Y := I(Args, 'y');
  if (Abs(Int64(X)) > 30000) or (Abs(Int64(Y)) > 30000) then raise Exception.Create('Invalid full-body placement');
  var O := TJSONObject.Create; var Pending := TDictionary<string, TBytes>.Create;
  try
    var Id := NewId; O.AddPair('id', Id); O.AddPair('name', Name); O.AddPair('kind', Kind);
    O.AddPair('x', TJSONNumber.Create(X)); O.AddPair('y', TJSONNumber.Create(Y));
    if Kind = 'pose' then begin
      var PNG := ReceivePng(Workspace, S(Args, 'path'), S(Args, 'sha256'));
      var L := Character.Document.AddLayer(alkImage, '*' + Name, TArtBounds.Create(X, Y, X + PNG.Width, Y + PNG.Height), Character.NonFront);
      L.Pixels := PNG.Pixels; L.Visible := False; O.AddPair('layerId', L.Id);
      RecordTransfer(Character, Workspace, L.Id, Args);
    end else begin
      var FPS := N(Args, 'fps', 24); var Frames := Arr(Args, 'frames');
      if (FPS <= 0) or (FPS > 120) or (Frames.Count < 1) or (Frames.Count > 2000) then raise Exception.Create('Sequence limits');
      O.AddPair('fps', TJSONNumber.Create(FPS)); O.AddPair('loop', TJSONBool.Create(B(Args, 'loop', True)));
      var Names := TJSONArray.Create; O.AddPair('frames', Names); var W := 0; var H := 0; var Total: Int64 := 0;
      for var V in Frames do begin
        var F := TJSONObject(V); var PNG := ReceivePng(Workspace, S(F, 'path'), S(F, 'sha256'));
        if W = 0 then begin W := PNG.Width; H := PNG.Height; end;
        if (W <> PNG.Width) or (H <> PNG.Height) then raise Exception.Create('Sequence frame dimensions must match');
        // 再エンコードで画像妥当性を保証し、元ファイルとの競合を回避する。
        var Job := Workspace.BeginJob;
        try
          WriteRgbaPng(Job.FilePath('frame.png'), W, H, PNG.Pixels);
          var Data := TFile.ReadAllBytes(Job.FilePath('frame.png')); Inc(Total, Length(Data));
          if Total > 256 * 1024 * 1024 then raise Exception.Create('Sequence compressed size limit');
          var Asset := 'motions/' + Id + '/' + Names.Count.ToString + '.png'; Pending.Add(Asset, Data); Names.Add(Asset);
        finally Job.Free; end;
      end;
      for var Pair in Pending do Character.Assets.Add(Pair.Key, Pair.Value);
    end;
    Arr(Character.Settings, 'nonFront').AddElement(O); O := nil;
  finally O.Free; Pending.Free; end;
end;
end.
