unit RigmRenderer;

interface
uses System.SysUtils, System.Types, System.Generics.Collections, RigmModel;

type
  TRigmMatrix = record
    A, B, C, D, X, Y: Double;
    class function Identity: TRigmMatrix; static;
    function Apply(PX, PY: Double): TPointF;
  end;
  TRigmRenderContext = class
  private
    FDocument: TRigmDocument;
    FPose: TRigmPose;
    FTransforms: TDictionary<string, TRigmMatrix>;
  public
    constructor Create(Document: TRigmDocument; Pose: TRigmPose);
    destructor Destroy; override;
    function BoneMatrix(const Id: string; Depth: Integer = 0): TRigmMatrix;
    function VertexPosition(Mesh: TRigmMesh; Index: Integer): TPointF;
  end;

function Multiply(const Parent, Local: TRigmMatrix): TRigmMatrix;
function BoneTransform(Document: TRigmDocument; Bone: TRigmBone; Pose: TRigmPose; Depth: Integer = 0): TRigmMatrix;
function VertexPosition(Document: TRigmDocument; Mesh: TRigmMesh; Index: Integer; Pose: TRigmPose): TPointF;
function RenderRigm(Document: TRigmDocument; Pose: TRigmPose; MaxSize: Integer; out Width, Height: Integer): TBytes;

implementation
uses System.Math, ArtDocument;

function FeaturePoint(Part: TRigmPart; Layer: TArtLayer; Pose: TRigmPose; Point: TPointF): TPointF;
var S,C,X,Y: Double;
begin
  Result := Point; if (Pose=nil) or ((Part.Role<>'eye') and (Part.Role<>'mouth')) then Exit;
  SinCos(DegToRad(Part.Rotation),S,C);
  X := (Point.X-Part.X)*C+(Point.Y-Part.Y)*S;
  Y := -(Point.X-Part.X)*S+(Point.Y-Part.Y)*C;
  if Part.Role='eye' then begin
    if not Pose.PartFeatureAssets.ContainsKey(Part.Id) then Y := Y*Max(0.02,Pose.Value('eyeOpen',1));
    X := X+Pose.Value('gazeX')*Layer.Bounds.Width*Part.ScaleX*0.08;
    Y := Y+Pose.Value('gazeY')*Layer.Bounds.Height*Part.ScaleY*0.12;
  end;
  if (Part.Role='mouth') and not Pose.PartFeatureAssets.ContainsKey(Part.Id) then Y := Y*(1+Pose.Value('mouthOpen')*1.5);
  Result := TPointF.Create(Part.X+X*C-Y*S,Part.Y+X*S+Y*C);
end;

class function TRigmMatrix.Identity: TRigmMatrix;
begin Result := Default(TRigmMatrix); Result.A := 1; Result.D := 1; end;

function TRigmMatrix.Apply(PX, PY: Double): TPointF;
begin Result := TPointF.Create(A * PX + C * PY + X, B * PX + D * PY + Y); end;

function Multiply(const Parent, Local: TRigmMatrix): TRigmMatrix;
begin
  Result.A := Parent.A * Local.A + Parent.C * Local.B;
  Result.B := Parent.B * Local.A + Parent.D * Local.B;
  Result.C := Parent.A * Local.C + Parent.C * Local.D;
  Result.D := Parent.B * Local.C + Parent.D * Local.D;
  Result.X := Parent.A * Local.X + Parent.C * Local.Y + Parent.X;
  Result.Y := Parent.B * Local.X + Parent.D * Local.Y + Parent.Y;
end;

function LocalBoneTransform(Document: TRigmDocument; Bone: TRigmBone; Pose: TRigmPose): TRigmMatrix;
var Angle, S, C, PX, PY: Double; Offset: TPointF; P: TRigmParameter;
begin
  Result := TRigmMatrix.Identity;
  if (Bone = nil) or (Pose = nil) or not Bone.Visible then Exit;
  Angle := 0; Pose.BoneAngles.TryGetValue(Bone.Id, Angle);
  for P in Document.Parameters do if P.BoneId = Bone.Id then Angle := Angle + Pose.Value(P.Id, P.Initial);
  Angle := EnsureRange(Angle, Bone.MinAngle, Bone.MaxAngle);
  Offset := TPointF.Zero; Pose.BoneOffsets.TryGetValue(Bone.Id, Offset);
  SinCos(DegToRad(Angle), S, C);
  PX := Bone.X; PY := Bone.Y;
  if Document.HasUpperBodyRig and (Bone.Id = Document.UpperBodyBoneId) then begin
    PX := Document.Bone(Document.WaistBoneId).X; PY := Document.Bone(Document.WaistBoneId).Y;
  end;
  Result.A := C; Result.B := S; Result.C := -S; Result.D := C;
  Result.X := PX - C * PX + S * PY + Offset.X;
  Result.Y := PY - S * PX - C * PY + Offset.Y;
