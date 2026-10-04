unit RigmMeshEditing;

interface
uses System.JSON, RigmModel;

function IsMeshCommand(const Command: string): Boolean;
function ApplyMeshCommand(Document: TRigmDocument; const Command: string; Args: TJSONObject): string;

implementation
uses System.SysUtils, System.Math, System.StrUtils, System.Generics.Collections, ArtDocument, RigmJson;

function IsMeshCommand(const Command: string): Boolean;
begin
  Result := (Command = 'generate-mesh') or (Command = 'set-mesh') or
    (Command = 'set-vertices') or (Command = 'delete-mesh') or (Command = 'update-mesh') or
    (Command = 'update-vertex') or (Command = 'add-vertex') or (Command = 'delete-vertex') or
    (Command = 'set-triangles') or (Command = 'set-weights');
end;

function ApplyMeshCommand(Document: TRigmDocument; const Command: string; Args: TJSONObject): string;
var M: TRigmMesh; L: TArtLayer; P: TRigmPart; Id, PartId, BoneId: string;
    A: TJSONArray; V: TRigmVertex; F, Face: TRigmTriangle;
    Faces: TArray<TRigmTriangle>; I, J, N, Index, Grid: Integer;
  function Number(O: TJSONObject; const Key: string): Double;
  begin
    if O.GetValue(Key) = nil then raise ERigm.Create('数値が必要です: ' + Key);
    Result := JN(O, Key);
    if Abs(Result) > 1000000 then raise ERigm.Create('数値が範囲外です: ' + Key);
  end;
  function NeedMesh: TRigmMesh;
  begin
    Result := Document.Mesh(JS(Args, 'id'));
    if Result = nil then raise ERigm.Create('対象メッシュがありません。');
    if Result.Locked and not (MatchStr(Command, ['update-mesh', 'set-mesh']) and
      (Args.GetValue('locked') <> nil) and not JB(Args, 'locked')) then
      raise ERigm.Create('メッシュはロックされています。');
  end;
  procedure CheckPart(const PartId: string);
  begin
    L := Document.Art.FindLayer(PartId);
    if (L = nil) or (L.Kind <> alkImage) or Document.IsReferencePart(PartId) then
      raise ERigm.Create('可動メッシュの対象画像パーツがありません。');
    if Document.Part(PartId).Locked then raise ERigm.Create('パーツはロックされています。');
  end;
  function ReadWeights(A: TJSONArray): TArray<TRigmWeight>;
  var Sum: Double; Bone: TRigmBone;
  begin
    Result := nil;
    if A.Count > 8 then raise ERigm.Create('頂点のボーン数の上限です。');
    SetLength(Result, A.Count); Sum := 0;
    for var K := 0 to A.Count - 1 do begin
      if not (A[K] is TJSONObject) then raise ERigm.Create('ウェイトの形式が不正です。');
      var W := TJSONObject(A[K]); Bone := Document.Bone(JS(W, 'boneId'));
      if (Bone = nil) or not Bone.Visible then raise ERigm.Create('表示中のウェイトボーンを指定してください。');
      Result[K] := TRigmWeight.Create(Bone.Id, Number(W, 'value'));
      if (Result[K].Value < 0) or (Result[K].Value > 1) then raise ERigm.Create('ウェイトは0～1にしてください。');
      for var Q := 0 to K - 1 do if Result[Q].BoneId = Bone.Id then raise ERigm.Create('ボーンのウェイトが重複しています。');
      Sum := Sum + Result[K].Value;
    end;
    if (A.Count > 0) and (Abs(Sum - 1) > 0.0001) then raise ERigm.Create('頂点ウェイトの合計は1にしてください。');
    if (A.Count = 0) and (M.Role <> 'fixed') then raise ERigm.Create('可動メッシュのウェイトが必要です。');
  end;
  function ReadVertex(O: TJSONObject): TRigmVertex;
  begin
    Result := Default(TRigmVertex);
    Result.X := Number(O, 'x'); Result.Y := Number(O, 'y');
    Result.U := Number(O, 'u'); Result.V := Number(O, 'v');
    if (Result.U < 0) or (Result.U > 1) or (Result.V < 0) or (Result.V > 1) then raise ERigm.Create('UVは0～1にしてください。');
    if O.GetValue('weights') <> nil then Result.Weights := ReadWeights(JA(O, 'weights'))
    else if M.Role <> 'fixed' then raise ERigm.Create('可動頂点のウェイトが必要です。');
  end;
  procedure Boundary(const Old, New: TRigmVertex);
  begin
    if M.BoundaryFixed and ((Old.U = 0) or (Old.U = 1) or (Old.V = 0) or (Old.V = 1)) and
      (not SameValue(Old.X, New.X) or not SameValue(Old.Y, New.Y) or
       not SameValue(Old.U, New.U) or not SameValue(Old.V, New.V)) then
      raise ERigm.Create('境界頂点は固定されています。boundaryFixed=falseを明示して解除してください。');
  end;
  procedure ReadFaces(A: TJSONArray);
  begin
    if (A.Count < 1) or (A.Count > 2048) then raise ERigm.Create('面数は1～2048にしてください。');
    SetLength(M.Triangles, A.Count);
    for var K := 0 to A.Count - 1 do begin
      if not (A[K] is TJSONObject) then raise ERigm.Create('面の形式が不正です。');
      var T := TJSONObject(A[K]);
      M.Triangles[K] := TRigmTriangle.Create(JI(T, 'a', -1), JI(T, 'b', -1), JI(T, 'c', -1));
    end;
  end;
  procedure ValidateGeometry;
  begin
    if (Length(M.Vertices) < 3) or (Length(M.Vertices) > 1024) then raise ERigm.Create('頂点数は3～1024にしてください。');
    if Length(M.Triangles) > 2048 then raise ERigm.Create('面数上限です。');
    for var T in M.Triangles do begin
      if (T.A < 0) or (T.B < 0) or (T.C < 0) or (T.A >= Length(M.Vertices)) or
        (T.B >= Length(M.Vertices)) or (T.C >= Length(M.Vertices)) then raise ERigm.Create('面の頂点参照が範囲外です。');
      var VA := M.Vertices[T.A]; var VB := M.Vertices[T.B]; var VC := M.Vertices[T.C];
      if Abs((VB.X - VA.X) * (VC.Y - VA.Y) - (VB.Y - VA.Y) * (VC.X - VA.X)) < 0.0001 then
        raise ERigm.Create('面が潰れています。');
    end;
    for var Vertex in M.Vertices do begin
      if not Finite(Vertex.X) or not Finite(Vertex.Y) or not Finite(Vertex.U) or not Finite(Vertex.V) or
        (Abs(Vertex.X) > 1000000) or (Abs(Vertex.Y) > 1000000) or
        (Vertex.U < 0) or (Vertex.U > 1) or (Vertex.V < 0) or (Vertex.V > 1) then raise ERigm.Create('頂点座標・UVが範囲外です。');
      var Sum := 0.0;
      if (Length(Vertex.Weights) > 8) or ((Length(Vertex.Weights) = 0) and (M.Role <> 'fixed')) then
        raise ERigm.Create('頂点のウェイト数が不正です。');
      for var K := 0 to High(Vertex.Weights) do begin
        var Weight := Vertex.Weights[K]; var Bone := Document.Bone(Weight.BoneId);
        if (Bone = nil) or not Bone.Visible or not Finite(Weight.Value) or (Weight.Value < 0) or (Weight.Value > 1) then
          raise ERigm.Create('ウェイトのボーン参照・値が不正です。');
        for var Q := 0 to K - 1 do if Vertex.Weights[Q].BoneId = Weight.BoneId then raise ERigm.Create('ボーンのウェイトが重複しています。');
        Sum := Sum + Weight.Value;
      end;
      if (Length(Vertex.Weights) > 0) and (Abs(Sum - 1) > 0.0001) then raise ERigm.Create('頂点ウェイトの合計は1にしてください。');
    end;
  end;
  procedure Metadata;
  begin
    M.Name := JS(Args, 'name', M.Name); M.Role := JS(Args, 'role', M.Role);
    M.Interpolation := JS(Args, 'interpolation', M.Interpolation);
    if M.Interpolation <> 'linear' then raise ERigm.Create('現在の補間方式はlinearのみです。');
    M.Visible := JB(Args, 'visible', M.Visible); M.Locked := JB(Args, 'locked', M.Locked);
    M.BoundaryFixed := JB(Args, 'boundaryFixed', M.BoundaryFixed); M.Strength := JN(Args, 'strength', M.Strength);
    if (M.Strength < 0) or (M.Strength > 1) then raise ERigm.Create('変形強度は0～1です。');
  end;
  procedure Generate(const Target: string);
  begin
    CheckPart(Target); P := Document.Part(Target);
    if (Document.MeshForPart(Target) <> nil) and not JB(Args, 'replaceExisting', True) then Exit;
    BoneId := JS(Args, 'boneId', P.BoneId);
    if (BoneId = '') and (P.Role <> 'fixed') then begin
      var ParameterId := 'headAngle';
      if not MatchStr(P.Role, ['eye', 'brow', 'mouth', 'hair', 'face', 'accessory']) then ParameterId := 'bodyAngle';
      for var Param in Document.Parameters do if Param.Id = ParameterId then BoneId := Param.BoneId;
    end;
    if P.Role = 'fixed' then BoneId := '';
    if P.Role <> 'fixed' then begin
      var Bone := Document.Bone(BoneId);
      if (Bone = nil) or not Bone.Visible then raise ERigm.Create('生成対象の表示中ボーンを指定してください: ' + L.Name);
    end;
    Document.GenerateMesh(Target, BoneId, Grid); M := Document.MeshForPart(Target); ValidateGeometry;
    if Result = '' then Result := M.Id;
  end;
