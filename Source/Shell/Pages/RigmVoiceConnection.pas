unit RigmVoiceConnection;
// 配役と詳細音声画面でEXE選択・保存・非同期接続を共有する。実際の起動はMovieJob所有。
interface
uses System.Classes, Vcl.ExtCtrls, RigmWizardWorkspace, SerifVoicevoxEngineConfig;
type
  TRigmVoiceConnection = class(TComponent)
  private
    FWorkspace: TRigmWizardWorkspace; FConfig: TSerifVoicevoxEngineConfig; FTimer: TTimer;
    FActive,FNeedsLocate: Boolean; FPrepared,FPrompted,FMessage: string; FOnChanged: TNotifyEvent;
    function Target: string;
    procedure Tick(Sender: TObject);
    procedure Notify;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure SetActive(Value: Boolean);
    procedure Prepare;
    procedure Locate;
    property MessageText: string read FMessage;
    property NeedsLocate: Boolean read FNeedsLocate; // EXE未検出・接続失敗時だけ手動指定を表示。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;
implementation
uses System.SysUtils, Vcl.Dialogs, RigmJson;
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
procedure TRigmVoiceConnection.Prepare;
begin
  if FWorkspace.VoiceBusy or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  FPrepared := Target; FPrompted := ''; var Exe: string; FNeedsLocate := not FConfig.Resolve(Exe);
  try FWorkspace.PrepareVoiceEngine(Exe); FMessage := 'VOICEVOXを確認しています。';
  except on E: Exception do FMessage := E.Message; end;
  Notify;
end;
procedure TRigmVoiceConnection.Locate;
begin
  if FWorkspace.VoiceBusy or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  var Old: string; FConfig.Resolve(Old); var Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := 'VOICEVOX.exe または vv-engine\run.exeを選択';
    Dialog.Filter := 'VOICEVOX / Engine (VOICEVOX.exe;run.exe)|VOICEVOX.exe;run.exe|実行ファイル (*.exe)|*.exe';
    Dialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing]; if Old<>'' then Dialog.InitialDir := ExtractFileDir(Old);
    if not Dialog.Execute then begin FMessage := 'VOICEVOXの選択を取り消しました。EXEボタンで再選択できます。'; Exit; end;
    var Exe: string;
    if not TSerifVoicevoxEngineConfig.NormalizeEngineSelection(Dialog.FileName,Exe) then begin FNeedsLocate := True; FMessage := 'VOICEVOX.exeまたはvv-engine\run.exeを選び直してください。'; Exit; end;
    if not FConfig.Save(Exe) then begin FMessage := FConfig.LastError; Exit; end;
    FPrepared := Target; FPrompted := FPrepared;
    FNeedsLocate := False; FMessage := 'VOICEVOXを確認しています。';
    try FWorkspace.PrepareVoiceEngine(Exe); except on E: Exception do FMessage := E.Message; end;
  finally Dialog.Free; Notify; end;
end;
procedure TRigmVoiceConnection.Tick(Sender: TObject);
begin
  if not FActive then begin FTimer.Enabled := False; Exit; end;
  if not (FWorkspace.CurrentScriptStage='casting') and not (FWorkspace.CurrentScriptStage='voice') then Exit;
  if (Target='') or FWorkspace.VoiceBusy or FWorkspace.VoiceContinuous or FWorkspace.ScriptTextEditing then Exit;
  if FPrepared<>Target then begin Prepare; Exit; end;
  var State := FWorkspace.VoiceConnectionStatus;
  try
    if JB(State,'catalogReady') and (JS(State,'error')='') then begin
      FNeedsLocate := False; var Done := 'VOICEVOXを確認しました。';
      if FMessage<>Done then begin FMessage := Done; Notify; end;
    end;
    if JS(State,'error')<>'' then begin
      FNeedsLocate := True; if FMessage<>JS(State,'error') then begin FMessage := JS(State,'error'); Notify; end;
    end;
    if JS(State,'error').StartsWith('VOICEVOX_EXE_REQUIRED:') and (FPrompted<>Target) then begin FPrompted := Target; Locate; end;
  finally State.Free; end;
end;
end.
