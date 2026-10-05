program PsdValidation;
{$APPTYPE CONSOLE}

// 破損入力、排他表示、音素区間、保存往復、復元可能な回収に限定した実行検証。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Zip,
  System.DateUtils, System.Generics.Collections, System.Hash, Winapi.Windows,
  ArtDocument, ArtPng, ArtPsd, PsdJson, PsdWorkspace, PsdCharacter, PsdPackage,
  PsdAnimation, PsdImport, PsdSession, ArtPipeProtocol;

var Passed: Integer;
procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Message);
  Inc(Passed); Writeln('PASS: ' + Message);
end;
procedure Reject(const Action: TProc; const Message: string);
begin
  var Rejected := False; try Action(); except on E: Exception do Rejected := True; end; Check(Rejected, Message);
end;
function Equal(const A, B: TBytes): Boolean;
begin Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A))); end;
function Fixture: TPsdCharacter;
var C: TPsdCharacter;
  function MakeGroup(const Name: string; X, Y: Integer; const Colors: array of Byte): TJSONObject;
  begin
    var Group := C.Document.AddLayer(alkGroup, Name, TArtBounds.Create(0, 0, 8, 8), C.Front);
    Result := TJSONObject.Create; Arr(C.Settings, 'groups').AddElement(Result);
    Result.AddPair('id', Group.Id); Result.AddPair('name', Name); var Parts := TJSONArray.Create; Result.AddPair('partIds', Parts);
    for var Color in Colors do begin
      var L := C.Document.AddLayer(alkImage, '*' + Color.ToString, TArtBounds.Create(X, Y, X + 1, Y + 1), Group);
      L.Pixels := TBytes.Create(Color, 0, 0, 255); L.Visible := Parts.Count = 0; Parts.Add(L.Id);
    end;
    Result.AddPair('defaultPartId', Parts[0].Value);
  end;
begin
  C := TPsdCharacter.Create; C.Name := 'validation'; C.Document.Width := 8; C.Document.Height := 8;
  var F := C.Document.AddLayer(alkGroup, '*正面', TArtBounds.Create(0, 0, 8, 8)); Put(C.Settings, 'frontId', F.Id);
  var NF := C.Document.AddLayer(alkGroup, '*非正面', TArtBounds.Create(0, 0, 8, 8)); NF.Visible := False; Put(C.Settings, 'nonFrontId', NF.Id);
  var Eye := MakeGroup('eyes', 1, 1, [40, 80, 120]); var Mouth := MakeGroup('mouth', 1, 2, [50, 100, 150]);
  var A := TJSONObject.Create; C.Settings.AddPair('animation', A);
  var Blink := TJSONObject.Create; A.AddPair('blink', Blink); Blink.AddPair('groupId', S(Eye, 'id'));
  Blink.AddPair('normalPartId', Arr(Eye, 'partIds')[0].Value); Blink.AddPair('halfOpenPartId', Arr(Eye, 'partIds')[1].Value); Blink.AddPair('closedPartId', Arr(Eye, 'partIds')[2].Value);
  var Lip := TJSONObject.Create; A.AddPair('lipSync', Lip); Lip.AddPair('groupId', S(Mouth, 'id')); Lip.AddPair('closedPartId', Arr(Mouth, 'partIds')[0].Value);
  var Phones := TJSONObject.Create; Lip.AddPair('phonemePartIds', Phones); Phones.AddPair('a', Arr(Mouth, 'partIds')[1].Value); Phones.AddPair('closed', Arr(Mouth, 'partIds')[0].Value);
  Put(Obj(C.Settings, 'gaze'), 'front', Arr(Eye, 'partIds')[0].Value);
  Put(Obj(C.Settings, 'gaze'), 'left', Arr(Eye, 'partIds')[1].Value);
  var P := C.Document.AddLayer(alkImage, '*back', TArtBounds.Create(5, 5, 6, 6), NF); P.Pixels := TBytes.Create(0, 255, 0, 255); P.Visible := False;
  var Pose := TJSONObject.Create; Arr(C.Settings, 'nonFront').AddElement(Pose); Pose.AddPair('id', 'back'); Pose.AddPair('kind', 'pose'); Pose.AddPair('name', 'back'); Pose.AddPair('layerId', P.Id);
  C.Validate; Result := C;
end;
procedure Age(Workspace: TPsdWorkspace; const Dir, Status, Owner: string);
begin
  var O := TJSONObject.Create;
  try
    O.AddPair('owner', Owner); O.AddPair('jobId', ExtractFileName(Dir)); O.AddPair('status', Status);
    O.AddPair('finishedUtc', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now) - 31, True));
    TFile.WriteAllText(TPath.Combine(Dir, 'job.json'), O.ToJSON, TEncoding.UTF8);
  finally O.Free; end;
