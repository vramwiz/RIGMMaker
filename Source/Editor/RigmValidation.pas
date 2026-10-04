unit RigmValidation;

interface
uses System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  RigmModel;

type
  TRigmIssue = class
  public
    Id, Code, TargetId, Message: string;
    Page: TRigmPage;
    Error, Fixable, Ignored: Boolean;
    function Json: TJSONObject;
  end;
  TRigmIssues = TObjectList<TRigmIssue>;

function ValidateRigm(Document: TRigmDocument; Pose: TRigmPose = nil): TRigmIssues;
function HasErrors(Issues: TRigmIssues; ThroughPage: TRigmPage): Boolean;
procedure AutoFixRigm(Document: TRigmDocument; const IssueId: string);

implementation
uses System.Math, System.Types, RigmJson, RigmRenderer, RigmClassification, ArtDocument;

function TRigmIssue.Json: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('id', Id); Result.AddPair('code', Code);
  Result.AddPair('targetId', TargetId); Result.AddPair('page', PageName(Page));
  Result.AddPair('message', Message); AddB(Result, 'error', Error);
  AddB(Result, 'fixable', Fixable); AddB(Result, 'ignored', Ignored);
end;

function HasErrors(Issues: TRigmIssues; ThroughPage: TRigmPage): Boolean;
var Issue: TRigmIssue;
begin
  Result := False;
  for Issue in Issues do if Issue.Error and (Issue.Page <= ThroughPage) then Exit(True);
end;

function ValidateRigm(Document: TRigmDocument; Pose: TRigmPose): TRigmIssues;
var L: TArtLayer; P: TRigmPart; B, Parent: TRigmBone; M: TRigmMesh; V: TRigmVertex;
    W: TRigmWeight; F: TRigmTriangle; I, J, Count: Integer; Sum, Area, DeformedArea: Double;
    Roles: TDictionary<string, Boolean>; Seen: TDictionary<string, Boolean>;
    Used: TArray<Boolean>; A, BP, C: TPointF; Param: TRigmParameter;
  procedure Issue(Page: TRigmPage; const Code, Target, Message: string; Error: Boolean = True; Fixable: Boolean = False);
  var Item: TRigmIssue;
  begin
    Item := TRigmIssue.Create; Item.Page := Page; Item.Code := Code; Item.TargetId := Target;
    Item.Id := Code + ':' + Target; Item.Message := Message; Item.Error := Error; Item.Fixable := Fixable;
    if Page = rpBone then begin
      var TargetBone := Document.Bone(Target);
      var TargetLayer := Document.Art.FindLayer(Target);
      if TargetBone <> nil then Item.Message := 'ボーン「' + TargetBone.Name + '」: ' + Message
      else if TargetLayer <> nil then Item.Message := 'パーツ「' + TargetLayer.Name + '」: ' + Message;
      if (Code = 'bone-parent') or (Code = 'bone-cycle') or (Code = 'hidden-parent') then
        Item.Message := Item.Message + ' 属性の「親ボーン」を修正してください。'
      else if (Code = 'bone-pair') or (Code = 'bone-self-pair') then
        Item.Message := Item.Message + ' 属性の「左右対応ボーン」を修正してください。'
    end;
    Item.Ignored := not Error and (Document.IgnoredWarnings.IndexOf(Item.Id) >= 0);
    Result.Add(Item);
  end;
  function Cross(const A, B, C: TPointF): Double;
  begin Result := (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X); end;
