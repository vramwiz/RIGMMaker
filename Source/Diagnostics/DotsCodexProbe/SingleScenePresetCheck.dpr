program SingleScenePresetCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, Winapi.Windows,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmWizardWorkspace, RigmScriptCreatorFrame, RigmScriptTextFrame,
  RigmScriptConfirmationFrame, RigmScriptScenesFrame,
  RigmMovieModel, RigmMovieComposition, RigmMovieLayout, RigmScriptTypes,
  RigmScriptTextModel, RigmScriptConfirmationModel, RigmScriptReviewModel,
  RigmScriptNavigationModel, RigmScriptCastingModel, RigmScriptVoiceModel,
  RigmScriptScenesModel, RigmScriptSceneAssignmentModel, RigmScriptThumbnailModel,
  RigmScriptCopyModel, RigmScriptAiImages, RigmScriptSubtitleModel, RigmJson, PsdJson;
var Root: string; Checks: Integer;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Inc(Checks); Writeln('PASS ',Message);
end;
procedure Capture(Control: TWinControl; const Name: string);
begin
  var B := TBitmap.Create; var P := TPngImage.Create;
  try
    B.SetSize(Control.Width,Control.Height); Control.PaintTo(B.Canvas,0,0);
    P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally P.Free; B.Free; end;
