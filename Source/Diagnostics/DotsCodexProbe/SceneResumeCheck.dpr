program SceneResumeCheck;
{$APPTYPE CONSOLE}
// 完成済み実台本は読取専用。所有コピーで第16段階の再開・画像保護・動画編集への遷移を検証する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, RigmMovieModel, RigmMovieComposition, RigmMovieChart,
  RigmScriptSummaryModel, RigmScriptScenesModel, RigmScriptThumbnailModel,
  RigmScriptNavigationModel, RigmWizardWorkspace, PsdJson, RigmJson;
var Checks: TJSONArray; Output,Error: string;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); Writeln('PASS ',Message); end;
procedure Run;
begin
  var Source := ParamStr(1); Output := ParamStr(2); ForceDirectories(Output);
  var Hash := THashSHA2.GetHashStringFromFile(Source); var P := LoadMovie(Source);
  try
    var Summary := P.Scene(ScriptSummaryCue(P).Scene);
    Check(Summary.ImageApproved and (Summary.ImageApprovalKey<>ScriptSceneFingerprint(P,Summary.Id)),
      'reproduction has a checked chart with an old source-cue approval key');
    var Before := P.Json;
    try
      Check(ScriptSceneReady(P,Summary,True),'valid generated chart is ready without an external image');
      Check(ScriptScenesReady(P,True),'all existing images and final thumbnail complete stage 16');
      RequireScriptThumbnail(P); Check(True,'final thumbnail card still passes its existing content checks');
      var After := P.Json;
      try Check(Before.ToJSON=After.ToJSON,'readiness check does not modify human approval or project data'); finally After.Free; end;
    finally Before.Free; end;
    var Copy := P.Clone;
    try
      var Chart := Copy.Scene(Summary.Id); Chart.ImageApproved := False; Chart.ImageApprovalKey := '';
      Check(ScriptScenesReady(Copy,True),'generated chart needs no image confirmation checkbox');
      var Maximum := JN(Chart.Chart,'maximum'); PsdJson.Put(Chart.Chart,'maximum',TJSONNumber.Create(0));
      Check(not ScriptSceneReady(Copy,Chart,True),'invalid generated chart still blocks readiness');
      PsdJson.Put(Chart.Chart,'maximum',TJSONNumber.Create(Maximum));
      var Picture: TRigmMovieScene := nil;
      for var S in Copy.Scenes do if SceneNeedsImage(S) then begin Picture := S; Break; end;
      Check(Picture<>nil,'fixture has an external scene image');
      var Image := Picture.Image; Picture.Image := '';
      Check(not ScriptScenesReady(Copy,True),'missing scene image still blocks stage 16'); Picture.Image := Image;
      Picture.ImageApproved := False;
      Check(not ScriptScenesReady(Copy,True),'unconfirmed scene image still blocks stage 16'); Picture.ImageApproved := True;
      var Key := Picture.ImageApprovalKey; Picture.ImageApprovalKey := 'stale';
      Check(not ScriptScenesReady(Copy,True),'changed external image source still requires confirmation'); Picture.ImageApprovalKey := Key;
      Copy.Thumbnail.ImageApproved := False;
      Check(not ScriptScenesReady(Copy,True),'unconfirmed final thumbnail still blocks stage 16');
      Copy.Thumbnail.Chart.Free; Copy.Thumbnail.Chart := Chart.Chart.Clone as TJSONObject;
      Check(not ScriptSceneReady(Copy,Copy.Thumbnail,True),'chart metadata cannot bypass mandatory thumbnail confirmation');
      Copy.Thumbnail.ImageApproved := True;
      Copy.Thumbnail.ImageApprovalKey := 'stale';
      Check(not ScriptScenesReady(Copy,True),'changed thumbnail sources still block stage 16');
    finally Copy.Free; end;
    var Data := TPath.Combine(Output,'Data'); var OriginalRoot := ExtractFileDir(ExtractFileDir(ExtractFileDir(Source)));
    for var V in JA(P.ScriptWizard,'selectedCharacters') do begin
      var Relative := JS(TJSONObject(V),'path'); var Target := TPath.Combine(Data,Relative);
      ForceDirectories(ExtractFileDir(Target)); TFile.Copy(TPath.Combine(OriginalRoot,Relative),Target,False);
    end;
    var Owned := TPath.Combine(Data,'Projects\'+P.Id+'\project.rigmovie');
    SaveMovie(P,Owned); // コピー先へ素材を移す。ここからは所有データだけを操作する。
    P.Thumbnail.ImageApprovalKey := ScriptSceneFingerprint(P,RigmThumbnailId);
    MaterializeScriptThumbnail(P); SaveMovie(P,Owned);
    var W := TRigmWizardWorkspace.Create(nil);
    try
      W.StartPipe(Data); W.OpenScriptDraft(Owned);
      var State := W.ScriptStatus;
      try
        Check((JS(JO(State,'wizard'),'stage')='scenes') and JB(State,'canAdvance') and JB(State,'scenesReady'),
          'reopened stage 16 reports ready and can advance');
        Check(ScriptStageAvailable(State,'editor'),'left stage list offers the movie editor');
      finally State.Free; end;
      W.FinishScriptToEditor;
      Check((W.ScriptDraft=nil) and (JS(W.ActiveSession.Project.ScriptWizard,'stage')='editor'),
        'normal workspace transition opens the editor');
      var Reloaded := LoadMovie(Owned);
      try Check(JS(Reloaded.ScriptWizard,'stage')='editor','editor destination survives saving and reloading'); finally Reloaded.Free; end;
    finally W.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Source)=Hash,'original user project SHA256 is unchanged');
  finally P.Free; end;
end;
begin
  Application.Initialize; Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
    if Output<>'' then begin
      var Report := TJSONObject.Create.AddPair('checks',Checks.Clone as TJSONArray).AddPair('error',Error);
      try TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end;
    end;
  finally Checks.Free; end;
end.
