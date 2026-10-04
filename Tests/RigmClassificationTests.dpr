program RigmClassificationTests;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  ArtDocument, ArtPsd, ArtPng, RigmModel, RigmEditor, RigmJson, RigmStorage,
  RigmRenderer, RigmValidation, RigmClassification;

var Count: Integer; Checks: TJSONArray; Directory, OriginalHash: string; OriginalTested: Boolean;

const OriginalPsd = 'C:\Users\zan12\Documents\Syncroh2\PSD\Generated\東北きりたん_立ち絵.psd';

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Checks.Add(Name); Writeln('PASS: ' + Name);
end;

procedure Command(E: TRigmEditor; const Name: string; Args: TJSONObject);
var Reply: TJSONObject;
begin
  try Reply := E.Execute(Name, Args); Reply.Free; finally Args.Free; end;
end;

function Image(Doc: TRigmDocument; const Name: string; Parent: TArtLayer = nil; Visible: Boolean = True): TArtLayer;
begin
  Result := Doc.Art.AddLayer(alkImage, Name, TArtBounds.Create(4, 4, 8, 8), Parent);
  Result.Visible := Visible; SetLength(Result.Pixels, 64);
  for var I := 0 to 15 do begin
    Result.Pixels[I * 4] := 120; Result.Pixels[I * 4 + 1] := 80;
    Result.Pixels[I * 4 + 2] := 180; Result.Pixels[I * 4 + 3] := 200;
  end;
  Doc.SyncParts;
end;

function Group(Doc: TRigmDocument; const Name: string; Parent: TArtLayer = nil): TArtLayer;
begin Result := Doc.Art.AddLayer(alkGroup, Name, TArtBounds.Create(0, 0, 0, 0), Parent); Doc.SyncParts; end;

function Find(Doc: TRigmDocument; const Name, ParentName: string): TArtLayer;
begin
  for var L in Doc.Layers do if L.Name = Name then begin
    var P := Doc.Art.FindLayer(Doc.ParentId(L.Id));
    if ((ParentName = '') and (P = nil)) or ((P <> nil) and (P.Name = ParentName)) then Exit(L);
  end;
  raise Exception.Create('Missing fixture: ' + ParentName + '/' + Name);
end;

procedure BuildObservedStructure(Doc: TRigmDocument);
var G: TArtLayer;
begin
  // Exact names/hierarchy observed via readonly pipe in the live revision-1 document.
  // Pixel buffers here are synthetic; the user's original PSD and document are never edited.
  Doc.Art.Width := 32; Doc.Art.Height := 32;
  G := Group(Doc, '髪（前）');
  for var N in TArray<string>.Create('髪飾り 画面左', '髪飾り 画面右', 'アホ毛', '前髪', '横髪 画面左', '横髪 画面右') do Image(Doc, N, G);
  G := Group(Doc, '目');
  for var N in TArray<string>.Create('*通常', '*閉じ', '*やや閉じ', '*笑顔閉じ', '*半開き', '*やさしい目') do Image(Doc, N, G, N = '*通常');
  G := Group(Doc, '眉');
  for var N in TArray<string>.Create('*通常', '*喜', '*怒', '*哀', '*楽', '*困る', '*画面左上げ', '*画面右上げ') do Image(Doc, N, G, N = '*楽');
  G := Group(Doc, '口');
  for var N in TArray<string>.Create('*通常', '*閉じ', '*半開き', '*開き', '*あ', '*い', '*う', '*え', '*お', '*ん') do Image(Doc, N, G, N = '*あ');
  Image(Doc, '顔（額・耳の補完）');
  G := Group(Doc, '体（ポーズ）');
  for var N in TArray<string>.Create('*通常', '*左上を指さす', '*右上を指さす', '*手のひらで紹介', '*腕組み', '*胸に手を添える') do Image(Doc, N, G, N = '*通常');
  Image(Doc, '後ろ髪（左右の付け根補完）'); Image(Doc, '元画像（比較用・非表示）', nil, False);
  Doc.ReferencePixels := RenderRigm(Doc, nil, 32, Doc.Art.Width, Doc.Art.Height);
end;

function HasIssue(Doc: TRigmDocument; const Code: string): Boolean;
var Issues: TRigmIssues;
begin
  Result := False; Issues := ValidateRigm(Doc);
  try for var Issue in Issues do if Issue.Code = Code then Exit(True); finally Issues.Free; end;
end;

procedure CheckRoles(Doc: TRigmDocument);
var Counts: TArray<Integer>;
const Roles: array[0..7] of string = ('eye','brow','mouth','hair','accessory','face','body','reference');
      Expected: array[0..7] of Integer = (6,8,10,5,2,1,6,1);
