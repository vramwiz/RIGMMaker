unit RigmScriptSummaryModel;
// 人間の総評draftと独立チャート。通常の配役行へ結び付け、旧台本の追加セリフも保持する。
interface
uses System.JSON, RigmMovieModel;
const ScriptSummaryAxisNames: array[0..4] of string = (
  'ストーリー','キャラクター','作画','演出・テンポ','世界観・設定');
function ScriptSummaryFixedDraft(Draft: TJSONObject; AnimeRanking: Boolean=False): TJSONObject; // 既存5項目と順位紹介専用6項目を区別。
procedure PrepareScriptSummary(Project: TRigmMovieProject);
procedure ValidateScriptSummary(Project: TRigmMovieProject);
procedure SetScriptSummaryDraft(Project: TRigmMovieProject; Draft: TJSONObject);
procedure ConfirmScriptSummaryDraft(Project: TRigmMovieProject); // 配役前のセリフ・チャートを検査し、下書きを確定する。
procedure ConfigureScriptSummaryScene(Project: TRigmMovieProject); // 配役で生成した総評各行へ1つの独立チャートを結び付ける。
function ScriptSummaryChart(Draft: TJSONObject): TJSONObject;
function ScriptSummaryDraftReason(Draft: TJSONObject): string; // 入力不足の理由。下書きは変更しない。
procedure MaterializeScriptSummary(Project: TRigmMovieProject);
procedure DisableScriptSummary(Project: TRigmMovieProject);
function ScriptSummaryCue(Project: TRigmMovieProject): TRigmMovieCue;
function IsScriptSummaryCue(Project: TRigmMovieProject; Cue: TRigmMovieCue): Boolean;
procedure SyncSummarySubtitle(Project: TRigmMovieProject; const CueId: string);
procedure SyncSummaryReading(Project: TRigmMovieProject; const CueId: string);
implementation
uses System.SysUtils, System.StrUtils, System.Generics.Collections, RigmJson, PsdJson, RigmMovieComposition,
  RigmMovieChart, RigmScriptVoiceModel, RigmScriptCastingModel, RigmScriptSubtitleModel,
  RigmScriptTextModel, RigmScriptSummaryFields, RigmScriptTypes;
function ScriptSummaryFixedDraft(Draft: TJSONObject; AnimeRanking: Boolean): TJSONObject;
begin
  Result := Draft.Clone as TJSONObject;
  var Axes := TArray<string>.Create('ストーリー','キャラクター','作画','演出・テンポ','世界観・設定');
  if AnimeRanking then Axes := TArray<string>.Create('物語','キャラクター','作画','演出','声の演技','音楽');
  var Items := TJSONArray.Create;
  for var I := 0 to High(Axes) do begin
    var Value := ''; var Found := False;
    for var V in JA(Draft,'items') do
      if JS(TJSONObject(V),'label')=Axes[I] then begin
        Value := JS(TJSONObject(V),'value'); Found := True; Break;
      end;
    if not Found and (I<JA(Draft,'items').Count) then begin
      var Previous := TJSONObject(JA(Draft,'items')[I]);
      if not MatchStr(JS(Previous,'label'),Axes) then Value := JS(Previous,'value');
    end;
    var Item := TJSONObject.Create; Items.AddElement(Item);
    Item.AddPair('label',Axes[I]); Item.AddPair('value',Value);
  end;
  PsdJson.Put(Result,'items',Items);
end;
function ScriptSummaryCue(Project: TRigmMovieProject): TRigmMovieCue;
begin Result := nil; if Project.ScriptWizard.GetValue('summaryData') is TJSONObject then Result := Project.Cue(JS(JO(Project.ScriptWizard,'summaryData'),'cueId')); end;
function IsScriptSummaryCue(Project: TRigmMovieProject; Cue: TRigmMovieCue): Boolean;
begin
  Result := (Cue<>nil) and (Project.ScriptWizard<>nil) and
    (Project.ScriptWizard.GetValue('summaryData') is TJSONObject);
  if Result then begin var O := JO(Project.ScriptWizard,'summaryData'); Result := JB(O,'materialized') and (Cue.Scene=JS(O,'sceneId')); end;
