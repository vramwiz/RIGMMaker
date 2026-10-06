// 共通scene正本、検証済み画像転送、既存previewジョブを台本ページで利用する。
procedure TRigmWizardWorkspace.SelectScriptScene(const Id: string);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('シーン工程で操作してください。'); RequireScriptScenes(FScriptDraft);
  if FScriptDraft.Scene(Id)=nil then raise Exception.Create('シーンがありません。');
  if JS(JO(FScriptDraft.ScriptWizard,'scenes'),'selectedScene')=Id then Exit;
  PsdJson.Put(JO(FScriptDraft.ScriptWizard,'scenes'),'selectedScene',Id); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.MoveScriptScene(Delta: Integer);
begin var S := FScriptDraft.Scene(JS(JO(FScriptDraft.ScriptWizard,'scenes'),'selectedScene')); SelectScriptScene(FScriptDraft.Scenes[EnsureRange(FScriptDraft.Scenes.IndexOf(S)+Delta,0,FScriptDraft.Scenes.Count-1)].Id); end;
procedure TRigmWizardWorkspace.EditScriptScene(const Id,Description,Prompt,Mode: string);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('シーン工程で操作してください。');
  var S := FScriptDraft.Scene(Id); if S=nil then raise Exception.Create('シーンがありません。');
  if (S.Description=NormalizeScriptText(Description)) and (S.ImagePrompt=NormalizeScriptText(Prompt)) and (S.DisplayMode=Mode) then Exit;
  RigmScriptScenesModel.EditScriptScene(FScriptDraft,Id,Description,Prompt,Mode); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.AdoptScriptSceneImage(const Id,Path: string);
