unit RigmScriptCreatorFrame;
interface
uses System.Classes, RigmScriptPageFrame, System.JSON, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, RigmBufferedControls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.ImgList, RigmWizardWorkspace,
  RigmMovieCreator, RigmPageNavigation, RigmIconToolbar, RigmThumbnailList, RigmScriptLayoutFrame, RigmScriptPlacementFrame, RigmScriptTextFrame, RigmScriptReviewFrame, RigmScriptCastingFrame, RigmScriptSubtitleFrame, RigmScriptVoiceFrame, RigmScriptVoiceEffectsFrame, RigmScriptSceneAssignmentFrame, RigmScriptScenesFrame, RigmScriptSummaryFrame, RigmScriptClosingFrame;
type
  TRigmScriptCreatorFrame = class(TRigmScriptPageFrame,IRigmPageLifecycle)
  private
    FWorkspace: TRigmWizardWorkspace; FRoot: string; FTitle: TEdit; FStatus,FProgress: TLabel;
    FToolbar: TRigmIconToolbar; FSave: TToolButton; FSync: Boolean;
    FTitleStage,FCharactersStage,FLayoutStage,FPlacementStage,FTextStage,FReviewStage,FCastingStage,FSubtitleStage,FVoiceStage,FEffectsStage,FSceneAssignmentStage,FScenesStage,FSummaryStage,FClosingStage,FNext: TToolButton;
    FText: TRigmScriptTextFrame; FReview: TRigmScriptReviewFrame; FCasting: TRigmScriptCastingFrame; FSubtitles: TRigmScriptSubtitleFrame; FVoice: TRigmScriptVoiceFrame;
    FScenes: TRigmScriptScenesFrame; FSummaryBody: TPanel; FSummaryChoice: TRadioGroup; FSummaryEdit: TRigmScriptSummaryFrame; FClosingEdit: TRigmScriptClosingFrame;
    FEffects: TRigmScriptVoiceEffectsFrame;
    FSceneAssignment: TRigmScriptSceneAssignmentFrame;
    FPlacement: TRigmScriptPlacementFrame;
    FLayout: TRigmScriptLayoutFrame; FActive: Boolean;
    FTitleBody,FStageHost: TScrollBox; FCharactersBody: TPanel; FCharacters: TListView; FImages: TImageList;
    FTitleContent: TPanel; FTitleLayout,FStageLayout: Boolean; FShownStage: string;
    FCatalog: TJSONObject; FCatalogProject: string; FCharactersGuide: TLabel;
    FLoader: TRigmThumbnailList;
    FCreator: TRigmMovieCreator; // 旧コードの明示利用用。通常は生成・表示しない。
    procedure SummaryChoiceChanged(Sender: TObject);
    procedure SelectStage(Sender: TObject);
    procedure NextWork(Sender: TObject);
    procedure ChangeStage(Sender: TObject; Advance: Boolean); // Nextと工程選択を明示的に区別する。
    procedure ReloadCharacters(Sender: TObject);
    procedure CharacterChecked(Sender: TObject; Item: TListItem);
    function ThumbnailPath(Item: TListItem): string;
    procedure ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
    function GetCreator: TRigmMovieCreator;
    procedure Changed(Sender: TObject);
    procedure RefreshScript(Sender: TObject);
    procedure SaveWork(Sender: TObject);
    procedure ReturnToLibrary(Sender: TObject);
    procedure LayoutStagePages;
    procedure LayoutTitlePage(Sender: TObject);
    procedure StageHostResized(Sender: TObject);
  protected
    procedure Resize; override;
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    destructor Destroy; override;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    property Creator: TRigmMovieCreator read GetCreator;
  end;
