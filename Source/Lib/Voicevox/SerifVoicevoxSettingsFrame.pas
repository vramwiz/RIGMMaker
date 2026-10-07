// VOICEVOX入力画面の設定ツールバーと機能別ページを管理し、キャラ＋感情の設定をプロジェクトへ保存する。
unit SerifVoicevoxSettingsFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  VoicevoxToolbarButtons, SerifVoicevoxAccentView,
  SerifVoicevoxIntonationFrame, SerifVoicevoxLengthFrame,
  SerifVoicevoxAudioSettingsFrame, SerifVoicevoxAudioSettings, Vcl.ComCtrls,
  Vcl.ToolWin, Vcl.StdCtrls, Vcl.AppEvnts, Winapi.Windows, Winapi.Messages, RigmBufferedControls;

type
  TFrameSerifVoicevoxSettings = class(TRigmBufferedFrame)
    PanelAccent: TPanel;
    PanelIntonation: TPanel;
    PanelLength: TPanel;
    PanelVoice: TPanel;
  private
    FNotice: TLabel; FOnQueryReady: TNotifyEvent;
    FRowMode: Boolean;
    FQueryJson: string;
    FOnAudioChange: TNotifyEvent;
    FToolbar: TVoicevoxToolbarButtons;
    FFrameAccent: TSerifVoicevoxAccentView;
    FFrameIntonation: TFrameSerifVoicevoxIntonation;
    FFrameLength: TFrameSerifVoicevoxLength;
    FFrameVoice: TFrameSerifVoicevoxAudioSettings;
    FPanelShortcuts: TPanel;
    FAdjustments: TScrollBox; // 3つの調整部品を順に並べ、狭い画面では縦スクロールする。
    FLayouting: Boolean;
    FColumnSync: Boolean; FWheelRemainder: Integer;
    FScrollEvents: TApplicationEvents;
    FCurrentText: string;
    FCurrentSpeakerUUID: string;
    FCurrentStyleId: Integer;
    FDisplayedStyleId: Integer;
    FOnAccentChange: TSerifVoicevoxAccentQueryEvent;
    FOnClose: TNotifyEvent;
    FOnError: TSerifVoicevoxAccentErrorEvent;
    FOnMoveEnd: TNotifyEvent;
    FOnPreview: TNotifyEvent;
    FOnSend: TNotifyEvent;
    FSaveTimer: TTimer;
    FSettings: TSerifVoicevoxAudioSettings;
    FUpdatingQuery: Boolean;
    function GetHasQuery: Boolean;
    procedure AccentChange(Sender: TObject; const QueryJson: string);
    procedure AccentError(Sender: TObject; const ErrorMessage: string);
    procedure AudioChange(Sender: TObject);
    procedure CloseRequest(Sender: TObject);
    procedure IntonationChange(Sender: TObject; const QueryJson: string);
    procedure LengthChange(Sender: TObject; const QueryJson: string);
    procedure MoveEndRequest(Sender: TObject);
    procedure PreviewRequest(Sender: TObject);
    procedure SendRequest(Sender: TObject);
    procedure SaveTimerTimer(Sender: TObject);
    procedure LayoutAdjustments(Sender: TObject);
    procedure SyncColumns;
    procedure ScrollChange(Sender: TObject);
    procedure AdjustmentMessage(var Msg: TMsg; var Handled: Boolean);
    procedure ToolbarPageSelected(Sender: TObject;
      const Page: TVoicevoxToolbarPage);
  public
    // 5つの編集ページ、再生付きツールバー、遅延保存タイマーを生成し、アクセントを表示する。
    constructor Create(AOwner: TComponent); override;
    procedure ShowRow(const Text, SpeakerUUID: string; StyleId: Integer;
      const Values: TSerifVoicevoxAudioValues; const QueryJson, EngineUrl: string);
    function RowValues: TSerifVoicevoxAudioValues;
    function RequestFinish: Boolean;
    procedure SetEditingEnabled(Value: Boolean);
    procedure UseAdjustmentOnly; // 調整3段を同じページに並べ、基本設定だけ別ページにする。
    procedure ShowNotice(const Text: string);
    property HasQuery: Boolean read GetHasQuery;
    property OnQueryReady: TNotifyEvent read FOnQueryReady write FOnQueryReady;
    property OnAudioChange: TNotifyEvent read FOnAudioChange write FOnAudioChange;
    // 保存待ちの変更を保存してから、設定ページと設定ストアを破棄する。
    destructor Destroy; override;
    // 動的に生成したツールバーと各編集ページを現在のモニターDPIへ追従させる。
    procedure ApplyDpi;
    // 外部で生成したショートカット表示を、ツールバー切替ページへ接続する。
    procedure AttachShortcutControl(Control: TControl);
    // 指定したキャラ＋感情の合成値を返す。未設定なら固定規定値を返す。
    function GetValues(const SpeakerUUID: string; const StyleId: Integer): TSerifVoicevoxAudioValues;
    // 旧プロジェクトの変更を保存し、指定した音声合成プロジェクトのINIを読み込む。
    procedure OpenProject(const ProjectFolder: string);
    // 遅延保存待ちの音声設定を直ちに保存する。
    procedure Save;
    // 現在編集している本文のアクセントを表示する。空文字は表示解除を表す。
    procedure ShowAccent(const Text: string; const StyleId: Integer;
      const QueryJson: string = '');
    // ツールバー右端の再生マークを再生中／停止中の表示へ切り替える。
    procedure SetPreviewActive(const Value: Boolean);
    // 編集対象を切り替えて保存済み値を表示する。表示の復元だけでは保存処理を発生させない。
    procedure ShowStyle(const SpeakerUUID: string; const StyleId: Integer);
    property OnAccentChange: TSerifVoicevoxAccentQueryEvent
      read FOnAccentChange write FOnAccentChange;
    // ツールバー左端の×から入力パネルを閉じる要求を通知する。
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnError: TSerifVoicevoxAccentErrorEvent
      read FOnError write FOnError;
    // ツールバーからセリフ一覧の終了位置へ移動する要求を通知する。
    property OnMoveEnd: TNotifyEvent read FOnMoveEnd write FOnMoveEnd;
    // 各編集ページまたはツールバーから、現在編集中の行の共通プレビュー処理を要求する。
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
    // ツールバーから、現在編集中の行をEnterと同じ経路で送信するよう要求する。
    property OnSend: TNotifyEvent read FOnSend write FOnSend;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Types, AviUtl2StyleColors, VerticalSliderControl, HorizontalScrollBarControl;

