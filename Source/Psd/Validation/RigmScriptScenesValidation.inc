// 明示的な架空コピーだけを操作。実音声と実PNG転送、GUI、保存再開の狭い確認。
procedure VerifyScriptScenes(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Scenes check: '+Text); Results.Add(Text); end;
  procedure WaitVoice(W: TRigmWizardWorkspace);
  begin var Deadline := GetTickCount64+60000; repeat Application.ProcessMessages; var S := W.VoiceStatus; try if not JB(S,'busy') then begin Sleep(150); Application.ProcessMessages; Exit; end; finally S.Free; end; Sleep(5); until GetTickCount64>Deadline; raise Exception.Create('Owned voice timeout'); end;
  procedure WaitPreview(W: TRigmWizardWorkspace);
  begin var Deadline := GetTickCount64+20000; repeat Application.ProcessMessages; if W.ScenePreview<>nil then Exit; Sleep(5); until GetTickCount64>Deadline; var S := W.ScriptScenePreviewStatus; try raise Exception.Create('Owned preview timeout '+S.ToJSON); finally S.Free; end; end;
  function CuesJson(P: TRigmMovieProject): string;
  begin var A := TJSONArray.Create; try for var C in P.Cues do A.AddElement(C.Json); Result := A.ToJSON; finally A.Free; end; end;
  function CharactersJson(P: TRigmMovieProject): string;
  begin var A := TJSONArray.Create; try for var C in P.Characters do A.AddElement(C.Json); Result := A.ToJSON; finally A.Free; end; end;
  function SpeakersJson(P: TRigmMovieProject): string;
  begin var A := TJSONArray.Create; try for var S in P.Speakers do A.AddElement(S.Json); Result := A.ToJSON; finally A.Free; end; end;
  function RegionHash(B: Vcl.Graphics.TBitmap; R: TRect): string;
  begin var H := THashSHA2.Create; var Y := R.Top; while Y<R.Bottom do begin var X := R.Left; while X<R.Right do begin var V := ColorToRGB(B.Canvas.Pixels[X,Y]); H.Update(V.ToString); Inc(X,8); end; Inc(Y,8); end; Result := H.HashAsString; end;
  procedure RenderChecks(P: TRigmMovieProject; Results: TJSONArray);
  begin
    var Copy := P.Clone;
    try
      for var C in Copy.Characters do C.Visible := False;
      for var C in Copy.Cues do C.Subtitle := '';
      var First := Copy.Scenes[0]; var Second := Copy.Scenes[1];
      Copy.Cues[1].Scene := First.Id; Copy.Scenes.Remove(Second); First.Padding := 0.3;
      Check(Copy.SceneDuration(First)>Copy.Cues[0].AudioSeconds+0.2,'scene duration contains multiple cues and tail',Results);
      for var Choice in ['theme','l-left','l-right'] do begin
        DecodeLayoutChoice(Choice,Copy.Layout,Copy.LDirection); First.DisplayMode := 'both';
        var Regions := MovieLayoutRegions(Copy.Layout,Copy.LDirection); var ImageR := ScaleLayoutRect(Regions.Image,Copy.Width,Copy.Height); var TextR := ScaleLayoutRect(Regions.Description,Copy.Width,Copy.Height);
        var Early := RenderComposition(Copy,0.05,nil); var Late := RenderComposition(Copy,Copy.SceneDuration(First)-0.01,nil);
        try
          Check((RegionHash(Early,ImageR)=RegionHash(Late,ImageR)) and (RegionHash(Early,TextR)=RegionHash(Late,TextR)),'image and description remain for whole multi-cue scene '+Choice,Results);
          Check(ColorToRGB(Early.Canvas.Pixels[ImageR.CenterPoint.X,ImageR.CenterPoint.Y])<>ColorToRGB(Early.Canvas.Pixels[ImageR.CenterPoint.X,ImageR.Top+2]),'wide image has vertical fit margin preserving aspect '+Choice,Results);
          First.DisplayMode := 'image'; var ImageOnly := RenderComposition(Copy,0.05,nil); First.DisplayMode := 'text'; var TextOnly := RenderComposition(Copy,0.05,nil); First.DisplayMode := 'none'; var None := RenderComposition(Copy,0.05,nil);
          try Check((RegionHash(ImageOnly,TextR)=RegionHash(None,TextR)) and (RegionHash(TextOnly,ImageR)=RegionHash(None,ImageR)) and (RegionHash(Early,ImageR)<>RegionHash(None,ImageR)) and (RegionHash(Early,TextR)<>RegionHash(None,TextR)),'image/text/none modes preserve independent regions '+Choice,Results);
          finally None.Free; TextOnly.Free; ImageOnly.Free; end;
        finally Late.Free; Early.Free; end;
      end;
    finally Copy.Free; end;
  end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptScenes.Validation.v1' then raise Exception.Create('Owned scenes root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1360,900); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    Check(SameText(RigmDocumentsDirectory,Main.DataRoot) and SameText(RigmSettingsDirectory,Main.DataRoot),'explicit data and settings overrides remain authoritative',Results);
    var Known: PWideChar := nil; OleCheck(SHGetKnownFolderPath(FOLDERID_Documents,0,0,Known));
    try var Expected := TPath.Combine(string(Known),'RIGMMaker'); if DirectoryExists('D:\Users\take6\RIGMMaker') then Expected := 'D:\Users\take6\RIGMMaker'; Check(SameText(RigmDefaultDocumentsDirectory,Expected),'existing legacy default is retained, absent default uses current KnownDocuments without creation',Results); finally CoTaskMemFree(Known); end;
    var W := Main.Workspace; W.OpenScriptDraft(Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8))); Main.NavigateTo(apScriptCreate);
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar')); var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var Json := W.ScriptDraft.Json;
      try Check((W.CurrentScriptStage='summary') and (Json.ToJSON=JS(Resume,'project')),'restart resumes saved summary destination with exact project',Results); finally Json.Free; Resume.Free; end;
      var Radio := TRadioGroup(Creator.FindComponent('ScriptSummaryChoice')); Check((Radio.ItemIndex=0) and not Next.Visible,'explicit summary omission survives restart without fabricated chart',Results);
      TToolButton(Toolbar.FindComponent('ScriptScenesStage')).Click;
    end else begin
      Check(W.CurrentScriptStage='voice','copied completed Stage9 fiction begins at voice',Results);
      W.RefreshVoiceCatalog; WaitVoice(W); W.BindVoice(2,108,'1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b');
      for var C in W.ScriptDraft.Cues do if not W.ScriptDraft.AudioReady(C) then begin W.GenerateVoice(C.Id,False); WaitVoice(W); Check(W.ScriptDraft.AudioReady(C),'real short cue synthesis '+C.Id,Results); end;
      WaitThumbnailLibrary(W); W.CompleteVoice; Next.Click; Check((W.CurrentScriptStage='scenes') and not W.ScriptDraft.Modified,'voice Next saves scenes destination before transition: '+TLabel(Creator.FindComponent('ScriptTitleStatus')).Caption,Results);
    end;
    var Frame: TRigmScriptScenesFrame := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptScenesFrame then Frame := TRigmScriptScenesFrame(Creator.Components[I]);
    Check((Frame<>nil) and Frame.Showing and Next.Visible,'lazy scene frame and Next share retained main form',Results);
    var List := TListView(Frame.FindComponent('ScriptSceneRows')); var Tools := TToolBar(Frame.FindComponent('ScriptScenesToolbar'));
    if Reopen then begin
      WaitPreview(W); Check((List.Items.Count=W.ScriptDraft.Scenes.Count) and (List.SmallImages.Count=List.Items.Count) and (W.ScenePreview<>nil),'saved material reloads real thumbnails and common preview',Results);
      for var C in W.ScriptDraft.Cues do Check(W.ScriptDraft.AudioReady(C),'scene restart preserves real ready WAV '+C.Id,Results);
      CaptureUiWindow(Main,ResultPath,'.reopened'); TToolButton(Toolbar.FindComponent('ScriptSummaryStage')).Click;
    end else begin
      var Before := CuesJson(W.ScriptDraft); var BeforeCharacters := CharactersJson(W.ScriptDraft); var Cast := CastingFingerprint(W.ScriptDraft); var Source := ScriptFingerprint(W.ScriptDraft);
      var BeforePlacements := JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON; var BeforeSpeakers := SpeakersJson(W.ScriptDraft); Check(JA(W.ScriptDraft.ScriptWizard,'placements').Count=2,'fiction contains two saved character placements',Results);
      var Id := W.ScriptDraft.Scenes[0].Id; TToolButton(Tools.FindComponent('ScriptSceneEdit')).Click;
      TMemo(Frame.FindComponent('ScriptSceneDescription')).Text := '確認用の色図。架空作品の説明文です。'; TMemo(Frame.FindComponent('ScriptScenePrompt')).Text := '確認PNG転送。意味的画像生成は行わない。';
      Check(W.ScriptTextEditing,'human scene text uses shared input lock',Results); CaptureUiWindow(Main,ResultPath,'.editing'); TToolButton(Tools.FindComponent('ScriptSceneDone')).Click;
      W.AdoptScriptSceneImage(Id,TPath.Combine(Main.DataRoot,'local-fixture.png')); var Local := W.ScriptDraft.Scene(Id).Image;
      Check(FileExists(Local) and (THashSHA2.GetHashStringFromFile(Local)=THashSHA2.GetHashStringFromFile(TPath.Combine(Main.DataRoot,'local-fixture.png'))),'local image is decoded and copied with original bytes',Results);
      TToolButton(Tools.FindComponent('ScriptSceneRequest')).Click; Check(JS(ScriptSceneRequest(W.ScriptDraft,Id),'state')='pending','external request remains pending without dummy generation',Results);
      TToolButton(Tools.FindComponent('ScriptSceneCancel')).Click; Check((JS(ScriptSceneRequest(W.ScriptDraft,Id),'state')='cancelled') and (W.ScriptDraft.Scene(Id).Image=Local),'request cancellation retains adopted local material',Results); TToolButton(Tools.FindComponent('ScriptSceneRequest')).Click;
      W.SaveScriptDraft(False); RequireSceneImageRequest(W.ScriptDraft,Id,JS(ScriptSceneRequest(W.ScriptDraft,Id),'requestId')); Check(True,'pending image request survives asset relocation during save',Results);
      CaptureUiWindow(Main,ResultPath,'.transfer');
      var R := ScriptSceneRequest(W.ScriptDraft,Id); Check((JS(R,'state')='adopted') and (JS(R,'imageProvenance')='test-fixture') and (W.ScriptDraft.Scene(Id).Image<>Local),'real pipe adopts explicitly labelled fixture image',Results);
      Check(W.ScriptDraft.Scene(Id).Description='パイプからの確認修正。架空作品です。','newer human description survives rejected stale delivery',Results);
      Check((CuesJson(W.ScriptDraft)=Before) and (CharactersJson(W.ScriptDraft)=BeforeCharacters) and (JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON=BeforePlacements) and (SpeakersJson(W.ScriptDraft)=BeforeSpeakers) and (CastingFingerprint(W.ScriptDraft)=Cast) and (ScriptFingerprint(W.ScriptDraft)=Source),'image delivery keeps voice subtitle cast raw source speaker UUID and actual placements identical',Results);
      WaitPreview(W); var PreviewState := W.ScriptScenePreviewStatus; try Check(JI(PreviewState,'characterCount')=2,'common preview derives two actors from saved placements without rewriting draft',Results); finally PreviewState.Free; end; CaptureUiWindow(Main,ResultPath,'.preview'); RenderChecks(W.ScriptDraft,Results);
      for var I := 1 to W.ScriptDraft.Scenes.Count-1 do begin W.SelectScriptScene(W.ScriptDraft.Scenes[I].Id); var Mode := TComboBox(Frame.FindComponent('ScriptSceneMode')); Mode.ItemIndex := 3; Mode.OnChange(Mode); end;
      W.SelectScriptScene(Id); TToolButton(Tools.FindComponent('ScriptSceneReady')).Click; Check(Next.Enabled,'explicit per-scene choices enable Next after confirmation',Results); Next.Click;
      Check((W.CurrentScriptStage='summary') and not W.ScriptDraft.Modified,'scene Next saves summary destination and all materials first',Results);
      var Radio := TRadioGroup(Creator.FindComponent('ScriptSummaryChoice')); Check(Radio.ItemIndex=-1,'summary starts without guessed choice',Results); Radio.ItemIndex := 0; Radio.OnClick(Radio); TToolButton(Toolbar.FindComponent('ScriptSave')).Click;
      CaptureUiWindow(Main,ResultPath,'.saved'); var Resume := TJSONObject.Create; var Json := W.ScriptDraft.Json;
      try Resume.AddPair('project',Json.ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Json.Free; Resume.Free; end;
    end;
    Check(W.RequestFinish,'owned application saves and closes normally',Results); var Target := ResultPath; if Reopen then Target := ResultPath+'.reopened.json'; TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
