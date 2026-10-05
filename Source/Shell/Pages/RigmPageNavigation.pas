unit RigmPageNavigation;
interface
type
  TRigmAppPage = (apHome,apCharacters,apCharacterEdit,apScripts,apScriptCreate,apMovieEdit);
  TRigmNavigateEvent = procedure(Sender: TObject; Page: TRigmAppPage; const Path: string) of object;
  IRigmPageLifecycle = interface
    ['{45B4E7DC-407C-4D55-A181-179C1493BBF1}']
    procedure SetActive(Value: Boolean);
    function RequestFinish: Boolean;
  end;
function RigmPageTitle(Page: TRigmAppPage): string;
implementation
function RigmPageTitle(Page: TRigmAppPage): string;
const Titles: array[TRigmAppPage] of string = ('ホーム','キャラ管理','キャラ制作・編集','台本管理','台本作成','動画編集');
begin Result := Titles[Page]; end;
end.
