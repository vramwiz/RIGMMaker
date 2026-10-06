# 台本ウィザード第2段階と更新日時（2026-10-06）

第1段階の確認後に許可された「キャラ選択」までを実装。配置・レイアウト・本文・音声生成・動画制作への接続は追加していない。

## 操作

台本管理から新規作成／再開し、題名を保存アイコンで確認する。チェックの進行アイコン、またはキャラ工程アイコンを押すと第2段階へ進む。保存だけでは工程を進めない。

共通サムネイル経路で登録済みPSD／RIGMを表示する。完成済みキャラをチェックで複数選択でき、1人以上で保存・確認できる。PSDは既存の実素材／production検査、RIGMは既存LoadRigmの検査後のUsableを使用する。未完成・読込不可は選択を拒否する。戻る・ホーム・終了では0人を含む途中状態も保存する。題名工程へ戻って編集しても選択とキャラ確認状態を保持する。

検査済み情報はプロセス内で再利用するが、毎回ファイル内容のSHA-256を比較する。素材が変われば検査し直す。タイムスタンプだけで完成判定を再利用しない。選択の変更でサムネイルを繰り返し合成しない。

台本管理から再開すると、最後に保存した工程・題名・チェック状態を復元する。同一UIDの画面と共通パイプが同じ状態を参照する。画面を開いた後に登録されたキャラをパイプで選んだ場合も一覧へ反映する。

## 永続データと互換性

保存先はデータルート内の `Projects\{台本UID}\project.rigmovie`。既存TRigmMovieProjectと原子保存・外部変更検出を再利用する。`scriptWizard`のschemaVersion=1へ任意フィールド`charactersStatus`と`selectedCharacters`を追加。stageはtitle／charactersのみ。

選択にはデータルートからの相対path、name、renderFormatを保存する。既存キャラを複製・改変しない。旧第1段階データは新フィールドがなくても開ける。読み取り時にファイルを書き換えず、キャラ工程への変更時に必要な情報を追加する。従来作品は従来経路のまま扱う。Documents、.rigmignore、再解析ポイントの除外を維持する。

この工程ではCharacters／Scenes／Cuesへ配置やセリフを作らない。既存Speakers、選択メタデータのvoiceBinding等を保持し、声IDや設定を生成しない。

仕様書にはキャラ登録時のVOICEVOX紐付けが記載されているが、現在のPSD／RIGM登録ファイルにはそのフィールドがなく、従来動画作品側で配役を管理していた。実際に登録された3素材のmanifestにも音声キーはない。新規選択のvoiceBindingStatusはunassignedと明示する。キャラ選択の確認は画像の選択確認であり、音声紐付けの完了を表さない。後続の音声処理には登録時の紐付け実装／明示した配役情報が必要。

## 共通パイプ

`app-script-status`はstage、確認状態、selectedCharactersを返す。implementedStageはcharacters。canAdvanceは確認済み題名からキャラ選択への移動だけを表し、キャラ工程ではfalse。

- `app-script-character-library`：登録path、name、renderFormat、readyForScript、productionReason、voiceBindingStatus。
- `app-script-set-characters`：projectId、現在revision、paths配列。登録範囲外、パス逸脱、重複、未完成、古いrevisionを拒否。0人は途中状態として許可。
- `app-script-set-stage`：projectId、現在revision、stage=title／characters。キャラ工程には題名の人による確認が必要。後続工程を拒否。
- `app-script-save`：projectId、現在revision。途中状態を保存する。人による確認を代行しない。

既存の題名／一覧／新規／再開APIも維持する。人の保存アイコンだけが現在工程を確認済みにする。

## 更新日時

UTCのupdatedAtをそのまま表示していた問題を修正。TryISO8601ToDate(ReturnUTC=True)でオフセットを正規化し、Windowsのローカル時刻へ一度だけ変換する。UTC保存は維持し、既存日時を書き換えない。日本時間のPCでは一覧ヘッダーに日本時間と表示する。空欄／不正値は安全に表示する。

対象PCはTokyo Standard Time。実際の既存台本の `2026-10-06T02:49:47.196Z` は表示上 `2026-10-06 11:49:47` となる。

## 検証と復元

通常のRIGMMaker.dprojを標準Debug／Release、Win64でビルド。EXEとDCU出力だけを専用Recoveryへ隔離して検証し、使用中プロセスがないことをGet-Processで確認して通常EXEへ配備する。ビルドログ、変更前EXE／ソース、配備ハッシュ、検証JSONと画面を `Win64\Validation\ScriptStage2` に保存する。

Invoke-ScriptCharacters.ps1はマーカー付き専用Tempへ素材をコピーし、所有GUI・実際の名前付きパイプ・別プロセスの再起動で検証する。元素材は前後のハッシュを比較する。Invoke-ScriptTitle.ps1で題名工程と日本時間表示も検証する。完了した所有作業フォルダはRecoveryへ移動して復元可能に保持する。永久削除／ごみ箱消去はしない。

検証用CLIは通常GUIに露出しない。現段階はキャラ選択までで停止し、ユーザーの試用確認を待つ。

最終結果：標準Debug／Release Win64ビルドはエラー0。通常パスのEXEでキャラ選択GUI22項目・再起動4項目・実パイプ8項目、題名／日時GUI27項目・再起動7項目・実パイプ5項目が成功した。最終EXEのSHA-256は `5333E2244254166499DF6E06E2A700EF785FA42F9D86884A7990FBB4353169E6`。既存の実台本と3素材のハッシュは維持。所有テスト作業フォルダ11件を専用Recoveryへ移動し、対応表をcompleted-work-map.jsonへ保存した。撮影要求のファイル共有も、読込中に原子的置換できる設定に修正し、所有ファイルで確認済み。
