unit RigmModel;

interface

uses System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  ArtDocument;

type
  ERigm = class(Exception);
  TRigmPage = (rpLayer, rpBone, rpMesh, rpPreview);
  TRigmPart = class
  public
    Id, Role, PairId, BoneId, Tags: string;
    X, Y, Rotation, ScaleX, ScaleY: Double;
    Locked, RoleManual, ReferenceOnly: Boolean;
    constructor Create;
    function Clone: TRigmPart;
  end;
  TRigmBone = class
  public
    Id, Name, ParentId, PairId: string;
    X, Y, InitialX, InitialY, MinAngle, MaxAngle: Double;
    Visible, Locked: Boolean;
    constructor Create;
    function Clone: TRigmBone;
  end;
  TRigmWeight = record
    BoneId: string;
    Value: Double;
    class function Create(const Id: string; Weight: Double): TRigmWeight; static;
  end;
  TRigmVertex = record
    X, Y, U, V: Double;
    Weights: TArray<TRigmWeight>;
  end;
  TRigmTriangle = record
    A, B, C: Integer;
    class function Create(IA, IB, IC: Integer): TRigmTriangle; static;
  end;
  TRigmMesh = class
  public
    Id, Name, PartId, Role, Interpolation: string;
    Visible, Locked, Automatic, BoundaryFixed: Boolean;
    Strength: Double;
    Vertices: TArray<TRigmVertex>;
    Triangles: TArray<TRigmTriangle>;
    constructor Create;
    function Clone: TRigmMesh;
  end;
  TRigmParameter = record
    Id, Name, Role, BoneId: string;
    Minimum, Maximum, Initial: Double;
  end;
  TRigmDocument = class
  private
    FArt: TArtDocument;
  public
    Name, FileId: string;
    PsdSourceName, PsdImportNotes: string;
    WaistBoneId, UpperBodyBoneId: string;
    Parts: TObjectDictionary<string, TRigmPart>;
    Bones: TObjectList<TRigmBone>;
    Meshes: TObjectList<TRigmMesh>;
    Parameters: TArray<TRigmParameter>;
    IgnoredWarnings: TStringList;
    ReferencePixels: TBytes;
    LayerComplete, BoneComplete, MeshComplete, Usable, SourceMatched: Boolean;
    LastPage: TRigmPage;
    constructor Create;
    destructor Destroy; override;
    function Clone: TRigmDocument;
    procedure SetArt(Value: TArtDocument);
    procedure SyncParts;
    function Layers: TArray<TArtLayer>;
    function Part(const Id: string): TRigmPart;
    function IsReferencePart(const Id: string): Boolean;
    function Bone(const Id: string): TRigmBone;
    function Mesh(const Id: string): TRigmMesh;
    function MeshForPart(const Id: string): TRigmMesh;
    function LayerList(const Id: string): TList<TArtLayer>;
    function ParentId(const Id: string): string;
    function CanOpen(Page: TRigmPage): Boolean;
    procedure Changed(Page: TRigmPage);
    procedure ValidateStructure;
    procedure SeedBones;
    function HasUpperBodyRig: Boolean;
    function UpgradeUpperBodyRig: Boolean;
    function UpperBodyWeight(Y: Double): Double;
    function FaceGuide(out Center: TPointF; out Radius: Double): Boolean;
    function AddBone(const ParentId, AName: string): TRigmBone;
    procedure HideBone(const Id: string; Paired: Boolean);
    procedure RestoreChildren(const Id: string; Paired: Boolean);
    procedure MoveBone(const Id: string; X, Y: Double; Paired: Boolean);
    procedure ReparentLayer(const Id, NewParentId: string; Index: Integer);
    procedure GenerateMesh(const PartId, BoneId: string; Grid: Integer);
    property Art: TArtDocument read FArt;
  end;
  TRigmPose = class
  public
    PartVisibility: TDictionary<string, Boolean>;
    PartFeatureAssets: TDictionary<string, Boolean>;
    Values: TDictionary<string, Double>;
    BoneAngles: TDictionary<string, Double>;
    BoneOffsets: TDictionary<string, TPointF>;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    function Value(const Id: string; Default: Double = 0): Double;
  end;

function NewRigmId: string;
function PageName(Page: TRigmPage): string;
function ParsePage(const Value: string): TRigmPage;
function Finite(Value: Double): Boolean;

implementation

uses System.Math;

function NewRigmId: string;
var G: TGUID;
begin
  CreateGUID(G); Result := GUIDToString(G);
end;

