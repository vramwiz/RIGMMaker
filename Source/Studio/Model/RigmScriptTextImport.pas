unit RigmScriptTextImport;

// 第一段階の原稿取込。呼出側のsnapshotだけを変更し、生成・採用・工程移動は行わない。
interface
uses System.JSON, RigmMovieModel;
function ScriptTextInputTemplate: string;
function ReadScriptTextInputFile(const FileName: string): string;
function ImportedScriptBody(Data: TJSONObject): string;
procedure ApplyScriptTextInput(Project: TRigmMovieProject; Data: TJSONObject; const SourceName: string);
procedure ApplyImportedSceneInputs(Project: TRigmMovieProject);
procedure ApplyImportedDialogueInputs(Project: TRigmMovieProject; Data: TJSONObject; AppliedCueIds: TJSONArray);
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.Generics.Collections, Winapi.Windows, RigmJson, PsdJson,
  RigmScriptTextModel, RigmScriptSummaryModel, RigmScriptClosingModel,
  RigmScriptCastingModel, RigmScriptSceneAssignmentModel, RigmScriptScenesModel,
  RigmMoviePosting, RigmScriptTypes;

function ScriptTextInputTemplate: string;
begin
  Result := '作品名：'+#13#10+'種類：アニメ／漫画'+#13#10+'ニコニコ漫画の作品URL：'+#13#10+#13#10+
    '*前段'+#13#10+'画像：'+#13#10+'表示：'+#13#10+'本文：'+#13#10+'字幕：'+#13#10+'読み：'+#13#10+#13#10+
    '*背景'+#13#10+'画像：'+#13#10+#13#10+
    '*シーン名'+#13#10+'画像：'+#13#10+'表示：'+#13#10+'本文：'+#13#10+'字幕：'+#13#10+'読み：'+#13#10+#13#10+
    '*総評'+#13#10+'ストーリー：'+#13#10+'キャラクター：'+#13#10+'作画：'+#13#10+
    '演出・テンポ：'+#13#10+'世界観・設定：'+#13#10+'本文：'+#13#10+'字幕：'+#13#10+'読み：'+#13#10+#13#10+
    '*締め'+#13#10+'画像：'+#13#10+'表示：'+#13#10+'本文：'+#13#10+'字幕：'+#13#10+'読み：'+#13#10+#13#10+
    '*投稿情報'+#13#10+'タイトル：'+#13#10+'概要：'+#13#10;
end;

function ReadScriptTextInputFile(const FileName: string): string;
begin
  if not FileExists(FileName) then raise Exception.Create('台本テキストファイルが見つかりません。');
  if TFile.GetSize(FileName)>1024*1024 then raise Exception.Create('台本テキストは1MiB以内にしてください。');
  var Bytes := TFile.ReadAllBytes(FileName);
  if Length(Bytes)>1024*1024 then raise Exception.Create('台本テキストは1MiB以内にしてください。');
  var Utf8 := TMBCSEncoding.Create(CP_UTF8,MB_ERR_INVALID_CHARS,0);
  try
    var Encoding: TEncoding := nil;
    var Offset := TEncoding.GetBufferEncoding(Bytes,Encoding,Utf8);
    if Encoding.CodePage=CP_UTF8 then Encoding := Utf8;
    try Result := Encoding.GetString(Bytes,Offset,Length(Bytes)-Offset);
    except on E: EEncodingError do raise Exception.Create('台本テキストをUTF-8またはBOM付きUTF-16で保存してください。'); end;
  finally Utf8.Free; end;
end;

function ImportedScriptBody(Data: TJSONObject): string;
begin
  Result := '';
  for var V in JA(Data,'scenes') do begin
    if Result<>'' then Result := Result+#13#10;
    Result := Result+NormalizeScriptText(JS(TJSONObject(V),'body'));
  end;
end;

