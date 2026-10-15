// 事前検査は非同期の段階応答を返す。必要条件を満たさなければ元台本を変更しない。
function TRigmWizardWorkspace.AutomationSources(const ScriptType: string): TJSONObject;
begin
  if not MatchStr(ScriptType,['manga-introduction','anime-review']) then raise Exception.Create('種類をmanga-introduction / anime-reviewで指定してください。');
  Result := TJSONObject.Create; var Candidates := TJSONArray.Create; Result.AddPair('candidates',Candidates);
  var Excluded := TJSONArray.Create; Result.AddPair('excluded',Excluded);
  var Offset := 0; var BestDate: TDateTime := -1; var Best: TJSONObject := nil;
  try
    repeat
      var Page := ScriptLibrary(Offset,100);
      try
        for var V in JA(Page,'scripts') do begin
          var Entry := TJSONObject(V); var Reason := '';
          if JS(Entry,'kind')<>'wizard' then Reason := '台本として読み込めません。'
          else if JS(Entry,'scriptType')='' then Reason := '漫画／アニメの種類が未設定です。'
          else if JS(Entry,'scriptType')<>ScriptType then Reason := '指定された種類と異なります。'
          else if (JS(Entry,'automationState')<>'') and (JS(Entry,'automationState')<>'completed') then Reason := '自動制作が完了していない台本です。'
          else if JS(Entry,'state')='in-progress' then Reason := '入力中の台本です。';
          for var Opened in FScriptDrafts do
            if (Opened.Id=JS(Entry,'projectId')) and
              (Opened.Modified or ((Opened=FScriptDraft) and (FPage=apScriptCreate))) then Reason := '現在入力・編集中の台本です。';
          var Stamp: TDateTime := 0;
          if (Reason='') and not TryISO8601ToDate(JS(Entry,'updatedAt'),Stamp,True) then Reason := '更新日時が不正です。';
          if Reason<>'' then begin
            var O := Entry.Clone as TJSONObject; O.AddPair('reason',Reason); Excluded.AddElement(O); Continue;
          end;
          var Candidate := Entry.Clone as TJSONObject; Candidates.AddElement(Candidate);
          if (Best=nil) or (Stamp>BestDate) or ((Stamp=BestDate) and (CompareStr(JS(Candidate,'path'),JS(Best,'path'))<0)) then begin
            Best := Candidate; BestDate := Stamp;
          end;
        end;
        Offset := JI(Page,'nextOffset');
        if Offset>=JI(Page,'total') then Break;
      finally Page.Free; end;
    until False;
    Result.AddPair('scriptType',ScriptType); AddB(Result,'available',Best<>nil);
    if Best<>nil then Result.AddPair('selected',Best.Clone as TJSONValue);
  except Result.Free; raise; end;
end;

