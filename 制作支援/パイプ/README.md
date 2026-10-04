## 2026-10-04 PNGバイト転送

共通パイプでPNGを分割受信・検証し、現在のプロジェクトのシーンへ採用できます。[ImageTransfer.md](ImageTransfer.md)と[Send-RigmImage.ps1](Send-RigmImage.ps1)を参照。標準動作は採用後未保存で、保存は明示的です。Windows上のPNGからアプリへの実転送と、生成環境からWindowsへの初回到達は別の経路として扱います。

## 2026-10-04 編集領域・スクロール・ホイール・フレームシーク・瞬きの更新（現在）

最新指示「出力テストなど不要、簡単な確認のみ」を優先。**動作確認はユーザー指示で省略**。今回の確認は変更箇所の静的レビュー、成果物/保護対象のSHA256照合、Win64 Debug/Release全ユニットビルドのみ。GUI起動/操作、ピクセル/DPI計測、数値テスト、回帰テスト、AVI/MP4再出力は行っていない。旧1980項目等の実行記録は旧版の履歴であり、この版の成功件数に数えない。

プレビュー・再生操作・タイムラインを共通の中央編集領域にまとめ、そのすぐ右に共通スプリッターと右アイコンページを置いた。タイムラインが右ツール列の下へ横断しない親子構成。中央全体と再生操作にもスクロールを備え、低い/狭い窓で操作がはみ出しても届くようにした。上下のスプリッターでタイムラインの高さを調整できる。既存右ページのスクロール、未適用入力、フォーカス、revision保護を維持。

タイムラインの目盛/見出し/クリップ文字は16論理pxへ少し縮小し、外側フォームDPIへ追従。目盛36、トラック行44論理px。内容は縦スクロール、拡大した時間範囲は横スクロールで移動する。字幕、画像の縦横比/名前、静的キャッシュを保持。追加トラックメタデータの数にも縦範囲を合わせる。

プレビュー上ホイールは表示倍率を0.1～16倍（フィット比）で変更し、カーソル位置を基準に範囲内で保持。横/縦バーまたは中ボタンドラッグでパン。「画面に合わせる」で倍率/移動を戻す。作品の出力サイズ・キャラ配置・revisionを書き換えない。左ボタンのキャラ移動/サイズ変更は従来の編集処理を維持。

タイムライン本体のホイールはカーソル付近を基準に時間軸を拡大縮小。時間目盛上のホイールは表示時間範囲だけを左右へ移動し、シークしない。横/縦バー上は各方向へスクロール。カーソル下のウィンドウで操作を振り分け、右プロパティのホイールスクロール/細かいスライダー更新と混同しない。全体シークバーはフレーム番号と秒を表示し、クリック/ドラッグとホイール1フレーム移動でシークする。タイムラインクリックも作品FPSへ丸め、最後の有効フレームへ制限。再生は既存時間に追従し、静止中の時間パンで再生位置を変えない。

瞬きは、従来の三角曲線の閉じ頂点がフレーム間で欠落し得たため、完全閉じ状態を少なくとも1.5出力フレーム、標準30fpsでは約64ms保持してから開く曲線へ変更。既定の約4秒間隔を維持し、低FPS時のみ必要な瞬き時間を確保する。通常目では実在する完全閉じ差分を選択。特殊目差分は固定表情としてblink候補にしない。口パクは独立し、全体モーション中のblink/lip/補助停止は維持。既存blinkStrength/Gain=0等の明示設定は尊重する。完全閉じの実際の画面表示は未検証。

元素材には独立した瞳/視線差分がなく、既存gazeX/Yは目素材全体を移動するため、本当の瞳の視線アニメーションは追加していない。代わりに「画像への向き補助（瞳移動なし）」を演技ページへ追加し、描画と共通の画像枠とキャラ位置から方向を求め、最大2度の小さな頭の傾きを滑らかに入れて通常へ戻す。HeadGain、演技時間/fade、rigSafeを尊重。既定autoは明示した画像説明文句、または場面animation.explainImage=trueで有効。目や元PSDを描き変えない。

起動EXE: D:\DelphiProg\RIGMMaker\RIGMMaker.exe
別名最新版: D:\DelphiProg\RIGMMaker\RIGMMaker.navigation-20261004T110447.exe
Release SHA256: 4B40A66B24BCF7A9D2AB8969AA17CA412EFFE4F492C3DD68D66D3A2EB8615125
Debug SHA256: 37C9F7D32B874AB63335B55791B8C9ED26919FF7E5B0C8E4111A0C6AB2160457
通常EXE反映: True
開始時/反映直前EXEの保管先: D:\DelphiProg\RIGMMaker\Win64\PreservedArtifacts\before-navigation-20261004T104715\root-at-final-install.exe（SHA256 9CE7D097B8183AA2CF82B3F8C250FA593FB8ADB0F89238C434093AF8F59603F0）

元作品と前回の「落ち着いた冒頭版」は変更していない。ユーザーアプリの強制終了、未保存文書や履歴の変更、コピー元Syncroh2/RIGM/PSDの変更、commit/pushなし。一時DCUと使い捨て回収ヘルパーは復元可能なWindowsごみ箱へ移し、元パスと全SHA256を照合。納品記録はWin64/Validation/NavigationRevision/delivery.json、ビルド記録はbuilds.json、起動EXE/保管はinstall.json。
既存movie-update-cueで {"id":"cue-id","acting":{"imageAttention":"head"}}、停止はoff、説明時だけはauto。既存movie-update-sceneで {"id":"scene-id","animation":{"explainImage":true}} を指定できる。既存projectId/revisionを併記し、変更は未保存状態で扱う。timelineの読み取り結果にfpsを追加。app-switch-pageのpropertyPageは従来通り。追加の操作名やoperation数変更なし。

