program ScriptCopyCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmWizardWorkspace, RigmScriptManagerFrame, RigmPageNavigation, RigmScriptCopyModel,
  RigmMovieModel, RigmMovieComposition, RigmMovieAudio, RigmModel, RigmSample, RigmStorage,
  RigmScriptTextModel, RigmScriptCastingModel, RigmScriptVoiceModel, RigmScriptSummaryModel,
  RigmScriptClosingModel, RigmJson, PsdJson;
type
  TProbe = class
    Navigated: Boolean;
    procedure Navigate(Sender: TObject; Page: TRigmAppPage; const Value: string);
  end;
var W: TRigmWizardWorkspace; Root,Error,SourcePath,SourceHash: string; Checks: TJSONArray;
  OriginalFiles: TJSONObject;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
procedure TProbe.Navigate(Sender: TObject; Page: TRigmAppPage; const Value: string);
begin Navigated := Page=apScriptCreate; end;
function FindNamed(Owner: TComponent; const Name: string): TComponent;
begin
  Result := nil; if Owner.Name=Name then Exit(Owner);
  for var I := 0 to Owner.ComponentCount-1 do begin Result := FindNamed(Owner.Components[I],Name); if Result<>nil then Exit; end;
end;
procedure Fixture;
begin
  Writeln('Fixture: assets'); Flush(Output);
  var Path := W.Pipe.Workspace.Resolve('RIGM\copy-source.rigm',False); ForceDirectories(ExtractFileDir(Path));
  var D := TRigmDocument.Create;
  try PopulateRigmSample(D); D.Usable := True; SaveRigm(D,Path); finally D.Free; end;
  var B := TBitmap.Create; var PNG := TPngImage.Create;
  try B.SetSize(32,32); B.Canvas.Brush.Color := clAqua; B.Canvas.FillRect(Rect(0,0,32,32));
    PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'original-image.png'));
  finally PNG.Free; B.Free; end;
  var Audio := TRigmPcm.Create;
  try Audio.Rate := 48000; SetLength(Audio.Samples,4800); Audio.Save(TPath.Combine(Root,'original-audio.wav'));
  finally Audio.Free; end;
  Writeln('Fixture: new script'); Flush(Output);
  W.NewScriptDraft; W.SetScriptTitle('コピー元の題名'); W.SetScriptType('manga-introduction');
  var P := W.ScriptDraft;
  JA(P.ScriptWizard,'selectedCharacters').AddElement(PsdJson.ObjectText('{"path":"RIGM\\copy-source.rigm","name":"説明キャラ","renderFormat":"rigm","voiceBinding":{"uuid":"old-voice","name":"旧話者","styleId":2,"style":"旧スタイル","forbidden":"discard"},"forbidden":"discard"}'));
  PsdJson.Put(P.ScriptWizard,'placements',TJSONObject.ParseJSONValue('[{"path":"RIGM\\copy-source.rigm","x":1.08,"y":-0.08,"width":0.37,"height":0.62,"flipX":true,"forbidden":"discard"}]'));
  PrepareScriptText(P);
  PsdJson.Put(ScriptSection(P,'opening'),'text','共通の出だし。'+StringOfChar('あ',5000));
  PsdJson.Put(ScriptSection(P,'body'),'text','コピーしてはいけない今回の本文。');
  PsdJson.Put(ScriptSection(P,'closing'),'text','共通の締め。');
  PrepareScriptSummary(P); var Summary := JO(JO(P.ScriptWizard,'summaryData'),'draft');
  PsdJson.Put(Summary,'text','総評の文章'); PsdJson.Put(Summary,'subtitle','総評の字幕'); PsdJson.Put(Summary,'reading','そうひょう');
  PsdJson.Put(Summary,'title','総評タイトル'); PsdJson.Put(TJSONObject(JA(Summary,'items')[0]),'label','評価名');
  PsdJson.Put(TJSONObject(JA(Summary,'items')[0]),'value','4');
  PrepareScriptClosing(P); var Closing := JO(JO(P.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  try PsdJson.Put(Closing,'title','締めの題名'); SetScriptClosingDraft(P,Closing); finally Closing.Free; end;
  Writeln('Fixture: casting'); Flush(Output); PrepareScriptCasting(P);
  var Role := TJSONObject(JA(JO(P.ScriptWizard,'casting'),'roles')[0]); var S := P.Speaker(JS(Role,'speakerId'));
  S.VoiceUuid := 'current-voice'; S.VoiceName := '現在の話者'; S.StyleId := 77; S.StyleName := '現在のスタイル';
  PsdJson.Put(P.ScriptWizard,'voice',PsdJson.ObjectText('{"format":"RIGMMaker.ScriptVoice","schemaVersion":1,"selectedCue":"","commonSettings":{"speedScale":1.25,"pitchScale":0.13,"intonationScale":0.8,"volumeScale":0.7,"prePhonemeLength":0.12,"postPhonemeLength":0.15},"forbidden":"discard"}'));
  PsdJson.Put(JO(P.ScriptWizard,'voice'),'selectedCue',P.Cues[0].Id);
  for var C in P.Cues do begin
    C.WaveFile := TPath.Combine(Root,'original-audio.wav'); C.AudioSeconds := 0.1; C.AudioKey := StringOfChar('A',64); C.VoiceHeardKey := C.AudioKey;
    C.VoiceReading := 'コピーしない個別の読み'; PsdJson.Put(C.VoiceSettings,'speedScale',TJSONNumber.Create(1.9));
  end;
  for var Scene in P.Scenes do begin Scene.Image := TPath.Combine(Root,'original-image.png'); Scene.Description := 'コピーしないシーン補足'; end;
  P.ThemeBackground := TPath.Combine(Root,'original-image.png'); P.Thumbnail.Image := P.ThemeBackground;
  P.BgmFile := TPath.Combine(Root,'original-audio.wav'); P.OutputTarget := TPath.Combine(Root,'do-not-overwrite.mp4');
  P.VideoPath := P.OutputTarget; P.VideoKey := 'discard-video'; P.PreviewPath := P.OutputTarget; P.PreviewKey := 'discard-preview';
  P.Width := 640; P.Height := 360; P.Fps := 15; P.Layout := 'l'; P.LDirection := 'left'; P.EncodeProfile := 'quality';
  PsdJson.Put(P.ScriptWizard,'furthestStage','editor'); PsdJson.Put(P.ScriptWizard,'flowVersion',TJSONNumber.Create(2));
  PsdJson.Put(P.ScriptWizard,'scriptConfirmedFingerprint','discard-confirmation'); PsdJson.Put(P.ScriptWizard,'forbiddenUnknown','discard');
  Writeln('Fixture: save'); Flush(Output);
  P.Changed; W.SaveScriptDraft(False); SourcePath := P.FileName; SourceHash := THashSHA2.GetHashStringFromFile(SourcePath);
  OriginalFiles := TJSONObject.Create;
  for var FileName in TDirectory.GetFiles(ExtractFileDir(SourcePath),'*',TSearchOption.soAllDirectories) do
    OriginalFiles.AddPair(FileName,THashSHA2.GetHashStringFromFile(FileName));
end;
procedure CheckCopy(P: TRigmMovieProject);
begin
  var Original := LoadMovie(SourcePath);
  try
    Check((P.Id<>Original.Id) and (P.FileName<>SourcePath) and FileExists(P.FileName),'copy receives a new saved identity and UID folder');
    Check((JS(P.ScriptWizard,'stage')='title') and (JS(P.ScriptWizard,'furthestStage')='title') and
      (JS(P.ScriptWizard,'titleStatus')='in-progress'),'copy starts at the unconfirmed title stage');
    Check((P.Title=Original.Title) and (JS(ScriptSection(P,'body'),'text')=''),'title retained and current body cleared');
    Check(JS(ScriptSection(P,'opening'),'text')=JS(ScriptSection(Original,'opening'),'text'),'full shared opening retained beyond chunk size');
    Check(JS(ScriptSection(P,'closing'),'text')='共通の締め。','shared closing retained');
    var Summary := JO(JO(P.ScriptWizard,'summaryData'),'draft');
    Check((JS(Summary,'text')='総評の文章') and (JS(Summary,'subtitle')='総評の字幕') and (JS(Summary,'reading')='そうひょう'),'summary text inputs retained');
    Check((JS(TJSONObject(JA(Summary,'items')[0]),'label')='評価名') and (JS(TJSONObject(JA(Summary,'items')[0]),'value')=''),'summary label retained without its score');
    var Closing := JO(JO(P.ScriptWizard,'closingData'),'draft');
    Check((JS(Closing,'title')='締めの題名') and (JS(Closing,'representative')='') and (JS(Closing,'thumbnailImage')=''),'closing title retained without images');
    Check((JA(P.ScriptWizard,'selectedCharacters').Count=1) and (P.Characters.Count=0),'selected character references retained without rendered character state');
    var Character := TJSONObject(JA(P.ScriptWizard,'selectedCharacters')[0]); var Binding := JO(Character,'voiceBinding');
    Check((JS(Binding,'uuid')='current-voice') and (JI(Binding,'styleId')=77) and (JS(Binding,'style')='現在のスタイル'),'current character speaker and style override stale selection binding');
    Check((Character.GetValue('forbidden')=nil) and (Binding.GetValue('forbidden')=nil),'character metadata copied by explicit field list');
    var Placement := TJSONObject(JA(P.ScriptWizard,'placements')[0]);
    Check((Abs(JN(Placement,'x')-1.08)<0.00001) and (Abs(JN(Placement,'y')+0.08)<0.00001) and
      (Abs(JN(Placement,'width')-0.37)<0.00001) and JB(Placement,'flipX'),'placement size, off-screen coordinates and mirroring retained');
    Check(Placement.GetValue('forbidden')=nil,'unrelated placement metadata excluded');
    Check((JN(JO(JO(P.ScriptWizard,'voice'),'commonSettings'),'speedScale')=1.25) and
      (JN(JO(JO(P.ScriptWizard,'voice'),'commonSettings'),'pitchScale')=0.13),'project-wide VOICEVOX values retained');
    Check((P.Cues.Count=0) and (P.Scenes.Count=0) and (P.EndCards.Count=0),'no dialogue rows, generated audio or scenes copied');
    Check((P.ThemeBackground='') and (P.Thumbnail.Image='') and (P.BgmFile=''),'background, thumbnail and music excluded');
    Check((P.OutputTarget='') and (P.VideoPath='') and (P.PreviewPath='') and (P.VideoKey=''),'output destinations and cached results excluded');
    Check((P.Width=1920) and (P.Height=1080) and (P.Layout='theme') and (P.EncodeProfile='balanced'),'unrequested video and layout settings use fresh defaults');
    Check((P.ScriptWizard.GetValue('casting')=nil) and (P.ScriptWizard.GetValue('scriptConfirmedFingerprint')=nil) and
      (P.ScriptWizard.GetValue('forbiddenUnknown')=nil) and (JS(P.ScriptWizard,'scriptType')=''),'casting, confirmation, classification and unknown state excluded');
    Check((JS(JO(P.ScriptWizard,'voice'),'selectedCue')='') and (JO(P.ScriptWizard,'voice').GetValue('forbidden')=nil),'voice selection and unrelated state excluded');
  finally Original.Free; end;
end;
procedure CheckClosingTitleRename;
  function ClosingTitle: string;
  begin Result := JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'title'); end;
  procedure SetClosingTitle(const Title: string);
  begin
    var D := JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
    try PsdJson.Put(D,'title',Title); SetScriptClosingDraft(W.ScriptDraft,D); finally D.Free; end;
    W.ScriptDraft.Changed;
  end;
begin
  W.CopyScriptDraft(SourcePath); W.SetScriptTitle('別の作品名');
  Check(ClosingTitle='締めの題名','copied custom closing heading survives a main-title change');
  W.SetScriptTitle(''); W.SaveScriptDraft(False); W.SetScriptTitle('新しい作品名');
  Check(ClosingTitle='締めの題名','custom heading survives clearing, saving and typing a replacement title');
  SetClosingTitle(''); W.SetScriptTitle('さらに別の作品名');
  Check(ClosingTitle='','explicitly hidden closing heading remains blank after renaming');
  W.SetScriptTitle(''); W.SaveScriptDraft(False); W.SetScriptTitle('新しい入力');
  Check(ClosingTitle='','explicit blank survives an empty saved main title and later input');
  SetClosingTitle('新しい入力');
  W.ScriptDraft.ScriptWizard.GetValue<TJSONObject>('closingData').RemovePair('titleFollowsProject').Free;
  W.SaveScriptDraft(False); var LegacyPath := W.ScriptDraft.FileName;
  W.CopyScriptDraft(LegacyPath);
  Check(ScriptClosingTitleFollowsProject(W.ScriptDraft),'legacy matching work title is recognized as automatic when copied');
  W.SetScriptTitle('異世界「嘘」ガイド');
  Check(ClosingTitle='異世界「嘘」ガイド','renaming a copied work replaces its inherited automatic closing title');
  W.SetScriptTitle(''); W.SaveScriptDraft(False); var Path := W.ScriptDraft.FileName;
  var Reopened := TRigmWizardWorkspace.Create(nil);
  try
    Reopened.StartPipe(W.Pipe.Workspace.Root); Reopened.OpenScriptDraft(Path);
    Reopened.SetScriptTitle('  入力し直した作品名  ');
    Check(JS(JO(JO(Reopened.ScriptDraft.ScriptWizard,'closingData'),'draft'),'title')='入力し直した作品名','new workspace preserves automatic linkage after loading a blank saved main title');
  finally Reopened.Free; end;
  W.SetScriptTitle('  入力し直した作品名  ');
  Check(ClosingTitle='入力し直した作品名','automatic linkage survives a cleared, saved and reopened main title');
  var P := W.ScriptDraft; PrepareScriptCasting(P);
  var D := JO(JO(P.ScriptWizard,'closingData'),'draft').Clone as TJSONObject;
  try
    PsdJson.Put(D,'representativeChoice','none'); PsdJson.Put(D,'endChoice','none'); SetScriptClosingDraft(P,D);
  finally D.Free; end;
  MaterializeScriptClosing(P); var Scene := P.Scene(ScriptClosingScene(P));
  Check((Scene<>nil) and (JS(JO(Scene.Animation,'closingCard'),'title')='入力し直した作品名'),'automatic title reaches the materialized video closing card');
  var BeforeCues := TJSONArray.Create;
  try
    for var C in P.Cues do BeforeCues.AddElement(C.Json);
    var Card := JO(Scene.Animation,'closingCard'); var CardBefore := Card.Clone as TJSONObject;
    try
      W.SetScriptTitle('動画に表示する新しい作品名');
      Check(JS(Card,'title')='動画に表示する新しい作品名','already materialized closing card follows the renamed work');
      CardBefore.RemovePair('title').Free; var CardAfter := Card.Clone as TJSONObject;
      try CardAfter.RemovePair('title').Free; Check(CardBefore.ToJSON=CardAfter.ToJSON,'renaming preserves closing representative image settings');
      finally CardAfter.Free; end;
    finally CardBefore.Free; end;
    var AfterCues := TJSONArray.Create;
    try for var C in P.Cues do AfterCues.AddElement(C.Json); Check(BeforeCues.ToJSON=AfterCues.ToJSON,'renaming does not recast, edit dialogue or replace audio');
    finally AfterCues.Free; end;
  finally BeforeCues.Free; end;
  var Before := P.Json; var Rejected := False;
  try
    try W.SetScriptTitle('不正'+#10+'題名'); except on E: Exception do Rejected := True; end;
    var After := P.Json;
    try Check(Rejected and (Before.ToJSON=After.ToJSON),'invalid main title is rejected before changing any closing title'); finally After.Free; end;
  finally Before.Free; end;
  W.SaveScriptDraft(False); Path := P.FileName; W.OpenScriptDraft(Path);
  Check((ClosingTitle='動画に表示する新しい作品名') and
    (JS(JO(W.ScriptDraft.Scene(ScriptClosingScene(W.ScriptDraft)).Animation,'closingCard'),'title')=ClosingTitle),'new title persists in both draft and video card across reopening');
  Reopened := TRigmWizardWorkspace.Create(nil);
  try
    Reopened.StartPipe(W.Pipe.Workspace.Root); Reopened.OpenScriptDraft(Path);
    var Loaded := Reopened.ScriptDraft;
    Check((JS(JO(JO(Loaded.ScriptWizard,'closingData'),'draft'),'title')=ClosingTitle) and
      (JS(JO(Loaded.Scene(ScriptClosingScene(Loaded)).Animation,'closingCard'),'title')=ClosingTitle),'new workspace loads the renamed draft and rendered video card from disk');
  finally Reopened.Free; end;
  W.CopyScriptDraft(Path); W.SetScriptTitle('次にコピーした作品');
  Check(ClosingTitle='次にコピーした作品','a second-generation copy keeps automatic title linkage');
  SetClosingTitle('手入力の独自見出し'); W.SaveScriptDraft(False); Path := W.ScriptDraft.FileName;
  W.CopyScriptDraft(Path); W.SetScriptTitle('別作品へコピー');
  Check(ClosingTitle='手入力の独自見出し','second-generation copy preserves a manually overridden heading');
  var Legacy := JO(W.ScriptDraft.ScriptWizard,'closingData'); Legacy.RemovePair('titleFollowsProject').Free;
  W.SetScriptTitle('旧形式の独自見出しを保持');
  Check(ClosingTitle='手入力の独自見出し','legacy custom heading does not become automatic');
  SetClosingTitle(''); Legacy.RemovePair('titleFollowsProject').Free; W.SetScriptTitle('旧形式の空欄を保持');
  Check(ClosingTitle='','legacy blank closing title remains hidden');
  W.SaveScriptDraft(False);
end;
procedure Run;
begin
  Fixture; W.CurrentPage := apScripts;
  var Host := TForm.Create(nil); var Probe := TProbe.Create;
  try
    Host.Width := 1280; Host.Height := 800;
    var Manager := TRigmScriptManagerFrame.CreateForWorkspace(Host,W,W.Pipe.Workspace.Root); Manager.Parent := Host;
    Manager.OnNavigate := Probe.Navigate;
    var Button := TToolButton(FindNamed(Manager,'ScriptCopy'));
    Check(Button<>nil,'library exposes a distinct copy action beside new creation'); Button.Click;
    Check(Probe.Navigated,'copy action navigates to the new script'); CheckCopy(W.ScriptDraft);
    var FirstId := W.ScriptDraft.Id; var FirstPath := W.ScriptDraft.FileName;
    var Reopened := TRigmWizardWorkspace.Create(nil);
    try Reopened.StartPipe(W.Pipe.Workspace.Root); Reopened.OpenScriptDraft(FirstPath); CheckCopy(Reopened.ScriptDraft); finally Reopened.Free; end;
    var Args := TJSONObject.Create;
    try Args.AddPair('path',SourcePath); var Reply := W.Command('app-script-copy',Args);
      try Check(JS(Reply,'projectId')=W.ScriptDraft.Id,'pipe copy returns the new script identity'); finally Reply.Free; end;
    finally Args.Free; end;
    Check(W.ScriptDraft.Id<>FirstId,'repeated copying creates distinct identities');
    var Deadline := GetTickCount64+10000; var Ready := False;
    repeat
      var Catalog := W.ScriptCharacterLibrary(False);
      try for var V in JA(Catalog,'characters') do Ready := Ready or JB(TJSONObject(V),'readyForScript'); finally Catalog.Free; end;
      if Ready then Break; Application.ProcessMessages; Sleep(10);
    until GetTickCount64>Deadline;
    Check(Ready,'owned character readiness has finished before advancing');
    W.NextScriptDraft; W.NextScriptDraft; W.NextScriptDraft; W.NextScriptDraft;
    Check((JS(W.ScriptDraft.ScriptWizard,'stage')='text') and
      (Abs(JN(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'placements')[0]),'x')-1.08)<0.00001),'copied placement survives normal character and layout stages');
    W.SetScriptText('body','新しく入力した本文。');
    var P := W.ScriptDraft; PrepareScriptCasting(P); ValidateScriptVoice(P);
    var Role := TJSONObject(JA(JO(P.ScriptWizard,'casting'),'roles')[0]);
    Check(P.Speaker(JS(Role,'speakerId')).StyleId=77,'copied character style applies when new casting is prepared');
    Check(JN(P.EffectiveVoiceSettings(P.Cues[0]),'speedScale')=1.25,'copied common settings apply to new dialogue');
    var EmptyAudio := True;
    for var C in P.Cues do EmptyAudio := EmptyAudio and (C.WaveFile='') and (C.LabFile='') and (C.AudioKey='') and
      (C.VoiceQuery='') and (C.VoiceReading='') and (C.VoiceSettings.Count=0);
    Check(EmptyAudio,'new dialogue has no source audio, reading overrides or per-line accent settings');
    var Current := W.ScriptDraft; Current.Modified := True; var Rejected := False;
    try W.CopyScriptDraft(SourcePath); except on E: Exception do Rejected := True; end;
    Check(Rejected and (W.ScriptDraft=Current) and Current.Modified,'copy preserves and refuses to discard unsaved current input');
    Current.Modified := False; Rejected := False;
    try W.CopyScriptDraft(TPath.Combine(Root,'missing.rigmovie')); except on E: Exception do Rejected := True; end;
    Check(Rejected and (W.ScriptDraft=Current),'failed source load preserves the active draft');
    W.CurrentPage := apScripts; W.NewScriptDraft;
    Check((W.ScriptDraft.Id<>FirstId) and (JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=0),'original new creation still creates an empty script');
    var EmptyCopy := CreateScriptCopy(W.ScriptDraft,'2026-10-12T00:00:00Z');
    try Check((EmptyCopy.ScriptWizard.GetValue('voice')=nil) and (JS(ScriptSection(EmptyCopy,'body'),'text')=''),'early draft without text or voice settings can be copied');
    finally EmptyCopy.Free; end;
    CheckClosingTitleRename;
    Check(SourceHash=THashSHA2.GetHashStringFromFile(SourcePath),'original saved script remains byte-for-byte unchanged');
    for var Pair in OriginalFiles do Check(THashSHA2.GetHashStringFromFile(Pair.JsonString.Value)=Pair.JsonValue.Value,'original asset retained '+ExtractFileName(Pair.JsonString.Value));
  finally Probe.Free; Host.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1); Error := ''; Checks := TJSONArray.Create;
  try
    try
      ForceDirectories(Root); W := TRigmWizardWorkspace.Create(nil);
      try W.StartPipe(TPath.Combine(Root,'OwnedData')); Run; finally W.Free; end;
    except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln('FAIL ',Error); end; end;
    var O := TJSONObject.Create;
    try O.AddPair('checks',Checks.Clone as TJSONArray); O.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally OriginalFiles.Free; Checks.Free; end;
  if Error<>'' then Halt(1);
end.
