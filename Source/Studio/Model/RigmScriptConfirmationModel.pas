unit RigmScriptConfirmationModel;

// 配役の前に四つの台本区分と任意工程の確定条件を検査する。作品・JSONは借用する。
interface
uses RigmMovieModel;
function ScriptConfirmationReason(Project: TRigmMovieProject): string; // 空文字なら配役を準備できる。変更しない。
function ScriptDialogueConfirmed(Project: TRigmMovieProject): Boolean; // 現文の確認指紋。旧配役の正本も受け入れる。
procedure UpgradeScriptFlow(Project: TRigmMovieProject); // 安定した工程IDから到達位置を復元する。素材は変更しない。
implementation
uses System.SysUtils, System.JSON, RigmJson, PsdJson, RigmScriptTextModel,
  RigmScriptReviewModel, RigmScriptSummaryModel, RigmScriptPlacementModel, RigmScriptTypes, RigmAnimeRankingModel;
function ScriptConfirmationReason(Project: TRigmMovieProject): string;
begin
  Result := '';
  if IsAnimeRankingScript(Project) then begin
    Result := AnimeRankingReason(Project); if Result<>'' then Exit;
    Result := ScriptSummaryDraftReason(JO(JO(Project.ScriptWizard,'summaryData'),'draft')); Exit;
  end;
  if IsSingleSceneScript(Project) then begin
    if Trim(JS(ScriptSection(Project,SingleSceneSection(ProjectScriptType(Project))),'text'))='' then
      Result := 'この構成のセリフを入力してください。';
    Exit;
  end;
  if Trim(JS(ScriptSection(Project,'body'),'text'))='' then Exit('本題の台本を入力してください。');
  if not ((JS(Project.ScriptWizard,'summaryChoice')='none') or (JS(Project.ScriptWizard,'summaryChoice')='yes')) then Exit('総評の有無を選んでください。');
  if JS(Project.ScriptWizard,'summaryChoice')='yes' then begin
    try
      var D := JO(JO(Project.ScriptWizard,'summaryData'),'draft');
      if Trim(JS(D,'text'))='' then Exit('総評のセリフを入力してください。');
      var Chart := ScriptSummaryChart(D); Chart.Free;
    except on E: Exception do Exit('第8段階「総評入力・チャート」を確認してください。'+E.Message); end;
  end;
  if not(Project.ScriptWizard.GetValue('closingData') is TJSONObject) or
    (JS(JO(Project.ScriptWizard,'closingData'),'status')<>'complete') then Exit('締め設定の確認完了を押してください。');
end;
function ScriptDialogueConfirmed(Project: TRigmMovieProject): Boolean;
begin
  if not(Project.ScriptWizard.GetValue('scriptText') is TJSONObject) then Exit(False);
  var Fingerprint := ScriptFingerprint(Project);
  Result := JS(Project.ScriptWizard,'scriptConfirmedFingerprint')=Fingerprint;
  if not Result and (Project.ScriptWizard.GetValue('scriptConfirmedFingerprint')=nil) and
    (Project.ScriptWizard.GetValue('casting') is TJSONObject) then begin
    var Cast := JO(Project.ScriptWizard,'casting');
    Result := (JS(Cast,'state')<>'stale') and (JS(Cast,'sourceFingerprint')=Fingerprint);
  end;
end;
procedure UpgradeScriptFlow(Project: TRigmMovieProject);
begin
  if JI(Project.ScriptWizard,'flowVersion')>=2 then Exit;
  var Reached := JS(Project.ScriptWizard,'furthestStage',JS(Project.ScriptWizard,'stage'));
  for var Stage in ['casting','subtitles','voice','voice-effects','scene-assignment','scenes'] do begin
    var Key := Stage; if Stage='voice-effects' then Key := 'voiceEffects';
    if Stage='scene-assignment' then Continue;
    if (Project.ScriptWizard.GetValue(Key)<>nil) and (ScriptStageIndex(Stage)>ScriptStageIndex(Reached)) then Reached := Stage;
  end;
  PsdJson.Put(Project.ScriptWizard,'furthestStage',Reached); PsdJson.Put(Project.ScriptWizard,'flowVersion',TJSONNumber.Create(2));
end;
end.