## 以前の実装・検証履歴（上記を優先）

## 2026-10-04 文字の可読性・右側ページ・控えめな冒頭演技の更新（現在の実装）

最新の指示「guiの修正だけなので動作確認はしなくてよい」を優先。**動作確認はユーザー指示で省略**。今回の確認は静的なソース/素材/成果物照合とWin64 Debug/Release全ユニットビルドだけで、起動、GUI操作、DPI別画面計測、回帰テスト、open→自動判定→次工程、MP4再出力は行っていない。以下の旧1980項目等は以前の版の履歴で、今回の成功件数には含めない。

下側タイムラインは外側フォームのDPIを使い、通常UIの実際のFont.Height以上、最低18論理pxで描画する。ルーラーは最低48論理pxか文字高+16px、左見出し112論理px、4行の必要高から下側領域を計算する。画像の縦横比・静的キャッシュ・シーク処理を維持。内部64桁ハッシュの画像名は「導入の画像」等の表示名に置換する。画面上の見え方は未検証。

右側はセリフ・字幕・話者を初期ページにし、アイコンとツールチップで「セリフ」「場面」「演技」「音声」「診断」の5ページへ切り替える。コントロールを再利用し、ページ別のスクロール位置と入力フォーカスを保持。別ページの未適用入力とrevision保護を維持。演技ページ内も表情/モーションと数値演技の未適用状態を別に保持し、一方の適用で他方を消さない。場面タイトル/説明/画像/レイアウト、全体モーションの状態/停止、明示的な音声再生成を各ページで扱う。音声は勝手に再生成しない。

静的確認では1024×1536の元RIGM、全体モーションの内容467×700、透明余白87、PNGキャンバス641×874を確認。生成時に内容寸法・キャンバス寸法・アンカーを記録し、合成時に内容寸法とアンカーで通常姿勢の枠へ合わせる。既存の既知生成素材にはメモリ内で情報を補い、共有PNG/元RIGM/PSDを書き換えない。新しい実描画のサイズ/位置は未検証。

元編集版を保持し、別ファイル「落ち着いた冒頭版」を保存。冒頭のhappy全体モーションを外し、最初のセリフをneutral/idle、headGain=0.12、bodyGain=0.05へ変更。mouthGain=1、瞬き、既存実音声、画像、字幕/セリフと配置を保持し、旧プレビュー/動画キャッシュを解除。独立した瞳/視線差分がなくGazeX/Yは目素材全体の移動なので、新しい視線アニメーションを実装したとは扱わず、控えめな頭/体の演技に留めた。新MP4は作成していない。

エラー欄の内部名MovieExportFeedbackはCaption/ShowCaptionを空/無効にし、実際のエラーと再試行を保持。開いた時の未分類再判定、手動役割/ロック保護、自動保存しない動作、人間確認を進行条件にしない仕様は従前コードを保持。必須素材不足/破損/不整合の停止条件、PSD取込、Pro HID、高速プロパティ更新、子UIホイール、パイプは今回は実行テストをしない。

通常起動EXE: D:\DelphiProg\RIGMMaker\RIGMMaker.exe
別名新版EXE: D:\DelphiProg\RIGMMaker\RIGMMaker.readability-20261004T102816.exe
Release SHA256: B9E77C6397A5D471ABA5A04228BF8E9E4FABB52CDCF4E0FF1A2534B3E853C4CA
Debug SHA256: E4E8C09D9E4B7668EF743875EFF52508BF3CCF3E72DDCF8DDCFA9ECF22602CAA
開始時の別ビルドEXE保管先: D:\DelphiProg\RIGMMaker\Win64\PreservedArtifacts\before-readable-properties-20261004T095329363\root-at-final-install.exe（SHA256 876ECCC5D2B9D405112CFD962C850F5E239799A563789D6EEEB2BE3C92063988）
新しい編集作品: C:\Users\zan12\Documents\RIGMMaker\Projects\星灯り郵便局-20261004T064959615\星灯り郵便局-落ち着いた冒頭版-20261004.rigmovie
作品SHA256: B1EBDF79B099E401077E68B937F1E15C9A1A3E9FA182C6C35942332BBE505E9B
元作品SHA256: 278EF70FEA76D7602CF0DC9ECE313ACB0CC8F1CB68899756170B714689C545E8（変更なし）

記録: Win64/Validation/ReadabilityRevision/delivery.json、builds.json、install.json、static-motion-geometry.json、calm-intro-delivery.json。今回の中間生成物はWindowsごみ箱へ回収し、元パスと各SHA256から復元可能性を照合。ユーザーアプリの強制終了、未保存文書/元作品/履歴/コピー元の変更、commit/pushは行っていない。
既存app-switch-pageにoptional propertyPageを追加。ID dialogue / scene / acting / audio / diagnosticsを指定できる。例: {"page":"preview","propertyPage":"acting"}。app-statusも現在のpropertyPageを返す。propertyPage省略時は従来互換。既存5個のapp操作と主要操作数、プロジェクト編集のrevision照合を維持。

## 以前の版の記録・仕様（今回の変更は上記を優先）

**2026-10-04 現行版は通常の `RIGMMaker.exe`。** 起動時は動画プレビュー・編集。上部アイコンでプレビュー／制作／キャラクター登録を切り替える。GUIとCodexは同じ文書モデルと共通パイプを使い、既存コア操作に加え動画64操作、workspace 5操作を提供する。旧EXE名・旧検証数を記した後続の段階別記録は履歴として読む。[最終検証1743項目](../../Win64/Validation/production-release-verification.json)。

