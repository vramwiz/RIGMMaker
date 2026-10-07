unit RigmScriptSubtitleFrame;

// 配役を表示し、字幕専用編集と既存合成の字幕プレビューを同じWorkspaceに接続する。
interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Graphics, RigmWizardWorkspace, RigmIconToolbar, RigmScriptTextFrame;
type
  TRigmSubtitlePreview = class(TCustomControl)
  private
    FWorkspace: TRigmWizardWorkspace; FPage,FPageCount: Integer; FBitmap: TBitmap;
  protected
    procedure Paint; override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshPreview; // 同じ寸法・フォントで合成字幕の1ページを描く。
    procedure MovePage(Delta: Integer);
    function AutomaticBreak: Integer; // 現在表示文の自動折返し位置。
    property PageCount: Integer read FPageCount;
    property PageIndex: Integer read FPage; // 0始まり。プレビュー送りの境界判定用。
    property Bitmap: TBitmap read FBitmap; // 借用。表示中ページ。
  end;
  TRigmScriptSubtitleFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync,FEditing: Boolean; FLoaded,FInputError: string;
    FList: TListView; FEditor,FNote: TRigmScriptMemo; FVoice: TMemo;
    FPreview: TRigmSubtitlePreview; FActor,FGuide: TLabel; FToolbar: TRigmIconToolbar;
    procedure Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BeginInput(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure Detail(Sender: TObject);
    procedure Complete(Sender: TObject);
    procedure Page(Sender: TObject);
    procedure UpdatePageButtons;
    function SelectedId: string;
    function ApplyCurrent: Boolean; // 拒否された編集欄を再検査し、成功時だけ正本へ反映する。
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState; // 入力中のカーソルを保って表示を更新する。
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean; // 保存・遷移前に未反映入力を確定する。失敗時は入力を保持する。
    property Preview: TRigmSubtitlePreview read FPreview;
    property InputError: string read FInputError; // 遷移元の状態欄にも拒否理由を残す。
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, System.Types, Winapi.Windows,
  RigmJson, RigmMovieRendering, RigmMovieLayout, RigmScriptSubtitleModel, RigmScriptTextModel, RigmScriptCastingModel, RigmToolbarIcons;
{$R *.dfm}
constructor TRigmSubtitlePreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(AOwner); FWorkspace := Workspace; FBitmap := Vcl.Graphics.TBitmap.Create; FBitmap.PixelFormat := pf32bit; DoubleBuffered := True; end;
destructor TRigmSubtitlePreview.Destroy;
begin FBitmap.Free; inherited; end;
procedure TRigmSubtitlePreview.RefreshPreview;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('subtitles')=nil) then Exit;
  var C := P.Cue(JS(JO(P.ScriptWizard,'subtitles'),'selectedCue')); if C=nil then Exit;
  var Outer := ScaleLayoutRect(MovieLayoutRegions(P.Layout,P.LDirection).Subtitle,P.Width,P.Height);
  var R := MovieSubtitleContentRect(P); R.Offset(-Outer.Left,-Outer.Top);
  FBitmap.SetSize(Outer.Width,Outer.Height); FBitmap.Canvas.Brush.Style := bsSolid; FBitmap.Canvas.Brush.Color := $251E18;
  FBitmap.Canvas.FillRect(Rect(0,0,FBitmap.Width,FBitmap.Height)); MovieSubtitleStyle(FBitmap.Canvas,P.Height);
  var Lines := Max(1,R.Height div Max(1,FBitmap.Canvas.TextHeight('国'))); var Count: Integer;
  MovieSubtitlePage(C.Subtitle,FBitmap.Canvas,R.Width,Lines,0,Count); FPage := EnsureRange(FPage,0,Count-1); FPageCount := Count;
  var Text := MovieSubtitlePage(C.Subtitle,FBitmap.Canvas,R.Width,Lines,FPage/Max(1,Count),Count);
  FBitmap.Canvas.Brush.Style := bsClear; FBitmap.Canvas.Font.Color := clWhite; FBitmap.Canvas.TextHeight('国');
  SetBkMode(FBitmap.Canvas.Handle,TRANSPARENT); SetTextColor(FBitmap.Canvas.Handle,RGB(255,255,255));
  DrawText(FBitmap.Canvas.Handle,PChar(Text),Length(Text),R,DT_CENTER or DT_NOPREFIX); Invalidate;
