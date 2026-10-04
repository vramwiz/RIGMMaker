unit RigmMovieCreator;
interface
uses System.Classes, System.SysUtils, System.JSON, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.ImgList,
  RigmMovieSession, RigmMovieForm, RigmIconToolbar;
type
  TCreationEntry = class
    Name,FileName,CharacterId: string;
  end;
  TRigmMovieCreator = class(TPanel)
  private
    FSession: TRigmMovieSession;
    FMovie: TRigmMovieForm;
    FDirectory: string;
    FEntries: TObjectList<TCreationEntry>;
    FList: TListView;
    FImages: TImageList;
    FPreview: TRigmMoviePreview;
    FToolbar: TRigmIconToolbar;
    FScript,FDescription: TMemo;
    FScenes: TListBox;
    FName,FSpeaker,FStyle,FX,FY,FW,FH,FSceneTitle,FSceneDuration: TEdit;
    FPosition,FLayout,FMotions: TComboBox;
    FRigSafe,FGenerated: TCheckBox;
    FStatus: TLabel;
    FTimer: TTimer;
    FRevision: Integer;
    FFrameCount: UInt64;
    FRefreshing: Boolean;
    FCharacterDrafts,FSceneDrafts: TObjectDictionary<string,TJSONObject>;
    FViewedCharacter,FViewedScene: string;
    FCharacterRevision,FSceneRevision: Integer;
    procedure DraftChanged(Sender: TObject);
    procedure PreviewSelection(Sender: TObject);
    procedure LoadThumbnail(Item: TListItem; const Path: string);
    function DraftKey(const Id: string): string;
    function Command(const Name: string; Args: TJSONObject=nil): TJSONObject;
    procedure Run(const Name: string; Args: TJSONObject=nil);
    procedure Selection(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure Checked(Sender: TObject; Item: TListItem);
    procedure SceneSelection(Sender: TObject);
    procedure Action(Sender: TObject);
    procedure Timer(Sender: TObject);
    procedure Refresh;
    function SelectedCharacter: string;
    function SelectedScene: string;
    procedure LoadLibrary;
  public
    constructor CreateForWorkspace(AOwner: TComponent; const Directory: string);
    destructor Destroy; override;
    procedure Bind(Session: TRigmMovieSession; Movie: TRigmMovieForm);
    procedure RefreshLibrary;
    property PreviewControl: TRigmMoviePreview read FPreview;
  end;
implementation
uses System.IOUtils, System.Math, System.Types, System.StrUtils, Vcl.Graphics, Vcl.Dialogs,
  RigmJson, RigmModel, RigmMovieModel, RigmStorage, RigmToolbarIcons, RigmMovieComposition, RigmMovieCompositor, RigmMovieWorkspace, RigmMovieMotionLibrary;
constructor TRigmMovieCreator.CreateForWorkspace(AOwner: TComponent; const Directory: string);
  function Edit(Parent: TWinControl; const Name,Caption: string; Y: Integer): TEdit;
  begin
    var L := TLabel.Create(Self); L.Parent := Parent; L.Caption := Caption; L.SetBounds(12,Y,290,20);
    Result := TEdit.Create(Self); Result.Parent := Parent; Result.Name := Name; Result.SetBounds(12,Y+20,290,26); Result.OnChange := DraftChanged;
  end;
  procedure Button(Parent: TWinControl; const Name,Caption: string; Tag,Y: Integer);
  begin var B := TButton.Create(Self); B.Parent := Parent; B.Name := Name; B.Caption := Caption; B.Tag := Tag; B.SetBounds(12,Y,290,30); B.OnClick := Action; end;
begin
  inherited Create(AOwner); if AOwner is TWinControl then Parent := TWinControl(AOwner); BevelOuter := bvNone; DoubleBuffered := True; Name := 'MovieCreationPage'; FDirectory := Directory;
  FEntries := TObjectList<TCreationEntry>.Create(True); FRevision := -1;
  FCharacterDrafts := TObjectDictionary<string,TJSONObject>.Create([doOwnsValues]); FSceneDrafts := TObjectDictionary<string,TJSONObject>.Create([doOwnsValues]);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop;
  FToolbar.Name := 'CreationToolbar';
  FToolbar.AddIcon('CreationRefresh','キャラクター一覧を更新',riRefresh,1,Action);
  FToolbar.AddIcon('CreationImport','入力した台本を取り込む',riPng,2,Action);
  FToolbar.AddIcon('CreationAnalyze','台本の感情を分析し、既存差分を再利用',riGenerate,3,Action);
  FToolbar.AddIcon('CreationSceneAdd','シーンを追加',riNew,4,Action);
  FToolbar.AddIcon('CreationSceneDelete','選択シーンとそのセリフを削除',riDelete,5,Action);
  FToolbar.AddIcon('CreationSceneImage','選択シーンの画像を登録',riOpen,6,Action);
  FToolbar.AddIcon('CreationTheme','共通背景を登録',riOpen,7,Action);
  FToolbar.AddIcon('CreationUnlock','Codex編集ロックを手動解除',riReset,8,Action);
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom;
  FStatus.Height := 48; FStatus.AutoSize := False; FStatus.WordWrap := True;
  FStatus.Caption := 'チェックで動画へ追加。選択行の設定だけを右側で編集します。配置はフルHD座標、10pxスナップです。';
  FImages := TImageList.Create(Self); FImages.Width := 96; FImages.Height := 96; FImages.ColorDepth := cd32Bit;
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := 235;
  FList.Name := 'CreationCharacters'; FList.ViewStyle := vsReport; FList.Checkboxes := True;
  FList.SmallImages := FImages; FList.Columns.Add.Width := 215; FList.ShowColumnHeaders := False;
  FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False;
  FList.OnSelectItem := Selection; FList.OnItemChecked := Checked;
  var Right := TScrollBox.Create(Self); Right.Parent := Self; Right.Align := alRight; Right.Width := 330;
  Right.Name := 'CreationSettings'; Right.HorzScrollBar.Visible := False;
  FName := Edit(Right,'CreationName','選択キャラクター',10);
  FSpeaker := Edit(Right,'CreationSpeaker','台本の話者ID（キャラクターごとに独立）',64);
  FStyle := Edit(Right,'CreationVoiceStyle','VOICEVOX styleId（対応する音声のみ）',118);
  FPosition := TComboBox.Create(Self); FPosition.Parent := Right; FPosition.Style := csDropDownList;
  FPosition.Name := 'CreationInitialPosition'; FPosition.SetBounds(12,172,290,28); FPosition.Items.AddStrings(['左','中央','右']); FPosition.ItemIndex := 2;
  Button(Right,'CreationApplyPosition','左 / 中央 / 右へ初期配置',9,206);
  FX := Edit(Right,'CreationX','X（フルHD基準）',248); FY := Edit(Right,'CreationY','Y',302);
  FW := Edit(Right,'CreationWidth','幅（元画像の縦横比を保持して表示）',356); FH := Edit(Right,'CreationHeight','高さ',410);
  FRigSafe := TCheckBox.Create(Self); FRigSafe.Parent := Right; FRigSafe.Caption := '小さなRIGM揺れを併用'; FRigSafe.SetBounds(12,470,290,24);
  FGenerated := TCheckBox.Create(Self); FGenerated.Parent := Right; FGenerated.Caption := '生成表情の追加を許可'; FGenerated.SetBounds(12,500,290,24);
  FRigSafe.OnClick := DraftChanged; FGenerated.OnClick := DraftChanged;
  Button(Right,'CreationApplyCharacter','選択キャラクターの設定を適用',10,534);
  FLayout := TComboBox.Create(Self); FLayout.Parent := Right; FLayout.Style := csDropDownList;
  FLayout.Name := 'CreationLayout'; FLayout.SetBounds(12,582,290,28); FLayout.Items.AddStrings(['共通背景＋中央画像','L字：左にキャラクター','L字：右にキャラクター']); FLayout.ItemIndex := 0;
  Button(Right,'CreationApplyLayout','レイアウトを適用',11,618);
  FScenes := TListBox.Create(Self); FScenes.Parent := Right; FScenes.Name := 'CreationScenes'; FScenes.SetBounds(12,664,290,120); FScenes.OnClick := SceneSelection;
  FSceneTitle := Edit(Right,'CreationSceneTitle','シーン名（複数セリフをまとめる単位）',800);
  FSceneDuration := Edit(Right,'CreationSceneDuration','シーン長：末尾余白を調整（秒）',854);
  FDescription := TMemo.Create(Self); FDescription.Parent := Right; FDescription.Name := 'CreationSceneDescription';
  FDescription.SetBounds(12,916,290,90); FDescription.ScrollBars := ssVertical;
  FDescription.OnChange := DraftChanged;
  Button(Right,'CreationApplyScene','シーン説明と長さを適用',12,1016);
  Button(Right,'CreationReloadFields','選択対象の最新設定を読み直す',13,1058);
  FMotions := TComboBox.Create(Self); FMotions.Parent := Right; FMotions.Style := csDropDownList;
  FMotions.Name := 'CreationMotions'; FMotions.SetBounds(12,1110,290,28);
  Button(Right,'CreationSelectMotion','選択モーションを現在位置から再生',14,1146);
  Button(Right,'CreationStopMotion','モーションを停止して通常表示に戻る',15,1188);
  Button(Right,'CreationRegisterMotion','モーション定義JSONを登録',16,1230);
  Button(Right,'CreationBuildMotions','感情の全体モーション4種を保管',17,1272);
  var Center := TPanel.Create(Self); Center.Parent := Self; Center.Align := alClient; Center.BevelOuter := bvNone;
  FScript := TMemo.Create(Self); FScript.Parent := Center; FScript.Align := alBottom; FScript.Height := 150;
  FScript.Name := 'CreationScript'; FScript.ScrollBars := ssVertical;
  FPreview := TRigmMoviePreview.Create(Self); FPreview.Parent := Center; FPreview.Align := alClient; FPreview.Name := 'CreationPreview';
  FPreview.OnCharacterSelected := PreviewSelection;
  FTimer := TTimer.Create(Self); FTimer.Interval := 100; FTimer.OnTimer := Timer;
  LoadLibrary;
end;
destructor TRigmMovieCreator.Destroy;
begin if FTimer<>nil then FTimer.Enabled := False; FCharacterDrafts.Free; FSceneDrafts.Free; FEntries.Free; inherited; end;
function TRigmMovieCreator.Command(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try
    if Args.GetValue('projectId')=nil then Args.AddPair('projectId',FSession.Project.Id);
    if Args.GetValue('revision')=nil then AddN(Args,'revision',FSession.Project.Revision);
    Result := FSession.Execute(Name,Args);
  finally Args.Free; end;
end;
procedure TRigmMovieCreator.Run(const Name: string; Args: TJSONObject);
begin var O := Command(Name,Args); O.Free; end;
procedure TRigmMovieCreator.Bind(Session: TRigmMovieSession; Movie: TRigmMovieForm);
begin FSession := Session; FMovie := Movie; FPreview.Session := Session; FRevision := -1; FFrameCount := High(UInt64); Refresh; end;
procedure TRigmMovieCreator.RefreshLibrary;
begin LoadLibrary; Refresh; end;
procedure TRigmMovieCreator.PreviewSelection(Sender: TObject);
begin
  for var I := 0 to FList.Items.Count-1 do
    if TCreationEntry(FList.Items[I].Data).CharacterId=FPreview.SelectedCharacter then begin
      FList.Items[I].Selected := True; Exit;
    end;
end;
function TRigmMovieCreator.SelectedCharacter: string;
begin Result := ''; if FList.Selected<>nil then Result := TCreationEntry(FList.Selected.Data).CharacterId; end;
function TRigmMovieCreator.SelectedScene: string;
begin Result := ''; if (FScenes.ItemIndex>=0) and (FScenes.ItemIndex<FSession.Project.Scenes.Count) then Result := FSession.Project.Scenes[FScenes.ItemIndex].Id; end;
procedure TRigmMovieCreator.LoadThumbnail(Item: TListItem; const Path: string);
begin
    if Path='@sample' then begin Item.ImageIndex := -1; Exit; end;
    var W,H: Integer; var N: string; var B := Vcl.Graphics.TBitmap.Create;
    try
      var Pixels := ReadRigmThumbnail(Path,N,W,H);
      if N<>'' then begin Item.Caption := N; TCreationEntry(Item.Data).Name := N; end;
      B.PixelFormat := pf32bit; B.SetSize(96,96);
      var K := Min(90/Max(1,W),90/Max(1,H)); var TW := Max(1,Round(W*K)); var TH := Max(1,Round(H*K));
      for var Y := 0 to 95 do begin var Row := PByte(B.ScanLine[Y]); for var X := 0 to 95 do begin
        var P := X*4; Row[P] := 40; Row[P+1] := 35; Row[P+2] := 30; Row[P+3] := 255;
        var SX := X-(96-TW) div 2; var SY := Y-(96-TH) div 2;
        if (SX>=0) and (SX<TW) and (SY>=0) and (SY<TH) then begin
          var Q := (Min(H-1,SY*H div TH)*W+Min(W-1,SX*W div TW))*4; var A := Pixels[Q+3];
          for var C := 0 to 2 do Row[P+2-C] := (Pixels[Q+C]*A+Row[P+2-C]*(255-A)+127) div 255;
        end;
      end; end;
      Item.ImageIndex := FImages.Add(B,nil);
    except Item.ImageIndex := -1; end;
    B.Free;
end;
procedure TRigmMovieCreator.LoadLibrary;
  procedure Entry(const Path,Name: string);
  begin
    var E := TCreationEntry.Create; E.FileName := Path; E.Name := Name; var Item := FList.Items.Add; Item.Caption := Name; Item.Data := E;
    FEntries.Add(E); LoadThumbnail(Item,Path);
  end;
begin
  FRefreshing := True; FList.Items.BeginUpdate;
  try
    FList.Items.Clear; FImages.Clear; FEntries.Clear; Entry('@sample','編集テスト用サンプル');
    if DirectoryExists(FDirectory) then for var P in TDirectory.GetFiles(FDirectory,'*.rigm') do Entry(P,ChangeFileExt(ExtractFileName(P),''));
    if FList.Items.Count>0 then FList.Items[0].Selected := True;
  finally FList.Items.EndUpdate; FRefreshing := False; end;
  FRevision := -1;
end;
procedure TRigmMovieCreator.Refresh;
begin
  if FSession=nil then Exit; FRefreshing := True;
  try
    for var E in FEntries do E.CharacterId := '';
    for var C in FSession.Project.Characters do begin
      var Entry: TCreationEntry := nil;
      for var E in FEntries do if (E.CharacterId='') and SameText(E.FileName,ResolveMoviePath(FSession.Project.FileName,C.FileName)) then begin Entry := E; Break; end;
      if Entry=nil then begin
        Entry := TCreationEntry.Create; Entry.Name := C.Name; Entry.FileName := ResolveMoviePath(FSession.Project.FileName,C.FileName); FEntries.Add(Entry);
        var I := FList.Items.Add; I.Data := Entry; I.Caption := C.Name; LoadThumbnail(I,Entry.FileName);
      end;
      Entry.CharacterId := C.Id;
    end;
    for var I := 0 to FList.Items.Count-1 do FList.Items[I].Checked := TCreationEntry(FList.Items[I].Data).CharacterId<>'';
    var SceneId := FViewedScene; FScenes.Items.Clear;
    for var S in FSession.Project.Scenes do FScenes.Items.Add(S.Title+Format('  %.2fs',[FSession.Project.SceneDuration(S)]));
    if (FScenes.ItemIndex<0) and (FScenes.Items.Count>0) then FScenes.ItemIndex := 0;
    for var I := 0 to FSession.Project.Scenes.Count-1 do if FSession.Project.Scenes[I].Id=SceneId then FScenes.ItemIndex := I;
    FLayout.ItemIndex := 0; if FSession.Project.Layout='l' then if FSession.Project.LDirection='left' then FLayout.ItemIndex := 1 else FLayout.ItemIndex := 2;
    FRevision := FSession.Project.Revision;
  finally FRefreshing := False; end;
  Selection(Self,FList.Selected,True); SceneSelection(Self);
end;
procedure TRigmMovieCreator.Selection(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FRefreshing or not Selected or (FSession=nil) then Exit;
  FRefreshing := True;
  try
  FViewedCharacter := SelectedCharacter; FCharacterRevision := FSession.Project.Revision;
  var C := FSession.Project.Character(SelectedCharacter);
  if (Sender=FList) or (FPreview.SelectedCharacter='') then FPreview.SelectedCharacter := SelectedCharacter;
  FPreview.Invalidate;
  if C=nil then begin FName.Text := ''; FSpeaker.Text := ''; Exit; end;
  FName.Text := C.Name; FSpeaker.Text := C.SpeakerId; FStyle.Text := FSession.Project.Speaker(C.SpeakerId).StyleId.ToString;
  FX.Text := FloatToStr(C.X,TFormatSettings.Invariant); FY.Text := FloatToStr(C.Y,TFormatSettings.Invariant);
  FW.Text := FloatToStr(C.Width,TFormatSettings.Invariant); FH.Text := FloatToStr(C.Height,TFormatSettings.Invariant);
  FRigSafe.Checked := C.RigSafe; FGenerated.Checked := C.AllowGeneratedExpressions;
  var MotionName := FMotions.Text; FMotions.Items.Clear;
  for var Pair in C.Motions do FMotions.Items.Add(Pair.JsonString.Value);
  FMotions.ItemIndex := FMotions.Items.IndexOf(MotionName);
  if FMotions.ItemIndex<0 then FMotions.ItemIndex := FMotions.Items.IndexOf(C.ActiveMotion);
  if (FMotions.ItemIndex<0) and (FMotions.Items.Count>0) then FMotions.ItemIndex := 0;
  FPosition.ItemIndex := 2; if C.InitialPosition='left' then FPosition.ItemIndex := 0 else if C.InitialPosition='center' then FPosition.ItemIndex := 1;
  var Draft: TJSONObject;
  if FCharacterDrafts.TryGetValue(DraftKey(FViewedCharacter),Draft) then begin
    FCharacterRevision := JI(Draft,'revision'); FName.Text := JS(Draft,'name'); FSpeaker.Text := JS(Draft,'speaker'); FStyle.Text := JS(Draft,'styleText');
    FX.Text := JS(Draft,'xText'); FY.Text := JS(Draft,'yText'); FW.Text := JS(Draft,'widthText'); FH.Text := JS(Draft,'heightText');
    FRigSafe.Checked := JB(Draft,'rigSafe',C.RigSafe); FGenerated.Checked := JB(Draft,'allowGeneratedExpressions',C.AllowGeneratedExpressions);
  end;
  finally FRefreshing := False; end;
end;
procedure TRigmMovieCreator.Checked(Sender: TObject; Item: TListItem);
begin
  if FRefreshing or (FSession=nil) then Exit;
  try
    var E := TCreationEntry(Item.Data); var O := TJSONObject.Create;
    if Item.Checked then begin
      var C := TRigmMovieCharacter.Create;
      try
        C.Name := E.Name; C.FileName := E.FileName;
        if FSession.Project.Characters.Count>0 then C.SpeakerId := 'speaker-'+NewRigmId;
        C.X := 80+(FSession.Project.Characters.Count mod 3)*660;
        if (FSession.Project.Layout='l') and (FSession.Project.LDirection='right') then C.X := 1370;
        C.InitialPosition := 'left'; if C.X>1200 then C.InitialPosition := 'right';
        O.AddPair('character',C.Json); Run('add-character',O);
      finally C.Free; end;
    end else begin O.AddPair('id',E.CharacterId); Run('delete-character',O); end;
    Refresh;
  except on E: Exception do begin FStatus.Caption := E.Message; Refresh; end; end;
end;
procedure TRigmMovieCreator.SceneSelection(Sender: TObject);
begin
  if (FSession=nil) or FRefreshing then Exit;
  FRefreshing := True;
  try
  FViewedScene := SelectedScene; FSceneRevision := FSession.Project.Revision;
  var S := FSession.Project.Scene(SelectedScene); if S=nil then Exit;
  FSceneTitle.Text := S.Title; FSceneDuration.Text := FloatToStr(FSession.Project.SceneDuration(S),TFormatSettings.Invariant); FDescription.Text := S.Description;
  var Draft: TJSONObject;
  if FSceneDrafts.TryGetValue(DraftKey(FViewedScene),Draft) then begin
    FSceneRevision := JI(Draft,'revision'); FSceneTitle.Text := JS(Draft,'title'); FSceneDuration.Text := JS(Draft,'durationText'); FDescription.Text := JS(Draft,'description');
  end;
  finally FRefreshing := False; end;
end;
function TRigmMovieCreator.DraftKey(const Id: string): string;
begin Result := IntToHex(NativeUInt(FSession),16)+'|'+Id; end;
procedure TRigmMovieCreator.DraftChanged(Sender: TObject);
begin
  if FRefreshing or (FSession=nil) then Exit;
  var O := TJSONObject.Create;
  if (Sender=FSceneTitle) or (Sender=FSceneDuration) or (Sender=FDescription) then begin
    AddN(O,'revision',FSceneRevision); O.AddPair('title',FSceneTitle.Text); O.AddPair('durationText',FSceneDuration.Text); O.AddPair('description',FDescription.Text);
    FSceneDrafts.AddOrSetValue(DraftKey(FViewedScene),O);
  end else begin
    AddN(O,'revision',FCharacterRevision); O.AddPair('name',FName.Text); O.AddPair('speaker',FSpeaker.Text); O.AddPair('styleText',FStyle.Text);
    O.AddPair('xText',FX.Text); O.AddPair('yText',FY.Text); O.AddPair('widthText',FW.Text); O.AddPair('heightText',FH.Text);
    AddB(O,'rigSafe',FRigSafe.Checked); AddB(O,'allowGeneratedExpressions',FGenerated.Checked);
    FCharacterDrafts.AddOrSetValue(DraftKey(FViewedCharacter),O);
  end;
end;
procedure TRigmMovieCreator.Timer(Sender: TObject);
begin
  if (FSession=nil) or not Visible then Exit;
  if FRevision<>FSession.Project.Revision then Refresh;
  if FFrameCount<>FMovie.PreviewControl.FrameCount then begin
    FFrameCount := FMovie.PreviewControl.FrameCount;
    if not FMovie.PreviewControl.Frame.Empty then FPreview.SetFrame(FMovie.PreviewControl.Frame);
  end;
  FList.Enabled := not FSession.GuiLocked; FScript.ReadOnly := FSession.GuiLocked; FDescription.ReadOnly := FSession.GuiLocked;
  for var I := 0 to ComponentCount-1 do begin
    var C := Components[I];
    if C is TEdit then TEdit(C).ReadOnly := FSession.GuiLocked;
    if C is TCheckBox then TCheckBox(C).Enabled := not FSession.GuiLocked;
    if C is TComboBox then TComboBox(C).Enabled := not FSession.GuiLocked;
    if C is TButton then TButton(C).Enabled := not FSession.GuiLocked or (TButton(C).Tag=13);
    if C is TToolButton then TToolButton(C).Enabled := not FSession.GuiLocked or (TToolButton(C).Tag in [1,8]);
  end;
end;
procedure TRigmMovieCreator.Action(Sender: TObject);
const Positions: array[0..2] of string = ('left','center','right');
begin
  if FSession=nil then Exit;
  try
    var Tag := TControl(Sender).Tag;
    if Tag=1 then begin LoadLibrary; Refresh; Exit; end;
    if Tag=8 then begin Run('edit-release'); Refresh; Exit; end;
    if Tag=13 then begin
      FCharacterDrafts.Remove(DraftKey(FViewedCharacter)); FSceneDrafts.Remove(DraftKey(FViewedScene)); Refresh; Exit;
    end;
    if FSession.GuiLocked then raise ERigm.Create('Codex編集中です。編集が終了するか、ロック解除を押すと操作できます。');
    case Tag of
      17: begin
        var Character := FSession.Project.Character(SelectedCharacter); if Character=nil then raise ERigm.Create('Select a character first');
        var Id := Character.Id; var Motions := BuildCharacterMotions(ResolveMoviePath(FSession.Project.FileName,Character.FileName));
        try
          for var Pair in Motions do begin
            var O := TJSONObject.Create; O.AddPair('id',Id); O.AddPair('name',Pair.JsonString.Value); O.AddPair('motion',Pair.JsonValue.Clone as TJSONValue); Run('register-motion',O);
          end;
        finally Motions.Free; end;
      end;
      14,15: begin
        var O := TJSONObject.Create; O.AddPair('id',SelectedCharacter);
        if Tag=14 then begin O.AddPair('name',FMotions.Text); AddN(O,'start',FSession.Time); Run('select-motion',O); end
        else Run('stop-motion',O);
      end;
      16: begin
        var D := TOpenDialog.Create(Self);
        try
          D.Filter := 'Motion definition (*.json)|*.json'; D.Options := [ofFileMustExist,ofPathMustExist,ofNoChangeDir,ofEnableSizing];
          if D.Execute then begin
            if TFile.GetSize(D.FileName)>1024*1024 then raise ERigm.Create('Motion definition is too large');
            var Definition := ParseObject(TFile.ReadAllText(D.FileName,TEncoding.UTF8));
            try
              var Motion := JO(Definition,'motion');
              for var V in JA(Motion,'frames') do begin
                var Frame := TJSONObject(V); var Path := ResolveMoviePath(D.FileName,JS(Frame,'image'));
                Frame.RemovePair('image').Free; Frame.AddPair('image',Path);
              end;
              var O := TJSONObject.Create; O.AddPair('id',SelectedCharacter); O.AddPair('name',JS(Definition,'name'));
              O.AddPair('motion',Motion.Clone as TJSONObject); Run('register-motion',O);
            finally Definition.Free; end;
          end;
        finally D.Free; end;
      end;
      2: begin var O := TJSONObject.Create; O.AddPair('text',FScript.Text); Run('import-script',O); Run('composition-enable'); end;
      3: Run('analyze-script');
      4: begin var O := TJSONObject.Create; var S := TRigmMovieScene.Create; try O.AddPair('scene',S.Json); finally S.Free; end; Run('add-scene',O); end;
      5: begin var O := TJSONObject.Create; O.AddPair('id',SelectedScene); Run('delete-scene',O); end;
      6,7: begin
        var D := TOpenDialog.Create(Self);
        try
          D.Filter := '画像 (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'; D.Options := [ofFileMustExist,ofPathMustExist,ofNoChangeDir,ofEnableSizing];
          if D.Execute then FSession.AdoptImage(SelectedScene,D.FileName,Tag=7);
        finally D.Free; end;
      end;
      9,10: begin
        var C := FSession.Project.Character(SelectedCharacter); if C=nil then Exit;
        var O := TJSONObject.Create; O.AddPair('id',C.Id);
        if Tag=9 then begin
          var X := 80.0; if FPosition.ItemIndex=1 then X := 700 else if FPosition.ItemIndex=2 then X := 1370;
          O.AddPair('initialPosition',Positions[Max(0,FPosition.ItemIndex)]); AddN(O,'x',X); AddN(O,'y',130);
        end else begin
          AddN(O,'revision',FCharacterRevision);
          O.AddPair('name',FName.Text); O.AddPair('speaker',FSpeaker.Text); AddN(O,'x',StrToFloat(FX.Text,TFormatSettings.Invariant));
          AddN(O,'y',StrToFloat(FY.Text,TFormatSettings.Invariant)); AddN(O,'width',StrToFloat(FW.Text,TFormatSettings.Invariant)); AddN(O,'height',StrToFloat(FH.Text,TFormatSettings.Invariant));
          AddB(O,'rigSafe',FRigSafe.Checked); AddB(O,'allowGeneratedExpressions',FGenerated.Checked);
          AddN(O,'styleId',StrToInt(FStyle.Text));
        end;
        Run('update-character',O);
        if Tag=10 then FCharacterDrafts.Remove(DraftKey(FViewedCharacter));
      end;
      11: begin
        // One atomic model update also moves all actors to the selected L side.
        var O := TJSONObject.Create; O.AddPair('layout',IfThen(FLayout.ItemIndex=0,'theme','l'));
        O.AddPair('lDirection',IfThen(FLayout.ItemIndex=1,'left','right')); Run('update-project',O);
      end;
      12: begin
        var O := TJSONObject.Create; O.AddPair('id',SelectedScene); O.AddPair('title',FSceneTitle.Text); O.AddPair('description',FDescription.Text);
        AddN(O,'revision',FSceneRevision);
        AddN(O,'duration',StrToFloat(FSceneDuration.Text,TFormatSettings.Invariant)); Run('update-scene',O);
        FSceneDrafts.Remove(DraftKey(FViewedScene));
      end;
    end;
    Refresh;
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
end.
