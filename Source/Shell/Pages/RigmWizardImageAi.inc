// 画像1枚ごとに受信・検査・管理コピーしてから、次の固定IDへ進む。確定は人間が行う。
procedure TRigmWizardWorkspace.AddScriptImageCharacterPreviews(Sources: TJSONObject);
begin
  for var V in JA(Sources,'characters') do begin
    var C := TJSONObject(V); var FileName := Thumbnails.ReferencePng(JS(C,'path'));
    AddB(C,'previewReady',FileName<>'');
    if FileName='' then Continue;
    PsdJson.Put(C,'previewPath',FileName);
  end;
end;
function TRigmWizardWorkspace.SceneImageAiBusy: Boolean;
begin Result := FImageAiTargets<>nil; end;
function TRigmWizardWorkspace.SceneImageAiMessage: string;
begin
  Result := '';
  if SceneImageAiBusy or ((FScriptDraft<>nil) and (FScriptDraft.Id=FImageAiProjectId)) then Result := FImageAiMessage;
end;
procedure TRigmWizardWorkspace.StartSceneImageAi(const Id: string);
begin
  if SceneImageAiBusy then raise Exception.Create('画像生成は処理中です。');
  if ExpressionAiBusy then raise Exception.Create('表情設定の終了を待ってください。');
  if (FScriptDraft=nil) or (CurrentScriptStage<>'scenes') or (FPipe=nil) then raise Exception.Create('画像工程で作品を開いてください。');
  FImageAiTargets := RigmScriptAiImages.SceneImageAiTargets(FScriptDraft,Id);
  FImageAiProjectId := FScriptDraft.Id; FImageAiIndex := 0; FImageAiCompleted := 0;
  FImageAiSucceeded := False;
  FImageAiCancel := ''; FImageAiLog := ''; FImageAiMessage := '画像生成を準備しています';
  // 要求作成とワーカー起動はPollで行い、最初に処理中UIを描画する。
  ScriptChanged;
end;
procedure TRigmWizardWorkspace.CancelSceneImageAi;
begin
  if not SceneImageAiBusy then Exit;
  FImageAiCancel := '画像生成を中止しました。受信済みの画像は保持しています。';
  if FImageAiJob<>nil then FImageAiJob.Terminate;
  FImageAiMessage := '画像生成を中止しています'; ScriptChanged;
end;
procedure TRigmWizardWorkspace.FinishSceneImageAi(const Message: string);
begin
  // 同じ作品・同じ未完了要求だけを終了する。別作品や作り直した要求へ触れない。
  if (FImageAiRequest<>nil) and (FScriptDraft<>nil) and (FScriptDraft.Id=FImageAiProjectId) then begin
    var R := ScriptSceneRequest(FScriptDraft,JS(FImageAiRequest,'sceneId'));
    if (R<>nil) and (JS(R,'requestId')=JS(FImageAiRequest,'requestId')) and (JS(R,'state')='pending') then begin
      PsdJson.Put(R,'state','cancelled'); FScriptDraft.Changed;
    end;
  end;
  FreeAndNil(FImageAiJob); FreeAndNil(FImageAiRequest); FreeAndNil(FImageAiTargets);
  FImageAiMessage := Message; ScriptChanged;
end;
procedure TRigmWizardWorkspace.PrepareSceneImageAi;
var References: TJSONArray; Paths: TList<string>; Folder: string;
  procedure AddReference(const Kind,Source: string);
  begin
    if Source='' then Exit;
    var Full := ResolveMoviePath(FScriptDraft.FileName,Source);
    var Hash := CheckedMovieImageHash(Full);
    for var V in References do if JS(TJSONObject(V),'sha256')=Hash then Exit;
    var CopyPath := CopyCheckedMovieImage(Full,TPath.Combine(Folder,'References'),Hash);
    References.AddElement(TJSONObject.Create.AddPair('kind',Kind).AddPair('path',CopyPath).AddPair('sha256',Hash));
    Paths.Add(CopyPath);
  end;
