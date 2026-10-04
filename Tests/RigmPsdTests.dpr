program RigmPsdTests;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  ArtDocument, ArtPsd, RigmModel, RigmEditor, RigmJson, RigmStorage,
  RigmRenderer, RigmValidation;

var Count: Integer; Checks, LocalFiles: TJSONArray; TestDirectory: string;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Writeln('PASS: ' + Name); Checks.Add(Name);
end;

procedure Command(Editor: TRigmEditor; const Name: string; Args: TJSONObject);
var Reply: TJSONObject;
begin
  try Reply := Editor.Execute(Name, Args); Reply.Free; finally Args.Free; end;
end;

procedure ImportPsd(Editor: TRigmEditor; const Path: string);
var Args: TJSONObject;
begin Args := TJSONObject.Create; Args.AddPair('path', Path); Command(Editor, 'import-psd', Args); end;

function SameBytes(const A, B: TBytes): Boolean;
begin Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A))); end;

function Snapshot(Editor: TRigmEditor): string;
var Manifest, Status: TJSONObject;
begin
  Manifest := RigmManifest(Editor.Document); Status := Editor.Status;
  try Result := Manifest.ToJSON + Status.ToJSON + Editor.SelectedId;
  finally Manifest.Free; Status.Free; end;
end;

procedure RejectAndPreserve(Editor: TRigmEditor; const Path, Name: string);
var Before: string; Rejected: Boolean;
begin
  Before := Snapshot(Editor); Rejected := False;
  try ImportPsd(Editor, Path); except on E: Exception do Rejected := E.Message <> ''; end;
  Check(Rejected and (Before = Snapshot(Editor)), Name);
end;

procedure CreateFixture;
var Doc: TArtDocument; Group, Layer: TArtLayer;
const Names: array[0..3] of string = ('左目', '眉', '口', '前髪');
begin
  Doc := TArtDocument.Create;
  try
    Doc.Width := 32; Doc.Height := 32;
    Group := Doc.AddLayer(alkGroup, '顔グループ', TArtBounds.Create(0, 0, 0, 0));
    Group.BlendKey := 'norm'; Group.Opacity := 180;
    for var I := 0 to 3 do begin
      Layer := Doc.AddLayer(alkImage, Names[I], TArtBounds.Create(3 + I, 4 + I, 11 + I, 12 + I), Group);
      SetLength(Layer.Pixels, 8 * 8 * 4);
      for var P := 0 to 63 do begin
        Layer.Pixels[P * 4] := 40 + I * 40; Layer.Pixels[P * 4 + 1] := 100;
        Layer.Pixels[P * 4 + 2] := 180 - I * 20; Layer.Pixels[P * 4 + 3] := 80 + P;
      end;
      Layer.Opacity := 200 + I * 10;
      if I = 0 then begin
        Layer.HasMask := True; Layer.MaskBounds := TArtBounds.Create(4, 5, 8, 9);
        Layer.MaskDefault := 255; Layer.MaskInvert := True; SetLength(Layer.MaskPixels, 16);
        for var P := 0 to 15 do Layer.MaskPixels[P] := P * 16;
      end;
    end;
    Layer := Doc.AddLayer(alkImage, '非表示の予備', TArtBounds.Create(-2, 1, 6, 9));
    Layer.Visible := False; SetLength(Layer.Pixels, 256);
    WriteNewPsd(Doc, TPath.Combine(TestDirectory, 'separated.psd'), pcRle);
  finally Doc.Free; end;
end;

