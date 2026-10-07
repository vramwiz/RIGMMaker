program RigmScriptLineValidation;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash,
  RigmMovieModel, RigmScriptCastingModel, RigmScriptTextModel, RigmScriptReviewModel, RigmJson, PsdJson;
var Checks: Integer;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Inc(Checks); end;
procedure CheckProtected(Original: TRigmMovieProject; Kind: Integer);
begin
  var P := Original.Clone;
  try
    var C := P.Cues[0]; var Row := CastingRow(P,C.Id);
    case Kind of
      0: begin PsdJson.Put(Row,'role',TJSONNumber.Create(1)); PsdJson.Put(Row,'confirmed',TJSONBool.Create(True)); C.SpeakerId := JS(CastingRole(P,1),'speakerId'); end;
      1: begin PsdJson.Put(Row,'role',TJSONNumber.Create(1)); PsdJson.Put(Row,'origin','ai'); C.SpeakerId := JS(CastingRole(P,1),'speakerId'); end;
      2: C.Subtitle := '独立字幕'+#13#10+'表示だけの折り返し';
      3: begin C.WaveFile := 'existing.wav'; C.LabFile := 'existing.lab'; C.AudioKey := 'existing-key'; end;
      4: C.VoiceReading := '既存の読み';
      5: PsdJson.Put(P.ScriptWizard,'stage','editor');
    end;
    var Before := P.Json;
    try Check(not UpgradeScriptCastingLines(P),'protected work must not migrate'); var After := P.Json;
      try Check(Before.ToJSON=After.ToJSON,'protected work changed'); finally After.Free; end;
    finally Before.Free; end;
  finally P.Free; end;
end;
begin
  try
    var OriginalHash := THashSHA2.GetHashStringFromFile(ParamStr(1)); var Original := LoadMovie(ParamStr(1));
    try
      Check(Original.Cues.Count=1,'legacy sample must have one cue');
      for var Kind := 0 to 5 do CheckProtected(Original,Kind);
      var P := Original.Clone;
      try
        var Source := ScriptFingerprint(P); var SceneId := P.Scenes[0].Id; var FirstId := P.Cues[0].Id;
        P.Scenes[0].Description := '保持するシーン説明';
        Check(UpgradeScriptCastingLines(P),'legacy casting must migrate');
        Check((P.Cues.Count=13) and (P.Scenes.Count=1),'13 lines must share the original scene');
        Check((P.Cues[0].Id=FirstId) and (P.Scenes[0].Id=SceneId) and (P.Scenes[0].Description='保持するシーン説明'),'existing cue ID and scene data retained');
        Check(ScriptFingerprint(P)=Source,'raw script and line breaks retained');
        var Text := JS(ScriptSection(P,'body'),'text');
        for var C in P.Cues do begin
          var Row := CastingRow(P,C.Id);
          Check((C.Scene=SceneId) and not C.Text.Contains(#13#10) and (Trim(C.Text)<>'') and
            (C.Text=Text.Substring(JI(Row,'offset'),JI(Row,'length'))),'line anchor or scene mismatch');
        end;
        Check(not UpgradeScriptCastingLines(P),'migration must be idempotent');
        AssignScriptCasting(P,P.Cues[0].Id,1,False); AssignScriptCasting(P,P.Cues[1].Id,2,False);
        Check(P.Cues[0].SpeakerId<>P.Cues[1].SpeakerId,'each line can have a different speaker');
        Check(JB(CastingRow(P,P.Cues[0].Id),'confirmed') and JB(CastingRow(P,P.Cues[1].Id),'confirmed'),'line assignments confirmed independently');
        var Saved := TPath.Combine(ParamStr(2),'line-resume.rigmovie'); SaveMovie(P,Saved,False);
        var Reopened := LoadMovie(Saved);
        try Check((Reopened.Cues.Count=13) and (Reopened.Scenes.Count=1) and
          (JS(Reopened.ScriptWizard,'stage')='casting') and not UpgradeScriptCastingLines(Reopened),'saved casting must resume without repeated migration');
          Check(ScriptFingerprint(Reopened)=Source,'reopened raw source retained');
          Check((JI(CastingRow(Reopened,Reopened.Cues[0].Id),'role')=1) and (JI(CastingRow(Reopened,Reopened.Cues[1].Id),'role')=2),'independent speakers retained on reopen');
        finally Reopened.Free; end;
      finally P.Free; end;
      P := Original.Clone;
      try
        P.ScriptWizard.RemovePair('casting').Free;
        var Text := '一行目。'+#13#10+' '+#13#10+'二行目'+Char($D83D)+Char($DE00)+'。'+#13#10+#13#10+'三行目。';
        PsdJson.Put(ScriptSection(P,'body'),'text',Text); PrepareScriptCasting(P);
        Check((P.Cues.Count=3) and (P.Scenes.Count=2),'empty lines must not create cues; paragraph scenes retained');
        Check((P.Cues[0].Scene=P.Cues[1].Scene) and (P.Cues[1].Scene<>P.Cues[2].Scene),'one scene may contain multiple lines');
        for var C in P.Cues do Check(Trim(C.Text)<>'','blank cue created');
        P.ScriptWizard.RemovePair('casting').Free;
        Text := StringOfChar(Char($3042),1999)+Char($D83D)+Char($DE00)+StringOfChar(Char($3044),2000);
        PsdJson.Put(ScriptSection(P,'body'),'text',Text); PrepareScriptCasting(P);
        Check((P.Cues.Count=3) and (P.Scenes.Count=1),'long line must retain the 2000 UTF16 limit');
        var Joined := ''; for var C in P.Cues do begin Joined := Joined+C.Text; Check(Length(C.Text)<=2000,'cue exceeds voice limit'); end;
        Check(Joined=Text,'surrogate-safe chunks must retain the complete line');
      finally P.Free; end;
      Check(THashSHA2.GetHashStringFromFile(ParamStr(1))=OriginalHash,'original sample file changed');
    finally Original.Free; end;
    Writeln('PASS ',Checks,' focused line/casting/resume checks');
  except on E: Exception do begin Writeln('FAIL: ',E.Message); Halt(1); end; end;
end.
