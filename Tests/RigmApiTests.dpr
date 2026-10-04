program RigmApiTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  System.Generics.Collections, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.Themes, Vcl.Styles, RigmModel, RigmJson, RigmStorage, RigmEditorForm, RigmPipeTestClient;

var Form: TRigmEditorForm; PipeName, Directory: string; Checks: TJSONArray; Passed: Integer;
procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FAIL: ' + Name);
  Inc(Passed); Checks.Add(Name); Writeln('PASS: ', Name);
end;
function Find(Parent: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var C := Parent.Controls[I]; if C.Name = Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C), Name); if Result <> nil then Exit; end;
  end;
end;
function Args(const Id: string = ''): TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('documentId', Form.Editor.Document.FileId);
  Result.AddPair('revision', Form.Editor.Document.Art.Revision.ToString);
  if Id <> '' then Result.AddPair('id', Id);
end;
function Call(const Command: string; A: TJSONObject = nil): TJSONObject;
var Reply: TJSONObject;
begin
  if A = nil then A := Args;
  Reply := PipeCall(PipeName, Command, A);
  try
    if not JB(Reply, 'ok') then raise Exception.Create(Command + ': ' + Reply.ToJSON);
    Result := TJSONObject(JO(Reply, 'data').Clone);
  finally Reply.Free; end;
end;
procedure Execute(const Command: string; A: TJSONObject = nil);
begin var R := Call(Command, A); R.Free; end;
procedure Reject(const Command, Name: string; A: TJSONObject);
var Before, After: TJSONObject; Text, Selection, Path: string; Revision: UInt64; Modified, Undo, Redo: Boolean;
begin
  Before := RigmManifest(Form.Editor.Document); Text := Before.ToJSON; Before.Free;
  Selection := Form.Editor.SelectedId; Path := Form.Editor.FileName; Revision := Form.Editor.Document.Art.Revision;
  Modified := Form.Editor.Modified; Undo := Form.Editor.CanUndo; Redo := Form.Editor.CanRedo;
  var R := PipeCall(PipeName, Command, A);
  try Check(not JB(R, 'ok'), Name + ' is rejected'); finally R.Free; end;
  After := RigmManifest(Form.Editor.Document);
  try Check((After.ToJSON = Text) and (Form.Editor.Document.Art.Revision = Revision) and
    (Form.Editor.SelectedId = Selection) and (Form.Editor.FileName = Path) and
    (Form.Editor.Modified = Modified) and (Form.Editor.CanUndo = Undo) and (Form.Editor.CanRedo = Redo),
    Name + ' preserves document revision selection path and undo/redo'); finally After.Free; end;
end;
function MeshData(const PartId, BoneId: string): TJSONObject;
var Vertices, Faces: TJSONArray;
begin
  Result := Args; Result.AddPair('partId', PartId); Vertices := TJSONArray.Create; Result.AddPair('vertices', Vertices);
  for var I := 0 to 3 do begin
    var V := TJSONObject.Create; Vertices.AddElement(V);
    AddN(V, 'x', (I mod 2) * 20 - 10); AddN(V, 'y', (I div 2) * 20 - 10);
    AddN(V, 'u', I mod 2); AddN(V, 'v', I div 2);
    var W := TJSONArray.Create; V.AddPair('weights', W); var B := TJSONObject.Create; W.AddElement(B);
    B.AddPair('boneId', BoneId); AddN(B, 'value', 1);
  end;
  Faces := TJSONArray.Create; Result.AddPair('triangles', Faces);
  Faces.AddElement(ParseObject('{"a":0,"b":1,"c":2}')); Faces.AddElement(ParseObject('{"a":1,"b":3,"c":2}'));
end;
procedure Run;
var A, R, O: TJSONObject; MeshId, PartId, BoneId, OtherBone, OriginalPipe, Saved, ImportedPath: string;
    Revision: UInt64; Loaded: TRigmDocument; Vertices: TJSONArray;
