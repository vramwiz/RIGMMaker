unit RigmAnimeRankingModel;
// 順位紹介パートの入力と表示。調査・画像生成・音声出力は実行しない。
interface
uses System.JSON, RigmMovieModel, RigmMovieComposition;
const
  AnimeRankingSections: array[0..6] of string = ('rank','body','characters','credits','op','ed','summary');
  AnimeRankingSectionNames: array[0..6] of string = ('順位','作品タイトル・概要','登場人物','原作者・制作会社','OP紹介・評価','ED紹介・評価','作品総評');
  AnimeRankingFields: array[0..7] of string = ('rank','workTitle','originalAuthor','studio','opSong','opArtist','edSong','edArtist');
  AnimeRankingFieldNames: array[0..7] of string = ('順位（1～999）','作品タイトル','原作者（原作なし・未確認も可）','アニメ制作会社','OP曲名（なし・未確認も可）','OPアーティスト','ED曲名（なし・未確認も可）','EDアーティスト');
procedure PrepareAnimeRanking(Project: TRigmMovieProject);
procedure ValidateAnimeRanking(Project: TRigmMovieProject);
procedure SetAnimeRankingField(Project: TRigmMovieProject; const Key,Value: string);
function AnimeRankingReason(Project: TRigmMovieProject): string;
function AnimeRankingSceneSection(Project: TRigmMovieProject; Scene: TRigmMovieScene): string;
function AnimeRankingOverlay(Project: TRigmMovieProject; Scene: TRigmMovieScene): string;
procedure ConfigureAnimeRankingScenes(Project: TRigmMovieProject);
function AnimeRankingInputTemplate: string;
procedure ImportAnimeRankingText(Project: TRigmMovieProject; const Text: string);
implementation
uses System.SysUtils, System.StrUtils, RigmJson, PsdJson, RigmScriptTypes,
  RigmScriptTextModel, RigmScriptSummaryModel;
procedure PrepareAnimeRanking(Project: TRigmMovieProject);
begin
  if not IsAnimeRankingScript(Project) then Exit;
  PrepareScriptText(Project);
  if Project.ScriptWizard.GetValue('animeRanking')=nil then begin
    var O := TJSONObject.Create;
    for var Key in AnimeRankingFields do O.AddPair(Key,'');
    PsdJson.Put(O,'rank','1'); O.AddPair('autoRankText','第1位です。');
    Project.ScriptWizard.AddPair('animeRanking',O);
    PsdJson.Put(JO(Project.ScriptWizard,'scriptText'),'activeSection','rank');
  end;
  for var Id in AnimeRankingSections do if (Id<>'summary') and (ScriptSection(Project,Id)=nil) then begin
    var S := TJSONObject.Create; S.AddPair('id',Id); S.AddPair('scope','episode'); S.AddPair('text','');
    JA(JO(Project.ScriptWizard,'scriptText'),'sections').AddElement(S);
  end;
  if Project.ScriptWizard.GetValue('rankingInitialized')=nil then begin
    PsdJson.Put(ScriptSection(Project,'rank'),'text',JS(JO(Project.ScriptWizard,'animeRanking'),'autoRankText'));
    PsdJson.Put(Project.ScriptWizard,'rankingInitialized',TJSONBool.Create(True));
  end;
  PsdJson.Put(Project.ScriptWizard,'summaryChoice','yes');
end;
procedure ValidateAnimeRanking(Project: TRigmMovieProject);
begin
  if not IsAnimeRankingScript(Project) then Exit;
  var O := Project.ScriptWizard.GetValue('animeRanking');
  if not (O is TJSONObject) then raise Exception.Create('順位紹介の保存情報がありません。');
  for var Key in AnimeRankingFields do begin
    var V := TJSONObject(O).GetValue(Key);
    if not (V is TJSONString) or (Length(V.Value)>512) then raise Exception.Create('順位紹介の項目は512文字以内の文字列です。');
    for var Ch in V.Value do if Ord(Ch)<32 then raise Exception.Create('作品情報は改行なしで入力してください。');
  end;
  for var Id in AnimeRankingSections do if (Id<>'summary') and (ScriptSection(Project,Id)=nil) then
    raise Exception.Create('順位紹介の台本区分がありません。');
