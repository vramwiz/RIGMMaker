// 動画編集セッションと埋込みフォームの寿命を管理する。作品タブ、最近の作品と復旧情報を結び付ける。
unit RigmMovieWorkspace;
interface
uses RigmMovieModel;
function MovieWorkDirectory(Project: TRigmMovieProject): string;
function MovieDefaultFile(Project: TRigmMovieProject): string;
function MovieDefaultExport(Project: TRigmMovieProject): string;
function IsMovieWorkPath(const Path: string): Boolean;
function CopyMovieImage(Project: TRigmMovieProject; const Source: string): string;
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
function MovieDefaultExport(Project: TRigmMovieProject): string;
begin Result := TPath.Combine(TPath.Combine(MovieWorkDirectory(Project),'Exports'),SafeName(Project.Title)+'.mp4'); end;
function CopyMovieImage(Project: TRigmMovieProject; const Source: string): string;
begin
  if not FileExists(Source) then raise ERigm.Create('Image file is missing');
  var Hash := THashSHA2.GetHashStringFromFile(Source);
  Result := TPath.Combine(TPath.Combine(MovieWorkDirectory(Project),'Images'),Hash+LowerCase(ExtractFileExt(Source)));
  if not FileExists(Result) then TFile.Copy(Source,Result,False);
  if THashSHA2.GetHashStringFromFile(Result)<>Hash then raise ERigm.Create('Image copy verification failed');
end;
end.
