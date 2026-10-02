# 元資料と処理コード

コピー元は `D:\DelphiProg\test\AIArtToPSD`。原文と学習記録は変更せずに保存し、RIGM 用の制作手順は [制作支援の入口](../README.md) から読む。
[コピー記録](コピー記録.json) には、コピー元・コピー先・SHA-256 と、既存コピーの確認結果を保存した。

## 原文ガイド

`AIArtToPSD` 以下に、元の README、note、Codex 再利用ガイド、立ち絵生成ルール、パイプ操作ルール、AI 画像交換、Undo と復帰、表情とパーツ切替の文書をコピーした。
元ガイド内の相対リンク、素材・PSD・試験・ツールへの参照はコピー元の構成を指す。元環境の詳細を調べるときはコピー元も参照する。

## 処理コードの対応表

処理コードは既存の `Source/Reference/AIArtToPSD` を使う。今回、24 ファイルが現在の参考元と同じであることを再確認した。

| 用途 | コピー済みのコード |
| --- | --- |
| パイプ通信・命令 | [通信](../../Source/Reference/AIArtToPSD/Lib/Pipe/PipeServerTThread.pas)、[接続](../../Source/Reference/AIArtToPSD/Integrations/Pipe/ArtPipeBridge.pas)、[JSON プロトコル](../../Source/Reference/AIArtToPSD/Integrations/Pipe/ArtPipeProtocol.pas) |
| 素材交換・一括取込・復帰 | [ArtExchange](../../Source/Reference/AIArtToPSD/Integrations/AIExchange/ArtExchange.pas) |
| 画像・グループのモデル | [ArtDocument](../../Source/Reference/AIArtToPSD/Core/ArtDocument.pas) |
| 切り出し・拡縮・透明余白除去 | [ArtRasterTransform](../../Source/Reference/AIArtToPSD/Core/ArtRasterTransform.pas) |
| パーツの排他切替・名前 | [ArtParts](../../Source/Reference/AIArtToPSD/Core/ArtParts.pas)、[ArtLayerName](../../Source/Reference/AIArtToPSD/Core/ArtLayerName.pas) |
| PNG 入出力 | [ArtPng](../../Source/Reference/AIArtToPSD/Persistence/PNG/ArtPng.pas) |
| Undo / Redo | [ArtUndo](../../Source/Reference/AIArtToPSD/Editor/ArtUndo.pas) |
| 独自レイヤー一覧と表示 | [ArtLayerList](../../Source/Reference/AIArtToPSD/Shell/ArtLayerList.pas)、[元フォーム](../../Source/Reference/AIArtToPSD/Shell/AIArtToPSDMainForm.pas) |
| PSD 取り込み・元の保存処理の参照 | [ArtPsd](../../Source/Reference/AIArtToPSD/Persistence/PSD/ArtPsd.pas) |

このコードは RIGM Maker にまだ接続していない。元の PSD 保存と復帰の呼び出し、文書モデル・座標系、パイプ名は [移植準備メモ](../../Source/Reference/AIArtToPSD/README.md) に従って RIGM へ合わせる。