function PageName(Page: TRigmPage): string;
const Names: array[TRigmPage] of string = ('layer', 'bone', 'mesh', 'preview');
begin Result := Names[Page]; end;

function ParsePage(const Value: string): TRigmPage;
var P: TRigmPage;
begin
  for P := Low(TRigmPage) to High(TRigmPage) do
    if SameText(Value, PageName(P)) then Exit(P);
  raise ERigm.Create('不明な編集ページ: ' + Value);
end;

function Finite(Value: Double): Boolean;
begin Result := not IsNan(Value) and not IsInfinite(Value); end;

constructor TRigmPart.Create;
begin inherited; Role := 'other'; ScaleX := 1; ScaleY := 1; end;

function TRigmPart.Clone: TRigmPart;
begin
  Result := TRigmPart.Create;
  Result.Id := Id; Result.Role := Role; Result.PairId := PairId;
  Result.BoneId := BoneId; Result.Tags := Tags;
  Result.X := X; Result.Y := Y; Result.Rotation := Rotation;
  Result.ScaleX := ScaleX; Result.ScaleY := ScaleY; Result.Locked := Locked;
  Result.RoleManual := RoleManual; Result.ReferenceOnly := ReferenceOnly;
end;

constructor TRigmBone.Create;
begin
  inherited; Id := NewRigmId; Visible := True; MinAngle := -60; MaxAngle := 60;
end;

function TRigmBone.Clone: TRigmBone;
begin
  Result := TRigmBone.Create;
  Result.Id := Id; Result.Name := Name; Result.ParentId := ParentId;
  Result.PairId := PairId; Result.X := X; Result.Y := Y;
  Result.InitialX := InitialX; Result.InitialY := InitialY;
  Result.MinAngle := MinAngle; Result.MaxAngle := MaxAngle;
  Result.Visible := Visible; Result.Locked := Locked;
end;

class function TRigmWeight.Create(const Id: string; Weight: Double): TRigmWeight;
begin Result.BoneId := Id; Result.Value := Weight; end;

class function TRigmTriangle.Create(IA, IB, IC: Integer): TRigmTriangle;
begin Result.A := IA; Result.B := IB; Result.C := IC; end;

constructor TRigmMesh.Create;
begin
  inherited; Id := NewRigmId; Visible := True; Automatic := True;
  Role := 'normal'; Strength := 1; Interpolation := 'linear';
end;

function TRigmMesh.Clone: TRigmMesh;
var I: Integer;
begin
  Result := TRigmMesh.Create;
  Result.Id := Id; Result.Name := Name; Result.PartId := PartId; Result.Role := Role;
  Result.Interpolation := Interpolation; Result.Visible := Visible;
  Result.Locked := Locked; Result.Automatic := Automatic;
  Result.BoundaryFixed := BoundaryFixed; Result.Strength := Strength;
  Result.Vertices := Copy(Vertices); Result.Triangles := Copy(Triangles);
  for I := 0 to High(Result.Vertices) do
    Result.Vertices[I].Weights := Copy(Vertices[I].Weights);
end;

constructor TRigmDocument.Create;
  procedure Parameter(Index: Integer; const Id, Caption, Role: string; Lo, Hi, Initial: Double);
  begin
    Parameters[Index].Id := Id; Parameters[Index].Name := Caption;
    Parameters[Index].Role := Role; Parameters[Index].Minimum := Lo;
    Parameters[Index].Maximum := Hi; Parameters[Index].Initial := Initial;
  end;
begin
  inherited; FileId := NewRigmId; Name := '新しいキャラクター';
  FArt := TArtDocument.Create; FArt.Width := 1024; FArt.Height := 1024;
  Parts := TObjectDictionary<string, TRigmPart>.Create([doOwnsValues]);
  Bones := TObjectList<TRigmBone>.Create(True);
  Meshes := TObjectList<TRigmMesh>.Create(True);
  IgnoredWarnings := TStringList.Create;
  SetLength(Parameters, 6);
  Parameter(0, 'gazeX', '視線 X', 'eye', -1, 1, 0);
  Parameter(1, 'gazeY', '視線 Y', 'eye', -1, 1, 0);
  Parameter(2, 'headAngle', '顔角度', 'head', -30, 30, 0);
  Parameter(3, 'eyeOpen', '目の開き', 'eye', 0, 1, 1);
  Parameter(4, 'mouthOpen', '口の開き', 'mouth', 0, 1, 0);
  Parameter(5, 'bodyAngle', '上半身角度', 'upperBody', -20, 20, 0);
end;

