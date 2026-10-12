unit RigmScriptCopyModel;
// コピー元を変更せず、許可された入力だけから新しい台本を作る。
interface
uses RigmMovieModel;
function CreateScriptCopy(Source: TRigmMovieProject; const CreatedAt: string): TRigmMovieProject;
implementation
uses System.SysUtils, System.JSON, RigmJson, PsdJson, RigmScriptTextModel,
  RigmScriptSummaryModel, RigmScriptClosingModel;
function CopyVoiceBinding(Source: TRigmMovieProject; Character: TJSONObject): TJSONObject;
begin
  Result := nil;
  var Speaker: TRigmMovieSpeaker := nil;
  if Source.ScriptWizard.GetValue('casting') is TJSONObject then
    for var V in JA(JO(Source.ScriptWizard,'casting'),'roles') do begin
      var Role := TJSONObject(V);
      if JB(Role,'active') and SameText(JS(Role,'path'),JS(Character,'path')) then
        Speaker := Source.Speaker(JS(Role,'speakerId'));
    end;
  if (Speaker<>nil) and (Speaker.StyleId>=0) and (Speaker.VoiceUuid<>'') then begin
    Result := TJSONObject.Create; Result.AddPair('uuid',Speaker.VoiceUuid);
    Result.AddPair('name',Speaker.VoiceName); AddN(Result,'styleId',Speaker.StyleId);
    Result.AddPair('style',Speaker.StyleName); Exit;
  end;
  if not(Character.GetValue('voiceBinding') is TJSONObject) then Exit;
  var Binding := JO(Character,'voiceBinding');
  if (JI(Binding,'styleId',-1)<0) or (JS(Binding,'uuid')='') then Exit;
  Result := TJSONObject.Create;
  for var Key in ['uuid','name','style'] do Result.AddPair(Key,JS(Binding,Key));
  AddN(Result,'styleId',JI(Binding,'styleId'));
end;
function CreateScriptCopy(Source: TRigmMovieProject; const CreatedAt: string): TRigmMovieProject;
begin
  if (Source=nil) or (Source.ScriptWizard=nil) then raise Exception.Create('コピーする台本を選んでください。');
  Result := TRigmMovieProject.Create;
  try
    Result.ScriptWizard := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptWizard","schemaVersion":1,"flowVersion":2,"stage":"title","furthestStage":"title","titleStatus":"in-progress","scriptType":"","charactersStatus":"in-progress","selectedCharacters":[]}');
    var Target := Result.ScriptWizard;
    Result.Title := Source.Title; Target.AddPair('titleInput',JS(Source.ScriptWizard,'titleInput',Source.Title));
    Target.AddPair('createdAt',CreatedAt); Target.AddPair('updatedAt',CreatedAt);
    var Selected := JA(Target,'selectedCharacters');
    for var V in JA(Source.ScriptWizard,'selectedCharacters') do begin
      var Old := TJSONObject(V); var Item := TJSONObject.Create; Selected.AddElement(Item);
      for var Key in ['path','name','renderFormat'] do Item.AddPair(Key,JS(Old,Key));
      var Binding := CopyVoiceBinding(Source,Old);
      if Binding<>nil then Item.AddPair('voiceBinding',Binding);
    end;
    if Source.ScriptWizard.GetValue('placements') is TJSONArray then begin
      var Placements := TJSONArray.Create; Target.AddPair('placements',Placements);
      for var V in JA(Source.ScriptWizard,'placements') do begin
        var Old := TJSONObject(V); var Item := TJSONObject.Create; Placements.AddElement(Item);
        Item.AddPair('path',JS(Old,'path'));
        for var Key in ['x','y','width','height'] do AddN(Item,Key,JN(Old,Key));
        AddB(Item,'flipX',JB(Old,'flipX'));
      end;
      Target.AddPair('placementStatus','in-progress');
    end;
    PrepareScriptText(Result);
    if Source.ScriptWizard.GetValue('scriptText') is TJSONObject then
      for var V in JA(JO(Source.ScriptWizard,'scriptText'),'sections') do begin
        var Old := TJSONObject(V); var Id := JS(Old,'id'); if Id='body' then Continue;
        var Section := ScriptSection(Result,Id);
        if Section=nil then begin
          Section := TJSONObject.Create; JA(JO(Target,'scriptText'),'sections').AddElement(Section);
          Section.AddPair('id',Id); Section.AddPair('scope',JS(Old,'scope'));
        end;
        PsdJson.Put(Section,'text',JS(Old,'text'));
      end;
    if Source.ScriptWizard.GetValue('summaryData') is TJSONObject then begin
      PrepareScriptSummary(Result);
      var Old := JO(JO(Source.ScriptWizard,'summaryData'),'draft'); var Draft := JO(JO(Target,'summaryData'),'draft');
      for var Key in ['text','subtitle','reading','title'] do PsdJson.Put(Draft,Key,JS(Old,Key));
      var Items := TJSONArray.Create; PsdJson.Put(Draft,'items',Items);
      for var V in JA(Old,'items') do begin
        var Item := TJSONObject.Create; Items.AddElement(Item);
        Item.AddPair('label',JS(TJSONObject(V),'label')); Item.AddPair('value','');
      end;
    end;
    if Source.ScriptWizard.GetValue('closingData') is TJSONObject then begin
      PrepareScriptClosing(Result);
      PsdJson.Put(JO(JO(Target,'closingData'),'draft'),'title',JS(JO(JO(Source.ScriptWizard,'closingData'),'draft'),'title'));
      PsdJson.Put(JO(Target,'closingData'),'titleFollowsProject',TJSONBool.Create(ScriptClosingTitleFollowsProject(Source)));
    end;
    if (Source.ScriptWizard.GetValue('voice') is TJSONObject) and
      (JO(Source.ScriptWizard,'voice').GetValue('commonSettings') is TJSONObject) then begin
      var Settings := TJSONObject.Create;
      var Voice := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptVoice","schemaVersion":1,"selectedCue":""}');
      Target.AddPair('voice',Voice); Voice.AddPair('commonSettings',Settings);
      var Old := JO(JO(Source.ScriptWizard,'voice'),'commonSettings');
      for var Key in ['speedScale','pitchScale','intonationScale','volumeScale','prePhonemeLength','postPhonemeLength'] do
        if Old.GetValue(Key)<>nil then AddN(Settings,Key,JN(Old,Key));
      ValidateVoiceValues(Settings);
    end;
    ValidateScriptText(JO(Target,'scriptText')); Result.Modified := True;
  except Result.Free; raise; end;
end;
end.
