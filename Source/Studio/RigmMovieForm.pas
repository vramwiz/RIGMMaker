unit RigmMovieForm;

interface
uses Winapi.Windows, System.SysUtils, System.Classes, System.JSON, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, System.Types, System.Generics.Collections,
  RigmMovieSession, RigmIconToolbar, RigmMovieTimeline, RigmPropertyScrollBox, Vcl.AppEvnts,
  RigmMovieNotification;

type
  TRigmOpenMovieFile = procedure(const Path: string) of object;
  TRigmPropertyDrafts = array[0..4] of Boolean;
  TRigmMovieProperty = record
    LabelControl: TLabel;
    Control: TControl;
    Row,Column,Height,Page: Integer;
  end;
  TRigmMoviePreview = class(TCustomControl)
  private
    FFrame: TBitmap;
    FPaintCount,FFrameCount: UInt64;
    FSession: TRigmMovieSession;
    FSelectedCharacter: string;
    FOnCharacterSelected: TNotifyEvent;
    FDragHandle: Integer;
    FDragging: Boolean;
    FDragRevision: Integer;
    FDragProject: string;
    FDragStart: TPointF;
    FOriginal,FWorking: TRectF;
    FZoom: Double;
    FPanning,FLayoutDragging,FViewDirty: Boolean;
    FPanStart,FPanOriginal,FPan: TPoint;
    FViewCache: TBitmap;
    FWheelRemainder: Integer;
    procedure ClampViewport;
    procedure DrawView(Target: TCanvas);
    procedure SetSelectedCharacter(const Value: string);
    function VideoRect: TRect;
  protected
    procedure Paint; override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetFrame(Bitmap: TBitmap);
    procedure WheelAt(Delta: Integer; const Position: TPoint);
    procedure Fit;
    procedure SetLayoutDragging(Value: Boolean);
    property Zoom: Double read FZoom;
    property Frame: TBitmap read FFrame;
    property PaintCount: UInt64 read FPaintCount;
    property FrameCount: UInt64 read FFrameCount;
    property Session: TRigmMovieSession read FSession write FSession;
    property SelectedCharacter: string read FSelectedCharacter write SetSelectedCharacter;
    property OnCharacterSelected: TNotifyEvent read FOnCharacterSelected write FOnCharacterSelected;
    function ScreenToBase(X,Y: Integer): TPointF;
    function CharacterBounds(const Id: string): TRect;
    function HandleRect(const Id: string; Index: Integer): TRect;
  end;
  TRigmMovieForm = class(TForm)
  private
    FSession: TRigmMovieSession;
    FToolbar: TRigmIconToolbar;
    FSettings, FScriptPanel: TPanel;
    FList: TListView;
    FPreview: TRigmMoviePreview;
    FScript,FDialogue,FSubtitle: TMemo;
    FScene,FPause,FEngine,FTitle,FCharacter,FDimensions: TEdit;
    FOutputPath: TEdit;
    FExamples: TComboBox;
    FPreparation: TMemo;
    FWorkflow: TLabel;
    FNext: TButton;
    FRunStep,FBackStep,FReloadDraft: TButton;
    FDraftRevision: Integer;
    FAutoDiagnosticKey,FSeenDiagnostic: string;
    FSpeaker,FStyle,FExpression,FMotion,FEmotion: TComboBox;
    FOutputPreset,FEncodeProfile,FMouthMode,FBlinkMode: TComboBox;
    FJobProgress: TPaintBox;
    FJobPosition: Integer;
    FStatusTick: UInt64;
    FSpeed,FPitch: TEdit;
    FStatus: TLabel;
    FSeek: TRigmFineTrackBar;
    FFramePosition: TLabel;
    FFitPreview: TButton;
    FEditHost,FTransport: TPanel;
    FPreviewArea: TPanel;
    FTimelineSplitter,FPropertySplitter: TSplitter;
    FSplitterDragging,FPendingSplitterLayout: Boolean;
    FEditScroll: TScrollBox;
    FEditingLayout: Boolean;
    FTransportScroll: TScrollBox;
    FWheelEvents: TApplicationEvents;
    FTimeline: TRigmMovieTimeline;
    FZoom,FVariantGroup,FVariant,FImageAttention: TComboBox;
    FActing: array[0..11] of TEdit;
    FAssets: TJSONObject;
    FTimer: TTimer;
    FRefreshing,FPlaying: Boolean;
    FTick: UInt64;
    FStartTime: Double;
    FAudioFile: string;
    FAudioReady,FAudioPreparing: Boolean;
    FClosing,FPendingPreview: Boolean;
    FSelectedId,FCatalogKey: string;
    FLastRevision, FViewRefreshCount: Integer;
    FSeenJob,FLastError: string;
    FPlayButton,FStopButton: TButton;
    FTransportStatus: TLabel;
    FSeekTick,FHistoryTick: UInt64;
    FDrawnFrame,FDrawnRevision: Integer;
    FPreparationStamp,FViewedProject: string;
    FPreviewRequests: Integer;
    FOnOpenWork: TRigmOpenMovieFile;
    FOnlyTextDraft,FTextPending: Boolean;
    FRight: TRigmPropertyScrollBox;
    FPropertyHost: TPanel;
    FPropertyBar: TRigmIconToolbar;
    FPropertyPage,FBuildPropertyPage: Integer;
    FPropertyScroll: array[0..4] of Integer;
    FPropertyFocus: array[0..4] of TWinControl;
    FPropertyDrafts: TRigmPropertyDrafts;
    FPoseDraft,FActingDraft,FSceneDraft,FChartDraft: Boolean;
    FOtherDraft: Boolean;
    FSceneTitle: TEdit;
    FSceneDescription: TMemo;
    FChartKind: TComboBox;
    FChartTitle,FChartMaximum: TEdit;
    FChartItems: TMemo;
    FChartColor: TColorBox;
    FLayoutChoice: TComboBox;
    FWholeMotionStatus: TLabel;
    FPropertyFields: TList<TRigmMovieProperty>;
    FPropertyLayout: Boolean;
    FWorkflowPanel: TPanel;
    FStaticUiUpdates,FPropertyLayouts: Integer;
    FSavePath: string;
    FLayoutPPI: Integer;
    FBottom: TPanel;
    FExportPanel: TPanel;
    FExportStatus: TLabel;
    FExportProgress: TProgressBar;
    FExportNotification: TRigmMovieNotification;
    FNotifiedExport,FExportProject: string;
    FExportRefreshTick: UInt64;
    FExportFinished: Boolean;
    FExportButton,FExportResult: TButton;
    FExportJobId,FCompletedExport,FExportWarning,FExportError: string;
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
    procedure AddProperty(LabelControl: TLabel; Control: TControl; Row,X,W,H: Integer);
    procedure PropertyPageClick(Sender: TObject);
    procedure PropertyInputEntered(Sender: TObject);
    procedure LayoutProperties(Sender: TObject);
    procedure RefreshTransport;
    procedure PreviewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BuildUI;
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
    procedure Closed(Sender: TObject; var Action: TCloseAction);
    function Command(const Name: string; Args: TJSONObject = nil): TJSONObject;
    procedure Run(const Name: string; Args: TJSONObject = nil);
    procedure RefreshView;
    procedure RefreshCue;
    procedure StartPlayback;
    procedure StopPlayback;
  public
    function ExportNotificationRequests: Integer;
    function ExportNotificationsShown: Integer;
    property ViewRefreshCount: Integer read FViewRefreshCount;
    property PreviewPending: Boolean read FPendingPreview;
    property PreviewRequests: Integer read FPreviewRequests;
    property StaticUiUpdates: Integer read FStaticUiUpdates;
    property PropertyLayouts: Integer read FPropertyLayouts;
    function PropertyPageName: string;
    procedure SelectPropertyPage(const Page: string);
    procedure InvokeAction(Action: Integer);
    constructor CreateForSession(AOwner: TComponent; Session: TRigmMovieSession; Embedded: Boolean=False);
    destructor Destroy; override;
    property Session: TRigmMovieSession read FSession;
    property PreviewControl: TRigmMoviePreview read FPreview;
    property OnOpenWork: TRigmOpenMovieFile read FOnOpenWork write FOnOpenWork;
  protected
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
    procedure Resize; override;
  end;
procedure PopulateMovieMenus(Menu: TMainMenu; Handler: TNotifyEvent);

implementation
uses System.IOUtils, System.Math, System.StrUtils, System.UITypes,
  Winapi.Messages, Winapi.MMSystem, Winapi.ShellAPI, Vcl.Dialogs, RigmModel, RigmJson, RigmMovieModel,
  RigmMovieAudio, RigmToolbarIcons, RigmMovieOutput, RigmMoviePreparation, RigmAppSettings, RigmEditorForm, RigmMovieWorkspace,
  RigmMovieActing, RigmMovieChart;

procedure PopulateMovieMenus(Menu: TMainMenu; Handler: TNotifyEvent);
  function Group(const Name,Caption: string): TMenuItem;
  begin Result := TMenuItem.Create(Menu.Owner); Result.Name := Name; Result.Caption := Caption; Menu.Items.Add(Result); end;
  procedure Item(Parent: TMenuItem; const Caption: string; Action: Integer; const Shortcut: string='');
  var M: TMenuItem;
  begin
    M := TMenuItem.Create(Menu.Owner); M.Name := 'MovieMenuAction'+Action.ToString;
    M.Caption := Caption; M.Tag := Action; M.OnClick := Handler;
    if Shortcut<>'' then M.ShortCut := TextToShortCut(Shortcut); Parent.Add(M);
  end;
begin
  var FileMenu := Group('MovieFileMenu','ファイル(&F)');
  Item(FileMenu,'作品を開く...',1,'Ctrl+O'); Item(FileMenu,'保存',2,'Ctrl+S');
  Item(FileMenu,'名前を付けて保存...',37,'Ctrl+Shift+S');
  var ExportMenu := TMenuItem.Create(Menu.Owner); ExportMenu.Name := 'MovieExportMenu';
  ExportMenu.Caption := '動画を書き出す'; FileMenu.Add(ExportMenu);
  Item(ExportMenu,'MP4（映像・音声）...',13,'Ctrl+Shift+E'); Item(ExportMenu,'AVI（映像・音声）...',39);
  Item(FileMenu,'台本を読み込む...',4); Item(FileMenu,'RIGMを選択...',3);
  var EditMenu := Group('MovieEditMenu','編集(&E)'); Item(EditMenu,'元に戻す',5,'Ctrl+Z'); Item(EditMenu,'やり直す',6,'Ctrl+Y');
  var ViewMenu := Group('MovieViewMenu','表示(&V)');
  Item(ViewMenu,'台本とセリフ一覧',34); Item(ViewMenu,'作品・出力設定',35); Item(ViewMenu,'工程と診断の詳細',38);
  var MakeMenu := Group('MovieMakeMenu','制作(&P)');
  Item(MakeMenu,'必要な音声を再生成',8); Item(MakeMenu,'現在の位置をプレビュー',11);
  Item(MakeMenu,'現在工程の結果を作る',31); Item(MakeMenu,'次の工程へ',27); Item(MakeMenu,'前の工程へ',32);
  var Tools := Group('MovieToolsMenu','詳細(&D)');
  Item(Tools,'VOICEVOX話者を更新',7); Item(Tools,'キャラクター素材を更新',23); Item(Tools,'波形を更新',24);
  Item(Tools,'FFmpegを選択...',22); Item(Tools,'不一致を診断',28); Item(Tools,'使える演技へ戻す',29);
  Item(Tools,'ジョブを中止',9); Item(Tools,'ジョブを再試行',10);
end;

const
  OutputPresetIds: array[0..3] of string = ('draft','hd','fullhd','custom');
  EncodeProfileIds: array[0..2] of string = ('fast','balanced','quality');
  FeatureModeIds: array[0..2] of string = ('auto','assets','deform');
  ImageAttentionModes: array[0..2] of string = ('auto','off','head');
  MovieActingKeys: array[0..11] of string = ('mouthGain','lipLead','blinkStrength','blinkInterval','blinkDuration','blinkPhase','headGain','bodyGain','onset','duration','fadeIn','fadeOut');
  MovieActingLabels: array[0..11] of string = ('口パク強度 0～2','口パク先行 ±0.3秒','瞬き強度 0～1','瞬き間隔 0.3～30秒','瞬き時間 0.04～1秒','瞬き位相 0～30秒','頭の動き 0～3','上半身の動き 0～3','演技開始（秒）','演技時間（-1=終端）','フェードイン（秒）','フェードアウト（秒）');

constructor TRigmMoviePreview.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ControlStyle := ControlStyle+[csOpaque]; FFrame := Vcl.Graphics.TBitmap.Create; FZoom := 1;
  FViewCache := Vcl.Graphics.TBitmap.Create; FViewCache.PixelFormat := pf32bit; FViewDirty := True;
  ShowHint := True; Hint := 'ホイールで表示倍率を変更。中ボタンドラッグで移動。「画面に合わせる」で倍率を戻す。';
end;
destructor TRigmMoviePreview.Destroy;
begin FViewCache.Free; FFrame.Free; inherited; end;
procedure TRigmMoviePreview.SetFrame(Bitmap: Vcl.Graphics.TBitmap);
begin
  Inc(FFrameCount);
  // Do not share a bitmap's cached GDI DC with an exited render thread.
  FFrame.Free; FFrame := Vcl.Graphics.TBitmap.Create; FFrame.PixelFormat := pf32bit;
  FFrame.SetSize(Bitmap.Width,Bitmap.Height); FFrame.AlphaFormat := afIgnored;
  for var Y := 0 to Bitmap.Height-1 do Move(Bitmap.ScanLine[Y]^,FFrame.ScanLine[Y]^,Bitmap.Width*4);
  ClampViewport; FViewDirty := True; Invalidate;
end;
procedure TRigmMoviePreview.SetSelectedCharacter(const Value: string);
begin
  if FSelectedCharacter=Value then Exit;
  FSelectedCharacter := Value; FViewDirty := True; Invalidate;
