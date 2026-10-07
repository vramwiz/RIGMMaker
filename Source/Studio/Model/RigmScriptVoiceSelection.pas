// 実話者一覧の人物・状態を分離する。人物はSpeaker、状態は選択Cueへ保存する。
unit RigmScriptVoiceSelection;

interface
uses System.JSON, RigmMovieModel;

// 戻り値は借用Catalog内の索引。人物はUUIDごとに1件、状態はそのUUIDだけを返す。
function VoicePersonIndices(Catalog: TJSONArray): TArray<Integer>;
function VoiceStateIndices(Catalog: TJSONArray; const Uuid: string): TArray<Integer>;
// 戻り値は借用。ノーマルを優先し、公開されていない人物は先頭の実状態を使う。
function NormalVoiceStyle(Catalog: TJSONArray; const Uuid: string): TJSONObject;
function FindVoiceStyle(Catalog: TJSONArray; const Uuid: string; StyleId: Integer): TJSONObject;
// 旧人物の既定状態をセリフへ移して保持し、以後の初期状態をノーマルへ統一する。
function NormalizeVoicePeople(Project: TRigmMovieProject; Catalog: TJSONArray): Boolean;
// 人物変更時はそのキャラのセリフ状態・解析を初期化する。保存済み音声ファイルは保持。
function BindScriptVoicePerson(Project: TRigmMovieProject; Catalog: TJSONArray; Number: Integer; const Uuid: string): Boolean;
// 実一覧で所属を検査して選択Cueだけを更新する。ノーマルはSpeakerの既定値を継承する。
function SetScriptVoiceState(Project: TRigmMovieProject; Catalog: TJSONArray; const CueId: string; StyleId: Integer): Boolean;

implementation
uses System.SysUtils, System.Generics.Collections, RigmJson, RigmScriptCastingModel;

function VoicePersonIndices(Catalog: TJSONArray): TArray<Integer>;
begin
  Result := nil; var Seen := TDictionary<string,Boolean>.Create;
  try
    for var I := 0 to Catalog.Count-1 do begin
      var Uuid := JS(TJSONObject(Catalog[I]),'uuid');
      if (Uuid='') or Seen.ContainsKey(Uuid) then Continue;
      Seen.Add(Uuid,True); SetLength(Result,Length(Result)+1); Result[High(Result)] := I;
    end;
  finally Seen.Free; end;
end;
function VoiceStateIndices(Catalog: TJSONArray; const Uuid: string): TArray<Integer>;
begin
  Result := nil; if Uuid='' then Exit;
  for var I := 0 to Catalog.Count-1 do if JS(TJSONObject(Catalog[I]),'uuid')=Uuid then begin
    SetLength(Result,Length(Result)+1); Result[High(Result)] := I;
  end;
end;
function NormalVoiceStyle(Catalog: TJSONArray; const Uuid: string): TJSONObject;
begin
  Result := nil; if Uuid='' then Exit;
  for var V in Catalog do begin
    var O := TJSONObject(V); if JS(O,'uuid')<>Uuid then Continue;
    if Result=nil then Result := O;
    if SameText(Trim(JS(O,'style')),'ノーマル') or SameText(Trim(JS(O,'style')),'normal') then Exit(O);
  end;
end;
function FindVoiceStyle(Catalog: TJSONArray; const Uuid: string; StyleId: Integer): TJSONObject;
begin
  Result := nil; if (Uuid='') or (StyleId<0) then Exit;
  for var V in Catalog do begin var O := TJSONObject(V);
    if (JS(O,'uuid')=Uuid) and (JI(O,'styleId',-1)=StyleId) then Exit(O);
  end;
