unit RigmEditor;

interface
uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  RigmModel, RigmValidation, RigmMovieSession;

type
  TRigmWorkspaceCommand = function(const Command: string; Args: TJSONObject): TJSONObject of object;
  TRigmMovieProvider = function: TRigmMovieSession of object;
  TRigmEditor = class
  private
    FDocument: TRigmDocument;
    FMovie: TRigmMovieSession;
    FFileName: string;
    FModified: Boolean;
    FUndo, FRedo: TObjectList<TRigmDocument>;
    FOnChanged, FOnPageChanged: TNotifyEvent;
    FOnMovieOpen: TNotifyEvent;
    FOnWorkspaceCommand: TRigmWorkspaceCommand;
    FOnGetMovie: TRigmMovieProvider;
    FPublishedPage: TRigmPage;
    procedure Notify;
    function GetMovie: TRigmMovieSession;
    procedure Commit(Candidate: TRigmDocument; InvalidatedPage: TRigmPage; Invalidate: Boolean);
    function ApplyCommand(D: TRigmDocument; const Command: string; Args: TJSONObject): string;
    procedure Complete(D: TRigmDocument);
  public
    Pose: TRigmPose;
    AiLog, FixRequests: TStringList;
    SelectedId: string;
    constructor Create;
    destructor Destroy; override;
    procedure NewDocument(const Name: string; Width, Height: Integer);
    procedure Open(const FileName: string);
    procedure Save(const FileName: string);
    procedure SwitchPage(Page: TRigmPage);
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function Status: TJSONObject;
    function Execute(const Command: string; Args: TJSONObject): TJSONObject;
    function IsAllowed(Page: TRigmPage; const Command: string): Boolean;
    property Document: TRigmDocument read FDocument;
    property FileName: string read FFileName;
    property Modified: Boolean read FModified;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnPageChanged: TNotifyEvent read FOnPageChanged write FOnPageChanged;
    property Movie: TRigmMovieSession read GetMovie;
    function MovieBusy: Boolean;
    procedure PollMovie;
    procedure CancelMovie;
    procedure RequestMovieUI;
    property OnMovieOpen: TNotifyEvent read FOnMovieOpen write FOnMovieOpen;
    property OnWorkspaceCommand: TRigmWorkspaceCommand read FOnWorkspaceCommand write FOnWorkspaceCommand;
    property OnGetMovie: TRigmMovieProvider read FOnGetMovie write FOnGetMovie;
  end;

implementation
uses System.Math, System.Types, System.IOUtils, System.Hash,
  ArtDocument, ArtPng, ArtPsd, RigmJson, RigmStorage, RigmRenderer, RigmClassification,
  RigmMeshEditing, RigmApiSchema;

constructor TRigmEditor.Create;
begin
  inherited; FDocument := TRigmDocument.Create;
  FUndo := TObjectList<TRigmDocument>.Create(True); FRedo := TObjectList<TRigmDocument>.Create(True);
  Pose := TRigmPose.Create; AiLog := TStringList.Create; FixRequests := TStringList.Create;
end;

destructor TRigmEditor.Destroy;
begin
  FMovie.Free; FixRequests.Free; AiLog.Free; Pose.Free; FRedo.Free; FUndo.Free; FDocument.Free; inherited;
end;

function TRigmEditor.GetMovie: TRigmMovieSession;
begin if Assigned(FOnGetMovie) then Exit(FOnGetMovie()); if FMovie=nil then FMovie := TRigmMovieSession.Create; Result := FMovie; end;
function TRigmEditor.MovieBusy: Boolean;
begin if Assigned(FOnGetMovie) then Exit(GetMovie.Busy); Result := (FMovie<>nil) and FMovie.Busy; end;
procedure TRigmEditor.PollMovie;
begin if Assigned(FOnGetMovie) then GetMovie.Poll else if FMovie<>nil then FMovie.Poll; end;
procedure TRigmEditor.CancelMovie;
var A,R: TJSONObject;
begin if (FMovie=nil) and not Assigned(FOnGetMovie) then Exit; A := TJSONObject.Create; try R := GetMovie.Execute('job-cancel',A); R.Free; finally A.Free; end; end;
procedure TRigmEditor.RequestMovieUI;
begin if not Assigned(FOnMovieOpen) then raise ERigm.Create('制作画面のないホストです。preview/exportジョブを使用してください。'); FOnMovieOpen(Self); end;

procedure TRigmEditor.Notify;
begin
  if FPublishedPage <> FDocument.LastPage then begin
    FPublishedPage := FDocument.LastPage; if Assigned(FOnPageChanged) then FOnPageChanged(Self);
  end;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TRigmEditor.NewDocument(const Name: string; Width, Height: Integer);
