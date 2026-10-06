unit RigmScriptReviewModel;

// 校正の原稿指紋・範囲・採否を管理する。文章生成は外部Codexが担当する。
interface
uses System.JSON, RigmMovieModel;
function ScriptFingerprint(Project: TRigmMovieProject): string; // 区分ID・本文のSHA-256。表示選択は含めない。
procedure RequestScriptReview(Project: TRigmMovieProject); // 現文を保持し、提案一覧と依頼IDを作り直す。
procedure SubmitScriptReview(Project: TRigmMovieProject; Args: TJSONObject); // 全提案を複製で検査して反映。本文は変更しない。
procedure DecideScriptReview(Project: TRigmMovieProject; const Id,Decision,Text: string); // GUI採否で対象文と後続範囲を更新。
procedure InvalidateScriptReview(Project: TRigmMovieProject); // 原稿編集後の未確定提案を失効させる。
function ReviewItem(Project: TRigmMovieProject; const Id: string): TJSONObject; // 借用参照。未登録IDならnil。
function ScriptReviewSummary(Project: TRigmMovieProject): TJSONObject; // 呼出側所有の小さな依頼・件数要約。
procedure ValidateScriptReview(Project: TRigmMovieProject); // 読込・保存時の形式と原稿整合検査。副作用なし。
implementation
uses System.SysUtils, System.Hash, System.Math, System.StrUtils, System.Generics.Collections,
  RigmJson, PsdJson, RigmScriptTextModel;
function ScriptFingerprint(Project: TRigmMovieProject): string;
begin
  var A := TJSONArray.Create;
  try
    for var V in JA(JO(Project.ScriptWizard,'scriptText'),'sections') do begin
      var O := TJSONObject.Create; A.AddElement(O); O.AddPair('id',JS(TJSONObject(V),'id')); O.AddPair('text',JS(TJSONObject(V),'text'));
    end;
    Result := THashSHA2.GetHashString(A.ToJSON);
  finally A.Free; end;
end;
function ReviewItem(Project: TRigmMovieProject; const Id: string): TJSONObject;
begin
  Result := nil;
  if (Project=nil) or not (Project.ScriptWizard.GetValue('review') is TJSONObject) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'review'),'items') do
    if JS(TJSONObject(V),'id')=Id then Exit(TJSONObject(V));
end;
procedure RequestScriptReview(Project: TRigmMovieProject);
begin
  var R := TJSONObject.Create;
  R.AddPair('format','RIGMMaker.ScriptReview'); R.AddPair('schemaVersion',TJSONNumber.Create(1));
  R.AddPair('requestId',PsdJson.NewId); R.AddPair('fingerprint',ScriptFingerprint(Project));
  R.AddPair('state','requested'); R.AddPair('items',TJSONArray.Create);
  PsdJson.Put(Project.ScriptWizard,'review',R); PsdJson.Put(Project.ScriptWizard,'reviewStatus','in-progress');
end;
procedure InvalidateScriptReview(Project: TRigmMovieProject);
begin
  if not (Project.ScriptWizard.GetValue('review') is TJSONObject) then Exit;
  var R := JO(Project.ScriptWizard,'review'); PsdJson.Put(R,'state','stale');
  for var V in JA(R,'items') do if MatchText(JS(TJSONObject(V),'decision'),['pending','hold']) then
    PsdJson.Put(TJSONObject(V),'decision','stale');
  PsdJson.Put(Project.ScriptWizard,'reviewStatus','in-progress');
