unit RigmVoiceConnection;
// 配役と詳細音声画面でEXE選択・保存・非同期接続を共有する。実際の起動はMovieJob所有。
interface
uses System.Classes, Vcl.ExtCtrls, RigmWizardWorkspace, SerifVoicevoxEngineConfig;
type
  TRigmVoiceConnection = class(TComponent)
  private
    FWorkspace: TRigmWizardWorkspace; FConfig: TSerifVoicevoxEngineConfig; FTimer: TTimer;
    FActive,FNeedsLocate: Boolean; FPrepared,FPrompted,FMessage: string; FOnChanged: TNotifyEvent;
    FPreparing,FLocating: Boolean; // 同期の設定確認・ファイル選択中も処理ページを維持する。
    function Target: string;
    function GetWaiting: Boolean;
    procedure Tick(Sender: TObject);
    procedure Notify;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure SetActive(Value: Boolean);
    procedure Prepare;
    procedure Locate;
    property MessageText: string read FMessage;
    property Waiting: Boolean read GetWaiting; // 起動・接続・一覧取得中。失敗時はFalseへ戻る。
    property NeedsLocate: Boolean read FNeedsLocate; // EXE未検出・接続失敗時だけ手動指定を表示。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;
implementation
uses System.SysUtils, System.JSON, Vcl.Dialogs, RigmJson;
constructor TRigmVoiceConnection.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; FConfig := TSerifVoicevoxEngineConfig.Create;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 200; FTimer.OnTimer := Tick;
end;
destructor TRigmVoiceConnection.Destroy;
begin FTimer.Enabled := False; FConfig.Free; inherited; end;
function TRigmVoiceConnection.Target: string;
begin Result := ''; if FWorkspace.ScriptDraft<>nil then Result := FWorkspace.ScriptDraft.Id+#10+FWorkspace.ScriptDraft.EngineUrl; end;
procedure TRigmVoiceConnection.Notify;
begin if Assigned(FOnChanged) then FOnChanged(Self); end;
procedure TRigmVoiceConnection.SetActive(Value: Boolean);
begin FActive := Value; FTimer.Enabled := Value; end;
function TRigmVoiceConnection.GetWaiting: Boolean;
begin
  Result := FPreparing or FLocating or FWorkspace.VoiceBusy or
    ((Target<>'') and ((FPrepared<>Target) or (not FWorkspace.VoiceCatalogReady and not FNeedsLocate)));
end;
procedure TRigmVoiceConnection.Prepare;
begin
  if FWorkspace.VoiceBusy or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  var State := FWorkspace.VoiceConnectionStatus;
  try
    if JB(State,'catalogReady') and (JS(State,'error')='') then begin
      FPrepared := Target; FNeedsLocate := False; FMessage := 'VOICEVOXを確認しました。'; Notify; Exit;
    end;
  finally State.Free; end;
  FPreparing := True; FMessage := 'VOICEVOXの設定と接続先を確認しています。'; Notify;
  try
    FPrepared := Target; FPrompted := ''; var Exe: string; FNeedsLocate := not FConfig.Resolve(Exe);
    try FWorkspace.PrepareVoiceEngine(Exe);
    except on E: Exception do begin FNeedsLocate := True; FMessage := E.Message; end; end;
  finally FPreparing := False; Notify; end;