var Candidate: TRigmDocument;
begin
  Candidate := TRigmDocument.Create;
  try
    Candidate.Name := Name; Candidate.Art.Width := Width; Candidate.Art.Height := Height; Candidate.ValidateStructure;
  except Candidate.Free; raise; end;
  FDocument.Free; FDocument := Candidate; FFileName := ''; FModified := True;
  FUndo.Clear; FRedo.Clear; Pose.Reset; SelectedId := ''; FixRequests.Clear; Notify;
end;

procedure TRigmEditor.Open(const FileName: string);
var Loaded, Candidate: TRigmDocument; Classified: Integer; Path: string; RigUpgraded: Boolean; Issues: TRigmIssues;
begin
  Path := ExpandFileName(FileName); Loaded := LoadRigm(Path); Candidate := nil;
  try
    Candidate := Loaded.Clone;
    Classified := ClassifyUnclassifiedParts(Candidate, True);
    if Classified > 0 then Candidate.Changed(rpLayer);
    RigUpgraded := False; Issues := ValidateRigm(Candidate);
    try if not HasErrors(Issues,rpBone) then RigUpgraded := Candidate.UpgradeUpperBodyRig;
    finally Issues.Free; end;
    if RigUpgraded then Candidate.Art.Changed;
    Candidate.ValidateStructure;
    // Finish all inference before replacing the currently edited document.
    FDocument.Free; FDocument := Candidate; Candidate := nil;
    FFileName := Path; FModified := (Classified > 0) or RigUpgraded;
    FUndo.Clear; FRedo.Clear;
    if FModified then begin FUndo.Add(Loaded); Loaded := nil; end;
    Pose.Reset; SelectedId := ''; FixRequests.Clear;
    AiLog.Add('読み込み: ' + FFileName);
    if Classified > 0 then AiLog.Add(Format(
      '読込時の自動再判定: %dパーツを更新。変更は未保存です。自動検証で問題がなければ工程を完了できます。', [Classified]));
    if RigUpgraded then AiLog.Add('腰支点の上半身構成へ更新しました。既存ID・位置・メッシュを保持。未保存でUndo可能です。');
    if not RigUpgraded and not FDocument.HasUpperBodyRig and (FDocument.Bones.Count > 0) then
      AiLog.Add('旧ボーン構成を保持しました。ロック・手動体メッシュ・独自階層やウェイトは自動移行しません。');
    Notify;
  finally Candidate.Free; Loaded.Free; end;
end;

procedure TRigmEditor.Save(const FileName: string);
begin
  SaveRigm(FDocument, ExpandFileName(FileName)); FFileName := ExpandFileName(FileName);
  FModified := False; AiLog.Add('保存: ' + FFileName); Notify;
end;

procedure TRigmEditor.SwitchPage(Page: TRigmPage);
begin
  if not FDocument.CanOpen(Page) then raise ERigm.Create('前工程を完了してからこのページへ進んでください。');
  if FDocument.LastPage = Page then Exit;
  FDocument.LastPage := Page; FDocument.Art.Changed; FModified := True; Pose.Reset; SelectedId := ''; Notify;
end;

procedure TRigmEditor.Commit(Candidate: TRigmDocument; InvalidatedPage: TRigmPage; Invalidate: Boolean);
begin
  Candidate.ValidateStructure;
  Candidate.Art.Revision := FDocument.Art.Revision;
  if Invalidate then Candidate.Changed(InvalidatedPage) else Candidate.Art.Changed;
  FUndo.Add(FDocument); FRedo.Clear;
  while FUndo.Count > 20 do FUndo.Delete(0);
  FDocument := Candidate; FModified := True; Pose.Reset;
end;

function TRigmEditor.CanUndo: Boolean;
begin Result := FUndo.Count > 0; end;
function TRigmEditor.CanRedo: Boolean;
begin Result := FRedo.Count > 0; end;

procedure TRigmEditor.Undo;
var Revision: UInt64;
begin
  if not CanUndo then raise ERigm.Create('元に戻せる操作がありません。');
  Revision := FDocument.Art.Revision; FRedo.Add(FDocument);
  FDocument := FUndo.Extract(FUndo.Last); FDocument.Art.Revision := Revision; FDocument.Art.Changed;
  FModified := True; Pose.Reset; Notify;
end;

procedure TRigmEditor.Redo;
var Revision: UInt64;
begin
  if not CanRedo then raise ERigm.Create('やり直せる操作がありません。');
  Revision := FDocument.Art.Revision; FUndo.Add(FDocument);
  FDocument := FRedo.Extract(FRedo.Last); FDocument.Art.Revision := Revision; FDocument.Art.Changed;
  FModified := True; Pose.Reset; Notify;
