unit RigmScriptVoiceEffectsFrame;
// 音声エフェクトの将来用工程。現段階は行別の「なし」を表示するだけで加工しない。
interface
uses System.Classes, RigmScriptPageFrame, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, RigmBufferedControls, RigmWizardWorkspace;
type
  TRigmScriptVoiceEffectsFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FList: TListView; FSync: Boolean;
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure Resized(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
  end;
implementation
uses System.SysUtils, System.Math, RigmJson, PsdJson;
{$R *.dfm}
constructor TRigmScriptVoiceEffectsFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  if AOwner is TWinControl then Parent := TWinControl(AOwner);
  var Guide := TRigmScriptLabel.Create(Self); Guide.Parent := Self; Guide.Align := alTop;
  Guide.AutoSize := False; Guide.Height := ScaleValue(60); Guide.WordWrap := True; Guide.Name := 'ScriptVoiceEffectsGuide';
  Guide.Caption := '音声エフェクト'+#13#10+'現在は全セリフ「なし」です。Nextでシーン画像・説明文へ進めます。';
  FList := TRigmBufferedListView.Create(Self); FList.Parent := Self; FList.Align := alClient;
  FList.Name := 'ScriptVoiceEffectsRows'; FList.ViewStyle := vsReport; FList.RowSelect := True; FList.ReadOnly := True;
  FList.HideSelection := False; FList.OnSelectItem := Selected;
  FList.Columns.Add.Caption := 'セリフ'; FList.Columns[0].Width := ScaleValue(700);
  FList.Columns.Add.Caption := 'エフェクト'; FList.Columns[1].Width := ScaleValue(160);
  OnResize := Resized;
end;
procedure TRigmScriptVoiceEffectsFrame.Resized(Sender: TObject);
begin if FList<>nil then FList.Columns[0].Width := Max(ScaleValue(120),FList.ClientWidth-FList.Columns[1].Width-ScaleValue(24)); end;
procedure TRigmScriptVoiceEffectsFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  if FSync or not Value then Exit;
  PsdJson.Put(JO(FWorkspace.ScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue',Item.SubItems[1]);
  FWorkspace.ScriptDraft.Changed;
end;
procedure TRigmScriptVoiceEffectsFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('voiceEffects')=nil) then Exit;
  var Id := JS(JO(P.ScriptWizard,'voiceEffects'),'selectedCue'); var Rebuild := FList.Items.Count<>P.Cues.Count;
  if not Rebuild then for var I := 0 to P.Cues.Count-1 do
    if (FList.Items[I].SubItems.Count<>2) or (FList.Items[I].SubItems[1]<>P.Cues[I].Id) then begin Rebuild := True; Break; end;
  FSync := True; if Rebuild then FList.Items.BeginUpdate;
  try
    if Rebuild then FList.Items.Clear;
    for var I := 0 to P.Cues.Count-1 do begin
      var C := P.Cues[I]; var Item: TListItem;
      if Rebuild then begin Item := FList.Items.Add; Item.SubItems.Add(''); Item.SubItems.Add(C.Id); end else Item := FList.Items[I];
      if Item.Caption<>C.SpokenText then Item.Caption := C.SpokenText;
      var Effect := C.AudioEffect; if Effect='none' then Effect := 'なし';
      if Item.SubItems[0]<>Effect then Item.SubItems[0] := Effect;
      if Item.Selected<>(C.Id=Id) then Item.Selected := C.Id=Id;
    end;
  finally if Rebuild then FList.Items.EndUpdate; FSync := False; end;
end;
end.