{$R *.dfm}

constructor TFrameSerifVoicevoxSettings.Create(AOwner: TComponent);
begin
  inherited;

  Color := A2SCPanelBackground; Font.Color := A2SCPanelText;
  DoubleBuffered := True;
  for var Panel in [PanelAccent,PanelIntonation,PanelLength,PanelVoice] do begin
    Panel.Caption := ''; Panel.Align := alClient; Panel.BevelOuter := bvNone; Panel.Color := A2SCPanelBackground; Panel.ParentBackground := False;
  end;
  FCurrentStyleId := -1;
  FDisplayedStyleId := -1;
  FSettings := TSerifVoicevoxAudioSettings.Create;

  FSaveTimer := TTimer.Create(Self);
  FSaveTimer.Enabled := False;
  FSaveTimer.Interval := 300;
  FSaveTimer.OnTimer := SaveTimerTimer;

  FFrameAccent := TSerifVoicevoxAccentView.Create(Self);
  FFrameAccent.Parent := PanelAccent;
  FFrameAccent.Align := alClient;
  FFrameAccent.OnChange := AccentChange;
  FFrameAccent.OnError := AccentError;
  FFrameAccent.OnPreview := PreviewRequest;
  FFrameAccent.OnScrollChange := ScrollChange;

  FFrameIntonation := TFrameSerifVoicevoxIntonation.Create(Self);
  FFrameIntonation.Parent := PanelIntonation;
  FFrameIntonation.Align := alClient;
  FFrameIntonation.OnChange := IntonationChange;
  FFrameIntonation.OnPreview := PreviewRequest;
  FFrameIntonation.OnScrollChange := ScrollChange;

  FFrameLength := TFrameSerifVoicevoxLength.Create(Self);
  FFrameLength.Parent := PanelLength;
  FFrameLength.Align := alClient;
  FFrameLength.OnChange := LengthChange;
  FFrameLength.OnPreview := PreviewRequest;

  FFrameVoice := TFrameSerifVoicevoxAudioSettings.Create(Self);
  FFrameVoice.Parent := PanelVoice;
  FFrameVoice.Align := alClient;
  FFrameVoice.OnChange := AudioChange;
  FFrameVoice.OnPreview := PreviewRequest;

  FPanelShortcuts := TPanel.Create(Self);
  FPanelShortcuts.Parent := Self;
  FPanelShortcuts.Align := alClient;
  FPanelShortcuts.BevelOuter := bvNone;
  FPanelShortcuts.Color := A2SCPanelBackground;
  FPanelShortcuts.ParentBackground := False;
  FPanelShortcuts.Visible := False;

  FToolbar := TVoicevoxToolbarButtons.Create(Self);
  FToolbar.Parent := Self; FToolbar.Name := 'VoicevoxPages';
  FToolbar.Align := alTop;
  FToolbar.BackgroundColor := A2SCToolBarBackground;
  FToolbar.FontColor := A2SCToolBarFont;
  FToolbar.CheckedColor := A2SCToolBarChecked;
  FToolbar.PressedColor := A2SCToolBarPressed;
  FToolbar.HotColor := A2SCToolBarHot;
  FToolbar.OnPageSelected := ToolbarPageSelected;
  FToolbar.OnClose := CloseRequest;
  FToolbar.OnMoveEnd := MoveEndRequest;
  FToolbar.OnPreview := PreviewRequest;
  FToolbar.OnSend := SendRequest;
  FNotice := TLabel.Create(Self); FNotice.Parent := Self; FNotice.Align := alTop;
  FNotice.AutoSize := False; FNotice.WordWrap := True; FNotice.Height := 64; FNotice.Font.Color := A2SCPanelText;
  FNotice.Name := 'VoicevoxDetailNotice'; FNotice.Caption := ''; FToolbar.Top := 0; FNotice.Top := FToolbar.Height;
  FToolbar.Activate(vtpAccent);