begin
  Form := TRigmEditorForm.Create(nil);
  try
    Form.OpenSample; Form.Editor.Document.SourceMatched := False; Form.Show; Application.ProcessMessages;
    var PipeDirectory := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RIGMMaker\pipes');
    for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--pipe-dir=') then PipeDirectory := ExpandFileName(ParamStr(I).Substring(11));
    var Files := TDirectory.GetFiles(PipeDirectory, 'RIGMMaker.' + GetCurrentProcessId.ToString + '.*.json');
    Check(Length(Files) = 1, 'isolated editor publishes one discovery file');
    R := ParseObject(TFile.ReadAllText(Files[0], TEncoding.UTF8));
    try PipeName := JS(R, 'commandPipe'); Check((PipeName = JS(R, 'controlPipe')) and (JS(R, 'routing') = 'common-command'), 'stable common command alias preserves legacy control discovery'); finally R.Free; end;
    OriginalPipe := PipeName;
    R := Call('schema');
    try Check((JI(R, 'apiVersion') = 2) and (JA(R, 'commands').Count >= 40), 'common pipe exposes command and argument schemas');
      Check(JS(JO(R,'upperBodyRig'),'parameterId')='bodyAngle','common schema describes upper-body control with the stable legacy parameter ID');
      TFile.WriteAllText(TPath.Combine(Directory, 'command-schema.json'), R.ToJSON, TEncoding.UTF8);
    finally R.Free; end;
    A := TJSONObject.Create; A.AddPair('section', 'summary'); R := Call('document', A);
    try Check((JI(R, 'width') = 256) and (JI(R, 'height') = 320) and (R.GetValue('meshes') = nil), 'bounded summary exposes canvas dimensions and stage state');
      Check((JS(JO(R,'bodyRig'),'waistBoneId')=Form.Editor.Document.WaistBoneId) and
        (JS(JO(R,'bodyRig'),'upperBodyBoneId')=Form.Editor.Document.UpperBodyBoneId),'common summary exposes waist and upper-body stable bone IDs');
    finally R.Free; end;
    PartId := Form.Editor.Document.Layers[0].Id; BoneId := Form.Editor.Document.Bones[0].Id; OtherBone := Form.Editor.Document.Bones[2].Id;
    A := TJSONObject.Create; A.AddPair('section', 'parts'); A.AddPair('id', PartId); R := Call('document', A);
    try Check((JI(R, 'total') = 1) and (JI(TJSONObject(JA(R, 'items')[0]), 'imageWidth') > 0), 'part query exposes exact image dimensions bounds transforms and bindings'); finally R.Free; end;
    A := Args(PartId); A.AddPair('name', 'common entry renamed'); Execute('update-layer', A);
    Check(Form.Editor.Document.Art.FindLayer(PartId).Name = 'common entry renamed', 'common entry retains layer editing');
    A := Args; A.AddPair('page', 'mesh'); Reject('switch-page', 'unprepared strict page switch', A);
    A := Args; A.AddPair('page', 'bone'); AddB(A, 'completeCurrent', True); Execute('switch-page', A);
    Check((Form.Editor.Document.LastPage = rpBone) and Form.Editor.Document.LayerComplete and not Form.Editor.Document.SourceMatched,
      'common switch-page can atomically validate preparation without source confirmation');
    A := Args(BoneId); A.AddPair('name', 'common root'); Execute('update-bone', A);
    Check(Form.Editor.Document.Bone(BoneId).Name = 'common root', 'common entry retains bone editing and UI refresh');
    A := Args; A.AddPair('page', 'mesh'); AddB(A, 'completeCurrent', True); Execute('switch-page', A);
    A := Args; AddN(A, 'grid', 4); Execute('generate-mesh', A);
    Check((Form.Editor.Document.Meshes.Count = 8) and (Length(Form.Editor.Document.Meshes[0].Vertices) = 16),
      'same common pipe generates meshes with automatic role-based bone bindings');
    MeshId := Form.Editor.Document.MeshForPart(PartId).Id;
    Revision := Form.Editor.Document.Art.Revision; Execute('select-object', Args(MeshId));
    Check((Form.Editor.SelectedId = MeshId) and (Form.Editor.Document.Art.Revision = Revision) and
      (TEdit(Find(Form, 'Fieldid')).Text = MeshId), 'select-object synchronizes UI selection without editing the document');
    A := TJSONObject.Create; A.AddPair('section', 'bones'); R := Call('document', A);
    try Check(JI(R, 'total') = 6, 'common pipe exposes waist upper-body bone positions hierarchy visibility and locks'); finally R.Free; end;
    A := TJSONObject.Create; A.AddPair('section', 'meshes'); A.AddPair('id', MeshId); R := Call('document', A);
    try Check((JI(TJSONObject(JA(R, 'items')[0]), 'vertexCount') = 16) and (TJSONObject(JA(R, 'items')[0]).GetValue('vertices') = nil),
      'mesh headers report sizes without embedding geometry'); finally R.Free; end;
    A := TJSONObject.Create; A.AddPair('section', 'mesh-vertices'); A.AddPair('id', MeshId); AddN(A, 'offset', 2); AddN(A, 'limit', 3); R := Call('document', A);
    try Check((JI(R, 'total') = 16) and (JA(R, 'items').Count = 3) and (TJSONObject(JA(R, 'items')[0]).GetValue('weights') <> nil),
      'vertices UV and weights support bounded reads'); finally R.Free; end;
    Execute('set-mesh', MeshData(PartId, BoneId));
    Check((Form.Editor.Document.MeshForPart(PartId).Id = MeshId) and (Length(Form.Editor.Document.Mesh(MeshId).Vertices) = 4) and
      (TEdit(Find(Form, 'Fieldid')).Text = MeshId), 'set-mesh atomically replaces geometry while preserving mesh ID and UI selection');
    A := Args(MeshId); Vertices := TJSONArray.Create; A.AddPair('vertices', Vertices); AddN(A, 'offset', 0);
    var Data := MeshData(PartId, BoneId);
    try O := TJSONObject(TJSONObject(JA(Data, 'vertices')[0]).Clone); O.RemovePair('x').Free; AddN(O, 'x', -11); Vertices.AddElement(O); finally Data.Free; end;
    Execute('set-vertices', A); Check(SameValue(Form.Editor.Document.Mesh(MeshId).Vertices[0].X, -11), 'set-vertices patches bounded vertex ranges');
    A := Args(MeshId); AddN(A, 'vertex', 0); AddN(A, 'u', -0.1); Reject('update-vertex', 'UV outside range', A);
    A := Args(MeshId); AddN(A, 'vertex', 9999); Reject('update-vertex', 'invalid vertex index', A);
    A := Args('missing-mesh'); Reject('delete-mesh', 'invalid mesh ID', A);
    A := TJSONObject.Create; A.AddPair('section', 'parts'); A.AddPair('id', 'missing-part'); Reject('document', 'invalid read ID', A);
    A := Args(MeshId); A.AddPair('triangles', TJSONObject.ParseJSONValue('[{"a":0,"b":1,"c":99}]')); Reject('set-triangles', 'invalid face index', A);
    A := Args(MeshId); A.AddPair('triangles', TJSONObject.ParseJSONValue('[{"a":0,"b":0,"c":1}]')); Reject('set-triangles', 'collapsed face', A);
    for var BadWeights in ['[{"boneId":"missing","value":1}]', '[{"boneId":"' + BoneId + '","value":0.5}]',
      '[{"boneId":"' + BoneId + '","value":-1}]', '[{"boneId":"' + BoneId + '","value":0.5},{"boneId":"' + BoneId + '","value":0.5}]'] do begin
      A := Args(MeshId); A.AddPair('weights', TJSONObject.ParseJSONValue(BadWeights)); Reject('set-weights', 'invalid weights ' + BadWeights, A);
    end;
    A := Args(MeshId); AddB(A, 'boundaryFixed', True); Execute('update-mesh', A);
    A := Args(MeshId); AddN(A, 'vertex', 0); AddN(A, 'x', -15); Reject('update-vertex', 'fixed boundary edit', A);
    A := Args(MeshId); AddB(A, 'boundaryFixed', False); AddB(A, 'locked', True); Execute('update-mesh', A);
    A := Args(MeshId); Reject('delete-mesh', 'locked mesh removal', A);
    A := Args(MeshId); AddN(A, 'vertex', 0); AddB(A, 'locked', False); AddN(A, 'x', -15); Reject('update-vertex', 'lock bypass on geometry command', A);
    A := Args(MeshId); AddB(A, 'locked', False); Execute('update-mesh', A);
    A := Args; A.RemovePair('documentId').Free; A.AddPair('documentId', 'wrong-document'); Reject('generate-mesh', 'wrong document version token', A);
    A := Args; A.RemovePair('revision').Free; A.AddPair('revision', '0'); Reject('generate-mesh', 'stale revision', A);
    A := Args; AddN(A, 'grid', 17); Reject('generate-mesh', 'grid outside supported range', A);
    A := Args; A.AddPair('operations', TJSONObject.ParseJSONValue('[{"command":"update-mesh","args":{"id":"' + MeshId + '","name":"must roll back"}},{"command":"delete-mesh","args":{"id":"missing"}}]'));
    Reject('batch', 'partial mesh batch failure', A);
    A := Args(PartId); Reject('update-layer', 'wrong stage editing', A);
    Execute('delete-mesh', Args(MeshId)); Check(Form.Editor.Document.Mesh(MeshId) = nil, 'mesh deletion updates document and UI');
    Execute('undo'); Check(Form.Editor.Document.Mesh(MeshId) <> nil, 'common undo restores deleted mesh geometry');
    Execute('redo'); Check(Form.Editor.Document.Mesh(MeshId) = nil, 'common redo reapplies deletion'); Execute('undo');
    // A file import carries large geometry without the 60KB message limit.
    O := TJSONObject.Create; O.AddPair('documentId', Form.Editor.Document.FileId); O.AddPair('revision', Form.Editor.Document.Art.Revision.ToString);
    var Operations := TJSONArray.Create; O.AddPair('operations', Operations); var Operation := TJSONObject.Create; Operations.AddElement(Operation);
    Operation.AddPair('command', 'set-mesh'); Data := MeshData(PartId, OtherBone); Data.RemovePair('documentId').Free; Data.RemovePair('revision').Free; Operation.AddPair('args', Data);
    ImportedPath := TPath.Combine(Directory, 'mesh-import.json'); TFile.WriteAllText(ImportedPath, O.ToJSON, TEncoding.UTF8); O.Free;
    A := Args; A.AddPair('path', ImportedPath); Execute('import', A);
    Check(Form.Editor.Document.Mesh(MeshId).Vertices[0].Weights[0].BoneId = OtherBone, 'mesh-stage file import applies custom geometry and weights atomically');
    A := Args; A.AddPair('path', ImportedPath); Reject('import', 'stale mesh import', A);
    A := Args; AddN(A, 'grid', 3); AddB(A, 'replaceExisting', False); Execute('generate-mesh', A);
    Check(Length(Form.Editor.Document.Mesh(MeshId).Vertices) = 4, 'missing-only generation preserves existing custom geometry');
    A := TJSONObject.Create; A.AddPair('throughPage', 'mesh'); R := Call('validate', A);
    try Check(JB(R, 'throughPageReady') and JB(R, 'currentStageReady') and (JI(R, 'errorCount') = 0), 'common validation exposes stage readiness and bounded issues'); finally R.Free; end;
    A := TJSONObject.Create; A.AddPair('root', TPath.Combine(Directory, 'Exchange')); AddB(A, 'images', True); R := Call('export', A);
    try Check(TFile.Exists(TPath.Combine(JS(R, 'directory'), 'part-000000.png')), 'mesh page exports part PNGs on explicit request'); finally R.Free; end;
    Saved := TPath.Combine(Directory, 'api-roundtrip.rigm'); Form.Editor.Save(Saved);
    A := Args; A.AddPair('path', Saved); Execute('save', A); Loaded := LoadRigm(Saved);
    try Check((Loaded.Mesh(MeshId) <> nil) and (Loaded.Mesh(MeshId).Vertices[0].Weights[0].BoneId = OtherBone),
      'common save roundtrips custom mesh IDs coordinates UV faces and weights'); finally Loaded.Free; end;
    A := Args; A.AddPair('page', 'preview'); AddB(A, 'completeCurrent', True); Execute('switch-page', A);
    Check(Form.Editor.Document.LastPage = rpPreview, 'common entry validates mesh preparation and reaches preview');
    A := Args('headAngle'); AddN(A, 'initial', 0); Execute('update-parameter', A);
    R := Call('status'); try Check(JS(JO(R, 'pipes'), 'commandPipe') = OriginalPipe, 'common command endpoint stays unchanged across all four stages'); finally R.Free; end;
    // Invalid preparation must roll back all automatically completed stages.
    Form.OpenSample; Form.Editor.Document.Meshes.Clear;
    A := Args(Form.Editor.Document.Layers[0].Id); A.AddPair('name', 'new preparation'); Execute('update-layer', A);
    A := Args; A.AddPair('page', 'preview'); AddB(A, 'completeCurrent', True); Reject('switch-page', 'failed multi-stage preparation', A);
  finally Form.Free; Form := nil; end;
end;
begin
  Application.Initialize; Application.ShowMainForm := False; TStyleManager.TrySetStyle('Windows Modern Dark');
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'CommonPipe'); ForceDirectories(Directory); Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report, 'passed', Passed); AddB(Report, 'success', ExitCode = 0); AddB(Report, 'userDocumentEdited', False);
      Report.AddPair('transport', 'real named pipe to isolated VCL editor through the stable common endpoint');
      Report.AddPair('checks', Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(Directory, 'results.json'), Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; end;
end.
