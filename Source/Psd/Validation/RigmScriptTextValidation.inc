// Owned local fixtures only. No synthesis, analysis, new images or video export.
procedure VerifyScriptText(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Script text validation failed: '+Text); Results.Add(Text); end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptStage5.Validation.v1' then raise Exception.Create('Owned stage five root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8));
      try
        W.OpenScriptDraft(JS(Resume,'path')); Main.NavigateTo(apScriptCreate);
        Check((W.ScriptDraft.Id=JS(Resume,'projectId')) and (W.CurrentScriptStage='text'),'restart restores same UID and last Next destination',Results);
        Check(W.ScriptDraft.Title=JS(Resume,'title'),'restart preserves earlier title',Results);
        Check(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON=JS(Resume,'cast'),'restart preserves mixed PSD and RIGM cast',Results);
        Check(JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON=JS(Resume,'placements'),'restart preserves canonical placements',Results);
        Check(JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON=JS(Resume,'scriptText'),'restart restores all sections and active section',Results);
      finally Resume.Free; end;
    end else begin
      var Manager := Main.PageInstance(apScripts);
      TToolButton(TToolBar(Manager.FindComponent('ScriptLibraryToolbar')).FindComponent('ScriptNew')).Click;
    end;
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar'));
    var Title := TEdit(Creator.FindComponent('ScriptTitle')); var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    var Back := TToolButton(Toolbar.FindComponent('ScriptReturn')); var Path := W.ScriptDraft.FileName; var Id := W.ScriptDraft.Id; var A: TJSONObject;
    if not Reopen then begin
      Title.Text := '台本の3区分入力と保存再開の確認'; Next.Click;
      WaitThumbnailLibrary(W); Sleep(120); Application.ProcessMessages;
      for var Item in TListView(Creator.FindComponent('ScriptCharacters')).Items do
        if JB(TJSONObject(Item.Data),'readyForScript') then Item.Checked := True;
      Check(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=2,'existing complete PSD and RIGM remain selectable',Results);
      Next.Click; Next.Click;
      Check((W.CurrentScriptStage='placement') and Next.Visible and Next.Enabled,'placement now offers Next to text',Results);
      var First := JS(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters')[0]),'path'); A := TJSONObject.Create;
      try A.AddPair('path',First); AddB(A,'flipX',True); W.SetScriptPlacement(A); finally A.Free; end;
      var Hash := THashSHA2.GetHashStringFromFile(Path); var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try
        Next.Click;
        Check((W.CurrentScriptStage='placement') and W.ScriptDraft.Modified and (W.ScriptDraft.ScriptWizard.GetValue('scriptText')=nil) and
          JB(Placement(W.ScriptDraft,First),'flipX') and (THashSHA2.GetHashStringFromFile(Path)=Hash),'failed Next preserves placement input and previous disk destination',Results);
      finally Guard.Free; end;
      Next.Click;
      var Saved := LoadMovie(Path);
      try Check((JS(Saved.ScriptWizard,'stage')='text') and (JO(Saved.ScriptWizard,'scriptText')<>nil) and JB(Placement(Saved,First),'flipX') and
        (Saved.Id=Id) and not W.ScriptDraft.Modified,'Next atomically persists placements and initialized text destination',Results); finally Saved.Free; end;
    end;
    var Frame: TRigmScriptTextFrame := nil;
    for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptTextFrame then Frame := TRigmScriptTextFrame(Creator.Components[I]);
    Check((Frame<>nil) and Frame.Showing and not Next.Visible,'wide lazy text frame stops before proofreading',Results);
    var Parts := TToolBar(Frame.FindComponent('ScriptTextToolbar'));
    var Opening := TMemo(Frame.FindComponent('ScriptText0')); var Body := TMemo(Frame.FindComponent('ScriptText1')); var Closing := TMemo(Frame.FindComponent('ScriptText2'));
    Check((Body.Width>800) and (Body.Height>400),'script input uses wide plain text area',Results);
    if Reopen then CaptureUiWindow(Main,ResultPath,'.reopened') else begin
      var Cast := JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON; var Positions := JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON;
      TToolButton(Parts.FindComponent('ScriptTextPart0')).Click; Opening.Text := 'こんにちは。いつもの解説を始めます。'+#13#10+'共通の出だしです。';
      Check(JS(ScriptSection(W.ScriptDraft,'opening'),'text')=NormalizeScriptText(Opening.Text),'opening memo immediately updates canonical text',Results);
      TToolButton(Parts.FindComponent('ScriptTextPart2')).Click; Closing.Text := '今回はここまでです。ご視聴ありがとうございました。';
      Check((JS(ScriptSection(W.ScriptDraft,'opening'),'scope')='shared') and (JS(ScriptSection(W.ScriptDraft,'closing'),'scope')='shared') and
        (JS(ScriptSection(W.ScriptDraft,'body'),'scope')='episode'),'common opening and closing are distinguished from episode body',Results);
      TToolButton(Parts.FindComponent('ScriptTextPart1')).Click;
      var LongText := StringOfChar('文',8191)+Char($D83D)+Char($DE00)+#13#10+'長文末尾'; Body.Text := LongText;
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=NormalizeScriptText(Body.Text),'long GUI input remains raw text without speech conversion',Results);
      TToolButton(Parts.FindComponent('ScriptTextReady')).Click; CaptureUiWindow(Main,ResultPath,'.long');
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=LongText+'追記。','actual pipe reads long chunks and patches full section tail',Results);
      Body.Text := '今回のテーマについて説明します。'+#13#10+'台本の本文だけを入力します。'; Body.SetFocus; Body.Perform(WM_KEYDOWN,VK_END,0);
      Check(W.ScriptTextEditing,'focus and actual key input acquire shared typing lock',Results);
      CaptureUiWindow(Main,ResultPath,'.editing');
      Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=NormalizeScriptText(Body.Text),'pipe rejection retains human text',Results);
      TToolButton(Parts.FindComponent('ScriptTextReady')).Click; Check(not W.ScriptTextEditing,'input complete icon releases AI mutation lock',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe');
      Check(Body.Text='今回のテーマについて説明します。'+#13#10+'台本の本文だけを入力します。'+#13#10+'パイプから追記しました。','actual pipe change refreshes visible memo',Results);
      Check(not W.ScriptDraft.Modified,'pipe save persists text without advancing destination',Results);
      Check((JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON=Cast) and (JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON=Positions),'text edits retain earlier cast and placements',Results);
      var Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
      Check(Rejected and (W.CurrentScriptStage='text'),'proofreading and production boundary remains closed',Results);
      // The old editor is exercised through its model and command path on a clone.
      var EditorProject := W.ScriptDraft.Clone;
      try
        EditorProject.EnableComposition; EditorProject.Validate;
        Check((EditorProject.Characters.Count=2) and (EditorProject.Cues.Count=0) and (EditorProject.Scenes.Count=0),'explicit editor composition imports linked actors without production',Results);
        var C := EditorProject.Characters[0]; var P := EditorProject.Placement(C.PlacementRef);
        A := TJSONObject.Create;
        try A.AddPair('id',C.Id); AddN(A,'x',200); AddN(A,'y',200); AddN(A,'width',240); AddN(A,'height',500); AddB(A,'flipX',False);
          ApplyCompositionCommand(EditorProject,'update-character',A); EditorProject.Validate;
        finally A.Free; end;
        Check((Abs(JN(P,'x')-200/1920)<0.0001) and (Abs(JN(P,'height')-500/1080)<0.0001) and not JB(P,'flipX'),
          'final editor geometry command writes the same canonical placement',Results);
        PsdJson.Put(P,'x',TJSONNumber.Create(300/1920)); PsdJson.Put(P,'flipX',TJSONBool.Create(True));
        Check((Abs(C.X-300)<0.01) and C.FlipX,'canonical placement changes are immediately reflected in editor properties',Results);
        var Copy := EditorProject.Clone;
        try Check((Abs(Copy.Characters[0].X-300)<0.01) and Copy.Characters[0].FlipX and (Copy.Characters[0].PlacementRef=C.PlacementRef),
          'clone and JSON load restore placement links',Results);
          var Extra := PsdJson.ObjectText('{"id":"supplement","scope":"episode","text":"将来の補足区分","custom":"keep"}');
          JA(JO(Copy.ScriptWizard,'scriptText'),'sections').AddElement(Extra); ValidateScriptText(JO(Copy.ScriptWizard,'scriptText'));
          var ExtraCopy := Copy.Clone;
          try Check(JS(ScriptSection(ExtraCopy,'supplement'),'custom')='keep','extensible section array preserves extra section metadata',Results); finally ExtraCopy.Free; end;
        finally Copy.Free; end;
        var Legacy := TRigmMovieCharacter.Create;
        try var LegacyJson := Legacy.Json;
          try var LegacyCopy := TRigmMovieCharacter.FromJson(LegacyJson);
            try Check((LegacyCopy.PlacementRef='') and not LegacyCopy.FlipX and (Abs(LegacyCopy.X-Legacy.X)<0.01),
              'legacy independent character geometry remains compatible',Results); finally LegacyCopy.Free; end;
          finally LegacyJson.Free; end;
        finally Legacy.Free; end;
        // Existing character assets rendered in memory only; no exported image or video.
        EditorProject.Width := 320; EditorProject.Height := 180;
        for var Actor in EditorProject.Characters do begin
          for var Other in EditorProject.Characters do Other.Visible := Other=Actor;
          Actor.FlipX := False; var B1 := RenderComposition(EditorProject,0,nil);
          try Actor.FlipX := True; var B2 := RenderComposition(EditorProject,0,nil);
            try
              var Bytes1,Bytes2: TBytes; SetLength(Bytes1,B1.Width*B1.Height*4); SetLength(Bytes2,Length(Bytes1));
              for var Y := 0 to B1.Height-1 do begin Move(B1.ScanLine[Y]^,Bytes1[Y*B1.Width*4],B1.Width*4); Move(B2.ScanLine[Y]^,Bytes2[Y*B2.Width*4],B2.Width*4); end;
              Check(PreviewDigest(Bytes1)<>PreviewDigest(Bytes2),'existing '+Actor.RenderFormat+' renderer applies common horizontal reflection',Results);
            finally B2.Free; end;
          finally B1.Free; end;
        end;
      finally EditorProject.Free; end;
      var TextState := JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON;
      TToolButton(Toolbar.FindComponent('ScriptTitleStage')).Click; Title.Text := '戻った題名と3区分を保持'; Back.Click;
      W.OpenScriptDraft(Path); Main.NavigateTo(apScriptCreate);
      Check((W.CurrentScriptStage='text') and (JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON=TextState) and
        (W.ScriptDraft.Title='戻った題名と3区分を保持'),'backward edits and exit resume text with all raw sections',Results);
      Body.SetFocus; Body.Perform(WM_KEYDOWN,VK_END,0); Check(W.ScriptTextEditing,'typing again reacquires lock',Results);
      var CanClose := True; Main.OnCloseQuery(Main,CanClose); Check(CanClose,'close saves active text input',Results);
      CaptureUiWindow(Main,ResultPath,'.text');
      var Resume := TJSONObject.Create;
      try Resume.AddPair('projectId',Id); Resume.AddPair('path',Path); Resume.AddPair('title',W.ScriptDraft.Title);
        Resume.AddPair('cast',JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').ToJSON); Resume.AddPair('placements',JA(W.ScriptDraft.ScriptWizard,'placements').ToJSON);
        Resume.AddPair('scriptText',JO(W.ScriptDraft.ScriptWizard,'scriptText').ToJSON);
        TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8);
      finally Resume.Free; end;
    end;
    Check((Screen.FormCount=1) and (W.Sessions.Count=0) and (Main.PageInstance(apMovieEdit)=nil) and
      (W.ScriptDraft.Characters.Count=0) and (W.ScriptDraft.Cues.Count=0) and (W.ScriptDraft.Scenes.Count=0),'no hidden editor session voice analysis or production was created',Results);
    var State := W.ScriptStatus; Check(not JB(State,'canAdvance') and (JS(State,'resumeStage')='text'),'persisted destination remains text and further Next is disabled',Results);
    Report.AddPair('state',State); var Output := ResultPath; if Reopen then Output := Output+'.reopened.json'; TFile.WriteAllText(Output,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
