unit RigmCharacterManagerFrame;
interface
uses System.Classes, System.Types, System.Generics.Collections, Vcl.Controls, Vcl.Forms, Vcl.ComCtrls, Vcl.StdCtrls,
  System.JSON, Vcl.Graphics, Vcl.ImgList, PsdWorkspace, RigmPageNavigation, RigmWizardWorkspace, Winapi.Messages,
  RigmThumbnailCache, RigmThumbnailList;
type
  TRigmLibraryThumbnail = class
  public
    Bitmap: TBitmap; Name,ProductionState: string; FileSize: Int64; Modified: TDateTime;
    destructor Destroy; override;
  end;
  TRigmCharacterManagerFrame = class(TFrame,IRigmPageLifecycle)
  private
    FWorkspace: TPsdWorkspace;
    FRegistration: TRigmWizardWorkspace;
    FList: TListView; FStatus: TLabel; FOnNavigate: TRigmNavigateEvent;
    FImages: TImageList; FThumbnails: TRigmThumbnailCache; FOwnThumbnails: Boolean; FLoader: TRigmThumbnailList;
    function ThumbnailPath(Item: TListItem): string;
    procedure ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
    procedure OpenSelected(Sender: TObject);
    procedure NewCharacter(Sender: TObject);
    procedure WMDropFiles(var Message: TWMDropFiles); message WM_DROPFILES;
    procedure SelectPath(const Path: string);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor CreateForRoot(AOwner: TComponent; const Root: string; Registration: TRigmWizardWorkspace = nil);
    destructor Destroy; override;
    procedure RefreshLibrary(Sender: TObject);
    procedure RegisterDroppedFile(const Path: string);
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.SysUtils, System.IOUtils, System.Math, Vcl.ExtCtrls,
  RigmCharacterCatalog, Winapi.CommCtrl, Winapi.ShellAPI, PsdImport, PsdPackage, PsdJson;
{$R *.dfm}
destructor TRigmLibraryThumbnail.Destroy;
begin Bitmap.Free; inherited; end;
function TRigmCharacterManagerFrame.ThumbnailPath(Item: TListItem): string;
begin Result := Item.SubItems[1]; end;
procedure TRigmCharacterManagerFrame.ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
begin
  var Name := S(Metadata,'name'); if Name='' then Name := TPath.GetFileNameWithoutExtension(ThumbnailPath(Item));
  var LabelText := CharacterFormatLabel(ThumbnailPath(Item));
  if S(Metadata,'productionState')<>'' then LabelText := LabelText+' / '+S(Metadata,'productionState');
  Item.Caption := '['+LabelText+'] '+Name;