procedure CheckLayers(Source: TArtDocument; Doc: TRigmDocument; const Name: string);
var Expected: TRigmDocument; A, B: TArtLayer; Good: Boolean;
begin
  Expected := TRigmDocument.Create;
  try
    Expected.SetArt(Source.Clone); Good := Length(Expected.Layers) = Length(Doc.Layers);
    if Good then for var I := 0 to High(Expected.Layers) do begin
      A := Expected.Layers[I]; B := Doc.Layers[I];
      Good := Good and (A.Name = B.Name) and (A.Kind = B.Kind) and (A.BlendKey = B.BlendKey) and
        (A.Bounds.Left = B.Bounds.Left) and (A.Bounds.Top = B.Bounds.Top) and
        (A.Bounds.Right = B.Bounds.Right) and (A.Bounds.Bottom = B.Bounds.Bottom) and
        (A.Visible = B.Visible) and (A.Opacity = B.Opacity) and SameBytes(A.Pixels, B.Pixels) and
        (A.HasMask = B.HasMask) and (A.MaskDefault = B.MaskDefault) and
        (A.MaskDisabled = B.MaskDisabled) and (A.MaskInvert = B.MaskInvert) and
        (A.MaskBounds.Left = B.MaskBounds.Left) and (A.MaskBounds.Top = B.MaskBounds.Top) and
        (A.MaskBounds.Right = B.MaskBounds.Right) and (A.MaskBounds.Bottom = B.MaskBounds.Bottom) and
        SameBytes(A.MaskPixels, B.MaskPixels) and
        (Expected.LayerList(A.Id).IndexOf(A) = Doc.LayerList(B.Id).IndexOf(B)) and
        (Expected.Part(A.Id).X = Doc.Part(B.Id).X) and (Expected.Part(A.Id).Y = Doc.Part(B.Id).Y);
      if Expected.ParentId(A.Id) = '' then Good := Good and (Doc.ParentId(B.Id) = '')
      else Good := Good and (Expected.Art.FindLayer(Expected.ParentId(A.Id)).Name = Doc.Art.FindLayer(Doc.ParentId(B.Id)).Name);
    end;
    Check(Good, Name);
  finally Expected.Free; end;
end;

procedure Run;
var Editor, Empty: TRigmEditor; Source: TArtDocument; Loaded: TRigmDocument;
    Path, Hash, Ids, ReloadIds: string; Bytes, Pixels, BeforePixels: TBytes; W, H: Integer; Args: TJSONObject;
