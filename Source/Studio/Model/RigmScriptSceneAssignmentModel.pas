unit RigmScriptSceneAssignmentModel;

// チェックしたセリフをシーンの開始点にする。セリフ・音声の正本は再生成しない。
interface
uses RigmMovieModel;
function ScriptSceneStartsAt(Project: TRigmMovieProject; Index: Integer): Boolean;
function ScriptSceneStartEditable(Project: TRigmMovieProject; Index: Integer): Boolean;
function ScriptSceneAssignmentCueIndices(Project: TRigmMovieProject): TArray<Integer>; // 総評を除いたセリフの正本インデックス。
procedure ValidateScriptSceneAssignment(Project: TRigmMovieProject);
procedure SetScriptSceneStart(Project: TRigmMovieProject; const CueId: string; Value: Boolean);
implementation
uses System.SysUtils, System.JSON, System.Generics.Collections, RigmJson, PsdJson,
  RigmMovieComposition, RigmScriptScenesModel, RigmScriptSummaryModel;

function ScriptSceneStartsAt(Project: TRigmMovieProject; Index: Integer): Boolean;
begin
  Result := (Index>0) and (Index<Project.Cues.Count);
  if Result then Result := Project.Cues[Index].Scene<>Project.Cues[Index-1].Scene;
end;
function ScriptSceneStartEditable(Project: TRigmMovieProject; Index: Integer): Boolean;
begin
  Result := (Index>0) and (Index<Project.Cues.Count);
  if not Result then Exit;
  // 総評の前後は独立チャートの境界を保持する。
  Result := not IsScriptSummaryCue(Project,Project.Cues[Index]) and not IsScriptSummaryCue(Project,Project.Cues[Index-1]);
end;
function ScriptSceneAssignmentCueIndices(Project: TRigmMovieProject): TArray<Integer>;
begin
  Result := nil;
  for var I := 0 to Project.Cues.Count-1 do if not IsScriptSummaryCue(Project,Project.Cues[I]) then begin
    SetLength(Result,Length(Result)+1); Result[High(Result)] := I;
  end;
end;
procedure ValidateScriptSceneAssignment(Project: TRigmMovieProject);
begin
  RequireScriptScenes(Project);
  if Project.Cues.Count=0 then raise Exception.Create('シーンへ割り当てるセリフがありません。');
  var Number := -1; var Previous := '';
  for var Cue in Project.Cues do begin
    if Cue.Scene<>Previous then begin
      Inc(Number);
      if (Number>=Project.Scenes.Count) or (Project.Scenes[Number].Id<>Cue.Scene) then
        raise Exception.Create('セリフの順序とシーンの割当が一致しません。');
      Previous := Cue.Scene;
    end;
  end;
  if Number<>Project.Scenes.Count-1 then raise Exception.Create('セリフのないシーンがあります。');
end;
procedure SetScriptSceneStart(Project: TRigmMovieProject; const CueId: string; Value: Boolean);
  function ArchivedScene(Archives: TJSONArray; const Id: string): TJSONObject;
  begin
    Result := nil;
    if Archives=nil then Exit;
    for var V in Archives do if JS(TJSONObject(V),'cueId')=Id then Exit(JO(TJSONObject(V),'scene'));
  end;
  procedure ArchiveScene(Archives: TJSONArray; const Id: string; Scene: TJSONObject);
  begin
    var Entry: TJSONObject := nil;
    for var V in Archives do if JS(TJSONObject(V),'cueId')=Id then begin Entry := TJSONObject(V); Break; end;
    if Entry=nil then begin Entry := TJSONObject.Create; Entry.AddPair('cueId',Id); Archives.AddElement(Entry); end;
    PsdJson.Put(Entry,'scene',Scene);
  end;
  procedure InvalidateImage(Scene: TRigmMovieScene);
  begin
    Scene.ImageApproved := False; Scene.ImageApprovalKey := '';
    if Scene.ImageEditEpoch=MaxInt then raise Exception.Create('画像編集世代の上限です。');
    Inc(Scene.ImageEditEpoch); Scene.Validate;
  end;
begin
  ValidateScriptSceneAssignment(Project);
  var Index := Project.Cues.IndexOf(Project.Cue(CueId));
  if Index<0 then raise Exception.Create('シーン開始点のセリフがありません。');
  if not ScriptSceneStartEditable(Project,Index) then
    raise Exception.Create('1行目と総評の開始点は固定です。');
  if ScriptSceneStartsAt(Project,Index)=Value then Exit;

  var Previous := Project.Scene(Project.Cues[Index-1].Scene); var Current := Project.Scene(Project.Cues[Index].Scene);
  var First := Index-1; while (First>0) and (Project.Cues[First-1].Scene=Previous.Id) do Dec(First);
  var Finish := Index+1; while (Finish<Project.Cues.Count) and (Project.Cues[Finish].Scene=Current.Id) do Inc(Finish);
  var Archives: TJSONArray := nil;
  if Project.ScriptWizard.GetValue('sceneAssignmentArchives') is TJSONArray then Archives := JA(Project.ScriptWizard,'sceneAssignmentArchives');
  var LeftData := Previous.Json; var RightData: TJSONObject := nil;
  var Left: TRigmMovieScene := nil; var Right: TRigmMovieScene := nil;
  try
    Left := TRigmMovieScene.FromJson(LeftData);
    if Value then begin
      var Data := ArchivedScene(Archives,CueId);
      if (Data<>nil) and (Project.Scene(JS(Data,'id'))=nil) then Right := TRigmMovieScene.FromJson(Data)
      else begin Right := TRigmMovieScene.Create; Right.Title := 'シーン '+(Project.Scenes.Count+1).ToString; end;
      Right.Padding := Left.Padding; Left.Padding := 0;
      InvalidateImage(Right);
    end else begin
      RightData := Current.Json; Left.Padding := Left.Padding+Current.Padding;
    end;
    InvalidateImage(Left);
    // 変更する左右のシーンだけ検査・退避し、他のシーン・画像・セリフは作り直さない。
    if Archives=nil then begin Archives := TJSONArray.Create; PsdJson.Put(Project.ScriptWizard,'sceneAssignmentArchives',Archives); end;
    ArchiveScene(Archives,Project.Cues[First].Id,LeftData); LeftData := nil;
    if RightData<>nil then begin ArchiveScene(Archives,CueId,RightData); RightData := nil; end;
    var SceneIndex := Project.Scenes.IndexOf(Previous); var TargetId := Left.Id;
    if Value then begin TargetId := Right.Id; Project.Scenes.Insert(SceneIndex+1,Right); Right := nil; end
    else Project.Scenes.Delete(SceneIndex+1);
    Project.Scenes[SceneIndex] := Left; Left := nil;
    for var I := Index to Finish-1 do Project.Cues[I].Scene := TargetId;
    var O := JO(Project.ScriptWizard,'scenes');
    if Project.Scene(JS(O,'selectedScene'))=nil then PsdJson.Put(O,'selectedScene',Project.Scenes[0].Id);
    PsdJson.Put(Project.ScriptWizard,'scene-assignmentStatus','in-progress');
    PsdJson.Put(Project.ScriptWizard,'scenesStatus','in-progress');
  finally Right.Free; Left.Free; RightData.Free; LeftData.Free; end;
end;
end.
