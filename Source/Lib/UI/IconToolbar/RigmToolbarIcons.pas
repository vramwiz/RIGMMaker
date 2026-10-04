unit RigmToolbarIcons;

interface

uses Vcl.Graphics, Vcl.ImgList;

type
  TRigmToolbarIcon = (riLayer, riBone, riMesh, riPreview, riComplete, riSave,
    riSaveAs, riUndo, riRedo, riReset, riEditPreview, riDirect, riBoneOverlay,
    riMeshOverlay, riPng, riPsd, riGroup, riReference, riClassify, riUp, riDown,
    riDelete, riAddBone, riHideBone, riResetBone, riGenerate, riAddVertex,
    riDeleteVertex, riNew, riOpen, riSample, riRefresh);

procedure BuildRigmToolbarIcons(Images: TCustomImageList; Size: Integer; Color: TColor);

implementation

uses System.Types, System.Math, Winapi.Windows, SerifToolbarIcons;

procedure DrawIcon(C: TCanvas; Kind: TRigmToolbarIcon; Size: Integer; Color: TColor);
  function S(V: Integer): Integer;
  begin Result := MulDiv(V, Size, 24); end;
  procedure Line(X1, Y1, X2, Y2: Integer);
  begin C.MoveTo(S(X1), S(Y1)); C.LineTo(S(X2), S(Y2)); end;
  procedure Box(L, T, R, B: Integer);
  begin C.Rectangle(S(L), S(T), S(R), S(B)); end;
  procedure Plus;
  begin Line(18, 14, 18, 22); Line(14, 18, 22, 18); end;
  procedure Bone;
  begin
    C.Ellipse(S(3), S(3), S(10), S(10)); Line(8, 8, 16, 16);
    C.Ellipse(S(14), S(14), S(21), S(21));
  end;
  procedure Mesh;
  begin
    C.Polygon([Point(S(3), S(4)), Point(S(21), S(6)), Point(S(19), S(21)), Point(S(4), S(19))]);
    Line(3, 4, 19, 21); Line(21, 6, 4, 19); Line(12, 5, 11, 20);
  end;
  procedure Refresh;
  begin
    C.Arc(S(3), S(3), S(21), S(21), S(20), S(6), S(19), S(18));
    Line(20, 3, 20, 9); Line(20, 9, 14, 9);
  end;
begin
  C.Pen.Color := Color; C.Pen.Style := psSolid; C.Pen.Width := Max(1, S(2));
  C.Brush.Color := Color; C.Brush.Style := bsClear;
  case Kind of
    riPreview: DrawSerifToolbarIcon(C, stiWatch, Size, Color);
    riEditPreview: DrawSerifToolbarIcon(C, stiInput, Size, Color);
    riOpen: DrawSerifToolbarIcon(C, stiProject, Size, Color);
    riSample: DrawSerifToolbarIcon(C, stiChara, Size, Color);
    riReference: DrawSerifToolbarIcon(C, stiBoard, Size, Color);
    riLayer: begin Box(3, 3, 17, 13); Box(6, 7, 20, 17); Line(8, 21, 22, 21); end;
    riBone, riBoneOverlay: Bone;
    riMesh, riMeshOverlay: Mesh;
    riComplete: begin Line(2, 12, 7, 17); Line(7, 17, 13, 7); Line(14, 12, 22, 12); Line(17, 7, 22, 12); Line(22, 12, 17, 17); end;
    riSave, riSaveAs: begin
      Box(3, 3, 21, 21); Box(7, 3, 17, 9); Box(7, 14, 17, 21);
      if Kind = riSaveAs then begin C.Brush.Style := bsSolid; C.Rectangle(S(13), S(13), S(24), S(24)); C.Pen.Color := $00FF00FF; Plus; end;
    end;
    riUndo: begin C.Arc(S(4), S(5), S(22), S(21), S(6), S(8), S(18), S(19)); Line(3, 3, 3, 10); Line(3, 10, 10, 10); end;
    riRedo: begin C.Arc(S(2), S(5), S(20), S(21), S(6), S(19), S(18), S(8)); Line(21, 3, 21, 10); Line(21, 10, 14, 10); end;
    riReset, riResetBone: begin Refresh; C.Ellipse(S(9), S(9), S(15), S(15)); end;
    riDirect: begin C.Polygon([Point(S(5), S(2)), Point(S(5), S(20)), Point(S(10), S(15)), Point(S(14), S(22)), Point(S(17), S(20)), Point(S(13), S(13)), Point(S(21), S(13))]); end;
    riPng, riPsd: begin
      Box(2, 3, 20, 20); C.Ellipse(S(5), S(6), S(10), S(11));
      C.Polyline([Point(S(3), S(18)), Point(S(9), S(12)), Point(S(14), S(17)), Point(S(18), S(12))]);
      if Kind = riPng then Plus else begin Line(6, 23, 23, 23); Line(23, 7, 23, 23); end;
    end;
    riGroup: begin DrawSerifToolbarIcon(C, stiProject, Size, Color); C.Brush.Style := bsClear; Plus; end;
    riClassify: begin Refresh; Line(7, 12, 10, 15); Line(10, 15, 16, 9); end;
    riUp: begin Line(12, 3, 12, 21); Line(4, 11, 12, 3); Line(12, 3, 20, 11); end;
    riDown: begin Line(12, 3, 12, 21); Line(4, 13, 12, 21); Line(12, 21, 20, 13); end;
    riDelete: begin Box(6, 7, 18, 21); Line(3, 5, 21, 5); Line(9, 2, 15, 2); Line(10, 10, 10, 18); Line(14, 10, 14, 18); end;
    riAddBone: begin Bone; Plus; end;
    riHideBone: begin Bone; Line(2, 22, 22, 2); end;
    riGenerate: begin Mesh; Plus; end;
    riAddVertex: begin C.Polygon([Point(S(3), S(4)), Point(S(20), S(4)), Point(S(6), S(21))]); Line(3, 4, 10, 10); Line(20, 4, 10, 10); Line(6, 21, 10, 10); Plus; end;
    riDeleteVertex: begin C.Polygon([Point(S(3), S(4)), Point(S(20), S(4)), Point(S(6), S(21))]); Line(14, 15, 22, 23); Line(14, 23, 22, 15); end;
    riNew: begin Box(3, 2, 17, 21); Plus; end;
    riRefresh: Refresh;
  end;
end;

procedure BuildRigmToolbarIcons(Images: TCustomImageList; Size: Integer; Color: TColor);
var B: Vcl.Graphics.TBitmap; Kind: TRigmToolbarIcon;
begin
  if (Images = nil) or (Size < 1) then Exit;
  Images.Clear; Images.Width := Size; Images.Height := Size;
  Images.Masked := True; Images.BkColor := clNone;
  B := Vcl.Graphics.TBitmap.Create;
  try
    B.PixelFormat := pf24bit; B.SetSize(Size, Size);
    for Kind := Low(TRigmToolbarIcon) to High(TRigmToolbarIcon) do begin
      B.Canvas.Brush.Style := bsSolid; B.Canvas.Brush.Color := $00FF00FF;
      B.Canvas.FillRect(Rect(0, 0, Size, Size));
      DrawIcon(B.Canvas, Kind, Size, Color); Images.AddMasked(B, $00FF00FF);
    end;
  finally B.Free; end;
end;

end.
