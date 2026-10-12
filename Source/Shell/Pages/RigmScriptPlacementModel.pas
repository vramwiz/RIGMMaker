unit RigmScriptPlacementModel;
interface
uses System.JSON, System.Types, RigmMovieModel, RigmThumbnailCache;
function ScriptStageIndex(const Stage: string): Integer;
function ScriptStageName(const Stage: string): string;
function Placement(Project: TRigmMovieProject; const Path: string): TJSONObject;
function PlacementRect(Value: TJSONObject): TRectF;
function PlacementArea(Project: TRigmMovieProject): TRectF;
procedure ValidatePlacement(Value: TJSONObject);
function DefaultScriptPlacement(Project: TRigmMovieProject; Cache: TRigmThumbnailCache; const Path: string): TJSONObject; // 呼出側所有。
procedure PreparePlacements(Project: TRigmMovieProject; Cache: TRigmThumbnailCache);
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, RigmJson, PsdJson, RigmModel, RigmMovieLayout;
function ScriptStageName(const Stage: string): string;
begin
  if Stage='title' then Result := '題名' else if Stage='characters' then Result := 'キャラ選択'
  else if Stage='layout' then Result := 'レイアウト選択' else if Stage='placement' then Result := 'キャラ配置' else if Stage='text' then Result := '台本入力' else if Stage='review' then Result := '作品情報・掘り下げ確認' else if Stage='casting' then Result := '配役' else if Stage='subtitles' then Result := '字幕' else if Stage='voice' then Result := '音声調整' else if Stage='voice-effects' then Result := '音声エフェクト' else if Stage='scene-assignment' then Result := 'セリフのシーン割当' else if Stage='scenes' then Result := 'シーン画像・説明' else if Stage='summary' then Result := '総評の有無' else if Stage='summary-edit' then Result := '総評入力・チャート' else if Stage='closing' then Result := '締め設定' else if Stage='script-confirm' then Result := '台本確認' else if Stage='editor' then Result := '動画編集' else Result := Stage;
end;
function ScriptStageIndex(const Stage: string): Integer;
begin
  if Stage='title' then Result := 0 else if Stage='characters' then Result := 1
  else if Stage='layout' then Result := 2 else if Stage='placement' then Result := 3 else if Stage='text' then Result := 4 else if Stage='review' then Result := 5 else if Stage='summary' then Result := 6 else if Stage='summary-edit' then Result := 7 else if Stage='closing' then Result := 8 else if Stage='script-confirm' then Result := 9 else if Stage='casting' then Result := 10 else if Stage='subtitles' then Result := 11 else if Stage='voice' then Result := 12 else if Stage='voice-effects' then Result := 13 else if Stage='scene-assignment' then Result := 14 else if Stage='scenes' then Result := 15 else if Stage='editor' then Result := 16 else Result := -1;
end;
function Placement(Project: TRigmMovieProject; const Path: string): TJSONObject;
begin
  Result := nil; if Project<>nil then Result := Project.Placement(Path);
end;
function PlacementRect(Value: TJSONObject): TRectF;
begin Result := RectF(JN(Value,'x')*1920,JN(Value,'y')*1080,(JN(Value,'x')+JN(Value,'width'))*1920,(JN(Value,'y')+JN(Value,'height'))*1080); end;
function PlacementArea(Project: TRigmMovieProject): TRectF;
begin
  Result := RectF(0,0,1920,1080);
  if Project.Layout='l' then begin
    var Guide := MovieLayoutRegions(Project.Layout,Project.LDirection);
    var R := Guide.LeftCharacters; if Project.LDirection='right' then R := Guide.RightCharacters;
    Result := RectF(R.Left*1920,R.Top*1080,R.Right*1920,R.Bottom*1080);
  end;
end;
procedure ValidatePlacement(Value: TJSONObject);
begin
  for var Name in ['x','y','width','height'] do
    if not (Value.GetValue(Name) is TJSONNumber) or not Finite(JN(Value,Name)) then raise Exception.Create('配置には有限の比率座標を指定してください。');
  var X := JN(Value,'x'); var Y := JN(Value,'y'); var W := JN(Value,'width'); var H := JN(Value,'height');
  if (Abs(X)>4) or (Abs(Y)>4) or (W<20/1920) or (H<20/1080) or (W>4) or (H>4) or
    not (Value.GetValue('flipX') is TJSONBool) then raise Exception.Create('配置枠は20px以上、座標・サイズは画面の4倍以内にしてください。');
end;
function DefaultScriptPlacement(Project: TRigmMovieProject; Cache: TRigmThumbnailCache; const Path: string): TJSONObject;
begin
  var Selected := JA(Project.ScriptWizard,'selectedCharacters'); var I := -1;
  for var N := 0 to Selected.Count-1 do if SameText(JS(TJSONObject(Selected[N]),'path'),Path) then begin I := N; Break; end;
  if I<0 then raise Exception.Create('選択済みキャラを指定してください。');
  var Entry := Cache.Request(Path);
  if (Entry=nil) or (Entry.Width<=0) or (Entry.Height<=0) or not JB(Entry.Metadata,'readyForScript') then
    raise Exception.Create('キャラのサムネイル検査が完了してから操作してください。');
  var Guide := MovieLayoutRegions(Project.Layout,Project.LDirection); var R := Guide.LeftCharacters;
  if (Project.Layout='theme') and ((I mod 2)=1) or ((Project.Layout='l') and (Project.LDirection='right')) then R := Guide.RightCharacters;
  var Count := Selected.Count; if Project.Layout='theme' then Count := (Count+1-I mod 2) div 2;
  var Cols := Max(1,Ceil(Sqrt(Count*R.Width*1920/Max(1,R.Height*1080))));
  var Rows := (Count+Cols-1) div Cols; var N := I; if Project.Layout='theme' then N := I div 2;
  var CW := R.Width*1920/Cols; var CH := R.Height*1080/Rows;
  var K := Max(Min(CW/Entry.Width,CH/Entry.Height)*0.90,Max(20/Entry.Width,20/Entry.Height));
  var W := Entry.Width*K; var H := Entry.Height*K;
  Result := TJSONObject.Create;
  Result.AddPair('path',Path); Result.AddPair('flipX',TJSONBool.Create(False));
  AddN(Result,'x',(R.Left*1920+N mod Cols*CW+(CW-W)/2)/1920);
  AddN(Result,'y',(R.Top*1080+(N div Cols+1)*CH-H)/1080);
  AddN(Result,'width',W/1920); AddN(Result,'height',H/1080);
end;
procedure PreparePlacements(Project: TRigmMovieProject; Cache: TRigmThumbnailCache);
begin
  var Selected := JA(Project.ScriptWizard,'selectedCharacters'); var Items := TJSONArray.Create;
  try
    for var I := 0 to Selected.Count-1 do begin
      var Path := JS(TJSONObject(Selected[I]),'path'); var Old := Placement(Project,Path); var O: TJSONObject;
      if Old<>nil then O := Old.Clone as TJSONObject
      else O := DefaultScriptPlacement(Project,Cache,Path);
      Items.AddElement(O);
      ValidatePlacement(O);
    end;
    PsdJson.Put(Project.ScriptWizard,'placements',Items); Items := nil;
    var SelectedPath := JS(Project.ScriptWizard,'placementSelected');
    if Placement(Project,SelectedPath)=nil then SelectedPath := JS(TJSONObject(Selected[0]),'path');
    PsdJson.Put(Project.ScriptWizard,'placementSelected',SelectedPath);
    PsdJson.Put(Project.ScriptWizard,'placementStatus','in-progress');
  finally Items.Free; end;
end;
end.
