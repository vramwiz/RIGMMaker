unit RigmHomeFrame;
interface
uses System.Classes, Vcl.Forms, RigmPageNavigation;
type
  TRigmHomeFrame = class(TFrame)
  private
    FOnNavigate: TRigmNavigateEvent;
    procedure Navigate(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses Vcl.Controls, Vcl.StdCtrls;
{$R *.dfm}
constructor TRigmHomeFrame.Create(AOwner: TComponent);
  procedure Entry(const Name,Text: string; Page: TRigmAppPage; Y: Integer);
  begin
    var Button := TButton.Create(Self); Button.Parent := Self; Button.Name := Name;
    Button.SetBounds(48,Y,460,58); Button.Caption := Text; Button.Tag := Ord(Page); Button.OnClick := Navigate;
  end;
begin
  inherited; Align := alClient;
  // Parent接続前に96 DPIで構築する。フォントの継承時も基準DPIを保持する。
  ParentFont := False; Font.PixelsPerInch := 96; Font.IsDPIRelated := True;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  var Title := TLabel.Create(Self); Title.Parent := Self; Title.SetBounds(48,38,740,36);
  Title.Name := 'HomeTitle'; Title.Font.Size := 22; Title.Caption := '作業を選んでください';
  Entry('HomeCharacters','キャラ管理・PSD制作',apCharacters,114);
  Entry('HomeScripts','台本・作品管理',apScripts,194);
  Entry('HomeMovie','動画編集',apMovieEdit,274);
  var Note := TLabel.Create(Self); Note.Parent := Self; Note.Name := 'HomeNote'; Note.AutoSize := False; Note.SetBounds(48,370,930,130); Note.WordWrap := True;
  Note.Caption := 'キャラの登録・編集と、既存の台本・動画制作を選んでください。'+#13#10+
    '作品を保存すると台本・作品管理から再開できます。'+#13#10+
    'ページは初回選択時に作り、戻った後も編集中の状態を保持します。';
end;
procedure TRigmHomeFrame.Navigate(Sender: TObject);
begin if Assigned(FOnNavigate) then FOnNavigate(Self,TRigmAppPage(TButton(Sender).Tag),''); end;
end.
