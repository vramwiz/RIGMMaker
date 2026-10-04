#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$recordPath=Join-Path $root 'Win64\Validation\guided-release-verification.json'
$r=Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if(-not $r.success -or -not $r.smoke.normalClose){throw 'Guided release is not verified'}
$aliasLeaf=Split-Path -Leaf $r.alias
$oldExeCount=$r.preservedExecutables.Count
$encoding=[Text.UTF8Encoding]::new($true)
function Write-Doc([string]$Relative,[string]$Text){[IO.File]::WriteAllText((Join-Path $root $Relative),$Text,$encoding)}
$guidePath=Join-Path $root '制作支援\動画制作\README.md'
$guide=[IO.File]::ReadAllText($guidePath).Replace('RIGMMaker.fullhd.exe','RIGMMaker.guided.exe').Replace('fullhd-release-verification.json','guided-release-verification.json')
$guide=$guide.Replace('RIGMMaker.guided.exe',$aliasLeaf).Replace('既存EXE10本',('既存EXE'+$oldExeCount+'本'))
$oldGuided=$guide.IndexOf('## 制作案内と読取事前診断')
if($oldGuided -ge 0){$guide=$guide.Substring(0,$oldGuided)}
$guide=$guide.Replace('**774項目**','**814項目を今回実行**').Replace('既存回帰527、動画コア73、制作UI/共通パイプ104、動画PowerShell送信器10、短尺AVI/MP4の独立復号各10、実素材22、1080p全復号18を各1回集計した。','既存回帰527、動画コア102、制作UI/共通パイプ129、動画PowerShell送信器14、短尺AVI/MP4の独立復号各10、実素材22を今回各1回集計した。前版の1080p全復号18項目と180秒の速度測定は、描画・演技・音声・AVI・出力の5ユニットがSHA256一致する基準記録として保持し、今回の814項目へ加算していない。')
$guide=$guide.Replace('既存EXE9本','既存EXE10本')
$guide=[regex]::Replace($guide,'(?m)^.*\*\*814項目を今回実行\*\*.*$','今回の成功項目は **814項目**。既存回帰527、動画コア102、制作UI/共通パイプ129、動画PowerShell送信器14、短尺AVI/MP4独立復号各10、実素材22を今回各1回集計した。前版1080p全復号18項目と180秒の測定は基準として保持し、今回の814へ加算していない。描画・演技・音声・AVI・出力5ユニットのSHA256は基準と一致する。最終Win64 Debug/Releaseの警告・エラー・ヒントは0。')
$tail=$guide.IndexOf('## 次の改善優先')
if($tail -ge 0){$guide=$guide.Substring(0,$tail)}
$guide+=@'
## 制作案内と読取事前診断

上部に「台本取込 → 話者・キャラ・素材 → 音声生成 → プレビュー → 出力」と現在の準備状態を表示する。「次の操作」は必要な取込・設定・音声生成・プレビュー・出力へ進む。最初の台本欄は空で、ユーザーの台本を作成・評価しない。

「準備を診断」はVOICEVOXの話者一覧と保存済みRIGMを別の読取ジョブで確認する。診断中も台本・設定を編集できる。右側を診断欄までスクロールし、不備のコード、修正すべき内容、利用できる演技、概算時間、一時容量、空き容量を表示する。編集途中の未適用入力を診断完了時に書き換えない。エンジンの起動・修復、素材の変更、自動保存は行わない。取消アイコンで診断と制作処理を取り消せる。

