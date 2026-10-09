// Codex著の架空作品のみ。親AIが本文を読んだ提案を正式パイプで受信し、許可されたGUI採用を検証する。
procedure VerifyScriptSemantic(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Semantic check: '+Text); Results.Add(Text); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptSemantic.Validation.v1' then raise Exception.Create('Owned semantic root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; W.OpenScriptDraft(Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8))); Main.NavigateTo(apScriptCreate);
    Check(W.ScriptDraft.Title='Codex実往復用：架空の星空観測所','explicit Codex fictional fixture only',Results);
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TComponent(Creator); var Next := TRigmScriptStageProbe.CreateForFrame(Toolbar,W);
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var Json := W.ScriptDraft.Json;
      try Check(W.CurrentScriptStage='subtitles','restart resumes subtitle destination',Results);
        Check(Json.ToJSON=JS(Resume,'project'),'adopted correction confirmed AI roles and subtitles survive restart',Results);
      finally Json.Free; Resume.Free; end;
      CaptureUiWindow(Main,ResultPath,'.reopened');
    end else begin
      Check(W.CurrentScriptStage='review','copied review fixture opens at saved stage',Results);
      var Body := JS(ScriptSection(W.ScriptDraft,'body'),'text'); var Opening := JS(ScriptSection(W.ScriptDraft,'opening'),'text'); var Closing := JS(ScriptSection(W.ScriptDraft,'closing'),'text');
      Check(Body.Substring(7,2)='明り','exact original UTF16 anchor verified',Results);
      CaptureUiWindow(Main,ResultPath,'.review-proposal');
      var Items := JA(JO(W.ScriptDraft.ScriptWizard,'review'),'items');
      Check((Items.Count=1) and (JS(TJSONObject(Items[0]),'decision')='pending') and (JS(ScriptSection(W.ScriptDraft,'body'),'text')=Body),'real pipe proposal remains pending without replacing original',Results);
      var Frame: TRigmScriptReviewFrame := nil;
      for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptReviewFrame then Frame := TRigmScriptReviewFrame(Creator.Components[I]);
      Check((Frame<>nil) and Frame.Showing,'main form review frame receives actual external proposal',Results);
      TToolButton(TToolBar(Frame.FindComponent('ScriptReviewToolbar')).FindComponent('ScriptReviewAI')).Click;
      Check((JS(TJSONObject(Items[0]),'decision')='ai') and (JS(ScriptSection(W.ScriptDraft,'body'),'text')=Body.Substring(0,7)+'明かり'+Body.Substring(9)),'authorized GUI AI adoption changes only requested spelling',Results);
      Check((JS(ScriptSection(W.ScriptDraft,'opening'),'text')=Opening) and (JS(ScriptSection(W.ScriptDraft,'closing'),'text')=Closing),'other sections unchanged after adoption',Results);
      CaptureUiWindow(Main,ResultPath,'.review-adopted'); WaitThumbnailLibrary(W); Next.Click;
      Check((W.CurrentScriptStage='casting') and not W.ScriptDraft.Modified and (W.ScriptDraft.Cues.Count=6),'Next saves six paragraph cues and casting destination before navigation: '+W.CurrentScriptStage+' / '+W.ScriptDraft.Cues.Count.ToString+' / edit '+BoolToStr(W.ScriptTextEditing,True),Results);
      CaptureUiWindow(Main,ResultPath,'.casting-proposal');
      var Cast: TRigmScriptCastingFrame := nil;
      for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptCastingFrame then Cast := TRigmScriptCastingFrame(Creator.Components[I]);
      var List := TListView(Cast.FindComponent('ScriptCastingRows')); W.SelectCasting(W.ScriptDraft.Cues[0].Id);
      for var I := 0 to W.ScriptDraft.Cues.Count-1 do begin
        var Row := CastingRow(W.ScriptDraft,W.ScriptDraft.Cues[I].Id);
        Check((JS(Row,'origin')='ai') and not JB(Row,'confirmed'),'semantic AI suggestion still needs GUI acceptance '+I.ToString,Results);
        List.SetFocus; List.Perform(WM_KEYDOWN,VK_RETURN,0); Application.ProcessMessages;
        Check(JB(Row,'confirmed') and (JS(Row,'origin')='ai'),'Enter accepts received AI role '+I.ToString,Results);
      end;
      Check(JS(W.ScriptDraft.ScriptWizard,'castingStatus')='complete','six explicit GUI confirmations complete casting',Results);
      CaptureUiWindow(Main,ResultPath,'.casting-adopted'); Next.Click;
      Check((W.CurrentScriptStage='subtitles') and not W.ScriptDraft.Modified,'Next saves subtitle destination before navigation',Results);
      for var C in W.ScriptDraft.Cues do Check(C.Subtitle=C.Text,'initial display text remains independent copy of voice text '+C.Id,Results);
      CaptureUiWindow(Main,ResultPath,'.subtitles'); W.SaveScriptDraft(False);
      var Resume := TJSONObject.Create; var Saved := W.ScriptDraft.Json;
      try Resume.AddPair('projectId',W.ScriptDraft.Id); Resume.AddPair('project',Saved.ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; Saved.Free; end;
    end;
    Check(W.RequestFinish,'owned application closes normally',Results);
    var Target := ResultPath; if Reopen then Target := ResultPath+'.reopened.json'; TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
