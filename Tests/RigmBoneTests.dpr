program RigmBoneTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  System.Math, System.Hash, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Themes, Vcl.Styles,
  RigmEditorForm, RigmModel, RigmValidation, RigmJson;

var Checks: TJSONArray; Passed: Integer; Directory: string;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
  Inc(Passed); Checks.Add(Name); Writeln('PASS: ', Name);
end;

function Find(Parent: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var C := Parent.Controls[I];
    if C.Name = Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C), Name); if Result <> nil then Exit; end;
  end;
end;

procedure Click(Form: TRigmEditorForm; const Name: string);
begin
  var C := TToolButton(Find(Form, Name));
  if not C.Enabled then raise Exception.Create('Disabled: ' + Name);
  C.OnClick(C); Application.ProcessMessages;
end;

function PointFor(Form: TRigmEditorForm; X, Y: Double): TPoint;
var Preview: TControl; Scale: Double; W, H: Integer;
begin
  Preview := Find(Form, 'CharacterPreview');
  Scale := Min((Preview.Width - 48) / Form.Editor.Document.Art.Width,
    (Preview.Height - 48) / Form.Editor.Document.Art.Height);
  W := Max(1, Round(Form.Editor.Document.Art.Width * Scale));
  H := Max(1, Round(Form.Editor.Document.Art.Height * Scale));
  Result := Point((Preview.Width - W) div 2 + Round((X + Form.Editor.Document.Art.Width / 2) * W / Form.Editor.Document.Art.Width),
    (Preview.Height - H) div 2 + Round((Y + Form.Editor.Document.Art.Height / 2) * H / Form.Editor.Document.Art.Height));
end;

function Frame(Form: TRigmEditorForm; const Name: string): string;
var Bitmap: TBitmap; Stream: TMemoryStream; Png: TPngImage; Preview: TPaintBox;
begin
  Bitmap := TBitmap.Create; Stream := TMemoryStream.Create; Png := TPngImage.Create;
  try
    Preview := TPaintBox(Find(Form, 'CharacterPreview'));
    Bitmap.SetSize(Preview.Parent.ClientWidth, Preview.Parent.ClientHeight);
    Preview.Parent.PaintTo(Bitmap.Canvas.Handle, 0, 0);
    Bitmap.SaveToStream(Stream); Stream.Position := 0;
    Result := THashSHA2.GetHashString(Stream);
    if Name <> '' then begin Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Directory, Name + '.png')); end;
  finally Png.Free; Stream.Free; Bitmap.Free; end;
end;

procedure DragChecks;
var F: TRigmEditorForm; Preview: TRigmPreviewPaintBox; Id: string; Start, Finish: TPoint;
    Revision: UInt64; Origin: TPointF; NameEdit, XEdit: TEdit; Stable, Unchanged: Boolean;
    InitialFrame, MovedFrame: string;
