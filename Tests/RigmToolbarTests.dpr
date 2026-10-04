program RigmToolbarTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}

uses System.SysUtils, System.Classes, System.Types, System.IOUtils, System.JSON,
  System.Hash, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage, Winapi.Windows,
  Winapi.CommCtrl, RIGMMakerMainForm, RigmEditorForm, RigmIconToolbar,
  RigmToolbarIcons, RigmModel, RigmJson, ArtDocument, ArtLayerList;

var Checks, CaptureFailures: TJSONArray; Count: Integer; Directory: string;

function PrintWindow(hWnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';

procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Checks.Add(Name); Writeln('PASS: ' + Name);
end;

function Find(P: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to P.ControlCount - 1 do begin
    var C := P.Controls[I];
    if C.Name = Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C), Name); if Result <> nil then Exit; end;
  end;
end;

function Button(F: TForm; const Name: string): TToolButton;
begin
  var C := Find(F, Name);
  if not (C is TToolButton) then raise Exception.Create('Icon button missing: ' + Name);
  Result := TToolButton(C);
end;

procedure Click(F: TForm; const Name: string);
begin
  var B := Button(F, Name);
  if not B.Enabled or not B.Visible then raise Exception.Create('Icon button unavailable: ' + Name);
  B.Click; Application.ProcessMessages;
end;

procedure Capture(F: TForm; const Name: string);
var B: Vcl.Graphics.TBitmap; P: TPngImage;
begin
  Application.ProcessMessages; F.Update;
  B := Vcl.Graphics.TBitmap.Create; P := TPngImage.Create;
  try
    B.PixelFormat := pf24bit; B.SetSize(F.Width, F.Height);
    if not PrintWindow(F.Handle, B.Canvas.Handle, 2) then begin
      CaptureFailures.Add(Name + ': PrintWindow returned false');
      Writeln('CAPTURE UNAVAILABLE: ' + Name); Exit;
    end;
    P.Assign(B); P.SaveToFile(TPath.Combine(Directory, Name + '.png'));
  finally P.Free; B.Free; end;
end;

procedure CaptureRenderer(Bar: TToolBar; const Name: string);
var Bitmap: Vcl.Graphics.TBitmap; Png: TPngImage; OldDC: HDC;
    DefaultDraw: Boolean; State: TCustomDrawState;
begin
  Bitmap := Vcl.Graphics.TBitmap.Create; Png := TPngImage.Create;
  try
    Bitmap.SetSize(Bar.ClientWidth, Bar.ClientHeight); Bitmap.PixelFormat := pf24bit;
    OldDC := Bar.Canvas.Handle; Bar.Canvas.Handle := Bitmap.Canvas.Handle;
    try
      DefaultDraw := True; Bar.OnCustomDraw(Bar, Bar.ClientRect, DefaultDraw);
      for var I := 0 to Bar.ButtonCount - 1 do if Bar.Buttons[I].Visible and
        not (Bar.Buttons[I].Style in [tbsSeparator, tbsDivider]) then begin
        State := []; if Bar.Buttons[I].Down then Include(State, cdsChecked);
        if not Bar.Buttons[I].Enabled then Include(State, cdsDisabled);
        DefaultDraw := True; Bar.OnCustomDrawButton(Bar, Bar.Buttons[I], State, DefaultDraw);
      end;
    finally Bar.Canvas.Handle := OldDC; end;
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Directory, Name + '-renderer.png'));
  finally Png.Free; Bitmap.Free; end;
end;

function Fits(Bar: TToolBar): Boolean;
var R: TRect;
begin
  Result := True;
  for var I := 0 to Bar.ButtonCount - 1 do if Bar.Buttons[I].Visible then begin
    if (Bar.Perform(TB_GETITEMRECT, I, LPARAM(@R)) = 0) or
      (R.Left < 0) or (R.Right > Bar.ClientWidth) or (R.Top < 0) or (R.Bottom > Bar.ClientHeight) then begin
      Writeln('RECT: ', Bar.Name, ' ', Bar.Buttons[I].Name, ' ', R.Left, ',', R.Top, ',', R.Right, ',', R.Bottom,
        ' client ', Bar.ClientWidth, 'x', Bar.ClientHeight); Exit(False);
    end;
  end;
