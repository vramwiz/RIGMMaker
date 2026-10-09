// 作品情報のGUIとパイプは同じ更新経路を使用する。GUIだけが作品を承認できる。
procedure TRigmWizardWorkspace.PrepareResearch(Project: TRigmMovieProject);
begin
  if ScriptResearch(Project)<>nil then Exit;
  var Path := FPipe.Workspace.Resolve('Settings\script-research-elements.json',False);
  if not FileExists(Path) then begin PrepareScriptResearch(Project); Exit; end;
  var Config := PsdJson.ObjectText(TFile.ReadAllText(Path,TEncoding.UTF8));
  try
    if (JS(Config,'format')<>'RIGMMaker.ScriptResearchDefinitions') or (JI(Config,'schemaVersion')<>1) then
      raise Exception.Create('既定要素の設定形式が不正です。');
    var Types := JO(Config,'types'); var Definitions := Types.GetValue(ProjectScriptType(Project));
    if Definitions=nil then PrepareScriptResearch(Project)
    else if Definitions is TJSONArray then PrepareScriptResearch(Project,TJSONArray(Definitions))
    else raise Exception.Create('既定要素の設定は台本種類ごとの配列にしてください。');
  finally Config.Free; end;
end;
procedure TRigmWizardWorkspace.UpdateResearch(const Action: string; Args: TJSONObject; Human: Boolean);
begin
  if (FScriptDraft=nil) or (CurrentScriptStage<>'review') then raise Exception.Create('作品情報・掘り下げ確認の工程で操作してください。');
  if VoiceBusy or VoicePlaying or VoiceContinuous then raise Exception.Create('音声生成・再生を終了してください。');
  var Before := ScriptResearch(FScriptDraft).ToJSON;
  ApplyScriptResearch(FScriptDraft,Action,Args,Human);
  if ScriptResearch(FScriptDraft).ToJSON<>Before then begin FScriptDraft.Changed; ScriptChanged; end;
end;
function TRigmWizardWorkspace.ReadResearch(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
    raise Exception.Create('script-statusの現在のprojectId/revisionを指定してください。');
  Result := ResearchSummary(FScriptDraft);
  try
    AddN(Result,'revision',FScriptDraft.Revision); Result.AddPair('projectId',FScriptDraft.Id);
    AddB(Result,'isCurrentPage',(FPage=apScriptCreate) and (CurrentScriptStage='review'));
    Result.AddPair('currentPage',RigmPageKey(FPage)); Result.AddPair('currentStage',CurrentScriptStage);
    var R := ScriptResearch(FScriptDraft); if R=nil then Exit;
    var Section := JS(Args,'section','elements'); Result.AddPair('section',Section);
    if (Section='candidate') or (Section='element') then begin
      var O: TJSONObject;
      if Section='candidate' then O := ResearchCandidate(R,JS(Args,'id',JS(R,'selectedCandidateId')))
      else O := ResearchElement(R,JS(Args,'id',JS(R,'expandedElementId')));
      if O=nil then raise Exception.Create('作品情報の対象IDがありません。');
      Result.AddPair('item',O.Clone as TJSONObject); Exit;
    end;
    if Section='summary' then Exit;
    if not MatchStr(Section,['candidates','elements','integration']) then raise Exception.Create('作品情報の読取区分が不正です。');
    if (Section='integration') and (ResearchAdvanceReason(FScriptDraft)<>'') then raise Exception.Create(ResearchAdvanceReason(FScriptDraft));
    var Items: TJSONArray;
    if Section='candidates' then Items := JA(R,'candidates') else Items := JA(R,'elements');
    var Offset := JI(Args,'offset',0); var Limit := JI(Args,'limit',20);
    if (Offset<0) or (Limit<1) or (Limit>50) then raise Exception.Create('読取位置は0以上、件数は1〜50にしてください。');
    var Rows := TJSONArray.Create; Result.AddPair('rows',Rows); var Position := Min(Offset,Items.Count);
    while (Position<Items.Count) and (Rows.Count<Limit) do begin
      var O := TJSONObject(Items[Position]); Inc(Position);
      if (Section='integration') and (JS(O,'state')<>'confirmed-info') then Continue;
      var Row := TJSONObject.Create; Rows.AddElement(Row);
      for var Key in ['id','label','kind','name','state','confirmedBy','workId'] do
        if O.GetValue(Key)<>nil then Row.AddPair(Key,O.GetValue(Key).Clone as TJSONValue);
      if Section='candidates' then Row.AddPair('overview',ResearchSingleLine(JS(O,'overview')).Substring(0,160))
      else Row.AddPair('summary',ResearchSingleLine(JS(O,'summary')).Substring(0,160));
    end;
    AddN(Result,'total',Items.Count); AddN(Result,'nextOffset',Position); AddB(Result,'hasMore',Position<Items.Count);
  except Result.Free; raise; end;
end;
