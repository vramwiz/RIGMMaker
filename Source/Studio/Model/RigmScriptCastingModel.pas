unit RigmScriptCastingModel;

// 台本文を保存モデルのセリフ・シーンへ接続し、配役番号と人の確認を保持する。
interface
uses System.JSON, RigmMovieModel;
procedure PrepareScriptCasting(Project: TRigmMovieProject); // 未変更区分の配役・字幕・音声を保持して準備する。
function UpgradeScriptCastingLines(Project: TRigmMovieProject): Boolean; // 未割当・未編集の旧配役だけを改行単位へ更新する。
function UpgradeScriptSummaryLines(Project: TRigmMovieProject): Boolean; // 旧総評1行を配役・音声を保持して改行単位へ移行する。
function CastingFingerprint(Project: TRigmMovieProject): string; // 原稿・セリフ境界・キャラ番号の指紋。
function CastingRow(Project: TRigmMovieProject; const CueId: string): TJSONObject; // 借用。未登録ならnil。
function CastingRole(Project: TRigmMovieProject; Number: Integer): TJSONObject; // 借用。無効番号ならnil。
function ScriptCueRole(Project: TRigmMovieProject; const CueId: string): Integer;
procedure RequestScriptCasting(Project: TRigmMovieProject); // 人の確定配役を保持して新しい依頼を作る。
procedure SubmitScriptCasting(Project: TRigmMovieProject; Args: TJSONObject); // 現原稿への提案を原子的に反映する。
procedure AssignScriptCasting(Project: TRigmMovieProject; const CueId: string; Number: Integer; Confirm: Boolean);
procedure SelectCastingRow(Project: TRigmMovieProject; const CueId: string);
procedure MoveCastingRow(Project: TRigmMovieProject; Delta: Integer);
procedure SplitCastingRow(Project: TRigmMovieProject; const CueId: string; Offset: Integer);
procedure MergeCastingRow(Project: TRigmMovieProject; const CueId: string);
procedure InvalidateScriptCasting(Project: TRigmMovieProject); // 前工程の変更後も元配役を保全する。
function ScriptCastingSummary(Project: TRigmMovieProject): TJSONObject; // 呼出側所有。長文は含めない。
procedure ValidateScriptCasting(Project: TRigmMovieProject);
procedure ApplyScriptVoiceDefaults(Project: TRigmMovieProject);
procedure RefreshScriptCastingStatus(Project: TRigmMovieProject);
function UsedCastingRoles(Project: TRigmMovieProject): TJSONArray; // 実セリフが参照する番号。呼出側所有。
function MissingCastingVoices(Project: TRigmMovieProject): Integer;
function ReadCastingExpressionAssets(const Path: string): TJSONObject; // 呼出側所有。実素材の選択肢。
procedure SetCastingExpression(Project: TRigmMovieProject; const CueId,Expression: string;
  Variants: TJSONArray; Assets: TJSONObject; const CharacterPath: string=''); // nilのVariantsは個別差分を保持。
implementation
uses System.SysUtils, System.Types, System.Math, System.StrUtils, System.Hash, System.Generics.Collections,
  RigmJson, PsdJson, RigmScriptTextModel, RigmScriptReviewModel, RigmMovieComposition, RigmScriptSummaryModel,
  RigmMovieActing, RigmCharacterCatalog, RigmStorage, RigmModel;
function ReadCastingExpressionAssets(const Path: string): TJSONObject;
begin
  if CharacterFormat(Path)='psd' then Exit(ReadPsdActorAssets(Path));
  var D := LoadRigm(Path); try Result := MovieActorAssets(D); finally D.Free; end;
end;
procedure SetCastingExpression(Project: TRigmMovieProject; const CueId,Expression: string;
  Variants: TJSONArray; Assets: TJSONObject; const CharacterPath: string);
begin
  var C := Project.Cue(CueId);
  if (C=nil) or (CastingRow(Project,CueId)=nil) then raise Exception.Create('表情を設定するセリフを選んでください。');
  if (Expression<>'auto') and not MatchText(Expression,MovieEmotionIds) then raise Exception.Create('表情の選択が不正です。');
  var Checked: TRigmMovieActing := nil;
  try
    if Variants<>nil then begin
      var O := C.Acting.Json;
      try PsdJson.Put(O,'variants',Variants.Clone as TJSONArray); Checked := TRigmMovieActing.FromJson(O); finally O.Free; end;
      if (Checked.Variants.Count>0) and (Assets=nil) then raise Exception.Create('キャラを配役してから表情の差分を選んでください。');
      for var V in Checked.Variants do begin
        var Found := False;
        for var G in JA(Assets,'groups') do if JS(TJSONObject(G),'id')=JS(TJSONObject(V),'groupId') then
          for var P in JA(TJSONObject(G),'children') do if JS(TJSONObject(P),'id')=JS(TJSONObject(V),'partId') then Found := True;
        if not Found then raise Exception.Create('選択したキャラに表情の差分がありません。差分を選び直してください。');
      end;
      if (Checked.Variants.Count>0) and (CharacterPath<>'') and (CharacterFormat(CharacterPath)='rigm') then begin
        var D := LoadRigm(CharacterPath); var Pose := TRigmPose.Create;
        try Checked.ApplyVariants(D,Pose); finally Pose.Free; D.Free; end;
      end;
    end;
    C.FaceAutomatic := Expression='auto'; C.Emotion := 'neutral';
    if not C.FaceAutomatic then C.Emotion := LowerCase(Expression);
    C.Expression := 'neutral'; // 旧4種類の変形を二重適用しない。
    if Checked<>nil then begin C.Acting.Free; C.Acting := Checked; Checked := nil; end;
  finally Checked.Free; end;