begin
  SetLength(Counts, Length(Roles));
  for var L in Doc.Layers do if L.Kind = alkImage then
    for var I := 0 to High(Roles) do if Doc.Part(L.Id).Role = Roles[I] then Inc(Counts[I]);
  for var I := 0 to High(Roles) do Check(Counts[I] = Expected[I], 'observed role count ' + Roles[I]);
end;

procedure RunObserved;
var E: TRigmEditor; Loaded: TRigmDocument; Path, BeforeHash, Ids: string; Args: TJSONObject; W,H: Integer;
begin
  E := TRigmEditor.Create;
  try
    BuildObservedStructure(E.Document);
    Check(E.Document.Parts.Count = 44, 'observed five groups and 39 images reproduced');
    Path := TPath.Combine(Directory, 'observed-structure.psd'); WriteNewPsd(E.Document.Art, Path, pcRle);
    BeforeHash := THashSHA2.GetHashStringFromFile(Path);
    E.NewDocument('classification', 32, 32); Args := TJSONObject.Create; Args.AddPair('path', Path); Command(E, 'import-psd', Args);
    CheckRoles(E.Document);
    Check((E.Document.Part(Find(E.Document, '*通常', '目').Id).Role = 'eye') and
      (E.Document.Part(Find(E.Document, '*通常', '眉').Id).Role = 'brow') and
      (E.Document.Part(Find(E.Document, '*通常', '口').Id).Role = 'mouth') and
      (E.Document.Part(Find(E.Document, '*通常', '体（ポーズ）').Id).Role = 'body'), 'duplicate normal names use parent context');
    Check((E.Document.Part(Find(E.Document, '*閉じ', '目').Id).Role = 'eye') and
      (E.Document.Part(Find(E.Document, '*閉じ', '口').Id).Role = 'mouth'), 'duplicate closed names use parent context');
    Check(not HasIssue(E.Document,'required-eye') and not HasIssue(E.Document,'required-brow') and
      not HasIssue(E.Document,'required-mouth') and not HasIssue(E.Document,'required-hair'), 'actual content in observed roles satisfies preparation requirements');
    Check(not HasIssue(E.Document,'source-review') and not E.Document.SourceMatched and not E.Document.LayerComplete,
      'classification does not fabricate source confirmation or complete a stage');
    var Ref := Find(E.Document, '元画像（比較用・非表示）', '');
    Check(E.Document.IsReferencePart(Ref.Id), 'comparison source is explicitly outside motion');
    var Pixels := RenderRigm(E.Document, nil, 32, W, H); Ref.Visible := True;
    var WithReference := RenderRigm(E.Document, nil, 32, W, H);
    Check(CompareMem(@Pixels[0], @WithReference[0], Length(Pixels)), 'visible comparison source is excluded from character rendering');
    Ref.Visible := False;
    Ids := ''; for var L in E.Document.Layers do Ids := Ids + L.Id + '|' + L.Name + '|';
    E.Save(TPath.Combine(Directory,'classified.rigm')); Loaded := LoadRigm(E.FileName);
    try
      var ReloadIds := ''; for var L in Loaded.Layers do ReloadIds := ReloadIds + L.Id + '|' + L.Name + '|';
      Check((Ids = ReloadIds) and Loaded.IsReferencePart(Ref.Id), 'classification names IDs and reference flag survive reload');
      CheckRoles(Loaded);
    finally Loaded.Free; end;
    Command(E,'mark-complete',TJSONObject.Create); Command(E,'mark-complete',TJSONObject.Create);
    Command(E,'generate-mesh',TJSONObject.Create);
    Check((E.Document.Meshes.Count = 38) and (E.Document.MeshForPart(Ref.Id) = nil), 'all movable images get meshes while comparison source is excluded');
    Check(not HasIssue(E.Document,'mesh-missing') and not HasIssue(E.Document,'weight-missing'), 'comparison source creates no false mesh requirement');
    Check(E.Document.MeshForPart(Find(E.Document,'髪飾り 画面左','髪（前）').Id).Vertices[0].Weights[0].BoneId =
      E.Document.Parameters[2].BoneId, 'hair ornament remains separate and follows head');
    Command(E,'mark-complete',TJSONObject.Create);
    Check((E.Document.LastPage = rpPreview) and not E.Document.Usable, 'observed structure reaches preview only after explicit stage review');
    Check(BeforeHash = THashSHA2.GetHashStringFromFile(Path), 'PSD input is unchanged');
  finally E.Free; end;
end;