end;
procedure SyncSummaryField(Project: TRigmMovieProject; const CueId,Key: string);
begin
  if not IsScriptSummaryCue(Project,Project.Cue(CueId)) then Exit;
  var Text := ''; var Count := 0; var HasValue := False;
  for var C in Project.Cues do if IsScriptSummaryCue(Project,C) then begin
    var Value := C.Subtitle;
    if Key='reading' then begin Value := C.SpokenText; HasValue := HasValue or (C.VoiceReading<>''); end
    else HasValue := HasValue or (C.Subtitle<>'');
    if Count>0 then Text := Text+#13#10; Text := Text+Value; Inc(Count);
  end;
  if not HasValue then Text := '';
  var O := JO(Project.ScriptWizard,'summaryData');
  PsdJson.Put(JO(O,'draft'),Key,Text); PsdJson.Put(JO(O,'appliedDraft'),Key,Text);
end;
procedure SyncSummarySubtitle(Project: TRigmMovieProject; const CueId: string);
begin SyncSummaryField(Project,CueId,'subtitle'); end;
procedure SyncSummaryReading(Project: TRigmMovieProject; const CueId: string);
begin SyncSummaryField(Project,CueId,'reading'); end;
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
  if Project.ScriptWizard.GetValue('summaryData')=nil then begin
    var Summary := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptSummary","schemaVersion":1,"materialized":false,"status":"draft","draft":{"text":"","subtitle":"","reading":"","role":0,"kind":"radar","title":"","minimum":"0","maximum":"5","items":[]}}');
    PsdJson.Put(Summary,'draft',ScriptSummaryFixedDraft(JO(Summary,'draft'),IsAnimeRankingScript(Project)));
    Project.ScriptWizard.AddPair('summaryData',Summary);
  end;
  ValidateScriptSummary(Project);
end;
procedure ValidateScriptSummary(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'summaryData'); if (JS(O,'format')<>'RIGMMaker.ScriptSummary') or (JI(O,'schemaVersion')<>1) or not(O.GetValue('draft') is TJSONObject) or not MatchStr(JS(O,'status'),['draft','complete']) then raise Exception.Create('総評の保存形式が不正です。'); ValidateDraft(JO(O,'draft'));
  if JB(O,'materialized') then begin
    if not(O.GetValue('appliedDraft') is TJSONObject) then raise Exception.Create('総評の反映済み入力がありません。'); ValidateDraft(JO(O,'appliedDraft'));
    var C := ScriptSummaryCue(Project); var S := Project.Scene(JS(O,'sceneId'));
    if (C=nil) or (S=nil) or (C.Scene<>S.Id) or not MovieChartEnabled(S.Chart) then raise Exception.Create('総評セリフとチャートの参照が不正です。'); ValidateMovieChart(S.Chart);
    if not JB(O,'castingRow') then begin
      if CastingRow(Project,C.Id)<>nil then raise Exception.Create('総評の配役参照が不正です。');
      var Role := CastingRole(Project,JI(JO(O,'appliedDraft'),'role')); if (Role=nil) or (C.SpeakerId<>JS(Role,'speakerId')) then raise Exception.Create('総評の配役が不正です。');
    end else if (CastingRow(Project,C.Id)=nil) or (JS(CastingRow(Project,C.Id),'section')<>'summary') then raise Exception.Create('総評の配役行がありません。');
    var Count := 0;
    for var Cue in Project.Cues do if Cue.Scene=S.Id then begin
      Inc(Count);
      if JB(O,'castingRow') and ((CastingRow(Project,Cue.Id)=nil) or (JS(CastingRow(Project,Cue.Id),'section')<>'summary')) then
        raise Exception.Create('総評sceneに別のセリフが含まれています。');
    end;
    if (Count=0) or (not JB(O,'castingRow') and (Count<>1)) then raise Exception.Create('総評sceneのセリフ参照が不正です。');
    if JB(O,'castingRow') then for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do
      if JS(TJSONObject(V),'section')='summary' then begin
        var Cue := Project.Cue(JS(TJSONObject(V),'cueId'));
        if (Cue=nil) or (Cue.Scene<>S.Id) then raise Exception.Create('総評は1つのチャートsceneへ割り当ててください。');
      end;
  end;