## 2026-10-04 GUI MP4書き出しの現行手順

1. 検証済みRelease `D:\DelphiProg\RIGMMaker\RIGMMaker.timeline-export-20261004T090459.exe` で作品を開く。現在の通常EXEも作品open起動検証済み。両者のSHA256と保管先はnote.md先頭を参照する。
2. 「ファイル → 動画を書き出す → MP4（映像・音声）...」、またはプレビューの「MP4出力...」（Ctrl+Shift+E）を押し、新しい保存先を選ぶ。
3. 進捗表示を待ち、完了後に「保存先を開く」。処理中は「書き出しを中止」で中止できる。

工程切替やパイプ操作は不要。出力済みの同名ファイルは保護する。FFmpegが未設定なら既存ffmpeg.exeを選ぶ。セリフ変更が音声に未反映の構成作品は警告を表示して保存済み音声を使用し、自動再生成しない。必要な音声がない場合は出力できない理由を表示する。

GUIで実際に生成した実画像/実音声MP4は `C:\Users\zan12\Documents\RIGMMaker\Projects\星灯り郵便局-20261004T064959615\Exports\星灯り郵便局-GUI書出し確認-20261004.mp4`。元作品・既存MP4は変更なし。時間と四トラックはDPIに追従する16論理pxの文字で、各オブジェクトの内容を表示する。

検証済み範囲と未検証範囲、全1980項目、回収記録は `../../note.md` と `../../Win64/Validation/timeline-export-release-verification.json`。再実行はTests/Run-TimelineExportValidation.ps1のSourceMovieに実作品を指定する。これは4シーン実画像/音声作品用の隔離GUIテストで、全MP4出力には数分かかる。パイプAPIの64/5/43コマンドと素材/作品形式は今回変更していない。以下の段階別件数は過去の記録である。

`Send-RigmCommand.ps1` は構成編集、字幕と本文の独立編集、編集リース、全体モーションを含む現行操作を受け付ける。作品ID・revisionは既定で現在のmovie-statusから付与し、明示した古い値を上書きしない。編集リース中は取得したeditTokenも指定する。app操作はコアdocumentIdを付けず共通workspaceへ送る。

```powershell
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command app-status
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command app-switch-page -ArgsJson '{"page":"create"}'
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command app-library
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command app-open-work -ArgsJson '{"path":"D:\\works\\example.rigmovie"}'
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command movie-schema
& .\Send-RigmCommand.ps1 -ConnectionFile $connection -Command movie-composition-requests
```

構成編集は `movie-composition-enable/add-character/update-character/delete-character/add-scene/update-scene/delete-scene/move-scene/resize-scene`。実差分は `movie-register-expression`、既存差分・実話者に基づく提案は `movie-analyze-script`。表示字幕は `movie-update-subtitle`、音声本文は `movie-update-dialogue`。本文だけでは自動合成せず旧音声を保持し、`movie-audio-generate` の明示実行で必要なcueだけ再生成する。

編集リースは `movie-edit-begin/status/heartbeat/end/fail/release`。編集中はGUI読取専用、完了・失敗・期限切れ・手動解除で解放し、古いtoken/epoch/revisionを拒否する。全体モーションは `movie-register-motion/select-motion/stop-motion`。registerはキャラクターid、名前、`motion`（loop、framesのimageとduration）を指定し、selectはid/name/start/durationを指定する。start省略は現在の作品時刻。フレーム画像は実在するファイルを使い、保存時にassetsへコピーする。未知の素材品質は保証しない。パラメーターの正式な定義は実アプリの `movie-schema` を参照する。

通常の工程では人間の確認済みフラグを要求せず、本当のパーツ不足・破損・不整合で止める。検証は隔離したプロセス・設定・パイプで行い、実行中ユーザーの文書へ試験コマンドを送らない。

`Send-RigmCommand.ps1` はPowerShell 7用の送信器。編集画面と同じコントローラーを通じてレイヤー・ボーン・メッシュを操作する。現行APIは **共通パイプ＋commandによる振分け**。ページを切り替えても同じ共通パイプ名を使い、UIの一覧・選択・プロパティ・描画・Undo/Redoを更新する。

## 接続情報と対応命令を取得する

編集画面を開くと `%LOCALAPPDATA%\RIGMMaker\pipes\` に接続情報JSONを作成する。編集画面ごとに別のJSONと共通パイプを持つ。テスト時は `--pipe-dir=<フォルダー>` で保存先を変更できる。通常終了時に接続情報を削除する。

プロジェクトのルートで実行する例:

```powershell
$sender = '.\制作支援\パイプ\Send-RigmCommand.ps1'
$pipeDirectory = Join-Path $env:LOCALAPPDATA 'RIGMMaker\pipes'
Get-ChildItem -LiteralPath $pipeDirectory -Filter '*.control.json' |
    Select-Object FullName, LastWriteTime

# 対象編集画面のJSONを指定する。複数画面ではstatusの名前とdocumentIdで識別する。
$connectionFile = '<対象の接続情報JSONの絶対パス>'
$status = & $sender -ConnectionFile $connectionFile -Command status | ConvertFrom-Json
$status.data | Select-Object name, documentId, revision, page, selectedId, stages

$connection = Get-Content -LiteralPath $connectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
$commandPipe = $connection.commandPipe
# 旧controlPipeは同じ共通パイプ名を示す互換エイリアス。
$status.data.pipes | Select-Object commandPipe, controlPipe, routing, apiVersion

