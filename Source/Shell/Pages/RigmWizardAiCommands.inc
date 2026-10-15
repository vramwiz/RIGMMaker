// 外部Codex/Dotsからも、GUIと同じAI処理を呼ぶ。入力ID・版は開始/中止で照合する。
function TRigmWizardWorkspace.AiCommand(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Name<>'script-ai-status' then begin
    if (FScriptDraft=nil) or (JS(Args,'projectId')<>FScriptDraft.Id)
      or (JI(Args,'revision',-1)<>FScriptDraft.Revision) then
      raise Exception.Create('script-statusの現在のprojectId/revisionを指定してください。');
    if Name='script-ai-expressions-start' then begin
      if SceneImageAiBusy then raise Exception.Create('画像生成の終了を待ってください。');
      StartExpressionAi;
    end else if Name='script-ai-expressions-cancel' then CancelExpressionAi
    else if Name='script-ai-images-start' then begin
      if ExpressionAiBusy then raise Exception.Create('表情設定の終了を待ってください。');
      StartSceneImageAi(JS(Args,'sceneId'));
    end else if Name='script-ai-images-cancel' then CancelSceneImageAi
    else raise Exception.Create('Unknown AI command');
  end;
  Result := TJSONObject.Create;
  if FScriptDraft<>nil then Result.AddPair('projectId',FScriptDraft.Id).AddPair('revision',TJSONNumber.Create(FScriptDraft.Revision));
  Result.AddPair('expressions',TJSONObject.Create.AddPair('busy',TJSONBool.Create(ExpressionAiBusy))
    .AddPair('message',ExpressionAiMessage).AddPair('logPath',FExpressionAiLog));
  Result.AddPair('images',TJSONObject.Create.AddPair('busy',TJSONBool.Create(SceneImageAiBusy))
    .AddPair('message',SceneImageAiMessage).AddPair('logPath',FImageAiLog));
end;
