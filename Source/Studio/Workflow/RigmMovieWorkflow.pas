// 制作工程の遷移条件と不足項目を定義する。工程操作の実行はセッションが担当する。
unit RigmMovieWorkflow;
interface
uses System.JSON, RigmMovieModel;
function MovieStageIndex(const Stage: string): Integer;
function MovieStageName(Index: Integer): string;
function MovieFileIdentity(const Path: string): string;
function MovieRenderKey(Project: TRigmMovieProject): string;
function MovieWorkflow(Project: TRigmMovieProject; Preparation: TJSONObject;
  PreviewCurrent,VideoCurrent,Busy: Boolean; const RejectedJob: string): TJSONObject;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.Math, System.StrUtils,
  System.Generics.Collections, RigmJson;
const Stages: array[0..5] of string = ('script','setup','audio','preview','export','complete');
      Titles: array[0..5] of string = ('台本','設定・素材・声','音声','演技・プレビュー','動画出力','完成');
var FileHashes: TDictionary<string,string>;
function MovieStageIndex(const Stage: string): Integer;
begin Result := -1; for var I := 0 to High(Stages) do if Stage=Stages[I] then Exit(I); end;
function MovieStageName(Index: Integer): string;
begin Result := Stages[EnsureRange(Index,0,High(Stages))]; end;
function MovieFileIdentity(const Path: string): string;
begin
  if Path='' then Exit(''); if Path='@sample' then Exit(Path);
  if not FileExists(Path) then Exit('missing:'+Path);
  var Stamp := Path+'|'+TFile.GetSize(Path).ToString+'|'+FormatDateTime('yyyymmddhhnnsszzz',TFile.GetLastWriteTimeUtc(Path));
  if FileHashes.TryGetValue(Stamp,Result) then Exit;
  Result := THashSHA2.GetHashStringFromFile(Path);
  if FileHashes.Count>128 then FileHashes.Clear;
  FileHashes.AddOrSetValue(Stamp,Result);
end;
function MovieRenderKey(Project: TRigmMovieProject): string;
  procedure FileValue(O: TJSONObject; const Name: string);
  begin
    var Value := MovieFileIdentity(ResolveMoviePath(Project.FileName,JS(O,Name)));
    if JS(O,Name)='@sample' then Value := '@sample';
    O.RemovePair(Name).Free; O.AddPair(Name,Value);
  end;
begin
  var O := Project.Json;
  try
    for var Key in ['projectId','revision','workflow','engineUrl','ffmpeg','outputTarget'] do O.RemovePair(Key).Free;
    FileValue(O,'character'); if O.GetValue('bgm')<>nil then FileValue(JO(O,'bgm'),'file');
    if O.GetValue('themeBackground')<>nil then FileValue(O,'themeBackground');
    if O.GetValue('characters')<>nil then for var V in JA(O,'characters') do begin
      var Character := TJSONObject(V); FileValue(Character,'file');
      if Character.GetValue('expressions')<>nil then for var Pair in JO(Character,'expressions') do
        if (Pair.JsonValue is TJSONObject) and (TJSONObject(Pair.JsonValue).GetValue('image')<>nil) then FileValue(TJSONObject(Pair.JsonValue),'image');
      if Character.GetValue('motions')<>nil then for var Pair in JO(Character,'motions') do
        for var Frame in JA(TJSONObject(Pair.JsonValue),'frames') do FileValue(TJSONObject(Frame),'image');
    end;
    if O.GetValue('scenes')<>nil then for var V in JA(O,'scenes') do FileValue(TJSONObject(V),'image');
    for var V in JA(O,'cues') do begin
      var Cue := TJSONObject(V); for var Key in ['waveFile','labFile','background'] do FileValue(Cue,Key);
    end;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
end;
function MovieWorkflow(Project: TRigmMovieProject; Preparation: TJSONObject;
  PreviewCurrent,VideoCurrent,Busy: Boolean; const RejectedJob: string): TJSONObject;
var Needs: TJSONArray; Ready,SetupReady,CanRun: Boolean;
  procedure Need(const Code,Message,Action: string);
  begin
    var O := TJSONObject.Create; O.AddPair('code',Code); O.AddPair('message',Message);
    O.AddPair('nextAction',Action); AddB(O,'blocking',True); Needs.AddElement(O);
  end;