end;
procedure SetPersonDefault(Project: TRigmMovieProject; S: TRigmMovieSpeaker; Normal: TJSONObject);
begin
  var CurrentAudio := TList<TRigmMovieCue>.Create;
  try
    // 同じ実音声の保存表現を変える場合だけ、有効な音声キーを引き継ぐ。旧音声は昇格しない。
    for var C in Project.Cues do if C.SpeakerId=S.Id then begin
      if (C.AudioKey<>'') and (C.AudioKey=Project.AudioFingerprint(C)) then CurrentAudio.Add(C);
      if C.VoiceStyleId<0 then C.VoiceStyleId := S.StyleId;
    end;
    S.StyleId := JI(Normal,'styleId'); S.StyleName := JS(Normal,'style');
    for var C in CurrentAudio do C.AudioKey := Project.AudioFingerprint(C);
  finally CurrentAudio.Free; end;
end;
function NormalizeVoicePeople(Project: TRigmMovieProject; Catalog: TJSONArray): Boolean;
begin
  Result := False;
  for var S in Project.Speakers do begin
    var Normal := NormalVoiceStyle(Catalog,S.VoiceUuid);
    if (Normal=nil) or (FindVoiceStyle(Catalog,S.VoiceUuid,S.StyleId)=nil) or (S.StyleId=JI(Normal,'styleId')) then Continue;
    SetPersonDefault(Project,S,Normal); Result := True;
  end;
end;
function BindScriptVoicePerson(Project: TRigmMovieProject; Catalog: TJSONArray; Number: Integer; const Uuid: string): Boolean;
begin
  var Role := CastingRole(Project,Number);
  if (Role=nil) or not JB(Role,'active') then raise Exception.Create('登録キャラを選んでください。');
  var Normal := NormalVoiceStyle(Catalog,Uuid);
  if Normal=nil then raise Exception.Create('実話者一覧から人物を選んでください。');
  var S := Project.Speaker(JS(Role,'speakerId'));
  if S=nil then raise Exception.Create('選択キャラの声設定がありません。');
  var ChangedPerson := S.VoiceUuid<>Uuid;
  Result := (S.StyleId<>JI(Normal,'styleId')) or ChangedPerson or (S.VoiceName<>JS(Normal,'name')) or (S.StyleName<>JS(Normal,'style'));
  if not Result then Exit;
  if ChangedPerson then begin
    for var C in Project.Cues do if C.SpeakerId=S.Id then begin C.VoiceStyleId := -1; C.VoiceQuery := ''; C.VoiceQueryKey := ''; end;
  end else begin
    // 同じ人物の旧既定状態だけを各行へ移す。既に選んだ行別状態は保持する。
    if (S.StyleId<>JI(Normal,'styleId')) and (FindVoiceStyle(Catalog,Uuid,S.StyleId)<>nil) then SetPersonDefault(Project,S,Normal);
  end;
  S.StyleId := JI(Normal,'styleId'); S.VoiceUuid := Uuid; S.VoiceName := JS(Normal,'name'); S.StyleName := JS(Normal,'style');
end;
function SetScriptVoiceState(Project: TRigmMovieProject; Catalog: TJSONArray; const CueId: string; StyleId: Integer): Boolean;
begin
  var C := Project.Cue(CueId); if C=nil then raise Exception.Create('感情を設定するセリフを選んでください。');
  var S := Project.Speaker(C.SpeakerId);
  if (S=nil) or (S.StyleId<0) or (FindVoiceStyle(Catalog,S.VoiceUuid,StyleId)=nil) then
    raise Exception.Create('このキャラの人物に含まれる感情を選んでください。');
  var Stored := StyleId; if StyleId=S.StyleId then Stored := -1;
  Result := C.VoiceStyleId<>Stored; if not Result then Exit;
  var SameStyle := Project.EffectiveStyle(C)=StyleId;
  var CurrentAudio := SameStyle and (C.AudioKey<>'') and (C.AudioKey=Project.AudioFingerprint(C));
  if not SameStyle then begin C.VoiceQuery := ''; C.VoiceQueryKey := ''; end;
  C.VoiceStyleId := Stored;
  if CurrentAudio then C.AudioKey := Project.AudioFingerprint(C);
end;
end.