$api = & $sender -PipeName $commandPipe -Command schema | ConvertFrom-Json
$api.data.commands | Select-Object command, pages, available, requiresRevision
$api.data.commands | Where-Object command -eq 'set-mesh' | Select-Object -ExpandProperty argsSchema
```

`schema` はAPI version 2、全43命令、ページ制限、引数のJSON Schema、`$defs` の頂点/面/ウェイト定義、上限、意味上の検証条件を返す。`available` は取得時の現在ページに対する値。`argsSchema` の参照 `#/$defs/...` は応答dataの定義を参照するため、単独のJSON Schemaとして使う場合はその定義を一緒に渡す。

送信器は毎回 `status` を読み、変更命令と `select-object` で省略された `documentId`・`revision` を補完する。明示した値は上書きしない。オフライン計算の結果を適用するときは、計算に使ったIDとrevisionを明示し、途中のユーザー編集へ上書きしない。`revision` は文字列。

現行アプリでは `-ConnectionFile` も `-PipeName $commandPipe` も共通入口へ送信する。旧アプリのrouting情報がない場合だけ、`-ConnectionFile` は旧方式のページ専用パイプへ転送する。旧 `pagePipe` は現行アプリにも互換用に残り、ページ切替で更新される。プレビューに専用パイプはない。旧専用パイプを利用するクライアントは引き続き接続情報を読み直す。

## 命令一覧

すべての命令を共通入口へ送れる。編集命令は **現在工程** に適合する必要があり、別工程を編集するときは `switch-page` で切り替える。

| 使用できる工程 | 命令 |
| --- | --- |
| 全工程・情報取得 | `status`, `schema`, `document`, `validate`, `export` |
| 全工程・操作 | `switch-page`, `select-object`, `save`, `undo`, `redo`, `mark-complete`, `batch`, `autofix`, `ignore-issue`, `request-fix` |
| レイヤー | `import-png`, `replace-png`, `import-psd`, `classify-layers`, `add-group`, `update-layer`, `move-layer`, `set-parent`, `delete-layer`, `verify-source`, `import` |
| ボーン | `add-bone`, `update-bone`, `hide-bone`, `restore-bone`, `reset-bone`, `bind-part` |
| メッシュ | `generate-mesh`, `set-mesh`, `set-vertices`, `delete-mesh`, `update-mesh`, `update-vertex`, `add-vertex`, `delete-vertex`, `set-triangles`, `set-weights`, `import` |
| プレビュー | `update-parameter` |

新規命令は `schema`, `select-object`, `set-mesh`, `set-vertices`, `delete-mesh`。既存のメッシュ生成/部分編集/修正・保存処理を再利用した。`verify-source` は旧クライアント用の互換メタデータ操作で、工程進行には不要。

### ページ切替と準備判定

```powershell
# 完了済みの工程へ移動する。未準備なら拒否する。
& $sender -PipeName $commandPipe -Command switch-page -ArgsJson '{"page":"mesh"}'

# 必要な前工程を既存の自動検証で完了してから移動する。
& $sender -PipeName $commandPipe -Command switch-page -ArgsJson '{"page":"mesh","completeCurrent":true}'
```

`completeCurrent` の既定値はfalse。trueの場合は候補文書で必要な前工程を検証・完了し、成功時にまとめて確定する。必須画像の不足・ボーン循環・参照切れ等がある場合は停止し、途中まで完了したフラグも元に戻す。メッシュを自動生成する指定ではない。`mark-complete` は現在工程を自動検証して次へ進む。人間確認を前提にしない。

### 文書・対象・形状の取得

```powershell
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"summary"}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"parts","offset":0,"limit":50}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"bones","offset":0,"limit":50}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"meshes","offset":0,"limit":50}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"parameters","limit":50}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"mesh-vertices","id":"<メッシュID>","offset":0,"limit":50}'
& $sender -PipeName $commandPipe -Command document -ArgsJson '{"section":"mesh-triangles","id":"<メッシュID>","offset":0,"limit":50}'
```

`summary` はキャンバス寸法、座標系、工程フラグ、各対象の数を返す。各一覧は `items`, `total`, `documentId`, `revision` を返す。`parts`・`bones`・`meshes`・`parameters` は任意の `id` で1件を取得できる。画像パーツは `imageWidth`, `imageHeight`, `bounds`, `x/y`, 回転、拡大率、祖先グループ、種別、ボーン参照、ロック等を含む。メッシュ一覧は形状配列を省き `vertexCount`, `triangleCount` と属性を返す。形状は専用sectionで分割取得する。`offset>=0`, `limit=1～50`。

キャンバス中央を原点にX右・Y下。メッシュの頂点はパーツと同じ祖先グループのローカル座標で、描画時に祖先グループの変換が適用される。UVは画像内の0～1。パーツ位置、画像寸法、回転、拡大率と、祖先の属性を併せて使う。

## ページ切替→対象取得→生成→検証→保存

対象文書に対してメッシュを設定する例。新規生成が必要なパーツをCodexが選び、既存メッシュを保護する場合は `replaceExisting=false` を指定する。

```powershell
function Invoke-Rigm([string]$Command, [hashtable]$Arguments = @{}) {
    & $sender -PipeName $commandPipe -Command $Command `
        -ArgsJson ($Arguments | ConvertTo-Json -Depth 32 -Compress) | ConvertFrom-Json
}

$prepared = Invoke-Rigm 'switch-page' @{page='mesh';completeCurrent=$true}
$parts = Invoke-Rigm 'document' @{section='parts';offset=0;limit=50}
$bones = Invoke-Rigm 'document' @{section='bones';offset=0;limit=50}
$meshes = Invoke-Rigm 'document' @{section='meshes';offset=0;limit=50}
# totalが50を超える一覧はoffsetを増やして最後まで取得する。