end;

function TFrameSerifVoicevoxSettings.GetHasQuery: Boolean;
begin Result := FQueryJson<>''; end;
procedure TFrameSerifVoicevoxSettings.ShowNotice(const Text: string);
begin if FNotice.Caption<>Text then FNotice.Caption := Text; FNotice.Visible := Text<>''; end;
procedure TFrameSerifVoicevoxSettings.UseAdjustmentOnly;
begin
  if FAdjustments=nil then begin
    DisableAlign;
    try
      FAdjustments := TScrollBox.Create(Self); FAdjustments.Name := 'VoicevoxAdjustments';
      FAdjustments.Parent := Self; FAdjustments.Align := alClient; FAdjustments.BorderStyle := bsNone;
      FAdjustments.Color := A2SCPanelBackground; FAdjustments.HorzScrollBar.Visible := False;
      FAdjustments.ParentBackground := False; FAdjustments.DoubleBuffered := True;
      FAdjustments.VertScrollBar.Tracking := True;
      FAdjustments.DisableAlign;
      try
        var I := 0;
        for var Panel in [PanelAccent,PanelIntonation,PanelLength] do begin
          Panel.Parent := FAdjustments; Panel.Align := alTop; Panel.Top := I*154; Panel.Visible := True;
          var Title := TLabel.Create(Self); Title.Parent := Panel; Title.Align := alTop;
          Title.AutoSize := False; Title.Height := MulDiv(24,CurrentPPI,96); Title.Font.Color := A2SCPanelText;
          case I of 0: Title.Caption := 'アクセント'; 1: Title.Caption := '音高'; 2: Title.Caption := '音素長'; end;
          Inc(I);
        end;
      finally FAdjustments.EnableAlign; end;
      FAdjustments.OnResize := LayoutAdjustments;
      FScrollEvents := TApplicationEvents.Create(Self); FScrollEvents.OnMessage := AdjustmentMessage;
    finally EnableAlign; end;
  end;
  FToolbar.UseAdjustmentOnly; FNotice.Height := MulDiv(32,CurrentPPI,96); ShowNotice('');
  ToolbarPageSelected(Self,FToolbar.ActivePage); LayoutAdjustments(Self);
