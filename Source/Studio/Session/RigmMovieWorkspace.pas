// 動画編集セッションと埋込みフォームの寿命を管理する。作品タブ、最近の作品と復旧情報を結び付ける。
unit RigmMovieWorkspace;
interface
uses RigmMovieModel;
function MovieWorkDirectory(Project: TRigmMovieProject): string;
function MovieDefaultFile(Project: TRigmMovieProject): string;
// 出力動画の題名部分。禁止文字・予約名を避け、長い題名は区切りで短縮する。ファイル操作は行わない。
function MovieExportName(const Title: string): string;
function MovieDefaultExport(Project: TRigmMovieProject): string;
function IsMovieWorkPath(const Path: string): Boolean;
function CopyMovieImage(Project: TRigmMovieProject; const Source: string; const Directory: string=''): string;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.StrUtils,
  RigmAppSettings, RigmModel;
function WorkRoot: string;
begin Result := TPath.Combine(AppSettings.Root,'Projects'); end;
function SafeName(const Value: string): string;
begin
  Result := Value.Trim;
  for var C in TPath.GetInvalidFileNameChars do Result := Result.Replace(C,'_');
  Result := Result.Trim([' ','.']);
  if Result='' then Result := 'Movie';
  Result := Copy(Result,1,70);
  Result := Result+'-'+Copy(THashSHA2.GetHashString(Value),1,8);
end;
function IsMovieWorkPath(const Path: string): Boolean;
begin Result := (Path<>'') and StartsText(IncludeTrailingPathDelimiter(WorkRoot),ExpandFileName(Path)); end;
function MovieWorkDirectory(Project: TRigmMovieProject): string;
begin
  if IsMovieWorkPath(Project.FileName) then Result := ExtractFileDir(Project.FileName)
  else Result := TPath.Combine(WorkRoot,SafeName(Project.Title)+'-'+Copy(THashSHA2.GetHashString(Project.Id),1,8));
  ForceDirectories(Result);
  for var Name in ['Images','Audio','Characters','Exports'] do ForceDirectories(TPath.Combine(Result,Name));
end;
function MovieDefaultFile(Project: TRigmMovieProject): string;
begin Result := TPath.Combine(MovieWorkDirectory(Project),SafeName(Project.Title)+'.rigmovie'); end;
function MovieExportName(const Title: string): string;
const MaxLength = 70;
begin
  Result := Title.Trim;
  for var C in TPath.GetInvalidFileNameChars do Result := Result.Replace(C,'_');
  Result := Result.Trim([' ','.']);
  if Result='' then Result := '無題';
  var DeviceName := Result;
  var Dot := Pos('.',DeviceName);
  if Dot>0 then DeviceName := Copy(DeviceName,1,Dot-1);
  if MatchText(DeviceName,['CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
    'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9','COM¹','COM²','COM³','LPT¹','LPT²','LPT³']) then
    Result := '_'+Result;
  if Length(Result)>MaxLength then begin
    var Cut := MaxLength;
    for var I := MaxLength downto 16 do
      if Pos(Result[I],' 　、，,。！!？?：；;～〜―—')>0 then begin
        Cut := I; Break;
      end;
    // UTF-16のサロゲートペアを途中で切らない。
    if (Ord(Result[Cut])>=$D800) and (Ord(Result[Cut])<=$DBFF) then Dec(Cut);
    Result := Copy(Result,1,Cut).Trim([' ','.','　','、','，',',','。','：','；',';','～','〜','―','—']);
  end;
  if Result='' then Result := '無題';
end;
function MovieDefaultExport(Project: TRigmMovieProject): string;
begin Result := TPath.Combine(TPath.Combine(MovieWorkDirectory(Project),'Exports'),MovieExportName(Project.Title)+'.mp4'); end;
function CopyMovieImage(Project: TRigmMovieProject; const Source,Directory: string): string;
begin
  if not FileExists(Source) then raise ERigm.Create('Image file is missing');
  var Hash := THashSHA2.GetHashStringFromFile(Source);
  var TargetDirectory := Directory; if TargetDirectory='' then TargetDirectory := TPath.Combine(MovieWorkDirectory(Project),'Images');
  ForceDirectories(TargetDirectory); Result := TPath.Combine(TargetDirectory,Hash+LowerCase(ExtractFileExt(Source)));
  if not FileExists(Result) then TFile.Copy(Source,Result,False);
  if THashSHA2.GetHashStringFromFile(Result)<>Hash then raise ERigm.Create('Image copy verification failed');
end;
end.
