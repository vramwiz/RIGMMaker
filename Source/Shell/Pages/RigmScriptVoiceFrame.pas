unit RigmScriptVoiceFrame;
// 選択セリフの独立読み・実一覧の明示紐付け・query値・F5試聴。ジョブはWorkspaceを借用する。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  RigmWizardWorkspace, RigmIconToolbar, RigmScriptTextFrame;
type
  TRigmScriptVoiceFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing,FActive,FEngineDirty: Boolean; FLoaded: string;
    FList: TListView; FReading: TRigmScriptMemo; FSubtitle: TMemo; FStyle: TComboBox; FEngine: TEdit;
    FValues: array[0..5] of TEdit; FActor,FGuide: TLabel; FToolbar: TRigmIconToolbar;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Key(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Changed(Sender: TObject);
    procedure Detail(Sender: TObject);
    procedure Complete(Sender: TObject);
    procedure Ready(Sender: TObject);
    procedure RefreshCatalog(Sender: TObject);
    procedure ChangeEngine(Sender: TObject);
    procedure EngineChanged(Sender: TObject);
    procedure Bind(Sender: TObject);
    procedure SaveDefault(Sender: TObject);
    procedure Preview(Sender: TObject);
    procedure Generate(Sender: TObject);
    procedure Cancel(Sender: TObject);
    function ApplyCurrent: Boolean;
    function SelectedId: string;
    function Number: Integer;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean; // 未確定の数値を失わず、離脱を止める。
  end;
implementation
uses System.SysUtils, System.JSON, System.Generics.Collections, Winapi.Windows, RigmJson, RigmToolbarIcons, RigmMovieModel, RigmScriptCastingModel;
{$R *.dfm}
const ValueKeys: array[0..5] of string = ('speedScale','pitchScale','intonationScale','volumeScale','prePhonemeLength','postPhonemeLength');
      ValueNames: array[0..5] of string = ('話速','音高','抑揚','音量','前無音','後無音');
constructor TRigmScriptVoiceFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; Align := alClient;
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptVoiceToolbar';
  FToolbar.AddIcon('ScriptVoiceRefresh','接続先から実話者一覧を取得',riRefresh,0,RefreshCatalog);
  FToolbar.AddIcon('ScriptVoiceEdit','Enter：読みと音声query値を編集',riEditPreview,0,Detail);
  FToolbar.AddIcon('ScriptVoiceDone','入力完了（Ctrl+Enter / Esc）',riComplete,0,Complete);
  FToolbar.AddIcon('ScriptVoiceReady','全セリフの音声確認完了',riComplete,0,Ready);
  FToolbar.AddSeparator; FToolbar.AddIcon('ScriptVoicePreview','F5：選択セリフを生成・試聴。生成済みなら保存音声を再生',riPreview,0,Preview);
  FToolbar.AddIcon('ScriptVoiceGenerate','選択セリフだけ生成する',riSave,0,Generate);
  FToolbar.AddIcon('ScriptVoiceCancel','試聴停止・所有音声ジョブ取消',riDelete,0,Cancel);
  FToolbar.AddIcon('ScriptVoiceSaveDefault','選択キャラの声を登録初期値として保存（既存作品は変更しない）',riSave,0,SaveDefault);
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := 76; FGuide.Font.Height := -20; FGuide.Name := 'ScriptVoiceGuide';
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := 300; FList.ViewStyle := vsReport; FList.RowSelect := True; FList.ReadOnly := True;
  FList.HideSelection := False; FList.Name := 'ScriptVoiceRows'; FList.OnSelectItem := Selected; FList.OnKeyDown := Key;
  FList.Columns.Add.Caption := '状態'; FList.Columns[0].Width := 112; FList.Columns.Add.Caption := '読み'; FList.Columns[1].Width := 178;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.Caption := ''; Body.BevelOuter := bvNone; Body.Padding.SetBounds(8,4,8,4);
  var EngineRow := TPanel.Create(Self); EngineRow.Parent := Body; EngineRow.Align := alTop; EngineRow.Height := 40; EngineRow.Caption := ''; EngineRow.BevelOuter := bvNone;
  var EngineButton := TButton.Create(Self); EngineButton.Parent := EngineRow; EngineButton.Align := alRight; EngineButton.Width := 132; EngineButton.Caption := '適用'; EngineButton.Hint := '入力したVOICEVOX接続先をこの作品へ適用'; EngineButton.ShowHint := True; EngineButton.OnClick := ChangeEngine; EngineButton.Name := 'ScriptVoiceEngineApply';
  FEngine := TEdit.Create(Self); FEngine.Parent := EngineRow; FEngine.Align := alClient; FEngine.Name := 'ScriptVoiceEngine'; FEngine.TextHint := 'http://127.0.0.1:50021'; FEngine.OnChange := EngineChanged;
  FActor := TLabel.Create(Self); FActor.Parent := Body; FActor.Align := alTop; FActor.AutoSize := False; FActor.Height := 44; FActor.Name := 'ScriptVoiceActor';
  FStyle := TComboBox.Create(Self); FStyle.Parent := Body; FStyle.Align := alTop; FStyle.Style := csDropDownList; FStyle.Name := 'ScriptVoiceStyle'; FStyle.OnChange := Bind;
  var Query := TPanel.Create(Self); Query.Parent := Body; Query.Align := alTop; Query.Height := 96; Query.Caption := ''; Query.BevelOuter := bvNone;
  for var I := 0 to 5 do begin
    var Cell := TPanel.Create(Self); Cell.Parent := Query; Cell.Align := alLeft; Cell.Width := 112; Cell.Caption := ''; Cell.BevelOuter := bvNone;
    var L := TLabel.Create(Self); L.Parent := Cell; L.Align := alTop; L.Caption := ValueNames[I]; L.Font.Height := -22; L.AutoSize := False; L.Height := 28;
    FValues[I] := TEdit.Create(Self); FValues[I].Parent := Cell; FValues[I].Align := alTop; FValues[I].Name := 'ScriptVoiceValue'+I.ToString; FValues[I].OnChange := Changed; FValues[I].OnKeyDown := Key;
  end;
  var LabelReading := TLabel.Create(Self); LabelReading.Parent := Body; LabelReading.Align := alTop; LabelReading.Caption := '音声用の読み（表示字幕とは独立）'; LabelReading.Height := 28;
  var Display := TPanel.Create(Self); Display.Parent := Body; Display.Align := alBottom; Display.Top := 10000; Display.Height := 110; Display.Caption := ''; Display.BevelOuter := bvNone;
  var L := TLabel.Create(Self); L.Parent := Display; L.Align := alTop; L.Caption := '表示字幕（保持・読取専用）';
  FSubtitle := TMemo.Create(Self); FSubtitle.Parent := Display; FSubtitle.Align := alClient; FSubtitle.ReadOnly := True; FSubtitle.Font.Height := -22; FSubtitle.ScrollBars := ssVertical; FSubtitle.Name := 'ScriptVoiceSubtitle';
  FReading := TRigmScriptMemo.Create(Self); FReading.Parent := Body; FReading.Align := alClient; FReading.Font.Height := -26; FReading.MaxLength := 2000; FReading.ScrollBars := ssVertical; FReading.Name := 'ScriptVoiceReading'; FReading.OnChange := Changed; FReading.OnKeyDown := Key;
  FActor.Top := 0; EngineRow.Top := 44; FStyle.Top := 84; Query.Top := 130; LabelReading.Top := 230;
end;
function TRigmScriptVoiceFrame.SelectedId: string;
begin Result := JS(JO(FWorkspace.ScriptDraft.ScriptWizard,'voice'),'selectedCue'); end;
function TRigmScriptVoiceFrame.Number: Integer;
begin Result := JI(CastingRow(FWorkspace.ScriptDraft,SelectedId),'role'); end;
function TRigmScriptVoiceFrame.ApplyCurrent: Boolean;
begin
  Result := False; var O := TJSONObject.Create;
  try
    for var I := 0 to 5 do begin var N: Double; if not TryStrToFloat(FValues[I].Text,N) then raise Exception.Create(ValueNames[I]+'を数値で入力してください。'); AddN(O,ValueKeys[I],N); end;
    ValidateVoiceValues(O);
    var C := FWorkspace.ScriptDraft.Cue(SelectedId); var S := FWorkspace.ScriptDraft.Speaker(C.SpeakerId);
    var Defaults: array[0..5] of Double; Defaults[0] := S.Speed; Defaults[1] := S.Pitch; Defaults[2] := S.Intonation; Defaults[3] := S.Volume; Defaults[4] := 0.1; Defaults[5] := 0.1;
    var Different := FReading.Text<>C.SpokenText;
    for var I := 0 to 5 do if JN(O,ValueKeys[I])<>JN(C.VoiceSettings,ValueKeys[I],Defaults[I]) then Different := True;
    if Different then FWorkspace.EditVoice(SelectedId,FReading.Text,O); Result := True;
  except on E: Exception do FGuide.Caption := E.Message; end;
  O.Free;
end;
procedure TRigmScriptVoiceFrame.Changed(Sender: TObject);
begin if FSync or not FEditing then Exit; FWorkspace.BeginScriptTextEdit; ApplyCurrent; end;
procedure TRigmScriptVoiceFrame.Detail(Sender: TObject);
begin FEditing := True; FWorkspace.BeginScriptTextEdit; RefreshState; FReading.SetFocus; end;
function TRigmScriptVoiceFrame.RequestFinish: Boolean;
begin
  if FEngineDirty then begin FGuide.Caption := '入力中の接続先を適用してから操作してください。'; Exit(False); end;
  Result := not FEditing or ApplyCurrent; if not Result then Exit;
  FEditing := False; FWorkspace.EndScriptTextEdit; RefreshState;
end;
procedure TRigmScriptVoiceFrame.Complete(Sender: TObject);
begin if RequestFinish then FGuide.Caption := '入力を保存しました。↑↓で移動、F5で生成・試聴できます。'; end;
procedure TRigmScriptVoiceFrame.Ready(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.CompleteVoice; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  if FSync or not Value then Exit; var Id := Item.SubItems[1];
  if not RequestFinish then begin FSync := True; try for var Entry in FList.Items do Entry.Selected := Entry.SubItems[1]=SelectedId; finally FSync := False; end; Exit; end;
  FWorkspace.SelectVoice(Id); RefreshState;
end;
procedure TRigmScriptVoiceFrame.Key(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key=VK_F5 then begin Preview(Self); Key := 0; end
  else if FEditing then begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Complete(Self); Key := 0; end; end
  else if Key=VK_RETURN then begin Detail(Self); Key := 0; end
  else if (Key=VK_UP) or (Key=VK_DOWN) then begin if RequestFinish then if Key=VK_UP then FWorkspace.MoveVoice(-1) else FWorkspace.MoveVoice(1); Key := 0; end;
end;
procedure TRigmScriptVoiceFrame.ChangeEngine(Sender: TObject);
begin var Url := FEngine.Text; FEngineDirty := False; if not RequestFinish then begin FEngineDirty := True; Exit; end; try FWorkspace.SetVoiceEngine(Url); except on E: Exception do begin FEngineDirty := True; FEngine.Text := Url; FWorkspace.BeginScriptTextEdit; FGuide.Caption := E.Message; end; end; end;
procedure TRigmScriptVoiceFrame.EngineChanged(Sender: TObject);
begin if FSync then Exit; FEngineDirty := True; FWorkspace.BeginScriptTextEdit; end;
procedure TRigmScriptVoiceFrame.RefreshCatalog(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.RefreshVoiceCatalog; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Bind(Sender: TObject);
begin
  if FSync or (FStyle.ItemIndex<0) then Exit; var Index := FStyle.ItemIndex;
  if not RequestFinish then Exit;
  try var O := TJSONObject(FWorkspace.VoiceCatalog[Index]); FWorkspace.BindVoice(Number,JI(O,'styleId',-1),JS(O,'uuid')); except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptVoiceFrame.SaveDefault(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.SaveCharacterVoice(Number); FGuide.Caption := '登録キャラの声の初期値を保存しました。'; except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Preview(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.GenerateVoice(SelectedId,True); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Generate(Sender: TObject);
begin if not RequestFinish then Exit; try FWorkspace.GenerateVoice(SelectedId,False); except on E: Exception do FGuide.Caption := E.Message; end; end;
procedure TRigmScriptVoiceFrame.Cancel(Sender: TObject);
begin FWorkspace.CancelVoice; end;
procedure TRigmScriptVoiceFrame.SetActive(Value: Boolean);
begin if not Value and FActive then FWorkspace.StopVoice; FActive := Value; end;
procedure TRigmScriptVoiceFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('voice')=nil) then Exit; var Id := SelectedId; var C := P.Cue(Id); if C=nil then Exit;
  FSync := True; FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for var Cue in P.Cues do begin var Item := FList.Items.Add; Item.Caption := '未生成'; if P.AudioReady(Cue) then Item.Caption := '生成済' else if P.HasStoredAudio(Cue) then Item.Caption := '旧音声'; Item.SubItems.Add(Cue.SpokenText); Item.SubItems.Add(Cue.Id); Item.Selected := Cue.Id=Id; end;
    var S := P.Speaker(C.SpeakerId); FActor.Caption := JS(CastingRole(P,Number),'name')+' / 声：未割当';
    if S.StyleId>=0 then FActor.Caption := JS(CastingRole(P,Number),'name')+' / '+S.VoiceName+' '+S.StyleName+' ('+S.StyleId.ToString+')';
    FStyle.Items.Clear; for var V in FWorkspace.VoiceCatalog do begin var O := TJSONObject(V); FStyle.Items.Add(JS(O,'name')+' / '+JS(O,'style')+' ['+JI(O,'styleId').ToString+']'); end; FStyle.ItemIndex := -1;
    for var I := 0 to FWorkspace.VoiceCatalog.Count-1 do if (JI(TJSONObject(FWorkspace.VoiceCatalog[I]),'styleId',-1)=S.StyleId) and (JS(TJSONObject(FWorkspace.VoiceCatalog[I]),'uuid')=S.VoiceUuid) then FStyle.ItemIndex := I;
    if not FEditing or (FLoaded<>Id) then begin
      FReading.Text := C.SpokenText; FSubtitle.Text := C.Subtitle; FLoaded := Id;
      FValues[0].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[0],S.Speed)); FValues[1].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[1],S.Pitch)); FValues[2].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[2],S.Intonation)); FValues[3].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[3],S.Volume));
      FValues[4].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[4],0.1)); FValues[5].Text := FloatToStr(JN(C.VoiceSettings,ValueKeys[5],0.1));
    end;
    if not FEngineDirty then FEngine.Text := P.EngineUrl;
    FReading.ReadOnly := not FEditing; for var E in FValues do E.Enabled := FEditing;
    var State := FWorkspace.VoiceStatus;
    try FGuide.Caption := '↑↓：セリフ移動 / Enter：読み・数値編集 / F5：現在のセリフを生成・試聴。'+#13#10+'生成済み '+JI(State,'ready').ToString+' / '+P.Cues.Count.ToString;
      if FWorkspace.VoiceBusy then FGuide.Caption := FGuide.Caption+'　処理中（取消可）'; if JS(State,'error')<>'' then FGuide.Caption := FGuide.Caption+#13#10+JS(State,'error');
    finally State.Free; end;
  finally FList.Items.EndUpdate; FSync := False; end;
end;
end.
