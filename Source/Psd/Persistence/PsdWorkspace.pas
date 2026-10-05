unit PsdWorkspace;

// 永続データとアプリ所有の一時ジョブを分離する。回収は移動だけで復元可能。
interface
uses System.SysUtils, System.Classes;

const PSD_DEFAULT_ROOT = 'D:\Users\take6\RIGMMaker';
      PSD_RETENTION_DAYS = 30; // 完了/期限切れジョブの最低保持日数。

type
  TPsdWorkspace = class;
  TPsdWorkJob = class
  private
    FOwner: TPsdWorkspace; // 借用。ジョブより長く生存する。
    FDirectory, FId: string;
    FLease: TFileStream; // 生存中は他プロセスの回収を拒否する排他ハンドル。
    procedure WriteState(const Status: string);
  public
    constructor Create(Owner: TPsdWorkspace);
    destructor Destroy; override; // 正常終了を記録。異常終了のactiveは自動回収しない。
    function FilePath(const Name: string): string;
    property Directory: string read FDirectory;
  end;
  TPsdWorkspace = class
  private
    FRoot, FCleanupNotes: string;
  public
    constructor Create(const Root: string);
    // フルパス/相対パスをルート内へ限定。ADS、UNC、リンク、..を拒否。
    function Resolve(const Path: string; MustExist: Boolean = True): string;
    function ReadText(const Path: string): string;
    procedure Initialize;
    function BeginJob: TPsdWorkJob;
    function Cleanup: Integer; // 所有印＋30日経過＋非活動のみRecoveryへ移動。
    property Root: string read FRoot;
    property CleanupNotes: string read FCleanupNotes;
  end;

implementation
uses System.IOUtils, System.JSON, System.DateUtils, Winapi.Windows, PsdJson;

procedure CheckComponents(const Path: string);
begin
  var Current := ExcludeTrailingPathDelimiter(Path);
  while Length(Current) > 3 do begin
    if FileExists(Current) or DirectoryExists(Current) then
      if (GetFileAttributes(PChar(Current)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise Exception.Create('Reparse points are not allowed: ' + Current);
    var Parent := ExtractFileDir(Current); if Parent = Current then Break; Current := Parent;
  end;
end;
constructor TPsdWorkspace.Create(const Root: string);
begin
  inherited Create;
  FRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Root));
  if (Length(FRoot) < 4) or (FRoot[2] <> ':') or FRoot.StartsWith('\\') then raise Exception.Create('Local data root required');
  CheckComponents(FRoot);