end;
procedure TRigmMoviePreview.DrawView(Target: TCanvas);
var R: TRect;
begin

  Target.Brush.Color := $181818; Target.FillRect(ClientRect);
  if FFrame.Empty then begin Target.Font.Color := clSilver; Target.Font.Assign(Font); Target.TextOut(ScaleValue(12),ScaleValue(12),'キャラクターと台本を選び、プレビューを開始してください。'); Exit; end;
  R := VideoRect; Target.StretchDraw(R,FFrame);
  if (FSession<>nil) and (FSelectedCharacter<>'') then begin
    Target.Pen.Color := $00FFC060; Target.Pen.Width := ScaleValue(2); Target.Brush.Style := bsClear;
    R := CharacterBounds(FSelectedCharacter); Target.Rectangle(R);
    Target.Brush.Style := bsSolid; Target.Brush.Color := $00FFC060;
    for var I := 0 to 7 do Target.FillRect(HandleRect(FSelectedCharacter,I));
  end;
end;
procedure TRigmMoviePreview.Paint;
begin
  Inc(FPaintCount);
  // Resize during splitter drag reuses the last scaled image. Newly delivered
  // playback frames and explicit zoom/pan still mark the view dirty normally.
  if FViewDirty or FViewCache.Empty or (not FLayoutDragging and
    ((FViewCache.Width<>ClientWidth) or (FViewCache.Height<>ClientHeight))) then begin
    FViewCache.SetSize(Max(1,ClientWidth),Max(1,ClientHeight));
    DrawView(FViewCache.Canvas); FViewDirty := False;
  end;
  Canvas.Brush.Color := $181818; Canvas.FillRect(ClientRect);
  Canvas.Draw(0,0,FViewCache);
end;
function TRigmMoviePreview.VideoRect: TRect;
begin
  var VW := 1920; var VH := 1080;
  if FSession<>nil then begin VW := FSession.Project.Width; VH := FSession.Project.Height; end;
  var AvailableW := Max(1,ClientWidth); var AvailableH := Max(1,ClientHeight);
  var K := Min(AvailableW/Max(1,VW),AvailableH/Max(1,VH))*FZoom;
  var W := Max(1,Round(VW*K)); var H := Max(1,Round(VH*K));
  var X := (AvailableW-W) div 2; var Y := (AvailableH-H) div 2;
  if W>AvailableW then X := -FPan.X;
  if H>AvailableH then Y := -FPan.Y;
  Result := Rect(X,Y,X+W,Y+H);
end;
procedure TRigmMoviePreview.ClampViewport;
begin
  var R := VideoRect;
  FPan.X := EnsureRange(FPan.X,0,Max(0,R.Width-Max(1,ClientWidth)));
  FPan.Y := EnsureRange(FPan.Y,0,Max(0,R.Height-Max(1,ClientHeight)));
end;
procedure TRigmMoviePreview.Resize;
begin
  inherited; ClampViewport;
  if not FLayoutDragging then begin FViewDirty := True; Invalidate; end;
end;
procedure TRigmMoviePreview.SetLayoutDragging(Value: Boolean);
begin
  if FLayoutDragging=Value then Exit;
  FLayoutDragging := Value;
  if not Value then begin ClampViewport; FViewDirty := True; Invalidate; end;
end;
procedure TRigmMoviePreview.Fit;
begin
  FZoom := 1; FPan := Point(0,0);
  ClampViewport; FViewDirty := True; Invalidate;
end;
procedure TRigmMoviePreview.WheelAt(Delta: Integer; const Position: TPoint);
begin
  if FDragging or FPanning then Exit;
  Inc(FWheelRemainder,Delta); var Steps := FWheelRemainder div 120; FWheelRemainder := FWheelRemainder mod 120;
  if Steps=0 then Exit;
  var R := VideoRect; var X := (Position.X-R.Left)/Max(1,R.Width); var Y := (Position.Y-R.Top)/Max(1,R.Height);
  FZoom := EnsureRange(FZoom*Power(1.2,EnsureRange(Steps,-12,12)),0.1,16.0);
  ClampViewport; R := VideoRect;
  FPan.X := EnsureRange(Round(X*R.Width-Position.X),0,Max(0,R.Width-Max(1,ClientWidth)));
  FPan.Y := EnsureRange(Round(Y*R.Height-Position.Y),0,Max(0,R.Height-Max(1,ClientHeight)));
  FViewDirty := True; Invalidate;
end;
function TRigmMoviePreview.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin Result := PtInRect(ClientRect,ScreenToClient(MousePos)); if Result then WheelAt(WheelDelta,ScreenToClient(MousePos)); end;
function TRigmMoviePreview.ScreenToBase(X,Y: Integer): TPointF;
begin var R := VideoRect; Result := PointF((X-R.Left)*1920/Max(1,R.Width),(Y-R.Top)*1080/Max(1,R.Height)); end;
function TRigmMoviePreview.CharacterBounds(const Id: string): TRect;
begin
  Result := Rect(0,0,0,0); if FSession=nil then Exit;
  var C := FSession.Project.Character(Id); if C=nil then Exit;
  var B := RectF(C.X,C.Y,C.X+C.Width,C.Y+C.Height);
  if FDragging and (Id=FSelectedCharacter) then B := FWorking;
  var R := VideoRect;
  Result := Rect(R.Left+Round(B.Left*R.Width/1920),R.Top+Round(B.Top*R.Height/1080),
    R.Left+Round(B.Right*R.Width/1920),R.Top+Round(B.Bottom*R.Height/1080));
end;
function TRigmMoviePreview.HandleRect(const Id: string; Index: Integer): TRect;
begin
  var R := CharacterBounds(Id); var X := R.Left; var Y := R.Top;
  case Index of
    1: X := (R.Left+R.Right) div 2;
    2: X := R.Right;
    3: begin X := R.Right; Y := (R.Top+R.Bottom) div 2; end;
    4: begin X := R.Right; Y := R.Bottom; end;
    5: begin X := (R.Left+R.Right) div 2; Y := R.Bottom; end;
    6: Y := R.Bottom;
    7: Y := (R.Top+R.Bottom) div 2;
  end;
  var Size := ScaleValue(5); Result := Rect(X-Size,Y-Size,X+Size+1,Y+Size+1);
end;
procedure TRigmMoviePreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if Button=mbMiddle then begin
    FPanStart := Point(X,Y); FPanOriginal := FPan;
    FPanning := True; MouseCapture := True; Exit;
  end;
  if (Button<>mbLeft) or (FSession=nil) or FSession.GuiLocked or not FSession.CanEdit then Exit;
  FDragHandle := -1;
  if FSelectedCharacter<>'' then for var I := 0 to 7 do if PtInRect(HandleRect(FSelectedCharacter,I),Point(X,Y)) then FDragHandle := I;
  if FDragHandle<0 then begin
    FSelectedCharacter := '';
    for var I := FSession.Project.Characters.Count-1 downto 0 do begin
      var C := FSession.Project.Characters[I];
      if C.Visible and PtInRect(CharacterBounds(C.Id),Point(X,Y)) then begin FSelectedCharacter := C.Id; Break; end;
    end;
  end;
  var C := FSession.Project.Character(FSelectedCharacter);
  if C=nil then begin FViewDirty := True; Invalidate; Exit; end;
  if Assigned(FOnCharacterSelected) then FOnCharacterSelected(Self);
  FOriginal := RectF(C.X,C.Y,C.X+C.Width,C.Y+C.Height); FWorking := FOriginal;
  FDragStart := ScreenToBase(X,Y); FDragging := True; MouseCapture := True; FViewDirty := True; Invalidate;
  FDragRevision := FSession.Project.Revision; FDragProject := FSession.Project.Id;
end;
procedure TRigmMoviePreview.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if FPanning then begin
    FPan := Point(FPanOriginal.X+FPanStart.X-X,FPanOriginal.Y+FPanStart.Y-Y);
    ClampViewport; FViewDirty := True; Invalidate; Exit;
  end;
  if not FDragging then Exit;
  var P := ScreenToBase(X,Y); var DX := P.X-FDragStart.X; var DY := P.Y-FDragStart.Y;
  FWorking := FOriginal;
  if FDragHandle<0 then begin FWorking.Offset(DX,DY); end else begin
    if FDragHandle in [0,6,7] then FWorking.Left := FOriginal.Left+DX;
    if FDragHandle in [2,3,4] then FWorking.Right := FOriginal.Right+DX;
    if FDragHandle in [0,1,2] then FWorking.Top := FOriginal.Top+DY;
    if FDragHandle in [4,5,6] then FWorking.Bottom := FOriginal.Bottom+DY;
  end;
  FWorking.Left := Round(FWorking.Left/10)*10; FWorking.Top := Round(FWorking.Top/10)*10;
  FWorking.Right := Max(FWorking.Left+20,Round(FWorking.Right/10)*10);
  FWorking.Bottom := Max(FWorking.Top+20,Round(FWorking.Bottom/10)*10);
  if FSession.Project.Layout='l' then begin
    var Center := (FWorking.Left+FWorking.Right)/2;
    if (FSession.Project.LDirection='left') and (Center>720) then FWorking.Offset(720-Center,0);
    if (FSession.Project.LDirection='right') and (Center<1200) then FWorking.Offset(1200-Center,0);
  end;
  FViewDirty := True; Invalidate;
end;
procedure TRigmMoviePreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if FPanning then begin FPanning := False; MouseCapture := False; Exit; end;
  if (Button<>mbLeft) or not FDragging then Exit;
  MouseMove(Shift,X,Y); FDragging := False; MouseCapture := False;
  if FSession.GuiLocked or not FSession.CanEdit or (FSession.Project.Revision<>FDragRevision) or (FSession.Project.Id<>FDragProject) then begin FViewDirty := True; Invalidate; Exit; end;
  var O := TJSONObject.Create;
  try
    O.AddPair('id',FSelectedCharacter); O.AddPair('projectId',FDragProject); AddN(O,'revision',FDragRevision);
    AddN(O,'x',FWorking.Left); AddN(O,'y',FWorking.Top); AddN(O,'width',FWorking.Width); AddN(O,'height',FWorking.Height);
    var Reply := FSession.Execute('update-character',O); Reply.Free;
  finally O.Free; FViewDirty := True; Invalidate; end;
end;

constructor TRigmMovieForm.CreateForSession(AOwner: TComponent; Session: TRigmMovieSession; Embedded: Boolean);
begin
  inherited CreateScaledNew(AOwner,96); var TargetPPI := Monitor.PixelsPerInch; FSession := Session; Caption := 'RIGM Maker — 動画制作';
  Name := 'MovieStudio'+IntToHex(NativeUInt(Self),16); Width := 1380; Height := 900;
  Constraints.MinWidth := 640; Constraints.MinHeight := 360; Position := poScreenCenter;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10; DoubleBuffered := True;
  FDrawnFrame := -1; FDrawnRevision := -1; KeyPreview := True; OnKeyDown := PreviewKeyDown;
  FSelectedId := FSession.ResumeCue; FPendingPreview := FSession.Project.Cues.Count>0;
  FPropertyFields := TList<TRigmMovieProperty>.Create;
  FLayoutPPI := 96;
  FAssets := TJSONObject.Create; BuildUI; FPreview.Session := Session;
  if not Embedded then begin var Actions := TMainMenu.Create(Self); Menu := Actions; PopulateMovieMenus(Actions,ActionClick); end;
  if Embedded then begin BorderStyle := bsNone; Constraints.MinWidth := 0; Constraints.MinHeight := 0; end
  else ScaleForPPI(TargetPPI);
  OnCloseQuery := Closing; OnClose := Closed; RefreshView;
end;
destructor TRigmMovieForm.Destroy;
begin
  if FTimer<>nil then begin FTimer.Enabled := False; StopPlayback; end;
  FAssets.Free;
  FPropertyFields.Free;
  inherited;
end;
procedure TRigmMovieForm.BuildUI;
var Panel,Settings,Bottom,ScriptPanel,Bar: TPanel; Right: TRigmPropertyScrollBox; Splitter: TSplitter; L: TLabel;
  function Edit(Parent: TWinControl; const Name,Caption: string; X,Y,W: Integer): TEdit;
  begin
    L := TLabel.Create(Self); L.Parent := Parent; L.Caption := Caption; L.SetBounds(X,Y,W,20);
    Result := TEdit.Create(Self); Result.Parent := Parent; Result.Name := Name; Result.Text := ''; Result.SetBounds(X,Y+20,W,26);
    if Parent=FRight then AddProperty(L,Result,Y,X,W,26);
  end;
  function Combo(const Name,Caption: string; X,Y,W: Integer): TComboBox;
  begin
    L := TLabel.Create(Self); L.Parent := Right; L.Caption := Caption; L.SetBounds(X,Y,W,20);
    Result := TComboBox.Create(Self); Result.Parent := Right; Result.Name := Name; Result.Style := csDropDownList; Result.SetBounds(X,Y+20,W,26);
    AddProperty(L,Result,Y,X,W,26);
  end;
  procedure Button(Parent: TWinControl; const Name,Caption: string; Tag,X,Y,W: Integer);
  var B: TButton;
  begin B := TButton.Create(Self); B.Parent := Parent; B.Name := Name; B.Caption := Caption; B.Tag := Tag; B.SetBounds(X,Y,W,28); B.OnClick := ActionClick;
    if Parent=FRight then AddProperty(nil,B,Y,X,W,28);
  end;