end;
function CastingRow(Project: TRigmMovieProject; const CueId: string): TJSONObject;
begin
  Result := nil; if not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'cueId')=CueId then Exit(TJSONObject(V));
end;
function CastingRole(Project: TRigmMovieProject; Number: Integer): TJSONObject;
begin
  Result := nil; if not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'roles') do
    if (JI(TJSONObject(V),'number')=Number) and JB(TJSONObject(V),'active') then Exit(TJSONObject(V));
end;
function ScriptCueRole(Project: TRigmMovieProject; const CueId: string): Integer;
begin
  Result := 0; var Row := CastingRow(Project,CueId); if Row<>nil then Exit(JI(Row,'role'));
  if Project.ScriptWizard.GetValue('summaryData') is TJSONObject then begin var O := JO(Project.ScriptWizard,'summaryData'); if JB(O,'materialized') and (JS(O,'cueId')=CueId) then Result := JI(JO(O,'appliedDraft'),'role'); end;
end;
function CastingFingerprint(Project: TRigmMovieProject): string;
begin
  var O := TJSONObject.Create; var Cast := JO(Project.ScriptWizard,'casting');
  try
    O.AddPair('source',ScriptFingerprint(Project)); O.AddPair('roles',JA(Cast,'roles').Clone as TJSONArray);
    var A := TJSONArray.Create; O.AddPair('rows',A);
    for var V in JA(Cast,'rows') do begin
      var Row := TJSONObject(V); var R := TJSONObject.Create; A.AddElement(R);
      R.AddPair('cueId',JS(Row,'cueId')); R.AddPair('section',JS(Row,'section'));
      AddN(R,'offset',JI(Row,'offset')); AddN(R,'length',JI(Row,'length')); R.AddPair('text',Project.Cue(JS(Row,'cueId')).Text);
    end;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
end;
function UsedCastingRoles(Project: TRigmMovieProject): TJSONArray;
begin
  Result := TJSONArray.Create;
  if (Project=nil) or (Project.ScriptWizard=nil) or not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'roles') do begin
    var Role := TJSONObject(V); if not JB(Role,'active') then Continue;
    for var Row in JA(JO(Project.ScriptWizard,'casting'),'rows') do
      if (JI(TJSONObject(Row),'role')=JI(Role,'number')) and (Project.Cue(JS(TJSONObject(Row),'cueId'))<>nil) then begin Result.Add(JI(Role,'number')); Break; end;
  end;
end;
function MissingCastingVoices(Project: TRigmMovieProject): Integer;
begin
  Result := 0; var Used := UsedCastingRoles(Project);
  try for var N in Used do begin
    var Role := CastingRole(Project,StrToInt(N.Value)); var S := Project.Speaker(JS(Role,'speakerId'));
    if (S=nil) or (S.StyleId<0) or (S.VoiceUuid='') then Inc(Result);
  end; finally Used.Free; end;
end;
procedure ApplyScriptVoiceDefaults(Project: TRigmMovieProject);
begin
  for var V in JA(Project.ScriptWizard,'selectedCharacters') do begin
    var C := TJSONObject(V); if not (C.GetValue('voiceBinding') is TJSONObject) then Continue;
    for var R in JA(JO(Project.ScriptWizard,'casting'),'roles') do begin
      var Role := TJSONObject(R); if not JB(Role,'active') or not SameText(JS(Role,'path'),JS(C,'path')) then Continue;
      var S := Project.Speaker(JS(Role,'speakerId')); var Binding := JO(C,'voiceBinding');
      if (S.StyleId<0) and (JI(Binding,'styleId',-1)>=0) and (JS(Binding,'uuid')<>'') then begin
        S.StyleId := JI(Binding,'styleId'); S.VoiceUuid := JS(Binding,'uuid'); S.VoiceName := JS(Binding,'name'); S.StyleName := JS(Binding,'style');
      end;
    end;
  end;
end;
procedure RefreshScriptCastingStatus(Project: TRigmMovieProject);
begin
  var Complete := JS(JO(Project.ScriptWizard,'casting'),'state')<>'stale';
  for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do
    Complete := Complete and JB(TJSONObject(V),'confirmed') and (CastingRole(Project,JI(TJSONObject(V),'role'))<>nil);
  Complete := Complete and (MissingCastingVoices(Project)=0);
  if Complete then PsdJson.Put(Project.ScriptWizard,'castingStatus','complete')
  else PsdJson.Put(Project.ScriptWizard,'castingStatus','in-progress');
end;
procedure RequestScriptCasting(Project: TRigmMovieProject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'sourceFingerprint')<>ScriptFingerprint(Project)) then
    raise Exception.Create('前工程が変わりました。台本確認から配役へ進んで準備してください。');
  PsdJson.Put(Cast,'requestId',PsdJson.NewId); PsdJson.Put(Cast,'fingerprint',CastingFingerprint(Project));
  PsdJson.Put(Cast,'state','requested'); RefreshScriptCastingStatus(Project);
end;
procedure InvalidateScriptCasting(Project: TRigmMovieProject);
begin
  if not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  PsdJson.Put(JO(Project.ScriptWizard,'casting'),'state','stale'); PsdJson.Put(Project.ScriptWizard,'castingStatus','in-progress');
end;
procedure SelectCastingRow(Project: TRigmMovieProject; const CueId: string);
begin
  if CastingRow(Project,CueId)=nil then raise Exception.Create('配役するセリフを選んでください。');
  PsdJson.Put(JO(Project.ScriptWizard,'casting'),'selectedCue',CueId);