begin
  Result := TRigmIssues.Create(True);
  Roles := TDictionary<string, Boolean>.Create; Seen := TDictionary<string, Boolean>.Create;
  try
    try Document.ValidateStructure;
    except on E: Exception do Issue(rpLayer, 'structure', '', E.Message); end;
    if Document.Art.Roots.Count = 0 then Issue(rpLayer, 'empty', '', '画像パーツを取り込んでください。');
    for L in Document.Layers do begin
      P := Document.Part(L.Id);
      if Trim(L.Name) = '' then Issue(rpLayer, 'name', L.Id, 'パーツ名が空です。');
      if L.Kind = alkImage then begin
        if not Document.IsReferencePart(L.Id) and HasImageContent(L) then
          if not ((P.Role = 'hair') and (InferLayerRole(Document, L) = 'accessory')) then
            Roles.AddOrSetValue(P.Role, True);
        if (Length(L.Pixels) = 0) then Issue(rpLayer, 'missing-image', L.Id, 'パーツ画像がありません。');
        if (P.Role = 'other') and not Document.IsReferencePart(L.Id) then
          Issue(rpLayer, 'unclassified', L.Id, 'パーツ種別が未分類です。', False);
      end;
      if (P.PairId <> '') and (Document.Art.FindLayer(P.PairId) = nil) then
        Issue(rpLayer, 'part-pair', L.Id, '左右対応パーツが見つかりません。');
      if (P.BoneId <> '') and not Document.IsReferencePart(L.Id) then begin
        B := Document.Bone(P.BoneId);
        if B = nil then Issue(rpBone, 'part-bone', L.Id, 'パーツの追従ボーン参照が切れています。')
        else if not B.Visible then Issue(rpBone, 'part-hidden-bone', L.Id, 'パーツが非表示ボーンを参照しています。');
      end;
    end;
    for var Role in ['eye', 'brow', 'mouth', 'hair'] do if not Roles.ContainsKey(Role) then
      Issue(rpLayer, 'required-' + Role, '', '必須パーツ種別がありません: ' + Role);
    // sourceMatched is legacy metadata, not a condition for advancing an editing stage.
    if (Document.WaistBoneId <> '') or (Document.UpperBodyBoneId <> '') then begin
      if not Document.HasUpperBodyRig then Issue(rpBone,'body-rig-reference','', '腰・上半身ボーンの参照が不正です。')
      else begin
        var Waist := Document.Bone(Document.WaistBoneId); var Upper := Document.Bone(Document.UpperBodyBoneId);
        if Upper.ParentId <> Waist.Id then Issue(rpBone,'body-rig-parent',Upper.Id,'上半身の親は腰支点にしてください。');
        if Upper.Y >= Waist.Y then Issue(rpBone,'body-rig-position',Upper.Id,'上半身の位置を腰支点より上にしてください。');
        if not Waist.Visible or not Upper.Visible then Issue(rpBone,'body-rig-hidden',Upper.Id,'腰・上半身ボーンを表示してください。');
        for var Parameter in Document.Parameters do if (Parameter.Id = 'bodyAngle') and (Parameter.BoneId <> Upper.Id) then
          Issue(rpPreview,'body-rig-parameter',Upper.Id,'上半身角度は上半身ボーンに関連付けてください。');
      end;
    end;

    if Document.LayerComplete or (Document.Bones.Count > 0) then begin
      Count := 0;
      for B in Document.Bones do begin
        if B.Visible then Inc(Count);
        if Trim(B.Name) = '' then Issue(rpBone, 'bone-name', B.Id, 'ボーン名が空です。');
        if (B.ParentId <> '') and (Document.Bone(B.ParentId) = nil) then Issue(rpBone, 'bone-parent', B.Id, '親ボーン参照が切れています。');
        if (B.PairId <> '') and (Document.Bone(B.PairId) = nil) then Issue(rpBone, 'bone-pair', B.Id, '左右対応ボーンがありません。');
        if B.PairId = B.Id then Issue(rpBone, 'bone-self-pair', B.Id, '自身を左右対応にできません。');
        Seen.Clear; Parent := B;
        while Parent <> nil do begin
          if Seen.ContainsKey(Parent.Id) then begin Issue(rpBone, 'bone-cycle', B.Id, 'ボーン親子関係が循環しています。'); Break; end;
          Seen.Add(Parent.Id, True); Parent := Document.Bone(Parent.ParentId);
          if (Parent <> nil) and B.Visible and not Parent.Visible then begin
            Issue(rpBone, 'hidden-parent', B.Id, '表示中のボーンに非表示の親があります。'); Break;
          end;
        end;
      end;
      if Count = 0 then Issue(rpBone, 'no-bone', '', '表示中のボーンがありません。');
    end;

    if Document.BoneComplete or (Document.Meshes.Count > 0) then begin
      Seen.Clear;
      for M in Document.Meshes do begin
        L := Document.Art.FindLayer(M.PartId);
        if (L = nil) or (L.Kind <> alkImage) then begin Issue(rpMesh, 'mesh-part', M.Id, 'メッシュの対象パーツがありません。'); Continue; end;
        if Document.IsReferencePart(L.Id) then Continue;
        if Seen.ContainsKey(M.PartId) then Issue(rpMesh, 'mesh-duplicate', M.Id, '同じパーツに複数のメッシュがあります。');
        Seen.AddOrSetValue(M.PartId, True);
        if Length(M.Vertices) < 3 then Issue(rpMesh, 'mesh-vertices', M.Id, 'メッシュには3頂点以上が必要です。');
        if Length(M.Triangles) = 0 then Issue(rpMesh, 'mesh-faces', M.Id, 'メッシュの面がありません。');
        SetLength(Used, Length(M.Vertices)); if Length(Used) > 0 then FillChar(Used[0], Length(Used), 0);
        for F in M.Triangles do begin
          if (F.A < 0) or (F.B < 0) or (F.C < 0) or (F.A >= Length(Used)) or (F.B >= Length(Used)) or (F.C >= Length(Used)) then begin
            Issue(rpMesh, 'mesh-index', M.Id, '面の頂点参照が範囲外です。'); Continue;
          end;
          Used[F.A] := True; Used[F.B] := True; Used[F.C] := True;
          A := TPointF.Create(M.Vertices[F.A].X, M.Vertices[F.A].Y);
          BP := TPointF.Create(M.Vertices[F.B].X, M.Vertices[F.B].Y);
          C := TPointF.Create(M.Vertices[F.C].X, M.Vertices[F.C].Y);
          Area := Cross(A, BP, C);
          if Abs(Area) < 0.0001 then Issue(rpMesh, 'mesh-degenerate', M.Id, '面が潰れています。');
          if Pose <> nil then begin
            A := VertexPosition(Document, M, F.A, Pose); BP := VertexPosition(Document, M, F.B, Pose);
            C := VertexPosition(Document, M, F.C, Pose); DeformedArea := Cross(A, BP, C);
            if (Area * DeformedArea <= 0) then Issue(rpPreview, 'mesh-inversion', M.Id, '現在のポーズで面が反転・崩壊しています。');
          end;
        end;
        for I := 0 to High(M.Vertices) do begin
          V := M.Vertices[I]; Sum := 0;
          if not Used[I] then Issue(rpMesh, 'mesh-disconnected', M.Id, '未接続頂点があります。', True, True);
          if (V.U < 0) or (V.U > 1) or (V.V < 0) or (V.V > 1) then Issue(rpMesh, 'mesh-uv', M.Id, 'UV座標が画像範囲外です。');
          for J := 0 to High(V.Weights) do begin
            W := V.Weights[J]; Sum := Sum + W.Value; B := Document.Bone(W.BoneId);
            if (B = nil) then Issue(rpMesh, 'weight-bone', M.Id, 'ウェイトのボーン参照が切れています。')
            else if not B.Visible then Issue(rpMesh, 'weight-hidden', M.Id, '非表示ボーンへのウェイトがあります。');
            if (W.Value < 0) or (W.Value > 1) then Issue(rpMesh, 'weight-range', M.Id, 'ウェイトは0～1にしてください。');
            for var K := 0 to J - 1 do if V.Weights[K].BoneId = W.BoneId then Issue(rpMesh, 'weight-duplicate', M.Id, '同じボーンのウェイトが重複しています。');
          end;
          if (M.Role <> 'fixed') and (Length(V.Weights) = 0) then Issue(rpMesh, 'weight-missing', M.Id, '可動メッシュの頂点にウェイトがありません。');
          if (Length(V.Weights) > 0) and (Abs(Sum - 1) > 0.0001) then
            Issue(rpMesh, 'weight-sum', M.Id, '頂点ウェイトの合計が1ではありません。', True, True);
        end;
      end;
      for L in Document.Layers do if L.Kind = alkImage then
        if not Seen.ContainsKey(L.Id) and (Document.Part(L.Id).Role <> 'fixed') and not Document.IsReferencePart(L.Id) then
          Issue(rpMesh, 'mesh-missing', L.Id, '可動パーツのメッシュがありません。');
    end;
    Seen.Clear;
    for Param in Document.Parameters do begin
      Seen.AddOrSetValue(Param.Id, True);
      if (Param.BoneId <> '') and (Document.Bone(Param.BoneId) = nil) then
        Issue(rpPreview, 'parameter-bone', Param.Id, 'パラメータのボーン参照が切れています。');
    end;
    for var Required in ['gazeX', 'gazeY', 'headAngle', 'eyeOpen', 'mouthOpen', 'bodyAngle'] do
      if not Seen.ContainsKey(Required) then Issue(rpPreview, 'parameter-missing-' + Required, '', 'プレビューパラメータが不足しています。');
  except Seen.Free; Roles.Free; Result.Free; raise; end;
  Seen.Free; Roles.Free;
