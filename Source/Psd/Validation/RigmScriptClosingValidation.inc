// 架空確認作品だけで締め途中保存・画像採用・既存動画編集への引き渡しを検証。
type TEndingDialogAnswer = class(TReturnDialogAnswer)
  Path: string;
  Main: TRigmWizardMainForm;
  procedure TickEnding(Sender: TObject);
end;
procedure TEndingDialogAnswer.TickEnding(Sender: TObject);
begin
  for var I := 0 to Screen.FormCount-1 do if (Screen.Forms[I] is TRigmMovieEndingDialog) and (fsModal in Screen.Forms[I].FormState) then begin
    var D := Screen.Forms[I]; Seen := True; TTimer(Sender).Enabled := False;
    ShowWindow(D.Handle,SW_SHOWNOACTIVATE); D.Update; CaptureUiWindow(Main,Path,'.dialog'); D.ModalResult := mrCancel; Exit;
  end;
end;
procedure VerifyScriptClosing(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Closing check: '+Text); Results.Add(Text); end;
  function Core(P: TRigmMovieProject): string;
  begin var O := TJSONObject.Create; try var Cues := TJSONArray.Create; O.AddPair('cues',Cues); for var C in P.Cues do Cues.AddElement(C.Json); var Speakers := TJSONArray.Create; O.AddPair('speakers',Speakers); for var S in P.Speakers do Speakers.AddElement(S.Json); O.AddPair('source',ScriptFingerprint(P)); O.AddPair('casting',CastingFingerprint(P)); O.AddPair('placements',JA(P.ScriptWizard,'placements').Clone as TJSONArray); Result := O.ToJSON; finally O.Free; end; end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptClosing.Validation.v1' then raise Exception.Create('Owned closing root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1360,900); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; var Path := Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8)); W.OpenWork(W.Pipe.Workspace.Resolve(Path));
    if W.ScriptDraft<>nil then begin
      var Creator := Main.PageInstance(apScriptCreate); var Tools := TToolBar(Creator.FindComponent('ScriptTitleToolbar')); var Next := TToolButton(Tools.FindComponent('ScriptNext'));
      var Frame: TRigmScriptClosingFrame := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptClosingFrame then Frame := TRigmScriptClosingFrame(Creator.Components[I]);
      Check((Frame<>nil) and Frame.Showing and (W.CurrentScriptStage='closing'),'lazy closing frame shows saved destination in one main form',Results);
      var Before := Core(W.ScriptDraft); var BeforePlacements := JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON; var SceneData := W.ScriptDraft.Scenes[0].Json; var Summary := JO(W.ScriptDraft.ScriptWizard,'summaryData').ToJSON;
      try
        var ClosingTools := TToolBar(Frame.FindComponent('ScriptClosingToolbar'));
        if not Reopen then begin
          Check((W.ScriptDraft.EndCards.Count=0) and (JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'endChoice')=''),'missing images have no fabricated adoption/completion',Results);
          TEdit(Frame.FindComponent('ScriptClosingEndSeconds')).Text := '-'; Check(W.ScriptTextEditing,'human ending edit locks common pipe',Results); CaptureUiWindow(Main,ResultPath,'.editing');
          TToolButton(ClosingTools.FindComponent('ScriptClosingDone')).Click; TToolButton(Tools.FindComponent('ScriptSave')).Click;
          var Rejected := False; try W.CompleteScriptClosing; except on E: Exception do Rejected := True; end; Check(Rejected and not Next.Enabled,'unselected images cannot confirm or advance',Results);
          var J := W.ScriptDraft.Json; try var Saved := TJSONObject.Create; Saved.AddPair('project',J.ToJSON); Saved.AddPair('core',Before); TFile.WriteAllText(ResultPath+'.resume.json',Saved.ToJSON,TEncoding.UTF8); Saved.Free; finally J.Free; end;
        end else begin
          var Saved := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var J := W.ScriptDraft.Json;
          try Check((J.ToJSON=JS(Saved,'project')) and (JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'endSeconds')='-'),'normal closing restart retains incomplete numeric draft exactly',Results); finally J.Free; Saved.Free; end;
          CaptureUiWindow(Main,ResultPath,'.pipe');
          Check((JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'endChoice')='use') and (JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'thumbnailChoice')='use'),'real pipe adopts only existing fixture images',Results);
          var Mode := TComboBox(Frame.FindComponent('ScriptClosingPreviewMode')); Mode.ItemIndex := 1; Mode.OnChange(Mode); CaptureUiWindow(Main,ResultPath,'.adopt');
          TToolButton(ClosingTools.FindComponent('ScriptClosingReady')).Click; Check(Next.Enabled,'valid image choices geometry and existing ready audio confirm Next',Results);
          var Alternate := W.ScriptDraft.Clone;
          try var D2 := JO(JO(Alternate.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
            try for var Key in ['representativeChoice','endChoice','thumbnailChoice'] do PsdJson.Put(D2,Key,'none'); RigmScriptClosingModel.SetScriptClosingDraft(Alternate,D2); MaterializeScriptClosing(Alternate); finally D2.Free; end;
            Check((Alternate.EndCards.Count=0) and (Alternate.Duration=Alternate.StoryDuration) and (Core(Alternate)=Before),'explicit omission creates no silent card and preserves adopted source assets',Results);
            var ExtraScene := TRigmMovieScene.Create; Alternate.Scenes.Add(ExtraScene); var ExtraCue := TRigmMovieCue.Create; ExtraCue.Scene := ExtraScene.Id; ExtraCue.SpeakerId := Alternate.Cues[0].SpeakerId; ExtraCue.Text := '架空作品だけの追加締め確認'; Alternate.Cues.Add(ExtraCue);
            var Row := TJSONObject.Create; Row.AddPair('cueId',ExtraCue.Id); Row.AddPair('section','closing'); JA(JO(Alternate.ScriptWizard,'casting'),'rows').AddElement(Row); MaterializeScriptClosing(Alternate);
            Check(ExtraScene.Animation.GetValue('closingCard') is TJSONObject,'multiple closing lines retain common human title and representative setting',Results);
          finally Alternate.Free; end;
          Check((W.ScriptDraft.EndCards.Count=2) and (Abs(W.ScriptDraft.Duration-W.ScriptDraft.StoryDuration-7)<0.001),'ordered end and thumbnail add seven seconds without fake scene/cue',Results);
          Check((Core(W.ScriptDraft)=Before) and (W.ScriptDraft.Scenes[0].Json.ToJSON=SceneData.ToJSON) and (JO(W.ScriptDraft.ScriptWizard,'summaryData').ToJSON=Summary),'closing retains dialogue subtitles reading real audio bindings placement scene description and summary',Results);
          Next.Click; Check((W.ScriptDraft=nil) and (JS(W.ActiveSession.Project.ScriptWizard,'stage')='editor') and not W.ActiveSession.Project.Modified,'Next saves destination before handing ownership to existing editor',Results);
          var P := W.ActiveSession.Project; Check((P.Characters.Count=2) and (P.Cues.Count=7) and (P.Scenes.Count=7) and (Core(P)=Before),'same project transfers two actors and all seven confirmed scenes/cues',Results);
          var Editor := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)).CurrentEditor; var EndingAction := False;
          if Editor<>nil then for var I := 0 to Editor.ComponentCount-1 do if (Editor.Components[I] is TToolBar) and (Editor.Components[I].FindComponent('MovieEndingEdit')<>nil) then EndingAction := True;
          Check((Editor<>nil) and (Editor.Session=W.ActiveSession) and EndingAction,'existing MovieEditorFrame exposes common ending re-edit action',Results);
          var Probe := TEndingDialogAnswer.Create; var Timer := TTimer.Create(nil); var EditorBefore := P.Json;
          try Probe.Main := Main; Probe.Path := ResultPath; Timer.Interval := 500; Timer.OnTimer := Probe.TickEnding; Timer.Enabled := True;
            TToolButton(TToolBar(Editor.FindComponent('MovieToolbar')).FindComponent('MovieEndingEdit')).Click;
            var After := W.ActiveSession.Project.Json; try Check(Probe.Seen and (After.ToJSON=EditorBefore.ToJSON),'real ending dialog opens and cancel preserves all current editor input',Results); finally After.Free; end;
          finally EditorBefore.Free; Timer.Free; Probe.Free; end;
          var PreviewArgs := TJSONObject.Create; AddN(PreviewArgs,'time',ScriptSceneStart(P,ScriptClosingScene(P))+0.02); var PreviewReply := W.ActiveSession.Execute('preview',PreviewArgs); PreviewReply.Free; PreviewArgs.Free;
          var PreviewDeadline := GetTickCount64+15000;
          repeat Application.ProcessMessages; W.ActiveSession.Poll; Sleep(10); if GetTickCount64>PreviewDeadline then raise Exception.Create('Owned editor preview timeout'); until not W.ActiveSession.Busy and not Editor.PreviewControl.Frame.Empty;
          Check(Editor.PreviewControl.Frame.Width=1920,'existing editor generates real composed closing preview with handed-off actors',Results);
          var Timeline := W.ActiveSession.Execute('timeline',nil); try Check(JA(Timeline,'endCards').Count=2,'real editor timeline exposes separate silent ending cards',Results); finally Timeline.Free; end;
          var Audio := MixMovieAudio(P); try var Silent := True; for var I := Ceil(P.StoryDuration*Audio.Rate)+1 to High(Audio.Samples) do if Audio.Samples[I]<>0 then Silent := False; Check(Silent and (Abs(Audio.Duration-P.Duration)<0.01),'real PCM mix includes silent ending duration',Results); finally Audio.Free; end;
          var B := RenderComposition(P,P.StoryDuration+0.1,nil); try B.SaveToFile(ResultPath+'.end.bmp'); Check(B.Canvas.Pixels[1800,950]=TColor(P.BackgroundColor),'end card omits actors and speech on reserved side',Results); finally B.Free; end;
          var A := TJSONObject.Create; A.AddPair('projectId',P.Id); AddN(A,'revision',W.ActiveSession.Project.Revision); var D := JO(JO(W.ActiveSession.Project.ScriptWizard,'closingData'),'draft').Clone as TJSONObject; PsdJson.Put(D,'title','動画編集で修正した架空作品'); A.AddPair('draft',D); var R := W.ActiveSession.Execute('update-ending',A); R.Free; A.Free;
          Check(JS(JO(W.ActiveSession.Project.Scene(ScriptClosingScene(W.ActiveSession.Project)).Animation,'closingCard'),'title')='動画編集で修正した架空作品','common editor ending command revises human title without recasting or audio changes',Results);
          A := TJSONObject.Create; A.AddPair('projectId',P.Id); AddN(A,'revision',W.ActiveSession.Project.Revision); A.AddPair('id',W.ActiveSession.Project.Characters[0].Id); AddN(A,'x',W.ActiveSession.Project.Characters[0].X+8); R := W.ActiveSession.Execute('update-character',A); R.Free; A.Free;
          Check(JA(W.ActiveSession.Project.ScriptWizard,'placements').ToJSON<>BeforePlacements,'existing editor changes original shared placement data',Results);
          A := TJSONObject.Create; A.AddPair('projectId',W.ActiveSession.Project.Id); AddN(A,'revision',W.ActiveSession.Project.Revision); A.AddPair('path',W.ActiveSession.Project.FileName); R := W.ActiveSession.Execute('save',A); R.Free; A.Free;
          var J2 := W.ActiveSession.Project.Json; TFile.WriteAllText(ResultPath+'.editor-resume.json',J2.ToJSON,TEncoding.UTF8); J2.Free; CaptureUiWindow(Main,ResultPath,'.editor'); Editor.SetActive(False);
        end;
      finally SceneData.Free; end;
    end else begin
      var P := W.ActiveSession.Project; var J := P.Json; var Saved := ParseObject(TFile.ReadAllText(ResultPath+'.editor-resume.json',TEncoding.UTF8));
      try Check((J.ToJSON=Saved.ToJSON) and (JS(P.ScriptWizard,'stage')='editor'),'normal saved work restart opens exact edited project in MovieEditor',Results); finally J.Free; Saved.Free; end;
      var Editor := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)).CurrentEditor; Check((Editor<>nil) and (P.EndCards.Count=2) and (P.Cues.Count=7),'editor restart retains cards actors independent cue data and ready audio',Results);
      for var C in P.Cues do Check(P.AudioReady(C),'restart preserves current real WAV '+C.Id,Results);
      var Listing := W.ScriptLibrary; try Check(JS(TJSONObject(JA(Listing,'scripts')[0]),'kind')='wizard','edited completed work remains readable in script library',Results); finally Listing.Free; end;
      CaptureUiWindow(Main,ResultPath,'.reopen'); Editor.SetActive(False);
    end;
    var Deadline := GetTickCount64+15000; while not W.RequestFinish do begin Application.ProcessMessages; Sleep(10); if GetTickCount64>Deadline then raise Exception.Create('Owned ending job shutdown timeout'); end;
    Report.AddPair('passed',TJSONBool.Create(True)); TFile.WriteAllText(ResultPath+'.phase'+IfThen(Reopen,'reopen','initial')+'.json',Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
