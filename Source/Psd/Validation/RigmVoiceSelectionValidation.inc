// API・GUI・実ファイルを操作しない人物・状態・保存音声移行の検証。
procedure VerifyVoicePersonState(Results: TJSONArray);
  procedure Check(Value: Boolean; const Text: string);
  begin if not Value then raise Exception.Create('Voice selection: '+Text); Results.Add(Text); end;
begin
  var Catalog := TJSONObject.ParseJSONValue('[{"uuid":"person-a","name":"同名人物","style":"怒り","styleId":10},{"uuid":"person-a","name":"同名人物","style":"ノーマル","styleId":0},{"uuid":"person-a","name":"同名人物","style":"喜び","styleId":12},{"uuid":"person-b","name":"同名人物","style":"ささやき","styleId":20}]') as TJSONArray;
  var P := TRigmMovieProject.Create;
  try
    P.ScriptWizard := ParseObject('{"casting":{"roles":[{"number":1,"active":true,"speakerId":"narrator"}]}}');
    var S := P.Speakers[0]; var Other := TRigmMovieSpeaker.Create; Other.Id := 'other'; P.Speakers.Add(Other);
    var A := TRigmMovieCue.Create; A.Text := '最初'; P.Cues.Add(A);
    var B := TRigmMovieCue.Create; B.Text := '次'; P.Cues.Add(B);
    var C := TRigmMovieCue.Create; C.SpeakerId := 'other'; C.Text := '別人'; P.Cues.Add(C);
    Check(Length(VoicePersonIndices(Catalog))=2,'person candidates deduplicate by UUID rather than display name');
    Check((Length(VoiceStateIndices(Catalog,'person-a'))=3) and (Length(VoiceStateIndices(Catalog,''))=0),'states belong only to selected person');
    Check(JI(NormalVoiceStyle(Catalog,'person-a'),'styleId',-1)=0,'normal is selected even after another state and accepts style zero');
    Check(JI(NormalVoiceStyle(Catalog,'person-b'),'styleId',-1)=20,'person without normal uses an actual supported state');
    BindScriptVoicePerson(P,Catalog,1,'person-a');
    Check((S.StyleId=0) and (P.EffectiveStyle(A)=0) and (P.EffectiveStyle(B)=0),'first person binding initializes all cue states to normal');
    A.WaveFile := 'kept.wav'; A.LabFile := 'kept.lab'; A.AudioSeconds := 1; A.AudioKey := 'old-audio'; A.VoiceQuery := 'old-query'; A.VoiceQueryKey := 'old-query-key';
    var OtherJson := B.Json; var OtherPersonJson := C.Json;
    try
      SetScriptVoiceState(P,Catalog,A.Id,12);
      var OtherCueAfter := B.Json; try Check((A.VoiceStyleId=12) and (S.StyleId=0) and (OtherCueAfter.ToJSON=OtherJson.ToJSON),'state edits affect one cue and leave the person default unchanged'); finally OtherCueAfter.Free; end;
      Check((A.VoiceQuery='') and (A.VoiceQueryKey='') and (A.WaveFile='kept.wav') and (A.LabFile='kept.lab') and (A.AudioKey='old-audio'),'changed state invalidates its query and retains previous audio metadata');
      var Snapshot := A.Json;
      try
        var Rejected := False; try SetScriptVoiceState(P,Catalog,A.Id,20); except on E: Exception do Rejected := True; end;
        var After := A.Json; try Check(Rejected and (After.ToJSON=Snapshot.ToJSON),'another person state rejects atomically'); finally After.Free; end;
        var Restored := TRigmMovieCue.FromJson(Snapshot); try Check(Restored.VoiceStyleId=12,'per-cue state survives JSON persistence'); finally Restored.Free; end;
      finally Snapshot.Free; end;
      SetScriptVoiceState(P,Catalog,A.Id,0); Check((A.VoiceStyleId=-1) and (P.EffectiveStyle(A)=0),'returning to normal restores the person default');
      SetScriptVoiceState(P,Catalog,A.Id,10); BindScriptVoicePerson(P,Catalog,1,'person-b');
      var OtherAfter := C.Json; try Check((A.VoiceStyleId=-1) and (B.VoiceStyleId=-1) and (OtherAfter.ToJSON=OtherPersonJson.ToJSON),'person replacement resets own cue states and retains unrelated character'); finally OtherAfter.Free; end;
    finally OtherJson.Free; OtherPersonJson.Free; end;
    S.VoiceUuid := 'person-a'; S.VoiceName := '同名人物'; S.StyleId := 10; S.StyleName := '怒り'; A.VoiceStyleId := -1; B.VoiceStyleId := -1;
    A.VoiceQuery := 'saved-query'; A.VoiceQueryKey := P.VoiceQuerySourceKey(A); A.AudioKey := P.AudioFingerprint(A); B.AudioKey := 'stale-audio';
    NormalizeVoicePeople(P,Catalog);
    Check((S.StyleId=0) and (P.EffectiveStyle(A)=10) and (P.EffectiveStyle(B)=10),'legacy default state moves to existing cues while new default becomes normal');
    Check((A.AudioKey=P.AudioFingerprint(A)) and (B.AudioKey='stale-audio') and (P.EffectiveVoiceQuery(A)='saved-query'),'migration preserves current audio and query without promoting stale audio');
    var NewCue := TRigmMovieCue.Create; NewCue.Text := '追加'; P.Cues.Add(NewCue); Check(P.EffectiveStyle(NewCue)=0,'new cue defaults to normal after legacy migration');
  finally P.Free; Catalog.Free; end;
end;
