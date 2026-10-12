procedure CheckSceneNames;
begin
  var Frame := StageFrame(TRigmScriptScenesFrame) as TRigmScriptScenesFrame; Frame.RefreshState;
  var Row: TRigmSceneImageRow := nil;
  for var I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TRigmSceneImageRow then begin
    var Candidate := TRigmSceneImageRow(Frame.Components[I]);
    if Candidate.SceneId=RigmCommonBackgroundId then Check(not Candidate.SceneName.Visible,'common background has no video scene name input')
    else if Row=nil then Row := Candidate;
  end;
  var Id := Row.SceneId; var S := W.ScriptDraft.Scene(Id); var Approval := S.ImageApprovalKey;
  Check((Row.SceneName.Top+Row.SceneName.Height<Row.Height) and
    (Row.Approved.Height>=MulDiv(24,Row.Approved.CurrentPPI,96)),'name input fits its row and the native confirmation glyph is not clipped');
  Check(Row.SceneName.Visible and not Row.SceneName.ReadOnly and (Row.SceneName.Text=S.Title),'stage 16 offers the existing scene title as an editable initial value');
  var BeforeCues := TJSONArray.Create;
  try
    for var Cue in W.ScriptDraft.Cues do BeforeCues.AddElement(Cue.Json);
    Row.SceneName.Text := '本題：新しい一歩'; Check(Frame.RequestFinish,'native name editor applies a Japanese scene title');
    S := W.ScriptDraft.Scene(Id);
    Check((S.Title='本題：新しい一歩') and S.ImageApproved and (S.ImageApprovalKey=Approval) and ScriptThumbnailSourcesReady(W.ScriptDraft),
      'renaming an approved scene preserves its approval and thumbnail source readiness');
    W.SaveScriptDraft(False); var Saved := LoadMovie(W.ScriptDraft.FileName);
    try Check((Saved.Scene(Id).Title=W.ScriptDraft.Scene(Id).Title) and Saved.Scene(Id).ImageApproved,'saved project reopens with its edited scene name and image approval'); finally Saved.Free; end;
    var A := TJSONObject.Create;
    try
      A.AddPair('projectId',W.ScriptDraft.Id); AddN(A,'revision',W.ScriptDraft.Revision); A.AddPair('sceneId',Id); A.AddPair('title','パイプからの名前');
      A.AddPair('description',W.ScriptDraft.Scene(Id).Description); A.AddPair('prompt',W.ScriptDraft.Scene(Id).ImagePrompt);
      A.AddPair('displayMode',W.ScriptDraft.Scene(Id).DisplayMode); A.AddPair('feedback',W.ScriptDraft.Scene(Id).ImageFeedback);
      var Reply := W.Command('app-script-edit-scene',A); Reply.Free;
      Check(W.ScriptDraft.Scene(Id).Title='パイプからの名前','pipe and native editor share scene name editing after approval');
    finally A.Free; end;
    for var Bad in [StringOfChar('長',301),'改行'+#13#10+'不可'] do begin
      A := TJSONObject.Create;
      try
        A.AddPair('projectId',W.ScriptDraft.Id); AddN(A,'revision',W.ScriptDraft.Revision); A.AddPair('sceneId',Id); A.AddPair('title',Bad);
        var Rejected := False; try var Reply := W.Command('app-script-edit-scene',A); Reply.Free; except on E: Exception do Rejected := True; end;
        Check(Rejected and (W.ScriptDraft.Scene(Id).Title='パイプからの名前'),'invalid scene name is rejected without partial changes');
      finally A.Free; end;
    end;
    A := TJSONObject.Create;
    try
      A.AddPair('projectId',W.ScriptDraft.Id); AddN(A,'revision',W.ScriptDraft.Revision); A.AddPair('sceneId',Id);
      A.AddPair('title','適用されない名前'); A.AddPair('prompt','確定済み画像の変更');
      var Rejected := False; try var Reply := W.Command('app-script-edit-scene',A); Reply.Free; except on E: Exception do Rejected := True; end;
      Check(Rejected and (W.ScriptDraft.Scene(Id).Title='パイプからの名前') and W.ScriptDraft.Scene(Id).ImageApproved,
        'combined name and protected image edits are atomic');
    finally A.Free; end;
    Frame.RefreshState; Row.SceneName.Text := ''; Check(Frame.RequestFinish and (W.ScriptDraft.Scene(Id).Title=''),'blank name remains blank and hides the video title');
    W.SetScriptSceneApproved(Id,False); W.EditScriptScene(Id,'','専用シーン画像','image'); W.RequestScriptSceneImage(Id);
    var Request := JS(ScriptSceneRequest(W.ScriptDraft,Id),'requestId'); var Fingerprint := ScriptSceneFingerprint(W.ScriptDraft,Id);
    Frame.RefreshState; Row.SceneName.Text := '画像要求中のシーン'; Check(Frame.RequestFinish,'scene name can change during image generation');
    RequireSceneImageRequest(W.ScriptDraft,Id,Request);
    Check(ScriptSceneFingerprint(W.ScriptDraft,Id)=Fingerprint,'name edits retain the active image request and fingerprint');
    var Path := TPath.Combine(Root,'Background\named-scene.png'); BgPng(Path,320,180,False);
    BgChunkTransfer(Path,Id,True); W.SetScriptSceneApproved(Id,True); Frame.RefreshState;
    var AfterCues := TJSONArray.Create;
    try for var Cue in W.ScriptDraft.Cues do AfterCues.AddElement(Cue.Json);
      Check(AfterCues.ToJSON=BeforeCues.ToJSON,'scene name editing retains every dialogue, voice and timing value');
    finally AfterCues.Free; end;
    Capture('scene-names-stage16');
  finally BeforeCues.Free; end;
end;
