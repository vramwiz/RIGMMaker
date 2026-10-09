unit RigmScriptCreatorFrame;
interface
uses System.Classes, System.Types, RigmScriptPageFrame, System.JSON, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, RigmBufferedControls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.ImgList, RigmWizardWorkspace,
  RigmMovieCreator, RigmPageNavigation, RigmThumbnailList, RigmScriptLayoutFrame, RigmScriptPlacementFrame, RigmScriptTextFrame, RigmScriptReviewFrame, RigmScriptCastingFrame, RigmScriptSubtitleFrame, RigmScriptVoiceFrame, RigmScriptVoiceEffectsFrame, RigmScriptSceneAssignmentFrame, RigmScriptScenesFrame, RigmScriptSummaryFrame, RigmScriptClosingFrame;
type
  TRigmScriptCreatorFrame = class(TRigmScriptPageFrame,IRigmPageLifecycle)
  private
    FWorkspace: TRigmWizardWorkspace; FRoot: string; FTitle: TEdit; FScriptType: TComboBox; FStatus,FProgress: TLabel;
    FHeader,FSidebar,FBody: TPanel; FSave,FReturn,FReload: TButton; FStageLabel: TLabel; FSync: Boolean;
    FStages: TListBox; FStageIds: TArray<string>; FStageEnabled: TArray<Boolean>;
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
    procedure RefreshNavigation(State: TJSONObject);
    procedure DrawStage(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure LayoutNavigation;
    procedure ChangeStage(const Stage: string; Advance: Boolean);
    procedure ReloadCharacters(Sender: TObject);
    procedure CharacterChecked(Sender: TObject; Item: TListItem);
    function ThumbnailPath(Item: TListItem): string;
    procedure ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
    function GetCreator: TRigmMovieCreator;
    procedure Changed(Sender: TObject);
    procedure ScriptTypeChanged(Sender: TObject);
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
uses System.SysUtils, System.IOUtils, System.Math, Vcl.Graphics, Vcl.Themes, Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  RigmJson, RigmCharacterCatalog, PsdJson, RigmScriptPlacementModel, RigmScriptTypes, RigmScriptNavigationModel;
{$R *.dfm}
type
  TRigmStageListBox = class(TListBox)
  private
    FWheelDelta: Integer;
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure CreateParams(var Params: TCreateParams); override;
  end;
procedure TRigmStageListBox.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // 工程一覧はバーを表示しない。高さ不足時もホイール・キーで移動できる。
  Params.Style := Params.Style and not (WS_HSCROLL or WS_VSCROLL or LBS_DISABLENOSCROLL);
end;
procedure TRigmStageListBox.WndProc(var Message: TMessage);
begin
  if Message.Msg=WM_MOUSEWHEEL then begin
    Inc(FWheelDelta,SmallInt(HiWord(Message.WParam)));
    var Steps := FWheelDelta div WHEEL_DELTA; FWheelDelta := FWheelDelta mod WHEEL_DELTA;
    var Lines: Cardinal := 3; SystemParametersInfo(SPI_GETWHEELSCROLLLINES,0,@Lines,0);
    if Lines=WHEEL_PAGESCROLL then Lines := Max(1,ClientHeight div Max(1,ItemHeight));
    if Steps<>0 then TopIndex := EnsureRange(TopIndex-Steps*Integer(Lines),0,Max(0,Items.Count-1));
    Message.Result := 1; Exit;
  end;
  inherited;
end;
constructor TRigmScriptCreatorFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FRoot := Root; DoubleBuffered := True;
  // 一覧・ツールバーがHWNDを要求する前に表示先を接続する。シェルは構築後にホストへ移す。
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  FHeader := TRigmBufferedPanel.Create(Self); FHeader.Parent := Self; FHeader.Align := alTop;
  FHeader.Height := ScaleValue(52); FHeader.BevelOuter := bvNone; FHeader.ShowCaption := False;
  FHeader.Name := 'ScriptHeader';
  FReturn := TButton.Create(Self); FReturn.Parent := FHeader; FReturn.Caption := '保存して台本管理へ';
  FReturn.Name := 'ScriptReturn'; FReturn.OnClick := ReturnToLibrary;
  FSave := TButton.Create(Self); FSave.Parent := FHeader; FSave.Caption := '保存';
  FSave.Name := 'ScriptSave'; FSave.OnClick := SaveWork;
  FStageLabel := TLabel.Create(Self); FStageLabel.Parent := FHeader; FStageLabel.AutoSize := False;
  FStageLabel.Layout := tlCenter; FStageLabel.Font.Size := 13; FStageLabel.Name := 'ScriptCurrentStage';
  FSidebar := TRigmBufferedPanel.Create(Self); FSidebar.Parent := Self; FSidebar.Align := alLeft;
  FSidebar.Width := ScaleValue(240); FSidebar.BevelOuter := bvNone; FSidebar.ShowCaption := False;
  FSidebar.Padding.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(8),ScaleValue(8));
  FSidebar.Name := 'ScriptStageSidebar';
  FStages := TRigmStageListBox.Create(Self); FStages.Parent := FSidebar; FStages.Align := alClient;
  FStages.Name := 'ScriptStages'; FStages.Style := lbOwnerDrawFixed; FStages.BorderStyle := bsNone;
  FStages.ItemHeight := ScaleValue(30); FStages.OnDrawItem := DrawStage; FStages.OnClick := SelectStage;
  FStages.Hint := '工程を選ぶと入力を保存して切り替えます。条件が整うと次の工程が表示されます。';
  FStages.ShowHint := True; FStages.ScrollWidth := 0;
  FBody := TRigmBufferedPanel.Create(Self); FBody.Parent := Self; FBody.Align := alClient;
  FBody.BevelOuter := bvNone; FBody.ShowCaption := False; FBody.Name := 'ScriptPageBody';
  FStatus := TRigmScriptLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := ScaleValue(38);
  FSummaryBody := TRigmBufferedPanel.Create(Self); FSummaryBody.Parent := FBody; FSummaryBody.Align := alClient; FSummaryBody.Caption := ''; FSummaryBody.BevelOuter := bvNone; FSummaryBody.Visible := False;
  FSummaryChoice := TRadioGroup.Create(Self); FSummaryChoice.Parent := FSummaryBody; FSummaryChoice.Align := alTop; FSummaryChoice.Height := ScaleValue(180); FSummaryChoice.Caption := '総評を入れますか'; FSummaryChoice.Items.Add('総評なし'); FSummaryChoice.Items.Add('総評あり'); FSummaryChoice.ItemIndex := -1; FSummaryChoice.OnClick := SummaryChoiceChanged; FSummaryChoice.Name := 'ScriptSummaryChoice';
  FStatus.AutoSize := False; FStatus.WordWrap := True; FStatus.Name := 'ScriptTitleStatus';
  FTitleBody := TScrollBox.Create(Self); FTitleBody.Parent := FBody; FTitleBody.Align := alClient;
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
  var TypeHeading := TRigmScriptLabel.Create(Self); TypeHeading.Parent := Body; TypeHeading.Align := alTop;
  TypeHeading.AutoSize := False; TypeHeading.Height := ScaleValue(32); TypeHeading.Caption := '台本の種類'; TypeHeading.Name := 'ScriptTypeHeading';
  FScriptType := TComboBox.Create(Self); FScriptType.Parent := Body; FScriptType.Align := alTop;
  FScriptType.Style := csDropDownList; FScriptType.Font.Size := 12; FScriptType.Name := 'ScriptType';
  FScriptType.TextHint := '種類を選択（未設定）';
  for var I := 0 to ScriptTypeCount-1 do FScriptType.Items.Add(ScriptTypeName(ScriptTypeId(I)));
  FScriptType.ItemIndex := -1; FScriptType.OnChange := ScriptTypeChanged;
  var Guide := TRigmScriptLabel.Create(Self); Guide.Parent := Body; Guide.Align := alTop; Guide.Top := FScriptType.Top+FScriptType.Height;
  Guide.AutoSize := False; Guide.Height := ScaleValue(94); Guide.WordWrap := True;
  Guide.Name := 'ScriptTitleGuide';
  Guide.Caption := '台本の種類と題名を入力し、左の工程リストでキャラ選択を選んでください。'+#13#10+
    '上部の保存ボタンで途中の内容を保存し、台本管理から続けられます。'+#13#10+
    '次の工程を選ぶと内容と移動先を一緒に保存します。再開時は最後に進んだ工程を開きます。';
  FProgress := TRigmScriptLabel.Create(Self); FProgress.Parent := Body; FProgress.Align := alTop; FProgress.Top := Guide.Top+Guide.Height;
  FProgress.AutoSize := False; FProgress.Height := ScaleValue(40); FProgress.Name := 'ScriptTitleProgress';
  // 見出し→題名→種類→案内→進捗の順に配置し、DPI変更時は既存のスクロールを使う。
  Body.DisableAlign;
  try
    LabelTitle.Top := 0; FTitle.Top := LabelTitle.Height;
    TypeHeading.Top := FTitle.Top+FTitle.Height; FScriptType.Top := TypeHeading.Top+TypeHeading.Height;
    Guide.Top := FScriptType.Top+FScriptType.Height; FProgress.Top := Guide.Top+Guide.Height;
  finally Body.EnableAlign; end;
  FCharactersBody := TRigmBufferedPanel.Create(Self); FCharactersBody.Parent := FBody; FCharactersBody.Align := alClient;
  FCharactersBody.BevelOuter := bvNone; FCharactersBody.Caption := ''; FCharactersBody.ShowCaption := False;
  FCharactersBody.Padding.SetBounds(ScaleValue(32),ScaleValue(24),ScaleValue(32),ScaleValue(24)); FCharactersBody.Visible := False;
  FReload := TButton.Create(Self); FReload.Parent := FCharactersBody; FReload.Align := alTop;
  FReload.Height := ScaleValue(36); FReload.Caption := '登録キャラを更新';
  FReload.Name := 'ScriptCharactersRefresh'; FReload.OnClick := ReloadCharacters;
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
  FStageHost := TScrollBox.Create(Self); FStageHost.Parent := FBody; FStageHost.Align := alClient;
  FStageHost.BorderStyle := bsNone; FStageHost.VertScrollBar.Tracking := True; FStageHost.HorzScrollBar.Tracking := True;
  FStageHost.Name := 'ScriptStageScroll'; FStageHost.Visible := False;
  FStageHost.OnResize := StageHostResized;
  FWorkspace.OnScriptChanged := RefreshScript;
  LayoutNavigation;
