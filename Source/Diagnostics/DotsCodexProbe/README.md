# Dots / Codex 通信試験

本編と独立したDelphi VCLの1フォームアプリ。Dotsの実装を前提とせず、Dotsが対応できるか問い合わせるための通信仕様と送信器を同梱する。まずテキスト、次に画像入力・画像生成・転送を試す。

## 入口

- [通信仕様](PROTOCOL.md)
- [Dotsへ渡す問い合わせ文](DOTS-QUESTION.md)
- [機械可読な接続・操作情報](protocol.json)
- [送受信JSON例](examples.json)
- [要求のJSON Schema](request.schema.json)

ここでいう学習資料は、実行時にDotsが読む接続・操作手順であり、モデルの追加学習ではない。Dotsへの問い合わせ・送信はこのプロジェクトから自動では行わない。

## ビルドと起動

リポジトリのルートでPowerShell 7から実行する。RAD Studio 37が必要。

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Build-Probe.ps1
& ./Win64/DotsCodexProbe/Release/DotsCodexProbe.exe
```

IDEでは `DotsCodexProbe.dproj` を開く。フォームはコードで作るためDFMはない。本編のEXE・設定・作品・既存パイプを変更しない。出力は `Win64/DotsCodexProbe/Debug` と `Release`。

起動時に通信は待受けるが、Codexへの送信は開始しない。フォーム上部に表示される `connection.json` の絶対パスを送信器に渡す。インスタンスごとに名前付きパイプを分ける。接続先を「最新のファイル」と推測せず、対象の接続情報を明示する。

作業先は既定で `%LOCALAPPDATA%/RIGMMaker/DotsCodexProbe/<PID>-<GUID>/`。必要なら `--state-dir "絶対パス"` を起動引数に指定する。既存の `connection.json` があるフォルダは拒否する。異常終了時の接続情報は残るため、新しいフォルダを使う。

フォームでの操作:

1. 上の入力欄へテキストを入力し「テキストをCodexへ」。左下に結果JSONを表示する。
2. 画像パス欄にPNG/JPEG/BMPの絶対パスを入力して「画像を読み込む」。右下で確認する。
3. 「参照画像をCodexへ」で、直近の読込画像を添付して質問する。
4. 入力欄に画像要望を書き「Codexで画像生成」。生成画像を受信・検査して表示する。
5. 実行中は「実行中ジョブを中止」で所有する専用Codexだけを止められる。

## タスクバー修正版の別出力と無音検査

既存プロセスとEXEを保護して別フォルダへビルドする場合:

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Build-Probe.ps1 -OutputRoot "$PWD/Win64/DotsCodexProbe/TaskbarFix-20261015"
```

メインフォームはOwnerなしのトップレベルウィンドウとして作成し、`WS_EX_APPWINDOW` を設定する。`CreateNew` による早期ハンドル作成でも、非表示Applicationウィンドウの所有下にならないようにしている。`MainFormOnTaskbar=True` も維持する。

ビルド後は新しい未使用の作業フォルダで、Owner・ウィンドウスタイルを無音検査できる。Codex呼び出しやパイプへの要求送信は行わず、初回作成・ハンドル再作成後をJSONへ記録して終了する。

```powershell
$exe = "$PWD/Win64/DotsCodexProbe/TaskbarFix-20261015/Release/DotsCodexProbe.exe"
$checkRoot = Join-Path $PWD ('output/validation/taskbar-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $checkRoot | Out-Null
$check = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -Wait -ArgumentList ('--state-dir "' + (Join-Path $checkRoot 'state') + '" --window-check "' + (Join-Path $checkRoot 'window.json') + '"')
$check.ExitCode
Get-Content -LiteralPath (Join-Path $checkRoot 'window.json')
```

終了コード0・JSONの `passed=true` がネイティブ検査の成功条件。Windowsシェル上のタスクバーボタンの目視確認とは別の検査なので、通常起動した実画面も確認する。通常起動時には `--window-check` を付けない。既存アプリの重複起動を避け、必要ならユーザーが既存ウィンドウを閉じてから新EXEを通常起動する。

2026-10-15の追加作業ではビルド環境のレジストリアクセス拒否により修正版EXEは未作成。この無音検査と通常起動の実画面確認は未実行。詳細は `VALIDATION.md` を参照。

## Dots相当の送信例

