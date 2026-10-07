// 動画編集画面のコントロール生成とイベント配線を担当する。
// 作品編集や再生状態は保持せず、操作は呼び出し側のコールバックへ通知する。
unit RigmMovieControls;
interface
uses Winapi.Windows, System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.AppEvnts, RigmIconToolbar, RigmMovieTimeline, RigmMoviePreview,
  RigmPropertyScrollBox, RigmMovieNotification, RigmMoviePropertyPages;
type
  TRigmMovieUiCallbacks = record
    ActionClick         : TNotifyEvent;       // ボタンのTagに対応する作品操作の要求。
    OutputPresetChanged : TNotifyEvent;       // 出力プリセット選択による寸法入力の更新。
    PaintJobProgress    : TNotifyEvent;       // 汎用ジョブ進捗バーの描画。
    TimelineSeek        : TNotifyEvent;       // タイムラインの指定時刻への移動。
    TimelineSelectCue   : TNotifyEvent;       // タイムラインで選んだ区間への属性切替。
    ZoomChanged         : TNotifyEvent;       // タイムラインの表示時間幅の変更。
    SeekChanged         : TNotifyEvent;       // フレームスライダーによる再生位置の変更。
    LayoutProperties    : TNotifyEvent;       // 属性パネルの寸法変更に伴う再配置。
    DraftEdited         : TNotifyEvent;       // 未適用入力の発生。作品への適用は別操作。
    SelectSpeaker       : TNotifyEvent;       // 区間の話者選択に伴う音声設定の表示。
    VariantGroupChanged : TNotifyEvent;       // 実在素材グループに対応する候補一覧の更新。
    SplitterBeforeResize: TNotifyEvent;       // ドラッグ開始時の最小寸法設定と描画抑止。
    SplitterCanResize   : TCanResizeEvent;    // ドラッグ寸法の受入判定と有効範囲への補正。
    SplitterAfterResize : TNotifyEvent;       // ドラッグ終了時の保留配置と描画の再開。
    EditingAreaResize   : TNotifyEvent;       // 中央編集領域の最小寸法とスクロール範囲の更新。
    SelectCue           : TLVSelectItemEvent; // 台本一覧の区間選択。解除通知も届く。
    ApplicationMessage  : TMessageEvent;      // カーソル位置に応じたホイール入力の振分け。
    Tick                : TNotifyEvent;       // ジョブ回収と再生・プレビューの定期更新。
  end;
  TRigmMovieControls = class
  private
    FOwner    : TWinControl;                   // コントロールを所有する借用先。フォームより先に本オブジェクトを破棄する。
    FCallbacks: TRigmMovieUiCallbacks;
    FPages    : TRigmMoviePropertyPages; // 所有するページ配置部品。イベント配線より先に生成する。
    function Edit(Parent: TWinControl; const Name,Caption: string; X,Y,W: Integer): TEdit;
    function Combo(const Name,Caption: string; X,Y,W: Integer): TComboBox;
    procedure Button(Parent: TWinControl; const Name,Caption: string; Tag,X,Y,W: Integer);
  public
    Acting            : array[0..11] of TEdit;  // MovieActingKeysと同じ順序の演技値。
    BackStep          : TButton;
    BlinkMode         : TComboBox;
    Bottom            : TPanel;
    Character         : TEdit;
    ChartColor        : TColorBox;
    ChartItems        : TMemo;
    ChartKind         : TComboBox;
    ChartMaximum      : TEdit;
    ChartTitle        : TEdit;
    Dialogue          : TMemo;
    Dimensions        : TEdit;                  // 幅×高さ×fpsの下書き。プリセットからの入力にも使う。
    EditHost          : TPanel;
    EditScroll        : TScrollBox;
    Emotion           : TComboBox;
    EncodeProfile     : TComboBox;
    Engine            : TEdit;
    Examples          : TComboBox;
    ExportButton      : TButton;
    ExportNotification: TRigmMovieNotification;
    ExportPanel       : TPanel;
    ExportProgress    : TProgressBar;
    ExportResult      : TButton;                // 出力状態に応じて取消・保存先変更・フォルダー表示を切り替える。
    ExportStatus      : TLabel;
    Expression        : TComboBox;
    FitPreview        : TButton;
    FramePosition     : TLabel;
    ImageAttention    : TComboBox;
    JobProgress       : TPaintBox;
    LayoutChoice      : TComboBox;
    List              : TListView;
    Motion            : TComboBox;
    MouthMode         : TComboBox;
    Next              : TButton;
    OutputPath        : TEdit;
    OutputPreset      : TComboBox;
    Pause             : TEdit;
    Pitch             : TEdit;
    PlayButton        : TButton;
    Preparation       : TMemo;                  // 読取専用の診断結果。DraftEditedの対象から除外する。
    Preview           : TRigmMoviePreview;
    PreviewArea       : TPanel;
    PropertyBar       : TRigmIconToolbar;
    PropertyHost      : TPanel;
    PropertySplitter  : TSplitter;
    ReloadDraft       : TButton;
    Right             : TRigmPropertyScrollBox;
    RunStep           : TButton;
    Scene             : TEdit;                  // 選択区間の場面ID。場面名と区別する読取専用欄。
    SceneDescription  : TMemo;
    SceneTitle        : TEdit;
    ImageEnter,ImageExit: TComboBox;
    ImageEnterSeconds,ImageExitSeconds: TEdit;
    BgmPath,BgmVolume,BgmFadeOut: TEdit;
    Script            : TMemo;
    ScriptPanel       : TPanel;
    Seek              : TRigmFineTrackBar;
    Settings          : TPanel;
    Speaker           : TComboBox;
    Speed             : TEdit;
    Status            : TLabel;
    StopButton        : TButton;
    Style             : TComboBox;
    Subtitle          : TMemo;
    Timeline          : TRigmMovieTimeline;
    TimelineSplitter  : TSplitter;
    Timer             : TTimer;                 // 40 ms間隔で操作側へ通知する。作品の状態は保持しない。
    Title             : TEdit;
    Toolbar           : TRigmIconToolbar;
    Transport         : TPanel;
    TransportScroll   : TScrollBox;
    TransportStatus   : TLabel;
    Variant           : TComboBox;
    VariantGroup      : TComboBox;
    WheelEvents       : TApplicationEvents;
    WholeMotionStatus : TLabel;
    Workflow          : TLabel;
    WorkflowPanel     : TPanel;
    Zoom              : TComboBox;              // コントロールはOwnerが所有し、ページ配置状態だけを本オブジェクトが所有する。
    constructor Create(Owner: TWinControl);
    // 所有するページ管理を解放する。VCLコントロールはOwnerの破棄まで保持する。
    destructor Destroy; override;
    // 96 DPIで一度だけ画面を構築する。Callbacksの所有者は本画面より長く生存する必要がある。
    procedure Build(const Callbacks: TRigmMovieUiCallbacks);
    property Pages: TRigmMoviePropertyPages read FPages; // 非所有参照。Build完了後からフォーム破棄前まで有効。
  end;