begin
  F := TRigmEditorForm.Create(nil);
  try
    F.OpenSample; F.Editor.Document.SourceMatched := False;
    Click(F, 'Page1'); F.Show; Application.ProcessMessages;
    Preview := TRigmPreviewPaintBox(Find(F, 'CharacterPreview'));
    Check(TPanel(Preview.Parent).DoubleBuffered and not TPanel(Preview.Parent).ParentBackground,
      'viewport parent buffers painting without a themed background erase');
    Id := F.Editor.Document.Bones[0].Id;
    F.Editor.SelectedId := Id; F.Editor.SwitchPage(rpBone); Application.ProcessMessages;
    NameEdit := TEdit(Find(F, 'Fieldname')); XEdit := TEdit(Find(F, 'Fieldx'));
    Stable := True; Unchanged := True;
    for var Pass := 0 to 9 do begin
      Origin := TPointF.Create(F.Editor.Document.Bone(Id).X, F.Editor.Document.Bone(Id).Y);
      Start := PointFor(F, Origin.X, Origin.Y); Finish := Point(Start.X + 6, Start.Y - 4);
      Revision := F.Editor.Document.Art.Revision;
      Preview.OnMouseDown(Preview, mbLeft, [], Start.X + 2, Start.Y);
      Check(Preview.MouseCapture, 'bone drag captures the mouse for release outside the viewport ' + Pass.ToString);
      for var I := 1 to 120 do begin
        Preview.OnMouseMove(Preview, [ssLeft], Start.X + 2 + I mod 6, Start.Y - I mod 4);
        Application.ProcessMessages;
        Stable := Stable and (Find(F, 'Fieldname') = NameEdit) and (Find(F, 'Fieldx') = XEdit);
        Unchanged := Unchanged and (F.Editor.Document.Art.Revision = Revision) and
          SameValue(F.Editor.Document.Bone(Id).X, Origin.X) and SameValue(F.Editor.Document.Bone(Id).Y, Origin.Y);
      end;
      // The release position must win even when no preceding move reported it.
      Preview.OnMouseUp(Preview, mbLeft, [], Finish.X + 2, Finish.Y); Application.ProcessMessages;
      Check((F.Editor.Document.Art.Revision = Revision + 1) and not Preview.MouseCapture,
        'drag release commits exactly once and releases capture ' + Pass.ToString);
      Check((F.Editor.Document.Bone(Id).X > Origin.X) and (F.Editor.Document.Bone(Id).Y < Origin.Y),
        'release coordinates move the bone without snapping its pickup offset ' + Pass.ToString);
    end;
    Check(Stable, '1200 drag moves reuse numeric and name property controls');
    Check(Unchanged, '1200 drag moves leave persisted positions and revision untouched until release');
    Check(not F.Editor.Document.BoneComplete and Find(F, 'Page2').Enabled,
      'bone edits invalidate completion while the mesh icon remains a validated next action');
    Origin := TPointF.Create(F.Editor.Document.Bone(Id).X, F.Editor.Document.Bone(Id).Y);
    Click(F, 'UndoButton');
    Check(not SameValue(F.Editor.Document.Bone(Id).X, Origin.X), 'undo restores the entire last drag in one step');
    Click(F, 'RedoButton');
    Check(SameValue(F.Editor.Document.Bone(Id).X, Origin.X), 'redo restores the last drag position');
    Start := PointFor(F, Origin.X, Origin.Y); Revision := F.Editor.Document.Art.Revision;
    Preview.OnMouseDown(Preview, mbLeft, [], Start.X + 2, Start.Y);
    Preview.OnMouseUp(Preview, mbLeft, [], Start.X + 2, Start.Y);
    Check(F.Editor.Document.Art.Revision = Revision, 'click without movement does not create an edit or undo entry');
    TCheckBox(Find(F, 'Checkpaired')).Checked := False;
    XEdit.Text := FloatToStr(Origin.X + 0.25, TFormatSettings.Invariant);
    var Apply := TButton(Find(F, 'ApplyBonePropertiesButton')); Apply.OnClick(Apply);
    Check(SameValue(F.Editor.Document.Bone(Id).X, Origin.X + 0.25), 'bone properties preserve fractional position values');
    Click(F, 'UndoButton'); Click(F, 'RedoButton');
    Check(SameValue(F.Editor.Document.Bone(Id).X, Origin.X + 0.25), 'property edits also survive undo and redo');
    TCheckBox(Find(F, 'Checklocked')).Checked := True; Apply.OnClick(Apply);
    Revision := F.Editor.Document.Art.Revision; Origin.X := F.Editor.Document.Bone(Id).X;
    Start := PointFor(F, Origin.X, Origin.Y);
    Preview.OnMouseDown(Preview, mbLeft, [], Start.X, Start.Y);
    Preview.OnMouseMove(Preview, [ssLeft], Start.X + 30, Start.Y + 30);
    Preview.OnMouseUp(Preview, mbLeft, [], Start.X + 30, Start.Y + 30);
    Check((F.Editor.Document.Art.Revision = Revision) and SameValue(F.Editor.Document.Bone(Id).X, Origin.X),
      'locked bone does not drag or create a rejected edit');
    TCheckBox(Find(F, 'Checklocked')).Checked := False; Apply.OnClick(Apply);
    Start := PointFor(F, Origin.X, Origin.Y); InitialFrame := Frame(F, 'rest-frame');
    Revision := F.Editor.Document.Art.Revision;
    Preview.OnMouseDown(Preview, mbLeft, [], Start.X, Start.Y);
    Preview.OnMouseMove(Preview, [ssLeft], Start.X + 25, Start.Y);
    MovedFrame := Frame(F, 'drag-frame');
    Check(InitialFrame <> MovedFrame, 'composited paint output changes to include the drag overlay');
    F.OnDeactivate(F); Preview.OnMouseUp(Preview, mbLeft, [], Start.X + 25, Start.Y);
    Check((F.Editor.Document.Art.Revision = Revision) and not Preview.MouseCapture,
      'deactivation cancels a pending edit without changing the document');
    Click(F, 'EditModeButton'); Revision := F.Editor.Document.Art.Revision;
    Preview.OnMouseDown(Preview, mbLeft, [], Start.X, Start.Y);
    Preview.OnMouseMove(Preview, [ssLeft], Start.X + 12, Start.Y);
    Preview.OnMouseUp(Preview, mbLeft, [], Start.X + 15, Start.Y);
    Check((F.Editor.Document.Art.Revision = Revision) and (F.Editor.Pose.BoneOffsets.Count > 0) and not Preview.MouseCapture,
      'preview drag changes only the temporary pose and clears capture on release');
    Click(F, 'ResetPoseButton'); Click(F, 'EditModeButton');
    var Path := TPath.Combine(Directory, 'drag-roundtrip.rigm'); F.Editor.Save(Path); F.OpenFile(Path);
    Check(SameValue(F.Editor.Document.Bone(Id).X, Origin.X) and not F.Editor.Modified,
      'save and reopen preserve the dragged and property edited bone position');
    Click(F, 'Page2');
    Check(F.Editor.Document.BoneComplete and (F.Editor.Document.LastPage = rpMesh) and not F.Editor.Document.SourceMatched,
      'mesh icon validates and completes edited bones without human confirmation');
  finally F.Free; end;
