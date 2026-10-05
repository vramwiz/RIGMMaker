// GUIと共通パイプで開始された出力ジョブの進捗・完了・再試行表示を管理する。
// 作品入力は変更せず、完了通知は同じジョブにつき一度だけ要求する。
unit RigmMovieExportFeedback;
interface
uses System.JSON, Vcl.Forms, Vcl.Controls, RigmMovieSession, RigmMovieControls;
type
  TRigmMovieExportFeedback = class
  private
    FOwner  : TWinControl;              // 配置と再整列に使う借用フォーム。
    FSession: TRigmMovieSession;  // ジョブ結果を読む借用セッション。
    FUi     : TRigmMovieControls; // 更新対象の借用コントロール集合。
    FNotifiedExport,FExportProject,FExportJobId,FCompletedExport,FExportWarning,FExportError: string;
    FExportRefreshTick: UInt64;  // 実行中の表示更新を200 ms間隔へ抑える。
    FExportFinished   : Boolean; // 終了結果を表示済みなら継続ポーリングを止める。
    function JobStatus(Args: TJSONObject=nil): TJSONObject;
  public
    // 引数は借用し、コントロールとセッションの寿命は呼び出し側が管理する。
    constructor Create(Owner: TWinControl; Session: TRigmMovieSession; Ui: TRigmMovieControls);
    // 出力パネルの寸法と文字を所有フォーム、または埋込み親の現在DPIへ合わせる。
    procedure LayoutExportFeedback;
    // 失敗を表示する。実行中ジョブがある場合は警告として同じ進捗表示へ加える。
    procedure ShowExportError(const Message: string);
    // 現在のジョブを読み取り、完了・回収・実ファイル確認後に一度だけ通知する。
    procedure RefreshExport;
    // 次の出力を開始する前に、以前のエラーと完了ファイル参照を消す。警告文は保持する。
    procedure Reset;
    // 作品切替時に以前のジョブの監視を解除し、出力パネルを隠す。
    procedure ClearProject;
    // 開始済みジョブIdを現在の作品に関連付けて監視する。ジョブ自体は開始しない。
    procedure BeginJob(const Id: string);
    property Warning: string read FExportWarning write FExportWarning; // 保存済み音声を使用する等、出力を継続できる注意文。
    property Error: string read FExportError; // 出力開始に失敗した理由。進捗中の注意文とは分ける。
    property CompletedPath: string read FCompletedExport; // 成功・回収・存在を確認した動画の絶対パス。未完了は空文字。
  end;
implementation
uses Winapi.Windows, System.SysUtils, System.Math, Vcl.ComCtrls,
  RigmJson, RigmMovieJobPresentation;
constructor TRigmMovieExportFeedback.Create(Owner: TWinControl; Session: TRigmMovieSession; Ui: TRigmMovieControls);
begin inherited Create; FOwner := Owner; FSession := Session; FUi := Ui; end;
function TRigmMovieExportFeedback.JobStatus(Args: TJSONObject): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try Result := FSession.Execute('job-status',Args); finally Args.Free; end;
end;
procedure TRigmMovieExportFeedback.Reset;
begin FExportError := ''; FCompletedExport := ''; end;
procedure TRigmMovieExportFeedback.ClearProject;
begin FExportJobId := ''; FExportProject := ''; FUi.ExportPanel.Visible := False; end;
procedure TRigmMovieExportFeedback.BeginJob(const Id: string);
begin FExportJobId := Id; FExportProject := FSession.Project.Id; FExportFinished := False; end;
procedure TRigmMovieExportFeedback.LayoutExportFeedback;
begin
  if FUi.ExportPanel=nil then Exit;
  var Host := GetParentForm(FOwner,True); var PPI := FOwner.CurrentPPI; if Host<>nil then PPI := Host.CurrentPPI;
  FUi.ExportPanel.Height := MulDiv(78,PPI,96);
  FUi.ExportResult.Width := MulDiv(130,PPI,96); FUi.ExportProgress.Height := MulDiv(10,PPI,96);
  FUi.ExportStatus.Font.Height := -MulDiv(15,PPI,96);
  FUi.ExportStatus.Margins.Left := MulDiv(10,PPI,96); FUi.ExportStatus.Margins.Right := MulDiv(10,PPI,96);
  FUi.ExportStatus.AlignWithMargins := True;
end;

