// 実音声の代わりに所有WAVを用い、前工程へ戻る編集で無関係な音声が失効しないか調べる。
procedure CheckScriptVoiceReuse;
const
  BodyText = '一行目はそのまま。'+#13#10+'修正する二行目。'+#13#10+'同じ返事。'+#13#10+
    '区切り前半。区切り後半。'+#13#10+'同じ返事。'+#13#10+'最後の一行😀。'+#13#10+'結合の前。'+#13#10+'結合の後。';
  Query = '{"accent_phrases":[{"moras":[{"text":"カ","consonant":"k","consonant_length":0.05,"vowel":"a","vowel_length":0.1,"pitch":5}],"accent":1,"pause_mora":null,"is_interrogative":false}],"speedScale":1,"pitchScale":0,"intonationScale":1,"volumeScale":1,"prePhonemeLength":0.1,"postPhonemeLength":0.1,"outputSamplingRate":24000,"outputStereo":false}';
  function BodyCue(P: TRigmMovieProject; const Text: string): TRigmMovieCue;
  begin
    Result := nil;
    for var C in P.Cues do if (C.Text=Text) and (JS(CastingRow(P,C.Id),'section')='body') then Exit(C);
  end;
  procedure Change(P: TRigmMovieProject; const Text: string);
  begin
    PsdJson.Put(ScriptSection(P,'body'),'text',Text); InvalidateScriptCasting(P); PrepareScriptCasting(P);
    ValidateScriptCasting(P);
    for var V in JA(JO(P.ScriptWizard,'casting'),'rows') do begin
      var R := TJSONObject(V); var C := P.Cue(JS(R,'cueId'));
      Check(C.Text=JS(ScriptSection(P,JS(R,'section')),'text').Substring(JI(R,'offset'),JI(R,'length')),
        'every reconciled row points at its current source text');
    end;
  end;
  procedure CheckKept(Base,P: TRigmMovieProject; const ExceptIds: TArray<string>; const Description: string);
  begin
    var Kept := True;
    for var C in Base.Cues do begin
      var Skip := False; for var Id in ExceptIds do Skip := Skip or (C.Id=Id); if Skip then Continue;
      var Current := P.Cue(C.Id);
      Kept := Kept and (Current<>nil);
      if Current<>nil then Kept := Kept and (Current.Json.ToJSON=C.Json.ToJSON) and P.AudioReady(Current) and P.AudioHeard(Current);
    end;
    Check(Kept,Description);
  end;
