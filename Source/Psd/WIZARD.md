# 単一メインフォーム・遅延生成の中間成果（2026-10-05）

入口は `RIGMWizard.dpr`。新シェルは常にホームから開始し、初回選択時に必要なページだけを生成する。生成後は表示を切り替えて再利用し、アプリ終了まで保持する。通常の `RIGMMaker.dpr` と通常EXEは新シェルへ切り替えていない。

## 到達点

- ホーム → キャラ管理 → PSD制作・編集 → キャラ管理 → ホーム。既存パッケージを読み込み、未完成でも編集できる。
- PSD編集は `TPsdStudioFrame` 内のレイヤー・表情・ボーン基準・動作確認ページ。同じSessionで表情/視線/選択部位/入力中の名前/途中の基準点を保持する。戻るやホーム移動で保存・破棄しない。
- 動作確認へはボーン基準の検査が必須。タブ移動も検査し、無効なら基準ページへ戻す。別の編集フォームを開かない。
- 制作中の設定反映は既存の自動保存経路を使用。完成後の編集Sessionは明示保存を維持し、終了時は未保存変更の破棄確認を行う。必須感情が未確定で、実キャラの完成後編集は未検証。
- 台本管理 → 台本作成 → 動画編集は、未実装と表示する導線確認ページ。制作・保存・動画機能の移行済みとは扱わない。Live2D編集も未移行。通常版の各機能と作品を保持する。

`TRigmWizardMainForm` はページ所有・遷移・共通終了を担当する。ページのOwnerはメインフォーム、表示Parentはページ用パネル。Ownerによって終了時に解放し、二重Freeを行わない。非表示のPSDプレビューはタイマーを停止し、再表示時に同じ時刻から再開する。編集中のSession/パイプはページ移動だけでは破棄せず、Session破棄時に既存終了処理を通す。

`PsdStudioForm.pas` は独立検証入口/旧シェル用の薄い互換ホスト。新シェルではこのTFormを生成せず、Frameを直接所有する。

## 起動・検証

ビルドは `Source\Psd\build-integrated.ps1 -Configuration Release -Project RIGMWizard.dpr`。隔離Releaseの起動先は `Win64\Validation\IntegratedPsd\Release\RIGMWizard.exe`。既定データルートは `D:\Users\take6\RIGMMaker`、`--data-root <folder>` で変更できる。

Debugの再検証は `Source\Psd\Validation\Invoke-WizardFlow.ps1 -Configuration Debug`。登録パッケージを所有印付きの別ルートへ複製し、原本へ基準点や名前を保存しない。証拠は `Win64\Validation\PsdStudio\wizard-flow-debug.json`、同 `.pages.json`、画面PNG、metadata.json。実部品イベントを使用し、物理マウスやファイル選択ダイアログは自動操作しない。移動した検証物は `Recovery\wizard-shell-20261005\recovery-index.json` に復元先を記録する。

Debugは導線14項目・PSD編集11項目が成功し正常終了。1個のTForm、初回生成と再利用、ページ/名前/基準点の下書き保持、基準検査、保存と未完成状態の維持を確認した。新シェルのReleaseはビルド確認のみ。内部キャプチャには一部Windows標準部品が描画されない環境制限がある。GUI全体の物理操作・完成後の実キャラ編集・認証付き制作は確認済みとは扱わない。

## 残作業・認証の停止点

旧動画・台本・Live2DをFrameへ移し、旧パイプの共通入口を接続してから通常起動先を変更する。新シェルに旧メインの動画/制作パイプ入口は未接続。PSD独自SessionパイプはFrame内で利用する。

Syncroh2の真正な新規PSD認証/交換/バイト保全接続は未実装。共有ライブラリと制作ルールはPRODUCTION.mdに記録済み。実行Windowsユーザーは `o-taketani\CodexSandboxOffline`。このユーザーの `%LOCALAPPDATA%\Syncroh2\PSDArtEditor\origin.key` は存在しない。`NewArtPsdOrigin` は鍵を発行してDPAPIで永続化するため、鍵セットアップが必要な場合は停止する指示に従い呼び出していない。運用Windowsユーザーと鍵のセットアップが必要。別ユーザーの鍵の読み出し・コピー、署名フラグによる旧PSDの昇格は行わない。

必須感情は依然未回答で完成付与を保留。新規AI画像生成、長尺MP4、通常EXEの配置、インストール、課金、commit/pushは行っていない。
