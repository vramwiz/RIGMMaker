#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$validation=Join-Path $root 'Win64\Validation'
function Read-Record([string]$Path){
  if(-not [IO.Path]::IsPathRooted($Path)){$Path=Join-Path $validation $Path}
  Get-Content -LiteralPath $Path -Raw -Encoding utf8|ConvertFrom-Json
}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
$selected=[Collections.Generic.List[object]]::new()
function Select-Json([string]$Name,[string]$Path,[int]$Expected){
  if(-not [IO.Path]::IsPathRooted($Path)){$Path=Join-Path $validation $Path}
  $record=Read-Record $Path
  if(-not $record.success -or $record.passed -ne $Expected){throw "Incomplete selected suite: $Name"}
  $selected.Add(@{name=$Name;record=$Path;sha256=(Sha $Path);passed=$record.passed;success=$true})
  return $record
}
function Select-Log([string]$Name,[string]$File,[int]$Expected){
  $path=Join-Path $validation $File
  $count=@(Select-String -LiteralPath $path -Pattern '^PASS:').Count
  if($count -ne $Expected){throw "Incomplete selected log: $Name ($count)"}
  $selected.Add(@{name=$Name;record=$path;sha256=(Sha $path);passed=$count;success=$true})
}
foreach($lane in @('Core','Media','Collaboration')){
  $r=Read-Record ('timeline-export-shipping-'+$lane+'-results.json')
  if(-not $r.success -or @($r.completed|Where-Object {-not $_.success}).Count){throw "Regression lane failed: $lane"}
}
Select-Log core 'timeline-export-shipping-Run-Validation.log' 519
Select-Log DPI 'timeline-export-final-Run-DpiValidation.log' 571
Select-Log movie 'timeline-export-shipping-Run-MovieValidation.log' 102
$workflow=Select-Json workflow 'movie-workflow-results.json' 133
$production=Select-Json production 'production-results.json' 42
$null=Select-Json collaboration 'collaboration-results.json' 66
$null=Select-Json resume 'resume-results.json' 47
$null=Select-Json sender 'movie-sender-results.json' 14
$null=Select-Json composition 'composition-results.json' 111
$quality=Read-Record 'quality-material.json'
$null=Select-Json quality (Join-Path $quality.directory 'timeline-export-final-results.json') 22
$null=Select-Json UI 'ui-revision-results.json' 108
$regressionPassed=($selected|Measure-Object passed -Sum).Sum
foreach($job in @(@{name='workflow';directory=$workflow.directory},@{name='production';directory=$production.directory})){
  foreach($format in @('AVI','MP4')){
    $null=Select-Json ($job.name+' independent '+$format) (Join-Path $job.directory ('Decoded'+$format+'\inspection.json')) 10
  }
}
$gui=Select-Json 'native GUI timeline/export' 'TimelineExportFixture\20261004T085330679\results.json' 83
$decode=Select-Json 'real GUI MP4 independent decode' 'timeline-export-independent-decode.json' 34
$delivery=Read-Record 'timeline-export-documents-delivery.json'
if(-not $delivery.success -or $delivery.sourceGuiExport -ne $decode.path -or $delivery.sha256 -ne $decode.sha256 -or (Sha $delivery.delivered) -ne $decode.sha256 -or (Sha $delivery.sourceWork) -ne $delivery.sourceWorkSha256){throw 'Delivered GUI movie or original source changed'}
$startups=@(foreach($label in @('timeline-export-Debug','timeline-export-Release','timeline-export-CurrentRoot','timeline-export-Shipping')){
  $r=Select-Json ('product startup '+$label) ('production-startup-'+$label+'.json') 22
  if(-not $r.gracefulExit -or $r.exitCode -ne 0 -or -not $r.sourceUnchanged -or (Sha $r.executable) -ne $r.exeSha256){throw "Product startup no longer matches executable: $label"}
  $r
})
$cleanup=Read-Record 'timeline-export-cleanup-result.json'
$helperCleanup=Read-Record 'timeline-export-helper-cleanup-result.json'
if(-not $cleanup.success -or $cleanup.permanentDeleteFallback -or @($cleanup.items|Where-Object {-not $_.recoverableVerified}).Count -or -not $helperCleanup.success -or $helperCleanup.sourceExists){throw 'Recoverable cleanup incomplete'}
$originals=Read-Record 'timeline-export-original-integrity.json'
foreach($original in $originals){if(-not $original.unchanged -or (Sha $original.path) -ne $original.sha256){throw 'Protected original changed'}}
$install=Read-Record 'timeline-export-install.json'
$external=Read-Record 'timeline-export-external-root-preserved.json'
if((Sha $install.alias) -ne $install.sha256 -or (Sha $install.preserved) -ne $install.preservedSha256 -or (Sha $external.preserved) -ne $external.sha256){throw 'Executable preservation/delivery mismatch'}
$builds=@(foreach($config in @('Debug','Release')){
  $path=Join-Path $validation ($config+'\RIGMMaker.exe')
  @{configuration=$config;path=$path;sha256=(Sha $path);buildLog=(Join-Path $validation ('timeline-export-build-'+$config+'.log'));startupPassed=22}
})
$passed=($selected|Measure-Object passed -Sum).Sum
if($regressionPassed -ne 1735 -or $passed -ne 1980){throw "Unexpected successful selection total: $passed"}
$summary=@'
## 2026-10-04 タイムライン／GUI MP4書き出し修正・最終検証完了

