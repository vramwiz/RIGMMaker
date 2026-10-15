# Dots通信方式 — RIGMMaker / DotsCodexProbe

本編RIGMMakerへ組み込んだ通信を使う場合は、[本編のCodex／Dots連携](制作支援/パイプ/Dots連携.md)と[機械可読情報](制作支援/パイプ/Dots連携.json)を読む。本書の以降は独立診断アプリ向けであり、本編とは接続情報・protocol・操作コマンドが異なる。

更新日: 2026-10-15。これはDotsが実行時に読む操作資料であり、モデルの追加学習ではない。RIGMMaker内の独立した診断アプリを対象とする。他プロジェクトや本編の設定・作品は変更しない。

## 1. 目的と入口

次の実経路で、短いテキスト回答と画像の生成・返却を確認する。

```text
DotsのWindows側実行環境
  → Windows名前付きパイプ
  → DotsCodexProbe.exe
  → 専用の codex app-server --listen stdio://
  → Codexの回答・画像
  → アプリのローカル保存
  → 名前付きパイプの応答
```

接続先のAPIはCodex app-serverのRPC API。既存のCodexログインを利用し、要求ごとに専用のephemeralセッションを作る。開いているデスクトップチャットへの送信、HTTP Responses APIへの直接接続ではない。新しい認証情報の設定や契約変更が必要になったら停止して報告する。

作業開始時は、この文書に加えて次の現行ファイルを読む。将来の更新では実装との整合を確認し、過去の検証値より現行仕様を優先する。

| 資料 | 内容 |
| --- | --- |
| [README](Source/Diagnostics/DotsCodexProbe/README.md) | 起動、実行環境、試験モード、診断 |
| [PROTOCOL](Source/Diagnostics/DotsCodexProbe/PROTOCOL.md) | フレーム、認証、コマンド、状態、上限 |
| [DOTS-QUESTION](Source/Diagnostics/DotsCodexProbe/DOTS-QUESTION.md) | Dots側への追試依頼と責務 |
| [VALIDATION](Source/Diagnostics/DotsCodexProbe/VALIDATION.md) | 開発側の過去検証。今回の実測と混同しない |
| [protocol.json](Source/Diagnostics/DotsCodexProbe/protocol.json) / [request.schema.json](Source/Diagnostics/DotsCodexProbe/request.schema.json) | 機械可読仕様 |
| [examples.json](Source/Diagnostics/DotsCodexProbe/examples.json) | 通常モードの例。新モードでは接続トークンの追加が必要 |
| [送信器](Source/Diagnostics/DotsCodexProbe/Send-ProbeCommand.ps1) / [パイプ実装](Source/Diagnostics/DotsCodexProbe/DotsProbePipe.pas) / [フォーム](Source/Diagnostics/DotsCodexProbe/DotsProbeForm.pas) / [Codex通信](Source/Diagnostics/DotsCodexProbe/DotsCodexTransport.pas) | 実際に使える引数と処理 |

## 2. 新方式の意味と安全上の境界

「UIDを使わない」は、**実行ごとに変わる個別AppContainer SIDを固定登録しない**という意味。同一ユーザーSIDの確認、要求の `id`、ジョブID、画像IDをなくした方式ではない。

| モード | 接続情報と実装 |
| --- | --- |
| 通常モード | 起動ユーザーSIDだけを許可する従来のパイプACL。通常版Release EXEを新モードと取り違えない |
| `appcontainer-test` | `--allow-appcontainer` 付き起動。AppContainer / Restricted AppContainerグループへの読み書きACEとLow整合性ラベルを当該パイプに設定。受信後のWindowsクライアント偽装で同一ユーザーSIDを確認し、さらに起動ごとのランダムな接続トークンを照合 |

新モードの `connection.json` は `accessMode="appcontainer-test"`、`requiresAccessToken=true`、`accessToken` を持つ。**全要求のルート**にその起動の `accessToken` を付ける。同梱送信器が自動で付与するので、下記例では値を手動で扱わない。`accessToken` は `args` 内ではない。

新モードでも同一PC向けであり、リモートパイプ接続拒否は維持される。他のAppContainerもパイプOpenを試せる範囲になるため、ユーザー確認とトークン照合が必要。接続情報ファイルを丸ごと表示・共有・ログ保存しない。トークンを文書、チャット、Git、Codexへのプロンプトへ入れない。

