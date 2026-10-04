// キャラクタープレビューのボーン・メッシュ・選択オーバーレイを描く。
// フォームや入力処理を参照せず、渡された表示状態と描画先だけを使用する。
unit RigmCharacterPreviewRendering;
interface
uses System.Types, Vcl.Graphics, RigmModel;
type
  TRigmCharacterPreviewState = record
    Document     : TRigmDocument; // 借用する文書。描画中に置換しないこと。
    Pose         : TRigmPose;     // 未保存プレビューの姿勢。通常編集時には適用しない。
    ImageRect    : TRect;         // 描画先内でのキャラクター画像の矩形。
    PPI          : Integer;       // 枠・頂点・ラベルの寸法に使う画面DPI。
    SelectedId   : string;        // 強調するパーツ・ボーン・メッシュの安定ID。
    PreviewMode  : Boolean;       // パラメータ姿勢をオーバーレイへ反映するか。
    Direct       : Boolean;       // 直接操作プレビューでは編集オーバーレイを隠す。
    ShowReference: Boolean;       // 比較画像を表示中は編集オーバーレイを隠す。
    ShowMeshes   : Boolean;       // メッシュ面と選択頂点を表示するか。
    ShowBones    : Boolean;       // ボーン階層と顔位置ガイドを表示するか。
    Dragging     : Boolean;       // 未確定のドラッグ位置を表示するか。
    Vertex       : Integer;       // 選択頂点。未選択は-1。
    DragId       : string;        // 未確定ドラッグの対象ID。
    DragPoint    : TPointF;       // キャンバス中央原点の未確定座標。
  end;
// 背景・Bitmap・オーバーレイをCanvasへ合成する。文書・姿勢・入力Bitmapは変更しない。
procedure PaintCharacterPreview(Canvas: TCanvas; const Bounds: TRect; Bitmap: Vcl.Graphics.TBitmap;
  const State: TRigmCharacterPreviewState);
implementation
uses Winapi.Windows, System.Math, System.StrUtils, System.UITypes, ArtDocument, RigmRenderer;
function PreviewPixels(const State: TRigmCharacterPreviewState; Value: Integer): Integer;
begin Result := MulDiv(Value,State.PPI,96); end;
function PreviewScreen(const State: TRigmCharacterPreviewState; X,Y: Double): TPoint;
begin
  Result := Point(State.ImageRect.Left+Round((X+State.Document.Art.Width/2)*State.ImageRect.Width/State.Document.Art.Width),
    State.ImageRect.Top+Round((Y+State.Document.Art.Height/2)*State.ImageRect.Height/State.Document.Art.Height));
end;
function VisiblePart(Document: TRigmDocument; const Id: string): Boolean;
  var Layer: TArtLayer; ParentId: string;
  begin
    Result := False; Layer := Document.Art.FindLayer(Id);
    if (Layer = nil) or not Layer.Visible then Exit;
    ParentId := Document.ParentId(Id);
    while ParentId <> '' do begin
      Layer := Document.Art.FindLayer(ParentId); if (Layer = nil) or not Layer.Visible then Exit;
      ParentId := Document.ParentId(ParentId);
    end;
    Result := True;
  end;
function MeshColor(const Role: string): TColor;
  begin
    if Role = 'eye' then Result := $00DDBB55
    else if Role = 'brow' then Result := $00DD88EE
    else if Role = 'mouth' then Result := $0088DD55
    else if Role = 'hair' then Result := $0055AADD
    else if Role = 'body' then Result := $00DDDD55
    else if Role = 'fixed' then Result := clGray
    else if Role = 'correction' then Result := $005599EE
    else if Role = 'expression' then Result := $00AA77DD
    else Result := $00DD9955;
  end;
procedure PaintCharacterPreview(Canvas: TCanvas; const Bounds: TRect; Bitmap: Vcl.Graphics.TBitmap;
  const State: TRigmCharacterPreviewState);
var R: TRect; A,B,C: TPoint; P,Center: TPointF; Parent,Head: TRigmBone;
  Pose: TRigmPose; Context: TRigmRenderContext; Radius: Double; CircleRadius: Integer;
  MeshPoints: TArray<TPoint>;