1. 自分の台本を貼り付けて「次の操作」または「入力した台本を取り込む」を押す。
2. 保存済みRIGMを選び、接続先・寸法・画質を設定する。「準備を診断」で実際の話者一覧を取得し、話者ごとの声を選んで「音声設定適用」を押す。
3. 「次の操作」で音声を生成する。字幕・演技の変更では既存音声を再生成しない。失敗した場合は具体的な理由を表示し、成功済みの音声を保持する。
4. 「次の操作」でプレビューする。素材にない口・目の切替を指定している場合は「使える演技へ戻す」で選択中セリフの口/瞬きを自動、素材選択を解除し、ボーン/メッシュがない場合は頭/上半身の強度を0にする。元素材は変更しない。
5. 上部の「新しい出力先」に未使用の絶対パス（.avi/.mp4）を設定して「設定適用」を押す。MP4は既存FFmpegを選ぶ。「次の操作」で出力する。既存出力を上書きせず、追加の必須確認は挟まない。
6. 保存アイコンで`.rigmovie`を保存し、再度開いて診断する。出力先・演技・音声参照を保持して再開する。同じ接続先・話者・本文の保存済み音声が有効なら、エンジン停止中でもプレビュー・出力できる。

台本例の選択欄には「架空の短い紹介例」と「3分紹介の構成テンプレート」がある。「選択した例を入力欄へ表示」を明示的に押した場合だけ、入力欄へ表示する。取り込みは別の操作。3分テンプレートは6区間の構成案で、【】の内容をユーザーが置換する。実音声の速度と間によって長さが変わり、180秒を保証しない。例文で既存の制作台本を自動置換しない。

## 利用上の制限と未検証

今回の依頼範囲で実装・回帰検証を残した項目はない。ただし、実VOICEVOXの起動不良があり、日本語の実音声生成と実音声での口パク品質は外部環境の未検証として残る。修復未承認のためインストール内容を変更していない。通常処理でテスト音を代替生成しない。

- 素材にない自然な横向き・後ろ向きや新しい表情画像は生成しない。既存画像の切替・変形を利用する。頭と上半身の動きにはボーンとメッシュの準備が必要。未準備素材でも静止表示と既存ポーズ差分は利用できる。
- MP4も一時AVIを経由するため2GB上限がある。サイズ・fps・尺を抑える必要がある。
- 診断の時間・容量は1080p/30fps/速度優先の保存済み基準からの目安。PC・素材に依存し、標準/画質優先の係数は未実測。書込権限とFFmpegの起動・コーデックは読取診断では試さず、実際の出力時にエラーを報告する。
- GUIの素材選択一覧は先頭20グループ。パイプの`movie-assets`はページ取得できる。
- 物理デスクトップの手操作、実Pro HID入力、複数モニターDPI、最大密度メッシュでの性能は未検証。画面確認は隔離したVCLフォームのPaintTo画像を閲覧した範囲。

[最終検証JSON](../../Win64/Validation/guided-release-verification.json)に今回の検証と保持した1080p基準を分けて記録した。
'@
Write-Doc '制作支援\動画制作\README.md' $guide
$specPath=Join-Path $root '制作支援\動画制作\仕様.md'
$spec=[IO.File]::ReadAllText($specPath).Replace('RIGMMaker.fullhd.exe','RIGMMaker.guided.exe').Replace('計31命令','計33命令')
$spec=$spec.Replace('RIGMMaker.guided.exe',$aliasLeaf)
$oldGuided=$spec.IndexOf('## guided版の案内と事前診断')
if($oldGuided -ge 0){$spec=$spec.Substring(0,$oldGuided)}
$spec=$spec.Replace('最新段階の成功項目','前版fullhdの成功項目')
$spec+=@'

## guided版の案内と事前診断

`outputTarget`は新しいAVI/MP4出力先としてproject JSONと保存ファイルに保持する。`movie-export`はpath省略時にoutputTargetを用いる。既存ファイルを上書きしない。

`movie-preparation {outputPath?}`は読取応答。steps[5]、issues（最大20件、totalIssues）、nextAction/nextCommand/nextArgs/nextArgsRequireUserValues、engine、availableStyles、capabilities、estimate、audioPending、canGenerateAudio/canPreview/canExport、diagnosticsCurrent/diagnosticsBusy、previewCurrentを返す。issuesはcode/message/nextAction/scope/subjectId/blocking。`safe-acting`はUI操作識別子で、機械用nextCommandは実在する`movie-update-cue`、nextArgsはauto/auto/variants解除などの編集内容。仮のID・パス・声はschemaと実データから置換する。編集前に最新movie-statusのprojectId/revisionが必要。

