**任意の一括制作APIの例。** 通常は [工程ごとの協働操作](AI操作例.md) を使う。このAPIを明示的に選んだ場合だけ診断から出力まで連続実行する。

# Codex / dot から一件の依頼で動画を作る

最新版はルートの `RIGMMaker.preview.exe`。通常は共通パイプへ依頼を送り、診断 → 必要な音声生成 → 演技付きプレビュー → AVI/MP4出力まで一つのジョブで進める。補助GUIで工程ボタンを順番に押す必要はない。

以下は、既存の動画プロジェクトに設定された素材・声・演技・出力場所を再利用する最小例。編集画面を開いた対象アプリの `%LOCALAPPDATA%\RIGMMaker\pipes\*.control.json` を指定する。複数アプリがある場合は対象の接続情報を選び、別アプリへ送信しない。

```powershell
$sender = '.\制作支援\パイプ\Send-RigmCommand.ps1'
$connectionFile = '<対象アプリの接続情報JSONの絶対パス>'
$request = @{
    requestKey = 'shop-intro-001'
    script = "narrator:こんにちは。静かな雰囲気の店を紹介します。`nnarrator:最後までご覧いただき、ありがとうございました。"
}
& $sender -ConnectionFile $connectionFile -Command movie-produce `
    -ArgsJson ($request | ConvertTo-Json -Depth 8 -Compress)
& $sender -ConnectionFile $connectionFile -Command movie-production-status `
    -ArgsJson '{"requestKey":"shop-intro-001"}'
```

応答の `data.state`、`done`、`completedSteps`、`job`、`needs` を読む。進行中は `movie-production-status` を取得し、成功時の `data.result.videoPath`、`previewPath`、`audioFiles` が実ファイルを指す。同じ `requestKey` と同じ依頼の再送は元のジョブ・結果を返し、重複制作しない。内容を変えた新規制作には新しいキーを使う。

VOICEVOXへ接続できない場合は `state=blocked` と `needs[].code=engine_unavailable` が返る。無音・テスト音を代用せず停止する。エンジンが利用可能になった後は同じキーで再開する。接続先を変更する場合は必要な設定だけ渡す。

```powershell
& $sender -ConnectionFile $connectionFile -Command movie-production-resume `
    -ArgsJson '{"requestKey":"shop-intro-001","settings":{"engineUrl":"http://127.0.0.1:50021"}}'
& $sender -ConnectionFile $connectionFile -Command movie-production-status `
    -ArgsJson '{"requestKey":"shop-intro-001"}'
```

素材・声・出力先などが不足する場合も `needs` が必要な項目を返す。Codex / dot は既存設定と取得済み情報を優先して補い、`movie-production-resume` に修正項目だけ渡す。例えば声の指定は `voices:{narrator:<実際のstyleId>}`、素材は `settings:{character:<保存済みRIGMパス>}`。音声・演技設定が有効なら再入力は不要。既に完成した音声は保護し、未完了部分だけ再処理する。

プレビューだけなら `deliver:"preview"`、出力先指定は未使用の `outputPath`、字幕・演技付きJSONは `script` オブジェクトまたは `scriptPath` を使う。省略時の出力名は設定済みの場所と形式を使い、キー由来の新しい名前になる。既存出力は上書きしない。

プロジェクト変更は未保存状態で保持し、自動保存しない。保存は明示的な `movie-save`。中断は `movie-production-cancel`。キー履歴は現在のセッション内の最新64件で、アプリ再起動を越えて保持されない。

直接JSONを送るクライアントは `schemaVersion:1`、`requestId`、`command:"movie-produce"`、`args` を使い、更新系の `args.projectId/revision` に最新 `movie-status` の値を入れる。上記PowerShell送信器は省略された識別情報を補う。引数の一覧は `movie-schema` を取得する。

実VOICEVOXの日本語発話と実音声による口パクは未検証。この環境の既存エンジンは内部ファイル不足で起動できず、今回の自動検証では明示的なHTTPテスト音フィクスチャを使用した。通常処理にはその代用を組み込んでいない。