end;
procedure TRigmSubtitlePreview.Paint;
begin
  Canvas.Brush.Color := clBlack; Canvas.FillRect(ClientRect); if (FBitmap.Width=0) or (FBitmap.Height=0) then Exit;
  var K := Min(ClientWidth/FBitmap.Width,(ClientHeight-28)/FBitmap.Height); var W := Round(FBitmap.Width*K); var H := Round(FBitmap.Height*K);
  Canvas.StretchDraw(Rect((ClientWidth-W) div 2,4,(ClientWidth+W) div 2,4+H),FBitmap);
  Canvas.Font.Height := -18; Canvas.Font.Color := clSilver; Canvas.Brush.Style := bsClear; Canvas.TextOut(8,ClientHeight-25,'字幕 '+(FPage+1).ToString+' / '+FPageCount.ToString+' ページ（動画と同じ折返し）');
end;
procedure TRigmSubtitlePreview.MovePage(Delta: Integer);
begin FPage := EnsureRange(FPage+Delta,0,Max(0,FPageCount-1)); RefreshPreview; end;
function TRigmSubtitlePreview.AutomaticBreak: Integer;
begin
  Result := 1; var P := FWorkspace.ScriptDraft; var C := P.Cue(JS(JO(P.ScriptWizard,'subtitles'),'selectedCue'));
  if C=nil then Exit; MovieSubtitleStyle(FBitmap.Canvas,P.Height); var Lines := MovieSubtitleLines(C.Subtitle,FBitmap.Canvas,MovieSubtitleContentRect(P).Width);
  try if Lines.Count>0 then Result := Length(Lines[0]); finally Lines.Free; end;
end;
constructor TRigmScriptSubtitleFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Name := 'ScriptSubtitleToolbar';
  FToolbar.AddIcon('ScriptSubtitleEdit','Enter：表示字幕・改行・メモを編集',riEditPreview,0,Detail);
  FToolbar.AddIcon('ScriptSubtitleReady','字幕入力完了（Ctrl+Enter / Esc、次の工程へは上段Next）',riComplete,0,Complete);
  FToolbar.AddSeparator; FToolbar.AddIcon('ScriptSubtitlePrevious','前の字幕ページ',riUp,0,Page).Tag := -1;
  FToolbar.AddIcon('ScriptSubtitleFollowing','次の字幕プレビューページ',riDown,0,Page).Tag := 1;
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alBottom; FGuide.AutoSize := False; FGuide.WordWrap := True; FGuide.Height := 70; FGuide.Name := 'ScriptSubtitleGuide';
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := 310; FList.ViewStyle := vsReport;
  FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False; FList.OnSelectItem := Selected; FList.OnKeyDown := HandleKey; FList.Name := 'ScriptSubtitleRows';
  FList.Columns.Add.Caption := '配役'; FList.Columns[0].Width := 60;
  FList.Columns.Add.Caption := '表示字幕'; FList.Columns[1].Width := 240;
  var Splitter := TSplitter.Create(Self); Splitter.Parent := Self; Splitter.Align := alLeft;
  var Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient; Body.Caption := ''; Body.BevelOuter := bvNone;
  FActor := TLabel.Create(Self); FActor.Parent := Body; FActor.Align := alTop; FActor.AutoSize := False; FActor.Height := 38; FActor.Name := 'ScriptSubtitleActor';
  FPreview := TRigmSubtitlePreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Body; FPreview.Align := alTop; FPreview.Height := 110; FPreview.Name := 'ScriptSubtitlePreview';
  var VoicePanel := TPanel.Create(Self); VoicePanel.Parent := Body; VoicePanel.Align := alBottom; VoicePanel.Top := 10000; VoicePanel.Height := 88; VoicePanel.BevelOuter := bvNone; VoicePanel.Caption := '';
  var VoiceLabel := TLabel.Create(Self); VoiceLabel.Parent := VoicePanel; VoiceLabel.Align := alTop; VoiceLabel.AutoSize := False; VoiceLabel.Height := 22; VoiceLabel.Font.Height := -18; VoiceLabel.Caption := '音声文（保持・読取専用）';
  FVoice := TMemo.Create(Self); FVoice.Parent := VoicePanel; FVoice.Align := alClient; FVoice.Font.Height := -22; FVoice.ReadOnly := True; FVoice.ScrollBars := ssVertical; FVoice.Name := 'ScriptSubtitleVoice';
  var NotePanel := TPanel.Create(Self); NotePanel.Parent := Body; NotePanel.Align := alBottom; NotePanel.Top := 0; NotePanel.Height := 74; NotePanel.BevelOuter := bvNone; NotePanel.Caption := '';
  var NoteLabel := TLabel.Create(Self); NoteLabel.Parent := NotePanel; NoteLabel.Align := alTop; NoteLabel.AutoSize := False; NoteLabel.Height := 22; NoteLabel.Font.Height := -18; NoteLabel.Caption := '字幕のメモ';
  FNote := TRigmScriptMemo.Create(Self); FNote.Parent := NotePanel; FNote.Align := alClient; FNote.Font.Height := -22; FNote.ReadOnly := True; FNote.MaxLength := 2048; FNote.ScrollBars := ssVertical; FNote.Name := 'ScriptSubtitleNote';
  FNote.OnChange := Changed; FNote.OnBeginInput := BeginInput; FNote.OnKeyDown := EditKey;
  FEditor := TRigmScriptMemo.Create(Self); FEditor.Parent := Body; FEditor.Align := alClient; FEditor.Font.Height := -26;
  FEditor.ReadOnly := True; FEditor.MaxLength := 3000; FEditor.ScrollBars := ssVertical; FEditor.Name := 'ScriptSubtitleText';
  FEditor.OnChange := Changed; FEditor.OnBeginInput := BeginInput; FEditor.OnKeyDown := EditKey;
