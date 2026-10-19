program StageCompletionCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Diagnostics, System.Types,
  Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.StdCtrls,
  RigmScriptCreatorFrame,
  RigmWizardWorkspace, RigmScriptNavigationModel, RigmScriptTextModel,
  RigmScriptSummaryModel, RigmScriptClosingModel, RigmScriptCastingModel,
  RigmScriptReviewModel, RigmScriptScenesModel, RigmScriptThumbnailModel,
  RigmMovieModel, RigmMovieComposition, RigmMovieLayout, RigmJson, PsdJson;
var Root: string; Checks: Integer;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Inc(Checks); Writeln('PASS ',Message);
end;
function Offers(W: TRigmWizardWorkspace; const Stage: string): Boolean;
begin
  Result := False; var State := W.ScriptStatus;
  try for var Id in ScriptVisibleStages(State) do if Id=Stage then Exit(True);
  finally State.Free; end;
end;
procedure CheckStages;
  procedure ClickNext(W: TRigmWizardWorkspace; Frame: TRigmScriptCreatorFrame);
  begin
    var State := W.ScriptStatus;
    try
      var Ids := ScriptVisibleStages(State);
      var Next := ScriptNextStage(W.CurrentScriptStage,JO(State,'wizard'));
      var List := Frame.FindComponent('ScriptStages') as TListBox;
      for var I := 0 to High(Ids) do if Ids[I]=Next then begin
        List.ItemIndex := I; List.OnClick(List); Exit;
      end;
      raise Exception.Create('Next stage missing from sidebar');
    finally State.Free; end;
  end;