begin
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'MovieToolbar';
  FToolbar.Visible := False;
  FToolbar.AddIcon('MovieOpen','制作プロジェクトを開く',riOpen,1,ActionClick);
  FToolbar.AddIcon('MovieSave','制作プロジェクト保存',riSave,2,ActionClick);
  FToolbar.AddIcon('MovieCharacter','RIGMキャラクターを選ぶ',riSample,3,ActionClick);
  FToolbar.AddIcon('MovieImport','台本テキスト / JSONを開く',riPng,4,ActionClick);
  FToolbar.AddIcon('MovieUndo','制作を元に戻す',riUndo,5,ActionClick);
  FToolbar.AddIcon('MovieRedo','制作をやり直す',riRedo,6,ActionClick);
  FToolbar.AddSeparator;
  FToolbar.AddIcon('MovieVoices','VOICEVOX話者一覧を取得',riRefresh,7,ActionClick);
  FToolbar.AddIcon('MovieAudio','台本から音声を生成（未生成だけ）',riGenerate,8,ActionClick);
  FToolbar.AddIcon('MovieCancel','ジョブ取消',riDelete,9,ActionClick);
  FToolbar.AddIcon('MovieRetry','ジョブ再試行',riRefresh,10,ActionClick);
  FToolbar.AddIcon('MoviePreview','現在時刻をプレビュー',riPreview,11,ActionClick);
  FToolbar.AddIcon('MoviePlay','再生 / 停止',riDirect,12,ActionClick);
  FToolbar.AddIcon('MovieExport','音声付きAVI / MP4を書き出す',riSaveAs,13,ActionClick);
  FToolbar.AddIcon('MovieFfmpeg','MP4用の既存FFmpegを選ぶ',riOpen,22,ActionClick);
  FToolbar.AddIcon('MovieAssets','既存キャラクター素材一覧を取得',riSample,23,ActionClick);
  FToolbar.AddIcon('MovieWaveform','音声波形を取得',riRefresh,24,ActionClick);
  FToolbar.AddIcon('MovieShowScript','台本入力を表示 / 隠す',riEditPreview,34,ActionClick);
  FToolbar.AddIcon('MovieShowSettings','出力・接続の詳細設定を表示 / 隠す',riRefresh,35,ActionClick);
  Settings := TPanel.Create(Self); FSettings := Settings; Settings.Parent := Self; Settings.Align := alTop; Settings.Height := 146; Settings.BevelOuter := bvNone;
  Settings.Visible := False;
  FTitle := Edit(Settings,'MovieTitle','動画タイトル',12,2,270);
  FEngine := Edit(Settings,'MovieEngineUrl','VOICEVOX接続先（このPC）',292,2,240);
  FDimensions := Edit(Settings,'MovieDimensions','幅 × 高さ × fps',542,2,170);
  FCharacter := Edit(Settings,'MovieCharacterPath','キャラクター',722,2,295); FCharacter.ReadOnly := True;
  Button(Settings,'MovieApplySettings','設定を適用',14,12,106,120);
  Button(Settings,'MovieSampleCharacter','テスト用キャラ',15,142,106,120);
  L := TLabel.Create(Self); L.Parent := Settings; L.Caption := '台本を取り込み → 実在する話者を選択 → 音声生成 → プレビュー → 動画出力'; L.SetBounds(280,110,730,24);
  L := TLabel.Create(Self); L.Parent := Settings; L.Caption := '出力サイズ'; L.SetBounds(12,52,270,20);
  FOutputPreset := TComboBox.Create(Self); FOutputPreset.Parent := Settings; FOutputPreset.Name := 'MovieOutputPreset';
  FOutputPreset.Style := csDropDownList; FOutputPreset.SetBounds(12,72,270,26);
  FOutputPreset.Items.AddStrings(['下書き 640×360 / 15fps','HD 1280×720 / 30fps','フルHD 1920×1080 / 30fps','カスタム']); FOutputPreset.OnChange := OutputPresetChanged;
  L := TLabel.Create(Self); L.Parent := Settings; L.Caption := '出力の画質と速度'; L.SetBounds(292,52,300,20);
  FEncodeProfile := TComboBox.Create(Self); FEncodeProfile.Parent := Settings; FEncodeProfile.Name := 'MovieEncodeProfile';
  FEncodeProfile.Style := csDropDownList; FEncodeProfile.SetBounds(292,72,300,26);
  FEncodeProfile.Items.AddStrings(['速度優先','標準','画質優先']);
  FEncodeProfile.Hint := '速度優先は圧縮を軽くします。画質優先は出力に時間がかかります。'; FEncodeProfile.ShowHint := True;
  FOutputPath := Edit(Settings,'MovieOutputTarget','新しい出力先（AVI / MP4）',622,52,395);
  Bar := TPanel.Create(Self); FWorkflowPanel := Bar; Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 72; Bar.BevelOuter := bvNone; Bar.Visible := False;
  FWorkflow := TLabel.Create(Self); FWorkflow.Parent := Bar; FWorkflow.Name := 'MovieWorkflowGuide';
  FWorkflow.AutoSize := False; FWorkflow.WordWrap := True;
  FWorkflow.SetBounds(12,2,Bar.ClientWidth-24,35); FWorkflow.Anchors := [akLeft,akTop,akRight];
  Button(Bar,'MovieRunStep','工程の結果を作る',31,12,40,150); FRunStep := TButton(FindComponent('MovieRunStep'));
  Button(Bar,'MovieNextStep','次へ',27,172,40,100); FNext := TButton(FindComponent('MovieNextStep'));
  Button(Bar,'MovieBackStep','前の工程へ',32,282,40,120); FBackStep := TButton(FindComponent('MovieBackStep'));
  Button(Bar,'MovieDiagnose','不足を診断',28,412,40,130);
  Button(Bar,'MovieSafeActing','使える演技へ戻す',29,552,40,180);
  Button(Bar,'MovieReloadDraft','最新データを読込',33,742,40,160);
  FReloadDraft := TButton(FindComponent('MovieReloadDraft')); FReloadDraft.Visible := False;
  FJobProgress := TPaintBox.Create(Self); FJobProgress.Parent := Self; FJobProgress.Align := alBottom;
  FJobProgress.Name := 'MovieJobProgress'; FJobProgress.Height := 8; FJobProgress.OnPaint := PaintJobProgress; FJobProgress.Visible := False;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 52;
  FStatus.WordWrap := True; FStatus.Layout := tlCenter; FStatus.Name := 'MovieStatus';
  FStatus.Visible := False;
  FExportPanel := TPanel.Create(Self); FExportPanel.Parent := Self; FExportPanel.Align := alBottom;
  FExportPanel.Name := 'MovieExportFeedback'; FExportPanel.Caption := ''; FExportPanel.ShowCaption := False;
  FExportPanel.Height := 64; FExportPanel.BevelOuter := bvNone; FExportPanel.Visible := False;
  FExportStatus := TLabel.Create(Self); FExportStatus.Parent := FExportPanel; FExportStatus.Align := alClient;
  FExportStatus.Name := 'MovieExportFeedbackText'; FExportStatus.AutoSize := False; FExportStatus.WordWrap := True;
  FExportStatus.Layout := tlCenter; FExportStatus.ShowHint := True;
  FExportProgress := TProgressBar.Create(Self); FExportProgress.Parent := FExportPanel;
  FExportProgress.Name := 'MovieExportProgress'; FExportProgress.Align := alBottom;
  FExportProgress.Height := 10; FExportProgress.Min := 0; FExportProgress.Max := 1000;
  FExportNotification := TRigmMovieNotification.Create(Self);
  FExportResult := TButton.Create(Self); FExportResult.Parent := FExportPanel; FExportResult.Align := alRight;
  FExportResult.Name := 'MovieExportFeedbackAction'; FExportResult.Width := 130; FExportResult.OnClick := ActionClick;
  Bottom := TPanel.Create(Self); FBottom := Bottom; Bottom.Parent := Self; Bottom.Align := alBottom; Bottom.Height := 296; Bottom.BevelOuter := bvNone; Bottom.Caption := '';
  FTimeline := TRigmMovieTimeline.Create(Self); FTimeline.Parent := Bottom; FTimeline.Align := alClient;
  FTimeline.Name := 'MovieWaveTimeline'; FTimeline.OnSeek := TimelineSeek;
  FTimeline.OnSelectCue := TimelineSelectCue;
  Bar := TPanel.Create(Self); Bar.Parent := Bottom; Bar.Align := alBottom; Bar.Height := 64; Bar.BevelOuter := bvNone; Bar.Caption := ''; Bar.ShowCaption := False; Bar.Name := 'MovieFrameSeek';
  var SeekHeader := TPanel.Create(Self); SeekHeader.Parent := Bar; SeekHeader.Align := alTop; SeekHeader.Height := 26; SeekHeader.Caption := ''; SeekHeader.ShowCaption := False; SeekHeader.BevelOuter := bvNone; SeekHeader.Name := 'MovieSeekHeader';
  FFramePosition := TLabel.Create(Self); FFramePosition.Parent := SeekHeader; FFramePosition.Align := alClient;
  FFramePosition.Name := 'MovieFramePosition'; FFramePosition.AutoSize := False; FFramePosition.Layout := tlCenter; FFramePosition.ShowHint := True;
  FZoom := TComboBox.Create(Self); FZoom.Parent := SeekHeader; FZoom.Align := alRight; FZoom.Width := 100; FZoom.Style := csDropDownList;
  FZoom.Items.AddStrings(['全体','10秒','30秒','60秒']); FZoom.ItemIndex := 0; FZoom.OnChange := ZoomChanged; FZoom.Name := 'MovieTimelineZoom';
  FSeek := TRigmFineTrackBar.Create(Self); FSeek.Parent := Bar; FSeek.Align := alClient; FSeek.Name := 'MovieSeek'; FSeek.Min := 0; FSeek.Max := 1; FSeek.OnChange := SeekChanged;
  FSeek.Frequency := 0; FSeek.TickStyle := tsNone; FSeek.LineSize := 1; FSeek.PageSize := 10;
  FSeek.ShowHint := True; FSeek.Hint := '作品全体のフレーム位置。クリック・ドラッグでシーク、ホイールで1フレームずつ移動。';
  FPropertyHost := TPanel.Create(Self); FPropertyHost.Parent := Self; FPropertyHost.Align := alRight;
  FPropertyHost.Name := 'MoviePropertyHost'; FPropertyHost.Caption := ''; FPropertyHost.BevelOuter := bvNone;
  FPropertyHost.Width := 370; FPropertyHost.Constraints.MinWidth := 340;
  FPropertyBar := TRigmIconToolbar.Create(Self); FPropertyBar.Parent := FPropertyHost; FPropertyBar.Align := alTop;
  FPropertyBar.Name := 'MoviePropertyPages';
  FPropertyBar.AddIcon('MoviePropertiesDialogue','セリフ・字幕・話者',riEditPreview,0,PropertyPageClick,True);
  FPropertyBar.AddIcon('MoviePropertiesScene','場面画像・説明・レイアウト',riPng,1,PropertyPageClick,True);
  FPropertyBar.AddIcon('MoviePropertiesActing','表情・動作・演技',riPreview,2,PropertyPageClick,True);
  FPropertyBar.AddIcon('MoviePropertiesAudio','音声の詳細・再生成',riGenerate,3,PropertyPageClick,True);
  FPropertyBar.AddIcon('MoviePropertiesDiagnostics','素材と出力の診断',riClassify,4,PropertyPageClick,True);
  Right := TRigmPropertyScrollBox.Create(Self); FRight := Right; Right.Parent := FPropertyHost; Right.Align := alClient;
  Right.BorderStyle := bsNone; Right.Name := 'MovieProperties';
  Right.HorzScrollBar.Visible := False; Right.VertScrollBar.Visible := True; Right.OnResize := LayoutProperties;
  FBuildPropertyPage := 1;
  FSceneTitle := Edit(Right,'MovieSceneTitle','場面名',12,0,330);
  FScene := Edit(Right,'MovieCueScene','シーン',12,4,330);
  FScene.ReadOnly := True;
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := '場面の説明';
  FSceneDescription := TMemo.Create(Self); FSceneDescription.Parent := Right; FSceneDescription.Name := 'MovieSceneDescription';
  FSceneDescription.ScrollBars := ssVertical; AddProperty(L,FSceneDescription,160,12,330,90);
  FLayoutChoice := Combo('MovieSceneLayout','画像と説明の配置',12,266,330);
  FLayoutChoice.Items.AddStrings(['背景・画像・説明の標準配置','L字配置・キャラクターを左','L字配置・キャラクターを右']);
  FLayoutChoice.OnChange := DraftEdited;
  Button(Right,'MovieApplyScene','場面と配置を適用',41,12,320,330);
  FChartKind := Combo('MovieSceneChartKind','総評チャート',12,370,330);
  FChartKind.Items.AddStrings(['なし','レーダーチャート','棒グラフ']); FChartKind.ItemIndex := 0; FChartKind.OnChange := DraftEdited;
  FChartTitle := Edit(Right,'MovieSceneChartTitle','チャートの題名',12,424,330);
  FChartMaximum := Edit(Right,'MovieSceneChartMaximum','満点',12,478,330);
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := '項目 = 値（1行1項目、最大8項目）';
  FChartItems := TMemo.Create(Self); FChartItems.Parent := Right; FChartItems.Name := 'MovieSceneChartItems';
  FChartItems.ScrollBars := ssVertical; AddProperty(L,FChartItems,532,12,330,120);
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := 'チャートの色';
  FChartColor := TColorBox.Create(Self); FChartColor.Parent := Right; FChartColor.Name := 'MovieSceneChartColor';
  FChartColor.Style := [cbStandardColors,cbExtendedColors,cbCustomColor,cbPrettyNames];
  FChartColor.Selected := RGB(90,184,232); FChartColor.OnChange := DraftEdited; AddProperty(L,FChartColor,672,12,330,28);
  Button(Right,'MovieApplySceneChart','チャートを適用',44,12,726,330);
  FBuildPropertyPage := 0;
  FSpeaker := Combo('MovieCueSpeaker','台本上の話者',12,53,158); FSpeaker.OnChange := SelectSpeaker;
  FPause := Edit(Right,'MovieCuePause','セリフ後の間（秒）',184,53,158);
  FBuildPropertyPage := 2;
  FEmotion := Combo('MovieCueEmotion','感情（既存の立ち絵差分）',12,48,330);
  FEmotion.OnChange := DraftEdited;
  FImageAttention := Combo('MovieImageAttention','画像への向き補助（瞳移動なし）',12,300,330);
  FImageAttention.Items.AddStrings(['説明時に控えめな頭の向き補助','補助なし','このセリフでは画像へ頭の向き補助']);
  FImageAttention.OnChange := DraftEdited;
  FExpression := Combo('MovieCueExpression','表情ポーズ',12,102,158); FExpression.Items.AddStrings(['neutral','smile','serious','sad']);
  FMotion := Combo('MovieCueMotion','動作',184,102,158); FMotion.Items.AddStrings(['idle','still','nod','emphasis']);
  Button(Right,'MovieApplyPose','表情と動作を適用',16,12,152,330);
  FWholeMotionStatus := TLabel.Create(Self); FWholeMotionStatus.Parent := Right;
  FWholeMotionStatus.Name := 'MovieWholeMotionStatus'; FWholeMotionStatus.Caption := '';
  FWholeMotionStatus.AutoSize := False; FWholeMotionStatus.WordWrap := True;
  AddProperty(nil,FWholeMotionStatus,188,12,330,42);
  Button(Right,'MovieStopWholeMotion','全体モーションを停止',42,12,242,330);
  FBuildPropertyPage := 0;
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := 'セリフ'; L.SetBounds(12,156,330,20);
  FDialogue := TMemo.Create(Self); FDialogue.Parent := Right; FDialogue.Name := 'MovieCueText'; FDialogue.Text := ''; FDialogue.SetBounds(12,178,330,85); FDialogue.ScrollBars := ssVertical;
  AddProperty(L,FDialogue,156,12,330,85);
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := '字幕（読み上げとは別に調整できます）'; L.SetBounds(12,269,330,20);
  FSubtitle := TMemo.Create(Self); FSubtitle.Parent := Right; FSubtitle.Name := 'MovieCueSubtitle'; FSubtitle.Text := ''; FSubtitle.SetBounds(12,291,330,75); FSubtitle.ScrollBars := ssVertical;
  AddProperty(L,FSubtitle,269,12,330,75);
  Button(Right,'MovieApplyCue','セリフを適用',16,12,374,158); Button(Right,'MovieBackground','シーン画像を選ぶ',17,184,374,158);
  Button(Right,'MovieAddCue','セリフ追加',18,12,408,158); Button(Right,'MovieDeleteCue','セリフ削除',19,184,408,158);
  FBuildPropertyPage := 3;
  FStyle := Combo('MovieVoiceStyle','選択中の話者のVOICEVOX音声',12,448,330);
  FSpeed := Edit(Right,'MovieVoiceSpeed','話速（0.5～2）',12,500,158); FPitch := Edit(Right,'MovieVoicePitch','音高（-0.15～0.15）',184,500,158);
  Button(Right,'MovieApplyVoice','音声設定を適用',20,12,554,330);
  Button(Right,'MovieGenerateVoice','必要な音声を再生成',8,12,600,330);
  FBuildPropertyPage := 2;
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := 'セリフ別の演技（音声は再生成しません）'; L.SetBounds(12,594,330,20);
  AddProperty(L,nil,594,12,330,0);
  for var I := 0 to 11 do FActing[I] := Edit(Right,'MovieActing_'+MovieActingKeys[I],MovieActingLabels[I],12+(I mod 2)*172,618+(I div 2)*50,158);
  FMouthMode := Combo('MovieMouthMode','口パクの方式',12,922,158); FMouthMode.Items.AddStrings(['自動（素材を優先）','既存素材を切替','変形']);
  FBlinkMode := Combo('MovieBlinkMode','瞬きの方式',184,922,158); FBlinkMode.Items.AddStrings(['自動（素材を優先）','既存素材を切替','変形']);
  FVariantGroup := Combo('MovieVariantGroup','実在素材グループ',12,974,330); FVariantGroup.OnChange := VariantGroupChanged;
  FVariant := Combo('MovieVariantPart','表示候補（同じグループの子素材）',12,1026,330);
  Button(Right,'MovieApplyActing','演技を適用・プレビュー',25,12,1078,330);
  Button(Right,'MovieClearVariants','このセリフの素材選択を解除',26,12,1112,330);
  Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alRight;
  Splitter.Name := 'MoviePropertySplitter'; Splitter.MinSize := 220; Splitter.Width := 10; Splitter.ResizeStyle := rsUpdate;
  FPropertySplitter := Splitter; Splitter.AutoSnap := False;
  Splitter.OnBeforeResize := SplitterBeforeResize; Splitter.OnCanResize := SplitterCanResize;
  Splitter.OnAfterResize := SplitterAfterResize;
  FBuildPropertyPage := 4;
  L := TLabel.Create(Self); L.Parent := Right; L.Caption := '準備診断・素材で使える演技'; L.SetBounds(12,1150,330,20);
  FPreparation := TMemo.Create(Self); FPreparation.Parent := Right; FPreparation.Name := 'MoviePreparationDetails';
  FPreparation.SetBounds(12,1172,330,220); FPreparation.ReadOnly := True; FPreparation.ScrollBars := ssVertical;
  AddProperty(L,FPreparation,1150,12,330,220);
  FReloadDraft.Parent := FPropertyHost; FReloadDraft.Align := alTop;
  FEditScroll := TScrollBox.Create(Self); FEditScroll.Parent := Self; FEditScroll.Align := alClient;
  FEditScroll.Name := 'MovieEditingScroll'; FEditScroll.BorderStyle := bsNone;
  FEditScroll.VertScrollBar.Tracking := True; FEditScroll.HorzScrollBar.Tracking := True;
  Panel := TPanel.Create(Self); Panel.Parent := FEditScroll; Panel.BevelOuter := bvNone;
  FEditScroll.OnResize := EditingAreaResize;
  Panel.Caption := ''; Panel.Name := 'MovieEditingArea'; FEditHost := Panel;
  Panel.SetBounds(0,0,Max(240,FEditScroll.ClientWidth),Max(340,FEditScroll.ClientHeight));
  Panel.DisableAlign;
  Bottom.Parent := Panel;
  Bottom.SetBounds(0,Panel.ClientHeight-Bottom.Height,Panel.ClientWidth,Bottom.Height);
  var TimelineSplitter := TSplitter.Create(Self); TimelineSplitter.Parent := Panel; TimelineSplitter.Align := alBottom;
  TimelineSplitter.Name := 'MovieTimelineSplitter'; TimelineSplitter.Height := 10; TimelineSplitter.MinSize := 165; TimelineSplitter.ResizeStyle := rsUpdate;
  TimelineSplitter.Top := Bottom.Top-TimelineSplitter.Height;
  FTimelineSplitter := TimelineSplitter; TimelineSplitter.AutoSnap := False;
  TimelineSplitter.OnBeforeResize := SplitterBeforeResize; TimelineSplitter.OnCanResize := SplitterCanResize;
  TimelineSplitter.OnAfterResize := SplitterAfterResize;
  FPreviewArea := TPanel.Create(Self); FPreviewArea.Parent := Panel; FPreviewArea.Align := alClient;
  FPreviewArea.Name := 'MoviePreviewArea'; FPreviewArea.Caption := ''; FPreviewArea.BevelOuter := bvNone;
  ScriptPanel := TPanel.Create(Self); FScriptPanel := ScriptPanel; ScriptPanel.Parent := FPreviewArea; ScriptPanel.Align := alLeft; ScriptPanel.Width := 310; ScriptPanel.BevelOuter := bvNone;
  ScriptPanel.Visible := False;
  Bar := TPanel.Create(Self); Bar.Parent := ScriptPanel; Bar.Align := alBottom; Bar.Height := 34; Bar.BevelOuter := bvNone;
  Button(Bar,'MovieApplyScript','入力した台本を取り込む',21,8,2,295);
  FScript := TMemo.Create(Self); FScript.Parent := ScriptPanel; FScript.Align := alTop; FScript.Height := 170; FScript.Name := 'MovieScript'; FScript.ScrollBars := ssBoth;
  FExamples := TComboBox.Create(Self); FExamples.Parent := ScriptPanel; FExamples.Align := alTop; FExamples.Style := csDropDownList; FExamples.Name := 'MovieScriptExample';
  FExamples.Items.AddStrings(['架空の短い紹介例','3分紹介の構成テンプレート']); FExamples.ItemIndex := 0;
  Bar := TPanel.Create(Self); Bar.Parent := ScriptPanel; Bar.Align := alTop; Bar.Height := 30; Bar.BevelOuter := bvNone;
  Button(Bar,'MovieLoadExample','選択した例を入力欄へ表示',30,8,1,295);
  FScript.Text := '';
  FList := TListView.Create(Self); FList.Parent := ScriptPanel; FList.Align := alClient; FList.Name := 'MovieCueList'; FList.ViewStyle := vsReport;
  FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False;
  FList.Columns.Add.Caption := '開始'; FList.Columns[0].Width := 50; FList.Columns.Add.Caption := '台本'; FList.Columns[1].Width := 190;
  FList.Columns.Add.Caption := '音声'; FList.Columns[2].Width := 55; FList.OnSelectItem := SelectCue;
  Splitter := TSplitter.Create(Self); Splitter.Parent := FPreviewArea; Splitter.Align := alLeft;
  FTransportScroll := TScrollBox.Create(Self); FTransportScroll.Parent := FPreviewArea; FTransportScroll.Align := alBottom;
  FTransportScroll.Name := 'MovieTransportScroll'; FTransportScroll.Height := 64; FTransportScroll.BorderStyle := bsNone;
  FTransportScroll.VertScrollBar.Visible := False; FTransportScroll.HorzScrollBar.Tracking := True;
  Bar := TPanel.Create(Self); Bar.Parent := FTransportScroll; Bar.Height := 44; Bar.BevelOuter := bvNone; Bar.Name := 'MovieTransport'; FTransport := Bar;
  Bar.Caption := '';
  Button(Bar,'MovieTransportPlay','▶ 再生',12,8,10,112); FPlayButton := TButton(FindComponent('MovieTransportPlay'));
  Button(Bar,'MovieTransportStop','■ 停止',36,128,10,112); FStopButton := TButton(FindComponent('MovieTransportStop'));
  Button(Bar,'MovieTransportExport','MP4出力...',13,248,10,130); FExportButton := TButton(FindComponent('MovieTransportExport'));
  FExportButton.Hint := '保存先を選んで映像・音声付きMP4を書き出す（Ctrl+Shift+E）'; FExportButton.ShowHint := True;
  FPlayButton.Hint := 'この位置から再生（入力欄以外では Space）'; FPlayButton.ShowHint := True;
  FStopButton.Hint := '再生を停止（入力欄以外では Space）'; FStopButton.ShowHint := True;
  FTransportStatus := TLabel.Create(Self); FTransportStatus.Parent := Bar; FTransportStatus.Name := 'MoviePlaybackState';
  Button(Bar,'MoviePreviewFit','画面に合わせる',43,388,10,150); FFitPreview := TButton(FindComponent('MoviePreviewFit'));
  FFitPreview.ShowHint := True; FFitPreview.Hint := 'プレビューの表示倍率と移動をリセット。作品の配置や出力サイズは変更しません。';
  FTransportStatus.Visible := False;
  FTransportStatus.AutoSize := False; FTransportStatus.SetBounds(252,8,400,32); FTransportStatus.Anchors := [akLeft,akTop,akRight];
  FTransportStatus.Layout := tlCenter; FTransportStatus.WordWrap := True;
  FPreview := TRigmMoviePreview.Create(Self); FPreview.Parent := FPreviewArea; FPreview.Align := alClient; FPreview.Name := 'MoviePreviewImage';
  Panel.EnableAlign;
  FWheelEvents := TApplicationEvents.Create(Self); FWheelEvents.OnMessage := ApplicationMessage;
  FTimer := TTimer.Create(Self); FTimer.Interval := 40; FTimer.OnTimer := Tick;
  for var I := 0 to ComponentCount-1 do begin
    if Components[I] is TEdit then TEdit(Components[I]).OnChange := DraftEdited;
    if (Components[I] is TMemo) and (Components[I]<>FPreparation) then TMemo(Components[I]).OnChange := DraftEdited;
  end;
  FStyle.OnChange := DraftEdited; FExpression.OnChange := DraftEdited; FMotion.OnChange := DraftEdited;
  FEncodeProfile.OnChange := DraftEdited; FMouthMode.OnChange := DraftEdited; FBlinkMode.OnChange := DraftEdited;
  for var Field in FPropertyFields do begin
    if Field.Control is TEdit then TEdit(Field.Control).OnEnter := PropertyInputEntered;
    if Field.Control is TMemo then TMemo(Field.Control).OnEnter := PropertyInputEntered;
    if Field.Control is TComboBox then TComboBox(Field.Control).OnEnter := PropertyInputEntered;
  end;
  SelectPropertyPage('dialogue'); LayoutProperties(Self);
  Resize; // Establish the scrollable editing area's initial size before first display.
