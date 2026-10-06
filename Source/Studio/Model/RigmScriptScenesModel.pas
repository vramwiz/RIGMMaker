unit RigmScriptScenesModel;
// シーンの説明・外部画像要求を既存scene正本に結び付ける。画像生成は外部Codexの工程。
interface
uses System.JSON, RigmMovieModel, RigmMovieComposition;
procedure PrepareScriptScenes(Project: TRigmMovieProject);
procedure ValidateScriptScenes(Project: TRigmMovieProject);
procedure RequireScriptScenes(Project: TRigmMovieProject);
procedure EditScriptScene(Project: TRigmMovieProject; const Id,Description,Prompt,Mode: string);
function ScriptSceneReady(Project: TRigmMovieProject; Scene: TRigmMovieScene): Boolean;
function ScriptScenesReady(Project: TRigmMovieProject): Boolean;
function ScriptSceneNumber(Project: TRigmMovieProject; const Id: string): Integer;
function ScriptSceneStart(Project: TRigmMovieProject; const Id: string): Double;
function ScriptSceneFingerprint(Project: TRigmMovieProject; const Id: string): string;
function ScriptSceneRequest(Project: TRigmMovieProject; const Id: string): TJSONObject; // 借用。
function RequestScriptSceneImage(Project: TRigmMovieProject; const Id: string): TJSONObject; // 借用。
procedure RequireSceneImageRequest(Project: TRigmMovieProject; const Id,RequestId: string);
function ScriptScenesSummary(Project: TRigmMovieProject): TJSONObject;
implementation
uses System.SysUtils, System.Hash, System.Generics.Collections, RigmJson, PsdJson, RigmScriptCastingModel, RigmScriptVoiceModel, RigmScriptTextModel, RigmMovieChart;
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
procedure PrepareScriptScenes(Project: TRigmMovieProject);
begin
  RequireCurrentVoice(Project);
  if JS(Project.ScriptWizard,'voiceStatus')<>'complete' then raise Exception.Create('音声確認完了を押してから進んでください。');
  for var C in Project.Cues do if not Project.AudioReady(C) then raise Exception.Create('変更後または未生成の音声を確認してください。');
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
    if (JS(R,'requestId')='') or (JS(R,'sceneId')='') or (Length(JS(R,'fingerprint'))<>64) or (Length(JS(R,'prompt'))>8000) then raise Exception.Create('画像要求の識別情報が不正です。');
  end;
  for var S in Project.Scenes do begin
    ValidateText(S.Description,3000); ValidateText(S.ImagePrompt,8000);
    var HasCue := False; for var C in Project.Cues do if C.Scene=S.Id then HasCue := True;
    if not HasCue then raise Exception.Create('シーンには1つ以上のセリフが必要です。');
  end;
end;
procedure EditScriptScene(Project: TRigmMovieProject; const Id,Description,Prompt,Mode: string);
begin
  RequireScriptScenes(Project); var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。');
  var D := NormalizeScriptText(Description); var P := NormalizeScriptText(Prompt); ValidateText(D,3000); ValidateText(P,8000);
  var O := S.Json;
  try PsdJson.Put(O,'description',D); PsdJson.Put(O,'imagePrompt',P); PsdJson.Put(O,'displayMode',Mode);
    var Copy := TRigmMovieScene.FromJson(O); try S.Description := Copy.Description; S.ImagePrompt := Copy.ImagePrompt; S.DisplayMode := Copy.DisplayMode; finally Copy.Free; end;
  finally O.Free; end;
  PsdJson.Put(Project.ScriptWizard,'scenesStatus','in-progress');
end;
function ScriptSceneReady(Project: TRigmMovieProject; Scene: TRigmMovieScene): Boolean;
begin
  Result := True;
  if (Scene.DisplayMode='both') or (Scene.DisplayMode='image') then Result := MovieChartEnabled(Scene.Chart) or ((Scene.Image<>'') and FileExists(ResolveMoviePath(Project.FileName,Scene.Image)));
  if (Scene.DisplayMode='both') or (Scene.DisplayMode='text') then Result := Result and (Scene.Description.Trim<>'');