begin
  var W := TRigmWizardWorkspace.Create(nil);
  var Form := TForm.CreateNew(nil);
  try
    W.StartPipe(TPath.Combine(Root,'OwnedData')); W.NewScriptDraft;
    W.SetScriptTitle('工程移動の所有テスト'); var P := W.ScriptDraft;
    PrepareScriptText(P); PsdJson.Put(ScriptSection(P,'body'),'text','本題の原稿');
    PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'backgroundTone','dark');
    PsdJson.Put(P.ScriptWizard,'layoutStatus','complete'); P.BackgroundColor := LayoutBackgroundColor('dark');
    PsdJson.Put(P.ScriptWizard,'summaryChoice','yes'); PsdJson.Put(P.ScriptWizard,'furthestStage','closing');
    PrepareScriptSummary(P); PrepareScriptClosing(P); W.SetScriptStage('summary-edit');
    var Frame := TRigmScriptCreatorFrame.CreateForWorkspace(Form,W,TPath.Combine(Root,'OwnedData'));
    Frame.SetActive(True);
    Check(not Offers(W,'closing'),'empty summary cannot unlock closing');
    var D := JO(JO(P.ScriptWizard,'summaryData'),'draft').Clone as TJSONObject;
    try
      PsdJson.Put(D,'text','総評のセリフ');
      for var V in JA(D,'items') do PsdJson.Put(TJSONObject(V),'value','3');
      W.SetScriptSummaryDraft(D);
    finally D.Free; end;
    Check(JS(JO(P.ScriptWizard,'summaryData'),'status')='draft','editing keeps summary as draft');
    Check(Offers(W,'closing'),'valid summary offers closing without confirmation button');
    ClickNext(W,Frame);
    Check((W.CurrentScriptStage='closing') and not P.Modified,'list transition confirms and saves summary');
    var Saved := LoadMovie(P.FileName);
    try Check((JS(Saved.ScriptWizard,'stage')='closing') and
      (JS(JO(Saved.ScriptWizard,'summaryData'),'status')='complete'),'summary destination and confirmation persist together');
    finally Saved.Free; end;
    Check(not Offers(W,'script-confirm'),'undecided closing images cannot unlock script confirmation');
    D := JO(JO(P.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
    try
      PsdJson.Put(D,'representativeChoice','none'); PsdJson.Put(D,'endChoice','none');
      W.SetScriptClosingDraft(D);
    finally D.Free; end;
    Check(JS(JO(P.ScriptWizard,'closingData'),'status')='draft','editing keeps closing as draft');
    Check(Offers(W,'script-confirm'),'valid closing offers script confirmation without ready button');
    var Before := P.Json;
    try
      var Invalid := JO(JO(P.ScriptWizard,'closingData'),'draft');
      PsdJson.Put(Invalid,'endChoice','use'); PsdJson.Put(Invalid,'endImage',TPath.Combine(Root,'missing.png'));
      Check(not Offers(W,'script-confirm'),'missing selected image blocks navigation');
      var Rejected := False;
      try W.NextScriptDraft; except Rejected := True; end;
      Check(Rejected and (W.CurrentScriptStage='closing'),'invalid closing cannot change stage');
      PsdJson.Put(Invalid,'endChoice','none'); PsdJson.Put(Invalid,'endImage','');
      ClickNext(W,Frame);
      Check((W.CurrentScriptStage='script-confirm') and not P.Modified,'list transition materializes and saves closing');
      var After := P.Json;
      try Check(JA(Before,'cues').ToJSON=JA(After,'cues').ToJSON,'closing navigation preserves dialogue and voice data');
      finally After.Free; end;
    finally Before.Free; end;
    Saved := LoadMovie(P.FileName);
    try Check((JS(Saved.ScriptWizard,'stage')='script-confirm') and
      (JS(JO(Saved.ScriptWizard,'closingData'),'status')='complete'),'closing destination and confirmation persist together');
    finally Saved.Free; end;
  finally Form.Free; W.Free; end;
end;
procedure CheckImages;
begin
  var P := TRigmMovieProject.Create;
  try
    P.FileName := TPath.Combine(Root,'image-fixture.rigmovie');
    P.ScriptWizard := PsdJson.ObjectText('{"titleInput":"画像テスト","selectedCharacters":[],"casting":{"state":"ready","roles":[],"rows":[]}}');
    PrepareScriptText(P);
    var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
    try
      Bitmap.SetSize(1672,941); Bitmap.PixelFormat := pf24bit;
      for var Y := 0 to Bitmap.Height-1 do begin
        var Line := PByte(Bitmap.ScanLine[Y]);
        for var X := 0 to Bitmap.Width*3-1 do Line[X] := Byte((X xor (Y*71) xor (X shr 3)) and 255);
      end;
      Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,'seed.png'));
    finally Png.Free; Bitmap.Free; end;
    for var I := 1 to 10 do begin
      var S := TRigmMovieScene.Create; S.Title := 'Scene '+I.ToString;
      S.DisplayMode := 'image'; S.ImagePrompt := S.Title;
      S.Image := TPath.Combine(Root,'image-'+I.ToString+'.png');
      TFile.Copy(TPath.Combine(Root,'seed.png'),S.Image); P.Scenes.Add(S);
      for var J := 1 to 4 do begin
        var C := TRigmMovieCue.Create; C.Scene := S.Id; C.SpeakerId := P.Speakers[0].Id;
        P.Cues.Add(C);
      end;
    end;
    var Cast := JO(P.ScriptWizard,'casting');
    PsdJson.Put(Cast,'sourceFingerprint',ScriptFingerprint(P));
    PsdJson.Put(Cast,'fingerprint',CastingFingerprint(P));
    PrepareScriptScenes(P,False);
    for var S in P.Scenes do SetScriptSceneApproved(P,S.Id,True);
    P.Thumbnail.Image := TPath.Combine(Root,'seed.png');
    var Watch := TStopwatch.StartNew;
    for var I := 1 to 3 do begin
      SetScriptSceneApproved(P,RigmThumbnailId,True);
      var State := ScriptScenesSummary(P); State.Free;
      SetScriptSceneApproved(P,RigmThumbnailId,False);
    end;
    Watch.Stop; Writeln('THUMBNAIL_3_CYCLES_MS=',Watch.ElapsedMilliseconds);
    SetScriptSceneApproved(P,RigmThumbnailId,True);
    Check(ScriptScenesReady(P,True),'all approved images pass full validation');
    var Key := P.Scenes[0].ImageApprovalKey;
    var Other := TBitmap.Create; var OtherPng := TPngImage.Create;
    try
      Other.SetSize(64,64); Other.Canvas.Brush.Color := clRed; Other.Canvas.FillRect(Rect(0,0,64,64));
      OtherPng.Assign(Other); OtherPng.SaveToFile(P.Scenes[0].Image);
    finally OtherPng.Free; Other.Free; end;
    Check((P.Scenes[0].ImageApprovalKey=Key) and not ScriptSceneReady(P,P.Scenes[0]),'changed file invalidates cached approval');
    Check(not ScriptThumbnailSourcesReady(P),'changed source blocks thumbnail');
    var Rejected := False;
    SetScriptSceneApproved(P,RigmThumbnailId,False);
    try SetScriptSceneApproved(P,RigmThumbnailId,True); except Rejected := True; end;
    Check(Rejected,'thumbnail confirmation rejects changed source');
  finally P.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1);
  try
    if (Root='') or DirectoryExists(Root) then raise Exception.Create('New isolated output directory required');
    ForceDirectories(Root);
    if ParamStr(2)<>'benchmark' then CheckStages;
    CheckImages; Writeln('CHECKS=',Checks);
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
