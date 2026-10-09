unit RigmScriptResearchModel;

// 第6段階の作品特定と調査結果。原稿は変更せず、人間の作品承認を外部更新から分離する。
interface
uses System.JSON, RigmMovieModel;
function ScriptResearch(Project: TRigmMovieProject): TJSONObject; // 借用。未作成ならnil。
function ResearchCandidate(R: TJSONObject; const Id: string): TJSONObject;
function ResearchElement(R: TJSONObject; const Id: string): TJSONObject;
function ResearchWorkReady(R: TJSONObject): Boolean;
function ResearchAdvanceReason(Project: TRigmMovieProject): string;
function ResearchSummary(Project: TRigmMovieProject): TJSONObject; // 呼出側が解放。
function ResearchIntegrationData(Project: TRigmMovieProject): TJSONObject; // 情報ありの確定項目だけを返す。
function ResearchStateName(const State: string): string;
function ResearchSingleLine(const Text: string): string;
procedure PrepareScriptResearch(Project: TRigmMovieProject; Definitions: TJSONArray = nil);
procedure ValidateScriptResearch(Project: TRigmMovieProject);
procedure ChangeResearchType(Project: TRigmMovieProject);
// 更新は複製上で検査し、失敗時には正本・原稿・確認状態を保持する。
procedure ApplyScriptResearch(Project: TRigmMovieProject; const Action: string;
  Args: TJSONObject; Human: Boolean = False);
implementation
uses System.SysUtils, System.StrUtils, System.Generics.Collections, RigmJson, PsdJson, RigmScriptTypes;

function ScriptResearch(Project: TRigmMovieProject): TJSONObject;
begin
  Result := nil;
  if (Project<>nil) and (Project.ScriptWizard.GetValue('research') is TJSONObject) then
    Result := JO(Project.ScriptWizard,'research');
end;
function ResearchCandidate(R: TJSONObject; const Id: string): TJSONObject;
begin
  Result := nil; if R=nil then Exit;
  for var V in JA(R,'candidates') do if JS(TJSONObject(V),'id')=Id then Exit(TJSONObject(V));
end;
function ResearchElement(R: TJSONObject; const Id: string): TJSONObject;
begin
  Result := nil; if R=nil then Exit;
  for var V in JA(R,'elements') do if JS(TJSONObject(V),'id')=Id then Exit(TJSONObject(V));
end;
function ResearchWorkReady(R: TJSONObject): Boolean;
begin
  Result := False; if R=nil then Exit;
  var C := ResearchCandidate(R,JS(R,'selectedCandidateId'));
  Result := (C<>nil) and JB(R,'humanConfirmed');
  if Result then Result := Trim(JS(C,'overview'))<>'';
end;
function ResearchStateName(const State: string): string;
begin
  if State='checking' then Result := '確認中'
  else if State='confirmed-info' then Result := '情報あり・確定'
  else if State='confirmed-none' then Result := '情報なし・確定'
  else Result := '未確認';
