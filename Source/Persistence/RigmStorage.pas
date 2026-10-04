unit RigmStorage;

interface
uses System.SysUtils, System.JSON, RigmModel;

const RIGM_FORMAT_VERSION = 1;

function RigmManifest(Document: TRigmDocument): TJSONObject;
procedure SaveRigm(Document: TRigmDocument; const FileName: string);
function LoadRigm(const FileName: string): TRigmDocument;
function ReadRigmThumbnail(const FileName: string; out CharacterName: string; out Width, Height: Integer): TBytes;

implementation
uses System.Classes, System.IOUtils, System.Zip, System.Math, System.StrUtils, System.Generics.Collections,
  System.Generics.Defaults, Winapi.Windows, ArtDocument, RigmJson, RigmRenderer, RigmValidation;

function AssetName(Index: Integer; Mask: Boolean = False): string;
begin
  if Mask then Result := Format('images/%d.mask', [Index])
  else Result := Format('images/%d.rgba', [Index]);
end;

function BoundsJson(const Bounds: TArtBounds): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddN(Result, 'left', Bounds.Left); AddN(Result, 'top', Bounds.Top);
  AddN(Result, 'right', Bounds.Right); AddN(Result, 'bottom', Bounds.Bottom);
end;

function ReadBounds(O: TJSONObject): TArtBounds;
begin Result := TArtBounds.Create(JI(O, 'left'), JI(O, 'top'), JI(O, 'right'), JI(O, 'bottom')); end;