procedure RunConservative;
var E: TRigmEditor; G, L, Manual, Comparison: TArtLayer; Args, Reply: TJSONObject;
begin
  E := TRigmEditor.Create;
  try
    E.NewDocument('conservative',32,32); G := Group(E.Document,'目');
    L := Image(E.Document,'*謎差分',G); Manual := Image(E.Document,'!右目:flipx',G);
    Args := TJSONObject.Create; Args.AddPair('id',Manual.Id); Args.AddPair('role','other'); Command(E,'update-layer',Args);
    G := E.Document.Art.FindLayer(G.Id); Manual := E.Document.Art.FindLayer(Manual.Id);
    Comparison := Image(E.Document,'元画像（比較用・非表示）');
    var P := E.Document.Part(Comparison.Id); P.Role := 'eye'; P.RoleManual := True;
    P.Tags := 'keep'; P.PairId := Manual.Id; P.X := 7;
    var Locked := Image(E.Document,'前髪'); E.Document.Part(Locked.Id).Locked := True;
    var Empty := Image(E.Document,'眉'); Empty.Pixels := nil; SetLength(Empty.Pixels,64);
    var Ornament := Image(E.Document,'髪飾り 画面左'); E.Document.Part(Ornament.Id).Role := 'hair';
    var Nested := Group(E.Document,'表情',G); var Normal := Image(E.Document,'*通常',Nested);
    var NoContext := Image(E.Document,'*通常');
    var Uncertain := Image(E.Document,'髪っぽい背景');
    Reply := E.Execute('classify-layers',TJSONObject.Create); Reply.Free;
    Normal := E.Document.Art.FindLayer(Normal.Id);
    Check((E.Document.Part(Manual.Id).Role = 'other') and E.Document.Part(Manual.Id).RoleManual, 'manual other role is preserved');
    Check((E.Document.Part(Comparison.Id).Role = 'eye') and (E.Document.Part(Comparison.Id).Tags = 'keep') and
      (E.Document.Part(Comparison.Id).PairId = Manual.Id) and (E.Document.Part(Comparison.Id).X = 7) and
      E.Document.IsReferencePart(Comparison.Id), 'manual values preserved while comparison identity stays nonmovable');
    Check((E.Document.Part(L.Id).Role = 'other') and (E.Document.Part(NoContext.Id).Role = 'other'), 'unknown name and ambiguous root normal stay unclassified');
    Check(E.Document.Part(Uncertain.Id).Role = 'other', 'loose hair substring is not accepted as a part name');
    Check(E.Document.Part(Locked.Id).Role = 'other', 'locked role stays unclassified');
    Check(E.Document.Part(Normal.Id).Role = 'eye', 'nearest recognized ancestor supports nested variant');
    Check(HasIssue(E.Document,'required-brow'), 'transparent named image cannot satisfy required brow');
    Check(HasIssue(E.Document,'required-hair'), 'ornament cannot satisfy required hair even with existing hair label');
    Normal.Pixels := nil; SetLength(Normal.Pixels,64);
    Check(HasIssue(E.Document,'required-eye'), 'comparison image cannot satisfy required eye even with manual eye label');
    var Plain := Image(E.Document,'!*横髪　画面右（補完）:flipx');
    var Masked := Image(E.Document,'口'); Masked.HasMask := True; Masked.MaskBounds := Masked.Bounds;
    Masked.MaskDefault := 0; SetLength(Masked.MaskPixels,16);
    Reply := E.Execute('classify-layers',TJSONObject.Create); Reply.Free;
    Check(E.Document.Part(Plain.Id).Role = 'hair', 'prefix flip annotation and fullwidth side suffix are normalized without renaming');
    Check(Plain.Name = '!*横髪　画面右（補完）:flipx', 'classifier preserves original decorated name');
    Check(HasIssue(E.Document,'required-mouth'), 'fully masked image cannot satisfy required mouth');
    var Revision := E.Document.Art.Revision; var Flags := E.Document.SourceMatched;
    Reply := E.Execute('classify-layers',TJSONObject.Create);
    try Check((JI(Reply,'classifiedCount') = 0) and (E.Document.Art.Revision = Revision) and
      (E.Document.SourceMatched = Flags), 'no-op reclassification preserves revision and review state'); finally Reply.Free; end;
    E.Save(TPath.Combine(Directory,'manual.rigm')); var Loaded := LoadRigm(E.FileName);
    try Check(Loaded.Part(Manual.Id).RoleManual and (Loaded.Part(Manual.Id).Role = 'other') and
      Loaded.IsReferencePart(Comparison.Id), 'manual role and comparison identity persist'); finally Loaded.Free; end;
    Check(not E.Document.LayerComplete and not E.Document.Usable, 'conservative inference cannot complete invalid preparation');
    var PngPath := TPath.Combine(Directory,'前髪.png');
    WriteRgbaPng(PngPath,4,4,Plain.Pixels);
    Args := TJSONObject.Create; Args.AddPair('path',PngPath); Args.AddPair('role','other'); Command(E,'import-png',Args);
    var PngId := E.SelectedId; Command(E,'classify-layers',TJSONObject.Create);
    Check((E.Document.Part(PngId).Role = 'other') and E.Document.Part(PngId).RoleManual,
      'explicit PNG import role is protected from reclassification');
  finally E.Free; end;