destructor TRigmDocument.Destroy;
begin
  IgnoredWarnings.Free; Meshes.Free; Bones.Free; Parts.Free; FArt.Free; inherited;
end;

function TRigmDocument.Layers: TArray<TArtLayer>;
var List: TList<TArtLayer>;
  procedure Visit(Roots: TList<TArtLayer>);
  var L: TArtLayer;
  begin for L in Roots do begin List.Add(L); Visit(L.Children); end; end;
begin
  List := TList<TArtLayer>.Create;
  try Visit(FArt.Roots); Result := List.ToArray; finally List.Free; end;
end;

procedure TRigmDocument.SetArt(Value: TArtDocument);
begin
  if Value = nil then raise ERigm.Create('画像文書がありません。');
  FArt.Free; FArt := Value; Parts.Clear; SyncParts;
end;

procedure TRigmDocument.SyncParts;
var L: TArtLayer; P: TRigmPart;
begin
  for L in Layers do if not Parts.ContainsKey(L.Id) then begin
    P := TRigmPart.Create; P.Id := L.Id;
    if L.Kind = alkGroup then P.Role := 'group'
    else begin
      P.X := (L.Bounds.Left + L.Bounds.Right) / 2 - FArt.Width / 2;
      P.Y := (L.Bounds.Top + L.Bounds.Bottom) / 2 - FArt.Height / 2;
    end;
    Parts.Add(L.Id, P);
  end;
end;

function TRigmDocument.Clone: TRigmDocument;
var P: TPair<string, TRigmPart>; B: TRigmBone; M: TRigmMesh;
begin
  Result := TRigmDocument.Create;
  try
    Result.FArt.Free; Result.FArt := FArt.Clone;
    Result.FileId := FileId; Result.Name := Name;
    Result.PsdSourceName := PsdSourceName; Result.PsdImportNotes := PsdImportNotes;
    Result.WaistBoneId := WaistBoneId; Result.UpperBodyBoneId := UpperBodyBoneId;
    for P in Parts do Result.Parts.Add(P.Key, P.Value.Clone);
    for B in Bones do Result.Bones.Add(B.Clone);
    for M in Meshes do Result.Meshes.Add(M.Clone);
    Result.Parameters := Copy(Parameters);
    Result.ReferencePixels := ReferencePixels;
    Result.IgnoredWarnings.Assign(IgnoredWarnings);
    Result.LayerComplete := LayerComplete; Result.BoneComplete := BoneComplete;
    Result.MeshComplete := MeshComplete; Result.Usable := Usable;
    Result.SourceMatched := SourceMatched; Result.LastPage := LastPage;
  except Result.Free; raise; end;
end;

function TRigmDocument.Part(const Id: string): TRigmPart;
begin
  if not Parts.TryGetValue(Id, Result) then raise ERigm.Create('パーツが見つかりません: ' + Id);
end;

function TRigmDocument.IsReferencePart(const Id: string): Boolean;
var P: TRigmPart;
begin P := Part(Id); Result := P.ReferenceOnly or (P.Role = 'reference'); end;

function TRigmDocument.Bone(const Id: string): TRigmBone;
var B: TRigmBone;
begin Result := nil; for B in Bones do if B.Id = Id then Exit(B); end;

function TRigmDocument.Mesh(const Id: string): TRigmMesh;
var M: TRigmMesh;
begin Result := nil; for M in Meshes do if M.Id = Id then Exit(M); end;

function TRigmDocument.MeshForPart(const Id: string): TRigmMesh;
var M: TRigmMesh;
begin Result := nil; for M in Meshes do if M.PartId = Id then Exit(M); end;

function TRigmDocument.LayerList(const Id: string): TList<TArtLayer>;
var L: TArtLayer;
begin
  if FArt.Roots.Contains(FArt.FindLayer(Id)) then Exit(FArt.Roots);
  for L in Layers do if L.Children.Contains(FArt.FindLayer(Id)) then Exit(L.Children);
  raise ERigm.Create('パーツの親が見つかりません。');
end;

function TRigmDocument.ParentId(const Id: string): string;
var L: TArtLayer;
begin
  Result := ''; for L in Layers do if L.Children.Contains(FArt.FindLayer(Id)) then Exit(L.Id);
end;

function TRigmDocument.CanOpen(Page: TRigmPage): Boolean;
begin
  case Page of
    rpLayer: Result := True;
    rpBone: Result := LayerComplete;
    rpMesh: Result := LayerComplete and BoneComplete;
    rpPreview: Result := LayerComplete and BoneComplete and MeshComplete;
  else Result := False; end;
end;