implementation
uses System.SysUtils, System.IOUtils, System.Math, Vcl.Graphics, Winapi.Windows, Winapi.CommCtrl,
  RigmJson, RigmToolbarIcons, RigmCharacterCatalog, PsdJson, RigmScriptPlacementModel;
{$R *.dfm}
constructor TRigmScriptCreatorFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FRoot := Root; DoubleBuffered := True;
  // 一覧・ツールバーがHWNDを要求する前に表示先を接続する。シェルは構築後にホストへ移す。
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptTitleToolbar';
  FToolbar.AddIcon('ScriptReturn','保存して台本管理へ戻る',riLayer,0,ReturnToLibrary);
  FToolbar.AddSeparator;
  FSave := FToolbar.AddIcon('ScriptSave','下書きを保存する',riSave,0,SaveWork);
  FToolbar.AddSeparator;
  FTitleStage := FToolbar.AddIcon('ScriptTitleStage','第1段階：題名へ戻る',riEditPreview,0,SelectStage,True);
  FCharactersStage := FToolbar.AddIcon('ScriptCharactersStage','第2段階：キャラ選択',riGroup,0,SelectStage,True);
  FLayoutStage := FToolbar.AddIcon('ScriptLayoutStage','第3段階：レイアウト選択',riLayer,0,SelectStage,True);
  FPlacementStage := FToolbar.AddIcon('ScriptPlacementStage','第4段階：キャラ配置',riEditPreview,0,SelectStage,True);
  FTextStage := FToolbar.AddIcon('ScriptTextStage','第5段階：台本入力',riEditPreview,0,SelectStage,True);
  FReviewStage := FToolbar.AddIcon('ScriptReviewStage','第6段階：校正',riEditPreview,0,SelectStage,True);
  FCastingStage := FToolbar.AddIcon('ScriptCastingStage','第7段階：配役',riGroup,0,SelectStage,True);
  FSubtitleStage := FToolbar.AddIcon('ScriptSubtitleStage','第8段階：字幕折返し・編集',riEditPreview,0,SelectStage,True);
  FVoiceStage := FToolbar.AddIcon('ScriptVoiceStage','第9段階：読み・音声調整',riEditPreview,0,SelectStage,True);
  FEffectsStage := FToolbar.AddIcon('ScriptVoiceEffectsStage','第10段階：音声エフェクト',riMesh,0,SelectStage,True);
  FSceneAssignmentStage := FToolbar.AddIcon('ScriptSceneAssignmentStage','第11段階：セリフのシーン割当',riLayer,0,SelectStage,True);
  FScenesStage := FToolbar.AddIcon('ScriptScenesStage','第12段階：シーン画像・説明文',riPreview,0,SelectStage,True);
  FSummaryStage := FToolbar.AddIcon('ScriptSummaryStage','総評の有無',riGroup,0,SelectStage,True);
  FClosingStage := FToolbar.AddIcon('ScriptClosingStage','締め',riPreview,0,SelectStage,True);
  FNext := FToolbar.AddIcon('ScriptNext','Next：保存して次の工程へ進む',riComplete,0,NextWork);
  FToolbar.AddIcon('ScriptCharactersRefresh','登録キャラを更新',riRefresh,0,ReloadCharacters);
  FStatus := TRigmScriptLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := ScaleValue(38);
  FSummaryBody := TRigmBufferedPanel.Create(Self); FSummaryBody.Parent := Self; FSummaryBody.Align := alClient; FSummaryBody.Caption := ''; FSummaryBody.BevelOuter := bvNone; FSummaryBody.Visible := False;
  FSummaryChoice := TRadioGroup.Create(Self); FSummaryChoice.Parent := FSummaryBody; FSummaryChoice.Align := alTop; FSummaryChoice.Height := ScaleValue(180); FSummaryChoice.Caption := '総評を入れますか'; FSummaryChoice.Items.Add('総評なし'); FSummaryChoice.Items.Add('総評あり'); FSummaryChoice.ItemIndex := -1; FSummaryChoice.OnClick := SummaryChoiceChanged; FSummaryChoice.Name := 'ScriptSummaryChoice';
  FStatus.AutoSize := False; FStatus.WordWrap := True; FStatus.Name := 'ScriptTitleStatus';
  FTitleBody := TScrollBox.Create(Self); FTitleBody.Parent := Self; FTitleBody.Align := alClient;
  FTitleBody.BorderStyle := bsNone; FTitleBody.HorzScrollBar.Visible := False; FTitleBody.VertScrollBar.Tracking := True;
  FTitleBody.Name := 'ScriptTitleScroll';
  FTitleBody.OnResize := LayoutTitlePage;
  var Body := TRigmBufferedPanel.Create(Self); Body.Parent := FTitleBody; Body.Align := alTop; Body.BevelOuter := bvNone;
  FTitleContent := Body;
  Body.Caption := ''; Body.ShowCaption := False; Body.Padding.SetBounds(ScaleValue(32),ScaleValue(24),ScaleValue(32),ScaleValue(24));
  var LabelTitle := TRigmScriptLabel.Create(Self); LabelTitle.Parent := Body; LabelTitle.Align := alTop; LabelTitle.Height := ScaleValue(40);
  LabelTitle.AutoSize := False; LabelTitle.Font.Size := 18; LabelTitle.Caption := '台本の題名'; LabelTitle.Name := 'ScriptTitleHeading';
  FTitle := TEdit.Create(Self); FTitle.Parent := Body; FTitle.Align := alTop; FTitle.Height := ScaleValue(42);
  FTitle.Font.Size := 16; FTitle.MaxLength := 128; FTitle.Name := 'ScriptTitle'; FTitle.TextHint := 'あとで見つけやすい題名を入力'; FTitle.OnChange := Changed;
  var Guide := TRigmScriptLabel.Create(Self); Guide.Parent := Body; Guide.Align := alTop; Guide.Top := FTitle.Top+FTitle.Height;
  Guide.AutoSize := False; Guide.Height := ScaleValue(94); Guide.WordWrap := True;
  Guide.Name := 'ScriptTitleGuide';
  Guide.Caption := '題名を入力し、Nextのチェックアイコンでキャラ選択へ進んでください。'+#13#10+
    '戻る・ホーム・終了でも途中の題名を保存し、台本管理から続けられます。'+#13#10+
    'Nextは内容と移動先を一緒に保存します。再開時は最後にNextで到達した画面を開きます。';
  FProgress := TRigmScriptLabel.Create(Self); FProgress.Parent := Body; FProgress.Align := alTop; FProgress.Top := Guide.Top+Guide.Height;
  FProgress.AutoSize := False; FProgress.Height := ScaleValue(40); FProgress.Name := 'ScriptTitleProgress';
  // 早期にParentを接続しても、見出し→入力欄→案内→進捗の既定順を保つ。
  Body.DisableAlign;
  try
    LabelTitle.Top := 0; FTitle.Top := LabelTitle.Height;
    Guide.Top := FTitle.Top+FTitle.Height; FProgress.Top := Guide.Top+Guide.Height;
  finally Body.EnableAlign; end;
  FCharactersBody := TRigmBufferedPanel.Create(Self); FCharactersBody.Parent := Self; FCharactersBody.Align := alClient;
  FCharactersBody.BevelOuter := bvNone; FCharactersBody.Caption := ''; FCharactersBody.ShowCaption := False;
  FCharactersBody.Padding.SetBounds(ScaleValue(32),ScaleValue(24),ScaleValue(32),ScaleValue(24)); FCharactersBody.Visible := False;
  FCharactersGuide := TRigmScriptLabel.Create(Self); FCharactersGuide.Parent := FCharactersBody; FCharactersGuide.Align := alTop;
  FCharactersGuide.AutoSize := False; FCharactersGuide.Height := ScaleValue(74); FCharactersGuide.WordWrap := True;
  FCharactersGuide.Name := 'ScriptCharactersProgress';
  FImages := TImageList.Create(Self); FImages.ColorDepth := cd32Bit; FImages.Width := ScaleValue(144); FImages.Height := ScaleValue(176);
  FCharacters := TListView.Create(Self); FCharacters.Parent := FCharactersBody; FCharacters.Align := alClient;
  FCharacters.Name := 'ScriptCharacters'; FCharacters.ViewStyle := vsIcon; FCharacters.ReadOnly := True;
  FCharacters.Checkboxes := True; FCharacters.HideSelection := False; FCharacters.LargeImages := FImages;
  FCharacters.IconOptions.AutoArrange := True; FCharacters.DoubleBuffered := True;
  ListView_SetIconSpacing(FCharacters.Handle,ScaleValue(220),ScaleValue(255));
  FCharacters.OnItemChecked := CharacterChecked;
  FLoader := TRigmThumbnailList.CreateForList(Self,FWorkspace.Thumbnails,FCharacters,FImages);
  FLoader.OnPath := ThumbnailPath; FLoader.OnApplied := ThumbnailApplied;
  FStageHost := TScrollBox.Create(Self); FStageHost.Parent := Self; FStageHost.Align := alClient;
  FStageHost.BorderStyle := bsNone; FStageHost.VertScrollBar.Tracking := True; FStageHost.HorzScrollBar.Tracking := True;
  FStageHost.Name := 'ScriptStageScroll'; FStageHost.Visible := False;
  FStageHost.OnResize := StageHostResized;
  FWorkspace.OnScriptChanged := RefreshScript;