begin
  var Base := W.ScriptDraft.Clone;
  try
    PsdJson.Put(ScriptSection(Base,'body'),'text',BodyText); InvalidateScriptCasting(Base); PrepareScriptCasting(Base);
    var Split := BodyCue(Base,'区切り前半。区切り後半。'); SplitCastingRow(Base,Split.Id,Length('区切り前半。'));
    var Merge := BodyCue(Base,'結合の前。'); MergeCastingRow(Base,Merge.Id);
    var Ids: TArray<string>; SetLength(Ids,Base.Cues.Count);
    for var I := 0 to Base.Cues.Count-1 do Ids[I] := Base.Cues[I].Id;
    for var Id in Ids do AssignScriptCasting(Base,Id,1,True);
    var ChangedId := BodyCue(Base,'修正する二行目。').Id;
    var SplitBefore := BodyCue(Base,'区切り前半。').Id; var SplitAfter := BodyCue(Base,'区切り後半。').Id;
    for var C in Base.Cues do begin
      C.Subtitle := '独自字幕：'+C.Text; C.SubtitleNote := '保持するメモ'; C.VoiceReading := '固有の読み'+C.Text;
      C.VoiceQuery := Query; C.VoiceQueryKey := Base.VoiceQuerySourceKey(C);
      C.WaveFile := TPath.Combine(Root,'owned.wav'); C.AudioSeconds := 0.5;
      C.AudioKey := Base.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
    end;
    var P := Base.Clone;
    try
      Change(P,BodyText.Replace('修正する二行目。','修正した二行目。'));
      CheckKept(Base,P,[ChangedId],'one wording edit retains all other cue IDs, voices, accents, subtitles and heard approvals');
      var C := P.Cue(ChangedId);
      Check((C<>nil) and not P.AudioReady(C) and not P.AudioHeard(C) and (C.VoiceQuery='') and (C.VoiceReading='') and
        (C.WaveFile=Base.Cue(ChangedId).WaveFile) and (C.Subtitle=Base.Cue(ChangedId).Subtitle),
        'only changed speech needs regeneration and retains its old asset and independent subtitle');
      Check(not JB(CastingRow(P,ChangedId),'confirmed') and (C.SpeakerId=Base.Cue(ChangedId).SpeakerId),
        'changed speech retains its voice assignment and requests human reconfirmation');
      var Path := TPath.Combine(Root,'voice-reuse-saved.rigmovie'); SaveMovie(P,Path); var Reloaded := LoadMovie(Path);
      try CheckKept(P,Reloaded,[ChangedId],'unchanged audio and accent approval survive save and reload after a script edit'); finally Reloaded.Free; end;
    finally P.Free; end;
    P := Base.Clone;
    try
      Change(P,'新しく追加した行。'+#13#10+BodyText);
      CheckKept(Base,P,[],'leading line insertion preserves shifted audio and custom split and merged boundaries');
      Check((P.Cues.Count=Base.Cues.Count+1) and not P.AudioReady(BodyCue(P,'新しく追加した行。')),
        'line insertion requires new audio for the inserted speech only');
    finally P.Free; end;
    P := Base.Clone;
    try
      PrepareScriptScenes(P,False); SetScriptSceneStart(P,SplitBefore,True);
      var Assigned := P.Clone;
      try
        Change(P,BodyText.Replace('区切り後半。','区切り後半。'+#13#10+'シーン内に追加。'));
        CheckKept(Assigned,P,[],'inserting inside a manually assigned scene keeps all existing voices and boundaries');
        PrepareScriptScenes(P,False); ValidateScriptSceneAssignment(P);
        Check(BodyCue(P,'シーン内に追加。').Scene=P.Cue(SplitAfter).Scene,
          'new speech inherits its adjacent assigned scene without creating a repeated scene block');
      finally Assigned.Free; end;
    finally P.Free; end;
    P := Base.Clone;
    try
      for var Key in ['voice','voiceEffects','subtitles'] do if P.ScriptWizard.GetValue(Key) is TJSONObject then
        PsdJson.Put(JO(P.ScriptWizard,Key),'selectedCue',ChangedId);
      Change(P,BodyText.Replace('修正する二行目。'+#13#10,''));
      CheckKept(Base,P,[ChangedId],'deleting a line preserves all remaining audio including duplicate dialogue');
      Check((P.Cue(ChangedId)=nil) and (P.Cues.Count=Base.Cues.Count-1),'deleted speech leaves the current cue list while prior assets stay on disk');
      var SelectionValid := True;
      for var Key in ['voice','voiceEffects','subtitles'] do if P.ScriptWizard.GetValue(Key) is TJSONObject then
        SelectionValid := SelectionValid and (P.Cue(JS(JO(P.ScriptWizard,Key),'selectedCue'))<>nil);
      Check(SelectionValid,'deleting a selected line repairs saved voice, effect and subtitle selections');
    finally P.Free; end;
    P := Base.Clone;
    try
      Change(P,BodyText.Replace('区切り後半。','区切り後半を修正。'));
      CheckKept(Base,P,[SplitAfter],'editing one manually split part preserves the other part and every unrelated voice');
      Check((P.Cue(SplitBefore)<>nil) and (P.Cue(SplitAfter)<>nil) and not P.AudioReady(P.Cue(SplitAfter)),
        'a changed split part keeps its identity and invalidates only its own audio');
    finally P.Free; end;
    P := Base.Clone;
    try
      Change(P,BodyText.Replace('一行目はそのまま。','一行目を修正。').Replace('最後の一行😀。','最後の一行😀を修正。'));
      CheckKept(Base,P,[BodyCue(Base,'一行目はそのまま。').Id,BodyCue(Base,'最後の一行😀。').Id],
        'separate edits and surrogate characters preserve the intervening duplicate and merged speech');
    finally P.Free; end;
  finally Base.Free; end;
  // 通常の台本確認→配役→字幕→音声のGUI経路でも保存・再利用を検査する。
  var Original := W.ScriptDraft.Clone;
  try
    var ChangedId := '';
    for var V in JA(JO(Original.ScriptWizard,'casting'),'rows') do
      if JS(TJSONObject(V),'section')='body' then begin ChangedId := JS(TJSONObject(V),'cueId'); Break; end;
    var C := Original.Cue(ChangedId); var OldText := JS(ScriptSection(Original,'body'),'text');
    var NewText := OldText.Insert(OldText.IndexOf(C.Text)+Length(C.Text),' 修正。');
    Creator.SetActive(False); Go('script-confirm'); W.SetScriptText('body',NewText); Go('casting'); Go('subtitles'); Go('voice');
    CheckKept(Original,W.ScriptDraft,[ChangedId],'returning through confirmation, casting and subtitles reuses all untouched generated voices');
    var State := W.ScriptStatus;
    try Check(JI(JO(JO(State,'wizard'),'voice'),'ready')=W.ScriptDraft.Cues.Count-1,
      'voice stage reports exactly one generated line requiring regeneration after one script edit'); finally State.Free; end;
    var Requests := TPath.Combine(ExtractFileDir(ParamStr(3)),'requests.txt');
    var BeforeRequests := TFile.ReadAllText(Requests);
    Creator.SetActive(True); W.SelectVoice(ChangedId); Sleep(450); Application.ProcessMessages;
    Check(not W.VoiceBusy and (TFile.ReadAllText(Requests)=BeforeRequests),
      'entering and selecting an edited line does not start VOICEVOX analysis or synthesis');
    W.GenerateVoice(ChangedId,False);
    var Deadline := GetTickCount64+10000;
    repeat
      Sleep(10); Application.ProcessMessages; State := W.VoiceStatus;
      try
        if JS(State,'error')<>'' then raise Exception.Create(JS(State,'error'));
      finally State.Free; end;
      if GetTickCount64>Deadline then raise Exception.Create('Owned playback generation timed out');
    until not W.VoiceBusy;
    State := W.VoiceStatus;
    try TFile.WriteAllText(TPath.Combine(Root,'playback-generation-state.json'),State.ToJSON,TEncoding.UTF8);
      if JS(State,'error')<>'' then raise Exception.Create(JS(State,'error'));
    finally State.Free; end;
    C := W.ScriptDraft.Cue(ChangedId);
    var CueData := C.Json;
    try AddB(CueData,'ready',W.ScriptDraft.AudioReady(C)); CueData.AddPair('fingerprint',W.ScriptDraft.AudioFingerprint(C));
      TFile.WriteAllText(TPath.Combine(Root,'playback-generation-cue.json'),CueData.ToJSON,TEncoding.UTF8);
    finally CueData.Free; end;
    Check(W.ScriptDraft.AudioReady(C) and (W.ScriptDraft.EffectiveVoiceQuery(C)<>''),
      'explicit playback generation adopts both the current audio and its editable accent query');
    CheckKept(Original,W.ScriptDraft,[ChangedId],'explicit generation leaves every unchanged generated voice and heard approval intact');
    var Frame := StageFrame(TRigmScriptVoiceFrame) as TRigmScriptVoiceFrame;
    var Settings := Frame.FindComponent('ScriptVoiceDetails') as TFrameSerifVoicevoxSettings;
    var Accent: TSerifVoicevoxAccentView := nil;
    for var I := 0 to Settings.ComponentCount-1 do if Settings.Components[I] is TSerifVoicevoxAccentView then Accent := TSerifVoicevoxAccentView(Settings.Components[I]);
    var Paint: TSerifVoicevoxAccentPaintControl := nil;
    for var I := 0 to Accent.ComponentCount-1 do if Accent.Components[I] is TSerifVoicevoxAccentPaintControl then Paint := TSerifVoicevoxAccentPaintControl(Accent.Components[I]);
    BeforeRequests := TFile.ReadAllText(Requests);
    Paint.OnReading(Paint,0,'カナ'); Sleep(450); Application.ProcessMessages;
    Check(Accent.RequestFinish and not W.VoiceBusy and (TFile.ReadAllText(Requests)=BeforeRequests) and
      C.VoiceQuery.Contains('_rigm_pending_reading'),'phrase reading edits remain editable and defer engine requests until playback');
    W.GenerateVoice(ChangedId,False); Deadline := GetTickCount64+10000;
    repeat
      Sleep(10); Application.ProcessMessages; State := W.VoiceStatus;
      try if JS(State,'error')<>'' then raise Exception.Create(JS(State,'error')); finally State.Free; end;
      if GetTickCount64>Deadline then raise Exception.Create('Owned reading generation timed out');
    until not W.VoiceBusy;
    State := W.VoiceStatus; State.Free;
    Check(W.ScriptDraft.AudioReady(C) and not C.VoiceQuery.Contains('_rigm_pending_reading') and
      TFile.ReadAllText(Requests).Contains('/accent_phrases?'),'playback resolves deferred phrase readings before generating the replacement audio');
    C.VoiceHeardKey := C.AudioKey;
    var Legacy := W.ScriptDraft.Cues[2];
    Check(W.ScriptDraft.AudioReady(Legacy) and (W.ScriptDraft.EffectiveVoiceQuery(Legacy)=''),
      'legacy generated speech can still be ready without a stored accent query');
    W.GenerateVoice(Legacy.Id,False); Deadline := GetTickCount64+10000;
    repeat
      Sleep(10); Application.ProcessMessages; State := W.VoiceStatus;
      try if JS(State,'error')<>'' then raise Exception.Create(JS(State,'error')); finally State.Free; end;
      if GetTickCount64>Deadline then raise Exception.Create('Owned legacy query generation timed out');
    until not W.VoiceBusy;
    State := W.VoiceStatus; State.Free;
    Check(W.ScriptDraft.AudioReady(Legacy) and (W.ScriptDraft.EffectiveVoiceQuery(Legacy)<>''),
      'playback of a legacy WAV retrieves its missing editable query for that speech only');
    Legacy.VoiceHeardKey := Legacy.AudioKey;
    W.ScriptDraft.Changed; W.CompleteVoice; Go('voice-effects');
    Check(W.CurrentScriptStage='voice-effects','regenerating and confirming only the edited speech unlocks the later stage');
  finally Original.Free; end;
end;
