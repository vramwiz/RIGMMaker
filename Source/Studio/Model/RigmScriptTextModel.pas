unit RigmScriptTextModel;
interface
uses System.JSON, RigmMovieModel;
const ScriptSectionLimit = 100000; ScriptTextChunkLimit = 4096;
procedure PrepareScriptText(Project: TRigmMovieProject);
procedure ValidateScriptText(Value: TJSONObject);
function ScriptSection(Project: TRigmMovieProject; const Id: string): TJSONObject;
function NormalizeScriptText(const Value: string): string;
function ScriptTextSummary(Project: TRigmMovieProject): TJSONObject;
function ScriptTextBoundary(const Text: string; Offset: Integer): Boolean;
implementation
uses System.SysUtils, System.Generics.Collections, RigmJson;
function ScriptTextBoundary(const Text: string; Offset: Integer): Boolean;
begin
  Result := (Offset>=0) and (Offset<=Length(Text));
  if Result and (Offset>0) and (Offset<Length(Text)) then
    Result := not ((Ord(Text[Offset])>=$D800) and (Ord(Text[Offset])<=$DBFF) and
      (Ord(Text[Offset+1])>=$DC00) and (Ord(Text[Offset+1])<=$DFFF));
end;
function NormalizeScriptText(const Value: string): string;
begin Result := Value.Replace(#13#10,#10).Replace(#13,#10).Replace(#10,#13#10); end;
function ScriptSection(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin
  Result := nil; if (Project.ScriptWizard=nil) or not (Project.ScriptWizard.GetValue('scriptText') is TJSONObject) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'scriptText'),'sections') do if JS(TJSONObject(V),'id')=Id then Exit(TJSONObject(V));
end;
procedure PrepareScriptText(Project: TRigmMovieProject);
begin
  if Project.ScriptWizard.GetValue('scriptText')<>nil then Exit;
  var O := TJSONObject.Create; O.AddPair('format','RIGMMaker.ScriptText'); O.AddPair('schemaVersion',TJSONNumber.Create(1));
  O.AddPair('activeSection','body'); var A := TJSONArray.Create; O.AddPair('sections',A);
  for var Id in ['opening','body','closing'] do begin
    var S := TJSONObject.Create; A.AddElement(S); S.AddPair('id',Id); S.AddPair('text','');
    if Id='body' then S.AddPair('scope','episode') else S.AddPair('scope','shared');
  end;
  Project.ScriptWizard.AddPair('scriptText',O); Project.ScriptWizard.AddPair('textStatus','in-progress');
end;
procedure ValidateScriptText(Value: TJSONObject);
begin
  if (JS(Value,'format')<>'RIGMMaker.ScriptText') or (JI(Value,'schemaVersion')<>1) or
    not (Value.GetValue('sections') is TJSONArray) or (JA(Value,'sections').Count>100) then raise Exception.Create('台本文の形式が不正です。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in JA(Value,'sections') do begin
      if not (V is TJSONObject) then raise Exception.Create('台本区分の形式が不正です。');
      var S := TJSONObject(V); var Id := JS(S,'id');
      if (Id='') or (Length(Id)>64) or Seen.ContainsKey(Id) or not (S.GetValue('text') is TJSONString) or
        (Length(JS(S,'text'))>ScriptSectionLimit) or not ((JS(S,'scope')='shared') or (JS(S,'scope')='episode')) then
        raise Exception.Create('台本区分の値が不正です。');
      Seen.Add(Id,True);
      if ((Id='opening') or (Id='closing')) and (JS(S,'scope')<>'shared') or (Id='body') and (JS(S,'scope')<>'episode') then
        raise Exception.Create('共通パートと今回本文の区分が不正です。');
      for var C in JS(S,'text') do if (Ord(C)<32) and not CharInSet(C,[#9,#10,#13]) then raise Exception.Create('台本に無効な制御文字が含まれています。');
    end;
    for var Id in ['opening','body','closing'] do if not Seen.ContainsKey(Id) then raise Exception.Create('基本の台本3区分がありません。');
    if not Seen.ContainsKey(JS(Value,'activeSection')) then raise Exception.Create('台本の表示区分が不正です。');
  finally Seen.Free; end;
end;
function ScriptTextSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; var O := JO(Project.ScriptWizard,'scriptText');
  Result.AddPair('format',JS(O,'format')); Result.AddPair('schemaVersion',TJSONNumber.Create(1)); Result.AddPair('activeSection',JS(O,'activeSection'));
  var A := TJSONArray.Create; Result.AddPair('sections',A);
  for var V in JA(O,'sections') do begin var S := TJSONObject(V); var Summary := TJSONObject.Create; A.AddElement(Summary);
    Summary.AddPair('id',JS(S,'id')); Summary.AddPair('scope',JS(S,'scope')); AddN(Summary,'length',Length(JS(S,'text'))); end;
end;
end.