end;
procedure TFrameSerifVoicevoxSettings.LayoutAdjustments(Sender: TObject);
begin
  if (FAdjustments=nil) or FLayouting then Exit;
  FLayouting := True;
  try
    // アクセントの104px表示・26pxスクロール・24px見出しを基準とし、リサイズで引き伸ばさない。
    var PartHeight := MulDiv(154,CurrentPPI,96);
    FAdjustments.DisableAlign;
    try
      for var Panel in [PanelAccent,PanelIntonation,PanelLength] do Panel.Height := PartHeight;
    finally FAdjustments.EnableAlign; end;
  finally FLayouting := False; end;
end;
procedure TFrameSerifVoicevoxSettings.SyncColumns;
begin
  if (FAdjustments=nil) or FColumnSync then Exit;
  FColumnSync := True;
  try
    var Cells := FFrameAccent.MoraCells; var Width := FFrameAccent.ContentWidth;
    FFrameIntonation.SetMoraLayout(Cells,Width);
    FFrameIntonation.ScrollPosition := FFrameAccent.ScrollPosition;
  finally FColumnSync := False; end;
end;
procedure TFrameSerifVoicevoxSettings.ScrollChange(Sender: TObject);
begin
  if (FAdjustments=nil) or FColumnSync then Exit;
  FColumnSync := True;
  try
    var Position := FFrameAccent.ScrollPosition;
    if Sender=FFrameIntonation then Position := FFrameIntonation.ScrollPosition;
    FFrameAccent.ScrollPosition := Position; FFrameIntonation.ScrollPosition := Position;
  finally FColumnSync := False; end;
end;
procedure TFrameSerifVoicevoxSettings.AdjustmentMessage(var Msg: TMsg; var Handled: Boolean);
begin
  // フォーカスがセリフ一覧にあっても、調整ページの余白上ならホイールを縦スクロールへ送る。
  if Handled or (Msg.message<>WM_MOUSEWHEEL) or (FAdjustments=nil) or not FAdjustments.Showing or
    (FAdjustments.VertScrollBar.Range<=FAdjustments.ClientHeight) or (GetCapture<>0) then Exit;
  var Point := System.Types.Point(SmallInt(LoWord(Msg.lParam)),SmallInt(HiWord(Msg.lParam)));
  var Local := FAdjustments.ScreenToClient(Point); if not PtInRect(FAdjustments.ClientRect,Local) then Exit;
  var Hit := FAdjustments.ControlAtPos(Local,True,True,True);
  if (Hit is TVerticalSliderControl) or (Hit is TCustomEdit) or (Hit is THorizontalScrollBarControl) then Exit;
  if FFrameAccent.EditableAt(Point) and PtInRect(FFrameAccent.ClientRect,FFrameAccent.ScreenToClient(Point)) then Exit;
  Inc(FWheelRemainder,SmallInt(HiWord(Msg.wParam)));
  var Steps := FWheelRemainder div WHEEL_DELTA; FWheelRemainder := FWheelRemainder mod WHEEL_DELTA;
  var Distance := MulDiv(16,CurrentPPI,96)*Integer(Mouse.WheelScrollLines);
  if Mouse.WheelScrollLines=-1 then Distance := FAdjustments.ClientHeight;
  FAdjustments.VertScrollBar.Position := FAdjustments.VertScrollBar.Position-Steps*Distance;
  Handled := True;
end;
procedure TFrameSerifVoicevoxSettings.ShowRow(const Text, SpeakerUUID: string;
  StyleId: Integer; const Values: TSerifVoicevoxAudioValues; const QueryJson, EngineUrl: string);
begin
  FRowMode := True; FSaveTimer.Enabled := False;
  FCurrentText := Text; FCurrentSpeakerUUID := SpeakerUUID; FCurrentStyleId := StyleId;
  FDisplayedStyleId := StyleId; FFrameVoice.SetValues(Values); FFrameAccent.EngineUrl := EngineUrl;
  FUpdatingQuery := True;
  try
    FQueryJson := FFrameIntonation.ShowQuery(QueryJson);
    FQueryJson := FFrameLength.ShowQuery(FQueryJson);
    FFrameAccent.ShowText(Text,StyleId,FQueryJson);
  finally FUpdatingQuery := False; end;
  SyncColumns;
end;
function TFrameSerifVoicevoxSettings.RowValues: TSerifVoicevoxAudioValues;
begin Result := FFrameVoice.GetValues; end;
function TFrameSerifVoicevoxSettings.RequestFinish: Boolean;
begin
  Result := FFrameVoice.RequestFinish and FFrameIntonation.RequestFinish and FFrameLength.RequestFinish;
  if Result then Result := FFrameAccent.RequestFinish;
