program PostingCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  Winapi.Windows, Winapi.ActiveX, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Clipbrd, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmMovieModel, RigmMoviePosting, RigmMovieSession, RigmMovieForm, RigmMovieEditorFrame, RigmMovieWorkflow,
  RigmMoviePostingFrame, RigmNicoManga, RigmScriptResearchModel, RigmScriptTextModel, RigmJson, PsdJson,
  RigmWizardMainForm, RigmWizardWorkspace, RigmScriptReviewFrame;
{$R *.res}
var Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS ',Name); end;
procedure Capture(Control: TWinControl; const Name: string);
begin
  var B := TBitmap.Create; var Png := TPngImage.Create;
  try B.SetSize(Control.Width,Control.Height); Control.PaintTo(B.Canvas,0,0);
    Png.Assign(B); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; B.Free; end;
end;
function Copied(Button: TButton; const Expected: string): Boolean;
begin
  Result := False; var Deadline := GetTickCount64+1000;
  repeat
    Button.OnClick(Button); Sleep(40);
    try Result := Clipboard.AsText=Expected; except on E: EClipboardException do Result := False; end;
    if Result then Exit; Application.ProcessMessages;
  until GetTickCount64>=Deadline;
end;
function Fixture: TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create; Result.Title := '猫と手';
  Result.ScriptWizard := PsdJson.ObjectText('{"titleInput":"猫と手","scriptType":"manga-introduction","createdAt":"2026-10-10T23:37:01Z"}');
  PrepareScriptResearch(Result);
  var Cue := TRigmMovieCue.Create; Cue.Id := 'posting-fixture'; Cue.SpeakerId := 'narrator'; Cue.Text := '検証用のセリフ'; Cue.Subtitle := Cue.Text;
  Cue.AudioKey := StringOfChar('a',64); Cue.VoiceHeardKey := StringOfChar('b',64); Result.Cues.Add(Cue);
