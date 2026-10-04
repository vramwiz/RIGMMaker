program RigmHistorySeed;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  RigmMovieSession, RigmAppSettings, RigmJson;
begin
  try
    if not SameText(RigmSettingsDirectory,RigmDocumentsDirectory) then raise Exception.Create('Expected default Documents settings directory');
    var Path := ParamStr(1); var Hash := THashSHA2.GetHashStringFromFile(Path);
    var S := TRigmMovieSession.Create;
    try
      var A := TJSONObject.Create;
      try A.AddPair('path',Path); A.AddPair('projectId',S.Project.Id); AddN(A,'revision',S.Project.Revision); var O := S.Execute('open',A); O.Free; finally A.Free; end;
      if AppSettings.LastError<>'' then raise Exception.Create(AppSettings.LastError);
      if THashSHA2.GetHashStringFromFile(Path)<>Hash then raise Exception.Create('Original project changed');
      var O := TJSONObject.Create;
      try AddB(O,'success',True); O.AddPair('settingsDirectory',AppSettings.Root); O.AddPair('openedProject',Path);
        O.AddPair('projectSha256',Hash); O.AddPair('recent',AppSettings.Recent); AddB(O,'projectModified',S.Project.Modified);
        AddB(O,'playing',S.Playing); AddB(O,'busy',S.Busy);
        TFile.WriteAllText(ParamStr(2),O.ToJSON,TEncoding.UTF8); Writeln(O.ToJSON);
      finally O.Free; end;
    finally S.Free; end;
  except on E: Exception do begin Writeln(E.Message); ExitCode := 1; end; end;
end.
