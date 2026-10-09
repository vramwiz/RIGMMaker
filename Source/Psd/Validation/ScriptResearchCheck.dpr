program ScriptResearchCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Hash,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.ComCtrls,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmWizardWorkspace, RigmScriptCreatorFrame, RigmScriptReviewFrame, RigmScriptTextFrame,
  RigmScriptNavigationModel, RigmScriptNavigationProbe, RigmPageNavigation,
  RigmMovieModel, RigmMovieComposition, RigmScriptTextModel, RigmScriptResearchModel,
  RigmModel, RigmSample, RigmStorage, RigmJson, PsdJson;
{$R *.res}
var Main: TRigmWizardMainForm; W: TRigmWizardWorkspace; Creator: TRigmScriptCreatorFrame;
  Review: TRigmScriptReviewFrame; Root,Error,Body: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
procedure Capture(const Name: string);
begin
  Application.ProcessMessages;
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try Bitmap.SetSize(Main.ClientWidth,Main.ClientHeight); Main.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
function Args(const Text: string = '{}'): TJSONObject;
begin
  Result := PsdJson.ObjectText(Text); Result.AddPair('projectId',W.ScriptDraft.Id); AddN(Result,'revision',W.ScriptDraft.Revision);
  if ScriptResearch(W.ScriptDraft)<>nil then Result.AddPair('researchId',JS(ScriptResearch(W.ScriptDraft),'researchId'));
end;
procedure Send(const Action,Text: string; Rejected: Boolean = False);
begin
  var A := Args(Text); var Before := W.ScriptDraft.Json; var Failed := False;
  try
    try var Reply := W.Command('app-script-research-'+Action,A); Reply.Free;
    except on E: Exception do begin Failed := True; if not Rejected then raise; end; end;
    if Rejected then begin
      Check(Failed,'reject '+Action); var After := W.ScriptDraft.Json;
      try Check(Before.ToJSON=After.ToJSON,'rejected '+Action+' preserves project'); finally After.Free; end;
    end else Check(not Failed,'accept '+Action);
  finally Before.Free; A.Free; end;
end;
function R: TJSONObject;
begin Result := ScriptResearch(W.ScriptDraft); end;
procedure ConfirmWork;
begin
  (Review.FindComponent('ScriptResearchConfirmed') as TCheckBox).Checked := True; Application.ProcessMessages;
  Check(ResearchWorkReady(R),'GUI alone confirms selected work');
