unit RigmScriptReadingModel;

// 字幕を保持して、作品ごとの辞書から読みの補正候補を作る。確認前には変更しない。
interface
uses System.JSON, RigmMovieModel;
function ScriptReadingDictionary(Project: TRigmMovieProject): TJSONArray; // 呼出側所有。
procedure ValidateReadingDictionary(Entries: TJSONArray);
function CorrectScriptReading(const Text: string; Entries: TJSONArray): string;
function ScriptReadingCorrections(Project: TRigmMovieProject; Entries: TJSONArray): TJSONArray;
function ApplyScriptReadingCorrections(Project: TRigmMovieProject; Entries, Selected: TJSONArray): Integer;
implementation
uses System.SysUtils, System.Classes, System.Generics.Collections, RigmJson, PsdJson,
  RigmScriptSummaryModel;

procedure ValidateReadingDictionary(Entries: TJSONArray);
begin
  if (Entries=nil) or (Entries.Count>256) then raise Exception.Create('読み辞書は256件以内です。');
  var Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in Entries do begin
      if not (V is TJSONObject) then raise Exception.Create('読み辞書の項目が不正です。');
      var O := TJSONObject(V);
      if not (O.GetValue('word') is TJSONString) or not (O.GetValue('reading') is TJSONString) then
        raise Exception.Create('読み辞書には表記と読みを指定してください。');
      var Word := JS(O,'word'); var Reading := JS(O,'reading');
      if (Word.Replace('　','').Trim='') or (Reading.Replace('　','').Trim='') or (Word<>Word.Trim) or (Reading<>Reading.Trim) or
        (Length(Word)>128) or (Length(Reading)>256) then
        raise Exception.Create('辞書の表記は1～128文字、読みは1～256文字で入力してください。');
      ValidateVoiceReading(Word); ValidateVoiceReading(Reading);
      for var C in Word do if (Ord(C)<32) or (C='=') or (C='＝') then
        raise Exception.Create('辞書の表記に改行・制御文字・＝は使えません。');
      for var C in Reading do if not (((Ord(C)>=$3041) and (Ord(C)<=$3096)) or
        ((Ord(C)>=$309D) and (Ord(C)<=$309E)) or ((Ord(C)>=$30A1) and (Ord(C)<=$30FA)) or
        ((Ord(C)>=$30FC) and (Ord(C)<=$30FE)) or (C=' ') or (C='　') or (C='・')) then
        raise Exception.Create('辞書の読みはひらがな・カタカナで入力してください。');
      if Seen.ContainsKey(Word) then raise Exception.Create('辞書の表記が重複しています：'+Word);
      Seen.Add(Word,True);
    end;
  finally Seen.Free; end;
end;

function ScriptReadingDictionary(Project: TRigmMovieProject): TJSONArray;
begin
  var W := Project.ScriptWizard;
  if (W<>nil) and (W.GetValue('readingDictionary')<>nil) then begin
    if not (W.GetValue('readingDictionary') is TJSONObject) then raise Exception.Create('読み辞書の保存形式が不正です。');
    var O := JO(W,'readingDictionary');
    if (JS(O,'format')<>'RIGMMaker.ScriptReadingDictionary') or (JI(O,'schemaVersion')<>1) or
      not (O.GetValue('items') is TJSONArray) then raise Exception.Create('読み辞書の保存形式が不正です。');
    ValidateReadingDictionary(JA(O,'items')); Exit(JA(O,'items').Clone as TJSONArray);
  end;
  Result := TJSONArray.Create;
  Result.AddElement(TJSONObject.Create.AddPair('word','神獣').AddPair('reading','しんじゅう'));
  Result.AddElement(TJSONObject.Create.AddPair('word','幻獣').AddPair('reading','げんじゅう'));
  Result.AddElement(TJSONObject.Create.AddPair('word','世界樹').AddPair('reading','せかいじゅ'));
end;

function CorrectScriptReading(const Text: string; Entries: TJSONArray): string;
begin
  ValidateReadingDictionary(Entries);
  var Output := TStringBuilder.Create;
  try
    var Position := 0;
    while Position<Length(Text) do begin
      var Best: TJSONObject := nil; var BestLength := 0;
      for var V in Entries do begin
        var O := TJSONObject(V); var Word := JS(O,'word');
        if (Length(Word)>BestLength) and (Position+Length(Word)<=Length(Text)) and (Text.Substring(Position,Length(Word))=Word) then begin
          Best := O; BestLength := Length(Word);
        end;
      end;
      if Best<>nil then begin Output.Append(JS(Best,'reading')); Inc(Position,BestLength); end
      else begin Output.Append(Text[Position+1]); Inc(Position); end;
    end;
    Result := Output.ToString;
  finally Output.Free; end;
