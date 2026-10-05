unit PsdPackage;

// .psdchar = ZIP(manifest.json, character.psd, motions/*)。旧.rigmとは識別子も入口も別。
interface
uses PsdCharacter, PsdWorkspace;

procedure SaveCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace; const Path: string);
function LoadCharacter(Workspace: TPsdWorkspace; const Path: string): TPsdCharacter;
procedure ExportPsd(Character: TPsdCharacter; Workspace: TPsdWorkspace; const Path: string);

implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Zip,
  System.Generics.Collections, Winapi.Windows, ArtDocument, ArtPsd, ArtPng, PsdJson;

function LayerIds(Layers: TList<TArtLayer>): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var L in Layers do begin
    var O := TJSONObject.Create; Result.AddElement(O); O.AddPair('id', L.Id);
    O.AddPair('name', L.Name); O.AddPair('children', LayerIds(L.Children));
  end;
end;
procedure RestoreIds(Layers: TList<TArtLayer>; Ids: TJSONArray; Seen: TDictionary<string, Boolean>; Depth: Integer);
begin
  if (Depth > 40) or (Layers.Count <> Ids.Count) then raise Exception.Create('PSD layer tree mismatch');
  for var Index := 0 to Layers.Count - 1 do begin
    var O := TJSONObject(Ids[Index]); var Id := S(O, 'id');
    if (Id = '') or Seen.ContainsKey(Id) or (S(O, 'name') <> Layers[Index].Name) then raise Exception.Create('PSD layer identity mismatch');
    Seen.Add(Id, True); Layers[Index].Id := Id;
    RestoreIds(Layers[Index].Children, Arr(O, 'children'), Seen, Depth + 1);
  end;
end;
function Entry(Zip: TZipFile; const Name: string; Limit: Integer): TBytes;
var Stream: TStream; Header: TZipHeader;
begin
  var Index := Zip.IndexOf(Name);
  if (Index < 0) or (Zip.FileInfo[Index].UncompressedSize > Cardinal(Limit)) then raise Exception.Create('Missing/oversize package entry: ' + Name);
  Stream := nil; Zip.Read(Index, Stream, Header, True);
  try
    if Stream.Size <> Zip.FileInfo[Index].UncompressedSize then raise Exception.Create('ZIP length mismatch');
    SetLength(Result, Stream.Size); if Length(Result) > 0 then Stream.ReadBuffer(Result[0], Length(Result));
  finally Stream.Free; end;