end;
procedure TFrameSerifVoicevoxSettings.SetEditingEnabled(Value: Boolean);
begin FFrameAccent.Enabled := Value; FFrameIntonation.Enabled := Value; FFrameLength.Enabled := Value; FFrameVoice.Enabled := Value; end;

procedure TFrameSerifVoicevoxSettings.ApplyDpi;
begin
  if Assigned(FToolbar) then FToolbar.ApplyDpi;
  if Assigned(FFrameAccent) then FFrameAccent.ApplyDpi;
  if Assigned(FFrameIntonation) then FFrameIntonation.ApplyDpi;
  if Assigned(FFrameLength) then FFrameLength.ApplyDpi;
  LayoutAdjustments(Self);
  SyncColumns;
end;

procedure TFrameSerifVoicevoxSettings.AccentChange(Sender: TObject;
  const QueryJson: string);
var
  SharedQuery: string;
begin
  if FUpdatingQuery then Exit;
  FUpdatingQuery := True;
  try
    SharedQuery := FFrameIntonation.ShowQuery(QueryJson);
    SharedQuery := FFrameLength.ShowQuery(SharedQuery);
    if SharedQuery <> QueryJson then
      FFrameAccent.ShowText(FCurrentText, FCurrentStyleId, SharedQuery);
  finally
    FUpdatingQuery := False;
  end;
  FQueryJson := SharedQuery;
  SyncColumns;
  if FFrameAccent.AnalysisUpdate then begin if Assigned(FOnQueryReady) then FOnQueryReady(Self); end
  else if Assigned(FOnAccentChange) then FOnAccentChange(Self,SharedQuery);
end;

procedure TFrameSerifVoicevoxSettings.IntonationChange(Sender: TObject;
  const QueryJson: string);
var
  SharedQuery: string;
begin
  if FUpdatingQuery then Exit;
  FUpdatingQuery := True;
  try
    SharedQuery := FFrameLength.ShowQuery(QueryJson);
    FFrameAccent.ShowText(FCurrentText, FCurrentStyleId, SharedQuery);
  finally
    FUpdatingQuery := False;
  end;
  FQueryJson := SharedQuery;
  SyncColumns;
  if Assigned(FOnAccentChange) then FOnAccentChange(Self, SharedQuery);
end;

procedure TFrameSerifVoicevoxSettings.LengthChange(Sender: TObject;
  const QueryJson: string);
var
  SharedQuery: string;
begin
  if FUpdatingQuery then Exit;
  FUpdatingQuery := True;
  try
    SharedQuery := FFrameIntonation.ShowQuery(QueryJson);
    FFrameAccent.ShowText(FCurrentText, FCurrentStyleId, SharedQuery);
  finally
    FUpdatingQuery := False;
  end;
  FQueryJson := SharedQuery;
  SyncColumns;
  if Assigned(FOnAccentChange) then FOnAccentChange(Self, SharedQuery);
end;

procedure TFrameSerifVoicevoxSettings.AccentError(Sender: TObject;
  const ErrorMessage: string);
begin
  // 更新失敗時は、操作不可で保持していた旧イントネーションを残さない。
  FQueryJson := ''; FFrameIntonation.ShowQuery(''); FFrameLength.ShowQuery('');
  SyncColumns;
  if Assigned(FOnError) then FOnError(Self, ErrorMessage);
end;

procedure TFrameSerifVoicevoxSettings.AudioChange(Sender: TObject);
begin
  if FRowMode then begin if Assigned(FOnAudioChange) then FOnAudioChange(Self); Exit; end;
  if (FCurrentSpeakerUUID = '') or (FCurrentStyleId < 0) then Exit;
  FSettings.SetValues(FCurrentSpeakerUUID, FCurrentStyleId,
    FFrameVoice.GetValues);
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