end;
procedure TRigmScriptCreatorFrame.LayoutTitlePage(Sender: TObject);
begin
  if FTitleLayout or (FTitleContent=nil) or (FProgress=nil) then Exit;
  FTitleLayout := True;
  try
    FTitleContent.Width := FTitleBody.ClientWidth;
    FTitleContent.Realign;
    var Total := FTitleContent.Padding.Top+FTitleContent.Padding.Bottom;
    for var I := 0 to FTitleContent.ControlCount-1 do Inc(Total,FTitleContent.Controls[I].Height);
    FTitleContent.Height := Total;
  finally FTitleLayout := False; end;
end;
procedure TRigmScriptCreatorFrame.LayoutStagePages;
begin
  if (FStageHost=nil) or FStageLayout then Exit;
  FStageLayout := True;
  FStageHost.DisableAlign;
  try
    for var Page in TArray<TFrame>.Create(FLayout,FPlacement,FText,FReview,FCasting,FSubtitles,FVoice,FEffects,FSceneAssignment,FScenes,FSummaryEdit,FClosingEdit) do
      if Page<>nil then begin
        Page.Align := alNone; Page.Parent := FStageHost;
        // 狭い高DPI画面でも編集欄を潰さず、必要な方向だけスクロールして到達できるようにする。
        Page.SetBounds(-FStageHost.HorzScrollBar.Position,-FStageHost.VertScrollBar.Position,
          Max(FStageHost.ClientWidth,ScaleValue(800)),Max(FStageHost.ClientHeight,ScaleValue(520)));
      end;
  finally FStageHost.EnableAlign; FStageLayout := False; end;
end;
procedure TRigmScriptCreatorFrame.StageHostResized(Sender: TObject);
begin LayoutStagePages; end;
procedure TRigmScriptCreatorFrame.Resize;
begin inherited; LayoutTitlePage(Self); LayoutStagePages; end;
procedure TRigmScriptCreatorFrame.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin
  inherited;
  if FImages<>nil then begin
    FImages.SetSize(MulDiv(144,M,96),MulDiv(176,M,96));
    if FLoader<>nil then begin
      FLoader.Reset; for var Item in FCharacters.Items do Item.ImageIndex := -1;
      if FActive and FCharactersBody.Visible then FLoader.Refresh;
    end;
    ListView_SetIconSpacing(FCharacters.Handle,MulDiv(220,M,96),MulDiv(255,M,96));
  end;
  LayoutStagePages;
  LayoutTitlePage(Self);
