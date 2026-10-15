# Dots向けパイプ通信仕様 v1

## 1. 接続

対象アプリの `connection.json` をUTF-8で読む。`protocol` は `dots-codex-probe/1`。`pipeName` を使って `\\.\pipe\<pipeName>` へ接続する。`processId` と対象フォームを照合する。パイプ名は起動ごとに変わる。通常終了で接続情報を削除する。異常終了後のファイルは有効接続の証拠にならず、接続後の `ping` 成功を確認する。

サーバーはWindows名前付きパイプのduplex / byte mode。パイプのDACLは起動ユーザーのSIDだけを許可し、リモートクライアントを拒否する。1接続につき1要求・1応答。応答をLFまで読んだらクライアントが接続を閉じる。次の要求は再接続する。多重接続・同じ接続での連続要求・サーバーからの自発通知はv1では扱わない。

上記は通常モード。`--allow-appcontainer` 起動時は、変動するAppContainer SIDへ対応するためAppContainer / Restricted AppContainerグループの読み書きACEとLow整合性ラベルをパイプへ設定する。受信後にWindowsのクライアント偽装で同一ユーザーSIDを必須確認する。`connection.json` の `requiresAccessToken=true` が示す場合、全要求のルートに同ファイルの `accessToken` を指定すること。トークン不一致・欠落は `unauthorized`。このモードもリモート接続を拒否する。グループ許可は試験起動だけに適用し、WindowsやDotsの全体設定は変更しない。

要求と応答はBOMなしUTF-8のJSONオブジェクト + LF (`0A`)。CRLF送信もJSON末尾の空白として受け付ける。JSON文字列内の改行は `\n` とエスケープする。UTF-8文字の途中やJSONの途中で複数回に分割されてもLFまで連結する。

1フレームはLF込み8MiBまで。読み書きの各I/O待ちは15秒、送信器の既定タイムアウトも15秒。不正フレーム、過大フレーム、LF未着のタイムアウト、接続断ではその接続を閉じる。LFまで到達した構文不正JSONにはエラーJSONを返す。受信を終えてから応答を読む。応答後に開いたままの接続も15秒で解放する。

## 2. 形式

```json
{"version":1,"id":"req-001","command":"echo","args":{"text":"こんにちは"}}
```

`id` は1～128文字の文字列。`version` は数値の1。`args` は常にオブジェクト。コマンド固有の引数は後述する。

AppContainer試験モードの例（`accessToken` の値は接続情報から毎回読む）:

```json
{"version":1,"id":"req-001","accessToken":"<connection.accessToken>","command":"echo","args":{"text":"こんにちは"}}
```

```json
{"version":1,"id":"req-001","ok":true,"data":{"text":"こんにちは"}}
```

```json
{"version":1,"id":"req-002","ok":false,"error":{"code":"unknown_job","message":"unknown_job"}}
```

解析不能またはidが文字列でない場合の応答idは空文字列。`ok=false` は処理失敗。`ok=true` の `codex.start` は受付成功であり、Codexの完了を示さない。最終成功は `job.get` の `state=completed` で判定する。

直近の要求・応答を最大256件、応答文字数合計16Mi文字までキャッシュする。同じid・同じ要求（空白を除くJSON表現。キー順も同じ）を再送すると当初の応答を返し、保存やCodex開始を二重実行しない。同じidで要求が違う場合は `id_conflict`。古いキャッシュの追い出し・アプリ再起動をまたぐ再実行防止は保証しない。通常は新しいGUIDを使い、応答喪失時だけ同一要求を速やかに再送する。状態のポーリングには毎回新しいidを使う。

## 3. コマンド

