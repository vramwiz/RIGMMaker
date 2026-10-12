unit RigmScriptNavigationModel;
interface
uses System.JSON;
const ScriptStages: array[0..16] of string = (
  'title','characters','layout','placement','text','review','summary','summary-edit','closing',
  'script-confirm','casting','subtitles','voice','voice-effects','scene-assignment','scenes','editor');
function ScriptNextStage(const Stage: string; Wizard: TJSONObject): string;
function ScriptStageCaption(const Stage: string): string;
function ScriptCanAdvance(State: TJSONObject): Boolean;
function ScriptStageBlockReason(State: TJSONObject; const Stage: string; AllowConfirmation: Boolean=True): string;
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
  if Stage='scenes' then Exit('editor');
  if Stage='summary' then begin
    if JS(Wizard,'summaryChoice')='none' then Result := 'closing'
    else if JS(Wizard,'summaryChoice')='yes' then Result := 'summary-edit';
  end
  else if Stage='summary-edit' then Result := 'closing'
  else begin
    var Index := ScriptStageIndex(Stage);
    if (Index>=0) and (Index<ScriptStageIndex('scenes')) then Result := ScriptStages[Index+1];
  end;
end;
function ScriptCanAdvance(State: TJSONObject): Boolean;
begin
  Result := JB(State,'canAdvance') or JB(State,'canConfirmVoice') or JB(State,'canConfirmSubtitles') or JB(State,'canConfirmCasting');
end;
function ScriptStageAvailable(State: TJSONObject; const Stage: string): Boolean;
begin
  Result := ScriptStageBlockReason(State,Stage)='';
end;
function ScriptStageBlockReason(State: TJSONObject; const Stage: string; AllowConfirmation: Boolean): string;
begin
  Result := '';
  if not JB(State,'hasProject') then Exit('台本を開いてください。');
  var Wizard := JO(State,'wizard'); var Current := JS(Wizard,'stage');
  var Index := ScriptStageIndex(Stage); var CurrentIndex := ScriptStageIndex(Current);
  if Index<0 then Exit('工程がありません。');
  // 前工程へ戻って不足を直す操作は、後工程の未完了によって妨げない。
  if Index<=CurrentIndex then Exit;
  var Next := ScriptNextStage(Current,Wizard); var Immediate := Stage=Next;
  var Reached := Max(ScriptStageIndex(Current),ScriptStageIndex(JS(Wizard,'furthestStage',JS(State,'resumeStage'))));
  if not Immediate and ((Index>Reached) or (Stage='editor')) then Exit('先の工程を順に確認してください。');
  if not (JB(State,'canAdvance') or (AllowConfirmation and Immediate and ScriptCanAdvance(State))) then begin
    Result := JS(State,'advanceBlockedReason'); if Result='' then Result := '現在の工程を確認してください。'; Exit;
  end;
  if (Index>=ScriptStageIndex('casting')) and not (AllowConfirmation and Immediate and (Current='script-confirm')) and
    not JB(State,'scriptConfirmed',True) then Exit('台本確認でセリフを確認してください。');
  if (Index>ScriptStageIndex('casting')) and not (Immediate and (Current='casting')) and
    not JB(State,'castingReady') then Exit('配役を確認してください。');
  if (Index>ScriptStageIndex('subtitles')) and not (Immediate and (Current='subtitles')) and
    not JB(State,'subtitlesReady',JS(Wizard,'subtitlesStatus')='complete') then Exit('字幕を確認してください。');
  if (Index>ScriptStageIndex('voice')) and not (Immediate and (Current='voice')) and
    not JB(State,'voiceReady',JS(Wizard,'voiceStatus')='complete') then Exit('全セリフの音声を生成し、最後まで再生してください。');
  if (Index>=ScriptStageIndex('scenes')) and not (AllowConfirmation and Immediate and (Current='scene-assignment')) and
    not JB(State,'assignmentReady',JS(Wizard,'scene-assignmentStatus')='complete') then Exit('シーン割当を確認してください。');
  if (Stage='editor') and not JB(State,'scenesReady',False) then Exit('全シーンを確認してください。');
end;
function ScriptVisibleStages(State: TJSONObject): TArray<string>;
begin
  Result := nil;
  if not JB(State,'hasProject') then Exit;
  var Wizard := JO(State,'wizard'); var Current := JS(Wizard,'stage');
  var Reached := Max(ScriptStageIndex(Current),ScriptStageIndex(JS(Wizard,'furthestStage',JS(State,'resumeStage'))));
  var Next := ScriptNextStage(Current,Wizard);
  for var Stage in ScriptStages do begin
    var Seen := (ScriptStageIndex(Stage)<=Reached) and (Stage<>'editor') and
      ((ScriptStageIndex(Stage)<=ScriptStageIndex(Current)) or ScriptStageAvailable(State,Stage));
    // 総評入力を飛ばした旧台本には、まだ存在しない総評画面を追加しない。
    if (Stage='summary-edit') and (JS(Wizard,'summaryChoice')<>'yes') then Seen := False;
    if Seen or (Stage=Current) or ((Stage=Next) and ScriptStageAvailable(State,Stage)) then begin
      SetLength(Result,Length(Result)+1); Result[High(Result)] := Stage;
    end;
  end;
end;
end.
