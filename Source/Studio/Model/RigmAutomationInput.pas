unit RigmAutomationInput;

// 自動制作の入力書式を検査する。作品・音声・画像は作成せず、不足をまとめて返す。
interface
uses System.JSON;
function ValidateAutomationInput(const Text: string; IncludeSharedSections: Boolean=False): TJSONObject; // 呼出側所有。valid/issues/dataを返す。
implementation
uses System.SysUtils, System.Classes, System.Generics.Collections, System.Math,
  RigmScriptSummaryModel, RigmMovieModel;
function ValidateAutomationInput(const Text: string; IncludeSharedSections: Boolean): TJSONObject;
var Lines: TStringList; Data,Summary,Scene: TJSONObject; Issues,Scenes,Items: TJSONArray;
  Seen: TDictionary<string,Boolean>; Section: string; InBody: Boolean;
  function S(O: TJSONObject; const Key: string): string;
  begin Result := ''; if (O<>nil) and (O.GetValue(Key) is TJSONString) then Result := O.GetValue(Key).Value; end;
  procedure SetText(O: TJSONObject; const Key,Value: string);
  begin O.RemovePair(Key).Free; O.AddPair(Key,Value); end;
  procedure Issue(const Field,Message: string; Line: Integer=0);
  begin Issues.AddElement(TJSONObject.Create.AddPair('field',Field).AddPair('line',TJSONNumber.Create(Line)).AddPair('message',Message)); end;
  procedure Required(O: TJSONObject; const Key,Field: string);
  begin if S(O,Key).Trim='' then Issue(Field,'未記入です。'); end;
  function BodyTarget: TJSONObject;
  begin
    Result := Scene;
    if Section='summary' then Result := Summary
    else if (Section='opening') or (Section='closing') or (Section='posting') then
      Result := TJSONObject(Data.GetValue(Section));
  end;
  procedure AppendBody(const Raw: string; LineNumber: Integer);
  begin
    var Target := BodyTarget;
    if Section='posting' then begin
      var Body := S(Target,'body');
      var SeenKey := Section+'-body-'+Scenes.Count.ToString;
      if Seen.ContainsKey(SeenKey) then Body := Body+#13#10;
      SetText(Target,'body',Body+Raw); Seen.AddOrSetValue(SeenKey,True); Exit;
    end;
    var Text := Raw.Trim;
    if Text.Replace(#$3000,'').Trim='' then Exit; // 全角空白だけの行も詰める。
    var Key := ''; var Value := Raw;
    var SplitAt := Pos('：',Text); var AsciiColon := Pos(':',Text);
    if (SplitAt=0) or ((AsciiColon>0) and (AsciiColon<SplitAt)) then SplitAt := AsciiColon;
    if SplitAt>0 then begin Key := Text.Substring(0,SplitAt-1).Trim; Value := Text.Substring(SplitAt).Trim; end;
    if Value.Replace(#$3000,'').Trim='' then Value := '';
    if not (Target.GetValue('dialogue') is TJSONArray) then Target.AddPair('dialogue',TJSONArray.Create);
    var Dialogue := TJSONArray(Target.GetValue('dialogue'));
    if Key='読み' then begin
      if Dialogue.Count=0 then begin Issue(Section+'.reading','「読み：」の前に字幕またはセリフを入力してください。',LineNumber); Exit; end;
      var Last := TJSONObject(Dialogue[Dialogue.Count-1]);
      if Last.GetValue('reading')<>nil then begin Issue(Section+'.reading','同じセリフの読みが重複しています。',LineNumber); Exit; end;
      try ValidateVoiceReading(Value); ValidateVoiceReading(S(Last,'subtitle'));
      except on E: Exception do Issue(Section+'.reading',E.Message,LineNumber); end;
      SetText(Last,'reading',Value); Exit;
    end;
    if Key='字幕' then begin
      if Value='' then begin Issue(Section+'.subtitle','「字幕：」にセリフを入力してください。',LineNumber); Exit; end;
      try ValidateVoiceReading(Value);
      except on E: Exception do Issue(Section+'.subtitle',E.Message,LineNumber); end;
    end else Value := Raw;
    Dialogue.AddElement(TJSONObject.Create.AddPair('subtitle',Value));
    var Body := S(Target,'body'); if Body<>'' then Body := Body+#13#10;
    SetText(Target,'body',Body+Value);
  end;
begin
  Result := TJSONObject.Create; Issues := TJSONArray.Create; Result.AddPair('issues',Issues);
  Data := TJSONObject.Create; Result.AddPair('data',Data);
  Scenes := TJSONArray.Create; Data.AddPair('scenes',Scenes);
  Summary := TJSONObject.Create; Data.AddPair('summary',Summary);
  Items := TJSONArray.Create; Summary.AddPair('items',Items);
  Lines := TStringList.Create; Seen := TDictionary<string,Boolean>.Create;
  try
    try
      if Length(Text)>200000 then begin Issue('text','入力は200000 UTF-16文字以内です。'); Exit; end;
      Lines.Text := Text.Replace(#13#10,#10).Replace(#13,#10);
      Section := 'header'; InBody := False; Scene := nil;
      for var I := 0 to Lines.Count-1 do begin
        var Raw := Lines[I]; var Line := Raw.Trim;
        if Line.StartsWith('*') then begin
          var Name := Line.Substring(1).Trim; InBody := False;
          if IncludeSharedSections and ((Name='前段') or (Name='締め') or (Name='投稿情報')) then begin
            if Name='前段' then Section := 'opening' else if Name='締め' then Section := 'closing' else Section := 'posting';
            if Seen.ContainsKey(Section) then Issue(Section,'区分が重複しています。',I+1)
            else begin Data.AddPair(Section,TJSONObject.Create); Seen.Add(Section,True); end;
            Scene := nil;
          end else if Name='背景' then begin
            if Seen.ContainsKey('background') then Issue('background','背景が重複しています。',I+1);
            Seen.AddOrSetValue('background',True); Section := 'background'; Scene := nil;
          end else if Name='総評' then begin
            if Seen.ContainsKey('summary') then Issue('summary','総評が重複しています。',I+1);
            Seen.AddOrSetValue('summary',True); Section := 'summary'; Scene := nil;
          end else begin
            Section := 'scene'; Scene := TJSONObject.Create; Scenes.AddElement(Scene); Scene.AddPair('title',Name);
            if Name='' then Issue('scenes['+(Scenes.Count-1).ToString+'].title','シーン名がありません。',I+1);
          end;
          Continue;
        end;
        if InBody then begin
          AppendBody(Raw,I+1);
          Continue;
        end;
        if Line='' then Continue;
        var SplitAt := Pos('：',Line); var AsciiColon := Pos(':',Line);
        if (SplitAt=0) or ((AsciiColon>0) and (AsciiColon<SplitAt)) then SplitAt := AsciiColon;
        if SplitAt=0 then begin Issue(Section,'項目名と「：」を付けてください。本文の前には「本文：」が必要です。',I+1); Continue; end;
        var Key := Line.Substring(0,SplitAt-1).Trim; var Value := Line.Substring(SplitAt).Trim;
        var SeenKey := Section+'-'+Scenes.Count.ToString+'-'+Key;
        if Seen.ContainsKey(SeenKey) then begin Issue(Key,'項目が重複しています。',I+1); Continue; end;
        Seen.Add(SeenKey,True);
        if Section='header' then begin
          if Key='作品名' then SetText(Data,'title',Value)
          else if Key='種類' then begin
            if Value='漫画' then SetText(Data,'scriptType','manga-introduction')
            else if Value='アニメ' then SetText(Data,'scriptType','anime-review')
            else Issue('scriptType','アニメ／漫画のどちらか一方を残してください。',I+1);
          end else if Key='ニコニコ漫画の作品URL' then SetText(Data,'workUrl',Value)
          else Issue(Key,'不明な入力項目です。',I+1);
        end else if Section='background' then begin
          if Key='画像' then SetText(Data,'backgroundPrompt',Value) else Issue(Key,'背景には「画像：」のみ指定できます。',I+1);
        end else if ((Key='本文') and ((Section='scene') or (Section='summary') or
          (Section='opening') or (Section='closing'))) or ((Key='概要') and (Section='posting')) then begin
          InBody := True;
          if Value<>'' then AppendBody(Value,I+1);
        end else if (Section='scene') or (Section='opening') or (Section='closing') then begin
          if Key='画像' then SetText(BodyTarget,'imagePrompt',Value)
          else if Key='表示' then SetText(BodyTarget,'displayText',Value)
          else Issue(Key,'シーンでは画像・表示・本文を指定してください。',I+1);
        end else if Section='posting' then begin
          if Key='タイトル' then SetText(BodyTarget,'title',Value)
          else Issue(Key,'投稿情報ではタイトル・概要を指定してください。',I+1);
        end else if Section='summary' then begin
          var Found := False;
          for var Axis in ScriptSummaryAxisNames do if Key=Axis then begin
            Found := True; var Score: Double;
            if not TryStrToFloat(Value,Score,TFormatSettings.Invariant) or IsNan(Score) or IsInfinite(Score)
              or (Score<0) or (Score>5) then Issue('summary.'+Axis,'点数は0～5の数値で入力してください。',I+1)
            else Items.AddElement(TJSONObject.Create.AddPair('label',Axis).AddPair('value',TJSONNumber.Create(Score)));
            Break;
          end;
          if not Found then Issue(Key,'総評はアプリの固定5項目を指定してください。',I+1);
        end;
      end;
      Required(Data,'title','title'); Required(Data,'scriptType','scriptType');
      if Length(S(Data,'title'))>128 then Issue('title','作品名は128文字以内です。');
      if Length(S(Data,'workUrl'))>4000 then Issue('workUrl','作品URLは4000文字以内です。');
      var TotalBody := 0;
      for var V in Scenes do Inc(TotalBody,Length(S(TJSONObject(V),'body'))+2);
      if TotalBody>100000 then Issue('scenes','本題の本文合計は100000文字以内です。');
      for var Key in ['opening','closing'] do if Data.GetValue(Key) is TJSONObject then begin
        var O := TJSONObject(Data.GetValue(Key));
        if Length(S(O,'body'))>100000 then Issue(Key+'.body','本文は100000文字以内です。');
        if Length(S(O,'imagePrompt'))>16004 then Issue(Key+'.image','画像指示は16004文字以内です。');
        if Length(S(O,'displayText'))>3000 then Issue(Key+'.display','表示テキストは3000文字以内です。');
      end;
      if Data.GetValue('posting') is TJSONObject then begin
        var O := TJSONObject(Data.GetValue('posting'));
        if Length(S(O,'title'))>1000 then Issue('posting.title','投稿タイトルは1000文字以内です。');
        if Length(S(O,'body'))>20000 then Issue('posting.body','概要は20000文字以内です。');
      end;
      Required(Data,'backgroundPrompt','background.image');
      if Scenes.Count=0 then Issue('scenes','通常シーンがありません。');
      for var I := 0 to Scenes.Count-1 do begin
        var O := TJSONObject(Scenes[I]); var Prefix := 'scenes['+I.ToString+'].';
        Required(O,'imagePrompt',Prefix+'image'); Required(O,'body',Prefix+'body');
        if Length(S(O,'title'))>300 then Issue(Prefix+'title','シーン名は300文字以内です。');
        if Length(S(O,'imagePrompt'))>16004 then Issue(Prefix+'image','画像指示は16004文字以内です。');
        if Length(S(O,'displayText'))>3000 then Issue(Prefix+'display','表示テキストは3000文字以内です。');
      end;
      Required(Summary,'body','summary.body');
      if Length(S(Summary,'body'))>2000 then Issue('summary.body','総評本文は2000文字以内です。');
      if Summary.GetValue('dialogue') is TJSONArray then begin
        var Reading := '';
        for var V in TJSONArray(Summary.GetValue('dialogue')) do begin
          var Entry := TJSONObject(V); var Value := S(Entry,'reading');
          if Value='' then Value := S(Entry,'subtitle');
          if Reading<>'' then Reading := Reading+#13#10; Reading := Reading+Value;
        end;
        try ValidateVoiceReading(Reading);
        except on E: Exception do Issue('summary.reading','総評の読み全体：'+E.Message); end;
      end;
      for var Axis in ScriptSummaryAxisNames do begin
        var Found := False;
        for var V in Items do if S(TJSONObject(V),'label')=Axis then Found := True;
        if not Found then Issue('summary.'+Axis,'点数が未記入または不正です。');
      end;
    finally Result.AddPair('valid',TJSONBool.Create(Issues.Count=0)); end;
  finally Seen.Free; Lines.Free; end;
end;
end.