この節を現行仕様として優先する。以前のクリップ文字非表示、旧出荷EXE、検証件数は各段階の履歴である。

時間ルーラーは38論理px、見出しは96論理px、文字は16論理px、各行は最低34論理pxとし、UIのDPIだけで拡大する。映像はシーン名/画像名、キャラは名前/表情または全体モーション、音声は話者/セリフ、字幕は本文を表示する。短いクリップは省略表示し、ヒントで全内容と時刻を確認できる。サムネイルの縦横比と静的キャッシュを保持し、時間ラベルの間隔は狭幅に追従する。100/125/150/200%・幅640/1200の実描画とキャッシュ保持を検証した。

GUI出力は「ファイル → 動画を書き出す → MP4（映像・音声）...」（Ctrl+Shift+E）、またはプレビューの「MP4出力...」。保存先を選び、進捗表示を待ち、完了後に「保存先を開く」を押す。処理中は「書き出しを中止」で中止できる。工程の切替やパイプ操作は不要。AVIは同メニューの明示選択を維持する。

旧GUIでMP4が出なかった原因は、保存済み出力先があると保存先選択を省略し、既存ファイル保護により出力が拒否されていたこと。現在は毎回保存先を選び、既存ファイルがある場合は未使用の候補名を提示する。既存ファイルは上書きしない。選択キャンセルで作品のrevision/出力先を変更しない。FFmpeg未設定は既存実行ファイルを選ぶ。未適用編集、編集ロック、欠落音声、エラーは表示する。セリフ変更が保存済み音声に未反映の構成作品は、その旨を表示して既存WAVを使用する。音声の自動再生成は行わない。

変更した製品ソースはSource/Studio/RigmMovieTimeline.pas、RigmMovieSession.pas、RigmMovieForm.pas。工程テストは保存ダイアログとFFmpeg選択ダイアログを実操作する形へ更新し、実際のMP4生成とcollected/encoderExitedを確認した。ネイティブGUIテストはWindows保存ダイアログを使い、選択キャンセル、出力中止、setupからの全作品出力、完了表示を確認した。テスト用プロセスだけ旧形式のネイティブ共通ダイアログを有効にし、製品の共通ダイアログ設定は変更していない。

検証済みReleaseは `@LAUNCH@`。SHA256 `6D37884DAB5E49DFE94B70E3E6938C091B222E5DB8937C4058631C305037B364`。Win64 Debug SHA256は `B0BCA2F2F9FE23FA70B5303D69FB21D498FFD8BFE87EE964B49BFB0E14D00F40`。

通常の `@NORMAL@` は09:04 UTCに上記Releaseを反映した後、09:16 UTCに別のDebugビルドへ更新された。現在のSHA256は `D2E8905B9764A86F4E172514655AA4324EC56CEC3EFEC311D1D6274FDC791AF4`。この現在EXEも隔離起動22項目成功。実行中ユーザーアプリを維持して再上書きせず、現在ビルドと開始時ビルド `5B0EB8D2B19E2897432CE3C6F92E33D0DFD75CC94280FBF5EF45A936195E6F4F` をWin64/PreservedArtifactsへSHA256一致で保管した。Source配下のコードは最終ビルド後に追加変更されていない。外部ビルドでRIGMMaker.resは09:15:58 UTCに更新されたため、最終source manifestはこの現在の生成リソースも含む。検証済みDebug/ReleaseのビルドログとEXEはそれぞれの実ビルド結果として保持する。