procedure TRigmDocument.Changed(Page: TRigmPage);
begin
  FArt.Changed; Usable := False;
  if Page = rpLayer then begin LayerComplete := False; SourceMatched := False; end;
  if Page <= rpBone then BoneComplete := False;
  if Page <= rpMesh then MeshComplete := False;
  if not CanOpen(LastPage) then LastPage := Page;
end;

procedure TRigmDocument.ValidateStructure;
var Seen: TDictionary<string, Boolean>; PixelTotal: Int64; P: TRigmPart;
    B: TRigmBone; M: TRigmMesh; V: TRigmVertex; W: TRigmWeight; Param: TRigmParameter;
  procedure Unique(const Id: string);
  begin
    if (Id = '') or (Length(Id) > 128) or Seen.ContainsKey(Id) then
      raise ERigm.Create('空・重複した固有IDがあります。');
    Seen.Add(Id, True);
  end;
  procedure Number(Value: Double);
  begin
    if not Finite(Value) or (Abs(Value) > 1000000) then raise ERigm.Create('数値が範囲外です。');
  end;
  procedure Visit(List: TList<TArtLayer>; Depth: Integer);
  var L: TArtLayer;
  begin
    if Depth > 64 then raise ERigm.Create('階層が深すぎます。');
    for L in List do begin
      Unique(L.Id); P := Part(L.Id);
      if P.Id <> L.Id then raise ERigm.Create('パーツIDの不一致です。');
      Number(P.X); Number(P.Y); Number(P.Rotation); Number(P.ScaleX); Number(P.ScaleY);
      if (P.ScaleX <= 0) or (P.ScaleY <= 0) or (P.ScaleX > 100) or (P.ScaleY > 100) then
        raise ERigm.Create('拡大率は0より大きく100以下にしてください。');
      if L.Kind = alkImage then begin
        if L.Children.Count <> 0 then raise ERigm.Create('画像パーツに子があります。');
        if (L.Bounds.Width < 1) or (L.Bounds.Height < 1) or
          (Length(L.Pixels) <> PixelByteCount(L.Bounds.Width, L.Bounds.Height, 4)) then
          raise ERigm.Create('パーツ画像の寸法・画素数が一致しません。');
        Inc(PixelTotal, Length(L.Pixels));
      end else if L.Kind <> alkGroup then raise ERigm.Create('未対応のパーツ種別です。');
      if L.HasMask then begin
        if Length(L.MaskPixels) <> PixelByteCount(L.MaskBounds.Width, L.MaskBounds.Height, 1) then
          raise ERigm.Create('マスクの画素数が一致しません。');
        Inc(PixelTotal, Length(L.MaskPixels));
      end;
      Visit(L.Children, Depth + 1);
      if (Seen.Count > 2000) or (PixelTotal > ART_MAX_BYTES) then raise ERigm.Create('文書サイズ上限です。');
    end;
  end;
begin
  if (FArt.Width < 1) or (FArt.Height < 1) or (FArt.Width > 30000) or (FArt.Height > 30000) then raise ERigm.Create('キャンバス寸法が不正です。');
  PixelByteCount(FArt.Width, FArt.Height, 4);
  Seen := TDictionary<string, Boolean>.Create;
  try
    PixelTotal := Length(ReferencePixels); Visit(FArt.Roots, 0);
    if Parts.Count <> Seen.Count then raise ERigm.Create('パーツ属性の数が一致しません。');
    if (Length(ReferencePixels) <> 0) and
      (Length(ReferencePixels) <> PixelByteCount(FArt.Width, FArt.Height, 4)) then
      raise ERigm.Create('比較用画像の寸法が一致しません。');
    if (Bones.Count > 512) or (Meshes.Count > 2000) then raise ERigm.Create('ボーン・メッシュ数の上限です。');
    for B in Bones do begin
      Unique(B.Id); Number(B.X); Number(B.Y); Number(B.InitialX); Number(B.InitialY);
      Number(B.MinAngle); Number(B.MaxAngle);
      if B.MinAngle > B.MaxAngle then raise ERigm.Create('ボーン角度の範囲が逆です。');
    end;
    for M in Meshes do begin
      Unique(M.Id); Number(M.Strength);
      if (M.Strength < 0) or (M.Strength > 1) then raise ERigm.Create('変形強度は0～1です。');
      if (Length(M.Vertices) > 1024) or (Length(M.Triangles) > 2048) then raise ERigm.Create('メッシュ頂点・面数の上限です。');
      for V in M.Vertices do begin
        Number(V.X); Number(V.Y); Number(V.U); Number(V.V);
        if Length(V.Weights) > 8 then raise ERigm.Create('頂点のボーン数の上限です。');
        for W in V.Weights do Number(W.Value);
      end;
    end;
    Seen.Clear;
    for Param in Parameters do begin
      Unique(Param.Id); Number(Param.Minimum); Number(Param.Maximum); Number(Param.Initial);
      if (Param.Minimum >= Param.Maximum) or (Param.Initial < Param.Minimum) or (Param.Initial > Param.Maximum) then
        raise ERigm.Create('パラメータの範囲が不正です。');
    end;
    if (Length(Parameters) > 32) then raise ERigm.Create('パラメータ数の上限です。');
  finally Seen.Free; end;
