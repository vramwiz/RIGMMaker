// 専用Codexによる表情の一括設定。ジョブの結果はWorkspaceのメインスレッドで回収する。
function TRigmWizardWorkspace.ExpressionAiBusy: Boolean;
begin Result := FExpressionAiJob<>nil; end;
function TRigmWizardWorkspace.ExpressionAiMessage: string;
begin
  Result := '';
  if ExpressionAiBusy or ((FScriptDraft<>nil) and (FScriptDraft.Id=FExpressionAiProjectId)) then Result := FExpressionAiMessage;
end;
procedure TRigmWizardWorkspace.StartExpressionAi;
begin
  if ExpressionAiBusy then raise Exception.Create('AIの表情設定は処理中です。');
  if SceneImageAiBusy then raise Exception.Create('画像生成の終了を待ってください。');
  if (FScriptDraft=nil) or (CurrentScriptStage<>'casting') then raise Exception.Create('配役工程でAIの表情設定を実行してください。');
  if FPipe=nil then raise Exception.Create('台本の保存先が準備されていません。');
  var Request := RigmScriptAiExpressions.CreateExpressionRequest(FScriptDraft);
  var Schema: TJSONObject := nil;
  try
    Schema := RigmScriptAiExpressions.ExpressionOutputSchema(Request);
    var Folder := FPipe.Workspace.Resolve('Exchange\CodexExpressions\'+JS(Request,'requestId'),False);
    FExpressionAiJob := TRigmCodexJob.Create(RigmScriptAiExpressions.ExpressionPrompt(Request),Schema,Folder);
    FExpressionAiRequest := Request; Request := nil;
    FExpressionAiProjectId := FScriptDraft.Id; FExpressionAiCancel := '';
    FExpressionAiLog := FExpressionAiJob.LogPath;
    FExpressionAiSucceeded := False;
    FExpressionAiMessage := JA(FExpressionAiRequest,'cues').Count.ToString+'件の表情をAIにまとめて依頼しています';
    FExpressionAiJob.BeginRun;
  except
    FreeAndNil(FExpressionAiJob); FreeAndNil(FExpressionAiRequest);
    Schema.Free; Request.Free; raise;
  end;
  Schema.Free; ScriptChanged;
end;
procedure TRigmWizardWorkspace.CancelExpressionAi;
begin
  if not ExpressionAiBusy then Exit;
  FExpressionAiCancel := 'AIの表情設定を中止しました。表情は変更していません。';
  FExpressionAiJob.Terminate; FExpressionAiMessage := 'AIの表情設定を中止しています'; ScriptChanged;
end;
procedure TRigmWizardWorkspace.PollExpressionAi;
begin
  if FExpressionAiJob=nil then Exit;
  if ((FScriptDraft=nil) or (FScriptDraft.Id<>FExpressionAiProjectId) or (CurrentScriptStage<>'casting'))
    and (FExpressionAiCancel='') then begin
    FExpressionAiCancel := '台本または工程が切り替わったため、AIの表情設定を中止しました。';
    FExpressionAiJob.Terminate;
  end;
  if WaitForSingleObject(FExpressionAiJob.Handle,0)<>WAIT_OBJECT_0 then begin
    var Message := 'AIの表情設定を中止しています';
    if FExpressionAiCancel='' then Message := JA(FExpressionAiRequest,'cues').Count.ToString+'件：'+FExpressionAiJob.Stage;
    if FExpressionAiMessage<>Message then begin FExpressionAiMessage := Message; ScriptChanged; end;
    Exit;
  end;
  try
    if FExpressionAiCancel<>'' then FExpressionAiMessage := FExpressionAiCancel
    else if not FExpressionAiJob.Success then FExpressionAiMessage := 'AIの表情設定に失敗しました：'+FExpressionAiJob.ErrorText
    else begin
      var Value := TJSONObject.ParseJSONValue(FExpressionAiJob.Answer);
      try
        if not (Value is TJSONObject) then raise Exception.Create('AIの判定結果がJSONオブジェクトではありません。');
        var Count := RigmScriptAiExpressions.ApplyExpressionResponse(FScriptDraft,FExpressionAiRequest,TJSONObject(Value));
        FExpressionAiSucceeded := True;
        if Count>0 then FScriptDraft.Changed;
        FExpressionAiMessage := '全'+JA(FExpressionAiRequest,'cues').Count.ToString+'件の判定が完了しました。'+
          Count.ToString+'件の表情を設定しました。';
      finally Value.Free; end;
    end;
  except on E: Exception do FExpressionAiMessage := E.Message; end;
  FreeAndNil(FExpressionAiJob); FreeAndNil(FExpressionAiRequest); ScriptChanged;
end;