function TRigmWizardWorkspace.AutomationSourceCheck(const ScriptType, ProjectId: string): TJSONObject;
begin
  if ProjectId='' then raise Exception.Create('projectIdを指定してください。');
  var Sources := AutomationSources(ScriptType);
  try
    Result := TJSONObject.Create.AddPair('projectId',ProjectId);
    try
      var Entry: TJSONObject := nil; var Eligible := False;
      for var V in JA(Sources,'candidates') do
        if SameText(JS(TJSONObject(V),'projectId'),ProjectId) then begin Entry := TJSONObject(V); Eligible := True; Break; end;
      if Entry=nil then for var V in JA(Sources,'excluded') do
        if SameText(JS(TJSONObject(V),'projectId'),ProjectId) then begin Entry := TJSONObject(V); Break; end;
      AddB(Result,'found',Entry<>nil); AddB(Result,'eligible',Eligible);
      AddB(Result,'selected',Eligible and SameText(JS(JO(Sources,'selected'),'projectId'),ProjectId));
      AddB(Result,'copyValidated',False); AddB(Result,'saved',False);
      if Entry=nil then begin Result.AddPair('message','指定した台本は一覧にありません。'); Exit; end;
      Result.AddPair('source',Entry.Clone as TJSONValue);
      if Eligible then Result.AddPair('message','コピー元候補として選択できます。selectedは種類別の最新候補を示します。')
      else Result.AddPair('message','コピー元候補から除外されています。source.reasonを確認してください。');
      // GUIと同じコピー処理をメモリ上で検証する。保存・画面切替・元台本更新は行わない。
      if JS(Entry,'kind')='wizard' then try
        var FullPath := FPipe.Workspace.Resolve(JS(Entry,'path'));
        var Hash := THashSHA2.GetHashStringFromFile(FullPath);
        var Source := LoadMovie(FullPath);
        try
          CheckScript(Source);
          if not SameText(FullPath,ScriptPath(Source)) then raise Exception.Create('UIDフォルダと保存先が一致しません。');
          Result.AddPair('selectedCharacterCount',TJSONNumber.Create(JA(Source.ScriptWizard,'selectedCharacters').Count));
          Result.AddPair('layoutChoice',JS(Source.ScriptWizard,'layoutChoice'));
          var Copy := CreateScriptCopy(Source,ScriptUtcNow);
          try
            CheckScript(Copy);
            if FileExists(ScriptPath(Copy)) then raise Exception.Create('コピー先のUIDが既に存在します。');
          finally Copy.Free; end;
          if not SameText(Hash,THashSHA2.GetHashStringFromFile(FullPath)) then raise Exception.Create('検査中に元台本が更新されました。再検査してください。');
          PsdJson.Put(Result,'copyValidated',TJSONBool.Create(True));
        finally Source.Free; end;
      except on E: Exception do begin
        PsdJson.Put(Result,'eligible',TJSONBool.Create(False));
        PsdJson.Put(Result,'selected',TJSONBool.Create(False));
        Result.AddPair('copyError',E.Message);
        PsdJson.Put(Result,'message','コピー検証で停止しました。copyErrorを確認してください。');
      end; end;
    except Result.Free; raise; end;
  finally Sources.Free; end;
end;

procedure TRigmWizardWorkspace.AutomationCheckEvent(const Stage,State,Message: string);
begin
  var Events := JA(FAutomationCheck,'events');
  Events.AddElement(TJSONObject.Create.AddPair('sequence',TJSONNumber.Create(Events.Count+1))
    .AddPair('stage',Stage).AddPair('state',State).AddPair('message',Message));
  PsdJson.Put(FAutomationCheck,'stage',Stage); PsdJson.Put(FAutomationCheck,'message',Message);
end;

