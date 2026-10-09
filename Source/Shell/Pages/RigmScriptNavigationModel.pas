unit RigmScriptNavigationModel;
interface
uses System.JSON;
const ScriptStages: array[0..15] of string = (
  'title','characters','layout','placement','text','review','casting','subtitles',
  'voice','voice-effects','scene-assignment','scenes','summary','summary-edit','closing','editor');
function ScriptNextStage(const Stage: string; Wizard: TJSONObject): string;
function ScriptStageCaption(const Stage: string): string;
function ScriptCanAdvance(State: TJSONObject): Boolean;
function ScriptStageAvailable(State: TJSONObject; const Stage: string): Boolean;
function ScriptVisibleStages(State: TJSONObject): TArray<string>;
implementation
uses System.SysUtils, System.Math, RigmJson, RigmScriptPlacementModel;
function ScriptStageCaption(const Stage: string): string;
begin
  if Stage='editor' then Result := '動画編集'
  else Result := '第'+(ScriptStageIndex(Stage)+1).ToString+'段階  '+ScriptStageName(Stage);
end;
function ScriptNextStage(const Stage: string; Wizard: TJSONObject): string;
begin
  Result := '';
  if (Stage='scenes') or (Stage='closing') then Exit('editor');
  if Stage='summary' then begin
    if JS(Wizard,'summaryChoice')='none' then Result := 'closing'
    else if JS(Wizard,'summaryChoice')='yes' then Result := 'summary-edit';
  end
  else if Stage='summary-edit' then Result := 'voice'
  else if (Stage='voice-effects') and (JS(Wizard,'voiceReturnStage')='closing') then Result := 'closing'
  else begin
    var Index := ScriptStageIndex(Stage);
    if (Index>=0) and (Index<ScriptStageIndex('scenes')) then Result := ScriptStages[Index+1];
  end;
end;
function ScriptCanAdvance(State: TJSONObject): Boolean;
begin
  Result := JB(State,'canAdvance') or JB(State,'canConfirmVoice') or JB(State,'canConfirmSubtitles');
end;
function ScriptStageAvailable(State: TJSONObject; const Stage: string): Boolean;
begin
  if not JB(State,'hasProject') then Exit(False);
  if (State.GetValue('researchReady')<>nil) and not JB(State,'researchReady') and
    (ScriptStageIndex(Stage)>ScriptStageIndex('review')) then Exit(False);
  var Wizard := JO(State,'wizard'); var Current := JS(Wizard,'stage');
  if Stage=Current then Exit(True);
  if Stage=ScriptNextStage(Current,Wizard) then Exit(ScriptCanAdvance(State));
  var Index := ScriptStageIndex(Stage);
  var Reached := Max(ScriptStageIndex(Current),ScriptStageIndex(JS(Wizard,'furthestStage',JS(State,'resumeStage'))));
  Result := (Index>=0) and (Index<=Reached) and (Stage<>'editor');
  if not Result then Exit;
  if (Current='review') and (Index>ScriptStageIndex('review')) and not ScriptCanAdvance(State) then Exit(False);
  if (Index>ScriptStageIndex('casting')) and not JB(State,'castingReady') then Exit(False);
  if (Current='subtitles') and (Index>ScriptStageIndex(Current)) and not JB(State,'canAdvance') then Exit(False);
  if (Current='scene-assignment') and (Index>ScriptStageIndex(Current)) then Exit(False);
  if (Index>=ScriptStageIndex('scenes')) and (JS(Wizard,'scene-assignmentStatus')<>'complete') then Exit(False);
  if (Index>ScriptStageIndex('scenes')) and (Wizard.GetValue('scenes')<>nil) and not JB(JO(Wizard,'scenes'),'allApproved') then Exit(False);
end;
function ScriptVisibleStages(State: TJSONObject): TArray<string>;
begin
  Result := nil;
  if not JB(State,'hasProject') then Exit;
  var Wizard := JO(State,'wizard'); var Current := JS(Wizard,'stage');
  var Reached := Max(ScriptStageIndex(Current),ScriptStageIndex(JS(Wizard,'furthestStage',JS(State,'resumeStage'))));
  var Next := ScriptNextStage(Current,Wizard);
  for var Stage in ScriptStages do begin
    var Seen := (ScriptStageIndex(Stage)<=Reached) and (Stage<>'editor');
    // 総評入力を飛ばした旧台本には、まだ存在しない総評画面を追加しない。
    if (Stage='summary-edit') and (Wizard.GetValue('summaryData')=nil) then Seen := False;
    if Seen or (Stage=Current) or ((Stage=Next) and ScriptCanAdvance(State)) then begin
      SetLength(Result,Length(Result)+1); Result[High(Result)] := Stage;
    end;
  end;
end;
end.