end;

function TRigmDocument.AddBone(const ParentId, AName: string): TRigmBone;
var Parent: TRigmBone;
begin
  Parent := Bone(ParentId);
  if (ParentId <> '') and (Parent = nil) then raise ERigm.Create('親ボーンがありません。');
  Result := TRigmBone.Create; Result.Name := AName; Result.ParentId := ParentId;
  if Parent <> nil then begin Result.X := Parent.X; Result.Y := Parent.Y - FArt.Height * 0.1; end;
  Result.InitialX := Result.X; Result.InitialY := Result.Y; Bones.Add(Result);
end;

procedure TRigmDocument.SeedBones;
var Root, Upper, Neck, Head, Left, Right: TRigmBone; Center: TPointF; Radius: Double;
    BodyTop, BodyHeight: Double;
begin
  if Bones.Count <> 0 then Exit;
  Root := AddBone('', '腰（下半身）'); Root.Y := FArt.Height * 0.1;
  BodyTop := -FArt.Height * 0.12;
  for var Layer in Layers do if (Layer.Kind = alkImage) and Layer.Visible and
    (Part(Layer.Id).Role = 'body') then begin
    var Ancestor := ParentId(Layer.Id); var Simple := True;
    while Ancestor <> '' do begin
      var Group := Part(Ancestor);
      Simple := Simple and (Group.X = 0) and (Group.Y = 0) and (Group.Rotation = 0) and (Group.ScaleX = 1) and (Group.ScaleY = 1);
      Ancestor := ParentId(Ancestor);
    end;
    if not Simple then Continue;
    BodyHeight := Layer.Bounds.Height * Abs(Part(Layer.Id).ScaleY);
    BodyTop := Part(Layer.Id).Y - BodyHeight * 0.5;
    if BodyHeight >= FArt.Height * 0.5 then Root.Y := BodyTop + BodyHeight * 0.25
    else Root.Y := BodyTop + BodyHeight * 0.8;
    Break;
  end;
  Root.InitialY := Root.Y;
  Upper := AddBone(Root.Id, '上半身'); Upper.Y := (Root.Y + BodyTop) * 0.5; Upper.InitialY := Upper.Y;
  WaistBoneId := Root.Id; UpperBodyBoneId := Upper.Id;
  Neck := AddBone(Upper.Id, '首'); Neck.Y := BodyTop; Neck.InitialY := Neck.Y;
  Head := AddBone(Neck.Id, '頭'); Head.Y := -FArt.Height * 0.28; Head.InitialY := Head.Y;
  if FaceGuide(Center, Radius) then begin Head.X := Center.X; Head.Y := Center.Y; Head.InitialX := Head.X; Head.InitialY := Head.Y; end;
  Left := AddBone(Neck.Id, '左肩'); Left.X := -FArt.Width * 0.15; Left.Y := Neck.Y;
  Left.InitialX := Left.X; Left.InitialY := Left.Y;
  Right := AddBone(Neck.Id, '右肩'); Right.X := -Left.X; Right.Y := Neck.Y;
  Right.InitialX := Right.X; Right.InitialY := Right.Y;
  Left.PairId := Right.Id; Right.PairId := Left.Id;
  for var I := 0 to High(Parameters) do begin
    if Parameters[I].Id = 'headAngle' then Parameters[I].BoneId := Head.Id;
    if Parameters[I].Id = 'bodyAngle' then Parameters[I].BoneId := Upper.Id;
  end;
end;

function TRigmDocument.HasUpperBodyRig: Boolean;
begin
  Result := (WaistBoneId <> '') and (UpperBodyBoneId <> '') and
    (WaistBoneId <> UpperBodyBoneId) and (Bone(WaistBoneId) <> nil) and (Bone(UpperBodyBoneId) <> nil);
end;

