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
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then raise Exception.Create('画像入力を完了してから採用してください。');
  RequireScriptScenes(FScriptDraft); RequireEditableScriptScene(FScriptDraft,Id);
  var Copied := CopyCheckedMovieImage(Path,TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Images'));
  ApplyScriptSceneImage(FScriptDraft,Id,Copied,''); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.DeliverScriptSceneImage(Args: TJSONObject);
begin
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then raise Exception.Create('画像工程の入力を完了してから再取得してください。');
  var Id := JS(Args,'sceneId'); var RequestId := JS(Args,'requestId');
  RequireSceneImageRequest(FScriptDraft,Id,RequestId);
  var Provenance := JS(Args,'provenance'); if not MatchStr(Provenance,['external-generated','existing-material','test-fixture']) then raise Exception.Create('画像の由来を指定してください。');
  var Hash := JS(Args,'sha256'); if Length(Hash)<>64 then raise Exception.Create('SHA256を指定してください。');
  for var C in Hash do if not CharInSet(C,['0'..'9','a'..'f','A'..'F']) then raise Exception.Create('SHA256は64桁の16進数です。');
  // Keep the existing data-root boundary; Codex places local files in Exchange and sends only metadata.
  var Path := FPipe.Workspace.Resolve(JS(Args,'path'));
  var Copied := CopyCheckedMovieImage(Path,TPath.Combine(ExtractFileDir(ScriptPath(FScriptDraft)),'Images'),Hash);
  RequireSceneImageRequest(FScriptDraft,Id,RequestId);
  ApplyScriptSceneImage(FScriptDraft,Id,Copied,RequestId);
  PsdJson.Put(ScriptSceneRequest(FScriptDraft,Id),'imageProvenance',Provenance);
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.UpdateScriptSceneInputs(Inputs: TJSONArray);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('画像工程で入力してください。');
  if Inputs.Count=0 then Exit; var P := FScriptDraft.Clone;
  try
    for var V in Inputs do begin
      var O := V as TJSONObject; var Id := JS(O,'id');
      RigmScriptScenesModel.EditScriptScene(P,Id,JS(O,'description'),JS(O,'prompt'),JS(O,'mode'));
      RigmScriptScenesModel.EditScriptSceneFeedback(P,Id,JS(O,'feedback'));
    end;
    // Publish all rows only after every value has passed model validation.
    var Old := FScriptDraft.Scenes; FScriptDraft.Scenes := P.Scenes; P.Scenes := Old;
    SyncScriptScenesStatus(FScriptDraft); FScriptDraft.Changed; ScriptChanged;
  finally P.Free; end;
end;
procedure TRigmWizardWorkspace.EditScriptSceneFeedback(const Id,Feedback: string);
begin
  if CurrentScriptStage<>'scenes' then raise Exception.Create('画像工程で操作してください。');
  if FScriptDraft.Scene(Id)=nil then raise Exception.Create('対象シーンがありません。');
  if FScriptDraft.Scene(Id).ImageFeedback=NormalizeScriptText(Feedback) then Exit;
  RigmScriptScenesModel.EditScriptSceneFeedback(FScriptDraft,Id,Feedback); FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.SetScriptSceneApproved(const Id: string; Value: Boolean);
begin
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then raise Exception.Create('入力を完了してから確定チェックを操作してください。');
  // Only the actual GUI checkbox calls this method. No pipe can silently unlock a scene.
  RigmScriptScenesModel.SetScriptSceneApproved(FScriptDraft,Id,Value);
  FScriptDraft.Changed; ScriptChanged;
end;
procedure TRigmWizardWorkspace.RequestUnapprovedScriptImages;
begin
  if (CurrentScriptStage<>'scenes') or FScriptTextEditing then raise Exception.Create('入力を完了してから画像要求を作成してください。');
  RequireScriptScenes(FScriptDraft); var Count := 0;
  for var S in FScriptDraft.Scenes do if not S.ImageApproved and (S.ImagePrompt.Trim<>'') then begin
    RigmScriptScenesModel.RequestScriptSceneImage(FScriptDraft,S.Id); Inc(Count);
  end;
  if Count=0 then raise Exception.Create('要望のある未確定シーンがありません。');
  FScriptDraft.Changed; ScriptChanged;
end;
function TRigmWizardWorkspace.ScriptScenesAdvanceReason: string;
begin
  Result := '';
  if FScriptDraft=nil then Exit('作品を開いてください。');
  if FScriptTextEditing or FPlacementEditing then Exit('画像要望・補足文の入力を完了してください。');
  if VoiceBusy or VoicePlaying or VoiceContinuous then Exit('音声生成・再生を停止してください。');
  if Trim(JS(FScriptDraft.ScriptWizard,'titleInput'))='' then Exit('題名を入力してください。');
  if JS(FScriptDraft.ScriptWizard,'scene-assignmentStatus')<>'complete' then Exit('シーン割当をNextで保存してください。');
  if not ScriptScenesReady(FScriptDraft) then Exit('全シーンの画像を用意し、右端の確定チェックを入れてください。');
  for var C in FScriptDraft.Cues do if not FScriptDraft.AudioReady(C) then Exit('音声変更を確認してください。');
  Result := CastingAdvanceReason(False);
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
  RequireScriptScenes(FScriptDraft); if not ScriptScenesReady(FScriptDraft,True) then raise Exception.Create('全シーンの画像と右端の確定チェックを確認してください。');
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
  while (Offset<FScriptDraft.Scenes.Count) and JB(Args,'unapprovedOnly') and FScriptDraft.Scenes[Offset].ImageApproved do Inc(Offset);
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
    ApplyScriptSceneImage(FScriptDraft,Id,Path,JS(Args,'requestId')); var R := ScriptSceneRequest(FScriptDraft,Id); PsdJson.Put(R,'imageProvenance',JS(Contract,'provenance'));
    FScriptTransfers.Adopted(Args); FSceneContracts.Remove(JS(Args,'transferId')); SyncScriptScenesStatus(FScriptDraft); FScriptDraft.Changed; ScriptChanged;
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
