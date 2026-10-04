program RigmUiTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Themes, Vcl.ExtCtrls,
  Vcl.Styles, Vcl.Imaging.pngimage, RIGMMakerMainForm, RigmEditorForm,
  RigmModel, RigmJson, RigmStorage, Winapi.Windows, System.Hash;

var Count: Integer; Checks: TJSONArray; TestDirectory: string;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Writeln('PASS: ' + Name); Checks.Add(Name);
end;

function FindControl(Parent: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var Control := Parent.Controls[I];
    if Control.Name = Name then Exit(Control);
    if Control is TWinControl then begin Result := FindControl(TWinControl(Control), Name); if Result <> nil then Exit; end;
  end;
end;

procedure Click(Parent: TWinControl; const Name: string);
var Control: TControl;
begin
  Control := FindControl(Parent, Name);
  if (Control = nil) or not Control.Enabled then raise Exception.Create('Button unavailable: ' + Name);
  if Control is TToolButton then TToolButton(Control).Click
  else if Control is TButton then TButton(Control).Click
  else raise Exception.Create('Unsupported button: ' + Name);
  Application.ProcessMessages;
end;

function ButtonsFit(Parent: TWinControl): Boolean;
begin
  Result := True;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var Control := Parent.Controls[I];
    if ((Control is TButton) or (Control is TToolButton)) and Control.Visible and (Control.Name <> '') and
      ((Control.Left < 0) or (Control.Left + Control.Width > Parent.ClientWidth)) then begin Writeln('OUTSIDE ',Control.Name,' left=',Control.Left,' width=',Control.Width,' parent=',Parent.ClientWidth); Exit(False); end;
    if (Control is TWinControl) and Control.Visible and not (Control is TScrollBox) then
      if not ButtonsFit(TWinControl(Control)) then begin Writeln('OUTSIDE ',Control.Name,' left=',Control.Left,' width=',Control.Width,' parent=',Parent.ClientWidth); Exit(False); end;
  end;
end;

procedure Capture(Form: TForm; const Name: string);
var Bitmap: Vcl.Graphics.TBitmap; Png: TPngImage;
begin
  Application.ProcessMessages; Bitmap := Vcl.Graphics.TBitmap.Create; Png := TPngImage.Create;
  try
    Bitmap.SetSize(Form.ClientWidth, Form.ClientHeight); Bitmap.PixelFormat := pf24bit;
    Bitmap.Canvas.Brush.Color := clBtnFace; Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
    Form.PaintTo(Bitmap.Canvas.Handle, 0, 0);
    Png.Assign(Bitmap);
    Png.SaveToFile(TPath.Combine(TestDirectory, Name + '.png'));
  finally Png.Free; Bitmap.Free; end;
end;

procedure Run;
var Editor: TRigmEditorForm; LibraryList: TListView; Loaded: TRigmDocument; Id, MeshId, BoneId, Path: string;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
  Application.CreateForm(TMainForm, MainForm); MainForm.Show; Application.ProcessMessages;
  Capture(MainForm, 'library');
  LibraryList := TListView(FindControl(MainForm, 'CharacterLibrary'));
  Check((LibraryList <> nil) and (LibraryList.Items.Count >= 1), 'main library includes explicit sample');
  MainForm.Width := MainForm.Constraints.MinWidth; Application.ProcessMessages;
  Check(ButtonsFit(MainForm), 'main toolbar fits minimum window width'); MainForm.Width := 1120;
  Click(MainForm, 'OpenSampleButton'); Editor := nil;
  for var I := 0 to MainForm.ComponentCount - 1 do if MainForm.Components[I] is TRigmEditorForm then Editor := TRigmEditorForm(MainForm.Components[I]);
  Check((Editor <> nil) and Editor.Visible, 'sample button opens visible editor');
  Check((Editor.Editor.Document.Parts.Count = 8) and not Editor.Editor.Document.Usable, 'sample has eight parts and remains unreviewed');
  Editor.Width := Editor.Constraints.MinWidth; Application.ProcessMessages;
  Check(ButtonsFit(Editor), 'editor toolbar fits minimum window width'); Editor.Width := 1280;
  Id := Editor.Editor.Document.Layers[0].Id; MeshId := Editor.Editor.Document.MeshForPart(Id).Id; BoneId := Editor.Editor.Document.Part(Id).BoneId;
  Capture(Editor, 'layer');
  Click(Editor, 'Page1'); Check(Editor.Editor.Document.LastPage = rpBone, 'bone page button switches page'); Capture(Editor, 'bone');
  Click(Editor, 'Page2'); Check(Editor.Editor.Document.LastPage = rpMesh, 'mesh page button switches page'); Capture(Editor, 'mesh');
  Click(Editor, 'Page3'); Check(Editor.Editor.Document.LastPage = rpPreview, 'preview page button switches page'); Capture(Editor, 'preview');
  Click(Editor, 'DirectModeButton'); Check(FindControl(Editor, 'Fieldhelp') <> nil, 'direct preview hides parameter controls'); Capture(Editor, 'direct-preview');
  var PadEnabled := TCheckBox(FindControl(Editor, 'CheckgamepadEnabled'));
  Check((PadEnabled <> nil) and not PadEnabled.Checked and
    (TComboBox(FindControl(Editor, 'CombogamepadTarget')).Items.Count = 4), 'direct preview offers opt-in Pro Controller and four targets');
  PadEnabled.Checked := True; PadEnabled.OnClick(PadEnabled);
  var PreviewControl := TPaintBox(FindControl(Editor, 'CharacterPreview'));
  PreviewControl.OnMouseDown(PreviewControl, mbLeft, [], PreviewControl.Width div 2, PreviewControl.Height div 2);
  PadEnabled := TCheckBox(FindControl(Editor, 'CheckgamepadEnabled'));
  Check(PadEnabled.Checked, 'controller opt-in survives mouse target property rebuild');
  PreviewControl.OnMouseUp(PreviewControl, mbLeft, [], PreviewControl.Width div 2, PreviewControl.Height div 2);
  PadEnabled.Checked := False; PadEnabled.OnClick(PadEnabled);
  Click(Editor, 'DirectModeButton'); Click(Editor, 'Page0');
  Editor.Editor.SelectedId := Id;
  Click(Editor, 'LayerDownButton');
  Check(Editor.Editor.Document.Mesh(MeshId).PartId = Id, 'UI reorder preserves mesh part reference');
  var NameField := TEdit(FindControl(Editor, 'Fieldname')); Check(NameField <> nil, 'selected layer has editable name');
  NameField.Text := 'UIで変更した目'; Click(Editor, 'ApplyLayerPropertiesButton');
  Check((Editor.Editor.Document.Art.FindLayer(Id).Name = 'UIで変更した目') and (Editor.Editor.Document.Part(Id).BoneId = BoneId), 'UI property apply changes name and preserves bone id');
  Check(not Editor.Editor.Document.CanOpen(rpBone) and not FindControl(Editor, 'Page2').Enabled,
    'upstream edit invalidates completion and prevents skipping stages');
  Path := TPath.Combine(TestDirectory, 'ui-roundtrip.rigm'); Editor.Editor.Save(Path); Click(Editor, 'SaveCharacterButton');
  Loaded := LoadRigm(Path);
  try Check((Loaded.Art.FindLayer(Id).Name = 'UIで変更した目') and not Loaded.Usable, 'UI save reloads modified unfinished data'); finally Loaded.Free; end;
  Editor.Free;
  LibraryList.Items[0].Selected := True; LibraryList.OnDblClick(LibraryList); Application.ProcessMessages;
  Editor := nil; for var I := 0 to MainForm.ComponentCount - 1 do if MainForm.Components[I] is TRigmEditorForm then Editor := TRigmEditorForm(MainForm.Components[I]);
  Check((Editor <> nil) and Editor.Visible, 'library double click opens sample editor');
  Editor.Editor.Save(TPath.Combine(TestDirectory, 'sample2.rigm'));
  var PsdPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'PsdWorkflow\separated.psd');
  Check((FindControl(MainForm, 'OpenSeparatedPsdButton') is TToolButton) and
    FindControl(MainForm, 'OpenSeparatedPsdButton').Enabled, 'main offers separated PSD entry');
  MainForm.OpenSeparatedPsdFile(PsdPath); Application.ProcessMessages;
  var Imported: TRigmEditorForm := nil;
  for var I := 0 to MainForm.ComponentCount - 1 do
    if (MainForm.Components[I] is TRigmEditorForm) and (MainForm.Components[I] <> Editor) then Imported := TRigmEditorForm(MainForm.Components[I]);
  Check((Imported <> nil) and Imported.Visible and (Imported.Editor.Document.LastPage = rpLayer) and
    (Imported.Editor.Document.Parts.Count = 6), 'main PSD entry opens classification without generation');
  Check((Pos('画像生成を省略', Vcl.StdCtrls.TLabel(FindControl(Imported, 'PsdImportHint')).Caption) > 0) and
    not Imported.Editor.Document.CanOpen(rpBone), 'imported UI explains generation bypass and requires automatic layer validation');
  Imported.Width := Imported.Constraints.MinWidth; Application.ProcessMessages;
  Check(ButtonsFit(Imported), 'PSD classification toolbar fits minimum width');
  var RoleId := Imported.Editor.Document.Layers[1].Id;
  Imported.Editor.Document.Part(RoleId).Role := 'other';
  var ClassifyRevision := Imported.Editor.Document.Art.Revision;
  Click(Imported, 'ClassifyLayersButton');
  Check((Imported.Editor.Document.Part(RoleId).Role = 'eye') and
    (Imported.Editor.Document.Art.Revision > ClassifyRevision) and not Imported.Editor.Document.SourceMatched,
    'classification button infers unloaded roles without source confirmation');
  var ManualArgs := TJSONObject.Create; ManualArgs.AddPair('id', RoleId); ManualArgs.AddPair('role', 'other');
  var ManualReply := Imported.Editor.Execute('update-layer', ManualArgs); ManualReply.Free; ManualArgs.Free;
  Click(Imported, 'ClassifyLayersButton');
  Check((Imported.Editor.Document.Part(RoleId).Role = 'other') and Imported.Editor.Document.Part(RoleId).RoleManual,
    'classification button preserves manual other role');
  Imported.Editor.Save(TPath.Combine(TestDirectory, 'psd-ui.rigm')); Click(Imported, 'SaveCharacterButton');
  Imported.OpenFile(Imported.Editor.FileName);
  Check((Imported.Editor.Document.PsdSourceName = 'separated.psd') and
    (Pos('画像生成を省略', Vcl.StdCtrls.TLabel(FindControl(Imported, 'PsdImportHint')).Caption) > 0), 'reopened PSD character retains classification origin in UI');
  Imported.Free;
  var OldId := Editor.Editor.Document.FileId; var OldRevision := Editor.Editor.Document.Art.Revision;
  var OldPath := Editor.Editor.FileName; var OldParts := Editor.Editor.Document.Parts.Count;
  Imported := Editor.OpenSeparatedPsd(PsdPath); Application.ProcessMessages;
  Check((Imported <> Editor) and Imported.Visible and (Editor.Editor.Document.FileId = OldId) and
    (Editor.Editor.Document.Art.Revision = OldRevision) and (Editor.Editor.FileName = OldPath) and
    (Editor.Editor.Document.Parts.Count = OldParts), 'editor PSD entry opens separate form and preserves edited character');
  Imported.Editor.Save(TPath.Combine(TestDirectory, 'psd-separate.rigm')); Imported.Free;
  var BeforeComponents := MainForm.ComponentCount; var Failed := False;
  try Editor.OpenSeparatedPsd(TPath.Combine(TestDirectory, 'missing.psd')); except on E: Exception do Failed := True; end;
  Check(Failed and (MainForm.ComponentCount = BeforeComponents) and
    (Editor.Editor.Document.FileId = OldId) and (Editor.Editor.Document.Art.Revision = OldRevision) and
    (Editor.Editor.FileName = OldPath), 'failed editor PSD import removes temporary form and preserves original');
  Failed := False;
  try MainForm.OpenSeparatedPsdFile(TPath.Combine(TestDirectory, 'missing.psd')); except on E: Exception do Failed := True; end;
  Check(Failed and (MainForm.ComponentCount = BeforeComponents), 'failed main PSD import leaves existing windows unchanged');
  var LegacyPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'OpenWorkflow\legacy.rigm');
  var LegacyHash := THashSHA2.GetHashStringFromFile(LegacyPath);
  var Opened := TRigmEditorForm.Create(nil);
  try
    Opened.OpenFile(LegacyPath); Opened.Show; Application.ProcessMessages;
    Check(Opened.Editor.Modified and Opened.Editor.CanUndo and (Opened.Editor.Document.LastPage = rpLayer),
      'UI open automatically infers legacy parts as an unsaved undoable change');
    Check(THashSHA2.GetHashStringFromFile(LegacyPath) = LegacyHash, 'UI open does not save the legacy file');
    var Guide := Vcl.StdCtrls.TLabel(FindControl(Opened, 'PsdImportHint'));
    Check((Pos('自動検証', Guide.Caption) > 0) and (Pos('任意', Guide.Caption) > 0) and
      (FindControl(Opened, 'VerifySourceButton') = nil), 'UI explains automatic validation and optional comparison without a confirmation button');
    Check(not Opened.Editor.Document.CanOpen(rpBone) and not FindControl(Opened, 'Page2').Enabled,
      'automatic inference requires validation and prevents skipping stages');
    Click(Opened, 'ReferenceButton');
    Check(TToolButton(FindControl(Opened, 'ReferenceButton')).Hint = '編集画像に戻す', 'comparison button identifies how to return to edited image');
    Click(Opened, 'ReferenceButton');
    Check(not Opened.Editor.Document.SourceMatched and (Pos('自動検証', Guide.Caption) > 0),
      'optional comparison does not record a source confirmation');
    Click(Opened, 'CompleteStageButton');
    Check(Opened.Editor.Document.LayerComplete and (Opened.Editor.Document.LastPage = rpBone) and
      FindControl(Opened, 'Page1').Enabled and not Opened.Editor.Document.SourceMatched,
      'UI open infer complete reaches the bone page without extra confirmation');
    var VerifiedPath := TPath.Combine(TestDirectory, 'open-reviewed.rigm'); Opened.Editor.Save(VerifiedPath);
    Opened.OpenFile(VerifiedPath); Click(Opened, 'Page0');
    Check(not Opened.Editor.Document.SourceMatched and (Pos('自動検証', Guide.Caption) > 0),
      'reopening classified data retains false source metadata and current automatic-validation guide');
    Click(Opened, 'ApplyLayerPropertiesButton');
    Check(not Opened.Editor.Document.SourceMatched and (Pos('自動検証', Guide.Caption) > 0) and
      (FindControl(Opened, 'VerifySourceButton') = nil), 'subsequent layer edit does not restore a human confirmation gate');
  finally Opened.Free; end;
  Editor.Free; MainForm.Free;
end;

begin
  TestDirectory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'UI'); ForceDirectories(TestDirectory); Checks := TJSONArray.Create;
  try
    try Run; Writeln(IntToStr(Count) + ' UI checks passed');
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report, 'passed', Count); AddB(Report, 'success', ExitCode = 0);
      AddB(Report, 'visualVerified', False); Report.AddPair('visualNote', 'PaintTo image does not capture styled child controls; desktop visual review remains required.');
      Report.AddPair('checks', Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(TestDirectory, 'results.json'), Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; end;
end.