end;
procedure SetScriptSummaryDraft(Project: TRigmMovieProject; Draft: TJSONObject);
begin
  ValidateDraft(Draft); PrepareScriptSummary(Project); var O := JO(Project.ScriptWizard,'summaryData'); if JO(O,'draft').ToJSON=Draft.ToJSON then Exit;
  var Fixed := ScriptSummaryFixedDraft(JO(O,'draft'),IsAnimeRankingScript(Project));
  var NewFixed := ScriptSummaryFixedDraft(Draft,IsAnimeRankingScript(Project));
  try
    // 旧3～8項目の内容は固定5項目へ初めて書き換える際にも復元できる形で残す。
    if (O.GetValue('previousChartDraft')=nil) and
      (JA(Fixed,'items').ToJSON<>JA(JO(O,'draft'),'items').ToJSON) and
      (JA(Draft,'items').ToJSON=JA(NewFixed,'items').ToJSON) then
      PsdJson.Put(O,'previousChartDraft',JO(O,'draft').Clone as TJSONObject);
  finally NewFixed.Free; Fixed.Free; end;
  PsdJson.Put(O,'draft',Draft.Clone as TJSONObject); PsdJson.Put(O,'status','draft');
end;
procedure ConfirmScriptSummaryDraft(Project: TRigmMovieProject);
begin
  PrepareScriptSummary(Project); var D := JO(JO(Project.ScriptWizard,'summaryData'),'draft');
  var Reason := ScriptSummaryDraftReason(D); if Reason<>'' then raise Exception.Create(Reason);
  PsdJson.Put(JO(Project.ScriptWizard,'summaryData'),'status','complete');
end;
procedure ConfigureScriptSummaryScene(Project: TRigmMovieProject);
begin
  if JS(Project.ScriptWizard,'summaryChoice')<>'yes' then Exit;
  RestoreScriptSummarySubtitles(Project);
  RestoreScriptSummaryReadings(Project);
  var O := JO(Project.ScriptWizard,'summaryData'); var D := JO(O,'draft');
  var Count := 0;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='summary' then Inc(Count);
  var CueIds := TJSONArray.Create; var Index := 0; var First: TRigmMovieCue := nil;
  try
    for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do begin
      var Row := TJSONObject(V); if JS(Row,'section')<>'summary' then Continue;
      var C := Project.Cue(JS(Row,'cueId'));
      if First=nil then begin
        First := C; var S := Project.Scene(C.Scene);
        var Chart := ScriptSummaryChart(D); S.Chart.Free; S.Chart := Chart; S.Title := '総評'; S.DisplayMode := 'image';
      end;
      C.Scene := First.Scene;
      var NewCue := not (O.GetValue('cueIds') is TJSONArray);
      if not NewCue then begin NewCue := True; for var Id in JA(O,'cueIds') do if Id.Value=C.Id then NewCue := False; end;
      // 未変更行の字幕・読み・アクセントは保持し、新規行か総評欄の変更だけを反映する。
      for var Key in ['subtitle','reading'] do
        if NewCue or not (O.GetValue('appliedDraft') is TJSONObject) or
          (JS(JO(O,'appliedDraft'),Key)<>JS(D,Key)) then begin
          var Value := ScriptSummaryFieldLine(D,Key,Index,Count,C.Text);
          if NewCue and (O.GetValue('appliedDraft') is TJSONObject) and
            (JS(JO(O,'appliedDraft'),'text')<>JS(D,'text')) and (JS(JO(O,'appliedDraft'),Key)=JS(D,Key)) then begin
            Value := ''; if Key='subtitle' then Value := C.Text;
          end;
          if Key='subtitle' then begin
            if JS(D,'subtitle')='' then Value := C.Text;
            C.Subtitle := Value;
          end else C.VoiceReading := Value;
        end;
      CueIds.Add(C.Id); Inc(Index);
    end;
    if First=nil then Exit;
    PsdJson.Put(O,'cueId',First.Id); PsdJson.Put(O,'sceneId',First.Scene);
    PsdJson.Put(O,'cueIds',CueIds); CueIds := nil;
    PsdJson.Put(O,'materialized',TJSONBool.Create(True)); PsdJson.Put(O,'castingRow',TJSONBool.Create(True));
    PsdJson.Put(O,'appliedDraft',D.Clone as TJSONObject);
  finally CueIds.Free; end;
end;
function ScriptSummaryChart(Draft: TJSONObject): TJSONObject;
  function Number(const Text,LabelText: string): Double;
  begin if not TryStrToFloat(Text,Result,TFormatSettings.Invariant) then raise Exception.Create(LabelText+'を数値で入力してください。'); end;
