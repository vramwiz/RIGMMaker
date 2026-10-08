unit RigmScriptScenesModel;
// シーンの説明・外部画像要求を既存scene正本に結び付ける。画像生成は外部Codexの工程。
interface
uses System.JSON, RigmMovieModel, RigmMovieComposition;
procedure PrepareScriptScenes(Project: TRigmMovieProject; RequireVoiceConfirmation: Boolean = True);
procedure ValidateScriptScenes(Project: TRigmMovieProject);
procedure RequireScriptScenes(Project: TRigmMovieProject);
procedure EditScriptScene(Project: TRigmMovieProject; const Id,Description,Prompt,Mode: string; const Position: string='');
function SceneImageInstruction(Scene: TRigmMovieScene): string; // 旧要望・修正指示を欠落なく1欄へ表示する。
function SceneInputDisplayMode(const Prompt,Description: string): string;
function SceneNeedsImage(Scene: TRigmMovieScene): Boolean;
procedure EditScriptSceneFeedback(Project: TRigmMovieProject; const Id,Feedback: string);
procedure RequireEditableScriptScene(Project: TRigmMovieProject; const Id: string);
procedure SetScriptSceneApproved(Project: TRigmMovieProject; const Id: string; Value: Boolean);
procedure ApplyScriptSceneImage(Project: TRigmMovieProject; const Id,Path,RequestId: string);
procedure SyncScriptScenesStatus(Project: TRigmMovieProject);
function ScriptSceneReady(Project: TRigmMovieProject; Scene: TRigmMovieScene; Force: Boolean=False): Boolean;
function ScriptScenesReady(Project: TRigmMovieProject; Force: Boolean=False): Boolean;
function ScriptSceneNumber(Project: TRigmMovieProject; const Id: string): Integer;
function ScriptSceneStart(Project: TRigmMovieProject; const Id: string): Double;
function ScriptSceneFingerprint(Project: TRigmMovieProject; const Id: string): string;
function ScriptSceneRequest(Project: TRigmMovieProject; const Id: string): TJSONObject; // 借用。
function RequestScriptSceneImage(Project: TRigmMovieProject; const Id: string): TJSONObject; // 借用。
procedure RequireSceneImageRequest(Project: TRigmMovieProject; const Id,RequestId: string);
function ScriptScenesSummary(Project: TRigmMovieProject): TJSONObject;
implementation
uses System.SysUtils, System.Hash, System.Generics.Collections, RigmJson, PsdJson, RigmScriptCastingModel, RigmScriptVoiceModel, RigmScriptTextModel, RigmMovieChart, RigmMovieImageTransfer;
function SceneImageInstruction(Scene: TRigmMovieScene): string;
begin
  Result := Scene.ImagePrompt;
  if Scene.ImageFeedback.Trim<>'' then begin
    if Result.Trim<>'' then Result := Result+#13#10+#13#10;
    Result := Result+Scene.ImageFeedback;
  end;
end;
function SceneInputDisplayMode(const Prompt,Description: string): string;
begin
  Result := 'none';
  if Prompt.Trim<>'' then begin Result := 'image'; if Description.Trim<>'' then Result := 'both'; end
  else if Description.Trim<>'' then Result := 'text';
