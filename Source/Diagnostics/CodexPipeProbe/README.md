# Codex パイプ確認

本編へ組み込む前に、フォームのボタンを起点として専用Codexに画像を生成させ、返された画像をアプリで受信・表示できるか確認する独立したDelphi VCLプロジェクト。既存の検証プロジェクトは本編のモデルや画面への依存が大きいため、小さい専用プロジェクトを追加した。

## 起動と操作

リポジトリ直下の `Win64/CodexPipeProbe/Release/CodexPipeProbe.exe` を起動する。フォームは1つで、入力TEdit、2つの送信ボタン、画像表示TPaintBox、状態・受信画像パス・ログパスを表示する。通常起動では送信を始めない。

- **専用Codexで画像生成**：`codex app-server --listen stdio://` を子プロセスとして起動し、標準入出力のWindowsパイプで入力内容を送る。専用Codexに内蔵画像生成ツールを使わせる。
- **既存Codexで画像生成**：`codex app-server proxy` の標準入出力パイプを通じて、起動済みの共有app-serverの制御ソケットへの接続を試す。共有サーバーを自動起動・再起動しない。開いているデスクトップアプリがこの接続先を提供しているかは環境に依存する。

画像を受信すると縦横比を保ってPaintBoxに表示する。失敗理由は状態欄に表示する。Codexの文章回答はログに残す。送信中は2つのボタンを無効にする。フォームを閉じると自分の通信を中止し、所有する子プロセスを終了する。既存サーバーや本編のプロセスは終了しない。

成功条件は、正常な `turn/completed`、正式な `imageGeneration` 完了通知、画像ファイルの受信、画像の復号、表示中フォームのPaintBox描画がすべて成功すること。生成したと説明する文章やパスの文字列だけでは成功にしない。画像生成待ちは最大10分。

`imageGeneration.savedPath` が返れば、そのファイルを今回の実行フォルダの `received-image.*` へコピーする。保存先がなく画像データが返った場合はBase64を復号する。PNG・JPEG・BMPを表示できる。元画像を保持し、描画時だけ縮小する。親チャットで別途作った画像や既存画像を、この往復の成功証拠には使わない。

## どのパイプか

本編の名前付きパイプは、外部からの要求をアプリが受ける入口である。そこに要求状態を保存したり待ち受けたりするだけでは、Codexに新しいターンは発生しない。

このテストでは、公式app-server APIを呼ぶために別途Codexプロセスまたはproxyを用意する。通信順は `initialize` → `initialized` → `thread/start` → `turn/start` → 回答受信 → `turn/completed`。標準入出力には匿名パイプを使い、本編の名前付きパイプへ送信するテストとは区別する。

既存モードでも確認用の一時セッションを作る。この作業中のチャットに同じ指示を送って再帰実行したり、他の既存チャットを書き換えたりはしない。共有サーバーで確認用セッションが成功した場合も、既存デスクトップチャットを直接起動できた証明とは区別する。

## 認証・設定

PATH上の `codex.exe` と既存のCodexログインを使う。APIキーの入力・保存・取得は実装していない。この端末では `codex login status` がChatGPTログイン済みであることを確認した。モデルは利用者の設定に従い、テストコードから固定しない。

必要な場合だけ、起動前の環境変数で次を指定できる。

| 変数 | 用途 |
| --- | --- |
| `CODEX_PIPE_EXE` | 使用する `codex.exe` の絶対パス |
| `CODEX_PIPE_MODEL` | 検証したいモデルID |
| `CODEX_PIPE_SOCKET` | 既存モードの制御ソケットのパス。既知の接続先だけ指定する |

確認用セッションは一時扱い、読取専用サンドボックス、承認なしで開始し、そのセッションだけ `features.image_generation=true` を指定する。内蔵画像生成ツールで新しい画像を1枚作るよう指示し、コード描画・SVG・外部APIによる代用を禁止する。サーバーからのクライアントツール・承認要求はこのテストでは実装せず、未対応として返す。Codexのユーザー設定やログイン情報は書き換えない。

## ビルド

RAD Studio 37を使い、リポジトリ直下から実行する。

```powershell
& ./Source/Diagnostics/CodexPipeProbe/Build-Probe.ps1
```

専用dprojをMSBuildでDebug/Releaseの両方ビルドする。IDEで `CodexPipeProbe.dproj` を開いてもよい。フォームはコードで生成するためDFMはない。EXE、DCU、ビルドログ、通信ログはGit対象外の `Win64/CodexPipeProbe` 以下に置く。