end;

function TRigmEditor.Status: TJSONObject;
var Pages, Requests: TJSONArray; Flags: TJSONObject; Page: TRigmPage;
begin
  Result := TJSONObject.Create; Result.AddPair('application', 'RIGM Maker');
  Result.AddPair('documentId', FDocument.FileId); Result.AddPair('revision', FDocument.Art.Revision.ToString);
  Result.AddPair('name', FDocument.Name); Result.AddPair('fileName', FFileName); Result.AddPair('page', PageName(FDocument.LastPage));
  Result.AddPair('psdSourceName', FDocument.PsdSourceName);
  Result.AddPair('psdImportNotes', FDocument.PsdImportNotes);
  AddB(Result, 'generationSkipped', FDocument.PsdSourceName <> '');
  AddB(Result, 'modified', FModified); AddB(Result, 'canUndo', CanUndo); AddB(Result, 'canRedo', CanRedo);
  Result.AddPair('selectedId', SelectedId);
  AddN(Result, 'width', FDocument.Art.Width); AddN(Result, 'height', FDocument.Art.Height);
  Result.AddPair('coordinates', 'canvas-center-x-right-y-down');
  AddN(Result, 'partCount', FDocument.Parts.Count); AddN(Result, 'boneCount', FDocument.Bones.Count); AddN(Result, 'meshCount', FDocument.Meshes.Count);
  Flags := TJSONObject.Create; Result.AddPair('stages', Flags);
  AddB(Flags, 'layer', FDocument.LayerComplete); AddB(Flags, 'bone', FDocument.BoneComplete);
  AddB(Flags, 'mesh', FDocument.MeshComplete); AddB(Flags, 'usable', FDocument.Usable);
  Pages := TJSONArray.Create; Result.AddPair('availablePages', Pages);
  for Page := Low(TRigmPage) to High(TRigmPage) do if FDocument.CanOpen(Page) then Pages.Add(PageName(Page));
  Requests := TJSONArray.Create; Result.AddPair('fixRequests', Requests);
  for var Request in FixRequests do Requests.Add(Request);
end;

function TRigmEditor.IsAllowed(Page: TRigmPage; const Command: string): Boolean;
begin
  Result := (Command = 'status') or (Command = 'schema') or (Command = 'document') or (Command = 'validate') or
    (Command = 'mark-complete') or (Command = 'autofix') or (Command = 'ignore-issue') or
    (Command = 'request-fix') or (Command = 'export') or (Command = 'undo') or (Command = 'redo') or
    (Command = 'batch') or (Command = 'select-object');
  if Result then Exit;
  case Page of
    rpLayer: Result := (Command = 'import-png') or (Command = 'replace-png') or (Command = 'import-psd') or
      (Command = 'add-group') or (Command = 'update-layer') or (Command = 'move-layer') or
      (Command = 'set-parent') or (Command = 'delete-layer') or (Command = 'verify-source') or
      (Command = 'classify-layers') or (Command = 'import');
    rpBone: Result := (Command = 'add-bone') or (Command = 'update-bone') or (Command = 'hide-bone') or
      (Command = 'restore-bone') or (Command = 'reset-bone') or (Command = 'bind-part');
    rpMesh: Result := IsMeshCommand(Command) or (Command = 'import');
    rpPreview: Result := (Command = 'update-parameter');
  end;
end;

procedure TRigmEditor.Complete(D: TRigmDocument);
var Issues: TRigmIssues;
begin
  if not D.CanOpen(D.LastPage) then raise ERigm.Create('前工程が未完了です。');
  Issues := ValidateRigm(D, Pose);
  try
    for var Issue in Issues do if Issue.Error and (Issue.Page <= D.LastPage) then raise ERigm.Create(Issue.Message);
    case D.LastPage of
      rpLayer: begin D.LayerComplete := True; D.SeedBones; D.LastPage := rpBone; end;
      rpBone: begin D.BoneComplete := True; D.LastPage := rpMesh; end;
      rpMesh: begin D.MeshComplete := True; D.LastPage := rpPreview; end;
      rpPreview: D.Usable := True;
    end;
  finally Issues.Free; end;
end;

