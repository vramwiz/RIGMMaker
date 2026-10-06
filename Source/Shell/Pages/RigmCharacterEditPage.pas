unit RigmCharacterEditPage;
interface
uses System.Classes, Winapi.Messages, Vcl.Forms, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.StdCtrls,
  PsdStudioFrame, RigmLegacyEditorFrame, RigmWizardWorkspace, RigmPageNavigation, RigmIconToolbar;
type
  TRigmCharacterLoadingPanel = class(TPanel)
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    FirstPaintAt: UInt64; // 現在の読み込み案内を実際に描画した時刻。0は未描画。
    procedure Paint; override;
    procedure PaintImmediately;
  end;
  TRigmCharacterEditPage = class(TFrame,IRigmPageLifecycle)
  private
    FRoot: string; FWorkspace: TRigmWizardWorkspace;
    FPsd: TPsdStudioFrame; FLegacy: TRigmLegacyEditorFrame; FCurrent: TFrame;
    FLoading: TRigmCharacterLoadingPanel; FLoadingText: TLabel;
    FLoadStarted,FLoadFeedbackMs: UInt64; FLoadPaintedBeforeActivation: Boolean;
    FLoadDepth: Integer; FActive: Boolean; // 入れ子の読込完了まで案内を維持し、元の再生状態を復帰する。
    FOnReturn,FOnSaved: TNotifyEvent;
    procedure Return(Sender: TObject);
    procedure Saved(Sender: TObject);
    procedure SelectLegacy(Sender: TObject);
    function EnsurePsd: TPsdStudioFrame;
    function EnsureLegacy: TRigmLegacyEditorFrame;
    procedure ShowCurrentEditor;
    procedure PsdCharacterLoad(Sender: TObject; const Path: string; Loading: Boolean);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    function ActivateCharacter(const Path: string): Boolean;
    // 軽量な案内を表示する。メインフォームが描画を完了してから読み込みを開始する。
    procedure BeginCharacterLoad(const Path: string);
    procedure EndCharacterLoad;
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    procedure ActivateLegacyEditor;
    property OnReturn: TNotifyEvent read FOnReturn write FOnReturn;
    property OnSaved: TNotifyEvent read FOnSaved write FOnSaved;
    property PsdEditor: TPsdStudioFrame read FPsd;
    property LegacyEditor: TRigmLegacyEditorFrame read FLegacy;
    property LoadFeedbackMs: UInt64 read FLoadFeedbackMs;
    property LoadPaintedBeforeActivation: Boolean read FLoadPaintedBeforeActivation;
  end;
implementation
uses System.SysUtils, Vcl.Controls, Winapi.Windows, RigmToolbarIcons;
{$R *.dfm}
procedure TRigmCharacterLoadingPanel.Paint;
begin inherited; if FirstPaintAt=0 then FirstPaintAt := GetTickCount64; end;
procedure TRigmCharacterLoadingPanel.PaintImmediately;
begin
  if not Showing then Exit;
  // スタイルのWindowProcがVCLのPaint/WndProcを迂回しても、ネイティブの更新領域で描画完了を確認する。
  InvalidateRect(Handle,nil,False);
  var Pending := GetUpdateRect(Handle,nil,False);
  RedrawWindow(Handle,nil,0,RDW_UPDATENOW or RDW_ALLCHILDREN);
  if Pending and not GetUpdateRect(Handle,nil,False) and IsWindowVisible(Handle) and (FirstPaintAt=0) then
    FirstPaintAt := GetTickCount64;
end;
procedure TRigmCharacterLoadingPanel.WndProc(var Message: TMessage);
begin
  var PaintMessage := Message.Msg=WM_PAINT;
  inherited;
  // VCLスタイルがPaintを経由せず描画する場合も、完了したWM_PAINTで記録する。
  if PaintMessage and Showing and (FirstPaintAt=0) then FirstPaintAt := GetTickCount64;
end;
constructor TRigmCharacterEditPage.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; DoubleBuffered := True; FRoot := Root; FWorkspace := Workspace;
  FLoading := TRigmCharacterLoadingPanel.Create(Self); FLoading.Name := 'CharacterLoading';
  FLoading.Caption := ''; FLoading.ShowCaption := False;
  FLoading.Visible := False; FLoading.Parent := Self;
  FLoading.Align := alClient; FLoading.BevelOuter := bvNone; FLoading.DoubleBuffered := True;
  FLoadingText := TLabel.Create(Self); FLoadingText.Parent := FLoading; FLoadingText.Align := alClient;
  FLoadingText.Alignment := taCenter; FLoadingText.Layout := tlCenter; FLoadingText.WordWrap := True;
  FLoadingText.Font.Size := 16;
end;
procedure TRigmCharacterEditPage.BeginCharacterLoad(const Path: string);
begin
  Inc(FLoadDepth); if FLoadDepth>1 then Exit;
  if FPsd<>nil then FPsd.SetActive(False);
  if FLegacy<>nil then FLegacy.SetActive(False);
  FLoadStarted := GetTickCount64; FLoading.FirstPaintAt := 0;
  FLoadPaintedBeforeActivation := False;
  if FPsd<>nil then FPsd.Visible := False;
  if FLegacy<>nil then FLegacy.Visible := False;
  FLoadingText.Caption := '編集画面を準備しています…';
  if Path<>'' then FLoadingText.Caption := ExtractFileName(Path)+#13#10+'読み込み中…';
  FLoading.Visible := True; FLoading.BringToFront;
  if Showing then begin
    // 入力を処理せず案内の描画だけを完了してから、重いPSD読み込みへ進む。
    RedrawWindow(Handle,nil,0,RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN);
    FLoading.PaintImmediately;
    FLoadPaintedBeforeActivation := FLoading.FirstPaintAt<>0;
    if FLoadPaintedBeforeActivation then FLoadFeedbackMs := FLoading.FirstPaintAt-FLoadStarted;
  end;
