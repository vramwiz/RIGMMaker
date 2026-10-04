program RigmHistoryMaintenance;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Generics.Collections,
  RigmAppSettings, RigmJson;
begin
  try
    var Root := RigmDocumentsDirectory;
    var ReportPath := ExpandFileName(ParamStr(1));
    if not ReportPath.StartsWith('D:\DelphiProg\RIGMMaker\Win64\Validation\',True) then raise Exception.Create('Unexpected report path');
    var Path := TPath.Combine(Root,'settings.json');
    var Before := TFile.ReadAllText(Path,TEncoding.UTF8); var BeforeHash := THashSHA2.GetHashStringFromFile(Path);
    TFile.WriteAllText(ReportPath+'.settings-before.json',Before,TEncoding.UTF8);
    var Protected := TDictionary<string,string>.Create; var Original := ParseObject(Before);
    var Report := TJSONObject.Create;
    try
      for var Key in ['recent','recoveries'] do begin
        if not(Original.GetValue(Key) is TJSONArray) then Continue;
        for var V in TJSONArray(Original.GetValue(Key)) do begin
          if not(V is TJSONObject) then Continue;
          var Work := JS(TJSONObject(V),'path');
          if FileExists(Work) and not Protected.ContainsKey(Work) then Protected.Add(Work,THashSHA2.GetHashStringFromFile(Work));
        end;
      end;
      var Settings := TRigmAppSettings.Create(Root);
      try
        if Settings.LastError<>'' then raise Exception.Create(Settings.LastError);
        Settings.NormalizeHistory;
        var Recent := Settings.Recent; var Recoveries := Settings.Recoveries;
        AddN(Report,'recentCount',Recent.Count); AddN(Report,'recoveryCount',Recoveries.Count);
        Report.AddPair('recent',Recent); Report.AddPair('recoveries',Recoveries);
      finally Settings.Free; end;
      var Files := TJSONArray.Create; Report.AddPair('protectedFiles',Files);
      for var Pair in Protected do begin
        var Current := THashSHA2.GetHashStringFromFile(Pair.Key);
        if Current<>Pair.Value then raise Exception.Create('Protected work changed');
        var FileReport := TJSONObject.Create; FileReport.AddPair('path',Pair.Key); FileReport.AddPair('beforeSha256',Pair.Value);
        FileReport.AddPair('afterSha256',Current); AddB(FileReport,'preserved',True); Files.AddElement(FileReport);
      end;
      var AfterHash := THashSHA2.GetHashStringFromFile(Path);
      AddB(Report,'success',True); Report.AddPair('settingsPath',Path); Report.AddPair('beforeSha256',BeforeHash); Report.AddPair('afterSha256',AfterHash);
      AddB(Report,'onDiskMigrationDeferred',AfterHash=BeforeHash);
      AddB(Report,'savedOrRecoveryFilesWritten',False); AddB(Report,'userApplicationStopped',False);
      TFile.WriteAllText(ReportPath,Report.ToJSON,TEncoding.UTF8); Writeln(Report.ToJSON);
    finally Report.Free; Original.Free; Protected.Free; end;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