$partId = '<生成する画像パーツID>'
$created = Invoke-Rigm 'generate-mesh' @{id=$partId;grid=4;replaceExisting=$false}
# 全画像パーツの不足分だけ生成する場合:
# $created = Invoke-Rigm 'generate-mesh' @{grid=4;replaceExisting=$false}

$mesh = Invoke-Rigm 'document' @{section='meshes';id=$created.data.selectedId}
$geometry = Invoke-Rigm 'document' @{section='mesh-vertices';id=$created.data.selectedId;limit=50}
$checked = Invoke-Rigm 'validate' @{throughPage='mesh';errorsOnly=$true;limit=50}
if (-not $checked.data.throughPageReady) { throw ($checked.data.issues | ConvertTo-Json -Depth 12) }

$saved = Invoke-Rigm 'save' @{path='D:\作業\character.rigm'}
# メッシュ準備を検証・完了してプレビューへ移動する。
$preview = Invoke-Rigm 'switch-page' @{page='preview';completeCurrent=$true}
```

`generate-mesh` の `id` は **パーツID**、他のメッシュ編集命令の `id` は **メッシュID**。gridは2～16で、頂点数はgrid²。骨IDを省くとパーツの追従ボーン、顔系はheadAngleのボーン、体等はbodyAngleのボーンを使う。fixedにはウェイトを付けない。参照用画像は生成対象外。既存クライアント互換のため `replaceExisting` の既定値はtrueであり、falseは既存のカスタム形状を保持する。全対象生成の途中でロック・不正な参照が見つかった場合も確定せず、元文書を保持する。

`validate` は `issues`, `total`, `errorCount`, `throughPageReady`, `currentStageReady` を返す。`throughPage`、`targetId`、`errorsOnly`、`offset/limit` を指定できる。readyは返された1ページだけでなく全件を判定する。`save` は明示した時だけ行い、自動保存しない。現在の保存先以外の既存ファイルをパイプから上書きすることは拒否する。

## カスタム形状をまとめて設定する

`set-mesh` はパーツのメッシュを作成、または既存メッシュのIDを保持して形状を置換する。既存 `id` または `partId`、頂点と面の両配列を指定する。メッシュを別パーツへ付け替えない。次の数値は形状の形式を示す例で、実際には対象画像の寸法・位置から計算する。

```powershell
$meshArgs = @{
    partId = '<画像パーツID>'
    vertices = @(
        @{x=-10;y=-10;u=0;v=0;weights=@(@{boneId='<ボーンID>';value=1})},
        @{x= 10;y=-10;u=1;v=0;weights=@(@{boneId='<ボーンID>';value=1})},
        @{x=-10;y= 10;u=0;v=1;weights=@(@{boneId='<ボーンID>';value=1})},
        @{x= 10;y= 10;u=1;v=1;weights=@(@{boneId='<ボーンID>';value=1})}
    )
    triangles = @(@{a=0;b=1;c=2}, @{a=1;b=3;c=2})
}
$configured = Invoke-Rigm 'set-mesh' $meshArgs
$meshId = $configured.data.selectedId

# UIの対象選択を同期する。文書リビジョンは変わらない。
Invoke-Rigm 'select-object' @{id=$meshId}
# 属性とウェイトを1回のUndoで戻せる一括操作として設定する。
Invoke-Rigm 'batch' @{operations=@(
    @{command='update-mesh';args=@{id=$meshId;strength=0.8}},
    @{command='set-weights';args=@{id=$meshId;vertex=-1;weights=@(
        @{boneId='<主ボーンID>';value=0.7}, @{boneId='<補助ボーンID>';value=0.3}
    )}}
)}
```

| 命令 | 引数と動作 |
| --- | --- |
| `set-mesh` | `partId`または既存`id`, `vertices`, `triangles`。必要ならname/role/visible/locked/boundaryFixed/strength/interpolationも指定。頂点3～1024、面1～2048。作成または全形状の置換 |
| `set-vertices` | メッシュ`id`, `offset`（既定0）, `vertices`。既存頂点の範囲を置換し、数を変更しない。各項目はx/y/u/v/weightsを含む |
| `update-vertex` | `id`, `vertex`, 任意のx/y/u/v。1頂点の部分変更 |
| `set-triangles` | `id`, `triangles`。面全体を設定。a/b/cは0から始まる頂点番号 |
| `set-weights` | `id`, `vertex`（-1で全頂点）, `weights`。表示中の既存ボーン、各0～1、合計1（許容0.0001）、重複なし、最大8ボーン |
| `add-vertex` | `id`, `face`（既定0）。面の中心に頂点を加えて3面に分割。3隅のウェイトを平均する |
| `delete-vertex` | `id`, `vertex`。頂点と接続面を除き、残る面の番号を更新。構成途中の未接続等はvalidateで判定する |
| `update-mesh` | `id`, 任意の属性。strengthは0～1、補間方式は現在linearのみ |
| `delete-mesh` | `id`。メッシュを削除。可動パーツの欠落メッシュはvalidateで検出し、完成扱いにはしない |

ロックされたメッシュは編集・削除を拒否する。解除は `update-mesh {id,locked:false}` として明示する。`boundaryFixed=true` の境界位置/UVも保護する。形状を作成・置換・生成する際は対象パーツのロックも保護する。不正ID、非有限値、範囲外UV/ウェイト、範囲外または潰れた面を設定すると、文書・revision・選択・保存先・Undo/Redoを保持してエラーを返す。未接続頂点や欠落メッシュは構成途中の状態として保存できるが、工程完了時の検証は通らない。

### 大きい形状とオフライン計算結果の取込

要求・応答はUTF-8で60,000 bytes以下。`-ArgsFile` はJSON引数をファイルから読む機能で、通信上限を増やすものではない。大きい全形状は8MB以下の操作結果ファイルを `import` で読み、候補文書にまとめて適用する。現在はレイヤー/メッシュ工程に対応する。

```powershell
$baseStatus = Invoke-Rigm 'status'
# この版のメタデータ/PNGを使ってCodexが形状を計算する。
$workDirectory = 'D:\作業\mesh-job'
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
$resultFile = Join-Path $workDirectory 'mesh-result.json'
@{
    documentId = $baseStatus.data.documentId
    revision = $baseStatus.data.revision
    operations = @(@{command='set-mesh';args=$meshArgs})
} | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $resultFile -Encoding utf8
Invoke-Rigm 'import' @{path=$resultFile}