end;

procedure RunOriginal;
var E: TRigmEditor; Args: TJSONObject; Loaded: TRigmDocument; Ids: string;
  function Signature(Art: TArtDocument): string;
    procedure Visit(L: TArtLayer; Depth: Integer);
    begin
      Result := Result+Depth.ToString+'|'+L.Name+'|'+Ord(L.Kind).ToString+'|'+BoolToStr(L.Visible,True)+'|'+Length(L.Pixels).ToString+';';
      for var C in L.Children do Visit(C,Depth+1);
    end;
  begin Result := ''; for var L in Art.Roots do Visit(L,0); end;
  function LayerCount(L: TArtLayer): Integer;
  begin Result := 1; for var C in L.Children do Inc(Result,LayerCount(C)); end;
begin
  if not FileExists(OriginalPsd) then Exit;
  OriginalHash := THashSHA2.GetHashStringFromFile(OriginalPsd); E := TRigmEditor.Create;
  try
    // The user's live PSD can acquire new layers. Pin a read-only snapshot and
    // compare every imported layer against that input; RunObserved keeps exact fixture counts.
    var Snapshot := TPath.Combine(Directory,'readonly-input-'+NewRigmId+'.psd'); TFile.Copy(OriginalPsd,Snapshot,False);
    var Source := ReadPsd(Snapshot);
    try
      var ExpectedCount := 0; for var L in Source.Roots do Inc(ExpectedCount,LayerCount(L));
      Args := TJSONObject.Create; Args.AddPair('path',Snapshot); Command(E,'import-psd',Args);
      Check((E.Document.Parts.Count=ExpectedCount) and (Signature(E.Document.Art)=Signature(Source)),
        'actual user PSD snapshot preserves every layer, hierarchy, visibility and pixel count');
    finally Source.Free; end;
    Check(not HasIssue(E.Document,'required-eye') and not HasIssue(E.Document,'required-brow') and
      not HasIssue(E.Document,'required-mouth') and not HasIssue(E.Document,'required-hair'),
      'actual PSD pixels satisfy all four required roles');
    Check(not HasIssue(E.Document,'source-review') and not E.Document.LayerComplete and not E.Document.Usable,
      'actual PSD has no source confirmation gate and still starts at the layer stage');
    Ids := ''; for var L in E.Document.Layers do Ids := Ids + L.Id + '|' + L.Name + '|' + E.Document.Part(L.Id).Role + '|' + BoolToStr(E.Document.IsReferencePart(L.Id),True) + '|';
    E.Save(TPath.Combine(Directory,'original-readonly.rigm')); Loaded := LoadRigm(E.FileName);
    try
      var ReloadIds := ''; for var L in Loaded.Layers do ReloadIds := ReloadIds + L.Id + '|' + L.Name + '|' + Loaded.Part(L.Id).Role + '|' + BoolToStr(Loaded.IsReferencePart(L.Id),True) + '|';
      Check(Ids = ReloadIds,
        'actual PSD classification and IDs survive RIGM reload');
    finally Loaded.Free; end;
    Check(OriginalHash = THashSHA2.GetHashStringFromFile(OriginalPsd),'actual original PSD SHA256 unchanged'); OriginalTested := True;
  finally E.Free; end;
end;

begin
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)),'Classification'); ForceDirectories(Directory); Checks := TJSONArray.Create;
  try
    try RunObserved; RunConservative; RunOriginal; Writeln(Count.ToString + ' classification checks passed');
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: '+E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report,'passed',Count); AddB(Report,'success',ExitCode = 0);
      Report.AddPair('fixture','Names and hierarchy observed in 東北きりたん_立ち絵.psd, document {1A117963-EDC6-4266-8114-C24203F6D29E}, revision 1; synthetic RGBA.');
      Report.AddPair('originalPsd',OriginalPsd); AddB(Report,'originalTested',OriginalTested); Report.AddPair('originalSha256',OriginalHash);
      Report.AddPair('checks',Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(Directory,'results.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; end;
end.