end;
procedure TRigmMovieForm.InvokeAction(Action: Integer);
begin
  var Proxy := TComponent.Create(nil);
  try Proxy.Tag := Action; ActionClick(Proxy); finally Proxy.Free; end;
end;
procedure TRigmMovieForm.AddProperty(LabelControl: TLabel; Control: TControl; Row,X,W,H: Integer);
begin
  var Field: TRigmMovieProperty; Field.LabelControl := LabelControl; Field.Control := Control;
  Field.Row := Row; Field.Height := H; Field.Column := 0;
  Field.Page := FBuildPropertyPage;
  if (Control<>nil) and (Control.Name='MovieBackground') then begin Field.Page := 1; Field.Row := 110; end;
  if Field.Page=0 then case Row of 156: Field.Row := 0; 269: Field.Row := 110; 53: Field.Row := 210;
    374: Field.Row := 265; 408: Field.Row := 299; end;
  if (Field.Page=1) and (Control<>nil) and (Control.Name='MovieCueScene') then Field.Row := 55;
  if Field.Page=2 then begin if Row=102 then Field.Row := 0 else if Row=152 then Field.Row := 50; end;
  if Field.Page=3 then Field.Row := Row-448;
  if Field.Page=4 then Field.Row := Row-1150;
  if W<260 then if X<170 then Field.Column := 1 else Field.Column := 2;
  if LabelControl<>nil then begin LabelControl.AutoSize := False; LabelControl.WordWrap := True; end;
  FPropertyFields.Add(Field);
