unit RigmAppSettings;

interface
uses System.SysUtils, System.Classes, System.JSON, RigmMovieModel;
type
  TRigmAppSettings = class
  private
    FRoot,FError: string;
    FRecent,FRecoveries: TJSONArray;
    FNeedsPersist: Boolean;
    FMutex: THandle;
    function Lock: Boolean;
    procedure Load;
    procedure Persist;
    function IndexOf(const Path: string): Integer;
    procedure ImportLegacy;
  public
    constructor Create(const Directory: string);
    destructor Destroy; override;
    procedure RecordMovie(Project: TRigmMovieProject; Seconds: Double; const CueId: string='');
    procedure RememberPosition(Project: TRigmMovieProject; Seconds: Double; const CueId: string);
    procedure RecordRecovery(Project: TRigmMovieProject; const Path: string; Seconds: Double; const CueId: string);
    procedure NormalizeHistory;
    function Recoveries: TJSONArray;
    function ResumeMovie(Project: TRigmMovieProject; out CueId: string): Double;
    function Recent: TJSONArray;
    property Root: string read FRoot;
    property LastError: string read FError;
  end;
function RigmDocumentsDirectory: string;
function RigmSettingsDirectory: string;
function AppSettings: TRigmAppSettings;

implementation
uses System.IOUtils, System.Math, System.DateUtils, System.IniFiles, System.StrUtils, System.Generics.Collections,
  Winapi.Windows, Winapi.TlHelp32, Winapi.ShlObj, Winapi.ActiveX, Winapi.KnownFolders, RigmJson, RigmMovieOutput, RigmMovieWorkflow, System.Win.ComObj, System.Hash, RigmMovieHistory;
procedure SetPair(O: TJSONObject; const Key: string; Value: TJSONValue);
begin O.RemovePair(Key).Free; O.AddPair(Key,Value); end;
var Settings: TRigmAppSettings;

function RigmDocumentsDirectory: string;
begin
  Result := 'D:\Users\take6\RIGMMaker';
  for var I := 1 to ParamCount - 1 do if ParamStr(I)='--data-root' then Result := ExpandFileName(ParamStr(I+1));
end;
function RigmSettingsDirectory: string;
begin
  Result := GetEnvironmentVariable('RIGMMAKER_SETTINGS_DIR');
  for var I := 1 to ParamCount do begin
    if ParamStr(I).StartsWith('--settings-dir=') then Result := ParamStr(I).Substring(15);
    if (ParamStr(I)='--settings-dir') and (I<ParamCount) then Result := ParamStr(I+1);
  end;
  if Result='' then Result := RigmDocumentsDirectory;
  Result := ExpandFileName(Result);
end;
function AppSettings: TRigmAppSettings;
begin
  if Settings=nil then Settings := TRigmAppSettings.Create(RigmSettingsDirectory);
  Result := Settings;
end;
constructor TRigmAppSettings.Create(const Directory: string);
begin
  inherited Create; FRoot := ExpandFileName(Directory); FRecent := TJSONArray.Create; FRecoveries := TJSONArray.Create;
  FMutex := CreateMutex(nil,False,PChar('Local\RIGMMakerSettings-'+THashSHA2.GetHashString(LowerCase(FRoot))));
  Load;
  if not FileExists(TPath.Combine(FRoot,'settings.json')) then ImportLegacy;
  if FNeedsPersist then NormalizeHistory;
end;
destructor TRigmAppSettings.Destroy;
begin if FMutex<>0 then CloseHandle(FMutex); FRecoveries.Free; FRecent.Free; inherited; end;
function TRigmAppSettings.Lock: Boolean;
begin
  Result := False;
  if FMutex=0 then begin FError := 'Settings lock unavailable'; Exit; end;
  var State := WaitForSingleObject(FMutex,2000);
  Result := (State=WAIT_OBJECT_0) or (State=WAIT_ABANDONED);
  if not Result then FError := 'Settings are busy';
end;
procedure TRigmAppSettings.Load;
var O: TJSONObject; Path: string;
begin
  Path := TPath.Combine(FRoot,'settings.json');
  if not FileExists(Path) then Exit;
  try
    if TFile.GetSize(Path)>1024*1024 then raise Exception.Create('Settings file is too large');
    O := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
    try
      if JS(O,'application')<>'RIGMMaker' then raise Exception.Create('Unknown settings format');
      var A := JA(O,'recent');
      FRecent.Free; FRecent := A.Clone as TJSONArray;
      FRecoveries.Free; FRecoveries := TJSONArray.Create;
      if O.GetValue('recoveries')<>nil then begin FRecoveries.Free; FRecoveries := JA(O,'recoveries').Clone as TJSONArray; end;
      var Before := FRecent.ToJSON+'|'+FRecoveries.ToJSON;
      NormalizeMovieHistory(FRoot,FRecent,FRecoveries);
      FNeedsPersist := (JI(O,'historyVersion')<>2) or (Before<>FRecent.ToJSON+'|'+FRecoveries.ToJSON);
    finally O.Free; end;
    FError := '';
  except on E: Exception do FError := E.Message; end;
