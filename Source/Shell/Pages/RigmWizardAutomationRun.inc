// 自動制作の正本はWorkspaceで所有する。タイマー1回につき1工程を進める。
procedure TRigmWizardWorkspace.AutomationRunEvent(const Stage,State,Message: string);
begin
  var Events := JA(FAutomationRun,'events');
  Events.AddElement(TJSONObject.Create.AddPair('sequence',TJSONNumber.Create(Events.Count+1))
    .AddPair('stage',Stage).AddPair('state',State).AddPair('message',Message).AddPair('at',ScriptUtcNow));
  PsdJson.Put(FAutomationRun,'stage',Stage); PsdJson.Put(FAutomationRun,'message',Message);
  TFile.WriteAllText(TPath.Combine(FAutomationFolder,'status.json'),FAutomationRun.ToJSON,TEncoding.UTF8);
end;

function TRigmWizardWorkspace.AutomationRunCommand(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Name='start' then begin
    if (FAutomationRunPhase<>0) or (FAutomationCheckPhase<>0) then raise Exception.Create('自動制作または事前検査は実行中です。');
    if ExpressionAiBusy or SceneImageAiBusy or VoiceBusy or FPlacementEditing or
      ((FActive<>nil) and FActive.Busy) or ((FScriptDraft<>nil) and FScriptDraft.Modified) then
      raise Exception.Create('実行中の処理・未保存の編集を終了してから自動制作を開始してください。');
    var Input := ValidateAutomationInput(JS(Args,'text'));
    try
      if not JB(Input,'valid') then begin
        Result := Input.Clone as TJSONObject; Result.AddPair('state','invalid'); AddB(Result,'productionStarted',False); Exit;
      end;
      var Sources := AutomationSources(JS(JO(Input,'data'),'scriptType'));
      try
        if not JB(Sources,'available') then begin
          Result := TJSONObject.Create.AddPair('state','blocked').AddPair('productionStarted',TJSONBool.Create(False))
            .AddPair('code','copy_source_not_found').AddPair('message','同種類の入力中ではないコピー元がありません。')
            .AddPair('sources',Sources.Clone as TJSONObject); Exit;
        end;
        var Selected := JO(Sources,'selected');
        var Probe := AutomationSourceCheck(JS(JO(Input,'data'),'scriptType'),JS(Selected,'projectId'));
        try if not JB(Probe,'eligible') or not JB(Probe,'copyValidated') then begin
          Result := TJSONObject.Create.AddPair('state','blocked').AddPair('productionStarted',TJSONBool.Create(False))
            .AddPair('code','copy_source_invalid').AddPair('sourceCheck',Probe.Clone as TJSONObject); Exit;
        end; finally Probe.Free; end;
        // DLLの存在だけでなくABIと全必要エクスポートまで、制作前に検査する。
        var Api := TRigmFFmpegApi.Create; Api.Free;
        var Source := LoadMovie(FPipe.Workspace.Resolve(JS(Selected,'path')));
        try
          var Id := TGUID.NewGuid.ToString;
          var Folder := FPipe.Workspace.Resolve('Automation\'+Id,False); ForceDirectories(Folder);
          var Run := TJSONObject.Create.AddPair('jobId',Id).AddPair('operation','production')
            .AddPair('state','running').AddPair('productionStarted',TJSONBool.Create(False))
            .AddPair('productionCompleted',TJSONBool.Create(False)).AddPair('resumeSupported',TJSONBool.Create(False))
            .AddPair('input',JO(Input,'data').Clone as TJSONObject).AddPair('source',Selected.Clone as TJSONObject)
            .AddPair('sourceSha256',THashSHA2.GetHashStringFromFile(Source.FileName))
            .AddPair('events',TJSONArray.Create).AddPair('issues',TJSONArray.Create).AddPair('logDirectory',Folder);
          FreeAndNil(FAutomationRun); FAutomationRun := Run;
          FreeAndNil(FAutomationSource); FAutomationSource := Source; Source := nil;
          FAutomationFolder := Folder; FAutomationStarted := GetTickCount64; FAutomationCueIndex := 0;
          FAutomationImageId := ''; FAutomationExportId := '';
          TFile.WriteAllText(TPath.Combine(Folder,'input.txt'),JS(Args,'text'),TEncoding.UTF8);
          AutomationRunEvent('input','completed','入力確認完了。最新台本のコピーから自動制作を開始します。');
          FAutomationRunPhase := 1;
          Result := FAutomationRun.Clone as TJSONObject; Result.RemovePair('input').Free;
        finally Source.Free; end;
      finally Sources.Free; end;
    finally Input.Free; end;
    Exit;
  end;
  if (FAutomationRun=nil) or (JS(Args,'jobId')<>JS(FAutomationRun,'jobId')) then raise Exception.Create('unknown_job');
  if Name='cancel' then begin
    if FAutomationRunPhase<>0 then begin
      PsdJson.Put(FAutomationRun,'cancelRequested',TJSONBool.Create(True));
      if ExpressionAiBusy then CancelExpressionAi;
      if SceneImageAiBusy then CancelSceneImageAi;
      if VoiceBusy then CancelVoice;
      if (FAutomationExportId<>'') and (FActive<>nil) and (FActive.Project.Id=JS(FAutomationRun,'projectId')) then begin
        var O := TJSONObject.Create; try var R := FActive.Execute('job-cancel',O); R.Free; finally O.Free; end;
      end;
    end;
  end;
  var After := JI(Args,'afterSequence',0); if After<0 then raise Exception.Create('invalid_sequence');
  Result := FAutomationRun.Clone as TJSONObject; Result.RemovePair('input').Free;
  var Events := TJSONArray.Create;
  for var V in JA(FAutomationRun,'events') do if JI(TJSONObject(V),'sequence')>After then Events.AddElement(V.Clone as TJSONValue);
  PsdJson.Put(Result,'events',Events);
  if (FAutomationRunPhase=10) and (FActive<>nil) then begin
    var O := TJSONObject.Create.AddPair('jobId',FAutomationExportId);
    try Result.AddPair('currentJob',FActive.Execute('job-status',O)); finally O.Free; end;
  end else if SceneImageAiBusy then Result.AddPair('currentTask',FImageAiMessage)
  else if ExpressionAiBusy then Result.AddPair('currentTask',FExpressionAiMessage);
end;

function TRigmWizardWorkspace.AutomationBodyScene(Offset: Integer): Integer;
begin
  var Position := 0; var Scenes := JA(JO(FAutomationRun,'input'),'scenes');
  Result := Scenes.Count-1;
  for var I := 0 to Scenes.Count-1 do begin
    Inc(Position,Length(NormalizeScriptText(JS(TJSONObject(Scenes[I]),'body'))));
    if Offset<Position then Exit(I);
    Inc(Position,2);
  end;
end;

procedure TRigmWizardWorkspace.PollAutomationRun;
  procedure Advance;
  begin
    var Stage := CurrentScriptStage; NextScriptDraft;
    AutomationRunEvent(Stage,'completed',ScriptStageName(Stage)+'を完了しました。');
  end;
  procedure ApplyScene(const Id,Title,Description,Prompt: string);
  begin
    var A := TJSONArray.Create;
    try
      var O := TJSONObject.Create.AddPair('id',Id);
      if Id<>RigmCommonBackgroundId then O.AddPair('title',Title);
      A.AddElement(O
      .AddPair('description',Description).AddPair('prompt',Prompt).AddPair('mode',SceneInputDisplayMode(Prompt,Description))
      .AddPair('descriptionPosition','below-image')); UpdateScriptSceneInputs(A);
    finally A.Free; end;
  end;
  function MovieCommand(const Name: string; Args: TJSONObject): TJSONObject;
  begin try Result := FActive.Execute(Name,Args); finally Args.Free; end; end;
  procedure PersistProjectState(const State: string);
  begin
    if (FScriptDraft<>nil) and (FScriptDraft.Id=JS(FAutomationRun,'projectId')) then begin
      PsdJson.Put(JO(FScriptDraft.ScriptWizard,'automation'),'state',State);
      FScriptDraft.Changed; SaveScriptDraft(False);
    end else if (FActive<>nil) and (FActive.Project.Id=JS(FAutomationRun,'projectId')) then begin
      PsdJson.Put(JO(FActive.Project.ScriptWizard,'automation'),'state',State);
      FActive.Project.Changed;
      var O := MovieCommand('save',TJSONObject.Create); O.Free;
    end;
  end;
begin
  if FAutomationRunPhase=0 then Exit;
  try
    if JB(FAutomationRun,'cancelRequested') then begin
      if VoiceBusy or ExpressionAiBusy or SceneImageAiBusy or ((FActive<>nil) and FActive.Busy) then Exit;
      PersistProjectState('cancelled');
      FAutomationRunPhase := 0; PsdJson.Put(FAutomationRun,'state','cancelled');
      AutomationRunEvent('cancel','completed','自動制作を中止しました。作成済みのデータは保持しています。'); Exit;
    end;
    if GetTickCount64-FAutomationStarted>UInt64(3600000) then raise Exception.Create('自動制作が60分を超えたため停止します。');
    if (FAutomationRunPhase>1) and (FAutomationRunPhase<9) and
      ((FScriptDraft=nil) or (FScriptDraft.Id<>JS(FAutomationRun,'projectId'))) then raise Exception.Create('制作対象の台本が切り替わりました。');
    var Data := JO(FAutomationRun,'input');
    case FAutomationRunPhase of
      1: begin
        AutomationRunEvent('copy','started','元台本を保持して新しい作品IDへコピーします。');
        var Path := JS(JO(FAutomationRun,'source'),'path');
        if not SameText(JS(FAutomationRun,'sourceSha256'),THashSHA2.GetHashStringFromFile(Path)) then raise Exception.Create('コピー元が受付後に変更されました。');
        CopyScriptDraft(Path);
        PsdJson.Put(FAutomationRun,'projectId',FScriptDraft.Id); PsdJson.Put(FAutomationRun,'projectPath',ScriptPath(FScriptDraft));
        PsdJson.Put(FAutomationRun,'productionStarted',TJSONBool.Create(True));
        FScriptDraft.EngineUrl := FAutomationSource.EngineUrl;
        FScriptDraft.Width := FAutomationSource.Width; FScriptDraft.Height := FAutomationSource.Height;
        FScriptDraft.Fps := FAutomationSource.Fps;
        FScriptDraft.EncodeProfile := FAutomationSource.EncodeProfile;
        PsdJson.Put(FScriptDraft.ScriptWizard,'automation',TJSONObject.Create.AddPair('jobId',JS(FAutomationRun,'jobId'))
          .AddPair('acceptGeneratedVoice',TJSONBool.Create(True)).AddPair('acceptGeneratedImages',TJSONBool.Create(True))
          .AddPair('sourceProjectId',FAutomationSource.Id).AddPair('state','running'));
        SetScriptTitle(JS(Data,'title')); SetScriptType(JS(Data,'scriptType'));
        AutomationRunEvent('copy','completed','元台本のコピーを作成しました。'); FAutomationRunPhase := 2;
      end;
      2: begin
        var Stage := CurrentScriptStage;
        if Stage='layout' then SetScriptLayout(JS(FAutomationSource.ScriptWizard,'layoutChoice'),JS(FAutomationSource.ScriptWizard,'backgroundTone','dark'));
        if Stage='text' then begin
          var Body := ''; for var V in JA(Data,'scenes') do begin
            if Body<>'' then Body := Body+#13#10; Body := Body+NormalizeScriptText(JS(TJSONObject(V),'body'));
          end;
          SetScriptText('body',Body);
        end;
        if Stage='summary' then SetScriptSummaryChoice('yes');
        if Stage='summary-edit' then begin
          var D := JO(JO(FScriptDraft.ScriptWizard,'summaryData'),'draft').Clone as TJSONObject;
          try
            for var Key in ['text','subtitle','reading'] do PsdJson.Put(D,Key,NormalizeScriptText(JS(JO(Data,'summary'),'body')));
            PsdJson.Put(D,'minimum','0'); PsdJson.Put(D,'maximum','5');
            var Items := TJSONArray.Create; for var V in JA(JO(Data,'summary'),'items') do
              Items.AddElement(TJSONObject.Create.AddPair('label',JS(TJSONObject(V),'label')).AddPair('value',TJSONObject(V).GetValue('value').Value));
            PsdJson.Put(D,'items',Items); SetScriptSummaryDraft(D); CompleteScriptSummary;
          finally D.Free; end;
        end;
        if Stage='closing' then begin
          var D := JO(JO(FScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
          try
            // 固定エンドカードは元台本の設定を引き継ぐ。未指定の任意画像は省略する。
            if FAutomationSource.ScriptWizard.GetValue('closingData') is TJSONObject then begin
              var Old := JO(JO(FAutomationSource.ScriptWizard,'closingData'),'draft');
              for var Key in ['endChoice','endImage','endSeconds','thumbnailSeconds','rect','reserved'] do
                if Old.GetValue(Key)<>nil then PsdJson.Put(D,Key,Old.GetValue(Key).Clone as TJSONValue);
              if JS(D,'endImage')<>'' then PsdJson.Put(D,'endImage',ResolveMoviePath(FAutomationSource.FileName,JS(D,'endImage')));
            end;
            for var Key in ['representativeChoice','thumbnailChoice'] do PsdJson.Put(D,Key,'none');
            if JS(D,'endChoice')='' then PsdJson.Put(D,'endChoice','none');
            SetScriptClosingDraft(D); CompleteScriptClosing;
          finally D.Free; end;
        end;
        if Stage='casting' then begin
          AutomationRunEvent('casting','started','保存済みの声を使って配役と表情を設定します。');
          RefreshVoiceCatalog; FAutomationRunPhase := 3; Exit;
        end;
        Advance;
      end;
      3: begin
        if VoiceBusy then Exit;
        if not VoiceCatalogReady then raise Exception.Create('VOICEVOXの話者一覧を取得できません：'+FVoiceError);
        var Roles := JA(JO(FScriptDraft.ScriptWizard,'casting'),'roles'); var Number := 0;
        for var V in Roles do if JB(TJSONObject(V),'active') then begin Number := JI(TJSONObject(V),'number'); Break; end;
        if Number=0 then raise Exception.Create('使用できる説明キャラの配役がありません。');
        for var RoleValue in Roles do begin
          var Role := TJSONObject(RoleValue); var Target := FScriptDraft.Speaker(JS(Role,'speakerId'));
          if Target=nil then Continue;
          for var Old in FAutomationSource.Speakers do
            if (Old.VoiceUuid=Target.VoiceUuid) and (Old.StyleId=Target.StyleId) then begin
              Target.Speed := Old.Speed; Target.Pitch := Old.Pitch;
              Target.Intonation := Old.Intonation; Target.Volume := Old.Volume; Break;
            end;
        end;
        for var C in FScriptDraft.Cues do begin
          AssignCasting(C.Id,Number,True);
          PsdJson.Put(CastingRow(FScriptDraft,C.Id),'origin','automation');
          C.Subtitle := C.Text; C.VoiceReading := C.Text;
        end;
        var DialogueIds := TJSONArray.Create;
        try ApplyImportedDialogueInputs(FScriptDraft,Data,DialogueIds); finally DialogueIds.Free; end;
        var Reason := CastingAdvanceReason; if Reason<>'' then raise Exception.Create(Reason);
        StartExpressionAi; FAutomationRunPhase := 4;
      end;
      4: begin
        if ExpressionAiBusy then Exit;
        if not FExpressionAiSucceeded then raise Exception.Create(FExpressionAiMessage);
        AutomationRunEvent('expressions','completed',FExpressionAiMessage); Advance;
        for var C in FScriptDraft.Cues do EditSubtitle(C.Id,C.Subtitle,'');
        CompleteSubtitles; Advance; FAutomationRunPhase := 5;
        AutomationRunEvent('voice','started','セリフごとに指定された読み上げ文から音声を生成します。');
      end;
      5: begin
        if VoiceBusy then Exit;
        if FVoiceError<>'' then raise Exception.Create(FVoiceError);
        if FAutomationCueIndex<FScriptDraft.Cues.Count then begin
          var C := FScriptDraft.Cues[FAutomationCueIndex];
          if not FScriptDraft.AudioReady(C) then begin GenerateVoice(C.Id,False); Exit; end;
          Inc(FAutomationCueIndex);
          AutomationRunEvent('voice','progress',Format('%d / %d 件の音声を生成しました。',[FAutomationCueIndex,FScriptDraft.Cues.Count])); Exit;
        end;
        CompleteVoice; Advance; FAutomationRunPhase := 6;
      end;
      6: begin
        // エフェクト設定は元台本の声ごとの先頭設定を引き継ぐ。派生WAVは既存出力処理が作る。
        for var C in FScriptDraft.Cues do begin
          for var Old in FAutomationSource.Cues do if Old.SpeakerId<>'' then begin
            var S := FAutomationSource.Speaker(Old.SpeakerId); var Target := FScriptDraft.Speaker(C.SpeakerId);
            if (S<>nil) and (Target<>nil) and (S.VoiceUuid=Target.VoiceUuid) and (S.StyleId=Target.StyleId) then begin EditVoiceEffects(C.Id,Old.AudioEffects); Break; end;
          end;
        end;
        Advance;
        // section+原稿offsetで入力のシーン区切りを再現し、改行はセリフへ残す。
        var Previous := ''; var PreviousBlock := -2;
        for var I := 0 to FScriptDraft.Cues.Count-1 do begin
          var C := FScriptDraft.Cues[I]; if IsScriptSummaryCue(FScriptDraft,C) then begin Previous := 'summary'; Continue; end;
          var Row := CastingRow(FScriptDraft,C.Id); var Section := JS(Row,'section'); var Block := -1;
          if Section='body' then Block := AutomationBodyScene(JI(Row,'offset'));
          if ScriptSceneStartEditable(FScriptDraft,I) then SetScriptSceneStart(C.Id,(Section<>Previous) or (Block<>PreviousBlock));
          Previous := Section; PreviousBlock := Block;
        end;
        Advance;
        ApplyScene(RigmCommonBackgroundId,'共通背景','',JS(Data,'backgroundPrompt'));
        for var SceneIndex := 0 to FScriptDraft.Scenes.Count-1 do begin
          var S := FScriptDraft.Scenes[SceneIndex];
          if MovieChartEnabled(S.Chart) then begin SetScriptSceneApproved(S.Id,True); Continue; end;
          var Row: TJSONObject := nil;
          for var C in FScriptDraft.Cues do if C.Scene=S.Id then begin Row := CastingRow(FScriptDraft,C.Id); Break; end;
          if Row=nil then raise Exception.Create('シーンに対応する本文がありません。');
          if JS(Row,'section')='body' then begin
            var InputScene := TJSONObject(JA(Data,'scenes')[AutomationBodyScene(JI(Row,'offset'))]);
            ApplyScene(S.Id,JS(InputScene,'title'),JS(InputScene,'displayText'),JS(InputScene,'imagePrompt'));
          end else ApplyScene(S.Id,S.Title,'','紹介動画の補助画像。文字は描かない。'+JS(ScriptSection(FScriptDraft,JS(Row,'section')),'text'));
        end;
        SaveScriptDraft(False); FAutomationRunPhase := 7;
        AutomationRunEvent('images','started','背景・各シーン・実キャラを参照したサムネイルを順に生成します。');
      end;
      7: begin
        if SceneImageAiBusy then Exit;
        var Target: TRigmMovieScene := nil;
        if not FScriptDraft.CommonBackground.ImageApproved then Target := FScriptDraft.CommonBackground;
        if Target=nil then for var S in FScriptDraft.Scenes do if not S.ImageApproved then begin Target := S; Break; end;
        if Target=nil then if not FScriptDraft.Thumbnail.ImageApproved then Target := FScriptDraft.Thumbnail;
        if Target=nil then begin CompleteScriptScenes; Advance; FAutomationRunPhase := 9; Exit; end;
        if not SceneNeedsImage(Target) then begin SetScriptSceneApproved(Target.Id,True); Exit; end;
        FAutomationImageId := Target.Id; StartSceneImageAi(Target.Id); FAutomationRunPhase := 8;
        AutomationRunEvent('images','progress',Target.Title+'の画像生成を開始しました。');
      end;
      8: begin
        if SceneImageAiBusy then Exit;
        if not FImageAiSucceeded then raise Exception.Create(FImageAiMessage);
        SetScriptSceneApproved(FAutomationImageId,True); SaveScriptDraft(False);
        AutomationRunEvent('images','completed',FScriptDraft.ImageTarget(FAutomationImageId).Title+'の画像を検査し、自動採用しました。');
        FAutomationRunPhase := 7;
      end;
      9: begin
        if (FActive=nil) or (FActive.Project.Id<>JS(FAutomationRun,'projectId')) then raise Exception.Create('動画編集への引渡し先が一致しません。');
        var Folder := TPath.Combine(ExtractFileDir(FActive.Project.FileName),'Exports'); ForceDirectories(Folder);
        var Video := TPath.Combine(Folder,MovieExportName(FActive.Project.Title)+'.mp4');
        PsdJson.Put(FAutomationRun,'videoPath',Video);
        var O := MovieCommand('export',TJSONObject.Create.AddPair('path',Video));
        try FAutomationExportId := JS(O,'jobId',JS(O,'id')); finally O.Free; end;
        AutomationRunEvent('mp4','started','MP4を書き出しています。'); FAutomationRunPhase := 10;
      end;
      10: begin
        if (FActive=nil) or (FActive.Project.Id<>JS(FAutomationRun,'projectId')) then raise Exception.Create('動画出力の対象が切り替わりました。');
        var O := MovieCommand('job-status',TJSONObject.Create.AddPair('jobId',FAutomationExportId));
        try
          if not JB(O,'done') then Exit;
          if JS(O,'state')<>'succeeded' then raise Exception.Create('MP4出力に失敗しました：'+JS(O,'error'));
        finally O.Free; end;
        var Video := JS(FAutomationRun,'videoPath');
        if not FileExists(Video) or (TFile.GetSize(Video)<32) then raise Exception.Create('出力MP4を確認できません。');
        PsdJson.Put(FAutomationRun,'videoSha256',THashSHA2.GetHashStringFromFile(Video));
        AutomationRunEvent('mp4','completed','MP4が完成しました：'+Video); FAutomationRunPhase := 11;
      end;
      11: begin
        var Info := MoviePostingInfo(FActive.Project);
        try
          PsdJson.Put(Info,'title','【'+ScriptTypeName(JS(Data,'scriptType'))+'】'+JS(Data,'title'));
          var Description := MoviePostingDescription(FActive.Project);
          if Description='' then begin
            Description := JS(Data,'title');
            if JS(Data,'workUrl')<>'' then Description := Description+#13#10+JS(Data,'workUrl');
            Description := Description+#13#10+#13#10+JS(JO(Data,'summary'),'body');
          end;
          PsdJson.Put(Info,'description',Description); ValidateMoviePosting(Info);
          var O := MovieCommand('update-posting',TJSONObject.Create.AddPair('projectId',FActive.Project.Id)
            .AddPair('revision',TJSONNumber.Create(FActive.Project.Revision)).AddPair('title',JS(Info,'title')).AddPair('description',Description)); O.Free;
          var Path := TPath.Combine(ExtractFileDir(JS(FAutomationRun,'videoPath')),'投稿用テキスト.txt');
          if FileExists(Path) then raise Exception.Create('投稿用テキストの出力先が既に存在します。');
          TFile.WriteAllText(Path,JS(Info,'title')+#13#10+#13#10+Description+#13#10+#13#10+MovieParentWorks+#13#10,TEncoding.UTF8);
          PsdJson.Put(FAutomationRun,'textPath',Path); PsdJson.Put(FAutomationRun,'textSha256',THashSHA2.GetHashStringFromFile(Path));
          if not SameText(JS(FAutomationRun,'sourceSha256'),THashSHA2.GetHashStringFromFile(JS(JO(FAutomationRun,'source'),'path'))) then raise Exception.Create('制作中にコピー元が更新されました。完成データを保持して停止します。');
          PersistProjectState('completed');
        finally Info.Free; end;
        PsdJson.Put(FAutomationRun,'productionCompleted',TJSONBool.Create(True)); PsdJson.Put(FAutomationRun,'state','completed');
        AutomationRunEvent('posting','completed','タイトル・概要・親作品情報を1つのテキストへ出力しました。');
        AutomationRunEvent('production','completed','MP4と投稿用テキストの作成が完了しました。');
        FAutomationRunPhase := 0; FreeAndNil(FAutomationSource);
      end;
    end;
  except on E: Exception do begin
    if ExpressionAiBusy then CancelExpressionAi;
    if SceneImageAiBusy then CancelSceneImageAi;
    if VoiceBusy then CancelVoice;
    PsdJson.Put(FAutomationRun,'state','failed');
    JA(FAutomationRun,'issues').AddElement(TJSONObject.Create.AddPair('stage',JS(FAutomationRun,'stage')).AddPair('message',E.Message));
    try PersistProjectState('failed'); except on Saved: Exception do PsdJson.Put(FAutomationRun,'projectStateSaveError',Saved.Message); end;
    try AutomationRunEvent(JS(FAutomationRun,'stage'),'failed',E.Message);
    except on LogError: Exception do PsdJson.Put(FAutomationRun,'logWriteError',LogError.Message); end;
    FAutomationRunPhase := 0;
  end; end;
end;