GUIで全作品を書き出したMP4は `@MOVIE@`。1920×1080、30fps、H.264/AAC、1117フレーム、映像37.233333秒/音声37.233秒、SHA256 `F093206A13DF2D20EB148D1B4DAC9A03A43F004A091E4E1FEBCBAE52EDE448FB`。元作品 `@WORK@` のSHA256 `278EF70FEA76D7602CF0DC9ECE313ACB0CC8F1CB68899756170B714689C545E8` は変更なし。元のMP4と過去版も維持する。

最終成功は1980項目。各スイートで最新の成功を選び、重複実行・失敗した旧テスト・前段階2080項目を加算しない。回帰1735（core519、DPI571、movie102、workflow133、production42、collaboration66、resume47、sender14、composition111、quality22、UI108）、回帰AVI/MP4独立デコード40、ネイティブGUI83、実作品MP4独立デコード34、製品起動Debug/Release/現在通常EXE/別名出荷EXE各22の88。実作品の五母音LABフレーム、四シーン、全体モーションのサイズ/移動、実音声の波形相関0.9999666も確認した。PSD、Pro HID入力経路、高速プロパティ更新、子UIホイール、共通パイプ、開いた時の分類と手動役割/ロック保護を回帰対象に含む。

コピー元ToolBarPanelManager/SerifToolbarIcons、元RIGM/PSD/画像など保護対象39ファイルのSHA256は一致。開いた時に未分類を再判定し、自動保存せず、廃止済みSourceMatched人間確認を工程条件にしない。本当の必須不足/破損/不整合は停止する。今回の出力テストはユーザー作品・履歴・未保存文書を変更せず、所有テストの待機ダイアログだけキャンセルし自然終了した。commit/pushは行っていない。

使い捨てEXE/DCU・所有作品コピー・Documents配置済みGUI MP4テストコピー@CLEANUP_COUNT@項目（@CLEANUP_BYTES@ bytes）をごみ箱へ回収し、元パスの$Iメタデータと全$RペイロードSHA256を確認した。Tempヘルパーも別途回収・全SHA256照合済み。永久削除へのフォールバックはない。ログ、JSON、PNG、出荷EXE、元作品とDocuments出力は保持する。Windowsごみ箱から元パスへ復元できる。対応先はtimeline-export-cleanup-result.jsonとtimeline-export-helper-cleanup-result.jsonを参照する。

未実施は人によるデスクトップGUIのマウス目視操作、連続視聴/聴取、実モニターのDPI切替、実Pro HID機器。PNGは所有VCLのPaintTo画像をモデルで確認したもので、ネイティブメニューバー/一部共通コントロールを含むデスクトップ全体の確認とは区別する。GUI自動操作と全フレーム・PCMの独立検証結果を人の主観確認として扱わない。

最終記録はWin64/Validation/timeline-export-release-verification.json、timeline-export-source-manifest.json。GUI結果と描画PNGはTimelineExportFixture/20261004T085330679、実動画の独立検証はtimeline-export-independent-decode.json。以下は過去段階の履歴。

---

'@
$summary=$summary.Replace('@LAUNCH@',$install.alias).Replace('@NORMAL@',$external.source).Replace('@MOVIE@',$delivery.delivered).Replace('@WORK@',$delivery.sourceWork).Replace('@CLEANUP_COUNT@',[string]$cleanup.count).Replace('@CLEANUP_BYTES@',[string]$cleanup.bytes)
foreach($name in @('note.md','編集実装と検証.md')){
  $path=Join-Path $root $name
  $old=[IO.File]::ReadAllText($path)
  if($old.StartsWith('## 2026-10-04 09:06 UTC ') -or $old.StartsWith('## 2026-10-04 タイムライン／GUI MP4書き出し修正')){
    $end=$old.IndexOf("`n---")
    if($end -lt0){throw 'Checkpoint boundary missing'}
    $old=$old.Substring($end+5).TrimStart([char]13,[char]10)
  }
  [IO.File]::WriteAllText($path,$summary+$old,[Text.UTF8Encoding]::new($false))
}
$spec=@'
## 2026-10-04 現行：時間とオブジェクト内容・GUI MP4出力