begin
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then raise Exception.Create('シーン入力を完了してから画像を採用してください。'); RequireScriptScenes(FScriptDraft);
  var S := FScriptDraft.Scene(Id); if S=nil then raise Exception.Create('シーンがありません。');
  if not MatchText(ExtractFileExt(Path),['.png','.jpg','.jpeg','.bmp']) or (TFile.GetSize(Path)>RigmImageMaxBytes) then raise Exception.Create('32MB以内のPNG/JPEG/BMPを選んでください。');
  var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite); var Picture := TPicture.Create;
  try
    Picture.LoadFromFile(Path);
    if (Picture.Width<1) or (Picture.Height<1) or (Picture.Width>8192) or (Picture.Height>8192) or (Int64(Picture.Width)*Picture.Height>16777216) then raise Exception.Create('画像は8192px/辺、16MP以内です。');
    var Copied := CopyMovieImage(FScriptDraft,Path,TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Images')); if S.Image=Copied then Exit; S.Image := Copied;
  finally Picture.Free; Guard.Free; end;
  PsdJson.Put(FScriptDraft.ScriptWizard,'scenesStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.RequestScriptSceneImage(const Id: string);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('シーン工程で操作してください。');
  RigmScriptScenesModel.RequestScriptSceneImage(FScriptDraft,Id); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CancelScriptSceneImage(const Id: string);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('シーン工程で操作してください。'); var R := ScriptSceneRequest(FScriptDraft,Id); if R=nil then Exit;
  PsdJson.Put(R,'state','cancelled');
  for var Key in FSceneContracts.Keys.ToArray do if JS(FSceneContracts[Key],'sceneId')=Id then begin
    var A := TJSONObject.Create;
    try A.AddPair('transferId',Key); var Reply := FScriptTransfers.Execute('image-transfer-cancel',A); Reply.Free; finally A.Free; end;
    FSceneContracts.Remove(Key);
  end;
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteScriptScenes;
begin
  RequireScriptScenes(FScriptDraft); if not ScriptScenesReady(FScriptDraft) then raise Exception.Create('画像・説明文・表示方法を各シーンで確認してください。不要なら表示なしを選べます。');
  PsdJson.Put(FScriptDraft.ScriptWizard,'scenesStatus','complete'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ScenePreviewKey: string;
begin
  Result := ''; if (FScriptDraft=nil) or (FScriptDraft.ScriptWizard=nil) or (FScriptDraft.ScriptWizard.GetValue('scenes')=nil) then Exit;
  Result := FScriptDraft.Id+'|'+FScriptDraft.Revision.ToString+'|'+JS(JO(FScriptDraft.ScriptWizard,'scenes'),'selectedScene');
end;
procedure TRigmWizardWorkspace.PreviewScriptScene(Force: Boolean);
begin
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then Exit; RequireScriptScenes(FScriptDraft);
  var Key := ScenePreviewKey; if not Force and (Key=FSceneJobKey) and (FSceneJob<>nil) then Exit;
  if FSceneJob<>nil then begin FSceneJob.Cancel; FSceneRetired.Add(FSceneJob); FSceneJob := nil; end;
  var Id := JS(JO(FScriptDraft.ScriptWizard,'scenes'),'selectedScene'); var Time := ScriptSceneStart(FScriptDraft,Id)+Min(0.05,FScriptDraft.SceneDuration(FScriptDraft.Scene(Id))/2);
  var Path := FPipe.Workspace.Resolve('Cache\ScriptScenes\'+THashSHA2.GetHashString(FScriptDraft.Id)+'\'+PsdJson.NewId+'.png',False); ForceDirectories(ExtractFilePath(Path));
  // 保存済みキャラ配置から共通合成を作るのは描画コピーだけ。台本正本を再配置しない。
  var PreviewProject := FScriptDraft.Clone;
  try PreviewProject.EnableComposition; FSceneJob := TRigmMovieJob.Create(PreviewProject,'preview',Path,Time); finally PreviewProject.Free; end;
  FSceneJobKey := Key; FSceneCollected := False; FSceneError := ''; FSceneJob.Start;
end;
procedure TRigmWizardWorkspace.PollScriptScenes;
begin
  for var I := FSceneRetired.Count-1 downto 0 do if FSceneRetired[I].Done then FSceneRetired.Delete(I);
  if (FSceneJob=nil) or not FSceneJob.Done or FSceneCollected then Exit; FSceneCollected := True;
  var Status := FSceneJob.Status;
  try
    if FSceneJobKey=ScenePreviewKey then begin
      FSceneError := JS(Status,'error');
      if JS(Status,'state')='succeeded' then begin FSceneBitmap.Free; FSceneBitmap := FSceneJob.TakeFrame; FSceneFrameKey := FSceneJobKey; FScenePreviewPath := FSceneJob.Output; end;
      ScriptChanged;
    end;
  finally Status.Free; end;
end;
function TRigmWizardWorkspace.ScenePreview: Vcl.Graphics.TBitmap;
begin Result := nil; if ScenePreviewKey=FSceneFrameKey then Result := FSceneBitmap; end;
function TRigmWizardWorkspace.ScriptScenePreviewStatus: TJSONObject;
begin
  Result := TJSONObject.Create; AddB(Result,'current',ScenePreviewKey=FSceneFrameKey); Result.AddPair('error',FSceneError);
  if ScenePreviewKey=FSceneFrameKey then Result.AddPair('path',FScenePreviewPath); if FSceneJob<>nil then begin Result.AddPair('job',FSceneJob.Status); AddN(Result,'characterCount',FSceneJob.Project.Characters.Count); end;
end;
function TRigmWizardWorkspace.ReadScriptScenes(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionでシーンを取得してください。');
  Result := ScriptScenesSummary(FScriptDraft); Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision);
  var A := TJSONArray.Create; Result.AddPair('rows',A); var Offset := EnsureRange(JI(Args,'offset'),0,FScriptDraft.Scenes.Count);
  if Offset<FScriptDraft.Scenes.Count then begin
    var S := FScriptDraft.Scenes[Offset]; var O := S.Json; A.AddElement(O); AddN(O,'sceneNumber',Offset+1); AddN(O,'start',ScriptSceneStart(FScriptDraft,S.Id)); AddN(O,'duration',FScriptDraft.SceneDuration(S));
    AddB(O,'ready',ScriptSceneReady(FScriptDraft,S)); O.AddPair('imagePath',ResolveMoviePath(FScriptDraft.FileName,S.Image));
    var Cues := TJSONArray.Create; O.AddPair('sourceCues',Cues); var Count := 0;
    for var C in FScriptDraft.Cues do if C.Scene=S.Id then begin Inc(Count); if Cues.Count>=10 then Continue; var Row := TJSONObject.Create; Row.AddPair('cueId',C.Id); Row.AddPair('sourceText',C.Text); Cues.AddElement(Row); end;
    AddN(O,'cueCount',Count); AddB(O,'hasMoreCues',Count>Cues.Count);
    var R := ScriptSceneRequest(FScriptDraft,S.Id); if R<>nil then begin var Request := R.Clone as TJSONObject; var Key := JS(R,'fingerprint'); if JS(R,'state')='adopted' then Key := JS(R,'adoptedFingerprint'); AddB(Request,'current',Key=ScriptSceneFingerprint(FScriptDraft,S.Id)); O.AddPair('imageRequest',Request); end;
  end;
  AddN(Result,'nextOffset',Offset+A.Count); AddB(Result,'hasMore',Offset+A.Count<FScriptDraft.Scenes.Count);
  Result.AddPair('preview',ScriptScenePreviewStatus);
end;
function TRigmWizardWorkspace.ExecuteScriptImageTransfer(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if MatchText(Name,['image-transfer-begin','image-transfer-adopt']) then begin
    if FScriptTextEditing or FPlacementEditing or (CurrentScriptStage<>'scenes') then raise Exception.Create('GUI入力を完了してから画像を取得・採用してください。');
    if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで画像を取得・採用してください。');
  end;
  if Name='image-transfer-begin' then begin
    var Id := JS(Args,'sceneId'); RequireSceneImageRequest(FScriptDraft,Id,JS(Args,'requestId'));
    var Provenance := JS(Args,'provenance'); if not MatchStr(Provenance,['external-generated','existing-material','test-fixture']) then raise Exception.Create('画像の由来を指定してください。');
    Result := FScriptTransfers.BeginTransfer(FScriptDraft,Args); var Contract := TJSONObject.Create;
    Contract.AddPair('sceneId',Id); Contract.AddPair('requestId',JS(Args,'requestId')); Contract.AddPair('fingerprint',ScriptSceneFingerprint(FScriptDraft,Id)); Contract.AddPair('projectId',FScriptDraft.Id);
    Contract.AddPair('provenance',Provenance);
    FSceneContracts.Add(JS(Result,'transferId'),Contract); Exit;
  end;
  if Name='image-transfer-adopt' then begin
    var Contract: TJSONObject; if not FSceneContracts.TryGetValue(JS(Args,'transferId'),Contract) then raise Exception.Create('画像転送の要求契約がありません。');
    var Id := JS(Contract,'sceneId'); RequireSceneImageRequest(FScriptDraft,Id,JS(Args,'requestId'));
    if (JS(Args,'requestId')<>JS(Contract,'requestId')) or (JS(Contract,'projectId')<>FScriptDraft.Id) or (JS(Contract,'fingerprint')<>ScriptSceneFingerprint(FScriptDraft,Id)) then raise Exception.Create('取得後にシーンが変わりました。古い画像は採用しません。');
    var ReceivedId: string; var Path := FScriptTransfers.ReadyPath(FScriptDraft,Args,ReceivedId); if ReceivedId<>Id then raise Exception.Create('画像の対象シーンが異なります。');
    FScriptDraft.Scene(Id).Image := Path; var R := ScriptSceneRequest(FScriptDraft,Id); PsdJson.Put(R,'state','adopted'); R.AddPair('imageProvenance',JS(Contract,'provenance')); R.AddPair('adoptedFingerprint',ScriptSceneFingerprint(FScriptDraft,Id));
    FScriptTransfers.Adopted(Args); FSceneContracts.Remove(JS(Args,'transferId')); PsdJson.Put(FScriptDraft.ScriptWizard,'scenesStatus','in-progress'); FScriptDraft.Changed; ScriptChanged;
    Result := FScriptTransfers.Execute('image-transfer-status',Args); AddN(Result,'revision',FScriptDraft.Revision); Exit;
  end;
  Result := FScriptTransfers.Execute(Name,Args);
end;
procedure TRigmWizardWorkspace.SetScriptSummaryChoice(const Choice: string);
begin
  if (CurrentScriptStage<>'summary') or not MatchStr(Choice,['none','yes']) then raise Exception.Create('総評の有無を選択してください。');
  if JS(FScriptDraft.ScriptWizard,'summaryChoice')=Choice then Exit;
  if Choice='none' then begin DisableScriptSummary(FScriptDraft); FScriptDraft.ScriptWizard.RemovePair('voiceReturnStage').Free; end;
  PsdJson.Put(FScriptDraft.ScriptWizard,'summaryChoice',Choice); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptSummaryDraft(Draft: TJSONObject);
begin
  if CurrentScriptStage<>'summary-edit' then raise Exception.Create('総評入力工程で操作してください。');
  var Before := JO(FScriptDraft.ScriptWizard,'summaryData').ToJSON; RigmScriptSummaryModel.SetScriptSummaryDraft(FScriptDraft,Draft); if Before=JO(FScriptDraft.ScriptWizard,'summaryData').ToJSON then Exit; FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CompleteScriptSummary;
begin
  if (CurrentScriptStage<>'summary-edit') or FScriptTextEditing then raise Exception.Create('総評入力を完了してください。'); var Copy := FScriptDraft.Clone;
  try MaterializeScriptSummary(Copy); finally Copy.Free; end; PsdJson.Put(JO(FScriptDraft.ScriptWizard,'summaryData'),'status','complete'); FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ReadScriptSummary(Args: TJSONObject): TJSONObject;
begin
  if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id) or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then raise Exception.Create('最新projectId/revisionで総評を取得してください。');
  Result := TJSONObject.Create; Result.AddPair('projectId',FScriptDraft.Id); AddN(Result,'revision',FScriptDraft.Revision); Result.AddPair('choice',JS(FScriptDraft.ScriptWizard,'summaryChoice'));
  if FScriptDraft.ScriptWizard.GetValue('summaryData') is TJSONObject then begin var Data := JO(FScriptDraft.ScriptWizard,'summaryData').Clone as TJSONObject; for var Key in ['appliedDraft','archivedCue','archivedScene'] do Data.RemovePair(Key).Free; Result.AddPair('data',Data); end;
  var Cue := ScriptSummaryCue(FScriptDraft); if Cue<>nil then begin var Brief := TJSONObject.Create; Brief.AddPair('cueId',Cue.Id); Brief.AddPair('sceneId',Cue.Scene); AddN(Brief,'role',ScriptCueRole(FScriptDraft,Cue.Id)); Brief.AddPair('waveFile',Cue.WaveFile); Brief.AddPair('labFile',Cue.LabFile); AddN(Brief,'audioSeconds',Cue.AudioSeconds); Result.AddPair('cue',Brief); AddB(Result,'audioReady',FScriptDraft.AudioReady(Cue)); end;
end;
