program RigmCritiqueAssets;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils, System.IOUtils, System.JSON, System.Hash,
  Vcl.Graphics, Vcl.Imaging.pngimage, RigmEditor, RigmModel, RigmStorage,
  RigmRenderer, RigmMovieCompositor, RigmJson, ArtDocument;
var Editor: TRigmEditor; Report: TJSONObject; Source,Target,Root,Before: string;
begin
  Source := ParamStr(1); Root := ParamStr(2);
  Editor := TRigmEditor.Create; Report := TJSONObject.Create;
  try
    try
      if not FileExists(Source) or (Root='') then raise Exception.Create('Specify the real PSD and a new inspection directory');
      ForceDirectories(Root); Before := THashSHA2.GetHashStringFromFile(Source);
      var Args := TJSONObject.Create; Args.AddPair('path',Source);
      try var Reply := Editor.Execute('import-psd',Args); Reply.Free; finally Args.Free; end;
      // This is a new imported character; original PSD and existing user rigs remain untouched.
      for var G in Editor.Document.Layers do if G.Kind=alkGroup then begin
        var Role := ''; if G.Name='記号' then Role := 'accessory' else if G.Name='顔色' then Role := 'face';
        if Role<>'' then for var L in G.Children do if L.Kind=alkImage then begin
          Args := TJSONObject.Create; Args.AddPair('id',L.Id); Args.AddPair('role',Role);
          try var Reply := Editor.Execute('update-layer',Args); Reply.Free; finally Args.Free; end;
        end;
      end;
      for var Step := 0 to 1 do begin
        Args := TJSONObject.Create;
        try var Reply := Editor.Execute('mark-complete',Args); Reply.Free; finally Args.Free; end;
      end;
      Args := TJSONObject.Create; AddN(Args,'grid',3);
      try var Reply := Editor.Execute('generate-mesh',Args); Reply.Free; finally Args.Free; end;
      for var Step := 0 to 1 do begin
        Args := TJSONObject.Create;
        try var Reply := Editor.Execute('mark-complete',Args); Reply.Free; finally Args.Free; end;
      end;
      Target := TPath.Combine(Root,'kiritan-emotions.rigm');
      if FileExists(Target) then raise Exception.Create('Use a new inspection directory');
      Editor.Document.Name := '東北きりたん・感情差分';
      SaveRigm(Editor.Document,Target);
      var Manifest := RigmManifest(Editor.Document);
      TFile.WriteAllText(TPath.Combine(Root,'manifest.json'),Manifest.ToJSON,TEncoding.UTF8); Manifest.Free;
      Report.AddPair('expressions',ExistingExpressions(Editor.Document));
      var Layers := TJSONArray.Create; Report.AddPair('layers',Layers);
      for var L in Editor.Document.Layers do begin
        var O := TJSONObject.Create; O.AddPair('id',L.Id); O.AddPair('name',L.Name);
        O.AddPair('parentId',Editor.Document.ParentId(L.Id)); AddN(O,'kind',Ord(L.Kind));
        AddB(O,'visible',L.Visible); AddN(O,'pixelBytes',Length(L.Pixels)); AddN(O,'children',L.Children.Count);
        var P := Editor.Document.Part(L.Id); if P<>nil then O.AddPair('role',P.Role);
        Layers.AddElement(O);
      end;
      var Width,Height: Integer; var Pixels := RenderRigm(Editor.Document,Editor.Pose,900,Width,Height);
      var Image := TPngImage.CreateBlank(COLOR_RGBALPHA,8,Width,Height);
      try
        for var Y := 0 to Height-1 do for var X := 0 to Width-1 do begin
          var I := (Y*Width+X)*4;
          Image.Pixels[X,Y] := RGB(Pixels[I],Pixels[I+1],Pixels[I+2]);
          Image.AlphaScanline[Y]^[X] := Pixels[I+3];
        end;
        Image.SaveToFile(TPath.Combine(Root,'default.png'));
      finally Image.Free; end;
      AddB(Report,'success',True); AddB(Report,'sourceUnchanged',Before=THashSHA2.GetHashStringFromFile(Source));
      Report.AddPair('source',Source); Report.AddPair('sourceSha256',Before); Report.AddPair('rigm',Target);
      AddN(Report,'width',Editor.Document.Art.Width); AddN(Report,'height',Editor.Document.Art.Height);
      AddN(Report,'layerCount',Length(Editor.Document.Layers));
      AddN(Report,'boneCount',Editor.Document.Bones.Count); AddN(Report,'meshCount',Editor.Document.Meshes.Count);
      AddB(Report,'usable',Editor.Document.Usable); AddB(Report,'sourceMatched',Editor.Document.SourceMatched);
    except on E: Exception do begin AddB(Report,'success',False); Report.AddPair('error',E.ClassName+': '+E.Message); ExitCode := 1; end; end;
    TFile.WriteAllText(TPath.Combine(Root,'inspection.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally Report.Free; Editor.Free; end;
end.
