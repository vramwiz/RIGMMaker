unit RigmScriptTextFrame;
interface
uses System.Classes, RigmScriptPageFrame, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Winapi.Messages, RigmWizardWorkspace, RigmIconToolbar;
type
  TRigmScriptMemo = class(TMemo)
  private
    FOnBeginInput: TNotifyEvent;
    procedure ImeStart(var M: TMessage); message WM_IME_STARTCOMPOSITION;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    property OnBeginInput: TNotifyEvent read FOnBeginInput write FOnBeginInput;
  end;
  TRigmScriptTextFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FToolbar: TRigmIconToolbar; FParts: array[0..2] of TToolButton;
    FEditors: array[0..2] of TRigmScriptMemo; FHeading,FGuide: TLabel;
    procedure BeginInput(Sender: TObject);
    procedure EndInput(Sender: TObject);
    procedure CompleteInput(Sender: TObject);
    procedure SelectSection(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure UpdateGuide;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
  end;
implementation
uses System.SysUtils, RigmJson, RigmScriptTextModel, RigmToolbarIcons;
{$R *.dfm}
const SectionIds: array[0..2] of string = ('opening','body','closing');
  SectionNames: array[0..2] of string = ('共通の出だし','今回の本文','共通の締め');
procedure TRigmScriptMemo.KeyDown(var Key: Word; Shift: TShiftState);
begin if Assigned(FOnBeginInput) then FOnBeginInput(Self); inherited; end;
procedure TRigmScriptMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin if Assigned(FOnBeginInput) then FOnBeginInput(Self); inherited; end;
procedure TRigmScriptMemo.ImeStart(var M: TMessage);
begin if Assigned(FOnBeginInput) then FOnBeginInput(Self); inherited; end;
constructor TRigmScriptTextFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptTextToolbar';
  for var I := 0 to 2 do begin
    FParts[I] := FToolbar.AddIcon('ScriptTextPart'+I.ToString,SectionNames[I],riEditPreview,0,SelectSection,True); FParts[I].Tag := I;
  end;
  FToolbar.AddSeparator; FToolbar.AddIcon('ScriptTextReady','入力完了：AIの変更を許可する',riComplete,0,CompleteInput);
  FHeading := TRigmScriptLabel.Create(Self); FHeading.Parent := Self; FHeading.Align := alTop; FHeading.AutoSize := False;
  FHeading.Height := ScaleValue(38); FHeading.Font.Size := 16; FHeading.Name := 'ScriptTextHeading';
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.Height := ScaleValue(56);
  FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Name := 'ScriptTextGuide';
  var Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.Caption := ''; Body.BevelOuter := bvNone; Body.Padding.SetBounds(ScaleValue(16),ScaleValue(8),ScaleValue(16),ScaleValue(8));
  for var I := 0 to 2 do begin
    FEditors[I] := TRigmScriptMemo.Create(Self); FEditors[I].Parent := Body; FEditors[I].Align := alClient;
    FEditors[I].Name := 'ScriptText'+I.ToString; FEditors[I].Tag := I; FEditors[I].Font.Name := 'Yu Gothic UI'; FEditors[I].Font.Size := 14;
    FEditors[I].ScrollBars := ssVertical; FEditors[I].WordWrap := True; FEditors[I].MaxLength := ScriptSectionLimit;
    FEditors[I].Visible := False; FEditors[I].OnEnter := BeginInput; FEditors[I].OnExit := EndInput;
    FEditors[I].OnBeginInput := BeginInput; FEditors[I].OnChange := Changed;
  end;
end;
destructor TRigmScriptTextFrame.Destroy;
begin FWorkspace.EndScriptTextEdit; inherited; end;
procedure TRigmScriptTextFrame.UpdateGuide;
begin
  if FWorkspace.ScriptTextEditing then FGuide.Caption := '入力中：AIの変更を停止しています。入力完了のチェックアイコンで解除できます。'
  else FGuide.Caption := '入力完了：AIはパイプで取得・変更できます。再び入力を始めると変更を停止します。';
  FGuide.Caption := FGuide.Caption+#13#10+'戻る・終了・任意の保存で文章を保存します。Nextで保存して校正へ進み、Codexへ入力完了を伝えてください。';
end;
procedure TRigmScriptTextFrame.BeginInput(Sender: TObject);
begin if FSync then Exit; FWorkspace.BeginScriptTextEdit; UpdateGuide; end;
procedure TRigmScriptTextFrame.EndInput(Sender: TObject);
begin FWorkspace.EndScriptTextEdit; UpdateGuide; end;
procedure TRigmScriptTextFrame.CompleteInput(Sender: TObject);
begin FWorkspace.EndScriptTextEdit; UpdateGuide; end;
procedure TRigmScriptTextFrame.Changed(Sender: TObject);
begin
  if FSync then Exit; BeginInput(Sender);
  try FWorkspace.SetScriptText(SectionIds[TControl(Sender).Tag],TRigmScriptMemo(Sender).Text);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptTextFrame.SelectSection(Sender: TObject);
begin
  FWorkspace.EndScriptTextEdit;
  try FWorkspace.SelectScriptSection(SectionIds[TToolButton(Sender).Tag]);
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptTextFrame.RefreshState;
begin
  if FWorkspace.ScriptDraft=nil then Exit; FSync := True;
  try
    var Active := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'scriptText'),'activeSection');
    for var I := 0 to 2 do begin
      var Section := ScriptSection(FWorkspace.ScriptDraft,SectionIds[I]); if Section=nil then Continue;
      if NormalizeScriptText(FEditors[I].Text)<>JS(Section,'text') then FEditors[I].Text := JS(Section,'text');
      FParts[I].Down := Active=SectionIds[I]; FEditors[I].Visible := FParts[I].Down;
      if FParts[I].Down then FHeading.Caption := '第5段階：'+SectionNames[I]+'  （'+Length(JS(Section,'text')).ToString+'文字）';
    end;
    UpdateGuide;
  finally FSync := False; end;
end;
procedure TRigmScriptTextFrame.SetActive(Value: Boolean);
begin if Value then RefreshState else if FWorkspace.CurrentScriptStage='text' then FWorkspace.EndScriptTextEdit; end;
end.