end;
function ResearchSingleLine(const Text: string): string;
begin Result := Text.Replace(#13#10,' ').Replace(#13,' ').Replace(#10,' '); end;
function ResearchAdvanceReason(Project: TRigmMovieProject): string;
begin
  var R := ScriptResearch(Project);
  if not ResearchWorkReady(R) then Exit('作品候補と概要を確認し、「この作品で正しい」にチェックしてください。');
  if not JB(R,'definitionsReady') then Exit('台本の種類に応じた既定要素は未定義です。Codex側で要素一覧を設定してください。');
  for var V in JA(R,'elements') do if not MatchStr(JS(TJSONObject(V),'state'),['confirmed-info','confirmed-none']) then
    Exit('未確認または確認中の項目があります。すべての項目を確定してください。');
  Result := '';
end;
procedure CheckText(O: TJSONObject; const Key: string; Limit: Integer; Required: Boolean = False);
begin
  var S := JS(O,Key);
  if (Length(S)>Limit) or (Required and (Trim(S)='')) then raise Exception.Create('作品情報の'+Key+'が空、または文字数上限を超えています。');
  for var Ch in S do if (Ord(Ch)<32) and not CharInSet(Ch,[#9,#10,#13]) then
    raise Exception.Create('作品情報に無効な制御文字があります。');
end;
procedure CheckSources(O: TJSONObject);
begin
  if O.GetValue('sources')=nil then Exit;
  var A := JA(O,'sources'); if A.Count>12 then raise Exception.Create('参照URLは12件以内で指定してください。');
  for var V in A do if not (V is TJSONString) or (Length(V.Value)>2048) or
    not (V.Value.StartsWith('https://',True) or V.Value.StartsWith('http://',True)) then
    raise Exception.Create('参照URLはhttp/httpsの文字列で指定してください。');
end;
procedure ValidateResearch(R: TJSONObject);
begin
  if (JS(R,'format')<>'RIGMMaker.ScriptResearch') or (JI(R,'schemaVersion')<>1) or (JS(R,'researchId')='') then
    raise Exception.Create('作品情報の保存形式が不正です。');
  for var Key in ['title','scriptType','selectedCandidateId','expandedElementId'] do
    if not (R.GetValue(Key) is TJSONString) then raise Exception.Create('作品情報の必須文字列がありません。');
  CheckText(R,'title',256); CheckText(R,'scriptType',128);
  if not (R.GetValue('humanConfirmed') is TJSONBool) or not (R.GetValue('definitionsReady') is TJSONBool) then
    raise Exception.Create('作品情報の確認状態が不正です。');
  if (JA(R,'candidates').Count>100) or (JA(R,'elements').Count>200) then raise Exception.Create('作品候補または調査項目の上限を超えています。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in JA(R,'candidates') do begin
      if not (V is TJSONObject) then raise Exception.Create('作品候補はオブジェクトで指定してください。');
      var C := TJSONObject(V); CheckText(C,'id',64,True); CheckText(C,'name',256,True);
      CheckText(C,'overview',3000,True); CheckText(C,'identity',2000); CheckText(C,'details',8000); CheckSources(C);
      if Seen.ContainsKey(JS(C,'id')) then raise Exception.Create('作品候補IDが重複しています。'); Seen.Add(JS(C,'id'),True);
    end;
    Seen.Clear;
    for var V in JA(R,'elements') do begin
      if not (V is TJSONObject) then raise Exception.Create('調査項目はオブジェクトで指定してください。');
      var E := TJSONObject(V); CheckText(E,'id',64,True); CheckText(E,'label',128,True);
      for var Key in ['name','summary','details','confirmedBy','workId'] do
        if not (E.GetValue(Key) is TJSONString) then raise Exception.Create('調査項目の必須文字列がありません。');
      if not (E.GetValue('sources') is TJSONArray) then raise Exception.Create('調査項目の参照URL配列がありません。');
      CheckText(E,'name',256); CheckText(E,'summary',3000); CheckText(E,'details',8000); CheckSources(E);
      if Seen.ContainsKey(JS(E,'id')) or not MatchStr(JS(E,'kind'),['default','extra']) or
        not MatchStr(JS(E,'state'),['unconfirmed','checking','confirmed-info','confirmed-none']) or
        not MatchStr(JS(E,'confirmedBy'),['','human','codex']) then raise Exception.Create('調査項目の状態またはIDが不正です。');
      Seen.Add(JS(E,'id'),True);
      if JS(E,'state')='confirmed-info' then begin
        CheckText(E,'name',256,True); CheckText(E,'summary',3000,True);
      end;
      if MatchStr(JS(E,'state'),['confirmed-info','confirmed-none']) and (JS(E,'confirmedBy')='') then
        raise Exception.Create('確定した項目には確認者が必要です。');
      if JS(E,'state')<>'unconfirmed' then
        if not ResearchWorkReady(R) or (JS(E,'workId')<>JS(R,'selectedCandidateId')) then
          raise Exception.Create('調査項目の対象作品が人間の確認済み作品と一致しません。');
    end;
  finally Seen.Free; end;
  if (JS(R,'selectedCandidateId')<>'') and (ResearchCandidate(R,JS(R,'selectedCandidateId'))=nil) then
    raise Exception.Create('選択した作品候補がありません。');
  if JB(R,'humanConfirmed') and not ResearchWorkReady(R) then raise Exception.Create('作品確認と概要が一致しません。');
  if (JS(R,'expandedElementId')<>'') and (ResearchElement(R,JS(R,'expandedElementId'))=nil) then
    raise Exception.Create('展開した項目がありません。');
end;
procedure ValidateScriptResearch(Project: TRigmMovieProject);
begin
  var R := ScriptResearch(Project); if R=nil then raise Exception.Create('作品情報の保存データがありません。');
  ValidateResearch(R);
  if JS(R,'scriptType')<>ProjectScriptType(Project) then raise Exception.Create('作品情報の台本種類が一致しません。');
end;
function BlankElement(Definition: TJSONObject; const Kind: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',JS(Definition,'id')); Result.AddPair('label',JS(Definition,'label')); Result.AddPair('kind',Kind);
  Result.AddPair('name',''); Result.AddPair('summary',''); Result.AddPair('details','');
  Result.AddPair('state','unconfirmed'); Result.AddPair('confirmedBy',''); Result.AddPair('workId','');
  Result.AddPair('sources',TJSONArray.Create);
end;
procedure ResetInformation(R: TJSONObject);
begin
  var A := TJSONArray.Create;
  for var V in JA(R,'elements') do A.AddElement(BlankElement(TJSONObject(V),JS(TJSONObject(V),'kind')));
  PsdJson.Put(R,'elements',A); PsdJson.Put(R,'expandedElementId','');
  PsdJson.Put(R,'humanConfirmed',TJSONBool.Create(False)); PsdJson.Put(R,'researchId',NewId);
end;
procedure ArchiveResearch(Project: TRigmMovieProject; R: TJSONObject; const Reason: string);
begin
  // タイトル入力の2文字目以降には、空の調査状態を重複保存しない。
  if (Reason='title') and (JA(R,'candidates').Count=0) then begin
    var HasInformation := False;
    for var V in JA(R,'elements') do HasInformation := HasInformation or
      (JS(TJSONObject(V),'state')<>'unconfirmed') or (JS(TJSONObject(V),'name')<>'') or
      (JS(TJSONObject(V),'summary')<>'') or (JS(TJSONObject(V),'details')<>'');
    if not HasInformation then Exit;
  end;
  if Project.ScriptWizard.GetValue('researchArchives')=nil then Project.ScriptWizard.AddPair('researchArchives',TJSONArray.Create);
  var O := TJSONObject.Create; O.AddPair('reason',Reason); O.AddPair('research',R.Clone as TJSONObject);
  JA(Project.ScriptWizard,'researchArchives').AddElement(O);
end;
procedure PrepareScriptResearch(Project: TRigmMovieProject; Definitions: TJSONArray);
begin
  if ScriptResearch(Project)<>nil then Exit;
  var R := TJSONObject.Create;
  R.AddPair('format','RIGMMaker.ScriptResearch'); R.AddPair('schemaVersion',TJSONNumber.Create(1)); R.AddPair('researchId',NewId);
  R.AddPair('title',JS(Project.ScriptWizard,'titleInput',Project.Title)); R.AddPair('scriptType',ProjectScriptType(Project));
  R.AddPair('selectedCandidateId',''); R.AddPair('humanConfirmed',TJSONBool.Create(False));
  R.AddPair('expandedElementId',''); R.AddPair('definitionsReady',TJSONBool.Create(Definitions<>nil));
  R.AddPair('candidates',TJSONArray.Create); R.AddPair('elements',TJSONArray.Create);
  try
    if Definitions<>nil then for var V in Definitions do begin
      if not (V is TJSONObject) then raise Exception.Create('既定要素はオブジェクトで指定してください。');
      JA(R,'elements').AddElement(BlankElement(TJSONObject(V),'default'));
    end;
    ValidateResearch(R); PsdJson.Put(Project.ScriptWizard,'research',R); R := nil;
  finally R.Free; end;
end;
procedure ChangeResearchType(Project: TRigmMovieProject);
begin
  var Old := ScriptResearch(Project); if Old=nil then Exit;
  var R := Old.Clone as TJSONObject;
  try
    PsdJson.Put(R,'scriptType',ProjectScriptType(Project)); ResetInformation(R);
    PsdJson.Put(R,'elements',TJSONArray.Create); PsdJson.Put(R,'definitionsReady',TJSONBool.Create(False));
    ValidateResearch(R); ArchiveResearch(Project,Old,'script-type-changed');
    PsdJson.Put(Project.ScriptWizard,'research',R); R := nil;
    Project.ScriptWizard.RemovePair('researchIntegration').Free;
  finally R.Free; end;
end;
procedure ApplyScriptResearch(Project: TRigmMovieProject; const Action: string; Args: TJSONObject; Human: Boolean);
begin
  var Old := ScriptResearch(Project); if Old=nil then raise Exception.Create('作品情報の工程を開いてください。');
  if not Human and (JS(Args,'researchId')<>JS(Old,'researchId')) then raise Exception.Create('作品または検索条件が変わりました。作品情報を再取得してください。');
  var R := Old.Clone as TJSONObject; var Archive := False;
  try
    if Action='title' then begin
      CheckText(Args,'title',256); var Title := JS(Args,'title');
      if JS(R,'title')=Title then Exit;
      PsdJson.Put(R,'title',Title); ResetInformation(R); Archive := True;
      PsdJson.Put(R,'candidates',TJSONArray.Create); PsdJson.Put(R,'selectedCandidateId','');
    end
    else if Action='candidates' then begin
      if Trim(JS(R,'title'))='' then raise Exception.Create('作品タイトルを入力してください。');
      // 1作品でも自動承認はしない。選択だけを行う。
      var A := JA(Args,'candidates').Clone as TJSONArray; PsdJson.Put(R,'candidates',A);
      ResetInformation(R); Archive := True; PsdJson.Put(R,'selectedCandidateId','');
      if A.Count=1 then begin
        if not (A[0] is TJSONObject) then raise Exception.Create('作品候補の形式が不正です。');
        PsdJson.Put(R,'selectedCandidateId',JS(TJSONObject(A[0]),'id'));
      end;
    end
    else if Action='select' then begin
      var Id := JS(Args,'id'); if ResearchCandidate(R,Id)=nil then raise Exception.Create('作品候補を選択してください。');
      if Id=JS(R,'selectedCandidateId') then Exit;
      ResetInformation(R); Archive := True; PsdJson.Put(R,'selectedCandidateId',Id);
    end
    else if Action='confirm-work' then begin
      if not Human then raise Exception.Create('作品の最終承認は人間のチェック操作が必要です。');
      if ResearchCandidate(R,JS(R,'selectedCandidateId'))=nil then raise Exception.Create('作品候補を選択してください。');
      var Confirm := JB(Args,'confirmed');
      if Confirm=JB(R,'humanConfirmed') then Exit;
      if not Confirm then begin ResetInformation(R); Archive := True; end
      else PsdJson.Put(R,'humanConfirmed',TJSONBool.Create(True));
    end
    else if Action='definitions' then begin
      if JS(Args,'scriptType')<>JS(R,'scriptType') then raise Exception.Create('既定要素の台本種類が一致しません。');
      var A := TJSONArray.Create; PsdJson.Put(R,'elements',A); Archive := True;
      for var V in JA(Args,'elements') do begin
        if not (V is TJSONObject) then raise Exception.Create('既定要素の形式が不正です。');
        A.AddElement(BlankElement(TJSONObject(V),'default'));
      end;
      PsdJson.Put(R,'expandedElementId',''); PsdJson.Put(R,'definitionsReady',TJSONBool.Create(True));
    end
    else if Action='add' then begin
      if not ResearchWorkReady(R) or not JB(R,'definitionsReady') then raise Exception.Create('作品と既定要素を先に確定してください。');
      for var V in JA(R,'elements') do if (JS(TJSONObject(V),'kind')='default') and
        not MatchStr(JS(TJSONObject(V),'state'),['confirmed-info','confirmed-none']) then
        raise Exception.Create('既定要素の確定後に追加要素を作成してください。');
      JA(R,'elements').AddElement(BlankElement(Args,'extra')); PsdJson.Put(R,'expandedElementId',JS(Args,'id'));
    end
    else if Action='expand' then begin
      var Id := JS(Args,'id'); if (Id<>'') and (ResearchElement(R,Id)=nil) then raise Exception.Create('展開する項目がありません。');
      PsdJson.Put(R,'expandedElementId',Id);
    end
    else if (Action='element') or (Action='decide') then begin
      if not ResearchWorkReady(R) then raise Exception.Create('先に人間が対象作品を確認してください。');
      var E := ResearchElement(R,JS(Args,'id')); if E=nil then raise Exception.Create('調査項目IDがありません。');
      if not Human and (JS(Args,'workId')<>JS(R,'selectedCandidateId')) then raise Exception.Create('調査対象の作品IDが一致しません。');
      if Action='element' then begin
        for var Key in ['name','summary','details','sources'] do if Args.GetValue(Key)<>nil then PsdJson.Put(E,Key,Args.GetValue(Key).Clone as TJSONValue);
        // 確定済みの情報を更新した場合、明示した状態以外では再確認に戻す。
        PsdJson.Put(E,'state',JS(Args,'state','checking'));
      end else PsdJson.Put(E,'state',JS(Args,'state'));
      var State := JS(E,'state'); PsdJson.Put(E,'workId',JS(R,'selectedCandidateId'));
      PsdJson.Put(E,'confirmedBy','');
      if MatchStr(State,['confirmed-info','confirmed-none']) then begin
        if Human then PsdJson.Put(E,'confirmedBy','human') else PsdJson.Put(E,'confirmedBy','codex');
      end;
      if State='confirmed-none' then begin PsdJson.Put(E,'name',''); PsdJson.Put(E,'summary','該当情報なし'); end;
      if State='checking' then begin
        // 通信中の詳細は1項目だけ展開し、前の確認中項目は未確認へ戻す。
        for var V in JA(R,'elements') do if (V<>E) and (JS(TJSONObject(V),'state')='checking') then
          PsdJson.Put(TJSONObject(V),'state','unconfirmed');
        PsdJson.Put(R,'expandedElementId',JS(E,'id'));
      end;
    end
    else raise Exception.Create('対応していない作品情報操作です。');
    ValidateResearch(R);
    if Archive then ArchiveResearch(Project,Old,Action);
    PsdJson.Put(Project.ScriptWizard,'research',R); R := nil;
    if Action<>'expand' then Project.ScriptWizard.RemovePair('researchIntegration').Free;
    PsdJson.Put(Project.ScriptWizard,'reviewStatus','in-progress');
  finally R.Free; end;
end;
function ResearchSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; var R := ScriptResearch(Project);
  Result.AddPair('pageId','script-research'); Result.AddPair('stage','review');
  Result.AddPair('scriptType',ProjectScriptType(Project)); Result.AddPair('scriptTypeName',ScriptTypeName(ProjectScriptType(Project)));
  var Reason := ResearchAdvanceReason(Project); Result.AddPair('advanceBlockedReason',Reason); AddB(Result,'canAdvance',Reason='');
  if R=nil then begin Result.AddPair('phase','identify'); AddB(Result,'initialized',False); Exit; end;
  AddB(Result,'initialized',True);
  for var Key in ['researchId','title','selectedCandidateId','expandedElementId','humanConfirmed','definitionsReady'] do
    Result.AddPair(Key,R.GetValue(Key).Clone as TJSONValue);
  if ResearchWorkReady(R) then Result.AddPair('phase','deepen') else Result.AddPair('phase','identify');
  AddN(Result,'candidateCount',JA(R,'candidates').Count);
  var Done := 0; var DefaultCount := 0; var ExtraCount := 0;
  for var V in JA(R,'elements') do begin
    var E := TJSONObject(V); if JS(E,'kind')='default' then Inc(DefaultCount) else Inc(ExtraCount);
    if MatchStr(JS(E,'state'),['confirmed-info','confirmed-none']) then Inc(Done);
  end;
  AddN(Result,'defaultCount',DefaultCount); AddN(Result,'extraCount',ExtraCount); AddN(Result,'confirmedCount',Done);
  var C := ResearchCandidate(R,JS(R,'selectedCandidateId'));
  if C<>nil then Result.AddPair('selectedCandidateName',JS(C,'name'));
end;
function ResearchIntegrationData(Project: TRigmMovieProject): TJSONObject;
begin
  if ResearchAdvanceReason(Project)<>'' then raise Exception.Create(ResearchAdvanceReason(Project));
  var R := ScriptResearch(Project); Result := TJSONObject.Create;
  Result.AddPair('work',ResearchCandidate(R,JS(R,'selectedCandidateId')).Clone as TJSONObject);
  var A := TJSONArray.Create; Result.AddPair('elements',A);
  for var V in JA(R,'elements') do if JS(TJSONObject(V),'state')='confirmed-info' then A.AddElement(V.Clone as TJSONObject);
end;
end.
