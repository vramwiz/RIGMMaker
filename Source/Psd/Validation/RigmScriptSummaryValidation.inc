// 明示的な架空コピー。人間入力・実チャート・追加音声だけを確認。
procedure VerifyScriptSummary(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Summary check: '+Text); Results.Add(Text); end;
  procedure WaitVoice(W: TRigmWizardWorkspace);
  begin var Deadline := GetTickCount64+60000; repeat Application.ProcessMessages; var S := W.VoiceStatus; try if not JB(S,'busy') then begin Sleep(150); Application.ProcessMessages; Exit; end; finally S.Free; end; Sleep(5); until GetTickCount64>Deadline; raise Exception.Create('Owned summary voice timeout'); end;
  function PrimaryCues(P: TRigmMovieProject): string;
  begin var A := TJSONArray.Create; try for var V in JA(JO(P.ScriptWizard,'casting'),'rows') do A.AddElement(P.Cue(JS(TJSONObject(V),'cueId')).Json); Result := A.ToJSON; finally A.Free; end; end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptSummary.Validation.v1' then raise Exception.Create('Owned summary root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1360,900); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; W.OpenScriptDraft(Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8))); Main.NavigateTo(apScriptCreate); WaitThumbnailLibrary(W);
    var Creator := Main.PageInstance(apScriptCreate); var Tools := TToolBar(Creator.FindComponent('ScriptTitleToolbar')); var Next := TToolButton(Tools.FindComponent('ScriptNext'));
    var Before := PrimaryCues(W.ScriptDraft); var Cast := CastingFingerprint(W.ScriptDraft); var Source := ScriptFingerprint(W.ScriptDraft); var Placements := JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON;
    if Reopen then begin
      var Saved := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var Json := W.ScriptDraft.Json;
      try Check(Json.ToJSON=JS(Saved,'project'),'normal restart preserves exact saved project and assets',Results); finally Json.Free; Saved.Free; end;
      if W.CurrentScriptStage='voice' then begin
        var CueId := ScriptSummaryCue(W.ScriptDraft).Id; Check(not W.ScriptDraft.AudioReady(ScriptSummaryCue(W.ScriptDraft)),'summary interruption resumes only pending extra audio',Results);
        W.RefreshVoiceCatalog; WaitVoice(W); W.GenerateVoice(CueId,False); WaitVoice(W); Check(W.ScriptDraft.AudioReady(ScriptSummaryCue(W.ScriptDraft)),'real existing VOICEVOX produces selected summary WAV',Results);
        W.SetScriptStage('subtitles'); W.EditSubtitle(CueId,StringOfChar('A',2001),''); W.SaveScriptDraft(False); Check(Length(JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'subtitle'))=2001,'summary subtitle reuses 3000-character independent validation',Results);
        W.EditSubtitle(CueId,'総評字幕の個別修正',''); W.SetSubtitleBreak(CueId,3); W.MoveSubtitleBreak(CueId,1,3); W.SetScriptStage('voice'); Check((JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'subtitle')=ScriptSummaryCue(W.ScriptDraft).Subtitle) and W.ScriptDraft.AudioReady(ScriptSummaryCue(W.ScriptDraft)),'auxiliary subtitle editing and wrapping retain current audio and latest draft',Results);
        W.CompleteVoice; Next.Click; Check((W.CurrentScriptStage='closing') and not W.ScriptDraft.Modified,'summary voice Next saves closing destination first',Results);
        var ExtraId := ScriptSummaryCue(W.ScriptDraft).Id; var ExtraJson := ScriptSummaryCue(W.ScriptDraft).Json; var Wave := ResolveMoviePath(W.ScriptDraft.FileName,ScriptSummaryCue(W.ScriptDraft).WaveFile); var WaveHash := THashSHA2.GetHashStringFromFile(Wave);
        try
          TToolButton(Tools.FindComponent('ScriptSummaryStage')).Click; W.SetScriptSummaryChoice('none'); Next.Click;
          Check((W.ScriptDraft.Cues.Count=6) and (ScriptSummaryCue(W.ScriptDraft)=nil) and FileExists(Wave),'omitting summary removes only owned extra cue and retains draft/audio archive',Results);
          TToolButton(Tools.FindComponent('ScriptSummaryStage')).Click; W.SetScriptSummaryChoice('yes'); Next.Click; W.CompleteScriptSummary; Next.Click;
          Check(W.CurrentScriptStage='voice','confirmed current pipe/human draft reaches voice without rewriting displayed memo: '+TLabel(Creator.FindComponent('ScriptTitleStatus')).Caption,Results);
          var C := ScriptSummaryCue(W.ScriptDraft); var J := C.Json; try Check((C.Id=ExtraId) and (J.ToJSON=ExtraJson.ToJSON) and W.ScriptDraft.AudioReady(C) and (THashSHA2.GetHashStringFromFile(Wave)=WaveHash),'re-enabling unchanged summary restores same identifiers and ready real audio',Results); finally J.Free; end;
          W.CompleteVoice; Next.Click;
        finally ExtraJson.Free; end;
        CaptureUiWindow(Main,ResultPath,'.saved');
      end else begin Check((W.CurrentScriptStage='closing') and not Next.Visible,'closing restart remains concrete saved boundary',Results); CaptureUiWindow(Main,ResultPath,'.reopened'); end;
    end else begin
      Check((W.CurrentScriptStage='summary') and (W.ScriptDraft.Cues.Count=6),'owned scene fixture begins at summary with six ready cues',Results);
      W.SetScriptSummaryChoice('none'); Next.Click; Check((W.CurrentScriptStage='closing') and not W.ScriptDraft.Modified and (W.ScriptDraft.ScriptWizard.GetValue('summaryData')=nil),'no summary naturally skips without creating evaluation',Results);
      TToolButton(Tools.FindComponent('ScriptSummaryStage')).Click; W.SetScriptSummaryChoice('yes'); Next.Click; Check((W.CurrentScriptStage='summary-edit') and not W.ScriptDraft.Modified,'yes saves chart input destination before transition',Results);
      var Frame: TRigmScriptSummaryFrame := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptSummaryFrame then Frame := TRigmScriptSummaryFrame(Creator.Components[I]); Check((Frame<>nil) and Frame.Showing,'lazy summary input retains main form',Results);
      var D := JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'); Check((JS(D,'text')='') and (JI(D,'role')=0) and (JS(TJSONObject(JA(D,'items')[0]),'value')=''),'empty input contains no fabricated evaluation or actor',Results);
      var SummaryTools := TToolBar(Frame.FindComponent('ScriptSummaryToolbar')); TToolButton(SummaryTools.FindComponent('ScriptSummaryEdit')).Click;
      TMemo(Frame.FindComponent('ScriptSummaryText')).Text := '確認作品の総評です。'; TMemo(Frame.FindComponent('ScriptSummarySubtitle')).Text := '架空作品：字幕は独立'; TMemo(Frame.FindComponent('ScriptSummaryReading')).Text := 'かくにんさくひんのそうひょうです。';
      var Role := TComboBox(Frame.FindComponent('ScriptSummaryRole')); Role.ItemIndex := 0; Role.OnChange(Role);
      var Grid := TStringGrid(Frame.FindComponent('ScriptSummaryAxes')); Grid.Cells[0,1] := '確認A'; Grid.Cells[1,1] := '-'; Grid.Cells[0,2] := '確認B'; Grid.Cells[1,2] := '3'; Grid.Cells[0,3] := '確認C'; Grid.Cells[1,3] := '4'; Grid.OnSetEditText(Grid,1,1,'-');
      Check(W.ScriptTextEditing,'human summary input owns shared edit lock',Results); CaptureUiWindow(Main,ResultPath,'.editing'); TToolButton(SummaryTools.FindComponent('ScriptSummaryDone')).Click; TToolButton(Tools.FindComponent('ScriptSave')).Click;
      var Disk := LoadMovie(W.ScriptDraft.FileName); try Check(JS(TJSONObject(JA(JO(JO(Disk.ScriptWizard,'summaryData'),'draft'),'items')[0]),'value')='-','incomplete numeric text is safely saved without invented number',Results); finally Disk.Free; end;
      var Rejected := False; try W.CompleteScriptSummary; except on E: Exception do Rejected := True; end; Check(Rejected,'invalid numeric draft blocks confirmation and advancement',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe'); Check(JS(JO(JO(W.ScriptDraft.ScriptWizard,'summaryData'),'draft'),'text')='架空の確認作品だけの総評です。','real pipe applies explicit human fixture draft',Results);
      CaptureUiWindow(Main,ResultPath,'.chart'); TToolButton(SummaryTools.FindComponent('ScriptSummaryReady')).Click; Check(Next.Enabled,'valid human text and values enable Next after confirmation',Results); Next.Click;
      Check((W.CurrentScriptStage='voice') and not W.ScriptDraft.Modified and (W.ScriptDraft.Cues.Count=7) and (W.ScriptDraft.Scenes.Count=7),'summary Next saves one owned extra scene/cue and voice destination',Results);
      var C := ScriptSummaryCue(W.ScriptDraft); var S := W.ScriptDraft.Scene(C.Scene); Check((C.Text<>C.Subtitle) and (C.VoiceReading<>C.Text) and (ScriptCueRole(W.ScriptDraft,C.Id)=1),'summary speech subtitle reading and actor remain independently mapped',Results);
      Check(W.ScriptDraft.Scenes.IndexOf(S)<W.ScriptDraft.Scenes.IndexOf(W.ScriptDraft.Scene(W.ScriptDraft.Cues[5].Scene)),'summary scene sits before original closing for ripple timing',Results);
      var Copy := W.ScriptDraft.Clone; try Copy.EnableComposition; var Bitmap := RenderComposition(Copy,ScriptSceneStart(Copy,S.Id)+0.02,nil); try Bitmap.SaveToFile(ResultPath+'.composition.bmp'); Check(Bitmap.Width=1920,'common compositor renders actual summary chart at saved scene time',Results); finally Bitmap.Free; end; finally Copy.Free; end;
      CaptureUiWindow(Main,ResultPath,'.voice');
    end;
    Check((Before=PrimaryCues(W.ScriptDraft)) and (Cast=CastingFingerprint(W.ScriptDraft)) and (Source=ScriptFingerprint(W.ScriptDraft)) and (Placements=JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON),'primary cues audio subtitle cast source and placements remain identical',Results);
    if ScriptSummaryCue(W.ScriptDraft)<>nil then begin var Copy := W.ScriptDraft.Clone; try DisableScriptSummary(Copy); PrepareScriptCasting(Copy); ValidateScriptSummary(Copy); Check((Copy.Cues.Count=6) and (JO(Copy.ScriptWizard,'summaryData').GetValue('archivedCue') is TJSONObject),'recasting preparation preserves auxiliary human draft and audio archive',Results); finally Copy.Free; end; end;
    for var V in JA(JO(W.ScriptDraft.ScriptWizard,'casting'),'rows') do Check(W.ScriptDraft.AudioReady(W.ScriptDraft.Cue(JS(TJSONObject(V),'cueId'))),'existing cue real audio retained '+JS(TJSONObject(V),'cueId'),Results);
    Check(W.RequestFinish,'owned application exits after normal save',Results); var Resume := TJSONObject.Create; var Json := W.ScriptDraft.Json;
    try Resume.AddPair('project',Json.ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Json.Free; Resume.Free; end;
    var Target := ResultPath; if Reopen then Target := ResultPath+'.'+W.CurrentScriptStage+'.json'; TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
