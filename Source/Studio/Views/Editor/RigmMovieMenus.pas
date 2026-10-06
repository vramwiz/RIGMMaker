// 動画制作のメニュー項目と操作番号を定義する。実行処理は渡されたハンドラーへ委譲する。
unit RigmMovieMenus;
interface
uses System.Classes, Vcl.Menus;
// Menuへ操作項目を追加する。クリックはHandlerへ通知し、作品データは変更しない。
procedure PopulateMovieMenus(Menu: TMenu; Handler: TNotifyEvent);
implementation
uses System.SysUtils;
function CreateMovieMenuGroup(Menu: TMenu; const Name,Caption: string): TMenuItem;
begin Result := TMenuItem.Create(Menu.Owner); Result.Name := Name; Result.Caption := Caption; Menu.Items.Add(Result); end;
procedure AddMovieMenuItem(Menu: TMenu; Parent: TMenuItem; const Caption: string; Action: Integer;
  Handler: TNotifyEvent; const Shortcut: string='');
var M: TMenuItem;
begin
  M := TMenuItem.Create(Menu.Owner); M.Name := 'MovieMenuAction'+Action.ToString;
  M.Caption := Caption; M.Tag := Action; M.OnClick := Handler;
  if Shortcut<>'' then M.ShortCut := TextToShortCut(Shortcut); Parent.Add(M);
end;
procedure PopulateMovieMenus(Menu: TMenu; Handler: TNotifyEvent);
begin
  var FileMenu := CreateMovieMenuGroup(Menu,'MovieFileMenu','ファイル(&F)');
  AddMovieMenuItem(Menu,FileMenu,'作品を開く...',1,Handler,'Ctrl+O'); AddMovieMenuItem(Menu,FileMenu,'保存',2,Handler,'Ctrl+S');
  AddMovieMenuItem(Menu,FileMenu,'名前を付けて保存...',37,Handler,'Ctrl+Shift+S');
  var ExportMenu := TMenuItem.Create(Menu.Owner); ExportMenu.Name := 'MovieExportMenu';
  ExportMenu.Caption := '動画を書き出す'; FileMenu.Add(ExportMenu);
  AddMovieMenuItem(Menu,ExportMenu,'MP4（映像・音声）...',13,Handler,'Ctrl+Shift+E'); AddMovieMenuItem(Menu,ExportMenu,'AVI（映像・音声）...',39,Handler);
  AddMovieMenuItem(Menu,FileMenu,'台本を読み込む...',4,Handler); AddMovieMenuItem(Menu,FileMenu,'RIGMを選択...',3,Handler);
  var EditMenu := CreateMovieMenuGroup(Menu,'MovieEditMenu','編集(&E)'); AddMovieMenuItem(Menu,EditMenu,'元に戻す',5,Handler,'Ctrl+Z'); AddMovieMenuItem(Menu,EditMenu,'やり直す',6,Handler,'Ctrl+Y');
  var ViewMenu := CreateMovieMenuGroup(Menu,'MovieViewMenu','表示(&V)');
  AddMovieMenuItem(Menu,ViewMenu,'台本とセリフ一覧',34,Handler); AddMovieMenuItem(Menu,ViewMenu,'作品・出力設定',35,Handler); AddMovieMenuItem(Menu,ViewMenu,'工程と診断の詳細',38,Handler);
  var MakeMenu := CreateMovieMenuGroup(Menu,'MovieMakeMenu','制作(&P)');
  AddMovieMenuItem(Menu,MakeMenu,'必要な音声を再生成',8,Handler); AddMovieMenuItem(Menu,MakeMenu,'現在の位置をプレビュー',11,Handler);
  AddMovieMenuItem(Menu,MakeMenu,'現在工程の結果を作る',31,Handler); AddMovieMenuItem(Menu,MakeMenu,'次の工程へ',27,Handler); AddMovieMenuItem(Menu,MakeMenu,'前の工程へ',32,Handler);
  var Tools := CreateMovieMenuGroup(Menu,'MovieToolsMenu','詳細(&D)');
  AddMovieMenuItem(Menu,Tools,'VOICEVOX話者を更新',7,Handler); AddMovieMenuItem(Menu,Tools,'キャラクター素材を更新',23,Handler); AddMovieMenuItem(Menu,Tools,'波形を更新',24,Handler);
  AddMovieMenuItem(Menu,Tools,'FFmpegを選択...',22,Handler); AddMovieMenuItem(Menu,Tools,'不一致を診断',28,Handler); AddMovieMenuItem(Menu,Tools,'使える演技へ戻す',29,Handler);
  AddMovieMenuItem(Menu,Tools,'ジョブを中止',9,Handler); AddMovieMenuItem(Menu,Tools,'ジョブを再試行',10,Handler);
end;
end.
