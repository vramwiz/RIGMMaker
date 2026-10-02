# RIGM 用パイプ連携の準備

[Send-RigmCommand.ps1](Send-RigmCommand.ps1) は、参考元の `Tools/Send-ArtCommand.ps1` をファイル名だけ変えてコピーした送信器。
PowerShell 7 を使用し、UTF-8 JSON を Windows のメッセージ型名前付きパイプへ送る。
送信器は文書形式の読み書きを行わないため、通信処理を再利用できる。

現在の RIGM Maker にはサーバーと命令処理を接続していない。RIGM 用の接続先ができてから使用する。

## コピー済みの処理コード

| コード | 役割 |
| --- | --- |
| [PipeServerTThread](../../Source/Reference/AIArtToPSD/Lib/Pipe/PipeServerTThread.pas) | 共通のメッセージ型パイプ通信 |
| [ArtPipeBridge](../../Source/Reference/AIArtToPSD/Integrations/Pipe/ArtPipeBridge.pas) | 通信スレッドから UI スレッドへの受け渡し、接続情報、終了処理 |
| [ArtPipeProtocol](../../Source/Reference/AIArtToPSD/Integrations/Pipe/ArtPipeProtocol.pas) | 要求・応答 JSON の検査と命令の呼び出し |
| [ArtExchange](../../Source/Reference/AIArtToPSD/Integrations/AIExchange/ArtExchange.pas) | 素材交換、結果の一括検証、取込、復帰 |
| [元フォーム](../../Source/Reference/AIArtToPSD/Shell/AIArtToPSDMainForm.pas) | 命令を文書・編集・プレビューへ接続する処理 |

## 通信と素材交換

要求は `schemaVersion`、`requestId`、`command`、`args` を持つ。応答の要求 ID と成功・失敗を送信器が確認する。
画像は JSON への base64 埋め込みではなく、ジョブ内の PNG として交換する元構成を利用する。
`export → PNG 加工・生成 → result.json → import` の流れと、文書 ID・版・ジョブ ID・画像ハッシュの検査を維持する。

参考元のフォームで確認できる命令は `status`、`export`、`import`、`progress`、`cancel`、`undo`、`redo`、`recover`。
送信スクリプトの許可リストにはそれ以外の名前も含まれるが、送信側の許可リストはアプリ側の実装状況を表さない。接続後は実際のハンドラーを確認する。

結果 JSON の操作には画像パーツ・グループの追加、画像置換、名前・属性変更、差分選択がある。
切り出し矩形、拡縮、透明余白除去、作業領域からの配置変換も元のコードに含まれる。

## RIGM 用に接続するとき

- `ArtPipeBridge` の `AIArtToPSD` 用のパイプ名と接続情報の保存先を RIGMMaker 用に変更する。
- 最新の接続情報と応答から対象アプリ・文書を確認する。元資料の接続名や PID を使わない。
- 元のレイヤー操作を RIGM パーツへ接続し、ID・親・表示順・変形・ロック状態と Undo を維持する。
- 通常保存と `snapshot.psd` を使う復帰処理を RIGM 保存・復帰へ変更する。拡張子だけの変更で代用しない。
- 左上基準の交換用 bounds と中央原点の RIGM 座標を対応付ける。
- PNG の原寸・alpha、配置、合成、保存・再読み込みを確認する。

移植後の送信例は、対象の RIGM 用パイプ名を指定する。

```powershell
& '.\制作支援\パイプ\Send-RigmCommand.ps1' -PipeName $rigmPipeName -Command status
```

元のプロトコル・処理の詳細は [パイプ操作ルール原文](../元資料/AIArtToPSD/パイプ操作ルール.md) と [AI 画像交換の原文](../元資料/AIArtToPSD/アプリ実装_AI画像指示交換.md) を参照する。