end;
function TRigmMovieForm.PropertyPageName: string;
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin Result := Names[FPropertyPage]; end;
procedure TRigmMovieForm.PropertyPageClick(Sender: TObject);
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin SelectPropertyPage(Names[TComponent(Sender).Tag]); end;
procedure TRigmMovieForm.PropertyInputEntered(Sender: TObject);
begin
  for var Field in FPropertyFields do if Field.Control=Sender then begin
    FPropertyFocus[Field.Page] := TWinControl(Sender); Break;
  end;
end;
procedure TRigmMovieForm.SelectPropertyPage(const Page: string);
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin
  var Index := -1; for var I := 0 to High(Names) do if Page=Names[I] then Index := I;
  if Index<0 then raise ERigm.Create('Unknown movie property page');
  var Host := GetParentForm(Self,True);
  if (Host<>nil) and (Host.ActiveControl<>nil) and
    FRight.ContainsControl(Host.ActiveControl) then FPropertyFocus[FPropertyPage] := Host.ActiveControl;
  FPropertyScroll[FPropertyPage] := FRight.VertScrollBar.Position;
  FPropertyPage := Index;
  FRight.DisableAlign;
  try
    for var Field in FPropertyFields do begin
      if Field.Control<>nil then Field.Control.Visible := Field.Page=Index;
      if Field.LabelControl<>nil then Field.LabelControl.Visible := Field.Page=Index;
    end;
    for var I := 0 to FPropertyBar.ButtonCount-1 do FPropertyBar.Buttons[I].Down := I=Index;
  finally FRight.EnableAlign; end;
  FRight.VertScrollBar.Position := 0; LayoutProperties(Self);
  FRight.VertScrollBar.Position := FPropertyScroll[Index]; LayoutProperties(Self);
  var Focus := FPropertyFocus[Index];
  if (Focus<>nil) and Focus.CanFocus then Focus.SetFocus;
end;
procedure TRigmMovieForm.LayoutProperties(Sender: TObject);
  function Pixels(Value: Integer): Integer;
  begin Result := MulDiv(Value,FLayoutPPI,96); end;
