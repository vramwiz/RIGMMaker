unit RigmScriptSummaryFields;
// 総評の字幕・読みを発話行へ対応付ける。旧版の空行ずれは履歴と照合して復元する。
interface
uses System.JSON, RigmMovieModel;
// 借用する下書きから現在の発話に対応する字幕／読みを返す。入力は変更しない。
function ScriptSummaryFieldLine(Draft: TJSONObject; const Key: string;
  Index, Count: Integer; const CueText: string): string;
// 借用する作品の字幕だけを変更し、旧値を退避する。原本への保存・音声変更は行わない。
function RestoreScriptSummarySubtitles(Project: TRigmMovieProject): Boolean;
// 旧字幕補正の記録と読みの全行が一致する場合だけ、誤った読みと音声採用状態を補正する。
// 元のcueは退避し、音声ファイルは残す。呼出側が保存・必要な音声再生成を行う。
function RestoreScriptSummaryReadings(Project: TRigmMovieProject): Boolean;
implementation
uses System.SysUtils, System.Generics.Collections, RigmJson, PsdJson;
function NonemptyLines(const Text: string): TArray<string>;
begin
  Result := nil;
  for var Line in Text.Split([#13#10]) do if Trim(Line)<>'' then begin
    SetLength(Result,Length(Result)+1); Result[High(Result)] := Line;
  end;
end;
function ScriptSummaryFieldLine(Draft: TJSONObject; const Key: string;
  Index, Count: Integer; const CueText: string): string;
begin
  Result := JS(Draft,Key); if (Result='') or (Count=1) then Exit;
  // 原稿そのものを入力した場合は、空行や手動の分割によらず現在の発話に一致させる。
  if Result=JS(Draft,'text') then Exit(CueText);
  var Lines := Result.Split([#13#10]);
  if Length(Lines)<>Count then begin
    var SpokenLines := NonemptyLines(Result);
    if Length(SpokenLines)=Count then Lines := SpokenLines;
  end;
  // 発話数と同じ行数の独立字幕では、意図した空欄を保持する。
  if Index<Length(Lines) then Result := Lines[Index] else Result := '';
end;
function RestoreScriptSummarySubtitles(Project: TRigmMovieProject): Boolean;
begin
  Result := False;
  if (Project.ScriptWizard=nil) or
    not (Project.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit;
  var O := JO(Project.ScriptWizard,'summaryData');
  if not JB(O,'materialized') or not (O.GetValue('draft') is TJSONObject) or
    not (O.GetValue('appliedDraft') is TJSONObject) or
    not (O.GetValue('cueIds') is TJSONArray) then Exit;
  var D := JO(O,'appliedDraft'); var Draft := JO(O,'draft');
  if (JS(D,'text')<>JS(Draft,'text')) or (JS(D,'subtitle')<>JS(Draft,'subtitle')) then Exit;
  var Cues := TList<TRigmMovieCue>.Create;
  try
    for var C in Project.Cues do if C.Scene=JS(O,'sceneId') then Cues.Add(C);
    var Lines := JS(D,'subtitle').Split([#13#10]);
    var Source := NonemptyLines(JS(D,'text'));
    var Subtitles := NonemptyLines(JS(D,'subtitle'));
    if (Cues.Count<2) or (Length(Lines)<=Cues.Count) or
      (Length(Source)<>Cues.Count) or (Length(Subtitles)<>Cues.Count) or
      (JA(O,'cueIds').Count<>Cues.Count) then Exit;
    // 全行が旧割当と一致する場合だけ補正する。個別の字幕編集・非表示は推測で直さない。
    var Different := False;
    for var I := 0 to Cues.Count-1 do begin
      if (Cues[I].Id<>JA(O,'cueIds')[I].Value) or (Cues[I].Text<>Source[I]) or
        (Cues[I].Subtitle<>Lines[I]) then Exit;
      Different := Different or (Cues[I].Subtitle<>Subtitles[I]);
    end;
    if not Different then Exit;
    var Archive := TJSONArray.Create;
    try
      for var C in Cues do Archive.AddElement(TJSONObject.Create
        .AddPair('cueId',C.Id).AddPair('subtitle',C.Subtitle));
      PsdJson.Put(O,'subtitleLineMigration',Archive); Archive := nil;
    finally Archive.Free; end;
    for var I := 0 to Cues.Count-1 do Cues[I].Subtitle := Subtitles[I];
    Result := True;
  finally Cues.Free; end;
end;
function RestoreScriptSummaryReadings(Project: TRigmMovieProject): Boolean;
begin
  Result := False;
  if (Project.ScriptWizard=nil) or
    not (Project.ScriptWizard.GetValue('summaryData') is TJSONObject) then Exit;
  var O := JO(Project.ScriptWizard,'summaryData');
  if not JB(O,'materialized') or not (O.GetValue('draft') is TJSONObject) or
    not (O.GetValue('appliedDraft') is TJSONObject) or
    not (O.GetValue('subtitleLineMigration') is TJSONArray) then Exit;
  var Draft := JO(O,'draft'); var Applied := JO(O,'appliedDraft');
  if JS(Draft,'reading')<>JS(Applied,'reading') then Exit;
  var Lines := JS(Applied,'reading').Split([#13#10]);
  var Source := NonemptyLines(JS(Applied,'reading'));
  var Previous := JA(O,'subtitleLineMigration');
  if (Previous.Count<2) or (Length(Lines)<=Previous.Count) or
    (Length(Source)<>Previous.Count) then Exit;
  var Affected := TList<TRigmMovieCue>.Create;
  try
    // 字幕補正後に原稿へ行を追加していても、元のcue IDで対応する。個別の読み変更は保護する。
    for var I := 0 to Previous.Count-1 do begin
      if not (Previous[I] is TJSONObject) then Exit;
      var Old := TJSONObject(Previous[I]); var C := Project.Cue(JS(Old,'cueId'));
      if (C=nil) or (C.Scene<>JS(O,'sceneId')) or (C.Text<>Source[I]) or
        (JS(Old,'subtitle')<>Lines[I]) or (C.VoiceReading<>Lines[I]) then Exit;
      if (C.VoiceReading<>'') and (C.VoiceReading<>C.Text) then Affected.Add(C);
    end;
    if Affected.Count=0 then Exit;
    var Archive := TJSONArray.Create;
    try
      for var C in Affected do Archive.AddElement(C.Json);
      PsdJson.Put(O,'readingLineMigration',Archive); Archive := nil;
    finally Archive.Free; end;
    for var C in Affected do begin
      C.VoiceReading := ''; C.VoiceQuery := ''; C.VoiceQueryKey := '';
      C.AudioKey := ''; C.VoiceHeardKey := ''; C.EffectAudioKey := '';
    end;
    var Reading := '';
    for var C in Project.Cues do if C.Scene=JS(O,'sceneId') then begin
      if Reading<>'' then Reading := Reading+#13#10;
      Reading := Reading+C.SpokenText;
    end;
    PsdJson.Put(Draft,'reading',Reading); PsdJson.Put(Applied,'reading',Reading);
    PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
    Result := True;
  finally Affected.Free; end;
end;
end.