送信ごとのログはEXE隣の `ProbeRuns/<日時>-<モード>-<ID>/protocol.log`。送受信した入力・回答とエラーを含むためローカルで扱う。大きな画像データはログから省き、通知の保存先・状態・IDを残す。

## 再実行できる確認

```powershell
$exe = './Win64/CodexPipeProbe/Release/CodexPipeProbe.exe'
& $exe --self-test dedicated --result "$PWD/output/validation/20261013-codex-pipe/dedicated.json"
& $exe --self-test existing --result "$PWD/output/validation/20261013-codex-pipe/existing.json"
```

自動確認もフォーム上の同じボタンのClickから開始する。`--prompt-file <UTF-8ファイル>` で入力を変更できる。自分のフォームを表示してPaintBoxのPaintイベントまで確認する。結果JSONには生成・受信・読込・描画それぞれの状態、画像パス・寸法・SHA256、フォーム数、thread/turn ID、ログパスを記録する。PaintBoxと共通の描画関数によるプレビューPNGも保存する。GUIアプリなのでPowerShellで終了を待つ場合は `Start-Process -PassThru -Wait` 等を使う。

## 2026-10-13のテキスト往復の結果（画像対応前）

- 専用モード：実際のモデル応答を受信して成功。「パイプ接続成功」と、別入力「海辺の図書館」を含む日本語の一文の2パターンを確認した。
- 既存モード：標準制御ソケットへの接続で失敗。実際のエラーは `os error 10050`。`initialize` の応答、セッション作成、プロンプト送信には到達していない。デスクトップアプリが終了していると断定する根拠にはしない。
- ディープリンクの公式仕様は入力欄へのプロンプト設定までで、自動送信しない。自動発火に成功した代替経路として扱わない。
- 本編のコード・プロジェクト・作品ファイル・EXEを変更せず確認した。デスクトップ画面に対する物理マウス操作は未実施。ボタンイベントによる実往復とフォームの構成を確認した。

テキスト検証の証跡はローカルの `output/validation/20261013-codex-pipe` と各実行の通信ログ。画像対応の結果は後続の画像検証記録と開発履歴を参照する。

## 2026-10-13の画像生成・表示の結果

専用モードのボタンClickから「青い空と海辺の小さな図書館。絵本風のイラスト。文字は入れない。」を送信。専用Codexが内蔵画像生成ツールを実行し、`imageGeneration` の `status=completed` と `savedPath` をパイプで返した。画像1536×1024、3,330,788バイトを受信し、PNGとして読み込み、表示中フォームのPaintBoxのPaintイベントで描画した。turnも正常完了した。

生成元と受信コピーのSHA256はともに `d806d7329109f82f5a36f6e6ee0d3748ca7b4475334fbf5f2815c2844475b7ce`。結果JSONの `success / transportSuccess / imageGenerated / imageLoaded / imagePainted / windowVisible` はすべてtrue、フォーム数1、出力UIはTPaintBox。PaintBoxと同じ描画関数で保存したプレビューPNGを目視し、指定した海・青空・図書館の画像が表示されることを確認した。プレビューPNGは画面全体のスクリーンショットとは区別する。

この通知には4,441,052文字のBase64も含まれていたため、従来の1行4MB上限を画像用に64MBへ変更した。画像データ本体は通信ログへ保存せず、状態・保存先・IDとデータ長を残した。画像生成は親チャットから別途実行していない。専用Codex自身が生成した画像である。

最終Win64 Debug/Releaseは警告0・エラー0。専用モードの証跡は `output/validation/20261013-codex-pipe/image-generation-result.json`、同 `.preview.png`、結果JSONが指す実行フォルダの `protocol.log / received-image.png`。画像、ログ、JSON、EXEはGit同期対象外。画像対応後の既存接続モードの結果は `image-existing-result.json` に記録する。物理マウスによるボタンクリックは未実施だが、同じボタンイベントから実モデル生成・受信・画面描画まで実行した。

公式資料：[App Server](https://learn.chatgpt.com/docs/app-server)、[CLIコマンド](https://learn.chatgpt.com/docs/cli/reference)、[デスクトップのディープリンク](https://learn.chatgpt.com/docs/app/commands)。この端末のCLIは `0.162.0-alpha.17.2`。既存モードのproxyはこの版の `--help` でも確認した実験的な接続機能であり、将来の互換性は別途確認する。