end;
procedure CheckText(const Text: string; Limit: Integer);
begin
  if Length(Text)>Limit then raise Exception.Create('校正項目の文字数上限を超えています。');
  for var C in Text do if (Ord(C)<32) and not CharInSet(C,[#9,#10,#13]) then
    raise Exception.Create('校正項目に無効な制御文字があります。');
end;
procedure CheckAnchor(Project: TRigmMovieProject; Item: TJSONObject);
begin
  var S := ScriptSection(Project,JS(Item,'section')); if S=nil then raise Exception.Create('校正の台本区分が不正です。');
  var Text := JS(S,'text'); var Offset := JI(Item,'offset',-1); var Original := JS(Item,'original');
  if (Offset<0) or (Offset>Length(Text)) or (Length(Original)>Length(Text)-Offset) or
    not ScriptTextBoundary(Text,Offset) or not ScriptTextBoundary(Text,Offset+Length(Original)) then
    raise Exception.Create('校正の対象範囲が不正です。');
  if Text.Substring(Offset,Length(Original))<>Original then raise Exception.Create('校正の対象文章が変更されています。原稿を再取得してください。');
end;
procedure ValidateScriptReview(Project: TRigmMovieProject);
begin
  var R := JO(Project.ScriptWizard,'review');
  if (JS(R,'format')<>'RIGMMaker.ScriptReview') or (JI(R,'schemaVersion')<>1) or
    (JS(R,'requestId')='') or (Length(JS(R,'fingerprint'))<>64) or
    not MatchText(JS(R,'state'),['requested','ready','stale']) or
    not (R.GetValue('items') is TJSONArray) or (JA(R,'items').Count>1000) then
    raise Exception.Create('校正データの形式が不正です。');
  if (JS(R,'state')<>'stale') and (JS(R,'fingerprint')<>ScriptFingerprint(Project)) then
    raise Exception.Create('校正データと台本文の指紋が一致しません。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in JA(R,'items') do begin
      if not (V is TJSONObject) then raise Exception.Create('校正項目の形式が不正です。');
      var O := TJSONObject(V); var Id := JS(O,'id');
      if (Id='') or (Length(Id)>64) or Seen.ContainsKey(Id) or
        not MatchText(JS(O,'decision'),['pending','ai','human','edited','hold','stale']) or
        not (O.GetValue('original') is TJSONString) or not (O.GetValue('proposed') is TJSONString) or
        (ScriptSection(Project,JS(O,'section'))=nil) or (JI(O,'offset',-1)<0) then
        raise Exception.Create('校正項目の値が不正です。');
      Seen.Add(Id,True); CheckText(JS(O,'original'),4096); CheckText(JS(O,'proposed'),4096); CheckText(JS(O,'reason'),2048);
      if O.GetValue('editedDraft')<>nil then CheckText(JS(O,'editedDraft'),4096);
      if O.GetValue('acceptedText')<>nil then CheckText(JS(O,'acceptedText'),4096);
      if (JS(R,'state')<>'stale') and MatchText(JS(O,'decision'),['pending','hold']) then CheckAnchor(Project,O);
    end;
  finally Seen.Free; end;
end;
procedure SubmitScriptReview(Project: TRigmMovieProject; Args: TJSONObject);
begin
  var R := JO(Project.ScriptWizard,'review');
  if (JS(R,'state')<>'requested') or (JS(Args,'requestId')<>JS(R,'requestId')) or
    (JS(Args,'fingerprint')<>JS(R,'fingerprint')) or (ScriptFingerprint(Project)<>JS(R,'fingerprint')) then
    raise Exception.Create('校正依頼または原稿が変わりました。最新の依頼から再取得してください。');
  if not (Args.GetValue('items') is TJSONArray) or (JA(Args,'items').Count>20) then
    raise Exception.Create('校正提案はitems配列で20件以内ずつ送信してください。');
  // 全件を複製上で検査し、一件の異常でも正本に部分反映しない。
  var Snapshot := Project.Clone;
  try
    var CopyR := JO(Snapshot.ScriptWizard,'review'); var Items := JA(CopyR,'items');
    for var V in JA(Args,'items') do begin
      if not (V is TJSONObject) then raise Exception.Create('校正提案の形式が不正です。');
      var O := V.Clone as TJSONObject; Items.AddElement(O);
      if not (O.GetValue('original') is TJSONString) or not (O.GetValue('proposed') is TJSONString) then
        raise Exception.Create('original/proposedは文字列で指定してください。');
      PsdJson.Put(O,'decision','pending');
      PsdJson.Put(O,'proposed',NormalizeScriptText(JS(O,'proposed')));
      CheckAnchor(Snapshot,O);
    end;
    if JB(Args,'complete') then PsdJson.Put(CopyR,'state','ready');
    ValidateScriptReview(Snapshot);
    PsdJson.Put(Project.ScriptWizard,'review',CopyR.Clone as TJSONObject);
  finally Snapshot.Free; end;
end;
procedure DecideScriptReview(Project: TRigmMovieProject; const Id,Decision,Text: string);
begin
  if not MatchText(Decision,['ai','human','edited','hold']) then raise Exception.Create('校正の採否が不正です。');
  var R := JO(Project.ScriptWizard,'review'); var O := ReviewItem(Project,Id);
  if (O=nil) or (JS(R,'state')<>'ready') or (ScriptFingerprint(Project)<>JS(R,'fingerprint')) or
    not MatchText(JS(O,'decision'),['pending','hold']) then raise Exception.Create('現在の原稿に対する未確定の提案を選んでください。');
  CheckAnchor(Project,O);
  var Replacement := JS(O,'original');
  if Decision='ai' then Replacement := JS(O,'proposed') else if Decision='edited' then Replacement := NormalizeScriptText(Text);
  CheckText(Replacement,4096);
  var Section := ScriptSection(Project,JS(O,'section')); var Old := JS(Section,'text');
  var Offset := JI(O,'offset'); var Removed := Length(JS(O,'original'));
  var Updated := Old.Substring(0,Offset)+Replacement+Old.Substring(Offset+Removed);
  if Length(Updated)>ScriptSectionLimit then raise Exception.Create('採用後の台本が区分の文字数上限を超えます。');
  if Decision<>'hold' then begin
    if Replacement<>JS(O,'original') then begin
      PsdJson.Put(Section,'text',Updated);
      for var V in JA(R,'items') do begin
        var Other := TJSONObject(V); if Other=O then Continue;
        if (JS(Other,'section')<>JS(O,'section')) or not MatchText(JS(Other,'decision'),['pending','hold']) then Continue;
        var Start := JI(Other,'offset'); var Finish := Start+Length(JS(Other,'original'));
        if Start>=Offset+Removed then PsdJson.Put(Other,'offset',TJSONNumber.Create(Start+Length(Replacement)-Removed))
        else if Finish>Offset then PsdJson.Put(Other,'decision','stale');
      end;
      PsdJson.Put(R,'fingerprint',ScriptFingerprint(Project));
    end;
    PsdJson.Put(O,'acceptedText',Replacement);
  end;
  PsdJson.Put(O,'decision',Decision);
  PsdJson.Put(Project.ScriptWizard,'reviewStatus','in-progress');
end;
function ScriptReviewSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  if not (Project.ScriptWizard.GetValue('review') is TJSONObject) then Exit;
  var R := JO(Project.ScriptWizard,'review');
  Result.AddPair('requestId',JS(R,'requestId')); Result.AddPair('fingerprint',JS(R,'fingerprint')); Result.AddPair('state',JS(R,'state'));
  var Pending := 0; var Held := 0; var Stale := 0;
  for var V in JA(R,'items') do begin
    if JS(TJSONObject(V),'decision')='pending' then Inc(Pending);
    if JS(TJSONObject(V),'decision')='hold' then Inc(Held);
    if JS(TJSONObject(V),'decision')='stale' then Inc(Stale);
  end;
  AddN(Result,'count',JA(R,'items').Count); AddN(Result,'pending',Pending); AddN(Result,'held',Held); AddN(Result,'stale',Stale);
end;
end.