const Roles: array[0..3] of string = ('eye', 'brow', 'mouth', 'hair');
begin
  CreateFixture; Path := TPath.Combine(TestDirectory, 'separated.psd'); Hash := THashSHA2.GetHashStringFromFile(Path);
  Editor := TRigmEditor.Create; Empty := TRigmEditor.Create; Source := ReadPsd(Path);
  try
    Editor.NewDocument('PSDから開始', 32, 32); ImportPsd(Editor, Path);
    CheckLayers(Source, Editor.Document, 'PSD preserves hierarchy names order bounds RGBA masks visibility opacity and centered positions');
    Check((Editor.Document.LastPage = rpLayer) and not Editor.Document.LayerComplete and
      not Editor.Document.BoneComplete and not Editor.Document.MeshComplete and not Editor.Document.Usable and
      not Editor.Document.SourceMatched and not Editor.Document.CanOpen(rpBone), 'PSD starts classification with all preparation gates unreviewed');
    var Issues := ValidateRigm(Editor.Document);
    try
      var MissingRoles := False;
      for var Issue in Issues do if Issue.Code.StartsWith('required-') then MissingRoles := True;
      Check(not MissingRoles and not HasErrors(Issues, rpLayer), 'named PSD infers required roles without a source confirmation gate');
    finally Issues.Free; end;
    Check(not Editor.Document.SourceMatched and not Editor.Document.LayerComplete, 'inference does not invent a source confirmation or stage completion');
    Check(SameBytes(Editor.Document.ReferencePixels, RenderPsdLayers(Source)), 'PSD reference image comes from supported layers');
    var Status := Editor.Status;
    try Check(JB(Status, 'generationSkipped') and (JS(Status, 'psdSourceName') = 'separated.psd'), 'status identifies generation bypass'); finally Status.Free; end;
    BeforePixels := RenderRigm(Editor.Document, nil, 32, W, H); Ids := '';
    for var L in Editor.Document.Layers do Ids := Ids + L.Id + '|';
    Editor.Save(TPath.Combine(TestDirectory, 'roundtrip.rigm')); Loaded := LoadRigm(Editor.FileName);
    try
      CheckLayers(Source, Loaded, 'RIGM reload preserves supported PSD data including normal group blending');
      ReloadIds := ''; for var L in Loaded.Layers do ReloadIds := ReloadIds + L.Id + '|';
      Check((Ids = ReloadIds) and (Loaded.FileId = Editor.Document.FileId), 'imported IDs remain stable after save reload');
      Pixels := RenderRigm(Loaded, nil, 32, W, H);
      Check(SameBytes(BeforePixels, Pixels), 'save reload retains rendered pixels');
      Check((Loaded.PsdSourceName = 'separated.psd') and not Loaded.LayerComplete and not Loaded.Usable and
        (Loaded.LastPage = rpLayer), 'reload retains PSD bypass origin and incomplete stage');
    finally Loaded.Free; end;
    Editor.SelectedId := Editor.Document.Layers[1].Id;
    RejectAndPreserve(Editor, Path, 'existing edited parts file revision selection and undo state are preserved on rejected replacement');
    Empty.NewDocument('取込前', 16, 16); Empty.Save(TPath.Combine(TestDirectory, 'empty.rigm'));
    RejectAndPreserve(Empty, TPath.Combine(TestDirectory, 'missing.psd'), 'missing PSD leaves saved empty document unchanged');
    Bytes := TFile.ReadAllBytes(Path); SetLength(Bytes, 30); TFile.WriteAllBytes(TPath.Combine(TestDirectory, 'truncated.psd'), Bytes);
    RejectAndPreserve(Empty, TPath.Combine(TestDirectory, 'truncated.psd'), 'truncated PSD leaves document unchanged');
    Bytes := TFile.ReadAllBytes(Path); Bytes[23] := 16; TFile.WriteAllBytes(TPath.Combine(TestDirectory, 'depth16.psd'), Bytes);
    RejectAndPreserve(Empty, TPath.Combine(TestDirectory, 'depth16.psd'), 'unsupported 16-bit PSD rejected without state change');
    Bytes := TFile.ReadAllBytes(Path); Bytes[5] := 2; TFile.WriteAllBytes(TPath.Combine(TestDirectory, 'psb.psd'), Bytes);
    RejectAndPreserve(Empty, TPath.Combine(TestDirectory, 'psb.psd'), 'unsupported PSB version rejected without state change');
    Bytes := TFile.ReadAllBytes(Path); var Position := -1;
    for var I := 0 to Length(Bytes) - 8 do
      if TEncoding.ASCII.GetString(Bytes, I, 8) = '8BIMnorm' then begin Position := I + 4; Break; end;
    if Position < 0 then raise Exception.Create('Blend fixture not found');
    Bytes[Position] := Ord('m'); Bytes[Position + 1] := Ord('u'); Bytes[Position + 2] := Ord('l'); Bytes[Position + 3] := Ord(' ');
    TFile.WriteAllBytes(TPath.Combine(TestDirectory, 'multiply.psd'), Bytes);
    RejectAndPreserve(Empty, TPath.Combine(TestDirectory, 'multiply.psd'), 'unsupported visible blending rejected without state change');
    // Insert an image resource section. The parser explicitly marks it as archive-only metadata.
    Bytes := TFile.ReadAllBytes(Path); var Metadata: TBytes; SetLength(Metadata, Length(Bytes) + 2);
    Move(Bytes[0], Metadata[0], 30); Metadata[30] := 0; Metadata[31] := 0; Metadata[32] := 0; Metadata[33] := 2;
    Metadata[34] := 1; Metadata[35] := 2; Move(Bytes[34], Metadata[36], Length(Bytes) - 34);
    TFile.WriteAllBytes(TPath.Combine(TestDirectory, 'metadata.psd'), Metadata); ImportPsd(Empty, TPath.Combine(TestDirectory, 'metadata.psd'));
    Check(Empty.Document.PsdImportNotes <> '', 'archive-only image metadata has an explicit omission notice');
    Empty.Save(TPath.Combine(TestDirectory, 'metadata.rigm')); Loaded := LoadRigm(Empty.FileName);
    try Check(Loaded.PsdImportNotes = Empty.Document.PsdImportNotes, 'metadata notice survives save reload'); finally Loaded.Free; end;
    var RoleIndex := 0;
    for var L in Editor.Document.Layers do if (L.Kind = alkImage) and L.Visible then begin
      Args := TJSONObject.Create; Args.AddPair('id', L.Id); Args.AddPair('role', Roles[RoleIndex]);
      Command(Editor, 'update-layer', Args); Inc(RoleIndex); if RoleIndex = 4 then Break;
    end;
    Command(Editor, 'mark-complete', TJSONObject.Create);
    Check(Editor.Document.LayerComplete and (Editor.Document.LastPage = rpBone) and
      (Editor.Document.Bones.Count > 0) and not Editor.Document.MeshComplete and not Editor.Document.Usable,
      'classification advances to bone stage without source confirmation');
    Editor.Save(Editor.FileName); Loaded := LoadRigm(Editor.FileName);
    try Check(Loaded.LayerComplete and (Loaded.LastPage = rpBone) and not Loaded.Usable, 'reviewed layer stage reopens at bone without marking usable'); finally Loaded.Free; end;
    Check(Hash = THashSHA2.GetHashStringFromFile(Path), 'source PSD is unchanged');
  finally Source.Free; Empty.Free; Editor.Free; end;
