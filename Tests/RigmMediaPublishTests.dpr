program RigmMediaPublishTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, RigmMovieModel,
  RigmMovieMotionLibrary, RigmMovieWorkflow, RigmAppSettings, RigmJson;
begin
  var Path := ParamStr(1); var Output := ParamStr(2); var P := LoadMovie(Path); var Checks := TJSONArray.Create;
  try
    var Before := THashSHA2.GetHashStringFromFile(Path); var Presets := LoadCharacterMotions(ResolveMoviePath(Path,P.Characters[0].FileName));
    try if Presets.Count<>4 then raise Exception.Create('Real Documents motion library does not contain all four presets'); Checks.Add('real Documents library supplies four reusable character motions'); finally Presets.Free; end;
    AppSettings.RecordMovie(P,0,P.Cues[0].Id);
    if AppSettings.LastError<>'' then raise Exception.Create(AppSettings.LastError);
    var History := AppSettings.Recent;
    try
      var Count := 0;
      for var V in History do if SameText(JS(TJSONObject(V),'path'),Path) then Inc(Count);
      if Count<>1 then raise Exception.Create('Delivered work does not have exactly one actual-path history entry');
      Checks.Add('delivered image work has exactly one ordinary MRU entry');
      if not SameText(JS(TJSONObject(History[0]),'path'),Path) then raise Exception.Create('Delivered work is not first in history');
      Checks.Add('delivered image work is first in the recent-work menu');
    finally History.Free; end;
    if THashSHA2.GetHashStringFromFile(Path)<>Before then raise Exception.Create('History publication changed the delivered work');
    Checks.Add('publishing the menu history does not modify the delivered project');
    var O := TJSONObject.Create;
    try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('project',Path); O.AddPair('settingsRoot',AppSettings.Root); O.AddPair('sha256',Before); O.AddPair('checks',Checks.Clone as TJSONArray); TFile.WriteAllText(Output,O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  Checks.Free; P.Free;
end.