procedure TFrameSerifVoicevoxSettings.PreviewRequest(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

procedure TFrameSerifVoicevoxSettings.MoveEndRequest(Sender: TObject);
begin
  if Assigned(FOnMoveEnd) then FOnMoveEnd(Self);
end;

procedure TFrameSerifVoicevoxSettings.AttachShortcutControl(
  Control: TControl);
begin
  if not Assigned(Control) or not Assigned(FPanelShortcuts) then Exit;
  Control.Parent := FPanelShortcuts;
  Control.Align := alTop;
  Control.Top := 0;
end;

procedure TFrameSerifVoicevoxSettings.CloseRequest(Sender: TObject);
begin
  if Assigned(FOnClose) then FOnClose(Self);
end;

procedure TFrameSerifVoicevoxSettings.SendRequest(Sender: TObject);
begin
  if Assigned(FOnSend) then FOnSend(Self);
end;

procedure TFrameSerifVoicevoxSettings.SetPreviewActive(
  const Value: Boolean);
begin
  FToolbar.SetPreviewActive(Value);
end;

destructor TFrameSerifVoicevoxSettings.Destroy;
begin
  FSaveTimer.Enabled := False;
  FSettings.Save;
  FSettings.Free;
  inherited;
end;

function TFrameSerifVoicevoxSettings.GetValues(const SpeakerUUID: string;
  const StyleId: Integer): TSerifVoicevoxAudioValues;
begin
  Result := FSettings.GetValues(SpeakerUUID, StyleId);
end;

procedure TFrameSerifVoicevoxSettings.OpenProject(
  const ProjectFolder: string);
begin
  FSaveTimer.Enabled := False;
  FSettings.OpenProject(ProjectFolder);
  if (FCurrentSpeakerUUID <> '') and (FCurrentStyleId >= 0) then
    FFrameVoice.SetValues(FSettings.GetValues(FCurrentSpeakerUUID,
      FCurrentStyleId))
  else
    FFrameVoice.SetValues(TSerifVoicevoxAudioValues.Defaults);
end;

procedure TFrameSerifVoicevoxSettings.SaveTimerTimer(Sender: TObject);
begin
  FSaveTimer.Enabled := False;
  FSettings.Save;
end;

procedure TFrameSerifVoicevoxSettings.Save;
begin
  FSaveTimer.Enabled := False;
  FSettings.Save;
end;

procedure TFrameSerifVoicevoxSettings.ShowAccent(const Text: string;
  const StyleId: Integer; const QueryJson: string);
var
  KeepIntonation: Boolean;
  SharedQuery: string;
begin
  KeepIntonation := (Trim(Text) = Trim(FCurrentText)) and
    (FDisplayedStyleId >= 0) and (StyleId >= 0) and
    (FDisplayedStyleId <> StyleId) and (Trim(QueryJson) = '');
  FCurrentText := Text;
  FDisplayedStyleId := StyleId;
  FUpdatingQuery := True;
  try
    SharedQuery := FFrameIntonation.ShowQuery(QueryJson, KeepIntonation);
    SharedQuery := FFrameLength.ShowQuery(SharedQuery);
    FFrameAccent.ShowText(Text, StyleId, SharedQuery);
  finally
    FUpdatingQuery := False;
  end;
  if (SharedQuery <> QueryJson) and Assigned(FOnAccentChange) then
    FOnAccentChange(Self, SharedQuery);
end;

procedure TFrameSerifVoicevoxSettings.ShowStyle(const SpeakerUUID: string;
  const StyleId: Integer);
begin
  FCurrentSpeakerUUID := Trim(SpeakerUUID);
  FCurrentStyleId := StyleId;
  if (FCurrentSpeakerUUID = '') or (FCurrentStyleId < 0) then
    FFrameVoice.SetValues(TSerifVoicevoxAudioValues.Defaults)
  else
    FFrameVoice.SetValues(FSettings.GetValues(FCurrentSpeakerUUID,
      FCurrentStyleId));
end;

procedure TFrameSerifVoicevoxSettings.ToolbarPageSelected(Sender: TObject;
  const Page: TVoicevoxToolbarPage);
begin
  DisableAlign;
  try
    if FAdjustments<>nil then begin
      FAdjustments.Visible := Page<>vtpAudioSettings;
      FPanelShortcuts.Visible := False; PanelVoice.Visible := Page=vtpAudioSettings;
      LayoutAdjustments(Self); Exit;
    end;
    PanelAccent.Visible := Page = vtpAccent;
    PanelIntonation.Visible := Page = vtpIntonation;
    PanelLength.Visible := Page = vtpLength;
    FPanelShortcuts.Visible := Page = vtpShortcuts;
    PanelVoice.Visible := Page = vtpAudioSettings;
  finally
    EnableAlign;
  end;
end;

end.