end;

procedure FailureChecks;
var F: TRigmEditorForm; Args, Reply: TJSONObject; Id, Other: string; Revision: UInt64;
    List: TListBox; Guide: TLabel;
begin
  F := TRigmEditorForm.Create(nil);
  try
    F.OpenSample; Click(F, 'Page1');
    Id := F.Editor.Document.Bones[0].Id; Other := F.Editor.Document.Bones[2].Id;
    Args := TJSONObject.Create; Args.AddPair('id', Id); Args.AddPair('parentId', Other);
    try Reply := F.Editor.Execute('update-bone', Args); Reply.Free; finally Args.Free; end;
    Revision := F.Editor.Document.Art.Revision;
    Check(not Find(F, 'Page2').Enabled, 'cyclic bone relationships disable the adjacent mesh action');
    Click(F, 'CompleteStageButton');
    Check((F.Editor.Document.Art.Revision = Revision) and not F.Editor.Document.BoneComplete and
      (F.Editor.Document.LastPage = rpBone), 'completion rejects invalid bones without modifying them or marking them complete');
    List := TListBox(Find(F, 'ValidationIssues')); Guide := TLabel(Find(F, 'PsdImportHint'));
    Check(List.Visible and (List.ItemIndex >= 0) and (Pos('親ボーン', Guide.Caption) > 0) and
      (Pos(F.Editor.Document.Bone(Id).Name, Guide.Caption) > 0), 'failure names the affected bone and its repair field inline');
    List.OnDblClick(List);
    Check(F.Editor.Document.Bone(F.Editor.SelectedId) <> nil, 'blocking bone issue opens the target property controls');
    Click(F, 'UndoButton');
    Check(Find(F, 'Page2').Enabled, 'undoing invalid relationship restores the validated mesh action');
    Click(F, 'Page2'); Check(F.Editor.Document.LastPage = rpMesh, 'repaired bone data advances normally');
  finally F.Free; end;
end;

procedure SavedCopyChecks;
var F: TRigmEditorForm; Issues: TRigmIssues; Path, Hash: string;
begin
  Path := TPath.Combine(Directory, 'user-saved-copy.rigm');
  if not TFile.Exists(Path) then Exit;
  Hash := THashSHA2.GetHashStringFromFile(Path); F := TRigmEditorForm.Create(nil);
  try
    F.OpenFile(Path);
    Issues := ValidateRigm(F.Editor.Document);
    try Check(not HasErrors(Issues, rpBone), 'saved user document copy has no blocking bone or layer errors'); finally Issues.Free; end;
    Check((F.Editor.Document.LastPage = rpBone) and not F.Editor.Document.BoneComplete and Find(F, 'Page2').Enabled,
      'saved user copy reproduces unfinished bones with a usable validated mesh action');
    Click(F, 'Page2');
    Check(F.Editor.Document.BoneComplete and (F.Editor.Document.LastPage = rpMesh),
      'saved user copy advances from bone to mesh through the icon');
    Check(THashSHA2.GetHashStringFromFile(Path) = Hash, 'copy workflow never auto-saves its input');
  finally F.Free; end;
end;

begin
  Application.Initialize; Application.ShowMainForm := False;
  TStyleManager.TrySetStyle('Windows Modern Dark');
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'BonePreview'); ForceDirectories(Directory);
  Checks := TJSONArray.Create;
  try
    try DragChecks; FailureChecks; SavedCopyChecks;
    except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var R := TJSONObject.Create;
    try AddN(R, 'passed', Passed); AddB(R, 'success', ExitCode = 0); AddB(R, 'physicalFlickerVerified', False);
      R.AddPair('frameMethod', 'VCL PaintTo of isolated test viewport; not desktop screenshots');
      R.AddPair('checks', Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(Directory, 'results.json'), R.ToJSON, TEncoding.UTF8);
    finally R.Free; end;
  finally Checks.Free; end;
end.