function TRigmEditor.ApplyCommand(D: TRigmDocument; const Command: string; Args: TJSONObject): string;
var L, Parent: TArtLayer; P: TRigmPart; B: TRigmBone;
    Image: TArtPngData; Psd: TArtDocument; Id, ParentId, Path: string;
    Index, I: Integer; List: TList<TArtLayer>;
  function NeedLayer: TArtLayer;
  begin
    Result := D.Art.FindLayer(JS(Args, 'id'));
    if Result = nil then raise ERigm.Create('対象パーツがありません。');
    if D.Part(Result.Id).Locked and not ((Args.GetValue('locked') <> nil) and not JB(Args, 'locked')) then
      raise ERigm.Create('パーツはロックされています。');
  end;
  function NeedBone: TRigmBone;
  begin
    Result := D.Bone(JS(Args, 'id')); if Result = nil then raise ERigm.Create('対象ボーンがありません。');
    if Result.Locked and not ((Args.GetValue('locked') <> nil) and not JB(Args, 'locked')) then raise ERigm.Create('ボーンはロックされています。');
  end;
  procedure DeleteLayer(Layer: TArtLayer);
  begin
    while Layer.Children.Count > 0 do DeleteLayer(Layer.Children.Last);
    D.Parts.Remove(Layer.Id); D.Art.RemoveNewLayer(Layer);
  end;