function RigmManifest(Document: TRigmDocument): TJSONObject;
var Parts, Bones, Meshes, Vertices, Faces, Weights, Parameters, Warnings: TJSONArray;
    O, V, W, Flags: TJSONObject; Layer: TArtLayer; Part: TRigmPart; Bone: TRigmBone;
    Mesh: TRigmMesh; Vertex: TRigmVertex; Weight: TRigmWeight; Face: TRigmTriangle;
    Param: TRigmParameter; I: Integer;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('format', 'RIGM'); AddN(Result, 'formatVersion', RIGM_FORMAT_VERSION);
    Result.AddPair('documentId', Document.FileId); Result.AddPair('name', Document.Name);
    Result.AddPair('psdSourceName', Document.PsdSourceName);
    Result.AddPair('psdImportNotes', Document.PsdImportNotes);
    Result.AddPair('revision', Document.Art.Revision.ToString);
    AddN(Result, 'width', Document.Art.Width); AddN(Result, 'height', Document.Art.Height);
    Result.AddPair('coordinates', 'canvas-center-x-right-y-down');
    Result.AddPair('lastPage', PageName(Document.LastPage));
    AddB(Result, 'sourceMatched', Document.SourceMatched);
    AddB(Result, 'hasReference', Length(Document.ReferencePixels) > 0);
    Flags := TJSONObject.Create; Result.AddPair('stages', Flags);
    AddB(Flags, 'layer', Document.LayerComplete); AddB(Flags, 'bone', Document.BoneComplete);
    AddB(Flags, 'mesh', Document.MeshComplete); AddB(Flags, 'usable', Document.Usable);
    Parts := TJSONArray.Create; Result.AddPair('parts', Parts); I := 0;
    for Layer in Document.Layers do begin
      Part := Document.Part(Layer.Id); O := TJSONObject.Create; Parts.AddElement(O);
      O.AddPair('id', Layer.Id); O.AddPair('name', Layer.Name);
      O.AddPair('kind', ifthen(Layer.Kind = alkGroup, 'group', 'image'));
      O.AddPair('blendKey', string(Layer.BlendKey));
      O.AddPair('parentId', Document.ParentId(Layer.Id));
      AddN(O, 'order', Document.LayerList(Layer.Id).IndexOf(Layer));
      O.AddPair('bounds', BoundsJson(Layer.Bounds)); AddB(O, 'visible', Layer.Visible);
      if Layer.Kind = alkImage then begin AddN(O, 'imageWidth', Layer.Bounds.Width); AddN(O, 'imageHeight', Layer.Bounds.Height); end;
      AddN(O, 'opacity', Layer.Opacity); O.AddPair('role', Part.Role);
      AddB(O, 'roleManual', Part.RoleManual); AddB(O, 'referenceOnly', Part.ReferenceOnly);
      O.AddPair('pairId', Part.PairId); O.AddPair('boneId', Part.BoneId); O.AddPair('tags', Part.Tags);
      AddN(O, 'x', Part.X); AddN(O, 'y', Part.Y); AddN(O, 'rotation', Part.Rotation);
      AddN(O, 'scaleX', Part.ScaleX); AddN(O, 'scaleY', Part.ScaleY); AddB(O, 'locked', Part.Locked);
      if Layer.Kind = alkImage then O.AddPair('asset', AssetName(I));
      AddB(O, 'hasMask', Layer.HasMask);
      if Layer.HasMask then begin
        O.AddPair('maskAsset', AssetName(I, True)); O.AddPair('maskBounds', BoundsJson(Layer.MaskBounds));
        AddN(O, 'maskDefault', Layer.MaskDefault); AddB(O, 'maskDisabled', Layer.MaskDisabled); AddB(O, 'maskInvert', Layer.MaskInvert);
      end;
      Inc(I);
    end;
    var Rig := TJSONObject.Create; Result.AddPair('bodyRig', Rig);
    Rig.AddPair('waistBoneId', Document.WaistBoneId); Rig.AddPair('upperBodyBoneId', Document.UpperBodyBoneId);
    Bones := TJSONArray.Create; Result.AddPair('bones', Bones);
    for Bone in Document.Bones do begin
      O := TJSONObject.Create; Bones.AddElement(O); O.AddPair('id', Bone.Id); O.AddPair('name', Bone.Name);
      O.AddPair('parentId', Bone.ParentId); O.AddPair('pairId', Bone.PairId);
      AddN(O, 'x', Bone.X); AddN(O, 'y', Bone.Y); AddN(O, 'initialX', Bone.InitialX); AddN(O, 'initialY', Bone.InitialY);
      AddN(O, 'minAngle', Bone.MinAngle); AddN(O, 'maxAngle', Bone.MaxAngle);
      AddB(O, 'visible', Bone.Visible); AddB(O, 'locked', Bone.Locked);
    end;
    Meshes := TJSONArray.Create; Result.AddPair('meshes', Meshes);
    for Mesh in Document.Meshes do begin
      O := TJSONObject.Create; Meshes.AddElement(O); O.AddPair('id', Mesh.Id); O.AddPair('name', Mesh.Name);
      O.AddPair('partId', Mesh.PartId); O.AddPair('role', Mesh.Role); O.AddPair('interpolation', Mesh.Interpolation);
      AddB(O, 'visible', Mesh.Visible); AddB(O, 'locked', Mesh.Locked); AddB(O, 'automatic', Mesh.Automatic);
      AddB(O, 'boundaryFixed', Mesh.BoundaryFixed); AddN(O, 'strength', Mesh.Strength);
      AddN(O, 'vertexCount', Length(Mesh.Vertices)); AddN(O, 'triangleCount', Length(Mesh.Triangles));
      Vertices := TJSONArray.Create; O.AddPair('vertices', Vertices);
      for Vertex in Mesh.Vertices do begin
        V := TJSONObject.Create; Vertices.AddElement(V);
        AddN(V, 'x', Vertex.X); AddN(V, 'y', Vertex.Y); AddN(V, 'u', Vertex.U); AddN(V, 'v', Vertex.V);
        Weights := TJSONArray.Create; V.AddPair('weights', Weights);
        for Weight in Vertex.Weights do begin
          W := TJSONObject.Create; Weights.AddElement(W); W.AddPair('boneId', Weight.BoneId); AddN(W, 'value', Weight.Value);
        end;
      end;
      Faces := TJSONArray.Create; O.AddPair('triangles', Faces);
      for Face in Mesh.Triangles do begin V := TJSONObject.Create; Faces.AddElement(V); AddN(V, 'a', Face.A); AddN(V, 'b', Face.B); AddN(V, 'c', Face.C); end;
    end;
    Parameters := TJSONArray.Create; Result.AddPair('parameters', Parameters);
    for Param in Document.Parameters do begin
      O := TJSONObject.Create; Parameters.AddElement(O); O.AddPair('id', Param.Id); O.AddPair('name', Param.Name);
      O.AddPair('role', Param.Role); O.AddPair('boneId', Param.BoneId);
      AddN(O, 'minimum', Param.Minimum); AddN(O, 'maximum', Param.Maximum); AddN(O, 'initial', Param.Initial);
    end;
    Warnings := TJSONArray.Create; Result.AddPair('ignoredWarnings', Warnings);
    for var Warning in Document.IgnoredWarnings do Warnings.Add(Warning);
  except Result.Free; raise; end;