function TRigmWizardWorkspace.AutomationCommand(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if MatchStr(Name,['start','cancel']) or ((Name='status') and (FAutomationRun<>nil) and
    (JS(Args,'jobId')=JS(FAutomationRun,'jobId'))) then Exit(AutomationRunCommand(Name,Args));
  if Name='validate' then begin
    Result := ValidateAutomationInput(JS(Args,'text'));
    if JB(Result,'valid') then Result.AddPair('message','入力確認完了。事前検査を実行できます。')
    else Result.AddPair('message','入力に不足または不正があります。issuesの全項目を修正してください。');
    Exit;
  end;
  if Name='sources' then Exit(AutomationSources(JS(Args,'scriptType')));
  if Name='source-check' then Exit(AutomationSourceCheck(JS(Args,'scriptType'),JS(Args,'projectId')));
  if Name='check' then begin
    if FAutomationRunPhase<>0 then raise Exception.Create('自動制作は実行中です。');
    if FAutomationCheckPhase<>0 then raise Exception.Create('事前検査は実行中です。');
    if ExpressionAiBusy or SceneImageAiBusy or VoiceBusy or FPlacementEditing then raise Exception.Create('実行中の制作・編集処理を終了してから検査してください。');
    var Input := ValidateAutomationInput(JS(Args,'text'));
    if not JB(Input,'valid') then begin
      Input.AddPair('state','invalid'); Input.AddPair('message','入力に不足または不正があります。制作は開始していません。'); Exit(Input);
    end;
    try
      FreeAndNil(FAutomationCheck);
      FAutomationCheck := TJSONObject.Create.AddPair('jobId',TGUID.NewGuid.ToString)
        .AddPair('operation','preflight').AddPair('state','running')
        .AddPair('productionStarted',TJSONBool.Create(False))
        .AddPair('input',JO(Input,'data').Clone as TJSONValue)
        .AddPair('issues',TJSONArray.Create).AddPair('events',TJSONArray.Create);
      AutomationCheckEvent('input','completed','入力確認完了。コピー元と実行環境を確認します。');
      FAutomationCheckPhase := 1;
      Result := FAutomationCheck.Clone as TJSONObject;
      Result.RemovePair('input').Free;
    finally Input.Free; end;
    Exit;
  end;
  if Name='status' then begin
    if (FAutomationCheck=nil) or (JS(Args,'jobId')<>JS(FAutomationCheck,'jobId')) then raise Exception.Create('unknown_job');
    var After := JI(Args,'afterSequence',0); if After<0 then raise Exception.Create('invalid_sequence');
    Result := FAutomationCheck.Clone as TJSONObject; Result.RemovePair('input').Free;
    var Events := TJSONArray.Create;
    for var V in JA(FAutomationCheck,'events') do
      if JI(TJSONObject(V),'sequence')>After then Events.AddElement(V.Clone as TJSONValue);
    PsdJson.Put(Result,'events',Events); Exit;
  end;
  raise Exception.Create('Unknown automation operation');
end;

procedure TRigmWizardWorkspace.PollAutomationCheck;
  procedure AddIssue(const Field,Code,Message: string);
  begin JA(FAutomationCheck,'issues').AddElement(TJSONObject.Create
    .AddPair('field',Field).AddPair('code',Code).AddPair('message',Message)); end;
begin
  if FAutomationCheckPhase=0 then Exit;
  try
    case FAutomationCheckPhase of
      1: begin
        AutomationCheckEvent('copy-source','started','種類別の最新コピー元を検索しています。');
        var Sources := AutomationSources(JS(JO(FAutomationCheck,'input'),'scriptType'));
        FAutomationCheck.AddPair('sources',Sources);
        if JB(Sources,'available') then AutomationCheckEvent('copy-source','completed','コピー元を選択しました。元台本はまだ変更していません。')
        else begin
          AddIssue('copySource','copy_source_not_found','入力中ではない同種類のコピー元がありません。sources.excludedの理由を確認してください。種類未設定の台本を推測で分類しません。');
          AutomationCheckEvent('copy-source','blocked','コピー元を選べません。');
        end;
        FAutomationCheckPhase := 2;
      end;
      2: begin
        AutomationCheckEvent('runtime','started','MP4用の同梱FFmpeg DLLを確認しています。');
        var Missing := TJSONArray.Create;
        for var Name in ['avutil-60.dll','swresample-6.dll','swscale-9.dll','avcodec-62.dll','avformat-62.dll'] do
          if not FileExists(TPath.Combine(BundledFFmpegDirectory,Name)) then Missing.AddElement(TJSONString.Create(Name));
        FAutomationCheck.AddPair('missingFFmpegDlls',Missing); FAutomationCheck.AddPair('ffmpegDirectory',BundledFFmpegDirectory);
        if Missing.Count>0 then begin
          AddIssue('ffmpeg','ffmpeg_runtime_missing','MP4用の同梱FFmpeg DLLが不足しています。ffmpegDirectoryとmissingFFmpegDllsを確認してください。');
          AutomationCheckEvent('runtime','blocked','MP4用DLLが不足しています。');
        end else AutomationCheckEvent('runtime','completed','必要なDLLファイルの存在を確認しました。ロード・MP4出力の成功を保証する検査ではありません。');
        FAutomationCheckPhase := 0;
        if JA(FAutomationCheck,'issues').Count>0 then begin
          PsdJson.Put(FAutomationCheck,'state','blocked');
          AutomationCheckEvent('preflight','blocked','事前検査で停止しました。台本のコピー・生成・MP4出力は実行していません。');
        end else begin
          PsdJson.Put(FAutomationCheck,'state','ready');
          AutomationCheckEvent('preflight','completed','事前検査完了。検査のみの操作です。制作は開始していません。');
        end;
      end;
    end;
  except on E: Exception do begin
    FAutomationCheckPhase := 0; PsdJson.Put(FAutomationCheck,'state','failed');
    AddIssue('preflight','check_failed',E.Message); AutomationCheckEvent('preflight','failed',E.Message);
  end; end;
end;