# 小さなJSON引数ファイルを直接送る場合:
$argsFile = Join-Path $workDirectory 'set-mesh-args.json'
$meshArgs | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $argsFile -Encoding utf8
& $sender -PipeName $commandPipe -Command set-mesh -ArgsFile $argsFile
```

`batch`/`import` は最大2,000操作で、現在工程に適合する実編集命令を実行する。1件でも失敗すると全部を破棄する。`import` は外側の要求に加え結果ファイル内の文書ID・revisionも照合する。コマンド内の再帰batchやページ切替/保存/読み取り命令は一括処理に含めない。大きい設定の計算中にユーザーが編集した場合は古い結果を拒否する。

`export {root,images:true}` はどの工程からも固有の交換フォルダーに `snapshot.rigm`, `manifest.json`, パーツPNGとID/ファイル/SHA-256対応表を出力できる。画像を省く場合は `images:false`。画像データをパイプJSONへ埋め込まない。通常のレイヤーexportは従来どおり画像を含む。

## 形式・対応範囲・検証

メッセージ型Named Pipe、UTF-8 JSON、要求は `{schemaVersion:1,requestId,command,args}`。応答は同じrequestId、ok、dataまたはerror。パイプのapiVersion=2と封筒のschemaVersion=1は別の値。旧 `controlPipe` 名、旧ページ専用パイプ、既存命令は互換維持するが、不正な面/UV/ウェイトを確定する旧動作は拒否に修正した。

既定の自動生成はパーツ矩形の格子。顔・髪等は単一ボーン、上半身構成の体は腰と上半身の混合ウェイトと腰の頂点行を使用する。輪郭に沿う形状や素材ごとの自然な変形はCodexがPNG/寸法/ボーンから計算し、set-mesh/import等で設定できる。アプリに外部AIの自動呼出しや輪郭最適化を内蔵したものではない。`request-fix` はアプリ内キューへの登録で、外部AIへ送信しない。

上半身スライダーは既存の`bodyAngle` IDを維持する。`schema.upperBodyRig`に意味と互換条件、`document {section:"summary"}`およびexport manifestの`bodyRig`に`waistBoneId`と`upperBodyBoneId`がある。`parameters`で実際の関連ボーンを確認する。新規構成は腰→上半身→首→頭で、上半身の回転支点は腰。Proコントローラーの体割当も同じIDの上半身操作となる。

旧5ボーンの標準階層はロック等のない互換条件下でopen時に未保存・Undo可能な構成へ移行する。元のボーンID/位置とメッシュ形状/保存ウェイトを保持し、旧体ボーン位置を腰支点として使用する。識別可能な手動体メッシュ、複合体ウェイト、追加ボーンや独自階層は自動移行しない。`set-mesh`等の手動形状・ウェイト操作は`automatic=false`とし、明示した腰ウェイトを自動配分しない。旧APIで作られたデータには手動形状でも`automatic=true`のものがあるため、保存されたフラグとウェイト/階層が移行判定の基準になる。一体の体画像は独立した腕・襟等の変形を表現できず、粗い既存格子では腰をまたぐ面に伸縮が残る。

`Tests/Run-Validation.ps1` は隔離した文書で、実フォームの共通パイプ69項目、プレビュー/ホイール/腰構成58項目とPowerShell送信器の一連操作を含む全回帰・Win64両構成を検証する。文書/対象/形状取得→ページ切替→生成/設定→検証→保存再読込、拒否時保持、旧レイヤー/ボーン、Undo/Redo、旧専用パイプ、PSD、HID、UIを含む。結果は `Win64/Validation/CommonPipe/results.json`、`Preview/results.json`、`Sender/results.json` と各ログ。ユーザーが開いている文書へ生成・編集命令を送らず、ユーザーアプリを強制終了しない。

旧 `ArtExchange` の全ジョブ管理、キャンセル・復旧は未移植。参考元のprogress/cancel/recover等を現行RIGMへ送らない。旧資料は [パイプ操作ルール原本](../元資料/AIArtToPSD/パイプ操作ルール.md) と [AI画像指示交換の原本](../元資料/AIArtToPSD/アプリ実装_AI画像指示交換.md) に履歴として保持する。

## 動画制作の共通パイプ操作

制作対応版は `RIGMMaker.fullhd.exe`。既存の共通 `commandPipe` へ `movie-`接頭辞を付けて送る。通常のRIGM編集43命令はそのまま利用できる。制作編集は別の `projectId` と `revision` を使用し、`Send-RigmCommand.ps1` が `movie-status` から補う。制作ジョブは保存済みRIGMの独立スナップショットを使い、編集画面の未保存文書を変更しない。

演技・波形対応の制作命令は31件。`movie-schema` の `actingFields` に範囲と意味がある。`movie-update-cue` の `acting` は部分更新で、省略した項目を保持する。演技・字幕だけの編集は生成済み音声を失効させない。

```powershell
# 以下はこの節のInvoke-Movie関数を定義した後に実行する。
# cueId、groupId、partIdはmovie-project / movie-assetsで取得した実在IDを指定する。
Invoke-Movie 'assets-refresh'
# job-statusがdone=trueかつsucceededになってから一覧を取得する。
Invoke-Movie 'job-status'
Invoke-Movie 'assets' @{offset=0;limit=20}
Invoke-Movie 'update-cue' @{id=$cueId;acting=@{
    mouthGain=0.8;lipLead=0.03;blinkInterval=3.2
    headGain=0.7;bodyGain=0.5;onset=0.1;duration=-1;fadeIn=0.2;fadeOut=0.2
    variants=@(@{groupId=$groupId;partId=$partId})
}}
Invoke-Movie 'waveform-refresh'
Invoke-Movie 'job-status'
# 波形の生成終了後に取得。current=falseなら音声・間の変更後に取得し直す。
Invoke-Movie 'waveform'
Invoke-Movie 'timeline'
Invoke-Movie 'seek' @{time=12.5}
Invoke-Movie 'preview' @{time=12.5}
```

素材一覧はページ取得でき、既定20・最大100グループ。選択は同じグループの直下の子だけで、元RIGMの表示状態を変更しない。存在しないIDや矛盾した入れ子選択はプレビュー／出力時に失敗する。制作ファイルを開いた後は素材・波形一覧を取得し直す。[制作仕様](../動画制作/仕様.md)と[今回の検証範囲](../動画制作/README.md#今回の提供版と性能検証)を参照する。

```powershell
$sender = 'D:\DelphiProg\RIGMMaker\制作支援\パイプ\Send-RigmCommand.ps1'
# connectionFileには操作対象の編集画面の接続情報ファイルを指定する。
function Invoke-Movie([string]$command, [hashtable]$arguments=@{}) {
    & $sender -ConnectionFile $connectionFile -Command ('movie-'+$command) `
        -ArgsJson ($arguments | ConvertTo-Json -Depth 32 -Compress) | ConvertFrom-Json
}
Invoke-Movie 'open-ui'
Invoke-Movie 'schema'
Invoke-Movie 'import-script' @{text="# 紹介`nnarrator:これは自作の紹介です。"}
Invoke-Movie 'update-project' @{character='D:\作品\character.rigm';width=1280;height=720;fps=30}
Invoke-Movie 'speakers-refresh'
# job-statusがdone=trueになるまで確認し、speaker-listの実在するstyleIdを選ぶ。
Invoke-Movie 'speaker-list'
Invoke-Movie 'update-speaker' @{id='narrator';styleId=$selectedStyleId;speed=1.0}
Invoke-Movie 'audio-generate'
Invoke-Movie 'job-status'
Invoke-Movie 'preview' @{time=0.5}
Invoke-Movie 'play'
Invoke-Movie 'pause'
Invoke-Movie 'save' @{path='D:\作品\紹介.rigmovie'}
Invoke-Movie 'export' @{path='D:\作品\紹介-new.avi'}
# 任意のMP4: 既存のFFmpegを明示して、新しい出力先を使う。
Invoke-Movie 'update-project' @{ffmpeg='C:\Tools\ffmpeg\bin\ffmpeg.exe'}
Invoke-Movie 'export' @{path='D:\作品\紹介-new.mp4'}
```

音声生成・話者一覧取得・プレビュー・出力は非同期で、開始応答は完了を意味しない。次の編集やジョブを送る前に `movie-job-status` の `done=true` と `state=succeeded` を確認する。完了応答の `collected=true` は結果を制作プロジェクトへ反映済みであることを示す。`jobId` と `snapshotProjectId` / `snapshotRevision` で対象を確認できる。エラーは `state=failed` と `error`。取消は `movie-job-cancel`、直後の `movie-job-retry` は取消完了後に一度だけ再試行する。部分成功した音声は保持し、再試行は未生成の発話だけを処理する。プロジェクトを開き直すと以前の再試行対象を消去する。

`movie-project {offset,limit}` は台本をページ分割して取得できる。要求・応答は従来どおり60,000 UTF-8 bytesまで。長い台本やJSONは `movie-import-script {path,format:"text"|"json"}` でローカルファイルから読む。JSON取込は指定した動画寸法・fps・話者設定を尊重する。`movie-timeline` は全件を返すため、非常に長い台本では応答上限エラーになることがある。

制作画面と制限、VOICEVOXの現在の未検証範囲は[動画制作の利用手順](../動画制作/README.md)。実音声への接続は正常なローカルVOICEVOX Engineが必要で、通常処理に試験音の自動代替はない。

### 出力プリセット・演技方式・工程進捗（fullhd版）

上部UIと同じプロジェクト設定を、既存の共通commandPipeで変更できる。プリセットと方式は保存・再開される。`movie-schema.outputPresets`と`actingFields`が引数の基準。追加の独立パイプはない。

```powershell
Invoke-Rigm 'movie-update-project' @{outputPreset='fullhd';encodeProfile='fast'}
# 寸法を明示するとプリセットの値より優先される。
Invoke-Rigm 'movie-update-project' @{outputPreset='hd';width=1600;height=900;fps=30;encodeProfile='balanced'}
Invoke-Rigm 'movie-update-cue' @{id=$cueId;acting=@{mouthMode='auto';blinkMode='assets'}}
Invoke-Rigm 'movie-export' @{path='D:\制作\新しい動画.mp4'}
$job = Invoke-Rigm 'movie-job-status'
# phase / phaseCompleted / phaseTotal / elapsedSeconds / remainingSeconds
# encoderPeakPrivateBytes / encoderPeakWorkingSetBytes / exportStagingPeakBytes
# encoderProcessId / encoderExited
Invoke-Rigm 'movie-job-cancel'
```

outputPresetはdraft/hd/fullhd/custom、encodeProfileはfast/balanced/quality。mouthMode/blinkModeはauto/assets/deform。進捗のphaseはprepare-character/prepare-audio/render/encode。remainingSeconds=-1は未算出、完了後0で、残り時間は現在の工程の概算。描画中の残り時間には後続の圧縮を含めない。

取消要求の成功後、`movie-job-status`でdoneとstateを確認する。FFmpegを使ったジョブではencoderExitedで終了状態を確認できる。仮ファイルを整理してからdoneを返す。既存出力を上書きせず、生成途中に出現した出力も保持する。保存済み原素材や編集中RIGMの未保存変更へ書き込まない。

前版の履歴：[fullhd版の最終検証記録](../../Win64/Validation/fullhd-release-verification.json)に104項目のUI/共通パイプ検証と10項目のPowerShell送信器検証を記録した。全系列の最新成功判定は774項目で、再実行と過去版の結果は重複加算していない。実VOICEVOX復旧は保留で、検証音声は明示的テスト音。


### 読取診断と次の操作（guided版）

次の例は上のInvoke-Movieを使用する。台本本文・実在素材・利用声・出力先はユーザーの値を用い、診断で修復や自動保存はしない。

```powershell
Invoke-Movie 'diagnostics-refresh'
do {
    $d = Invoke-Movie 'job-status' @{scope='diagnostics'}
    if (-not $d.data.done) { Start-Sleep -Milliseconds 200 }
} until ($d.data.done)
$p = Invoke-Movie 'preparation' @{outputPath=$newOutputPath}
$p.data.issues | Select-Object code,message,nextAction,subjectId,blocking
$p.data | Select-Object nextCommand,nextArgs,nextArgsRequireUserValues,canGenerateAudio,canPreview,canExport
# 診断だけ取り消す場合（通常は上の完了を待つ）
Invoke-Movie 'job-cancel' @{scope='diagnostics'}
# 不足素材の切替指定を戻す場合: cueIdはmovie-projectから選んだ実ID
Invoke-Movie 'update-cue' @{id=$cueId;acting=@{mouthMode='auto';blinkMode='auto';variants=@()}}
# ボーン/メッシュが未準備なら、必要に応じてheadGain/bodyGain=0も指定する。
Invoke-Movie 'update-project' @{outputTarget=$newOutputPath}
Invoke-Movie 'preparation'
# 準備後は audio-generate → job-status → preview → job-status → export → job-status。
# 音声が保存済みで有効ならaudio-generateを省略できる。path省略はoutputTargetを使う。
Invoke-Movie 'export'
```

nextArgsの仮ID・未指定値は実データで置換する。mutationは送信器がmovie-statusのprojectId/revisionを補う。診断ジョブは制作ジョブとは独立し、制作Busyを立てない。issuesのsafe-actingはUI識別子で、nextCommand/nextArgsはパイプ編集として利用できる。例文はmovie-schema.examplesで架空例/構成テンプレートと明示する。3分を保証せず、台本へ自動取込しない。

今回の最終Win64 Debug/Releaseと回帰814項目、配布EXEの起動確認は[guided最終記録](../../Win64/Validation/guided-release-verification.json)参照。前版1080pの全復号・測定は別の保持基準。[制限と未検証](../動画制作/README.md#利用上の制限と未検証)も参照。
2026-10-04 UI整理版：通常の `D:\DelphiProg\RIGMMaker\RIGMMaker.exe` に最終Releaseを反映済み。開く／保存／別名保存／履歴はメニューに移動し、3ページのアイコンと再生／停止は保持。履歴は実ファイルごとに1件、復旧コピーは別管理。右側はスプリッターと縦スクロール、再生中の静的UI更新抑止に対応した。movie 64／app 5／core 43の共通パイプ契約は維持。起動中の他インスタンスが存在する場合は実履歴の自動移行を延期し、単独の新版起動時に安全に移行する。今回1835項目の検証記録と未検証範囲は `note.md` と `Win64/Validation/ui-revision-release-verification.json` を参照。
2026-10-04 メディア修正版：通常起動は `D:\DelphiProg\RIGMMaker\RIGMMaker.exe`。ファイル → 最近の作品 → 「星灯り郵便局・シーン編集版 [星灯り郵便局-画像付き編集版.rigmovie]」を開く。実作品は `C:\Users\zan12\Documents\RIGMMaker\Projects\星灯り郵便局-20261004T064959615\星灯り郵便局-画像付き編集版.rigmovie`、最終MP4は `C:\Users\zan12\Documents\RIGMMaker\Projects\星灯り郵便局-20261004T064959615\Exports\星灯り郵便局-画像付き編集版.mp4`。開くと停止・位置0、作業フォルダーにImages/Audio/Characters/Exportsを保管。シーン画像と共通背景は別項目で、画像採用は検証付きコピー・未保存のまま、明示保存後の再読込でも画像を維持する。標準出力はMP4。全体モーション4種は実キャラクター描画の回転/移動PNG列で、通常口パクを止める間も音声・字幕は続ける。全体モーションを停止するとLABの五母音口パクを使う。元作品と旧MP4は保持。SourceMatchedの人間確認は不要で、実際の素材不良は停止する。現行の実装・2080項目検証・未検証範囲は `../../note.md` と `../../Win64/Validation/media-release-verification.json`。API数はmovie64/app5/core43を維持し、新コマンドは追加していない。