時間ルーラー38論理px、見出し96論理px、文字16論理px、各行最低34論理px。映像はシーン名/画像名、キャラは名前/表情または全体モーション、音声は話者/セリフ、字幕は本文を表示する。狭幅では範囲内の省略表示と全内容ヒントを使い、DPIに追従する。画像比率と静的キャッシュを維持する。以前のクリップ文字非表示の方針は今回の最新指示で置き換える。

ファイル → 動画を書き出す → MP4（映像・音声）...、Ctrl+Shift+E、またはプレビューのMP4出力...から直接書き出す。工程切替と人間確認フラグは不要。毎回保存先を選択し、既存出力を保護する。進捗・中止・完了/保存先を開くを表示する。セリフに未反映の保存済み音声は明示し、自動再生成しない。欠落/破損/不整合・編集ロックは止める。既存movie64/app5/core43 APIと保存形式は維持する。最終1980項目と出荷EXE/未検証範囲はnote.md先頭およびWin64/Validation/timeline-export-release-verification.jsonを参照する。

'@
foreach($name in @('RIGM_Maker_編集仕様.md','RIGM仕様.md')){
  $path=Join-Path $root $name
  $old=[IO.File]::ReadAllText($path).Replace('クリップ内小文字は表示しない。','クリップ内にシーン/キャラ/話者/字幕の内容を16論理pxで表示し、短い部分は省略とヒントを使う。')
  if(-not $old.Contains('## 2026-10-04 現行：時間とオブジェクト内容・GUI MP4出力')){
    $index=$old.IndexOf("`n")+1
    $old=$old.Insert($index,"`n"+$spec)
  }
  [IO.File]::WriteAllText($path,$old,[Text.UTF8Encoding]::new($false))
}
$guide=@'
## 2026-10-04 GUI MP4書き出しの現行手順

1. 検証済みRelease `@LAUNCH@` で作品を開く。現在の通常EXEも作品open起動検証済み。両者のSHA256と保管先はnote.md先頭を参照する。
2. 「ファイル → 動画を書き出す → MP4（映像・音声）...」、またはプレビューの「MP4出力...」（Ctrl+Shift+E）を押し、新しい保存先を選ぶ。
3. 進捗表示を待ち、完了後に「保存先を開く」。処理中は「書き出しを中止」で中止できる。

工程切替やパイプ操作は不要。出力済みの同名ファイルは保護する。FFmpegが未設定なら既存ffmpeg.exeを選ぶ。セリフ変更が音声に未反映の構成作品は警告を表示して保存済み音声を使用し、自動再生成しない。必要な音声がない場合は出力できない理由を表示する。

GUIで実際に生成した実画像/実音声MP4は `@MOVIE@`。元作品・既存MP4は変更なし。時間と四トラックはDPIに追従する16論理pxの文字で、各オブジェクトの内容を表示する。

検証済み範囲と未検証範囲、全1980項目、回収記録は `../../note.md` と `../../Win64/Validation/timeline-export-release-verification.json`。再実行はTests/Run-TimelineExportValidation.ps1のSourceMovieに実作品を指定する。これは4シーン実画像/音声作品用の隔離GUIテストで、全MP4出力には数分かかる。パイプAPIの64/5/43コマンドと素材/作品形式は今回変更していない。以下の段階別件数は過去の記録である。

