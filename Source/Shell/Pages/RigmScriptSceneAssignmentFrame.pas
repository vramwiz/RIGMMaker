unit RigmScriptSceneAssignmentFrame;

interface
uses System.Classes, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, RigmScriptPageFrame, RigmWizardWorkspace;
type
  TRigmScriptSceneAssignmentFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FList: TListView; FGuide,FInfo: TLabel;
    procedure Checked(Sender: TObject; Item: TListItem);
    procedure Selected(Sender: TObject; Item: TListItem; Value: Boolean);
    procedure FitColumns;
  protected
    procedure Resize; override;
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean); override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
  end;
implementation
uses System.SysUtils, System.Math, System.Types, Winapi.Windows, Winapi.CommCtrl,
  Vcl.Graphics, Vcl.Themes, RigmBufferedControls, RigmJson, RigmScriptCastingModel,
  RigmScriptScenesModel, RigmScriptSceneAssignmentModel;
{$R *.dfm}
type
  TRigmSceneAssignmentList = class(TRigmBufferedListView)
  protected
    function IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean; override;
    function CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean; override;
  end;
function TRigmSceneAssignmentList.IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean;
begin Result := ((Target in [dtControl,dtItem]) and (Stage=cdPrePaint)) or inherited IsCustomDrawn(Target,Stage); end;
function TRigmSceneAssignmentList.CustomDrawItem(Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage): Boolean;
begin
  if Stage<>cdPrePaint then Exit(inherited CustomDrawItem(Item,State,Stage));
  Result := False;
  var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := ClientWidth;
  var Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Row.Left,Row.Top,Row.Right,Row.Bottom);
    Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := StyleServices(Self).GetStyleColor(scListView);
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText);
    if Item.Selected then begin Canvas.Brush.Color := $00D07000; Canvas.Font.Color := clWhite; end;
    Canvas.FillRect(Row); SetBkMode(Canvas.Handle,TRANSPARENT);
    var Header := ListView_GetHeader(Handle); var Padding := MulDiv(6,CurrentPPI,96);
    for var Index := 0 to Columns.Count-1 do begin
      var Cell: TRect; if not Header_GetItemRect(Header,Index,@Cell) then Continue;
      MapWindowPoints(Header,Handle,Cell,2); Cell.Top := Row.Top; Cell.Bottom := Row.Bottom;
      var CellSaved := SaveDC(Canvas.Handle);
      try
        IntersectClipRect(Canvas.Handle,Cell.Left,Cell.Top,Cell.Right,Cell.Bottom);
        Inc(Cell.Left,Padding); Dec(Cell.Right,Padding);
        if Index=0 then begin
          if Item.Data<>nil then begin
            var Size := MulDiv(16,CurrentPPI,96);
            var Box := Rect(Cell.Left,Cell.Top+(Cell.Height-Size) div 2,Cell.Left+Size,Cell.Top+(Cell.Height+Size) div 2);
            var Flags: Cardinal := DFCS_BUTTONCHECK; if Item.Checked then Flags := Flags or DFCS_CHECKED;
            DrawFrameControl(Canvas.Handle,Box,DFC_BUTTON,Flags);
          end;
          Inc(Cell.Left,MulDiv(22,CurrentPPI,96));
        end;
        var Text := Item.Caption;
        if Index>0 then begin Text := ''; if Index<=Item.SubItems.Count then Text := Item.SubItems[Index-1]; end;
        if Cell.Right>Cell.Left then DrawText(Canvas.Handle,PChar(Text),Length(Text),Cell,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
      finally RestoreDC(Canvas.Handle,CellSaved); end;
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;
constructor TRigmScriptSceneAssignmentFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; Align := alClient;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alTop;
  FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Name := 'ScriptSceneAssignmentGuide';
  FGuide.Caption := '新しいシーンを始めるセリフにチェックを入れてください。チェックを外すと前のシーンへ結合します。'+#13#10+
    '例：3行目にチェック → 1〜2行目はシーン1、3行目以降はシーン2。1行目は常にシーン1の開始です。';
  FInfo := TRigmScriptLabel.Create(Self); FInfo.Parent := Self; FInfo.Align := alBottom;
  FInfo.AutoSize := False; FInfo.WordWrap := True; FInfo.Name := 'ScriptSceneAssignmentInfo';
  FList := TRigmSceneAssignmentList.Create(Self); FList.Parent := Self; FList.Align := alClient;
  FList.Name := 'ScriptSceneAssignmentRows'; FList.ViewStyle := vsReport; FList.ReadOnly := True;
  FList.RowSelect := True; FList.HideSelection := False; FList.Checkboxes := True;
  FList.Columns.Add.Caption := '開始 / 行'; FList.Columns.Add.Caption := 'シーン';
  FList.Columns.Add.Caption := '配役'; FList.Columns.Add.Caption := 'セリフ';
  FList.OnItemChecked := Checked; FList.OnSelectItem := Selected;
  FitColumns;
end;
procedure TRigmScriptSceneAssignmentFrame.FitColumns;
begin
  if (FList=nil) or (FList.Columns.Count<>4) then Exit;
  FList.Columns[0].Width := ScaleValue(90); FList.Columns[1].Width := ScaleValue(80);
  FList.Columns[2].Width := ScaleValue(170);
  FList.Columns[3].Width := Max(ScaleValue(260),FList.ClientWidth-ScaleValue(340)-GetSystemMetrics(SM_CXVSCROLL));
end;
procedure TRigmScriptSceneAssignmentFrame.Resize;
begin inherited; FitColumns; end;
procedure TRigmScriptSceneAssignmentFrame.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; FitColumns; end;
procedure TRigmScriptSceneAssignmentFrame.Selected(Sender: TObject; Item: TListItem; Value: Boolean);
begin
  if Item=nil then Exit;
  var Row := Item.DisplayRect(drBounds); Row.Left := 0; Row.Right := FList.ClientWidth;
  InvalidateRect(FList.Handle,@Row,False);
end;
procedure TRigmScriptSceneAssignmentFrame.Checked(Sender: TObject; Item: TListItem);
begin
  if FSync or (Item=nil) then Exit;
  if Item.Data=nil then begin RefreshState; Exit; end;
  try FWorkspace.SetScriptSceneStart(Item.SubItems[3],Item.Checked);
  except on E: Exception do begin RefreshState; FInfo.Caption := E.Message; end; end;
end;
procedure TRigmScriptSceneAssignmentFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('scenes')=nil) then Exit;
  var Rebuild := FList.Items.Count<>P.Cues.Count;
  if not Rebuild then for var I := 0 to P.Cues.Count-1 do
    if (FList.Items[I].SubItems.Count<>4) or (FList.Items[I].SubItems[3]<>P.Cues[I].Id) then begin Rebuild := True; Break; end;
  var WasSync := FSync; FSync := True; if Rebuild then FList.Items.BeginUpdate;
  try
    if Rebuild then FList.Items.Clear;
    for var I := 0 to P.Cues.Count-1 do begin
      var Cue := P.Cues[I]; var Item: TListItem;
      if Rebuild then begin Item := FList.Items.Add; Item.Caption := (I+1).ToString; for var N := 0 to 3 do Item.SubItems.Add(''); Item.SubItems[3] := Cue.Id; end
      else Item := FList.Items[I];
      var Scene := ScriptSceneNumber(P,Cue.Scene).ToString;
      if Item.SubItems[0]<>Scene then Item.SubItems[0] := Scene;
      var Role := ScriptCueRole(P,Cue.Id); var Name := '';
      if CastingRole(P,Role)<>nil then Name := JS(CastingRole(P,Role),'name');
      if Item.SubItems[1]<>Name then Item.SubItems[1] := Name;
      if Item.SubItems[2]<>Cue.Text then Item.SubItems[2] := Cue.Text;
      if ScriptSceneStartEditable(P,I) then Item.Data := Pointer(1) else Item.Data := nil;
      var Start := ScriptSceneStartsAt(P,I); if Item.Checked<>Start then Item.Checked := Start;
      if Item.Data=nil then ListView_SetItemState(FList.Handle,I,0,LVIS_STATEIMAGEMASK);
    end;
    // 最初のセリフには開始チェックを表示しない。Spaceで操作されても割当は変えない。
    FInfo.Caption := P.Cues.Count.ToString+'セリフ / '+P.Scenes.Count.ToString+'シーン。左の工程リストで割当を保存し、シーンごとの画像・説明文へ進みます。';
  finally if Rebuild then FList.Items.EndUpdate; FSync := WasSync; end;
end;
end.
