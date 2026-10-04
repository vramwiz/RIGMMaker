program RigmMediaReexportTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, RigmMovieModel, RigmMovieSession, RigmJson;
begin
  var FileName := ParamStr(1); var ResultPath := ParamStr(2); var S := TRigmMovieSession.Create;
  try
    S.SetProject(LoadMovie(FileName));
    if ParamStr(3)<>'' then S.Project.OutputTarget := ParamStr(3);
    var Args := TJSONObject.Create;
    try Args.AddPair('projectId',S.Project.Id); AddN(Args,'revision',S.Project.Revision);
      var Reply := S.Execute('export',Args); Reply.Free;
    finally Args.Free; end;
    var Deadline := GetTickCount64+1200000;
    while S.Busy and (GetTickCount64<Deadline) do begin Sleep(50); S.Poll; end;
    Args := TJSONObject.Create;
    try var Reply := S.Execute('job-status',Args);
      try
        if JS(Reply,'state')<>'succeeded' then raise Exception.Create(Reply.ToJSON);
        SaveMovie(S.Project,FileName,True);
        var O := TJSONObject.Create;
        try AddB(O,'success',True); AddN(O,'passed',2); O.AddPair('project',FileName); O.AddPair('export',S.Project.OutputTarget); O.AddPair('exportSha256',THashSHA2.GetHashStringFromFile(S.Project.OutputTarget)); O.AddPair('job',Reply.Clone as TJSONObject);
          TFile.WriteAllText(ResultPath,O.ToJSON,TEncoding.UTF8);
        finally O.Free; end;
      finally Reply.Free; end;
    finally Args.Free; end;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  S.Free;
end.