implementation
uses System.SysUtils, System.Math, RigmToolbarIcons, RigmMovieUiValues;
constructor TRigmMovieControls.Create(Owner: TWinControl);
begin inherited Create; FOwner := Owner; end;
destructor TRigmMovieControls.Destroy;
begin FPages.Free; inherited; end;
function TRigmMovieControls.Edit(Parent: TWinControl; const Name,Caption: string; X,Y,W: Integer): TEdit;
  begin
    var L := TLabel.Create(FOwner); L.Parent := Parent; L.Caption := Caption; L.SetBounds(X,Y,W,20);
    Result := TEdit.Create(FOwner); Result.Parent := Parent; Result.Name := Name; Result.Text := ''; Result.SetBounds(X,Y+20,W,26);
    if Parent=Right then FPages.AddProperty(L,Result,Y,X,W,26);
  end;
function TRigmMovieControls.Combo(const Name,Caption: string; X,Y,W: Integer): TComboBox;
  begin
    var L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := Caption; L.SetBounds(X,Y,W,20);
    Result := TComboBox.Create(FOwner); Result.Parent := Right; Result.Name := Name; Result.Style := csDropDownList; Result.SetBounds(X,Y+20,W,26);
    FPages.AddProperty(L,Result,Y,X,W,26);
  end;
procedure TRigmMovieControls.Button(Parent: TWinControl; const Name,Caption: string; Tag,X,Y,W: Integer);
  var B: TButton;
  begin B := TButton.Create(FOwner); B.Parent := Parent; B.Name := Name; B.Caption := Caption; B.Tag := Tag; B.SetBounds(X,Y,W,28); B.OnClick := FCallbacks.ActionClick;
    if Parent=Right then FPages.AddProperty(nil,B,Y,X,W,28);
  end;