begin
  Result := ''; Id := JS(Args, 'id');
  if (Command = 'import-png') or (Command = 'replace-png') then begin
    Path := JS(Args, 'path'); Image := ReadPng(Path);
    if Command = 'replace-png' then begin
      L := NeedLayer; if L.Kind <> alkImage then raise ERigm.Create('画像パーツを選択してください。');
      L.Bounds := TArtBounds.Create(L.Bounds.Left, L.Bounds.Top, L.Bounds.Left + Image.Width, L.Bounds.Top + Image.Height);
      L.Pixels := Image.Pixels; L.HasMask := False; L.MaskPixels := nil;
    end else begin
      ParentId := JS(Args, 'parentId'); Parent := D.Art.FindLayer(ParentId);
      if (ParentId <> '') and ((Parent = nil) or (Parent.Kind <> alkGroup)) then raise ERigm.Create('親グループがありません。');
      L := D.Art.AddLayer(alkImage, JS(Args, 'name', ChangeFileExt(ExtractFileName(Path), '')),
        TArtBounds.Create(0, 0, Image.Width, Image.Height), Parent); L.Pixels := Image.Pixels;
      if Parent = nil then List := D.Art.Roots else List := Parent.Children;
      List.Remove(L); List.Insert(0, L); D.SyncParts;
      P := D.Part(L.Id); P.X := JN(Args, 'x', 0); P.Y := JN(Args, 'y', 0); P.Role := JS(Args, 'role', 'other');
      P.RoleManual := Args.GetValue('role') <> nil;
      if (D.Parts.Count = 1) and (Image.Width = D.Art.Width) and (Image.Height = D.Art.Height) then D.ReferencePixels := Image.Pixels;
    end;
    Result := L.Id;
  end else if Command = 'import-psd' then begin
    if (D.Parts.Count > 0) or (D.Bones.Count > 0) or (D.Meshes.Count > 0) then
      raise ERigm.Create('編集中のデータは保持します。分解済みPSDは別の編集画面で開いてください。');
    Path := JS(Args, 'path');
    if not SameText(ExtractFileExt(Path), '.psd') then raise ERigm.Create('分解済みPSD（.psd）を選択してください。');
    Psd := nil;
    try
      try
        Psd := ReadPsd(Path);
        // Only these non-rendering archive records may be omitted, with a visible notice.
        for var Reason in Psd.Unsupported do
          if (Reason <> 'Image resources retained in source archive') and
            (Reason <> 'Additional info retained in archive: lclr') and
            (Reason <> 'Additional info retained in archive: lyvr') then
            raise EArtFormat.Create(Reason);
        D.ReferencePixels := RenderPsdLayers(Psd);
      except on E: EArtFormat do raise ERigm.Create('このPSDは編集用に取り込めません: ' + E.Message); end;
      D.PsdImportNotes := '';
      if Psd.Unsupported.Count > 0 then D.PsdImportNotes :=
        '画像リソース・色ラベル・レイヤー版などの編集メタデータはRIGMへ保存しません。';
      if JS(Args, 'name') <> '' then D.Name := JS(Args, 'name');
      D.PsdSourceName := ExtractFileName(Path);
      Psd.Unsupported.Clear;
      Psd.SourceBytes := nil;
      var Imported := Psd; Psd := nil; D.SetArt(Imported);
      ClassifyUnclassifiedParts(D);
      var Images := 0;
      for L in D.Layers do if L.Kind = alkImage then Inc(Images);
      if Images = 0 then raise ERigm.Create('画像レイヤーのある分解済みPSDを選択してください。');
      D.IgnoredWarnings.Clear; D.LayerComplete := False; D.BoneComplete := False;
      D.MeshComplete := False; D.Usable := False; D.SourceMatched := False; D.LastPage := rpLayer;
    finally Psd.Free; end;
  end else if Command = 'classify-layers' then begin
    ClassifyUnclassifiedParts(D);
  end else if Command = 'add-group' then begin
    Parent := D.Art.FindLayer(JS(Args, 'parentId'));
    L := D.Art.AddLayer(alkGroup, JS(Args, 'name', 'グループ'), TArtBounds.Create(0, 0, 0, 0), Parent);
    D.SyncParts; Result := L.Id;
  end else if Command = 'update-layer' then begin
    L := NeedLayer; P := D.Part(L.Id);
    L.Name := JS(Args, 'name', L.Name); L.Visible := JB(Args, 'visible', L.Visible);
    Index := JI(Args, 'opacity', L.Opacity); if (Index < 0) or (Index > 255) then raise ERigm.Create('不透明度は0～255です。'); L.Opacity := Index;
      P.Role := JS(Args, 'role', P.Role); P.PairId := JS(Args, 'pairId', P.PairId); P.BoneId := JS(Args, 'boneId', P.BoneId);
      if Args.GetValue('role') <> nil then P.RoleManual := True;
      if P.Role = 'reference' then P.ReferenceOnly := True;
    P.Tags := JS(Args, 'tags', P.Tags); P.X := JN(Args, 'x', P.X); P.Y := JN(Args, 'y', P.Y);
    P.Rotation := JN(Args, 'rotation', P.Rotation); P.ScaleX := JN(Args, 'scaleX', P.ScaleX); P.ScaleY := JN(Args, 'scaleY', P.ScaleY);
    if (Args.GetValue('parentId') <> nil) and (JS(Args, 'parentId') <> D.ParentId(L.Id)) then
      D.ReparentLayer(L.Id, JS(Args, 'parentId'), JI(Args, 'index'));
    P.Locked := JB(Args, 'locked', P.Locked); Result := L.Id;
  end else if Command = 'move-layer' then begin
    L := NeedLayer; List := D.LayerList(Id); Index := EnsureRange(List.IndexOf(L) + JI(Args, 'delta'), 0, List.Count - 1);
    List.Remove(L); List.Insert(Index, L); Result := Id;
  end else if Command = 'set-parent' then begin
    L := NeedLayer; D.ReparentLayer(L.Id, JS(Args, 'parentId'), JI(Args, 'index')); Result := L.Id;
  end else if Command = 'delete-layer' then begin L := NeedLayer; DeleteLayer(L);
  end else if Command = 'verify-source' then D.SourceMatched := JB(Args, 'confirmed')
  else if Command = 'add-bone' then begin B := D.AddBone(JS(Args, 'parentId'), JS(Args, 'name', '新しいボーン')); Result := B.Id;
  end else if Command = 'update-bone' then begin
    B := NeedBone; B.Name := JS(Args, 'name', B.Name); B.ParentId := JS(Args, 'parentId', B.ParentId);
    B.PairId := JS(Args, 'pairId', B.PairId); B.MinAngle := JN(Args, 'minAngle', B.MinAngle); B.MaxAngle := JN(Args, 'maxAngle', B.MaxAngle);
    if (Args.GetValue('locked') <> nil) and not JB(Args, 'locked') then B.Locked := False;
    D.MoveBone(B.Id, JN(Args, 'x', B.X), JN(Args, 'y', B.Y), JB(Args, 'paired'));
    B.Locked := JB(Args, 'locked', B.Locked); Result := B.Id;
  end else if Command = 'hide-bone' then begin D.HideBone(Id, JB(Args, 'paired')); Result := Id;
  end else if Command = 'restore-bone' then begin D.RestoreChildren(Id, JB(Args, 'paired')); Result := Id;
  end else if Command = 'reset-bone' then begin
    B := NeedBone; D.MoveBone(Id, B.InitialX, B.InitialY, JB(Args, 'paired')); Result := Id;
  end else if Command = 'bind-part' then begin
    L := NeedLayer; D.Part(L.Id).BoneId := JS(Args, 'boneId'); Result := L.Id;
  end else if IsMeshCommand(Command) then Result := ApplyMeshCommand(D, Command, Args)
  else if Command = 'autofix' then AutoFixRigm(D, JS(Args, 'issueId'))
  else if Command = 'ignore-issue' then begin
    var Issues := ValidateRigm(D);
    try
      var Found := False;
      for var Issue in Issues do if Issue.Id = JS(Args, 'issueId') then begin
        if Issue.Error then raise ERigm.Create('完了を妨げる異常は無視できません。'); Found := True;
        if D.IgnoredWarnings.IndexOf(Issue.Id) < 0 then D.IgnoredWarnings.Add(Issue.Id);
      end;
      if not Found then raise ERigm.Create('対象の警告がありません。');
    finally Issues.Free; end;
  end else if Command = 'update-parameter' then begin
    var Found := False;
    for I := 0 to High(D.Parameters) do if D.Parameters[I].Id = Id then begin
      D.Parameters[I].BoneId := JS(Args, 'boneId', D.Parameters[I].BoneId);
      D.Parameters[I].Minimum := JN(Args, 'minimum', D.Parameters[I].Minimum);
      D.Parameters[I].Maximum := JN(Args, 'maximum', D.Parameters[I].Maximum);
      D.Parameters[I].Initial := JN(Args, 'initial', D.Parameters[I].Initial); Found := True;
    end;
    if not Found then raise ERigm.Create('パラメータがありません。');
  end else raise ERigm.Create('未対応の命令: ' + Command);