end;
destructor TRigmScriptCreatorFrame.Destroy;
begin FWorkspace.OnScriptChanged := nil; FLoader.Free; FCatalog.Free; inherited; end;
function TRigmScriptCreatorFrame.GetCreator: TRigmMovieCreator;
begin
  if FCreator=nil then begin
    FCreator := TRigmMovieCreator.CreateForWorkspace(Self,TPath.Combine(FRoot,'RIGM'));
    FCreator.Visible := False; FCreator.Bind(FWorkspace.ActiveSession,nil); FCreator.SetActive(False);
  end;
  Result := FCreator;
end;
procedure TRigmScriptCreatorFrame.RefreshScript(Sender: TObject);
begin
  var State := FWorkspace.ScriptStatus;
  try
    FSync := True;
    try
      if FTitle.Text<>JS(State,'title') then FTitle.Text := JS(State,'title');
      if not JB(State,'hasProject') then Exit;
      var Wizard := JO(State,'wizard'); var IsScenes := JS(Wizard,'stage')='scenes'; var IsSummary := JS(Wizard,'stage')='summary'; var IsSummaryEdit := JS(Wizard,'stage')='summary-edit'; var IsClosing := JS(Wizard,'stage')='closing'; var IsVoice := JS(Wizard,'stage')='voice'; var IsCharacters := JS(Wizard,'stage')='characters'; var IsLayout := JS(Wizard,'stage')='layout';
      var IsEffects := JS(Wizard,'stage')='voice-effects';
      var IsSceneAssignment := JS(Wizard,'stage')='scene-assignment';
      var IsPlacement := JS(Wizard,'stage')='placement'; var IsText := JS(Wizard,'stage')='text'; var IsReview := JS(Wizard,'stage')='review'; var IsCasting := JS(Wizard,'stage')='casting'; var IsSubtitles := JS(Wizard,'stage')='subtitles'; var StageIndex := ScriptStageIndex(JS(Wizard,'stage'));
      if IsLayout and (FLayout=nil) then begin
        FLayout := TRigmScriptLayoutFrame.CreateForWorkspace(Self,FWorkspace); FLayout.Parent := Self;
      end;
      if IsPlacement and (FPlacement=nil) then begin FPlacement := TRigmScriptPlacementFrame.CreateForWorkspace(Self,FWorkspace); FPlacement.Parent := Self; end;
      if IsText and (FText=nil) then begin FText := TRigmScriptTextFrame.CreateForWorkspace(Self,FWorkspace); FText.Parent := Self; end;
      if IsReview and (FReview=nil) then begin FReview := TRigmScriptReviewFrame.CreateForWorkspace(Self,FWorkspace); FReview.Parent := Self; end;
      if IsCasting and (FCasting=nil) then begin FCasting := TRigmScriptCastingFrame.CreateForWorkspace(Self,FWorkspace); FCasting.Parent := Self; end;
      if IsSubtitles and (FSubtitles=nil) then begin FSubtitles := TRigmScriptSubtitleFrame.CreateForWorkspace(Self,FWorkspace); FSubtitles.Parent := Self; end;
      if IsVoice and (FVoice=nil) then begin FVoice := TRigmScriptVoiceFrame.CreateForWorkspace(Self,FWorkspace); FVoice.Parent := Self; end;
      if IsSceneAssignment and (FSceneAssignment=nil) then begin FSceneAssignment := TRigmScriptSceneAssignmentFrame.CreateForWorkspace(Self,FWorkspace); FSceneAssignment.Parent := Self; end;
      if IsScenes and (FScenes=nil) then begin FScenes := TRigmScriptScenesFrame.CreateForWorkspace(Self,FWorkspace); FScenes.Parent := Self; end;
      if IsEffects and (FEffects=nil) then begin FEffects := TRigmScriptVoiceEffectsFrame.CreateForWorkspace(Self,FWorkspace); FEffects.Parent := Self; end;
      if IsClosing and (FClosingEdit=nil) then begin FClosingEdit := TRigmScriptClosingFrame.CreateForWorkspace(Self,FWorkspace); FClosingEdit.Parent := Self; end;
      if IsSummaryEdit and (FSummaryEdit=nil) then begin FSummaryEdit := TRigmScriptSummaryFrame.CreateForWorkspace(Self,FWorkspace); FSummaryEdit.Parent := Self; end;
      FTitleBody.Visible := not IsCharacters and not IsLayout and not IsPlacement and not IsText and not IsReview and not IsCasting and not IsSubtitles and not IsVoice and not IsEffects and not IsSceneAssignment and not IsScenes and not IsSummary and not IsSummaryEdit and not IsClosing; FCharactersBody.Visible := IsCharacters;
      FStageHost.Visible := not FTitleBody.Visible and not IsCharacters and not IsSummary;
      if FShownStage<>JS(Wizard,'stage') then begin
        FStageHost.HorzScrollBar.Position := 0; FStageHost.VertScrollBar.Position := 0;
        FShownStage := JS(Wizard,'stage');
      end;
      FSummaryBody.Visible := IsSummary; FSummaryChoice.ItemIndex := -1; if JS(Wizard,'summaryChoice')='none' then FSummaryChoice.ItemIndex := 0 else if JS(Wizard,'summaryChoice')='yes' then FSummaryChoice.ItemIndex := 1;
      if FClosingEdit<>nil then begin FClosingEdit.Visible := IsClosing; if IsClosing then FClosingEdit.RefreshState; end;
      if FSummaryEdit<>nil then begin FSummaryEdit.Visible := IsSummaryEdit; if IsSummaryEdit then FSummaryEdit.RefreshState; end;
      if FLayout<>nil then begin FLayout.Visible := IsLayout; FLayout.SetActive(FActive and IsLayout); if IsLayout then FLayout.RefreshState; end;
      if FPlacement<>nil then begin FPlacement.Visible := IsPlacement; if IsPlacement then FPlacement.RefreshState else FPlacement.SetActive(False); end;
      if FText<>nil then begin FText.Visible := IsText; FText.SetActive(FActive and IsText); if IsText then FText.RefreshState; end;
      if FReview<>nil then begin FReview.Visible := IsReview; if IsReview then FReview.RefreshState; end;
      if FCasting<>nil then begin FCasting.Visible := IsCasting; FCasting.SetActive(FActive and IsCasting); if IsCasting and not FActive then FCasting.RefreshState; end;
      if FSubtitles<>nil then begin FSubtitles.Visible := IsSubtitles; FSubtitles.SetActive(FActive and IsSubtitles); if IsSubtitles then FSubtitles.RefreshState; end;
      if FVoice<>nil then begin FVoice.Visible := IsVoice; FVoice.SetActive(FActive and IsVoice); if IsVoice then FVoice.RefreshState; end;
      if FSceneAssignment<>nil then begin FSceneAssignment.Visible := IsSceneAssignment; if IsSceneAssignment then FSceneAssignment.RefreshState; end;
      if FScenes<>nil then begin FScenes.Visible := IsScenes; FScenes.SetActive(FActive and IsScenes); if IsScenes then FScenes.RefreshState; end;
      if FEffects<>nil then begin FEffects.Visible := IsEffects; FEffects.SetActive(FActive and IsEffects); if IsEffects then FEffects.RefreshState; end;
      LayoutStagePages;
      FTitleStage.Down := StageIndex=0; FCharactersStage.Down := IsCharacters; FLayoutStage.Down := IsLayout; FPlacementStage.Down := IsPlacement;
      FCharactersStage.Enabled := StageIndex>=1; FLayoutStage.Enabled := StageIndex>=2; FPlacementStage.Enabled := StageIndex>=3;
      FTextStage.Down := IsText; FTextStage.Enabled := StageIndex>=4;
      FReviewStage.Down := IsReview; FReviewStage.Enabled := StageIndex>=5;
      FCastingStage.Down := IsCasting; FCastingStage.Enabled := StageIndex>=6;
      FSubtitleStage.Down := IsSubtitles; FSubtitleStage.Enabled := StageIndex>=7;
      var Reached := Max(StageIndex,ScriptStageIndex(JS(Wizard,'furthestStage',JS(State,'resumeStage'))));
      FVoiceStage.Down := IsVoice; FVoiceStage.Enabled := Reached>=ScriptStageIndex('voice');
      FEffectsStage.Down := IsEffects; FEffectsStage.Enabled := Reached>=ScriptStageIndex('voice-effects');
      FSceneAssignmentStage.Down := IsSceneAssignment; FSceneAssignmentStage.Enabled := Reached>=ScriptStageIndex('scene-assignment');
      FScenesStage.Down := IsScenes; FScenesStage.Enabled := (Reached>=ScriptStageIndex('scenes')) and (JS(FWorkspace.ScriptDraft.ScriptWizard,'scene-assignmentStatus')='complete'); FSummaryStage.Down := IsSummary or IsSummaryEdit; FSummaryStage.Enabled := Reached>=ScriptStageIndex('summary'); FClosingStage.Down := IsClosing; FClosingStage.Enabled := Reached>=ScriptStageIndex('closing'); FNext.Visible := True; FNext.Enabled := JB(State,'canAdvance') or (IsVoice and JB(State,'canConfirmVoice')) or (IsSubtitles and JB(State,'canConfirmSubtitles'));
      if (Wizard.GetValue('scenes')<>nil) and not JB(JO(Wizard,'scenes'),'allApproved') then begin FSummaryStage.Enabled := False; FClosingStage.Enabled := False; end;
    if not JB(State,'castingReady') then begin
        FSubtitleStage.Enabled := False; FVoiceStage.Enabled := False; FEffectsStage.Enabled := False; FScenesStage.Enabled := False; FSummaryStage.Enabled := False; FClosingStage.Enabled := False;
      end;
      if IsSubtitles and not JB(State,'canAdvance') then begin
        FVoiceStage.Enabled := False; FEffectsStage.Enabled := False; FScenesStage.Enabled := False; FSummaryStage.Enabled := False; FClosingStage.Enabled := False;
      end;
      if IsClosing then FNext.Hint := 'Next：締め設定を確認し、保存して動画編集へ'
      else if IsSummaryEdit then FNext.Hint := 'Next：総評・評価を確認し、保存して総評の音声へ'
      else if IsSummary then FNext.Hint := 'Next：総評の選択と移動先を保存する'
      else if IsScenes then FNext.Hint := 'Next：全シーンの確定チェックを確認し、保存して動画編集へ'
      else if IsSceneAssignment then FNext.Hint := 'Next：セリフのシーン割当を保存して、画像・説明文の設定へ'
      else if IsEffects and (JS(Wizard,'voiceReturnStage')='closing') then FNext.Hint := 'Next：保存して締めへ'
      else if IsEffects then FNext.Hint := 'Next：保存してセリフのシーン割当へ'
      else if IsVoice then FNext.Hint := 'Next：全セリフの再生を確認し、保存して音声エフェクトへ'
      else if IsSubtitles then FNext.Hint := 'Next：字幕入力を確認し、保存して読み・音声調整へ'
      else if IsCharacters then FNext.Hint := 'Next：キャラ選択と移動先を保存してレイアウトへ'
      else if IsLayout then FNext.Hint := 'Next：レイアウトと移動先を保存してキャラ配置へ'
      else if IsCasting then FNext.Hint := 'Next：配役と使用キャラの声を確認し保存して字幕へ'
      else if IsReview then FNext.Hint := 'Next：校正を確認し保存して配役へ'
      else if IsText then FNext.Hint := 'Next：台本と移動先を保存して校正へ'
      else if IsPlacement then FNext.Hint := 'Next：配置と移動先を保存して台本入力へ'
      else FNext.Hint := 'Next：題名と移動先を保存してキャラ選択へ';
      FNext.Caption := FNext.Hint; // ネイティブのボタン名も現在の移動先へ揃える。
      if not FNext.Enabled and (IsSubtitles or IsCasting or IsVoice or IsSceneAssignment or IsScenes) and (JS(State,'advanceBlockedReason')<>'') then FNext.Hint := FNext.Hint+#13#10+JS(State,'advanceBlockedReason');
      var Reload := (FCatalog=nil) or (FCatalogProject<>JS(State,'projectId'));
      if IsCharacters and not Reload then for var V in JA(Wizard,'selectedCharacters') do begin
        var Found := False;
        for var Item in FCharacters.Items do if SameText(JS(TJSONObject(Item.Data),'path'),JS(TJSONObject(V),'path')) then begin Found := True; Break; end;
        if not Found then begin Reload := True; Break; end;
      end;
      if IsCharacters and Reload then ReloadCharacters(Self);
      for var Item in FCharacters.Items do begin
        var Entry := TJSONObject(Item.Data); var Selected := False;
        for var V in JA(Wizard,'selectedCharacters') do
          if SameText(JS(TJSONObject(V),'path'),JS(Entry,'path')) then begin Selected := True; Break; end;
        Item.Checked := Selected;
      end;
      FSave.Enabled := JB(State,'modified'); FSave.Hint := '下書きを保存する（Nextでも保存されます）';
      if IsCharacters then begin
        var Progress := '選択中'; if JS(Wizard,'charactersStatus')='complete' then Progress := '確認済み';
        FCharactersGuide.Caption := 'キャラ選択：'+Progress+'（第2段階）  '+JA(Wizard,'selectedCharacters').Count.ToString+'人'+#13#10+
          '完成済みキャラを1人以上チェックし、Nextで保存してレイアウト選択へ進んでください。未完成・読込不可は選べません。'+#13#10+
          '声の割り当てはこの工程では行いません。';
      end;
    finally FSync := False; end;
    if not JB(State,'hasProject') then FProgress.Caption := '台本管理から新規作成してください。'
    else if JS(JO(State,'wizard'),'titleStatus')='complete' then FProgress.Caption := '題名：確認済み（第1段階）'
    else FProgress.Caption := '題名：入力中（第1段階）';
    if JB(State,'modified') then FStatus.Caption := '入力中です。戻る・終了時に途中状態を保存します。'
    else FStatus.Caption := '保存済み。再開先は最後にNextで到達した画面です（'+ScriptStageName(JS(State,'resumeStage'))+'）。';
    FStatus.Hint := JS(State,'path'); FStatus.ShowHint := True;
    LayoutTitlePage(Self);
  finally State.Free; end;
