// 動画編集の正本を保存して台本へ引き渡す。動画側の借用ビューを先に閉じ、正本を二重に保持しない。
function TRigmWizardWorkspace.CanReturnMovieToScript: Boolean;
begin
  Result := (FActive<>nil) and (FActive.Project.ScriptWizard<>nil);
end;
procedure TRigmWizardWorkspace.ReturnMovieToScript;
begin
  if not CanReturnMovieToScript then raise Exception.Create('台本作成から開いた動画作品を選んでください。');
  var Session := FActive; Session.Poll;
  if Session.GuiLocked then raise Exception.Create('編集ロックを解除してから台本編集へ戻ってください。');
  if Session.Busy or VoiceBusy then raise Exception.Create('処理が完了するか、中止してから台本編集へ戻ってください。');
  var Path := ScriptPath(Session.Project);
  if not SameText(Session.Project.FileName,Path) or not FileExists(Path) then
    raise Exception.Create('台本のUIDフォルダに保存された作品から台本編集へ戻ってください。');
  if (FScriptDraft<>nil) and FScriptDraft.Modified then SaveScriptDraft(False);
  var Snapshot := Session.Project.Clone;
  try
    PsdJson.Put(Snapshot.ScriptWizard,'stage','text');
    PsdJson.Put(Snapshot.ScriptWizard,'furthestStage','editor');
    PsdJson.Put(Snapshot.ScriptWizard,'titleInput',Snapshot.Title);
    PsdJson.Put(Snapshot.ScriptWizard,'updatedAt',ScriptUtcNow);
    // 動画側でセリフを変更した場合も内容を保持し、前工程の確認済み状態だけを解除する。
    if (Snapshot.ScriptWizard.GetValue('casting') is TJSONObject) and
      (JS(JO(Snapshot.ScriptWizard,'casting'),'fingerprint')<>CastingFingerprint(Snapshot)) then
      InvalidateScriptCasting(Snapshot);
    if Snapshot.ScriptWizard.GetValue('scenes')<>nil then SyncScriptScenesStatus(Snapshot);
    Snapshot.Changed; CheckScript(Snapshot);
    SaveMovie(Snapshot,Path,False);
    var Hash := THashSHA2.GetHashStringFromFile(Path);
    // 保存に失敗した場合は、動画・ビュー・台本下書きの所有関係を一切変更しない。
    if Assigned(FOnMovieSessionClosing) then FOnMovieSessionClosing(Session);
    FActive := nil; FSessions.Remove(Session);
    for var I := FScriptDrafts.Count-1 downto 0 do if SameText(FScriptDrafts[I].Id,Snapshot.Id) then begin
      if FScriptDraft=FScriptDrafts[I] then FScriptDraft := nil;
      FScriptDrafts.Delete(I);
    end;
    FScriptDrafts.Add(Snapshot); FScriptDraft := Snapshot; Snapshot := nil;
    FScriptViewStage := 'text'; FScriptSavedHashes.AddOrSetValue(FScriptDraft.Id,Hash);
    StopVoice; ScriptChanged;
    if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,'');
  finally Snapshot.Free; end;
end;