end;
procedure TRigmScriptCreatorFrame.LayoutNavigation;
begin
  if (FHeader=nil) or (FStageLabel=nil) then Exit;
  FReturn.SetBounds(ScaleValue(8),ScaleValue(8),ScaleValue(190),ScaleValue(36));
  FSave.SetBounds(FReturn.Left+FReturn.Width+ScaleValue(8),ScaleValue(8),ScaleValue(76),ScaleValue(36));
  var X := FSave.Left+FSave.Width+ScaleValue(20);
  FStageLabel.SetBounds(X,0,Max(0,FHeader.ClientWidth-X-ScaleValue(8)),FHeader.Height);
  FStages.ItemHeight := ScaleValue(30);
  FStages.Canvas.Font.Assign(FStages.Font);
  var TextWidth := 0;
  // 未到達の工程も測り、段階を進めた時に編集領域の幅が変わらないようにする。
  for var Stage in ScriptStages do TextWidth := Max(TextWidth,FStages.Canvas.TextWidth(ScriptStageCaption(Stage)));
  var SidebarWidth := TextWidth+ScaleValue(20)+FSidebar.Padding.Left+FSidebar.Padding.Right;
  if FSidebar.Width<>SidebarWidth then FSidebar.Width := SidebarWidth;
end;
procedure TRigmScriptCreatorFrame.RefreshNavigation(State: TJSONObject);
begin
  var Ids := ScriptVisibleStages(State); var Same := Length(Ids)=Length(FStageIds);
  if Same then for var I := 0 to High(Ids) do if Ids[I]<>FStageIds[I] then begin Same := False; Break; end;
  var OldTop := FStages.TopIndex; var Current := '';
  if JB(State,'hasProject') then Current := JS(JO(State,'wizard'),'stage');
  var OldSelection := '';
  if (FStages.ItemIndex>=0) and (FStages.ItemIndex<Length(FStageIds)) then OldSelection := FStageIds[FStages.ItemIndex];
  FStages.Items.BeginUpdate;
  try
    if not Same then begin
      FStages.Clear; FStageIds := Ids;
      for var Stage in Ids do FStages.Items.Add(ScriptStageCaption(Stage));
    end;
    SetLength(FStageEnabled,Length(Ids));
    for var I := 0 to High(Ids) do begin
      FStageEnabled[I] := ScriptStageAvailable(State,Ids[I]);
      if Ids[I]=Current then FStages.ItemIndex := I;
    end;
    if (OldSelection=Current) and (Length(Ids)>0) then FStages.TopIndex := Min(OldTop,Length(Ids)-1);
  finally FStages.Items.EndUpdate; end;
  if Current='' then FStageLabel.Caption := ''
  else FStageLabel.Caption := ScriptStageCaption(Current);
  FStages.Invalidate;