end;
function Offered(State: TJSONObject; const Id: string): Boolean;
begin Result := False; for var S in ScriptVisibleStages(State) do if S=Id then Exit(True); end;
procedure RunPreset(const Id: string);
begin
  var W := TRigmWizardWorkspace.Create(nil); var Form := TForm.CreateNew(nil);
  var DataRoot := TPath.Combine(Root,Id);
  var Section := SingleSceneSection(Id);
  try
    W.StartPipe(DataRoot); W.NewScriptDraft; W.SetScriptTitle('共通構成の検証');
    Form.SetBounds(0,0,1100,760);
    var Frame := TRigmScriptCreatorFrame.CreateForWorkspace(Form,W,DataRoot);
    Frame.Parent := Form; Frame.SetActive(True);
    Form.Show; Application.ProcessMessages;
    var Combo := Frame.FindComponent('ScriptType') as TComboBox;
    Check((Combo.Items.Count=ScriptTypeCount) and (Combo.Items[ScriptTypeIndex(Id)]=ScriptTypeName(Id)),'title selector offers '+Id);
    Combo.ItemIndex := ScriptTypeIndex(Id); Combo.OnChange(Combo);
    Check(ProjectScriptType(W.ScriptDraft)=Id,'GUI selection stores stable preset ID');
    Check(not (Frame.FindComponent('ScriptTextImportActions') as TPanel).Visible,'external script actions hidden for preset');
    Capture(Frame,Id+'-title');
    W.SaveScriptDraft(False);
    var SavedPath := W.ScriptDraft.FileName;
    var Loaded := LoadMovie(SavedPath);
    try Check((ProjectScriptType(Loaded)=Id) and (JS(JO(Loaded.ScriptWizard,'scriptText'),'activeSection')=Section),'preset and active section survive save/load'); finally Loaded.Free; end;
    Check(ScriptConfirmationReason(W.ScriptDraft)<>'','empty preset requires its own dialogue');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'layoutChoice','theme');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'backgroundTone','dark');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'layoutStatus','complete');
    W.ScriptDraft.Layout := 'theme'; W.ScriptDraft.LDirection := 'right';
    W.ScriptDraft.BackgroundColor := LayoutBackgroundColor('dark');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'furthestStage','script-confirm');
    W.SetScriptStage('text');
    W.SetScriptText(Section,'最初のセリフ。'+#13#10+#13#10+'次のセリフ。');
    Check(ScriptConfirmationReason(W.ScriptDraft)='','preset requires no body, research, score or closing settings');
    Check(ScriptNextStage('text',W.ScriptDraft.ScriptWizard)='script-confirm','text goes directly to confirmation');
    var Rejected := False; var Before := W.ScriptDraft.ScriptWizard.ToJSON;
    try W.SetScriptType('manga-introduction'); except Rejected := True; end;
    Check(Rejected and (Before=W.ScriptDraft.ScriptWizard.ToJSON),'changing populated structure preserves all input');
    Rejected := False;
    try W.SetScriptText('body','余計な本文'); except Rejected := True; end;
    Check(Rejected and (JS(ScriptSection(W.ScriptDraft,'body'),'text')=''),'unrelated section cannot enter preset');
    var TextFrame := TRigmScriptTextFrame.CreateForWorkspace(Form,W);
    try
      TextFrame.Parent := Form; TextFrame.RefreshState;
      Check(not (TextFrame.FindComponent('ScriptTextSections') as TTabControl).Visible,'text UI exposes only preset dialogue');
    finally TextFrame.Free; end;
    Capture(Frame,Id+'-text');
    W.SaveScriptDraft(False);
    // Fixture reaches confirmation without any sound device or playback frame.
    W.SetScriptStage('title'); W.SetScriptStage('script-confirm');
    Check(W.ScriptDraft.ScriptWizard.GetValue('closingData')=nil,'return to confirmation does not create closing settings');
    Capture(Frame,Id+'-confirm');
    var State := W.ScriptStatus;
    try
      Check(not Offered(State,'review') and not Offered(State,'summary') and not Offered(State,'summary-edit') and not Offered(State,'closing'),'irrelevant stages stay absent after reopening reached stages');
      Check(ScriptStageBlockReason(State,'summary')<>'','direct entry to score stage rejected');
    finally State.Free; end;
    var P := W.ScriptDraft.Clone;
    try
      var Character := TJSONObject.Create; JA(P.ScriptWizard,'selectedCharacters').AddElement(Character);
      Character.AddPair('path','Characters\OwnedFixture.rigm'); Character.AddPair('name','検証キャラ'); Character.AddPair('renderFormat','rigm');
      PrepareScriptCasting(P);
      Check((P.Scenes.Count=1) and (P.Cues.Count=2),'blank-line-separated dialogue remains exactly one scene');
      Check((P.Cues[0].Scene=P.Cues[1].Scene) and not ScriptSceneStartEditable(P,1),'scene boundary cannot split preset');
      P.Cues[0].Subtitle := '保持する字幕'; P.Cues[0].VoiceReading := 'ほじするよみ';
      var CueId := P.Cues[0].Id; var SceneId := P.Scenes[0].Id;
      P.Scenes[0].Description := '編集した素材説明'; P.Scenes[0].ImagePrompt := '背景の要望';
      PsdJson.Put(ScriptSection(P,Section),'text','最初のセリフ。'+#13#10+#13#10+'変更したセリフ。'+#13#10+'追加のセリフ。');
      PrepareScriptCasting(P);
      Check((P.Scenes.Count=1) and (P.Scenes[0].Id=SceneId) and (P.Cues.Count=3),'re-edit retains one scene and identity');
      Check((P.Cue(CueId).Subtitle='保持する字幕') and (P.Cue(CueId).VoiceReading='ほじするよみ') and (P.Scenes[0].Description='編集した素材説明'),'unchanged dialogue edits and scene material survive reconciliation');
      PrepareScriptScenes(P,False);
      Check((P.Thumbnail.ImagePrompt='') and (P.EndCards.Count=0),'preset creates no required thumbnail or ten-second card');
      P.Scenes[0].DisplayMode := 'none';
      SetScriptSceneApproved(P,P.Scenes[0].Id,True);
      Check(ScriptScenesReady(P,True),'one confirmed scene passes readiness without thumbnail');
      RequireScriptThumbnail(P);
      Check(P.EndCards.Count=0,'existing output guard accepts preset without appending a card');
      P.Scenes[0].ImageApproved := False;
      Check(not ScriptScenesReady(P,True),'preset still requires human scene confirmation');
      P.Scenes[0].DisplayMode := 'image'; P.Scenes[0].ImagePrompt := '1枚の素材';
      var Targets := SceneImageAiTargets(P,'');
      try Check((Targets.Count=1) and (JS(TJSONObject(Targets[0]),'sceneId')=SceneId),'batch generation contains scene only, no thumbnail'); finally Targets.Free; end;
      var Copy := CreateScriptCopy(P,'2026-10-28T00:00:00Z');
      try Check((Copy.Id<>P.Id) and (ProjectScriptType(Copy)=Id) and (JS(ScriptSection(Copy,Section),'text')=JS(ScriptSection(P,Section),'text')),'reusable copy retains preset and dialogue under new ID'); finally Copy.Free; end;
      var Json := P.Json;
      try
        Loaded := TRigmMovieProject.FromJson(Json);
        try Check((Loaded.Scenes.Count=1) and (Loaded.Cues.Count=3) and (Loaded.EndCards.Count=0) and (ProjectScriptType(Loaded)=Id),'full JSON round trip preserves single-scene composition'); finally Loaded.Free; end;
      finally Json.Free; end;
      // Offline handoff fixture: simulated accepted voice metadata and a silent WAV.
      // No sound device, VOICEVOX process, real actor asset or video job is started.
      var Wave: TBytes; SetLength(Wave,9644); FillChar(Wave[0],Length(Wave),0);
      Move(PAnsiChar(AnsiString('RIFF'))^,Wave[0],4); PCardinal(@Wave[4])^ := 9636;
      Move(PAnsiChar(AnsiString('WAVEfmt '))^,Wave[8],8); PCardinal(@Wave[16])^ := 16;
      PWord(@Wave[20])^ := 1; PWord(@Wave[22])^ := 1; PCardinal(@Wave[24])^ := 48000;
      PCardinal(@Wave[28])^ := 96000; PWord(@Wave[32])^ := 2; PWord(@Wave[34])^ := 16;
      Move(PAnsiChar(AnsiString('data'))^,Wave[36],4); PCardinal(@Wave[40])^ := 9600;
      var WavePath := TPath.Combine(DataRoot,'silent.wav'); TFile.WriteAllBytes(WavePath,Wave);
      for var V in JA(JO(P.ScriptWizard,'casting'),'rows') do PsdJson.Put(TJSONObject(V),'confirmed',TJSONBool.Create(True));
      for var S in P.Speakers do begin S.StyleId := 0; S.VoiceUuid := 'offline-fixture'; end;
      RefreshScriptCastingStatus(P); PrepareScriptSubtitles(P);
      PsdJson.Put(P.ScriptWizard,'subtitlesStatus','complete'); PrepareScriptVoice(P);
      for var C in P.Cues do begin
        C.WaveFile := WavePath; C.AudioSeconds := 0.1; C.AudioKey := P.AudioFingerprint(C);
        C.VoiceHeardKey := C.AudioKey; // Fixture state only, never written to user data.
      end;
      PsdJson.Put(P.ScriptWizard,'voiceStatus','complete'); PsdJson.Put(P.ScriptWizard,'scene-assignmentStatus','complete');
      PsdJson.Put(P.ScriptWizard,'scriptConfirmedFingerprint',ScriptFingerprint(P));
      P.Scenes[0].DisplayMode := 'none'; SetScriptSceneApproved(P,SceneId,True);
      PsdJson.Put(P.ScriptWizard,'stage','scenes'); PsdJson.Put(P.ScriptWizard,'furthestStage','scenes');
      P.Id := PsdJson.NewId;
      var HandoffPath := TPath.Combine(DataRoot,'Projects\'+P.Id+'\project.rigmovie');
      SaveMovie(P,HandoffPath,False);
      var W2 := TRigmWizardWorkspace.Create(nil);
      try
        W2.StartPipe(DataRoot); W2.OpenScriptDraft(HandoffPath);
        Check(W2.CurrentScriptStage='scenes','fresh workspace reopens one-scene materials stage');
        W2.FinishScriptToEditor;
        Check((W2.ScriptDraft=nil) and (W2.ActiveSession<>nil) and
          (W2.ActiveSession.Project.Scenes.Count=1) and (W2.ActiveSession.Project.EndCards.Count=0),
          'offline fixture hands one scene to existing movie editor');
        Loaded := LoadMovie(HandoffPath);
        try Check((JS(Loaded.ScriptWizard,'stage')='editor') and (Loaded.Scenes.Count=1) and
          (Loaded.EndCards.Count=0),'handoff saves editor resume stage without extra scenes or cards'); finally Loaded.Free; end;
      finally W2.Free; end;
    finally P.Free; end;
  finally Form.Free; W.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1);
  try
    if (Root='') or DirectoryExists(Root) then raise Exception.Create('A new isolated output folder is required');
    ForceDirectories(Root);
    Check((ScriptTypeId(0)='anime-review') and (ScriptTypeId(1)='manga-introduction'),'original IDs retain order and meaning');
    var Legacy := PsdJson.ObjectText('{"scriptType":"manga-introduction"}');
    try Check(ScriptNextStage('text',Legacy)='review','existing manga flow still includes research'); finally Legacy.Free; end;
    RunPreset('anime-opening'); RunPreset('anime-closing');
    Writeln('CHECKS=',Checks);
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