これはユーザーが用意した試験用のセキュリティ実装の説明である。Dotsはアクセス拒否への対応としてACL、許可SID、必須ラベル、OS設定を変更したり、昇格、サンドボックス解除、別経路接続を自動実行したりしない。拒否時はその経路を停止して、拒否箇所と必要な判断を利用者へ報告する。

## 3. 現行アプリと接続情報を特定する

1. 利用者が今操作しているフォーム上部の `connection.json` 絶対パスを取得する。既存アプリは勝手に閉じず、重複起動しない。
2. 新モードなら上記モード値・トークン必須フラグを確認する。以前の通常モードの接続情報を流用しない。
3. フォルダやパイプ名のPIDは対象確認の補助情報。**この文書や過去ログの固定PID・SID・GUID・パイプ名・接続トークンを再利用しない。**
4. 接続情報の存在や更新日時だけでは稼働証明にならない。起動中フォームとの対応を確認し、最後は `ping/pong` で確認する。「一番新しいファイル」を自動選択しない。複数候補や対応不明なら利用者に正しいパスを確認する。

既定保存先は、**アプリを起動したWindowsユーザーの** `%LOCALAPPDATA%\RIGMMaker\DotsCodexProbe\<PID>-<GUID>\connection.json`。`--state-dir` を指定した場合はそのフォルダ。AppContainer側の `$env:LOCALAPPDATA` は別の場所へリダイレクトされることがあるので、Dots自身の環境変数からサーバー保存先を決めない。

フォームのパスを取得できないときの候補一覧は、利用者が確認した通常Windows側の保存先を指定し、秘密値を表示せず読み取る。以下は候補を列挙するだけで接続しない。

```powershell
$stateRoot = '<利用者が確認したアプリ側のDotsCodexProbe保存先の絶対パス>'
Get-ChildItem -LiteralPath $stateRoot -Directory | ForEach-Object {
    $candidate = Join-Path $_.FullName 'connection.json'
    if (Test-Path -LiteralPath $candidate) {
        $metadata = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
        [pscustomobject]@{
            connectionFile = $candidate
            processId = $metadata.processId
            pipeName = $metadata.pipeName
            protocol = $metadata.protocol
            accessMode = $metadata.accessMode
            requiresAccessToken = $metadata.requiresAccessToken
        }
    }
}
```

### 隔離環境での起動確認の限界

Dots側はAppContainer・Low整合性で動作し、通常アプリの `Get-Process` や `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` が見えない／拒否される場合がある。診断JSONの `serverProcessExists=false` だけで「終了している」と断定しない。EXEパスや実行ユーザーを照合できない場合は未確認と記録する。

現行送信器は `appcontainer-test` の場合、PID/プロセス名照会を必須とせずパイプ応答で確認する。通常モードでは照会結果により `stale_connection` を返すため、隔離環境ではそのメッセージにも上記の限界がある。

未起動と確認され、新モードの利用について利用者が明示的に判断した場合の起動入口は [Start-AppContainerProbe.ps1](Source/Diagnostics/DotsCodexProbe/Start-AppContainerProbe.ps1)。既定の対象は `Win64/DotsCodexProbe/AppContainerFix/Release/DotsCodexProbe.exe --allow-appcontainer`。利用者が通常Windows側から起動し、新しいフォームのパスを渡す。Dotsが拒否回避のためにこの起動を自動実行する手順にはしない。EXEがない／起動できないときも停止して報告し、自動ビルド・置換は行わない。

## 4. PowerShell 7の準備と基本往復

以下の例は**同じWindows PC上の、実際に通信するDots実行環境**で、利用者が通信試験を依頼したときに順に実行する。山括弧付きのパスを現行値へ置き換える。関数はこの文書内の補助関数で、アプリの追加APIではない。

```powershell
$ErrorActionPreference = 'Stop'
$projectRoot = 'D:\DelphiProg\MyApp\RIGMMaker'
$probeDir = Join-Path $projectRoot 'Source\Diagnostics\DotsCodexProbe'
$sender = Join-Path $probeDir 'Send-ProbeCommand.ps1'
$connection = '<起動中フォームに表示されたconnection.jsonの絶対パス>'
$discovery = Get-Content -LiteralPath $connection -Raw -Encoding UTF8 | ConvertFrom-Json
if ($discovery.protocol -ne 'dots-codex-probe/1') { throw 'Unsupported protocol' }
if ($discovery.accessMode -ne 'appcontainer-test' -or
    -not $discovery.requiresAccessToken -or
    [string]::IsNullOrWhiteSpace($discovery.accessToken)) {
    throw '今回の新方式の接続情報ではありません。対象フォームを確認してください。'
}
# $discoveryそのものは出力・保存しない。

function Invoke-Probe {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [hashtable]$Arguments = @{},
        [string]$Id = ([guid]::NewGuid().ToString())
    )
    $response = & $sender -ConnectionFile $connection -Command $Command `
        -ArgsJson ($Arguments | ConvertTo-Json -Depth 20 -Compress) -RequestId $Id
    if (-not $response.ok) {
        throw ($response.error.code + ': ' + $response.error.message)
    }
    return $response
}

