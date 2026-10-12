// 総評の改行ごとの音声・共通チャート・旧保存の移行を所有台本で確認する。
function SummaryCues(P: TRigmMovieProject): TArray<TRigmMovieCue>;
begin
  Result := nil;
  for var C in P.Cues do if IsScriptSummaryCue(P,C) then begin SetLength(Result,Length(Result)+1); Result[High(Result)] := C; end;
end;
procedure CheckSummaryLines;
begin
  var P := W.ScriptDraft; var Cues := SummaryCues(P); var SceneId := Cues[0].Scene;
  Check(Length(Cues)=6,'six summary source lines create six casting and voice cues');
  var Sections := JA(JO(P.ScriptWizard,'casting'),'rows');
  for var C in Cues do begin
    var Row := CastingRow(P,C.Id);
    Check((C.Scene=SceneId) and (JS(Row,'section')='summary') and not C.Text.Contains(#13#10) and
      (C.Text=JS(ScriptSection(P,'summary'),'text').Substring(JI(Row,'offset'),JI(Row,'length'))),
      'each summary line points to its source range and the same chart scene '+C.Text);
    Check(not ScriptSceneStartEditable(P,P.Cues.IndexOf(C)),'summary line cannot split its chart scene '+C.Text);
  end;
  Check((P.Cues.IndexOf(Cues[High(Cues)])<P.Cues.Count-1) and MovieChartEnabled(P.Scene(SceneId).Chart),
    'all six summary lines precede closing in one enabled chart scene');
  Check(Length(ScriptSceneAssignmentCueIndices(P))=P.Cues.Count-6,'assignment excludes every summary line');
  W.RefreshVoiceCatalog; WaitVoice;
  var Style := StageFrame(TRigmScriptCastingFrame).FindComponent('ScriptCastingVoiceStyle') as TComboBox;
  Style.ItemIndex := 1; Style.OnChange(Style);
  var Ids: TArray<string>; SetLength(Ids,P.Cues.Count);
  for var I := 0 to P.Cues.Count-1 do Ids[I] := P.Cues[I].Id;
  for var Id in Ids do W.AssignCasting(Id,1,True);
  Go('subtitles'); Cues := SummaryCues(P);
  W.EditSubtitle(Cues[1].Id,'二行目の字幕','');
  Go('voice'); Cues := SummaryCues(P); // 工程保存でcue所有リストが入れ替わる。
  var List := StageFrame(TRigmScriptVoiceFrame).FindComponent('ScriptVoiceRows') as TListView;
  Check(List.Items.Count=P.Cues.Count,'voice list includes every ordinary and summary cue');
  for var C in Cues do begin
    var Found := False;
    for var Item in List.Items do if Item.SubItems[1]=C.Id then Found := Item.SubItems[0]=C.Text;
    Check(Found,'voice list displays the full individual summary line '+C.Text);
    W.SelectVoice(C.Id); W.GenerateVoice(C.Id,False);
    var Deadline := GetTickCount64+15000;
    repeat Application.ProcessMessages; Sleep(10);
      if GetTickCount64>Deadline then raise Exception.Create('Summary fixture synthesis timed out');
    until not W.VoiceBusy;
    var Generated := W.VoiceStatus;
    try if JS(Generated,'error')<>'' then raise Exception.Create(JS(Generated,'error')); finally Generated.Free; end;
    Check(P.AudioReady(C) and FileExists(ResolveMoviePath(P.FileName,C.WaveFile)),
      'summary line synthesizes and stores its own audio '+C.Text);
  end;
  var Args := TJSONObject.Create;
  try
    Args.AddPair('projectId',P.Id); AddN(Args,'revision',P.Revision); var Status := W.ReadScriptSummary(Args);
    try Check((JI(Status,'cueCount')=6) and (JA(Status,'cues').Count=6) and JB(Status,'audioReady'),
      'summary pipe returns all six cues and aggregate audio readiness'); finally Status.Free; end;
  finally Args.Free; end;
  var Total := 0.0;
  for var C in Cues do begin
    Total := Total+P.CueDuration(C);
    var Local,Start,SceneStart,SceneLocal: Double;
    var Time := P.CueStart(C)+0.01;
    Check((P.CueAt(Time,Local,Start)=C) and (P.SceneAt(Time,SceneStart,SceneLocal).Id=SceneId),
      'movie timeline plays each summary cue within its shared chart scene '+C.Text);
  end;
  Check(Abs(P.SceneDuration(P.Scene(SceneId))-Total-P.Scene(SceneId).Padding)<0.001,
    'summary chart duration covers all six audio cues');
  W.EditVoice(Cues[1].Id,'総評二行目の独自読み。',Cues[1].VoiceSettings);
  Check(JS(JO(JO(P.ScriptWizard,'summaryData'),'draft'),'reading').Contains(Cues[0].Text+#13#10+'総評二行目の独自読み。'),
    'editing one summary reading retains the other source readings in the shared draft');
  var Snapshot := P.Clone;
  try
    var SavedCue := Snapshot.Cue(Cues[1].Id).Json; var FirstId := Cues[0].Id;
    try
      PrepareScriptCasting(Snapshot);
      Check(Snapshot.Cue(Cues[1].Id).Json.ToJSON=SavedCue.ToJSON,'casting preparation preserves individual summary reading and subtitle');
      var Chart := Snapshot.Scene(SceneId).Chart.ToJSON;
      DisableScriptSummary(Snapshot);
      Check((Length(SummaryCues(Snapshot))=0) and (Snapshot.Scene(SceneId)=nil) and
        (JA(JO(Snapshot.ScriptWizard,'summaryData'),'archivedCues').Count=6),'summary-none archives and removes all six cues and the chart scene');
      PrepareScriptCasting(Snapshot);
      Check((Length(SummaryCues(Snapshot))=6) and (Snapshot.Cue(Cues[1].Id).Json.ToJSON=SavedCue.ToJSON) and
        (Snapshot.Scene(SceneId).Chart.ToJSON=Chart),'reenabling the same summary restores all cue IDs, edits, audio and chart');
      // 未変更の行に音声がある状態で、総評の1行だけを書き換える。
      var D := JO(JO(Snapshot.ScriptWizard,'summaryData'),'draft');
      PsdJson.Put(D,'reading',''); PsdJson.Put(JO(JO(Snapshot.ScriptWizard,'summaryData'),'appliedDraft'),'reading','');
      var Source := JS(D,'text').Replace('総評の三行目。','修正した総評の三行目。');
      PsdJson.Put(D,'text',Source); PsdJson.Put(ScriptSection(Snapshot,'summary'),'text',Source);
      PrepareScriptCasting(Snapshot);
      Check((Snapshot.Cue(FirstId).Json.ToJSON=P.Cue(FirstId).Json.ToJSON) and Snapshot.AudioReady(Snapshot.Cue(FirstId)),
        'editing one summary source line preserves unchanged summary IDs, audio and chart assignment');
      Check((Length(SummaryCues(Snapshot))=6) and (Snapshot.Scene(SceneId)<>nil),'summary text edits keep exactly one shared chart scene');
    finally SavedCue.Free; end;
  finally Snapshot.Free; end;
  Snapshot := P.Clone;
  try
    var D := JO(JO(Snapshot.ScriptWizard,'summaryData'),'draft');
    var Text := '追加した総評。'+#13#10+JS(D,'text');
    PsdJson.Put(D,'text',Text); PsdJson.Put(ScriptSection(Snapshot,'summary'),'text',Text);
    PrepareScriptCasting(Snapshot); ValidateScriptSummary(Snapshot); ValidateScriptCasting(Snapshot);
    var Added := SummaryCues(Snapshot)[0];
    Check((Length(SummaryCues(Snapshot))=7) and (Added.Text='追加した総評。') and (Added.VoiceReading='') and
      (Added.Scene=SceneId) and (Snapshot.Cue(Cues[1].Id).VoiceReading='総評二行目の独自読み。'),
      'inserting a summary line keeps existing readings and uses source speech for the new line');
  finally Snapshot.Free; end;
  Snapshot := P.Clone;
  try
    var D := JO(JO(Snapshot.ScriptWizard,'summaryData'),'draft');
    var Text := JS(D,'text').Replace(#13#10,#13#10+#13#10);
    PsdJson.Put(D,'text',Text); PsdJson.Put(ScriptSection(Snapshot,'summary'),'text',Text);
    PrepareScriptCasting(Snapshot); ValidateScriptSummary(Snapshot); ValidateScriptCasting(Snapshot);
    Check(Length(SummaryCues(Snapshot))=6,'blank lines in summary source do not create empty audio cues or extra scenes');
  finally Snapshot.Free; end;
  W.SaveScriptDraft(False); Cues := SummaryCues(P);
  var Reloaded := LoadMovie(P.FileName);
  try Check((Length(SummaryCues(Reloaded))=6) and (Reloaded.Cue(Cues[1].Id).VoiceReading='総評二行目の独自読み。'),
    'six summary cues and their individual readings survive save and reload'); finally Reloaded.Free; end;
  // 保存済みの旧「複数行で1セリフ」を再現する。実ユーザーの台本は書き換えない。
  var Legacy := P.Clone;
  try
    var First := Legacy.Cue(Cues[0].Id); var Summary := JO(Legacy.ScriptWizard,'summaryData');
    PsdJson.Put(JO(Summary,'draft'),'reading',''); PsdJson.Put(JO(Summary,'appliedDraft'),'reading','');
    First.Text := JS(ScriptSection(Legacy,'summary'),'text'); First.Subtitle := ''; First.VoiceReading := '';
    var Row := CastingRow(Legacy,First.Id); PsdJson.Put(Row,'offset',TJSONNumber.Create(0)); PsdJson.Put(Row,'length',TJSONNumber.Create(Length(First.Text)));
    var Rows := TJSONArray.Create;
    for var V in JA(JO(Legacy.ScriptWizard,'casting'),'rows') do
      if (JS(TJSONObject(V),'section')<>'summary') or (JS(TJSONObject(V),'cueId')=First.Id) then Rows.AddElement(V.Clone as TJSONValue);
    PsdJson.Put(JO(Legacy.ScriptWizard,'casting'),'rows',Rows); Summary.RemovePair('cueIds').Free;
    for var I := Legacy.Cues.Count-1 downto 0 do
      if (Legacy.Cues[I].Scene=SceneId) and (Legacy.Cues[I].Id<>First.Id) then Legacy.Cues.Delete(I);
    First.AudioKey := Legacy.AudioFingerprint(First); First.VoiceHeardKey := First.AudioKey;
    for var Key in ['casting','subtitles','voice','voiceEffects'] do
      if Legacy.ScriptWizard.GetValue(Key) is TJSONObject then PsdJson.Put(JO(Legacy.ScriptWizard,Key),'selectedCue',First.Id);
    RequestScriptCasting(Legacy); ValidateScriptSummary(Legacy); Legacy.Validate;
    var OldJson := First.Json; var Primary := Legacy.Cues[0].Json;
    try
      SaveMovie(Legacy,P.FileName); var Fresh := TRigmWizardWorkspace.Create(nil);
      try
        Fresh.StartPipe(Main.DataRoot); Fresh.OpenScriptDraft(P.FileName);
        var Upgraded := Fresh.ScriptDraft;
        Check((Fresh.CurrentScriptStage='voice') and (Length(SummaryCues(Upgraded))=6),
          'opening a saved legacy voice-stage project automatically splits all six summary lines');
        Check((Upgraded.Cues[0].Json.ToJSON=Primary.ToJSON) and (ScriptSummaryCue(Upgraded).Id=First.Id) and
          (ScriptSummaryCue(Upgraded).Scene=SceneId),'legacy migration preserves ordinary cues and the first summary ID and chart');
        Check(JO(JO(JO(Upgraded.ScriptWizard,'summaryData'),'lineMigration'),'cue').ToJSON=OldJson.ToJSON,
          'legacy migration archives the original whole-summary cue and audio references');
        var Confirmed := True;
        for var C in SummaryCues(Upgraded) do Confirmed := Confirmed and JB(CastingRow(Upgraded,C.Id),'confirmed') and
          (C.SpeakerId=First.SpeakerId) and not Upgraded.AudioReady(C) and (C.VoiceQuery='');
        Check(Confirmed,'migrated lines retain confirmed roles and require their own regenerated audio');
        Check(not UpgradeScriptSummaryLines(Upgraded),'legacy summary migration runs only once');
        ValidateScriptSummary(Upgraded); ValidateScriptCasting(Upgraded); Upgraded.Validate;
      finally Fresh.Free; end;
    finally Primary.Free; OldJson.Free; end;
    // 所有ワークスペースの正本を保存し直す。
    SaveMovie(P,P.FileName);
  finally Legacy.Free; end;
  Capture('summary-six-lines-voice');
end;