end;

function BoneTransform(Document: TRigmDocument; Bone: TRigmBone; Pose: TRigmPose; Depth: Integer): TRigmMatrix;
begin
  Result := TRigmMatrix.Identity;
  if (Bone = nil) or (Pose = nil) or (Depth > Document.Bones.Count) then Exit;
  Result := Multiply(BoneTransform(Document,Document.Bone(Bone.ParentId),Pose,Depth+1),
    LocalBoneTransform(Document,Bone,Pose));
end;

constructor TRigmRenderContext.Create(Document: TRigmDocument; Pose: TRigmPose);
begin inherited Create; FDocument := Document; FPose := Pose; FTransforms := TDictionary<string,TRigmMatrix>.Create; end;
destructor TRigmRenderContext.Destroy;
begin FTransforms.Free; inherited; end;
function TRigmRenderContext.BoneMatrix(const Id: string; Depth: Integer): TRigmMatrix;
var Bone: TRigmBone;
begin
  Result := TRigmMatrix.Identity; if (FPose = nil) or (Id = '') or (Depth > FDocument.Bones.Count) then Exit;
  if FTransforms.TryGetValue(Id,Result) then Exit;
  Result := TRigmMatrix.Identity;
  Bone := FDocument.Bone(Id); if Bone = nil then Exit;
  Result := Multiply(BoneMatrix(Bone.ParentId,Depth+1),LocalBoneTransform(FDocument,Bone,FPose));
  FTransforms.AddOrSetValue(Id,Result);
end;

function TRigmRenderContext.VertexPosition(Mesh: TRigmMesh; Index: Integer): TPointF;
var V: TRigmVertex; W: TRigmWeight; P, Upper,Local: TPointF; Total, X, Y, Factor: Double;
begin
  V := Mesh.Vertices[Index]; Result := TPointF.Create(V.X, V.Y);
  if FPose = nil then Exit;
  Local := FeaturePoint(FDocument.Part(Mesh.PartId),FDocument.Art.FindLayer(Mesh.PartId),FPose,Result);
  Result := Local;
  Total := 0; X := 0; Y := 0;
  for W in V.Weights do begin
    if (FDocument.Bone(W.BoneId) = nil) or (W.Value <= 0) then Continue;
    P := BoneMatrix(W.BoneId).Apply(Local.X,Local.Y);
    // Legacy body meshes retain their saved weights. A waist-only body vertex
    // receives the same spatial transition as newly generated mixed weights.
    if FDocument.HasUpperBodyRig and Mesh.Automatic and (W.BoneId = FDocument.WaistBoneId) and
      (Length(V.Weights) = 1) and (FDocument.Part(Mesh.PartId).Role = 'body') then begin
      Factor := FDocument.UpperBodyWeight(V.Y);
      Upper := BoneMatrix(FDocument.UpperBodyBoneId).Apply(Local.X,Local.Y);
      P := TPointF.Create(P.X+(Upper.X-P.X)*Factor,P.Y+(Upper.Y-P.Y)*Factor);
    end;
    X := X + P.X * W.Value; Y := Y + P.Y * W.Value; Total := Total + W.Value;
  end;
  if Total > 0 then begin
    Result.X := Local.X + (X / Total - Local.X) * Mesh.Strength;
    Result.Y := Local.Y + (Y / Total - Local.Y) * Mesh.Strength;
  end;
end;

function VertexPosition(Document: TRigmDocument; Mesh: TRigmMesh; Index: Integer; Pose: TRigmPose): TPointF;
var Context: TRigmRenderContext;
begin
  if Pose = nil then Exit(TPointF.Create(Mesh.Vertices[Index].X,Mesh.Vertices[Index].Y));
  Context := TRigmRenderContext.Create(Document,Pose);
  try Result := Context.VertexPosition(Mesh,Index); finally Context.Free; end;
end;

function PartMatrix(Part: TRigmPart; Width, Height: Integer): TRigmMatrix;
var S, C: Double;
begin
  SinCos(DegToRad(Part.Rotation), S, C);
  Result.A := C * Part.ScaleX * Width; Result.B := S * Part.ScaleX * Width;
  Result.C := -S * Part.ScaleY * Height; Result.D := C * Part.ScaleY * Height;
  Result.X := Part.X - (Result.A + Result.C) * 0.5;
  Result.Y := Part.Y - (Result.B + Result.D) * 0.5;
end;

function GroupMatrix(Part: TRigmPart): TRigmMatrix;
var S, C: Double;
begin
  SinCos(DegToRad(Part.Rotation), S, C);
  Result := TRigmMatrix.Identity; Result.A := C * Part.ScaleX; Result.B := S * Part.ScaleX;
  Result.C := -S * Part.ScaleY; Result.D := C * Part.ScaleY; Result.X := Part.X; Result.Y := Part.Y;
