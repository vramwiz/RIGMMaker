# 本編のCodex / Dots通信

2026-10-15、独立テストで成功したDots通信を本編へ組み込んだ。既存Codex用のメッセージパイプを残し、Dots用のJSONLパイプを別に持つ。**起動時に選んだ方式だけを待受け、同じアプリで両方を同時に通信させない。**

機械可読な入口は [Dots連携.json](Dots連携.json)。診断アプリ用の資料に加え、本編を操作する際はこちらの資料と実行中アプリのschemaを読む。

## 起動

通常は`RIGMMaker.exe`をそのまま起動する。引数は不要。Dotsがホスト上で起動操作できる場合、次の起動器も引数なしで同じ通常EXEを起動する。

```powershell
& ./制作支援/パイプ/Start-RigmCommunication.ps1
```

起動器の既定EXEはプロジェクト直下の通常版 `RIGMMaker.exe`。2026-10-16以降は、このEXEを引数なしで通常起動するだけでDots用JSONLパイプを開く。特別な起動ファイルや起動引数を利用者へ要求しない。Codexからもこのパイプで同じ共通命令を使用できる。旧Codex受信方式が必要な場合だけ `--communication-mode codex` で互換モードを指定できる。ウィンドウのタイトルにも選択方式を表示する。

方式はその起動中固定。切り替える際は作品を保存して終了し、反対の方式で起動する。起動器は既存プロセスを強制終了しない。別インスタンスで同じ作品を同時操作する仕組みは今回の対象にしない。

`-Exe '<絶対パス>'` で対象EXE、`-DataRoot` と `-SettingsDirectory` で試験用のデータ・設定を分離できる。指定を省略した場合は本編の既存設定に従う。

## 方式ごとの仕様

| 項目 | Codex | Dots |
| --- | --- | --- |
| 受信パイプ | 既存workspace・キャラ・PSD用 | 新しいworkspace用の1本 |
| Windowsパイプモード | message | byte |
| フレーム | 従来の1メッセージ | UTF-8 JSON + LF、1接続1要求1応答 |
| 要求識別 | `schemaVersion=1`, `requestId` | `version=1`, `id`, `accessToken` |
| 接続情報 | `Exchange/workspace-<PID>.json`、既存の個別編集接続情報 | `Exchange/dots-<PID>-<GUID>.json` |
| AppContainer | 既存方式 | Low / 変動SID対応、同一ユーザー確認とトークン必須 |
| 命令の実処理 | 既存Workspace・Session | 同じWorkspace・Session |

Dotsモードでキャラ編集・PSD編集の画面を開いても、旧専用パイプの待受けと接続情報公開は行わない。操作はDots共通パイプから `legacy-*` / `psd-*` の既存振分けを通す。CodexモードではDots用パイプと接続情報は作らない。

既存のボタンによる専用Codex実行は内部処理として維持する。DotsからAI処理を開始した場合も専用Codexとの匿名パイプを内部で使い、旧Codex受信パイプを同時に開くことはない。

## Dotsへの操作資料

本編の接続情報は `protocol=rigm-maker-dots/1`。診断アプリの `dots-codex-probe/1` とは区別する。接続情報を読む際は対象PID・選択方式を確認し、古い接続情報を再利用しない。

```powershell
$sender = './制作支援/パイプ/Send-RigmDotsCommand.ps1'
$connection = '<本編データルート/Exchange/dots-PID-GUID.jsonの絶対パス>'
& $sender -ConnectionFile $connection -Command ping
& $sender -ConnectionFile $connection -Command app-status
& $sender -ConnectionFile $connection -Command schema
& $sender -ConnectionFile $connection -Command app-script-status
```

送信器は接続情報からトークンを自動で付ける。Dotsが直接パイプを開く場合は全要求へ接続情報の `accessToken` を含める。受信側はトークンをログ・status・schemaへ返さない。

```json
{"version":1,"id":"dots-001","accessToken":"<connection.accessToken>","command":"app-script-status","args":{}}
```

成功応答は `{"version":1,"id":"dots-001","ok":true,"data":{...}}`。失敗は `ok=false` と `error.code/message`。1フレームはLF込み8MiB、1回の読み書き待ちは15秒。応答をLFまで読んだら接続を閉じ、次の要求では再接続する。

再送は同じid・同じ要求で行う。直近256件・応答合計16Mi文字までのキャッシュ中は、変更・保存を二重に実行しない。違う要求で同じidを使うと `id_conflict`。ポーリングや次の操作では新しいidを使う。再起動やキャッシュの追い出しをまたぐ再送保証はない。

既存の命令名は変えない。台本は `app-script-*`、動画は `movie-*`、PSDは `psd-*`、旧キャラ編集は `legacy-*`。編集前には現在のprojectId / revision / requestIdを取得する。Dots送信器は古いrevisionを自動補正しない。古い値での編集は既存の検査で拒否される。工程・作品・人間の確定条件も共通処理が判定する。

## 画像の受渡し

Dots側の画像を一時配置する場合:

```powershell
$payload = @{base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes('<画像の絶対パス>'))}
$image = & $sender -ConnectionFile $connection -Command image.put `
    -ArgsJson ($payload | ConvertTo-Json -Compress)
```

`image.put` はPNG/JPEG/BMP、4MiBまで。本編の画像ヘッダー・CRC・画素・寸法検査を通し、`Exchange/Dots/<起動ID>/Images/` に新しいGUID名で保存する。`imageId`, `path`, `bytes`, `width`, `height`, `sha256` を返す。任意の保存先は受け付けない。

`image.get` へその `imageId` を渡すと同じ情報とBase64を取得できる。ファイルパスを指定して任意のファイルを読む命令ではない。画像IDは現在の起動中だけ有効。既存の画像分割転送コマンド（`app-script-image-transfer-*`, `movie-image-transfer-*`）も引き続き使える。

一時配置しただけでは作品へ採用しない。`app-script-request-scene-image` 等で現在の画像要求を作り、要求の作品ID・sceneId・revision・requestIdとSHA256を指定して、既存の `app-script-adopt-scene-image` または画像転送のadopt操作を使う。画像の最終確定は人間が行い、保存も既存の操作を使う。

## 既存のAI処理を外部から操作する

| command | 操作 |
| --- | --- |
| `app-script-ai-status` | 表情・画像それぞれのbusy、message、logPath。作品があればprojectId/revision |
| `app-script-ai-expressions-start` | 第11段階で既存のAI表情一括判定を開始 |
| `app-script-ai-expressions-cancel` | 表情判定の中止を要求 |
| `app-script-ai-images-start` | 第16段階で既存の画像生成を開始。任意のsceneId、空なら対象画像を順次生成 |
| `app-script-ai-images-cancel` | 画像生成の中止を要求 |

開始・中止には現在のprojectIdとrevisionを指定する。GUIと同じ工程・要求の検査を通し、表情判定と画像生成も同時に開始しない。状態取得は新しいidでポーリングする。`busy=false` だけを生成成功とは判定せず、messageと既存casting/scenes取得で結果を確認する。画像生成は自動確定しない。これらの共通命令は既存Codexパイプからも利用できる。

## ビルド・検証

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Build-RigmIntegration.ps1
& ./Source/Diagnostics/DotsCodexProbe/Test-RigmIntegration.ps1 `
    -Exe "$PWD/Win64/RigmCommunication/Release/RIGMMaker.exe" `
    -OutDir "$PWD/output/validation/dots-integration-new"
```

このスクリプトは本編dprojと同じ検索パスを使うコンパイル専用で、DLLを配置しない。FFmpeg DLLは2026-10-15に復元済み。通常の本編MSBuildの`DeployFFmpegRuntime`でEXE隣へ配置する。今回の`Win64/RigmAutomation`版はDebug/ReleaseともMSBuild・DLL配置に成功し、MP4出力の検証も成功した。詳細は [自動制作の実装状況](../../自動制作/実装状況.md) を参照する。

## コピー元の確認

`app-auto-sources`に`scriptType: manga-introduction`または`anime-review`を指定し、候補と除外理由、種類別の最新`selected`を取得する。一覧の`projectId`と同じ`scriptType`を`app-auto-source-check`へ渡すと、その台本の候補可否`eligible`、最新選択対象`selected`、GUIと同じコピー処理のメモリ上検証結果`copyValidated`を返す。`found=false`は一覧にないID。検証失敗時は`copyError`を返す。`saved=false`で、検査から台本を保存・作成しない。

入力中の台本はコピー処理自体に問題がなくても`eligible=false`になる。`copyValidated=true`はキャラ・レイアウト・VOICEVOX等の制作設定が揃っている保証ではない。

## 全自動制作

`app-auto-start {text}`で最新の既存台本をコピーし、音声・表情・背景／シーン／実キャラ参照サムネイルの生成、MP4、投稿用TXTまで実行する。`app-auto-status {jobId,afterSequence}`で段階応答と成果物を取得し、`app-auto-cancel {jobId}`で中止する。自動制作ジョブは試聴・画像の目視確認を待たず、整合性検査後に自動採用する。通常の単独画像操作の確認とは区別する。詳細は [自動制作のルール](../../自動制作/note.md)、[起動と実装範囲](../../自動制作/実装状況.md)、[機械読取ルール](../../自動制作/パイプ仕様.json) を参照する。最新の実装EXEを起動例の`-Exe`で明示する。

本編の隔離データ・設定を用いたDebug/Release試験は `output/validation/20261015-dots-integration/` に記録する。統合試験はパイプ経由の作品作成・題名変更・保存・古い版の拒否・画像往復・実AppContainer接続を確認する。AI命令の検査と状態取得も確認するが、今回の統合試験から実モデルの画像生成は行わない。

## 既に成功している範囲

独立テストでは、利用者が提示したDots画面の報告でテキスト往復、画像生成・パイプ取得、SHA256一致、18要求の通信エラーなしを確認した。本編への統合とこの独立試験の成功は別の証拠として扱う。リモートから停止中アプリを起動する常駐機構は、この組込みには含めない。
