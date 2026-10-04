# PNGを共通パイプで送信してシーンへ採用する

2026-10-04実装。既存の共通コマンドパイプ、接続JSON、`Send-RigmCommand.ps1`を使います。公開ポートや新しいリスナーは追加していません。

## 送信スクリプト

PowerShell 7で、対象アプリの接続JSONと`movie-project`にある既存シーンIDを指定します。

```powershell
$connection = '<対象アプリの接続JSONのWindowsパス>'
$scene = '<movie-projectで確認したscene id>'
& .\Send-RigmImage.ps1 -ConnectionFile $connection -Path 'C:\Images\scene.png' -SceneId $scene -StateFile '.\transfer-state.json'
```

標準動作はPNG送信、検証完了待機、シーン採用です。採用はUndo/Redo可能な1回の編集となり、プロジェクトは未保存になります。確認ダイアログや自動保存はありません。保存する場合だけ`-SaveProject`を指定するか、別途`movie-save`を実行します。

`-NoAdopt`は検証済み資産まで受信して採用を保留します。`-NoAdopt`と`-SaveProject`の併用は拒否します。編集リースを取得している場合は`-EditToken`にそのトークンを渡します。

同じアプリの同じプロジェクトで中断した転送は、状態ファイルの`transferId`を使って再開できます。

```powershell
$state = Get-Content -LiteralPath '.\transfer-state.json' -Raw | ConvertFrom-Json
& .\Send-RigmImage.ps1 -ConnectionFile $connection -Path 'C:\Images\scene.png' -SceneId $scene -TransferId $state.transferId -StateFile '.\transfer-state.json'
```

送信元のSHA-256、サイズ、シーンIDが一致する場合だけ再開します。元ファイルは送信中の書換えから保護します。受信済みオフセットから進み、応答を取り逃した場合は受信状態を照合して同じチャンクを再送します。再送回数と完了待機時間には上限があります。送信失敗時は再開できるよう自動キャンセルしません。不要になった転送は明示的にキャンセルします。

## コマンド

すべて共通パイプの`movie-`接頭辞付きコマンドです。`begin`と`adopt`には最新の`projectId`と`revision`が必要です。通常の送信スクリプトが現在値を補います。編集リースや処理中の編集制限も適用されます。

| コマンド | argsの固有項目 | 動作 |
| --- | --- | --- |
| `movie-image-transfer-begin` | `sceneId`, `byteCount`, `sha256`, `mimeType="image/png"` | 転送IDを発行する。シーンを変更しない |
| `movie-image-transfer-chunk` | `transferId`, `offset`, `data` | `data`は改行・空白のない正規Base64。順序通り受信する |
| `movie-image-transfer-finish` | `transferId` | 全バイト受理後に非同期の検証・資産配置を開始する |
| `movie-image-transfer-status` | `transferId` | 状態・進捗・エラー・検証済みパスを取得する |
| `movie-image-transfer-cancel` | `transferId` | 非同期で中止する。採用しない |
| `movie-image-transfer-adopt` | `transferId` | 検証済み画像を開始時のシーンへ1回だけ採用する |

`offset`は0始まりで16,384の倍数です。各チャンクは16,384バイト、最後だけ残りバイト数と一致させます。`nextOffset`を使って次を送ります。同一オフセット・同一内容の再送は二重計上しません。内容の異なる再送、欠落、順序違い、整数でないオフセットは拒否します。

```powershell
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command movie-image-transfer-status -ArgsJson (@{transferId=$state.transferId} | ConvertTo-Json -Compress)
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command movie-image-transfer-cancel -ArgsJson (@{transferId=$state.transferId} | ConvertTo-Json -Compress)
```

## 制限と保存先

- 静止PNG、圧縮ファイル1〜32MiB。1辺8,192px以下、合計16,777,216画素以下。APNGは拒否します。
- 元のプロトコル上限30,000文字・UTF-8 60,000バイトを保持します。16KiBチャンクでその両方に収まります。
- ワーカーは同時2転送まで、待ち行列は各8チャンク（128KiB）まで。混雑時は同じオフセットを再送します。
- 受信中に120秒間データ送信・完了要求がなければ中止し、一時ファイルを除去します。状態取得だけでは延長しません。
- 未採用のready転送を含め保持記録は最大8件。完了・失敗・キャンセル済み記録は次のbegin時に整理されます。転送IDは同じ起動セッションだけで有効です。

保存済みプロジェクトでは、`<プロジェクトの親フォルダ>\<プロジェクト名>.assets\ReceivedImages\<sha256>.png`へ配置します。未保存プロジェクトでは、そのアプリの設定ルートの`Projects\ReceivedImages\<projectIdのハッシュ>\`へ置きます。プロジェクト自体は作成・保存しません。

送信側のファイル名や保存先パスは受け付けません。保存先はアプリが決定します。ディレクトリのリパースポイントを拒否し、配置中はディレクトリを保持します。既存の同名資産はハッシュ一致の場合だけ再利用し、破損・不一致なら上書きしません。

受信・ハッシュ・PNG検証・一時配置はワーカーで実行します。全体のSHA-256、PNG構造・CRC・寸法を検証後、同じ保存先内の一時ファイルを名前変更して公開します。検証済みのready資産は採用またはキャンセルまで書換え・置換を防ぎ、採用時にはファイルの同一性も確認します。

`acceptedBytes`はチャンクが待ち行列に入った量、`receivedBytes`はファイルへ書いた量です。`ready`になるまで採用できません。プロジェクトを開き直すと未完了転送をキャンセルし、別プロジェクトや別の保存場所へ転送IDを流用できません。ready後のキャンセルでは検証済み資産は残り、`cancelRequested=true`になって採用できなくなります。失敗・中止ではシーンを変更しません。

## 生成画像がWindowsへ到達する経路との区別

この機能で確認する経路は **Windows上のPNGバイト → 名前付きパイプ → アプリの資産 → シーン** です。`-Path`は送信側Windows環境に実在するファイルです。URL取得や親スレッド側のファイル転送は実装していません。

既存PSDの成功例は、Windowsにある生成PNGをジョブの`images`へコピーし、`result.json`を作ってパイプのimportを送る方式です。保存資料はそのローカル配置を確認できますが、生成ツールの出力が最初にWindowsへ届いた操作は未特定です。生成側の出力・直後のファイル配置操作を確認するか、現在のWindows環境へ正式に取り込める生成結果を用意する必要があります。Libraryの保護メタデータを変更・回避する処理は加えていません。