end;
procedure SetAnimeRankingField(Project: TRigmMovieProject; const Key,Value: string);
begin
  if not MatchStr(Key,AnimeRankingFields) or (Length(Value)>512) then raise Exception.Create('作品情報の項目・長さが不正です。');
  for var Ch in Value do if Ord(Ch)<32 then raise Exception.Create('作品情報は改行なしで入力してください。');
  var N: Integer;
  if (Key='rank') and (Value<>'') and (not TryStrToInt(Value,N) or (N<1) or (N>999)) then
    raise Exception.Create('順位は1～999の整数で入力してください。');
  PrepareAnimeRanking(Project); var O := JO(Project.ScriptWizard,'animeRanking');
  if Key='rank' then begin
    var Section := ScriptSection(Project,'rank'); var Current := JS(Section,'text');
    var Generated := ''; if Value<>'' then Generated := '第'+StrToInt(Value).ToString+'位です。';
    // 自動文と一致する間だけ追従。編集したセリフは推測で置き換えない。
    if Current=JS(O,'autoRankText') then PsdJson.Put(Section,'text',Generated);
    PsdJson.Put(O,'autoRankText',Generated);
  end;
  var Stored := Value; if (Key='rank') and (Value<>'') then Stored := StrToInt(Value).ToString;
  PsdJson.Put(O,Key,Stored);
end;
function AnimeRankingReason(Project: TRigmMovieProject): string;
begin
  Result := ''; ValidateAnimeRanking(Project); var O := JO(Project.ScriptWizard,'animeRanking'); var N: Integer;
  if not TryStrToInt(JS(O,'rank'),N) or (N<1) or (N>999) then Exit('順位を1～999で入力してください。');
  if Trim(JS(O,'workTitle'))='' then Exit('作品タイトルを入力してください。');
  if Trim(JS(ScriptSection(Project,'rank'),'text'))='' then Exit('順位のセリフを入力してください。');
  if Trim(JS(ScriptSection(Project,'body'),'text'))='' then Exit('作品タイトル・概要のセリフを入力してください。');
end;
function AnimeRankingSceneSection(Project: TRigmMovieProject; Scene: TRigmMovieScene): string;
begin
  Result := ''; if (Scene=nil) or not IsAnimeRankingScript(Project) then Exit;
  Result := JS(Scene.Animation,'animeRankingSection');
end;
function AnimeRankingOverlay(Project: TRigmMovieProject; Scene: TRigmMovieScene): string;
  function Known(const Key: string): string;
  begin Result := JS(JO(Project.ScriptWizard,'animeRanking'),Key); if Trim(Result)='' then Result := '未確認'; end;
begin
  Result := ''; var Section := AnimeRankingSceneSection(Project,Scene);
  if Section='rank' then Result := '第'+Known('rank')+'位'
  else if Section='body' then Result := Known('workTitle')
  else if Section='credits' then Result := '原作者：'+Known('originalAuthor')+#13#10+'アニメ制作：'+Known('studio')
  else if Section='op' then Result := 'OP：'+Known('opSong')+#13#10+'アーティスト：'+Known('opArtist')
  else if Section='ed' then Result := 'ED：'+Known('edSong')+#13#10+'アーティスト：'+Known('edArtist');
end;
procedure ConfigureAnimeRankingScenes(Project: TRigmMovieProject);
begin
  if not IsAnimeRankingScript(Project) then Exit;
  for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do begin
    var Row := TJSONObject(V); var Cue := Project.Cue(JS(Row,'cueId')); if Cue=nil then Continue;
    var Scene := Project.Scene(Cue.Scene); if Scene=nil then Continue;
    var Section := JS(Row,'section');
    if Scene.Animation.GetValue('animeRankingSection')=nil then begin
      PsdJson.Put(Scene.Animation,'animeRankingSection',Section);
      for var I := 0 to High(AnimeRankingSections) do if AnimeRankingSections[I]=Section then Scene.Title := AnimeRankingSectionNames[I];
    end;
    if Section='rank' then Scene.DisplayMode := 'none';
  end;
  if Project.ScriptWizard.GetValue('rankingImport') is TJSONObject then begin
    var Input := JO(Project.ScriptWizard,'rankingImport');
    if JB(Input,'pending') then begin
      for var V in JA(Input,'readings') do begin
        var Entry := TJSONObject(V);
        for var R in JA(JO(Project.ScriptWizard,'casting'),'rows') do begin
          var Row := TJSONObject(R);
          if (JS(Row,'section')=JS(Entry,'section')) and (JI(Row,'offset')=JI(Entry,'offset')) then begin
            var Cue := Project.Cue(JS(Row,'cueId'));
            if (Cue<>nil) and (Cue.Text=JS(Entry,'text')) then begin Cue.Subtitle := Cue.Text; Cue.VoiceReading := JS(Entry,'reading'); end;
          end;
        end;
      end;
      for var S in Project.Scenes do begin
        var Key := AnimeRankingSceneSection(Project,S); var Settings := Input.GetValue(Key) as TJSONObject;
        if (Settings<>nil) and (Key<>'rank') then begin
          S.ImagePrompt := JS(Settings,'prompt'); S.Description := JS(Settings,'description');
          S.DisplayMode := 'none'; if S.Description<>'' then S.DisplayMode := 'text';
          if S.ImagePrompt<>'' then begin S.DisplayMode := 'image'; if S.Description<>'' then S.DisplayMode := 'both'; end;
        end;
      end;
      PsdJson.Put(Input,'pending',TJSONBool.Create(False));
    end;
  end;