end;

function RenderRigm(Document: TRigmDocument; Pose: TRigmPose; MaxSize: Integer; out Width, Height: Integer): TBytes;
var Pixels: TBytes; ScaleX, ScaleY: Double; Context: TRigmRenderContext;
  procedure Composite(var Target: TBytes; const Source: TBytes; Opacity: Byte;
    Left, Top, SourceWidth, SourceHeight: Integer);
  var I, Q, X, Y, C, SA, DA, OA: Integer;
  begin
    for Y := 0 to SourceHeight - 1 do for X := 0 to SourceWidth - 1 do begin
      I := ((Y+Top)*Width+X+Left)*4; Q := (Y*SourceWidth+X)*4;
      SA := Source[Q+3]*Opacity div 255; if SA = 0 then Continue;
      if SA = 255 then begin
        for C := 0 to 2 do Target[I+C] := Source[Q+C]; Target[I+3] := 255; Continue;
      end;
      DA := Target[I+3]; OA := SA+(DA*(255-SA)+127) div 255;
      for C := 0 to 2 do Target[I+C] :=
        (Integer(Source[Q+C])*SA+(Integer(Target[I+C])*DA*(255-SA)+127) div 255+OA div 2) div OA;
      Target[I+3] := OA;
    end;
  end;
  procedure RenderLayer(Layer: TArtLayer; const Parent: TRigmMatrix; var Target: TBytes);
  var Buffer: TBytes; Part: TRigmPart; Mesh: TRigmMesh; V: TArray<TRigmVertex>;
      Points: TArray<TPointF>; Faces: TArray<TRigmTriangle>; Face: TRigmTriangle;
      Matrix: TRigmMatrix; I, X, Y, L, T, R, B, SX, SY, P, Q, C, Mask, MX, MY: Integer;
      Den, WA, WB, WC, U, UVY, WX, WY: Double;
      A, BP, CP, World: TPointF; OriginX, OriginY, BufferWidth, BufferHeight: Integer;
      MinX, MinY, MaxX, MaxY: Double;
  begin
    Part := Document.Part(Layer.Id); Mesh := Document.MeshForPart(Layer.Id);
    Matrix := PartMatrix(Part, Layer.Bounds.Width, Layer.Bounds.Height);
    if Mesh <> nil then begin
      V := Mesh.Vertices; Faces := Mesh.Triangles; SetLength(Points, Length(V));
      for I := 0 to High(V) do Points[I] := Context.VertexPosition(Mesh,I);
    end else begin
      SetLength(V, 4); SetLength(Points, 4);
      V[0].U := 0; V[0].V := 0; V[1].U := 1; V[1].V := 0;
      V[2].U := 0; V[2].V := 1; V[3].U := 1; V[3].V := 1;
      Faces := [TRigmTriangle.Create(0, 1, 2), TRigmTriangle.Create(1, 3, 2)];
      for I := 0 to 3 do begin
        Points[I] := FeaturePoint(Part,Layer,Pose,Matrix.Apply(V[I].U,V[I].V));
        if (Pose <> nil) and (Part.BoneId <> '') then
          Points[I] := Context.BoneMatrix(Part.BoneId).Apply(Points[I].X,Points[I].Y);
      end;
    end;
    for I := 0 to High(Points) do begin
      World := Points[I];
      World := Parent.Apply(World.X, World.Y);
      Points[I] := TPointF.Create((World.X + Document.Art.Width / 2) * ScaleX,
        (World.Y + Document.Art.Height / 2) * ScaleY);
    end;
    MinX := Width; MinY := Height; MaxX := 0; MaxY := 0;
    for World in Points do begin MinX := Min(MinX,World.X); MinY := Min(MinY,World.Y); MaxX := Max(MaxX,World.X); MaxY := Max(MaxY,World.Y); end;
    OriginX := EnsureRange(Floor(MinX),0,Width); OriginY := EnsureRange(Floor(MinY),0,Height);
    BufferWidth := EnsureRange(Ceil(MaxX)+1,0,Width)-OriginX;
    BufferHeight := EnsureRange(Ceil(MaxY)+1,0,Height)-OriginY;
    if (BufferWidth <= 0) or (BufferHeight <= 0) then Exit;
    SetLength(Buffer,PixelByteCount(BufferWidth,BufferHeight,4));
    for Face in Faces do begin
      if (Face.A < 0) or (Face.B < 0) or (Face.C < 0) or
        (Face.A >= Length(V)) or (Face.B >= Length(V)) or (Face.C >= Length(V)) then Continue;
      A := Points[Face.A]; BP := Points[Face.B]; CP := Points[Face.C];
      Den := (BP.Y - CP.Y) * (A.X - CP.X) + (CP.X - BP.X) * (A.Y - CP.Y);
      if Abs(Den) < 0.0000001 then Continue;
      L := Max(0, Floor(Min(A.X, Min(BP.X, CP.X))));
      T := Max(0, Floor(Min(A.Y, Min(BP.Y, CP.Y))));
      R := Min(Width - 1, Ceil(Max(A.X, Max(BP.X, CP.X))));
      B := Min(Height - 1, Ceil(Max(A.Y, Max(BP.Y, CP.Y))));
      for Y := T to B do for X := L to R do begin
        WX := X + 0.5; WY := Y + 0.5;
        WA := ((BP.Y - CP.Y) * (WX - CP.X) + (CP.X - BP.X) * (WY - CP.Y)) / Den;
        WB := ((CP.Y - A.Y) * (WX - CP.X) + (A.X - CP.X) * (WY - CP.Y)) / Den; WC := 1 - WA - WB;
        if (WA < -0.000001) or (WB < -0.000001) or (WC < -0.000001) then Continue;
        U := WA * V[Face.A].U + WB * V[Face.B].U + WC * V[Face.C].U;
        UVY := WA * V[Face.A].V + WB * V[Face.B].V + WC * V[Face.C].V;
        if (U < 0) or (U > 1) or (UVY < 0) or (UVY > 1) then Continue;
        SX := EnsureRange(Floor(U * Layer.Bounds.Width), 0, Layer.Bounds.Width - 1);
        SY := EnsureRange(Floor(UVY * Layer.Bounds.Height), 0, Layer.Bounds.Height - 1);
        P := ((Y-OriginY)*BufferWidth+X-OriginX)*4; Q := (SY * Layer.Bounds.Width + SX) * 4;
        for C := 0 to 3 do Buffer[P + C] := Layer.Pixels[Q + C];
        if Layer.HasMask and not Layer.MaskDisabled then begin
          MX := SX + Layer.Bounds.Left - Layer.MaskBounds.Left;
          MY := SY + Layer.Bounds.Top - Layer.MaskBounds.Top; Mask := Layer.MaskDefault;
          if (MX >= 0) and (MY >= 0) and (MX < Layer.MaskBounds.Width) and (MY < Layer.MaskBounds.Height) then
            Mask := Layer.MaskPixels[MY * Layer.MaskBounds.Width + MX];
          if Layer.MaskInvert then Mask := 255 - Mask;
          Buffer[P + 3] := Buffer[P + 3] * Mask div 255;
        end;
      end;
    end;
    Composite(Target,Buffer,Layer.Opacity,OriginX,OriginY,BufferWidth,BufferHeight);
  end;
  procedure Draw(List: TList<TArtLayer>; const Parent: TRigmMatrix; var Target: TBytes; Depth: Integer);
  var I: Integer; L: TArtLayer; Group: TBytes; Matrix: TRigmMatrix;
  begin
    if Depth > 64 then Exit;
    for I := List.Count - 1 downto 0 do begin
      L := List[I]; var Visible := L.Visible;
      var Override: Boolean;
      if (Pose<>nil) and Pose.PartVisibility.TryGetValue(L.Id,Override) then Visible := Override;
      if not Visible or Document.IsReferencePart(L.Id) then Continue;
      if L.Kind = alkGroup then begin
        Matrix := Multiply(Parent, GroupMatrix(Document.Part(L.Id)));
        if (L.Opacity = 255) and (L.BlendKey = 'pass') then Draw(L.Children, Matrix, Target, Depth + 1)
        else begin
          if Int64(Depth + 1) * Length(Target) > ART_MAX_BYTES then raise ERigm.Create('グループ合成のメモリー上限です。');
          SetLength(Group, Length(Target)); if Length(Group) > 0 then FillChar(Group[0], Length(Group), 0);
          Draw(L.Children, Matrix, Group, Depth + 1); Composite(Target,Group,L.Opacity,0,0,Width,Height); Group := nil;
        end;
      end else RenderLayer(L, Parent, Target);
    end;
  end;
begin
  MaxSize := EnsureRange(MaxSize, 16, 2048);
  ScaleX := Min(1.0, MaxSize / Max(Document.Art.Width, Document.Art.Height));
  Width := Max(1, Round(Document.Art.Width * ScaleX)); Height := Max(1, Round(Document.Art.Height * ScaleX));
  ScaleX := Width / Document.Art.Width; ScaleY := Height / Document.Art.Height;
  SetLength(Pixels, PixelByteCount(Width, Height, 4));
  Context := TRigmRenderContext.Create(Document,Pose);
  try Draw(Document.Art.Roots, TRigmMatrix.Identity, Pixels, 0); Result := Pixels;
  finally Context.Free; end;
end;

end.