function TRigmDocument.UpperBodyWeight(Y: Double): Double;
var T, Span: Double;
begin
  Result := 0; if not HasUpperBodyRig then Exit;
  Span := Max(1, Bone(WaistBoneId).Y - Bone(UpperBodyBoneId).Y);
  T := EnsureRange((Bone(WaistBoneId).Y - Y) / Span, 0.0, 1.0);
  Result := T * T * (3 - 2 * T);
end;

function TRigmDocument.UpgradeUpperBodyRig: Boolean;
var Root, Head, Branch, Upper: TRigmBone; BodyIndex: Integer;
begin
  Result := False; if HasUpperBodyRig or (WaistBoneId <> '') or (UpperBodyBoneId <> '') or (Bones.Count <> 5) then Exit;
  Root := nil; Head := nil; BodyIndex := -1;
  for var I := 0 to High(Parameters) do begin
    if Parameters[I].Id = 'bodyAngle' then begin BodyIndex := I; Root := Bone(Parameters[I].BoneId); end;
    if Parameters[I].Id = 'headAngle' then Head := Bone(Parameters[I].BoneId);
  end;
  if (Root = nil) or (Head = nil) or (Root = Head) or (Root.ParentId <> '') or not Root.Visible or not Head.Visible then Exit;
  for var B in Bones do if B.Locked then Exit;
  for var M in Meshes do if M.Locked or ((Part(M.PartId).Role = 'body') and not M.Automatic) then Exit;
  for var P in Parts.Values do if P.Locked then Exit;
  for var Param in Parameters do if (Param.BoneId = Root.Id) and (Param.Id <> 'bodyAngle') then Exit;
  Branch := Head;
  for var Depth := 0 to Bones.Count do begin
    if Branch.ParentId = Root.Id then Break;
    Branch := Bone(Branch.ParentId); if Branch = nil then Exit;
  end;
  if (Branch = nil) or (Branch.ParentId <> Root.Id) or (Branch.Y >= Root.Y) then Exit;
  if (Head.ParentId <> Branch.Id) or (Root.PairId <> '') or (Head.PairId <> '') or (Branch.PairId <> '') then Exit;
  for var B in Bones do if (B <> Root) and (B <> Head) and (B <> Branch) then begin
    var Pair := Bone(B.PairId);
    if (B.ParentId <> Branch.Id) or (Pair = nil) or (Pair.PairId <> B.Id) or (Pair.ParentId <> Branch.Id) then Exit;
  end;
  for var M in Meshes do if Part(M.PartId).Role = 'body' then
    for var V in M.Vertices do if (Length(V.Weights) <> 1) or (V.Weights[0].BoneId <> Root.Id) or
      not SameValue(V.Weights[0].Value,1,0.0001) then Exit;
  // Keep every existing ID, position, part and vertex/weight; insert one ancestor.
  Upper := AddBone(Root.Id, '上半身'); Upper.X := Root.X;
  Upper.Y := (Root.Y + Branch.Y) * 0.5; Upper.InitialX := Upper.X; Upper.InitialY := Upper.Y;
  Branch.ParentId := Upper.Id; WaistBoneId := Root.Id; UpperBodyBoneId := Upper.Id;
  Parameters[BodyIndex].BoneId := Upper.Id; Parameters[BodyIndex].Role := 'upperBody';
  if (Parameters[BodyIndex].Name = '体の角度') or (Parameters[BodyIndex].Name = '体角度') then Parameters[BodyIndex].Name := '上半身角度';
  Result := True;
end;

function TRigmDocument.FaceGuide(out Center: TPointF; out Radius: Double): Boolean;
var P, Group: TRigmPart; Parent: string; Point, Corner: TPointF;
    L, T, R, B, S, C, X, Y: Double; Have: Boolean;
begin
  Have := False; Center := TPointF.Zero; Radius := 0; L := 1E30; T := L; R := -L; B := R;
  for var Layer in Layers do if (Layer.Kind = alkImage) and Layer.Visible and (Part(Layer.Id).Role = 'face') then begin
    P := Part(Layer.Id); SinCos(DegToRad(P.Rotation), S, C);
    for var I := 0 to 3 do begin
      X := ((I mod 2) - 0.5) * Layer.Bounds.Width * P.ScaleX;
      Y := ((I div 2) - 0.5) * Layer.Bounds.Height * P.ScaleY;
      Point := TPointF.Create(P.X + X*C - Y*S, P.Y + X*S + Y*C);
      Parent := ParentId(Layer.Id);
      while Parent <> '' do begin
        Group := Part(Parent); SinCos(DegToRad(Group.Rotation), S, C);
        Corner := Point;
        Point := TPointF.Create(Group.X + Corner.X*Group.ScaleX*C - Corner.Y*Group.ScaleY*S,
          Group.Y + Corner.X*Group.ScaleX*S + Corner.Y*Group.ScaleY*C);
        Parent := ParentId(Parent);
      end;
      L := Min(L, Point.X); T := Min(T, Point.Y); R := Max(R, Point.X); B := Max(B, Point.Y); Have := True;
      SinCos(DegToRad(P.Rotation), S, C);
    end;
  end;
  Result := Have;
  if Have then begin Center := TPointF.Create((L+R)*0.5, (T+B)*0.5); Radius := Max(R-L,B-T)*0.5; end;
