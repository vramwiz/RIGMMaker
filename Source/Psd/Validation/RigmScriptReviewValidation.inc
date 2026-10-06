// 所有Temp作品だけで校正の採否・保存再開・競合を確認する。
procedure VerifyScriptReview(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Review check: '+Text); Results.Add(Text); end;
  function ReviewFrame(Creator: TFrame): TRigmScriptReviewFrame;
  begin
    Result := nil;
    for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptReviewFrame then Exit(TRigmScriptReviewFrame(Creator.Components[I]));
  end;
  procedure SelectItem(Frame: TRigmScriptReviewFrame; const Id: string);
  begin
    var List := TListView(Frame.FindComponent('ScriptReviewItems'));
    for var Item in List.Items do if Item.SubItems[1]=Id then begin Item.Selected := True; Item.Focused := True; Exit; end;
    raise Exception.Create('Review item absent: '+Id);
  end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptReview.Validation.v1' then raise Exception.Create('Owned review root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; Main.NavigateTo(apScripts);
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try
        W.OpenScriptDraft(JS(Resume,'path')); Main.NavigateTo(apScriptCreate);
        Check(W.CurrentScriptStage='review','restart resumes review',Results);
        Check(W.ScriptDraft.Id=JS(Resume,'projectId'),'same UID after restart',Results);
        Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=JS(Resume,'body'),'accepted text survives restart',Results);
        Check(JO(W.ScriptDraft.ScriptWizard,'review').ToJSON=JS(Resume,'review'),'decisions and edited draft survive restart',Results);
      finally Resume.Free; end;
    end else begin
      W.NewScriptDraft; Main.NavigateTo(apScriptCreate);
    end;
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar'));
    var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    if not Reopen then begin
      TEdit(Creator.FindComponent('ScriptTitle')).Text := '校正工程の分離した確認作品'; Next.Click;
      WaitThumbnailLibrary(W);
      var UiDeadline := GetTickCount64+5000; var ReadyCount: Integer;
      repeat
        Application.ProcessMessages; ReadyCount := 0;
        for var Item in TListView(Creator.FindComponent('ScriptCharacters')).Items do if JB(TJSONObject(Item.Data),'readyForScript') then Inc(ReadyCount);
        if ReadyCount>0 then Break; Sleep(5);
      until GetTickCount64>UiDeadline;
      for var Item in TListView(Creator.FindComponent('ScriptCharacters')).Items do if JB(TJSONObject(Item.Data),'readyForScript') then Item.Checked := True;
      Check(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count>=1,'existing completed asset copied into owned root',Results);
      Next.Click; Next.Click; Next.Click;
      var TextFrame: TRigmScriptTextFrame := nil;
      for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptTextFrame then TextFrame := TRigmScriptTextFrame(Creator.Components[I]);
      Check((TextFrame<>nil) and Next.Visible,'text now offers Next',Results);
      var Body := TMemo(TextFrame.FindComponent('ScriptText1')); Body.Text := '今日は晴れです。'+#13#10+'同じ語語があります。'+#13#10+'最後の行です。';
      TToolButton(TToolBar(TextFrame.FindComponent('ScriptTextToolbar')).FindComponent('ScriptTextReady')).Click;
      var Path := W.ScriptDraft.FileName; var Hash := THashSHA2.GetHashStringFromFile(Path);
      var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try
        Next.Click;
        Check((W.CurrentScriptStage='text') and W.ScriptDraft.Modified and (W.ScriptDraft.ScriptWizard.GetValue('review')=nil) and
          (THashSHA2.GetHashStringFromFile(Path)=Hash),'failed Next retains raw text and previous destination',Results);
      finally Guard.Free; end;
      Next.Click;
      Check((W.CurrentScriptStage='review') and not W.ScriptDraft.Modified,'Next saves before review navigation',Results);
      var Saved := LoadMovie(Path);
      try Check((JS(Saved.ScriptWizard,'stage')='review') and (JS(JO(Saved.ScriptWizard,'review'),'state')='requested'),'disk includes request and review destination',Results); finally Saved.Free; end;
      var Frame := ReviewFrame(Creator); Check((Frame<>nil) and Frame.Showing and not Next.Visible,'lazy review frame occupies main area',Results);
      CaptureUiWindow(Main,ResultPath,'.requested');
      Check((TMemo(Frame.FindComponent('ScriptReviewContext')).Width>500) and (TMemo(Frame.FindComponent('ScriptReviewContext')).Height>200),'wide context area '+TMemo(Frame.FindComponent('ScriptReviewContext')).Width.ToString+'x'+TMemo(Frame.FindComponent('ScriptReviewContext')).Height.ToString,Results); // 外側スクリプトが実パイプで提案を送る。
      Check(JA(JO(W.ScriptDraft.ScriptWizard,'review'),'items').Count=5,'actual pipe proposals reach shared GUI',Results);
      Check(JS(JO(W.ScriptDraft.ScriptWizard,'review'),'state')='ready','Codex completion closes proposal batch',Results);
      var List := TListView(Frame.FindComponent('ScriptReviewItems')); Check(List.Items.Count=5,'proposal list shows received items',Results);
      SelectItem(Frame,'weather');
      Check(TMemo(Frame.FindComponent('ScriptReviewContext')).SelLength=4,'selection highlights exact source range',Results);
      CaptureUiWindow(Main,ResultPath,'.ready');
      TToolButton(TToolBar(Frame.FindComponent('ScriptReviewToolbar')).FindComponent('ScriptReviewAI')).Click;
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text').StartsWith('今日はよく晴れています。'),'AI acceptance updates only anchored text',Results);
      Check(JI(ReviewItem(W.ScriptDraft,'repeat'),'offset')=16,'length change shifts following proposal',Results);
      Check(JS(ReviewItem(W.ScriptDraft,'overlap'),'decision')='stale','overlapping pending proposal becomes stale',Results);
      SelectItem(Frame,'repeat'); TToolButton(TToolBar(Frame.FindComponent('ScriptReviewToolbar')).FindComponent('ScriptReviewHuman')).Click;
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text').Contains('語語'),'human choice preserves current text',Results);
      SelectItem(Frame,'last'); var Proposal := TMemo(Frame.FindComponent('ScriptReviewProposal'));
      Proposal.SetFocus; Proposal.Text := 'ここで説明を終えます。';
      Check(W.ScriptTextEditing and (JS(ReviewItem(W.ScriptDraft,'last'),'editedDraft')=Proposal.Text),'manual edit is locked and retained in project',Results);
      CaptureUiWindow(Main,ResultPath,'.editing');
      TToolButton(TToolBar(Frame.FindComponent('ScriptReviewToolbar')).FindComponent('ScriptReviewHold')).Click;
      Check((JS(ReviewItem(W.ScriptDraft,'last'),'decision')='hold') and JS(ScriptSection(W.ScriptDraft,'body'),'text').Contains('最後の行'),'hold leaves original text intact',Results);
      W.SaveScriptDraft(False); Main.NavigateTo(apHome); W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
      Frame := ReviewFrame(Creator); SelectItem(Frame,'last'); Proposal := TMemo(Frame.FindComponent('ScriptReviewProposal'));
      Check(Proposal.Text='ここで説明を終えます。','manual draft survives interruption',Results);
      TToolButton(TToolBar(Frame.FindComponent('ScriptReviewToolbar')).FindComponent('ScriptReviewEdited')).Click;
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text').Contains('ここで説明を終えます。'),'edited acceptance updates source',Results);
      Check(JS(ReviewItem(W.ScriptDraft,'last'),'decision')='edited','edited decision recorded',Results);
      W.SaveScriptDraft(False);
      var Snapshot := W.ScriptDraft.Clone;
      try ValidateScriptReview(Snapshot); Check(ScriptFingerprint(Snapshot)=JS(JO(Snapshot.ScriptWizard,'review'),'fingerprint'),'clone preserves reviewed source fingerprint',Results); finally Snapshot.Free; end;
      TToolButton(Toolbar.FindComponent('ScriptTextStage')).Click;
      W.SetScriptText('body',JS(ScriptSection(W.ScriptDraft,'body'),'text')+#13#10+'人が追記しました。'); W.EndScriptTextEdit;
      Check(JS(JO(W.ScriptDraft.ScriptWizard,'review'),'state')='stale','human raw edit invalidates old review',Results);
      Next.Click;
      Check((W.CurrentScriptStage='review') and (JA(JO(W.ScriptDraft.ScriptWizard,'review'),'items').Count=0),'Next requests fresh review after human edit',Results);
      CaptureUiWindow(Main,ResultPath,'.fresh');
      Check((JS(JO(W.ScriptDraft.ScriptWizard,'review'),'state')='ready') and (JA(JO(W.ScriptDraft.ScriptWizard,'review'),'items').Count=1),'fresh actual pipe batch accepted',Results);
      W.EditReviewDraft('fresh','人が書いた下書き'); W.EndScriptTextEdit; W.SaveScriptDraft(False);
      var Resume := TJSONObject.Create;
      try Resume.AddPair('path',Path); Resume.AddPair('projectId',W.ScriptDraft.Id); Resume.AddPair('body',JS(ScriptSection(W.ScriptDraft,'body'),'text'));
        Resume.AddPair('review',JO(W.ScriptDraft.ScriptWizard,'review').ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8);
      finally Resume.Free; end;
      Check((W.ScriptDraft.Cues.Count=0) and (W.ScriptDraft.Scenes.Count=0),'review does not create speech scenes or synthesis',Results);
    end else CaptureUiWindow(Main,ResultPath,'.reopened');
    Check(Main.Workspace.RequestFinish,'owned application closes normally',Results);
    var Target := ResultPath; if Reopen then Target := ResultPath+'.reopened.json';
    TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