begin
  Context := nil;
  // Composite the background, image and overlays before presenting one frame.
  try
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $002A2522; Canvas.FillRect(Bounds);
  R := State.ImageRect; if not R.IsEmpty then Canvas.StretchDraw(R, Bitmap);
  if State.ShowReference then Exit;
  if (State.Document.LastPage = rpPreview) and State.Direct then Exit;
  Pose := nil; if State.PreviewMode or (State.Document.LastPage = rpPreview) then Pose := State.Pose;
  Context := TRigmRenderContext.Create(State.Document,Pose);
  if State.ShowMeshes and (State.Document.LastPage in [rpMesh, rpPreview, rpBone]) then begin
    for var Mesh in State.Document.Meshes do begin
      if not Mesh.Visible then Continue;
      if (Mesh.Id <> State.SelectedId) and not VisiblePart(State.Document,Mesh.PartId) then Continue;
      SetLength(MeshPoints,Length(Mesh.Vertices));
      for var I := 0 to High(Mesh.Vertices) do begin P := Context.VertexPosition(Mesh,I); MeshPoints[I] := PreviewScreen(State,P.X,P.Y); end;
      Canvas.Pen.Color := MeshColor(Mesh.Role); Canvas.Pen.Width := PreviewPixels(State,1);
      for var Face in Mesh.Triangles do begin
        if (Face.A < 0) or (Face.B < 0) or (Face.C < 0) or (Face.A >= Length(Mesh.Vertices)) or (Face.B >= Length(Mesh.Vertices)) or (Face.C >= Length(Mesh.Vertices)) then Continue;
        A := MeshPoints[Face.A]; B := MeshPoints[Face.B]; C := MeshPoints[Face.C];
        Canvas.Polyline([A, B, C, A]);
      end;
      if Mesh.Id = State.SelectedId then for var I := 0 to High(Mesh.Vertices) do begin
        A := MeshPoints[I]; if State.Dragging and (I = State.Vertex) then A := PreviewScreen(State,State.DragPoint.X,State.DragPoint.Y);
        Canvas.Brush.Color := IfThen(I = State.Vertex, clWhite, Canvas.Pen.Color);
        Canvas.Ellipse(A.X - PreviewPixels(State,4), A.Y - PreviewPixels(State,4), A.X + PreviewPixels(State,5), A.Y + PreviewPixels(State,5));
      end;
    end;
  end;
  if State.ShowBones and (State.Document.LastPage in [rpBone, rpPreview]) then begin
    if (State.Document.LastPage = rpBone) and not State.PreviewMode then begin
      Head := nil;
      for var Param in State.Document.Parameters do if Param.Id = 'headAngle' then Head := State.Document.Bone(Param.BoneId);
      if (Head <> nil) and Head.Visible then begin
        if not State.Document.FaceGuide(Center,Radius) then begin Center := TPointF.Create(Head.X,Head.Y); Radius := Min(State.Document.Art.Width,State.Document.Art.Height)*0.12; end;
        if State.Dragging and (State.DragId = Head.Id) then Center := Center + State.DragPoint - TPointF.Create(Head.X,Head.Y);
        A := PreviewScreen(State,Center.X,Center.Y); B := PreviewScreen(State,Center.X+Radius,Center.Y);
        CircleRadius := Max(PreviewPixels(State,8),Abs(B.X-A.X)); Canvas.Pen.Color := $00DCCB8A; Canvas.Pen.Width := PreviewPixels(State,1);
        Canvas.Pen.Style := psDot; Canvas.Brush.Style := bsClear;
        Canvas.Ellipse(A.X-CircleRadius,A.Y-CircleRadius,A.X+CircleRadius,A.Y+CircleRadius);
        P := TPointF.Create(Head.X,Head.Y); if State.Dragging and (State.DragId = Head.Id) then P := State.DragPoint;
        B := PreviewScreen(State,P.X,P.Y); Canvas.MoveTo(B.X,B.Y); Canvas.LineTo(A.X,A.Y);
        Canvas.Font.Color := Canvas.Pen.Color; Canvas.TextOut(A.X-CircleRadius,A.Y-CircleRadius-PreviewPixels(State,18),'顔の位置');
        Canvas.Pen.Style := psSolid; Canvas.Brush.Style := bsSolid;
      end;
    end;
    for var Bone in State.Document.Bones do begin
      if not Bone.Visible then Continue;
      P := Context.BoneMatrix(Bone.Id).Apply(Bone.X,Bone.Y);
      if State.Dragging and (Bone.Id = State.SelectedId) then P := State.DragPoint;
      A := PreviewScreen(State,P.X, P.Y); Parent := State.Document.Bone(Bone.ParentId);
      Canvas.Pen.Color := IfThen(Bone.Id = State.SelectedId, clWhite, $00E8AA65); Canvas.Pen.Width := PreviewPixels(State,2);
      if (Parent <> nil) and Parent.Visible then begin
        P := Context.BoneMatrix(Parent.Id).Apply(Parent.X,Parent.Y);
        if State.Dragging and (Parent.Id = State.DragId) then P := State.DragPoint;
        B := PreviewScreen(State,P.X, P.Y);
        Canvas.Brush.Style := bsClear; Canvas.Polygon([B, Point((A.X + B.X) div 2 - 5, (A.Y + B.Y) div 2), A, Point((A.X + B.X) div 2 + 5, (A.Y + B.Y) div 2)]);
        Canvas.Brush.Style := bsSolid;
      end;
      Canvas.Brush.Color := Canvas.Pen.Color; Canvas.Ellipse(A.X - PreviewPixels(State,5), A.Y - PreviewPixels(State,5), A.X + PreviewPixels(State,6), A.Y + PreviewPixels(State,6));
      if State.Document.LastPage = rpBone then begin
        Canvas.Brush.Style := bsClear; Canvas.Font.Color := Canvas.Pen.Color;
        var Caption := Bone.Name; if Bone.Id = State.Document.WaistBoneId then Caption := Caption + '（腰支点）';
        Canvas.TextOut(A.X+PreviewPixels(State,9),A.Y-PreviewPixels(State,9),Caption); Canvas.Brush.Style := bsSolid;
      end;
    end;
  end;
  finally Context.Free; end;
end;
end.
