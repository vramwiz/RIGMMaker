unit RigmPendingFrame;
interface
uses System.Classes, Vcl.Forms, RigmPageNavigation;
type
  TRigmPendingFrame = class(TFrame)
  private
    FOnNavigate: TRigmNavigateEvent;
    procedure Navigate(Sender: TObject);
  public
    constructor CreateForPage(AOwner: TComponent; Page: TRigmAppPage);
    property OnNavigate: TRigmNavigateEvent read FOnNavigate write FOnNavigate;
  end;
implementation
uses System.SysUtils, Vcl.Controls, Vcl.StdCtrls;
{$R *.dfm}
constructor TRigmPendingFrame.CreateForPage(AOwner: TComponent; Page: TRigmAppPage);
begin
  inherited Create(AOwner); Name := 'PendingPage'+IntToStr(Ord(Page)); Align := alClient;
  var Title := TLabel.Create(Self); Title.Parent := Self; Title.SetBounds(48,48,1000,36); Title.Font.Size := 20; Title.Caption := RigmPageTitle(Page)+'：新シェルへの移行は未実装';
  var Note := TLabel.Create(Self); Note.Parent := Self; Note.SetBounds(48,112,920,90); Note.WordWrap := True;
  Note.Caption := 'このページは導線の確認用です。既存の制作・保存・動画機能はまだ組み込んでいません。'+#13#10+'通常版と作品ファイルは保持しています。';
  var Next: TRigmAppPage;
  if Page=apScripts then Next := apScriptCreate else if Page=apScriptCreate then Next := apMovieEdit else Next := apHome;
  var Button := TButton.Create(Self); Button.Parent := Self; Button.SetBounds(48,230,460,48); Button.Caption := '導線確認：'+RigmPageTitle(Next)+'へ'; Button.Tag := Ord(Next); Button.Name := 'PendingNext'; Button.OnClick := Navigate;
end;
procedure TRigmPendingFrame.Navigate(Sender: TObject);
begin if Assigned(FOnNavigate) then FOnNavigate(Self,TRigmAppPage(TButton(Sender).Tag),''); end;
end.