end;
function SceneNeedsImage(Scene: TRigmMovieScene): Boolean;
begin Result := (Scene.DisplayMode='both') or (Scene.DisplayMode='image'); end;
procedure ValidateText(const Text: string; Limit: Integer);
begin
  if Length(Text)>Limit then raise Exception.Create('シーンの文章が長すぎます。');
  var I := 1;
  while I<=Length(Text) do begin
    var N := Ord(Text[I]); if (N<32) and not CharInSet(Text[I],[#9,#10,#13]) then raise Exception.Create('シーンの制御文字が不正です。');
    if (N>=$D800) and (N<=$DBFF) then begin
      if (I=Length(Text)) or (Ord(Text[I+1])<$DC00) or (Ord(Text[I+1])>$DFFF) then raise Exception.Create('シーンの文字が途中で切れています。'); Inc(I);
    end else if (N>=$DC00) and (N<=$DFFF) then raise Exception.Create('シーンの文字が途中で切れています。');
    Inc(I);
  end;
end;
procedure RequireScriptScenes(Project: TRigmMovieProject);
begin
  RequireCurrentVoice(Project);
  if (Project.ScriptWizard.GetValue('scenes')=nil) or (JS(JO(Project.ScriptWizard,'scenes'),'castingFingerprint')<>CastingFingerprint(Project)) then
    raise Exception.Create('前工程が変わりました。音声工程からNextでシーンを再確認してください。');
end;
procedure PrepareScriptScenes(Project: TRigmMovieProject; RequireVoiceConfirmation: Boolean);
begin
  if RequireVoiceConfirmation then begin
    RequireCurrentVoice(Project);
    if JS(Project.ScriptWizard,'voiceStatus')<>'complete' then raise Exception.Create('全セリフの音声を最後まで再生してから進んでください。');
    for var C in Project.Cues do if not Project.AudioHeard(C) then raise Exception.Create('変更後または未再生の音声を確認してください。');
  end;
  if Project.Scenes.Count=0 then raise Exception.Create('セリフを含むシーンがありません。');
  if Project.ScriptWizard.GetValue('scenes')=nil then begin
    var O := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptScenes","schemaVersion":1,"requests":[]}');
    O.AddPair('selectedScene',Project.Scenes[0].Id); Project.ScriptWizard.AddPair('scenes',O);
  end;
  var O := JO(Project.ScriptWizard,'scenes'); var Changed := JS(O,'castingFingerprint')<>CastingFingerprint(Project); PsdJson.Put(O,'castingFingerprint',CastingFingerprint(Project));
  if Project.Scene(JS(O,'selectedScene'))=nil then PsdJson.Put(O,'selectedScene',Project.Scenes[0].Id);
  if Changed or (Project.ScriptWizard.GetValue('scenesStatus')=nil) then PsdJson.Put(Project.ScriptWizard,'scenesStatus','in-progress'); ValidateScriptScenes(Project);
end;
procedure ValidateScriptScenes(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'scenes');
  if (JS(O,'format')<>'RIGMMaker.ScriptScenes') or (JI(O,'schemaVersion')<>1) or (Project.Scene(JS(O,'selectedScene'))=nil) or not (O.GetValue('requests') is TJSONArray) then
    raise Exception.Create('シーン工程の保存状態が不正です。');
  if JA(O,'requests').Count>2000 then raise Exception.Create('画像要求件数が不正です。');
  for var V in JA(O,'requests') do begin
    if not (V is TJSONObject) then raise Exception.Create('画像要求の保存形式が不正です。');
    var R := TJSONObject(V);
    if (JS(R,'requestId')='') or (JS(R,'sceneId')='') or (Length(JS(R,'fingerprint'))<>64) or (Length(JS(R,'prompt'))>16004) then raise Exception.Create('画像要求の識別情報が不正です。');
  end;
  for var S in Project.Scenes do begin
    ValidateText(S.Description,3000); ValidateText(S.ImagePrompt,16004); ValidateText(S.ImageFeedback,8000); S.Validate;
    var HasCue := False; for var C in Project.Cues do if C.Scene=S.Id then HasCue := True;
    if not HasCue then raise Exception.Create('シーンには1つ以上のセリフが必要です。');
  end;
end;
procedure EditScriptScene(Project: TRigmMovieProject; const Id,Description,Prompt,Mode: string; const Position: string);
begin
  RequireScriptScenes(Project); RequireEditableScriptScene(Project,Id); var S := Project.Scene(Id);
  var D := NormalizeScriptText(Description); var P := NormalizeScriptText(Prompt); ValidateText(D,3000); ValidateText(P,16004);
  var O := S.Json;
  try PsdJson.Put(O,'description',D); PsdJson.Put(O,'imagePrompt',P); PsdJson.Put(O,'displayMode',Mode);
    if Position<>'' then PsdJson.Put(O,'descriptionPosition',Position);
    var Copy := TRigmMovieScene.FromJson(O); try S.Description := Copy.Description; S.ImagePrompt := Copy.ImagePrompt;
      S.DisplayMode := Copy.DisplayMode; S.DescriptionPosition := Copy.DescriptionPosition; finally Copy.Free; end;
  finally O.Free; end;
  PsdJson.Put(Project.ScriptWizard,'scenesStatus','in-progress');
end;
procedure RequireEditableScriptScene(Project: TRigmMovieProject; const Id: string);
begin
  var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。');
  if S.ImageApproved then raise Exception.Create('確定済みシーンです。画像工程のチェックを明示的に外してから編集してください。');
end;
procedure EditScriptSceneFeedback(Project: TRigmMovieProject; const Id,Feedback: string);
begin
  RequireScriptScenes(Project); RequireEditableScriptScene(Project,Id);
  var Text := NormalizeScriptText(Feedback); ValidateText(Text,8000); Project.Scene(Id).ImageFeedback := Text;
  SyncScriptScenesStatus(Project);
end;
procedure SetScriptSceneApproved(Project: TRigmMovieProject; const Id: string; Value: Boolean);
begin
  RequireScriptScenes(Project); var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。');
  if S.ImageApproved=Value then Exit;
  if S.ImageEditEpoch=MaxInt then raise Exception.Create('画像編集世代の上限です。');
  if Value and SceneNeedsImage(S) then begin
    if S.Image='' then raise Exception.Create('画像を用意してから確定してください。');
    CheckedMovieImageHash(ResolveMoviePath(Project.FileName,S.Image),True);
  end;
  Inc(S.ImageEditEpoch); S.ImageApproved := Value; S.ImageApprovalKey := '';
  if Value then S.ImageApprovalKey := ScriptSceneFingerprint(Project,Id);
  var R := ScriptSceneRequest(Project,Id); if R<>nil then PsdJson.Put(R,'state','cancelled');
  SyncScriptScenesStatus(Project);
end;
procedure ApplyScriptSceneImage(Project: TRigmMovieProject; const Id,Path,RequestId: string);
begin
  RequireScriptScenes(Project); RequireEditableScriptScene(Project,Id);
  if RequestId<>'' then RequireSceneImageRequest(Project,Id,RequestId);
  CheckedMovieImageHash(Path,True);
  // The caller copies first; this final check also protects a response started before approval.
  RequireEditableScriptScene(Project,Id);
  if RequestId<>'' then RequireSceneImageRequest(Project,Id,RequestId);
  Project.Scene(Id).Image := Path;
  if RequestId<>'' then begin var R := ScriptSceneRequest(Project,Id); PsdJson.Put(R,'state','adopted'); PsdJson.Put(R,'adoptedFingerprint',ScriptSceneFingerprint(Project,Id)); end;
  SyncScriptScenesStatus(Project);
end;
function ScriptSceneReady(Project: TRigmMovieProject; Scene: TRigmMovieScene; Force: Boolean): Boolean;
begin
  Result := False;
  try
    if not Scene.ImageApproved then Exit;
    if SceneNeedsImage(Scene) then begin
      if Scene.Image='' then Exit;
      CheckedMovieImageHash(ResolveMoviePath(Project.FileName,Scene.Image),Force);
    end;
    Result := Scene.ImageApprovalKey=ScriptSceneFingerprint(Project,Scene.Id);
  except on E: Exception do Result := False; end;
end;
function ScriptScenesReady(Project: TRigmMovieProject; Force: Boolean): Boolean;
begin Result := False; try RequireScriptScenes(Project); for var S in Project.Scenes do if not ScriptSceneReady(Project,S,Force) then Exit; Result := Project.Scenes.Count>0; except on E: Exception do Exit; end; end;
procedure SyncScriptScenesStatus(Project: TRigmMovieProject);
begin
  var State := 'in-progress'; if ScriptScenesReady(Project) then State := 'complete';
  PsdJson.Put(Project.ScriptWizard,'scenesStatus',State);
end;
function ScriptSceneNumber(Project: TRigmMovieProject; const Id: string): Integer;
begin var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。'); Result := Project.Scenes.IndexOf(S)+1; end;
function ScriptSceneStart(Project: TRigmMovieProject; const Id: string): Double;
begin Result := 0; for var S in Project.Scenes do begin if S.Id=Id then Exit; Result := Result+Project.SceneDuration(S); end; raise Exception.Create('対象シーンがありません。'); end;
function ScriptSceneFingerprint(Project: TRigmMovieProject; const Id: string): string;
begin
  var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。'); var O := S.Json;
  try
  // Approval itself is excluded; the edit epoch prevents approval -> unlock replay.
  for var Key in ['imageApproved','imageApprovalKey','animation','chart','padding','title'] do O.RemovePair(Key).Free;
  // 保存時に素材をproject.assetsへ移しても、同じ画像内容なら外部要求を保持する。
  if S.Image<>'' then begin var Path := ResolveMoviePath(Project.FileName,S.Image);
    if FileExists(Path) then begin try PsdJson.Put(O,'image','sha256:'+CheckedMovieImageHash(Path)); except on E: Exception do PsdJson.Put(O,'image','unreadable:'+ExpandFileName(Path)); end; end
    else PsdJson.Put(O,'image',ExpandFileName(Path));
  end;
    var A := TJSONArray.Create; O.AddPair('sourceCues',A); for var C in Project.Cues do if C.Scene=Id then begin var V := TJSONObject.Create; V.AddPair('id',C.Id); V.AddPair('text',C.Text); A.AddElement(V); end;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
end;
function ScriptSceneRequest(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin Result := nil; for var V in JA(JO(Project.ScriptWizard,'scenes'),'requests') do if JS(TJSONObject(V),'sceneId')=Id then Exit(TJSONObject(V)); end;
function RequestScriptSceneImage(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin
  RequireScriptScenes(Project); var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。');
  RequireEditableScriptScene(Project,Id);
  var Prompt := SceneImageInstruction(S);
  if Prompt.Trim='' then raise Exception.Create('Codexへの画像指示を入力してください。');
  ValidateText(Prompt,16004);
  var Fingerprint := ScriptSceneFingerprint(Project,Id);
  var A := JA(JO(Project.ScriptWizard,'scenes'),'requests'); for var I := A.Count-1 downto 0 do if JS(TJSONObject(A[I]),'sceneId')=Id then A.Remove(I).Free;
  Result := TJSONObject.Create; A.AddElement(Result); Result.AddPair('requestId',PsdJson.NewId); Result.AddPair('sceneId',Id); AddN(Result,'sceneNumber',ScriptSceneNumber(Project,Id));
  Result.AddPair('fingerprint',Fingerprint); Result.AddPair('prompt',Prompt); Result.AddPair('feedback',''); Result.AddPair('state','pending'); Result.AddPair('provider','external-codex');
end;
procedure RequireSceneImageRequest(Project: TRigmMovieProject; const Id,RequestId: string);
begin
  RequireScriptScenes(Project); RequireEditableScriptScene(Project,Id); var R := ScriptSceneRequest(Project,Id);
  if (R=nil) or (RequestId='') or (JS(R,'requestId')<>RequestId) or (JS(R,'state')<>'pending') or (JS(R,'fingerprint')<>ScriptSceneFingerprint(Project,Id)) then
    raise Exception.Create('古い画像要求です。人間の変更を保持しています。対象シーンから再要求してください。');
end;
function ScriptScenesSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; AddN(Result,'count',Project.Scenes.Count); var Ready := 0; var Pending := 0;
  for var S in Project.Scenes do begin if ScriptSceneReady(Project,S) then Inc(Ready); var R := ScriptSceneRequest(Project,S.Id); if (R<>nil) and (JS(R,'state')='pending') then Inc(Pending); end;
  AddB(Result,'allApproved',ScriptScenesReady(Project)); AddN(Result,'ready',Ready); AddN(Result,'pendingRequests',Pending); Result.AddPair('selectedScene',JS(JO(Project.ScriptWizard,'scenes'),'selectedScene')); var State := 'in-progress'; if ScriptScenesReady(Project) then State := 'complete'; Result.AddPair('state',State);
end;
end.