end;
procedure TRigmVoiceConnection.Locate;
begin
  if FWorkspace.VoiceBusy or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  FLocating := True; FMessage := 'VOICEVOXの実行ファイルを選択しています。'; Notify;
  var Dialog := TOpenDialog.Create(Self);
  try
    var Old: string; FConfig.Resolve(Old);
    Dialog.Title := 'VOICEVOX.exe または vv-engine\run.exeを選択';
    Dialog.Filter := 'VOICEVOX / Engine (VOICEVOX.exe;run.exe)|VOICEVOX.exe;run.exe|実行ファイル (*.exe)|*.exe';
    Dialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing]; if Old<>'' then Dialog.InitialDir := ExtractFileDir(Old);
    if not Dialog.Execute then begin FNeedsLocate := not FWorkspace.VoiceCatalogReady; FMessage := 'VOICEVOXの選択を取り消しました。手動設定から再選択できます。'; Exit; end;
    var Exe: string;
    if not TSerifVoicevoxEngineConfig.NormalizeEngineSelection(Dialog.FileName,Exe) then begin FNeedsLocate := True; FMessage := 'VOICEVOX.exeまたはvv-engine\run.exeを選び直してください。'; Exit; end;
    FMessage := 'VOICEVOXの設定を保存しています。'; Notify;
    if not FConfig.Save(Exe) then begin FNeedsLocate := True; FMessage := FConfig.LastError; Exit; end;
    FPrepared := Target; FPrompted := FPrepared;
    FNeedsLocate := False; FMessage := 'VOICEVOXの起動と接続を準備しています。'; Notify;
    try FWorkspace.PrepareVoiceEngine(Exe); except on E: Exception do begin FNeedsLocate := True; FMessage := E.Message; end; end;
  finally Dialog.Free; FLocating := False; Notify; end;
end;
procedure TRigmVoiceConnection.Tick(Sender: TObject);
begin
  if not FActive then begin FTimer.Enabled := False; Exit; end;
  if not (FWorkspace.CurrentScriptStage='casting') and not (FWorkspace.CurrentScriptStage='voice') then Exit;
  if (Target='') or FPreparing or FLocating or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  if not FWorkspace.VoiceBusy and (FPrepared<>Target) then begin Prepare; Exit; end;
  var State := FWorkspace.VoiceConnectionStatus;
  try
    if JB(State,'busy') then begin
      var MessageText := 'VOICEVOXの接続を確認しています。';
      if State.GetValue('job') is TJSONObject then begin
        var Job := JO(State,'job'); var Phase := JS(Job,'phase');
        if Phase='voice-engine-start' then MessageText := 'VOICEVOX Engineを起動しています。'
        else if Phase='voice-engine-wait' then MessageText := 'VOICEVOX Engineの起動を待っています。'
        else if Phase='voice-speakers' then MessageText := 'VOICEVOXの人物・感情一覧を取得しています。';
        if JS(Job,'kind')='audio' then MessageText := '選択したセリフの音声を生成しています。';
        if JB(Job,'cancelRequested') then MessageText := 'VOICEVOXの処理を取り消しています。';
        MessageText := MessageText+'  経過 '+Trunc(JN(Job,'elapsedSeconds')).ToString+'秒';
      end;
      if FMessage<>MessageText then begin FMessage := MessageText; Notify; end;
      Exit;
    end;
    if JB(State,'catalogReady') and (JS(State,'error')='') then begin
      FNeedsLocate := False; var Done := 'VOICEVOXを確認しました。';
      if FMessage<>Done then begin FMessage := Done; Notify; end;
    end;
    if JS(State,'error')<>'' then begin
      FNeedsLocate := True; if FMessage<>JS(State,'error') then begin FMessage := JS(State,'error'); Notify; end;
    end;
    if (State.GetValue('job') is TJSONObject) and (JS(JO(State,'job'),'state')='cancelled') and
      ((JS(JO(State,'job'),'kind')='voice-engine') or (JS(JO(State,'job'),'kind')='speakers')) then begin
      FNeedsLocate := True; var Cancelled := 'VOICEVOXの準備を取り消しました。手動設定から再接続できます。';
      if FMessage<>Cancelled then begin FMessage := Cancelled; Notify; end;
    end;
    if JS(State,'error').StartsWith('VOICEVOX_EXE_REQUIRED:') and (FPrompted<>Target) then begin FPrompted := Target; Locate; end;
  finally State.Free; end;
end;
end.
