// 境界の局所更新・所有一覧の応答・工程移動だけでの保存を調べる。
procedure CheckSceneAssignmentChanges;
begin
  var Indices := ScriptSceneAssignmentCueIndices(W.ScriptDraft);
  var Id := W.ScriptDraft.Cues[Indices[2]].Id;
  var OriginalStart := ScriptSceneStartsAt(W.ScriptDraft,Indices[2]);
  var List := StageFrame(TRigmScriptSceneAssignmentFrame).FindComponent('ScriptSceneAssignmentRows') as TListView;
  var Probe := TAccentRefreshProbe.Create; Probe.Previous := W.OnScriptChanged; W.OnScriptChanged := Probe.Changed;
  var Started := GetTickCount64;
  try
    for var I := 0 to 19 do List.Items[2].Checked := not List.Items[2].Checked;
    var Elapsed := GetTickCount64-Started;
    Check((Elapsed<1500) and (Probe.Count=0),'twenty native scene check toggles avoid synchronous whole-wizard refreshes');
    Sleep(350); Application.ProcessMessages;
    Check((Probe.Count=1) and (ScriptSceneStartsAt(W.ScriptDraft,Indices[2])=OriginalStart),
      'scene checkbox updates immediately and coalesces its navigation notification once');
    TFile.WriteAllText(TPath.Combine(Root,'scene-checkbox-metrics.json'),'{"toggles":20,"elapsedMs":'+Elapsed.ToString+'}',TEncoding.UTF8);
  finally W.OnScriptChanged := Probe.Previous; Probe.Free; end;
  List.Items[2].Checked := not OriginalStart;
  var ExpectedScene := W.ScriptDraft.Cue(Id).Scene;
  Creator.SetActive(False); Go('voice-effects');
  var Fresh := TRigmWizardWorkspace.Create(nil);
  try
    Fresh.StartPipe(Main.DataRoot); Fresh.OpenWork(W.ScriptDraft.FileName);
    Check((Fresh.CurrentScriptStage='voice-effects') and (Fresh.ScriptDraft.Cue(Id).Scene=ExpectedScene),
      'moving backward to an existing stage saves both the scene assignment and destination before restart');
  finally Fresh.Free; end;
  Go('scene-assignment'); Go('scenes');
  Fresh := TRigmWizardWorkspace.Create(nil);
  try
    Fresh.StartPipe(Main.DataRoot); Fresh.OpenWork(W.ScriptDraft.FileName);
    Check((Fresh.CurrentScriptStage='scenes') and (Fresh.ScriptDraft.Cue(Id).Scene=ExpectedScene) and
      (JS(Fresh.ScriptDraft.ScriptWizard,'scene-assignmentStatus')='complete'),
      'advancing to scene images saves the checked boundary and confirmation without an explicit save');
  finally Fresh.Free; end;
  Go('scene-assignment');
  var P := W.ScriptDraft.Clone;
  try
    var Body := ''; for var I := 0 to 299 do begin
      if I>0 then Body := Body+#13#10;
      if (I>0) and (I mod 5=0) then Body := Body+#13#10;
      Body := Body+'性能検証のセリフ '+I.ToString+'。';
    end;
    PsdJson.Put(ScriptSection(P,'body'),'text',Body); InvalidateScriptCasting(P); PrepareScriptCasting(P);
    PrepareScriptScenes(P,False); ValidateScriptSceneAssignment(P);
    for var S in P.Scenes do begin S.ImagePrompt := StringOfChar('図',8000); S.Padding := 0.5; end;
    var Target := P.Cues[3]; var Untouched := P.Scenes[P.Scenes.Count-1]; var UntouchedJson := Untouched.Json;
    var OriginalCue := Target.Json; var Left := P.Scene(P.Cues[2].Scene); var Padding := Left.Padding;
    var Metrics := TJSONObject.Create;
    try
      var Before := P.Clone; SaveMovie(Before,TPath.Combine(Root,'scene-benchmark-input.rigmovie')); Before.Free;
      Started := GetTickCount64;
      for var I := 0 to 39 do SetScriptSceneStart(P,Target.Id,I mod 2=0);
      var Elapsed := GetTickCount64-Started; AddN(Metrics,'cues',P.Cues.Count); AddN(Metrics,'scenes',P.Scenes.Count);
      AddN(Metrics,'toggles',40); AddN(Metrics,'elapsedMs',Elapsed);
      TFile.WriteAllText(TPath.Combine(Root,'scene-model-metrics.json'),Metrics.ToJSON,TEncoding.UTF8);
      Check(Elapsed<2500,'three hundred speeches and large scene prompts toggle forty times within the interaction budget');
      Check((P.Scene(Untouched.Id)=Untouched) and (Untouched.Json.ToJSON=UntouchedJson.ToJSON),
        'scene boundary editing retains unrelated scene instances and their image metadata');
      Check((P.Scene(P.Cues[2].Scene).Padding=Padding) and (Target.Json.ToJSON=OriginalCue.ToJSON),
        'split and merge restore padding while preserving dialogue and audio fields');
      ValidateScriptSceneAssignment(P);
    finally Metrics.Free; OriginalCue.Free; UntouchedJson.Free; end;
  finally P.Free; end;
end;