```powershell
$sender = './Source/Diagnostics/DotsCodexProbe/Send-ProbeCommand.ps1'
$connection = '<フォームに表示されたconnection.jsonの絶対パス>'
& $sender -ConnectionFile $connection -Command ping
& $sender -ConnectionFile $connection -Command echo -ArgsJson '{"text":"Dotsからこんにちは"}'
& $sender -ConnectionFile $connection -Command text.save -ArgsJson '{"text":"クライアントへの配置テスト"}'

$started = & $sender -ConnectionFile $connection -Command codex.start `
    -ArgsJson '{"mode":"text","text":"短い日本語で挨拶してください"}'
if (-not $started.ok) { throw $started.error.message }
$jobId = $started.data.jobId
# runningの間は新しい要求idで繰り返す。送信器は毎回GUIDを発行する。
& $sender -ConnectionFile $connection -Command job.get `
    -ArgsJson (@{jobId=$jobId} | ConvertTo-Json -Compress)
```

画像の送受信:

```powershell
$imagePath = '<送信するPNGの絶対パス>'
$payload = @{base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($imagePath))}
$uploaded = & $sender -ConnectionFile $connection -Command image.put `
    -ArgsJson ($payload | ConvertTo-Json -Compress)
if (-not $uploaded.ok) { throw $uploaded.error.message }
$download = & $sender -ConnectionFile $connection -Command image.get `
    -ArgsJson (@{imageId=$uploaded.data.imageId} | ConvertTo-Json -Compress)

$vision = @{mode='text';text='この画像の色を説明してください';imageId=$uploaded.data.imageId}
& $sender -ConnectionFile $connection -Command codex.start `
    -ArgsJson ($vision | ConvertTo-Json -Compress)
```

## Codex接続

アプリが `codex app-server --listen stdio://` を非表示で起動し、匿名パイプでJSONLを送受信する。`initialize` → `initialized` → `thread/start` → `turn/start` → 通知 → `turn/completed`。各要求は新しい専用の一時セッションで、このデスクトップチャットには送らない。テキストは通常の回答、画像入力は `localImage`、画像生成は内蔵生成ツールの完了通知を使う。[OpenAI公式仕様](https://learn.chatgpt.com/docs/app-server)

既存のCodexログインを利用する。`CODEX_PIPE_EXE`、PATH、`%LOCALAPPDATA%/OpenAI/Codex/bin/*/codex.exe` の順に探す。モデルは利用者の設定に従い、`CODEX_PIPE_MODEL` で指定可能。APIキー入力や別のHTTP Responses API接続はこの試験では実装していない。API接続はCodex app-serverのRPC APIを指す。

画像生成の可否はCodexのバージョン・モデル・アカウントのツール提供状況に依存する。正式な `imageGeneration` 完了通知とターンの正常終了を必要とし、画像パスを書いた文章だけで成功にはしない。テキストは最大5分、画像生成は最大10分、各RPC応答待ちは30秒。画像生成元のファイルは保持し、試験の受渡し上限4MiBを超える場合はジョブを失敗として記録する。

本編の `RigmCodexClient.pas` を基にした専用コピー `DotsCodexTransport.pas` を使う。試験用に通常テキスト回答と参照画像を追加した。本編の通信用ユニットは変更しない。

## 再検証

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Test-Probe.ps1 -OutDir "$PWD/output/validation/dots-new-offline"
& ./Source/Diagnostics/DotsCodexProbe/Test-Probe.ps1 -OutDir "$PWD/output/validation/dots-new-text" -LiveText
& ./Source/Diagnostics/DotsCodexProbe/Test-Probe.ps1 -OutDir "$PWD/output/validation/dots-new-image" -LiveImage
```

出力先は未使用のフォルダを指定する。Liveを指定したときだけ本物のCodexを呼ぶ。実画像・ログ・EXE・DCU・検証結果はGit同期対象外。通常の試験ログは作業先の `pipe.log`、Codexの送受信ログは `Jobs/<jobId>/protocol.log`、最終結果は同じ場所の `result.json`。Codexログには送信テキストが含まれる。

## リモート化の境界

この版は同じWindows PC・同じユーザーの名前付きパイプに限定する。パイプだけでは停止中のPCやアプリを起動できない。リモートDotsには、クライアント側で常駐して起動と転送を担当するエージェントなどが別途必要。接続経路、常駐可否、認証、起動・完了通知はDots側へ問い合わせる。この版にネットワーク待受けや任意コマンド実行は含めない。

## 接続時のアクセス拒否を調べる

### Low整合性・変動SIDのAppContainerから接続する試験モード

Dots側からLow整合性のAppContainerであることと、AppContainer SIDが変動することが確認されたため、固定SIDを使わないモードを追加した。通常起動では従来の同一ユーザー用ACLを使う。AppContainer試験をするときは次で新しいフォームを起動する。

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Start-AppContainerProbe.ps1
```