end;
procedure Run;
begin
  var Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'TestData\' + NewId);
  var W := TPsdWorkspace.Create(Root); var C := Fixture; var R: TPsdRenderer := nil;
  try
    W.Initialize;
    Reject(procedure begin W.Resolve('..\outside.png', False); end, 'reject parent traversal');
    Reject(procedure begin W.Resolve(Root + '-sibling\image.png', False); end, 'reject same-prefix sibling');
    Reject(procedure begin W.Resolve('Exchange\image.png:secret', False); end, 'reject alternate streams');
    Reject(procedure begin W.Resolve('\\localhost\share\image.png', False); end, 'reject UNC/device paths');
    Reject(procedure begin W.Resolve('Exchange\CON.png', False); end, 'reject Windows device filename');
    Reject(procedure begin var V := Parse('{"x":1,"x":2}'); V.Free; end, 'reject duplicate JSON keys');
    R := TPsdRenderer.Create(C, W, 0); var V := TPsdFrameState.Default; V.Motion := 'none';
    var A := R.Composite(V); Check(A[(1 * 8 + 1) * 4] = 40, 'initial exclusive eye');
    V.Seconds := 3.83; V.HasPhoneme := True; V.Phoneme := 'a';
    A := R.Composite(V); Check((A[(1 * 8 + 1) * 4] = 120) and (A[(2 * 8 + 1) * 4] = 100), 'blink and fast phoneme compose together');
    V.Seconds := 4.01; V.Gaze := 'left'; A := R.Composite(V); Check(A[(1 * 8 + 1) * 4] = 80, 'blink restores selected gaze');
    V.Gaze := 'up'; Reject(procedure begin R.Composite(V); end, 'missing gaze is not fabricated');
    V.Gaze := 'left'; V.NonFrontId := 'back'; A := R.Composite(V);
    Check((A[(1 * 8 + 1) * 4 + 3] = 0) and (A[(2 * 8 + 1) * 4 + 3] = 0) and (A[(5 * 8 + 5) * 4 + 3] = 255), 'non-front removes all facial layers');
    var D := R.Choices(V); try Check(D.Count = 0, 'non-front ignores blink and phoneme selection'); finally D.Free; end;
    V.NonFrontId := ''; V.Gaze := 'front'; V.Motion := 'sway'; V.Seconds := 1;
    var StateBefore := R.Composite(V); R.Frame(V, 320, 180); Check(Equal(StateBefore, R.Composite(V)), 'small motion preserves composed facial state');
    Check(Length(R.Frame(V)) = 1920 * 1080 * 4, 'FullHD frame base');
    var Track := TPsdPhonemeTrack.Create; var Events := TJSONArray.Create;
    try
      var E := ObjectText('{"start":0,"end":0.03,"phoneme":"a"}'); Events.AddElement(E);
      E := ObjectText('{"start":0.03,"end":0.06,"phoneme":"i"}'); Events.AddElement(E); Track.Load(Events);
      Check((Track.Sample(0.029) = 'a') and (Track.Sample(0.03) = 'i') and (Track.Sample(0.06) = 'closed'), 'phoneme half-open boundaries at 30ms');
    finally Events.Free; Track.Free; end;
    SaveCharacter(C, W, 'Characters\fixture.psdchar'); var Reopened := LoadCharacter(W, 'Characters\fixture.psdchar');
    try
      Check(Equal(C.Document.RenderRGBA, ArtPsd.RenderPsdLayers(Reopened.Document)), 'PSD/package roundtrip preserves RGBA');
      Check(Reopened.Document.FindLayer(C.Front.Id) <> nil, 'stable layer IDs survive PSD serialization');
      SaveCharacter(Reopened, W, 'Characters\fixture.psdchar');
    finally Reopened.Free; end;
    var Job := W.BeginJob;
    try
      WriteRgbaPng(Job.FilePath('valid.png'), 1, 1, TBytes.Create(4, 5, 6, 255));
      var Args := ObjectText('{"groupId":"' + S(TJSONObject(Arr(C.Settings, 'groups')[0]), 'id') + '","path":"' + Job.FilePath('valid.png').Replace('\', '\\') + '","name":"new","sha256":"' + StringOfChar('0', 64) + '"}');
      try Reject(procedure begin AddFrontLayer(C, W, Args); end, 'reject mismatched image digest'); finally Args.Free; end;
      var Sequence := TJSONObject.Create;
      try
        Sequence.AddPair('kind', 'sequence'); Sequence.AddPair('name', 'two-frame'); Sequence.AddPair('fps', TJSONNumber.Create(20)); Sequence.AddPair('loop', TJSONBool.Create(True));
        var Frames := TJSONArray.Create; Sequence.AddPair('frames', Frames);
        for var Color in [10, 20] do begin
          var Path := Job.FilePath(Color.ToString + '.png'); WriteRgbaPng(Path, 1, 1, TBytes.Create(Color, 0, 0, 255));
          var F := TJSONObject.Create; Frames.AddElement(F); F.AddPair('path', Path); F.AddPair('sha256', THashSHA2.GetHashStringFromFile(Path));
        end;
        AddNonFront(C, W, Sequence); R.Free; R := TPsdRenderer.Create(C, W, 0);
        V.NonFrontId := S(TJSONObject(Arr(C.Settings, 'nonFront')[1]), 'id'); V.Seconds := 0;
        Check(R.Composite(V)[0] = 10, 'whole-body sequence first frame'); V.Seconds := 0.05; Check(R.Composite(V)[0] = 20, 'whole-body sequence exact boundary');
        V.Seconds := 0.10; var Pixels := R.Composite(V); Check((Pixels[0] = 10) and (Pixels[(1 * 8 + 1) * 4 + 3] = 0), 'whole-body sequence loops without face remnants');
        SaveCharacter(C, W, 'Characters\fixture.psdchar'); var Saved := LoadCharacter(W, 'Characters\fixture.psdchar');
        try Check(Saved.Assets.Count = 2, 'motion frames reside in single package'); finally Saved.Free; end;
      finally Sequence.Free; end;
      TFile.WriteAllText(Job.FilePath('invalid.png'), 'not PNG'); Reject(procedure begin ReadPng(Job.FilePath('invalid.png')); end, 'reject invalid PNG header');
    finally Job.Free; end;
    var Zip := TZipFile.Create;
    try Zip.Open(W.Resolve('Characters\hostile.psdchar', False), zmWrite); Zip.Add(TBytes.Create(1), '../escape.png'); Zip.Close;
    finally Zip.Free; end;
    Reject(procedure begin var X := LoadCharacter(W, 'Characters\hostile.psdchar'); X.Free; end, 'reject ZIP traversal before extraction');
    C.Policy := 'external'; Reject(procedure begin C.RequireManaged; end, 'external PSD content editing blocked'); C.Policy := 'managed';
    ExportPsd(C, W, 'Characters\fixture-source.psd');
    var External := ImportExternalPsd(W, 'Characters\fixture-source.psd');
    try
      var OriginalBytes := External.Document.SourceBytes; SaveCharacter(External, W, 'Characters\external.psdchar'); ExportPsd(External, W, 'Characters\external.psd');
      Check(Equal(OriginalBytes, TFile.ReadAllBytes(W.Resolve('Characters\external.psd'))), 'external PSD export preserves original archive bytes');
    finally External.Free; end;
    var Finished := W.BeginJob; var CompletedPath := Finished.Directory; TFile.WriteAllText(Finished.FilePath('retain.txt'), 'recoverable'); Finished.Free;
    Age(W, CompletedPath, 'completed', 'RIGMMaker.PsdJobs.v1');
    var Active := W.BeginJob;
    try
      Age(W, Active.Directory, 'completed', 'RIGMMaker.PsdJobs.v1');
      var Unknown := W.BeginJob; var UnknownPath := Unknown.Directory; Unknown.Free; Age(W, UnknownPath, 'completed', 'someone-else');
      var Input := W.Resolve('Work\input.png', False); ForceDirectories(ExtractFileDir(Input)); TFile.WriteAllText(Input, 'keep');
      var Recovered := W.Cleanup; Writeln('Cleanup count: ', Recovered, '; ', W.CleanupNotes);
      Check(Recovered = 1, 'only expired owned completed job is recovered');
      Check(DirectoryExists(Active.Directory) and DirectoryExists(UnknownPath) and FileExists(Input), 'active jobs, unrelated jobs and input Work preserved');
      var Recovery := TDirectory.GetDirectories(W.Resolve('Temp\PsdRecovery', False));
      Check((Length(Recovery) = 1) and FileExists(TPath.Combine(Recovery[0], 'retain.txt')), 'recovery retains original contents');
    finally Active.Free; end;
  finally R.Free; C.Free; W.Free; end;
end;
begin
  try Run; Writeln('RESULT: ', Passed, ' checks passed');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
