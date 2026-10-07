unit RigmScriptManagerFrame;
interface
uses System.Classes, RigmScriptPageFrame, Vcl.Forms, Vcl.ComCtrls, Vcl.StdCtrls, RigmWizardWorkspace, RigmPageNavigation;
function ScriptUpdatedAtLocal(const Value: string): string;
type
  TRigmScriptManagerFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FRoot: string; FList: TListView; FStatus: TLabel; FOnNavigate: TRigmNavigateEvent;
    FCreating: Boolean;
    procedure OpenWork(Sender: TObject);
    procedure NewWork(Sender: TObject);
    procedure ChooseWork(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
    procedure RefreshLibrary;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.SysUtils, System.JSON, System.DateUtils, Vcl.Controls, Vcl.Dialogs, RigmJson, RigmIconToolbar, RigmToolbarIcons;
{$R *.dfm}
function ScriptUpdatedAtLocal(const Value: string): string;
begin
  if Value='' then Exit('');
  var Stamp: TDateTime;
  if not TryISO8601ToDate(Value,Stamp,True) then Exit('日時不明');
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss',TTimeZone.Local.ToLocalTime(Stamp));
end;
constructor TRigmScriptManagerFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace; const Root: string);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; FRoot := Root;
  var Toolbar := TRigmIconToolbar.Create(Self); Toolbar.Parent := Self; Toolbar.Align := alTop; Toolbar.Name := 'ScriptLibraryToolbar';
  Toolbar.AddIcon('ScriptNew','台本を新規作成',riNew,0,NewWork);
  Toolbar.AddIcon('ScriptResume','選択した台本・従来作品を再開',riOpen,0,OpenWork);
  Toolbar.AddSeparator; Toolbar.AddIcon('ScriptOpenLegacy','従来の作品ファイルを開く',riReference,0,ChooseWork);
  Toolbar.AddIcon('ScriptRefresh','一覧を更新',riRefresh,0,RefreshClick);
  FStatus := TRigmScriptLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := ScaleValue(42);
  FStatus.AutoSize := False; FStatus.WordWrap := True; FStatus.Name := 'ScriptLibraryStatus';
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport;
  FList.RowSelect := True; FList.ReadOnly := True; FList.Name := 'ScriptLibrary'; FList.HideSelection := False;
  FList.Columns.Add.Caption := '題名'; FList.Columns[0].Width := ScaleValue(480);
  FList.Columns.Add.Caption := '工程'; FList.Columns[1].Width := ScaleValue(170);
  FList.Columns.Add.Caption := '更新日時（PCの時刻）';
  if TTimeZone.Local.GetUtcOffset(Now).TotalMinutes=540 then FList.Columns[2].Caption := '更新日時（日本時間）';
  FList.Columns[2].Width := ScaleValue(220);
  FList.Columns.Add.Caption := '識別'; FList.Columns[3].Width := ScaleValue(100); FList.OnDblClick := OpenWork;
  RefreshLibrary;
end;
procedure TRigmScriptManagerFrame.RefreshLibrary;
begin
  var SelectedPath := ''; if FList.Selected<>nil then SelectedPath := FList.Selected.SubItems[3];
  if (FWorkspace.ScriptDraft<>nil) and (FWorkspace.ScriptDraft.FileName<>'') then SelectedPath := FWorkspace.ScriptDraft.FileName;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear; var Offset := 0; var Total: Integer;
    repeat
      var Listing := FWorkspace.ScriptLibrary(Offset,100);
      try
        Total := JI(Listing,'total');
        for var V in JA(Listing,'scripts') do begin
          var Entry := TJSONObject(V); var Item := FList.Items.Add; Item.Caption := JS(Entry,'title');
          var Stage := '従来作品（動画編集）';
          if JS(Entry,'kind')='wizard' then begin
            Stage := '題名：入力中'; if JS(Entry,'state')='complete' then Stage := '題名：確認済み';
            if JS(Entry,'stage')='characters' then begin
              Stage := 'キャラ：選択中'; if JS(Entry,'state')='complete' then Stage := 'キャラ：確認済み';
            end;
            if JS(Entry,'stage')='layout' then begin
              Stage := 'レイアウト：選択中'; if JS(Entry,'state')='complete' then Stage := 'レイアウト：確認済み';
            end;
            if JS(Entry,'stage')='placement' then Stage := 'キャラ配置：調整中';
            if JS(Entry,'stage')='text' then Stage := '台本入力：編集中';
            if JS(Entry,'stage')='closing' then Stage := '締め：設定中';
            if JS(Entry,'stage')='editor' then Stage := '動画編集';
          end else if JS(Entry,'kind')='unreadable' then Stage := '読込不可';
          Item.SubItems.Add(Stage); Item.SubItems.Add(ScriptUpdatedAtLocal(JS(Entry,'updatedAt')));
          Item.SubItems.Add(Copy(JS(Entry,'projectId').Replace('{','').Replace('}',''),1,8));
          Item.SubItems.Add(JS(Entry,'path')); Item.SubItems.Add(JS(Entry,'kind'));
          if SameText(JS(Entry,'path'),SelectedPath) then Item.Selected := True;
        end;
        Offset := JI(Listing,'nextOffset');
      finally Listing.Free; end;
    until Offset>=Total;
    if (FList.Selected=nil) and (FList.Items.Count>0) then FList.Items[0].Selected := True;
    FStatus.Caption := '新規作成は左端のアイコン。台本はダブルクリックで続けられます。従来作品は動画編集で開きます。';
  except on E: Exception do FStatus.Caption := E.Message;
  end;
  FList.Items.EndUpdate;
end;
procedure TRigmScriptManagerFrame.RefreshClick(Sender: TObject);
begin RefreshLibrary; end;
procedure TRigmScriptManagerFrame.OpenWork(Sender: TObject);
begin
  if FList.Selected=nil then Exit;
  try
    if FList.Selected.SubItems[4]='wizard' then begin
      FWorkspace.OpenWork(FList.Selected.SubItems[3]);
    end else if FList.Selected.SubItems[4]='legacy' then FWorkspace.OpenWork(FList.Selected.SubItems[3])
    else FStatus.Caption := '読込不可のファイルは変更せず保持しています。';
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TRigmScriptManagerFrame.NewWork(Sender: TObject);
begin
  if FCreating then Exit; FCreating := True;
  try
    try FWorkspace.NewScriptDraft; if Assigned(FOnNavigate) then FOnNavigate(Self,apScriptCreate,'');
    except on E: Exception do FStatus.Caption := E.Message; end;
  finally FCreating := False; end;
end;
procedure TRigmScriptManagerFrame.ChooseWork(Sender: TObject);
begin
  var Dialog := TOpenDialog.Create(Self);
  try Dialog.Filter := '従来の台本・動画作品|*.rigmovie'; Dialog.InitialDir := FRoot;
    if Dialog.Execute then try FWorkspace.OpenWork(Dialog.FileName); except on E: Exception do FStatus.Caption := E.Message; end;
  finally Dialog.Free; end;
end;
end.