end;

procedure RunLocalFile(const Path: string);
var Editor: TRigmEditor; Source: TArtDocument; Entry: TJSONObject; Hash, Before: string;
begin
  if not FileExists(Path) then Exit;
  Entry := TJSONObject.Create; LocalFiles.AddElement(Entry); Entry.AddPair('path', Path);
  Hash := THashSHA2.GetHashStringFromFile(Path); Entry.AddPair('sha256', Hash);
  Editor := TRigmEditor.Create; Source := nil;
  try
    Before := Snapshot(Editor);
    try
      ImportPsd(Editor, Path); Source := ReadPsd(Path);
      CheckLayers(Source, Editor.Document, 'local PSD import: ' + ExtractFileName(Path));
      var Output := TPath.Combine(TestDirectory, ExtractFileName(Path) + '.rigm'); Editor.Save(Output);
      var Loaded := LoadRigm(Output);
      try CheckLayers(Source, Loaded, 'local PSD save reload: ' + ExtractFileName(Path)); finally Loaded.Free; end;
      AddB(Entry, 'imported', True); AddN(Entry, 'parts', Editor.Document.Parts.Count);
    except on E: ERigm do begin
      AddB(Entry, 'imported', False); Entry.AddPair('reason', E.Message);
      Check(Before = Snapshot(Editor), 'unsupported local PSD leaves state unchanged: ' + ExtractFileName(Path));
    end; end;
    Check(Hash = THashSHA2.GetHashStringFromFile(Path), 'local PSD unchanged: ' + ExtractFileName(Path));
  finally Source.Free; Editor.Free; end;
end;

begin
  TestDirectory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'PsdWorkflow'); ForceDirectories(TestDirectory);
  Checks := TJSONArray.Create; LocalFiles := TJSONArray.Create;
  try
    try
      Run;
      for var Path in TArray<string>.Create('D:\DelphiProg\AIArtToPSD\Sample\LayerSplitTrial\character_layers_trial_v2.psd',
        'D:\DelphiProg\AIArtToPSD\Tests\output\aiueo_parts.psd',
        'D:\DelphiProg\AIArtToPSD\Tests\output\nested_rle.psd',
        'D:\DelphiProg\AIArtToPSD\Tests\output\mask_rle.psd',
        'D:\DelphiProg\AIArtToPSD\Tests\output\edit_blocked_source.psd') do RunLocalFile(Path);
      Writeln(Count.ToString + ' PSD checks passed');
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report, 'passed', Count); AddB(Report, 'success', ExitCode = 0);
      Report.AddPair('checks', Checks); Checks := nil; Report.AddPair('localFiles', LocalFiles); LocalFiles := nil;
      TFile.WriteAllText(TPath.Combine(TestDirectory, 'results.json'), Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; LocalFiles.Free; end;
end.