end;
function TRigmScriptSubtitleFrame.SelectedId: string;
begin Result := ''; if FList.Selected<>nil then Result := FList.Selected.SubItems[1]; end;
procedure TRigmScriptSubtitleFrame.BeginInput(Sender: TObject);
begin if not FSync and FEditing then FWorkspace.BeginScriptTextEdit; end;
procedure TRigmScriptSubtitleFrame.Changed(Sender: TObject);
begin
  if FSync or not FEditing then Exit; BeginInput(Sender);
  try FInputError := ''; FWorkspace.EditSubtitle(FLoaded,FEditor.Text,FNote.Text);
  except on E: Exception do begin FInputError := E.Message; FGuide.Caption := FInputError; end; end;
end;
function TRigmScriptSubtitleFrame.ApplyCurrent: Boolean;
begin
  Result := False;
  try
    if FEditing then begin
      var C := FWorkspace.ScriptDraft.Cue(FLoaded); if C=nil then raise Exception.Create('編集対象の字幕がありません。入力を保持しています。');
      var Text := NormalizeScriptText(FEditor.Text); var Note := NormalizeScriptText(FNote.Text);
      ValidateSubtitleText(Text,3000); ValidateSubtitleText(Note,2048);
      FInputError := '';
      if (C.Subtitle<>Text) or (C.SubtitleNote<>Note) then FWorkspace.EditSubtitle(FLoaded,Text,Note);
    end;
    FInputError := ''; Result := True;
  except on E: Exception do begin FInputError := E.Message; FGuide.Caption := FInputError; end; end;
end;
function TRigmScriptSubtitleFrame.RequestFinish: Boolean;
begin
  Result := ApplyCurrent; if not Result then Exit;
  FEditing := False; FEditor.ReadOnly := True; FNote.ReadOnly := True; FWorkspace.EndScriptTextEdit;
end;
procedure TRigmScriptSubtitleFrame.Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSync or not Selected then Exit; var Id := Item.SubItems[1];
  if not RequestFinish then begin
    FSync := True; try for var Entry in FList.Items do Entry.Selected := Entry.SubItems[1]=FLoaded; finally FSync := False; end; Exit;
  end;
  try FWorkspace.SelectSubtitle(Id); except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptSubtitleFrame.HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift<>[] then Exit;
  if not (Key in [VK_UP,VK_DOWN,VK_LEFT,VK_RIGHT,VK_RETURN]) then Exit;
  if not RequestFinish then begin Key := 0; Exit; end;
  try
    if Key=VK_UP then FWorkspace.MoveSubtitle(-1) else if Key=VK_DOWN then FWorkspace.MoveSubtitle(1)
    else if Key=VK_LEFT then FWorkspace.MoveSubtitleBreak(SelectedId,-1,FPreview.AutomaticBreak)
    else if Key=VK_RIGHT then FWorkspace.MoveSubtitleBreak(SelectedId,1,FPreview.AutomaticBreak)
    else if Key=VK_RETURN then Detail(Self) else Exit;
  except on E: Exception do FGuide.Caption := E.Message; end; Key := 0;