end;
procedure MoveCastingRow(Project: TRigmMovieProject; Delta: Integer);
begin
  var Cast := JO(Project.ScriptWizard,'casting'); var Rows := JA(Cast,'rows'); var Index := 0;
  for var I := 0 to Rows.Count-1 do if JS(TJSONObject(Rows[I]),'cueId')=JS(Cast,'selectedCue') then Index := I;
  SelectCastingRow(Project,JS(TJSONObject(Rows[EnsureRange(Index+Delta,0,Rows.Count-1)]),'cueId'));
end;
procedure AssignScriptCasting(Project: TRigmMovieProject; const CueId: string; Number: Integer; Confirm: Boolean);
begin
  var Cast := JO(Project.ScriptWizard,'casting'); var Row := CastingRow(Project,CueId); var Role := CastingRole(Project,Number);
  if (Row=nil) or (Role=nil) or (JS(Cast,'state')='stale') then raise Exception.Create('有効なキャラ番号と現在のセリフを選んでください。');
  var C := Project.Cue(CueId);
  if C.SpeakerId<>JS(Role,'speakerId') then begin C.Acting.Variants.Free; C.Acting.Variants := TJSONArray.Create; C.VoiceStyleId := -1; C.VoiceQuery := ''; C.VoiceQueryKey := ''; end;
  C.SpeakerId := JS(Role,'speakerId');
  PsdJson.Put(Row,'role',TJSONNumber.Create(Number)); PsdJson.Put(Row,'confirmed',TJSONBool.Create(True));
  if not Confirm then PsdJson.Put(Row,'origin','human');
  SelectCastingRow(Project,CueId); MoveCastingRow(Project,1); RefreshScriptCastingStatus(Project);
end;
procedure AddLineCues(const Text,Section,SceneId: string; Start,Finish: Integer;
  Cues: TObjectList<TRigmMovieCue>; Rows: TJSONArray; TemplateCue: TRigmMovieCue=nil; TemplateRow: TJSONObject=nil);
