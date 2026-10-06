unit RigmScriptSummaryModel;
// 人間の総評draftとチャート。追加セリフだけを生成し、本編の配役・音声・画像を保持する。
interface
uses System.JSON, RigmMovieModel;
procedure PrepareScriptSummary(Project: TRigmMovieProject);
procedure ValidateScriptSummary(Project: TRigmMovieProject);
procedure SetScriptSummaryDraft(Project: TRigmMovieProject; Draft: TJSONObject);
function ScriptSummaryChart(Draft: TJSONObject): TJSONObject;
procedure MaterializeScriptSummary(Project: TRigmMovieProject);
procedure DisableScriptSummary(Project: TRigmMovieProject);
function ScriptSummaryCue(Project: TRigmMovieProject): TRigmMovieCue;
procedure SyncSummarySubtitle(Project: TRigmMovieProject; const CueId: string);
implementation
uses System.SysUtils, System.StrUtils, System.Generics.Collections, RigmJson, PsdJson, RigmMovieComposition,
  RigmMovieChart, RigmScriptVoiceModel, RigmScriptCastingModel, RigmScriptSubtitleModel;
function ScriptSummaryCue(Project: TRigmMovieProject): TRigmMovieCue;
begin Result := nil; if Project.ScriptWizard.GetValue('summaryData') is TJSONObject then Result := Project.Cue(JS(JO(Project.ScriptWizard,'summaryData'),'cueId')); end;
procedure SyncSummarySubtitle(Project: TRigmMovieProject; const CueId: string);
begin var C := Project.Cue(CueId); if (C=nil) or (C<>ScriptSummaryCue(Project)) then Exit; var O := JO(Project.ScriptWizard,'summaryData'); PsdJson.Put(JO(O,'draft'),'subtitle',C.Subtitle); PsdJson.Put(JO(O,'appliedDraft'),'subtitle',C.Subtitle); end;
procedure ValidateDraft(D: TJSONObject);
begin
  for var Key in ['kind','title','minimum','maximum'] do begin if not(D.GetValue(Key) is TJSONString) then raise Exception.Create('総評設定は文字列で保存してください。'); ValidateVoiceReading(JS(D,Key)); end;
  if not(D.GetValue('role') is TJSONNumber) or (JN(D,'role',-1)<>JI(D,'role',-1)) then raise Exception.Create('キャラ番号は整数です。');
  for var Key in ['text','subtitle','reading'] do begin if not(D.GetValue(Key) is TJSONString) then raise Exception.Create('総評の文章形式が不正です。'); if Key='subtitle' then ValidateSubtitleText(JS(D,Key)) else ValidateVoiceReading(JS(D,Key)); end;
  if not MatchStr(JS(D,'kind'),['radar','bar']) or (Length(JS(D,'title'))>120) or (Length(JS(D,'minimum'))>32) or (Length(JS(D,'maximum'))>32) or (JI(D,'role',-1)<0) or (JI(D,'role')>9) or not(D.GetValue('items') is TJSONArray) then raise Exception.Create('総評設定の形式が不正です。');
  if (JA(D,'items').Count<3) or (JA(D,'items').Count>8) then raise Exception.Create('評価要素は3～8個です。');
  for var V in JA(D,'items') do begin if not(V is TJSONObject) then raise Exception.Create('評価要素が不正です。'); var O := TJSONObject(V);
    if not(O.GetValue('label') is TJSONString) or not(O.GetValue('value') is TJSONString) or (Length(JS(O,'label'))>24) or (Length(JS(O,'value'))>32) then raise Exception.Create('評価要素名は24文字、数値入力は32文字以内です。'); ValidateVoiceReading(JS(O,'label'));
  end;
end;
procedure PrepareScriptSummary(Project: TRigmMovieProject);
begin
  if Project.ScriptWizard.GetValue('summaryData')=nil then Project.ScriptWizard.AddPair('summaryData',PsdJson.ObjectText('{"format":"RIGMMaker.ScriptSummary","schemaVersion":1,"materialized":false,"status":"draft","draft":{"text":"","subtitle":"","reading":"","role":0,"kind":"radar","title":"","minimum":"0","maximum":"5","items":[{"label":"","value":""},{"label":"","value":""},{"label":"","value":""}]}}'));
  ValidateScriptSummary(Project);
end;
procedure ValidateScriptSummary(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'summaryData'); if (JS(O,'format')<>'RIGMMaker.ScriptSummary') or (JI(O,'schemaVersion')<>1) or not(O.GetValue('draft') is TJSONObject) or not MatchStr(JS(O,'status'),['draft','complete']) then raise Exception.Create('総評の保存形式が不正です。'); ValidateDraft(JO(O,'draft'));
  if JB(O,'materialized') then begin
    if not(O.GetValue('appliedDraft') is TJSONObject) then raise Exception.Create('総評の反映済み入力がありません。'); ValidateDraft(JO(O,'appliedDraft'));
    var C := ScriptSummaryCue(Project); var S := Project.Scene(JS(O,'sceneId'));
    if (C=nil) or (S=nil) or (C.Scene<>S.Id) or (CastingRow(Project,C.Id)<>nil) or not MovieChartEnabled(S.Chart) then raise Exception.Create('総評セリフとチャートの参照が不正です。'); ValidateMovieChart(S.Chart);
    var Role := CastingRole(Project,JI(JO(O,'appliedDraft'),'role')); if (Role=nil) or (C.SpeakerId<>JS(Role,'speakerId')) then raise Exception.Create('総評の配役が不正です。');
    var Count := 0; for var Cue in Project.Cues do if Cue.Scene=S.Id then Inc(Count); if Count<>1 then raise Exception.Create('総評sceneのセリフ参照が不正です。');
  end;
