unit RigmPageNavigation;
interface
type
  TRigmAppPage = (apHome,apCharacters,apCharacterEdit,apScripts,apScriptCreate,apMovieEdit);
  TRigmNavigateEvent = procedure(Sender: TObject; Page: TRigmAppPage; const Path: string) of object;
function RigmPageTitle(Page: TRigmAppPage): string;
implementation
function RigmPageTitle(Page: TRigmAppPage): string;
const Titles: array[TRigmAppPage] of string = ('ホーム','キャラ管理','キャラ制作・編集','台本管理','台本作成','動画編集');
begin Result := Titles[Page]; end;
end.
