unit RIGMMakerMainForm;

interface
uses System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.ImgList, Vcl.Graphics, Vcl.Menus,
  RigmIconToolbar, RigmMovieSession, RigmMovieForm, RigmMovieCreator, RigmEditorForm, System.JSON;

type
  TRigmLibraryEntry = class
  public
    Name, FileName, RenderFormat: string;
    Sample: Boolean;
  end;
  TRigmWorkspaceDocument = class
    Session: TRigmMovieSession;
    View: TRigmMovieForm;
    destructor Destroy; override;
  end;
  TMainForm = class(TForm)
  private
    FEntries: TObjectList<TRigmLibraryEntry>;
    FList: TListView;
    FImages: TImageList;
    FDirectory: string;
    FStatus: TLabel;
    FToolbar: TRigmIconToolbar;
    FHeader: TPanel;
    FTitle, FDescription, FGuide: TLabel;
    FRecent: TListView;
    FRecentTimer: TTimer;
    FRecentKey: string;
    FResume: TButton;
    FDocuments: TObjectList<TRigmWorkspaceDocument>;
    FActiveDocument: TRigmWorkspaceDocument;
    FHost: TRigmEditorForm;
    FPreviewPage,FCharacterPage,FCreatePage: TPanel;
    FCreation: TRigmMovieCreator;
    FPagebar: TRigmIconToolbar;
    FDocumentList: TComboBox;
    FWorkspacePage: string;
    FBuildingUI,FInLayout: Boolean;
    FMainMenu: TMainMenu;
    FRecentMenu,FRecoveryMenu: TMenuItem;
    procedure BuildMenu;
    procedure MovieMenuClick(Sender: TObject);
    procedure RecentMenuClick(Sender: TObject);
    procedure BuildWorkspace;
    procedure WorkspacePageClick(Sender: TObject);
    procedure DocumentSelection(Sender: TObject);
    procedure RequestMoviePage(Sender: TObject);
    function ActiveSession: TRigmMovieSession;
    function NewMovieDocument: TRigmWorkspaceDocument;
    procedure OpenMovieDocument(const Path: string);
    procedure RefreshRecent(Sender: TObject);
    procedure ResumeRecent(Sender: TObject);
    procedure RecentSelection(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure LayoutText;
    procedure LibrarySelection(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure BuildUI;
    procedure RefreshLibrary(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure SampleClick(Sender: TObject);
    procedure PsdClick(Sender: TObject);
    procedure CharacterSaved(Sender: TObject);
    procedure MovieClick(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenSeparatedPsdFile(const FileName: string);
    function OpenCharacterEditor(const Path: string): TForm;
    function ExecuteWorkspace(const Command: string; Args: TJSONObject): TJSONObject;
  protected
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  end;

var MainForm: TMainForm;

implementation
uses System.IOUtils, System.Types, System.Math, System.UITypes, Vcl.Dialogs,
  Winapi.Windows, RigmModel, RigmSample, RigmStorage, RigmRenderer, RigmToolbarIcons, RigmAppSettings, RigmJson,
  RigmMovieModel, RigmEditor, System.StrUtils, RigmCharacterCatalog, PsdStudioForm, PsdSession;

{$R *.dfm}

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited;
  FBuildingUI := True;
  var TargetPPI := Monitor.PixelsPerInch;
  ScaleForPPI(96); Font.PixelsPerInch := 96;
  Width := 1120; Height := 760; Constraints.MinWidth := 640; Constraints.MinHeight := 360;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  FEntries := TObjectList<TRigmLibraryEntry>.Create(True);
  FDirectory := TPath.Combine(RigmDocumentsDirectory, 'RIGM');
  for var I := 1 to ParamCount do begin
    if ParamStr(I).StartsWith('--data-dir=') then FDirectory := ExpandFileName(ParamStr(I).Substring(11));
    if (ParamStr(I) = '--data-dir') and (I < ParamCount) then FDirectory := ExpandFileName(ParamStr(I + 1));
  end;
  BuildUI; BuildWorkspace; ScaleForPPI(TargetPPI); FBuildingUI := False; LayoutText;
  OnCloseQuery := Closing; RefreshLibrary(Self); RefreshRecent(Self);
end;

destructor TRigmWorkspaceDocument.Destroy;
begin View.Free; Session.Free; inherited; end;
destructor TMainForm.Destroy;
begin
  FBuildingUI := True;
  if FRecentTimer<>nil then FRecentTimer.Enabled := False;
  if FCreation<>nil then FCreation.Bind(nil,nil);
  if FHost<>nil then begin FHost.Editor.OnGetMovie := nil; FHost.Free; FHost := nil; end;
  FDocuments.Free; FEntries.Free; inherited;
end;

procedure TMainForm.BuildWorkspace;
begin
  FDocuments := TObjectList<TRigmWorkspaceDocument>.Create(True);
  FCharacterPage := TPanel.Create(Self); FCharacterPage.Parent := Self; FCharacterPage.Align := alClient; FCharacterPage.BevelOuter := bvNone;
  FCharacterPage.Name := 'CharacterWorkspacePage';
  for var I := ControlCount-1 downto 0 do if Controls[I]<>FCharacterPage then Controls[I].Parent := FCharacterPage;
  FPreviewPage := TPanel.Create(Self); FPreviewPage.Parent := Self; FPreviewPage.Align := alClient; FPreviewPage.BevelOuter := bvNone;
  FPreviewPage.Name := 'PreviewWorkspacePage';
  var History := TPanel(FRecent.Parent); History.Visible := False;
  FCreatePage := TPanel.Create(Self); FCreatePage.Parent := Self; FCreatePage.Align := alClient; FCreatePage.BevelOuter := bvNone;
  FCreatePage.Name := 'CreationWorkspacePage';
  FCreation := TRigmMovieCreator.CreateForWorkspace(Self,FDirectory); FCreation.Parent := FCreatePage; FCreation.Align := alClient;
  var Bar := TPanel.Create(Self); Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 48; Bar.BevelOuter := bvNone;
  Bar.Name := 'WorkspaceHeader'; Bar.Caption := '';
  FDocumentList := TComboBox.Create(Self); FDocumentList.Parent := Bar; FDocumentList.Align := alRight; FDocumentList.Width := 310;
  FDocumentList.Name := 'WorkspaceDocuments'; FDocumentList.Style := csDropDownList; FDocumentList.OnChange := DocumentSelection;
  FPagebar := TRigmIconToolbar.Create(Self); FPagebar.Parent := Bar; FPagebar.Align := alClient; FPagebar.Name := 'WorkspaceToolbar';
  FPagebar.AddIcon('WorkspacePreview','動画プレビュー・編集',riPreview,0,WorkspacePageClick,True);
  FPagebar.AddIcon('WorkspaceCreate','台本から動画を作成・配置',riGenerate,1,WorkspacePageClick,True);
  FPagebar.AddIcon('WorkspaceCharacters','キャラクター登録・ライブラリ',riSample,2,WorkspacePageClick,True);
  FPagebar.AddSeparator;
  FPagebar.AddIcon('WorkspaceNewMovie','新しい動画を作成',riNew,3,WorkspacePageClick);
  FPagebar.AddIcon('WorkspaceOpenMovie','動画作品を開く',riOpen,4,WorkspacePageClick);
  TToolButton(FPagebar.FindComponent('WorkspaceNewMovie')).Visible := False;
  TToolButton(FPagebar.FindComponent('WorkspaceOpenMovie')).Visible := False;
  NewMovieDocument;
  BuildMenu;
  FHost := TRigmEditorForm.Create(Self); FHost.Editor.OnGetMovie := ActiveSession;
  FHost.Editor.OnWorkspaceCommand := ExecuteWorkspace; FHost.Editor.OnMovieOpen := RequestMoviePage;
  Caption := 'RIGM Maker — 動画プレビュー・編集'; Width := 1500; Height := 950;
  var A := TJSONObject.Create; try A.AddPair('page','preview'); var R := ExecuteWorkspace('switch-page',A); R.Free; finally A.Free; end;
end;
procedure TMainForm.BuildMenu;
begin
  FMainMenu := TMainMenu.Create(Self); FMainMenu.Name := 'WorkspaceMenu'; Menu := FMainMenu;
  PopulateMovieMenus(FMainMenu,MovieMenuClick);
  var FileMenu := TMenuItem(FindComponent('MovieFileMenu'));
  var NewItem := TMenuItem.Create(Self); NewItem.Name := 'WorkspaceNewMovieMenu'; NewItem.Caption := '新しい作品';
  NewItem.Tag := 100; NewItem.OnClick := MovieMenuClick; NewItem.ShortCut := TextToShortCut('Ctrl+N'); FileMenu.Insert(0,NewItem);
  FRecentMenu := TMenuItem.Create(Self); FRecentMenu.Name := 'RecentWorksMenu'; FRecentMenu.Caption := '最近の作業'; FileMenu.Add(FRecentMenu);
  FRecoveryMenu := TMenuItem.Create(Self); FRecoveryMenu.Name := 'RecoveryWorksMenu'; FRecoveryMenu.Caption := '復旧ファイル'; FileMenu.Add(FRecoveryMenu);
  FileMenu.OnClick := RefreshRecent;
end;
procedure TMainForm.MovieMenuClick(Sender: TObject);
begin
  if TComponent(Sender).Tag=100 then begin NewMovieDocument; RequestMoviePage(Self); Exit; end;
  FActiveDocument.View.InvokeAction(TComponent(Sender).Tag);
end;
procedure TMainForm.RecentMenuClick(Sender: TObject);
begin
  try OpenMovieDocument(TMenuItem(Sender).Hint);
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
function TMainForm.ActiveSession: TRigmMovieSession;
begin Result := FActiveDocument.Session; end;
function TMainForm.NewMovieDocument: TRigmWorkspaceDocument;
begin
  Result := TRigmWorkspaceDocument.Create; Result.Session := TRigmMovieSession.Create;
  try
    Result.View := TRigmMovieForm.CreateForSession(Self,Result.Session,True);
    // Scale the new 96-DPI controls before parenting adopts the already-scaled workspace font.
    Result.View.ScaleForPPI(CurrentPPI);
    Result.View.Parent := FPreviewPage; Result.View.Align := alClient;
    Result.View.OnOpenWork := OpenMovieDocument;
    for var D in FDocuments do D.View.Hide;
    FDocuments.Add(Result); FActiveDocument := Result; Result.View.Show;
    FDocumentList.Items.AddObject(Result.Session.Project.Title,Result); FDocumentList.ItemIndex := FDocumentList.Items.Count-1;
    FCreation.Bind(Result.Session,Result.View);
  except Result.Free; raise; end;
end;
procedure TMainForm.DocumentSelection(Sender: TObject);
begin
  if FDocumentList.ItemIndex<0 then Exit;
  FActiveDocument := TRigmWorkspaceDocument(FDocumentList.Items.Objects[FDocumentList.ItemIndex]);
  for var D in FDocuments do if D=FActiveDocument then D.View.Show else D.View.Hide;
  FCreation.Bind(FActiveDocument.Session,FActiveDocument.View);
end;
procedure TMainForm.OpenMovieDocument(const Path: string);
begin
  // Load before making a new page; failures preserve the current work and drafts.
  var Loaded := LoadMovie(Path);
  try
    var D := NewMovieDocument;
    var A := TJSONObject.Create;
    try A.AddPair('path',Path); A.AddPair('projectId',D.Session.Project.Id); AddN(A,'revision',D.Session.Project.Revision);
      var R := D.Session.Execute('open',A); R.Free;
    finally A.Free; end;
    FCreation.Bind(D.Session,D.View);
    A := TJSONObject.Create; try A.AddPair('page','preview'); var R := ExecuteWorkspace('switch-page',A); R.Free; finally A.Free; end;
    RefreshRecent(Self);
  finally Loaded.Free; end;
end;
procedure TMainForm.RequestMoviePage(Sender: TObject);
begin var A := TJSONObject.Create; try A.AddPair('page','preview'); var R := ExecuteWorkspace('switch-page',A); R.Free; finally A.Free; end; end;
procedure TMainForm.WorkspacePageClick(Sender: TObject);
const Pages: array[0..2] of string = ('preview','create','characters');
begin
  try
    var Tag := TComponent(Sender).Tag;
    if Tag=3 then begin NewMovieDocument; Tag := 1; end;
    if Tag=4 then begin
      var D := TOpenDialog.Create(Self);
      try D.Filter := '動画作品 (*.rigmovie)|*.rigmovie'; D.Options := [ofFileMustExist,ofPathMustExist,ofNoChangeDir,ofEnableSizing];
        if D.Execute then OpenMovieDocument(D.FileName);
      finally D.Free; end; Exit;
    end;
    var A := TJSONObject.Create; try A.AddPair('page',Pages[Tag]); var R := ExecuteWorkspace('switch-page',A); R.Free; finally A.Free; end;
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
function TMainForm.ExecuteWorkspace(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command='switch-page' then begin
    var Page := JS(Args,'page');
    if not MatchText(Page,['preview','create','characters']) then raise ERigm.Create('Unknown workspace page');
    if JS(Args,'propertyPage')<>'' then FActiveDocument.View.SelectPropertyPage(JS(Args,'propertyPage'));
    FWorkspacePage := Page; FPreviewPage.Visible := Page='preview'; FCreatePage.Visible := Page='create'; FCharacterPage.Visible := Page='characters';
    TToolButton(FPagebar.FindComponent('WorkspacePreview')).Down := Page='preview';
    TToolButton(FPagebar.FindComponent('WorkspaceCreate')).Down := Page='create';
    TToolButton(FPagebar.FindComponent('WorkspaceCharacters')).Down := Page='characters';
  end else if Command='open-work' then OpenMovieDocument(JS(Args,'path'))
  else if Command='edit-character' then begin
    var Path := ExpandFileName(JS(Args,'path')); var View := OpenCharacterEditor(Path);
    Result := TJSONObject.Create; Result.AddPair('renderFormat',CharacterFormat(Path)); Result.AddPair('editorClass',View.ClassName); Exit;
  end else if Command='register-character' then begin
    var Path := ExpandFileName(JS(Args,'path')); if not FileExists(Path) then raise ERigm.Create('Character source does not exist');
    if SameText(ExtractFileExt(Path),'.psdchar') or SameText(ExtractFileExt(Path),'.psd') then begin
      var S := TPsdSession.Create(ExtractFileDir(FDirectory),False);
      try
        var Input := S.Workspace.Resolve('Exchange\import-'+NewRigmId.Replace('{','').Replace('}','')+LowerCase(ExtractFileExt(Path)),False);
        TFile.Copy(Path,Input,False); // 入力原本を保持し、専用ルート内のファイル参照で読み込む。
        var A := TJSONObject.Create;
        try A.AddPair('path',Input); var R: TJSONObject;
          if SameText(ExtractFileExt(Path),'.psdchar') then R := S.Command('open',A) else R := S.Command('import-psd',A);
          R.Free;
        finally A.Free; end;
        if JS(Args,'name')<>'' then S.Character.Name := JS(Args,'name');
        var Target := S.Workspace.Resolve('Characters\character-'+NewRigmId.Replace('{','').Replace('}','')+'.psdchar',False);
        A := TJSONObject.Create;
        try A.AddPair('path',Target); var R := S.Command('save',A); R.Free; finally A.Free; end;
        RefreshLibrary(Self); FCreation.RefreshLibrary;
        Result := TJSONObject.Create; Result.AddPair('path',Target); Result.AddPair('name',S.Character.Name); Result.AddPair('renderFormat','psd'); Exit;
      finally S.Free; end;
    end;
    var E := RigmEditor.TRigmEditor.Create;
    try
      if SameText(ExtractFileExt(Path),'.rigm') then E.Open(Path)
      else raise ERigm.Create('Character registration accepts RIGM, PSD character or PSD');
      if JS(Args,'name')<>'' then E.Document.Name := JS(Args,'name');
      var Target := TPath.Combine(FDirectory,'character-'+NewRigmId.Replace('{','').Replace('}','')+'.rigm');
      ForceDirectories(FDirectory); E.Save(Target); RefreshLibrary(Self); FCreation.RefreshLibrary;
      Result := TJSONObject.Create; Result.AddPair('path',Target); Result.AddPair('name',E.Document.Name); Result.AddPair('renderFormat','rigm'); Exit;
    finally E.Free; end;
  end else if Command='library' then begin
    Result := TJSONObject.Create; var A := TJSONArray.Create; Result.AddPair('characters',A);
    for var E in FEntries do begin var O := TJSONObject.Create; O.AddPair('name',E.Name); O.AddPair('path',IfThen(E.Sample,'@sample',E.FileName)); O.AddPair('renderFormat',E.RenderFormat); A.AddElement(O); end; Exit;
  end else if Command<>'status' then raise ERigm.Create('Unknown workspace operation');
  Result := ActiveSession.Status; Result.AddPair('page',FWorkspacePage); AddN(Result,'openDocuments',FDocuments.Count);
  Result.AddPair('propertyPage',FActiveDocument.View.PropertyPageName);
end;

procedure TMainForm.BuildUI;
var Header, Guide: TPanel; Title, Description: TLabel; Button: TToolButton; I: Integer;
const Captions: array[0..5] of string = ('＋ 新規キャラクター', '選択データを編集', 'RIGMファイルを開く', '編集テスト用サンプル', '一覧を更新', '分解済みPSDから開始');
      Names: array[0..5] of string = ('NewCharacterButton', 'OpenEditorButton', 'OpenRigmFileButton', 'OpenSampleButton', 'RefreshLibraryButton', 'OpenSeparatedPsdButton');
      Icons: array[0..5] of TRigmToolbarIcon = (riNew, riEditPreview, riOpen, riSample, riRefresh, riPsd);
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 105; Header.BevelOuter := bvNone;
  FHeader := Header;
  Title := TLabel.Create(Self); FTitle := Title; Title.Name := 'LibraryTitle';
  Title.Parent := Header; Title.Caption := 'RIGM Maker'; Title.Font.PixelsPerInch := 96;
  Title.Font.Size := 24; Title.Font.Style := [fsBold]; Title.AutoSize := True;
  Title.SetBounds(24, 14, 400, 42);
  Description := TLabel.Create(Self); Description.Parent := Header;
  FDescription := Description; Description.Name := 'LibraryDescription';
  Description.AutoSize := False; Description.WordWrap := True;
  Description.Caption := 'キャラクターを選んで編集。PSDの表情・表示、またはLive2D風のボーン・メッシュ'; Description.SetBounds(26, 65, 1000, 24);
  FToolbar := TRigmIconToolbar.Create(Self); FToolbar.Name := 'LibraryToolbar';
  FToolbar.Parent := Self; FToolbar.Align := alTop; FToolbar.Top := Header.Height;
  for I := 0 to 5 do begin
    Button := FToolbar.AddIcon(Names[I], Captions[I], Icons[I], I, nil);
    case I of 0: Button.OnClick := NewClick; 1: Button.OnClick := OpenClick; 2: Button.OnClick := ImportClick;
      3: Button.OnClick := SampleClick; 4: Button.OnClick := RefreshLibrary; 5: Button.OnClick := PsdClick; end;
  end;
  FToolbar.AddIcon('OpenMovieStudioButton','台本から動画を制作',riPreview,6,MovieClick);
  FImages := TImageList.Create(Self); FImages.Width := 128; FImages.Height := 128; FImages.ColorDepth := cd32Bit;
  FList := TListView.Create(Self); FList.Parent := Self; FList.Align := alLeft; FList.Width := 385; FList.Name := 'CharacterLibrary';
  FList.ViewStyle := vsReport; FList.SmallImages := FImages; FList.Columns.Add.Width := 360;
  FList.ShowColumnHeaders := False; FList.ReadOnly := True; FList.HideSelection := False; FList.RowSelect := True;
  FList.OnDblClick := OpenClick;
  FList.OnSelectItem := LibrarySelection;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.Height := 54;
  FStatus.Name := 'LibraryStatus'; FStatus.AutoSize := False;
  FStatus.WordWrap := True; FStatus.Layout := tlCenter;
  Guide := TPanel.Create(Self); Guide.Parent := Self; Guide.Align := alClient; Guide.BevelOuter := bvNone;
  var History := TPanel.Create(Self); History.Parent := Guide; History.Align := alTop; History.Height := 250; History.BevelOuter := bvNone;
  History.Name := 'RecentWorkPanel';
  var Heading := TPanel.Create(Self); Heading.Parent := History; Heading.Align := alTop; Heading.Height := 46; Heading.BevelOuter := bvNone;
  var LabelControl := TLabel.Create(Self); LabelControl.Parent := Heading; LabelControl.Caption := '最近の作業';
  LabelControl.SetBounds(16,12,230,26); LabelControl.Font.Style := [fsBold];
  FResume := TButton.Create(Self); FResume.Parent := Heading; FResume.Name := 'ResumeRecentWork'; FResume.Caption := '選んだ作業を再開';
  FResume.Width := 180; FResume.Align := alRight; FResume.AlignWithMargins := True; FResume.Margins.SetBounds(8,8,16,8); FResume.OnClick := ResumeRecent;
  FRecent := TListView.Create(Self); FRecent.Parent := History; FRecent.Align := alClient; FRecent.Name := 'RecentWorks';
  FRecent.ViewStyle := vsReport; FRecent.ReadOnly := True; FRecent.RowSelect := True; FRecent.HideSelection := False;
  FRecent.Columns.Add.Caption := '作品'; FRecent.Columns[0].Width := 240;
  FRecent.Columns.Add.Caption := '再開位置'; FRecent.Columns[1].Width := 140;
  FRecent.Columns.Add.Caption := '保存先'; FRecent.Columns[2].Width := 360;
  FRecent.OnDblClick := ResumeRecent; FRecent.OnSelectItem := RecentSelection;
  FRecentTimer := TTimer.Create(Self); FRecentTimer.Interval := 1000; FRecentTimer.OnTimer := RefreshRecent;
  var Scroll := TScrollBox.Create(Self); Scroll.Parent := Guide; Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone; Scroll.HorzScrollBar.Visible := False;
  Description := TLabel.Create(Self); FGuide := Description; Description.Parent := Scroll; Description.Align := alTop;
  Description.Name := 'LibraryGuide'; Description.AutoSize := False;
  Description.AlignWithMargins := True; Description.Margins.SetBounds(32, 28, 24, 24);
  Description.WordWrap := True; Description.Font.PixelsPerInch := 96; Description.Font.Size := 12;
  Description.Caption := 'キャラクターを編集する' + sLineBreak + sLineBreak +
    '左の一覧をダブルクリックするか、上の「選択データを編集」で開きます。' + sLineBreak + sLineBreak +
    '1  レイヤー　画像・役割・階層と元画像の再現を確認' + sLineBreak +
    '2  ボーン　親子関係と動かす位置を設定' + sLineBreak +
    '3  メッシュ　頂点・面・ボーンウェイトを調整' + sLineBreak +
    '4  プレビュー　複数パラメータと直接操作で動作を確認' + sLineBreak + sLineBreak +
    '途中でも保存できます。矢印の「工程を自動検証して次へ進む」で進めます。' + sLineBreak +
    '分解済みPSDは「分解済みPSDから開始」で画像生成を省略し、レイヤー分類へ進めます。' + sLineBreak +
    '初めての確認は「編集テスト用サンプル」から開始できます。';
end;

procedure TMainForm.LayoutText;
  function TextHeight(LabelControl: TLabel; Width: Integer): Integer;
  begin
    var R := Rect(0,0,Max(1,Width),0);
    Canvas.Font.Assign(LabelControl.Font);
    DrawText(Canvas.Handle,PChar(LabelControl.Caption),Length(LabelControl.Caption),R,
      DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Result := R.Height;
  end;
begin
  if FBuildingUI or FInLayout or (csDestroying in ComponentState) or (FGuide=nil) then Exit;
  FInLayout := True;
  FList.Width := Min(ScaleValue(385),Max(ScaleValue(180),ClientWidth div 2));
  if FImages.Width<>ScaleValue(128) then begin
    FImages.Width := ScaleValue(128); FImages.Height := FImages.Width;
    if FEntries.Count>0 then RefreshLibrary(Self);
  end;
  DisableAlign;
  try
    FTitle.Left := ScaleValue(24); FTitle.Top := ScaleValue(14);
    FDescription.SetBounds(ScaleValue(26),FTitle.Top+FTitle.Height+ScaleValue(8),
      Max(1,ClientWidth-ScaleValue(52)),ScaleValue(24));
    FDescription.Height := TextHeight(FDescription,FDescription.Width)+ScaleValue(4);
    FHeader.Height := FDescription.Top+FDescription.Height+ScaleValue(12);
    FStatus.Height := TextHeight(FStatus,Max(1,ClientWidth-ScaleValue(12)))+ScaleValue(12);
    FGuide.Height := TextHeight(FGuide,Max(1,FGuide.Parent.ClientWidth-
      FGuide.Margins.Left-FGuide.Margins.Right))+ScaleValue(12);
    // ClientWidth creates the native list handle and can restore its columns.
    // Resolve it before taking the column object, which that restoration replaces.
    var ColumnWidth := Max(1,FList.ClientWidth-ScaleValue(8));
    if FList.Columns.Count>0 then FList.Columns[0].Width := ColumnWidth;
  finally EnableAlign; FInLayout := False; end;
end;

procedure TMainForm.Resize;
begin inherited; LayoutText; end;

procedure TMainForm.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin inherited; LayoutText; end;

procedure TMainForm.LibrarySelection(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if (FToolbar <> nil) and (FList <> nil) then
    TToolButton(FToolbar.FindComponent('OpenEditorButton')).Enabled := FList.Selected <> nil;
end;

procedure TMainForm.RefreshLibrary(Sender: TObject);
  procedure AddEntry(const FileName: string; IsSample: Boolean);
  var Entry: TRigmLibraryEntry; Item: TListItem; Bitmap: Vcl.Graphics.TBitmap; Pixels: TBytes;
      CharacterName: string; W, H, X, Y, P, C, A, OffsetX, OffsetY, Base, TW, TH: Integer;
      Row: PByte; Sample: TRigmDocument;
  begin
    Entry := TRigmLibraryEntry.Create; Entry.FileName := FileName; Entry.Sample := IsSample; Entry.RenderFormat := CharacterFormat(FileName);
    try
      if IsSample then begin
        Sample := TRigmDocument.Create;
        try PopulateRigmSample(Sample); Pixels := RenderRigm(Sample, nil, ScaleValue(120), W, H); CharacterName := '編集テスト用サンプル';
        finally Sample.Free; end;
      end else Pixels := ReadCharacterThumbnail(FileName, CharacterName, W, H);
      Entry.Name := CharacterName; Bitmap := Vcl.Graphics.TBitmap.Create;
      try
        Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(FImages.Width, FImages.Height); Bitmap.Canvas.Brush.Color := $003D3530; Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
        var Scale := Min(ScaleValue(120) / W, ScaleValue(120) / H); TW := Max(1, Round(W * Scale)); TH := Max(1, Round(H * Scale));
        OffsetX := (Bitmap.Width - TW) div 2; OffsetY := (Bitmap.Height - TH) div 2;
        for Y := 0 to TH - 1 do begin
          Row := Bitmap.ScanLine[Y + OffsetY];
          for X := 0 to TW - 1 do begin
            P := (Min(H - 1, Y * H div TH) * W + Min(W - 1, X * W div TW)) * 4; A := Pixels[P + 3]; Base := 61;
            for C := 0 to 2 do Row[(X + OffsetX) * 4 + 2 - C] := (Pixels[P + C] * A + Base * (255 - A)) div 255;
            Row[(X + OffsetX) * 4 + 3] := 255;
          end;
        end;
        Item := FList.Items.Add; Item.ImageIndex := FImages.Add(Bitmap, nil); Item.Caption := '['+CharacterFormatLabel(FileName)+'] '+Entry.Name; Item.Data := Entry;
        if Entry.RenderFormat='psd' then begin
          var Reason: string; if not CharacterReadyForNewScript(FileName,Reason) then Item.Caption := Item.Caption+'（未完成）';
        end;
      finally Bitmap.Free; end;
    except
      on E: Exception do begin Entry.Name := ChangeFileExt(ExtractFileName(FileName), '') + '（読み込み確認が必要）';
        Item := FList.Items.Add; Item.Caption := Entry.Name; Item.Data := Entry;
      end;
    end;
    FEntries.Add(Entry);
  end;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear; FImages.Clear; FEntries.Clear;
    AddEntry('', True);
    var PsdDirectory := TPath.Combine(ExtractFileDir(FDirectory),'Characters');
    if DirectoryExists(PsdDirectory) then for var FileName in TDirectory.GetFiles(PsdDirectory,'*.psdchar',TSearchOption.soAllDirectories) do AddEntry(FileName,False);
    if DirectoryExists(FDirectory) then for var FileName in TDirectory.GetFiles(FDirectory, '*.rigm', TSearchOption.soTopDirectoryOnly) do AddEntry(FileName, False);
    if FList.Items.Count > 0 then FList.Items[0].Selected := True;
    FStatus.Caption := '  保存場所: ' + FDirectory + sLineBreak +
      '  データがなくても「編集テスト用サンプル」から全編集ページを確認できます。サンプルは保存するまでファイルを作成しません。';
  finally FList.Items.EndUpdate; end;
  LayoutText;
end;

procedure TMainForm.NewClick(Sender: TObject);
var CharacterName, FileName: string; Form: TRigmEditorForm;
begin
  CharacterName := '新しいキャラクター'; if not InputQuery('新規キャラクター', 'キャラクター名', CharacterName) then Exit;
  if Trim(CharacterName) = '' then Exit;
  try
    ForceDirectories(FDirectory); FileName := TPath.Combine(FDirectory, 'character-' + NewRigmId.Replace('{', '').Replace('}', '') + '.rigm');
    Form := TRigmEditorForm.Create(Self);
    try Form.NewCharacter(CharacterName, FileName); Form.OnSaved := RefreshLibrary; Form.Show;
    except Form.Free; raise; end;
    RefreshLibrary(Self);
  except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
end;

procedure TMainForm.SampleClick(Sender: TObject);
var Form: TRigmEditorForm;
begin
  Form := TRigmEditorForm.Create(Self);
  try Form.OpenSample; Form.OnSaved := RefreshLibrary; Form.Show;
  except on E: Exception do begin Form.Free; MessageDlg(E.Message, mtError, [mbOK], 0); end; end;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var Entry: TRigmLibraryEntry;
begin
  if FList.Selected = nil then begin MessageDlg('キャラクターを選択してください。', mtInformation, [mbOK], 0); Exit; end;
  Entry := TRigmLibraryEntry(FList.Selected.Data); if Entry.Sample then begin SampleClick(Sender); Exit; end;
  try OpenCharacterEditor(Entry.FileName);
  except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
end;
function TMainForm.OpenCharacterEditor(const Path: string): TForm;
begin
  if CharacterFormat(Path)='psd' then begin
    for var Index := 0 to ComponentCount-1 do if Components[Index] is TPsdStudioForm then begin
      var Existing := TPsdStudioForm(Components[Index]); Existing.ActivateCharacter(Path);
      Existing.Show; Existing.BringToFront; Exit(Existing);
    end;
    var P := TPsdStudioForm.CreateForCharacter(Self,CharacterDataRoot(Path),Path);
    P.OnSaved := CharacterSaved; Result := P;
  end else begin
    var R := TRigmEditorForm.Create(Self);
    try R.OpenFile(Path); R.OnSaved := CharacterSaved; Result := R; except R.Free; raise; end;
  end;
  Result.Show;
end;
procedure TMainForm.CharacterSaved(Sender: TObject);
begin RefreshLibrary(Self); if FCreation<>nil then FCreation.RefreshLibrary; end;

procedure TMainForm.ImportClick(Sender: TObject);
var Dialog: TOpenDialog; Form: TRigmEditorForm;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'RIGM (*.rigm)|*.rigm';
    if Dialog.Execute then begin
      Form := TRigmEditorForm.Create(Self);
      try Form.OpenFile(Dialog.FileName); Form.OnSaved := RefreshLibrary; Form.Show;
      except on E: Exception do begin Form.Free; MessageDlg(E.Message, mtError, [mbOK], 0); end; end;
    end;
  finally Dialog.Free; end;
end;

procedure TMainForm.OpenSeparatedPsdFile(const FileName: string);
begin
  var Root := ExtractFileDir(FDirectory); var Path := ExpandFileName(FileName);
  if not Path.StartsWith(Root+'\',True) then begin
    var Exchange := TPath.Combine(Root,'Exchange'); ForceDirectories(Exchange);
    var CopyPath := TPath.Combine(Exchange,'import-'+NewRigmId.Replace('{','').Replace('}','')+'.psd');
    TFile.Copy(Path,CopyPath,False); Path := CopyPath;
  end;
  var Form := TPsdStudioForm.CreateForCharacter(Self,Root,Path); Form.OnSaved := CharacterSaved; Form.Show;
end;

procedure TMainForm.PsdClick(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := '分解済みPSDから開始（画像生成を省略）';
    Dialog.Filter := 'PSDキャラ (*.psdchar)|*.psdchar|分解済みPhotoshop PSD (*.psd)|*.psd'; Dialog.DefaultExt := 'psdchar';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing, ofNoChangeDir];
    if Dialog.Execute then
      try
        if CharacterFormat(Dialog.FileName)='psd' then OpenCharacterEditor(Dialog.FileName)
        else OpenSeparatedPsdFile(Dialog.FileName);
      except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
  finally Dialog.Free; end;
end;

procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  for var D in FDocuments do begin
    D.View.Close;
    if D.Session.Busy then begin CanClose := False; Exit; end;
  end;
  for var I := ComponentCount - 1 downto 0 do if Components[I] is TRigmEditorForm then begin
    var Form := TRigmEditorForm(Components[I]); if Form=FHost then Continue; Form.Close;
    if Form.Visible then begin CanClose := False; Exit; end;
  end;
  for var I := ComponentCount - 1 downto 0 do if Components[I] is TPsdStudioForm then begin
    var Form := TPsdStudioForm(Components[I]); Form.Close; if Form.Visible then begin CanClose := False; Exit; end;
  end;
end;

procedure TMainForm.RecentSelection(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FResume.Enabled := (FRecent.Selected<>nil) and (FRecent.Selected.SubItems.Count>=2) and FileExists(FRecent.Selected.SubItems[1]);
end;
procedure TMainForm.RefreshRecent(Sender: TObject);
var A: TJSONArray; Selected,Key: string;
begin
  if FDocuments<>nil then for var I := 0 to FDocuments.Count-1 do begin
    var Caption := FDocuments[I].Session.Project.Title;
    if FDocuments[I].Session.Project.Modified then Caption := Caption+' *';
    if FDocumentList.Items[I]<>Caption then FDocumentList.Items[I] := Caption;
  end;
  A := AppSettings.Recent; var Recovery := AppSettings.Recoveries;
  try
    Key := A.ToJSON+'|'+Recovery.ToJSON;
    for var V in A do Key := Key+'|'+BoolToStr(FileExists(JS(TJSONObject(V),'path')),True);
    for var V in Recovery do Key := Key+'|'+BoolToStr(FileExists(JS(TJSONObject(V),'path')),True);
    if FRecentKey=Key then Exit; FRecentKey := Key;
    Selected := ''; if (FRecent.Selected<>nil) and (FRecent.Selected.SubItems.Count>=2) then Selected := FRecent.Selected.SubItems[1];
    FRecent.Items.BeginUpdate;
    try
      FRecent.Items.Clear;
      for var V in A do begin
        var O := TJSONObject(V); var Item := FRecent.Items.Add; Item.Caption := JS(O,'title');
        if not FileExists(JS(O,'path')) then Item.Caption := Item.Caption+'（ファイルなし）';
        Item.SubItems.Add(JS(O,'stage')+Format(' / %.2f 秒',[JN(O,'time')])); Item.SubItems.Add(JS(O,'path'));
        if SameText(Selected,JS(O,'path')) then Item.Selected := True;
      end;
      if (FRecent.Selected=nil) and (FRecent.Items.Count>0) then FRecent.Items[0].Selected := True;
    finally FRecent.Items.EndUpdate; end;
    RecentSelection(Self,nil,False);
    if FRecentMenu<>nil then begin
      FRecentMenu.Clear;
      for var V in A do begin
        var O := TJSONObject(V); var M := TMenuItem.Create(Self);
        M.Caption := StringReplace(JS(O,'title')+'  ['+ExtractFileName(JS(O,'path'))+']','&','&&',[rfReplaceAll]);
        M.Hint := JS(O,'path'); M.Enabled := FileExists(M.Hint); M.OnClick := RecentMenuClick; FRecentMenu.Add(M);
      end;
      FRecentMenu.Enabled := FRecentMenu.Count>0;
      FRecoveryMenu.Clear;
      for var V in Recovery do begin
        var O := TJSONObject(V); var M := TMenuItem.Create(Self);
        M.Caption := StringReplace(JS(O,'title')+'  ['+ExtractFileName(JS(O,'path'))+']','&','&&',[rfReplaceAll]);
        M.Hint := JS(O,'path'); M.Enabled := FileExists(M.Hint); M.OnClick := RecentMenuClick; FRecoveryMenu.Add(M);
      end;
      FRecoveryMenu.Enabled := FRecoveryMenu.Count>0;
    end;
  finally Recovery.Free; A.Free; end;
end;
procedure TMainForm.ResumeRecent(Sender: TObject);
begin
  RecentSelection(Self,nil,False); if not FResume.Enabled then Exit;
  try OpenMovieDocument(FRecent.Selected.SubItems[1]);
  except on E: Exception do FStatus.Caption := '再開できません: '+E.Message; end;
end;
procedure TMainForm.MovieClick(Sender: TObject);
begin
  var A := TJSONObject.Create; try A.AddPair('page','create'); var R := ExecuteWorkspace('switch-page',A); R.Free; finally A.Free; end;
end;

end.
