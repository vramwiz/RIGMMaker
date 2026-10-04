program RigmPreviewTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Diagnostics,
  System.Math, System.Types, System.StrUtils, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  Vcl.Imaging.pngimage, Winapi.Windows, Winapi.Messages,
  ArtDocument, RigmEditorForm, RigmModel, RigmJson, RigmSample, RigmRenderer,
  RigmStorage, RigmEditor, RigmValidation, RigmPropertyScrollBox, RigmGamepadPreview;
var Checks: TJSONArray; Passed: Integer;
procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: '+Name);
  Inc(Passed); Checks.Add(Name); Writeln('PASS: '+Name);
end;
type
  TPaintCounter = class
    Count: Integer;
    Original: TNotifyEvent;
    procedure Paint(Sender: TObject);
  end;
procedure TPaintCounter.Paint(Sender: TObject);
begin Inc(Count); if Assigned(Original) then Original(Sender); end;
function FindControl(Parent: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var C := Parent.Controls[I]; if C.Name = Name then Exit(C);
    if C is TWinControl then begin Result := FindControl(TWinControl(C), Name); if Result <> nil then Exit; end;
  end;
end;
function Command(Form: TRigmEditorForm; const Name: string; Args: TJSONObject): TJSONObject;
begin
  Args.AddPair('documentId', Form.Editor.Document.FileId);
  Args.AddPair('revision', Form.Editor.Document.Art.Revision.ToString);
  try Result := Form.Editor.Execute(Name, Args); finally Args.Free; end;
end;
procedure Wheel(Control: TWinControl; Delta: Integer);
var P: TPoint;
begin
  P := Control.ClientToScreen(Point(Control.ClientWidth div 2,Control.ClientHeight div 2));
  PostMessage(Control.Handle,WM_MOUSEWHEEL,WPARAM(Cardinal(Word(SmallInt(Delta))) shl 16),
    LPARAM(Cardinal(Word(P.X)) or (Cardinal(Word(P.Y)) shl 16)));
  Application.ProcessMessages;
end;
procedure SliderChecks(Form: TRigmEditorForm);
var Track, Other: TTrackBar; Box: TScrollBox; LabelControl: TLabel;
    Revision, Builds, Renders: UInt64; Position, Count: Integer; Undo: Boolean;
begin
  Track := TTrackBar(FindControl(Form,'ParameterheadAngle'));
  Other := TTrackBar(FindControl(Form,'ParameterbodyAngle'));
  Box := TScrollBox(FindControl(Form,'PropertyScrollBox'));
  Check((Track is TRigmFineTrackBar) and (Other is TRigmFineTrackBar),'parameter sliders use fine wheel handling');
  LabelControl := TLabel(FindControl(Form,'LabelParameterheadAngle'));
  Revision := Form.Editor.Document.Art.Revision; Undo := Form.Editor.CanUndo;
  Builds := Form.PropertyBuildCount; Renders := Form.PreviewRenderCount; Count := Box.ControlCount;
  for var I := 0 to 999 do Track.Position := (I mod 101)-50;
  Check(SameValue(Form.Editor.Pose.Value('headAngle'),Track.Position/100.0),'1000 consecutive inputs immediately retain the exact final pose value');
  Check(EndsText(FormatFloat('0.00',Track.Position/100.0,TFormatSettings.Invariant),LabelControl.Caption), 'displayed value immediately matches final slider input');
  Check(Form.PreviewRenderCount = Renders,'continuous input does not synchronously render each event');
  Check((Form.PropertyBuildCount = Builds) and (Box.ControlCount = Count) and (FindControl(Form,'ParameterheadAngle') = Track),'continuous input keeps property layout controls and slider identities');
  Application.ProcessMessages;
  Check(Form.PreviewRenderCount = Renders+1,'a queued input burst renders the latest state in one frame');
  Check((Form.Editor.Document.Art.Revision = Revision) and (Form.Editor.CanUndo = Undo),'preview input preserves document revision and undo history');
  Track.Position := 0; Other.Position := 0; Other.SetFocus;
  var Focus := Form.ActiveControl;
  Box.VertScrollBar.Position := 0; Position := Box.VertScrollBar.Position;
  Wheel(Track,WHEEL_DELTA);
  Check((Track.Position = 1) and SameValue(Form.Editor.Pose.Value('headAngle'),0.01),'hover wheel increases angle by 0.01 degrees');
  Check((Box.VertScrollBar.Position = Position) and (Other.Position = 0) and (Form.ActiveControl = Focus),'wheel leaves panel other slider and focus unchanged');
  Wheel(Track,-WHEEL_DELTA); Check(Track.Position = 0,'opposite wheel reverses one fine step');
  Wheel(Track,WHEEL_DELTA div 2); Check(Track.Position = 0,'partial wheel delta waits for a whole notch');
  Wheel(Track,WHEEL_DELTA div 2); Check(Track.Position = 1,'partial deltas accumulate within their own slider');
  Track.Position := Track.Max; Wheel(Track,WHEEL_DELTA); Check(Track.Position = Track.Max,'wheel clamps at the maximum');
  Track.Position := Track.Min; Wheel(Track,-WHEEL_DELTA); Check(Track.Position = Track.Min,'wheel clamps at the minimum');
  Check((Form.Editor.Document.Art.Revision = Revision) and (Form.Editor.CanUndo = Undo),'wheel preview changes do not create document undo entries');
  Track.Position := 0; Application.ProcessMessages;
end;
function Image(Form: TRigmEditorForm; const FileName: string; GuidePixels: Boolean): Integer;
var Bitmap: Vcl.Graphics.TBitmap; Png: TPngImage; Preview: TPaintBox;
begin
  Result := 0; Bitmap := Vcl.Graphics.TBitmap.Create; Png := TPngImage.Create;
  try
    Preview := TPaintBox(FindControl(Form,'CharacterPreview')); Bitmap.SetSize(Preview.Width,Preview.Height);
    Preview.Parent.PaintTo(Bitmap.Canvas.Handle,0,0);
    if GuidePixels then for var Y := 0 to Bitmap.Height-1 do for var X := 0 to Bitmap.Width-1 do
      if ColorToRGB(Bitmap.Canvas.Pixels[X,Y]) = $00DCCB8A then Inc(Result);
    if FileName <> '' then begin Png.Assign(Bitmap); Png.SaveToFile(FileName); end;
  finally Png.Free; Bitmap.Free; end;
end;
procedure GuideChecks(Form: TRigmEditorForm; const Root: string);
var Args, Reply: TJSONObject; Track: TTrackBar; Box: TScrollBox; Revision: UInt64;
begin
  Args := TJSONObject.Create; Args.AddPair('page','bone'); Reply := Command(Form,'switch-page',Args); Reply.Free; Application.ProcessMessages;
  Check(Image(Form,TPath.Combine(Root,'bone-face-guide.png'),True) > 100,'bone editing draws the circular face guide as an overlay');
  var Button := TToolButton(FindControl(Form,'EditModeButton')); Button.OnClick(Button); Application.ProcessMessages;
  Check(Image(Form,TPath.Combine(Root,'bone-preview.png'),True) = 0,'bone preview does not draw the face editing guide');
  Track := TTrackBar(FindControl(Form,'BonePoseSlider')); Box := TScrollBox(FindControl(Form,'PropertyScrollBox'));
  Box.VertScrollBar.Position := Max(0,Track.Top+Box.VertScrollBar.Position-Box.ClientHeight div 2); Application.ProcessMessages;
  Track.Position := 0; Revision := Form.Editor.Document.Art.Revision; Wheel(Track,WHEEL_DELTA);
  var Angle: Double := 0; Form.Editor.Pose.BoneAngles.TryGetValue(Form.Editor.SelectedId,Angle);
  Check((Track.Position = 1) and SameValue(Angle,0.01),'bone preview wheel uses the same 0.01 degree step');
  Check(Form.Editor.Document.Art.Revision = Revision,'bone preview wheel preserves saved bone positions and revision');
  Args := TJSONObject.Create; Args.AddPair('page','preview'); Reply := Command(Form,'switch-page',Args); Reply.Free; Application.ProcessMessages;
  Check(Image(Form,TPath.Combine(Root,'parameter-preview.png'),True) = 0,'parameter preview excludes the face editing guide');
  var Direct := TToolButton(FindControl(Form,'DirectModeButton')); Direct.OnClick(Direct); Application.ProcessMessages;
  Check(Image(Form,TPath.Combine(Root,'clean-preview.png'),True) = 0,'clean direct preview excludes the face guide');
end;
function SamePoint(A,B: TPointF): Boolean;
begin Result := (Abs(A.X-B.X)<0.001) and (Abs(A.Y-B.Y)<0.001); end;
procedure RigChecks(const Root: string);
var D, Loaded: TRigmDocument; Pose: TRigmPose; Upper, Waist, Head, Neck: TRigmBone;
    Mesh: TRigmMesh; Layer: TArtLayer; Center: TPointF; Radius: Double; P: TPointF;
    Low, Moving, Mixed, Hinge: Integer; Path, Geometry, RootId, HeadId, NeckId, SavedUpperId: string;
    E: TRigmEditor; Before, After: TJSONObject;
begin
  D := TRigmDocument.Create; Pose := TRigmPose.Create;
  try
    PopulateRigmSample(D);
    Check(D.HasUpperBodyRig and (D.Bones.Count=6),'new rig includes an editable waist and upper-body ancestor');
    Waist := D.Bone(D.WaistBoneId); Upper := D.Bone(D.UpperBodyBoneId); Head := D.Bone(D.Parameters[2].BoneId); Neck := D.Bone(Head.ParentId);
    Check((Upper.ParentId = Waist.Id) and (Neck.ParentId = Upper.Id),'head and neck follow the upper-body hierarchy');
    Check((D.Parameters[5].Id='bodyAngle') and (D.Parameters[5].BoneId=Upper.Id) and (D.Parameters[5].Name='上半身角度'),'upper-body slider keeps its stable bodyAngle ID and targets the new branch');
    Check(Abs(Waist.Y-128)<0.001,'partial-body sample places the waist near the lower image region');
    Check(GamepadTargetName(gtBody)='上半身','controller target names match upper-body control');
    Check(D.FaceGuide(Center,Radius) and SamePoint(Center,TPointF.Create(0,-40)) and SameValue(Radius,85),'face guide derives its center and circle size from the actual face image');
    Layer := nil; for var L in D.Layers do if D.Part(L.Id).Role='body' then Layer := L;
    Check(Layer <> nil,'independent fixture contains a body image');
    D.GenerateMesh(Layer.Id,Upper.Id,5); Mesh := D.MeshForPart(Layer.Id);
    Pose.Values.AddOrSetValue('bodyAngle',20); Low := 0; Moving := 0; Mixed := 0; Hinge := 0;
    for var I := 0 to High(Mesh.Vertices) do begin
      P := VertexPosition(D,Mesh,I,Pose);
      if Mesh.Vertices[I].Y >= Waist.Y then begin Inc(Low); Check(SamePoint(P,TPointF.Create(Mesh.Vertices[I].X,Mesh.Vertices[I].Y)),'lower-body vertex remains fixed under upper-body rotation '+IntToStr(I)); end
      else if not SamePoint(P,TPointF.Create(Mesh.Vertices[I].X,Mesh.Vertices[I].Y)) then Inc(Moving);
      if Length(Mesh.Vertices[I].Weights)=2 then Inc(Mixed);
      if SameValue(Mesh.Vertices[I].Y,Waist.Y) then Inc(Hinge);
    end;
    Check((Low>0) and (Moving>0) and (Mixed>0) and (Hinge=5),'body mesh has a waist row plus upper lower and transitional weights');
    Check(SamePoint(BoneTransform(D,Upper,Pose).Apply(Waist.X,Waist.Y),TPointF.Create(Waist.X,Waist.Y)),'upper-body rotation uses the waist as its pivot');
    Check(not SamePoint(BoneTransform(D,Head,Pose).Apply(Head.X,Head.Y),TPointF.Create(Head.X,Head.Y)),'head follows upper-body rotation');
    Check(SamePoint(BoneTransform(D,Neck,Pose).Apply(Neck.X,Neck.Y),BoneTransform(D,Upper,Pose).Apply(Neck.X,Neck.Y)),'neck follows the same upper-body transform');
    var Manual := Mesh.Clone;
    try Manual.Automatic := False; Manual.Vertices[0].Weights := [TRigmWeight.Create(Waist.Id,1)];
      Check(SamePoint(VertexPosition(D,Manual,0,Pose),TPointF.Create(Manual.Vertices[0].X,Manual.Vertices[0].Y)),'manual waist-only weights remain explicitly anchored without automatic transition');
    finally Manual.Free; end;
    Path := TPath.Combine(Root,'upper-body-roundtrip.rigm'); SavedUpperId := Upper.Id; SaveRigm(D,Path); Loaded := LoadRigm(Path);
    try
      Check(Loaded.HasUpperBodyRig and (Loaded.WaistBoneId=Waist.Id) and (Loaded.UpperBodyBoneId=SavedUpperId),'waist and upper-body IDs survive save and reload');
      var ReloadedMesh := Loaded.Mesh(Mesh.Id);
      Check((Length(ReloadedMesh.Vertices)=25) and (Length(ReloadedMesh.Vertices[10].Weights)=2),'mixed body weights survive save and reload');
      Check(SamePoint(VertexPosition(Loaded,ReloadedMesh,0,Pose),VertexPosition(D,Mesh,0,Pose)),'upper-body deformation survives save and reload');
    finally Loaded.Free; end;
    // Make an authentic old five-bone fixture with its original whole-body weights.
    RootId := Waist.Id; HeadId := Head.Id; NeckId := Neck.Id;
    Neck.ParentId := RootId; D.Parameters[5].BoneId := RootId; D.Parameters[5].Name := '体の角度'; D.Parameters[5].Role := 'body';
    for var Part in D.Parts.Values do if Part.BoneId=Upper.Id then Part.BoneId := RootId;
    for var M in D.Meshes do for var I := 0 to High(M.Vertices) do
      for var J := 0 to High(M.Vertices[I].Weights) do if M.Vertices[I].Weights[J].BoneId=Upper.Id then M.Vertices[I].Weights[J].BoneId := RootId;
    for var I := 0 to High(Mesh.Vertices) do Mesh.Vertices[I].Weights := [TRigmWeight.Create(RootId,1)];
    D.Bones.Remove(Upper); D.WaistBoneId := ''; D.UpperBodyBoneId := ''; Waist.Name := '体';
    Before := RigmManifest(D); Geometry := JA(Before,'meshes').ToJSON;
    Path := TPath.Combine(Root,'legacy-five-bones.rigm'); SaveRigm(D,Path);
    E := TRigmEditor.Create;
    try
      E.Open(Path);
      Check(E.Document.HasUpperBodyRig and E.Modified and E.CanUndo,'compatible legacy open upgrades once as an undoable unsaved change');
      Check((E.Document.Bone(RootId).X=Waist.X) and (E.Document.Bone(RootId).Y=Waist.Y) and (E.Document.Bone(HeadId).X=Head.X) and (E.Document.Bone(HeadId).Y=Head.Y),'legacy migration preserves adjusted waist and head positions and IDs');
      After := RigmManifest(E.Document);
      try Check(JA(After,'meshes').ToJSON=Geometry,'legacy migration preserves every mesh ID vertex triangle UV and saved weight'); finally After.Free; end;
      Check(SamePoint(VertexPosition(E.Document,E.Document.Mesh(Mesh.Id),High(Mesh.Vertices),Pose),TPointF.Create(Mesh.Vertices[High(Mesh.Vertices)].X,Mesh.Vertices[High(Mesh.Vertices)].Y)),'legacy waist-only body weights keep the lower-body vertex fixed');
      E.Undo; Check(not E.Document.HasUpperBodyRig and (E.Document.Bones.Count=5) and (E.Document.Bone(NeckId).ParentId=RootId),'one undo restores the original legacy hierarchy');
      E.Redo; SavedUpperId := E.Document.UpperBodyBoneId;
      var UpgradedPath := TPath.Combine(Root,'upgraded-legacy.rigm'); E.Save(UpgradedPath); E.Open(UpgradedPath);
      Check(E.Document.HasUpperBodyRig and (E.Document.UpperBodyBoneId=SavedUpperId) and not E.Modified and not E.CanUndo,'saved migration reopens without duplicating bones or dirtying the document');
      Loaded := LoadRigm(Path);
      try Check(not Loaded.HasUpperBodyRig and (Loaded.Bones.Count=5),'opening does not overwrite the legacy source file'); finally Loaded.Free; end;
    finally E.Free; Before.Free; end;
    Waist.Locked := True; SaveRigm(D,TPath.Combine(Root,'locked-legacy.rigm')); E := TRigmEditor.Create;
    try E.Open(TPath.Combine(Root,'locked-legacy.rigm')); Check(not E.Document.HasUpperBodyRig and not E.Modified and (E.Document.Bones.Count=5),'locked legacy rigs retain their original hierarchy and saved state'); finally E.Free; end;
    Waist.Locked := False; Head.ParentId := ''; SaveRigm(D,TPath.Combine(Root,'custom-legacy.rigm')); E := TRigmEditor.Create;
    try E.Open(TPath.Combine(Root,'custom-legacy.rigm')); Check(not E.Document.HasUpperBodyRig and not E.Modified,'incompatible custom hierarchies are preserved'); finally E.Free; end;
    Head.ParentId := NeckId; Mesh.Automatic := False; SaveRigm(D,TPath.Combine(Root,'manual-body-legacy.rigm')); E := TRigmEditor.Create;
    try E.Open(TPath.Combine(Root,'manual-body-legacy.rigm')); Check(not E.Document.HasUpperBodyRig and not E.Modified,'identified manual body meshes keep their original hierarchy weights and saved state'); finally E.Free; end;
    Mesh.Automatic := True; Mesh.Vertices[0].Weights := [TRigmWeight.Create(RootId,0.5),TRigmWeight.Create(NeckId,0.5)];
    SaveRigm(D,TPath.Combine(Root,'mixed-weights-legacy.rigm')); E := TRigmEditor.Create;
    try E.Open(TPath.Combine(Root,'mixed-weights-legacy.rigm')); Check(not E.Document.HasUpperBodyRig and not E.Modified,'existing mixed body weights prevent guessed legacy migration'); finally E.Free; end;
    Mesh.Vertices[0].Weights := [TRigmWeight.Create(RootId,1)]; D.AddBone(RootId,'手動の追加ボーン');
    SaveRigm(D,TPath.Combine(Root,'extra-bone-legacy.rigm')); E := TRigmEditor.Create;
    try E.Open(TPath.Combine(Root,'extra-bone-legacy.rigm')); Check(not E.Document.HasUpperBodyRig and not E.Modified and (E.Document.Bones.Count=6),'additional manual bones preserve their hierarchy and stable IDs'); finally E.Free; end;
  finally Pose.Free; D.Free; end;
end;
function Benchmark(Form: TRigmEditorForm): TJSONObject;
const Iterations = 60; Burst = 240;
var Track: TTrackBar; Paint: TPaintBox; Counter: TPaintCounter; Start: Int64;
    Times: TArray<Double>; Total: Double; Modes: TJSONArray; Mode: TJSONObject;
begin
  Result := TJSONObject.Create;
  Track := TTrackBar(FindControl(Form, 'ParameterheadAngle'));
  if Track = nil then raise Exception.Create('Missing preview slider');
  Paint := TPaintBox(FindControl(Form, 'CharacterPreview'));
  Counter := TPaintCounter.Create;
  try
    Counter.Original := Paint.OnPaint; Paint.OnPaint := Counter.Paint;
    Result.AddPair('fixture', Form.Editor.Document.PsdSourceName);
    AddN(Result, 'parts', Form.Editor.Document.Parts.Count); AddN(Result, 'meshes', Form.Editor.Document.Meshes.Count);
    AddN(Result, 'windowWidth', Form.Width); AddN(Result, 'windowHeight', Form.Height);
    Modes := TJSONArray.Create; Result.AddPair('modes', Modes);
    for var Pump := 0 to 1 do begin
      for var I := 0 to 2 do begin Track.Position := I * 30; Application.ProcessMessages; end;
      Counter.Count := 0; Total := 0; SetLength(Times, Iterations);
      for var I := 0 to Iterations - 1 do begin
        Start := TStopwatch.GetTimeStamp;
        Track.Position := ((I mod 21) - 10) * 30;
        if Pump = 1 then Application.ProcessMessages;
        Times[I] := (TStopwatch.GetTimeStamp - Start) * 1000.0 / TStopwatch.Frequency;
        Total := Total + Times[I];
      end;
      Application.ProcessMessages;
      TArray.Sort<Double>(Times); Mode := TJSONObject.Create; Modes.Add(Mode);
      Mode.AddPair('mode', 'slider-event' + IfThen(Pump = 1, '-and-frame', ''));
      AddN(Mode, 'totalMs', Total); AddN(Mode, 'medianMs', Times[Iterations div 2]);
      AddN(Mode, 'p95Ms', Times[Round(Iterations * 0.95)-1]); AddN(Mode, 'paintCount', Counter.Count);
    end;
    Counter.Count := 0; Start := TStopwatch.GetTimeStamp;
    for var I := 0 to Burst - 1 do Track.Position := (I mod 100) - 50;
    AddN(Result, 'burstInputMs', (TStopwatch.GetTimeStamp-Start)*1000.0/TStopwatch.Frequency);
    Application.ProcessMessages; AddN(Result, 'burstPaintCount', Counter.Count);
    AddN(Result, 'finalSliderValue', Track.Position/100.0);
    AddN(Result, 'finalPoseValue', Form.Editor.Pose.Value('headAngle'));
    Paint.OnPaint := Counter.Original;
  finally Counter.Free; end;
end;
var Form: TRigmEditorForm; Reply, Args, Result: TJSONObject; Fixture, LabelName, Root: string; BenchmarkOnly: Boolean;
begin
  try
    Application.Initialize; Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Preview');
    LabelName := 'after'; Fixture := ''; BenchmarkOnly := False; Checks := TJSONArray.Create;
    for var I := 1 to ParamCount do begin
      if ParamStr(I).StartsWith('--fixture=') then Fixture := ParamStr(I).Substring(10);
      if ParamStr(I).StartsWith('--label=') then LabelName := ParamStr(I).Substring(8);
      if ParamStr(I)='--benchmark-only' then BenchmarkOnly := True;
    end;
    ForceDirectories(Root); Form := TRigmEditorForm.Create(nil);
    try
      if Fixture <> '' then Form.OpenFile(Fixture) else Form.OpenSample;
      Args := TJSONObject.Create; Args.AddPair('page','preview'); AddB(Args,'completeCurrent',True);
      Reply := Command(Form,'switch-page',Args); Reply.Free;
      Form.Show; Application.ProcessMessages;
      Result := Benchmark(Form);
      try
        TFile.WriteAllText(TPath.Combine(Root,'performance-'+LabelName+'.json'),Result.ToJSON,TEncoding.UTF8);
        Writeln(Result.ToJSON);
      finally Result.Free; end;
      if not BenchmarkOnly then begin SliderChecks(Form); GuideChecks(Form,Root); RigChecks(Root); end;
    finally Form.Free; end;
    if not BenchmarkOnly then begin
      Result := TJSONObject.Create;
      try AddB(Result,'success',True); AddN(Result,'passed',Passed); Result.AddPair('checks',Checks); Checks := nil;
        TFile.WriteAllText(TPath.Combine(Root,'results.json'),Result.ToJSON,TEncoding.UTF8); Writeln('All ',Passed,' preview tests passed');
      finally Result.Free; end;
    end;
    Checks.Free;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); Halt(1); end; end;
end.
