program PsdPrepareAssets;
{$APPTYPE CONSOLE}

// 生成後PNGの透明余白と共通倍率を測定して合わせる。意味的分離/肌補完は行わない。
uses System.SysUtils, System.IOUtils, System.JSON, System.Math, System.Hash,
  ArtDocument, ArtPng, ArtRasterTransform, PsdJson;

begin
  try
    if ParamCount <> 2 then raise Exception.Create('Usage: PsdPrepareAssets <input-directory> <reference-work-directory>');
    var Input := ExpandFileName(ParamStr(1)); var Reference := ExpandFileName(ParamStr(2));
    var Eye := ReadPng(TPath.Combine(Reference, 'images\eyes\eyes-original.png'));
    var Body := ReadPng(TPath.Combine(Reference, 'reference\original.png'));
    var EyeBounds := AlphaBounds(Eye.Pixels, Eye.Width, Eye.Height);
    var BodyBounds := AlphaBounds(Body.Pixels, Body.Width, Body.Height);
    var Records := TJSONArray.Create;
    try
      for var Key in ['eyes-left', 'eyes-left-up', 'eyes-up', 'eyes-right-up', 'eyes-right', 'pose-side', 'pose-back'] do begin
        var Path := TPath.Combine(Input, Key + '-source.png'); if not FileExists(Path) then Continue;
        var PNG := ReadPng(Path); var Bounds := AlphaBounds(PNG.Pixels, PNG.Width, PNG.Height);
        if (Bounds.Width < 1) or (Bounds.Height < 1) then raise Exception.Create('Empty generated PNG');
        var AlphaZero: Int64 := 0; var AlphaFull: Int64 := 0;
        for var Index := 0 to PNG.Width * PNG.Height - 1 do begin
          if PNG.Pixels[Index * 4 + 3] = 0 then Inc(AlphaZero);
          if PNG.Pixels[Index * 4 + 3] = 255 then Inc(AlphaFull);
        end;
        if (AlphaZero = 0) or (AlphaFull = 0) then raise Exception.Create('Generated transparency/opaque content missing');
        var Scale: Double; var X, Y: Integer;
        if Key.StartsWith('eyes-') then Scale := EyeBounds.Width / Bounds.Width
        else Scale := Min(BodyBounds.Height / Bounds.Height, Body.Width * 0.92 / Bounds.Width);
        var W := Max(1, Round(Bounds.Width * Scale)); var H := Max(1, Round(Bounds.Height * Scale));
        var Pixels := ResampleRgba(PNG.Pixels, PNG.Width, PNG.Height, Bounds, W, H);
        if Key.StartsWith('eyes-') then begin
          X := 484 + EyeBounds.Left; Y := 311 + EyeBounds.Top + Round((EyeBounds.Height - H) / 2.0);
        end else begin
          X := Round((BodyBounds.Left + BodyBounds.Right - W) / 2.0); Y := BodyBounds.Bottom - H;
        end;
        var Output := TPath.Combine(Input, Key + '.png');
        if FileExists(Output) then begin
          var Existing := ReadPng(Output);
          if (Existing.Width <> W) or (Existing.Height <> H) or (Length(Existing.Pixels) <> Length(Pixels)) or
            not CompareMem(@Existing.Pixels[0], @Pixels[0], Length(Pixels)) then raise Exception.Create('Prepared output differs; keep previous version');
        end else WriteRgbaPng(Output, W, H, Pixels);
        var O := TJSONObject.Create; Records.AddElement(O); O.AddPair('key', Key); O.AddPair('source', Path); O.AddPair('output', Output);
        O.AddPair('sourceSha256', THashSHA2.GetHashStringFromFile(Path)); O.AddPair('sha256', THashSHA2.GetHashStringFromFile(Output));
        O.AddPair('sourceWidth', TJSONNumber.Create(PNG.Width)); O.AddPair('sourceHeight', TJSONNumber.Create(PNG.Height));
        O.AddPair('width', TJSONNumber.Create(W)); O.AddPair('height', TJSONNumber.Create(H));
        O.AddPair('x', TJSONNumber.Create(X)); O.AddPair('y', TJSONNumber.Create(Y)); O.AddPair('scale', TJSONNumber.Create(Scale));
        O.AddPair('transparentPixels', TJSONNumber.Create(AlphaZero)); O.AddPair('opaquePixels', TJSONNumber.Create(AlphaFull));
        O.AddPair('method', 'new-imagegen-drawing; alpha-trim; single-uniform-scale; no-color-key'); O.AddPair('visualState', 'pending-review');
        Writeln(Key, ': ', W, 'x', H, ' at ', X, ',', Y);
      end;
      TFile.WriteAllText(TPath.Combine(Input, 'prepared-assets.json'), Records.ToJSON, TEncoding.UTF8);
    finally Records.Free; end;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
