unit RigmScriptTypes;

// 台本種類の固定IDと表示名。追加時はこの一覧を拡張し、保存済みIDを変更しない。
interface
uses System.JSON, RigmMovieModel;
function ScriptTypeCount: Integer;
function ScriptTypeId(Index: Integer): string;
function ScriptTypeName(const Id: string): string;
function ScriptTypeIndex(const Id: string): Integer;
function ScriptTypesJson: TJSONArray; // 呼出側が所有する種類一覧。
function ProjectScriptType(Project: TRigmMovieProject): string; // 旧台本・従来作品は空文字。
function SingleSceneSection(const Id: string): string; // 共通構成以外は空文字。
function IsSingleSceneScript(Project: TRigmMovieProject): Boolean;
function IsAnimeRankingScript(Project: TRigmMovieProject): Boolean;
function IsStandaloneScript(Project: TRigmMovieProject): Boolean;
procedure ValidateScriptType(Project: TRigmMovieProject); // 将来の有効なIDも保持。書換えなし。

implementation
uses System.SysUtils, RigmJson;
type
  TScriptTypeEntry = record
    Id,Name: string;
  end;
const
  Types: array[0..4] of TScriptTypeEntry = (
    (Id: 'anime-review'; Name: 'アニメ批評'),
    (Id: 'manga-introduction'; Name: '漫画紹介'),
    (Id: 'anime-opening'; Name: 'アニメ（最初）'),
    (Id: 'anime-closing'; Name: 'アニメ（最後）'),
    (Id: 'anime-ranking'; Name: 'アニメ（順位）'));
function ScriptTypeCount: Integer;
begin Result := Length(Types); end;
function ScriptTypeId(Index: Integer): string;
begin
  if (Index<0) or (Index>=Length(Types)) then raise EArgumentOutOfRangeException.Create('台本種類の番号が不正です。');
  Result := Types[Index].Id;
end;
function ScriptTypeIndex(const Id: string): Integer;
begin
  for var I := Low(Types) to High(Types) do if Id=Types[I].Id then Exit(I);
  Result := -1;
end;
function ScriptTypeName(const Id: string): string;
begin
  var I := ScriptTypeIndex(Id); if I>=0 then Exit(Types[I].Name);
  if Id='' then Exit('未設定'); Result := '未対応の種類（'+Id+'）';
end;
function ScriptTypesJson: TJSONArray;
begin
  Result := TJSONArray.Create;
  for var Entry in Types do begin
    var O := TJSONObject.Create; O.AddPair('id',Entry.Id); O.AddPair('name',Entry.Name); Result.AddElement(O);
  end;
end;
function ProjectScriptType(Project: TRigmMovieProject): string;
begin
  Result := ''; if (Project<>nil) and (Project.ScriptWizard<>nil) then Result := JS(Project.ScriptWizard,'scriptType');
end;
function SingleSceneSection(const Id: string): string;
begin
  Result := '';
  if Id='anime-opening' then Result := 'opening'
  else if Id='anime-closing' then Result := 'closing';
end;
function IsSingleSceneScript(Project: TRigmMovieProject): Boolean;
begin Result := SingleSceneSection(ProjectScriptType(Project))<>''; end;
function IsAnimeRankingScript(Project: TRigmMovieProject): Boolean;
begin Result := ProjectScriptType(Project)='anime-ranking'; end;
function IsStandaloneScript(Project: TRigmMovieProject): Boolean;
begin Result := IsSingleSceneScript(Project) or IsAnimeRankingScript(Project); end;
procedure ValidateScriptType(Project: TRigmMovieProject);
begin
  if (Project=nil) or (Project.ScriptWizard=nil) then Exit;
  var V := Project.ScriptWizard.GetValue('scriptType'); if V=nil then Exit;
  if not (V is TJSONString) then raise Exception.Create('台本種類は文字列で指定してください。');
  var Id := TJSONString(V).Value; if Id='' then Exit;
  if (Length(Id)>64) or not CharInSet(Id[1],['a'..'z']) or (Id[Length(Id)]='-') or Id.Contains('--') then
    raise Exception.Create('台本種類の識別子が不正です。');
  for var Ch in Id do if not CharInSet(Ch,['a'..'z','0'..'9','-']) then raise Exception.Create('台本種類の識別子が不正です。');
end;
end.