end;
function AnimeRankingInputTemplate: string;
begin
  Result := '作品タイトル：'+#13#10+'順位：1'+#13#10+'原作者：未確認'+#13#10+'制作会社：未確認'+#13#10+
    'OP曲名：未確認'+#13#10+'OPアーティスト：未確認'+#13#10+'ED曲名：未確認'+#13#10+'EDアーティスト：未確認'+#13#10;
  for var I := 0 to High(AnimeRankingSections) do begin
    Result := Result+#13#10+'*'+AnimeRankingSectionNames[I]+#13#10;
    if AnimeRankingSections[I]='summary' then Result := Result+'物語：'+#13#10+'キャラクター：'+#13#10+'作画：'+#13#10+'演出：'+#13#10+'声の演技：'+#13#10+'音楽：'+#13#10
    else if AnimeRankingSections[I]<>'rank' then Result := Result+'画像：'+#13#10+'表示：'+#13#10;
    Result := Result+'本文：'+#13#10;
  end;
end;
procedure ImportAnimeRankingText(Project: TRigmMovieProject; const Text: string);
const Labels: array[0..7] of string = ('順位','作品タイトル','原作者','制作会社','OP曲名','OPアーティスト','ED曲名','EDアーティスト');
var Section: string; InBody: Boolean; Input,Readings: TJSONObject;
  procedure AppendLine(const Value: string; Paired: Boolean);
  begin
    var Target := ScriptSection(Project,Section);
    var Before := JS(Target,'text'); if Before<>'' then Before := Before+#13#10;
    if Paired and (Trim(Value)='') then raise Exception.Create('字幕の空行は取り込めません。');
    if Paired and (Length(Value)>2000) then raise Exception.Create('字幕・読みのペアは1行2000文字以内です。');
    if Paired then JA(Input,'readings').AddElement(TJSONObject.Create.AddPair('section',Section)
      .AddPair('offset',TJSONNumber.Create(Length(Before))).AddPair('text',Value).AddPair('reading',Value));
    PsdJson.Put(Target,'text',Before+Value);
  end;
