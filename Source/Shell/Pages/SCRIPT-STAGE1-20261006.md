# 台本 第1段階：題名・保存再開（2026-10-06）

以下は第1段階の記録。同日の追加許可によるキャラ選択と日本時間表示の現行仕様は [第2段階の記録](SCRIPT-STAGE2-20261006.md) を参照。

第1段階の範囲は、ホーム→台本管理→新規作成→題名→保存/中断/再開だけ。この時点ではシリーズ・キャラ選択/配置・本文・校正・配役・音声・シーン・動画への反映は未着手。

## 操作

1. 通常の `D:\DelphiProg\MyApp\RIGMMaker\RIGMMaker.exe` を起動し、ホームの「台本・作品管理」を開く。
2. 一覧左端の新規アイコンから題名画面へ進む。各アイコンにヒントがある。
3. 題名（128文字以内）を入力し、保存アイコンで確認する。保存後も題名画面に留まる。
4. 左端の一覧アイコン、ホーム、ウィンドウ終了でも入力途中の題名を保存する。空の入力も未完成状態として保持する。
5. 台本管理で対象をダブルクリックすると、同じUID・題名・入力中/確認済み状態で再開する。アプリの終了後も再開できる。

保存できない場合は編集画面に留まり、入力と既存ファイルを保持する。「次へ」や旧制作開始のボタンは題名画面にはない。確認済みの題名でも次段階へ自動遷移しない。

## 保存方式

- データルート: `D:\Users\take6\RIGMMaker`。
- 新規台本: `Projects\{UID}\project.rigmovie`。題名をフォルダ名にしない。題名変更も同名別UIDも可能。
- 既存の `TRigmMovieProject` / `SaveMovie` / `LoadMovie` を使用する。別の大きなライブラリや保存形式は追加しない。
- `.rigmovie` の任意項目 `scriptWizard` に `format=RIGMMaker.ScriptWizard`、schemaVersion=1、stage=title、titleStatus、titleInput、createdAt/updatedAt（UTC）を保存する。旧作品ではこの項目を追加しない。
- 未完成入力は入力中として保存。人が保存アイコンで題名を確認すると確認済みになる。AIによる題名変更は入力中へ戻し、AI保存だけで人の確認を代行しない。
- 読込失敗/UIDと保存先の不一致/データルート逸脱/外部からのファイル更新を検出した場合は、現在の入力・元ファイルを保全する。
- 一覧では第1段階の台本と従来作品を区別する。従来の `.rigmovie` は既存動画編集経路で開く。`Scripts` の既存データを移動・削除・変換しない。
- 一覧走査は管理対象のProjects/Scriptsとルート直下の作品に限定。Documents、アプリの作業/素材フォルダ、再解析ポイントを除外し、`.rigmignore` のあるフォルダへ降りない。新規台本の保存先にも除外マーカーを適用する。

## 共通Workspaceパイプ

`Exchange\workspace-<PID>.json` のcommandPipeを使用する。既存のschemaVersion=1 / requestId / command / argsの封筒を維持する。新しい命令:

- `app-script-status`: 現在の題名・projectId・revision・保存先・工程状態。`canAdvance=false`。
- `app-script-list`: offset（既定0）、limit（既定50、上限100）。管理台本と従来作品を区別した一覧。
- `app-script-new`: 新規作成。題名画面上での連打は同じ新規台本を再利用。別の新規台本は一覧へ戻って作成する。
- `app-script-open`: path=`Projects\{UID}\project.rigmovie`。
- `app-script-set-title`: 現在のprojectId/revisionとtitle。GUIと同じ状態を更新する。
- `app-script-save`: 現在のprojectId/revision。途中状態を保存し、人の確認済み状態を勝手に付けない。

旧命令の接頭辞・応答形式・旧作品経路は維持。題名入力とパイプの状態を別々の下書きとして二重管理しない。

## 検証・配備

- 標準 `RIGMMaker.dproj` のWin64 Debug/Release成功。EXE/DCUの出力先だけ隔離した。既存警告/ヒント8件、エラー0件。
- `Source\Psd\Validation\Invoke-ScriptTitle.ps1 -ExecutablePath <検証EXE>` によるGUI23項目、再起動3項目、実Workspaceパイプ5項目が成功。実ウィンドウ4枚を保存して表示を確認した。正常終了済み。
- 新規/保存/一覧/再開、同名別UID、連打重複防止、空題名の確認拒否、戻る/ホーム/終了時保存、保存失敗時の入力/既存ファイル保持、AI題名変更のGUI反映、古いrevision拒否、AI保存と人の確認の区別、UID/工程/UTC日時の再読込、Documents/除外マーカー、従来作品の区別を確認した。
- 検証は所有マーカー付きTempデータルートと模擬作品だけを使用した。実際のScripts・キャラ・台本・作品・Documents素材は変更していない。
- 通常 `RIGMMaker.exe` に同じ検証済みReleaseを配備し、そのパスでも上記確認が成功した。最終SHA-256: `0FBF07E98CA220E6F98665A5FA508B03FD4A56D3D50853D101FC97E0B8473713`。
- 配備直前のEXEは `Win64\Validation\ScriptStage1\Recovery\stage1-32596a8d5da049e6a7179c1a754f5867\Before-deploy\RIGMMaker.exe` に保全した。元SHA: `8BC60CAEA842E659581C253A49E8776D0D7A671DB997300A86DABE8286CDC361`。実行中EXEの強制終了はしていない。
- 結果: `Win64\Validation\ScriptStage1\script-title.json`、`.reopened.json`、`.metadata.json`。一時的な撮影完了通知の共有違反は読み取り共有と再試行で修正し、過去の失敗と最新成功を区別した。
- 正常終了を確認した検証用Tempは同Recovery内へ復元可能に移動し、対応表を残す。恒久削除しない。
- 通常GUIにデバッグパネル/ログ表示は追加していない。既存検証入口に所有検証専用のCLI確認を追加しただけ。新しい画像、出力動画、長時間の全体検査、インストール、課金、commit/pushは行っていない。

第1段階で停止。次段階はユーザーの試用確認後に別途実装する。
