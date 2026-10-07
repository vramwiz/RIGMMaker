unit RigmAudioFilePaths;
// Extend Unicode audio paths at the filesystem boundary. Stored project references stay unchanged.
interface
function AudioFilePath(const Path: string): string;
function AudioFileExists(const Path: string): Boolean;
implementation
uses System.SysUtils, Winapi.Windows;
function AudioFilePath(const Path: string): string;
var Required,Written: DWORD; Part: PWideChar; Full: string;
begin
  if (Path='') or (Pos(#0,Path)>0) or Path.StartsWith('\\.\') then
    raise EArgumentException.Create('Invalid audio file path');
  if Path.StartsWith('\\?\') then begin
    if not (Path.StartsWith('\\?\UNC\',True) or
      ((Length(Path)>=7) and CharInSet(Path[5],['a'..'z','A'..'Z']) and
       (Path[6]=':') and (Path[7]='\'))) then
      raise EArgumentException.Create('Invalid extended audio file path');
    Result := Path;
  end else begin
    Part := nil; Required := GetFullPathNameW(PWideChar(Path),0,nil,Part);
    if Required=0 then RaiseLastOSError;
    if Required>32767 then raise EArgumentException.Create('Audio path is too long');
    SetLength(Full,Required); Written := GetFullPathNameW(PWideChar(Path),Required,PWideChar(Full),Part);
    if (Written=0) or (Written>=Required) then RaiseLastOSError;
    SetLength(Full,Written);
    if Full.StartsWith('\\') then Result := '\\?\UNC\'+Copy(Full,3,MaxInt)
    else Result := '\\?\'+Full;
  end;
  if Length(Result)>32767 then raise EArgumentException.Create('Audio path is too long');
end;
function AudioFileExists(const Path: string): Boolean;
begin
  Result := False;
  if Path='' then Exit;
  try Result := FileExists(AudioFilePath(Path));
  except on E: EArgumentException do Exit; on E: EOSError do Exit; end;
end;
end.