begin
  if Length(Text)>1024*1024 then raise Exception.Create('台本は1MiB以内です。');
  PrepareAnimeRanking(Project); PrepareScriptSummary(Project);
  // 明示的な再取込では、ファイルにない作品情報・点数を旧作品から流用しない。
  for var Key in AnimeRankingFields do SetAnimeRankingField(Project,Key,'');
  var Draft := JO(JO(Project.ScriptWizard,'summaryData'),'draft');
  for var Key in ['text','subtitle','reading'] do PsdJson.Put(Draft,Key,'');
  for var V in JA(Draft,'items') do PsdJson.Put(TJSONObject(V),'value','');
  for var Id in AnimeRankingSections do begin
    if ScriptSection(Project,Id)=nil then begin
      var O := TJSONObject.Create.AddPair('id',Id).AddPair('scope','episode').AddPair('text','');
      JA(JO(Project.ScriptWizard,'scriptText'),'sections').AddElement(O);
    end;
    PsdJson.Put(ScriptSection(Project,Id),'text','');
  end;
  Input := TJSONObject.Create.AddPair('pending',TJSONBool.Create(True)).AddPair('readings',TJSONArray.Create);
  Project.ScriptWizard.RemovePair('rankingImport').Free; Project.ScriptWizard.AddPair('rankingImport',Input);
  Readings := nil; Section := ''; InBody := False;
  for var Raw in NormalizeScriptText(Text).Split([#13#10]) do begin
    var Line := Raw.Trim; if Line='' then Continue;
    if Line.StartsWith('*') then begin
      Section := ''; InBody := False;
      for var I := 0 to High(AnimeRankingSections) do if Line='*'+AnimeRankingSectionNames[I] then Section := AnimeRankingSections[I];
      if Line='*総評' then Section := 'summary';
      if MatchStr(Line,['*作品紹介','*作品タイトル','*概要']) then Section := 'body';
      if Line='*制作情報' then Section := 'credits';
      if Line='*OP' then Section := 'op'; if Line='*ED' then Section := 'ed';
      if Section='' then raise Exception.Create('未対応の順位紹介区分：'+Line);
      Continue;
    end;
    var Colon := Line.IndexOf('：'); if Colon<0 then Colon := Line.IndexOf(':');
    var Key := ''; var Value := ''; if Colon>=0 then begin Key := Line.Substring(0,Colon); Value := Line.Substring(Colon+1).Trim; end;
    if Section='' then begin
      var Found := False;
      for var I := 0 to High(Labels) do if Key=Labels[I] then begin SetAnimeRankingField(Project,AnimeRankingFields[I],Value); Found := True; end;
      if Key='作品名' then begin SetAnimeRankingField(Project,'workTitle',Value); Found := True; end;
      if Key='アニメ制作会社' then begin SetAnimeRankingField(Project,'studio',Value); Found := True; end;
      if (Key='種類') and MatchStr(Value,['アニメ（順位）','anime-ranking']) then Found := True;
      if not Found then raise Exception.Create('未対応の作品情報：'+Line);
      Continue;
    end;
    if (Section='summary') and not InBody and (Key<>'本文') then begin
      var Found := False;
      for var V in JA(JO(JO(Project.ScriptWizard,'summaryData'),'draft'),'items') do
        if JS(TJSONObject(V),'label')=Key then begin PsdJson.Put(TJSONObject(V),'value',Value); Found := True; end;
      if not Found then raise Exception.Create('アニメ評価項目を確認してください：'+Line);
      Continue;
    end;
    if Key='本文' then begin InBody := True; if Value<>'' then AppendLine(Value,False); Continue; end;
    if not InBody and MatchStr(Key,['画像','表示']) then begin
      if Section='rank' then begin
        if Value<>'' then raise Exception.Create('順位シーンは画像・背景なしの黒画面です。画像指定を外してください。');
        Continue;
      end;
      var Settings := Input.GetValue(Section) as TJSONObject;
      if Settings=nil then begin Settings := TJSONObject.Create; Input.AddPair(Section,Settings); end;
      var Name := 'prompt'; if Key='表示' then Name := 'description'; PsdJson.Put(Settings,Name,Value); Continue;
    end;
    if not InBody then raise Exception.Create('本文：の後へセリフを入力してください。');
    if Key='字幕' then begin
      AppendLine(Value,True); Readings := TJSONObject(JA(Input,'readings').Items[JA(Input,'readings').Count-1]);
    end else if Key='読み' then begin
      if (Readings=nil) or (JS(Readings,'section')<>Section) then raise Exception.Create('読みは字幕の直後へ指定してください。');
      if Value<>'' then begin ValidateVoiceReading(Value); PsdJson.Put(Readings,'reading',Value); end; Readings := nil;
    end else begin AppendLine(Raw,False); Readings := nil; end;
  end;
  if JS(ScriptSection(Project,'rank'),'text')='' then
    PsdJson.Put(ScriptSection(Project,'rank'),'text',JS(JO(Project.ScriptWizard,'animeRanking'),'autoRankText'));
  var Reason := AnimeRankingReason(Project); if Reason<>'' then raise Exception.Create(Reason);
  PsdJson.Put(JO(JO(Project.ScriptWizard,'summaryData'),'draft'),'text',JS(ScriptSection(Project,'summary'),'text'));
  ValidateScriptText(JO(Project.ScriptWizard,'scriptText')); ValidateAnimeRanking(Project);
end;
end.
