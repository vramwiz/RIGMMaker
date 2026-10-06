procedure TRigmWizardWorkspace.SetScriptClosingDraft(Draft: TJSONObject);
begin
  if CurrentScriptStage<>'closing' then raise Exception.Create('締め設定で操作してください。');
  if Draft.ToJSON=JO(JO(FScriptDraft.ScriptWizard,'closingData'),'draft').ToJSON then Exit;
  RigmScriptClosingModel.SetScriptClosingDraft(FScriptDraft,Draft); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.AdoptScriptClosingImage(const Kind,Path: string);
begin
  if (CurrentScriptStage<>'closing') or FScriptTextEditing then raise Exception.Create('締め入力を完了してから画像を採用してください。');
  if not MatchStr(Kind,['representative','endImage','thumbnailImage']) then raise Exception.Create('画像種別が不正です。');
  if not FileExists(Path) or not MatchText(ExtractFileExt(Path),['.png','.jpg','.jpeg','.bmp']) then raise Exception.Create('既存PNG/JPEG/BMPを選んでください。');
  if TFile.GetSize(Path)>RigmImageMaxBytes then raise Exception.Create('画像は32MB以内です。');
  var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite); var Picture := TPicture.Create; var D := JO(JO(FScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  try
    Picture.LoadFromFile(Path); if (Picture.Width<1) or (Picture.Height<1) or (Picture.Width>8192) or (Picture.Height>8192) or (Int64(Picture.Width)*Picture.Height>16777216) then raise Exception.Create('画像は8192px/辺、16MP以内です。');
    PsdJson.Put(D,Kind,CopyMovieImage(FScriptDraft,Path,TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Images')));
    var Choice := 'representativeChoice'; if Kind='endImage' then Choice := 'endChoice' else if Kind='thumbnailImage' then Choice := 'thumbnailChoice';
    PsdJson.Put(D,Choice,'use'); SetScriptClosingDraft(D);
  finally D.Free; Picture.Free; Guard.Free; end;
end;
procedure TRigmWizardWorkspace.CompleteScriptClosing;
begin
  if (CurrentScriptStage<>'closing') or FScriptTextEditing or VoiceBusy then raise Exception.Create('締め入力・音声ジョブを完了してください。');
  if ScriptClosingScene(FScriptDraft)='' then raise Exception.Create('締めのセリフがありません。台本入力で締めを書いてください。');
  var Cast := ScriptCastingSummary(FScriptDraft); try if (JS(Cast,'state')='stale') or (JI(Cast,'pending')<>0) or (JI(Cast,'unassigned')<>0) then raise Exception.Create('配役を確認してください。'); finally Cast.Free; end;
  if not ScriptScenesReady(FScriptDraft) then raise Exception.Create('シーンを確認してください。');
  for var C in FScriptDraft.Cues do if not FScriptDraft.AudioReady(C) then raise Exception.Create('音声を確認してください。');
  var P := FScriptDraft.Clone;
  try MaterializeScriptClosing(P); P.EnableComposition; ValidateCompositionMaterials(P);
    P.Changed; StoreScript(P,'closing');
  finally P.Free; end;
end;
function TRigmWizardWorkspace.ReadScriptClosing(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新のprojectId/revisionで取得してください。');
  PrepareScriptClosing(FScriptDraft); Result := TJSONObject.Create; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  Result.AddPair('closing',JO(FScriptDraft.ScriptWizard,'closingData').Clone as TJSONObject); Result.AddPair('closingScene',ScriptClosingScene(FScriptDraft));
end;
procedure TRigmWizardWorkspace.FinishScriptToEditor;
begin
  if (CurrentScriptStage<>'closing') or FScriptTextEditing or FPlacementEditing or VoiceBusy then raise Exception.Create('締め設定を完了してください。');
  if JS(JO(FScriptDraft.ScriptWizard,'closingData'),'status')<>'complete' then raise Exception.Create('締め設定の確認完了を押してください。');
  for var Existing in FSessions do if SameText(Existing.Project.Id,FScriptDraft.Id) then
    raise Exception.Create('この作品は動画編集で既に開いています。既存の編集内容を確認してください。');
  var P := FScriptDraft.Clone;
  try
    MaterializeScriptClosing(P); P.EnableComposition; ValidateCompositionMaterials(P);
    for var C in P.Cues do if not P.AudioReady(C) then raise Exception.Create('音声変更を確認してください。');
    P.WorkflowStage := 'preview'; PsdJson.Put(P.ScriptWizard,'stage','editor'); PsdJson.Put(P.ScriptWizard,'furthestStage','editor'); P.Changed;
    StoreScript(P,'editor'); // 内容と再開先を同時に保存してから画面を切り替える。
  finally P.Free; end;
  var Delivered := FScriptDraft; var Session := TRigmMovieSession.Create; var EditorCopy := Delivered.Clone;
  try Session.SetProject(EditorCopy); EditorCopy := nil; FSessions.Add(Session); FActive := Session; Session := nil;
  finally EditorCopy.Free; Session.Free; end;
  FScriptSavedHashes.Remove(Delivered.Id); FScriptDraft := nil; FScriptViewStage := ''; FScriptDrafts.Remove(Delivered);
  ScriptChanged; if Assigned(FOnNavigate) then FOnNavigate(Self,apMovieEdit,'');
end;