end;
function TRigmAppSettings.IndexOf(const Path: string): Integer;
begin
  for var I := 0 to FRecent.Count-1 do if SameText(JS(TJSONObject(FRecent[I]),'path'),ExpandFileName(Path)) then Exit(I);
  Result := -1;
end;
procedure TRigmAppSettings.Persist;
var O: TJSONObject; Temp,Path: string;
begin
  // A corrupt existing file remains available for recovery; never overwrite it.
  if FError<>'' then Exit;
  ForceDirectories(FRoot); Path := TPath.Combine(FRoot,'settings.json');
  Temp := Path+'.'+TGUID.NewGuid.ToString+'.tmp'; O := TJSONObject.Create;
  try
    O.AddPair('application','RIGMMaker'); AddN(O,'version',1);
    AddN(O,'historyVersion',2); O.AddPair('recoveries',FRecoveries.Clone as TJSONArray);
    O.AddPair('recent',FRecent.Clone as TJSONArray);
    TFile.WriteAllText(Temp,O.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    FNeedsPersist := False;
  finally O.Free; if FileExists(Temp) then TFile.Delete(Temp); end;
end;
procedure TRigmAppSettings.RecordMovie(Project: TRigmMovieProject; Seconds: Double; const CueId: string);
var O: TJSONObject; I: Integer;
begin
  if (Project.FileName='') or not FileExists(Project.FileName) then Exit;
  if IsMovieRecovery(FRoot,Project.FileName) then begin RecordRecovery(Project,Project.FileName,Seconds,CueId); Exit; end;
  if not Lock then Exit;
  try
  try
    Load; if FError<>'' then Exit;
    I := IndexOf(Project.FileName); if I>=0 then FRecent.Remove(I).Free;
    O := TJSONObject.Create;
    O.AddPair('kind','movie'); O.AddPair('path',ExpandFileName(Project.FileName)); O.AddPair('title',Project.Title);
    O.AddPair('projectId',Project.Id);
    O.AddPair('stage',Project.WorkflowStage); AddN(O,'time',Seconds); O.AddPair('cueId',CueId);
    O.AddPair('fileHash',MovieFileIdentity(Project.FileName)); O.AddPair('renderKey',MovieRenderKey(Project));
    O.AddPair('accessed',DateToISO8601(TTimeZone.Local.ToUniversalTime(Now),True));
    // JSON arrays have no Insert; build the new MRU while retaining other entries.
    var A := TJSONArray.Create; A.AddElement(O);
    for var V in FRecent do if A.Count<20 then A.AddElement(V.Clone as TJSONValue);
    FRecent.Free; FRecent := A; NormalizeMovieHistory(FRoot,FRecent,FRecoveries); Persist;
  except on E: Exception do FError := E.Message; end;
  finally ReleaseMutex(FMutex); end;
end;
procedure TRigmAppSettings.RememberPosition(Project: TRigmMovieProject; Seconds: Double; const CueId: string);
begin
  if (Project.FileName='') or not FileExists(Project.FileName) then Exit;
  if not Lock then Exit;
  try
  try
    Load; if FError<>'' then Exit;
    var I := IndexOf(Project.FileName); if I<0 then Exit;
    var O := TJSONObject(FRecent[I]);
    // Only a saved, unchanged work can be resumed at its remembered stage.
    if (JS(O,'fileHash')<>MovieFileIdentity(Project.FileName)) or (JS(O,'renderKey')<>MovieRenderKey(Project)) then Exit;
    if SameValue(JN(O,'time'),Seconds,0.000001) and (JS(O,'cueId')=CueId) and (JS(O,'stage')=Project.WorkflowStage) then Exit;
    SetPair(O,'time',TJSONNumber.Create(Seconds)); SetPair(O,'cueId',TJSONString.Create(CueId));
    SetPair(O,'stage',TJSONString.Create(Project.WorkflowStage)); Persist;
  except on E: Exception do FError := E.Message; end;
  finally ReleaseMutex(FMutex); end;
end;
function TRigmAppSettings.ResumeMovie(Project: TRigmMovieProject; out CueId: string): Double;
begin
  Load; Result := 0; CueId := ''; var I := IndexOf(Project.FileName); if I<0 then Exit;
  var O := TJSONObject(FRecent[I]);
  if (JS(O,'fileHash')<>MovieFileIdentity(Project.FileName)) or (JS(O,'renderKey')<>MovieRenderKey(Project)) then Exit;
  // Opening a work always starts at the beginning. History still retains its
  // workflow stage; seeking and read-only queries never call this load policy.
  if Project.Cues.Count>0 then CueId := Project.Cues[0].Id;
  if MatchText(JS(O,'stage'),['script','setup','audio','preview','export','complete']) then Project.WorkflowStage := JS(O,'stage');
end;
function OtherProductInstance: Boolean;
begin
  Result := True; // If process enumeration fails, leave the real settings file alone.
  var Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
  if Snapshot=INVALID_HANDLE_VALUE then Exit;
  try
    var Entry: TProcessEntry32; ZeroMemory(@Entry,SizeOf(Entry)); Entry.dwSize := SizeOf(Entry);
    if not Process32First(Snapshot,Entry) then Exit;
    repeat
      var Name := string(Entry.szExeFile);
      if (Entry.th32ProcessID<>GetCurrentProcessId) and
        (SameText(Name,'RIGMMaker.exe') or (StartsText('RIGMMaker.',Name) and EndsText('.exe',Name))) then Exit;
    until not Process32Next(Snapshot,Entry);
    Result := False;
  finally CloseHandle(Snapshot); end;
end;
procedure TRigmAppSettings.NormalizeHistory;
begin
  // Older product instances may later write their own history format. Defer the automatic
  // on-disk migration until a sole product instance starts; in-memory menus still normalize.
  if SameText(FRoot,RigmDocumentsDirectory) and OtherProductInstance then Exit;
  if not Lock then Exit;
  try try Load; if FNeedsPersist and (FError='') then Persist; except on E: Exception do FError := E.Message; end;
  finally ReleaseMutex(FMutex); end;
end;
procedure TRigmAppSettings.RecordRecovery(Project: TRigmMovieProject; const Path: string; Seconds: Double; const CueId: string);
begin
  if not FileExists(Path) or not Lock then Exit;
  try try
    Load; if FError<>'' then Exit;
    var O := TJSONObject.Create; O.AddPair('path',ExpandFileName(Path)); O.AddPair('title',Project.Title);
    O.AddPair('projectId',Project.Id); O.AddPair('sourcePath',IfThen(IsMovieRecovery(FRoot,Project.FileName),'',Project.FileName));
    AddN(O,'time',Seconds); O.AddPair('cueId',CueId);
    O.AddPair('accessed',DateToISO8601(TTimeZone.Local.ToUniversalTime(Now),True));
    var Pending := TJSONArray.Create;
    try Pending.AddElement(O); for var V in FRecoveries do Pending.AddElement(V.Clone as TJSONObject);
      FRecoveries.Free; FRecoveries := Pending; Pending := nil;
    finally Pending.Free; end;
    NormalizeMovieHistory(FRoot,FRecent,FRecoveries); Persist;
  except on E: Exception do FError := E.Message; end;
  finally ReleaseMutex(FMutex); end;
end;
function TRigmAppSettings.Recent: TJSONArray;
begin Load; if FNeedsPersist then NormalizeHistory; Result := FRecent.Clone as TJSONArray; end;
function TRigmAppSettings.Recoveries: TJSONArray;
begin Load; if FNeedsPersist then NormalizeHistory; Result := FRecoveries.Clone as TJSONArray; end;
procedure TRigmAppSettings.ImportLegacy;
var Paths: TStringList; Ini: TMemIniFile;
  procedure Add(const Path: string);
  begin
    if (Path<>'') and SameText(ExtractFileExt(Path),'.rigmovie') and FileExists(Path) and (Paths.IndexOf(ExpandFileName(Path))<0) then Paths.Add(ExpandFileName(Path));
  end;
begin
  // Import references only. Existing projects, libraries and old recovery assets stay in place.
  Paths := TStringList.Create;
  try
    Paths.CaseSensitive := False;
    for var Dir in [FRoot,TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'RIGMMaker')] do begin
      var Path := TPath.Combine(Dir,'history.ini');
      if FileExists(Path) then begin
        Ini := TMemIniFile.Create(Path,TEncoding.UTF8);
        try for var Section in ['Recent','Opened','Saved'] do for var I := 0 to 19 do Add(Ini.ReadString(Section,IntToStr(I),'')); finally Ini.Free; end;
      end;
    end;
    // Test roots are isolated from the real user's recovery collection.
    if SameText(FRoot,RigmDocumentsDirectory) then begin
      var Dir := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'RIGMMaker\MovieRecovery');
      if DirectoryExists(Dir) then begin
        var Files := TDirectory.GetFiles(Dir,'*.rigmovie'); TArray.Sort<string>(Files);
        for var I := High(Files) downto 0 do Add(Files[I]);
      end;
    end;
    for var I := Min(Paths.Count,20)-1 downto 0 do begin
      try
        var P := LoadMovie(Paths[I]);
        try RecordMovie(P,0); finally P.Free; end;
      except on E: Exception do FError := ''; end;
    end;
  finally Paths.Free; end;
end;
initialization
  Settings := nil;
finalization
  Settings.Free;
end.
