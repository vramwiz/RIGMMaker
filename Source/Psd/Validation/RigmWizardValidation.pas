unit RigmWizardValidation;
interface
uses RigmWizardMainForm;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  RigmPageNavigation, PsdStudioFrame, PsdJson, RigmCharacterEditPage,
  RigmScriptCreatorFrame, RigmMovieWorkspaceFrame, RigmJson;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Wizard validation failed: '+Text); Results.Add(Text); end;
begin
  var Owner := ObjectText(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if S(Owner,'owner')<>'RIGMMaker.GuiValidation.v1' then raise Exception.Create('Owned GUI validation root required'); finally Owner.Free; end;
  var Results := TJSONArray.Create;
  try
    Check((Main.CurrentPage=apHome) and (Main.CreatedPageCount=1) and (Main.PageInstance(apCharacterEdit)=nil),'startup creates only home',Results);
    Main.Position := poDesigned; Main.SetBounds(-1400,-1000,1280,840); Main.Show; Main.Update; Application.ProcessMessages;
    Check(Screen.FormCount=1,'one top-level form at startup',Results);
    TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click;
    Check((Main.CurrentPage=apCharacters) and (Main.CreatedPageCount=2),'first navigation creates only requested management frame',Results);
    var Manager := Main.PageInstance(apCharacters); var List := TListView(Manager.FindComponent('CharacterLibrary'));
    Check((List.Items.Count>0) and (List.Selected<>nil),'registered character visible in management',Results);
    var Path := List.Selected.SubItems[1]; var OriginalHash := THashSHA2.GetHashStringFromFile(Path);
    TButton(Manager.FindComponent('CharacterOpen')).Click;
    var EditHost := TRigmCharacterEditPage(Main.PageInstance(apCharacterEdit)); var Editor := EditHost.PsdEditor;
    Check((Main.CurrentPage=apCharacterEdit) and (Main.CreatedPageCount=3) and (Editor.Session.Character<>nil),'management opens editor frame in same form',Results);
    var Name := TEdit(Editor.FindComponent('PsdCharacterName')); Name.Text := Name.Text+'（保持する下書き）';
    var Draft := Name.Text; var Id := Editor.Session.Character.Id;
    var Pages := TPageControl(Editor.FindComponent('PsdCharacterPages')); Pages.ActivePageIndex := 2; Pages.OnChange(Pages);
    TButton(Editor.FindComponent('PsdReturnToManagement')).Click;
    Check((Main.CurrentPage=apCharacters) and (Main.PageInstance(apCharacters)=Manager),'editor returns to existing management frame',Results);
    TButton(Main.FindComponent('WizardHome')).Click;
    TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click; TButton(Manager.FindComponent('CharacterOpen')).Click;
    Check((Main.PageInstance(apCharacterEdit)=EditHost) and (EditHost.PsdEditor=Editor) and (Editor.Session.Character.Id=Id) and (Name.Text=Draft) and (Pages.ActivePageIndex=2),'home and same-character return preserve frame, identity, draft and page',Results);
    Check(THashSHA2.GetHashStringFromFile(Path)=OriginalHash,'navigation does not save unapplied draft',Results);
    Name.Text := Editor.Session.Character.Name; TButton(Editor.FindComponent('PsdInfoApply')).Click;
    Editor.VerifyPageFlow(ResultPath+'.pages.json');
    Check(Screen.FormCount=1,'PSD page workflow keeps one main form',Results);
    if SmokePath<>'' then Editor.CaptureSmoke(SmokePath);
    TButton(Main.FindComponent('WizardHome')).Click; TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.CurrentPage=apScripts) and (Main.CreatedPageCount=4),'script management lazily created',Results);
    var Scripts := Main.PageInstance(apScripts); TButton(Scripts.FindComponent('ScriptNew')).Click;
    Check((Main.CurrentPage=apScriptCreate) and (Main.CreatedPageCount=5),'script creation lazily creates existing creation UI',Results);
    var Creator := TRigmScriptCreatorFrame(Main.PageInstance(apScriptCreate)); var Script := TMemo(Creator.Creator.FindComponent('CreationScript'));
    Script.Text := 'フレーム移行の短い検証台本です。'; var ScriptDraft := Script.Text;
    TButton(Creator.FindComponent('CreationGoMovie')).Click;
    Check((Main.CurrentPage=apMovieEdit) and (Main.CreatedPageCount=6),'movie navigation lazily creates existing editor frame',Results);
    var MovieHost := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)); var Movie := MovieHost.CurrentEditor;
    Check(Movie.Session=Main.Workspace.ActiveSession,'creation and movie share the same session',Results);
    Main.NavigateTo(apScriptCreate); Check(Script.Text=ScriptDraft,'unapplied script draft retained across movie navigation',Results);
    Main.NavigateTo(apMovieEdit); Check(MovieHost.CurrentEditor=Movie,'movie editor reused after page return',Results);
    var Title := TEdit(Movie.FindComponent('MovieTitle')); Title.Text := '移行後の保存検証';
    Main.NavigateTo(apHome); Main.NavigateTo(apMovieEdit); Check(Title.Text='移行後の保存検証','movie input draft retained across home return',Results);
    Movie.InvokeAction(14);
    var A := TJSONObject.Create; var Session := Movie.Session;
    try A.AddPair('path',TPath.Combine(Main.DataRoot,'saved-frame-work.rigmovie')); A.AddPair('projectId',Session.Project.Id); RigmJson.AddN(A,'revision',Session.Project.Revision); var R := Session.Execute('save',A); R.Free;
    finally A.Free; end;
    Check(not Session.Project.Modified and FileExists(Session.Project.FileName),'existing session save writes movie project',Results);
    var SavedPath := Session.Project.FileName; Main.Workspace.OpenWork(SavedPath);
    Check((Main.Workspace.ActiveSession=Session) and (MovieHost.CurrentEditor=Movie),'reopening active saved work preserves existing editor',Results);
    TButton(Main.FindComponent('WizardHome')).Click;
    Check(Main.CurrentPage=apHome,'movie returns home through main navigation',Results);
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.PageInstance(apScripts)=Scripts) and (Main.CreatedPageCount=6) and (Screen.FormCount=1),'repeated navigation reuses owned frames without additional forms',Results);
    Main.NavigateTo(apCharacterEdit); TButton(EditHost.FindComponent('CharacterLegacyEditor')).Click;
    var Legacy := EditHost.LegacyEditor;
    Check((Legacy<>nil) and (Screen.FormCount=1),'legacy character editor created lazily in same form',Results);
    Legacy.OpenSample; var RigPath := TPath.Combine(Main.DataRoot,'RIGM\legacy-frame-fixture.rigm'); ForceDirectories(ExtractFileDir(RigPath)); Legacy.Editor.Save(RigPath);
    Check(Legacy.SaveCharacter and FileExists(RigPath),'legacy explicit save uses existing editor persistence',Results);
    Legacy.Editor.NewDocument('未保存の保持検証',256,320); var LegacyId := Legacy.Editor.Document.FileId;
    Main.NavigateTo(apHome); Main.NavigateTo(apCharacterEdit);
    Check((EditHost.LegacyEditor=Legacy) and (Legacy.Editor.Document.FileId=LegacyId) and Legacy.Editor.Modified,'legacy unsaved document survives home return',Results);
    Legacy.Editor.Save(RigPath); Legacy.OpenFile(RigPath);
    Check((Legacy.Editor.Document.Name='未保存の保持検証') and not Legacy.Editor.Modified,'legacy save and reopen retain document',Results);
    Check(Screen.FormCount=1,'all migrated pages retain a single main form',Results);
    TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
end.