begin
  Result := ''; Id := JS(Args, 'id');
  if Command = 'generate-mesh' then begin
    Grid := JI(Args, 'grid', 3);
    if (Grid < 2) or (Grid > 16) then raise ERigm.Create('gridは2～16にしてください。');
    if Id <> '' then Generate(Id)
    else for var Layer in Document.Layers do if (Layer.Kind = alkImage) and not Document.IsReferencePart(Layer.Id) then Generate(Layer.Id);
    if (Result = '') and (Id <> '') and (Document.MeshForPart(Id) <> nil) then Result := Document.MeshForPart(Id).Id;
    Exit;
  end;
  if Command = 'set-mesh' then begin
    if Id <> '' then begin M := NeedMesh; PartId := JS(Args, 'partId', M.PartId);
      if PartId <> M.PartId then raise ERigm.Create('既存メッシュの対象パーツは変更できません。');
    end else begin
      PartId := JS(Args, 'partId'); CheckPart(PartId); M := Document.MeshForPart(PartId);
      if (M <> nil) and M.Locked then raise ERigm.Create('メッシュはロックされています。');
      if M = nil then begin M := TRigmMesh.Create; M.PartId := PartId; M.Name := L.Name; M.Role := Document.Part(PartId).Role; Document.Meshes.Add(M); end;
    end;
    CheckPart(PartId); Metadata;
    A := JA(Args, 'vertices');
    if (A.Count < 3) or (A.Count > 1024) then raise ERigm.Create('頂点数は3～1024にしてください。');
    var OldVertices := M.Vertices; SetLength(M.Vertices, A.Count);
    for I := 0 to A.Count - 1 do begin
      if not (A[I] is TJSONObject) then raise ERigm.Create('頂点の形式が不正です。');
      V := ReadVertex(TJSONObject(A[I])); if I < Length(OldVertices) then Boundary(OldVertices[I], V);
      M.Vertices[I] := V;
    end;
    ReadFaces(JA(Args, 'triangles')); M.Automatic := False;
  end else begin
    M := NeedMesh;
    if Command = 'delete-mesh' then begin CheckPart(M.PartId); Document.Meshes.Remove(M); Exit; end;
    if Command = 'update-mesh' then begin Metadata; Exit(M.Id); end;
    M.Automatic := False;
    if Command = 'set-vertices' then begin
      A := JA(Args, 'vertices'); Index := JI(Args, 'offset');
      if (A.Count < 1) or (Index < 0) or (A.Count > Length(M.Vertices)) or (Index > Length(M.Vertices) - A.Count) then
        raise ERigm.Create('頂点更新範囲が不正です。');
      for I := 0 to A.Count - 1 do begin
        if not (A[I] is TJSONObject) then raise ERigm.Create('頂点の形式が不正です。');
        V := ReadVertex(TJSONObject(A[I])); Boundary(M.Vertices[Index + I], V); M.Vertices[Index + I] := V;
      end;
    end else if Command = 'update-vertex' then begin
      Index := JI(Args, 'vertex', -1);
      if (Index < 0) or (Index >= Length(M.Vertices)) then raise ERigm.Create('頂点番号が範囲外です。');
      V := M.Vertices[Index]; var NewVertex := V;
      NewVertex.X := JN(Args, 'x', V.X); NewVertex.Y := JN(Args, 'y', V.Y);
      NewVertex.U := JN(Args, 'u', V.U); NewVertex.V := JN(Args, 'v', V.V);
      Boundary(V, NewVertex); M.Vertices[Index] := NewVertex;
    end else if Command = 'set-triangles' then ReadFaces(JA(Args, 'triangles'))
    else if Command = 'set-weights' then begin
      Index := JI(Args, 'vertex', -1);
      if (Index < -1) or (Index >= Length(M.Vertices)) then raise ERigm.Create('頂点番号が範囲外です。');
      var Weights := ReadWeights(JA(Args, 'weights'));
      for I := 0 to High(M.Vertices) do if (Index = -1) or (I = Index) then M.Vertices[I].Weights := Copy(Weights);
    end else if Command = 'add-vertex' then begin
      Index := JI(Args, 'face');
      if (Index < 0) or (Index >= Length(M.Triangles)) then raise ERigm.Create('面番号が範囲外です。');
      ValidateGeometry; F := M.Triangles[Index]; V := Default(TRigmVertex);
      V.X := (M.Vertices[F.A].X + M.Vertices[F.B].X + M.Vertices[F.C].X) / 3;
      V.Y := (M.Vertices[F.A].Y + M.Vertices[F.B].Y + M.Vertices[F.C].Y) / 3;
      V.U := (M.Vertices[F.A].U + M.Vertices[F.B].U + M.Vertices[F.C].U) / 3;
      V.V := (M.Vertices[F.A].V + M.Vertices[F.B].V + M.Vertices[F.C].V) / 3;
      // Average the three corners, combining repeated bone IDs.
      var Corners := TArray<Integer>.Create(F.A, F.B, F.C);
      for var Corner in Corners do for var W in M.Vertices[Corner].Weights do begin
        J := 0; while (J < Length(V.Weights)) and (V.Weights[J].BoneId <> W.BoneId) do Inc(J);
        if J = Length(V.Weights) then begin SetLength(V.Weights, J + 1); V.Weights[J] := TRigmWeight.Create(W.BoneId, 0); end;
        V.Weights[J].Value := V.Weights[J].Value + W.Value / 3;
      end;
      if Length(V.Weights) > 8 then raise ERigm.Create('補間頂点のウェイトが8ボーンを超えます。');
      N := Length(M.Vertices); SetLength(M.Vertices, N + 1); M.Vertices[N] := V;
      M.Triangles[Index] := TRigmTriangle.Create(F.A, F.B, N); I := Length(M.Triangles); SetLength(M.Triangles, I + 2);
      M.Triangles[I] := TRigmTriangle.Create(F.B, F.C, N); M.Triangles[I + 1] := TRigmTriangle.Create(F.C, F.A, N);
    end else if Command = 'delete-vertex' then begin
      Index := JI(Args, 'vertex', -1);
      if (Index < 0) or (Index >= Length(M.Vertices)) or (Length(M.Vertices) <= 3) then raise ERigm.Create('この頂点を削除できません。');
      if M.BoundaryFixed and ((M.Vertices[Index].U = 0) or (M.Vertices[Index].U = 1) or
        (M.Vertices[Index].V = 0) or (M.Vertices[Index].V = 1)) then raise ERigm.Create('境界頂点は固定されています。');
      for I := Index to High(M.Vertices) - 1 do M.Vertices[I] := M.Vertices[I + 1]; SetLength(M.Vertices, Length(M.Vertices) - 1);
      Faces := nil;
      for F in M.Triangles do begin
        if (F.A = Index) or (F.B = Index) or (F.C = Index) then Continue;
        Face := F; if Face.A > Index then Dec(Face.A); if Face.B > Index then Dec(Face.B); if Face.C > Index then Dec(Face.C);
        N := Length(Faces); SetLength(Faces, N + 1); Faces[N] := Face;
      end;
      M.Triangles := Faces;
    end else raise ERigm.Create('未対応のメッシュ命令です。');
  end;
  ValidateGeometry; M.Automatic := False; Result := M.Id;
end;

end.