procedure TRigmMovieControls.Build(const Callbacks: TRigmMovieUiCallbacks);
var Panel,Bar: TPanel; Splitter: TSplitter; L: TLabel;
begin
  FCallbacks := Callbacks;
  Toolbar := TRigmIconToolbar.Create(FOwner); Toolbar.Parent := FOwner; Toolbar.Align := alTop; Toolbar.Name := 'MovieToolbar';
  Toolbar.Visible := False;
  Toolbar.AddIcon('MovieOpen','制作プロジェクトを開く',riOpen,1,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieSave','制作プロジェクト保存',riSave,2,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieCharacter','RIGMキャラクターを選ぶ',riSample,3,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieImport','台本テキスト / JSONを開く',riPng,4,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieUndo','制作を元に戻す',riUndo,5,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieRedo','制作をやり直す',riRedo,6,FCallbacks.ActionClick);
  Toolbar.AddSeparator;
  Toolbar.AddIcon('MovieVoices','VOICEVOX話者一覧を取得',riRefresh,7,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieAudio','台本から音声を生成（未生成だけ）',riGenerate,8,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieCancel','ジョブ取消',riDelete,9,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieRetry','ジョブ再試行',riRefresh,10,FCallbacks.ActionClick);
  Toolbar.AddIcon('MoviePreview','現在時刻をプレビュー',riPreview,11,FCallbacks.ActionClick);
  Toolbar.AddIcon('MoviePlay','再生 / 停止',riDirect,12,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieExport','音声付きAVI / MP4を書き出す',riSaveAs,13,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieFfmpeg','MP4用の既存FFmpegを選ぶ',riOpen,22,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieAssets','既存キャラクター素材一覧を取得',riSample,23,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieWaveform','音声波形を取得',riRefresh,24,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieShowScript','台本入力を表示 / 隠す',riEditPreview,34,FCallbacks.ActionClick);
  Toolbar.AddIcon('MovieShowSettings','出力・接続の詳細設定を表示 / 隠す',riRefresh,35,FCallbacks.ActionClick);
  Settings := TPanel.Create(FOwner); Settings.Parent := FOwner; Settings.Align := alTop; Settings.Height := 146; Settings.BevelOuter := bvNone;
  Settings.Visible := False;
  Title := Edit(Settings,'MovieTitle','動画タイトル',12,2,270);
  Engine := Edit(Settings,'MovieEngineUrl','VOICEVOX接続先（このPC）',292,2,240);
  Dimensions := Edit(Settings,'MovieDimensions','幅 × 高さ × fps',542,2,170);
  Character := Edit(Settings,'MovieCharacterPath','キャラクター',722,2,295); Character.ReadOnly := True;
  Button(Settings,'MovieApplySettings','設定を適用',14,12,106,120);
  Button(Settings,'MovieSampleCharacter','テスト用キャラ',15,142,106,120);
  L := TLabel.Create(FOwner); L.Parent := Settings; L.Caption := '台本を取り込み → 実在する話者を選択 → 音声生成 → プレビュー → 動画出力'; L.SetBounds(280,110,730,24);
  L := TLabel.Create(FOwner); L.Parent := Settings; L.Caption := '出力サイズ'; L.SetBounds(12,52,270,20);
  OutputPreset := TComboBox.Create(FOwner); OutputPreset.Parent := Settings; OutputPreset.Name := 'MovieOutputPreset';
  OutputPreset.Style := csDropDownList; OutputPreset.SetBounds(12,72,270,26);
  OutputPreset.Items.AddStrings(['下書き 640×360 / 15fps','HD 1280×720 / 30fps','フルHD 1920×1080 / 30fps','カスタム']); OutputPreset.OnChange := FCallbacks.OutputPresetChanged;
  L := TLabel.Create(FOwner); L.Parent := Settings; L.Caption := '出力の画質と速度'; L.SetBounds(292,52,300,20);
  EncodeProfile := TComboBox.Create(FOwner); EncodeProfile.Parent := Settings; EncodeProfile.Name := 'MovieEncodeProfile';
  EncodeProfile.Style := csDropDownList; EncodeProfile.SetBounds(292,72,300,26);
  EncodeProfile.Items.AddStrings(['速度優先','標準','画質優先']);
  EncodeProfile.Hint := '速度優先は圧縮を軽くします。画質優先は出力に時間がかかります。'; EncodeProfile.ShowHint := True;
  OutputPath := Edit(Settings,'MovieOutputTarget','新しい出力先（AVI / MP4）',622,52,395);
  Bar := TPanel.Create(FOwner); WorkflowPanel := Bar; Bar.Parent := FOwner; Bar.Align := alTop; Bar.Height := 72; Bar.BevelOuter := bvNone; Bar.Visible := False;
  Workflow := TLabel.Create(FOwner); Workflow.Parent := Bar; Workflow.Name := 'MovieWorkflowGuide';
  Workflow.AutoSize := False; Workflow.WordWrap := True;
  Workflow.SetBounds(12,2,Bar.ClientWidth-24,35); Workflow.Anchors := [akLeft,akTop,akRight];
  Button(Bar,'MovieRunStep','工程の結果を作る',31,12,40,150); RunStep := TButton(FOwner.FindComponent('MovieRunStep'));
  Button(Bar,'MovieNextStep','次へ',27,172,40,100); Next := TButton(FOwner.FindComponent('MovieNextStep'));
  Button(Bar,'MovieBackStep','前の工程へ',32,282,40,120); BackStep := TButton(FOwner.FindComponent('MovieBackStep'));
  Button(Bar,'MovieDiagnose','不足を診断',28,412,40,130);
  Button(Bar,'MovieSafeActing','使える演技へ戻す',29,552,40,180);
  Button(Bar,'MovieReloadDraft','最新データを読込',33,742,40,160);
  ReloadDraft := TButton(FOwner.FindComponent('MovieReloadDraft')); ReloadDraft.Visible := False;
  JobProgress := TPaintBox.Create(FOwner); JobProgress.Parent := FOwner; JobProgress.Align := alBottom;
  JobProgress.Name := 'MovieJobProgress'; JobProgress.Height := 8; JobProgress.OnPaint := FCallbacks.PaintJobProgress; JobProgress.Visible := False;
  Status := TLabel.Create(FOwner); Status.Parent := FOwner; Status.Align := alBottom; Status.Height := 52;
  Status.WordWrap := True; Status.Layout := tlCenter; Status.Name := 'MovieStatus';
  Status.Visible := False;
  ExportPanel := TPanel.Create(FOwner); ExportPanel.Parent := FOwner; ExportPanel.Align := alBottom;
  ExportPanel.Name := 'MovieExportFeedback'; ExportPanel.Caption := ''; ExportPanel.ShowCaption := False;
  ExportPanel.Height := 64; ExportPanel.BevelOuter := bvNone; ExportPanel.Visible := False;
  ExportStatus := TLabel.Create(FOwner); ExportStatus.Parent := ExportPanel; ExportStatus.Align := alClient;
  ExportStatus.Name := 'MovieExportFeedbackText'; ExportStatus.AutoSize := False; ExportStatus.WordWrap := True;
  ExportStatus.Layout := tlCenter; ExportStatus.ShowHint := True;
  ExportProgress := TProgressBar.Create(FOwner); ExportProgress.Parent := ExportPanel;
  ExportProgress.Name := 'MovieExportProgress'; ExportProgress.Align := alBottom;
  ExportProgress.Height := 10; ExportProgress.Min := 0; ExportProgress.Max := 1000;
  ExportNotification := TRigmMovieNotification.Create(FOwner);
  ExportResult := TButton.Create(FOwner); ExportResult.Parent := ExportPanel; ExportResult.Align := alRight;
  ExportResult.Name := 'MovieExportFeedbackAction'; ExportResult.Width := 130; ExportResult.OnClick := FCallbacks.ActionClick;
  Bottom := TPanel.Create(FOwner); Bottom.Parent := FOwner; Bottom.Align := alBottom; Bottom.Height := 296; Bottom.BevelOuter := bvNone; Bottom.Caption := '';
  Timeline := TRigmMovieTimeline.Create(FOwner); Timeline.Parent := Bottom; Timeline.Align := alClient;
  Timeline.Name := 'MovieWaveTimeline'; Timeline.OnSeek := FCallbacks.TimelineSeek;
  Timeline.OnSelectCue := FCallbacks.TimelineSelectCue;
  Bar := TPanel.Create(FOwner); Bar.Parent := Bottom; Bar.Align := alBottom; Bar.Height := 64; Bar.BevelOuter := bvNone; Bar.Caption := ''; Bar.ShowCaption := False; Bar.Name := 'MovieFrameSeek';
  var SeekHeader := TPanel.Create(FOwner); SeekHeader.Parent := Bar; SeekHeader.Align := alTop; SeekHeader.Height := 26; SeekHeader.Caption := ''; SeekHeader.ShowCaption := False; SeekHeader.BevelOuter := bvNone; SeekHeader.Name := 'MovieSeekHeader';
  FramePosition := TLabel.Create(FOwner); FramePosition.Parent := SeekHeader; FramePosition.Align := alClient;
  FramePosition.Name := 'MovieFramePosition'; FramePosition.AutoSize := False; FramePosition.Layout := tlCenter; FramePosition.ShowHint := True;
  Zoom := TComboBox.Create(FOwner); Zoom.Parent := SeekHeader; Zoom.Align := alRight; Zoom.Width := 100; Zoom.Style := csDropDownList;
  Zoom.Items.AddStrings(['全体','10秒','30秒','60秒']); Zoom.ItemIndex := 0; Zoom.OnChange := FCallbacks.ZoomChanged; Zoom.Name := 'MovieTimelineZoom';
  Seek := TRigmFineTrackBar.Create(FOwner); Seek.Parent := Bar; Seek.Align := alClient; Seek.Name := 'MovieSeek'; Seek.Min := 0; Seek.Max := 1; Seek.OnChange := FCallbacks.SeekChanged;
  Seek.Frequency := 0; Seek.TickStyle := tsNone; Seek.LineSize := 1; Seek.PageSize := 10;
  Seek.ShowHint := True; Seek.Hint := '作品全体のフレーム位置。クリック・ドラッグでシーク、ホイールで1フレームずつ移動。';
  PropertyHost := TPanel.Create(FOwner); PropertyHost.Parent := FOwner; PropertyHost.Align := alRight;
  PropertyHost.Name := 'MoviePropertyHost'; PropertyHost.Caption := ''; PropertyHost.BevelOuter := bvNone;
  PropertyHost.Width := 370; PropertyHost.Constraints.MinWidth := 340;
  PropertyBar := TRigmIconToolbar.Create(FOwner); PropertyBar.Parent := PropertyHost; PropertyBar.Align := alTop;
  PropertyBar.Name := 'MoviePropertyPages';
  Right := TRigmPropertyScrollBox.Create(FOwner); Right.Parent := PropertyHost; Right.Align := alClient;
  FPages := TRigmMoviePropertyPages.Create(FOwner,Right,PropertyBar);
  PropertyBar.AddIcon('MoviePropertiesDialogue','セリフ・字幕・話者',riEditPreview,0,FPages.PropertyPageClick,True);
  PropertyBar.AddIcon('MoviePropertiesScene','場面画像・説明・レイアウト',riPng,1,FPages.PropertyPageClick,True);
  PropertyBar.AddIcon('MoviePropertiesActing','表情・動作・演技',riPreview,2,FPages.PropertyPageClick,True);
  PropertyBar.AddIcon('MoviePropertiesAudio','音声の詳細・再生成',riGenerate,3,FPages.PropertyPageClick,True);
  PropertyBar.AddIcon('MoviePropertiesDiagnostics','素材と出力の診断',riClassify,4,FPages.PropertyPageClick,True);
  Right.BorderStyle := bsNone; Right.Name := 'MovieProperties';
  Right.HorzScrollBar.Visible := False; Right.VertScrollBar.Visible := True; Right.OnResize := FCallbacks.LayoutProperties;
  FPages.BuildPage := 1;
  SceneTitle := Edit(Right,'MovieSceneTitle','場面名',12,0,330);
  Scene := Edit(Right,'MovieCueScene','シーン',12,4,330);
  Scene.ReadOnly := True;
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '場面の説明';
  SceneDescription := TMemo.Create(FOwner); SceneDescription.Parent := Right; SceneDescription.Name := 'MovieSceneDescription';
  SceneDescription.ScrollBars := ssVertical; FPages.AddProperty(L,SceneDescription,160,12,330,90);
  LayoutChoice := Combo('MovieSceneLayout','画像と説明の配置',12,266,330);
  LayoutChoice.Items.AddStrings(['背景・画像・説明の標準配置','L字配置・キャラクターを左','L字配置・キャラクターを右']);
  LayoutChoice.OnChange := FCallbacks.DraftEdited;
  Button(Right,'MovieApplyScene','場面と配置を適用',41,12,320,330);
  ChartKind := Combo('MovieSceneChartKind','総評チャート',12,370,330);
  ChartKind.Items.AddStrings(['なし','レーダーチャート','棒グラフ']); ChartKind.ItemIndex := 0; ChartKind.OnChange := FCallbacks.DraftEdited;
  ChartTitle := Edit(Right,'MovieSceneChartTitle','チャートの題名',12,424,330);
  ChartMaximum := Edit(Right,'MovieSceneChartMaximum','満点',12,478,330);
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '項目 = 値（1行1項目、最大8項目）';
  ChartItems := TMemo.Create(FOwner); ChartItems.Parent := Right; ChartItems.Name := 'MovieSceneChartItems';
  ChartItems.ScrollBars := ssVertical; FPages.AddProperty(L,ChartItems,532,12,330,120);
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := 'チャートの色';
  ChartColor := TColorBox.Create(FOwner); ChartColor.Parent := Right; ChartColor.Name := 'MovieSceneChartColor';
  ChartColor.Style := [cbStandardColors,cbExtendedColors,cbCustomColor,cbPrettyNames];
  ChartColor.Selected := RGB(90,184,232); ChartColor.OnChange := FCallbacks.DraftEdited; FPages.AddProperty(L,ChartColor,672,12,330,28);
  Button(Right,'MovieApplySceneChart','チャートを適用',44,12,726,330);
  ImageEnter := Combo('MovieImageEnter','画像の登場',12,780,158); ImageEnter.Items.AddStrings(['なし','フェード']);
  ImageExit := Combo('MovieImageExit','画像の退場',184,780,158); ImageExit.Items.AddStrings(['なし','フェード']);
  ImageEnterSeconds := Edit(Right,'MovieImageEnterSeconds','登場の時間（秒、0～60）',12,834,158);
  ImageExitSeconds := Edit(Right,'MovieImageExitSeconds','退場の時間（秒、0～60）',184,834,158);
  ImageEnter.OnChange := FCallbacks.DraftEdited; ImageExit.OnChange := FCallbacks.DraftEdited;
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '短い場面では登場・退場の時間を比例して縮めます。画像のみをフェードし、字幕と説明は保持します。';
  FPages.AddProperty(L,nil,888,12,330,0);
  Button(Right,'MovieApplyImageAnimation','画像アニメーションを適用',45,12,916,330);
  FPages.BuildPage := 0;
  Speaker := Combo('MovieCueSpeaker','台本上の話者',12,53,158); Speaker.OnChange := FCallbacks.SelectSpeaker;
  Pause := Edit(Right,'MovieCuePause','セリフ後の間（秒）',184,53,158);
  FPages.BuildPage := 2;
  Emotion := Combo('MovieCueEmotion','感情（既存の立ち絵差分）',12,48,330);
  Emotion.OnChange := FCallbacks.DraftEdited;
  ImageAttention := Combo('MovieImageAttention','画像への向き補助（瞳移動なし）',12,300,330);
  ImageAttention.Items.AddStrings(['説明時に控えめな頭の向き補助','補助なし','このセリフでは画像へ頭の向き補助']);
  ImageAttention.OnChange := FCallbacks.DraftEdited;
  Expression := Combo('MovieCueExpression','表情ポーズ',12,102,158); Expression.Items.AddStrings(['neutral','smile','serious','sad']);
  Motion := Combo('MovieCueMotion','動作',184,102,158); Motion.Items.AddStrings(['idle','still','nod','emphasis']);
  Button(Right,'MovieApplyPose','表情と動作を適用',16,12,152,330);
  WholeMotionStatus := TLabel.Create(FOwner); WholeMotionStatus.Parent := Right;
  WholeMotionStatus.Name := 'MovieWholeMotionStatus'; WholeMotionStatus.Caption := '';
  WholeMotionStatus.AutoSize := False; WholeMotionStatus.WordWrap := True;
  FPages.AddProperty(nil,WholeMotionStatus,188,12,330,42);
  Button(Right,'MovieStopWholeMotion','全体モーションを停止',42,12,242,330);
  FPages.BuildPage := 0;
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := 'セリフ'; L.SetBounds(12,156,330,20);
  Dialogue := TMemo.Create(FOwner); Dialogue.Parent := Right; Dialogue.Name := 'MovieCueText'; Dialogue.Text := ''; Dialogue.SetBounds(12,178,330,85); Dialogue.ScrollBars := ssVertical;
  FPages.AddProperty(L,Dialogue,156,12,330,85);
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '字幕（読み上げとは別に調整できます）'; L.SetBounds(12,269,330,20);
  Subtitle := TMemo.Create(FOwner); Subtitle.Parent := Right; Subtitle.Name := 'MovieCueSubtitle'; Subtitle.Text := ''; Subtitle.SetBounds(12,291,330,75); Subtitle.ScrollBars := ssVertical;
  FPages.AddProperty(L,Subtitle,269,12,330,75);
  Button(Right,'MovieApplyCue','セリフを適用',16,12,374,158); Button(Right,'MovieBackground','シーン画像を選ぶ',17,184,374,158);
  Button(Right,'MovieAddCue','セリフ追加',18,12,408,158); Button(Right,'MovieDeleteCue','セリフ削除',19,184,408,158);
  FPages.BuildPage := 3;
  Style := Combo('MovieVoiceStyle','選択中の話者のVOICEVOX音声',12,448,330);
  Speed := Edit(Right,'MovieVoiceSpeed','話速（0.5～2）',12,500,158); Pitch := Edit(Right,'MovieVoicePitch','音高（-0.15～0.15）',184,500,158);
  Button(Right,'MovieApplyVoice','音声設定を適用',20,12,554,330);
  Button(Right,'MovieGenerateVoice','必要な音声を再生成',8,12,600,330);
  BgmPath := Edit(Right,'MovieBgmPath','動画全体のBGM（PCM16 WAV）',12,654,330); BgmPath.ReadOnly := True;
  BgmPath.ShowHint := True;
  Button(Right,'MovieSelectBgm','BGMを選ぶ...',47,12,708,158); Button(Right,'MovieClearBgm','BGMを解除',48,184,708,158);
  BgmVolume := Edit(Right,'MovieBgmVolume','BGM音量（0～2、声とは別）',12,752,330);
  BgmFadeOut := Edit(Right,'MovieBgmFadeOut','動画末尾のBGMフェード（秒）',12,806,330);
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '短いBGMは繰り返します。フェードは動画末尾に合わせ、動画の長さを超えないように調整します。';
  FPages.AddProperty(L,nil,860,12,330,0);
  Button(Right,'MovieApplyBgm','BGM音量・フェードを適用',46,12,888,330);
  FPages.BuildPage := 2;
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := 'セリフ別の演技（音声は再生成しません）'; L.SetBounds(12,594,330,20);
  FPages.AddProperty(L,nil,594,12,330,0);
  for var I := 0 to 11 do Acting[I] := Edit(Right,'MovieActing_'+MovieActingKeys[I],MovieActingLabels[I],12+(I mod 2)*172,618+(I div 2)*50,158);
  MouthMode := Combo('MovieMouthMode','口パクの方式',12,922,158); MouthMode.Items.AddStrings(['自動（素材を優先）','既存素材を切替','変形']);
  BlinkMode := Combo('MovieBlinkMode','瞬きの方式',184,922,158); BlinkMode.Items.AddStrings(['自動（素材を優先）','既存素材を切替','変形']);
  VariantGroup := Combo('MovieVariantGroup','実在素材グループ',12,974,330); VariantGroup.OnChange := FCallbacks.VariantGroupChanged;
  Variant := Combo('MovieVariantPart','表示候補（同じグループの子素材）',12,1026,330);
  Button(Right,'MovieApplyActing','演技を適用・プレビュー',25,12,1078,330);
  Button(Right,'MovieClearVariants','このセリフの素材選択を解除',26,12,1112,330);
  Splitter := TSplitter.Create(FOwner); Splitter.Parent := FOwner; Splitter.Align := alRight;
  Splitter.Name := 'MoviePropertySplitter'; Splitter.MinSize := 220; Splitter.Width := 10; Splitter.ResizeStyle := rsUpdate;
  PropertySplitter := Splitter; Splitter.AutoSnap := False;
  Splitter.OnBeforeResize := FCallbacks.SplitterBeforeResize; Splitter.OnCanResize := FCallbacks.SplitterCanResize;
  Splitter.OnAfterResize := FCallbacks.SplitterAfterResize;
  FPages.BuildPage := 4;
  L := TLabel.Create(FOwner); L.Parent := Right; L.Caption := '準備診断・素材で使える演技'; L.SetBounds(12,1150,330,20);
  Preparation := TMemo.Create(FOwner); Preparation.Parent := Right; Preparation.Name := 'MoviePreparationDetails';
  Preparation.SetBounds(12,1172,330,220); Preparation.ReadOnly := True; Preparation.ScrollBars := ssVertical;
  FPages.AddProperty(L,Preparation,1150,12,330,220);
  ReloadDraft.Parent := PropertyHost; ReloadDraft.Align := alTop;
  EditScroll := TScrollBox.Create(FOwner); EditScroll.Parent := FOwner; EditScroll.Align := alClient;
  EditScroll.Name := 'MovieEditingScroll'; EditScroll.BorderStyle := bsNone;
  EditScroll.VertScrollBar.Tracking := True; EditScroll.HorzScrollBar.Tracking := True;
  Panel := TPanel.Create(FOwner); Panel.Parent := EditScroll; Panel.BevelOuter := bvNone;
  EditScroll.OnResize := FCallbacks.EditingAreaResize;
  Panel.Caption := ''; Panel.Name := 'MovieEditingArea'; EditHost := Panel;
  Panel.SetBounds(0,0,Max(240,EditScroll.ClientWidth),Max(340,EditScroll.ClientHeight));
  Panel.DisableAlign;
  Bottom.Parent := Panel;
  Bottom.SetBounds(0,Panel.ClientHeight-Bottom.Height,Panel.ClientWidth,Bottom.Height);
  TimelineSplitter := TSplitter.Create(FOwner); TimelineSplitter.Parent := Panel; TimelineSplitter.Align := alBottom;
  TimelineSplitter.Name := 'MovieTimelineSplitter'; TimelineSplitter.Height := 10; TimelineSplitter.MinSize := 165; TimelineSplitter.ResizeStyle := rsUpdate;
  TimelineSplitter.Top := Bottom.Top-TimelineSplitter.Height;
  TimelineSplitter.AutoSnap := False;
  TimelineSplitter.OnBeforeResize := FCallbacks.SplitterBeforeResize; TimelineSplitter.OnCanResize := FCallbacks.SplitterCanResize;
  TimelineSplitter.OnAfterResize := FCallbacks.SplitterAfterResize;
  PreviewArea := TPanel.Create(FOwner); PreviewArea.Parent := Panel; PreviewArea.Align := alClient;
  PreviewArea.Name := 'MoviePreviewArea'; PreviewArea.Caption := ''; PreviewArea.BevelOuter := bvNone;
  ScriptPanel := TPanel.Create(FOwner); ScriptPanel.Parent := PreviewArea; ScriptPanel.Align := alLeft; ScriptPanel.Width := 310; ScriptPanel.BevelOuter := bvNone;
  ScriptPanel.Visible := False;
  Bar := TPanel.Create(FOwner); Bar.Parent := ScriptPanel; Bar.Align := alBottom; Bar.Height := 34; Bar.BevelOuter := bvNone;
  Button(Bar,'MovieApplyScript','入力した台本を取り込む',21,8,2,295);
  Script := TMemo.Create(FOwner); Script.Parent := ScriptPanel; Script.Align := alTop; Script.Height := 170; Script.Name := 'MovieScript'; Script.ScrollBars := ssBoth;
  Examples := TComboBox.Create(FOwner); Examples.Parent := ScriptPanel; Examples.Align := alTop; Examples.Style := csDropDownList; Examples.Name := 'MovieScriptExample';
  Examples.Items.AddStrings(['架空の短い紹介例','3分紹介の構成テンプレート']); Examples.ItemIndex := 0;
  Bar := TPanel.Create(FOwner); Bar.Parent := ScriptPanel; Bar.Align := alTop; Bar.Height := 30; Bar.BevelOuter := bvNone;
  Button(Bar,'MovieLoadExample','選択した例を入力欄へ表示',30,8,1,295);
  Script.Text := '';
  List := TListView.Create(FOwner); List.Parent := ScriptPanel; List.Align := alClient; List.Name := 'MovieCueList'; List.ViewStyle := vsReport;
  List.ReadOnly := True; List.RowSelect := True; List.HideSelection := False;
  List.Columns.Add.Caption := '開始'; List.Columns[0].Width := 50; List.Columns.Add.Caption := '台本'; List.Columns[1].Width := 190;
  List.Columns.Add.Caption := '音声'; List.Columns[2].Width := 55; List.OnSelectItem := FCallbacks.SelectCue;
  Splitter := TSplitter.Create(FOwner); Splitter.Parent := PreviewArea; Splitter.Align := alLeft;
  TransportScroll := TScrollBox.Create(FOwner); TransportScroll.Parent := PreviewArea; TransportScroll.Align := alBottom;
  TransportScroll.Name := 'MovieTransportScroll'; TransportScroll.Height := 64; TransportScroll.BorderStyle := bsNone;
  TransportScroll.VertScrollBar.Visible := False; TransportScroll.HorzScrollBar.Tracking := True;
  Bar := TPanel.Create(FOwner); Bar.Parent := TransportScroll; Bar.Height := 44; Bar.BevelOuter := bvNone; Bar.Name := 'MovieTransport'; Transport := Bar;
  Bar.Caption := '';
  Button(Bar,'MovieTransportPlay','▶ 再生',12,8,10,112); PlayButton := TButton(FOwner.FindComponent('MovieTransportPlay'));
  Button(Bar,'MovieTransportStop','■ 停止',36,128,10,112); StopButton := TButton(FOwner.FindComponent('MovieTransportStop'));
  Button(Bar,'MovieTransportExport','MP4出力...',13,248,10,130); ExportButton := TButton(FOwner.FindComponent('MovieTransportExport'));
  ExportButton.Hint := '保存先を選んで映像・音声付きMP4を書き出す（Ctrl+Shift+E）'; ExportButton.ShowHint := True;
  PlayButton.Hint := 'この位置から再生（入力欄以外では Space）'; PlayButton.ShowHint := True;
  StopButton.Hint := '再生を停止（入力欄以外では Space）'; StopButton.ShowHint := True;
  TransportStatus := TLabel.Create(FOwner); TransportStatus.Parent := Bar; TransportStatus.Name := 'MoviePlaybackState';
  Button(Bar,'MoviePreviewFit','画面に合わせる',43,388,10,150); FitPreview := TButton(FOwner.FindComponent('MoviePreviewFit'));
  FitPreview.ShowHint := True; FitPreview.Hint := 'プレビューの表示倍率と移動をリセット。作品の配置や出力サイズは変更しません。';
  TransportStatus.Visible := False;
  TransportStatus.AutoSize := False; TransportStatus.SetBounds(252,8,400,32); TransportStatus.Anchors := [akLeft,akTop,akRight];
  TransportStatus.Layout := tlCenter; TransportStatus.WordWrap := True;
  Preview := TRigmMoviePreview.Create(FOwner); Preview.Parent := PreviewArea; Preview.Align := alClient; Preview.Name := 'MoviePreviewImage';
  Panel.EnableAlign;
  WheelEvents := TApplicationEvents.Create(FOwner); WheelEvents.OnMessage := FCallbacks.ApplicationMessage;
  Timer := TTimer.Create(FOwner); Timer.Interval := 40; Timer.OnTimer := FCallbacks.Tick;
  for var I := 0 to FOwner.ComponentCount-1 do begin
    if FOwner.Components[I] is TEdit then TEdit(FOwner.Components[I]).OnChange := FCallbacks.DraftEdited;
    if (FOwner.Components[I] is TMemo) and (FOwner.Components[I]<>Preparation) then TMemo(FOwner.Components[I]).OnChange := FCallbacks.DraftEdited;
  end;
  Style.OnChange := FCallbacks.DraftEdited; Expression.OnChange := FCallbacks.DraftEdited; Motion.OnChange := FCallbacks.DraftEdited;
  EncodeProfile.OnChange := FCallbacks.DraftEdited; MouthMode.OnChange := FCallbacks.DraftEdited; BlinkMode.OnChange := FCallbacks.DraftEdited;
  for var Field in FPages.Fields do begin
    if Field.Control is TEdit then TEdit(Field.Control).OnEnter := FPages.PropertyInputEntered;
    if Field.Control is TMemo then TMemo(Field.Control).OnEnter := FPages.PropertyInputEntered;
    if Field.Control is TComboBox then TComboBox(Field.Control).OnEnter := FPages.PropertyInputEntered;
  end;
end;
end.
