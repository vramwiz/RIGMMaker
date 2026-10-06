// 動画作品の編集入力・再生・工程操作を結び付けるフォーム。描画・画面生成・ページ配置・出力表示は専用部品へ委譲する。
unit RigmMovieEditorFrame;

interface
uses Winapi.Windows, System.SysUtils, System.Classes, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, System.Types, System.Generics.Collections,
  RigmMovieSession, RigmIconToolbar, RigmMovieTimeline, RigmPropertyScrollBox, Vcl.AppEvnts,
  RigmMovieNotification, RigmMoviePreview, RigmMovieControls, RigmMoviePropertyPages, RigmMovieExportFeedback;

type
  TRigmOpenMovieFile = procedure(const Path: string) of object;
  TRigmPropertyDrafts = array[0..4] of Boolean;
  TRigmMovieProperty = RigmMoviePropertyPages.TRigmMovieProperty;
  TRigmMoviePreview = RigmMoviePreview.TRigmMoviePreview;
  TRigmMovieEditorFrame = class(TFrame)
  private
    FSession      : TRigmMovieSession;        // 借用するGUI・パイプ共通の操作入口。画面より長く生存する。
    FUi           : TRigmMovieControls;       // 所有する画面構成部品。生成したVCLコントロールの所有者はSelf。
    FExport       : TRigmMovieExportFeedback; // 所有する出力ジョブの表示監視。
    FDraftRevision: Integer;                  // 表示値を編集し始めたrevision。0は未適用下書きなし。
    FAutoDiagnosticKey, FSeenDiagnostic: string;
    FJobPosition: Integer;
    FStatusTick : UInt64;
    FSplitterDragging, FPendingSplitterLayout: Boolean;
    FEditingLayout: Boolean;
    FAssets       : TJSONObject;
    FRefreshing, FPlaying: Boolean;
    FTick     : UInt64;
    FStartTime: Double;
    FAudioFile: string;
    FAudioReady, FAudioPreparing: Boolean;
    FClosing, FPendingPreview: Boolean;
    FSelectedId, FCatalogKey: string;
    FLastRevision, FViewRefreshCount: Integer;
    FSeenJob, FLastError: string;
    FSeekTick, FHistoryTick: UInt64;
    FDrawnFrame, FDrawnRevision: Integer; // 表示済み画像のフレームとrevision。-1はまだ表示していない。
    FPreparationStamp, FViewedProject: string;
    FPreviewRequests: Integer;
    FOnOpenWork     : TRigmOpenMovieFile;
    FOnlyTextDraft, FTextPending: Boolean;
    FPropertyDrafts: TRigmPropertyDrafts; // 属性ページ別の未適用変更。適用時に別ページの下書きを残す。
    FPoseDraft, FActingDraft, FSceneDraft, FChartDraft: Boolean;
    FOtherDraft     : Boolean;
    FStaticUiUpdates: Integer;
    FSavePath       : string;
    FLayoutPPI      : Integer; // 初期構築とDPI変更で追跡するレイアウト尺度。0の間は配置しない。
    function GetPreviewControl: TRigmMoviePreview;
    function GetPropertyLayouts: Integer;
    procedure ChooseExport(const Extension: string);
    procedure RefreshExport;
    procedure LayoutExportFeedback;
    procedure ShowExportError(const Message: string);
    procedure LayoutTransport;
    procedure EditingAreaResize(Sender: TObject);
    procedure SplitterBeforeResize(Sender: TObject);
    procedure SplitterAfterResize(Sender: TObject);
    procedure SplitterCanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
    procedure RefreshSeek;
    procedure SeekFrame(Frame: Integer);
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    procedure LayoutProperties(Sender: TObject);
    procedure RefreshTransport;
    procedure PreviewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BuildUI;
    procedure ShowOperations(Sender: TObject);
    procedure EditEnding(Sender: TObject);
    procedure DraftEdited(Sender: TObject);
    procedure ActionClick(Sender: TObject);
    procedure SelectCue(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SelectSpeaker(Sender: TObject);
    procedure SeekChanged(Sender: TObject);
    procedure TimelineSeek(Sender: TObject);
    procedure TimelineSelectCue(Sender: TObject);
    procedure ZoomChanged(Sender: TObject);
    procedure OutputPresetChanged(Sender: TObject);
    procedure PaintJobProgress(Sender: TObject);
    procedure RefreshPreparation;
    procedure VariantGroupChanged(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);

    function Command(const Name: string; Args: TJSONObject = nil): TJSONObject;
    procedure Run(const Name: string; Args: TJSONObject = nil);
    procedure RefreshView;
    procedure RefreshCue;
    procedure StartPlayback;
    procedure StopPlayback;
  public
    // 完了通知を要求した累計件数を返す。同じジョブは一度だけ数える。
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    procedure HandleKey(var Key: Word; Shift: TShiftState);
    function ExportNotificationRequests: Integer;
    // Windows通知の表示に成功した累計件数を返す。要求件数と区別する。
    function ExportNotificationsShown: Integer;
    property ViewRefreshCount: Integer read FViewRefreshCount;
    property PreviewPending: Boolean read FPendingPreview;
    property PreviewRequests: Integer read FPreviewRequests;
    property StaticUiUpdates: Integer read FStaticUiUpdates;
    property PropertyLayouts: Integer read GetPropertyLayouts;
    // 表示中の属性ページの保存識別子を返す。dialogue/scene/acting/audio/diagnosticsのいずれか。
    function PropertyPageName: string;
    // Pageへ切り替え、入力下書き・スクロール・フォーカスを保持する。未知のPageは拒否する。
    procedure SelectPropertyPage(const Page: string);
    // メニューと同じ操作番号を実行する。編集リース・revision・下書きの検査も共通になる。
    procedure InvokeAction(Action: Integer);
    // Sessionを借用して画面を作る。Embedded=Trueは親画面のDPI・メニューを使用する。
    constructor CreateForSession(AOwner: TComponent; Session: TRigmMovieSession; Embedded: Boolean=False);
    // タイマーと再生を止めて表示部品を解放する。借用セッションは解放しない。
    destructor Destroy; override;
    property Session: TRigmMovieSession read FSession; // 借用参照。セッションの所有者は呼び出し側。
    property PreviewControl: TRigmMoviePreview read GetPreviewControl; // 表示倍率や選択を操作する非所有参照。
    property OnOpenWork: TRigmOpenMovieFile read FOnOpenWork write FOnOpenWork; // 別作品をワークスペースへ開く要求。
  protected
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
    procedure Resize; override;
  end;
// Menuへ制作操作を追加する。操作はHandlerへ通知する互換入口。
procedure PopulateMovieMenus(Menu: TMainMenu; Handler: TNotifyEvent);

implementation
{$R *.dfm}
uses System.IOUtils, System.Math, System.StrUtils, System.UITypes,
  Winapi.Messages, Winapi.MMSystem, Winapi.ShellAPI, Vcl.Dialogs, RigmModel, RigmJson, RigmMovieModel,
  RigmMovieAudio, RigmToolbarIcons, RigmMovieOutput, RigmMoviePreparation, RigmAppSettings, RigmMovieWorkspace,
  RigmMovieActing, RigmMovieChart, RigmMovieMenus, RigmMovieUiValues, RigmMovieJobPresentation, RigmMovieEndingDialog;

procedure PopulateMovieMenus(Menu: TMainMenu; Handler: TNotifyEvent);
begin RigmMovieMenus.PopulateMovieMenus(Menu,Handler); end;

constructor TRigmMovieEditorFrame.CreateForSession(AOwner: TComponent; Session: TRigmMovieSession; Embedded: Boolean);
begin
  inherited Create(AOwner); Align := alClient; FSession := Session; Caption := 'RIGM Maker — 動画制作';
  Name := 'MovieStudio'+IntToHex(NativeUInt(Self),16); Width := 1380; Height := 900;
  Constraints.MinWidth := 0; Constraints.MinHeight := 0;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10; DoubleBuffered := True;
  FDrawnFrame := -1; FDrawnRevision := -1; 
  FSelectedId := FSession.ResumeCue; FPendingPreview := FSession.Project.Cues.Count>0;
  FLayoutPPI := 96;
  FAssets := TJSONObject.Create; BuildUI; FUi.Preview.Session := Session;
  FUi.Toolbar.Visible := True; FUi.ScriptPanel.Visible := True; RefreshView;
  var Operations := TButton.Create(Self); Operations.Parent := Self; Operations.Align := alTop; Operations.Height := 30;
  Operations.Name := 'MovieOperations'; Operations.Caption := 'ファイル・編集・制作の操作'; Operations.OnClick := ShowOperations;
  var Menu := TPopupMenu.Create(Self); Menu.Name := 'MovieOperationsMenu';
  RigmMovieMenus.PopulateMovieMenus(Menu,ActionClick); Operations.PopupMenu := Menu;
  if (Session.Project.ScriptWizard<>nil) and (Session.Project.ScriptWizard.GetValue('closingData')<>nil) then
    FUi.Toolbar.AddIcon('MovieEndingEdit','締め画像・終了区間を編集',riPreview,0,EditEnding);
end;
procedure TRigmMovieEditorFrame.EditEnding(Sender: TObject);
begin
  if (FDraftRevision<>0) or FSession.GuiLocked then begin ShowMessage('入力を適用し、編集ロックを完了してから締め設定を開いてください。'); Exit; end;
  StopPlayback; var P := FSession.Project.Clone; var D := TRigmMovieEndingDialog.CreateForProject(Self,P);
  try
    while D.ShowModal=mrOk do begin
      var A := TJSONObject.Create;
      try A.AddPair('projectId',P.Id); AddN(A,'revision',P.Revision); A.AddPair('draft',D.Draft);
        try var R := FSession.Execute('update-ending',A); R.Free; RefreshView; Break;
        except on E: Exception do ShowMessage(E.Message); end;
      finally A.Free; end;
    end;
  finally D.Free; P.Free; end;
end;
procedure TRigmMovieEditorFrame.ShowOperations(Sender: TObject);
begin
  var Button := TButton(Sender); var P := Button.ClientToScreen(Point(0,Button.Height));
  Button.PopupMenu.Popup(P.X,P.Y);
end;
destructor TRigmMovieEditorFrame.Destroy;
begin
  if (FUi<>nil) and (FUi.Timer<>nil) then begin FUi.Timer.Enabled := False; StopPlayback; end;
  FAssets.Free; FreeAndNil(FExport); FreeAndNil(FUi);
  inherited;
end;
procedure TRigmMovieEditorFrame.BuildUI;
var Callbacks: TRigmMovieUiCallbacks;
begin
  FUi := TRigmMovieControls.Create(Self);
  Callbacks.ActionClick := ActionClick;
  Callbacks.OutputPresetChanged := OutputPresetChanged;
  Callbacks.PaintJobProgress := PaintJobProgress;
  Callbacks.TimelineSeek := TimelineSeek;
  Callbacks.TimelineSelectCue := TimelineSelectCue;
  Callbacks.ZoomChanged := ZoomChanged;
  Callbacks.SeekChanged := SeekChanged;
  Callbacks.LayoutProperties := LayoutProperties;
  Callbacks.DraftEdited := DraftEdited;
  Callbacks.SelectSpeaker := SelectSpeaker;
  Callbacks.VariantGroupChanged := VariantGroupChanged;
  Callbacks.SplitterBeforeResize := SplitterBeforeResize;
  Callbacks.SplitterCanResize := SplitterCanResize;
  Callbacks.SplitterAfterResize := SplitterAfterResize;
  Callbacks.EditingAreaResize := EditingAreaResize;
  Callbacks.SelectCue := SelectCue;
  Callbacks.ApplicationMessage := ApplicationMessage;
  Callbacks.Tick := Tick;
  FUi.Build(Callbacks);
  FExport := TRigmMovieExportFeedback.Create(Self,FSession,FUi);
  SelectPropertyPage('dialogue'); LayoutProperties(Self); Resize;
end;
function TRigmMovieEditorFrame.GetPreviewControl: TRigmMoviePreview;
begin Result := FUi.Preview; end;
function TRigmMovieEditorFrame.GetPropertyLayouts: Integer;
begin Result := FUi.Pages.LayoutCount; end;
function TRigmMovieEditorFrame.PropertyPageName: string;
begin Result := FUi.Pages.PropertyPageName; end;
procedure TRigmMovieEditorFrame.SelectPropertyPage(const Page: string);
begin FUi.Pages.SelectPropertyPage(Page); end;
procedure TRigmMovieEditorFrame.LayoutProperties(Sender: TObject);
begin
  if (FUi=nil) or (FUi.Pages=nil) then Exit;
  if FSplitterDragging then begin FPendingSplitterLayout := True; Exit; end;
  FUi.Pages.LayoutProperties(Sender);
end;
procedure TRigmMovieEditorFrame.InvokeAction(Action: Integer);
begin
  var Proxy := TComponent.Create(nil);
  try Proxy.Tag := Action; ActionClick(Proxy); finally Proxy.Free; end;
end;
procedure TRigmMovieEditorFrame.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin
  inherited;
  if (FUi<>nil) and (FUi.Pages<>nil) then FUi.Pages.ChangeScale(M,D,isDpiChange);
  if isDpiChange then FLayoutPPI := M else FLayoutPPI := MulDiv(FLayoutPPI,M,D);
  EditingAreaResize(Self);
  LayoutProperties(Self);
end;
procedure TRigmMovieEditorFrame.Resize;
begin
  inherited;
  if (FUi=nil) then Exit;
  if (FUi.Bottom=nil) or (FUi.Timeline=nil) or (FLayoutPPI=0) then Exit;
  EditingAreaResize(Self);
  LayoutProperties(Self);
  LayoutTransport;
end;
procedure TRigmMovieEditorFrame.SplitterBeforeResize(Sender: TObject);
begin
  var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  if Sender=FUi.TimelineSplitter then FUi.TimelineSplitter.MinSize := MulDiv(165,PPI,96)
  else if Sender=FUi.PropertySplitter then FUi.PropertySplitter.MinSize := MulDiv(220,PPI,96);
  FSplitterDragging := True; FUi.Pages.Paused := True;
  FUi.Preview.SetLayoutDragging(True); FUi.Timeline.SetLayoutDragging(True);
end;
procedure TRigmMovieEditorFrame.SplitterAfterResize(Sender: TObject);
begin
  if not FSplitterDragging then Exit;
  FSplitterDragging := False; FUi.Pages.Paused := False;
  if FPendingSplitterLayout then begin
    FPendingSplitterLayout := False; EditingAreaResize(Self); LayoutProperties(Self);
  end;
  FUi.Preview.SetLayoutDragging(False); FUi.Timeline.SetLayoutDragging(False);
end;
procedure TRigmMovieEditorFrame.SplitterCanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
begin
  if Sender=FUi.TimelineSplitter then begin
    NewSize := Max(NewSize,FUi.TimelineSplitter.MinSize);
    Accept := Accept and (NewSize<=FUi.EditHost.ClientHeight-FUi.TimelineSplitter.Height-FUi.TimelineSplitter.MinSize);
  end else if Sender=FUi.PropertySplitter then begin
    NewSize := Max(NewSize,FUi.PropertyHost.Constraints.MinWidth);
    Accept := Accept and (NewSize<=ClientWidth-FUi.PropertySplitter.Width-FUi.PropertySplitter.MinSize);
  end;
  // Each splitter changes only its own target. No opposite-axis size is restored.
end;
procedure TRigmMovieEditorFrame.EditingAreaResize(Sender: TObject);
begin
  if FUi=nil then Exit;
  if FEditingLayout or (FUi.EditHost=nil) or (FUi.EditScroll=nil) or (FUi.Preview=nil) then Exit;
  FEditingLayout := True;
  try
    var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
    if not FSplitterDragging then begin
      var Thickness := MulDiv(10,PPI,96);
      if (FUi.PropertySplitter<>nil) and (FUi.PropertySplitter.Width<>Thickness) then FUi.PropertySplitter.Width := Thickness;
      if (FUi.TimelineSplitter<>nil) and (FUi.TimelineSplitter.Height<>Thickness) then FUi.TimelineSplitter.Height := Thickness;
    end;
    var MinimumW := MulDiv(240,PPI,96);
    if FUi.ScriptPanel.Visible then Inc(MinimumW,FUi.ScriptPanel.Width);
    var MinimumH := Max(MulDiv(340,PPI,96),MulDiv(165,PPI,96)*2+FUi.TimelineSplitter.Height);
    var W := Max(FUi.EditScroll.ClientWidth,MinimumW); var H := Max(FUi.EditScroll.ClientHeight,MinimumH);
    FUi.EditHost.SetBounds(-FUi.EditScroll.HorzScrollBar.Position,-FUi.EditScroll.VertScrollBar.Position,W,H);
    FUi.EditScroll.HorzScrollBar.Range := W; FUi.EditScroll.VertScrollBar.Range := H;
    LayoutTransport;
  finally FEditingLayout := False; end;
end;
procedure TRigmMovieEditorFrame.DraftEdited(Sender: TObject);
begin
  if FRefreshing then Exit;
  if FDraftRevision=0 then begin
    FillChar(FPropertyDrafts,SizeOf(FPropertyDrafts),0); FOtherDraft := False;
    FPoseDraft := False; FActingDraft := False; FSceneDraft := False; FChartDraft := False;
    // Stamp the data actually displayed, even before the next timer refresh.
    FDraftRevision := FLastRevision;
    if FDraftRevision=0 then FDraftRevision := FSession.Project.Revision;
    FOnlyTextDraft := (FSession.Project.Scenes.Count>0) and ((Sender=FUi.Dialogue) or (Sender=FUi.Subtitle));
  end;
  var Found := False;
  for var Field in FUi.Pages.Fields do if Field.Control=Sender then begin FPropertyDrafts[Field.Page] := True; Found := True; Break; end;
  if not Found then FOtherDraft := True;
  if (Sender=FUi.Expression) or (Sender=FUi.Motion) or (Sender=FUi.Emotion) then FPoseDraft := True
  else if Found and FPropertyDrafts[2] then begin
    for var Field in FUi.Pages.Fields do
      if (Field.Control=Sender) and (Field.Page=2) then begin FActingDraft := True; Break; end;
  end;
  if (Sender=FUi.ChartKind) or (Sender=FUi.ChartTitle) or (Sender=FUi.ChartMaximum) or
    (Sender=FUi.ChartItems) or (Sender=FUi.ChartColor) then FChartDraft := True
  else if (Sender=FUi.SceneTitle) or (Sender=FUi.SceneDescription) or (Sender=FUi.LayoutChoice) then FSceneDraft := True;
  if (Sender=FUi.Dialogue) or (Sender=FUi.Subtitle) then FTextPending := True else FOnlyTextDraft := False;
end;
function TRigmMovieEditorFrame.Command(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try
    var Editing := MatchText(Name,['update-project','update-cue','update-speaker','update-scene','import-script']);
    if MatchText(Name,['workflow-next','workflow-back']) and (FDraftRevision<>0) then
      raise ERigm.Create('未適用の編集を適用してから工程を移動してください。');
    var Revision := FSession.Project.Revision;
    if Editing and (FDraftRevision<>0) then Revision := FDraftRevision;
    Args.AddPair('projectId',FSession.Project.Id); AddN(Args,'revision',Revision);
    Result := FSession.Execute(Name,Args);
    if Editing then begin FDraftRevision := 0; FTextPending := False; FOnlyTextDraft := False; FUi.ReloadDraft.Visible := False; end;
  finally Args.Free; end;
end;
procedure TRigmMovieEditorFrame.Run(const Name: string; Args: TJSONObject);
var Reply: TJSONObject;
begin Reply := Command(Name,Args); Reply.Free; end;
procedure TRigmMovieEditorFrame.RefreshCue;
var C: TRigmMovieCue; WasRefreshing: Boolean;
begin
  WasRefreshing := FRefreshing; FRefreshing := True;
  try
  C := FSession.Project.Cue(FSelectedId);
  if C=nil then begin
    FUi.SceneTitle.Clear; FUi.SceneDescription.Clear; FUi.Emotion.Items.Clear;
    FUi.Scene.Clear; FUi.Pause.Clear; FUi.Dialogue.Clear; FUi.Subtitle.Clear; FUi.Speed.Clear; FUi.Pitch.Clear;
    FUi.Style.ItemIndex := -1; FUi.Speaker.ItemIndex := -1; FUi.Expression.ItemIndex := -1; FUi.Motion.ItemIndex := -1;
    for var E in FUi.Acting do E.Clear;
    Exit;
  end;
  FUi.Scene.Text := C.Scene; FUi.Pause.Text := FloatToStr(C.Pause,TFormatSettings.Invariant);
  var Scene := FSession.Project.Scene(C.Scene);
  if Scene<>nil then begin FUi.SceneTitle.Text := Scene.Title; FUi.SceneDescription.Text := Scene.Description; end
  else begin FUi.SceneTitle.Clear; FUi.SceneDescription.Clear; end;
  FUi.ChartKind.ItemIndex := 0; FUi.ChartTitle.Text := '総評'; FUi.ChartMaximum.Text := '5'; FUi.ChartItems.Clear;
  FUi.ChartColor.Selected := RGB(90,184,232);
  if (Scene<>nil) and MovieChartEnabled(Scene.Chart) then begin
    FUi.ChartKind.ItemIndex := IndexText(JS(Scene.Chart,'kind','none'),['none','radar','bar']);
    FUi.ChartTitle.Text := JS(Scene.Chart,'title','総評'); FUi.ChartMaximum.Text := FloatToStr(JN(Scene.Chart,'maximum',5),TFormatSettings.Invariant);
    if Scene.Chart.GetValue('items') is TJSONArray then for var V in JA(Scene.Chart,'items') do begin
      var Item := TJSONObject(V); FUi.ChartItems.Lines.Add(JS(Item,'label')+' = '+FloatToStr(JN(Item,'value'),TFormatSettings.Invariant));
    end;
    var ColorValue := StrToInt('$'+Copy(JS(Scene.Chart,'color','#5AB8E8'),2,6));
    FUi.ChartColor.Selected := RGB((ColorValue shr 16) and 255,(ColorValue shr 8) and 255,ColorValue and 255);
  end;
  FUi.Emotion.Items.Clear; FUi.Emotion.ItemIndex := -1;
  for var I := 0 to High(MovieEmotionIds) do begin
    var Available := (MovieEmotionIds[I]='neutral') or (MovieEmotionIds[I]=C.Emotion);
    for var Character in FSession.Project.Characters do if (Character.SpeakerId=C.SpeakerId) and
      (Character.Expressions.GetValue(MovieEmotionIds[I])<>nil) then Available := True;
    if Available then begin
      FUi.Emotion.Items.AddObject(MovieEmotionLabels[I],TObject(NativeInt(I)));
      if MovieEmotionIds[I]=C.Emotion then FUi.Emotion.ItemIndex := FUi.Emotion.Items.Count-1;
    end;
  end;
  FUi.LayoutChoice.ItemIndex := 0;
  if FSession.Project.Layout='l' then
    if FSession.Project.LDirection='left' then FUi.LayoutChoice.ItemIndex := 1 else FUi.LayoutChoice.ItemIndex := 2;
  FUi.WholeMotionStatus.Caption := '通常の演技（口パク・瞬きあり）';
  for var Character in FSession.Project.Characters do if
    (Character.SpeakerId=C.SpeakerId) and (Character.ActiveMotion<>'') then
    FUi.WholeMotionStatus.Caption := '全体モーション: '+Character.ActiveMotion+'（口パク・瞬きを停止）';
  FUi.Dialogue.Text := C.Text; FUi.Subtitle.Text := C.Subtitle;
  FUi.Speaker.ItemIndex := FUi.Speaker.Items.IndexOf(C.SpeakerId); FUi.Expression.ItemIndex := FUi.Expression.Items.IndexOf(C.Expression);
  FUi.Motion.ItemIndex := FUi.Motion.Items.IndexOf(C.Motion); SelectSpeaker(Self);
  var O := C.Acting.Json;
  FUi.ImageAttention.ItemIndex := IndexText(C.Acting.ImageAttention,['auto','off','head']);
  try
    for var I := 0 to 11 do FUi.Acting[I].Text := FloatToStr(JN(O,MovieActingKeys[I]),TFormatSettings.Invariant);
  finally O.Free; end;
  for var I := 0 to 2 do begin
    if FeatureModeIds[I]=C.Acting.MouthMode then FUi.MouthMode.ItemIndex := I;
    if FeatureModeIds[I]=C.Acting.BlinkMode then FUi.BlinkMode.ItemIndex := I;
  end;
  VariantGroupChanged(Self);
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieEditorFrame.RefreshView;
var Start: Double; O: TJSONObject; Catalog: TJSONArray;
begin
  if FDraftRevision<>0 then begin
    if FUi.ReloadDraft.Visible<>(FDraftRevision<>FSession.Project.Revision) then begin
      FUi.ReloadDraft.Visible := FDraftRevision<>FSession.Project.Revision; LayoutProperties(Self);
    end;
    if FUi.ReloadDraft.Visible then FUi.Status.Caption := '別操作で更新されています。未適用入力を保持しました。最新データを読み込んで再調整してください。';
    Exit;
  end;
  Inc(FViewRefreshCount);
  if FViewedProject<>FSession.Project.Id then begin FSelectedId := FSession.ResumeCue; FDrawnFrame := -1; FPendingPreview := FSession.Project.Cues.Count>0;
    FExport.ClearProject;
    FUi.Timeline.ResetView; FUi.Preview.Fit; FViewedProject := FSession.Project.Id; end;
  FRefreshing := True;
  try
    FUi.Title.Text := FSession.Project.Title; FUi.Engine.Text := FSession.Project.EngineUrl; FUi.Character.Text := FSession.Project.CharacterFile;
    FUi.Dimensions.Text := Format('%d × %d × %d',[FSession.Project.Width,FSession.Project.Height,FSession.Project.Fps]);
    for var I := 0 to 3 do if OutputPresetIds[I]=MoviePresetId(FSession.Project.Width,FSession.Project.Height,FSession.Project.Fps) then FUi.OutputPreset.ItemIndex := I;
    for var I := 0 to 2 do if EncodeProfileIds[I]=FSession.Project.EncodeProfile then FUi.EncodeProfile.ItemIndex := I;
    FUi.OutputPath.Text := FSession.Project.OutputTarget;
    FUi.Speaker.Items.Clear; for var S in FSession.Project.Speakers do FUi.Speaker.Items.Add(S.Id);
    FUi.List.Items.BeginUpdate;
    try
      FUi.List.Items.Clear;
      for var C in FSession.Project.Cues do begin
        Start := FSession.Project.CueStart(C);
        var Item := FUi.List.Items.Add; Item.Caption := FormatFloat('0.0',Start,TFormatSettings.Invariant);
        Item.SubItems.Add(C.Text); if FSession.Project.AudioReady(C) then Item.SubItems.Add('生成済') else Item.SubItems.Add('未生成');
        Item.SubItems.Add(C.Id); // Stable metadata; the third subitem has no visible column.
        if C.Id=FSelectedId then Item.Selected := True;
      end;
      if (FUi.List.Selected=nil) and (FUi.List.Items.Count>0) then begin FUi.List.Items[0].Selected := True; FSelectedId := FUi.List.Items[0].SubItems[2]; end;
    finally FUi.List.Items.EndUpdate; end;
    O := Command('speaker-list');
    try
      Catalog := JA(O,'styles'); var Key := Catalog.ToJSON;
      if Key<>FCatalogKey then begin
        FCatalogKey := Key; FUi.Style.Items.Clear;
        for var V in Catalog do begin var S := TJSONObject(V); FUi.Style.Items.AddObject(JS(S,'name')+' / '+JS(S,'style'),TObject(NativeInt(JI(S,'styleId')))); end;
      end;
    finally O.Free; end;
    RefreshCue;
    O := Command('assets');
    try
      var SelectedGroup := FUi.VariantGroup.Text;
      FAssets.Free; FAssets := O.Clone as TJSONObject; FUi.VariantGroup.Items.Clear;
      if O.GetValue('groups')<>nil then for var V in JA(O,'groups') do FUi.VariantGroup.Items.Add(JS(TJSONObject(V),'name'));
      FUi.VariantGroup.ItemIndex := FUi.VariantGroup.Items.IndexOf(SelectedGroup);
      if (FUi.VariantGroup.ItemIndex<0) and (FUi.VariantGroup.Items.Count>0) then FUi.VariantGroup.ItemIndex := 0;
      VariantGroupChanged(Self);
    finally O.Free; end;
    O := Command('timeline'); var Wave := Command('waveform');
    try FUi.Timeline.SetData(O,Wave); FUi.Timeline.SetTime(FSession.Time); FUi.Timeline.SelectCue(FSelectedId); finally O.Free; Wave.Free; end;
    RefreshSeek;
    FLastRevision := FSession.Project.Revision;
    TToolButton(FUi.Toolbar.FindComponent('MovieUndo')).Enabled := not FSession.Busy;
    TToolButton(FUi.Toolbar.FindComponent('MovieRedo')).Enabled := not FSession.Busy;
  finally FRefreshing := False; end;
end;
procedure TRigmMovieEditorFrame.SelectCue(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FRefreshing or not Selected or (Item.SubItems.Count<3) then Exit;
  if FDraftRevision<>0 then begin
    FRefreshing := True;
    try
      Item.Selected := False;
      for var I := 0 to FUi.List.Items.Count-1 do
        if (FUi.List.Items[I].SubItems.Count>=3) and (FUi.List.Items[I].SubItems[2]=FSelectedId) then FUi.List.Items[I].Selected := True;
    finally FRefreshing := False; end;
    Exit;
  end;
  FSelectedId := Item.SubItems[2]; RefreshCue;
  FUi.Timeline.SelectCue(FSelectedId);
end;
procedure TRigmMovieEditorFrame.TimelineSelectCue(Sender: TObject);
begin
  if FDraftRevision<>0 then begin FUi.Timeline.SelectCue(FSelectedId); Exit; end;
  for var I := 0 to FUi.List.Items.Count-1 do
    if (FUi.List.Items[I].SubItems.Count>=3) and (FUi.List.Items[I].SubItems[2]=FUi.Timeline.SelectedCueId) then begin
      FUi.List.Items[I].Selected := True; FUi.List.Items[I].MakeVisible(False); Exit;
    end;
end;
procedure TRigmMovieEditorFrame.SelectSpeaker(Sender: TObject);
var S: TRigmMovieSpeaker; WasRefreshing: Boolean;
begin
  WasRefreshing := FRefreshing; FRefreshing := True;
  try
  S := FSession.Project.Speaker(FUi.Speaker.Text); if S=nil then Exit;
  FUi.Speed.Text := FloatToStr(S.Speed,TFormatSettings.Invariant); FUi.Pitch.Text := FloatToStr(S.Pitch,TFormatSettings.Invariant); FUi.Style.ItemIndex := -1;
  for var I := 0 to FUi.Style.Items.Count-1 do if NativeInt(FUi.Style.Items.Objects[I])=S.StyleId then FUi.Style.ItemIndex := I;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieEditorFrame.SeekChanged(Sender: TObject);
begin
  if FRefreshing then Exit; SeekFrame(FUi.Seek.Position);
end;
procedure TRigmMovieEditorFrame.TimelineSeek(Sender: TObject);
begin
  SeekFrame(Round(FUi.Timeline.Time*Max(1,FSession.Project.Fps)));
end;
procedure TRigmMovieEditorFrame.SeekFrame(Frame: Integer);
begin
  StopPlayback;
  var FPS := Max(1,FSession.Project.Fps);
  var Last := Max(0,Ceil(Min(High(Integer)-1.0,FSession.Project.Duration*FPS))-1);
  var O := TJSONObject.Create; AddN(O,'time',EnsureRange(Frame,0,Last)/FPS); Run('seek',O);
  FPendingPreview := True; FSeekTick := GetTickCount64;
  FUi.Timeline.SetTime(FSession.Time); RefreshSeek;
end;
procedure TRigmMovieEditorFrame.RefreshSeek;
begin
  if FUi.Seek=nil then Exit;
  var WasRefreshing := FRefreshing; FRefreshing := True;
  try
    var FPS := Max(1,FSession.Project.Fps);
    var Last := Max(0,Ceil(Min(High(Integer)-1.0,FSession.Project.Duration*FPS))-1);
    var Frame := EnsureRange(Floor(FSession.Time*FPS+0.000001),0,Last);
    if FUi.Seek.Max<>Max(1,Last) then FUi.Seek.Max := Max(1,Last);
    FUi.Seek.Enabled := FSession.Project.Duration>0;
    if FUi.Seek.Position<>Frame then FUi.Seek.Position := Frame;
    var Text := Format('フレーム %d / %d  %.2f秒',[Frame,Last,FSession.Time]);
    if FUi.FramePosition.Caption<>Text then begin FUi.FramePosition.Caption := Text; FUi.FramePosition.Hint := Text; end;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieEditorFrame.ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if Handled or (Msg.message<>WM_MOUSEWHEEL) or not Showing or not Enabled then Exit;
  var Host := GetParentForm(Self,True); if (Host<>nil) and not Host.Enabled then Exit;
  var P := Point(SmallInt(LoWord(Msg.lParam)),SmallInt(HiWord(Msg.lParam)));
  var Hover := WindowFromPoint(P); var Delta := SmallInt(HiWord(Msg.wParam));
  if FUi.Preview.HandleAllocated and ((Hover=FUi.Preview.Handle) or IsChild(FUi.Preview.Handle,Hover)) then begin
    FUi.Preview.WheelAt(Delta,FUi.Preview.ScreenToClient(P)); Handled := True;
  end else if FUi.Timeline.HandleAllocated and ((Hover=FUi.Timeline.Handle) or IsChild(FUi.Timeline.Handle,Hover)) then begin
    FUi.Timeline.WheelAt(Delta,FUi.Timeline.ScreenToClient(P)); Handled := True;
  end else if FUi.Seek.Enabled and FUi.Seek.HandleAllocated and (Hover=FUi.Seek.Handle) then begin
    FUi.Seek.AdjustWheel(Delta); Handled := True;
  end;
end;
procedure TRigmMovieEditorFrame.ZoomChanged(Sender: TObject);
const Spans: array[0..3] of Double = (0,10,30,60);
begin if FUi.Zoom.ItemIndex>=0 then FUi.Timeline.SetSpan(Spans[FUi.Zoom.ItemIndex]); end;
procedure TRigmMovieEditorFrame.OutputPresetChanged(Sender: TObject);
var W,H,F: Integer;
begin
  if FRefreshing or (FUi.OutputPreset.ItemIndex<0) then Exit;
  DraftEdited(Sender);
  MoviePresetDimensions(OutputPresetIds[FUi.OutputPreset.ItemIndex],W,H,F);
  if W>0 then FUi.Dimensions.Text := Format('%d x %d x %d',[W,H,F]);
end;
procedure TRigmMovieEditorFrame.PaintJobProgress(Sender: TObject);
begin
  FUi.JobProgress.Canvas.Brush.Color := clBtnShadow; FUi.JobProgress.Canvas.FillRect(FUi.JobProgress.ClientRect);
  FUi.JobProgress.Canvas.Brush.Color := $D09040;
  FUi.JobProgress.Canvas.FillRect(Rect(0,0,Round(FUi.JobProgress.Width*FJobPosition/1000),FUi.JobProgress.Height));
end;
procedure TRigmMovieEditorFrame.RefreshPreparation;
var O,A,J: TJSONObject; Lines: TStringList; Guide,Key: string; WasRefreshing: Boolean;
begin
  if FClosing then Exit;
  WasRefreshing := FRefreshing; FRefreshing := True;
  try
  Key := MoviePreparationKey(FSession.Project);
  A := TJSONObject.Create; A.AddPair('scope','diagnostics'); J := Command('job-status',A);
  try
    if ((FAutoDiagnosticKey<>Key) or (JS(J,'state')='none')) and JB(J,'done',True) then begin
      Run('diagnostics-refresh'); FAutoDiagnosticKey := Key;
    end else if (FAutoDiagnosticKey<>Key) and not JB(J,'done',True) then begin
      A := TJSONObject.Create; A.AddPair('scope','diagnostics'); Run('job-cancel',A);
    end;
    Key := IntToStr(FSession.Project.Revision)+'|'+FSession.Project.WorkflowStage+'|'+BoolToStr(FSession.Project.Modified,True)+'|'+
      IntToStr(FDraftRevision)+'|'+FUi.OutputPath.Text+'|'+JS(J,'jobId')+'|'+JS(J,'state');
  finally J.Free; end;
  if FPreparationStamp=Key then Exit;
  FPreparationStamp := Key;
  Inc(FStaticUiUpdates);
  A := TJSONObject.Create; A.AddPair('outputPath',FUi.OutputPath.Text); O := Command('preparation',A);
  Lines := TStringList.Create;
  try
    Guide := '';
    for var V in JA(O,'steps') do begin
      J := TJSONObject(V);
      if Guide<>'' then Guide := Guide+' → ';
      Guide := Guide+IfThen(JB(J,'ready'),'✓ ','')+JS(J,'title');
    end;
    var Workflow := Command('workflow-status');
    try
      FUi.Workflow.Caption := '現在の工程: '+JS(Workflow,'title')+sLineBreak+JS(Workflow,'message');
      FUi.Next.Enabled := JB(Workflow,'canNext') and (FDraftRevision=0);
      FUi.RunStep.Enabled := JB(Workflow,'canRun') and ((FDraftRevision=0) or (JS(Workflow,'currentStage')='script'));
      FUi.BackStep.Enabled := JB(Workflow,'canBack') and (FDraftRevision=0);
      for var V in JA(Workflow,'needs') do begin var Need := TJSONObject(V); Lines.Add('['+JS(Need,'code')+'] '+JS(Need,'message')); end;
    finally Workflow.Free; end;
    J := JO(O,'diagnosticsJob');
    if JB(O,'diagnosticsBusy') then Lines.Add('接続・素材を読取診断中。台本の編集は続けられます。');
    Lines.Add('診断は読取のみ。接続成功は話者一覧の取得までです。実音声の確認を意味しません。');
    for var V in JA(O,'issues') do begin
      A := TJSONObject(V); Lines.Add('['+JS(A,'code')+'] '+JS(A,'message'));
    end;
    A := JO(O,'capabilities');
    Lines.Add('顔向き: 自然な横・後ろ向きは生成しません。既存の差分だけ利用します。');
    Lines.Add('口差分: '+IfThen(JB(A,'mouthAssets'),'あり','なし / 自動または変形を利用'));
    Lines.Add('瞬き差分: '+IfThen(JB(A,'blinkAssets'),'あり','なし / 自動または変形を利用'));
    Lines.Add('頭・上半身: '+IfThen(JB(A,'headBodyMotion'),'ボーンとメッシュあり','静止表示 / 既存ポーズ差分'));
    A := JO(O,'estimate');
    Lines.Add(Format('概算: 動画 %.1f秒 / 出力 %.0f秒 / 一時容量 %.0f MB / 空き %.0f MB',
      [JN(A,'durationSeconds'),JN(A,'exportSeconds'),JN(A,'stagingBytes')/1048576,JN(A,'freeBytes')/1048576]));
    Lines.Add('時間・容量は素材とPCで変わる目安です。書込権限とFFmpeg起動・コーデックはこの読取診断では確認しません。');
    if FUi.Preparation.Text<>Lines.Text then FUi.Preparation.Text := Lines.Text;
    // Refresh only catalog/asset selectors: do not overwrite pending editor text.
    if JB(J,'done',True) and (FSeenDiagnostic<>JS(J,'jobId')) then begin
      FSeenDiagnostic := JS(J,'jobId');
      A := Command('speaker-list');
      try
        var Catalog := JA(A,'styles'); var CatalogKey := Catalog.ToJSON;
        if CatalogKey<>FCatalogKey then begin
          var StyleId: NativeInt := -1;
          if FUi.Style.ItemIndex>=0 then StyleId := NativeInt(FUi.Style.Items.Objects[FUi.Style.ItemIndex]);
          FCatalogKey := CatalogKey; FUi.Style.Items.Clear;
          for var V in Catalog do begin var S := TJSONObject(V); FUi.Style.Items.AddObject(JS(S,'name')+' / '+JS(S,'style'),TObject(NativeInt(JI(S,'styleId')))); end;
          if StyleId<0 then begin var S := FSession.Project.Speaker(FUi.Speaker.Text); if S<>nil then StyleId := S.StyleId; end;
          for var I := 0 to FUi.Style.Items.Count-1 do if NativeInt(FUi.Style.Items.Objects[I])=StyleId then FUi.Style.ItemIndex := I;
        end;
      finally A.Free; end;
      A := Command('assets');
      try
        var GroupName := FUi.VariantGroup.Text;
        FAssets.Free; FAssets := A.Clone as TJSONObject; FUi.VariantGroup.Items.Clear;
        if A.GetValue('groups')<>nil then for var V in JA(A,'groups') do FUi.VariantGroup.Items.Add(JS(TJSONObject(V),'name'));
        FUi.VariantGroup.ItemIndex := FUi.VariantGroup.Items.IndexOf(GroupName);
        if (FUi.VariantGroup.ItemIndex<0) and (FUi.VariantGroup.Items.Count>0) then FUi.VariantGroup.ItemIndex := 0;
        VariantGroupChanged(Self);
      finally A.Free; end;
    end;
    var Cancel := TToolButton(FUi.Toolbar.FindComponent('MovieCancel'));
    Cancel.Enabled := FSession.Busy or JB(O,'diagnosticsBusy');
  finally Lines.Free; O.Free; end;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieEditorFrame.VariantGroupChanged(Sender: TObject);
begin
  FUi.Variant.Items.Clear; FUi.Variant.Items.Add('保存済みの表示状態'); FUi.Variant.ItemIndex := 0;
  if (FUi.VariantGroup.ItemIndex<0) or (FAssets.GetValue('groups')=nil) then Exit;
  var Group := TJSONObject(JA(FAssets,'groups')[FUi.VariantGroup.ItemIndex]);
  for var V in JA(Group,'children') do FUi.Variant.Items.Add(JS(TJSONObject(V),'name')+' ['+JS(TJSONObject(V),'role')+']');
  var C := FSession.Project.Cue(FSelectedId); if C=nil then Exit;
  for var V in C.Acting.Variants do if JS(TJSONObject(V),'groupId')=JS(Group,'id') then
    for var I := 0 to JA(Group,'children').Count-1 do if JS(TJSONObject(JA(Group,'children')[I]),'id')=JS(TJSONObject(V),'partId') then FUi.Variant.ItemIndex := I+1;
end;
procedure TRigmMovieEditorFrame.StartPlayback;
begin
  if FSession.Busy then Exit;
  FPlaying := True; FTick := GetTickCount64; FStartTime := FSession.Time; FAudioReady := False;
  var Ready := FSession.Project.Cues.Count>0;
  for var C in FSession.Project.Cues do if not FSession.Project.AudioReady(C) and not
    ((FSession.Project.Scenes.Count>0) and FSession.Project.HasStoredAudio(C)) then Ready := False;
  FAudioPreparing := Ready;
  if Ready then begin var O := TJSONObject.Create; AddN(O,'time',FStartTime); Run('playback-audio',O); end
  else FAudioReady := True; // Visual timing is estimated until real audio exists.
end;
procedure TRigmMovieEditorFrame.StopPlayback;
begin
  if FPlaying then begin FPlaying := False; sndPlaySound(nil,SND_ASYNC); end;
  if (FSession<>nil) and FSession.Playing then Run('pause'); FAudioReady := False;
  FAudioPreparing := False; RefreshTransport;
end;
procedure TRigmMovieEditorFrame.RefreshTransport;
begin
  if FUi.PlayButton=nil then Exit;
  var CanPlay := not FSession.Playing and not FAudioPreparing and FSession.CanEdit and (FSession.Project.Cues.Count>0);
  var CanStop := FSession.Playing or FPlaying or FAudioPreparing;
  if FUi.PlayButton.Enabled<>CanPlay then FUi.PlayButton.Enabled := CanPlay;
  if FUi.StopButton.Enabled<>CanStop then FUi.StopButton.Enabled := CanStop;
  var CanExport := FSession.CanEdit and not FSession.GuiLocked and (FSession.Project.Cues.Count>0);
  if FUi.ExportButton.Enabled<>CanExport then FUi.ExportButton.Enabled := CanExport;
end;
procedure TRigmMovieEditorFrame.LayoutTransport;
begin
  if (FUi=nil) or (FUi.ExportButton=nil) then Exit;
  if FSplitterDragging then begin FPendingSplitterLayout := True; Exit; end;
  var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  var P := MulDiv(8,PPI,96); var W := MulDiv(96,PPI,96); var H := MulDiv(28,PPI,96);
  var Y := MulDiv(8,PPI,96); var ExportW := MulDiv(130,PPI,96); var FitW := MulDiv(150,PPI,96);
  FUi.Transport.SetBounds(0,0,Max(FUi.TransportScroll.ClientWidth,2*W+ExportW+FitW+P*5),H+Y*2);
  FUi.PlayButton.SetBounds(P,Y,W,H); FUi.StopButton.SetBounds(W+P*2,Y,W,H);
  FUi.ExportButton.SetBounds(W*2+P*3,Y,ExportW,H);
  FUi.FitPreview.SetBounds(W*2+ExportW+P*4,Y,FitW,H);
  FUi.TransportScroll.HorzScrollBar.Range := FUi.Transport.Width;
  FUi.TransportScroll.Height := H+Y*2+MulDiv(17,PPI,96);
  TPanel(FUi.Seek.Parent).Height := MulDiv(64,PPI,96);
  TPanel(FUi.FramePosition.Parent).Height := MulDiv(26,PPI,96);
  FUi.FramePosition.Font.Height := -MulDiv(15,PPI,96);
  FUi.Zoom.Width := MulDiv(100,PPI,96);
  LayoutExportFeedback;
end;
function TRigmMovieEditorFrame.ExportNotificationRequests: Integer;
begin Result := FUi.ExportNotification.Requests; end;
function TRigmMovieEditorFrame.ExportNotificationsShown: Integer;
begin Result := FUi.ExportNotification.Shown; end;
procedure TRigmMovieEditorFrame.LayoutExportFeedback;
begin if FExport<>nil then FExport.LayoutExportFeedback; end;
procedure TRigmMovieEditorFrame.ShowExportError(const Message: string);
begin FLastError := ''; FExport.ShowExportError(Message); end;
procedure TRigmMovieEditorFrame.RefreshExport;
begin if FExport<>nil then FExport.RefreshExport; end;
procedure TRigmMovieEditorFrame.ChooseExport(const Extension: string);
var Dialog: TSaveDialog; A,Reply: TJSONObject; Encoder: string;
begin
  StopPlayback;
  if FSession.GuiLocked then raise ERigm.Create('Codex編集中です。制作ページで編集ロックを解除してから書き出してください。');
  if not FSession.CanEdit then raise ERigm.Create('処理中のジョブが終わるか、中止してから書き出してください。');
  if FTextPending and FOnlyTextDraft and (FDraftRevision=FSession.Project.Revision) then begin
    A := TJSONObject.Create; A.AddPair('id',FSelectedId); A.AddPair('text',FUi.Dialogue.Text); A.AddPair('subtitle',FUi.Subtitle.Text); Run('update-cue',A);
  end;
  if FDraftRevision<>0 then raise ERigm.Create('未適用の編集があります。右側の適用ボタンで反映してから書き出してください。');
  FExport.Warning := '';
  for var Cue in FSession.Project.Cues do if not FSession.Project.AudioReady(Cue) then begin
    if not FSession.Project.HasStoredAudio(Cue) then raise ERigm.Create('音声が未生成です。制作メニューの「必要な音声を再生成」で作成してから書き出してください。');
    if FSession.Project.Scenes.Count=0 then raise ERigm.Create('音声用テキストの変更が未反映です。制作メニューから必要な音声を再生成してください。');
    FExport.Warning := 'セリフ変更は音声に未反映です。保存済み音声を使用しています。';
  end;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Title := UpperCase(Extension)+'動画の保存先を選ぶ'; Dialog.DefaultExt := Extension;
    if Extension='mp4' then Dialog.Filter := 'MP4動画（映像・音声） (*.mp4)|*.mp4'
    else Dialog.Filter := 'AVI動画（映像・音声） (*.avi)|*.avi';
    var Target := FSession.Project.OutputTarget;
    if Trim(Target)='' then Target := MovieDefaultExport(FSession.Project);
    Target := ChangeFileExt(Target,'.'+Extension);
    if FileExists(Target) then Target := ChangeFileExt(Target,'')+'-'+FormatDateTime('yyyymmdd-hhnnss',Now)+'.'+Extension;
    var Base := ChangeFileExt(Target,''); var Index := 1;
    while FileExists(Target) do begin Target := Base+'-'+Index.ToString+'.'+Extension; Inc(Index); end;
    ForceDirectories(ExtractFilePath(Target)); Dialog.FileName := Target;
    Dialog.Options := [ofPathMustExist,ofEnableSizing,ofNoChangeDir];
    if not Dialog.Execute then Exit;
    Target := ChangeFileExt(ExpandFileName(Dialog.FileName),'.'+Extension);
    if FileExists(Target) then raise ERigm.Create('同名の動画が既にあります。既存動画を残して別の名前を選んでください。');
    Encoder := FSession.Project.FfmpegExe;
    if (Extension='mp4') and not FileExists(Encoder) then begin
      var SelectEncoder := TOpenDialog.Create(Self);
      try
        SelectEncoder.Title := 'MP4出力に使用する既存のFFmpegを選ぶ'; SelectEncoder.Filter := 'FFmpeg (ffmpeg.exe)|ffmpeg.exe';
        SelectEncoder.Options := [ofFileMustExist,ofPathMustExist,ofNoChangeDir];
        if not SelectEncoder.Execute then Exit; Encoder := SelectEncoder.FileName;
      finally SelectEncoder.Free; end;
    end;
    FPendingPreview := False; FExport.Reset;
    A := TJSONObject.Create; A.AddPair('outputTarget',Target); A.AddPair('ffmpeg',Encoder); Run('update-project',A);
    A := TJSONObject.Create; A.AddPair('path',Target); Reply := Command('export',A);
    try FExport.BeginJob(JS(Reply,'jobId')); finally Reply.Free; end;
    FUi.ExportPanel.Visible := True; FUi.Status.Visible := False; RefreshExport;
  finally Dialog.Free; end;
end;
procedure TRigmMovieEditorFrame.PreviewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key<>VK_SPACE) or (Shift<>[]) or (Screen.ActiveControl is TCustomEdit) or (Screen.ActiveControl is TCustomCombo) then Exit;
  if FSession.Playing then StopPlayback
  else if FUi.PlayButton.Enabled then Run('play');
  RefreshTransport; Key := 0;
end;
procedure TRigmMovieEditorFrame.Tick(Sender: TObject);
var O: TJSONObject; Frame: Vcl.Graphics.TBitmap; Job: TJSONObject; Time: Double; Text: string;
begin
  if not Showing then begin
    try
      FSession.Poll;
      if (FSavePath<>'') and not FSession.Busy then begin
        var PendingPath := FSavePath; FSavePath := ''; var Args := TJSONObject.Create; Args.AddPair('path',PendingPath); Run('save',Args);
      end;
    except on E: Exception do begin FLastError := E.Message; FUi.Status.Caption := E.Message; end; end;
    FUi.Timer.Enabled := FSession.Busy or (FSavePath<>''); Exit;
  end;
  try
    // Escape/capture loss may bypass the native splitter's OnAfterResize.
    if FSplitterDragging and (((GetAsyncKeyState(VK_LBUTTON) and $8000)=0) or
      ((GetAsyncKeyState(VK_ESCAPE) and $8000)<>0)) then SplitterAfterResize(Self);
    FSession.Poll;
    // Collect and report an export before automatic preview can replace its job.
    RefreshExport;
    Frame := FSession.TakeFrame;
    if FTextPending and FOnlyTextDraft and FSession.CanEdit and not FSession.GuiLocked and
      (FDraftRevision=FSession.Project.Revision) then begin
      O := TJSONObject.Create; O.AddPair('id',FSelectedId); O.AddPair('text',FUi.Dialogue.Text); O.AddPair('subtitle',FUi.Subtitle.Text);
      Run('update-cue',O); FLastRevision := FSession.Project.Revision;
      FreeAndNil(Frame); FDrawnRevision := -1;
      FPendingPreview := True; FSeekTick := GetTickCount64;
      var Timeline := Command('timeline'); var Wave := Command('waveform');
      try FUi.Timeline.SetData(Timeline,Wave); finally Timeline.Free; Wave.Free; end;
    end;
    if FLastRevision<>FSession.Project.Revision then begin
      if FSession.Project.Scenes.Count>0 then FPendingPreview := True;
      RefreshView;
    end;
    if Frame<>nil then begin
      try
        // Coalesced seeks display the requested frame, never an older completed job.
        if FPlaying or not FPendingPreview or
          (Floor(FSession.FrameTime*FSession.Project.Fps)=Floor(FSession.Time*FSession.Project.Fps)) then begin
          FUi.Preview.SetFrame(Frame); FDrawnFrame := Floor(FSession.FrameTime*FSession.Project.Fps);
          FDrawnRevision := FSession.Project.Revision;
        end;
      finally Frame.Free; end;
    end;
    FUi.Timeline.SetTime(FSession.Time);
    if GetTickCount64-FStatusTick>=200 then begin
      FStatusTick := GetTickCount64; O := FSession.Status;
      try
        Text := Format('  %.2f / %.2f 秒　%s　%s',[FSession.Time,FSession.Project.Duration,IfThen(FSession.Project.Modified,'未保存','保存済'),FSession.Project.FileName]);
        if O.GetValue('job')<>nil then begin
          Job := JO(O,'job'); Text := Text+sLineBreak+'  '+MovieJobText(Job);
          var ShowProgress := not MatchText(JS(Job,'kind'),['preview','export']) and not JB(Job,'done') and (JN(Job,'phaseTotal')>0);
          if FUi.JobProgress.Visible<>ShowProgress then FUi.JobProgress.Visible := ShowProgress;
          if JN(Job,'phaseTotal')>0 then begin
            var Position := Round(EnsureRange(JN(Job,'phaseCompleted')/JN(Job,'phaseTotal'),0.0,1.0)*1000);
            if FJobPosition<>Position then begin FJobPosition := Position; FUi.JobProgress.Invalidate; end;
          end;
          if JB(Job,'done') and (FSeenJob<>JS(Job,'jobId')) then begin
            FSeenJob := JS(Job,'jobId');
            if MatchText(JS(Job,'kind'),['speakers','assets','waveform']) then RefreshView;
          end;
        end;
        if FLastError<>'' then Text := Text+sLineBreak+'  '+FLastError;
        if FSession.GuiLocked then Text := Text+sLineBreak+'  Codex編集中 — 手動解除は作成ページのロック解除';
        FUi.Dialogue.ReadOnly := FSession.GuiLocked; FUi.Subtitle.ReadOnly := FSession.GuiLocked;
        FUi.Script.ReadOnly := FSession.GuiLocked;
        if (FLastError<>'') and (FUi.Status.Caption<>FLastError) then FUi.Status.Caption := FLastError;
        if FUi.Status.Visible<>(FLastError<>'') then FUi.Status.Visible := FLastError<>'';
      finally O.Free; end;
      if not FSession.Playing and not FAudioPreparing then RefreshPreparation;
    end;
    if FSession.Playing and not FPlaying then StartPlayback;
    if not FSession.Playing and FPlaying then StopPlayback;
    if FAudioPreparing and not FSession.Busy then begin
      O := Command('job-status');
      try
        if (JS(O,'kind')='playback-audio') and (JS(O,'state')='succeeded') then begin
          FAudioFile := JS(O,'output');
          if not sndPlaySound(PChar(FAudioFile),SND_ASYNC or SND_NODEFAULT) then raise ERigm.Create('Windows音声再生を開始できませんでした。');
          FTick := GetTickCount64; FAudioReady := True; FAudioPreparing := False;
        end else begin StopPlayback; FLastError := JS(O,'error','再生音声の準備に失敗しました。'); end;
      finally O.Free; end;
    end;
    if FPlaying and FAudioReady then begin
      Time := FStartTime+(GetTickCount64-FTick)/1000.0;
      if Time>=FSession.Project.Duration then begin StopPlayback; Time := FSession.Project.Duration; end;
      O := TJSONObject.Create; AddN(O,'time',Time); Run('seek',O);
      RefreshSeek;
      FPendingPreview := True;
    end;
    if (FSavePath<>'') and not FSession.Busy then begin
      O := TJSONObject.Create; O.AddPair('path',FSavePath); Run('save',O); FSavePath := ''; RefreshView;
    end;
    RefreshSeek;
    if FPendingPreview and (not FSplitterDragging or FPlaying or FSession.Playing) and
      (FSavePath='') and not FSession.Busy and not FAudioPreparing and
      (FPlaying or (GetTickCount64-FSeekTick>=80)) then begin
      FPendingPreview := False;
      if (FDrawnRevision<>FSession.Project.Revision) or (FDrawnFrame<>Floor(FSession.Time*FSession.Project.Fps)) then begin
        Inc(FPreviewRequests); O := FSession.PreviewFrame(FSession.Time); O.Free;
      end;
    end;
    if not FSession.Playing and not FPendingPreview and not FSession.Busy and (GetTickCount64-FHistoryTick>=1000) then begin
      FHistoryTick := GetTickCount64; AppSettings.RememberPosition(FSession.Project,FSession.Time,FSelectedId);
    end;
    RefreshTransport;
    if FClosing and not FSession.Busy then FClosing := False;
  except on E: Exception do begin StopPlayback; FLastError := E.Message; if FUi.Status.Caption<>FLastError then FUi.Status.Caption := FLastError; end; end;
end;
procedure TRigmMovieEditorFrame.ActionClick(Sender: TObject);
var O: TJSONObject; OpenDialog: TOpenDialog; SaveDialog: TSaveDialog;
begin
  var DraftPages := FPropertyDrafts; var OtherDraft := FOtherDraft;
  var PoseDraft := FPoseDraft; var ActingDraft := FActingDraft;
  var SceneDraft := FSceneDraft; var ChartDraft := FChartDraft;
  var TextPending := FTextPending; var TextOnly := FOnlyTextDraft;
  try
    FLastError := '';
    case TComponent(Sender).Tag of
      44: begin
        var Cue := FSession.Project.Cue(FSelectedId);
        if (Cue=nil) or (FSession.Project.Scene(Cue.Scene)=nil) then raise ERigm.Create('チャートを置く場面を選んでください。');
        var Chart := TJSONObject.Create;
        try
          Chart.AddPair('kind',MovieChartKinds[EnsureRange(FUi.ChartKind.ItemIndex,0,2)]);
          if FUi.ChartKind.ItemIndex>0 then begin
            Chart.AddPair('title',FUi.ChartTitle.Text); AddN(Chart,'maximum',StrToFloat(FUi.ChartMaximum.Text,TFormatSettings.Invariant));
            var ColorValue := ColorToRGB(FUi.ChartColor.Selected);
            Chart.AddPair('color','#'+IntToHex(GetRValue(ColorValue),2)+IntToHex(GetGValue(ColorValue),2)+IntToHex(GetBValue(ColorValue),2));
            var Items := TJSONArray.Create; Chart.AddPair('items',Items);
            for var Line in FUi.ChartItems.Lines do if Line.Trim<>'' then begin
              var Separator := LastDelimiter('=',Line);
              if Separator<2 then raise ERigm.Create('各行は「項目 = 値」の形で入力してください。');
              var Item := TJSONObject.Create; Items.AddElement(Item);
              Item.AddPair('label',Copy(Line,1,Separator-1).Trim);
              AddN(Item,'value',StrToFloat(Copy(Line,Separator+1,MaxInt).Trim,TFormatSettings.Invariant));
            end;
          end;
          ValidateMovieChart(Chart); O := TJSONObject.Create; O.AddPair('id',Cue.Scene);
          O.AddPair('chart',Chart.Clone as TJSONObject); Run('update-scene',O);
        finally Chart.Free; end;
      end;
      43: begin FUi.Preview.Fit; Exit; end;
      34: begin FUi.ScriptPanel.Visible := not FUi.ScriptPanel.Visible; EditingAreaResize(Self); end;
      35: FUi.Settings.Visible := not FUi.Settings.Visible;
      38: begin
        SelectPropertyPage('diagnostics'); RefreshPreparation; Exit;
      end;
      13,39: begin ChooseExport(IfThen(TComponent(Sender).Tag=13,'mp4','avi')); RefreshView; Exit; end;
      40: begin
        if FileExists(FExport.CompletedPath) then ShellExecute(Handle,'open',PChar(ExtractFileDir(FExport.CompletedPath)),nil,nil,SW_SHOWNORMAL);
        Exit;
      end;
      1,3,4,17,22: begin
        StopPlayback; OpenDialog := TOpenDialog.Create(Self);
        try
          OpenDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
          case TComponent(Sender).Tag of
            1: OpenDialog.Filter := '動画プロジェクト (*.rigmovie)|*.rigmovie';
            3: OpenDialog.Filter := 'キャラクター (*.psdchar;*.rigm)|*.psdchar;*.rigm';
            4: OpenDialog.Filter := '台本 (*.txt;*.json)|*.txt;*.json';
            17: OpenDialog.Filter := 'シーン画像 (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp';
            22: OpenDialog.Filter := 'FFmpeg (ffmpeg.exe)|ffmpeg.exe';
          end;
          if OpenDialog.Execute then begin
            O := TJSONObject.Create;
            case TComponent(Sender).Tag of
              1: begin
                if Assigned(FOnOpenWork) then begin O.Free; FOnOpenWork(OpenDialog.FileName); end
                else begin O.Free; raise ERigm.Create('作品を開く遷移が未接続です。'); end;
              end;
              3: begin O.AddPair('character',OpenDialog.FileName); Run('update-project',O); end;
              4: begin O.AddPair('path',OpenDialog.FileName); O.AddPair('format',IfThen(SameText(ExtractFileExt(OpenDialog.FileName),'.json'),'json','text')); Run('import-script',O); end;
              17: begin
                O.Free;
                var Cue := FSession.Project.Cue(FSelectedId); if Cue=nil then raise ERigm.Create('Select a cue first');
                var Id := Cue.Id; if FSession.Project.Scene(Cue.Scene)<>nil then Id := Cue.Scene;
                FSession.AdoptImage(Id,OpenDialog.FileName); FPendingPreview := True;
              end;
              22: begin O.AddPair('ffmpeg',OpenDialog.FileName); Run('update-project',O); end;
            end;
          end;
        finally OpenDialog.Free; end;
      end;
      2,37: begin
        if (TComponent(Sender).Tag=2) and (FSession.Project.FileName<>'') then begin
          StopPlayback; FSavePath := FSession.Project.FileName;
          if not FSession.Busy then begin O := TJSONObject.Create; O.AddPair('path',FSavePath); Run('save',O); FSavePath := ''; end;
          RefreshView; Exit;
        end;
        StopPlayback; SaveDialog := TSaveDialog.Create(Self);
        try
          SaveDialog.Filter := '動画プロジェクト (*.rigmovie)|*.rigmovie'; SaveDialog.DefaultExt := 'rigmovie'; SaveDialog.FileName := FSession.Project.FileName;
          if SaveDialog.FileName='' then SaveDialog.FileName := MovieDefaultFile(FSession.Project);
          SaveDialog.Options := [ofPathMustExist,ofEnableSizing,ofNoChangeDir];
          if SaveDialog.Execute then begin
            FSavePath := SaveDialog.FileName;
          end;
        finally SaveDialog.Free; end;
      end;
      5: Run('undo'); 6: Run('redo'); 7: Run('speakers-refresh'); 8: Run('audio-generate');
      9: Run('job-cancel'); 10: Run('job-retry');
      11: begin O := TJSONObject.Create; AddN(O,'time',FSession.Time); Run('preview',O); end;
      12: begin if FSession.Playing then StopPlayback else Run('play'); RefreshTransport; Exit; end;
      36: begin StopPlayback; Exit; end;
      14: begin
        O := TJSONObject.Create; O.AddPair('title',FUi.Title.Text); O.AddPair('engineUrl',FUi.Engine.Text);
        var Values := string(FUi.Dimensions.Text).Replace('×','x').Split(['x']);
        if Length(Values)<>3 then begin O.Free; raise ERigm.Create('幅 x 高さ x fps を指定してください。'); end;
        AddN(O,'width',StrToInt(Trim(Values[0]))); AddN(O,'height',StrToInt(Trim(Values[1]))); AddN(O,'fps',StrToInt(Trim(Values[2]))); O.AddPair('encodeProfile',EncodeProfileIds[Max(0,FUi.EncodeProfile.ItemIndex)]); O.AddPair('outputTarget',FUi.OutputPath.Text); Run('update-project',O);
      end;
      15: begin O := TJSONObject.Create; O.AddPair('character','@sample'); Run('update-project',O); end;
      16: begin O := TJSONObject.Create; O.AddPair('id',FSelectedId);
          if FUi.Pages.Page=2 then begin
            O.AddPair('expression',FUi.Expression.Text); O.AddPair('motion',FUi.Motion.Text);
            if FUi.Emotion.ItemIndex>=0 then O.AddPair('emotion',MovieEmotionIds[NativeInt(FUi.Emotion.Items.Objects[FUi.Emotion.ItemIndex])]);
          end
        else begin O.AddPair('scene',FUi.Scene.Text); O.AddPair('speaker',FUi.Speaker.Text);
          O.AddPair('text',Trim(FUi.Dialogue.Text)); O.AddPair('subtitle',Trim(FUi.Subtitle.Text));
          AddN(O,'pause',StrToFloat(FUi.Pause.Text,TFormatSettings.Invariant)); end;
        Run('update-cue',O);
      end;
      18: begin O := TJSONObject.Create; var Cue := TRigmMovieCue.Create; try Cue.SpeakerId := FUi.Speaker.Text; if FSession.Project.Speaker(Cue.SpeakerId)=nil then Cue.SpeakerId := FSession.Project.Speakers[0].Id; O.AddPair('cue',Cue.Json); finally Cue.Free; end; Run('add-cue',O); end;
      19: begin O := TJSONObject.Create; O.AddPair('id',FSelectedId); Run('delete-cue',O); FSelectedId := ''; end;
      20: begin
        if FUi.Style.ItemIndex<0 then raise ERigm.Create('話者一覧を取得して音声を選んでください。');
        O := TJSONObject.Create; O.AddPair('id',FUi.Speaker.Text); AddN(O,'styleId',NativeInt(FUi.Style.Items.Objects[FUi.Style.ItemIndex]));
        AddN(O,'speed',StrToFloat(FUi.Speed.Text,TFormatSettings.Invariant)); AddN(O,'pitch',StrToFloat(FUi.Pitch.Text,TFormatSettings.Invariant)); Run('update-speaker',O);
      end;
      21: begin O := TJSONObject.Create; O.AddPair('text',FUi.Script.Text); Run('import-script',O); end;
      23: Run('assets-refresh'); 24: Run('waveform-refresh');
      41: begin
        var Cue := FSession.Project.Cue(FSelectedId); if Cue=nil then raise ERigm.Create('場面を選択してください');
        if FSession.Project.Scene(Cue.Scene)=nil then raise ERigm.Create('構成作品の場面を選択してください');
        O := TJSONObject.Create; O.AddPair('id',Cue.Scene); O.AddPair('title',FUi.SceneTitle.Text);
        O.AddPair('description',FUi.SceneDescription.Text); Run('update-scene',O);
        O := TJSONObject.Create; O.AddPair('layout',IfThen(FUi.LayoutChoice.ItemIndex=0,'theme','l'));
        O.AddPair('lDirection',IfThen(FUi.LayoutChoice.ItemIndex=1,'left','right')); Run('update-project',O);
      end;
      42: begin
        var CurrentDraft := (FDraftRevision<>0) and (FDraftRevision=FSession.Project.Revision);
        var Cue := FSession.Project.Cue(FSelectedId); if Cue=nil then raise ERigm.Create('セリフを選択してください');
        for var Character in FSession.Project.Characters do if
          (Character.SpeakerId=Cue.SpeakerId) and (Character.ActiveMotion<>'') then begin
          O := TJSONObject.Create; O.AddPair('id',Character.Id); Run('stop-motion',O);
        end;
        if CurrentDraft then FDraftRevision := FSession.Project.Revision;
      end;
      27: Run('workflow-next');
      31: begin
        O := TJSONObject.Create;
        if FSession.Project.WorkflowStage='script' then begin O.AddPair('text',FUi.Script.Text); Run('import-script',O); end
        else begin
          if FDraftRevision<>0 then raise ERigm.Create('未適用の編集を適用してから結果を作成してください。');
          Run('workflow-run',O);
        end;
      end;
      32: Run('workflow-back');
      33: begin FDraftRevision := 0; FUi.ReloadDraft.Visible := False; RefreshView; end;
      28: begin Run('diagnostics-refresh'); TScrollBox(FUi.Preparation.Parent).VertScrollBar.Position := FUi.Preparation.Top-24; RefreshPreparation; Exit; end;
      29: begin
        var C := FSession.Project.Cue(FSelectedId); if C=nil then raise ERigm.Create('演技を戻すセリフを選択してください。');
        var Ready := Command('preparation'); var Acting := C.Acting.Json;
        try
          Acting.RemovePair('mouthMode').Free; Acting.AddPair('mouthMode','auto');
          Acting.RemovePair('blinkMode').Free; Acting.AddPair('blinkMode','auto');
          Acting.RemovePair('variants').Free; Acting.AddPair('variants',TJSONArray.Create);
          if not JB(JO(Ready,'capabilities'),'headBodyMotion') then begin
            Acting.RemovePair('headGain').Free; AddN(Acting,'headGain',0);
            Acting.RemovePair('bodyGain').Free; AddN(Acting,'bodyGain',0);
          end;
          O := TJSONObject.Create; O.AddPair('id',C.Id); O.AddPair('acting',Acting.Clone as TJSONObject); Run('update-cue',O);
        finally Acting.Free; Ready.Free; end;
      end;
      30: begin
        var Examples := MovieExamples;
        try
          FUi.Script.SelectAll; FUi.Script.SelText := JS(TJSONObject(Examples[Max(0,FUi.Examples.ItemIndex)]),'text');
          FUi.Script.SelStart := 0; FUi.Script.SelLength := 0; FUi.Script.Perform(EM_SCROLLCARET,0,0); FUi.Script.SetFocus;
        finally Examples.Free; end;
        RefreshPreparation; Exit;
      end;
      25,26: begin
        var C := FSession.Project.Cue(FSelectedId); if C=nil then raise ERigm.Create('セリフを選択してください。');
        var Acting := C.Acting.Json;
        try
          for var I := 0 to 11 do begin Acting.RemovePair(MovieActingKeys[I]).Free; AddN(Acting,MovieActingKeys[I],StrToFloat(FUi.Acting[I].Text,TFormatSettings.Invariant)); end;
          Acting.RemovePair('mouthMode').Free; Acting.AddPair('mouthMode',FeatureModeIds[Max(0,FUi.MouthMode.ItemIndex)]);
          Acting.RemovePair('blinkMode').Free; Acting.AddPair('blinkMode',FeatureModeIds[Max(0,FUi.BlinkMode.ItemIndex)]);
          Acting.RemovePair('imageAttention').Free;
          Acting.AddPair('imageAttention',ImageAttentionModes[EnsureRange(FUi.ImageAttention.ItemIndex,0,2)]);
          var Variants := TJSONArray.Create;
          if TComponent(Sender).Tag=25 then begin
            var GroupId := ''; if (FUi.VariantGroup.ItemIndex>=0) and (FAssets.GetValue('groups')<>nil) then GroupId := JS(TJSONObject(JA(FAssets,'groups')[FUi.VariantGroup.ItemIndex]),'id');
            for var V in C.Acting.Variants do if JS(TJSONObject(V),'groupId')<>GroupId then Variants.AddElement(V.Clone as TJSONObject);
            if (GroupId<>'') and (FUi.Variant.ItemIndex>0) then begin
              var Group := TJSONObject(JA(FAssets,'groups')[FUi.VariantGroup.ItemIndex]); var Choice := TJSONObject.Create;
              Choice.AddPair('groupId',GroupId); Choice.AddPair('partId',JS(TJSONObject(JA(Group,'children')[FUi.Variant.ItemIndex-1]),'id')); Variants.AddElement(Choice);
            end;
          end;
          Acting.RemovePair('variants').Free; Acting.AddPair('variants',Variants);
          O := TJSONObject.Create; O.AddPair('id',C.Id); O.AddPair('acting',Acting.Clone as TJSONObject); Run('update-cue',O);
          var Time := 0.0; for var Cue in FSession.Project.Cues do begin if Cue.Id=FSelectedId then Break; Time := Time+FSession.Project.CueDuration(Cue); end;
          O := TJSONObject.Create; AddN(O,'time',Time+0.1); Run('seek',O); FPendingPreview := True; FSeekTick := GetTickCount64;
        finally Acting.Free; end;
      end;
    end;
    // Applying one page must leave unrelated, still-unapplied page inputs intact.
    var AppliedPage := -1;
    case TComponent(Sender).Tag of
      16: if FUi.Pages.Page=2 then AppliedPage := 2 else AppliedPage := 0;
      20: AppliedPage := 3; 25,26: AppliedPage := 2; 41,44: AppliedPage := 1;
    end;
    if AppliedPage>=0 then begin
      DraftPages[AppliedPage] := False;
      if AppliedPage=2 then begin
        if TComponent(Sender).Tag=16 then PoseDraft := False else ActingDraft := False;
        DraftPages[2] := PoseDraft or ActingDraft;
      end;
      if AppliedPage=1 then begin
        if TComponent(Sender).Tag=44 then ChartDraft := False else SceneDraft := False;
        DraftPages[1] := SceneDraft or ChartDraft;
      end;
      FPoseDraft := PoseDraft; FActingDraft := ActingDraft;
      FSceneDraft := SceneDraft; FChartDraft := ChartDraft;
      FPropertyDrafts := DraftPages; FOtherDraft := OtherDraft;
      var Remaining := OtherDraft; for var Pending in DraftPages do Remaining := Remaining or Pending;
      if Remaining then begin
        FDraftRevision := FSession.Project.Revision;
        FTextPending := TextPending and DraftPages[0]; FOnlyTextDraft := TextOnly and DraftPages[0];
      end;
    end;
    RefreshView;
  except on E: Exception do begin
    if TComponent(Sender).Tag in [13,39] then ShowExportError(E.Message)
    else begin FLastError := E.Message; FUi.Status.Caption := E.Message; end;
  end; end;
end;
procedure TRigmMovieEditorFrame.Closing(Sender: TObject; var CanClose: Boolean);
begin
  StopPlayback; AppSettings.RememberPosition(FSession.Project,FSession.Time,FSelectedId); CanClose := not FSession.Busy;
  if not CanClose then begin Run('job-cancel'); FClosing := True; FUi.Status.Caption := '取消処理が終わるまで制作画面を保持しています。'; end;
  if CanClose and FSession.Project.Modified then begin
    var Directory := TPath.Combine(AppSettings.Root,'Recovery');
    var Snapshot := FSession.Project.Clone;
    try SaveMovie(Snapshot,TPath.Combine(Directory,'recovery-'+NewRigmId+'.rigmovie')); AppSettings.RecordRecovery(FSession.Project,Snapshot.FileName,FSession.Time,FSelectedId); finally Snapshot.Free; end;
  end;
end;
procedure TRigmMovieEditorFrame.SetActive(Value: Boolean);
begin
  if not Value then StopPlayback;
  FUi.Timer.Enabled := Value or FSession.Busy or (FSavePath<>'');
  if Value then RefreshView;
end;
function TRigmMovieEditorFrame.RequestFinish: Boolean;
begin
  if (FDraftRevision<>0) and (MessageDlg('未適用の動画入力を破棄して終了しますか？',mtConfirmation,[mbYes,mbNo],0)<>mrYes) then Exit(False);
  Closing(Self,Result);
end;
procedure TRigmMovieEditorFrame.HandleKey(var Key: Word; Shift: TShiftState);
begin
  if Shift=[ssCtrl] then case Key of
    Ord('S'): begin InvokeAction(2); Key := 0; Exit; end;
    Ord('Z'): begin InvokeAction(5); Key := 0; Exit; end;
    Ord('Y'): begin InvokeAction(6); Key := 0; Exit; end;
  end;
  if (Shift=[ssCtrl,ssShift]) and (Key=Ord('E')) then begin InvokeAction(13); Key := 0; Exit; end;
  PreviewKeyDown(Self,Key,Shift);
end;
end.
