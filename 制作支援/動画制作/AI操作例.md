# Codex / dot とGUIで工程ごとに制作する

起動する最新版は `RIGMMaker.preview.exe`。通常は **台本 → 設定・素材・声 → 音声 → 演技・プレビュー → 動画出力** の順に、Codexがパイプで結果を作り、GUIまたは同じパイプで調整してから、明示的に「次へ」で進める。生成完了だけで次工程へ移らず、毎回の「確認済み」フラグも要求しない。デバッグ用の個別操作は従来どおり残す。

新規プロジェクトの既定はFullHD 1920×1080。fps30は既存FullHDプリセットの値で、今回ユーザーが指定したfpsではない。既存プロジェクトの寸法・fps・声・素材・演技・出力設定は保持する。明示的な変更だけ適用する。

対象アプリで編集画面を開き、`%LOCALAPPDATA%\RIGMMaker\pipes\*.control.json` のうちそのアプリの接続情報を指定する。複数アプリがある場合は対象を取り違えない。

```powershell
$sender = '.\制作支援\パイプ\Send-RigmCommand.ps1'
$connectionFile = '<対象アプリの接続情報JSONの絶対パス>'
& $sender -ConnectionFile $connectionFile -Command movie-workflow-status
& $sender -ConnectionFile $connectionFile -Command movie-workflow-run `
    -ArgsJson '{"text":"narrator:静かな店を紹介します。"}'
# 台本がGUIに反映される。GUIの「セリフを適用」またはmovie-update-cueで調整する。
& $sender -ConnectionFile $connectionFile -Command movie-workflow-next
```

`movie-workflow-status` の `data.currentStage`、`canRun`、`canNext`、`needs`、`allowedCommands`、`regenerate`、`results` が現在の状態を示す。GUIも同じ工程状態を表示する。

| 工程 | Codexが結果を作る操作 | GUI / パイプで調整 | 次へ進む条件 |
| --- | --- | --- | --- |
| script / 台本 | `movie-workflow-run {text}` または既存の台本取込 | セリフ・字幕・順序などを適用 | 台本が存在する |
| setup / 設定 | `movie-workflow-run` で接続・素材・声を診断 | 保存済みRIGM、取得した実styleId、出力設定などを適用 | 実際の不足・不整合が解消される |
| audio / 音声 | `movie-workflow-run` で未完成音声を生成 | 声・本文を修正したら必要な音声だけ再生成 | すべての必要音声が現在の設定に合う |
| preview / 演技・プレビュー | `movie-workflow-run {time}` で現在の内容を描画 | 字幕・演技・素材などを適用し、必要なら再描画 | 音声とプレビューが現在の内容に合う |
| export / 動画出力 | `movie-workflow-run` で設定済みの新しい出力先へ書き出す | 出力設定を適用。前工程変更時は戻って再生成 | 現在の内容の動画が実在する |

ジョブ中は `movie-job-status` を取得する。完了後も現在工程に留まる。GUIの「工程の結果を作る」は `movie-workflow-run`、「次へ」は `movie-workflow-next`、「前の工程へ」は `movie-workflow-back` に対応する。

```powershell
& $sender -ConnectionFile $connectionFile -Command movie-workflow-run
& $sender -ConnectionFile $connectionFile -Command movie-job-status
& $sender -ConnectionFile $connectionFile -Command movie-workflow-status
# 必要な編集を適用してから進む。
& $sender -ConnectionFile $connectionFile -Command movie-workflow-next
# 調整したい前工程へ戻る。指定を省略すると一つ前へ戻る。
& $sender -ConnectionFile $connectionFile -Command movie-workflow-back -ArgsJson '{"stage":"audio"}'
```

声・本文の変更は音声と後続結果を古くする。字幕・演技などの変更では音声を保護してプレビュー・動画を古くする。`regenerate` が必要な再生成対象を返す。既存動画は上書きしないので、再出力には新しい `outputTarget` / `path` を使う。完成した音声は失敗・中断後も保持する。キャンセルは `movie-job-cancel`、同工程で再作成すれば再開できる。

VOICEVOXに接続できない場合は `needs` / 診断が `engine_unavailable` を返す。無音・試験音を代用しない。エンジンが利用可能になってから、必要なら `movie-update-project {engineUrl}`、`movie-diagnostics-refresh` を行い、現在工程で `movie-workflow-run` を再実行する。

編集・工程移動には最新の `movie-status.projectId/revision` が必要。PowerShell送信器は省略された値を補う。GUIは表示時点のリビジョンで編集を適用する。未適用入力中のパイプ更新やセリフ選択変更で入力を消さず、古い編集は拒否する。競合時の「最新データを読込」は未適用入力を明示的に戻して現在のデータを表示する。

プロジェクト変更と工程移動は未保存状態で保持し、自動保存しない。`movie-save` / `movie-open` で工程位置・音声・プレビュー・動画参照を保存・再開できる。参照先の変更・消失も結果の古さとして判定する。必要な情報は `movie-schema`（計41命令）で取得できる。

[一括制作API](AI一括制作例.md) は任意・互換用として保持する。通常の工程ごとの経路では `movie-produce` を呼ばない。

今回の完成プレビューはSyncroh2の実保存設定にあるV:\Program Files\VOICEVOX\vv-engine\run.exeで動作した。VOICEVOX 0.25.2の東北きりたん／ノーマル108により4区間の実台詞を生成し、同期再生・口パク・瞬きを検証済み。通常工程の完成成果と回帰用HTTP TEST TONEを区別する。詳細は[実設定と完成プレビュー](VOICEVOX起動と完成プレビュー.md)。主観試聴、全GUI手動目視、物理DPI移動、実HIDは未検証。