begin
  var Target := TJSONObject(FImageAiTargets[FImageAiIndex]); var Id := JS(Target,'sceneId');
  if (JS(Target,'contextFingerprint')<>RigmScriptAiImages.SceneImageAiContextKey(FScriptDraft)) or
    (JS(Target,'fingerprint')<>ScriptSceneFingerprint(FScriptDraft,Id)) then
    raise Exception.Create('処理中に画像要望・作品情報が変わりました。入力を保持して停止しました。');
  if FImageAiRequest=nil then begin
    FImageAiRequest := RigmScriptScenesModel.RequestScriptSceneImage(FScriptDraft,Id).Clone as TJSONObject;
    FScriptDraft.Changed; FImageAiPreparedAt := GetTickCount64;
    FImageAiMessage := Format('%d / %d：画像の参照素材を準備しています',[FImageAiIndex+1,FImageAiTargets.Count]);
    ScriptChanged;
  end;
  RequireSceneImageRequest(FScriptDraft,Id,JS(FImageAiRequest,'requestId'));
  Folder := FPipe.Workspace.Resolve('Exchange\CodexImages\'+JS(FImageAiRequest,'requestId'),False);
  ForceDirectories(Folder);
  // 既存のサムネイルAPIが用意する透過キャラPNGを使用し、元rigm/psdを直接送らない。
  if Id<>RigmCommonBackgroundId then begin
    var Sources: TJSONObject;
    if Id=RigmThumbnailId then Sources := JO(FImageAiRequest,'sources').Clone as TJSONObject
    else begin Sources := TJSONObject.Create; var AllSources := ThumbnailSources(FScriptDraft);
      try Sources.AddPair('characters',JA(AllSources,'characters').Clone as TJSONArray); finally AllSources.Free; end;
    end;
    try
      AddScriptImageCharacterPreviews(Sources);
      for var V in JA(Sources,'characters') do if not JB(TJSONObject(V),'previewReady') then begin
        if GetTickCount64-FImageAiPreparedAt>30000 then raise Exception.Create('キャラ参照画像の準備が完了しません。素材を確認して再実行してください。');
        Exit;
      end;
      PsdJson.Put(FImageAiRequest,'sources',Sources.Clone as TJSONObject);
    finally Sources.Free; end;
  end;
  References := TJSONArray.Create; Paths := TList<string>.Create;
  try
    var Scene := FScriptDraft.ImageTarget(Id); AddReference('current',Scene.Image);
    if Id=RigmThumbnailId then begin
      for var V in JA(JO(FImageAiRequest,'sources'),'images') do AddReference('source',JS(TJSONObject(V),'path'));
    end else if Id<>RigmCommonBackgroundId then begin
      var Index := FScriptDraft.Scenes.IndexOf(Scene);
      if Index>0 then AddReference('previous-scene',FScriptDraft.Scenes[Index-1].Image);
      AddReference('background',FScriptDraft.ThemeBackground);
    end;
    if Id<>RigmCommonBackgroundId then for var V in JA(JO(FImageAiRequest,'sources'),'characters') do AddReference('character',JS(TJSONObject(V),'previewPath'));
    // 参照は要求フォルダへ固定コピー。保存や次画像の採用でパスが変わっても入力を保持する。
    FImageAiJob := TRigmCodexJob.CreateImage(RigmScriptAiImages.SceneImageAiPrompt(FScriptDraft,FImageAiRequest,References),Paths.ToArray,Folder);
    FImageAiLog := FImageAiJob.LogPath; FImageAiJob.BeginRun;
  finally References.Free; Paths.Free; end;
end;
procedure TRigmWizardWorkspace.PollSceneImageAi;
begin
  if not SceneImageAiBusy then Exit;
  if ((FScriptDraft=nil) or (FScriptDraft.Id<>FImageAiProjectId) or (CurrentScriptStage<>'scenes')) and (FImageAiCancel='') then begin
    FImageAiCancel := '台本または工程が切り替わったため画像生成を中止しました。受信済み画像は保持しています。';
    if FImageAiJob<>nil then FImageAiJob.Terminate;
  end;
  if (FImageAiJob<>nil) and (WaitForSingleObject(FImageAiJob.Handle,0)<>WAIT_OBJECT_0) then begin
    var Message := '画像生成を中止しています';
    if FImageAiCancel='' then Message := Format('%d / %d：%s',[FImageAiIndex+1,FImageAiTargets.Count,FImageAiJob.Stage]);
    if FImageAiMessage<>Message then begin FImageAiMessage := Message; ScriptChanged; end;
    Exit;
  end;
  if FImageAiCancel<>'' then begin FinishSceneImageAi(FImageAiCancel); Exit; end;
  try
    if FImageAiJob=nil then begin PrepareSceneImageAi; Exit; end;
    if not FImageAiJob.Success then raise Exception.Create(FImageAiJob.ErrorText);
    var Target := TJSONObject(FImageAiTargets[FImageAiIndex]);
    if JS(Target,'contextFingerprint')<>RigmScriptAiImages.SceneImageAiContextKey(FScriptDraft) then
      raise Exception.Create('処理中に作品情報が変わりました。画像を適用せず停止しました。');
    var Args := TJSONObject.Create.AddPair('sceneId',JS(FImageAiRequest,'sceneId'))
      .AddPair('requestId',JS(FImageAiRequest,'requestId')).AddPair('path',FImageAiJob.ImagePath)
      .AddPair('sha256',CheckedMovieImageHash(FImageAiJob.ImagePath)).AddPair('provenance','external-generated');
    try DeliverScriptSceneImage(Args); finally Args.Free; end;
    Inc(FImageAiCompleted); Inc(FImageAiIndex); FreeAndNil(FImageAiJob); FreeAndNil(FImageAiRequest);
    if FImageAiIndex>=FImageAiTargets.Count then begin
      FImageAiSucceeded := True;
      FinishSceneImageAi(Format('%d枚の画像を取得しました。表示を確認し、各行の「確定」をチェックしてください。',[FImageAiCompleted])); Exit;
    end;
    FImageAiMessage := Format('%d枚受信済み。次の画像を準備しています',[FImageAiCompleted]); ScriptChanged;
  except on E: Exception do FinishSceneImageAi('画像生成を停止しました：'+E.Message+Format('（受信済み %d 枚は保持）',[FImageAiCompleted])); end;
end;
