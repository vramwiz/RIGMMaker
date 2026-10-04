program RigmTests;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages, ArtDocument, RigmModel, RigmJson, RigmRenderer,
  RigmStorage, RigmValidation, RigmEditor, RigmSample, RigmPipe, ArtPng, ArtPsd;

var Count: Integer; Results: TJSONArray;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Writeln('PASS: ' + Name); Results.Add(Name);
end;

procedure Command(E: TRigmEditor; const Name: string; Args: TJSONObject);
var Reply: TJSONObject;
begin
  try Reply := E.Execute(Name, Args); Reply.Free; finally Args.Free; end;
end;

function ArgsId(const Id: string): TJSONObject;
begin Result := TJSONObject.Create; Result.AddPair('id', Id); end;

procedure Rejected(const Name: string; Action: TProc);
var Failed: Boolean;
begin
  Failed := False;
  try Action(); except on E: Exception do Failed := True; end;
  Check(Failed, Name);
end;

procedure Pump;
var Message: TMsg;
begin
  while PeekMessage(Message, 0, 0, 0, PM_REMOVE) do begin TranslateMessage(Message); DispatchMessage(Message); end;
end;

function PipeCall(const PipeName, Command: string; Args: TJSONObject): TJSONObject;
var Client: TThread; Request, Reply, Failure: string; Envelope: TJSONObject; Start: UInt64;
begin
  Envelope := TJSONObject.Create;
  try
    AddN(Envelope, 'schemaVersion', 1); Envelope.AddPair('requestId', NewRigmId);
    Envelope.AddPair('command', Command); Envelope.AddPair('args', Args);
    Request := Envelope.ToJSON;
  finally Envelope.Free; end;
  Client := TThread.CreateAnonymousThread(procedure
    var Handle: THandle; Data, Buffer: TBytes; ReadCount, Written, Mode, Error: DWORD; FullName: string; Deadline: UInt64;
    begin
      try
        FullName := '\\.\pipe\' + PipeName;
        Deadline := GetTickCount64 + 3000;
        while not WaitNamedPipe(PChar(FullName), 100) do begin
          Error := GetLastError;
          if not (Error in [ERROR_FILE_NOT_FOUND, ERROR_PIPE_BUSY, ERROR_SEM_TIMEOUT]) or
            (GetTickCount64 >= Deadline) then begin SetLastError(Error); RaiseLastOSError; end;
          Sleep(5);
        end;
        Handle := CreateFile(PChar(FullName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
        if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
        try
          Mode := PIPE_READMODE_MESSAGE; if not SetNamedPipeHandleState(Handle, Mode, nil, nil) then RaiseLastOSError;
          Data := TEncoding.UTF8.GetBytes(Request); SetLength(Buffer, 65536);
          if not WriteFile(Handle, Data[0], Length(Data), Written, nil) then RaiseLastOSError;
          if not ReadFile(Handle, Buffer[0], Length(Buffer), ReadCount, nil) then RaiseLastOSError;
          Reply := TEncoding.UTF8.GetString(Buffer, 0, ReadCount);
        finally CloseHandle(Handle); end;
      except on E: Exception do Failure := E.Message; end;
    end);
  Client.FreeOnTerminate := False; Client.Start; Start := GetTickCount64;
  while WaitForSingleObject(Client.Handle, 1) = WAIT_TIMEOUT do begin
    Pump;
    if GetTickCount64 - Start > 10000 then begin CancelSynchronousIo(Client.Handle); Client.Terminate; Client.WaitFor; Client.Free; raise Exception.Create('Pipe test timed out'); end;
  end;
  Client.Free; Pump;
  if Failure <> '' then raise Exception.Create(Failure);
  Result := ParseObject(Reply);
end;

function RevisionArgs(E: TRigmEditor): TJSONObject;
begin Result := TJSONObject.Create; Result.AddPair('documentId', E.Document.FileId); Result.AddPair('revision', E.Document.Art.Revision.ToString); end;

procedure RunEditorTests;
var E: TRigmEditor; A, B, Batch, Operation: TJSONObject; Operations: TJSONArray;
    PartId, BoneId, MeshId, GroupId, OriginalName, RootId, ChildId, FileName: string;
    Revision: UInt64; Loaded: TRigmDocument; Issues: TRigmIssues; Pixels, Deformed: TBytes;
    W, H: Integer; Pose: TRigmPose;
begin
  E := TRigmEditor.Create;
  try
    E.NewDocument('tests', 256, 320); PopulateRigmSample(E.Document);
    Issues := ValidateRigm(E.Document);
    try Check(not HasErrors(Issues, rpMesh), 'sample covers required roles, bones and weights'); finally Issues.Free; end;
    PartId := E.Document.Layers[0].Id; BoneId := E.Document.Part(PartId).BoneId; MeshId := E.Document.MeshForPart(PartId).Id;
    FileName := TPath.Combine(ExtractFilePath(ParamStr(0)), 'complete.rigm'); E.Save(FileName);
    Loaded := LoadRigm(FileName);
    try
      Check((Loaded.Bone(BoneId) <> nil) and (Loaded.Mesh(MeshId).PartId = PartId), 'mesh and bone references survive save');
      Check(Loaded.Mesh(MeshId).Vertices[0].Weights[0].BoneId = BoneId, 'vertex weight reference survives save');
      Check((Length(Loaded.ReferencePixels) > 0) and (Length(Loaded.Parameters) = 6), 'source reference and parameters survive save');
    finally Loaded.Free; end;
    A := ArgsId(PartId); A.AddPair('name', '名前変更後'); Command(E, 'update-layer', A);
    Check((E.Document.Part(PartId).BoneId = BoneId) and (E.Document.Mesh(MeshId).PartId = PartId), 'rename preserves stable references');
    Check(not E.Document.LayerComplete and not E.Document.BoneComplete and not E.Document.MeshComplete and not E.Document.Usable, 'upstream edit invalidates completion');
    A := ArgsId(PartId); AddN(A, 'delta', 1); Command(E, 'move-layer', A);
    Check((E.Document.Layers[1].Id = PartId) and (E.Document.Mesh(MeshId).Vertices[0].Weights[0].BoneId = BoneId), 'reorder preserves mesh and weight ids');
    A := TJSONObject.Create; A.AddPair('name', '階層'); Command(E, 'add-group', A); GroupId := E.SelectedId;
    A := ArgsId(PartId); A.AddPair('parentId', GroupId); Command(E, 'set-parent', A);
    Check((E.Document.ParentId(PartId) = GroupId) and (E.Document.Mesh(MeshId).PartId = PartId), 'reparent preserves stable references');
    Rejected('layer hierarchy cycle rejected', procedure begin var A := ArgsId(GroupId); A.AddPair('parentId', GroupId); Command(E, 'set-parent', A); end);
    Revision := E.Document.Art.Revision; OriginalName := E.Document.Art.FindLayer(PartId).Name;
    Batch := TJSONObject.Create; Operations := TJSONArray.Create; Batch.AddPair('operations', Operations);
    Operation := TJSONObject.Create; Operations.AddElement(Operation); Operation.AddPair('command', 'update-layer'); A := ArgsId(PartId); A.AddPair('name', 'should rollback'); Operation.AddPair('args', A);
    Operation := TJSONObject.Create; Operations.AddElement(Operation); Operation.AddPair('command', 'set-parent'); A := ArgsId(PartId); A.AddPair('parentId', 'missing'); Operation.AddPair('args', A);
    Rejected('batch with invalid operation rejected', procedure begin Command(E, 'batch', Batch); end);
    Check((E.Document.Art.Revision = Revision) and (E.Document.Art.FindLayer(PartId).Name = OriginalName), 'failed batch leaves document unchanged');
    A := TJSONObject.Create; AddB(A, 'confirmed', True); Command(E, 'verify-source', A);
    Command(E, 'mark-complete', TJSONObject.Create); Check(E.Document.LastPage = rpBone, 'layer completion advances to bones');
    Command(E, 'mark-complete', TJSONObject.Create); Check(E.Document.LastPage = rpMesh, 'bone completion advances to meshes');
    Command(E, 'mark-complete', TJSONObject.Create); Check(E.Document.LastPage = rpPreview, 'mesh completion advances to preview');
    E.Document.SourceMatched := False;
    Command(E, 'mark-complete', TJSONObject.Create);
    Check(E.Document.Usable, 'valid preview completes without explicit review');
    Check(not E.Document.SourceMatched, 'completion does not fabricate source confirmation');
    E.Save(FileName); Loaded := LoadRigm(FileName);
    try Check(Loaded.Usable and (Loaded.LastPage = rpPreview), 'usable status and last page survive reload'); finally Loaded.Free; end;
    Check(FileExists(FileName + '.bak'), 'atomic save keeps prior backup');
    E.SwitchPage(rpBone); RootId := E.Document.Bones[0].Id; ChildId := E.Document.Bones[1].Id;
    var OldX := E.Document.Bone(ChildId).X; var OldY := E.Document.Bone(ChildId).Y;
    A := ArgsId(RootId); Command(E, 'hide-bone', A);
    Check(not E.Document.Bone(RootId).Visible and not E.Document.Bone(ChildId).Visible and (E.Document.Bones.Count = 6), 'bone deletion hides descendants without deleting data');
    A := ArgsId(RootId); Command(E, 'restore-bone', A);
    Check(E.Document.Bone(RootId).Visible and not E.Document.Bone(ChildId).Visible, 'restore hidden parent one level at a time');
    A := ArgsId(RootId); Command(E, 'restore-bone', A);
    Check(E.Document.Bone(ChildId).Visible and SameValue(E.Document.Bone(ChildId).X, OldX) and SameValue(E.Document.Bone(ChildId).Y, OldY), 'restored bones keep adjusted coordinates');
    E.Undo; E.Undo; E.Undo;
    Check(E.Document.BoneComplete and E.Document.MeshComplete and E.Document.Bone(ChildId).Visible, 'undo restores stage flags and bone data');
    Revision := E.Document.Art.Revision; E.Redo; Check(E.Document.Art.Revision > Revision, 'redo revision remains monotonic'); E.Undo;
    var LeftId := E.Document.Bones[4].Id; var RightId := E.Document.Bones[5].Id;
    var RightX := E.Document.Bone(RightId).X;
    A := ArgsId(LeftId); AddN(A, 'x', E.Document.Bone(LeftId).X + 10); AddB(A, 'paired', True); Command(E, 'update-bone', A);
    Check(SameValue(E.Document.Bone(RightId).X, RightX - 10), 'paired bone motion mirrors x'); E.Undo;
    A := ArgsId(RootId); A.AddPair('parentId', ChildId); Command(E, 'update-bone', A);
    Issues := ValidateRigm(E.Document);
    try Check(HasErrors(Issues, rpBone), 'bone cycle detected'); finally Issues.Free; end;
    Rejected('bone cycle blocks completion', procedure begin Command(E, 'mark-complete', TJSONObject.Create); end); E.Undo;
    E.SwitchPage(rpMesh); A := ArgsId(MeshId); AddN(A, 'face', 0); Command(E, 'add-vertex', A);
    Check(Length(E.Document.Mesh(MeshId).Vertices) = 10, 'adding vertex splits a face');
    Issues := ValidateRigm(E.Document); try Check(not HasErrors(Issues, rpMesh), 'split mesh remains valid'); finally Issues.Free; end;
    E.Undo; A := ArgsId(MeshId); AddN(A, 'vertex', -1); var Weights := TJSONArray.Create; A.AddPair('weights', Weights);
    B := TJSONObject.Create; Weights.AddElement(B); B.AddPair('boneId', BoneId); AddN(B, 'value', 0.5);
    Rejected('invalid weight sum refused before commit', procedure begin Command(E, 'set-weights', A); end);
    // Arrange damaged legacy data directly to keep exercising the existing repair path.
    for var I := 0 to High(E.Document.Mesh(MeshId).Vertices) do E.Document.Mesh(MeshId).Vertices[I].Weights[0].Value := 0.5;
    Issues := ValidateRigm(E.Document); try Check(HasErrors(Issues, rpMesh), 'invalid weight sum detected'); finally Issues.Free; end;
    A := TJSONObject.Create; A.AddPair('issueId', 'weight-sum:' + MeshId); Command(E, 'autofix', A);
    Check(SameValue(E.Document.Mesh(MeshId).Vertices[0].Weights[0].Value, 1), 'weight repair normalizes to one');
    A := TJSONObject.Create; A.AddPair('issueId', 'weight-sum:' + MeshId);
    Rejected('blocking error cannot be ignored', procedure begin Command(E, 'ignore-issue', A); end);
    Pose := TRigmPose.Create;
    try
      Pixels := RenderRigm(E.Document, nil, 512, W, H); Pose.Values.Add('headAngle', 20);
      Deformed := RenderRigm(E.Document, Pose, 512, W, H);
      Check(not CompareMem(@Pixels[0], @Deformed[0], Length(Pixels)), 'bone pose actually deforms rendered images');
      Pose.Values.Add('gazeX', 1); Pose.Values.Add('eyeOpen', 0.2); Pose.Values.Add('mouthOpen', 1);
      Deformed := RenderRigm(E.Document, Pose, 512, W, H); Check(Length(Deformed) = Length(Pixels), 'multiple parameters render together');
    finally Pose.Free; end;
    E.Save(FileName); Loaded := LoadRigm(FileName);
    try Check(not Loaded.Usable and not Loaded.MeshComplete, 'unfinished mesh saved and reloaded safely'); finally Loaded.Free; end;
    Rejected('wrong page mutation refused', procedure begin Command(E, 'update-layer', ArgsId(PartId)); end);
  finally E.Free; end;
end;

procedure RunImportTests;
var E: TRigmEditor; Source: TArtDocument; Group, Image: TArtLayer; Loaded: TRigmDocument;
    Directory, PsdPath, PngPath, Id, RigmPath, JobDirectory: string; A, Reply, Manifest, Operation: TJSONObject;
    Pixels: TBytes; Operations: TJSONArray; Revision: UInt64;
begin
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Import'); ForceDirectories(Directory);
  PsdPath := TPath.Combine(Directory, 'source.psd'); PngPath := TPath.Combine(Directory, 'source.png');
  RigmPath := TPath.Combine(Directory, 'imported.rigm'); Source := TArtDocument.Create;
  E := TRigmEditor.Create;
  try
    Source.Width := 8; Source.Height := 8;
    Group := Source.AddLayer(alkGroup, 'group', TArtBounds.Create(0, 0, 0, 0));
    Image := Source.AddLayer(alkImage, 'image', TArtBounds.Create(0, 0, 8, 8), Group);
    SetLength(Pixels, 8 * 8 * 4);
    for var I := 0 to 63 do begin Pixels[I * 4] := 180; Pixels[I * 4 + 1] := 70; Pixels[I * 4 + 3] := I * 4; end;
    Image.Pixels := Pixels; Image.HasMask := True; Image.MaskBounds := Image.Bounds;
    Image.MaskDefault := 255; SetLength(Image.MaskPixels, 64);
    for var I := 0 to 63 do Image.MaskPixels[I] := 255; Image.MaskPixels[0] := 0;
    WriteNewPsd(Source, PsdPath); WriteRgbaPng(PngPath, 8, 8, Pixels);
    E.NewDocument('PSD import', 8, 8); A := TJSONObject.Create; A.AddPair('path', PsdPath); Command(E, 'import-psd', A);
    Check((E.Document.Parts.Count = 2) and (E.Document.Art.Roots[0].Children.Count = 1), 'PSD import preserves group hierarchy');
    Image := E.Document.Art.Roots[0].Children[0]; Id := Image.Id;
    Check(CompareMem(@Image.Pixels[0], @Pixels[0], Length(Pixels)) and Image.HasMask and (Image.MaskPixels[0] = 0), 'PSD import preserves alpha and mask');
    Check(Length(E.Document.ReferencePixels) = 256, 'PSD import retains rendered source reference');
    E.Save(RigmPath); Loaded := LoadRigm(RigmPath);
    try Check((Loaded.Art.FindLayer(Id).MaskPixels[0] = 0) and (Loaded.Art.FindLayer(Id).Pixels[7] = 4), 'imported mask and alpha survive RIGM reload'); finally Loaded.Free; end;
    Rejected('PSD import into nonempty document refused', procedure begin var A := TJSONObject.Create; A.AddPair('path', PsdPath); Command(E, 'import-psd', A); end);
    TFile.WriteAllText(TPath.Combine(Directory, 'invalid.rigm'), 'invalid');
    Rejected('invalid RIGM open refused', procedure begin E.Open(TPath.Combine(Directory, 'invalid.rigm')); end);
    Check(E.Document.Art.FindLayer(Id) <> nil, 'failed open leaves current document intact');
    E.NewDocument('PNG import', 8, 8); A := TJSONObject.Create; A.AddPair('path', PngPath); Command(E, 'import-png', A); Id := E.SelectedId;
    Check(CompareMem(@E.Document.Art.FindLayer(Id).Pixels[0], @Pixels[0], Length(Pixels)), 'PNG import preserves straight alpha pixels');
    A := ArgsId(Id); A.AddPair('path', PngPath); Command(E, 'replace-png', A);
    Check((E.Document.Parts.Count = 1) and (E.Document.Art.FindLayer(Id) <> nil), 'PNG replacement keeps stable part id');
    A := TJSONObject.Create; A.AddPair('root', TPath.Combine(Directory, 'Exchange'));
    try Reply := E.Execute('export', A); try JobDirectory := JS(Reply, 'directory'); finally Reply.Free; end; finally A.Free; end;
    Manifest := ParseObject(TFile.ReadAllText(TPath.Combine(JobDirectory, 'manifest.json'), TEncoding.UTF8));
    try Check((JA(Manifest, 'exportedAssets').Count = 1) and (Length(JS(TJSONObject(JA(Manifest, 'exportedAssets')[0]), 'sha256')) = 64), 'exchange exports PNG mapping and hash'); finally Manifest.Free; end;
    Check(FileExists(TPath.Combine(JobDirectory, 'snapshot.rigm')) and FileExists(TPath.Combine(JobDirectory, 'part-000000.png')), 'exchange includes RIGM snapshot and bounded asset name');
    Revision := E.Document.Art.Revision; Manifest := TJSONObject.Create;
    try
      Manifest.AddPair('documentId', E.Document.FileId); Manifest.AddPair('revision', Revision.ToString);
      Operations := TJSONArray.Create; Manifest.AddPair('operations', Operations);
      Operation := TJSONObject.Create; Operations.AddElement(Operation); Operation.AddPair('command', 'update-layer');
      A := ArgsId(Id); A.AddPair('name', 'exchange rename'); Operation.AddPair('args', A);
      TFile.WriteAllText(TPath.Combine(JobDirectory, 'result.json'), Manifest.ToJSON, TEncoding.UTF8);
    finally Manifest.Free; end;
    A := TJSONObject.Create; A.AddPair('path', TPath.Combine(JobDirectory, 'result.json')); Command(E, 'import', A);
    Check(E.Document.Art.FindLayer(Id).Name = 'exchange rename', 'exchange operations import applies atomically');
    Rejected('stale exchange revision refused', procedure begin var A := TJSONObject.Create; A.AddPair('path', TPath.Combine(JobDirectory, 'result.json')); Command(E, 'import', A); end);
    Rejected('duplicate JSON keys refused', procedure begin var O := ParseObject('{"id":1,"id":2}'); O.Free; end);
  finally E.Free; Source.Free; end;
end;

procedure RunPipeHost;
var E: TRigmEditor; Hub: TRigmPipeHub; Directory: string; Start: UInt64;
begin
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Sender'); ForceDirectories(Directory);
  E := TRigmEditor.Create; Hub := nil;
  try
    E.NewDocument('sender integration', 256, 320); PopulateRigmSample(E.Document);
    Hub := TRigmPipeHub.Create(E, Directory);
    TFile.WriteAllText(TPath.Combine(Directory, 'ready.txt'), Hub.ConnectionFile, TEncoding.UTF8);
    Start := GetTickCount64;
    while (GetTickCount64 - Start < 60000) and not FileExists(TPath.Combine(Directory, 'stop.txt')) do begin Pump; Sleep(5); end;
  finally Hub.Free; E.Free; end;
end;

procedure RunPipeTests;
var E: TRigmEditor; Hub: TRigmPipeHub; Reply, A: TJSONObject; OldName: string;
    Revision: UInt64; PipeDirectory: string;
begin
  E := TRigmEditor.Create; Hub := nil;
  try
    E.NewDocument('pipe tests', 256, 320); PopulateRigmSample(E.Document);
    PipeDirectory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'pipes'); Hub := TRigmPipeHub.Create(E, PipeDirectory);
    Reply := PipeCall(Hub.ControlName, 'status', TJSONObject.Create);
    if not JB(Reply, 'ok') then Writeln('PIPE FAILURE: ' + Reply.ToJSON);
    try Check(JB(Reply, 'ok') and (JS(JO(Reply, 'data'), 'application') = 'RIGM Maker'), 'common pipe status'); finally Reply.Free; end;
    OldName := Hub.PagePipeName; Revision := E.Document.Art.Revision;
    A := RevisionArgs(E); A.AddPair('page', 'bone'); Reply := PipeCall(Hub.ControlName, 'switch-page', A);
    try Check(JB(Reply, 'ok') and (E.Document.LastPage = rpBone) and (Hub.PagePipeName <> OldName), 'pipe page switch replaces dedicated endpoint'); finally Reply.Free; end;
    Check(not WaitNamedPipe(PChar('\\.\pipe\' + OldName), 100), 'old page pipe disconnected');
    A := RevisionArgs(E); A.AddPair('id', E.Document.Layers[0].Id); Reply := PipeCall(Hub.PagePipeName, 'update-layer', A);
    try Check(not JB(Reply, 'ok'), 'bone pipe refuses layer command'); finally Reply.Free; end;
    A := TJSONObject.Create; A.AddPair('documentId', E.Document.FileId); A.AddPair('revision', Revision.ToString); A.AddPair('page', 'mesh');
    Reply := PipeCall(Hub.ControlName, 'switch-page', A); try Check(not JB(Reply, 'ok'), 'stale revision refused'); finally Reply.Free; end;
    A := RevisionArgs(E); A.AddPair('id', E.Document.Bones[0].Id); Reply := PipeCall(Hub.ControlName, 'hide-bone', A);
    try Check(JB(Reply, 'ok'), 'common pipe dispatches bone editing commands'); finally Reply.Free; end;
    E.Undo;
    A := RevisionArgs(E); A.AddPair('page', 'preview'); Reply := PipeCall(Hub.ControlName, 'switch-page', A);
    try Check(JB(Reply, 'ok') and (Hub.PagePipeName = ''), 'preview has no dedicated pipe'); finally Reply.Free; end;
    A := RevisionArgs(E); A.AddPair('page', 'layer'); Reply := PipeCall(Hub.ControlName, 'switch-page', A); Reply.Free;
    OldName := Hub.PagePipeName;
    Reply := PipeCall(Hub.PagePipeName, 'mark-complete', RevisionArgs(E));
    try Check(JB(Reply, 'ok'), 'dedicated completion reply survives endpoint rotation'); finally Reply.Free; end;
    for var I := 0 to 50 do begin Pump; if Hub.PagePipeName <> OldName then Break; Sleep(2); end;
    Check((E.Document.LastPage = rpBone) and (Hub.PagePipeName <> OldName), 'dedicated completion rotates after response');
    A := TJSONObject.Create; A.AddPair('section', 'parts'); AddN(A, 'limit', 2); Reply := PipeCall(Hub.ControlName, 'document', A);
    try Check(JB(Reply, 'ok') and (JA(JO(Reply, 'data'), 'items').Count = 2), 'document metadata supports bounded pagination'); finally Reply.Free; end;
    var ConnectionFile := Hub.ConnectionFile; FreeAndNil(Hub);
    Check(not FileExists(ConnectionFile), 'pipe shutdown removes discovery file');
  finally Hub.Free; E.Free; end;
end;

procedure Run;
var D, Loaded: TRigmDocument; Layer: TArtLayer; Issues: TRigmIssues;
    Pixels, Thumb: TBytes; W, H: Integer; Name, FileName: string;
begin
  D := TRigmDocument.Create;
  try
    D.Art.Width := 16; D.Art.Height := 16;
    Check(D.CanOpen(rpLayer) and not D.CanOpen(rpBone), 'initial stage gating');
    Layer := D.Art.AddLayer(alkImage, 'test', TArtBounds.Create(0, 0, 16, 16));
    SetLength(Layer.Pixels, 16 * 16 * 4);
    for var I := 0 to 255 do begin Layer.Pixels[I * 4] := 200; Layer.Pixels[I * 4 + 3] := 255; end;
    D.SyncParts;
    Pixels := RenderRigm(D, nil, 16, W, H);
    Check((W = 16) and (H = 16) and CompareMem(@Pixels[0], @Layer.Pixels[0], Length(Pixels)), 'rest render preserves pixels');
    Issues := ValidateRigm(D);
    try Check(HasErrors(Issues, rpLayer), 'incomplete character validation'); finally Issues.Free; end;
    FileName := TPath.Combine(ExtractFilePath(ParamStr(0)), 'roundtrip.rigm');
    SaveRigm(D, FileName); Loaded := LoadRigm(FileName);
    try
      Check(Loaded.FileId = D.FileId, 'document id roundtrip');
      Check(Loaded.Layers[0].Id = Layer.Id, 'part id roundtrip');
      Check(not Loaded.Usable, 'incomplete file stays unusable');
    finally Loaded.Free; end;
    Thumb := ReadRigmThumbnail(FileName, Name, W, H);
    Check((Length(Thumb) = W * H * 4) and (Name = D.Name), 'thumbnail without loading all parts');
  finally D.Free; end;
end;

begin
  if (ParamCount > 0) and (ParamStr(1) = '--pipe-host') then begin RunPipeHost; Exit; end;
  Results := TJSONArray.Create;
  try
    try Run; RunEditorTests; RunImportTests; RunPipeTests; Writeln(Format('%d tests passed', [Count]));
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Results.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report, 'passed', Count); AddB(Report, 'success', ExitCode = 0); Report.AddPair('checks', Results); Results := nil;
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)), 'results.json'), Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  finally Results.Free; end;
end.
