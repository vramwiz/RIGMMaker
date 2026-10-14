# AIで全セリフの表情を設定する

[開発ノート](../../../note.md) ／ [配役・表情の仕様](SCRIPT-CASTING-20261009.md)

2026-10-14、独立テストで成功した専用Codexと匿名パイプの通信を使い、本編の第11段階「配役」に最初のAI補助を追加した。対象は **表情（映像のキャラ）のみ**。

## 操作

1. 台本確認から第11段階「配役」へ進む。
2. 表情欄の下にある **「AIで全セリフの表情を設定」** を押す。
3. 全セリフを1回の要求にまとめて送る。処理中は件数・処理状況と動く進捗バーを表示し、開始ボタンと手動の表情変更を無効にする。
4. 正常終了すると全件を検査してまとめて反映し、完了件数と変更件数を表示する。必要なら手動で調整し、通常の保存ボタンまたは工程移動で保存する。

「中止」で処理を止められる。台本・工程を切り替えた場合も中止する。中止・通信失敗・不正な回答では、一部だけを反映せず元の表情を保持する。終了後は再実行できる。

既に手動設定した基本表情も含めて全行を判定する。通常・喜び・悲しみ・真剣・怒り・穏やか・驚き・疑問・楽しさ・困惑から選び、自動判定を明示的な表情へ置き換える。細かい部位の個別差分は保持するため、その部位では個別指定が優先される。

VOICEVOXの感情・声、読み、生成済み音声、最後まで再生した確認、配役・シーンの確認状態、原文・字幕・画像は変更しない。表情に対応する実素材の表示は既存の描画処理に従う。この機能は画像の生成ではない。

## Codexとの通信と記録

本編が処理専用の `codex app-server --listen stdio://` を非表示で起動し、Windowsの匿名パイプで通信する。現在開いているCodexチャットへ送信する操作ではない。既存のCodexログインを使う。

`CODEX_PIPE_EXE`、PATH、`%LOCALAPPDATA%\OpenAI\Codex\bin\*\codex.exe` の順で実行ファイルを探す。明示したパスが存在しない場合はエラーとする。モデルは利用者のCodex設定を使い、必要なら `CODEX_PIPE_MODEL` で指定できる。

台本の題名、全配役セリフの本文・順序・区分・話し手・現在の表情を送り、前後関係を含めて判定させる。1セリフずつの呼出しではなく、1回の `turn/start` と構造化JSONの回答で全件を処理する。接続応答の待機は30秒、判定の待機は最大5分。専用プロセスとその子プロセスは、この要求の完了・中止時に終了する。

作業データルート内の `Exchange/CodexExpressions/<要求ID>/protocol.log` に送信・応答・エラーを残す。台本本文も含む。生成物と検証結果はGit同期対象外であり、作品の通常保存とは別の記録である。

## 反映時の検査

作品ID・要求ID、セリフIDの全件一致・重複なし、件数と10種類の表情IDを全て検査してから反映する。要求時の入力フィンガープリントと現在の内容も照合する。処理中に本文・配役・表情・個別差分が変われば結果を適用せず、再実行を案内する。行選択や保存だけでrevisionが進んだ場合は、判定対象が同一なら反映できる。

通信はワーカースレッド、モデルへの反映はWorkspaceのメインスレッドで行う。表情は既存の `SetCastingExpression` を使い、全件反映後に作品の変更通知を1回行う。自動保存はしない。

| ファイル | 担当 |
| --- | --- |
| [RigmCodexClient.pas](../../Integrations/RigmCodexClient.pas) | 専用Codex・匿名パイプ・JSON応答・進捗・終了処理 |
| [RigmScriptAiExpressions.pas](../../Studio/Model/RigmScriptAiExpressions.pas) | 全件要求・出力スキーマ・照合・表情の反映 |
| [RigmWizardExpressionAi.inc](RigmWizardExpressionAi.inc) | Workspaceによる開始・監視・中止・結果回収 |
| [RigmScriptCastingFrame.pas](RigmScriptCastingFrame.pas) | ボタン・進捗・中止・状態表示 |
| [AiExpressionsCheck.dpr](../../Psd/Validation/AiExpressionsCheck.dpr) | 隔離した台本と実ボタンイベントによる検証 |

## 検証

証跡は `output/validation/20261014-ai-expressions/` に保持する。架空の6セリフを実際の専用Codexへ1回の要求で送り、喜び・悲しみ・怒り・疑問・真剣・穏やかの6件が返った。実ボタンのClickイベントからの開始、二重開始の拒否、進捗と中止UI、行選択後の反映、音声キー・再生確認・その他の項目の保持、保存と再読込、中止を含む68項目が成功した（`check-03/run/result.json`）。

さらに、不正回答・ID・件数・重複・処理中の編集の全件拒否、個別差分の保持、Codexが見つからない場合の復帰と再実行、ボタン・状態欄・一覧の配置を含むオフライン40項目が成功した（`check-06/run/result.json`）。検証台本と設定は専用フォルダに作り、ユーザーの実作品やVOICEVOX設定は変更していない。

本編のWin64 Debug／Releaseはdprojと同じ検索パスでビルド成功。既存警告13件、追加警告0件、エラー0件。既存の警告0件という全体目標は未達のままで、この機能とは別の課題である。

物理マウス操作、実作品での表情の見た目、音声の試聴は未実施。画面キャプチャは白画像だったため表示の証拠には使わず、UI配置の検査と実イベントの動作検証を記録する。複数DPIの検証は行っていない。

再検証はリポジトリ直下で次を実行する。`-Live` を付けた場合だけ実Codexへ架空台本を送る。

```powershell
& ./Source/Psd/Validation/Run-AiExpressionsCheck.ps1 -OutDir "$PWD/output/validation/ai-expressions-new"
& ./Source/Psd/Validation/Run-AiExpressionsCheck.ps1 -OutDir "$PWD/output/validation/ai-expressions-live-new" -Live
```

出力先には未使用のフォルダ名を指定する。
