program ScriptTypeCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardWorkspace, RigmScriptCreatorFrame, RigmMovieModel, RigmScriptTypes,
  RigmPageNavigation, RigmJson, PsdJson;
{$R *.res}
var
  W,W2: TRigmWizardWorkspace;
  Form,Form2: TForm;
  Frame,Frame2: TRigmScriptCreatorFrame;
  Combo,Combo2: TComboBox;
  Checks: TJSONArray;
  Root,Error: string;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
procedure Reject(Action: TProc; const Text: string);
begin var Failed := False; try Action(); except on E: Exception do Failed := True; end; Check(Failed,Text); end;
function Payload: TJSONObject;
begin Result := TJSONObject.Create; Result.AddPair('projectId',W.ScriptDraft.Id); Result.AddPair('revision',TJSONNumber.Create(W.ScriptDraft.Revision)); end;
procedure Capture(const Name: string);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try Bitmap.SetSize(Frame.Width,Frame.Height); Frame.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure FreshOpen(const Path: string);
begin
  W2.OpenScriptDraft(Path); Frame2.SetActive(True); Application.ProcessMessages;
  Combo2 := Frame2.FindComponent('ScriptType') as TComboBox;
end;
procedure Run;
begin
  Root := ParamStr(1); if Root='' then raise Exception.Create('New owned output directory is required');
  var DataRoot := TPath.Combine(Root,'OwnedData'); if DirectoryExists(DataRoot) then raise Exception.Create('OwnedData already exists; choose a new output directory');
  ForceDirectories(DataRoot); TFile.WriteAllText(TPath.Combine(DataRoot,'owner.json'),'{"owner":"RIGM.ScriptTypeCheck"}');
  Form := TForm.Create(nil); Form.SetBounds(0,0,1024,680);
  W := TRigmWizardWorkspace.Create(nil); W.StartPipe(DataRoot); W.NewScriptDraft;
  W.CurrentPage := apScriptCreate;
  Frame := TRigmScriptCreatorFrame.CreateForWorkspace(Form,W,DataRoot); Frame.SetActive(True);
  Form.Show; Application.ProcessMessages;
  Combo := Frame.FindComponent('ScriptType') as TComboBox;
  var Title := Frame.FindComponent('ScriptTitle') as TEdit;
  Check((Combo.Items.Count=2) and (Combo.Items[0]='アニメ批評') and (Combo.Items[1]='漫画紹介'),'two catalog choices reach title UI');
  Check((Combo.ItemIndex=-1) and (ProjectScriptType(W.ScriptDraft)=''),'new script is unclassified until selected');
  Title.Text := '種類を保存する検証'; var Id := W.ScriptDraft.Id; var Revision := W.ScriptDraft.Revision;
  Combo.ItemIndex := 0; Combo.OnChange(Combo);
  Check((ProjectScriptType(W.ScriptDraft)='anime-review') and (W.ScriptDraft.Revision=Revision+1),'GUI anime selection stores stable ID and changes revision');
  Check((W.ScriptDraft.Id=Id) and (Title.Text='種類を保存する検証'),'classification preserves title and project identity');
  W.SaveScriptDraft(False); var Path := W.ScriptDraft.FileName;
  var Loaded := LoadMovie(Path);
  try Check(ProjectScriptType(Loaded)='anime-review','anime ID survives actual save and independent load'); finally Loaded.Free; end;
  Combo.ItemIndex := 1; Combo.OnChange(Combo);
  Check(ProjectScriptType(W.ScriptDraft)='manga-introduction','GUI manga selection stores stable ID');
  W.SaveScriptDraft(False); Loaded := LoadMovie(Path);
  try Check(ProjectScriptType(Loaded)='manga-introduction','manga ID survives actual save and independent load'); finally Loaded.Free; end;
  var Status := W.ScriptStatus;
  try Check((JS(Status,'scriptType')='manga-introduction') and (JS(Status,'scriptTypeName')='漫画紹介') and (JA(Status,'scriptTypes').Count=2),'status exposes ID, display name and catalog'); finally Status.Free; end;
  var Schema := W.Command('app-schema',nil);
  try Check((JO(Schema,'workspace').GetValue('script-set-type')<>nil) and (JA(JO(Schema,'workspace'),'scriptTypes').Count=2),'schema exposes category setter and catalog'); finally Schema.Free; end;
  Revision := W.ScriptDraft.Revision; W.SetScriptType('manga-introduction');
  Check(W.ScriptDraft.Revision=Revision,'same type is an idempotent no-op');
  Reject(procedure begin W.SetScriptType('unsupported-type'); end,'setter rejects unsupported type');
  Check((W.ScriptDraft.Revision=Revision) and (ProjectScriptType(W.ScriptDraft)='manga-introduction'),'rejected type preserves current selection and revision');
  var A := Payload;
  try
    A.AddPair('scriptType',TJSONBool.Create(True));
    Reject(procedure begin var Reply := W.Command('app-script-set-type',A); Reply.Free; end,'pipe command rejects non-string classification');
  finally A.Free; end;
  A := Payload;
  try
    A.RemovePair('revision').Free; A.AddPair('revision',TJSONNumber.Create(Revision-1)); A.AddPair('scriptType','anime-review');
    Reject(procedure begin var Reply := W.Command('app-script-set-type',A); Reply.Free; end,'pipe command rejects stale revision');
  finally A.Free; end;
  Form2 := TForm.Create(nil); Form2.SetBounds(0,0,1024,680);
  W2 := TRigmWizardWorkspace.Create(nil); W2.StartPipe(DataRoot);
  Frame2 := TRigmScriptCreatorFrame.CreateForWorkspace(Form2,W2,DataRoot);
  FreshOpen(Path);
  Check((ProjectScriptType(W2.ScriptDraft)='manga-introduction') and (Combo2.ItemIndex=1),'fresh workspace restores saved classification to GUI');
  var Legacy := LoadMovie(Path);
  try
    Legacy.Id := PsdJson.NewId; Legacy.ScriptWizard.RemovePair('scriptType').Free;
    var LegacyPath := TPath.Combine(DataRoot,'Projects\'+Legacy.Id+'\project.rigmovie'); SaveMovie(Legacy,LegacyPath,False);
    var Hash := THashSHA2.GetHashStringFromFile(LegacyPath); FreshOpen(LegacyPath);
    Check((ProjectScriptType(W2.ScriptDraft)='') and (Combo2.ItemIndex=-1),'legacy script without field remains unclassified');
    Check(THashSHA2.GetHashStringFromFile(LegacyPath)=Hash,'opening legacy script does not rewrite its file');
    Legacy.Id := PsdJson.NewId; PsdJson.Put(Legacy.ScriptWizard,'scriptType','future-review');
    var FuturePath := TPath.Combine(DataRoot,'Projects\'+Legacy.Id+'\project.rigmovie'); SaveMovie(Legacy,FuturePath,False);
    FreshOpen(FuturePath);
    Check((Combo2.ItemIndex=2) and (Combo2.Items.Count=3) and (ProjectScriptType(W2.ScriptDraft)='future-review'),'future type is retained and displayed without substitution');
    (Frame2.FindComponent('ScriptTitle') as TEdit).Text := '将来の種類を保持'; W2.SaveScriptDraft(False);
    Loaded := LoadMovie(FuturePath);
    try Check(ProjectScriptType(Loaded)='future-review','editing title and saving preserves a future type ID'); finally Loaded.Free; end;
    Legacy.Id := PsdJson.NewId; PsdJson.Put(Legacy.ScriptWizard,'scriptType',TJSONNumber.Create(1));
    var BadPath := TPath.Combine(DataRoot,'Projects\'+Legacy.Id+'\project.rigmovie'); SaveMovie(Legacy,BadPath,False);
    Hash := THashSHA2.GetHashStringFromFile(BadPath);
    Reject(procedure begin W2.OpenScriptDraft(BadPath); end,'malformed stored type is rejected');
    Check(THashSHA2.GetHashStringFromFile(BadPath)=Hash,'malformed original file is preserved');
  finally Legacy.Free; end;
  var LibraryData := W.ScriptLibrary;
  try
    var Found := False;
    for var V in JA(LibraryData,'scripts') do if JS(TJSONObject(V),'projectId')=Id then
      Found := (JS(TJSONObject(V),'scriptType')='manga-introduction') and (JS(TJSONObject(V),'scriptTypeName')='漫画紹介');
    Check(Found,'library metadata identifies saved script kind');
  finally LibraryData.Free; end;
  for var Ppi in [96,144,192] do begin
    Form.ScaleForPPI(Ppi); Application.ProcessMessages;
    var Heading := Frame.FindComponent('ScriptTypeHeading') as TLabel;
    var Guide := Frame.FindComponent('ScriptTitleGuide') as TLabel;
    Check((Heading.Top>=Title.Top+Title.Height) and (Combo.Top>=Heading.Top+Heading.Height) and (Guide.Top>=Combo.Top+Combo.Height),'title, category and guide do not overlap at '+Ppi.ToString+' DPI');
    Check((Combo.Width>0) and (Combo.Left+Combo.Width<=Combo.Parent.ClientWidth),'category fits title content at '+Ppi.ToString+' DPI');
    Capture('title-'+Ppi.ToString);
  end;
  Form.ScaleForPPI(96); Application.ProcessMessages;
  if ParamStr(2)='pipe' then begin
    TFile.WriteAllText(TPath.Combine(Root,'pipe-ready.json'),W.Pipe.Info.ToJSON,TEncoding.UTF8);
    var Deadline := GetTickCount64+30000;
    while not FileExists(TPath.Combine(Root,'pipe-done.json')) do begin
      Application.ProcessMessages; Sleep(10); if GetTickCount64>Deadline then raise Exception.Create('Owned pipe test timed out');
    end;
    Check((ProjectScriptType(W.ScriptDraft)='anime-review') and (Combo.ItemIndex=0) and not W.ScriptDraft.Modified,'real named pipe updates GUI selection and saves it');
    Capture('title-after-pipe');
  end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Checks := TJSONArray.Create;
  try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  if Root<>'' then begin
    var Result := TJSONObject.Create;
    try Result.AddPair('checks',Checks.Clone as TJSONArray); Result.AddPair('error',Error); TFile.WriteAllText(TPath.Combine(Root,'result.json'),Result.ToJSON,TEncoding.UTF8); finally Result.Free; end;
  end;
  Frame2.Free; W2.Free; Form2.Free; Frame.Free; W.Free; Form.Free; Checks.Free;
end.