主なissueコード: script_empty、engine_unchecked、engine_unavailable、speaker_unavailable、audio_pending、character_none、material_unchecked、material_invalid、motion_unavailable、acting_unavailable、background_missing、output_missing、output_exists、output_format、ffmpeg_missing、disk_space_low、output_drive_unavailable、output_path_invalid、avi_staging_risk。

`movie-diagnostics-refresh`は別の取消可能な読取ジョブを起動する。`movie-job-status {scope:"diagnostics"}`で進捗確認、`movie-job-cancel {scope:"diagnostics"}`で診断だけ、scope=mainで制作だけ、省略/allで両方を取消す。診断成功は診断完了を意味し、engine.connectedとissuesを確認する。実音声生成・修復・自動保存は行わない。engine接続成功は話者一覧取得まで。realSpeechVerified=falseは診断が実音声を検証していないことを示す。

診断結果はエンジンURL・素材パス/サイズ/更新時刻・cue ID/口と目の方式/variantsで無効化する。古い診断結果を変更後の素材に適用しない。openはキャッシュとプレビュー準備状態をクリアして再診断する。診断は制作Busyを立てず、入力編集を許可する。例文はschema.examplesにfictional_example/structure_templateとして公開し、GUIでは明示的に選んだ場合だけ入力欄へ表示する。