end;

procedure TRigmDocument.HideBone(const Id: string; Paired: Boolean);
var B, Target: TRigmBone; Visited: TDictionary<string, Boolean>;
  procedure Hide(const BoneId: string);
  var Child: TRigmBone;
  begin
    if Visited.ContainsKey(BoneId) then Exit;
    Visited.Add(BoneId, True); Target := Bone(BoneId);
    if Target = nil then raise ERigm.Create('ボーンがありません。');
    if Target.Locked then raise ERigm.Create('ボーンはロックされています。');
    Target.Visible := False;
    for Child in Bones do if Child.ParentId = BoneId then Hide(Child.Id);
  end;
begin
  B := Bone(Id); if B = nil then raise ERigm.Create('ボーンがありません。');
  Visited := TDictionary<string, Boolean>.Create;
  try Hide(Id); if Paired and (B.PairId <> '') then Hide(B.PairId); finally Visited.Free; end;
end;

procedure TRigmDocument.RestoreChildren(const Id: string; Paired: Boolean);
var B, Pair: TRigmBone; Found: Boolean;
begin
  if (Id <> '') and (Bone(Id) = nil) then raise ERigm.Create('ボーンがありません。');
  B := Bone(Id);
  if (B <> nil) and not B.Visible then begin
    if B.Locked then raise ERigm.Create('ボーンはロックされています。');
    B.Visible := True;
    if Paired and (B.PairId <> '') then begin Pair := Bone(B.PairId); if (Pair <> nil) and not Pair.Locked then Pair.Visible := True; end;
    Exit;
  end;
  Found := False;
  for B in Bones do if (B.ParentId = Id) and not B.Visible then begin
    if B.Locked then Continue;
    B.Visible := True; Found := True;
    if Paired and (B.PairId <> '') then begin Pair := Bone(B.PairId); if (Pair <> nil) and not Pair.Locked then Pair.Visible := True; end;
  end;
  if not Found then begin
    B := Bone(Id);
    if (B <> nil) and not B.Visible and not B.Locked then B.Visible := True
    else AddBone(Id, '新しいボーン');
  end;
end;

procedure TRigmDocument.MoveBone(const Id: string; X, Y: Double; Paired: Boolean);
var B, Pair: TRigmBone; DX, DY: Double;
begin
  B := Bone(Id); if B = nil then raise ERigm.Create('ボーンがありません。');
  if B.Locked then raise ERigm.Create('ボーンはロックされています。');
  DX := X - B.X; DY := Y - B.Y; B.X := X; B.Y := Y;
  if Paired and (B.PairId <> '') then begin
    Pair := Bone(B.PairId);
    if (Pair <> nil) and not Pair.Locked then begin Pair.X := Pair.X - DX; Pair.Y := Pair.Y + DY; end;
  end;
end;

procedure TRigmDocument.ReparentLayer(const Id, NewParentId: string; Index: Integer);
var L, Parent, Ancestor: TArtLayer; OldList, NewList: TList<TArtLayer>; ParentKey: string;
begin
  L := FArt.FindLayer(Id); if L = nil then raise ERigm.Create('パーツがありません。');
  if Part(Id).Locked then raise ERigm.Create('パーツはロックされています。');
  Parent := FArt.FindLayer(NewParentId); NewList := FArt.Roots;
  if NewParentId <> '' then begin
    if (Parent = nil) or (Parent.Kind <> alkGroup) then raise ERigm.Create('親はグループを選択してください。');
    Ancestor := Parent;
    while Ancestor <> nil do begin
      if Ancestor = L then raise ERigm.Create('循環する親子関係です。');
      ParentKey := ParentId(Ancestor.Id); Ancestor := FArt.FindLayer(ParentKey);
    end;
    NewList := Parent.Children;
  end;
  OldList := LayerList(Id); OldList.Remove(L);
  NewList.Insert(EnsureRange(Index, 0, NewList.Count), L);
