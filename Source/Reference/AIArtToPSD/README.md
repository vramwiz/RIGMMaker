# AIArtToPSD エディタの移植準備

2026-10-02 に `D:\DelphiProg\test\AIArtToPSD\AIArtToPSD.dpr` と、その編集画面の構成・依存関係を確認した。
本フォルダーには、RIGMMaker の RIGM エディタへ移植するための参考ソースをコピーした。

## 今回のコピー範囲

コピー元の `Source` 以下の相対配置を維持し、ソースは変更せずにコピーした。
対象は 19 個の Pascal ユニット、メインフォームの DFM 1 個、依存部品の説明 4 個の計 24 ファイル。
元アプリの DPR / DPROJ / RES、実行ファイル、生成物、PSD・PNG の素材、試験用データはコピーしていない。

| 配置 | ファイル | 役割 |
| --- | --- | --- |
| `Shell` | `AIArtToPSDMainForm.pas` / `.dfm` | 編集画面の組み立て、プレビュー、操作と連携処理の接続 |
| `Shell` | `ArtLayerList.pas` | サムネイル付きの独自レイヤー一覧 |
| `Shell` | `ArtFileHistory.pas` | 最近使ったファイルの管理 |
| `Core` | `ArtDocument.pas` | 画像・グループ・文書状態の元実装 |
| `Core` | `ArtLayerName.pas` / `ArtParts.pas` | レイヤー名の修飾とパーツ切替 |
| `Core` | `ArtRasterTransform.pas` | ラスター画像の配置・変換 |
| `Editor` | `ArtUndo.pas` | 編集状態の Undo / Redo |
| `Persistence/PNG` | `ArtPng.pas` | PNG 素材の読み込み・書き出し |
| `Persistence/PSD` | `ArtPsd.pas` | PSD 入出力と、元エディタが呼び出すレイヤー合成の参照元 |
| `Integrations/AIExchange` | `ArtExchange.pas` | Codex 向けの素材交換、生成結果の取込、復帰処理 |
| `Integrations/Pipe` | `ArtPipeBridge.pas` / `ArtPipeProtocol.pas` | アプリと指示を接続するパイプ連携 |
| `Lib/Pipe` | `PipeServerTThread.pas` / `README.md` | パイプ通信の共通処理と説明 |
| `Lib/DropFile` | `DropFile.pas` | ファイルのドラッグ＆ドロップ |
| `Lib/UI/VerticalScrollBar` | `VerticalScrollBarControl.pas` / `README.md` | 独自一覧の縦スクロール |
| `Lib/UI/HorizontalTrackBar` | `HorizontalTrackBarControl.pas` / `HorizontalTrackBarRenderer.pas` / `README.md` | 一覧行の不透明度操作 |
| `Lib/UI/DarkComboBox` | `DarkComboBox.pas` / `README.md` | 暗色の選択コントロール |

この参考ソースは RIGMMaker の DPR / DPROJ / ユニット検索パスに登録していない。
現在のアプリは `Source\Shell\RIGMMakerMainForm.pas` だけを起動する。
本フォルダーを単独アプリとしてビルド・起動する構成にもしていない。

## 確認した元エディタの画面

DFM はフォームの基本設定のみを持ち、画面部品は `AIArtToPSDMainForm.pas` の `CreateWithHistory` で生成する。
現在の表示は、中央の画像プレビュー、右側の独自レイヤー一覧、下側の「AIとのやりとり」で構成される。
プレビューには拡大縮小とパンがあり、レイヤー一覧にはサムネイル、表示状態、名前、不透明度、縦スクロールの実装がある。
座標入力、パーツ切替、AI 交換操作等には、画面に表示されていない部品も残っている。

RIGMMaker の左側に置く一覧は、RIGM キャラクターデータを管理する専用 GUI とする。
元エディタのレイヤー一覧は文書内の画像・グループを対象にするため、RIGM ファイルの一覧とは別の責務として扱う。

## RIGM へ移植するときの変更箇所

- 元の PSD 読み込みは取り込み用に利用し、RIGM の読み込み・保存を別途実装する。ファイル選択フィルター、保存処理、PSD 用の表示文言も用途に合わせる。
- `ArtPsd.pas` は元処理の参照用。PSD のデータを `.rigm` という名前で保存する処理にはしない。
- プレビュー、Undo の復帰、AI 生成結果の取込も `RenderPsdLayers` を呼ぶ。入出力以外の PSD 依存も分離する。
- `ArtExchange.pas` は PSD を使う復帰用スナップショット等に依存する。RIGM 仕様に合わせて保存と復帰を変更する。
- `ArtDocument.pas` には PSD 由来の原データ・タグ・レイヤー情報がある。初期 RIGM では画像パーツ・グループ、安定したパーツ ID、親 ID、表示順、位置・サイズ・回転・拡大率、表示状態、不透明度、ロック状態を扱うモデルへ移行する。メッシュ・ボーン等は後から拡張する。
- 元フォームは `TMainForm` / `MainForm` という名前を使う。実際に組み込む際は RIGM エディタ用の名前に変更し、アプリのメインフォームと分ける。
- `ArtFileHistory` の既定の保存先はマイドキュメント配下の `AIArtToPSD`。RIGMMaker の管理フォルダーとは別途接続し直す。
- 元フォームの生成時にはパイプを開始する。`ArtPipeBridge` のパイプ名と接続情報の保存先も `AIArtToPSD` 用のため、RIGMMaker 用に変更してから接続する。

2026-10-02 に [RIGM 基本仕様（暫定）](../../../RIGM仕様.md) を受領した。
1 キャラクターを 1 個の `.rigm` ファイルとし、パーツ画像と専用サムネイルを内部に保持する。アプリ名は `RIGM Maker`、AviUtl2 プラグイン版は `RIGMスタジオ`。
具体的な格納方式やサムネイルサイズ等は実装時に決める。
現在は移植準備の段階であり、RIGM のモデル・読み書き・新規ファイル作成・サムネイル生成・一覧 GUI・エディタ起動処理は未実装。
マイドキュメント配下のフォルダー作成も、アプリ側の管理機能を実装する段階で行う。

## パイプ・分解・差分制作の資料

[RIGM 制作支援](../../../制作支援/README.md) に、送信スクリプト、RIGM 用の制作手順、参考元の学習記録・生成指示・加工スクリプトをまとめた。
処理コードは本フォルダーのコピーを参照し、パイプ・素材交換・画像操作・差分切替・Undo を RIGM の編集モデルへ接続する。
今回、本フォルダーの既存コピー 24 ファイルも現在の参考元と一致することを確認した。

## コピーの確認

- 24 ファイルすべてについて、コピー元とコピー先の SHA-256 が一致することを確認。
- 19 ユニットの `uses` を確認し、Delphi 標準以外の依存ユニットがコピー内に揃っていることを確認。
- 元の `AIArtToPSD` プロジェクトは変更していない。
- 参考ソースはアプリに未接続のため、本アプリでのコンパイル・画面起動・操作確認は未実施。