end;
procedure TRigmScriptCreatorFrame.DrawStage(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  if (Index<0) or (Index>=Length(FStageIds)) then Exit;
  var Canvas := FStages.Canvas;
  Canvas.Font.Assign(FStages.Font);
  Canvas.Brush.Color := StyleServices.GetSystemColor(clWindow);
  Canvas.Font.Color := StyleServices.GetSystemColor(clWindowText);
  if FStageIds[Index]=FShownStage then begin
    Canvas.Brush.Color := RGB(38,76,112);
    Canvas.Font.Color := clWhite;
  end
  else if not FStageEnabled[Index] then Canvas.Font.Color := StyleServices.GetSystemColor(clGrayText);
  Canvas.FillRect(Rect); InflateRect(Rect,-ScaleValue(10),-ScaleValue(4));
  var Text := ScriptStageCaption(FStageIds[Index]);
  DrawText(Canvas.Handle,PChar(Text),-1,Rect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
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
begin inherited; LayoutNavigation; LayoutTitlePage(Self); LayoutStagePages; end;
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
  LayoutNavigation;
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
      var TypeId := JS(State,'scriptType');
      // 将来の種類を旧版で開いても、表示・保持し、別の種類へ自動置換しない。
      while FScriptType.Items.Count>ScriptTypeCount do FScriptType.Items.Delete(FScriptType.Items.Count-1);
      FScriptType.ItemIndex := ScriptTypeIndex(TypeId);
      if (TypeId<>'') and (FScriptType.ItemIndex<0) then
        FScriptType.ItemIndex := FScriptType.Items.Add(ScriptTypeName(TypeId));
      if not JB(State,'hasProject') then begin RefreshNavigation(State); FSave.Enabled := False; Exit; end;
      var Wizard := JO(State,'wizard'); var IsScenes := JS(Wizard,'stage')='scenes'; var IsSummary := JS(Wizard,'stage')='summary'; var IsSummaryEdit := JS(Wizard,'stage')='summary-edit'; var IsClosing := JS(Wizard,'stage')='closing'; var IsVoice := JS(Wizard,'stage')='voice'; var IsCharacters := JS(Wizard,'stage')='characters'; var IsLayout := JS(Wizard,'stage')='layout';
      var IsEffects := JS(Wizard,'stage')='voice-effects';
      var IsSceneAssignment := JS(Wizard,'stage')='scene-assignment';
      var IsPlacement := JS(Wizard,'stage')='placement'; var IsText := JS(Wizard,'stage')='text'; var IsReview := JS(Wizard,'stage')='review'; var IsCasting := JS(Wizard,'stage')='casting'; var IsSubtitles := JS(Wizard,'stage')='subtitles';
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
      RefreshNavigation(State);
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
      FSave.Enabled := JB(State,'modified'); FSave.Hint := '途中の内容を保存する（工程を切り替えるときにも保存します）';
      if IsCharacters then begin
        var Progress := '選択中'; if JS(Wizard,'charactersStatus')='complete' then Progress := '確認済み';
        FCharactersGuide.Caption := 'キャラ選択：'+Progress+'（第2段階）  '+JA(Wizard,'selectedCharacters').Count.ToString+'人'+#13#10+
          '完成済みキャラを1人以上チェックし、左の工程リストでレイアウト選択へ進んでください。未完成・読込不可は選べません。'+#13#10+
          '声の割り当てはこの工程では行いません。';
      end;
    finally FSync := False; end;
    if not JB(State,'hasProject') then FProgress.Caption := '台本管理から新規作成してください。'
    else if JS(JO(State,'wizard'),'titleStatus')='complete' then FProgress.Caption := '題名：確認済み（第1段階）'
    else FProgress.Caption := '題名：未確認（第1段階）';
    if JB(State,'modified') then FStatus.Caption := '変更があります。保存ボタン・台本管理へ戻る時・終了時に保存します。'
    else FStatus.Caption := '保存済み。再開先は最後に進んだ工程です（'+ScriptStageName(JS(State,'resumeStage'))+'）。';
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
procedure TRigmScriptCreatorFrame.ScriptTypeChanged(Sender: TObject);
begin
  if FSync or (FScriptType.ItemIndex<0) or (FScriptType.ItemIndex>=ScriptTypeCount) then Exit;
  try FWorkspace.SetScriptType(ScriptTypeId(FScriptType.ItemIndex));
  except on E: Exception do begin FStatus.Caption := E.Message; end; end;
end;
procedure TRigmScriptCreatorFrame.SaveWork(Sender: TObject);
begin
  if RequestFinish then FStatus.Caption := '下書きを保存しました。条件が整うと左の工程リストに次の工程が表示されます。';
end;
procedure TRigmScriptCreatorFrame.SelectStage(Sender: TObject);
begin
  if FSync or (FStages.ItemIndex<0) or (FStages.ItemIndex>=Length(FStageIds)) then Exit;
  var Stage := FStageIds[FStages.ItemIndex]; var State := FWorkspace.ScriptStatus;
  try
    if not ScriptStageAvailable(State,Stage) then begin
      RefreshNavigation(State);
      FStatus.Caption := 'この工程にはまだ移動できません。'+JS(State,'advanceBlockedReason'); Exit;
    end;
    if Stage=FWorkspace.CurrentScriptStage then Exit;
    ChangeStage(Stage,Stage=ScriptNextStage(FWorkspace.CurrentScriptStage,JO(State,'wizard')));
  finally State.Free; end;
end;
procedure TRigmScriptCreatorFrame.ChangeStage(const Stage: string; Advance: Boolean);
begin
  var Before := FWorkspace.CurrentScriptStage;
  if (FWorkspace.ScriptDraft<>nil) and (FTitle.Text<>JS(FWorkspace.ScriptDraft.ScriptWizard,'titleInput')) then begin
    var State := FWorkspace.ScriptStatus;
    try RefreshNavigation(State); finally State.Free; end;
    FStatus.Caption := '題名を確認してください。入力を保持してこの画面に留まります。'; Exit;
  end;
  try
    if (FReview<>nil) and (Before='review') and not FReview.RequestFinish then raise Exception.Create('作品タイトルを確認してください。');
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
  if not FSync and (FWorkspace.CurrentScriptStage='characters') then begin
    var State := FWorkspace.ScriptStatus;
    try RefreshNavigation(State); finally State.Free; end;
  end;
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
  if (FReview<>nil) and (FWorkspace.CurrentScriptStage='review') and not FReview.RequestFinish then Exit;
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
