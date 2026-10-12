program RenderSavedSummary;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON, System.Math,
  Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, RigmMovieModel, RigmMovieCompositor,
  RigmMovieLayout, RigmMovieRendering, RigmScriptSummaryModel;
begin
  Application.Initialize;
  var Source := ParamStr(1); var Folder := ParamStr(2); var BeforePath := ParamStr(3);
  ForceDirectories(Folder); var Hash := THashSHA2.GetHashStringFromFile(Source);
  var P := LoadMovie(Source); var Before := LoadMovie(BeforePath); var Results := TJSONArray.Create;
  try
    Before.FileName := P.FileName; // 退避したJSONの相対素材参照も元の作品フォルダから解決する。
    P.Width := 960; P.Height := 540; Before.Width := P.Width; Before.Height := P.Height;
    var Index := 0;
    for var C in P.Cues do if IsScriptSummaryCue(P,C) then begin
      Inc(Index); if C.Subtitle<>C.Text then raise Exception.Create('Summary subtitle missing');
      var Time := P.CueStart(C)+Min(0.05,P.CueDuration(C)/2);
      var A := RenderComposition(P,Time,nil);
      try
        var B := RenderComposition(Before,Time,nil);
        try
          var Area := MovieSubtitleContentRect(P); var Changed := 0;
          for var Y := Area.Top to Area.Bottom-1 do begin
            var RowA := PByte(A.ScanLine[Y]); var RowB := PByte(B.ScanLine[Y]);
            for var X := Area.Left*4 to Area.Right*4-1 do if RowA[X]<>RowB[X] then Inc(Changed);
          end;
          if Changed<=100 then raise Exception.Create('Subtitle not rendered');
          var PNG := TPngImage.Create;
          try PNG.Assign(A); PNG.SaveToFile(TPath.Combine(Folder,'summary-'+Index.ToString+'.png')); finally PNG.Free; end;
          var Row := TJSONObject.Create; Results.AddElement(Row); Row.AddPair('cueId',C.Id);
          Row.AddPair('subtitle',C.Subtitle); Row.AddPair('time',TJSONNumber.Create(Time));
          Row.AddPair('changedSubtitleBytes',TJSONNumber.Create(Changed));
        finally B.Free; end;
      finally A.Free; end;
    end;
    if Index<>6 then raise Exception.Create('Summary count changed');
    if Hash<>THashSHA2.GetHashStringFromFile(Source) then raise Exception.Create('Source changed during read-only rendering');
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Results.ToJSON,TEncoding.UTF8);
    Writeln('PASS real project: six visible summary subtitles; original file unchanged');
  finally Results.Free; Before.Free; P.Free; end;
end.