end;
procedure Run;
begin
  Root := ParamStr(1); if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh output root required');
  var DataRoot := TPath.Combine(Root,'OwnedData'); ForceDirectories(TPath.Combine(DataRoot,'RIGM'));
  var Document := TRigmDocument.Create;
  try PopulateRigmSample(Document); Document.Usable := True; SaveRigm(Document,TPath.Combine(DataRoot,'RIGM\fixture.rigm'));
  finally Document.Free; end;
  Main := TRigmWizardMainForm.Create(nil); W := Main.Workspace; Main.ScaleForPPI(96);
  Main.SetBounds(0,0,1360,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update; W.NewScriptDraft; Main.NavigateTo(apScriptCreate);
  Creator := Main.PageInstance(apScriptCreate) as TRigmScriptCreatorFrame;
  W.SetScriptTitle('作品情報の確認用タイトル'); W.SetScriptType('anime-review'); W.NextScriptDraft;
  var Deadline := GetTickCount64+10000;
  repeat
    Application.ProcessMessages; var Ready := False;
    for var Item in (Creator.FindComponent('ScriptCharacters') as TListView).Items do
      if JB(TJSONObject(Item.Data),'readyForScript') then begin Item.Checked := True; Ready := True; end;
    if Ready then Break; Sleep(10);
  until GetTickCount64>Deadline;
  Check(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters').Count=1,'owned fixture character is ready');
  W.NextScriptDraft; W.NextScriptDraft; W.NextScriptDraft;
  Body := '人間が書いた評価です。'+#13#10+'この意見を勝手に変えません。';
  var TextFrame: TRigmScriptTextFrame := nil;
  for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptTextFrame then TextFrame := TRigmScriptTextFrame(Creator.Components[I]);
  var Editor := TextFrame.FindComponent('ScriptText1') as TMemo;
  Editor.SetFocus; Editor.Text := Body; Editor.Perform(WM_KEYDOWN,VK_END,0);
  Check((GetFocus=Editor.Handle) and not W.ScriptTextEditing,'focused human script input does not lock communication');
  var Status := W.ScriptStatus;
  try Check(not JB(Status,'textEditing'),'pipe status reports no text input lock'); finally Status.Free; end;
  var Patch := Args('{"section":"body","offset":0,"removeCount":0,"text":"通信の追記。"}');
  try var Reply := W.Command('app-script-set-text',Patch); Reply.Free; finally Patch.Free; end;
  Check((Editor.Text='通信の追記。'+Body) and (GetFocus=Editor.Handle),'pipe text update appears without leaving the editor');
  Editor.Text := Body;
  W.NextScriptDraft;
  for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptReviewFrame then Review := TRigmScriptReviewFrame(Creator.Components[I]);
  Check((Review<>nil) and (W.CurrentScriptStage='review'),'stage six opens research frame');
  Check(JS(R,'title')='作品情報の確認用タイトル','work title starts from script title');
  Check(not JB(R,'definitionsReady') and (JA(R,'elements').Count=0),'undefined element types are not invented');
  Check((Creator.FindComponent('ScriptStages') as TListBox).ItemHeight=30,'navigation uses one line');
  Check(Review.FindComponent('ScriptReviewToolbar')=nil,'no UI prompt request control');
  Send('definitions','{"scriptType":"anime-review","elements":[{"id":"one","label":"確認用の要素1"},{"id":"two","label":"確認用の要素2"},{"id":"three","label":"確認用の要素3"},{"id":"four","label":"確認用の要素4"},{"id":"five","label":"確認用の要素5"},{"id":"six","label":"確認用の要素6"}]}');
  (Review.FindComponent('ScriptResearchTitle') as TEdit).SetFocus;
  Send('candidates','{"candidates":[{"id":"work-a","name":"確認用作品A","overview":"検証用の概要です。実在作品の情報ではありません。","identity":"確認用作者 ／ 2026年 ／ 検証用ジャンル","sources":["https://example.com/work-a"]}]}');
  Check((GetFocus=TEdit(Review.FindComponent('ScriptResearchTitle')).Handle) and not W.ScriptTextEditing,'candidate update succeeds while work title retains focus');
  Check((JS(R,'selectedCandidateId')='work-a') and not JB(R,'humanConfirmed'),'single candidate selected without approval');
  Check(Pos('検証用の概要',TMemo(Review.FindComponent('ScriptResearchOverview')).Text)>0,'selected candidate overview is shown in memo');
  Check(Review.CurrentPPI=Creator.CurrentPPI,'research frame adopts parent DPI on creation');
  Send('confirm-work','{"confirmed":true}',True);
  Send('element','{"id":"one","workId":"work-a","state":"checking"}',True);
  Capture('identify-96'); ConfirmWork;
  Send('element','{"id":"one","workId":"another-work","state":"checking"}',True);
  Send('element','{"id":"one","workId":"work-a","name":"確認用名称","summary":"概要の前半\n後半","details":"検証用の詳細です。","state":"checking"}');
  Check(JS(R,'expandedElementId')='one','current element expands automatically');
  Check(ResearchSingleLine(JS(ResearchElement(R,'one'),'summary'))='概要の前半 後半','collapsed overview has no line breaks');
  Capture('deepen-96');
  for var Ppi in [144,192] do begin
    Main.ScaleForPPI(Ppi); Main.SetBounds(0,0,MulDiv(1360,Ppi,96),MulDiv(840,Ppi,96)); Application.ProcessMessages;
    Check((Creator.FindComponent('ScriptStages') as TListBox).ItemHeight=MulDiv(30,Ppi,96),'single line navigation at '+Ppi.ToString+' DPI');
    var Scroll := Review.FindComponent('ScriptResearchElements') as TScrollBox;
    Check(Scroll.ClientWidth>0,'research editor has usable width at '+Ppi.ToString+' DPI'); Capture('deepen-'+Ppi.ToString);
  end;
  Main.ScaleForPPI(96); Main.SetBounds(0,0,1360,840);
  Send('element','{"id":"one","workId":"work-a","state":"confirmed-info"}');
  for var Id in ['two','three','four','five','six'] do Send('element','{"id":"'+Id+'","workId":"work-a","state":"confirmed-none"}');
  Check(ResearchAdvanceReason(W.ScriptDraft)='','information missing is completed, not an error');
  var Integration := ResearchIntegrationData(W.ScriptDraft);
  try Check((JA(Integration,'elements').Count=1) and (JS(TJSONObject(JA(Integration,'elements')[0]),'id')='one'),'integration excludes no-information results'); finally Integration.Free; end;
  Send('add','{"id":"extra","label":"任意の追加調査"}');
  Check(ResearchAdvanceReason(W.ScriptDraft)<>'','unfinished additional element blocks next stage');
  var State := W.ScriptStatus;
  try Check(not JB(State,'canAdvance'),'workspace blocks pending additional element'); finally State.Free; end;
  Send('element','{"id":"extra","workId":"work-a","state":"confirmed-none"}');
  var SavedResearch := R.ToJSON; W.SaveScriptDraft; var Path := W.ScriptDraft.FileName; W.OpenScriptDraft(Path);
  Check((R.ToJSON=SavedResearch) and ResearchWorkReady(R),'save and reopen retain research, human approval, and extra elements');
  Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=Body,'original opinion remains unchanged');
  // Wait only for this owned probe's Named Pipe tests. Never operate on the normal app.
  var Info := W.Pipe.Info;
  try TFile.WriteAllText(TPath.Combine(Root,'ready-for-pipe.json'),Info.ToJSON,TEncoding.UTF8); finally Info.Free; end;
  (Review.FindComponent('ScriptResearchTitle') as TEdit).SetFocus;
  Deadline := GetTickCount64+50000;
  while not FileExists(TPath.Combine(Root,'pipe-done.json')) do begin
    Application.ProcessMessages; Sleep(10); if GetTickCount64>Deadline then raise Exception.Create('Pipe tests timed out');
  end;
  Check(not JB(R,'humanConfirmed'),'pipe re-search resets human confirmation');
  Check((GetFocus=TEdit(Review.FindComponent('ScriptResearchTitle')).Handle) and not W.ScriptTextEditing,'real named pipe update retains title focus without an input lock');
  Check(Pos('再検索した検証用概要',TMemo(Review.FindComponent('ScriptResearchOverview')).Text)>0,'real named pipe candidate overview is redrawn while title has focus');
  ConfirmWork;
  for var Id in ['one','two','three','four','five','six','extra'] do Send('element','{"id":"'+Id+'","workId":"work-a","state":"confirmed-none"}');
  var OldId := JS(R,'researchId'); var Bad := Args('{"title":"wrong"}');
  PsdJson.Put(Bad,'researchId','old-search');
  var Failed := False;
  try try var Reply := W.Command('app-script-research-title',Bad); Reply.Free; except on E: Exception do Failed := True; end;
  finally Bad.Free; end;
  Check(Failed and (JS(R,'researchId')=OldId),'old search token is rejected');
  Send('candidates','{"candidates":[{"id":"duplicate","name":"a","overview":"a"},{"id":"duplicate","name":"b","overview":"b"}]}',True);
  var CheckBox := Review.FindComponent('ScriptResearchConfirmed') as TCheckBox;
  CheckBox.Checked := False; Check(not ResearchWorkReady(R),'unchecking work releases all confirmation'); ConfirmWork;
  for var Id in ['one','two','three','four','five','six','extra'] do Send('element','{"id":"'+Id+'","workId":"work-a","state":"confirmed-none"}');
  W.NextScriptDraft; Check(W.CurrentScriptStage='casting','confirmed research advances to existing next stage');
  Check(JA(JO(W.ScriptDraft.ScriptWizard,'researchIntegration'),'elements').Count=0,'next stage snapshot excludes missing information');
  Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=Body,'advancing does not rewrite human script');
  W.SetScriptStage('review');
  Send('candidates','{"candidates":[{"id":"work-a","name":"確認用作品A","overview":"概要A"},{"id":"work-b","name":"確認用作品B","overview":"概要B"}]}');
  Check((JS(R,'selectedCandidateId')='') and not JB(R,'humanConfirmed'),'multiple candidates require explicit selection');
  Send('select','{"id":"work-b"}'); ConfirmWork;
  Send('element','{"id":"one","workId":"work-b","name":"作品Bの名称","summary":"作品Bの確認用情報","state":"confirmed-info"}');
  Send('select','{"id":"work-a"}');
  Check(not JB(R,'humanConfirmed') and (JS(ResearchElement(R,'one'),'state')='unconfirmed') and (JS(ResearchElement(R,'one'),'name')=''),'candidate change invalidates previous work details');
  (Review.FindComponent('ScriptResearchTitle') as TEdit).SetFocus;
  Send('title','{"title":"別の作品タイトル"}');
  Check((TEdit(Review.FindComponent('ScriptResearchTitle')).Text='別の作品タイトル') and (GetFocus=TEdit(Review.FindComponent('ScriptResearchTitle')).Handle),'external title update is shown even while title field retains focus');
  Check((JA(R,'candidates').Count=0) and not JB(R,'humanConfirmed'),'title edit invalidates candidates and confirmation');
  Check(JA(W.ScriptDraft.ScriptWizard,'researchArchives').Count>0,'invalidated research is preserved in archives');
  var JumpFailed := False; try W.SetScriptStage('casting'); except on E: Exception do JumpFailed := True; end;
  Check(JumpFailed and (W.CurrentScriptStage='review'),'reached later stage cannot bypass invalidated research');
  W.SaveScriptDraft; W.OpenScriptDraft(Path); Check(JS(R,'title')='別の作品タイトル','edited title persists on reopen');
  W.SetScriptType('manga-introduction');
  Check((JS(R,'scriptType')='manga-introduction') and not JB(R,'definitionsReady') and (JA(R,'elements').Count=0),'script type change invalidates definitions without inventing new elements');
  W.SaveScriptDraft; W.OpenScriptDraft(Path); ValidateScriptResearch(W.ScriptDraft);
  Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=Body,'type change retains human script');
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  if Root<>'' then begin
    var Report := TJSONObject.Create;
    try Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  end;
  Main.Free; Checks.Free;
end.