begin
  if FPropertyLayout or (FRight=nil) or (FPropertyFields=nil) or (csDestroying in ComponentState) then Exit;
  if FSplitterDragging then begin FPendingSplitterLayout := True; Exit; end;
  FPropertyLayout := True;
  try
    Inc(FPropertyLayouts);
    var HostForm := GetParentForm(Self,True);
    if (HostForm<>nil) and (HostForm<>Self) then FLayoutPPI := HostForm.ScaleValue(96);
    var Scroll := FRight.VertScrollBar.Position; var Margin := Pixels(12); var Gap := Pixels(12);
    var Available := Max(Pixels(220),FRight.ClientWidth-Margin*2); var Half := (Available-Gap) div 2;
    var Rows := TList<Integer>.Create;
    try
      for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and not Rows.Contains(Field.Row) then Rows.Add(Field.Row);
      Rows.Sort; var Y := Pixels(8);
      FRight.DisableAlign;
      try for var Row in Rows do begin
        var LabelHeight := 0; var ControlHeight := 0; var HasVisible := False;
        for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and (Field.Row=Row) then begin
          if (Field.Control<>nil) and not Field.Control.Visible then Continue;
          HasVisible := True;
          if Field.LabelControl<>nil then begin
            Field.LabelControl.Visible := True; var W := Available; if Field.Column<>0 then W := Half;
            Canvas.Font.Assign(Field.LabelControl.Font); Canvas.TextHeight('M');
            var R := Rect(0,0,W,0); DrawText(Canvas.Handle,PChar(Field.LabelControl.Caption),-1,R,DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
            LabelHeight := Max(LabelHeight,Max(Pixels(20),R.Height+Pixels(3)));
          end;
          ControlHeight := Max(ControlHeight,Pixels(Field.Height));
        end;
        if not HasVisible then Continue;
        for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and (Field.Row=Row) then begin
          if (Field.Control<>nil) and not Field.Control.Visible then Continue;
          var X := Margin; var W := Available; if Field.Column<>0 then W := Half;
          if Field.Column=2 then Inc(X,Half+Gap);
          if Field.LabelControl<>nil then Field.LabelControl.SetBounds(X,Y-Scroll,W,LabelHeight);
          if Field.Control<>nil then begin
            var Height := Pixels(Field.Height);
            if Field.Control is TEdit then Canvas.Font.Assign(TEdit(Field.Control).Font)
            else if Field.Control is TComboBox then Canvas.Font.Assign(TComboBox(Field.Control).Font)
            else if Field.Control is TButton then Canvas.Font.Assign(TButton(Field.Control).Font);
            if (Field.Control is TEdit) or (Field.Control is TComboBox) or (Field.Control is TButton) then
              Height := Max(Height,Canvas.TextHeight('Mg')+Pixels(8));
            Field.Control.SetBounds(X,Y+LabelHeight-Scroll,W,Height);
            // Native combo boxes enforce a font-dependent height, particularly after DPI changes.
            ControlHeight := Max(ControlHeight,Field.Control.Height);
          end;
        end;
        Inc(Y,LabelHeight+ControlHeight+Pixels(10));
      end;
      finally FRight.EnableAlign; end;
      FRight.VertScrollBar.Range := Y+Margin;
    finally Rows.Free; end;
  finally FPropertyLayout := False; end;
end;
procedure TRigmMovieForm.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin
  inherited;
  for var I := 0 to High(FPropertyScroll) do FPropertyScroll[I] := MulDiv(FPropertyScroll[I],M,D);
  if isDpiChange then FLayoutPPI := M else FLayoutPPI := MulDiv(FLayoutPPI,M,D);
  EditingAreaResize(Self);
  LayoutProperties(Self);
end;
procedure TRigmMovieForm.Resize;
begin
  inherited;
  if (FBottom=nil) or (FTimeline=nil) or (FLayoutPPI=0) then Exit;
  EditingAreaResize(Self);
  LayoutProperties(Self);
  LayoutTransport;
end;
procedure TRigmMovieForm.SplitterBeforeResize(Sender: TObject);
begin
  var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  if Sender=FTimelineSplitter then FTimelineSplitter.MinSize := MulDiv(165,PPI,96)
  else if Sender=FPropertySplitter then FPropertySplitter.MinSize := MulDiv(220,PPI,96);
  FSplitterDragging := True; FPreview.SetLayoutDragging(True); FTimeline.SetLayoutDragging(True);
end;
procedure TRigmMovieForm.SplitterAfterResize(Sender: TObject);
begin
  if not FSplitterDragging then Exit;
  FSplitterDragging := False;
  if FPendingSplitterLayout then begin
    FPendingSplitterLayout := False; EditingAreaResize(Self); LayoutProperties(Self);
  end;
  FPreview.SetLayoutDragging(False); FTimeline.SetLayoutDragging(False);
end;
procedure TRigmMovieForm.SplitterCanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
begin
  if Sender=FTimelineSplitter then begin
    NewSize := Max(NewSize,FTimelineSplitter.MinSize);
    Accept := Accept and (NewSize<=FEditHost.ClientHeight-FTimelineSplitter.Height-FTimelineSplitter.MinSize);
  end else if Sender=FPropertySplitter then begin
    NewSize := Max(NewSize,FPropertyHost.Constraints.MinWidth);
    Accept := Accept and (NewSize<=ClientWidth-FPropertySplitter.Width-FPropertySplitter.MinSize);
  end;
  // Each splitter changes only its own target. No opposite-axis size is restored.
end;
procedure TRigmMovieForm.EditingAreaResize(Sender: TObject);
begin
  if FEditingLayout or (FEditHost=nil) or (FEditScroll=nil) or (FPreview=nil) then Exit;
  FEditingLayout := True;
  try
    var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
    if not FSplitterDragging then begin
      var Thickness := MulDiv(10,PPI,96);
      if (FPropertySplitter<>nil) and (FPropertySplitter.Width<>Thickness) then FPropertySplitter.Width := Thickness;
      if (FTimelineSplitter<>nil) and (FTimelineSplitter.Height<>Thickness) then FTimelineSplitter.Height := Thickness;
    end;
    var MinimumW := MulDiv(240,PPI,96);
    if FScriptPanel.Visible then Inc(MinimumW,FScriptPanel.Width);
    var MinimumH := Max(MulDiv(340,PPI,96),MulDiv(165,PPI,96)*2+FTimelineSplitter.Height);
    var W := Max(FEditScroll.ClientWidth,MinimumW); var H := Max(FEditScroll.ClientHeight,MinimumH);
    FEditHost.SetBounds(-FEditScroll.HorzScrollBar.Position,-FEditScroll.VertScrollBar.Position,W,H);
    FEditScroll.HorzScrollBar.Range := W; FEditScroll.VertScrollBar.Range := H;
    LayoutTransport;
  finally FEditingLayout := False; end;
end;
procedure TRigmMovieForm.DraftEdited(Sender: TObject);
begin
  if FRefreshing then Exit;
  if FDraftRevision=0 then begin
    FillChar(FPropertyDrafts,SizeOf(FPropertyDrafts),0); FOtherDraft := False;
    FPoseDraft := False; FActingDraft := False; FSceneDraft := False; FChartDraft := False;
    // Stamp the data actually displayed, even before the next timer refresh.
    FDraftRevision := FLastRevision;
    if FDraftRevision=0 then FDraftRevision := FSession.Project.Revision;
    FOnlyTextDraft := (FSession.Project.Scenes.Count>0) and ((Sender=FDialogue) or (Sender=FSubtitle));
  end;
  var Found := False;
  for var Field in FPropertyFields do if Field.Control=Sender then begin FPropertyDrafts[Field.Page] := True; Found := True; Break; end;
  if not Found then FOtherDraft := True;
  if (Sender=FExpression) or (Sender=FMotion) or (Sender=FEmotion) then FPoseDraft := True
  else if Found and FPropertyDrafts[2] then begin
    for var Field in FPropertyFields do
      if (Field.Control=Sender) and (Field.Page=2) then begin FActingDraft := True; Break; end;
  end;
  if (Sender=FChartKind) or (Sender=FChartTitle) or (Sender=FChartMaximum) or
    (Sender=FChartItems) or (Sender=FChartColor) then FChartDraft := True
  else if (Sender=FSceneTitle) or (Sender=FSceneDescription) or (Sender=FLayoutChoice) then FSceneDraft := True;
  if (Sender=FDialogue) or (Sender=FSubtitle) then FTextPending := True else FOnlyTextDraft := False;
end;
function TRigmMovieForm.Command(const Name: string; Args: TJSONObject): TJSONObject;
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
    if Editing then begin FDraftRevision := 0; FTextPending := False; FOnlyTextDraft := False; FReloadDraft.Visible := False; end;
  finally Args.Free; end;
end;
procedure TRigmMovieForm.Run(const Name: string; Args: TJSONObject);
var Reply: TJSONObject;
begin Reply := Command(Name,Args); Reply.Free; end;
procedure TRigmMovieForm.RefreshCue;
var C: TRigmMovieCue; WasRefreshing: Boolean;
begin
  WasRefreshing := FRefreshing; FRefreshing := True;
  try
  C := FSession.Project.Cue(FSelectedId);
  if C=nil then begin
    FSceneTitle.Clear; FSceneDescription.Clear; FEmotion.Items.Clear;
    FScene.Clear; FPause.Clear; FDialogue.Clear; FSubtitle.Clear; FSpeed.Clear; FPitch.Clear;
    FStyle.ItemIndex := -1; FSpeaker.ItemIndex := -1; FExpression.ItemIndex := -1; FMotion.ItemIndex := -1;
    for var E in FActing do E.Clear;
    Exit;
  end;
  FScene.Text := C.Scene; FPause.Text := FloatToStr(C.Pause,TFormatSettings.Invariant);
  var Scene := FSession.Project.Scene(C.Scene);
  if Scene<>nil then begin FSceneTitle.Text := Scene.Title; FSceneDescription.Text := Scene.Description; end
  else begin FSceneTitle.Clear; FSceneDescription.Clear; end;
  FChartKind.ItemIndex := 0; FChartTitle.Text := '総評'; FChartMaximum.Text := '5'; FChartItems.Clear;
  FChartColor.Selected := RGB(90,184,232);
  if (Scene<>nil) and MovieChartEnabled(Scene.Chart) then begin
    FChartKind.ItemIndex := IndexText(JS(Scene.Chart,'kind','none'),['none','radar','bar']);
    FChartTitle.Text := JS(Scene.Chart,'title','総評'); FChartMaximum.Text := FloatToStr(JN(Scene.Chart,'maximum',5),TFormatSettings.Invariant);
    if Scene.Chart.GetValue('items') is TJSONArray then for var V in JA(Scene.Chart,'items') do begin
      var Item := TJSONObject(V); FChartItems.Lines.Add(JS(Item,'label')+' = '+FloatToStr(JN(Item,'value'),TFormatSettings.Invariant));
    end;
    var ColorValue := StrToInt('$'+Copy(JS(Scene.Chart,'color','#5AB8E8'),2,6));
    FChartColor.Selected := RGB((ColorValue shr 16) and 255,(ColorValue shr 8) and 255,ColorValue and 255);
  end;
  FEmotion.Items.Clear; FEmotion.ItemIndex := -1;
  for var I := 0 to High(MovieEmotionIds) do begin
    var Available := (MovieEmotionIds[I]='neutral') or (MovieEmotionIds[I]=C.Emotion);
    for var Character in FSession.Project.Characters do if (Character.SpeakerId=C.SpeakerId) and
      (Character.Expressions.GetValue(MovieEmotionIds[I])<>nil) then Available := True;
    if Available then begin
      FEmotion.Items.AddObject(MovieEmotionLabels[I],TObject(NativeInt(I)));
      if MovieEmotionIds[I]=C.Emotion then FEmotion.ItemIndex := FEmotion.Items.Count-1;
    end;
  end;
  FLayoutChoice.ItemIndex := 0;
  if FSession.Project.Layout='l' then
    if FSession.Project.LDirection='left' then FLayoutChoice.ItemIndex := 1 else FLayoutChoice.ItemIndex := 2;
  FWholeMotionStatus.Caption := '通常の演技（口パク・瞬きあり）';
  for var Character in FSession.Project.Characters do if
    (Character.SpeakerId=C.SpeakerId) and (Character.ActiveMotion<>'') then
    FWholeMotionStatus.Caption := '全体モーション: '+Character.ActiveMotion+'（口パク・瞬きを停止）';
  FDialogue.Text := C.Text; FSubtitle.Text := C.Subtitle;
  FSpeaker.ItemIndex := FSpeaker.Items.IndexOf(C.SpeakerId); FExpression.ItemIndex := FExpression.Items.IndexOf(C.Expression);
  FMotion.ItemIndex := FMotion.Items.IndexOf(C.Motion); SelectSpeaker(Self);
  var O := C.Acting.Json;
  FImageAttention.ItemIndex := IndexText(C.Acting.ImageAttention,['auto','off','head']);
  try
    for var I := 0 to 11 do FActing[I].Text := FloatToStr(JN(O,MovieActingKeys[I]),TFormatSettings.Invariant);
  finally O.Free; end;
  for var I := 0 to 2 do begin
    if FeatureModeIds[I]=C.Acting.MouthMode then FMouthMode.ItemIndex := I;
    if FeatureModeIds[I]=C.Acting.BlinkMode then FBlinkMode.ItemIndex := I;
  end;
  VariantGroupChanged(Self);
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieForm.RefreshView;
var Start: Double; O: TJSONObject; Catalog: TJSONArray;
begin
  if FDraftRevision<>0 then begin
    if FReloadDraft.Visible<>(FDraftRevision<>FSession.Project.Revision) then begin
      FReloadDraft.Visible := FDraftRevision<>FSession.Project.Revision; LayoutProperties(Self);
    end;
    if FReloadDraft.Visible then FStatus.Caption := '別操作で更新されています。未適用入力を保持しました。最新データを読み込んで再調整してください。';
    Exit;
  end;
  Inc(FViewRefreshCount);
  if FViewedProject<>FSession.Project.Id then begin FSelectedId := FSession.ResumeCue; FDrawnFrame := -1; FPendingPreview := FSession.Project.Cues.Count>0;
    FExportJobId := ''; FExportProject := ''; FExportPanel.Visible := False;
    FTimeline.ResetView; FPreview.Fit; FViewedProject := FSession.Project.Id; end;
  FRefreshing := True;
  try
    FTitle.Text := FSession.Project.Title; FEngine.Text := FSession.Project.EngineUrl; FCharacter.Text := FSession.Project.CharacterFile;
    FDimensions.Text := Format('%d × %d × %d',[FSession.Project.Width,FSession.Project.Height,FSession.Project.Fps]);
    for var I := 0 to 3 do if OutputPresetIds[I]=MoviePresetId(FSession.Project.Width,FSession.Project.Height,FSession.Project.Fps) then FOutputPreset.ItemIndex := I;
    for var I := 0 to 2 do if EncodeProfileIds[I]=FSession.Project.EncodeProfile then FEncodeProfile.ItemIndex := I;
    FOutputPath.Text := FSession.Project.OutputTarget;
    FSpeaker.Items.Clear; for var S in FSession.Project.Speakers do FSpeaker.Items.Add(S.Id);
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear; Start := 0;
      for var C in FSession.Project.Cues do begin
        Start := FSession.Project.CueStart(C);
        var Item := FList.Items.Add; Item.Caption := FormatFloat('0.0',Start,TFormatSettings.Invariant);
        Item.SubItems.Add(C.Text); if FSession.Project.AudioReady(C) then Item.SubItems.Add('生成済') else Item.SubItems.Add('未生成');
        Item.SubItems.Add(C.Id); // Stable metadata; the third subitem has no visible column.
        if C.Id=FSelectedId then Item.Selected := True; Start := Start+FSession.Project.CueDuration(C);
      end;
      if (FList.Selected=nil) and (FList.Items.Count>0) then begin FList.Items[0].Selected := True; FSelectedId := FList.Items[0].SubItems[2]; end;
    finally FList.Items.EndUpdate; end;
    O := Command('speaker-list');
    try
      Catalog := JA(O,'styles'); var Key := Catalog.ToJSON;
      if Key<>FCatalogKey then begin
        FCatalogKey := Key; FStyle.Items.Clear;
        for var V in Catalog do begin var S := TJSONObject(V); FStyle.Items.AddObject(JS(S,'name')+' / '+JS(S,'style'),TObject(NativeInt(JI(S,'styleId')))); end;
      end;
    finally O.Free; end;
    RefreshCue;
    O := Command('assets');
    try
      var SelectedGroup := FVariantGroup.Text;
      FAssets.Free; FAssets := O.Clone as TJSONObject; FVariantGroup.Items.Clear;
      if O.GetValue('groups')<>nil then for var V in JA(O,'groups') do FVariantGroup.Items.Add(JS(TJSONObject(V),'name'));
      FVariantGroup.ItemIndex := FVariantGroup.Items.IndexOf(SelectedGroup);
      if (FVariantGroup.ItemIndex<0) and (FVariantGroup.Items.Count>0) then FVariantGroup.ItemIndex := 0;
      VariantGroupChanged(Self);
    finally O.Free; end;
    O := Command('timeline'); var Wave := Command('waveform');
    try FTimeline.SetData(O,Wave); FTimeline.SetTime(FSession.Time); FTimeline.SelectCue(FSelectedId); finally O.Free; Wave.Free; end;
    RefreshSeek;
    FLastRevision := FSession.Project.Revision;
    TToolButton(FToolbar.FindComponent('MovieUndo')).Enabled := not FSession.Busy;
    TToolButton(FToolbar.FindComponent('MovieRedo')).Enabled := not FSession.Busy;
  finally FRefreshing := False; end;
end;
procedure TRigmMovieForm.SelectCue(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FRefreshing or not Selected or (Item.SubItems.Count<3) then Exit;
  if FDraftRevision<>0 then begin
    FRefreshing := True;
    try
      Item.Selected := False;
      for var I := 0 to FList.Items.Count-1 do
        if (FList.Items[I].SubItems.Count>=3) and (FList.Items[I].SubItems[2]=FSelectedId) then FList.Items[I].Selected := True;
    finally FRefreshing := False; end;
    Exit;
  end;
  FSelectedId := Item.SubItems[2]; RefreshCue;
  FTimeline.SelectCue(FSelectedId);
end;
procedure TRigmMovieForm.TimelineSelectCue(Sender: TObject);
begin
  if FDraftRevision<>0 then begin FTimeline.SelectCue(FSelectedId); Exit; end;
  for var I := 0 to FList.Items.Count-1 do
    if (FList.Items[I].SubItems.Count>=3) and (FList.Items[I].SubItems[2]=FTimeline.SelectedCueId) then begin
      FList.Items[I].Selected := True; FList.Items[I].MakeVisible(False); Exit;
    end;
end;
procedure TRigmMovieForm.SelectSpeaker(Sender: TObject);
var S: TRigmMovieSpeaker; WasRefreshing: Boolean;
begin
  WasRefreshing := FRefreshing; FRefreshing := True;
  try
  S := FSession.Project.Speaker(FSpeaker.Text); if S=nil then Exit;
  FSpeed.Text := FloatToStr(S.Speed,TFormatSettings.Invariant); FPitch.Text := FloatToStr(S.Pitch,TFormatSettings.Invariant); FStyle.ItemIndex := -1;
  for var I := 0 to FStyle.Items.Count-1 do if NativeInt(FStyle.Items.Objects[I])=S.StyleId then FStyle.ItemIndex := I;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieForm.SeekChanged(Sender: TObject);
begin
  if FRefreshing then Exit; SeekFrame(FSeek.Position);
end;
procedure TRigmMovieForm.TimelineSeek(Sender: TObject);
begin
  SeekFrame(Round(FTimeline.Time*Max(1,FSession.Project.Fps)));
end;
procedure TRigmMovieForm.SeekFrame(Frame: Integer);
begin
  StopPlayback;
  var FPS := Max(1,FSession.Project.Fps);
  var Last := Max(0,Ceil(Min(High(Integer)-1.0,FSession.Project.Duration*FPS))-1);
  var O := TJSONObject.Create; AddN(O,'time',EnsureRange(Frame,0,Last)/FPS); Run('seek',O);
  FPendingPreview := True; FSeekTick := GetTickCount64;
  FTimeline.SetTime(FSession.Time); RefreshSeek;
end;
procedure TRigmMovieForm.RefreshSeek;
begin
  if FSeek=nil then Exit;
  var WasRefreshing := FRefreshing; FRefreshing := True;
  try
    var FPS := Max(1,FSession.Project.Fps);
    var Last := Max(0,Ceil(Min(High(Integer)-1.0,FSession.Project.Duration*FPS))-1);
    var Frame := EnsureRange(Floor(FSession.Time*FPS+0.000001),0,Last);
    if FSeek.Max<>Max(1,Last) then FSeek.Max := Max(1,Last);
    FSeek.Enabled := FSession.Project.Duration>0;
    if FSeek.Position<>Frame then FSeek.Position := Frame;
    var Text := Format('フレーム %d / %d  %.2f秒',[Frame,Last,FSession.Time]);
    if FFramePosition.Caption<>Text then begin FFramePosition.Caption := Text; FFramePosition.Hint := Text; end;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieForm.ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if Handled or (Msg.message<>WM_MOUSEWHEEL) or not Showing or not Enabled then Exit;
  var Host := GetParentForm(Self,True); if (Host<>nil) and not Host.Enabled then Exit;
  var P := Point(SmallInt(LoWord(Msg.lParam)),SmallInt(HiWord(Msg.lParam)));
  var Hover := WindowFromPoint(P); var Delta := SmallInt(HiWord(Msg.wParam));
  if FPreview.HandleAllocated and ((Hover=FPreview.Handle) or IsChild(FPreview.Handle,Hover)) then begin
    FPreview.WheelAt(Delta,FPreview.ScreenToClient(P)); Handled := True;
  end else if FTimeline.HandleAllocated and ((Hover=FTimeline.Handle) or IsChild(FTimeline.Handle,Hover)) then begin
    FTimeline.WheelAt(Delta,FTimeline.ScreenToClient(P)); Handled := True;
  end else if FSeek.Enabled and FSeek.HandleAllocated and (Hover=FSeek.Handle) then begin
    FSeek.AdjustWheel(Delta); Handled := True;
  end;
end;
procedure TRigmMovieForm.ZoomChanged(Sender: TObject);
const Spans: array[0..3] of Double = (0,10,30,60);
begin if FZoom.ItemIndex>=0 then FTimeline.SetSpan(Spans[FZoom.ItemIndex]); end;
procedure TRigmMovieForm.OutputPresetChanged(Sender: TObject);
var W,H,F: Integer;
begin
  if FRefreshing or (FOutputPreset.ItemIndex<0) then Exit;
  DraftEdited(Sender);
  MoviePresetDimensions(OutputPresetIds[FOutputPreset.ItemIndex],W,H,F);
  if W>0 then FDimensions.Text := Format('%d x %d x %d',[W,H,F]);
end;
procedure TRigmMovieForm.PaintJobProgress(Sender: TObject);
begin
  FJobProgress.Canvas.Brush.Color := clBtnShadow; FJobProgress.Canvas.FillRect(FJobProgress.ClientRect);
  FJobProgress.Canvas.Brush.Color := $D09040;
  FJobProgress.Canvas.FillRect(Rect(0,0,Round(FJobProgress.Width*FJobPosition/1000),FJobProgress.Height));
end;
procedure TRigmMovieForm.RefreshPreparation;
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
      IntToStr(FDraftRevision)+'|'+FOutputPath.Text+'|'+JS(J,'jobId')+'|'+JS(J,'state');
  finally J.Free; end;
  if FPreparationStamp=Key then Exit;
  FPreparationStamp := Key;
  Inc(FStaticUiUpdates);
  A := TJSONObject.Create; A.AddPair('outputPath',FOutputPath.Text); O := Command('preparation',A);
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
      FWorkflow.Caption := '現在の工程: '+JS(Workflow,'title')+sLineBreak+JS(Workflow,'message');
      FNext.Enabled := JB(Workflow,'canNext') and (FDraftRevision=0);
      FRunStep.Enabled := JB(Workflow,'canRun') and ((FDraftRevision=0) or (JS(Workflow,'currentStage')='script'));
      FBackStep.Enabled := JB(Workflow,'canBack') and (FDraftRevision=0);
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
    if FPreparation.Text<>Lines.Text then FPreparation.Text := Lines.Text;
    // Refresh only catalog/asset selectors: do not overwrite pending editor text.
    if JB(J,'done',True) and (FSeenDiagnostic<>JS(J,'jobId')) then begin
      FSeenDiagnostic := JS(J,'jobId');
      A := Command('speaker-list');
      try
        var Catalog := JA(A,'styles'); var CatalogKey := Catalog.ToJSON;
        if CatalogKey<>FCatalogKey then begin
          var StyleId: NativeInt := -1;
          if FStyle.ItemIndex>=0 then StyleId := NativeInt(FStyle.Items.Objects[FStyle.ItemIndex]);
          FCatalogKey := CatalogKey; FStyle.Items.Clear;
          for var V in Catalog do begin var S := TJSONObject(V); FStyle.Items.AddObject(JS(S,'name')+' / '+JS(S,'style'),TObject(NativeInt(JI(S,'styleId')))); end;
          if StyleId<0 then begin var S := FSession.Project.Speaker(FSpeaker.Text); if S<>nil then StyleId := S.StyleId; end;
          for var I := 0 to FStyle.Items.Count-1 do if NativeInt(FStyle.Items.Objects[I])=StyleId then FStyle.ItemIndex := I;
        end;
      finally A.Free; end;
      A := Command('assets');
      try
        var GroupName := FVariantGroup.Text;
        FAssets.Free; FAssets := A.Clone as TJSONObject; FVariantGroup.Items.Clear;
        if A.GetValue('groups')<>nil then for var V in JA(A,'groups') do FVariantGroup.Items.Add(JS(TJSONObject(V),'name'));
        FVariantGroup.ItemIndex := FVariantGroup.Items.IndexOf(GroupName);
        if (FVariantGroup.ItemIndex<0) and (FVariantGroup.Items.Count>0) then FVariantGroup.ItemIndex := 0;
        VariantGroupChanged(Self);
      finally A.Free; end;
    end;
    var Cancel := TToolButton(FToolbar.FindComponent('MovieCancel'));
    Cancel.Enabled := FSession.Busy or JB(O,'diagnosticsBusy');
  finally Lines.Free; O.Free; end;
  finally FRefreshing := WasRefreshing; end;
end;
procedure TRigmMovieForm.VariantGroupChanged(Sender: TObject);
begin
  FVariant.Items.Clear; FVariant.Items.Add('保存済みの表示状態'); FVariant.ItemIndex := 0;
  if (FVariantGroup.ItemIndex<0) or (FAssets.GetValue('groups')=nil) then Exit;
  var Group := TJSONObject(JA(FAssets,'groups')[FVariantGroup.ItemIndex]);
  for var V in JA(Group,'children') do FVariant.Items.Add(JS(TJSONObject(V),'name')+' ['+JS(TJSONObject(V),'role')+']');
  var C := FSession.Project.Cue(FSelectedId); if C=nil then Exit;
  for var V in C.Acting.Variants do if JS(TJSONObject(V),'groupId')=JS(Group,'id') then
    for var I := 0 to JA(Group,'children').Count-1 do if JS(TJSONObject(JA(Group,'children')[I]),'id')=JS(TJSONObject(V),'partId') then FVariant.ItemIndex := I+1;
end;
procedure TRigmMovieForm.StartPlayback;
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
procedure TRigmMovieForm.StopPlayback;
begin
  if FPlaying then begin FPlaying := False; sndPlaySound(nil,SND_ASYNC); end;
  if (FSession<>nil) and FSession.Playing then Run('pause'); FAudioReady := False;
  FAudioPreparing := False; RefreshTransport;
end;
function JobText(Job: TJSONObject): string;
var Phase,State: string; Completed,Total,Remaining: Double;
begin
  Phase := JS(Job,'phase'); State := JS(Job,'state');
  if Phase='prepare-character' then Phase := 'キャラクター読込'
  else if Phase='prepare-audio' then Phase := '音声の準備'
  else if Phase='render' then Phase := '映像の作成'
  else if Phase='encode' then Phase := '動画の圧縮'
  else begin
    Phase := JS(Job,'kind');
    if Phase='production' then Phase := '一括制作'
    else if Phase='preview' then Phase := 'プレビュー'
    else if Phase='audio' then Phase := '音声生成'
    else if Phase='assets' then Phase := '素材読込'
    else if Phase='waveform' then Phase := '波形の作成'
    else if Phase='speakers' then Phase := '話者取得'
    else if Phase='playback-audio' then Phase := '再生の準備';
  end;
  if State='blocked' then State := '不足情報待ち' else if State='succeeded' then State := '完了' else if State='failed' then State := '失敗'
  else if State='cancelled' then State := '取消済み' else if JB(Job,'cancelRequested') then State := '取消中'
  else State := '処理中';
  Completed := JN(Job,'phaseCompleted'); Total := JN(Job,'phaseTotal');
  if Total=0 then begin Completed := JN(Job,'completed'); Total := JN(Job,'total'); end;
  Result := Phase+' '+State;
  if Total>0 then Result := Result+Format(' %.0f%%',[Min(100,Completed/Total*100)]);
  if JN(Job,'elapsedSeconds')>0 then Result := Result+Format(' 経過 %.0f秒',[JN(Job,'elapsedSeconds')]);
  Remaining := JN(Job,'remainingSeconds',-1);
  if not JB(Job,'done') then begin
    if Remaining>=0 then Result := Result+Format(' この工程の残り約%.0f秒',[Remaining])
    else Result := Result+' 残り時間を計算中';
  end;
  if JS(Job,'error')<>'' then Result := Result+' '+JS(Job,'error');
  if Job.GetValue('production')<>nil then begin
    var Needs := JA(JO(Job,'production'),'needs');
    if Needs.Count>0 then Result := Result+' '+JS(TJSONObject(Needs[0]),'message');
  end;
end;
procedure TRigmMovieForm.RefreshTransport;
begin
  if FPlayButton=nil then Exit;
  var CanPlay := not FSession.Playing and not FAudioPreparing and FSession.CanEdit and (FSession.Project.Cues.Count>0);
  var CanStop := FSession.Playing or FPlaying or FAudioPreparing;
  if FPlayButton.Enabled<>CanPlay then FPlayButton.Enabled := CanPlay;
  if FStopButton.Enabled<>CanStop then FStopButton.Enabled := CanStop;
  var CanExport := FSession.CanEdit and not FSession.GuiLocked and (FSession.Project.Cues.Count>0);
  if FExportButton.Enabled<>CanExport then FExportButton.Enabled := CanExport;
end;
procedure TRigmMovieForm.LayoutTransport;
begin
  if FExportButton=nil then Exit;
  if FSplitterDragging then begin FPendingSplitterLayout := True; Exit; end;
  var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  var P := MulDiv(8,PPI,96); var W := MulDiv(96,PPI,96); var H := MulDiv(28,PPI,96);
  var Y := MulDiv(8,PPI,96); var ExportW := MulDiv(130,PPI,96); var FitW := MulDiv(150,PPI,96);
  FTransport.SetBounds(0,0,Max(FTransportScroll.ClientWidth,2*W+ExportW+FitW+P*5),H+Y*2);
  FPlayButton.SetBounds(P,Y,W,H); FStopButton.SetBounds(W+P*2,Y,W,H);
  FExportButton.SetBounds(W*2+P*3,Y,ExportW,H);
  FFitPreview.SetBounds(W*2+ExportW+P*4,Y,FitW,H);
  FTransportScroll.HorzScrollBar.Range := FTransport.Width;
  FTransportScroll.Height := H+Y*2+MulDiv(17,PPI,96);
  TPanel(FSeek.Parent).Height := MulDiv(64,PPI,96);
  TPanel(FFramePosition.Parent).Height := MulDiv(26,PPI,96);
  FFramePosition.Font.Height := -MulDiv(15,PPI,96);
  FZoom.Width := MulDiv(100,PPI,96);
  LayoutExportFeedback;
end;
function TRigmMovieForm.ExportNotificationRequests: Integer;
begin Result := FExportNotification.Requests; end;
function TRigmMovieForm.ExportNotificationsShown: Integer;
begin Result := FExportNotification.Shown; end;
procedure TRigmMovieForm.LayoutExportFeedback;
begin
  if FExportPanel=nil then Exit;
  var Host := GetParentForm(Self,True); var PPI := CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  FExportPanel.Height := MulDiv(78,PPI,96);
  FExportResult.Width := MulDiv(130,PPI,96); FExportProgress.Height := MulDiv(10,PPI,96);
  FExportStatus.Font.Height := -MulDiv(15,PPI,96);
  FExportStatus.Margins.Left := MulDiv(10,PPI,96); FExportStatus.Margins.Right := MulDiv(10,PPI,96);
  FExportStatus.AlignWithMargins := True;
end;
procedure TRigmMovieForm.ShowExportError(const Message: string);
begin
  if (FExportJobId<>'') and FSession.Busy then begin FExportWarning := Message; RefreshExport; Exit; end;
  FExportJobId := '';
  FExportError := Message; FLastError := ''; FExportPanel.Visible := True;
  FExportStatus.Caption := Message; FExportStatus.Hint := Message;
  FExportResult.Caption := '保存先を選び直す'; FExportResult.Tag := 13; FExportResult.Enabled := True;
end;
procedure TRigmMovieForm.ChooseExport(const Extension: string);
var Dialog: TSaveDialog; A,Reply: TJSONObject; Encoder: string;
begin
  StopPlayback;
  if FSession.GuiLocked then raise ERigm.Create('Codex編集中です。制作ページで編集ロックを解除してから書き出してください。');
  if not FSession.CanEdit then raise ERigm.Create('処理中のジョブが終わるか、中止してから書き出してください。');
  if FTextPending and FOnlyTextDraft and (FDraftRevision=FSession.Project.Revision) then begin
    A := TJSONObject.Create; A.AddPair('id',FSelectedId); A.AddPair('text',FDialogue.Text); A.AddPair('subtitle',FSubtitle.Text); Run('update-cue',A);
  end;
  if FDraftRevision<>0 then raise ERigm.Create('未適用の編集があります。右側の適用ボタンで反映してから書き出してください。');
  FExportWarning := '';
  for var Cue in FSession.Project.Cues do if not FSession.Project.AudioReady(Cue) then begin
    if not FSession.Project.HasStoredAudio(Cue) then raise ERigm.Create('音声が未生成です。制作メニューの「必要な音声を再生成」で作成してから書き出してください。');
    if FSession.Project.Scenes.Count=0 then raise ERigm.Create('音声用テキストの変更が未反映です。制作メニューから必要な音声を再生成してください。');
    FExportWarning := 'セリフ変更は音声に未反映です。保存済み音声を使用しています。';
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
    FPendingPreview := False; FExportError := ''; FCompletedExport := '';
    A := TJSONObject.Create; A.AddPair('outputTarget',Target); A.AddPair('ffmpeg',Encoder); Run('update-project',A);
    A := TJSONObject.Create; A.AddPair('path',Target); Reply := Command('export',A);
    try FExportJobId := JS(Reply,'jobId'); FExportProject := FSession.Project.Id; FExportFinished := False; finally Reply.Free; end;
    FExportPanel.Visible := True; FStatus.Visible := False; RefreshExport;
  finally Dialog.Free; end;
end;
procedure TRigmMovieForm.RefreshExport;
begin
  // Observe exports started through either the GUI or the shared pipe.
  if FSession.CurrentJobKind='export' then begin
    var Current := Command('job-status');
    try
      if (JS(Current,'snapshotProjectId')=FSession.Project.Id) and
        (JS(Current,'jobId')<>FExportJobId) then begin
        FExportJobId := JS(Current,'jobId'); FExportProject := FSession.Project.Id;
        FCompletedExport := ''; FExportError := ''; FExportRefreshTick := 0; FExportFinished := False;
      end;
    finally Current.Free; end;
  end;
  if (FExportJobId='') or (FExportProject<>FSession.Project.Id) or FExportFinished then Exit;
  var A := TJSONObject.Create; A.AddPair('jobId',FExportJobId); var Job := Command('job-status',A);
  try
    if not JB(Job,'done') and (GetTickCount64-FExportRefreshTick<200) then Exit;
    FExportRefreshTick := GetTickCount64;
    var Text := 'MP4 / AVI 書き出し: '+JobText(Job);
    if (JS(Job,'phase')='render') and (JN(Job,'phaseTotal')>0) then
      Text := Text+Format('  %.0f / %.0f フレーム',[JN(Job,'phaseCompleted'),JN(Job,'phaseTotal')]);
    if FExportWarning<>'' then Text := Text+sLineBreak+FExportWarning;
    FExportResult.Tag := 9; FExportResult.Caption := '書き出しを中止';
    if JB(Job,'done') then begin
      if (JS(Job,'state')='succeeded') and JB(Job,'collected') and
        (not SameText(ExtractFileExt(JS(Job,'output')),'.mp4') or JB(Job,'encoderExited')) and
        FileExists(JS(Job,'output')) then begin
        FCompletedExport := JS(Job,'output'); Text := '動画を書き出しました: '+ExtractFileName(FCompletedExport);
        if FExportWarning<>'' then Text := Text+sLineBreak+FExportWarning;
        FExportResult.Caption := '保存先を開く'; FExportResult.Tag := 40;
        if FNotifiedExport<>FExportJobId then begin
          FNotifiedExport := FExportJobId;
          FExportNotification.ExportFinished(FCompletedExport);
        end;
      end else begin
        Text := '動画書き出し: '+JobText(Job); FExportResult.Caption := '保存先を選び直す'; FExportResult.Tag := 13;
      end;
    end;
    var KnownProgress := JN(Job,'phaseTotal')>0;
    var Style := pbstNormal;
    if not KnownProgress and not JB(Job,'done') then Style := pbstMarquee;
    if FExportProgress.Style<>Style then FExportProgress.Style := Style;
    var Position := 0;
    if KnownProgress then Position := Round(EnsureRange(JN(Job,'phaseCompleted')/JN(Job,'phaseTotal'),0.0,1.0)*1000);
    if (JS(Job,'state')='succeeded') and JB(Job,'done') then Position := 1000;
    if FExportProgress.Position<>Position then FExportProgress.Position := Position;
    FExportFinished := JB(Job,'done') and ((JS(Job,'state')<>'succeeded') or (FCompletedExport<>''));
    FExportResult.Enabled := not JB(Job,'cancelRequested') or JB(Job,'done');
    if FExportStatus.Caption<>Text then FExportStatus.Caption := Text;
    FExportStatus.Hint := JS(Job,'output')+sLineBreak+Text;
    if not FExportPanel.Visible then begin
      LayoutExportFeedback;
      FExportPanel.SetBounds(0,ClientHeight-FExportPanel.Height,ClientWidth,FExportPanel.Height);
      FExportPanel.Visible := True; FExportPanel.BringToFront; Realign;
    end;
  finally Job.Free; end;
end;
procedure TRigmMovieForm.PreviewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key<>VK_SPACE) or (Shift<>[]) or (ActiveControl is TCustomEdit) or (ActiveControl is TCustomCombo) then Exit;
  if FSession.Playing then StopPlayback
  else if FPlayButton.Enabled then Run('play');
  RefreshTransport; Key := 0;
end;
procedure TRigmMovieForm.Tick(Sender: TObject);
var O: TJSONObject; Frame: Vcl.Graphics.TBitmap; Job: TJSONObject; Time: Double; Text: string;
begin
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
      O := TJSONObject.Create; O.AddPair('id',FSelectedId); O.AddPair('text',FDialogue.Text); O.AddPair('subtitle',FSubtitle.Text);
      Run('update-cue',O); FLastRevision := FSession.Project.Revision;
      FreeAndNil(Frame); FDrawnRevision := -1;
      FPendingPreview := True; FSeekTick := GetTickCount64;
      var Timeline := Command('timeline'); var Wave := Command('waveform');
      try FTimeline.SetData(Timeline,Wave); finally Timeline.Free; Wave.Free; end;
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
          FPreview.SetFrame(Frame); FDrawnFrame := Floor(FSession.FrameTime*FSession.Project.Fps);
          FDrawnRevision := FSession.Project.Revision;
        end;
      finally Frame.Free; end;
    end;
    FTimeline.SetTime(FSession.Time);
    if GetTickCount64-FStatusTick>=200 then begin
      FStatusTick := GetTickCount64; O := FSession.Status;
      try
        Text := Format('  %.2f / %.2f 秒　%s　%s',[FSession.Time,FSession.Project.Duration,IfThen(FSession.Project.Modified,'未保存','保存済'),FSession.Project.FileName]);
        if O.GetValue('job')<>nil then begin
          Job := JO(O,'job'); Text := Text+sLineBreak+'  '+JobText(Job);
          var ShowProgress := not MatchText(JS(Job,'kind'),['preview','export']) and not JB(Job,'done') and (JN(Job,'phaseTotal')>0);
          if FJobProgress.Visible<>ShowProgress then FJobProgress.Visible := ShowProgress;
          if JN(Job,'phaseTotal')>0 then begin
            var Position := Round(EnsureRange(JN(Job,'phaseCompleted')/JN(Job,'phaseTotal'),0.0,1.0)*1000);
            if FJobPosition<>Position then begin FJobPosition := Position; FJobProgress.Invalidate; end;
          end;
          if JB(Job,'done') and (FSeenJob<>JS(Job,'jobId')) then begin
            FSeenJob := JS(Job,'jobId');
            if MatchText(JS(Job,'kind'),['speakers','assets','waveform']) then RefreshView;
          end;
        end;
        if FLastError<>'' then Text := Text+sLineBreak+'  '+FLastError;
        if FSession.GuiLocked then Text := Text+sLineBreak+'  Codex編集中 — 手動解除は作成ページのロック解除';
        FDialogue.ReadOnly := FSession.GuiLocked; FSubtitle.ReadOnly := FSession.GuiLocked;
        FScript.ReadOnly := FSession.GuiLocked;
        if (FLastError<>'') and (FStatus.Caption<>FLastError) then FStatus.Caption := FLastError;
        if FStatus.Visible<>(FLastError<>'') then FStatus.Visible := FLastError<>'';
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
    if FClosing and not FSession.Busy then begin FClosing := False; Close; end;
  except on E: Exception do begin StopPlayback; FLastError := E.Message; if FStatus.Caption<>FLastError then FStatus.Caption := FLastError; end; end;
end;
procedure TRigmMovieForm.ActionClick(Sender: TObject);
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
          Chart.AddPair('kind',MovieChartKinds[EnsureRange(FChartKind.ItemIndex,0,2)]);
          if FChartKind.ItemIndex>0 then begin
            Chart.AddPair('title',FChartTitle.Text); AddN(Chart,'maximum',StrToFloat(FChartMaximum.Text,TFormatSettings.Invariant));
            var ColorValue := ColorToRGB(FChartColor.Selected);
            Chart.AddPair('color','#'+IntToHex(GetRValue(ColorValue),2)+IntToHex(GetGValue(ColorValue),2)+IntToHex(GetBValue(ColorValue),2));
            var Items := TJSONArray.Create; Chart.AddPair('items',Items);
            for var Line in FChartItems.Lines do if Line.Trim<>'' then begin
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
      43: begin FPreview.Fit; Exit; end;
      34: begin FScriptPanel.Visible := not FScriptPanel.Visible; EditingAreaResize(Self); end;
      35: FSettings.Visible := not FSettings.Visible;
      38: begin
        SelectPropertyPage('diagnostics'); RefreshPreparation; Exit;
      end;
      13,39: begin ChooseExport(IfThen(TComponent(Sender).Tag=13,'mp4','avi')); RefreshView; Exit; end;
      40: begin
        if FileExists(FCompletedExport) then ShellExecute(Handle,'open',PChar(ExtractFileDir(FCompletedExport)),nil,nil,SW_SHOWNORMAL);
        Exit;
      end;
      1,3,4,17,22: begin
        StopPlayback; OpenDialog := TOpenDialog.Create(Self);
        try
          OpenDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing,ofNoChangeDir];
          case TComponent(Sender).Tag of
            1: OpenDialog.Filter := '動画プロジェクト (*.rigmovie)|*.rigmovie';
            3: OpenDialog.Filter := 'RIGM (*.rigm)|*.rigm';
            4: OpenDialog.Filter := '台本 (*.txt;*.json)|*.txt;*.json';
            17: OpenDialog.Filter := 'シーン画像 (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp';
            22: OpenDialog.Filter := 'FFmpeg (ffmpeg.exe)|ffmpeg.exe';
          end;
          if OpenDialog.Execute then begin
            O := TJSONObject.Create;
            case TComponent(Sender).Tag of
              1: begin
                if Assigned(FOnOpenWork) then begin O.Free; FOnOpenWork(OpenDialog.FileName); end
                else if FSession.Project.Modified or (FDraftRevision<>0) then begin
                  O.Free;
                  var Host := TRigmEditorForm.Create(Application.MainForm);
                  try
                    O := TJSONObject.Create;
                    try O.AddPair('path',OpenDialog.FileName); O.AddPair('projectId',Host.Editor.Movie.Project.Id); AddN(O,'revision',Host.Editor.Movie.Project.Revision);
                      var Reply := Host.Editor.Movie.Execute('open',O); Reply.Free;
                    finally O.Free; end;
                    Host.Show; Host.ShowMovieStudio(Self);
                  except Host.Free; raise; end;
                end else begin O.AddPair('path',OpenDialog.FileName); Run('open',O); end;
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
        O := TJSONObject.Create; O.AddPair('title',FTitle.Text); O.AddPair('engineUrl',FEngine.Text);
        var Values := string(FDimensions.Text).Replace('×','x').Split(['x']);
        if Length(Values)<>3 then begin O.Free; raise ERigm.Create('幅 x 高さ x fps を指定してください。'); end;
        AddN(O,'width',StrToInt(Trim(Values[0]))); AddN(O,'height',StrToInt(Trim(Values[1]))); AddN(O,'fps',StrToInt(Trim(Values[2]))); O.AddPair('encodeProfile',EncodeProfileIds[Max(0,FEncodeProfile.ItemIndex)]); O.AddPair('outputTarget',FOutputPath.Text); Run('update-project',O);
      end;
      15: begin O := TJSONObject.Create; O.AddPair('character','@sample'); Run('update-project',O); end;
      16: begin O := TJSONObject.Create; O.AddPair('id',FSelectedId);
          if FPropertyPage=2 then begin
            O.AddPair('expression',FExpression.Text); O.AddPair('motion',FMotion.Text);
            if FEmotion.ItemIndex>=0 then O.AddPair('emotion',MovieEmotionIds[NativeInt(FEmotion.Items.Objects[FEmotion.ItemIndex])]);
          end
        else begin O.AddPair('scene',FScene.Text); O.AddPair('speaker',FSpeaker.Text);
          O.AddPair('text',Trim(FDialogue.Text)); O.AddPair('subtitle',Trim(FSubtitle.Text));
          AddN(O,'pause',StrToFloat(FPause.Text,TFormatSettings.Invariant)); end;
        Run('update-cue',O);
      end;
      18: begin O := TJSONObject.Create; var Cue := TRigmMovieCue.Create; try Cue.SpeakerId := FSpeaker.Text; if FSession.Project.Speaker(Cue.SpeakerId)=nil then Cue.SpeakerId := FSession.Project.Speakers[0].Id; O.AddPair('cue',Cue.Json); finally Cue.Free; end; Run('add-cue',O); end;
      19: begin O := TJSONObject.Create; O.AddPair('id',FSelectedId); Run('delete-cue',O); FSelectedId := ''; end;
      20: begin
        if FStyle.ItemIndex<0 then raise ERigm.Create('話者一覧を取得して音声を選んでください。');
        O := TJSONObject.Create; O.AddPair('id',FSpeaker.Text); AddN(O,'styleId',NativeInt(FStyle.Items.Objects[FStyle.ItemIndex]));
        AddN(O,'speed',StrToFloat(FSpeed.Text,TFormatSettings.Invariant)); AddN(O,'pitch',StrToFloat(FPitch.Text,TFormatSettings.Invariant)); Run('update-speaker',O);
      end;
      21: begin O := TJSONObject.Create; O.AddPair('text',FScript.Text); Run('import-script',O); end;
      23: Run('assets-refresh'); 24: Run('waveform-refresh');
      41: begin
        var Cue := FSession.Project.Cue(FSelectedId); if Cue=nil then raise ERigm.Create('場面を選択してください');
        if FSession.Project.Scene(Cue.Scene)=nil then raise ERigm.Create('構成作品の場面を選択してください');
        O := TJSONObject.Create; O.AddPair('id',Cue.Scene); O.AddPair('title',FSceneTitle.Text);
        O.AddPair('description',FSceneDescription.Text); Run('update-scene',O);
        O := TJSONObject.Create; O.AddPair('layout',IfThen(FLayoutChoice.ItemIndex=0,'theme','l'));
        O.AddPair('lDirection',IfThen(FLayoutChoice.ItemIndex=1,'left','right')); Run('update-project',O);
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
        if FSession.Project.WorkflowStage='script' then begin O.AddPair('text',FScript.Text); Run('import-script',O); end
        else begin
          if FDraftRevision<>0 then raise ERigm.Create('未適用の編集を適用してから結果を作成してください。');
          Run('workflow-run',O);
        end;
      end;
      32: Run('workflow-back');
      33: begin FDraftRevision := 0; FReloadDraft.Visible := False; RefreshView; end;
      28: begin Run('diagnostics-refresh'); TScrollBox(FPreparation.Parent).VertScrollBar.Position := FPreparation.Top-24; RefreshPreparation; Exit; end;
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
          FScript.SelectAll; FScript.SelText := JS(TJSONObject(Examples[Max(0,FExamples.ItemIndex)]),'text');
          FScript.SelStart := 0; FScript.SelLength := 0; FScript.Perform(EM_SCROLLCARET,0,0); FScript.SetFocus;
        finally Examples.Free; end;
        RefreshPreparation; Exit;
      end;
      25,26: begin
        var C := FSession.Project.Cue(FSelectedId); if C=nil then raise ERigm.Create('セリフを選択してください。');
        var Acting := C.Acting.Json;
        try
          for var I := 0 to 11 do begin Acting.RemovePair(MovieActingKeys[I]).Free; AddN(Acting,MovieActingKeys[I],StrToFloat(FActing[I].Text,TFormatSettings.Invariant)); end;
          Acting.RemovePair('mouthMode').Free; Acting.AddPair('mouthMode',FeatureModeIds[Max(0,FMouthMode.ItemIndex)]);
          Acting.RemovePair('blinkMode').Free; Acting.AddPair('blinkMode',FeatureModeIds[Max(0,FBlinkMode.ItemIndex)]);
          Acting.RemovePair('imageAttention').Free;
          Acting.AddPair('imageAttention',ImageAttentionModes[EnsureRange(FImageAttention.ItemIndex,0,2)]);
          var Variants := TJSONArray.Create;
          if TComponent(Sender).Tag=25 then begin
            var GroupId := ''; if (FVariantGroup.ItemIndex>=0) and (FAssets.GetValue('groups')<>nil) then GroupId := JS(TJSONObject(JA(FAssets,'groups')[FVariantGroup.ItemIndex]),'id');
            for var V in C.Acting.Variants do if JS(TJSONObject(V),'groupId')<>GroupId then Variants.AddElement(V.Clone as TJSONObject);
            if (GroupId<>'') and (FVariant.ItemIndex>0) then begin
              var Group := TJSONObject(JA(FAssets,'groups')[FVariantGroup.ItemIndex]); var Choice := TJSONObject.Create;
              Choice.AddPair('groupId',GroupId); Choice.AddPair('partId',JS(TJSONObject(JA(Group,'children')[FVariant.ItemIndex-1]),'id')); Variants.AddElement(Choice);
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
      16: if FPropertyPage=2 then AppliedPage := 2 else AppliedPage := 0;
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
    else begin FLastError := E.Message; FStatus.Caption := E.Message; end;
  end; end;
end;
procedure TRigmMovieForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  StopPlayback; AppSettings.RememberPosition(FSession.Project,FSession.Time,FSelectedId); CanClose := not FSession.Busy;
  if not CanClose then begin Run('job-cancel'); FClosing := True; FStatus.Caption := '取消処理が終わるまで制作画面を保持しています。'; end;
  if CanClose and FSession.Project.Modified then begin
    var Directory := TPath.Combine(AppSettings.Root,'Recovery');
    var Snapshot := FSession.Project.Clone;
    try SaveMovie(Snapshot,TPath.Combine(Directory,'recovery-'+NewRigmId+'.rigmovie')); AppSettings.RecordRecovery(FSession.Project,Snapshot.FileName,FSession.Time,FSelectedId); finally Snapshot.Free; end;
  end;
end;
procedure TRigmMovieForm.Closed(Sender: TObject; var Action: TCloseAction);
begin Action := caHide; end;
end.
