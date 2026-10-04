unit RigmSample;

interface
uses RigmModel;
procedure PopulateRigmSample(Document: TRigmDocument);

implementation
uses System.SysUtils, System.Math, ArtDocument, RigmRenderer;

procedure PopulateRigmSample(Document: TRigmDocument);
var W, H: Integer;
  procedure Shape(const Name, Role: string; X, Y, Width, Height: Integer; R, G, B: Byte; Ellipse: Boolean);
  var Layer: TArtLayer; I, J, Offset: Integer; NX, NY: Double;
  begin
    Layer := Document.Art.AddLayer(alkImage, Name, TArtBounds.Create(X, Y, X + Width, Y + Height));
    SetLength(Layer.Pixels, Width * Height * 4);
    for J := 0 to Height - 1 do for I := 0 to Width - 1 do begin
      NX := (I + 0.5 - Width / 2) / (Width / 2); NY := (J + 0.5 - Height / 2) / (Height / 2);
      if Ellipse and (Sqr(NX) + Sqr(NY) > 1) then Continue;
      Offset := (J * Width + I) * 4; Layer.Pixels[Offset] := R; Layer.Pixels[Offset + 1] := G;
      Layer.Pixels[Offset + 2] := B; Layer.Pixels[Offset + 3] := 255;
    end;
    Document.SyncParts; Document.Part(Layer.Id).Role := Role;
  end;
begin
  Document.Art.Width := 256; Document.Art.Height := 320;
  Document.Name := '編集テスト用サンプル（未保存）';
  Shape('左目', 'eye', 86, 100, 18, 24, 36, 49, 64, True);
  Shape('右目', 'eye', 151, 100, 18, 24, 36, 49, 64, True);
  Shape('左眉', 'brow', 81, 82, 28, 5, 72, 52, 44, False);
  Shape('右眉', 'brow', 146, 82, 28, 5, 72, 52, 44, False);
  Shape('口', 'mouth', 111, 151, 34, 8, 155, 66, 82, True);
  Shape('髪', 'hair', 49, 24, 158, 61, 91, 64, 51, True);
  Shape('顔', 'face', 53, 35, 150, 170, 245, 208, 170, True);
  Shape('体', 'body', 38, 188, 180, 125, 71, 135, 169, True);
  Document.SeedBones;
  for var Layer in Document.Layers do begin
    var Part := Document.Part(Layer.Id);
    if Part.Role = 'body' then Part.BoneId := Document.Parameters[5].BoneId
    else Part.BoneId := Document.Parameters[2].BoneId;
    Document.GenerateMesh(Layer.Id, Part.BoneId, 3);
  end;
  Document.ReferencePixels := RenderRigm(Document, nil, 512, W, H);
  Document.SourceMatched := True; Document.LayerComplete := True;
  Document.BoneComplete := True; Document.MeshComplete := True;
  Document.Usable := False; Document.LastPage := rpLayer; Document.ValidateStructure;
end;

end.