end;
procedure CheckZip(Zip: TZipFile);
begin
  if Zip.FileCount > 2100 then raise Exception.Create('Package entry count limit');
  var Seen := TDictionary<string, Boolean>.Create;
  try
    var Total: UInt64 := 0;
    for var Index := 0 to Zip.FileCount - 1 do begin
      var Name := Zip.FileNames[Index];
      if Name.StartsWith('/') or (Pos('\', Name) > 0) or (Pos(':', Name) > 0) or (Pos(#0, Name) > 0) then raise Exception.Create('Invalid ZIP path');
      for var Part in Name.Split(['/']) do if (Part = '') or (Part = '.') or (Part = '..') then raise Exception.Create('Invalid ZIP component');
      if Seen.ContainsKey(LowerCase(Name)) then raise Exception.Create('Duplicate ZIP entry'); Seen.Add(LowerCase(Name), True);
      Inc(Total, Zip.FileInfo[Index].UncompressedSize);
      if Total > ART_MAX_BYTES then raise Exception.Create('Package allocation limit');
      if (Name <> 'manifest.json') and (Name <> 'character.psd') and not Name.StartsWith('motions/') then raise Exception.Create('Unknown package entry');
    end;
  finally Seen.Free; end;
end;
function LoadCharacter(Workspace: TPsdWorkspace; const Path: string): TPsdCharacter;
var M: TJSONObject; Job: TPsdWorkJob;
begin
  var FileName := Workspace.Resolve(Path); if TFile.GetSize(FileName) > ART_MAX_BYTES then raise Exception.Create('Package file size limit');
  var Zip := TZipFile.Create; var Seen := TDictionary<string, Boolean>.Create; M := nil; Job := nil; Result := nil;
  try
    Zip.Open(FileName, zmRead); CheckZip(Zip);
    M := ObjectText(TEncoding.UTF8.GetString(Entry(Zip, 'manifest.json', 8 * 1024 * 1024)));
    if (S(M, 'format') <> 'RIGMMaker.PsdCharacter') or (I(M, 'version') <> 1) then raise Exception.Create('Unsupported PSD character package');
    Result := TPsdCharacter.Create;
    try
      Result.Id := S(M, 'id'); Result.Name := S(M, 'name'); Result.Policy := S(M, 'editPolicy'); Result.Source := S(M, 'source');
      Result.SupplementName := S(M, 'supplementName');
      if M.GetValue('production') <> nil then begin
        Result.Production.Free; Result.Production := TJSONObject(Obj(M, 'production').Clone);
      end;
      Result.Settings.Free; Result.Settings := TJSONObject(Obj(M, 'settings').Clone);
      Job := Workspace.BeginJob; TFile.WriteAllBytes(Job.FilePath('character.psd'), Entry(Zip, 'character.psd', ART_MAX_BYTES));
      Result.Document.Free; Result.Document := nil; Result.Document := ReadPsd(Job.FilePath('character.psd'));
      RestoreIds(Result.Document.Roots, Arr(M, 'layers'), Seen, 0);
      for var Name in Zip.FileNames do if Name.StartsWith('motions/') then begin
        if not Name.EndsWith('.png', True) then raise Exception.Create('PNG motion entry required');
        var Data := Entry(Zip, Name, 128 * 1024 * 1024);
        TFile.WriteAllBytes(Job.FilePath('frame.png'), Data); ReadPng(Job.FilePath('frame.png'));
        Result.Assets.Add(Name, Data);
      end;
      Result.Validate;
    except Result.Free; Result := nil; raise; end;
  finally Job.Free; M.Free; Seen.Free; Zip.Free; end;
end;
procedure PsdToJob(Character: TPsdCharacter; const Path: string);
begin
  if Character.Policy = 'external' then TFile.WriteAllBytes(Path, Character.Document.SourceBytes)
  else begin
    // managedは本系統が新規生成したPSDのみ。外部PSDは必ず上の原アーカイブ経路。
    // 自前PSDを素の文書として書くことで、保存済み文書も再編集・再保存できる。
    var Copy := Character.Document.Clone;
    try Copy.SourceBytes := nil; Copy.Unsupported.Clear; WriteNewPsd(Copy, Path, pcRle);
    finally Copy.Free; end;
  end;
end;
procedure ExportPsd(Character: TPsdCharacter; Workspace: TPsdWorkspace; const Path: string);
begin
  var Target := Workspace.Resolve(Path, False);
  if not SameText(ExtractFileExt(Target), '.psd') or FileExists(Target) then raise Exception.Create('新しいPSD保存先を指定してください。元画像/PSDは上書きしません。');
  Character.Validate; var Job := Workspace.BeginJob;
  try
    PsdToJob(Character, Job.FilePath('character.psd'));
    var Check := ReadPsd(Job.FilePath('character.psd')); Check.Free;
    ForceDirectories(ExtractFileDir(Target)); TFile.Copy(Job.FilePath('character.psd'), Target, False);
  finally Job.Free; end;
end;
procedure SaveCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace; const Path: string);
begin
  var Target := Workspace.Resolve(Path, False);
  if not SameText(ExtractFileExt(Target), '.psdchar') then raise Exception.Create('.psdchar保存先を指定してください。');
  Character.Validate; var Job := Workspace.BeginJob; var Zip := TZipFile.Create; var M := TJSONObject.Create;
  try
    PsdToJob(Character, Job.FilePath('character.psd'));
    M.AddPair('format', 'RIGMMaker.PsdCharacter'); M.AddPair('version', TJSONNumber.Create(1));
    M.AddPair('id', Character.Id); M.AddPair('name', Character.Name); M.AddPair('editPolicy', Character.Policy); M.AddPair('source', Character.Source);
    M.AddPair('supplementName', Character.SupplementName); M.AddPair('production', TJSONValue(Character.Production.Clone));
    M.AddPair('videoWidth', TJSONNumber.Create(1920)); M.AddPair('videoHeight', TJSONNumber.Create(1080));
    M.AddPair('settings', TJSONValue(Character.Settings.Clone)); M.AddPair('layers', LayerIds(Character.Document.Roots));
    Zip.Open(Job.FilePath('candidate.psdchar'), zmWrite); Zip.Add(TEncoding.UTF8.GetBytes(M.ToJSON), 'manifest.json');
    Zip.Add(TFile.ReadAllBytes(Job.FilePath('character.psd')), 'character.psd');
    for var Pair in Character.Assets do Zip.Add(Pair.Value, Pair.Key);
    Zip.Close;
    var Check := LoadCharacter(Workspace, Job.FilePath('candidate.psdchar')); Check.Free;
    ForceDirectories(ExtractFileDir(Target));
    if FileExists(Target) then begin
      var Old := LoadCharacter(Workspace, Target);
      try if Old.Id <> Character.Id then raise Exception.Create('別キャラの保存ファイルは上書きできません。'); finally Old.Free; end;
      // 旧版を所有ジョブへ保全。30日後にもRecoveryへ移動するだけで消さない。
      TFile.Copy(Target, Job.FilePath('previous.psdchar'), False);
    end;
    if not MoveFileEx(PChar(Job.FilePath('candidate.psdchar')), PChar(Target), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally M.Free; Zip.Free; Job.Free; end;
end;
end.
