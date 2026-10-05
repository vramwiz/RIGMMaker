unit RigmWizardValidation;
interface
uses RigmWizardMainForm;
procedure VerifyWizard(Main: TRigmWizardMainForm; const ResultPath,SmokePath: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  RigmPageNavigation, PsdStudioFrame, PsdJson;
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
    var Editor := TPsdStudioFrame(Main.PageInstance(apCharacterEdit));
    Check((Main.CurrentPage=apCharacterEdit) and (Main.CreatedPageCount=3) and (Editor.Session.Character<>nil),'management opens editor frame in same form',Results);
    var Name := TEdit(Editor.FindComponent('PsdCharacterName')); Name.Text := Name.Text+'（保持する下書き）';
    var Draft := Name.Text; var Id := Editor.Session.Character.Id;
    var Pages := TPageControl(Editor.FindComponent('PsdCharacterPages')); Pages.ActivePageIndex := 2; Pages.OnChange(Pages);
    TButton(Editor.FindComponent('PsdReturnToManagement')).Click;
    Check((Main.CurrentPage=apCharacters) and (Main.PageInstance(apCharacters)=Manager),'editor returns to existing management frame',Results);
    TButton(Main.FindComponent('WizardHome')).Click;
    TButton(Main.PageInstance(apHome).FindComponent('HomeCharacters')).Click; TButton(Manager.FindComponent('CharacterOpen')).Click;
    Check((Main.PageInstance(apCharacterEdit)=Editor) and (Editor.Session.Character.Id=Id) and (Name.Text=Draft) and (Pages.ActivePageIndex=2),'home and same-character return preserve frame, identity, draft and page',Results);
    Check(THashSHA2.GetHashStringFromFile(Path)=OriginalHash,'navigation does not save unapplied draft',Results);
    Name.Text := Editor.Session.Character.Name; TButton(Editor.FindComponent('PsdInfoApply')).Click;
    Editor.VerifyPageFlow(ResultPath+'.pages.json');
    Check(Screen.FormCount=1,'PSD page workflow keeps one main form',Results);
    if SmokePath<>'' then Editor.CaptureSmoke(SmokePath);
    TButton(Main.FindComponent('WizardHome')).Click; TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.CurrentPage=apScripts) and (Main.CreatedPageCount=4),'script management lazily created as explicitly pending page',Results);
    var Scripts := Main.PageInstance(apScripts); TButton(Scripts.FindComponent('PendingNext')).Click;
    Check((Main.CurrentPage=apScriptCreate) and (Main.CreatedPageCount=5),'script creation navigation lazily creates pending page',Results);
    TButton(Main.PageInstance(apScriptCreate).FindComponent('PendingNext')).Click;
    Check((Main.CurrentPage=apMovieEdit) and (Main.CreatedPageCount=6),'movie navigation lazily creates pending page',Results);
    TButton(Main.PageInstance(apMovieEdit).FindComponent('PendingNext')).Click;
    Check(Main.CurrentPage=apHome,'movie pending page returns home',Results);
    TButton(Main.PageInstance(apHome).FindComponent('HomeScripts')).Click;
    Check((Main.PageInstance(apScripts)=Scripts) and (Main.CreatedPageCount=6) and (Screen.FormCount=1),'repeated navigation reuses owned frames without additional forms',Results);
    TFile.WriteAllText(ResultPath,Results.ToJSON,TEncoding.UTF8);
  finally Results.Free; end;
end;
end.