end;

function ScriptReadingCorrections(Project: TRigmMovieProject; Entries: TJSONArray): TJSONArray;
begin
  ValidateReadingDictionary(Entries); Result := TJSONArray.Create;
  try
    for var I := 0 to Project.Cues.Count-1 do begin
      var C := Project.Cues[I]; var Before := C.SpokenText;
      // 手入力した読みを元原稿へ戻さず、現在の読みの辞書該当語だけを補正する。
      var After := CorrectScriptReading(Before,Entries);
      if After=Before then Continue;
      try ValidateVoiceReading(After);
      except on E: Exception do raise Exception.CreateFmt('セリフ%dの補正後の読み：%s',[I+1,E.Message]); end;
      Result.AddElement(TJSONObject.Create.AddPair('cueId',C.Id).AddPair('subtitle',C.Subtitle)
        .AddPair('before',Before).AddPair('after',After).AddPair('number',TJSONNumber.Create(I+1)));
    end;
  except Result.Free; raise; end;
end;

function ApplyScriptReadingCorrections(Project: TRigmMovieProject; Entries, Selected: TJSONArray): Integer;
begin
  Result := 0; ValidateReadingDictionary(Entries);
  if (Project.ScriptWizard=nil) or (Selected=nil) then raise Exception.Create('読みの確認対象がありません。');
  var Changes := TDictionary<string,string>.Create;
  try
    // 現在値・候補を全件検査してから変更する。外部更新後の古い候補を採用しない。
    for var V in Selected do begin
      if not (V is TJSONObject) then raise Exception.Create('読みの補正候補が不正です。');
      var O := TJSONObject(V); var C := Project.Cue(JS(O,'cueId'));
      if (C=nil) or Changes.ContainsKey(C.Id) then raise Exception.Create('読みの補正対象が不正または重複しています。');
      if (C.SpokenText<>JS(O,'before')) or (C.Subtitle<>JS(O,'subtitle')) or
        (JS(O,'after')<>CorrectScriptReading(C.SpokenText,Entries)) or (JS(O,'after')=C.SpokenText) then
        raise Exception.Create('セリフまたは辞書が変わりました。読みの候補を確認し直してください。');
      ValidateVoiceReading(JS(O,'after')); Changes.Add(C.Id,JS(O,'after'));
    end;
    var SummaryReading := ''; var SummaryId := ''; var Count := 0;
    for var C in Project.Cues do if IsScriptSummaryCue(Project,C) then begin
      var Reading := C.SpokenText; var After: string;
      if Changes.TryGetValue(C.Id,After) then begin Reading := After; SummaryId := C.Id; end;
      if Count>0 then SummaryReading := SummaryReading+#13#10;
      SummaryReading := SummaryReading+Reading; Inc(Count);
    end;
    if SummaryId<>'' then begin
      try ValidateVoiceReading(SummaryReading);
      except on E: Exception do raise Exception.Create('総評の読み全体：'+E.Message); end;
    end;
    for var C in Project.Cues do begin
      var After: string; if not Changes.TryGetValue(C.Id,After) then Continue;
      C.VoiceReading := After; C.VoiceQuery := ''; C.VoiceQueryKey := '';
      C.AudioKey := ''; C.VoiceHeardKey := ''; C.EffectAudioKey := ''; Inc(Result);
    end;
    if SummaryId<>'' then SyncSummaryReading(Project,SummaryId);
    PsdJson.Put(Project.ScriptWizard,'readingDictionary',TJSONObject.Create
      .AddPair('format','RIGMMaker.ScriptReadingDictionary').AddPair('schemaVersion',TJSONNumber.Create(1))
      .AddPair('items',Entries.Clone as TJSONArray));
    if Result>0 then begin
      PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
      if JS(Project.ScriptWizard,'stage')='subtitles' then PsdJson.Put(Project.ScriptWizard,'subtitlesStatus','in-progress');
    end;
  finally Changes.Free; end;
end;
end.
