# 台本ウィザード 第3段階：レイアウト選択

本記録は第3段階受入時点の履歴。現行のNext保存・配置・再開動作は `SCRIPT-STAGE4-20261006.md` を参照。

2026-10-06。第1・第2段階に続く、独立した構図選択画面を追加。
`auto_video_ui_spec.md` の13・14・27節と既存動画モデル・合成処理の構図を使用する。

## 操作

1. 通常の `RIGMMaker.exe` で台本管理から新規作成、または既存のウィザード作品を再開する。
2. 題名を保存・確認し、キャラ選択へ進む。完成済みキャラを1人以上選び、保存・確認する。
3. チェックアイコンまたはレイアウトアイコンで第3段階へ進む。
4. 中央型、L字型（画面左にキャラ・右に画像）、逆L字型（画面右にキャラ・左に画像）を選ぶ。
5. 保存アイコンでレイアウトを確認する。キャラ・題名への戻り、台本管理からの再開も可能。

16:9のFullHD構図見本は、画像、補足説明、字幕、キャラ領域を明示する。
中央型は選択順で左右へ交互に仮表示し、L字型は全員を同じ側へ仮表示する。人数は1人に制限しない。
サムネイルは既存の共有キャッシュを借用する。重い素材処理をこの画面から同期実行しない。
キャッシュがなければ既存サービスが非同期にサムネイルを作る。
中央型の共通背景は仮の暗色・明色・青色を選べる。画像背景や説明画像は今回はプレースホルダー。
L字型・逆L字型には共通背景を表示しない。中央型の色は切替時も保持する。

## 保存と共通状態

保存先は既存と同じデータルートの `Projects\{UID}\project.rigmovie`。
`scriptWizard.stage=layout`、`layoutChoice=theme|l-left|l-right`、
`backgroundTone=dark|light|blue`、`layoutStatus=in-progress|complete` を保存する。
既存動画モデルの `layout=theme|l`、`lDirection=left|right`、`backgroundColor` と整合させる。
キャラの選択、未知の音声紐付け情報、話者定義を保持する。
既存の題名・キャラ工程作品は、開くだけでは移行保存しない。
キャラ選択を変更すると構図選択は残し、レイアウト確認を未完了に戻す。

保存には既存の原子的保存・外部変更検出を使用する。
画面は主フォーム内の遅延作成フレーム。旧動画制作Session、配置Actor、シーン、セリフは作らない。

## 構図の共有

`RigmMovieLayout.pas` の比率領域を新UIと既存合成処理で共有する。
元のFHD画像・説明・字幕領域を維持し、動画解像度へ `ScaleLayoutRect` で拡縮する。
キャラ領域とキャラ側の補足領域は構図ガイドであり、実際のキャラ位置・サイズを設定しない。
正面・非正面の制御、PSD編集、従来動画編集への選択分岐は今回変更しない。

## パイプ

人の操作と同じ `TRigmWizardWorkspace` に対して行う。

- `app-script-status`: 工程・選択・状態を取得。`layoutGuide` は0〜1の比率領域、FHD基準寸法、動画寸法を返す。
- `app-script-set-stage`: `projectId`、最新 `revision`、`stage=title|characters|layout`。
  レイアウトへ進むには題名・1人以上のキャラ選択を人が確認済みであることが必要。
- `app-script-set-layout`: `projectId`、最新 `revision`、`choice=theme|l-left|l-right`、
  任意の `backgroundTone=dark|light|blue`。即座にGUIへ反映する。
- `app-script-save`: 途中保存。人の確認済み状態にはしない。

無効な構図・背景・古いrevisionは変更前に拒否する。
`placement` 等の第4段階は受け付けず、第3段階の `canAdvance` はfalse。自動進行や生成・出力は行わない。

## 検証と配備

標準 `RIGMMaker.dproj` のDebug/Release Win64を、EXE/DCU出力先のみ隔離してビルド。
通常EXEへ配備後、所有マーカー付きのTemp検証ルートに実素材3点をコピーして短い操作確認を実施。
GUI20項目、再起動6項目、実パイプ7項目、主フォームの実画面5枚で確認する。
元素材3点のSHA-256は検証前後で一致。長尺出力・新規画像生成・新規ソフト導入は実施しない。

検証コードは `Invoke-ScriptLayout.ps1` と `VerifyScriptLayout`。
実行中の既存EXEは終了させず、配備前にプロセスとタスク開始時のEXEハッシュを確認する。
旧EXE、隔離ビルド、結果、検証作品は復元できるよう
`Win64\Validation\ScriptLayout\Recovery\layout-ab9c1c561d7f4f1c8683e9352fb58aa1` に保管。
通常EXEのSHA-256は `6A1FD921781C3E16BA0DA1CFAFC3F242522C886B0AE70B4D1ECBFAFECDBF1E79`。

第4段階の位置・大きさ・向きのドラッグ調整、画像背景の選択、説明素材の生成・台本入力・動画制作は未実装。
今回の第3段階をユーザーが試すまで、次工程の実装は停止する。