end;
procedure TRigmScriptCreatorFrame.Changed(Sender: TObject);
begin
  if FSync then Exit;
  try FWorkspace.SetScriptTitle(FTitle.Text);
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TRigmScriptCreatorFrame.SaveWork(Sender: TObject);
begin
  if (FSubtitles<>nil) and (FWorkspace.CurrentScriptStage='subtitles') and not FSubtitles.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='closing') and (FClosingEdit<>nil) and not FClosingEdit.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='summary-edit') and (FSummaryEdit<>nil) and not FSummaryEdit.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='scenes') and (FScenes<>nil) and not FScenes.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='casting') and (FCasting<>nil) and not FCasting.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='voice') and (FVoice<>nil) and not FVoice.RequestFinish then Exit;
  if (FWorkspace.CurrentScriptStage='voice-effects') and (FEffects<>nil) and not FEffects.RequestFinish then Exit;
  try
    FWorkspace.SaveScriptDraft(False);
    if FNext.Enabled then FStatus.Caption := '下書きを保存しました。Nextで入力を確認し、次の工程へ進めます。'
    else FStatus.Caption := '下書きを保存しました。次へ進む条件を確認してください。';
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TRigmScriptCreatorFrame.SelectStage(Sender: TObject);
begin ChangeStage(Sender,False); end;
procedure TRigmScriptCreatorFrame.NextWork(Sender: TObject);
begin ChangeStage(Sender,True); end;
procedure TRigmScriptCreatorFrame.ChangeStage(Sender: TObject; Advance: Boolean);
begin
  var Before := FWorkspace.CurrentScriptStage;
  try
    if (FSubtitles<>nil) and (Before='subtitles') and not FSubtitles.RequestFinish then
      raise Exception.Create('字幕入力を確定できません。'+FSubtitles.InputError);
    if (FClosingEdit<>nil) and (Before='closing') and not FClosingEdit.RequestFinish then raise Exception.Create('締めの入力を確定できません。編集欄の理由を確認してください。');
    if (FSummaryEdit<>nil) and (Before='summary-edit') and not FSummaryEdit.RequestFinish then raise Exception.Create('総評の入力を確定できません。編集欄の理由を確認してください。');
    if (FCasting<>nil) and (Before='casting') and not FCasting.RequestFinish then raise Exception.Create('配役工程のVOICEVOX接続先を適用してください。');
    if (FVoice<>nil) and (Before='voice') and not FVoice.RequestFinish then raise Exception.Create('音声の入力を確定できません。編集欄の理由を確認してください。');
    if (FEffects<>nil) and (Before='voice-effects') and not FEffects.RequestFinish then raise Exception.Create('音声エフェクトの入力を確定できません。編集欄の理由を確認してください。');
    if (FScenes<>nil) and (Before='scenes') and not FScenes.RequestFinish then raise Exception.Create('シーンの入力を確定できません。編集欄の理由を確認してください。');
    if Advance then begin
      if Before='subtitles' then FWorkspace.CompleteSubtitles;
      if Before='voice' then FWorkspace.CompleteVoice;
      FWorkspace.NextScriptDraft; RefreshScript(Self);
      if (Before='subtitles') and (FWorkspace.CurrentScriptStage<>'voice') then raise Exception.Create('字幕を保存しましたが、音声工程へ切り替わりませんでした。');
    end
    else begin
      var Stage := 'characters'; if Sender=FTitleStage then Stage := 'title'
      else if Sender=FLayoutStage then Stage := 'layout' else if Sender=FPlacementStage then Stage := 'placement' else if Sender=FTextStage then Stage := 'text' else if Sender=FReviewStage then Stage := 'review' else if Sender=FCastingStage then Stage := 'casting' else if Sender=FSubtitleStage then Stage := 'subtitles' else if Sender=FVoiceStage then Stage := 'voice' else if Sender=FEffectsStage then Stage := 'voice-effects' else if Sender=FSceneAssignmentStage then Stage := 'scene-assignment' else if Sender=FScenesStage then Stage := 'scenes' else if Sender=FSummaryStage then Stage := 'summary' else if Sender=FClosingStage then Stage := 'closing';
      FWorkspace.SetScriptStage(Stage);
    end;
  except on E: Exception do begin
    var Failure := E.Message;
    try RefreshScript(Self); except on SyncError: Exception do Failure := Failure+' / 表示更新：'+SyncError.Message; end;
    if Advance then FStatus.Caption := '次へ進めません。'+Failure else FStatus.Caption := Failure;
  end; end;