end;

function ZipBytes(Zip: TZipFile; const Name: string; MaxBytes: Int64): TBytes;
var Index: Integer; Stream: TStream; Header: TZipHeader;
begin
  Index := Zip.IndexOf(Name);
  if (Index < 0) then raise ERigm.Create('RIGM内に必要なデータがありません: ' + Name);
  if Zip.FileInfo[Index].UncompressedSize > MaxBytes then raise ERigm.Create('RIGM内のデータサイズ上限です。');
  Stream := nil;
  Zip.Read(Index, Stream, Header, True);
  try
    SetLength(Result, Zip.FileInfo[Index].UncompressedSize);
    if Length(Result) > 0 then Stream.ReadBuffer(Result[0], Length(Result));
  finally Stream.Free; end;
end;

procedure CheckArchive(Zip: TZipFile);
var Names: TDictionary<string, Boolean>; Name: string;
begin
  if Zip.FileCount > 5000 then raise ERigm.Create('RIGM内の項目数上限です。');
  Names := TDictionary<string, Boolean>.Create;
  try
    for Name in Zip.FileNames do begin
      if Names.ContainsKey(Name) then raise ERigm.Create('RIGM内の項目名が重複しています。');
      Names.Add(Name, True);
    end;
  finally Names.Free; end;
end;

function OpenManifest(Zip: TZipFile): TJSONObject;
begin
  CheckArchive(Zip);
  Result := ParseObject(TEncoding.UTF8.GetString(ZipBytes(Zip, 'manifest.json', 8 * 1024 * 1024)));
  try
    if (JS(Result, 'format') <> 'RIGM') or (JI(Result, 'formatVersion') <> RIGM_FORMAT_VERSION) then
      raise ERigm.Create('未対応のRIGM形式・バージョンです。');
    if JS(Result, 'coordinates') <> 'canvas-center-x-right-y-down' then raise ERigm.Create('未対応の座標系です。');
  except Result.Free; raise; end;
end;

procedure SaveRigm(Document: TRigmDocument; const FileName: string);
var Zip: TZipFile; Manifest: TJSONObject; Temp: string; Layer: TArtLayer; I, Width, Height: Integer;
    Thumbnail: TBytes; Verify: TRigmDocument;
