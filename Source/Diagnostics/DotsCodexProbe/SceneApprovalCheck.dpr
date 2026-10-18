program SceneApprovalCheck;
{$APPTYPE CONSOLE}
// 実台本は読取専用。メモリ上のコピーで字幕変更・旧確定・画像変更の判定を検証する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, Vcl.Forms,
  RigmMovieModel, RigmMovieComposition, RigmJson, PsdJson,
  RigmScriptScenesModel, RigmScriptThumbnailModel, RigmScriptCastingModel,
  RigmScriptScenesFrame, RigmWizardWorkspace;
var Checks: TJSONArray; Output,Error: string;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); Writeln('PASS ',Message); end;
procedure RefreshCasting(Project: TRigmMovieProject);
begin
  var Key := CastingFingerprint(Project);
  PsdJson.Put(JO(Project.ScriptWizard,'casting'),'fingerprint',Key);
  PsdJson.Put(JO(Project.ScriptWizard,'scenes'),'castingFingerprint',Key);
end;
procedure CheckFrame(const Source,OriginalPath: string);
begin
  var Data := TPath.Combine(Output,'FrameData'); var P := LoadMovie(Source);
  var Owned := TPath.Combine(Data,'Projects\'+P.Id+'\project.rigmovie');
  try
    // JSONと絶対参照だけの所有fixture。利用者の素材を複製・書き換えない。
    for var S in P.Scenes do if S.Image<>'' then S.Image := ResolveMoviePath(OriginalPath,S.Image);
    P.CommonBackground.Image := ResolveMoviePath(OriginalPath,P.CommonBackground.Image);
    P.ThemeBackground := P.CommonBackground.Image;
    P.Thumbnail.Image := ResolveMoviePath(OriginalPath,P.Thumbnail.Image);
    PsdJson.Put(P.ScriptWizard,'stage','scenes');
    ForceDirectories(ExtractFileDir(Owned)); var O := P.Json;
    try TFile.WriteAllText(Owned,O.ToJSON,TEncoding.UTF8); finally O.Free; end;
  finally P.Free; end;
  var W := TRigmWizardWorkspace.Create(nil);
  try
    W.StartPipe(Data); W.OpenScriptDraft(Owned);
    var Form := TForm.CreateNew(nil);
    try
      var Frame := TRigmScriptScenesFrame.CreateForWorkspace(Form,W); Frame.SetActive(True);
      var Row: TRigmSceneImageRow := nil;
      for var I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TRigmSceneImageRow then begin
        var Candidate := TRigmSceneImageRow(Frame.Components[I]);
        if Candidate.SceneId='{EA7C3A1F-4301-4EA5-B2B7-7F933E76804C}' then Row := Candidate;
      end;
      Check(Row<>nil,'frame contains the affected introduction row');
      Check(not Row.Approved.Checked and (Row.Approved.Caption='再確認'),'stale approval is visibly unchecked and labelled for reconfirmation');
      var State := W.ScriptStatus;
      try Check(Pos('作品紹介',JS(State,'advanceBlockedReason'))>0,'blocked navigation identifies the exact scene'); finally State.Free; end;
      var Before := W.ScriptDraft.Json;
      try
        Row.Approved.Checked := True; // VCLのOnClickからRequestFinishとWorkspaceを通す。
        Check(Row.Approved.Checked and ScriptSceneReady(W.ScriptDraft,W.ScriptDraft.Scene(Row.SceneId),True),
          'one checkbox event applies inputs and refreshes stale approval');
        var After := W.ScriptDraft.Json;
        try Check(JA(Before,'cues').ToJSON=JA(After,'cues').ToJSON,'checkbox event preserves every dialogue and voice record'); finally After.Free; end;
      finally Before.Free; end;
    finally Form.Free; end;
  finally W.Free; end;
end;
procedure Run;
begin
  var Source := ParamStr(1); Output := ParamStr(2); ForceDirectories(Output);
  var OriginalHash := THashSHA2.GetHashStringFromFile(Source);
  var P := LoadMovie(Source);
  try
    // 保存前の採取JSONを使い、相対素材だけを元作品の場所で解決する。書き込みは行わない。
    if ParamStr(3)<>'' then P.FileName := ParamStr(3);
    var S := P.Scene('{EA7C3A1F-4301-4EA5-B2B7-7F933E76804C}');
    Check((S<>nil) and S.ImageApproved and not ScriptSceneReady(P,S,True),'reproduce checked image with stale approval after dialogue edit');
    Check(ScriptSceneReadinessReason(P,S)<>'','stale checked image has an actionable explanation');
    var Before := P.Json;
    try
      var CueJson := JA(Before,'cues').ToJSON; var Image := S.Image; var Epoch := S.ImageEditEpoch;
      SetScriptSceneApproved(P,S.Id,True);
      Check(ScriptSceneReady(P,S,True) and (S.ImageEditEpoch=Epoch+1),'one explicit confirmation refreshes a stale checked image');
      Check(S.Image=Image,'confirmation keeps the existing image');
      var After := P.Json;
      try Check(JA(After,'cues').ToJSON=CueJson,'confirmation preserves all dialogue subtitle and audio data'); finally After.Free; end;
      Epoch := S.ImageEditEpoch; SetScriptSceneApproved(P,S.Id,True);
      Check(S.ImageEditEpoch=Epoch,'confirming an already current image does not invalidate requests');
      var C: TRigmMovieCue := nil; for var Cue in P.Cues do if Cue.Scene=S.Id then begin C := Cue; Break; end;
      Check(C<>nil,'fixture has dialogue attached to the image');
      var Text := C.Text; var Key := ScriptSceneFingerprint(P,S.Id);
      C.Text := Text+'！'; C.Subtitle := C.Text;
      Check(ScriptSceneReady(P,S,True),'dialogue and subtitle edits preserve image confirmation');
      Check(ScriptSceneFingerprint(P,S.Id)<>Key,'generation requests still detect changed dialogue');
      C.Text := Text; RefreshCasting(P);
      SetScriptSceneApproved(P,S.Id,False);
      var RequestId := JS(RequestScriptSceneImage(P,S.Id),'requestId');
      C.Text := Text+'？'; RefreshCasting(P);
      var Rejected := False;
      try RequireSceneImageRequest(P,S.Id,RequestId); except on E: Exception do Rejected := True; end;
      Check(Rejected,'old pending response is rejected after dialogue changes');
      C.Text := Text; RefreshCasting(P); SetScriptSceneApproved(P,S.Id,True);
      var Prompt := S.ImagePrompt; S.ImagePrompt := Prompt+' 修正';
      Check(not ScriptSceneReady(P,S,True),'changed image instructions still require human confirmation'); S.ImagePrompt := Prompt;
      S.Image := '';
      Check(not ScriptSceneReady(P,S,True),'missing image still blocks readiness'); S.Image := Image;
      S.Image := P.CommonBackground.Image;
      Check(not ScriptSceneReady(P,S,True),'different image content still invalidates confirmation'); S.Image := Image;
      SetScriptSceneApproved(P,S.Id,False);
      Check(not ScriptSceneReady(P,S,True),'unconfirmed image still blocks readiness'); SetScriptSceneApproved(P,S.Id,True);
      S.ImageApprovalKey := ScriptSceneFingerprint(P,S.Id);
      Check(ScriptSceneReady(P,S,True),'valid legacy approval remains readable');
      PrepareScriptScenes(P,False);
      Check(S.ImageApprovalKey=ScriptSceneApprovalKey(P,S.Id),'preparing scenes migrates only a verified legacy approval');
      C.Text := Text+'。'; RefreshCasting(P);
      Check(ScriptSceneReady(P,S,True),'migrated approval survives a later dialogue correction');
      C.Text := Text; RefreshCasting(P);
      P.Thumbnail.ImageApproved := False; P.Thumbnail.ImageApprovalKey := '';
      Check(not ScriptScenesReady(P,True),'mandatory thumbnail is never automatically confirmed');
      Check(ScriptThumbnailSourcesReady(P,True),'existing background and scenes can unlock thumbnail confirmation');
      SetScriptSceneApproved(P,RigmThumbnailId,True);
      Check(ScriptScenesReady(P,True),'confirmed existing images and thumbnail complete the stage');
      var Title := P.Title; var Input := JS(P.ScriptWizard,'titleInput');
      P.Title := Title+'改'; PsdJson.Put(P.ScriptWizard,'titleInput',Input+'改');
      Check(not ScriptSceneReady(P,P.Thumbnail,True),'changed title still invalidates the thumbnail');
      P.Title := Title; PsdJson.Put(P.ScriptWizard,'titleInput',Input);
      Check(ScriptScenesReady(P,True),'restoring the unchanged sources restores readiness');
      var Reopened := P.Clone;
      try Check(ScriptScenesReady(Reopened,True),'approval survives a JSON serialization round trip'); finally Reopened.Free; end;
    finally Before.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Source)=OriginalHash,'original user project is unchanged');
  finally P.Free; end;
  if ParamStr(3)<>'' then CheckFrame(Source,ParamStr(3));
end;
begin
  Application.Initialize;
  Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
    if Output<>'' then begin
      var Report := TJSONObject.Create.AddPair('checks',Checks.Clone as TJSONArray).AddPair('error',Error);
      try TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end;
    end;
  finally Checks.Free; end;
end.