end;

procedure AutoFixRigm(Document: TRigmDocument; const IssueId: string);
var M: TRigmMesh; I, J, N: Integer; Sum: Double; Map: TArray<Integer>;
    Used: TArray<Boolean>; Vertices: TArray<TRigmVertex>; F: TRigmTriangle;
begin
  for M in Document.Meshes do begin
    if IssueId = 'weight-sum:' + M.Id then begin
      if M.Locked then raise ERigm.Create('メッシュはロックされています。');
      for I := 0 to High(M.Vertices) do begin
        Sum := 0;
        for var W in M.Vertices[I].Weights do Sum := Sum + Max(0.0, W.Value);
        if Sum <= 0 then raise ERigm.Create('正のウェイトがなく、自動修正できません。');
        for J := 0 to High(M.Vertices[I].Weights) do M.Vertices[I].Weights[J].Value := Max(0.0, M.Vertices[I].Weights[J].Value) / Sum;
      end;
      Exit;
    end;
    if IssueId = 'mesh-disconnected:' + M.Id then begin
      if M.Locked then raise ERigm.Create('メッシュはロックされています。');
      SetLength(Used, Length(M.Vertices)); SetLength(Map, Length(Used));
      for F in M.Triangles do begin
        if (F.A < 0) or (F.B < 0) or (F.C < 0) or (F.A >= Length(Used)) or (F.B >= Length(Used)) or (F.C >= Length(Used)) then
          raise ERigm.Create('面の参照を先に修正してください。');
        Used[F.A] := True; Used[F.B] := True; Used[F.C] := True;
      end;
      SetLength(Vertices, Length(Used)); N := 0;
      for I := 0 to High(Used) do if Used[I] then begin Map[I] := N; Vertices[N] := M.Vertices[I]; Inc(N); end;
      SetLength(Vertices, N); M.Vertices := Vertices;
      for I := 0 to High(M.Triangles) do begin
        M.Triangles[I].A := Map[M.Triangles[I].A]; M.Triangles[I].B := Map[M.Triangles[I].B]; M.Triangles[I].C := Map[M.Triangles[I].C];
      end;
      Exit;
    end;
  end;
  raise ERigm.Create('この異常は手動修正またはAIへの修正依頼が必要です。');
end;

end.