今回のWin64 Debug/Releaseは診断0。今回の回帰814項目（527+102+129+14+10+10+22）。前版1080p全復号18項目は描画系5ユニットのSHA256一致を確認した基準として保持し、814へ加算しない。実装範囲に残作業はない。実音声、物理操作、DPI、AVI上限、既存素材だけの演技、性能概算の制限は[操作ガイド](README.md#利用上の制限と未検証)と[今回の最終記録](../../Win64/Validation/guided-release-verification.json)に記載。
'@
Write-Doc '制作支援\動画制作\仕様.md' $spec
$pipePath=Join-Path $root '制作支援\パイプ\README.md'
$pipe=[IO.File]::ReadAllText($pipePath).Replace('動画対応版は `RIGMMaker.fullhd.exe`','動画対応版は `RIGMMaker.guided.exe`').Replace('制作命令は31個','制作命令は33個')
$pipe=$pipe.Replace('動画対応版は `RIGMMaker.guided.exe`',('動画対応版は `'+$aliasLeaf+'`'))
$oldGuided=$pipe.IndexOf('### 読取診断と次の操作（guided版）')
if($oldGuided -ge 0){$pipe=$pipe.Substring(0,$oldGuided)}
$pipe=[regex]::Replace($pipe,'(?m)^(\[fullhd.*774.*)$','前版の履歴：$1')
$pipe+=@'

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
'@
Write-Doc '制作支援\パイプ\README.md' $pipe
$summary=@'
**最新提供版: `RIGMMaker.guided.exe`。** [操作ガイド](制作支援/動画制作/README.md)、[最終検証](Win64/Validation/guided-release-verification.json)参照。案内ラベルの最小幅表示、初回/不足設定/診断取消/保存再開、パイプと例、次の操作からの出力まで完了。今回814項目成功、最終Win64 Debug/Releaseの警告・エラー・ヒント0、別名Releaseの隔離起動/通常終了を確認。旧EXE10本、原素材、ユーザー仕様と未保存文書は保持。前版1080p基準18項目と180秒の測定は保持し今回の814へ加算しない。今回の実装範囲に残作業はない。実VOICEVOXは修復未承認で実音声未検証。素材にない自然な顔向き、新規表情生成、AVI一時ファイル2GB上限、読取診断の権限/コーデック未試験、物理操作/DPI/最大性能未検証は操作ガイドに明記。以下の中間記録・fullhd記録は履歴。

'@
$summary=$summary.Replace('RIGMMaker.guided.exe',$aliasLeaf).Replace('旧EXE10本',('旧EXE'+$oldExeCount+'本'))
foreach($relative in @('note.md','編集実装と検証.md')){
  $old=[IO.File]::ReadAllText((Join-Path $root $relative));
  if($old.StartsWith('**最新提供版:')){$old=[regex]::Replace($old,'\A[^\r\n]*\r?\n','')}
  if($relative -eq '編集実装と検証.md'){$oldGuided=$old.IndexOf('## guided版の完了記録');if($oldGuided -ge 0){$old=$old.Substring(0,$oldGuided)}}
  Write-Doc $relative ($summary+[Environment]::NewLine+$old)
}
$details=@"

## guided版の完了記録（$($r.atUtc)）

変更: RigmMoviePreparation追加、MovieJobsの独立読取診断、MovieSessionの診断キャッシュ/取消と再開、MovieModelのoutputTarget、MovieFormの案内/次操作/不足演技復帰/明示例文と最小幅ラベル、PowerShell送信器の33命令対応。コピー元のToolBarPanelManager、SerifToolbarIcons、VOICEVOX関連7ライブラリはSyncroh2原本のハッシュを再確認して保護した。

今回: 既存527、コア102、制作UI/パイプ129、動画送信器14、AVI/MP4復号各10、実素材22 = 814。前版5400フレーム/180秒の独立復号18項目と386.265秒の測定は基準として保持し、今回の実行件数へ加算していない。描画/演技/音声/AVI/出力5ユニットのSHA256が基準と一致する。

EXE: $($r.alias)
Release SHA256: $($r.releaseSha256)
Debug SHA256: $($r.debugSha256)
旧EXE保管: $($r.preservedDirectory)
起動: own PID $($r.smoke.pid)、inputIdle=$($r.smoke.inputIdle)、normalClose=$($r.smoke.normalClose)、exitCode=$($r.smoke.exitCode)。ユーザーアプリへ強制終了や文書変更は行わない。

VCL PaintTo画像で初回/最小幅/診断詳細を閲覧確認。物理デスクトップ操作を実施したとは記録しない。実VOICEVOXは既知のjaracoテキスト不足で起動不能、復旧未承認。音声経路はTEST TONEと明示した隔離HTTPで検証し、実音声に置換したとは主張しない。原素材のSHA256とユーザー編集仕様を保持。実装範囲は完了、利用上の制限・未検証は操作ガイドへ分離した。
"@
$impl=[IO.File]::ReadAllText((Join-Path $root '編集実装と検証.md')); Write-Doc '編集実装と検証.md' ($impl+$details)
$docs=@('note.md','編集実装と検証.md','制作支援\動画制作\README.md','制作支援\動画制作\仕様.md','制作支援\パイプ\README.md','制作支援\パイプ\Send-RigmCommand.ps1')
$r | Add-Member -NotePropertyName documentation -NotePropertyValue @($docs | ForEach-Object {@{path=(Join-Path $root $_);sha256=(Get-FileHash (Join-Path $root $_)).Hash}}) -Force
$r | Add-Member -NotePropertyName finalRecordAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
$r | Add-Member -NotePropertyName fixturePortClosed -NotePropertyValue (-not [bool](Get-NetTCPConnection -LocalPort 51234 -State Listen -ErrorAction SilentlyContinue)) -Force
$r | Add-Member -NotePropertyName visualInspected -NotePropertyValue @('studio-first-use.png','studio-minimum.png','studio-preparation-details.png') -Force
if((Get-FileHash (Join-Path $root 'RIGM_Maker_編集仕様.md')).Hash -ne '7EEE403987DC29F0620B06B6DD5ED680A1C12B655CB3F693F1F1228AFFB1B23D'){throw 'Original user spec changed'}
$r | Add-Member -NotePropertyName originalUserSpecProtected -NotePropertyValue $true -Force
$r | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $recordPath -Encoding utf8
Write-Output ('Documentation finalized; freshPassed='+$r.freshPassed+'; alias='+$r.alias)