begin
  Result := TJSONObject.Create; Needs := TJSONArray.Create; Result.AddPair('needs',Needs);
  Result.AddPair('projectId',Project.Id); AddN(Result,'revision',Project.Revision);
  var Stage := MovieStageIndex(Project.WorkflowStage);
  Result.AddPair('currentStage',Project.WorkflowStage); Result.AddPair('title',Titles[Stage]);
  Result.AddPair('nextStage',MovieStageName(Stage+1)); AddB(Result,'automaticAdvance',False);
  AddB(Result,'requiresHumanConfirmation',False); AddB(Result,'busy',Busy);
  AddB(Result,'canBack',(Stage>0) and not Busy);
  Result.AddPair('runCommand','movie-workflow-run'); Result.AddPair('nextCommand','movie-workflow-next');
  Result.AddPair('backCommand','movie-workflow-back'); Result.AddPair('rejectedJobId',RejectedJob);
  SetupReady := JB(Preparation,'diagnosticsCurrent');
  for var V in JA(Preparation,'issues') do begin
    var Issue := TJSONObject(V); var Code := JS(Issue,'code');
    if JB(Issue,'blocking') and not MatchText(Code,['audio_pending','output_missing','output_exists','output_format','ffmpeg_missing','disk_space_low','output_drive_unavailable','output_path_invalid']) then SetupReady := False;
  end;
  var AudioReady := (Project.Cues.Count>0) and (JI(Preparation,'audioPending')=0);
  Ready := False;
  case Stage of
    0: begin Ready := Project.Cues.Count>0; if not Ready then Need('script_empty','台本を作成・調整してください。','movie-import-script'); end;
    1: begin
      Ready := SetupReady;
      if not JB(Preparation,'diagnosticsCurrent') then Need('diagnostics_stale','接続・素材・声の診断が必要です。','movie-workflow-run');
      for var V in JA(Preparation,'issues') do begin
        var Issue := TJSONObject(V); var Code := JS(Issue,'code');
        if JB(Issue,'blocking') and not MatchText(Code,['audio_pending','output_missing','output_exists','output_format','ffmpeg_missing','disk_space_low','output_drive_unavailable','output_path_invalid']) then Needs.AddElement(Issue.Clone as TJSONObject);
      end;
    end;
    2: begin Ready := AudioReady; if not Ready then Need('audio_stale','未完成または変更された音声を生成してください。','movie-workflow-run'); end;
    3: begin Ready := AudioReady and PreviewCurrent; if not AudioReady then Need('audio_stale','前工程で変更された音声の生成が必要です。','movie-audio-generate'); if not PreviewCurrent then Need('preview_stale','現在の演技・字幕・素材でプレビューを作成してください。','movie-workflow-run'); end;
    4: begin Ready := AudioReady and PreviewCurrent and VideoCurrent; if not AudioReady then Need('audio_stale','前工程の音声が古くなっています。','movie-audio-generate'); if not PreviewCurrent then Need('preview_stale','調整後のプレビューが必要です。','movie-preview'); if not VideoCurrent then Need('video_stale','現在の内容を新しいファイルへ出力してください。','movie-workflow-run'); end;
    5: begin Ready := AudioReady and PreviewCurrent and VideoCurrent; if not Ready then Need('results_stale','変更に対応する工程へ戻り、必要な結果を再生成してください。','movie-workflow-back'); end;
  end;
  if (Stage>=2) and not SetupReady then begin
    Ready := False;
    if not JB(Preparation,'diagnosticsCurrent') then Need('diagnostics_stale','変更後の接続・素材・演技の診断が必要です。','movie-diagnostics-refresh');
    for var V in JA(Preparation,'issues') do begin
      var Issue := TJSONObject(V);
      if JB(Issue,'blocking') and MatchText(JS(Issue,'code'),['material_invalid','acting_unavailable','background_missing','speaker_unavailable','engine_unavailable','engine_unchecked','script_empty']) then Needs.AddElement(Issue.Clone as TJSONObject);
    end;
  end;
  if (Stage=4) and not VideoCurrent then
    for var V in JA(Preparation,'issues') do begin
      var Issue := TJSONObject(V); if JB(Issue,'blocking') and (JS(Issue,'scope')='output') then Needs.AddElement(Issue.Clone as TJSONObject);
    end;
  CanRun := not Busy and (Stage<5);
  if Stage=2 then CanRun := CanRun and (JB(Preparation,'canGenerateAudio') or AudioReady);
  if Stage=3 then CanRun := CanRun and AudioReady and JB(Preparation,'canPreview');
  if Stage=4 then CanRun := CanRun and PreviewCurrent and JB(Preparation,'canExport');
  AddB(Result,'canRun',CanRun);
  AddB(Result,'ready',Ready); AddB(Result,'canNext',Ready and not Busy and (Stage<5));
  var Commands := TJSONArray.Create; Result.AddPair('allowedCommands',Commands);
  if not Busy then begin
    Commands.Add('movie-update-project'); Commands.Add('movie-update-cue'); Commands.Add('movie-update-speaker');
    if not JB(Preparation,'diagnosticsCurrent') then Commands.Add('movie-diagnostics-refresh');
    if CanRun then Commands.Add('movie-workflow-run'); if Ready and (Stage<5) then Commands.Add('movie-workflow-next'); if Stage>0 then Commands.Add('movie-workflow-back');
  end else Commands.Add('movie-job-cancel');
  var Stale := TJSONArray.Create; Result.AddPair('regenerate',Stale);
  if not AudioReady then Stale.Add('audio'); if not PreviewCurrent then Stale.Add('preview'); if not VideoCurrent then Stale.Add('export');
  var Artifacts := TJSONObject.Create; Result.AddPair('results',Artifacts);
  AddB(Artifacts,'audioCurrent',AudioReady); AddB(Artifacts,'previewCurrent',PreviewCurrent); AddB(Artifacts,'videoCurrent',VideoCurrent);
  Artifacts.AddPair('previewPath',Project.PreviewPath); Artifacts.AddPair('videoPath',Project.VideoPath);
  Result.AddPair('message',Titles[Stage]+': '+IfThen(Ready,'結果を調整し、明示的に「次へ」で進めます。','必要な編集・生成を行ってください。'));
end;
initialization FileHashes := TDictionary<string,string>.Create;
finalization FileHashes.Free;
end.
