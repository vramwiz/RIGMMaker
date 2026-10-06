// 実エンジンの短文のみ。所有複製のGUI、読み分離、設定、旧音声保持、再開とパイプを確認。
procedure VerifyScriptVoice(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Voice check: '+Text); Results.Add(Text); end;
  procedure WaitVoice(W: TRigmWizardWorkspace);
  begin
    var Deadline := GetTickCount64+60000;
    repeat Application.ProcessMessages; var S := W.VoiceStatus; try if not JB(S,'busy') then Exit; finally S.Free; end; Sleep(5); until GetTickCount64>Deadline;
    raise Exception.Create('Owned voice job timeout');
  end;
  procedure Press(Control: TWinControl; Key: Word);
  begin Control.SetFocus; Control.Perform(WM_KEYDOWN,Key,0); Application.ProcessMessages; end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptVoice.Validation.v1' then raise Exception.Create('Owned voice root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1360,900); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; W.OpenScriptDraft(Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8))); Main.NavigateTo(apScriptCreate);
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TToolBar(Creator.FindComponent('ScriptTitleToolbar')); var Next := TToolButton(Toolbar.FindComponent('ScriptNext'));
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var Json := W.ScriptDraft.Json;
      try Check(W.CurrentScriptStage='voice','restart resumes saved voice screen',Results); Check(Json.ToJSON=JS(Resume,'project'),'binding reading query audio metadata and selection survive restart',Results);
      finally Json.Free; Resume.Free; end;
    end else begin
      Check(W.CurrentScriptStage='subtitles','copied semantic fixture begins at subtitles',Results);
      for var BadText in ['A'+#1,'A'+Char($D800),'A'+Char($DC00)] do begin
        var Rejected := False; try ValidateVoiceReading(BadText); except on E: Exception do Rejected := True; end;
        Check(Rejected,'reading rejects invalid UTF16/control at even offset',Results);
      end;
      ValidateVoiceReading('A'+Char($D83D)+Char($DE00)+'B'); Check(True,'reading accepts complete supplementary character',Results);
      var BadCue := TJSONObject.Create;
      try BadCue.AddPair('voiceSettings',TJSONArray.Create); var Rejected := False;
        try var Invalid := TRigmMovieCue.FromJson(BadCue); Invalid.Free; except on E: ERigm do Rejected := True; end;
        Check(Rejected,'malformed saved query object rejects safely before replacing owned settings',Results);
      finally BadCue.Free; end;
      var C := W.ScriptDraft.Cues[0]; var OldSpeaker := W.ScriptDraft.Speaker(C.SpeakerId).Json;
      try Check(W.ScriptDraft.AudioFingerprint(C)=THashSHA2.GetHashString(W.ScriptDraft.EngineUrl+#10+C.Text+#10+OldSpeaker.ToJSON),'empty new fields preserve legacy audio fingerprint',Results); finally OldSpeaker.Free; end;
      var SubFrame: TRigmScriptSubtitleFrame := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptSubtitleFrame then SubFrame := TRigmScriptSubtitleFrame(Creator.Components[I]);
      TToolButton(TToolBar(SubFrame.FindComponent('ScriptSubtitleToolbar')).FindComponent('ScriptSubtitleReady')).Click;
      WaitThumbnailLibrary(W); Next.Click; Check((W.CurrentScriptStage='voice') and not W.ScriptDraft.Modified,'Next saves voice destination before navigation',Results);
    end;
    var Frame: TRigmScriptVoiceFrame := nil; for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptVoiceFrame then Frame := TRigmScriptVoiceFrame(Creator.Components[I]);
    Check((Frame<>nil) and Frame.Showing and Next.Visible and not Next.Enabled,'lazy voice frame retains audio completion gate before scenes',Results);
    var List := TListView(Frame.FindComponent('ScriptVoiceRows')); var Reading := TMemo(Frame.FindComponent('ScriptVoiceReading')); var Style := TComboBox(Frame.FindComponent('ScriptVoiceStyle')); var Tools := TToolBar(Frame.FindComponent('ScriptVoiceToolbar'));
    if not Reopen then begin
      Check((Style.ItemIndex=-1) and (W.ScriptDraft.Speaker(W.ScriptDraft.Cues[0].SpeakerId).StyleId=-1),'unassigned character has no guessed default voice',Results);
      TEdit(Frame.FindComponent('ScriptVoiceEngine')).Text := 'http://127.0.0.1:50022'; TButton(Frame.FindComponent('ScriptVoiceEngineApply')).Click;
      Check(W.ScriptDraft.EngineUrl='http://127.0.0.1:50022','explicit GUI endpoint is saved in copied project',Results);
      TToolButton(Tools.FindComponent('ScriptVoiceRefresh')).Click; WaitVoice(W);
      var Index := -1; for var I := 0 to W.VoiceCatalog.Count-1 do if (JI(TJSONObject(W.VoiceCatalog[I]),'styleId')=108) and (JS(TJSONObject(W.VoiceCatalog[I]),'uuid')='1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b') then Index := I;
      Check(Index>=0,'live catalog supplies Tohoku Kiritan normal 108 actual UUID',Results);
      Style.ItemIndex := Index; Style.OnChange(Style); Check(W.ScriptDraft.Speaker(W.ScriptDraft.Cues[0].SpeakerId).StyleId=108,'explicit test-only GUI selection binds actual style to guide character',Results);
      TToolButton(Tools.FindComponent('ScriptVoiceSaveDefault')).Click;
      Check(FileExists(TPath.Combine(Main.DataRoot,'CharacterVoiceBindings.json')),'registered character initial binding saved separately from rigm',Results);
      var Before := W.ScriptDraft.Revision; var Fingerprint := W.ScriptDraft.AudioFingerprint(W.ScriptDraft.Cues[0]);
      Press(List,VK_RETURN); TToolButton(Tools.FindComponent('ScriptVoiceDone')).Click;
      Check((W.ScriptDraft.Revision=Before) and (W.ScriptDraft.AudioFingerprint(W.ScriptDraft.Cues[0])=Fingerprint),'unchanged detail editing preserves existing audio fingerprint and revision',Results);
      Press(List,VK_DOWN); Check((Style.ItemIndex=-1) and (W.ScriptDraft.Speaker(W.ScriptDraft.Cues[1].SpeakerId).StyleId=-1),'other character remains explicitly unassigned',Results); Press(List,VK_UP);
      var C := W.ScriptDraft.Cues[0]; var Id := C.Id; var Source := C.Text; var Subtitle := C.Subtitle; var Scene := C.Scene; var Raw := ScriptFingerprint(W.ScriptDraft);
      Press(List,VK_RETURN); Reading.Text := 'かくうのほしぞらかんそくじょです。'; TEdit(Frame.FindComponent('ScriptVoiceValue0')).Text := '0.97'; TEdit(Frame.FindComponent('ScriptVoiceValue1')).Text := '0.02';
      Check(W.ScriptTextEditing and (C.SpokenText=Reading.Text) and (C.Text=Source) and (C.Subtitle=Subtitle) and (C.Scene=Scene) and (ScriptFingerprint(W.ScriptDraft)=Raw),'human reading and query edits preserve raw subtitle scene and cast source',Results);
      var Settings := C.VoiceSettings.Clone as TJSONObject;
      try var Bad := Settings.Clone as TJSONObject; try PsdJson.Put(Bad,'speedScale',TJSONNumber.Create(9)); var Rejected := False;
        try W.EditVoice(Id,'上書き',Bad); except on E: Exception do Rejected := True; end; Check(Rejected and (C.SpokenText=Reading.Text),'invalid query atomically rejects reading overwrite',Results);
      finally Bad.Free; end; finally Settings.Free; end;
      TEdit(Frame.FindComponent('ScriptVoiceValue0')).Text := '-'; Check(not Frame.RequestFinish,'incomplete numeric input blocks leaving without discarding typed value',Results);
      Check(TEdit(Frame.FindComponent('ScriptVoiceValue0')).Text='-','incomplete typed value retained',Results); TEdit(Frame.FindComponent('ScriptVoiceValue0')).Text := '0.97';
      CaptureUiWindow(Main,ResultPath,'.editing'); TToolButton(Tools.FindComponent('ScriptVoiceDone')).Click; Check(not W.ScriptTextEditing,'input complete releases common pipe edit guard',Results);
      Press(List,VK_F5); WaitVoice(W); Check(W.ScriptDraft.AudioReady(C) and FileExists(C.LabFile),'F5 generates and previews one real WAV and phoneme LAB',Results);
      var Pcm := TRigmPcm.Load(C.WaveFile); try Check((Pcm.Duration>0.2) and (Length(Pcm.Samples)>1000),'real PCM is nonempty and measured',Results); finally Pcm.Free; end;
      for var I := 1 to W.ScriptDraft.Cues.Count-1 do Check(W.ScriptDraft.Cues[I].WaveFile='','selected generation leaves other cue audio untouched '+I.ToString,Results);
      W.StopVoice; var Wave := C.WaveFile; var Lab := C.LabFile; var Seconds := C.AudioSeconds; var Key := C.AudioKey; var Hash := THashSHA2.GetHashStringFromFile(Wave);
      var StartAfterFirst := W.ScriptDraft.CueStart(W.ScriptDraft.Cues[1]);
      CaptureUiWindow(Main,ResultPath,'.generated');
      var Values := C.VoiceSettings.Clone as TJSONObject;
      try
        W.EditVoice(Id,'変更前のかくにんです。',Values); W.GenerateVoice(Id,False); W.EditVoice(Id,'変更後のかくにんです。',Values); WaitVoice(W);
        Check((C.WaveFile=Wave) and (C.LabFile=Lab) and (C.AudioSeconds=Seconds) and (C.AudioKey=Key) and (THashSHA2.GetHashStringFromFile(Wave)=Hash) and not W.ScriptDraft.AudioReady(C),'late real generation never replaces newer human reading or previous audio',Results);
        W.GenerateVoice(Id,False); W.CancelVoice; WaitVoice(W); Check((C.WaveFile=Wave) and (C.AudioKey=Key),'cancelled selected generation keeps previous audio',Results);
        var Failed := W.ScriptDraft.Clone; var Options := TJSONObject.Create;
        try Failed.EngineUrl := 'http://127.0.0.1:50029'; Options.AddPair('cueId',Id); var Job := TRigmMovieJob.Create(Failed,'audio',TPath.Combine(Main.DataRoot,'FailedAudio'),0,Options);
          try Job.Start; var Deadline := GetTickCount64+10000; while not Job.Done and (GetTickCount64<Deadline) do begin Application.ProcessMessages; Sleep(5); end;
            var Status := Job.Status; try Check(Job.Done and (JS(Status,'state')='failed') and (Job.Project.Cue(Id).WaveFile=Wave),'actual unavailable HTTP synthesis preserves snapshot previous WAV',Results); finally Status.Free; end;
          finally Job.Free; end;
        finally Options.Free; Failed.Free; end;
        Check((C.WaveFile=Wave) and (C.LabFile=Lab) and (THashSHA2.GetHashStringFromFile(Wave)=Hash),'failed or cancelled generation leaves stored files and metadata intact',Results);
        W.EditVoice(Id,'かくにんです。',Values); Press(List,VK_F5); WaitVoice(W); W.StopVoice;
        Check(W.ScriptDraft.AudioReady(C) and (C.WaveFile<>Wave) and (C.AudioSeconds<Seconds),'new short reading regenerates selected audio and measured duration only',Results);
        Check(Abs(W.ScriptDraft.CueStart(W.ScriptDraft.Cues[1])-StartAfterFirst-(C.AudioSeconds-Seconds))<0.00001,'changed measured duration ripples subsequent cue start',Results);
      finally Values.Free; end;
      Check((C.Text=Source) and (C.Subtitle=Subtitle) and (ScriptFingerprint(W.ScriptDraft)=Raw),'real synthesis and retries preserve raw source and subtitle',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe');
      Check(C.SpokenText='ぱいぷでかくにんです。','actual pipe reading edit reaches common cue',Results); Press(List,VK_F5); WaitVoice(W); W.StopVoice;
      W.SaveScriptDraft(False); CaptureUiWindow(Main,ResultPath,'.saved');
      var Resume := TJSONObject.Create; var Saved := W.ScriptDraft.Json;
      try Resume.AddPair('project',Saved.ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; Saved.Free; end;
    end else begin
      Check(W.ScriptDraft.AudioReady(W.ScriptDraft.Cues[0]),'saved selected audio still ready after normal restart',Results); CaptureUiWindow(Main,ResultPath,'.reopened');
      var OldPath := W.ScriptDraft.FileName; var OriginalHash := THashSHA2.GetHashStringFromFile(OldPath); var Previous := W.ScriptDraft.Clone;
      try
        WaitThumbnailLibrary(W); var Catalog := W.ScriptCharacterLibrary(False);
        try
          var Found := False; for var V in JA(Catalog,'characters') do if SameText(JS(TJSONObject(V),'path'),'RIGM\casting-guide.rigm') then
            Found := (JS(TJSONObject(V),'voiceBindingStatus')='registered') and (JI(JO(TJSONObject(V),'voiceBinding'),'styleId')=108) and (JS(JO(TJSONObject(V),'voiceBinding'),'uuid')='1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b');
          Check(Found,'registered character binding is read from disk after restart',Results);
        finally Catalog.Free; end;
        Main.NavigateTo(apHome); W.CurrentPage := apHome; W.NewScriptDraft; W.SetScriptTitle('登録音声再利用の分離確認'); W.NextScriptDraft;
        var Paths := TJSONArray.Create;
        try Paths.Add('RIGM\casting-guide.rigm'); Paths.Add('RIGM\casting-question.rigm'); W.SetScriptCharacters(Paths); finally Paths.Free; end;
        var Selected := JA(W.ScriptDraft.ScriptWizard,'selectedCharacters');
        Check((Selected.Count=2) and (JI(JO(TJSONObject(Selected[0]),'voiceBinding'),'styleId')=108) and (JS(TJSONObject(Selected[1]),'voiceBindingStatus')='unassigned'),'new project selection copies only explicitly registered binding',Results);
        Check(W.ScriptDraft.EngineUrl='http://127.0.0.1:50021','registered voice copy does not change project or global engine URL',Results);
        var Copy := Previous.Clone;
        try
          PsdJson.Put(Copy.ScriptWizard,'selectedCharacters',Selected.Clone as TJSONArray);
          var Speaker := Copy.Speaker(Copy.Cues[0].SpeakerId); Speaker.StyleId := -1; Speaker.VoiceUuid := ''; Speaker.VoiceName := ''; Speaker.StyleName := '';
          PrepareScriptVoice(Copy); Check((Speaker.StyleId=108) and (Speaker.VoiceUuid='1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b'),'voice preparation reuses copied registration UUID and style',Results);
          Speaker.StyleId := 77; Speaker.VoiceUuid := 'existing-explicit-voice'; var OldWave := Copy.Cues[0].WaveFile; var OldKey := Copy.Cues[0].AudioKey;
          PrepareScriptVoice(Copy); Check((Speaker.StyleId=77) and (Speaker.VoiceUuid='existing-explicit-voice') and (Copy.Cues[0].WaveFile=OldWave) and (Copy.Cues[0].AudioKey=OldKey),'registration copy retains existing speaker and stored audio',Results);
        finally Copy.Free; end;
        W.SaveScriptDraft(False); W.OpenScriptDraft(OldPath); Main.NavigateTo(apScriptCreate);
        Check(THashSHA2.GetHashStringFromFile(OldPath)=OriginalHash,'new project registration reuse leaves older project disk unchanged',Results);
        var BindingPath := TPath.Combine(Main.DataRoot,'CharacterVoiceBindings.json'); var Bytes := TFile.ReadAllBytes(BindingPath);
        try
          var External := ParseObject(TEncoding.UTF8.GetString(Bytes));
          try External.AddPair('externalRevision',TJSONNumber.Create(7)); TFile.WriteAllText(BindingPath,External.ToJSON,TEncoding.UTF8); finally External.Free; end;
          var ExternalHash := THashSHA2.GetHashStringFromFile(BindingPath); var Rejected := False;
          try W.SaveCharacterVoice(1); except on E: Exception do Rejected := True; end;
          Check(Rejected and (THashSHA2.GetHashStringFromFile(BindingPath)=ExternalHash),'external binding change rejects save and keeps external contents',Results);
        finally TFile.WriteAllBytes(BindingPath,Bytes); end;
      finally Previous.Free; end;
    end;
    Check(W.RequestFinish,'owned application closes normally',Results); var Target := ResultPath; if Reopen then Target := ResultPath+'.reopened.json'; TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