この起動器は `Win64/DotsCodexProbe/AppContainerFix/Release/DotsCodexProbe.exe --allow-appcontainer` を起動する。起動した**新しいフォーム**に表示される `connection.json` をDotsへ渡す。以前の接続情報・パイプ名・接続トークンは使わない。既に起動している通常モードのEXEは、この起動器では変更・終了しない。

このモードはパイプにAppContainerグループの読み書き権限とLow必須ラベルを設定する。パッケージ個別のSIDを固定しない。リモート接続拒否は維持する。受信バイトの送信者をWindowsのパイプ偽装APIで確認し、起動したユーザーSIDと一致する場合だけ要求処理へ進める。さらに起動ごとのランダムな接続トークンを必須にする。

`connection.json` に `accessMode=appcontainer-test`, `requiresAccessToken=true`, `accessToken` が追加される。Dotsは**全要求のルート**へその `accessToken` を付ける。同梱送信器は自動で付ける。トークンをログや共有資料へ貼り付けない。トークンなし・不一致では、パイプOpenが成功しても `unauthorized` として命令を実行しない。

```json
{"version":1,"id":"dots-ping-001","accessToken":"<今回のconnection.jsonのaccessToken>","command":"ping","args":{}}
```

このモードではパイプOpen自体を他のAppContainerも試せるため、利用者・トークンの照合を必ず通す。AppContainerからは通常のプロセス情報照会が拒否される場合もあるので、同梱送信器はこのモードでのPID/プロセス名照会を必須にせず、パイプの応答で接続を確認する。大容量転送の分割など、他の仕様は変更しない。

再ビルドと実AppContainer試験:

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Build-Probe.ps1 -OutputRoot "$PWD/Win64/DotsCodexProbe/AppContainerFix"
& ./Source/Diagnostics/DotsCodexProbe/Test-AppContainerAccess.ps1 `
    -Exe "$PWD/Win64/DotsCodexProbe/AppContainerFix/Release/DotsCodexProbe.exe" `
    -OutDir "$PWD/output/validation/dots-new-appcontainer"
```

Windows AppContainerの二重のアクセス検査と名前付きパイプの権限は [MicrosoftのAppContainer資料](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer) と [名前付きパイプのアクセス権](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights) を参照。試験は一時AppContainerプロファイルを作り、所有する試験プロセスの終了後にプロファイルを削除する。読み取りACLを加える範囲は新規の検証出力フォルダだけ。診断・通信結果は親が保存し、試験クライアントへの任意フォルダ書込み権限は加えない。

### 診断情報

`0x80070005` はパイプを開く段階のアクセス拒否。同じPCでも、別ユーザー・制限付きトークン・低い整合性レベル・AppContainerなどで通常の端末と接続可否が変わる。接続情報JSONを読めることだけではパイプへのアクセス許可は確認できない。権限の異なる通常端末で試すだけでは、Dots側の制限を切り分けられない。

**失敗したDots側と同じ実行環境から**、PowerShell 7で次を実行して出力JSONを確認する。

```powershell
& ./Source/Diagnostics/DotsCodexProbe/Diagnose-PipeAccess.ps1 `
    -ConnectionFile '<起動中フォームに表示されるconnection.jsonの絶対パス>'
```

診断は接続情報、対象PIDの存否、送信側のユーザーSID・整合性SID・制限SID・AppContainer情報、Windows APIによる接続エラー、接続可能ならpingの結果を出力する。認証トークンやAPIキーは取得しない。`-OutFile '<絶対パス>'` でJSONを保存できる。

- `nativeOpenWin32Error=0` と `pingSucceeded=true`: その実行環境から接続・往復可能。
- `nativeOpenWin32Error=5`: アクセス制御で拒否。ユーザーSID・restrictedSids・integritySid・AppContainer情報を通常端末の結果と比較する。
- `nativeOpenWin32Error=2`: その名前のパイプが存在しない。古い接続情報や別の実行環境を確認する。
- `nativeOpenWin32Error=231`: 別のクライアントが接続中。接続終了後に再試行する。

送信器は通常モードで終了済みPIDの接続情報を `stale_connection` として拒否する。アクセス拒否は診断スクリプトへの案内を返す。通常モードの起動ユーザーSIDだけを許可するACLは維持する。