end;
procedure TRigmCharacterEditPage.EndCharacterLoad;
begin
  if FLoadDepth=0 then Exit;
  Dec(FLoadDepth); if FLoadDepth>0 then Exit;
  // 工程ごとの初回表示（ボーン基準を含む）も案内の背後で準備する。
  try SetActive(FActive);
  finally FLoading.Visible := False; ShowCurrentEditor; end;
end;
procedure TRigmCharacterEditPage.PsdCharacterLoad(Sender: TObject; const Path: string; Loading: Boolean);
begin if Loading then BeginCharacterLoad(Path) else EndCharacterLoad; end;
function TRigmCharacterEditPage.EnsurePsd: TPsdStudioFrame;
begin
  if FPsd=nil then begin
    FPsd := TPsdStudioFrame.CreateForCharacter(Self,FRoot,''); FPsd.Visible := False;
    FPsd.Parent := Self; FPsd.Align := alClient; FPsd.OnReturn := Return; FPsd.OnSaved := Saved;
    FPsd.OnCharacterLoad := PsdCharacterLoad;
  end;
  Result := FPsd;
end;
function TRigmCharacterEditPage.EnsureLegacy: TRigmLegacyEditorFrame;
begin
  if FLegacy=nil then begin
    FLegacy := TRigmLegacyEditorFrame.CreateForRoot(Self,FRoot); FLegacy.Visible := False; FLegacy.SetActive(False);
    FLegacy.Parent := Self; FLegacy.Align := alClient;
    FLegacy.Editor.OnGetMovie := FWorkspace.ActiveSession; FLegacy.OnSaved := Saved;
    FLegacy.OnCharacterLoad := PsdCharacterLoad;
    FLegacy.Editor.OnWorkspaceCommand := FWorkspace.ExecuteWorkspace;
  end;
  Result := FLegacy;
end;
function TRigmCharacterEditPage.ActivateCharacter(const Path: string): Boolean;
begin
  if FLoading.Visible then begin
    if Showing then begin FLoading.BringToFront; FLoading.PaintImmediately; end;
    FLoadPaintedBeforeActivation := Showing and (FLoading.FirstPaintAt<>0);
    if FLoadPaintedBeforeActivation then FLoadFeedbackMs := FLoading.FirstPaintAt-FLoadStarted;
  end;
  if FPsd<>nil then FPsd.SetActive(False);
  if FLegacy<>nil then FLegacy.SetActive(False);
  if (Path='') or SameText(ExtractFileExt(Path),'.psdchar') or SameText(ExtractFileExt(Path),'.psd') then begin
    var Target := EnsurePsd; Result := (Path='') or FPsd.ActivateCharacter(Path);
    if Result or (FCurrent=nil) then FCurrent := Target;
  end else begin
    var Target := EnsureLegacy; Result := FLegacy.ActivateCharacter(Path);
    if Result or (FCurrent=nil) then FCurrent := Target;
  end;
  ShowCurrentEditor;
end;
procedure TRigmCharacterEditPage.ShowCurrentEditor;
begin
  if FPsd<>nil then FPsd.Visible := (FLoadDepth=0) and (FCurrent=FPsd);
  if FLegacy<>nil then FLegacy.Visible := (FLoadDepth=0) and (FCurrent=FLegacy);
  if FCurrent<>nil then FCurrent.BringToFront;
  if FLoading.Visible then FLoading.BringToFront;
end;
procedure TRigmCharacterEditPage.SetActive(Value: Boolean);
begin
  FActive := Value;
  if Value and (FCurrent=nil) then ActivateCharacter('');
  if FPsd<>nil then FPsd.SetActive(Value and (FLoadDepth=0) and (FCurrent=FPsd));
  if FLegacy<>nil then FLegacy.SetActive(Value and (FLoadDepth=0) and (FCurrent=FLegacy));
end;
function TRigmCharacterEditPage.RequestFinish: Boolean;
begin Result := ((FPsd=nil) or FPsd.RequestFinish) and ((FLegacy=nil) or FLegacy.RequestFinish); end;
procedure TRigmCharacterEditPage.Return(Sender: TObject);
begin if Assigned(FOnReturn) then FOnReturn(Self); end;
procedure TRigmCharacterEditPage.Saved(Sender: TObject);
begin if Assigned(FOnSaved) then FOnSaved(Self); end;
procedure TRigmCharacterEditPage.SelectLegacy(Sender: TObject);
begin
  BeginCharacterLoad('');
  try FCurrent := EnsureLegacy; FLegacy.PrepareForDisplay;
  finally EndCharacterLoad; SetActive(True); end;
end;
procedure TRigmCharacterEditPage.ActivateLegacyEditor;
begin SelectLegacy(Self); end;
end.