end;
function TPsdWorkspace.Resolve(const Path: string; MustExist: Boolean): string;
begin
  if (Path = '') or (Pos(#0, Path) > 0) or (Pos('*', Path) > 0) or (Pos('?', Path) > 0) then raise Exception.Create('Invalid path');
  var P := Path.Replace('/', '\');
  if P.StartsWith('\\') then raise Exception.Create('UNC/device paths are not allowed');
  var Relative := P;
  if (Length(P) > 2) and (P[2] = ':') then Relative := Copy(P, 3, MaxInt);
  if Pos(':', Relative) > 0 then raise Exception.Create('Alternate streams are not allowed');
  for var Part in Relative.Split(['\']) do begin
    if Part = '' then Continue;
    if (Part = '..') or (Part = '.') or Part.EndsWith(' ') or Part.EndsWith('.') then raise Exception.Create('Ambiguous path component');
    var Device := UpperCase(Part.Split(['.'])[0]);
    if (Device = 'CON') or (Device = 'PRN') or (Device = 'AUX') or (Device = 'NUL') or
      ((Length(Device) = 4) and (Device.StartsWith('COM') or Device.StartsWith('LPT')) and CharInSet(Device[4], ['0'..'9'])) then
      raise Exception.Create('Reserved device filename');
  end;
  if not TPath.IsPathRooted(P) then P := TPath.Combine(FRoot, P);
  Result := TPath.GetFullPath(P);
  if not Result.StartsWith(IncludeTrailingPathDelimiter(FRoot), True) then raise Exception.Create('Path outside data root');
  CheckComponents(Result);
  if MustExist and not FileExists(Result) then raise Exception.Create('Input file missing: ' + Result);
end;
function TPsdWorkspace.ReadText(const Path: string): string;
begin
  var P := Resolve(Path);
  if TFile.GetSize(P) > 8 * 1024 * 1024 then raise Exception.Create('Text size limit');
  Result := TFile.ReadAllText(P, TEncoding.UTF8);
end;
procedure TPsdWorkspace.Initialize;
begin
  for var Name in ['Characters', 'Scripts', 'Exchange', 'Temp\PsdJobs', 'Temp\PsdRecovery', 'Temp\PsdLeases'] do
    ForceDirectories(Resolve(Name, False));
  Cleanup;
end;
function TPsdWorkspace.BeginJob: TPsdWorkJob;
begin Result := TPsdWorkJob.Create(Self); end;
constructor TPsdWorkJob.Create(Owner: TPsdWorkspace);
begin
  inherited Create; FOwner := Owner; FId := NewId;
  FDirectory := Owner.Resolve('Temp\PsdJobs\' + FId, False); ForceDirectories(FDirectory);
  FLease := TFileStream.Create(Owner.Resolve('Temp\PsdLeases\' + FId + '.lock', False), fmCreate or fmShareExclusive);
  WriteState('active');
end;
procedure TPsdWorkJob.WriteState(const Status: string);
begin
  var O := TJSONObject.Create;
  try
    O.AddPair('owner', 'RIGMMaker.PsdJobs.v1'); O.AddPair('jobId', FId); O.AddPair('status', Status);
    O.AddPair('finishedUtc', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
    TFile.WriteAllText(FilePath('job.json'), O.ToJSON, TEncoding.UTF8);
  finally O.Free; end;
end;
destructor TPsdWorkJob.Destroy;
begin
  try if FLease <> nil then WriteState('completed'); except end;
  FLease.Free; inherited;
end;
function TPsdWorkJob.FilePath(const Name: string): string;
begin
  if (Name = '') or (ExtractFileName(Name) <> Name) or (Pos(':', Name) > 0) then raise Exception.Create('Job filename required');
  Result := FOwner.Resolve(TPath.Combine(FDirectory, Name), False);
end;
function TPsdWorkspace.Cleanup: Integer;
begin
  Result := 0; FCleanupNotes := '';
  var Jobs := Resolve('Temp\PsdJobs', False); if not DirectoryExists(Jobs) then Exit;
  for var Dir in TDirectory.GetDirectories(Jobs) do begin
    var Lease: THandle := INVALID_HANDLE_VALUE; var O: TJSONObject := nil;
    try
     try
      Resolve(Dir, False);
      var Id := ExtractFileName(Dir); var G: TGUID;
      try G := StringToGUID(Id); except Continue; end;
      var StatePath := Resolve(TPath.Combine(Dir, 'job.json'));
      if TFile.GetSize(StatePath) > 4096 then Continue;
      O := ObjectText(TFile.ReadAllText(StatePath, TEncoding.UTF8));
      if (S(O, 'owner') <> 'RIGMMaker.PsdJobs.v1') or (S(O, 'jobId') <> Id) then Continue;
      if (S(O, 'status') <> 'completed') and (S(O, 'status') <> 'expired') then Continue;
      var Finished := ISO8601ToDate(S(O, 'finishedUtc'), True);
      if (TTimeZone.Local.ToUniversalTime(Now) - Finished) < PSD_RETENTION_DAYS then Continue;
      var Safe := True;
      // 非再帰列挙でリンク先へ降りる前に検査する。
      var Pending := TStringList.Create;
      try
        Pending.Add(Dir); var Index := 0;
        while Index < Pending.Count do begin
          for var Child in TDirectory.GetFileSystemEntries(Pending[Index]) do begin
            if (GetFileAttributes(PChar(Child)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then begin Safe := False; Break; end;
            if DirectoryExists(Child) then Pending.Add(Child);
          end;
          if not Safe then Break; Inc(Index);
        end;
      finally Pending.Free; end;
      if not Safe then Continue;
      var LeasePath := Resolve('Temp\PsdLeases\' + Id + '.lock');
      Lease := CreateFile(PChar(LeasePath), GENERIC_READ or GENERIC_WRITE,
        0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
      if Lease = INVALID_HANDLE_VALUE then begin FCleanupNotes := FCleanupNotes + 'Lease busy: ' + Id + #13#10; Continue; end;
      // 活動中は排他openが失敗する。移動対象の外側でロックを保持する。
      var Target := Resolve('Temp\PsdRecovery\' + Id + '-' + FormatDateTime('yyyymmddhhnnss', Now), False);
      if MoveFile(PChar(Dir), PChar(Target)) then begin
        Inc(Result); CloseHandle(Lease); Lease := INVALID_HANDLE_VALUE;
        MoveFile(PChar(LeasePath), PChar(TPath.Combine(Target, 'lease.lock')));
      end
      else FCleanupNotes := FCleanupNotes + 'Move failed: ' + SysErrorMessage(GetLastError) + #13#10;
    except
      // 不明な所有印・活動中・時刻不正・アクセス不能は保全する。
      on E: Exception do FCleanupNotes := FCleanupNotes + E.Message + #13#10;
     end;
    finally O.Free; if Lease <> INVALID_HANDLE_VALUE then CloseHandle(Lease); end;
  end;
end;
end.