end;
procedure TRigmScriptCreatorFrame.ReloadCharacters(Sender: TObject);
begin
  if FWorkspace.ScriptDraft=nil then Exit;
  var WasSync := FSync; FSync := True; FCharacters.Items.BeginUpdate;
  try
    var Catalog := FWorkspace.ScriptCharacterLibrary;
    FLoader.Reset; FCharacters.Items.Clear; FCatalog.Free; FCatalog := Catalog; FCatalogProject := FWorkspace.ScriptDraft.Id;
    var State := FWorkspace.ScriptStatus;
    try
      // 登録素材が一時的に見つからなくても、保存済み選択を黙って消さない。
      for var V in JA(JO(State,'wizard'),'selectedCharacters') do begin
        var Found := False;
        for var E in JA(FCatalog,'characters') do if SameText(JS(TJSONObject(E),'path'),JS(TJSONObject(V),'path')) then begin Found := True; Break; end;
        if not Found then begin
          var Missing := TJSONObject(V.Clone); Missing.AddPair('readyForScript',TJSONBool.Create(False));
          Missing.AddPair('productionReason','登録素材が見つかりません。'); JA(FCatalog,'characters').AddElement(Missing);
        end;
      end;
      for var V in JA(FCatalog,'characters') do begin
        var Entry := TJSONObject(V); var Item := FCharacters.Items.Add; Item.Data := Entry;
        var LabelText := CharacterFormatLabel(JS(Entry,'path'));
        if JB(Entry,'loading') then LabelText := LabelText+' / 準備中' else if not JB(Entry,'readyForScript') then LabelText := LabelText+' / 未完成';
        Item.Caption := '['+LabelText+'] '+JS(Entry,'name'); Item.ImageIndex := -1;
        for var Saved in JA(JO(State,'wizard'),'selectedCharacters') do
          if SameText(JS(TJSONObject(Saved),'path'),JS(Entry,'path')) then Item.Checked := True;
      end;
    finally State.Free; end;
  except on E: Exception do FStatus.Caption := E.Message;
  end;
  FCharacters.Items.EndUpdate; FSync := WasSync;
  FLoader.Refresh;
