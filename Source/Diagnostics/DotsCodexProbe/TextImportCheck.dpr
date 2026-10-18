program TextImportCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmMovieModel, RigmScriptCopyModel, RigmWizardWorkspace, RigmScriptCreatorFrame,
  RigmScriptTextImport, RigmAutomationInput, RigmScriptTextModel,
  RigmScriptSummaryModel, RigmScriptScenesModel, RigmScriptCastingModel, RigmScriptSubtitleModel,
  RigmScriptSceneAssignmentModel, RigmMovieChart, RigmJson, PsdJson;
var Checks: TJSONArray; Report: TJSONObject; Output,DataRoot: string;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); end;
function JsonOf(W: TRigmWizardWorkspace): string;
begin var O := W.ScriptDraft.Json; try Result := O.ToJSON; finally O.Free; end; end;
procedure CheckDialogueParser(const Text: string);
begin
  var Paired := Text.Replace('最初の見どころを紹介します。',
    '字幕：歩が蜻蛉高校へ向かいます。'+#13#10+'　 '+#13#10+'読み:あゆむがかげろう高校へ向かいます。'+#13#10+#13#10);
  var Input := ValidateAutomationInput(Paired,True);
  try
    Check(JB(Input,'valid'),'paired subtitle and reading accepted with intervening blanks');
    var Block := TJSONObject(JA(JO(Input,'data'),'scenes')[0]); var Rows := JA(Block,'dialogue');
    Check((Rows.Count=2) and (JS(TJSONObject(Rows[0]),'subtitle')='歩が蜻蛉高校へ向かいます。') and
      (JS(TJSONObject(Rows[0]),'reading')='あゆむがかげろう高校へ向かいます。'),'one pair creates one dialogue with independent reading');
    Check(JS(Block,'body')='歩が蜻蛉高校へ向かいます。'+#13#10+'この二行は同じシーンになります。',
      'blank lines and reading labels never enter source dialogue');
    Check(JS(TJSONObject(Rows[1]),'reading')='','plain dialogue keeps default pronunciation');
  finally Input.Free; end;
  for var BadLine in ['読み：先に読み','字幕：','字幕：セリフ'+#13#10+'読み：'+#13#10+'読み：重複',
    '字幕：セリフ'+#13#10+'読み：'+StringOfChar('あ',2001)] do begin
    Input := ValidateAutomationInput(Text.Replace('最初の見どころを紹介します。',BadLine),True);
    try Check(not JB(Input,'valid'),'invalid pair rejected before any project mutation'); finally Input.Free; end;
  end;
  Input := ValidateAutomationInput(Text.Replace('実際に使用するとき',#13#10+'実際に使用するとき'),True);
  try Check(JS(JO(JO(Input,'data'),'posting'),'body').Contains(#13#10+#13#10),'posting paragraph breaks remain intact'); finally Input.Free; end;
  Input := ValidateAutomationInput(Text.Replace('登場人物の関係が魅力的な作品でした。',
    '字幕：総評です。'+#13#10+'読み：'+StringOfChar('あ',2000)),True);
  try Check(not JB(Input,'valid'),'combined summary reading overflow rejected before materialization'); finally Input.Free; end;
end;
procedure CheckDialogueEdits(Project: TRigmMovieProject; const CueId: string);
begin
  var P := Project.Clone;
  try
    var C := P.Cue(CueId); var Source := C.Text; var Other := P.Cues[0];
    C.AudioKey := 'old-audio'; C.VoiceHeardKey := 'old-heard'; C.VoiceQuery := '{}'; C.VoiceQueryKey := 'old-query'; C.EffectAudioKey := 'old-effect';
    Other.AudioKey := 'other-audio'; Other.VoiceHeardKey := 'other-heard';
    EditSubtitleDialogue(P,C.Id,'表示だけ変更',C.VoiceReading,'メモ');
    Check((C.Text=Source) and (C.AudioKey='old-audio') and (C.VoiceQueryKey='old-query') and
      (C.VoiceHeardKey='old-heard') and (C.EffectAudioKey='old-effect'),'subtitle-only edit retains audio accent and playback acceptance');
    EditSubtitleDialogue(P,C.Id,'表示だけ変更','あゆむがかげろう高校へ向かいます。','メモ');
    Check((C.Text=Source) and (C.Subtitle='表示だけ変更') and (C.AudioKey='') and (C.VoiceQuery='') and
      (C.VoiceHeardKey='') and (C.EffectAudioKey=''),'reading edit invalidates only matching cue audio and query');
    Check((Other.AudioKey='other-audio') and (Other.VoiceHeardKey='other-heard'),'other dialogue audio untouched');
    var Before := C.Json; var Rejected := False;
    try
      try EditSubtitleDialogue(P,C.Id,'変更しない',StringOfChar('あ',2001),'変更しない'); except on E: Exception do Rejected := True; end;
      var After := C.Json;
      try Check(Rejected and (Before.ToJSON=After.ToJSON),'invalid reading leaves subtitle reading and memo unchanged'); finally After.Free; end;
    finally Before.Free; end;
  finally P.Free; end;
end;
procedure Run;
begin
  var SourceFile := ParamStr(1); var Example := ParamStr(2); Output := ParamStr(3);
  if FileExists(TPath.Combine(Output,'result.json')) then raise Exception.Create('Fresh output required.');
  ForceDirectories(Output); DataRoot := TPath.Combine(Output,'Data'); ForceDirectories(DataRoot);
  TFile.WriteAllText(TPath.Combine(Output,'テンプレート.txt'),ScriptTextInputTemplate,TEncoding.UTF8);
  var Text := ReadScriptTextInputFile(Example); var InputHash := THashSHA2.GetHashStringFromFile(Example);
  CheckDialogueParser(Text);
  var Valid := ValidateAutomationInput(Text,True);
  try
    Check(JB(Valid,'valid'),'complete manual template is valid');
    var Legacy := ValidateAutomationInput(TFile.ReadAllText(ParamStr(4),TEncoding.UTF8));
    try Check(JB(Legacy,'valid'),'old Dots automation format remains valid'); finally Legacy.Free; end;
  finally Valid.Free; end;
  var Blank := ValidateAutomationInput(ScriptTextInputTemplate,True);
  try Check(not JB(Blank,'valid') and (JA(Blank,'issues').Count>5),'blank template lists all missing inputs'); finally Blank.Free; end;
  var InvalidScore := ValidateAutomationInput(Text.Replace('ストーリー：4','ストーリー：6'),True);
  try Check(not JB(InvalidScore,'valid'),'out-of-range summary score rejected'); finally InvalidScore.Free; end;
  var Duplicate := ValidateAutomationInput(Text+#13#10+'*前段'+#13#10+'本文：重複',True);
  try Check(not JB(Duplicate,'valid'),'duplicate shared section rejected'); finally Duplicate.Free; end;
  var Index := 0;
  for var Encoding in [TEncoding.UTF8,TEncoding.Unicode,TEncoding.BigEndianUnicode] do begin
    var Name := TPath.Combine(Output,'encoding-'+Index.ToString+'.txt');
    TFile.WriteAllText(Name,Text,Encoding);
    Check(ReadScriptTextInputFile(Name)=Text,'UTF BOM file encoding preserved'); Inc(Index);
  end;
  var NoBom := TUTF8Encoding.Create(False);
  try var Name := TPath.Combine(Output,'encoding-no-bom.txt'); TFile.WriteAllText(Name,Text,NoBom);
    Check(ReadScriptTextInputFile(Name)=Text,'UTF8 without BOM preserved');
  finally NoBom.Free; end;
  var SourceHash := THashSHA2.GetHashStringFromFile(SourceFile); var Source := LoadMovie(SourceFile);
  try
    var Seed := CreateScriptCopy(Source,'2026-10-16T00:00:00Z');
    try
      var Path := TPath.Combine(DataRoot,'Projects\'+Seed.Id+'\project.rigmovie'); ForceDirectories(ExtractFilePath(Path)); SaveMovie(Seed,Path,False);
      for var V in JA(Seed.ScriptWizard,'selectedCharacters') do begin
        var Relative := JS(TJSONObject(V),'path'); var OriginalRoot := ExtractFileDir(ExtractFileDir(ExtractFileDir(SourceFile)));
        var Destination := TPath.Combine(DataRoot,Relative); ForceDirectories(ExtractFilePath(Destination));
        TFile.Copy(TPath.Combine(OriginalRoot,Relative),Destination,False);
      end;
      var SeedHash := THashSHA2.GetHashStringFromFile(Path);
      var W := TRigmWizardWorkspace.Create(nil);
      try
        W.StartPipe(DataRoot); W.CopyScriptDraft(Path);
        var Target := W.ScriptDraft.FileName; var Id := W.ScriptDraft.Id;
        Check(Id<>Seed.Id,'GUI copy has its own target project ID');
        var Before := JsonOf(W); var DiskHash := THashSHA2.GetHashStringFromFile(Target);
        var Bad := W.ImportScriptText('');
        try Check(not JB(Bad,'valid') and (JA(Bad,'issues').Count>5),'invalid import returns missing fields'); finally Bad.Free; end;
        Check((JsonOf(W)=Before) and (THashSHA2.GetHashStringFromFile(Target)=DiskHash),'invalid import preserves memory and saved file');
        var PairedText := Text.Replace('最初の見どころを紹介します。',
          '字幕：歩が蜻蛉高校へ向かいます。'+#13#10+#13#10+'読み：あゆむがかげろう高校へ向かいます。')
          .Replace('登場人物の関係が魅力的な作品でした。',
          '字幕：歩の物語でした。'+#13#10+'読み：あゆむの物語でした。')
          .Replace('こんにちは。','字幕：こんにちは。'+#13#10+'読み：こんにちわ。')
          .Replace('ご視聴ありがとうございました。','字幕：ご視聴ありがとうございました。'+#13#10+'読み：ごしちょうありがとうございました。');
        var PairedReply := W.ImportScriptText(PairedText);
        try Check(JB(PairedReply,'imported'),'paired dialogue imported through shared workspace'); finally PairedReply.Free; end;
        var PairedSaved := LoadMovie(Target); var PairCount := 0;
        try
          for var C in PairedSaved.Cues do begin
            Check(not C.Text.StartsWith('読み：') and not C.Text.StartsWith('字幕：') and (C.Text.Trim<>''),'saved cues contain no labels or empty dialogue');
            if C.Text='歩が蜻蛉高校へ向かいます。' then begin
              Inc(PairCount); Check((C.Subtitle=C.Text) and (C.SpokenText='あゆむがかげろう高校へ向かいます。'),'body pair survives save and reload');
              C.Subtitle := '手動字幕'; C.VoiceReading := '手動よみ'; ApplyImportedSceneInputs(PairedSaved);
              Check((C.Subtitle='手動字幕') and (C.VoiceReading='手動よみ'),'reapplying input preserves manual subtitle and reading edits');
            end;
            if C.Text='歩の物語でした。' then begin
              Inc(PairCount); Check(C.SpokenText='あゆむの物語でした。','summary pair survives save and reload');
            end;
            if C.Text='こんにちは。' then begin Inc(PairCount); Check(C.SpokenText='こんにちわ。','opening reading imported'); end;
            if C.Text='ご視聴ありがとうございました。' then begin Inc(PairCount); Check(C.SpokenText='ごしちょうありがとうございました。','closing reading imported'); end;
          end;
          Check(PairCount=4,'each paired input creates exactly one cue in all four dialogue sections');
        finally PairedSaved.Free; end;
        var FullExample := ParamStr(5); var FullText := ReadScriptTextInputFile(FullExample);
        var FullInput := ValidateAutomationInput(FullText,True);
        try
          Check(JB(FullInput,'valid') and (JA(JO(FullInput,'data'),'scenes').Count=7),'supplied elf script accepted without extra sections or blank lines');
          var FullReply := W.ImportScriptFile(FullExample);
          try Check(JB(FullReply,'imported') and (JI(FullReply,'sceneCount')=7),'supplied script imported with seven scenes'); finally FullReply.Free; end;
          Check((W.CurrentScriptStage='title') and (JS(JO(W.ScriptDraft.ScriptWizard,'textImport'),'sceneState')='applied'),'all scene construction finishes during import');
          for var V in JA(JO(FullInput,'data'),'scenes') do begin
            var Block := TJSONObject(V); var Found := 0;
            for var S in W.ScriptDraft.Scenes do if S.Title=JS(Block,'title') then begin
              Inc(Found); Check((S.ImagePrompt=JS(Block,'imagePrompt')) and (S.Description=JS(Block,'displayText')) and
                (S.DescriptionPosition='below-image'),'supplied scene prompt and caption assigned automatically');
              var Dialogue := '';
              for var C in W.ScriptDraft.Cues do if C.Scene=S.Id then begin
                if Dialogue<>'' then Dialogue := Dialogue+#13#10; Dialogue := Dialogue+C.Text;
                Check(C.Text=C.Subtitle,'supplied dialogue and subtitle match');
              end;
              Check(Dialogue.Trim=NormalizeScriptText(JS(Block,'body')).Trim,'all lines assigned to correct supplied scene');
            end;
            Check(Found=1,'one scene created for each supplied block');
          end;
          var FullSaved := LoadMovie(Target);
          try Check((FullSaved.Cues.Count=W.ScriptDraft.Cues.Count) and (FullSaved.Scenes.Count=W.ScriptDraft.Scenes.Count),'immediate scenes and dialogue saved on disk'); finally FullSaved.Free; end;
        finally FullInput.Free; end;
        var Reply := W.ImportScriptFile(Example);
        try Check(JB(Reply,'valid') and JB(Reply,'imported') and (JI(Reply,'sceneCount')=2),'file import fills all input fields'); finally Reply.Free; end;
        Check((W.CurrentScriptStage='title') and (W.ScriptDraft.Id=Id) and not W.ScriptDraft.Modified,'import saves same copy and stays at first stage');
        for var S in W.ScriptDraft.Scenes do Check(S.Title<>'100年留年という衝撃','first-stage reimport removes superseded scenes');
        Check((W.ScriptDraft.Cues.Count>0) and (W.ScriptDraft.Scenes.Count>0) and not W.VoiceBusy and not W.ExpressionAiBusy and not W.SceneImageAiBusy,'import immediately builds cues and scenes without voice image or AI production');
        Check(JS(JO(W.ScriptDraft.ScriptWizard,'textImport'),'sceneState')='applied','scene creation completed at first stage');
        var P := W.ScriptDraft;
        Check(P.Title='テキスト読み込みの記入例','work title imported');
        Check(JS(P.ScriptWizard,'scriptType')='manga-introduction','script type imported');
        Check(Pos('こんにちは',JS(ScriptSection(P,'opening'),'text'))>0,'opening dialogue imported');
        Check(Pos('ご視聴ありがとうございました',JS(ScriptSection(P,'closing'),'text'))>0,'closing dialogue imported');
        Check((JA(JO(JO(P.ScriptWizard,'summaryData'),'draft'),'items').Count=5) and
          (JS(JO(P.ScriptWizard,'summaryData'),'status')='complete'),'fixed five summary scores and speech imported');
        Check(JS(P.Posting,'title')='作品紹介・テキスト読み込みの試験','posting title reflected in memory');
        Check(Pos('実際に使用するとき',JS(P.Posting,'description'))>0,'multiline posting description imported');
        Check(P.CommonBackground.ImagePrompt<>'','background prompt imported');
        var Saved := LoadMovie(Target);
        try Check((JS(Saved.Posting,'title')=JS(P.Posting,'title')) and (Saved.ScriptWizard.GetValue('textImport') is TJSONObject),'posting and deferred scene input persist on disk'); finally Saved.Free; end;
        W.Free; W := TRigmWizardWorkspace.Create(nil); W.StartPipe(DataRoot); W.OpenScriptDraft(Target);
        Check((W.CurrentScriptStage='title') and (W.ScriptDraft.Id=Id),'first-stage import survives reopening');
        var Host := TForm.Create(nil); var Frame: TRigmScriptCreatorFrame := nil;
        try
          Host.SetBounds(0,0,1200,800); Frame := TRigmScriptCreatorFrame.CreateForWorkspace(Host,W,DataRoot);
          Frame.Parent := Host; Frame.SetActive(True); Host.Show; Application.ProcessMessages; Host.HandleNeeded; Frame.HandleNeeded;
          Check((Frame.FindComponent('ScriptImportText') is TButton) and TButton(Frame.FindComponent('ScriptImportText')).Enabled,'first stage exposes enabled file-import button');
          Check(Frame.FindComponent('ScriptSaveInputTemplate') is TButton,'first stage exposes template-save button');
          var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
          try Bitmap.SetSize(1200,800); Host.PaintTo(Bitmap.Canvas,0,0); Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Output,'first-stage.png'));
          finally Png.Free; Bitmap.Free; end;
          Frame.Free; Frame := nil;
        finally Frame.Free; Host.Free; end;
        var Deadline := GetTickCount64+20000; var Relative := JS(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters')[0]),'path');
        while W.Thumbnails.Request(Relative)=nil do begin if GetTickCount64>Deadline then raise Exception.Create('Character wait timed out.'); Sleep(10); end;
        var Steps := 0;
        while W.CurrentScriptStage<>'casting' do begin
          if W.CurrentScriptStage='closing' then W.CompleteScriptClosing;
          W.NextScriptDraft; Inc(Steps); if Steps>12 then raise Exception.Create('Stage advance did not reach casting.');
        end;
        P := W.ScriptDraft; var Blue := ''; var Red := ''; var BodyLines := 0;
        for var S in P.Scenes do begin
          if S.Title='物語の魅力' then begin Blue := S.Id; Check(S.Description='物語の見どころ','first scene display text imported'); Check(S.ImagePrompt.Contains('青い円'),'first scene image prompt imported'); Check(S.DescriptionPosition='below-image','display text is below image'); end;
          if S.Title='キャラクターの魅力' then begin Red := S.Id; Check(S.ImagePrompt.Contains('赤い四角'),'second scene image prompt imported'); end;
        end;
        Check((Blue<>'') and (Red<>'') and (Blue<>Red),'input scene names and boundaries survive stage transitions');
        for var C in P.Cues do begin
          if C.Scene=Blue then Inc(BodyLines);
          Check(C.Text=C.Subtitle,'prepared dialogue and subtitle match');
        end;
        Check(BodyLines=2,'multiline body remains in one input scene');
        for var C in P.Cues do if C.Scene=Blue then begin CheckDialogueEdits(P,C.Id); Break; end;
        var Summary := ScriptSummaryCue(P); Check((Summary<>nil) and MovieChartEnabled(P.Scene(Summary.Scene).Chart),'summary retains independent chart');
        Check(JS(JO(P.ScriptWizard,'textImport'),'sceneState')='applied','deferred scene inputs applied');
        EditScriptSceneTitle(P,Blue,'手動で直したシーン名'); ApplyImportedSceneInputs(P);
        Check(P.Scene(Blue).Title='手動で直したシーン名','revisiting does not overwrite manual scene edits');
        var Changed := P.Clone;
        try PsdJson.Put(ScriptSection(Changed,'body'),'text','変更した本文'); ApplyImportedSceneInputs(Changed);
          Check(JS(JO(Changed.ScriptWizard,'textImport'),'sceneState')='stale','changed body does not receive old scene bindings');
        finally Changed.Free; end;
        var Rejected := False;
        try var R := W.ImportScriptFile(Example); R.Free; except on E: Exception do Rejected := True; end;
        Check(Rejected,'later stages reject replacement of the script');
        Check(SeedHash=THashSHA2.GetHashStringFromFile(Path),'copy source unchanged');
      finally W.Free; end;
    finally Seed.Free; end;
  finally Source.Free; end;
  Check(SourceHash=THashSHA2.GetHashStringFromFile(SourceFile),'real source project unchanged');
  Check(InputHash=THashSHA2.GetHashStringFromFile(Example),'input text file unchanged');
end;
begin
  Application.Initialize; Application.ShowMainForm := False;
  Checks := TJSONArray.Create; Report := TJSONObject.Create;
  try
    try Run; Report.AddPair('success',TJSONBool.Create(True));
    except on E: Exception do begin Report.AddPair('success',TJSONBool.Create(False)); Report.AddPair('error',E.Message); ExitCode := 1; end; end;
    Report.AddPair('checks',Checks); Checks := nil;
    if Output<>'' then TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally Checks.Free; Report.Free; end;
end.