end;
function ScriptScenesReady(Project: TRigmMovieProject): Boolean;
begin Result := False; try RequireScriptScenes(Project); for var S in Project.Scenes do if not ScriptSceneReady(Project,S) then Exit; Result := Project.Scenes.Count>0; except on E: Exception do Exit; end; end;
function ScriptSceneNumber(Project: TRigmMovieProject; const Id: string): Integer;
begin var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。'); Result := Project.Scenes.IndexOf(S)+1; end;
function ScriptSceneStart(Project: TRigmMovieProject; const Id: string): Double;
begin Result := 0; for var S in Project.Scenes do begin if S.Id=Id then Exit; Result := Result+Project.SceneDuration(S); end; raise Exception.Create('対象シーンがありません。'); end;
function ScriptSceneFingerprint(Project: TRigmMovieProject; const Id: string): string;
begin
  var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。'); var O := S.Json;
  // 保存時に素材をproject.assetsへ移しても、同じ画像内容なら外部要求を保持する。
  if S.Image<>'' then begin var Path := ResolveMoviePath(Project.FileName,S.Image);
    if FileExists(Path) then PsdJson.Put(O,'image','sha256:'+THashSHA2.GetHashStringFromFile(Path))
    else PsdJson.Put(O,'image',ExpandFileName(Path));
  end;
  try var A := TJSONArray.Create; O.AddPair('sourceCues',A); for var C in Project.Cues do if C.Scene=Id then begin var V := TJSONObject.Create; V.AddPair('id',C.Id); V.AddPair('text',C.Text); A.AddElement(V); end;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
end;
function ScriptSceneRequest(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin Result := nil; for var V in JA(JO(Project.ScriptWizard,'scenes'),'requests') do if JS(TJSONObject(V),'sceneId')=Id then Exit(TJSONObject(V)); end;
function RequestScriptSceneImage(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin
  RequireScriptScenes(Project); var S := Project.Scene(Id); if S=nil then raise Exception.Create('対象シーンがありません。');
  if S.ImagePrompt.Trim='' then raise Exception.Create('Codexへの画像指示を入力してください。');
  var A := JA(JO(Project.ScriptWizard,'scenes'),'requests'); for var I := A.Count-1 downto 0 do if JS(TJSONObject(A[I]),'sceneId')=Id then A.Remove(I).Free;
  Result := TJSONObject.Create; A.AddElement(Result); Result.AddPair('requestId',PsdJson.NewId); Result.AddPair('sceneId',Id); AddN(Result,'sceneNumber',ScriptSceneNumber(Project,Id));
  Result.AddPair('fingerprint',ScriptSceneFingerprint(Project,Id)); Result.AddPair('prompt',S.ImagePrompt); Result.AddPair('state','pending'); Result.AddPair('provider','external-codex');
end;
procedure RequireSceneImageRequest(Project: TRigmMovieProject; const Id,RequestId: string);
begin
  RequireScriptScenes(Project); var R := ScriptSceneRequest(Project,Id);
  if (R=nil) or (RequestId='') or (JS(R,'requestId')<>RequestId) or (JS(R,'state')<>'pending') or (JS(R,'fingerprint')<>ScriptSceneFingerprint(Project,Id)) then
    raise Exception.Create('古い画像要求です。人間の変更を保持しています。対象シーンから再要求してください。');
end;
function ScriptScenesSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; AddN(Result,'count',Project.Scenes.Count); var Ready := 0; var Pending := 0;
  for var S in Project.Scenes do begin if ScriptSceneReady(Project,S) then Inc(Ready); var R := ScriptSceneRequest(Project,S.Id); if (R<>nil) and (JS(R,'state')='pending') then Inc(Pending); end;
  AddN(Result,'ready',Ready); AddN(Result,'pendingRequests',Pending); Result.AddPair('selectedScene',JS(JO(Project.ScriptWizard,'scenes'),'selectedScene')); Result.AddPair('state',JS(Project.ScriptWizard,'scenesStatus','in-progress'));
end;
end.
