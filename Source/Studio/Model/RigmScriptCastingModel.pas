unit RigmScriptCastingModel;

// 台本文を保存モデルのセリフ・シーンへ接続し、配役番号と人の確認を保持する。
interface
uses System.JSON, RigmMovieModel;
procedure PrepareScriptCasting(Project: TRigmMovieProject); // 未変更区分の配役・字幕・音声を保持して準備する。
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
implementation
uses System.SysUtils, System.Math, System.StrUtils, System.Hash, System.Generics.Collections,
  RigmJson, PsdJson, RigmScriptTextModel, RigmScriptReviewModel, RigmMovieComposition;
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
procedure RefreshCastingStatus(Project: TRigmMovieProject);
begin
  var Complete := True;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do
    Complete := Complete and JB(TJSONObject(V),'confirmed') and (CastingRole(Project,JI(TJSONObject(V),'role'))<>nil);
  if Complete then PsdJson.Put(Project.ScriptWizard,'castingStatus','complete')
  else PsdJson.Put(Project.ScriptWizard,'castingStatus','in-progress');
end;
procedure RequestScriptCasting(Project: TRigmMovieProject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'sourceFingerprint')<>ScriptFingerprint(Project)) then
    raise Exception.Create('前工程が変わりました。校正からNextで配役を準備してください。');
  PsdJson.Put(Cast,'requestId',PsdJson.NewId); PsdJson.Put(Cast,'fingerprint',CastingFingerprint(Project));
  PsdJson.Put(Cast,'state','requested'); RefreshCastingStatus(Project);
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
  var C := Project.Cue(CueId); C.SpeakerId := JS(Role,'speakerId');
  PsdJson.Put(Row,'role',TJSONNumber.Create(Number)); PsdJson.Put(Row,'confirmed',TJSONBool.Create(True));
  if not Confirm then PsdJson.Put(Row,'origin','human');
  SelectCastingRow(Project,CueId); MoveCastingRow(Project,1); RefreshCastingStatus(Project);
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
    for var Id in ['opening','body','closing'] do begin
      var Text := JS(ScriptSection(Project,Id),'text'); var S := TJSONObject.Create; Sections.AddElement(S); S.AddPair('id',Id); S.AddPair('text',Text);
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
      var Start := 0; var Paragraph := 0;
      while Start<Length(Text) do begin
        while (Start<Length(Text)) and CharInSet(Text[Start+1],[#13,#10]) do Inc(Start);
        if Start=Length(Text) then Break;
        var Finish := Text.IndexOf(#13#10+#13#10,Start); if Finish<0 then Finish := Length(Text);
        if Trim(Text.Substring(Start,Finish-Start))<>'' then begin
          Inc(Paragraph); var Scene := TRigmMovieScene.Create; Scene.Title := Id+' '+Paragraph.ToString; NewScenes.Add(Scene);
          while Start<Finish do begin
            var Count := Min(2000,Finish-Start); if not ScriptTextBoundary(Text,Start+Count) then Dec(Count);
            if (Start+Count<Finish) and (Text[Start+Count]=#13) and (Text[Start+Count+1]=#10) then Dec(Count);
            var C := TRigmMovieCue.Create; C.Scene := Scene.Id; C.Text := Text.Substring(Start,Count); C.Subtitle := C.Text; NewCues.Add(C);
            var Row := TJSONObject.Create; Rows.AddElement(Row); Row.AddPair('cueId',C.Id); Row.AddPair('section',Id);
            AddN(Row,'offset',Start); AddN(Row,'length',Count); AddN(Row,'role',0); Row.AddPair('origin','unassigned'); AddB(Row,'confirmed',False);
            Inc(Start,Count);
          end;
        end;
        Start := Finish+4;
      end;
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
      if (Role=nil) or (not JB(Row,'confirmed') and (SourceChanged or (Old=nil))) then begin
        PsdJson.Put(Row,'confirmed',TJSONBool.Create(False));
        if Single<>nil then begin PsdJson.Put(Row,'role',TJSONNumber.Create(JI(Single,'number'))); PsdJson.Put(Row,'origin','single-default'); C.SpeakerId := JS(Single,'speakerId'); end
        else begin PsdJson.Put(Row,'role',TJSONNumber.Create(0)); PsdJson.Put(Row,'origin','unassigned'); C.SpeakerId := 'narrator'; end;
      end;
    end;
    RequestScriptCasting(Project); ValidateScriptCasting(Project);
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
      Project.Cue(JS(Row,'cueId')).SpeakerId := JS(Role,'speakerId');
    end;
    if JB(Args,'complete') then PsdJson.Put(Cast,'state','ready'); RefreshCastingStatus(Project);
  finally Seen.Free; end;
end;
procedure CheckUneditedCue(Project: TRigmMovieProject; Row: TJSONObject);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'fingerprint')<>CastingFingerprint(Project)) then
    raise Exception.Create('原稿が変わりました。校正から配役へ進んで再確認してください。');
  var C := Project.Cue(JS(Row,'cueId')); var Text := JS(ScriptSection(Project,JS(Row,'section')),'text').Substring(JI(Row,'offset'),JI(Row,'length'));
  if (C.Text<>Text) or (C.Subtitle<>Text) or (C.WaveFile<>'') then raise Exception.Create('字幕または音声を編集済みのセリフは、この工程で分割・結合できません。');
end;
procedure SplitCastingRow(Project: TRigmMovieProject; const CueId: string; Offset: Integer);
begin
  var Cast := JO(Project.ScriptWizard,'casting'); var Rows := JA(Cast,'rows'); var Row := CastingRow(Project,CueId); if Row=nil then raise Exception.Create('セリフを選んでください。');
  CheckUneditedCue(Project,Row); var C := Project.Cue(CueId);
  if (Offset<=0) or (Offset>=Length(C.Text)) or not ScriptTextBoundary(C.Text,Offset) or
    ((C.Text[Offset]=#13) and (C.Text[Offset+1]=#10)) or
    (Trim(C.Text.Substring(0,Offset))='') or (Trim(C.Text.Substring(Offset))='') then raise Exception.Create('文章内の分割位置を選んでください。');
  var Next := TRigmMovieCue.Create; Next.Scene := C.Scene; Next.SpeakerId := C.SpeakerId;
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
        not MatchText(JS(O,'origin'),['unassigned','single-default','ai','human']) then raise Exception.Create('配役セリフの形式が不正です。');
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
end;
end.