end;

function TRigmEditor.Execute(const Command: string; Args: TJSONObject): TJSONObject;
var Candidate: TRigmDocument; Page: TRigmPage; Invalidate: Boolean; Issues: TRigmIssues;
    ArrayValue: TJSONArray; Selected, Directory, Path: string; Manifest, Operation: TJSONObject;
    Item: TJSONValue; Revision: UInt64;
begin
  if Command = 'status' then Exit(Status);
  if Command = 'schema' then Exit(RigmCommandSchema(FDocument.LastPage));
  if Command = 'document' then begin
    Manifest := RigmManifest(FDocument);
    if JS(Args, 'section') = '' then Exit(Manifest);
    try
      var Section := JS(Args, 'section');
      if Section = 'summary' then begin
        for var Key in ['parts', 'bones', 'meshes', 'parameters', 'ignoredWarnings'] do Manifest.RemovePair(Key).Free;
        AddN(Manifest, 'partCount', FDocument.Parts.Count); AddN(Manifest, 'boneCount', FDocument.Bones.Count);
        AddN(Manifest, 'meshCount', FDocument.Meshes.Count); AddN(Manifest, 'parameterCount', Length(FDocument.Parameters));
        Result := TJSONObject(Manifest.Clone); Exit;
      end;
      if (Section = 'mesh-vertices') or (Section = 'mesh-triangles') then begin
        var Found: TJSONObject := nil;
        for var Value in JA(Manifest, 'meshes') do if JS(TJSONObject(Value), 'id') = JS(Args, 'id') then Found := TJSONObject(Value);
        if Found = nil then raise ERigm.Create('対象メッシュがありません。');
        if Section = 'mesh-vertices' then ArrayValue := JA(Found, 'vertices') else ArrayValue := JA(Found, 'triangles');
      end else if (Section = 'parts') or (Section = 'bones') or (Section = 'meshes') or (Section = 'parameters') then ArrayValue := JA(Manifest, Section)
      else raise ERigm.Create('不明な取得対象です。');
      var Offset := JI(Args, 'offset'); var Limit := JI(Args, 'limit', 20);
      if (Offset < 0) or (Limit < 1) or (Limit > 50) then raise ERigm.Create('取得範囲はoffset>=0、limit=1～50です。');
      var FilterId := JS(Args, 'id'); var Total := 0;
      for var Value in ArrayValue do if Section.StartsWith('mesh-') or (FilterId = '') or
        (JS(TJSONObject(Value), 'id') = FilterId) then Inc(Total);
      if (FilterId <> '') and not Section.StartsWith('mesh-') and (Total = 0) then raise ERigm.Create('取得対象のIDがありません。');
      Result := TJSONObject.Create; var Items := TJSONArray.Create; Result.AddPair('items', Items); AddN(Result, 'total', Total);
      var Position := 0;
      for var I := 0 to ArrayValue.Count - 1 do begin
        if not Section.StartsWith('mesh-') and (FilterId <> '') and (JS(TJSONObject(ArrayValue[I]), 'id') <> FilterId) then Continue;
        Inc(Position);
        if (Position <= Offset) or (Position - Offset > Limit) then Continue;
        if (Section = 'meshes') then begin
          var Header := TJSONObject(ArrayValue[I].Clone); Header.RemovePair('vertices').Free; Header.RemovePair('triangles').Free; Items.AddElement(Header);
        end else Items.AddElement(TJSONValue(ArrayValue[I].Clone));
      end;
      Result.AddPair('documentId', FDocument.FileId); Result.AddPair('revision', FDocument.Art.Revision.ToString);
    finally Manifest.Free; end;
    Exit;
  end;
  if Command = 'validate' then begin
    Result := TJSONObject.Create; ArrayValue := TJSONArray.Create; Result.AddPair('issues', ArrayValue);
    Issues := ValidateRigm(FDocument, Pose);
    try
      try
      var Through := ParsePage(JS(Args, 'throughPage', 'preview'));
      var Offset := JI(Args, 'offset'); var Limit := JI(Args, 'limit', 50);
      if (Offset < 0) or (Limit < 1) or (Limit > 50) then raise ERigm.Create('取得範囲はoffset>=0、limit=1～50です。');
      var Total := 0; var Errors := 0;
      for var Issue in Issues do if (Issue.Page <= Through) and
        ((JS(Args, 'targetId') = '') or (JS(Args, 'targetId') = Issue.TargetId)) and
        (not JB(Args, 'errorsOnly') or Issue.Error) then begin
        if Issue.Error then Inc(Errors);
        if (Total >= Offset) and (Total - Offset < Limit) then ArrayValue.AddElement(Issue.Json);
        Inc(Total);
      end;
      AddN(Result, 'total', Total); AddN(Result, 'errorCount', Errors);
      AddB(Result, 'throughPageReady', not HasErrors(Issues, Through));
      AddB(Result, 'currentStageReady', FDocument.CanOpen(FDocument.LastPage) and not HasErrors(Issues, FDocument.LastPage));
      Result.AddPair('documentId', FDocument.FileId); Result.AddPair('revision', FDocument.Art.Revision.ToString);
      except Result.Free; raise; end;
    finally Issues.Free; end; Exit;
  end;
  if Command = 'save' then begin
    Path := JS(Args, 'path', FFileName); if Path = '' then raise ERigm.Create('保存先を指定してください。');
    if FileExists(Path) and not SameText(ExpandFileName(Path), FFileName) then raise ERigm.Create('別の既存ファイルの上書きは画面で確認してください。');
    Save(Path); Exit(Status);
  end;
  if Command = 'switch-page' then begin
    var TargetPage := ParsePage(JS(Args, 'page'));
    if not FDocument.CanOpen(TargetPage) and JB(Args, 'completeCurrent') then begin
      Candidate := FDocument.Clone;
      try
        while (Candidate.LastPage < TargetPage) and not Candidate.CanOpen(TargetPage) do Complete(Candidate);
        if not Candidate.CanOpen(TargetPage) then raise ERigm.Create('必要な前工程を完了できません。');
        Candidate.LastPage := TargetPage; Commit(Candidate, FDocument.LastPage, False); Candidate := nil;
        SelectedId := ''; Notify;
      finally Candidate.Free; end;
    end else SwitchPage(TargetPage);
    Exit(Status);
  end;
  if Command = 'select-object' then begin
    var Id := JS(Args, 'id'); var Valid := False;
    case FDocument.LastPage of
      rpLayer: Valid := FDocument.Art.FindLayer(Id) <> nil;
      rpBone: Valid := FDocument.Bone(Id) <> nil;
      rpMesh: Valid := FDocument.Mesh(Id) <> nil;
      rpPreview: Valid := (FDocument.Art.FindLayer(Id) <> nil) or (FDocument.Bone(Id) <> nil) or (FDocument.Mesh(Id) <> nil);
    end;
    if not Valid then raise ERigm.Create('現在工程の対象IDを指定してください。');
    SelectedId := Id; Notify; Exit(Status);
  end;
  if Command = 'undo' then begin Undo; Exit(Status); end;
  if Command = 'redo' then begin Redo; Exit(Status); end;
  if not IsAllowed(FDocument.LastPage, Command) then raise ERigm.Create('このページでは実行できない命令です: ' + Command);
  if Command = 'classify-layers' then begin
    Candidate := FDocument.Clone;
    try
      var Classified := ClassifyUnclassifiedParts(Candidate);
      if Classified > 0 then begin Commit(Candidate, rpLayer, True); Candidate := nil; end;
      AiLog.Add(Format('未分類を再判定: %dパーツを更新。手動種別は保持し、不明な名称は未分類のままです。', [Classified]));
      Notify; Result := Status; AddN(Result, 'classifiedCount', Classified); Exit;
    finally Candidate.Free; end;
  end;
  if Command = 'request-fix' then begin
    Issues := ValidateRigm(FDocument, Pose);
    try
      var Found := False;
      for var Issue in Issues do if Issue.Id = JS(Args, 'issueId') then begin
        var IssueJson := Issue.Json;
        try FixRequests.Add(IssueJson.ToJSON); finally IssueJson.Free; end;
        AiLog.Add('AI修正依頼: ' + Issue.Message); Found := True;
      end;
      if not Found then raise ERigm.Create('対象の異常がありません。');
    finally Issues.Free; end;
    Notify; Exit(Status);
  end;
  if Command = 'export' then begin
    Directory := TPath.Combine(JS(Args, 'root', TPath.Combine(ExtractFilePath(ParamStr(0)), 'Exchange')), NewRigmId);
    ForceDirectories(Directory); SaveRigm(FDocument, TPath.Combine(Directory, 'snapshot.rigm'));
    Manifest := RigmManifest(FDocument);
    try
      Manifest.AddPair('jobId', ExtractFileName(Directory));
      var Assets := TJSONArray.Create; Manifest.AddPair('exportedAssets', Assets); var AssetIndex := 0;
      if JB(Args, 'images', FDocument.LastPage = rpLayer) then for var L in FDocument.Layers do if L.Kind = alkImage then begin
        var AssetName := Format('part-%.6d.png', [AssetIndex]); Inc(AssetIndex);
        Path := TPath.Combine(Directory, AssetName);
        WriteRgbaPng(Path, L.Bounds.Width, L.Bounds.Height, L.Pixels);
        var Asset := TJSONObject.Create; Assets.AddElement(Asset); Asset.AddPair('partId', L.Id);
        Asset.AddPair('file', AssetName); Asset.AddPair('sha256', THashSHA2.GetHashStringFromFile(Path));
      end;
      TFile.WriteAllText(TPath.Combine(Directory, 'manifest.json'), Manifest.ToJSON, TEncoding.UTF8);
    finally Manifest.Free; end;
    Result := TJSONObject.Create; Result.AddPair('directory', Directory); Exit;
  end;
  Candidate := FDocument.Clone; Page := FDocument.LastPage; Invalidate := True;
  try
    if Command = 'mark-complete' then begin Complete(Candidate); Invalidate := False; Selected := '';
    end else if Command = 'batch' then begin
      Selected := '';
      if JA(Args, 'operations').Count > 2000 then raise ERigm.Create('一括操作が多すぎます。');
      for Item in JA(Args, 'operations') do begin
        if not (Item is TJSONObject) then raise ERigm.Create('操作の形式が不正です。'); Operation := TJSONObject(Item);
        var OpName := JS(Operation, 'command');
        if not IsAllowed(Page, OpName) or (OpName = 'batch') then raise ERigm.Create('このページでは実行できない一括操作です。');
        Selected := ApplyCommand(Candidate, OpName, JO(Operation, 'args'));
      end;
    end else if Command = 'import' then begin
      Path := JS(Args, 'path');
      var ImportStream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
      try if ImportStream.Size > 8 * 1024 * 1024 then raise ERigm.Create('交換結果が大きすぎます。');
      finally ImportStream.Free; end;
      Manifest := ParseObject(TFile.ReadAllText(Path, TEncoding.UTF8));
      try
        if (JS(Manifest, 'documentId') <> FDocument.FileId) or not TryStrToUInt64(JS(Manifest, 'revision'), Revision) or
          (Revision <> FDocument.Art.Revision) then raise ERigm.Create('生成結果の文書ID・版が現在の文書と一致しません。');
        Selected := '';
        if JA(Manifest, 'operations').Count > 2000 then raise ERigm.Create('一括操作が多すぎます。');
        for Item in JA(Manifest, 'operations') do begin
          if not (Item is TJSONObject) then raise ERigm.Create('操作の形式が不正です。'); Operation := TJSONObject(Item);
          var OpName := JS(Operation, 'command');
          if not IsAllowed(Page, OpName) or (OpName = 'import') or (OpName = 'batch') or
            (OpName = 'mark-complete') or (OpName = 'export') or (OpName = 'undo') or (OpName = 'redo') or
            (OpName = 'request-fix') or (OpName = 'select-object') or (OpName = 'schema') or
            (OpName = 'status') or (OpName = 'document') or (OpName = 'validate') then raise ERigm.Create('一括取込で許可されない操作です。');
          Selected := ApplyCommand(Candidate, OpName, JO(Operation, 'args'));
        end;
      finally Manifest.Free; end;
    end else Selected := ApplyCommand(Candidate, Command, Args);
    if (Command = 'verify-source') and JB(Args, 'confirmed') then Invalidate := False;
    if Command = 'ignore-issue' then Invalidate := False;
    Commit(Candidate, Page, Invalidate); Candidate := nil; SelectedId := Selected; Notify;
    AiLog.Add(PageName(Page) + ': ' + Command); Result := Status;
  finally Candidate.Free; end;
end;

end.