begin
  ValidateDraft(Draft); Result := TJSONObject.Create;
  try Result.AddPair('kind',JS(Draft,'kind')); Result.AddPair('title',JS(Draft,'title')); AddN(Result,'minimum',Number(JS(Draft,'minimum'),'総評チャートの最小値')); AddN(Result,'maximum',Number(JS(Draft,'maximum'),'総評チャートの最大値'));
    var A := TJSONArray.Create; Result.AddPair('items',A);
    for var I := 0 to JA(Draft,'items').Count-1 do begin
      var D := TJSONObject(JA(Draft,'items')[I]); var LabelText := Trim(JS(D,'label'));
      var Location := Format('総評チャートの%d行目：',[I+1]);
      if LabelText='' then begin
        if Trim(JS(D,'value'))='' then raise Exception.Create(Location+'評価項目名と点数を入力してください。');
        raise Exception.Create(Location+'評価項目名を入力してください。');
      end;
      var O := TJSONObject.Create; A.AddElement(O); O.AddPair('label',JS(D,'label'));
      AddN(O,'value',Number(JS(D,'value'),Location+'「'+LabelText+'」の点数'));
    end;
    ValidateMovieChart(Result);
  except Result.Free; raise; end;
end;
function ScriptSummaryDraftReason(Draft: TJSONObject): string;
begin
  Result := '';
  try
    ValidateDraft(Draft);
    if Trim(JS(Draft,'text'))='' then Exit('総評のセリフを入力してください。');
    var Chart := ScriptSummaryChart(Draft); Chart.Free;
  except on E: Exception do Result := E.Message; end;
end;
procedure MaterializeScriptSummary(Project: TRigmMovieProject);
begin
  PrepareScriptSummary(Project); var O := JO(Project.ScriptWizard,'summaryData');
  if JB(O,'castingRow') and JB(O,'materialized') then begin ConfigureScriptSummaryScene(Project); Exit; end;
  var D := JO(O,'draft'); if JS(D,'text').Trim='' then raise Exception.Create('総評の音声文を人間が入力してください。');
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
    if JS(D,'subtitle')='' then C.Subtitle := C.Text;
    S.Title := '総評'; S.DisplayMode := 'image'; S.Chart.Free; S.Chart := Chart; Chart := nil;
    PsdJson.Put(O,'appliedDraft',D.Clone as TJSONObject); PsdJson.Put(O,'status','complete');
  finally Chart.Free; end;
end;
procedure DisableScriptSummary(Project: TRigmMovieProject);
begin
  if not(Project.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit;
  var O := JO(Project.ScriptWizard,'summaryData'); if not JB(O,'materialized') then Exit; ValidateScriptSummary(Project);
  var S := Project.Scene(JS(O,'sceneId')); var Cues := TJSONArray.Create; var SavedRows := TJSONArray.Create;
  PsdJson.Put(O,'archivedCue',ScriptSummaryCue(Project).Json); PsdJson.Put(O,'archivedScene',S.Json);
  var Rows := TJSONArray.Create; var Cast := JO(Project.ScriptWizard,'casting');
  for var V in JA(Cast,'rows') do begin
    if IsScriptSummaryCue(Project,Project.Cue(JS(TJSONObject(V),'cueId'))) then SavedRows.AddElement(V.Clone as TJSONValue)
    else Rows.AddElement(V.Clone as TJSONValue);
  end;
  for var C in Project.Cues do if IsScriptSummaryCue(Project,C) then Cues.AddElement(C.Json);
  PsdJson.Put(O,'archivedCues',Cues); PsdJson.Put(O,'archivedRows',SavedRows); PsdJson.Put(Cast,'rows',Rows);
  for var I := Project.Cues.Count-1 downto 0 do if Project.Cues[I].Scene=S.Id then Project.Cues.Delete(I);
  Project.Scenes.Remove(S); PsdJson.Put(O,'materialized',TJSONBool.Create(False));
  if JB(O,'castingRow') then InvalidateScriptCasting(Project);
  for var Key in ['casting','voice','voiceEffects','subtitles'] do
    if Project.ScriptWizard.GetValue(Key) is TJSONObject then begin
      var Page := JO(Project.ScriptWizard,Key);
      if (Project.Cue(JS(Page,'selectedCue'))=nil) and (Project.Cues.Count>0) then PsdJson.Put(Page,'selectedCue',Project.Cues[0].Id);
    end;
  if (Project.ScriptWizard.GetValue('scenes') is TJSONObject) and (Project.Scenes.Count>0) and
    (JS(JO(Project.ScriptWizard,'scenes'),'selectedScene')=JS(O,'sceneId')) then PsdJson.Put(JO(Project.ScriptWizard,'scenes'),'selectedScene',Project.Scenes[0].Id);
end;
end.