procedure TRigmMovieExportFeedback.ShowExportError(const Message: string);
begin
  if (FExportJobId<>'') and FSession.Busy then begin FExportWarning := Message; RefreshExport; Exit; end;
  FExportJobId := '';
  FExportError := Message; FUi.ExportPanel.Visible := True;
  FUi.ExportStatus.Caption := Message; FUi.ExportStatus.Hint := Message;
  FUi.ExportResult.Caption := '保存先を選び直す'; FUi.ExportResult.Tag := 13; FUi.ExportResult.Enabled := True;
end;

procedure TRigmMovieExportFeedback.RefreshExport;
begin
  // Observe exports started through either the GUI or the shared pipe.
  if FSession.CurrentJobKind='export' then begin
    var Current := JobStatus;
    try
      if (JS(Current,'snapshotProjectId')=FSession.Project.Id) and
        (JS(Current,'jobId')<>FExportJobId) then begin
        FExportJobId := JS(Current,'jobId'); FExportProject := FSession.Project.Id;
        FCompletedExport := ''; FExportError := ''; FExportRefreshTick := 0; FExportFinished := False;
      end;
    finally Current.Free; end;
  end;
  if (FExportJobId='') or (FExportProject<>FSession.Project.Id) or FExportFinished then Exit;
  var A := TJSONObject.Create; A.AddPair('jobId',FExportJobId); var Job := JobStatus(A);
  try
    if not JB(Job,'done') and (GetTickCount64-FExportRefreshTick<200) then Exit;
    FExportRefreshTick := GetTickCount64;
    var Text := 'MP4 / AVI 書き出し: '+MovieJobText(Job);
    if (JS(Job,'phase')='render') and (JN(Job,'phaseTotal')>0) then
      Text := Text+Format('  %.0f / %.0f フレーム',[JN(Job,'phaseCompleted'),JN(Job,'phaseTotal')]);
    if FExportWarning<>'' then Text := Text+sLineBreak+FExportWarning;
    FUi.ExportResult.Tag := 9; FUi.ExportResult.Caption := '書き出しを中止';
    if JB(Job,'done') then begin
      if (JS(Job,'state')='succeeded') and JB(Job,'collected') and
        (not SameText(ExtractFileExt(JS(Job,'output')),'.mp4') or JB(Job,'encoderExited')) and
        FileExists(JS(Job,'output')) then begin
        FCompletedExport := JS(Job,'output'); Text := '動画を書き出しました: '+ExtractFileName(FCompletedExport);
        if FExportWarning<>'' then Text := Text+sLineBreak+FExportWarning;
        FUi.ExportResult.Caption := '保存先を開く'; FUi.ExportResult.Tag := 40;
        if FNotifiedExport<>FExportJobId then begin
          FNotifiedExport := FExportJobId;
          FUi.ExportNotification.ExportFinished(FCompletedExport);
        end;
      end else begin
        Text := '動画書き出し: '+MovieJobText(Job); FUi.ExportResult.Caption := '保存先を選び直す'; FUi.ExportResult.Tag := 13;
      end;
    end;
    var KnownProgress := JN(Job,'phaseTotal')>0;
    var Style := pbstNormal;
    if not KnownProgress and not JB(Job,'done') then Style := pbstMarquee;
    if FUi.ExportProgress.Style<>Style then FUi.ExportProgress.Style := Style;
    var Position := 0;
    if KnownProgress then Position := Round(EnsureRange(JN(Job,'phaseCompleted')/JN(Job,'phaseTotal'),0.0,1.0)*1000);
    if (JS(Job,'state')='succeeded') and JB(Job,'done') then Position := 1000;
    if FUi.ExportProgress.Position<>Position then FUi.ExportProgress.Position := Position;
    FExportFinished := JB(Job,'done') and ((JS(Job,'state')<>'succeeded') or (FCompletedExport<>''));
    FUi.ExportResult.Enabled := not JB(Job,'cancelRequested') or JB(Job,'done');
    if FUi.ExportStatus.Caption<>Text then FUi.ExportStatus.Caption := Text;
    FUi.ExportStatus.Hint := JS(Job,'output')+sLineBreak+Text;
    if not FUi.ExportPanel.Visible then begin
      LayoutExportFeedback;
      FUi.ExportPanel.SetBounds(0,FOwner.ClientHeight-FUi.ExportPanel.Height,FOwner.ClientWidth,FUi.ExportPanel.Height);
      FUi.ExportPanel.Visible := True; FUi.ExportPanel.BringToFront; FOwner.Realign;
    end;
  finally Job.Free; end;
end;
end.