end;
constructor TRigmCharacterManagerFrame.CreateForRoot(AOwner: TComponent; const Root: string; Registration: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; DoubleBuffered := True;
  FRegistration := Registration;
  FOwnThumbnails := Registration=nil; if FOwnThumbnails then FThumbnails := TRigmThumbnailCache.Create(Root) else FThumbnails := Registration.Thumbnails;
  FWorkspace := TPsdWorkspace.Create(Root); FWorkspace.Initialize;
  var Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 42; Header.BevelOuter := bvNone;
  var New := TButton.Create(Self); New.Parent := Header; New.Align := alLeft; New.Width := 160; New.Caption := '新規作成'; New.Name := 'CharacterNew'; New.OnClick := NewCharacter;
  var Reload := TButton.Create(Self); Reload.Parent := Header; Reload.Align := alLeft; Reload.Width := 140; Reload.Caption := '一覧を更新'; Reload.OnClick := RefreshLibrary;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 76; FStatus.WordWrap := True;
  FStatus.Name := 'CharacterLibraryStatus';
  FImages := TImageList.Create(Self); FImages.ColorDepth := cd32Bit; FImages.Width := ScaleValue(144); FImages.Height := ScaleValue(176);
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alClient; FList.ViewStyle := vsIcon; FList.ReadOnly := True; FList.HideSelection := False; FList.Name := 'CharacterLibrary';
  FList.LargeImages := FImages; FList.DoubleBuffered := True; FList.IconOptions.AutoArrange := True;
  FList.Columns.Add.Caption := 'キャラ名'; FList.Columns[0].Width := 480;
  FList.Columns.Add.Caption := '形式'; FList.Columns[1].Width := 90;
  FList.Columns.Add.Caption := '保存先'; FList.Columns[2].Width := 680; FList.OnDblClick := OpenSelected;
  ListView_SetIconSpacing(FList.Handle,ScaleValue(220),ScaleValue(255));
  FLoader := TRigmThumbnailList.CreateForList(Self,FThumbnails,FList,FImages); FLoader.OnPath := ThumbnailPath; FLoader.OnApplied := ThumbnailApplied;
  RefreshLibrary(Self);
end;
destructor TRigmCharacterManagerFrame.Destroy;
begin FLoader.Free; if FOwnThumbnails then FThumbnails.Free; FWorkspace.Free; inherited; end;
procedure TRigmCharacterManagerFrame.RefreshLibrary(Sender: TObject);
  procedure Add(const Path: string);
  begin
    var Item := FList.Items.Add; Item.Caption := '['+CharacterFormatLabel(Path)+'] '+TPath.GetFileNameWithoutExtension(Path);
    Item.SubItems.Add(CharacterFormatLabel(Path)); Item.SubItems.Add(Path);
    Item.ImageIndex := -1; Item.Caption := Item.Caption+'（準備中）';
  end;
begin
  var SelectedPath := ''; if FList.Selected<>nil then SelectedPath := FList.Selected.SubItems[1];
  FList.Items.BeginUpdate;
  try
    FLoader.Reset; FList.Items.Clear;
    if FRegistration<>nil then begin
      var Catalog := FRegistration.ScriptCharacterLibrary(False);
      try for var V in Arr(Catalog,'characters') do Add(FWorkspace.Resolve(S(TJSONObject(V),'path')));
      finally Catalog.Free; end;
    end else begin
      for var Path in TDirectory.GetFiles(FWorkspace.Resolve('Characters',False),'*.psdchar',TSearchOption.soAllDirectories) do Add(Path);
      var RigmRoot := FWorkspace.Resolve('RIGM',False);
      if DirectoryExists(RigmRoot) then for var Path in TDirectory.GetFiles(RigmRoot,'*.rigm') do Add(Path);
    end;
    for var Item in FList.Items do if SameText(Item.SubItems[1],SelectedPath) then Item.Selected := True;
    if (FList.Selected=nil) and (FList.Items.Count>0) then FList.Items[0].Selected := True;
    FStatus.Caption := FList.Items.Count.ToString+'件。新規作成で追加し、ダブルクリックで編集します。'+#13#10+
      'PSD・PSDキャラ（.psdchar）・RIGMをここへドロップして登録できます。重複は追加しません。未完成キャラは台本へ追加できません。';
  finally FList.Items.EndUpdate; end;
  FLoader.Refresh;
end;
procedure TRigmCharacterManagerFrame.OpenSelected(Sender: TObject);
begin
  if FList.Selected=nil then Exit;
  if Assigned(FOnNavigate) then try
    FOnNavigate(Self,apCharacterEdit,FList.Selected.SubItems[1]);
  except on E: Exception do begin
    FOnNavigate(Self,apCharacters,''); FStatus.Caption := 'キャラを開けませんでした: '+E.Message;
  end; end;
end;
procedure TRigmCharacterManagerFrame.SetActive(Value: Boolean);
begin if Value then FLoader.Refresh; end;
function TRigmCharacterManagerFrame.RequestFinish: Boolean;
begin Result := True; end;
procedure TRigmCharacterManagerFrame.NewCharacter(Sender: TObject);
begin
  try
    var C := CreateDraftCharacter('新規キャラ','');
    var Path: string;
    try
      Path := FWorkspace.Resolve('Characters\'+C.Id+'\character.psdchar',False);
      SaveCharacter(C,FWorkspace,Path);
    finally C.Free; end;
    RefreshLibrary(Self);
    SelectPath(Path);
    FStatus.Caption := '未完成の新規キャラを保存しました。ダブルクリックしてレイヤー画面で素材を登録してください。'+#13#10+Path;
  except on E: Exception do FStatus.Caption := '新規作成できませんでした: '+E.Message; end;
end;
procedure TRigmCharacterManagerFrame.SelectPath(const Path: string);
begin
  for var Item in FList.Items do if SameText(Item.SubItems[1],Path) then begin
    FList.Selected := Item; Item.Focused := True; Item.MakeVisible(False); Exit;
  end;
end;
procedure TRigmCharacterManagerFrame.CreateWnd;
begin inherited; DragAcceptFiles(Handle,True); end;
procedure TRigmCharacterManagerFrame.DestroyWnd;
begin DragAcceptFiles(Handle,False); inherited; end;
procedure TRigmCharacterManagerFrame.WMDropFiles(var Message: TWMDropFiles);
begin
  try
    var Count := DragQueryFile(Message.Drop,$FFFFFFFF,nil,0);
    if (Count=0) or (Count>1000) then Exit;
    for var Index: Cardinal := 0 to Count-1 do begin
      var Size := DragQueryFile(Message.Drop,Index,nil,0); var Path: string; SetLength(Path,Size+1);
      DragQueryFile(Message.Drop,Index,PChar(Path),Size+1); SetLength(Path,Size); RegisterDroppedFile(Path);
    end;
  finally DragFinish(Message.Drop); end;
  Message.Result := 0;
end;
procedure TRigmCharacterManagerFrame.RegisterDroppedFile(const Path: string);
begin
  try
    if FRegistration=nil then raise Exception.Create('登録先が準備されていません。');
    var R := FRegistration.RegisterDroppedCharacter(Path);
    try
    RefreshLibrary(Self); SelectPath(S(R,'path'));
      if B(R,'duplicate') then FStatus.Caption := '登録済みのキャラを選択しました。重複したファイルは追加していません。'
      else FStatus.Caption := 'キャラを登録しました。ダブルクリックで編集できます。';
    finally R.Free; end;
  except on E: Exception do FStatus.Caption := '登録できませんでした: '+E.Message; end;
end;
end.
