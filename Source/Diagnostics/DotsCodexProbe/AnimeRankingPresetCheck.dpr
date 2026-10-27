program AnimeRankingPresetCheck;
{$APPTYPE CONSOLE}
// ユーザー側コンパイル用。今回の作業ではコンパイル・実行しない。
uses System.SysUtils, System.JSON,
  RigmMovieModel, RigmScriptTypes, RigmScriptTextModel, RigmAnimeRankingModel,
  RigmScriptSummaryModel, RigmScriptCastingModel, RigmScriptNavigationModel,
  RigmScriptSceneAssignmentModel, RigmScriptCopyModel, RigmJson, PsdJson;
var Checks: Integer;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Inc(Checks); Writeln('PASS ',Message); end;
function NewProject(const Kind: string): TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create;
  Result.ScriptWizard := TJSONObject.Create.AddPair('scriptType',Kind).AddPair('titleInput','所有テスト').AddPair('selectedCharacters',TJSONArray.Create);
  PrepareScriptText(Result);
  if IsAnimeRankingScript(Result) then PrepareAnimeRanking(Result);
  PrepareScriptSummary(Result);
end;
procedure Run;
begin
  Check((ScriptTypeId(0)='anime-review') and (ScriptTypeId(1)='manga-introduction') and
    (ScriptTypeIndex('anime-ranking')>=0),'existing IDs remain and ranking is selectable');
  var Manga := NewProject('manga-introduction'); var P := NewProject('anime-ranking');
  try
    Check(JA(JO(JO(Manga.ScriptWizard,'summaryData'),'draft'),'items').Count=5,'manga retains five axes');
    Check(JA(JO(JO(P.ScriptWizard,'summaryData'),'draft'),'items').Count=6,'ranking initializes six anime axes');
    SetAnimeRankingField(P,'rank','4');
    Check(JS(ScriptSection(P,'rank'),'text')='第4位です。','untouched rank narration follows rank');
    PsdJson.Put(ScriptSection(P,'rank'),'text','手動の順位セリフ'); SetAnimeRankingField(P,'rank','3');
    Check(JS(ScriptSection(P,'rank'),'text')='手動の順位セリフ','edited rank narration is preserved');
    SetAnimeRankingField(P,'workTitle','架空の検証用題名');
    Check(AnimeRankingReason(P)<>'','overview narration is required');
    for var Id in ['body','characters','credits','op','ed'] do PsdJson.Put(ScriptSection(P,Id),'text','所有fixtureのセリフ');
    PsdJson.Put(ScriptSection(P,'body'),'text','タイトルのセリフ'+#13#10+#13#10+'概要のセリフ');
    var Summary := TJSONObject.Create.AddPair('id','summary').AddPair('scope','episode').AddPair('text','総評のセリフ');
    JA(JO(P.ScriptWizard,'scriptText'),'sections').AddElement(Summary);
    var D := JO(JO(P.ScriptWizard,'summaryData'),'draft'); PsdJson.Put(D,'text','総評のセリフ');
    for var V in JA(D,'items') do PsdJson.Put(TJSONObject(V),'value','3');
    Check(AnimeRankingReason(P)='','unknown optional credits do not invent facts or block narration');
    var Character := TJSONObject.Create.AddPair('path','Characters\Owned.rigm').AddPair('name','所有fixture').AddPair('renderFormat','rigm');
    JA(P.ScriptWizard,'selectedCharacters').AddElement(Character); PrepareScriptCasting(P);
    Check(P.Scenes.Count=7,'rank, overview, people, credits, OP, ED, summary form seven scenes');
    var BodyScene := ''; var BodyCount := 0;
    for var V in JA(JO(P.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='body' then begin
      var Cue := P.Cue(JS(TJSONObject(V),'cueId'));
      if BodyScene='' then BodyScene := Cue.Scene;
      Check(Cue.Scene=BodyScene,'title and overview share the same scene'); Inc(BodyCount);
    end;
    Check((BodyCount=2) and not ScriptSceneStartEditable(P,2),'overview cannot split into another screen');
    Check((P.EndCards.Count=0) and (P.Thumbnail.ImagePrompt=''),'no global ending or thumbnail is added');
    var Json := P.Json;
    try var Saved := TRigmMovieProject.FromJson(Json);
      try Check(IsAnimeRankingScript(Saved) and (Saved.Scenes.Count=7),'JSON round trip retains ranking and scene structure'); finally Saved.Free; end;
    finally Json.Free; end;
    var Copy := CreateScriptCopy(P,'2026-10-28T00:00:00Z');
    try Check((Copy.Id<>P.Id) and IsAnimeRankingScript(Copy) and (JS(ScriptSection(Copy,'body'),'text')=JS(ScriptSection(P,'body'),'text')),'copy has a new ID and retains overview'); finally Copy.Free; end;
    Check((ScriptNextStage('text',P.ScriptWizard)='summary-edit') and
      (ScriptNextStage('summary-edit',P.ScriptWizard)='script-confirm'),'ranking skips global introduction and closing settings');
    PsdJson.Put(TJSONObject(JA(JO(JO(Manga.ScriptWizard,'summaryData'),'draft'),'items')[0]),'value','4.5');
    var Before := Manga.ScriptWizard.ToJSON; PrepareScriptSummary(Manga);
    Check(Manga.ScriptWizard.ToJSON=Before,'preexisting manga scores are unchanged');
  finally P.Free; Manga.Free; end;
end;
begin
  try Run; Writeln('CHECKS=',Checks);
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