end;
procedure TRigmScriptSubtitleFrame.EditKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if (Key=VK_ESCAPE) or ((Key=VK_RETURN) and (ssCtrl in Shift)) then begin Complete(Self); Key := 0; end; end;
procedure TRigmScriptSubtitleFrame.Detail(Sender: TObject);
begin
  try
    RequireCurrentSubtitles(FWorkspace.ScriptDraft);
    FInputError := ''; FEditing := True; FEditor.ReadOnly := False; FNote.ReadOnly := False; FWorkspace.BeginScriptTextEdit; FEditor.SetFocus;
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptSubtitleFrame.Complete(Sender: TObject);
begin
  if not ApplyCurrent then Exit;
  try
    RequireCurrentSubtitles(FWorkspace.ScriptDraft);
    FEditing := False; FEditor.ReadOnly := True; FNote.ReadOnly := True; FWorkspace.CompleteSubtitles; FList.SetFocus;
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmScriptSubtitleFrame.Page(Sender: TObject);
begin FPreview.MovePage(TToolButton(Sender).Tag); UpdatePageButtons; end;
procedure TRigmScriptSubtitleFrame.UpdatePageButtons;
begin
  TToolButton(FToolbar.FindComponent('ScriptSubtitlePrevious')).Enabled := FPreview.PageIndex>0;
  TToolButton(FToolbar.FindComponent('ScriptSubtitleFollowing')).Enabled := FPreview.PageIndex+1<FPreview.PageCount;
end;
procedure TRigmScriptSubtitleFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if (P=nil) or (P.ScriptWizard.GetValue('subtitles')=nil) then Exit;
  var Id := JS(JO(P.ScriptWizard,'subtitles'),'selectedCue'); var C := P.Cue(Id); if C=nil then Exit;
  FSync := True; FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for var Cue in P.Cues do begin
      var Item := FList.Items.Add;
      Item.Caption := ScriptCueRole(P,Cue.Id).ToString; Item.SubItems.Add(Cue.Subtitle.Replace(#13#10,' / ')); Item.SubItems.Add(Cue.Id);
      if Cue.Id=Id then begin Item.Selected := True; Item.Focused := True; end;
    end;
    if FList.Selected<>nil then FList.Selected.MakeVisible(False);
    if (FLoaded<>Id) or not FEditing then begin
      if FLoaded<>Id then FEditing := False; FEditor.Text := C.Subtitle; FNote.Text := C.SubtitleNote;
      FEditor.ReadOnly := not FEditing; FNote.ReadOnly := not FEditing; FLoaded := Id;
    end;
    FVoice.Text := C.Text; var RoleNumber := ScriptCueRole(P,Id); FActor.Caption := RoleNumber.ToString+' / '+JS(CastingRole(P,RoleNumber),'name');
    FGuide.Caption := '↑↓：セリフ選択 / ←→：最初の折返し移動 / Enter：表示文・改行・メモの編集。'+#13#10+'Ctrl+Enter / Esc：入力完了。原稿と音声文は保持します。';
    var Problem := ScriptSubtitleBlockReason(P,False);
    TToolButton(FToolbar.FindComponent('ScriptSubtitleEdit')).Enabled := Problem='';
    TToolButton(FToolbar.FindComponent('ScriptSubtitleReady')).Enabled := Problem='';
    if Problem<>'' then FGuide.Caption := Problem+' 以前の字幕とメモは保持しています。'
    else if FEditing then FGuide.Caption := FGuide.Caption+#13#10+'入力中：完了するまでNextへ進めません。'
    else if JS(P.ScriptWizard,'subtitlesStatus')='complete' then FGuide.Caption := FGuide.Caption+#13#10+'字幕入力完了：上段のNextで保存し、読み・音声調整へ進めます。'
    else FGuide.Caption := FGuide.Caption+#13#10+'字幕入力完了のチェックアイコンを押してから、上段のNextで音声へ進んでください。';
    if FInputError<>'' then FGuide.Caption := FInputError;
    FPreview.RefreshPreview; UpdatePageButtons;
  finally FList.Items.EndUpdate; FSync := False; end;
end;
procedure TRigmScriptSubtitleFrame.SetActive(Value: Boolean);
begin if not Value and FEditing then RequestFinish; end;
end.