| command | args | data / 動作 |
| --- | --- | --- |
| `ping` | `{}` | `protocol`, `message=pong` |
| `status` | `{}` | `stateDirectory`, `busy`, `lastImageId` |
| `echo` | `text`: 文字列 | 同じ `text` を返し、フォームに表示 |
| `text.save` | `text`: 文字列 | 作業先直下の新しいGUID名 `.txt` へUTF-8で保存し、`path` を返す |
| `codex.start` | `mode`: `text` / `image`, `text`: 1～32000文字、任意の `imageId` | `jobId`, `mode`, `state=running`, `stage`, `logPath` |
| `job.get` | `jobId`: 文字列 | ジョブの現在状態または最終結果 |
| `job.cancel` | `jobId`: 文字列 | 実行中なら中止を要求し現在状態を返す。終了まで `job.get` で確認 |
| `image.put` | `base64`: 画像バイト列のBase64文字列 | 新しい `imageId`, `path`, `bytes`, `width`, `height`, `sha256`。保存・復号・画面表示 |
| `image.get` | `imageId`: 文字列 | 上記画像情報と `base64` |

保存先の任意指定はv1では扱わない。サーバーが発行したIDからのみジョブ・画像を参照する。`path` はクライアントPC内の保存場所を示す情報で、リモート側のローカルファイル名として使わない。画像の本体は `image.get` の `base64` から取得する。

画像はPNG/JPEG/BMP、1枚4MiBまで、幅・高さ各8192pxまで、総画素数16,777,216まで。拡張子でなくバイト列とデコーダーで検査する。`base64` はdata URLヘッダーなし。返却Base64には改行を入れない。SHA256は保存された画像バイト列から計算した小文字16進文字列で、受信側でも再計算する。

同時に実行できるCodexジョブは1件。実行中の追加開始は `busy`。1起動で最大128ジョブ。ジョブが上限なら `job_limit`。過去の結果は同じ起動中に取得でき、ディスクにも残すが、再起動後のジョブ再開は扱わない。

`mode=text` はテキスト回答。`imageId` を指定すると画像質問として送る。`mode=image` は内蔵画像生成で1枚生成し、任意の `imageId` を参照画像として送る。画像転送・画像認識・画像生成は独立した能力なので、個別に成功可否を確認する。

## 4. 非同期結果

```json
{"version":1,"id":"poll-002","ok":true,"data":{"jobId":"<受付で得たjobId>","mode":"text","state":"completed","text":"こんにちは。","logPath":"<クライアント内のログパス>"}}
```

状態は `running`, `completed`, `failed`, `cancelled`。終了結果には `text` があり、失敗・中止には `error` がある。画像生成の正常終了では `image` に画像情報（Base64以外）がある。その `imageId` で `image.get` を呼ぶ。

`job.cancel` の返却直後は `running` の場合がある。`cancelled` 到達または `status.busy=false` を待って次を開始する。完了済みジョブへの中止は保存済み結果をそのまま返す。

エラーコードの例: `invalid_json`, `invalid_id`, `invalid_version`, `invalid_args`, `invalid_text`, `invalid_mode`, `unknown_command`, `unknown_job`, `unknown_image`, `busy`, `job_limit`, `id_conflict`, `invalid_image_data`, `unsupported_image`, `invalid_image_dimensions`。デコーダーやOS由来の失敗では実際の例外メッセージを返すため、すべてを固定コードと仮定しない。

## 5. 試験順

1. 起動・接続情報取得 → `ping`。
2. `echo` で日本語と改行の一致を確認。
3. `text.save` でローカル配置を確認。
4. `codex.start(mode=text)` → `job.get` → テキスト回答確認。
5. `image.put` → `image.get` → SHA256と画面表示確認。
6. `codex.start(mode=text,imageId=...)` で画像内容を質問。
7. `codex.start(mode=image)` → 正常終了 → `image.get` で生成画像取得。
8. 中止・通信断・Codex未導入・不正要求時の復帰を確認。

## 6. Dots側との責務

この仕様で確定するのはクライアントPC上のパイプだけ。Dotsがリモートで実行される場合、同じユーザーのローカル補助プロセス等を通して上記要求を渡す。停止中アプリの起動、リモート経路、認証、転送再開、大容量画像の分割転送、任意フォルダ配置は今後の拡張であり、Dotsが対応できる方法を問い合わせてから決める。
