unit RigmScriptSceneAssignmentModel;

// チェックしたセリフをシーンの開始点にする。セリフ・音声の正本は再生成しない。
interface
uses RigmMovieModel;
function ScriptSceneStartsAt(Project: TRigmMovieProject; Index: Integer): Boolean;
function ScriptSceneStartEditable(Project: TRigmMovieProject; Index: Integer): Boolean;
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
  // 後工程で作る総評は独立シーンを保持する。本文の開始点は自由に変更できる。
  var Summary := ScriptSummaryCue(Project);
  Result := (Project.Cues[Index]<>Summary) and (Project.Cues[Index-1]<>Summary);
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
begin
  ValidateScriptSceneAssignment(Project);
  var Index := Project.Cues.IndexOf(Project.Cue(CueId));
  if Index<0 then raise Exception.Create('シーン開始点のセリフがありません。');
  if not ScriptSceneStartEditable(Project,Index) then
    raise Exception.Create('1行目と総評の開始点は固定です。');
  if ScriptSceneStartsAt(Project,Index)=Value then Exit;

  var Starts: TArray<Boolean>; SetLength(Starts,Project.Cues.Count); Starts[0] := True;
  for var I := 1 to High(Starts) do Starts[I] := ScriptSceneStartsAt(Project,I);
  Starts[Index] := Value;
  var Assignments: TArray<string>; SetLength(Assignments,Project.Cues.Count);
  var Scenes := TObjectList<TRigmMovieScene>.Create(True);
  var Used := TDictionary<string,Boolean>.Create;
  var Archives := TJSONArray.Create;
  try
    if Project.ScriptWizard.GetValue('sceneAssignmentArchives') is TJSONArray then begin
      Archives.Free; Archives := JA(Project.ScriptWizard,'sceneAssignmentArchives').Clone as TJSONArray;
    end;
    // 結合で一覧から外れる画像・説明文も、元の開始セリフとともに保存して再分割に備える。
    for var I := 0 to Project.Cues.Count-1 do
      if (I=0) or ScriptSceneStartsAt(Project,I) then begin
        var Entry: TJSONObject := nil;
        for var V in Archives do if JS(TJSONObject(V),'cueId')=Project.Cues[I].Id then begin Entry := TJSONObject(V); Break; end;
        if Entry=nil then begin Entry := TJSONObject.Create; Entry.AddPair('cueId',Project.Cues[I].Id); Archives.AddElement(Entry); end;
        PsdJson.Put(Entry,'scene',Project.Scene(Project.Cues[I].Scene).Json);
      end;
    var Current: TRigmMovieScene := nil;
    for var I := 0 to Project.Cues.Count-1 do begin
      if Starts[I] then begin
        var Data: TJSONObject := nil;
        for var V in Archives do if JS(TJSONObject(V),'cueId')=Project.Cues[I].Id then begin Data := JO(TJSONObject(V),'scene'); Break; end;
        if (Data<>nil) and not Used.ContainsKey(JS(Data,'id')) then Current := TRigmMovieScene.FromJson(Data)
        else begin
          Current := TRigmMovieScene.Create; Current.Title := 'シーン '+(Scenes.Count+1).ToString;
        end;
        Current.Padding := 0;
        Scenes.Add(Current); Used.Add(Current.Id,True);
      end;
      Assignments[I] := Current.Id;
    end;
    // 旧シーン末尾の余白は、その末尾セリフを含む新シーンへ移す。分割・結合で尺を失わない。
    for var Old in Project.Scenes do begin
      var Last := -1;
      for var I := 0 to Project.Cues.Count-1 do if Project.Cues[I].Scene=Old.Id then Last := I;
      if Last>=0 then for var Scene in Scenes do if Scene.Id=Assignments[Last] then begin Scene.Padding := Scene.Padding+Old.Padding; Break; end;
    end;
    for var Scene in Scenes do begin
      var OldIds := ''; var NewIds := '';
      for var I := 0 to Project.Cues.Count-1 do begin
        if Project.Cues[I].Scene=Scene.Id then OldIds := OldIds+'|'+Project.Cues[I].Id;
        if Assignments[I]=Scene.Id then NewIds := NewIds+'|'+Project.Cues[I].Id;
      end;
      if OldIds<>NewIds then begin Scene.ImageApproved := False; Scene.ImageApprovalKey := ''; if Scene.ImageEditEpoch=MaxInt then raise Exception.Create('画像編集世代の上限です。'); Inc(Scene.ImageEditEpoch); end;
      Scene.Validate;
    end;
    // 構築・検査に成功した後で、既存セリフのscene参照とscene一覧だけを置き換える。
    for var I := 0 to Project.Cues.Count-1 do Project.Cues[I].Scene := Assignments[I];
    var OldScenes := Project.Scenes; Project.Scenes := Scenes; Scenes := nil; OldScenes.Free;
    PsdJson.Put(Project.ScriptWizard,'sceneAssignmentArchives',Archives); Archives := nil;
    var O := JO(Project.ScriptWizard,'scenes');
    if Project.Scene(JS(O,'selectedScene'))=nil then PsdJson.Put(O,'selectedScene',Project.Scenes[0].Id);
    PsdJson.Put(Project.ScriptWizard,'scene-assignmentStatus','in-progress');
    PsdJson.Put(Project.ScriptWizard,'scenesStatus','in-progress');
  finally Archives.Free; Used.Free; Scenes.Free; end;
end;
end.
