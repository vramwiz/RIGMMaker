unit RigmCharacterManagerFrame;
interface
uses System.Classes, Vcl.Forms, Vcl.ComCtrls, Vcl.StdCtrls, PsdWorkspace, RigmPageNavigation;
type
  TRigmCharacterManagerFrame = class(TFrame)
  private
    FWorkspace: TPsdWorkspace;
    FList: TListView; FStatus: TLabel; FOnNavigate: TRigmNavigateEvent;
    procedure OpenSelected(Sender: TObject);
    procedure NewCharacter(Sender: TObject);
  public
    constructor CreateForRoot(AOwner: TComponent; const Root: string);
    destructor Destroy; override;
    procedure RefreshLibrary(Sender: TObject);
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.SysUtils, System.IOUtils, Vcl.Controls, Vcl.ExtCtrls, PsdCharacter, PsdPackage;
{$R *.dfm}
constructor TRigmCharacterManagerFrame.CreateForRoot(AOwner: TComponent; const Root: string);
begin
  inherited Create(AOwner); Align := alClient;
  FWorkspace := TPsdWorkspace.Create(Root); FWorkspace.Initialize;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 42; Header.BevelOuter := bvNone;
  var Open := TButton.Create(Self); Open.Parent := Header; Open.Align := alLeft; Open.Width := 180; Open.Caption := '選択キャラを編集'; Open.Name := 'CharacterOpen'; Open.OnClick := OpenSelected;
  var New := TButton.Create(Self); New.Parent := Header; New.Align := alLeft; New.Width := 240; New.Caption := 'PSD素材を登録・制作'; New.Name := 'CharacterNew'; New.OnClick := NewCharacter;
  var Reload := TButton.Create(Self); Reload.Parent := Header; Reload.Align := alLeft; Reload.Width := 140; Reload.Caption := '一覧を更新'; Reload.OnClick := RefreshLibrary;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 76; FStatus.WordWrap := True;
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsReport; FList.ReadOnly := True; FList.RowSelect := True; FList.Name := 'CharacterLibrary';
  FList.Columns.Add.Caption := 'キャラ名'; FList.Columns[0].Width := 480;
  FList.Columns.Add.Caption := '形式'; FList.Columns[1].Width := 90;
  FList.Columns.Add.Caption := '保存先'; FList.Columns[2].Width := 680; FList.OnDblClick := OpenSelected;
  RefreshLibrary(Self);
end;
destructor TRigmCharacterManagerFrame.Destroy;
begin FWorkspace.Free; inherited; end;
procedure TRigmCharacterManagerFrame.RefreshLibrary(Sender: TObject);
begin
  var SelectedPath := ''; if FList.Selected<>nil then SelectedPath := FList.Selected.SubItems[1];
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for var Path in TDirectory.GetFiles(FWorkspace.Resolve('Characters',False),'*.psdchar',TSearchOption.soAllDirectories) do begin
      var Item := FList.Items.Add; Item.Caption := TPath.GetFileNameWithoutExtension(Path); Item.SubItems.Add('PSD'); Item.SubItems.Add(Path);
      var C: TPsdCharacter := nil;
      try
        try C := LoadCharacter(FWorkspace,Path); Item.Caption := C.Name; if C.SupplementName<>'' then Item.Caption := Item.Caption+' / '+C.SupplementName;
        except on E: Exception do Item.Caption := Item.Caption+'（読込不可）'; end;
      finally C.Free; end;
      if SameText(Path,SelectedPath) then Item.Selected := True;
    end;
    var RigmRoot := FWorkspace.Resolve('RIGM',False);
    if DirectoryExists(RigmRoot) then for var Path in TDirectory.GetFiles(RigmRoot,'*.rigm') do begin
      var Item := FList.Items.Add; Item.Caption := TPath.GetFileNameWithoutExtension(Path); Item.SubItems.Add('RIGM'); Item.SubItems.Add(Path);
      if SameText(Path,SelectedPath) then Item.Selected := True;
    end;
    if (FList.Selected=nil) and (FList.Items.Count>0) then FList.Items[0].Selected := True;
    FStatus.Caption := FList.Items.Count.ToString+'件。PSDは未完成でも編集できます。台本への新規追加は別途必須仕様の検査が必要です。'+#13#10+
      'RIGM / Live2D編集の新シェル移行は未完了です。既存ファイルは通常版で利用できます。';
  finally FList.Items.EndUpdate; end;
end;
procedure TRigmCharacterManagerFrame.OpenSelected(Sender: TObject);
begin
  if FList.Selected=nil then Exit;
  if FList.Selected.SubItems[0]<>'PSD' then begin FStatus.Caption := 'RIGM / Live2D編集は新シェルへの移行待ちです。通常版を利用してください。'; Exit; end;
  if Assigned(FOnNavigate) then FOnNavigate(Self,apCharacterEdit,FList.Selected.SubItems[1]);
end;
procedure TRigmCharacterManagerFrame.NewCharacter(Sender: TObject);
begin if Assigned(FOnNavigate) then FOnNavigate(Self,apCharacterEdit,''); end;
end.