end;
function TRigmScriptCreatorFrame.ThumbnailPath(Item: TListItem): string;
begin Result := JS(TJSONObject(Item.Data),'path'); end;
procedure TRigmScriptCreatorFrame.ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
begin
  var Entry := TJSONObject(Item.Data);
  for var Pair in Metadata do PsdJson.Put(Entry,Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
  if Metadata.GetValue('loading')=nil then PsdJson.Put(Entry,'loading',TJSONBool.Create(False));
  var LabelText := CharacterFormatLabel(JS(Entry,'path'));
  if JS(Entry,'productionState')<>'' then LabelText := LabelText+' / '+JS(Entry,'productionState');
  Item.Caption := '['+LabelText+'] '+JS(Entry,'name');
end;
procedure TRigmScriptCreatorFrame.CharacterChecked(Sender: TObject; Item: TListItem);
begin
  if FSync then Exit;
  var Paths := TJSONArray.Create;
  try
    try
      for var Entry in FCharacters.Items do if Entry.Checked then Paths.Add(JS(TJSONObject(Entry.Data),'path'));
      FWorkspace.SetScriptCharacters(Paths);
    except on E: Exception do begin FLoader.Refresh; RefreshScript(Self); FStatus.Caption := E.Message; end; end;
  finally Paths.Free; end;
end;
procedure TRigmScriptCreatorFrame.ReturnToLibrary(Sender: TObject);
begin
  if RequestFinish and Assigned(FWorkspace.OnNavigate) then FWorkspace.OnNavigate(Self,apScripts,'');
end;
procedure TRigmScriptCreatorFrame.SetActive(Value: Boolean);
begin
  FActive := Value;
  if FLayout<>nil then FLayout.SetActive(Value and (FWorkspace.ScriptDraft<>nil) and (FWorkspace.CurrentScriptStage='layout'));
  if FPlacement<>nil then FPlacement.SetActive(Value and (FWorkspace.CurrentScriptStage='placement'));
  if FText<>nil then FText.SetActive(Value and (FWorkspace.CurrentScriptStage='text'));
  if FReview<>nil then FReview.SetActive(Value and (FWorkspace.CurrentScriptStage='review'));
  if FCasting<>nil then FCasting.SetActive(Value and (FWorkspace.CurrentScriptStage='casting'));
  if FSubtitles<>nil then FSubtitles.SetActive(Value and (FWorkspace.CurrentScriptStage='subtitles'));
  if Value then begin if FWorkspace.ScriptDraft=nil then FWorkspace.NewScriptDraft; RefreshScript(Self); if FCatalog<>nil then FLoader.Refresh; end;
  if FVoice<>nil then FVoice.SetActive(Value and (FWorkspace.CurrentScriptStage='voice'));
  if FEffects<>nil then FEffects.SetActive(Value and (FWorkspace.CurrentScriptStage='voice-effects'));
  if FScenes<>nil then FScenes.SetActive(Value and (FWorkspace.CurrentScriptStage='scenes'));
  if FCreator<>nil then FCreator.SetActive(False);
end;
function TRigmScriptCreatorFrame.RequestFinish: Boolean;
begin
  Result := False;
  if (FSubtitles<>nil) and (FWorkspace.CurrentScriptStage='subtitles') and not FSubtitles.RequestFinish then Exit;
  if (FClosingEdit<>nil) and (FWorkspace.CurrentScriptStage='closing') and not FClosingEdit.RequestFinish then Exit;
  if (FSummaryEdit<>nil) and (FWorkspace.CurrentScriptStage='summary-edit') and not FSummaryEdit.RequestFinish then Exit;
  if (FCasting<>nil) and (FWorkspace.CurrentScriptStage='casting') and not FCasting.RequestFinish then Exit;
  if (FVoice<>nil) and (FWorkspace.CurrentScriptStage='voice') and not FVoice.RequestFinish then Exit;
  if (FEffects<>nil) and (FWorkspace.CurrentScriptStage='voice-effects') and not FEffects.RequestFinish then Exit;
  if (FScenes<>nil) and (FWorkspace.CurrentScriptStage='scenes') and not FScenes.RequestFinish then Exit;
  if (FWorkspace.ScriptDraft<>nil) and (FTitle.Text<>JS(FWorkspace.ScriptDraft.ScriptWizard,'titleInput')) then begin
    FStatus.Caption := '題名を確認してください。入力を保持してこの画面に留まります。'; Exit;
  end;
  try FWorkspace.SaveScriptDraft(False); Result := True;
  except on E: Exception do FStatus.Caption := '保存できません。入力を保持しています。'+E.Message; end;
end;
procedure TRigmScriptCreatorFrame.SummaryChoiceChanged(Sender: TObject);
begin
  if FSync or (FSummaryChoice.ItemIndex<0) then Exit;
  try if FSummaryChoice.ItemIndex=0 then FWorkspace.SetScriptSummaryChoice('none') else FWorkspace.SetScriptSummaryChoice('yes'); except on E: Exception do FStatus.Caption := E.Message; end;
end;
end.