$ping = Invoke-Probe -Command 'ping'
if ($ping.data.message -ne 'pong' -or $ping.data.protocol -ne 'dots-codex-probe/1') {
    throw 'Unexpected ping response'
}
$ping
$message = "Dotsからこんにちは。`n2行目です。😀"
$echo = Invoke-Probe -Command 'echo' -Arguments @{text=$message}
if ($echo.data.text -cne $message) { throw 'echo mismatch' }
$saved = Invoke-Probe -Command 'text.save' -Arguments @{text=$message}
# 同じWindows側でその保存先を読める場合のみ、実ファイルを照合する。
$savedText = Get-Content -LiteralPath $saved.data.path -Raw -Encoding UTF8
if ($savedText -cne $message) { throw 'saved text mismatch' }
```

ファイル照会が拒否された場合はその照会を停止し、「パイプ応答成功／ファイル読取未確認」を分ける。ファイル権限を変更しない。

送信器の実引数は `-ConnectionFile`、`-Command`、`-ArgsJson`、`-RequestId`、`-TimeoutMs`、`-Raw`。`-Raw` なしでは応答はPowerShellオブジェクト。要求 `version=1`、`id`、`command`、`args` と必要な接続トークンを組み立て、応答のversion/idも照合する。

## 5. テキストをCodexへ送り、完了まで待つ

`codex.start` の `ok=true` は受付成功であり生成完了ではない。返された `jobId` を保持し、新しい要求IDで `job.get` を繰り返す。同時実行は1件なので、利用者のジョブが動いているときは追加開始しない。

```powershell
function Wait-ProbeJob {
    param([Parameter(Mandatory=$true)][string]$JobId, [int]$TimeoutSec=340)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    do {
        $poll = Invoke-Probe -Command 'job.get' -Arguments @{jobId=$JobId}
        $job = $poll.data
        switch ($job.state) {
            'completed' { return $job }
            'failed' { throw ('job failed: ' + $JobId + ': ' + $job.error) }
            'cancelled' { throw ('job cancelled: ' + $JobId + ': ' + $job.error) }
            'running' { }
            default { throw ('Unknown job state: ' + $job.state) }
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Polling deadline exceeded; job may still be running: ' + $JobId)
}

$status = Invoke-Probe -Command 'status'
if ($status.data.busy) { throw 'アプリに実行中ジョブがあります。追加開始しません。' }
$expected = 'RIGM_TEXT_OK_' + [guid]::NewGuid().ToString('N')
$started = Invoke-Probe -Command 'codex.start' -Arguments @{
    mode='text'
    text=('Reply with exactly this token and nothing else: ' + $expected)
}
$textJobId = $started.data.jobId
$textJob = Wait-ProbeJob -JobId $textJobId -TimeoutSec 340
if ($textJob.text -cne $expected) { throw 'Codex text mismatch' }
$textJob | Select-Object jobId,mode,state,text,logPath
```

ポーリング側の期限切れはジョブ失敗や中止を意味しない。保持したIDで状態を確認し、`codex.start` を新IDで送り直して二重生成しない。中止を明示的に依頼された自分のジョブだけに `job.cancel` とその `jobId` を使い、`cancelled` または `status.busy=false` を確認する。ユーザー起動プロセスを強制終了しない。

## 6. 画像生成、正式完了通知、image.get

テキスト成功後、無害な画像を同じ経路で1回生成する。別の画像生成ツールによる代用は、この通信検証の成功と扱わない。

アプリは `item/completed` の `item.type=imageGeneration`、`status=completed`、失敗情報なしの正式通知を処理する。さらに画像が1件だけ存在し、`turn/completed` の正常完了を受信することを要求する。パスが書かれた文章や開始受付だけでは成功にしない。この処理は [DotsCodexTransport.pas](Source/Diagnostics/DotsCodexProbe/DotsCodexTransport.pas) にある。

```powershell
$status = Invoke-Probe -Command 'status'
if ($status.data.busy) { throw 'アプリに実行中ジョブがあります。追加開始しません。' }
$imageStarted = Invoke-Probe -Command 'codex.start' -Arguments @{
    mode='image'
    text='Generate exactly one raster PNG image: a solid blue circle centered on a plain white square background, no text or logos. Use 512 by 512 pixels if supported; keep the file under 4 MiB. Use the built-in image generation tool once.'
}
$imageJobId = $imageStarted.data.jobId
$imageJob = Wait-ProbeJob -JobId $imageJobId -TimeoutSec 650
if ($null -eq $imageJob.image -or [string]::IsNullOrEmpty($imageJob.image.imageId)) {
    throw 'No generated image metadata'
}
$imageJob.image | Select-Object imageId,path,bytes,width,height,sha256
```

`image.path` はアプリ側Windows PCの保存場所。画像本体を取得するには、その起動中に返された `imageId` で `image.get` を呼ぶ。以下はデータの復号・サイズ・SHA256・画像デコードを照合し、送信器側の新規出力ファイルへ保存する補助関数。

```powershell
$outputDir = Join-Path $projectRoot ('output\validation\dots-transfer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputDir | Out-Null

function Receive-ProbeImage {
    param(
        [Parameter(Mandatory=$true)][string]$ImageId,
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][object]$ExpectedMetadata
    )
    $download = Invoke-Probe -Command 'image.get' -Arguments @{imageId=$ImageId}
    $data = $download.data
    $bytes = [Convert]::FromBase64String($data.base64)
    if ($bytes.Length -gt 4194304 -or $bytes.Length -ne $data.bytes -or
        $bytes.Length -ne $ExpectedMetadata.bytes) { throw 'Image size mismatch/limit' }
    $extension = [IO.Path]::GetExtension($data.path).ToLowerInvariant()
    if ($extension -notin @('.png','.jpg','.jpeg','.bmp')) { throw 'Unsupported image extension' }
    $destination = Join-Path $Directory ([guid]::NewGuid().ToString('N') + $extension)
    if (Test-Path -LiteralPath $destination) { throw 'Output already exists' }
    [IO.File]::WriteAllBytes($destination,$bytes)
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $data.sha256 -or $hash -cne $ExpectedMetadata.sha256) {
        throw 'Image SHA256 mismatch'
    }
    Add-Type -AssemblyName System.Drawing
    $decoded = [Drawing.Image]::FromFile($destination)
    try {
        $width = $decoded.Width
        $height = $decoded.Height
        if ($width -gt 8192 -or $height -gt 8192 -or
            ([long]$width * $height) -gt 16777216 -or
            $width -ne $data.width -or $height -ne $data.height -or
            $width -ne $ExpectedMetadata.width -or $height -ne $ExpectedMetadata.height) {
            throw 'Image dimensions mismatch/limit'
        }
    } finally { $decoded.Dispose() }
    [pscustomobject]@{path=$destination;bytes=$bytes.Length;sha256=$hash;width=$width;height=$height}
}

$receivedImage = Receive-ProbeImage -ImageId $imageJob.image.imageId `
    -Directory $outputDir -ExpectedMetadata $imageJob.image
$receivedImage
```

同じWindows側で元の `image.path` も読める場合は、その実在・サイズ・SHA256とも比較する。読めなければ未確認と報告し、ローカルパスをクラウドへ渡すだけで転送成功としない。画像閲覧機能で実画像を開き、指示した内容かも確認する。指定解像度は文章上の希望で、実戻り値を必ず検証する。

## 7. image.putで画像をアプリへ渡す

`image.put` は画像ファイルの生バイトをBase64化し、`args.base64` へ送る。data URLヘッダーは付けない。以下は前節で受け取った画像を再利用する例で、追加生成はしない。

```powershell
$inputPath = $receivedImage.path
$inputBytes = [IO.File]::ReadAllBytes($inputPath)
if ($inputBytes.Length -gt 4194304) { throw 'Input exceeds 4 MiB' }
$inputHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$uploaded = Invoke-Probe -Command 'image.put' -Arguments @{
    base64=[Convert]::ToBase64String($inputBytes)
}
if ($uploaded.data.sha256 -cne $inputHash) { throw 'Uploaded image mismatch' }
$roundtripImage = Receive-ProbeImage -ImageId $uploaded.data.imageId `
    -Directory $outputDir -ExpectedMetadata $uploaded.data
if ($roundtripImage.sha256 -cne $inputHash) { throw 'Image roundtrip mismatch' }
$roundtripImage
```

アプリは画像を復号・保存してフォームに表示する。画像認識は別の能力であり、このバイト往復だけで成功とは判定しない。認識を試す場合は、別途許可された `codex.start(mode=text, text=質問, imageId=返却ID)` を使い、同じ完了待ちを行う。今回の追加検証では認識ジョブは実行していない。

## 8. フレーム、制限、エラーと復帰

| 項目 | 現行値／扱い |
| --- | --- |
| パイプ | `\\.\pipe\<connection.pipeName>`、duplex / byte mode、BOMなしUTF-8 JSON + LF、1接続1要求1応答 |
| 最大フレーム | LF込み8MiB。画像を複数フレームへ分割する機能は未実装 |
| 画像 | PNG/JPEG/BMP、1枚4MiB、各辺8192px以下、総画素数16,777,216以下 |
| テキスト生成要求 | `text` は1～32000文字の空でない内容 |
| 同時実行 | Codexジョブ1件、1起動あたり最大128ジョブ |
| パイプI/O | 既定15秒。送信器の `-TimeoutMs` は接続・各読書き待ち。ジョブ全体の生成時間ではない |
| Codex RPC | 各応答待ち30秒 |
| Codexターン待ち | テキスト300秒、画像600秒。初期化・RPC等の時間は別にかかる |
| 要求ID | 毎回新しいID。ポーリングも新ID。応答を失った同一要求の再送時だけ元のIDと同じ本文を使う |
| 再送キャッシュ | 直近256件・応答文字数合計16Mi文字まで。追い出しや再起動をまたぐ二重実行防止は保証しない |

正常結果は `ok=true`。命令のエラーJSONは `ok=false` と `error.code/message`。生成は `job.get` の `state=completed/failed/cancelled` まで見る。ローカル例外、接続拒否、受付エラー、生成失敗、ファイル読取失敗を分けて記録する。

| 症状 | 行動 |
| --- | --- |
| `pipe_access_denied`、`0x80070005`、Win32エラー5 | パイプOpen時の拒否。その経路を停止。権限変更・昇格・別経路へ切り替えない |
| `unauthorized` | 接続後のトークン欠落／不一致。起動中フォームの接続情報と送信器を確認。トークンを公開せず、認証を省略しない |
| `stale_connection`、Win32エラー2 | 対象パス、起動中フォーム、隔離環境の照会制限を確認。古いファイルだけで起動状態を決めない |
| Win32エラー231 | パイプが使用中。別クライアントの終了を待つ。アクセス拒否後に再試行を繰り返す根拠にはしない |
| `busy` | 他のジョブを妨げず待つ。ユーザーのジョブを勝手に中止しない |
| `id_conflict` | 同一IDを別本文に使っている。再送と新規要求を区別する |
| `unknown_job` / `unknown_image` | 別起動のIDや誤った対象を疑う。古いIDで生成を勝手にやり直さない |
| サイズ超過、画像デコード失敗、SHA256不一致 | 当該段階の失敗として保存。文章のパスや別画像で成功扱いにしない |
| タイムアウト／通信断 | 元の要求IDとjobIdを保持。生成が動いている可能性を報告し、無条件の新規開始をしない |

診断を依頼された場合だけ、失敗した通信と同じDots実行環境から次を使う。通常パイプのOpen確認と、Open成功時のpingを含む。拒否後に昇格や設定変更へ進むスクリプトではない。実行前に現行内容を確認する。

```powershell
& (Join-Path $probeDir 'Diagnose-PipeAccess.ps1') -ConnectionFile $connection
```

通常端末の接続成功は、隔離されたDots環境の接続成功を証明しない。診断のユーザーSID・整合性・AppContainer情報は比較資料であり、接続トークン等の秘密値とは区別する。

## 9. 証拠・Windowsローカル・Dotsクラウド・Library

アプリ側の通常ログは作業フォルダの `pipe.log`、Codex通信は `Jobs/<jobId>/protocol.log`、最終結果は同じジョブフォルダの `result.json`。生成画像はジョブ内の受信ファイルと `Images/<imageId>.<拡張子>` に残る。通信ログにはプロンプトが含まれる。記録する要求から接続トークンを除き、画像Base64をチャットへ大量貼付しない。

段階を区別して報告する。

1. パイプ接続・ping成功。
2. Codexへの受付と正常完了。
3. アプリ側のファイル実在・サイズ・デコード。
4. `image.get` による実バイト返却・受信側SHA256照合・実画像確認。
5. 必要な場合だけ、別途チャット／Libraryへのファイル登録。

`C:\...` や `D:\...` はこのWindows側のパスであり、親のDotsクラウドのfilesystemから見えるとは限らない。Windows側で閲覧できたことを、親クラウドが `view_image` できることと混同しない。パイプ本体にクラウドアップロード機能はない。ネットワーク経由の常駐起動・中継、任意フォルダへの配置、転送再開も未実装。

Libraryを使ってチャットへ届ける場合は、利用可能なLibraryスキルの正式なアップロード機能を使う。今回使えたのは `create_library_file` の `file` に実ファイルを読めるWindowsホストの絶対パスを渡す方法。これはPowerShellコマンドや本アプリのAPIではない。親クラウドから見えないWindowsパスを、クラウド側の読取APIへ渡しても代用にならない。正式なアップロード機能がない場合は「ローカル返却成功・クラウド転送未実施」と報告し、別サービスや認証情報の取得で迂回しない。

登録成功時は返却された `library_file_id`、ファイル名・サイズを使う。IDを作らず、ライブラリ登録成功とチャット上での表示確認も区別する。同じ画像の再登録や再生成を不要に繰り返さない。

## 10. 2026-10-15の今回の実測

証拠の入口: [今回の報告](output/validation/dots-appcontainer-live-20261015-034345/REPORT.md)、[集計](output/validation/dots-appcontainer-live-20261015-034345/summary.json)、[画像確認](output/validation/dots-appcontainer-live-20261015-034345/image-verification.json)、[文書確認](output/validation/dots-appcontainer-live-20261015-034345/documents-reviewed.json)。これらは過去の証拠であり、次回の接続先を指示するファイルではない。

| 段階 | 今回の結果 |
| --- | --- |
| 旧通常モード | 同じDots環境でパイプOpenがエラー5。送信側はAppContainer・Low整合性。相手プロセス照会も拒否。停止し、権限は変更しなかった |
| ユーザーが起動した新モード | `appcontainer-test` とトークン必須を確認。同梱送信器でping/pong成功 |
| テキスト | `codex.start(mode=text)` 1回。`completed`、一意の検証文字列完全一致。Codexログの `turn/completed` も確認 |
| 画像生成 | アプリ経由で1回。正式な `imageGeneration` 完了通知1件と正常ターン完了。別経路の生成による代用なし |
| 画像返却 | `image.get` のBase64を復号、実ファイル・デコード・ハッシュ一致。白背景に青い円1個を実画像で確認 |
| 解像度とサイズ | 希望512×512に対し実出力1254×1254。856,255 bytes、4MiB未満。厳密な指定解像度の遵守は未達 |
| 追加の基本確認 | 日本語・改行・絵文字echo、text.saveが完全一致。生成済み画像のput/getも元バイト・メタデータと一致 |
| 要求記録 | 18要求すべて別ID、通信エラー・タイムアウトなし。最終busy=false。文書再読後に基本試験を補完したため、全項目を文書掲載順に実行したわけではない |
| Library転送 | 後続の別操作で同じ既存PNGの登録成功。ローカルLibrary属性の保存補助はPython起動拒否で未完了だが、Library登録は成功済み |
| 未検証 | 今回の画像認識、強制タイムアウト・中止・不正要求等の全面再試験、通常デスクトップのタスクバー目視、クラウドからの直接パイプ接続、再起動後のジョブ再開 |

今回の画像は [returned-image.png](output/validation/dots-appcontainer-live-20261015-034345/returned-image.png)。SHA256は `c8ae7c1459eb963dd41c42eaa4a23b94dc16e44dd14fb41e5abbdab029fc0eec`。

Libraryの既存登録は `library_file_id=libfile_456d33c6123481919bce766274652682`、`file_id=file_00000000179881fba0db8e500161b0f5`、`returned-image.png`（image/png、856,255 bytes）。[登録結果](output/validation/dots-appcontainer-live-20261015-034345/library-upload-result.json) が後続の成功証拠。先に作った集計／報告の「クラウド未実施」および「親からローカルview_image可能」という記述は、登録前の記録・後に訂正した案内として扱い、現在の転送状態の根拠にしない。

今回の通信検証ではユーザー起動アプリを終了せず、ACL・OS設定・認証情報・ソースを変更していない。今後も通信方式の再確認とセキュリティ設定変更は別の判断として扱う。