end;
procedure Models;
const Names: array[0..2] of string = ('MovieCopyPostingTitle','MovieCopyPostingDescription','MovieCopyPostingParents');
begin
  var P := Fixture;
  try
    var Info := MoviePostingInfo(P);
    try Check(JS(Info,'title')='【ニコニコ漫画】ニコニコ漫画の作品を紹介する　猫と手  #60 【2026年10月11日】','title uses manual 60 and local creation date');
      Check(JS(Info,'description')='','unconfirmed work does not supply publication facts');
    finally Info.Free; end;
    var C := ParseNicoComic(TFile.ReadAllText(ParamStr(2)+'\niconico-sample.html',TEncoding.UTF8),'https://manga.nicovideo.jp/comic/77802');
    try
      Check((JS(C,'name')='猫と手') and (JS(C,'author')='色鳥こぼし'),'real public HTML supplies correct work and author');
      Check((JS(C,'niconicoUrl')='https://manga.nicovideo.jp/comic/77802') and (JS(C,'overview')<>''),'real public HTML supplies canonical link and overview');
      var A := TJSONObject.Create; var Candidates := TJSONArray.Create; A.AddPair('candidates',Candidates); Candidates.AddElement(C.Clone as TJSONObject);
      try ApplyScriptResearch(P,'candidates',A,True); finally A.Free; end;
      Check(MoviePostingDescription(P)='','search result remains unapproved');
      A := PsdJson.ObjectText('{"confirmed":true}'); try ApplyScriptResearch(P,'confirm-work',A,True); finally A.Free; end;
      Check(MoviePostingDescription(P)='猫と手'+#13#10+'作者:色鳥こぼし'+#13#10+'https://manga.nicovideo.jp/comic/77802','approved work produces requested three-line description');
      var Selected := ResearchCandidate(ScriptResearch(P),'nico-77802'); Selected.AddPair('postingSummary','猫と不思議な手の交流を紹介します。');
      Check(MoviePostingDescription(P).Contains(#13#10+#13#10+'猫と不思議な手の交流を紹介します。'),'optional original AI introduction follows the source block');
    finally C.Free; end;
    var Urls := NicoSearchUrls(TFile.ReadAllText(ParamStr(2)+'\niconico-search.html',TEncoding.UTF8));
    Check((Length(Urls)=1) and (Urls[0]='https://manga.nicovideo.jp/comic/77802'),'search parser deduplicates thumbnail and title links');
    Check(not NicoComicUrl('javascript:alert(1)') and not NicoComicUrl('https://manga.nicovideo.jp.evil.test/comic/1'),'URL guard only permits canonical Nico comic pages');
    var S := TRigmMovieSession.Create;
    try
      S.SetProject(P); P := nil; var Key := MovieRenderKey(S.Project); var Revision := S.Project.Revision;
      var A := TJSONObject.Create;
      try A.AddPair('projectId',S.Project.Id); AddN(A,'revision',Revision); A.AddPair('title','手動変更 #61'); A.AddPair('description','複数行の概要'+#13#10+'編集内容');
        var Reply := S.Execute('update-posting',A); Reply.Free;
        Check((MovieRenderKey(S.Project)=Key) and (S.Project.Cues[0].AudioKey=StringOfChar('a',64)) and (S.Project.Cues[0].VoiceHeardKey=StringOfChar('b',64)),'posting edits preserve rendered-video key and audio confirmation');
        var Before := S.Project.Json; var Rejected := False;
        try try Reply := S.Execute('update-posting',A); Reply.Free; except Rejected := True; end;
          var After := S.Project.Json; try Check(Rejected and (Before.ToJSON=After.ToJSON),'stale posting revision is rejected atomically'); finally After.Free; end;
        finally Before.Free; end;
      finally A.Free; end;
      var Path := TPath.Combine(Root,'posting.rigmovie'); SaveMovie(S.Project,Path);
      var Loaded := LoadMovie(Path);
      try Check((JS(Loaded.Posting,'title')='手動変更 #61') and (JS(Loaded.Posting,'description')='複数行の概要'+#13#10+'編集内容') and
        (JS(Loaded.Posting,'createdDate')='2026-10-11'),'save and reopen retain manual number, multiline description and creation date');
      finally Loaded.Free; end;
      A := TJSONObject.Create;
      try A.AddPair('projectId',S.Project.Id); AddN(A,'revision',S.Project.Revision);
        A.AddPair('id',S.Project.Cues[0].Id); A.AddPair('subtitle','取り消し検証');
        var Reply := S.Execute('update-cue',A); Reply.Free;
      finally A.Free; end;
      A := TJSONObject.Create;
      try A.AddPair('projectId',S.Project.Id); AddN(A,'revision',S.Project.Revision); A.AddPair('title','履歴とは独立した投稿タイトル #61');
        var Reply := S.Execute('update-posting',A); Reply.Free;
      finally A.Free; end;
      for var Command in ['undo','redo'] do begin
        A := TJSONObject.Create;
        try A.AddPair('projectId',S.Project.Id); AddN(A,'revision',S.Project.Revision);
          var Reply := S.Execute(Command,A); Reply.Free;
          Check(JS(S.Project.Posting,'title')='履歴とは独立した投稿タイトル #61','video '+Command+' retains independently edited posting text');
        finally A.Free; end;
      end;
      var Editor := TRigmMovieForm.CreateForSession(nil,S);
      try
        Editor.Show; for var I := 0 to Editor.ComponentCount-1 do if Editor.Components[I] is TTimer then TTimer(Editor.Components[I]).Enabled := False;
        var Panel := Editor.FindComponent('MoviePosting') as TRigmMoviePostingFrame;
        var Title := Panel.FindComponent('MoviePostingTitle') as TEdit;
        var Description := Panel.FindComponent('MoviePostingDescription') as TMemo;
        Check((Editor.PropertyPageName='posting') and Panel.Visible,'editor starts on posting page');
        Check(not TControl(Editor.FindComponent('MovieCueText')).Visible and not TControl(Editor.FindComponent('MovieVoiceStyle')).Visible,'old dialogue and VOICEVOX reset controls are absent from the displayed UI');
        var Refreshes := Editor.ViewRefreshCount; var Previews := Editor.PreviewRequests; Key := MovieRenderKey(S.Project);
        Title.Text := '入力したタイトル #62'; Description.Text := '作品名'+#13#10+'作者:検証'+#13#10+'https://manga.nicovideo.jp/comic/77802';
        Check((JS(S.Project.Posting,'title')=Title.Text) and (JS(S.Project.Posting,'description')=Description.Text),'native edits immediately reach the saved project model');
        Check((Editor.ViewRefreshCount=Refreshes) and (Editor.PreviewRequests=Previews) and (MovieRenderKey(S.Project)=Key),'typing posting fields does not refresh the editor or regenerate preview');
        var Original: IDataObject; OleGetClipboard(Original);
        try
          for var I := 0 to 2 do begin
            var B := Panel.FindComponent(Names[I]) as TButton;
            var Expected := Title.Text; if I=1 then Expected := Description.Text else if I=2 then Expected := MovieParentWorks;
            Check(Copied(B,Expected),'copy button transfers complete field '+I.ToString);
          end;
        finally if Original<>nil then OleSetClipboard(Original); end;
        Capture(Editor,'posting-editor');
        Editor.SelectPropertyPage('scene'); Editor.SelectPropertyPage('posting');
        Check((Title.Text='入力したタイトル #62') and (Description.Lines.Count=3),'property page changes retain posting edits');
      finally Editor.Free; end;
      var Host := TForm.Create(nil); Host.ScaleForPPI(96); Host.SetBounds(0,0,1380,1000);
      try
        var Embedded := TRigmMovieEditorFrame.CreateForSession(Host,S,True);
        try
          for var I := 0 to Embedded.ComponentCount-1 do if Embedded.Components[I] is TTimer then TTimer(Embedded.Components[I]).Enabled := False;
          Host.Show; ShowWindow(Host.Handle,SW_SHOWNOACTIVATE);
          var Panel := Embedded.FindComponent('MoviePosting') as TRigmMoviePostingFrame;
          var BeforeRefresh := Embedded.ViewRefreshCount; var BeforePreview := Embedded.PreviewRequests;
          (Panel.FindComponent('MoviePostingTitle') as TEdit).Text := '埋込み画面のタイトル #63';
          Check((JS(S.Project.Posting,'title')='埋込み画面のタイトル #63') and (Embedded.ViewRefreshCount=BeforeRefresh) and
            (Embedded.PreviewRequests=BeforePreview),'embedded editor updates posting text without refreshing video');
          for var Name in Names do begin
            var B := Panel.FindComponent(Name) as TButton;
            Check(B.Visible and B.Enabled and B.CanFocus,'embedded copy button is visible and operable '+Name);
          end;
          Capture(Host,'posting-embedded');
        finally Embedded.Free; end;
      finally Host.Free; end;
    finally S.Free; end;
  finally P.Free; end;
end;
procedure PostingDuringPreview;
begin
  var S := TRigmMovieSession.Create;
  try
    var P := Fixture; P.CharacterFile := '@sample'; P.Width := 320; P.Height := 180; S.SetProject(P);
    var Reply := S.PreviewFrame(0,320,180); Reply.Free;
    var Args := TJSONObject.Create;
    try Args.AddPair('projectId',S.Project.Id); AddN(Args,'revision',S.Project.Revision); Args.AddPair('title','描画中に入力した投稿タイトル');
      Reply := S.Execute('update-posting',Args); Reply.Free;
    finally Args.Free; end;
    var Deadline := GetTickCount64+20000;
    while S.Busy and (GetTickCount64<Deadline) do begin CheckSynchronize(0); Sleep(10); end;
    S.Poll; var Frame := S.TakeFrame;
    try Check((Frame<>nil) and (JS(S.Project.Posting,'title')='描画中に入力した投稿タイトル'),'posting during a preview retains both the completed frame and metadata');
    finally Frame.Free; end;
  finally S.Free; end;
end;
procedure LiveSearch;
begin
  var Main := TRigmWizardMainForm.Create(nil);
  try
    var W := Main.Workspace; W.NewScriptDraft;
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'stage','review'); PsdJson.Put(W.ScriptDraft.ScriptWizard,'titleInput','猫と手');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'furthestStage','review');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(W.ScriptDraft.ScriptWizard,'layoutStatus','in-progress');
    PsdJson.Put(W.ScriptDraft.ScriptWizard,'backgroundTone','dark'); PrepareScriptText(W.ScriptDraft);
    PrepareScriptResearch(W.ScriptDraft);
    var Path := W.ScriptDraft.FileName; SaveMovie(W.ScriptDraft,Path); W.OpenScriptDraft(Path);
    Check(W.CurrentScriptStage='review','owned search fixture resumes its stored research stage');
    var Review := TRigmScriptReviewFrame.CreateForWorkspace(Main,W);
    try
      Review.Parent := Main; Review.RefreshState;
      var Button := Review.FindComponent('ScriptResearchNicoSearch') as TButton;
      var Started := GetTickCount64; Button.OnClick(Button);
      Check(GetTickCount64-Started<250,'native Nico search starts without blocking the UI');
      var Deadline := GetTickCount64+30000;
      while not Button.Enabled and (GetTickCount64<Deadline) do begin Application.ProcessMessages; CheckSynchronize(0); Sleep(10); end;
      var R := ScriptResearch(W.ScriptDraft);
      TFile.WriteAllText(TPath.Combine(Root,'live-search-state.json'),R.ToJSON,TEncoding.UTF8);
      Writeln('SEARCH ',W.CurrentScriptStage,' ',(Review.FindComponent('ScriptResearchGuide') as TLabel).Caption);
      Check(Button.Enabled and (JA(R,'candidates').Count=1) and not JB(R,'humanConfirmed'),'live search adopts the Nico candidate without approving it');
      var Link := Review.FindComponent('ScriptResearchNicoUrl') as TLinkLabel;
      Check((Pos('https://manga.nicovideo.jp/comic/77802',Link.Caption)>0) and Assigned(Link.OnLinkClick),'selected Nico URL is visible and clickable');
      Capture(Review,'nico-search-result');
      Button.OnClick(Button); (Review.FindComponent('ScriptResearchTitle') as TEdit).Text := '検索中に変更した作品';
      Deadline := GetTickCount64+30000;
      while not Button.Enabled and (GetTickCount64<Deadline) do begin Application.ProcessMessages; CheckSynchronize(0); Sleep(10); end;
      Check(Button.Enabled and (JA(ScriptResearch(W.ScriptDraft),'candidates').Count=0),'late search result cannot overwrite changed title or research identity');
      Capture(Review,'nico-research');
    finally Review.Free; end;
  finally Main.Free; end;
end;
begin
  Root := ParamStr(1); ForceDirectories(Root); Checks := TJSONArray.Create; OleInitialize(nil);
  try
    try Application.Initialize; Models; PostingDuringPreview; LiveSearch;
    except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); end; end;
    var Report := TJSONObject.Create;
    try Report.AddPair('checks',Checks); Checks := nil; if Error<>'' then Report.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; OleUninitialize; end;
  if Error<>'' then Halt(1);
end.
