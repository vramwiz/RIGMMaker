unit RigmMoviePostingFrame;

interface
uses System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, RigmMovieSession;
type
  TRigmMoviePostingFrame = class(TPanel)
  private
    FSession: TRigmMovieSession; FSync,FUnapplied: Boolean; FProjectId: string; FRevision,FPreviousRevision: Integer;
    FTitle,FParents: TEdit; FDescription: TMemo; FGuide: TLabel;
    FOnEdited: TNotifyEvent;
    procedure Edited(Sender: TObject);
    procedure CopyText(Sender: TObject);
    procedure UseWork(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Bind(Session: TRigmMovieSession; OnEdited: TNotifyEvent);
    procedure RefreshState;
    property PreviousRevision: Integer read FPreviousRevision;
  end;
implementation
uses System.SysUtils, System.JSON, Vcl.Clipbrd, RigmJson, RigmMoviePosting;

constructor TRigmMoviePostingFrame.Create(AOwner: TComponent);
  function LabelAt(const Caption: string; Y: Integer): TLabel;
  begin
    Result := TLabel.Create(Self); Result.Parent := Self; Result.Caption := Caption;
    Result.AutoSize := False; Result.SetBounds(0,Y,330,22); Result.Anchors := [akLeft,akTop,akRight];
  end;
  procedure CopyButton(const Name,Caption: string; Tag,Y: Integer);
  begin
    var B := TButton.Create(Self); B.Parent := Self; B.Name := Name; B.Caption := Caption; B.Tag := Tag;
    B.SetBounds(0,Y,330,30); B.Anchors := [akLeft,akTop,akRight]; B.OnClick := CopyText;
  end;
begin
  inherited Create(AOwner); Name := 'MoviePosting'; Caption := ''; BevelOuter := bvNone; Width := 330; Height := 568;
  LabelAt('投稿用タイトル（連番は手動で変更）',0);
  FTitle := TEdit.Create(Self); FTitle.Parent := Self; FTitle.Name := 'MoviePostingTitle'; FTitle.MaxLength := 1000;
  FTitle.SetBounds(0,24,330,28); FTitle.Anchors := [akLeft,akTop,akRight]; FTitle.OnChange := Edited;
  CopyButton('MovieCopyPostingTitle','タイトルをコピー',0,58);
  LabelAt('概要',98);
  FDescription := TMemo.Create(Self); FDescription.Parent := Self; FDescription.Name := 'MoviePostingDescription';
  FDescription.SetBounds(0,122,330,230); FDescription.Anchors := [akLeft,akTop,akRight];
  FDescription.ScrollBars := ssVertical; FDescription.MaxLength := 20000; FDescription.OnChange := Edited;
  CopyButton('MovieCopyPostingDescription','概要をコピー',1,358);
  var B := TButton.Create(Self); B.Parent := Self; B.Name := 'MoviePostingUseWork'; B.Caption := '確認した作品情報を概要へ追加';
  B.SetBounds(0,394,330,30); B.Anchors := [akLeft,akTop,akRight]; B.OnClick := UseWork;
  LabelAt('親作品登録（固定）',434);
  FParents := TEdit.Create(Self); FParents.Parent := Self; FParents.Name := 'MoviePostingParents'; FParents.ReadOnly := True;
  FParents.SetBounds(0,458,330,28); FParents.Anchors := [akLeft,akTop,akRight]; FParents.Text := MovieParentWorks;
  CopyButton('MovieCopyPostingParents','親作品をコピー',2,492);
  FGuide := LabelAt('入力は作品に反映され、作品保存時に保存します。',530);
  FGuide.Height := 38; FGuide.WordWrap := True;
end;
procedure TRigmMoviePostingFrame.Bind(Session: TRigmMovieSession; OnEdited: TNotifyEvent);
begin FSession := Session; FOnEdited := OnEdited; RefreshState; end;
procedure TRigmMoviePostingFrame.RefreshState;
begin
  if FSession=nil then Exit;
  if FUnapplied and (FProjectId=FSession.Project.Id) then Exit;
  FSync := True;
  var Info := MoviePostingInfo(FSession.Project);
  try
    if FTitle.Text<>JS(Info,'title') then FTitle.Text := JS(Info,'title');
    if FDescription.Text<>JS(Info,'description') then FDescription.Text := JS(Info,'description');
    FProjectId := FSession.Project.Id;
    FRevision := FSession.Project.Revision; FUnapplied := False;
  finally Info.Free; FSync := False; end;
end;
procedure TRigmMoviePostingFrame.Edited(Sender: TObject);
begin
  if FSync or (FSession=nil) or (FProjectId<>FSession.Project.Id) then Exit;
  var Args := TJSONObject.Create;
  try
    FPreviousRevision := FRevision; FUnapplied := True;
    Args.AddPair('projectId',FProjectId); AddN(Args,'revision',FRevision);
    Args.AddPair('title',FTitle.Text); Args.AddPair('description',FDescription.Text);
    var Result := FSession.Execute('update-posting',Args);
    try FRevision := JI(Result,'revision'); finally Result.Free; end; FUnapplied := False;
    FGuide.Caption := '入力を反映しました。作品保存時に保存します。';
    if Assigned(FOnEdited) then FOnEdited(Self);
  except on E: Exception do FGuide.Caption := E.Message; end;
  Args.Free;
end;
procedure TRigmMoviePostingFrame.CopyText(Sender: TObject);
begin
  try
    case TComponent(Sender).Tag of
      0: Clipboard.AsText := FTitle.Text;
      1: Clipboard.AsText := FDescription.Text;
      2: Clipboard.AsText := FParents.Text;
    end;
    FGuide.Caption := 'クリップボードへコピーしました。';
  except on E: Exception do FGuide.Caption := E.Message; end;
end;
procedure TRigmMoviePostingFrame.UseWork(Sender: TObject);
begin
  if FSession=nil then Exit;
  var Text := MoviePostingDescription(FSession.Project);
  if Text='' then begin FGuide.Caption := '第6段階で作品情報を取得し、作品を確認してください。'; Exit; end;
  if Pos(Text,FDescription.Text)>0 then begin FGuide.Caption := 'この作品情報は概要へ追加済みです。'; Exit; end;
  if Trim(FDescription.Text)='' then FDescription.Text := Text
  else FDescription.Text := TrimRight(FDescription.Text)+#13#10+#13#10+Text;
end;
end.