procedure ApplyScriptTextInput(Project: TRigmMovieProject; Data: TJSONObject; const SourceName: string);
begin
  var W := Project.ScriptWizard;
  if (W=nil) or (JS(W,'stage')<>'title') or ((Project.Cues.Count<>0) and not (W.GetValue('textImport') is TJSONObject)) or
    ((JS(W,'furthestStage')<>'') and (JS(W,'furthestStage')<>'title')) then
    raise Exception.Create('コピー直後の第1段階で読み込んでください。後工程の台本は変更しません。');
  PrepareScriptText(Project); Project.Title := JS(Data,'title');
  PsdJson.Put(W,'titleInput',Project.Title); PsdJson.Put(W,'titleStatus','in-progress');
  PsdJson.Put(W,'scriptType',JS(Data,'scriptType')); ValidateScriptType(Project);
  PsdJson.Put(ScriptSection(Project,'body'),'text',ImportedScriptBody(Data));
  for var Section in ['opening','closing'] do if Data.GetValue(Section) is TJSONObject then
    PsdJson.Put(ScriptSection(Project,Section),'text',NormalizeScriptText(JS(JO(Data,Section),'body')));
  PrepareScriptSummary(Project);
  var Draft := JO(JO(W,'summaryData'),'draft').Clone as TJSONObject;
  try
    for var Key in ['text','subtitle','reading'] do PsdJson.Put(Draft,Key,NormalizeScriptText(JS(JO(Data,'summary'),'body')));
    PsdJson.Put(Draft,'minimum','0'); PsdJson.Put(Draft,'maximum','5');
    var Items := TJSONArray.Create;
    for var V in JA(JO(Data,'summary'),'items') do
      Items.AddElement(TJSONObject.Create.AddPair('label',JS(TJSONObject(V),'label')).AddPair('value',TJSONObject(V).GetValue('value').Value));
    PsdJson.Put(Draft,'items',Items); SetScriptSummaryDraft(Project,Draft); ConfirmScriptSummaryDraft(Project);
  finally Draft.Free; end;
  PsdJson.Put(W,'summaryChoice','yes');
  var Section := ScriptSection(Project,'summary');
  if Section=nil then begin
    Section := TJSONObject.Create.AddPair('id','summary').AddPair('scope','episode');
    JA(JO(W,'scriptText'),'sections').AddElement(Section);
  end;
  PsdJson.Put(Section,'text',NormalizeScriptText(JS(JO(Data,'summary'),'body')));
  PrepareScriptClosing(Project); SyncScriptClosingTitle(Project,Project.Title);
  var Closing := JO(JO(W,'closingData'),'draft');
  for var Key in ['representativeChoice','endChoice','thumbnailChoice'] do
    if JS(Closing,Key)='' then PsdJson.Put(Closing,Key,'none');
  Project.CommonBackground.ImagePrompt := NormalizeScriptText(JS(Data,'backgroundPrompt'));
  Project.CommonBackground.DisplayMode := 'image';
  if Data.GetValue('posting') is TJSONObject then begin
    var Posting := MoviePostingInfo(Project);
    try
      var Input := JO(Data,'posting');
      if JS(Input,'title')<>'' then PsdJson.Put(Posting,'title',JS(Input,'title'));
      PsdJson.Put(Posting,'description',NormalizeScriptText(JS(Input,'body')));
      ValidateMoviePosting(Posting); Project.Posting.Free; Project.Posting := Posting; Posting := nil;
    finally Posting.Free; end;
  end else if JS(Data,'workUrl')<>'' then begin
    var Posting := MoviePostingInfo(Project);
    PsdJson.Put(Posting,'description',Project.Title+#13#10+JS(Data,'workUrl'));
    Project.Posting.Free; Project.Posting := Posting;
  end;
  ValidateScriptText(JO(W,'scriptText'));
  PsdJson.Put(W,'textStatus','in-progress'); PsdJson.Put(W,'scriptConfirmedFingerprint','');
  PsdJson.Put(W,'textImport',TJSONObject.Create.AddPair('format','RIGMMaker.ScriptTextImport')
    .AddPair('schemaVersion',TJSONNumber.Create(1)).AddPair('sourceName',TPath.GetFileName(SourceName))
    .AddPair('sceneState','pending').AddPair('data',Data.Clone as TJSONObject));
  Project.Changed;
end;

procedure ApplyImportedDialogueInputs(Project: TRigmMovieProject; Data: TJSONObject; AppliedCueIds: TJSONArray);
var Applied: TDictionary<string,Boolean>; Rows: TDictionary<string,TJSONObject>;
  Cues: TDictionary<string,TRigmMovieCue>; SummaryId: string;
  procedure ApplyBlock(Block: TJSONObject; const Section: string; BaseOffset: Integer);
  begin
    if (Block=nil) or not (Block.GetValue('dialogue') is TJSONArray) then Exit;
    var Position := BaseOffset;
    for var V in JA(Block,'dialogue') do begin
      var Entry := TJSONObject(V); var Text := JS(Entry,'subtitle');
      var Offset := Position;
      while Offset<Position+Length(Text) do begin
        var Row: TJSONObject;
        if not Rows.TryGetValue(Section+'|'+Offset.ToString,Row) then Break;
        var C: TRigmMovieCue; if not Cues.TryGetValue(JS(Row,'cueId'),C) then Break;
        var Count := JI(Row,'length');
        if (Count<=0) or (Offset+Count>Position+Length(Text)) or
          (C.Text<>Text.Substring(Offset-Position,Count)) then Break;
        var WholeLine := (Offset=Position) and (Count=Length(Text));
        Inc(Offset,Count);
        if Applied.ContainsKey(C.Id) then Continue;
        // 明示した読みを、手動で分割した複数行へ丸ごと複製しない。
        var Reading := ''; if WholeLine then Reading := JS(Entry,'reading');
        ValidateVoiceReading(Reading);
        var Previous := C.SpokenText;
        C.Subtitle := C.Text; C.VoiceReading := Reading;
        if Previous<>C.SpokenText then begin
          C.VoiceQuery := ''; C.VoiceQueryKey := ''; C.AudioKey := '';
          C.VoiceHeardKey := ''; C.EffectAudioKey := '';
          PsdJson.Put(Project.ScriptWizard,'voiceStatus','in-progress');
        end;
        Applied.Add(C.Id,True); AppliedCueIds.Add(C.Id);
        if Section='summary' then SummaryId := C.Id;
      end;
      Inc(Position,Length(Text)+2);
    end;
  end;
begin
  Applied := TDictionary<string,Boolean>.Create;
  Rows := TDictionary<string,TJSONObject>.Create;
  Cues := TDictionary<string,TRigmMovieCue>.Create;
  try
    SummaryId := '';
    for var V in AppliedCueIds do Applied.AddOrSetValue(V.Value,True);
    for var C in Project.Cues do Cues.Add(C.Id,C);
    for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do begin
      var Row := TJSONObject(V);
      Rows.AddOrSetValue(JS(Row,'section')+'|'+JI(Row,'offset').ToString,Row);
    end;
    for var Section in ['opening','body','summary','closing'] do begin
      var Expected := '';
      if Section='body' then Expected := ImportedScriptBody(Data)
      else if Data.GetValue(Section) is TJSONObject then Expected := JS(JO(Data,Section),'body')
      else Continue;
      // 校正で原稿が変わった区分に、古い位置の読みを再適用しない。
      if JS(ScriptSection(Project,Section),'text')<>Expected then Continue;
      if Section='body' then begin
        var Position := 0;
        for var V in JA(Data,'scenes') do begin
          var Block := TJSONObject(V); ApplyBlock(Block,Section,Position);
          Inc(Position,Length(JS(Block,'body'))+2);
        end;
      end else ApplyBlock(JO(Data,Section),Section,0);
    end;
    if SummaryId<>'' then begin SyncSummarySubtitle(Project,SummaryId); SyncSummaryReading(Project,SummaryId); end;
  finally Cues.Free; Rows.Free; Applied.Free; end;
end;

procedure ApplyImportedSceneInputs(Project: TRigmMovieProject);
  function BlockAt(Data: TJSONObject; Offset: Integer): Integer;
  begin
    var Position := 0; var Scenes := JA(Data,'scenes'); Result := Scenes.Count-1;
    for var I := 0 to Scenes.Count-1 do begin
      Inc(Position,Length(NormalizeScriptText(JS(TJSONObject(Scenes[I]),'body'))));
      if Offset<Position then Exit(I); Inc(Position,2);
    end;
  end;
begin
  var W := Project.ScriptWizard;
  if not (W.GetValue('textImport') is TJSONObject) then Exit;
  var Import := JO(W,'textImport'); var Data := JO(Import,'data');
  if not (Import.GetValue('dialogueCueIds') is TJSONArray) then Import.AddPair('dialogueCueIds',TJSONArray.Create);
  ApplyImportedDialogueInputs(Project,Data,JA(Import,'dialogueCueIds'));
  if JS(ScriptSection(Project,'body'),'text')<>ImportedScriptBody(Data) then begin
    PsdJson.Put(Import,'sceneState','stale'); Exit;
  end;
  var Rows := JA(JO(W,'casting'),'rows'); var Bound := Data.ToJSON;
  for var V in Rows do begin
    var Row := TJSONObject(V); Bound := Bound+'|'+JS(Row,'cueId')+'|'+JS(Row,'section')+'|'+
      JI(Row,'offset').ToString+'|'+JI(Row,'length').ToString;
  end;
  var Key := THashSHA2.GetHashString(Bound);
  if JS(Import,'appliedKey')=Key then Exit;
  var Previous := ''; var PreviousBlock := -2;
  for var I := 0 to Project.Cues.Count-1 do begin
    var C := Project.Cues[I]; if IsScriptSummaryCue(Project,C) then begin Previous := 'summary'; Continue; end;
    var Row := CastingRow(Project,C.Id); var Section := JS(Row,'section'); var Block := -1;
    if Section='body' then Block := BlockAt(Data,JI(Row,'offset'));
    if ScriptSceneStartEditable(Project,I) then SetScriptSceneStart(Project,C.Id,(Section<>Previous) or (Block<>PreviousBlock));
    Previous := Section; PreviousBlock := Block;
  end;
  for var S in Project.Scenes do begin
    var Row: TJSONObject := nil;
    for var C in Project.Cues do if C.Scene=S.Id then begin Row := CastingRow(Project,C.Id); Break; end;
    if Row=nil then Continue;
    if JS(Row,'section')='summary' then Continue; // 総評の表示は独立チャートを保持する。
    var Input: TJSONObject := nil;
    if JS(Row,'section')='body' then begin
      Input := TJSONObject(JA(Data,'scenes')[BlockAt(Data,JI(Row,'offset'))]);
      EditScriptSceneTitle(Project,S.Id,JS(Input,'title'));
    end else if Data.GetValue(JS(Row,'section')) is TJSONObject then Input := JO(Data,JS(Row,'section'));
    if Input<>nil then EditScriptScene(Project,S.Id,JS(Input,'displayText'),JS(Input,'imagePrompt'),
      SceneInputDisplayMode(JS(Input,'imagePrompt'),JS(Input,'displayText')),'below-image');
  end;
  PsdJson.Put(Import,'appliedKey',Key); PsdJson.Put(Import,'sceneState','applied');
end;
end.