end;

procedure TRigmDocument.GenerateMesh(const PartId, BoneId: string; Grid: Integer);
var L: TArtLayer; P: TRigmPart; M: TRigmMesh; X, Y, I, A: Integer; V: TRigmVertex;
    C, S, LX, LY, Factor, WaistV: Double; WaistRow: Integer; BodyWeights: Boolean;
begin
  L := FArt.FindLayer(PartId);
  if (L = nil) or (L.Kind <> alkImage) then raise ERigm.Create('画像パーツを選択してください。');
  P := Part(PartId); if P.Locked then raise ERigm.Create('パーツはロックされています。');
  if IsReferencePart(PartId) then raise ERigm.Create('比較用画像は可動メッシュの対象外です。');
  if (BoneId <> '') and (Bone(BoneId) = nil) then raise ERigm.Create('関連付けるボーンがありません。');
  M := MeshForPart(PartId);
  if (M <> nil) and M.Locked then raise ERigm.Create('メッシュはロックされています。');
  if M = nil then begin M := TRigmMesh.Create; M.PartId := PartId; Meshes.Add(M); end;
  M.Name := L.Name; M.Role := P.Role; M.Automatic := True;
  Grid := EnsureRange(Grid, 2, 16); SetLength(M.Vertices, Grid * Grid);
  SetLength(M.Triangles, (Grid - 1) * (Grid - 1) * 2);
  SinCos(DegToRad(P.Rotation), S, C);
  BodyWeights := HasUpperBodyRig and (P.Role = 'body') and (BoneId = UpperBodyBoneId);
  WaistRow := -1; WaistV := 0;
  if BodyWeights and (Grid >= 3) and (Abs(C * P.ScaleY) > 0.0001) then begin
    WaistV := (Bone(WaistBoneId).Y-P.Y)/(L.Bounds.Height*P.ScaleY*C)+0.5;
    if (WaistV > 0) and (WaistV < 1) then WaistRow := EnsureRange(Round(WaistV*(Grid-1)),1,Grid-2);
  end;
  for Y := 0 to Grid - 1 do for X := 0 to Grid - 1 do begin
    V := Default(TRigmVertex); V.U := X / (Grid - 1); V.V := Y / (Grid - 1);
    if Y = WaistRow then V.V := WaistV;
    LX := (V.U - 0.5) * L.Bounds.Width * P.ScaleX;
    LY := (V.V - 0.5) * L.Bounds.Height * P.ScaleY;
    V.X := P.X + LX * C - LY * S; V.Y := P.Y + LX * S + LY * C;
    if BodyWeights then begin
      Factor := UpperBodyWeight(V.Y);
      if Factor <= 0 then V.Weights := [TRigmWeight.Create(WaistBoneId,1)]
      else if Factor >= 1 then V.Weights := [TRigmWeight.Create(UpperBodyBoneId,1)]
      else V.Weights := [TRigmWeight.Create(UpperBodyBoneId,Factor),TRigmWeight.Create(WaistBoneId,1-Factor)];
    end else if BoneId <> '' then V.Weights := [TRigmWeight.Create(BoneId, 1)];
    M.Vertices[Y * Grid + X] := V;
  end;
  I := 0;
  for Y := 0 to Grid - 2 do for X := 0 to Grid - 2 do begin
    A := Y * Grid + X;
    M.Triangles[I] := TRigmTriangle.Create(A, A + 1, A + Grid); Inc(I);
    M.Triangles[I] := TRigmTriangle.Create(A + 1, A + Grid + 1, A + Grid); Inc(I);
  end;
end;

constructor TRigmPose.Create;
begin
  PartVisibility := TDictionary<string,Boolean>.Create;
  PartFeatureAssets := TDictionary<string,Boolean>.Create;
  inherited; Values := TDictionary<string, Double>.Create;
  BoneAngles := TDictionary<string, Double>.Create;
  BoneOffsets := TDictionary<string, TPointF>.Create;
end;

destructor TRigmPose.Destroy;
begin PartFeatureAssets.Free; PartVisibility.Free; BoneOffsets.Free; BoneAngles.Free; Values.Free; inherited; end;

procedure TRigmPose.Reset;
begin PartFeatureAssets.Clear; PartVisibility.Clear; Values.Clear; BoneAngles.Clear; BoneOffsets.Clear; end;

function TRigmPose.Value(const Id: string; Default: Double): Double;
begin if not Values.TryGetValue(Id, Result) then Result := Default; end;

end.