'@
$guide=$guide.Replace('@LAUNCH@',$install.alias).Replace('@MOVIE@',$delivery.delivered)
foreach($name in @('制作支援\動画制作\README.md','制作支援\パイプ\README.md')){
  $path=Join-Path $root $name
  $old=[IO.File]::ReadAllText($path).Replace('D:DelphiProgRIGMMakerRIGMMaker.timeline-export-20261004T090459.exe',$install.alias)
  if(-not $old.Contains('## 2026-10-04 GUI MP4書き出しの現行手順')){$old=$old.Insert($old.IndexOf("`n")+1,"`n"+$guide)}
  [IO.File]::WriteAllText($path,$old,[Text.UTF8Encoding]::new($false))
}
$prior=Read-Record 'media-source-manifest.json'
$paths=@($prior.path)+@((Join-Path $PSScriptRoot 'RigmTimelineExportTests.dpr'),(Join-Path $PSScriptRoot 'RigmNativeSaveDialog.pas'),(Join-Path $PSScriptRoot 'Run-TimelineExportValidation.ps1'),$PSCommandPath)
$manifest=@(foreach($path in $paths|Sort-Object -Unique){@{path=$path;sha256=(Sha $path);bytes=(Get-Item -LiteralPath $path).Length}})
$manifest|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $validation 'timeline-export-source-manifest.json') -Encoding utf8
$report=@{success=$true;completedUtc=[DateTime]::UtcNow.ToString('o');passed=$passed;regressionPassed=$regressionPassed;countPolicy='latest successful selection per suite; repeated/failed/previous-stage tests excluded; startup checks separately cover Debug, Release, current external root and shipped alias';tests=@($selected);builds=$builds;launchExecutable=$install.alias;launchSha256=$install.sha256;currentNormalExecutable=$external.source;currentNormalSha256=(Sha $external.source);currentNormalExternallyRebuilt=$true;currentNormalStartupPassed=22;preservedInitialExecutable=$install.preserved;preservedInitialSha256=$install.preservedSha256;preservedExternalExecutable=$external.preserved;preservedExternalSha256=$external.sha256;delivery=$delivery;gui=$gui;independentRealMovieDecode=$decode;cleanup=@{count=$cleanup.count;bytes=$cleanup.bytes;record=(Join-Path $validation 'timeline-export-cleanup-result.json');success=$cleanup.success;permanentDeleteFallback=$false;temporaryHelperRecord=(Join-Path $validation 'timeline-export-helper-cleanup-result.json');temporaryHelperSuccess=$helperCleanup.success};protectedOriginalCount=$originals.Count;protectedOriginalsUnchanged=$true;sourceManifest=(Join-Path $validation 'timeline-export-source-manifest.json');sourceManifestSha256=(Sha (Join-Path $validation 'timeline-export-source-manifest.json'));apiCounts=@{movie=64;app=5;core=43};humanDesktopVerification=$false;modelInspectedOwnedPaintToImages=$true;unverified=@('human desktop mouse/visual workflow','continuous human playback/listening','physical monitor DPI switching','physical Pro HID hardware');userApplicationsForcedClosed=$false;userUnsavedDocumentsModified=$false;commitPushPerformed=$false;remainingImplementationBlockers=@()}
$resource=Get-Item -LiteralPath (Join-Path $root 'RIGMMaker.res')
$report.externalBuildResource=@{path=$resource.FullName;sha256=(Sha $resource.FullName);lastWriteTimeUtc=$resource.LastWriteTimeUtc.ToString('o');changedAfterSelectedDebugReleaseBuilds=$true}
$report.sourceManifestRole='final source/document inventory, including the resource generated by the later external root build; selected Debug/Release binaries and their original build logs remain separately identified'
$report|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $validation 'timeline-export-release-verification.json') -Encoding utf8
$progress=Read-Record 'timeline-export-progress.json'
$progress.status='completed'
$progress.atUtc=[DateTime]::UtcNow.ToString('o')
$progress.pending=@()
$progress.workflowRegressionBlocker='Resolved: owned native FFmpeg/open and MP4/save pickers exercised; 133 checks succeeded'
$progress.normalExecutableSha256=$report.currentNormalSha256
$progress.productStartupPassed=88
$progress|Add-Member -NotePropertyName finalPassed -NotePropertyValue $passed -Force
$progress|Add-Member -NotePropertyName workflowRegressionPassed -NotePropertyValue 133 -Force
$progress|Add-Member -NotePropertyName installedReleaseSha256 -NotePropertyValue $report.launchSha256 -Force
$progress|Add-Member -NotePropertyName currentNormalExternallyRebuilt -NotePropertyValue $true -Force
$progress|Add-Member -NotePropertyName releaseVerification -NotePropertyValue (Join-Path $validation 'timeline-export-release-verification.json') -Force
$progress|Add-Member -NotePropertyName currentNormalSha256 -NotePropertyValue $report.currentNormalSha256 -Force
$progress|Add-Member -NotePropertyName launchExecutable -NotePropertyValue $report.launchExecutable -Force
$progress|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $validation 'timeline-export-progress.json') -Encoding utf8
@{success=$true;passed=$passed;regressionPassed=$regressionPassed;launchExecutable=$report.launchExecutable;launchSha256=$report.launchSha256;currentNormalSha256=$report.currentNormalSha256;documentsMovie=$delivery.delivered;recycledCount=$cleanup.count;recycledBytes=$cleanup.bytes;sourceFiles=$manifest.Count}|ConvertTo-Json