begin
  if not SameText(ExtractFileExt(FileName), '.rigm') then raise ERigm.Create('保存先には.rigm拡張子を指定してください。');
  Document.ValidateStructure; ForceDirectories(ExtractFilePath(ExpandFileName(FileName)));
  Temp := FileName + '.' + NewRigmId + '.tmp'; Zip := TZipFile.Create; Manifest := nil;
  try
    Manifest := RigmManifest(Document); Thumbnail := RenderRigm(Document, nil, 192, Width, Height);
    AddN(Manifest, 'thumbnailWidth', Width); AddN(Manifest, 'thumbnailHeight', Height);
    Zip.Open(Temp, zmWrite); Zip.Add(TEncoding.UTF8.GetBytes(Manifest.ToJSON), 'manifest.json');
    Zip.Add(Thumbnail, 'thumbnail.rgba'); I := 0;
    for Layer in Document.Layers do begin
      if Layer.Kind = alkImage then Zip.Add(Layer.Pixels, AssetName(I));
      if Layer.HasMask then Zip.Add(Layer.MaskPixels, AssetName(I, True)); Inc(I);
    end;
    if Length(Document.ReferencePixels) > 0 then Zip.Add(Document.ReferencePixels, 'reference.rgba');
    Zip.Close;
    Verify := LoadRigm(Temp); Verify.Free;
    if FileExists(FileName) then TFile.Copy(FileName, FileName + '.bak', True);
    if not MoveFileEx(PChar(Temp), PChar(FileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally
    Manifest.Free; Zip.Free;
    if FileExists(Temp) then TFile.Delete(Temp);
  end;
end;

function LoadRigm(const FileName: string): TRigmDocument;
var Zip: TZipFile; Manifest, O, V, W, Flags: TJSONObject; ArrayValue, Vertices, Weights: TJSONArray;
    Value: TJSONValue; Layer, Parent: TArtLayer; Part: TRigmPart; Bone: TRigmBone; Mesh: TRigmMesh;
    Param: TRigmParameter; I, J, K, Bytes: Integer; Total: Int64;
    Parents: TDictionary<string, string>; Orders: TDictionary<string, Integer>; Issues: TRigmIssues;
  function ObjectValue(Value: TJSONValue): TJSONObject;
  begin
    if not (Value is TJSONObject) then raise ERigm.Create('RIGM内のオブジェクトが不正です。');
    Result := TJSONObject(Value);
  end;
  function Image(const Name: string; Expected: Integer): TBytes;
  begin
    if Int64(Expected) + Total > ART_MAX_BYTES then raise ERigm.Create('RIGM画像の合計サイズ上限です。');
    Result := ZipBytes(Zip, Name, Expected);
    if Length(Result) <> Expected then raise ERigm.Create('RIGM画像・マスクのサイズが一致しません。');
    Inc(Total, Expected);
  end;
begin
  Result := TRigmDocument.Create; Zip := TZipFile.Create; Manifest := nil;
  Parents := TDictionary<string, string>.Create; Orders := TDictionary<string, Integer>.Create;
  try
    try
      if TFile.GetSize(FileName) > ART_MAX_BYTES then raise ERigm.Create('RIGMファイルのサイズ上限です。');
      Zip.Open(FileName, zmRead); Manifest := OpenManifest(Zip);
      Result.FileId := JS(Manifest, 'documentId'); if Result.FileId = '' then raise ERigm.Create('文書IDがありません。');
      Result.Name := JS(Manifest, 'name');
      Result.PsdSourceName := JS(Manifest, 'psdSourceName');
      Result.PsdImportNotes := JS(Manifest, 'psdImportNotes');
      if not TryStrToUInt64(JS(Manifest, 'revision'), Result.Art.Revision) then raise ERigm.Create('文書版が不正です。');
      Result.Art.Width := JI(Manifest, 'width'); Result.Art.Height := JI(Manifest, 'height');
      Bytes := PixelByteCount(Result.Art.Width, Result.Art.Height, 4); Total := 0;
      ArrayValue := JA(Manifest, 'parts'); if ArrayValue.Count > 2000 then raise ERigm.Create('パーツ数上限です。');
      for Value in ArrayValue do begin
        O := ObjectValue(Value); Layer := Result.Art.NewUnattachedLayer;
        Layer.Id := JS(O, 'id'); Layer.Name := JS(O, 'name'); Layer.Bounds := ReadBounds(JO(O, 'bounds'));
        if JS(O, 'kind') = 'group' then begin Layer.Kind := alkGroup; Layer.BlendKey := 'pass'; end
        else if JS(O, 'kind') = 'image' then begin
          Layer.Kind := alkImage; Layer.Pixels := Image(JS(O, 'asset'), PixelByteCount(Layer.Bounds.Width, Layer.Bounds.Height, 4));
        end else raise ERigm.Create('パーツ種別が不正です。');
        Layer.BlendKey := AnsiString(JS(O, 'blendKey', string(Layer.BlendKey)));
        Parents.Add(Layer.Id, JS(O, 'parentId')); Orders.Add(Layer.Id, JI(O, 'order'));
        Layer.Visible := JB(O, 'visible'); Layer.Opacity := EnsureRange(JI(O, 'opacity'), 0, 255);
        Layer.HasMask := JB(O, 'hasMask');
        if Layer.HasMask then begin
          Layer.MaskBounds := ReadBounds(JO(O, 'maskBounds')); Layer.MaskDefault := EnsureRange(JI(O, 'maskDefault'), 0, 255);
          Layer.MaskDisabled := JB(O, 'maskDisabled'); Layer.MaskInvert := JB(O, 'maskInvert');
          Layer.MaskPixels := Image(JS(O, 'maskAsset'), PixelByteCount(Layer.MaskBounds.Width, Layer.MaskBounds.Height, 1));
        end;
        Part := TRigmPart.Create; Part.Id := Layer.Id; Result.Parts.Add(Part.Id, Part);
        Part.Role := JS(O, 'role'); Part.RoleManual := JB(O, 'roleManual'); Part.ReferenceOnly := JB(O, 'referenceOnly');
        Part.PairId := JS(O, 'pairId'); Part.BoneId := JS(O, 'boneId'); Part.Tags := JS(O, 'tags');
        Part.X := JN(O, 'x'); Part.Y := JN(O, 'y'); Part.Rotation := JN(O, 'rotation');
        Part.ScaleX := JN(O, 'scaleX', 1); Part.ScaleY := JN(O, 'scaleY', 1); Part.Locked := JB(O, 'locked');
      end;
      for var Pair in Parents do begin
        Layer := Result.Art.FindLayer(Pair.Key);
        if Pair.Value = '' then Result.Art.Roots.Add(Layer)
        else begin
          Parent := Result.Art.FindLayer(Pair.Value);
          if (Parent = nil) or (Parent.Kind <> alkGroup) then raise ERigm.Create('パーツ階層の親が不正です。');
          Parent.Children.Add(Layer);
        end;
      end;
      Result.Art.Roots.Sort(TComparer<TArtLayer>.Construct(
        function(const A, B: TArtLayer): Integer begin Result := CompareValue(Orders[A.Id], Orders[B.Id]); end));
      for Layer in Result.Layers do Layer.Children.Sort(TComparer<TArtLayer>.Construct(
        function(const A, B: TArtLayer): Integer begin Result := CompareValue(Orders[A.Id], Orders[B.Id]); end));
      Result.SourceMatched := JB(Manifest, 'sourceMatched');
      if JB(Manifest, 'hasReference') then Result.ReferencePixels := Image('reference.rgba', Bytes);
      ArrayValue := JA(Manifest, 'bones'); if ArrayValue.Count > 512 then raise ERigm.Create('ボーン数上限です。');
      for Value in ArrayValue do begin
        O := ObjectValue(Value); Bone := TRigmBone.Create; Result.Bones.Add(Bone);
        Bone.Id := JS(O, 'id'); Bone.Name := JS(O, 'name'); Bone.ParentId := JS(O, 'parentId'); Bone.PairId := JS(O, 'pairId');
        Bone.X := JN(O, 'x'); Bone.Y := JN(O, 'y'); Bone.InitialX := JN(O, 'initialX'); Bone.InitialY := JN(O, 'initialY');
        Bone.MinAngle := JN(O, 'minAngle'); Bone.MaxAngle := JN(O, 'maxAngle'); Bone.Visible := JB(O, 'visible'); Bone.Locked := JB(O, 'locked');
      end;
      if Manifest.GetValue('bodyRig') <> nil then begin
        Result.WaistBoneId := JS(JO(Manifest, 'bodyRig'), 'waistBoneId');
        Result.UpperBodyBoneId := JS(JO(Manifest, 'bodyRig'), 'upperBodyBoneId');
      end;
      ArrayValue := JA(Manifest, 'meshes'); if ArrayValue.Count > 2000 then raise ERigm.Create('メッシュ数上限です。');
      for Value in ArrayValue do begin
        O := ObjectValue(Value); Mesh := TRigmMesh.Create; Result.Meshes.Add(Mesh);
        Mesh.Id := JS(O, 'id'); Mesh.Name := JS(O, 'name'); Mesh.PartId := JS(O, 'partId'); Mesh.Role := JS(O, 'role');
        Mesh.Interpolation := JS(O, 'interpolation'); Mesh.Strength := JN(O, 'strength', 1);
        Mesh.Visible := JB(O, 'visible'); Mesh.Locked := JB(O, 'locked'); Mesh.Automatic := JB(O, 'automatic'); Mesh.BoundaryFixed := JB(O, 'boundaryFixed');
        Vertices := JA(O, 'vertices'); if Vertices.Count > 1024 then raise ERigm.Create('メッシュ頂点数上限です。');
        SetLength(Mesh.Vertices, Vertices.Count);
        for I := 0 to Vertices.Count - 1 do begin
          V := ObjectValue(Vertices[I]); Mesh.Vertices[I].X := JN(V, 'x'); Mesh.Vertices[I].Y := JN(V, 'y');
          Mesh.Vertices[I].U := JN(V, 'u'); Mesh.Vertices[I].V := JN(V, 'v');
          Weights := JA(V, 'weights'); if Weights.Count > 8 then raise ERigm.Create('ウェイト数上限です。');
          SetLength(Mesh.Vertices[I].Weights, Weights.Count);
          for J := 0 to Weights.Count - 1 do begin W := ObjectValue(Weights[J]); Mesh.Vertices[I].Weights[J] := TRigmWeight.Create(JS(W, 'boneId'), JN(W, 'value')); end;
        end;
        Vertices := JA(O, 'triangles'); if Vertices.Count > 2048 then raise ERigm.Create('メッシュ面数上限です。');
        SetLength(Mesh.Triangles, Vertices.Count);
        for I := 0 to Vertices.Count - 1 do begin V := ObjectValue(Vertices[I]); Mesh.Triangles[I] := TRigmTriangle.Create(JI(V, 'a'), JI(V, 'b'), JI(V, 'c')); end;
      end;
      ArrayValue := JA(Manifest, 'parameters'); if ArrayValue.Count > 32 then raise ERigm.Create('パラメータ数上限です。');
      SetLength(Result.Parameters, ArrayValue.Count); K := 0;
      for Value in ArrayValue do begin
        O := ObjectValue(Value); Param.Id := JS(O, 'id'); Param.Name := JS(O, 'name'); Param.Role := JS(O, 'role'); Param.BoneId := JS(O, 'boneId');
        Param.Minimum := JN(O, 'minimum'); Param.Maximum := JN(O, 'maximum'); Param.Initial := JN(O, 'initial'); Result.Parameters[K] := Param; Inc(K);
      end;
      for Value in JA(Manifest, 'ignoredWarnings') do begin
        if not (Value is TJSONString) then raise ERigm.Create('無視した警告の形式が不正です。'); Result.IgnoredWarnings.Add(Value.Value);
      end;
      Flags := JO(Manifest, 'stages'); Result.LayerComplete := JB(Flags, 'layer'); Result.BoneComplete := JB(Flags, 'bone');
      Result.MeshComplete := JB(Flags, 'mesh'); Result.Usable := JB(Flags, 'usable'); Result.LastPage := ParsePage(JS(Manifest, 'lastPage'));
      Result.ValidateStructure; Issues := ValidateRigm(Result);
      try
        Result.LayerComplete := Result.LayerComplete and not HasErrors(Issues, rpLayer);
        Result.BoneComplete := Result.BoneComplete and Result.LayerComplete and not HasErrors(Issues, rpBone);
        Result.MeshComplete := Result.MeshComplete and Result.BoneComplete and not HasErrors(Issues, rpMesh);
        Result.Usable := Result.Usable and Result.MeshComplete and not HasErrors(Issues, rpPreview);
      finally Issues.Free; end;
      while not Result.CanOpen(Result.LastPage) do Result.LastPage := Pred(Result.LastPage);
    except Result.Free; raise; end;
  finally Orders.Free; Parents.Free; Manifest.Free; Zip.Free; end;
end;

function ReadRigmThumbnail(const FileName: string; out CharacterName: string; out Width, Height: Integer): TBytes;
var Zip: TZipFile; Manifest: TJSONObject;
begin
  Zip := TZipFile.Create; Manifest := nil;
  try
    Zip.Open(FileName, zmRead); Manifest := OpenManifest(Zip); CharacterName := JS(Manifest, 'name');
    Width := JI(Manifest, 'thumbnailWidth'); Height := JI(Manifest, 'thumbnailHeight');
    if (Width < 1) or (Height < 1) or (Width > 192) or (Height > 192) then raise ERigm.Create('サムネイルの寸法が不正です。');
    Result := ZipBytes(Zip, 'thumbnail.rgba', PixelByteCount(Width, Height, 4));
    if Length(Result) <> PixelByteCount(Width, Height, 4) then raise ERigm.Create('サムネイルのサイズが不正です。');
  finally Manifest.Free; Zip.Free; end;
end;

end.