end;

function IconsReady(Bar: TToolBar): Boolean;
begin
  Result := not Bar.ShowCaptions and (Bar.Images <> nil) and (Bar.DisabledImages <> nil);
  for var I := 0 to Bar.ButtonCount - 1 do if not (Bar.Buttons[I].Style in [tbsSeparator, tbsDivider]) then
    Result := Result and (Bar.Buttons[I].Hint <> '') and Bar.Buttons[I].ShowHint and
      (Bar.Buttons[I].ImageIndex >= 0) and (Bar.Buttons[I].ImageIndex < Bar.Images.Count);
end;

procedure Run;
var F: TRigmEditorForm; L: TMainForm; Args, Reply: TJSONObject;
    Id, BoneId, MeshId, Path, Hash: string; Before: Integer; Bar, Context: TToolBar;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
  L := TMainForm.Create(nil);
  try
    L.Show; Application.ProcessMessages;
    Check(IconsReady(TToolBar(Find(L, 'LibraryToolbar'))), 'library uses hinted normal and disabled icon lists');
    L.Width := L.Constraints.MinWidth; Application.ProcessMessages;
    Check(Fits(TToolBar(Find(L, 'LibraryToolbar'))), 'library native icon rectangles fit minimum width');
    Capture(L, 'library-icons');
    CaptureRenderer(TToolBar(Find(L, 'LibraryToolbar')), 'library');
    var List := TListView(Find(L, 'CharacterLibrary'));
    List.Selected := nil; Application.ProcessMessages;
    Check(not Button(L, 'OpenEditorButton').Enabled, 'library edit icon disables without a selection');
    List.Items[0].Selected := True; Application.ProcessMessages;
    Check(Button(L, 'OpenEditorButton').Enabled, 'library edit icon enables when a character is selected');
    Click(L, 'RefreshLibraryButton');
    Check((List.Selected <> nil) and Button(L, 'OpenEditorButton').Enabled, 'refresh icon preserves a usable library entry');
    for var PPI in [144, 192, 96] do begin
      L.ScaleForPPI(PPI);
      Writeln('SCALE: requested=', PPI, ' scaled=', L.Scaled, ' form=', L.CurrentPPI,
        ' image=', TToolBar(Find(L, 'LibraryToolbar')).Images.Width);
      L.Width := L.Constraints.MinWidth;
      Bar := TToolBar(Find(L, 'LibraryToolbar'));
      Writeln('DPI: requested=', PPI, ' form=', L.CurrentPPI, ' toolbar=', Bar.CurrentPPI,
        ' image=', Bar.Images.Width, ' button=', Bar.ButtonWidth, 'x', Bar.ButtonHeight);
      Check((Bar.Images.Width = MulDiv(24, PPI, 96)) and Fits(Bar), 'library icons regenerate and fit at DPI ' + PPI.ToString);
    end;
  finally L.Free; end;
  F := TRigmEditorForm.Create(nil);
  try
    Check(not Button(F, 'ReferenceButton').Enabled and not Button(F, 'ClassifyLayersButton').Enabled,
      'empty document disables reference and reclassification icons');
    F.OpenSample; F.Show; Application.ProcessMessages;
    Bar := TToolBar(Find(F, 'EditorToolbar')); Context := TToolBar(Find(F, 'PageToolbar'));
    Check(IconsReady(Bar) and IconsReady(Context), 'editor and page actions are icon toolbars with named tooltips');
    Check(Button(F, 'Page0').Down and not Button(F, 'Page1').Down, 'active stage has a selected icon');
    Check(not Button(F, 'RedoButton').Enabled and Button(F, 'ReferenceButton').Enabled,
      'redo is disabled and available comparison data enables the reference icon');
    F.Width := F.Constraints.MinWidth; Application.ProcessMessages;
    Check(Fits(Bar) and Fits(Context), 'editor native icon rectangles fit minimum width');
    Capture(F, 'layer-icons');
    CaptureRenderer(Bar, 'layer-common'); CaptureRenderer(Context, 'layer-actions');
    for var PPI in [144, 192, 96] do begin
      F.ScaleForPPI(PPI); F.Width := F.Constraints.MinWidth;
      Check((Bar.Images.Width = MulDiv(24, PPI, 96)) and
        (Context.DisabledImages.Width = MulDiv(24, PPI, 96)) and Fits(Bar) and Fits(Context),
        'editor glyphs and disabled glyphs regenerate and fit at DPI ' + PPI.ToString);
      Capture(F, 'layer-dpi-' + PPI.ToString);
      CaptureRenderer(Bar, 'common-dpi-' + PPI.ToString);
    end;
    var WrapHost := TPanel.Create(F);
    try
      WrapHost.Parent := F; WrapHost.SetBounds(0, 160, 132, 300);
      var WrapBar := TRigmIconToolbar.Create(WrapHost); WrapBar.Parent := WrapHost; WrapBar.Align := alTop;
      for var I := 0 to 6 do WrapBar.AddIcon('Wrap' + I.ToString, '折り返しテスト', riSave, I, nil);
      Application.ProcessMessages;
      Check((WrapBar.Height > WrapBar.ButtonHeight) and Fits(WrapBar), 'narrow icon toolbar wraps every action into accessible rows');
    finally WrapHost.Free; end;
    Id := F.Editor.Document.Layers[0].Id; MeshId := F.Editor.Document.MeshForPart(Id).Id;
    F.Editor.SelectedId := Id;
    var LayerList := TArtLayerList(Find(F, 'LayerList'));
    LayerList.Selected := F.Editor.Document.Art.FindLayer(Id); LayerList.OnSelect(LayerList);
    Click(F, 'ToolbarLayerDown');
    Check(F.Editor.Document.Mesh(MeshId).PartId = Id, 'toolbar reorder preserves mesh references');
    Click(F, 'ToolbarDeleteLayer');
    Check(F.Editor.Document.Art.FindLayer(Id) = nil, 'toolbar delete removes only the selected layer');
    Check(Button(F, 'UndoButton').Enabled and not Button(F, 'RedoButton').Enabled, 'undo availability follows document changes');
    Click(F, 'UndoButton');
    Check((F.Editor.Document.Art.FindLayer(Id) <> nil) and Button(F, 'RedoButton').Enabled, 'undo icon restores removed layer and enables redo');
    Click(F, 'RedoButton');
    Check(F.Editor.Document.Art.FindLayer(Id) = nil, 'redo icon reapplies the removal');
    Click(F, 'UndoButton'); F.OpenSample; Click(F, 'Page1');
    Check(Button(F, 'Page1').Down and not Button(F, 'ImportPngButton').Visible and Button(F, 'HideBoneButton').Visible,
      'bone stage selects its icon and shows only bone actions');
    Click(F, 'EditModeButton');
    Check(Button(F, 'EditModeButton').Down, 'edit preview icon reports preview mode');
    Click(F, 'EditModeButton');
    BoneId := F.Editor.SelectedId; Click(F, 'HideBoneButton');
    Check(not F.Editor.Document.Bone(BoneId).Visible and not Button(F, 'HideBoneButton').Enabled,
      'bone hide icon preserves data and disables repeated hide');
    Click(F, 'AddBoneButton');
    Check(F.Editor.Document.Bone(BoneId).Visible, 'add restore icon restores the hidden bone');
    Click(F, 'ResetBoneButton');
    Check(F.Editor.Document.Bone(BoneId).X = F.Editor.Document.Bone(BoneId).InitialX, 'reset bone icon retains initial coordinates');
    Capture(F, 'bone-icons'); F.OpenSample; Click(F, 'Page2');
    CaptureRenderer(Bar, 'mesh-common'); CaptureRenderer(Context, 'mesh-actions');
    MeshId := F.Editor.SelectedId; Before := Length(F.Editor.Document.Mesh(MeshId).Vertices);
    Click(F, 'AddVertexButton');
    Check(Length(F.Editor.Document.Mesh(MeshId).Vertices) = Before + 1, 'mesh vertex add icon splits a triangle');
    Click(F, 'DeleteVertexButton');
    Check(Length(F.Editor.Document.Mesh(MeshId).Vertices) = Before, 'mesh vertex delete icon removes the selected vertex');
    Capture(F, 'mesh-icons'); F.OpenSample; Click(F, 'Page3');
    Click(F, 'DirectModeButton');
    Check(Button(F, 'DirectModeButton').Down and not Context.Visible, 'direct preview shows checked mode and hides page edit tools');
    Click(F, 'BoneOverlayButton'); Click(F, 'MeshOverlayButton');
    Check(not Button(F, 'BoneOverlayButton').Down and not Button(F, 'MeshOverlayButton').Down,
      'overlay icons reflect disabled overlays');
    F.Editor.Pose.Values.AddOrSetValue('angle', 0.7); Click(F, 'ResetPoseButton');
    Check(F.Editor.Pose.Values.Count = 0, 'reset pose icon clears preview overrides');
    Capture(F, 'preview-icons');
    Path := TPath.Combine(ExtractFilePath(ParamStr(0)), 'OpenWorkflow\legacy.rigm'); Hash := THashSHA2.GetHashStringFromFile(Path);
    F.OpenFile(Path); Application.ProcessMessages;
    Check(F.Editor.Modified and Button(F, 'UndoButton').Enabled and not F.Editor.Document.CanOpen(rpBone) and
      not Button(F, 'Page2').Enabled, 'normal open infers roles unsaved and requires validation before later stages');
    Check((Find(F, 'VerifySourceButton') = nil) and not F.Editor.Document.SourceMatched,
      'opened document requires no human confirmation control');
    Click(F, 'ReferenceButton');
    Check(Button(F, 'ReferenceButton').Down and (Button(F, 'ReferenceButton').Hint = '編集画像に戻す'),
      'reference comparison icon reports selection and return action');
    Click(F, 'ReferenceButton'); Capture(F, 'open-inferred');
    Click(F, 'CompleteStageButton');
    Check(F.Editor.Document.LayerComplete and (F.Editor.Document.LastPage = rpBone) and Button(F, 'Page1').Down and
      not F.Editor.Document.SourceMatched, 'open inference and next-stage icon progress without human confirmation');
    Check(THashSHA2.GetHashStringFromFile(Path) = Hash, 'open inference comparison and completion never auto-save the original');
    Capture(F, 'open-next-stage');
    CaptureRenderer(Bar, 'opened-next-stage'); CaptureRenderer(Context, 'bone-actions');
    F.Editor.Save(TPath.Combine(Directory, 'icon-save.rigm')); Click(F, 'SaveCharacterButton');
    Check(not F.Editor.Modified, 'save icon saves only on explicit invocation');
    F.OpenSample; Click(F, 'Page2'); Click(F, 'GenerateMeshesButton');
    Check(F.Editor.Document.Meshes.Count = 8, 'mesh generation icon rebuilds all image meshes');
    F.Editor.SelectedId := F.Editor.Document.Meshes[0].Id;
    Args := TJSONObject.Create; Args.AddPair('id', F.Editor.SelectedId); AddB(Args, 'locked', True);
    try Reply := F.Editor.Execute('update-mesh', Args); Reply.Free; finally Args.Free; end;
    Check(not Button(F, 'AddVertexButton').Enabled and not Button(F, 'DeleteVertexButton').Enabled,
      'locked mesh disables vertex editing icons');
  finally F.Free; end;
end;

begin
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Toolbar'); ForceDirectories(Directory);
  Checks := TJSONArray.Create; CaptureFailures := TJSONArray.Create;
  try
    try Run; Writeln(Count.ToString + ' toolbar checks passed');
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var R := TJSONObject.Create;
    try
      AddN(R, 'passed', Count); AddB(R, 'success', ExitCode = 0);
      AddB(R, 'physicalInputVerified', False); R.AddPair('captureMethod', 'PrintWindow of isolated VCL test forms');
      R.AddPair('captureFailures', CaptureFailures); CaptureFailures := nil;
      R.AddPair('rendererImages', 'CustomDraw callbacks into a bitmap using native button rectangles; not desktop screenshots');
      R.AddPair('checks', Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(Directory, 'results.json'), R.ToJSON, TEncoding.UTF8);
    finally R.Free; end;
  finally CaptureFailures.Free; Checks.Free; end;
end.
