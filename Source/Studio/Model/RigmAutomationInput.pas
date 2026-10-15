unit RigmAutomationInput;

// 自動制作の入力書式を検査する。作品・音声・画像は作成せず、不足をまとめて返す。
interface
uses System.JSON;
function ValidateAutomationInput(const Text: string): TJSONObject; // 呼出側所有。valid/issues/dataを返す。
implementation
uses System.SysUtils, System.Classes, System.Generics.Collections, System.Math,
  RigmScriptSummaryModel;
function ValidateAutomationInput(const Text: string): TJSONObject;
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
          if Name='背景' then begin
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
          var Target := Scene; if Section='summary' then Target := Summary;
          var Body := S(Target,'body');
          if Seen.ContainsKey(Section+'-body-'+Scenes.Count.ToString) then Body := Body+#13#10;
          SetText(Target,'body',Body+Raw); Seen.AddOrSetValue(Section+'-body-'+Scenes.Count.ToString,True);
          Continue;
        end;
        if Line='' then Continue;
        var SplitAt := Pos('：',Line); if SplitAt=0 then SplitAt := Pos(':',Line);
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
        end else if (Key='本文') and ((Section='scene') or (Section='summary')) then begin
          InBody := True;
          if Value<>'' then begin
            if Section='summary' then SetText(Summary,'body',Value) else SetText(Scene,'body',Value);
            Seen.AddOrSetValue(Section+'-body-'+Scenes.Count.ToString,True);
          end;
        end else if Section='scene' then begin
          if Key='画像' then SetText(Scene,'imagePrompt',Value)
          else if Key='表示' then SetText(Scene,'displayText',Value)
          else Issue(Key,'シーンでは画像・表示・本文を指定してください。',I+1);
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
      for var Axis in ScriptSummaryAxisNames do begin
        var Found := False;
        for var V in Items do if S(TJSONObject(V),'label')=Axis then Found := True;
        if not Found then Issue('summary.'+Axis,'点数が未記入または不正です。');
      end;
    finally Result.AddPair('valid',TJSONBool.Create(Issues.Count=0)); end;
  finally Seen.Free; Lines.Free; end;
end;
end.