begin
  var Reused := False;
  while Start<Finish do begin
    var LineEnd := Text.IndexOf(#13#10,Start); if (LineEnd<0) or (LineEnd>Finish) then LineEnd := Finish;
    if Trim(Text.Substring(Start,LineEnd-Start))<>'' then
      while Start<LineEnd do begin
        var Count := Min(2000,LineEnd-Start); if not ScriptTextBoundary(Text,Start+Count) then Dec(Count);
        var C: TRigmMovieCue;
        if TemplateCue=nil then C := TRigmMovieCue.Create
        else begin
          var Q := TemplateCue.Json; try C := TRigmMovieCue.FromJson(Q); finally Q.Free; end;
          if Reused then C.Id := PsdJson.NewId;
        end;
        Reused := True; C.Scene := SceneId; C.Text := Text.Substring(Start,Count); C.Subtitle := C.Text; Cues.Add(C);
        var Row: TJSONObject;
        if TemplateRow<>nil then Row := TemplateRow.Clone as TJSONObject
        else begin Row := TJSONObject.Create; AddN(Row,'role',0); Row.AddPair('origin','unassigned'); AddB(Row,'confirmed',False); end;
        Rows.AddElement(Row); PsdJson.Put(Row,'cueId',C.Id); PsdJson.Put(Row,'section',Section);
        PsdJson.Put(Row,'offset',TJSONNumber.Create(Start)); PsdJson.Put(Row,'length',TJSONNumber.Create(Count));
        Inc(Start,Count);
      end;
    Start := LineEnd+2;
  end;
end;
function UpgradeScriptCastingLines(Project: TRigmMovieProject): Boolean;
begin
  Result := False;
  if (Project.ScriptWizard=nil) or not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  if not MatchText(JS(Project.ScriptWizard,'stage'),['review','casting']) then Exit;
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'sourceFingerprint')<>ScriptFingerprint(Project)) then Exit;
  for var Key in ['subtitles','voice','scenes','summaryData','closingData'] do if Project.ScriptWizard.GetValue(Key)<>nil then Exit;
  var HasLines := False;
  for var V in JA(Cast,'rows') do begin
    var Row := TJSONObject(V); var C := Project.Cue(JS(Row,'cueId')); if C=nil then Exit;
    // 人の配役、AI候補、独立字幕、読み、音声資産を自動更新で失わない。
    if JB(Row,'confirmed') or (JI(Row,'role')<>0) or (JS(Row,'origin')<>'unassigned') or
      (C.SpeakerId<>'narrator') or (C.Subtitle<>C.Text) or (C.SubtitleNote<>'') or
      (C.VoiceReading<>'') or (C.VoiceSettings.Count>0) or (C.VoiceStyleId>=0) or
      (C.WaveFile<>'') or (C.LabFile<>'') or (C.AudioKey<>'') or (C.AudioSeconds<>0) then Exit;
    var Text := JS(ScriptSection(Project,JS(Row,'section')),'text');
    if C.Text<>Text.Substring(JI(Row,'offset'),JI(Row,'length')) then Exit;
    HasLines := HasLines or C.Text.Contains(#13#10);
  end;
  if not HasLines then Exit;
  ValidateScriptCasting(Project);
  var Snapshot := Project.Clone;
  try
    Snapshot.Cues.Clear; var Rows := TJSONArray.Create; PsdJson.Put(JO(Snapshot.ScriptWizard,'casting'),'rows',Rows);
    for var V in JA(Cast,'rows') do begin
      var Row := TJSONObject(V); var C := Project.Cue(JS(Row,'cueId'));
      AddLineCues(JS(ScriptSection(Project,JS(Row,'section')),'text'),JS(Row,'section'),C.Scene,
        JI(Row,'offset'),JI(Row,'offset')+JI(Row,'length'),Snapshot.Cues,Rows,C,Row);
    end;
    if (Rows.Count=0) or (Rows.Count>2000) then raise Exception.Create('セリフは1～2000件の範囲にしてください。');
    RequestScriptCasting(Snapshot); ValidateScriptCasting(Snapshot);
    Project.Cues.Free; Project.Cues := Snapshot.Cues; Snapshot.Cues := TObjectList<TRigmMovieCue>.Create(True);
    PsdJson.Put(Project.ScriptWizard,'casting',JO(Snapshot.ScriptWizard,'casting').Clone as TJSONObject);
    PsdJson.Put(Project.ScriptWizard,'castingStatus',JS(Snapshot.ScriptWizard,'castingStatus')); Result := True;
  finally Snapshot.Free; end;
end;
{$I RigmScriptCastingReuse.inc}
procedure AddScriptSummaryLines(Project: TRigmMovieProject; Old: TJSONObject; const Text: string;
  Cues: TObjectList<TRigmMovieCue>; Rows: TJSONArray; Scenes: TObjectList<TRigmMovieScene>);
begin
  var O := JO(Project.ScriptWizard,'summaryData'); var D := JO(O,'draft');
  var First := ScriptSummaryCue(Project); var Scene := Project.Scene(JS(O,'sceneId'));
  if Scene=nil then begin
    if O.GetValue('archivedScene') is TJSONObject then Scene := TRigmMovieScene.FromJson(JO(O,'archivedScene'))
    else Scene := TRigmMovieScene.Create;
  end else begin var Q := Scene.Json; try Scene := TRigmMovieScene.FromJson(Q); finally Q.Free; end; end;
  Scenes.Add(Scene);
  var Start := Cues.Count; var Parts := ScriptSourceParts(Text);
  // 独立した読みの区切りが原稿と異なる場合は、入力済みの一続きの読みを保つ。
  var ReadingParts := ScriptSourceParts(JS(D,'reading'));
  var WholeReading := (Length(ReadingParts)>0) and (Length(ReadingParts)<>Length(Parts)) and
    ((O.GetValue('cueIds')=nil) or ((First<>nil) and First.Text.Contains(#13#10)));
  if (First=nil) and (O.GetValue('archivedCues') is TJSONArray) and (O.GetValue('archivedRows') is TJSONArray) then begin
    var Archived := JA(O,'archivedCues'); var SavedRows := JA(O,'archivedRows');
    var Restore := (Archived.Count=Length(Parts)) and (SavedRows.Count=Archived.Count) and not WholeReading;
    if Restore then for var I := 0 to Archived.Count-1 do
      Restore := Restore and (JS(TJSONObject(Archived[I]),'text')=Parts[I].Text);
    if Restore then begin
      for var I := 0 to Archived.Count-1 do begin
        var C := TRigmMovieCue.FromJson(TJSONObject(Archived[I])); C.Scene := Scene.Id; Cues.Add(C);
        var Row := SavedRows[I].Clone as TJSONObject; Rows.AddElement(Row);
        PsdJson.Put(Row,'offset',TJSONNumber.Create(Parts[I].Offset));
      end;
      Exit;
    end;
  end;
  // 初期版の総評はcasting.rowsへ未登録。1行の既存字幕・読み・音声もそのまま引き継ぐ。
  if (First<>nil) and (CastingRow(Project,First.Id)=nil) and (First.Text=Text) and not First.Text.Contains(#13#10) then begin
    var Q := First.Json; try Cues.Add(TRigmMovieCue.FromJson(Q)); finally Q.Free; end;
    var Row := TJSONObject.Create; Rows.AddElement(Row); Row.AddPair('cueId',First.Id); Row.AddPair('section','summary');
    AddN(Row,'offset',0); AddN(Row,'length',Length(Text)); AddN(Row,'role',JI(D,'role'));
    AddB(Row,'confirmed',True); Row.AddPair('origin','human'); Exit;
  end;
  var Legacy := (First<>nil) and First.Text.Contains(#13#10);
  if Legacy or (Old=nil) or WholeReading then begin
    var TemplateRow: TJSONObject := nil;
    if First<>nil then TemplateRow := CastingRow(Project,First.Id);
    if Legacy and (O.GetValue('lineMigration')=nil) then begin
      var Archive := TJSONObject.Create; Archive.AddPair('cue',First.Json);
      if TemplateRow<>nil then Archive.AddPair('row',TemplateRow.Clone as TJSONObject);
      PsdJson.Put(O,'lineMigration',Archive);
    end;
    if WholeReading then begin
      var C := TRigmMovieCue.Create;
      if First<>nil then begin C.Free; var Q := First.Json; try C := TRigmMovieCue.FromJson(Q); finally Q.Free; end; end;
      C.Scene := Scene.Id; C.Text := Text; Cues.Add(C);
      var Row := TJSONObject.Create;
      if TemplateRow<>nil then begin Row.Free; Row := TemplateRow.Clone as TJSONObject; end
      else begin AddN(Row,'role',JI(D,'role')); AddB(Row,'confirmed',False); Row.AddPair('origin','unassigned'); end;
      Rows.AddElement(Row); PsdJson.Put(Row,'cueId',C.Id); PsdJson.Put(Row,'section','summary');
      PsdJson.Put(Row,'offset',TJSONNumber.Create(0)); PsdJson.Put(Row,'length',TJSONNumber.Create(Length(Text)));
    end else begin
      AddLineCues(Text,'summary',Scene.Id,0,Length(Text),Cues,Rows,First,TemplateRow);
      for var I := Start to Cues.Count-1 do begin
        var C := Cues[I]; C.Subtitle := ''; C.VoiceReading := '';
        C.WaveFile := ''; C.LabFile := ''; C.AudioKey := ''; C.AudioSeconds := 0;
        C.VoiceQuery := ''; C.VoiceQueryKey := ''; C.VoiceHeardKey := ''; C.EffectWaveFile := ''; C.EffectAudioKey := '';
      end;
    end;
  end else AddReconciledScriptSection(Project,Old,'summary',Text,Cues,Rows,Scenes,Scene.Id);
  for var I := Start to Cues.Count-1 do begin
    var C := Cues[I]; C.Scene := Scene.Id;
    var Row: TJSONObject := nil;
    for var V in Rows do if JS(TJSONObject(V),'cueId')=C.Id then begin Row := TJSONObject(V); Break; end;
    if (First<>nil) and (Project.Cue(C.Id)=nil) and (JI(Row,'role')=0) then begin
      C.SpeakerId := First.SpeakerId; C.VoiceStyleId := First.VoiceStyleId;
      C.VoiceSettings.Free; C.VoiceSettings := First.VoiceSettings.Clone as TJSONObject;
      var PreviousRow := CastingRow(Project,First.Id);
      if PreviousRow<>nil then begin
        PsdJson.Put(Row,'role',TJSONNumber.Create(JI(PreviousRow,'role'))); PsdJson.Put(Row,'origin',JS(PreviousRow,'origin'));
      end;
    end;
    if (First=nil) and (JI(Row,'role')=0) then PsdJson.Put(Row,'role',TJSONNumber.Create(JI(D,'role')));
  end;
end;
function UpgradeScriptSummaryLines(Project: TRigmMovieProject): Boolean;
begin
  Result := False;
  if (Project.ScriptWizard=nil) or not (Project.ScriptWizard.GetValue('casting') is TJSONObject) or
    (JS(Project.ScriptWizard,'summaryChoice')<>'yes') then Exit;
  var C := ScriptSummaryCue(Project); if (C=nil) or not C.Text.Contains(#13#10) then Exit;
  var D := JO(JO(Project.ScriptWizard,'summaryData'),'draft');
  if (ScriptSummaryDraftReason(D)<>'') or (JS(D,'text')<>C.Text) or
    (JS(JO(Project.ScriptWizard,'casting'),'sourceFingerprint')<>ScriptFingerprint(Project)) then Exit;
  if (JS(D,'reading')<>'') and (Length(ScriptSourceParts(JS(D,'reading')))<>Length(ScriptSourceParts(C.Text))) then Exit;
  var Snapshot := Project.Clone;
  try
    var Selected := JS(JO(Project.ScriptWizard,'casting'),'selectedCue');
    PrepareScriptCasting(Snapshot);
    if CastingRow(Snapshot,Selected)<>nil then PsdJson.Put(JO(Snapshot.ScriptWizard,'casting'),'selectedCue',Selected);
    PsdJson.Put(Snapshot.ScriptWizard,'voiceStatus','in-progress'); Snapshot.Validate;
    Project.Cues.Free; Project.Cues := Snapshot.Cues; Snapshot.Cues := TObjectList<TRigmMovieCue>.Create(True);
    Project.Scenes.Free; Project.Scenes := Snapshot.Scenes; Snapshot.Scenes := TObjectList<TRigmMovieScene>.Create(True);
    Project.Speakers.Free; Project.Speakers := Snapshot.Speakers; Snapshot.Speakers := TObjectList<TRigmMovieSpeaker>.Create(True);
    Project.ScriptWizard.Free; Project.ScriptWizard := Snapshot.ScriptWizard; Snapshot.ScriptWizard := nil; Result := True;
  finally Snapshot.Free; end;
end;
procedure PrepareScriptCasting(Project: TRigmMovieProject);
begin
  var Selected := JA(Project.ScriptWizard,'selectedCharacters');
  if (Selected.Count=0) or (Selected.Count>9) then raise Exception.Create('配役では使用キャラを1～9人にしてください。');
  var Old := Project.ScriptWizard.GetValue('casting') as TJSONObject;
  var Cast := TJSONObject.Create; var NewCues := TObjectList<TRigmMovieCue>.Create(True);
  var NewScenes := TObjectList<TRigmMovieScene>.Create(True);
  try
    Cast.AddPair('format','RIGMMaker.ScriptCasting'); AddN(Cast,'schemaVersion',1);
    var Roles := TJSONArray.Create; Cast.AddPair('roles',Roles);
    if Old<>nil then for var V in JA(Old,'roles') do begin
      var R := V.Clone as TJSONObject; Roles.AddElement(R); PsdJson.Put(R,'active',TJSONBool.Create(False));
    end;
    for var V in Selected do begin
      var S := TJSONObject(V); var Found: TJSONObject := nil;
      for var R in Roles do if SameText(JS(TJSONObject(R),'path'),JS(S,'path')) then Found := TJSONObject(R);
      if Found=nil then begin
        var Number := 0;
        for var N := 1 to 9 do begin
          var Used := False; for var R in Roles do Used := Used or (JI(TJSONObject(R),'number')=N);
          if not Used then begin Number := N; Break; end;
        end;
        if Number=0 then raise Exception.Create('この作品の1～9の番号は使用済みです。既存番号のキャラを選んでください。');
        Found := TJSONObject.Create; Roles.AddElement(Found); AddN(Found,'number',Number);
        Found.AddPair('path',JS(S,'path')); Found.AddPair('name',JS(S,'name')); Found.AddPair('speakerId','script-'+PsdJson.NewId);
      end;
      PsdJson.Put(Found,'active',TJSONBool.Create(True));
      if Project.Speaker(JS(Found,'speakerId'))=nil then begin
        var Speaker := TRigmMovieSpeaker.Create; Speaker.Id := JS(Found,'speakerId'); Speaker.Name := JS(Found,'name'); Project.Speakers.Add(Speaker);
      end;
    end;
    if Project.Speaker('narrator')=nil then Project.Speakers.Add(TRigmMovieSpeaker.Create);
    var Rows := TJSONArray.Create; Cast.AddPair('rows',Rows); var Sections := TJSONArray.Create; Cast.AddPair('sections',Sections);
    var SourceChanged := (Old<>nil) and (JS(Old,'sourceFingerprint')<>ScriptFingerprint(Project));
    if SourceChanged then begin
      if Project.ScriptWizard.GetValue('castingArchives')=nil then Project.ScriptWizard.AddPair('castingArchives',TJSONArray.Create);
      var Archive := TJSONObject.Create; JA(Project.ScriptWizard,'castingArchives').AddElement(Archive);
      Archive.AddPair('casting',Old.Clone as TJSONObject); var A := TJSONArray.Create; Archive.AddPair('cues',A);
      for var C in Project.Cues do A.AddElement(C.Json); A := TJSONArray.Create; Archive.AddPair('scenes',A);
      for var S in Project.Scenes do A.AddElement(S.Json);
    end;
    for var Id in ['opening','body','summary','closing'] do begin
      if (Id='summary') and (JS(Project.ScriptWizard,'summaryChoice')<>'yes') then Continue;
      var Text := JS(ScriptSection(Project,Id),'text'); var S := TJSONObject.Create; Sections.AddElement(S); S.AddPair('id',Id); S.AddPair('text',Text);
      if Id='summary' then begin AddScriptSummaryLines(Project,Old,Text,NewCues,Rows,NewScenes); Continue; end;
      var Unchanged := False;
      if Old<>nil then for var V in JA(Old,'sections') do if (JS(TJSONObject(V),'id')=Id) and (JS(TJSONObject(V),'text')=Text) then Unchanged := True;
      if Unchanged then begin
        for var V in JA(Old,'rows') do if JS(TJSONObject(V),'section')=Id then begin
          var Row := V.Clone as TJSONObject; Rows.AddElement(Row); var C := Project.Cue(JS(Row,'cueId')); var Q := C.Json;
          try NewCues.Add(TRigmMovieCue.FromJson(Q)); finally Q.Free; end;
          var ExistingScene := Project.Scene(C.Scene); var Found := False;
          for var Scene in NewScenes do if Scene.Id=ExistingScene.Id then Found := True;
          if not Found then begin Q := ExistingScene.Json; try NewScenes.Add(TRigmMovieScene.FromJson(Q)); finally Q.Free; end; end;
        end;
        Continue;
      end;
      AddReconciledScriptSection(Project,Old,Id,Text,NewCues,Rows,NewScenes);
    end;
    if Rows.Count=0 then raise Exception.Create('配役するセリフがありません。');
    if Rows.Count>2000 then raise Exception.Create('セリフは既存モデルの2000件上限以内にしてください。');
    Project.Cues.Free; Project.Cues := NewCues; NewCues := nil; Project.Scenes.Free; Project.Scenes := NewScenes; NewScenes := nil;
    Cast.AddPair('sourceFingerprint',ScriptFingerprint(Project)); Cast.AddPair('selectedCue',JS(TJSONObject(Rows[0]),'cueId'));
    Cast.AddPair('state','requested'); Cast.AddPair('requestId',PsdJson.NewId);
    PsdJson.Put(Project.ScriptWizard,'casting',Cast); Cast := nil;
    var Single: TJSONObject := nil;
    if Selected.Count=1 then for var V in Roles do if JB(TJSONObject(V),'active') then Single := TJSONObject(V);
    for var V in Rows do begin
      var Row := TJSONObject(V); var C := Project.Cue(JS(Row,'cueId')); var Role := CastingRole(Project,JI(Row,'role'));
      if (Role<>nil) and (C.SpeakerId='narrator') then C.SpeakerId := JS(Role,'speakerId');
      if Role=nil then begin
        PsdJson.Put(Row,'confirmed',TJSONBool.Create(False));
        if Single<>nil then begin PsdJson.Put(Row,'role',TJSONNumber.Create(JI(Single,'number'))); PsdJson.Put(Row,'origin','single-default'); C.SpeakerId := JS(Single,'speakerId'); end
        else begin PsdJson.Put(Row,'role',TJSONNumber.Create(0)); PsdJson.Put(Row,'origin','unassigned'); C.SpeakerId := 'narrator'; end;
      end;
    end;
    for var Key in ['voice','voiceEffects','subtitles'] do
      if Project.ScriptWizard.GetValue(Key) is TJSONObject then begin
        var Page := JO(Project.ScriptWizard,Key);
        if Project.Cue(JS(Page,'selectedCue'))=nil then PsdJson.Put(Page,'selectedCue',Project.Cues[0].Id);
      end;
    ConfigureScriptSummaryScene(Project);
    ApplyScriptVoiceDefaults(Project); RequestScriptCasting(Project); ValidateScriptCasting(Project); UpgradeScriptCastingLines(Project);
  finally Cast.Free; NewCues.Free; NewScenes.Free; end;
end;
procedure SubmitScriptCasting(Project: TRigmMovieProject; Args: TJSONObject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')<>'requested') or (JS(Args,'requestId')<>JS(Cast,'requestId')) or
    (JS(Args,'fingerprint')<>JS(Cast,'fingerprint')) or (CastingFingerprint(Project)<>JS(Cast,'fingerprint')) then
    raise Exception.Create('配役依頼または原稿が変わりました。最新状態を再取得してください。');
  if not (Args.GetValue('items') is TJSONArray) or (JA(Args,'items').Count>50) then raise Exception.Create('配役提案は50件以内ずつ送ってください。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in JA(Args,'items') do begin
      if not (V is TJSONObject) then raise Exception.Create('配役提案はオブジェクトで指定してください。');
      var O := TJSONObject(V); var Row := CastingRow(Project,JS(O,'cueId')); var Role := CastingRole(Project,JI(O,'role'));
      if (Row=nil) or (Role=nil) or JB(Row,'confirmed') or Seen.ContainsKey(JS(O,'cueId')) or
        (Length(JS(O,'reason'))>2048) then raise Exception.Create('有効な未確定セリフとキャラ番号を指定してください。人の確定配役は変更できません。');
      Seen.Add(JS(O,'cueId'),True);
    end;
    for var V in JA(Args,'items') do begin
      var O := TJSONObject(V); var Row := CastingRow(Project,JS(O,'cueId')); var Role := CastingRole(Project,JI(O,'role'));
      PsdJson.Put(Row,'role',TJSONNumber.Create(JI(O,'role'))); PsdJson.Put(Row,'origin','ai'); PsdJson.Put(Row,'reason',JS(O,'reason'));
      var C := Project.Cue(JS(Row,'cueId'));
      if C.SpeakerId<>JS(Role,'speakerId') then begin C.Acting.Variants.Free; C.Acting.Variants := TJSONArray.Create; C.VoiceStyleId := -1; C.VoiceQuery := ''; C.VoiceQueryKey := ''; end;
      C.SpeakerId := JS(Role,'speakerId');
    end;
    if JB(Args,'complete') then PsdJson.Put(Cast,'state','ready'); RefreshScriptCastingStatus(Project);
  finally Seen.Free; end;
end;
procedure CheckUneditedCue(Project: TRigmMovieProject; Row: TJSONObject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'fingerprint')<>CastingFingerprint(Project)) then
    raise Exception.Create('原稿が変わりました。台本確認から配役へ進んで再確認してください。');
  var C := Project.Cue(JS(Row,'cueId')); var Text := JS(ScriptSection(Project,JS(Row,'section')),'text').Substring(JI(Row,'offset'),JI(Row,'length'));
  if (C.Text<>Text) or (C.Subtitle<>Text) or ((C.VoiceReading<>'') and (C.VoiceReading<>Text)) or
    (C.WaveFile<>'') then raise Exception.Create('字幕・読み・音声を編集済みのセリフは、この工程で分割・結合できません。原稿の行区切りを直してください。');
end;
procedure SplitCastingRow(Project: TRigmMovieProject; const CueId: string; Offset: Integer);
begin
  var Cast := JO(Project.ScriptWizard,'casting'); var Rows := JA(Cast,'rows'); var Row := CastingRow(Project,CueId); if Row=nil then raise Exception.Create('セリフを選んでください。');
  if JS(Row,'section')='summary' then raise Exception.Create('総評の行区切りは台本確認で編集してください。総評は1つのチャートシーンにまとめます。');
  CheckUneditedCue(Project,Row); var C := Project.Cue(CueId);
  if (Offset<=0) or (Offset>=Length(C.Text)) or not ScriptTextBoundary(C.Text,Offset) or
    ((C.Text[Offset]=#13) and (C.Text[Offset+1]=#10)) or
    (Trim(C.Text.Substring(0,Offset))='') or (Trim(C.Text.Substring(Offset))='') then raise Exception.Create('文章内の分割位置を選んでください。');
  var Next := TRigmMovieCue.Create; Next.Scene := C.Scene; Next.SpeakerId := C.SpeakerId;
  Next.VoiceStyleId := C.VoiceStyleId;
  Next.Emotion := C.Emotion; Next.FaceAutomatic := C.FaceAutomatic; Next.Expression := C.Expression;
  var Acting := C.Acting.Json;
  try Next.Acting.Free; Next.Acting := nil; Next.Acting := TRigmMovieActing.FromJson(Acting); finally Acting.Free; end;
  Next.Text := C.Text.Substring(Offset); Next.Subtitle := Next.Text; C.Text := C.Text.Substring(0,Offset); C.Subtitle := C.Text;
  var Index := Project.Cues.IndexOf(C); Project.Cues.Insert(Index+1,Next);
  var NewRow := Row.Clone as TJSONObject; PsdJson.Put(NewRow,'cueId',Next.Id); PsdJson.Put(NewRow,'offset',TJSONNumber.Create(JI(Row,'offset')+Offset));
  PsdJson.Put(NewRow,'length',TJSONNumber.Create(JI(Row,'length')-Offset)); PsdJson.Put(NewRow,'confirmed',TJSONBool.Create(False));
  PsdJson.Put(Row,'length',TJSONNumber.Create(Offset)); PsdJson.Put(Row,'confirmed',TJSONBool.Create(False));
  var Rebuilt := TJSONArray.Create;
  for var V in Rows do begin Rebuilt.AddElement(V.Clone as TJSONObject); if TJSONObject(V)=Row then Rebuilt.AddElement(NewRow); end;
  PsdJson.Put(Cast,'rows',Rebuilt); RequestScriptCasting(Project);
end;
procedure MergeCastingRow(Project: TRigmMovieProject; const CueId: string);
begin
  var Cast := JO(Project.ScriptWizard,'casting'); var Rows := JA(Cast,'rows'); var C := Project.Cue(CueId);
  if (C=nil) or (Project.Cues.IndexOf(C)=Project.Cues.Count-1) then raise Exception.Create('結合する次のセリフがありません。');
  var Next := Project.Cues[Project.Cues.IndexOf(C)+1]; var Row := CastingRow(Project,C.Id); var Other := CastingRow(Project,Next.Id);
  if JS(Row,'section')='summary' then raise Exception.Create('総評のセリフは結合できません。');
  if (C.Scene<>Next.Scene) or (JS(Row,'section')<>JS(Other,'section')) then raise Exception.Create('同じシーン・台本区分内の次のセリフと結合できます。');
  CheckUneditedCue(Project,Row); CheckUneditedCue(Project,Other);
  var Count := JI(Other,'offset')+JI(Other,'length')-JI(Row,'offset'); if Count>2000 then raise Exception.Create('結合後の音声文は2000文字以内にしてください。');
  C.Text := JS(ScriptSection(Project,JS(Row,'section')),'text').Substring(JI(Row,'offset'),Count); C.Subtitle := C.Text;
  PsdJson.Put(Row,'length',TJSONNumber.Create(Count)); PsdJson.Put(Row,'confirmed',TJSONBool.Create(False));
  var Rebuilt := TJSONArray.Create; for var V in Rows do if TJSONObject(V)<>Other then Rebuilt.AddElement(V.Clone as TJSONObject);
  PsdJson.Put(Cast,'rows',Rebuilt); Project.Cues.Remove(Next); RequestScriptCasting(Project);
end;
procedure ValidateScriptCasting(Project: TRigmMovieProject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  var PrimaryCount := Project.Cues.Count;
  if Project.ScriptWizard.GetValue('summaryData') is TJSONObject then begin var O := JO(Project.ScriptWizard,'summaryData'); if JB(O,'materialized') and (Project.Cue(JS(O,'cueId'))<>nil) and (CastingRow(Project,JS(O,'cueId'))=nil) then Dec(PrimaryCount); end;
  if (JS(Cast,'format')<>'RIGMMaker.ScriptCasting') or (JI(Cast,'schemaVersion')<>1) or
    not MatchText(JS(Cast,'state'),['requested','ready','stale']) or (JA(Cast,'roles').Count>9) or
    (JA(Cast,'rows').Count<>PrimaryCount) or (PrimaryCount=0) then raise Exception.Create('配役データの形式が不正です。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in JA(Cast,'roles') do begin
      var O := TJSONObject(V); var N := JI(O,'number');
      if (N<1) or (N>9) or Seen.ContainsKey(N.ToString) or (JS(O,'path')='') or (Project.Speaker(JS(O,'speakerId'))=nil) then raise Exception.Create('キャラ番号の形式が不正です。');
      Seen.Add(N.ToString,True);
    end;
    Seen.Clear;
    for var V in JA(Cast,'rows') do begin
      var O := TJSONObject(V); var C := Project.Cue(JS(O,'cueId'));
      if (C=nil) or Seen.ContainsKey(C.Id) or (Project.Scene(C.Scene)=nil) or
        not MatchText(JS(O,'origin'),['unassigned','single-default','ai','human','automation']) then raise Exception.Create('配役セリフの形式が不正です。');
      Seen.Add(C.Id,True);
      if JS(Cast,'state')<>'stale' then begin
        var S := ScriptSection(Project,JS(O,'section')); if S=nil then raise Exception.Create('セリフの台本区分がありません。');
        var Text := JS(S,'text'); var Offset := JI(O,'offset',-1); var Count := JI(O,'length',-1);
        if (Offset<0) or (Count<1) or (Offset>Length(Text)) or (Count>Length(Text)-Offset) or
          not ScriptTextBoundary(Text,Offset) or not ScriptTextBoundary(Text,Offset+Count) then raise Exception.Create('セリフの原稿範囲が不正です。');
        var Role := CastingRole(Project,JI(O,'role')); if (JI(O,'role')>0) and ((Role=nil) or (JS(Role,'speakerId')<>C.SpeakerId)) then raise Exception.Create('配役番号と話者の対応が不正です。');
        if JB(O,'confirmed') and (Role=nil) then raise Exception.Create('未割当のセリフは確認済みにできません。');
      end;
    end;
    if CastingRow(Project,JS(Cast,'selectedCue'))=nil then raise Exception.Create('選択セリフが不正です。');
    if (JS(Cast,'state')<>'stale') and (JS(Cast,'fingerprint')<>CastingFingerprint(Project)) then raise Exception.Create('配役の原稿指紋が一致しません。');
  finally Seen.Free; end;
end;
function ScriptCastingSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; if not (Project.ScriptWizard.GetValue('casting') is TJSONObject) then Exit;
  var Cast := JO(Project.ScriptWizard,'casting'); Result.AddPair('state',JS(Cast,'state')); Result.AddPair('requestId',JS(Cast,'requestId'));
  Result.AddPair('fingerprint',JS(Cast,'fingerprint')); Result.AddPair('selectedCue',JS(Cast,'selectedCue')); Result.AddPair('roles',JA(Cast,'roles').Clone as TJSONArray);
  var Pending := 0; var Unassigned := 0;
  for var V in JA(Cast,'rows') do begin if not JB(TJSONObject(V),'confirmed') then Inc(Pending); if JI(TJSONObject(V),'role')=0 then Inc(Unassigned); end;
  AddN(Result,'count',JA(Cast,'rows').Count); AddN(Result,'pending',Pending); AddN(Result,'unassigned',Unassigned);
  var Used := UsedCastingRoles(Project); Result.AddPair('usedRoles',Used); AddN(Result,'missingVoices',MissingCastingVoices(Project));
  AddB(Result,'rolesComplete',(Pending=0) and (Unassigned=0) and (JS(Cast,'state')<>'stale'));
  AddB(Result,'voicesComplete',MissingCastingVoices(Project)=0);
end;
end.