end;
procedure SetScriptSummaryDraft(Project: TRigmMovieProject; Draft: TJSONObject);
begin
  ValidateDraft(Draft); PrepareScriptSummary(Project); var O := JO(Project.ScriptWizard,'summaryData'); if JO(O,'draft').ToJSON=Draft.ToJSON then Exit;
  PsdJson.Put(O,'draft',Draft.Clone as TJSONObject); PsdJson.Put(O,'status','draft');
end;
function ScriptSummaryChart(Draft: TJSONObject): TJSONObject;
  function Number(const Text,LabelText: string): Double;
  begin if not TryStrToFloat(Text,Result,TFormatSettings.Invariant) then raise Exception.Create(LabelText+'を数値で入力してください。'); end;
begin
  ValidateDraft(Draft); Result := TJSONObject.Create;
  try Result.AddPair('kind',JS(Draft,'kind')); Result.AddPair('title',JS(Draft,'title')); AddN(Result,'minimum',Number(JS(Draft,'minimum'),'最小値')); AddN(Result,'maximum',Number(JS(Draft,'maximum'),'最大値'));
    var A := TJSONArray.Create; Result.AddPair('items',A); for var V in JA(Draft,'items') do begin var D := TJSONObject(V); var O := TJSONObject.Create; A.AddElement(O); O.AddPair('label',JS(D,'label')); AddN(O,'value',Number(JS(D,'value'),JS(D,'label'))); end; ValidateMovieChart(Result);
  except Result.Free; raise; end;
end;
procedure MaterializeScriptSummary(Project: TRigmMovieProject);
begin
  PrepareScriptSummary(Project); var O := JO(Project.ScriptWizard,'summaryData'); var D := JO(O,'draft'); if JS(D,'text').Trim='' then raise Exception.Create('総評の音声文を人間が入力してください。');
  var Role := CastingRole(Project,JI(D,'role')); if Role=nil then raise Exception.Create('総評を読むキャラ番号を選んでください。'); var Chart := ScriptSummaryChart(D);
  try
    var C := ScriptSummaryCue(Project); var S := Project.Scene(JS(O,'sceneId'));
    if not JB(O,'materialized') then begin
      if O.GetValue('archivedCue') is TJSONObject then C := TRigmMovieCue.FromJson(JO(O,'archivedCue')) else C := TRigmMovieCue.Create;
      if O.GetValue('archivedScene') is TJSONObject then S := TRigmMovieScene.FromJson(JO(O,'archivedScene')) else S := TRigmMovieScene.Create;
      Project.Cues.Add(C); var Index := Project.Scenes.Count;
      for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='closing' then begin Index := Project.Scenes.IndexOf(Project.Scene(Project.Cue(JS(TJSONObject(V),'cueId')).Scene)); Break; end;
      Project.Scenes.Insert(Index,S); PsdJson.Put(O,'cueId',C.Id); PsdJson.Put(O,'sceneId',S.Id); PsdJson.Put(O,'materialized',TJSONBool.Create(True));
    end;
    C.Scene := S.Id; C.SpeakerId := JS(Role,'speakerId'); C.Text := JS(D,'text'); C.Subtitle := JS(D,'subtitle'); C.VoiceReading := JS(D,'reading');
    S.Title := '総評'; S.DisplayMode := 'image'; S.Chart.Free; S.Chart := Chart; Chart := nil;
    PsdJson.Put(O,'appliedDraft',D.Clone as TJSONObject); PsdJson.Put(O,'status','complete');
  finally Chart.Free; end;
end;
procedure DisableScriptSummary(Project: TRigmMovieProject);
begin
  if not(Project.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit; var O := JO(Project.ScriptWizard,'summaryData'); if not JB(O,'materialized') then Exit; ValidateScriptSummary(Project);
  var C := ScriptSummaryCue(Project); var S := Project.Scene(JS(O,'sceneId')); PsdJson.Put(O,'archivedCue',C.Json); PsdJson.Put(O,'archivedScene',S.Json);
  Project.Cues.Remove(C); Project.Scenes.Remove(S); PsdJson.Put(O,'materialized',TJSONBool.Create(False));
  if JS(JO(Project.ScriptWizard,'voice'),'selectedCue')=JS(O,'cueId') then PsdJson.Put(JO(Project.ScriptWizard,'voice'),'selectedCue',Project.Cues[0].Id);
  if JS(JO(Project.ScriptWizard,'subtitles'),'selectedCue')=JS(O,'cueId') then PsdJson.Put(JO(Project.ScriptWizard,'subtitles'),'selectedCue',Project.Cues[0].Id);
  if JS(JO(Project.ScriptWizard,'scenes'),'selectedScene')=JS(O,'sceneId') then PsdJson.Put(JO(Project.ScriptWizard,'scenes'),'selectedScene',Project.Scenes[0].Id);
end;
end.
