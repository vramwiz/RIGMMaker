# 第10段階：シーン画像・説明文

音声確認完了と全セリフの現在入力に一致する音声を確認してからNextでscenesへ進む。シーン内容と移動先を同じsnapshotで保存してから遷移する。シーンフレームは初回だけ生成し、メインフォーム内で保持する。全シーンの確認後Nextはsummaryを保存して遷移する。戻る・終了時は下書きを保持し、再開先は最後にNextで到達した画面。

## 操作

左にシーン番号と実画像サムネイル、中央に選択シーンの共通合成プレビューを表示する。↑↓で選択、Enterで説明文と外部Codexへの画像指示を編集、Ctrl+Enter / Escまたは入力完了アイコンで編集を終える。

説明文はScene.Descriptionに保存し、Cue.Text / Subtitle / VoiceReadingから独立する。画像と説明文、画像のみ、説明文のみ、表示なしを明示選択できる。表示なしでも素材を保持する。全シーンの確認完了は、選択した表示方式に必要な実画像・説明文が揃っている場合だけ受理する。

既存画像採用はPNG/JPEG/BMPの実decodeとサイズ確認を行い、原本を保持してプロジェクト内へhash検証コピーする。32MB以内、各辺8192px以内、16MP以内。パイプから指定する既存素材はdata root内に限定する。画像・説明文の変更は配役、話者UUID、保存済みキャラ配置、読み、字幕、WAV/LABを変更しない。

合成は既存RenderCompositionを利用する。画像・説明文は該当Sceneの全セリフとpaddingの全時間に表示する。中央型・L字型・逆L字型の共通領域で比率fitし、FHD以外の画像も比率を保つ。シーン変更による保存済みキャラ配置の再生成は行わない。

## 外部画像要求と共通パイプ

アプリは画像を生成しない。画像指示からrequestId、sceneId、sceneNumber、fingerprint、prompt、state=pending、provider=external-codexを保存し、Codexが共通パイプで読んで外部で処理する。生成完了は返された実PNGの検証・採用後にのみ記録する。取消は現在の素材を保持する。

- app-script-scenes：最新projectId/revisionで1シーンずつ取得。duration、最大10sourceCues、要求、プレビューjob/pathを返す。
- app-script-select-scene / edit-scene / adopt-scene-image / request-scene-image / cancel-scene-image / complete-scenes / preview-scene：最新projectId/revisionが必須。edit-sceneはdescription、prompt、displayModeを任意指定する。
- app-script-image-transfer-begin：最新projectId/revision、sceneId、requestId、byteCount、sha256、mimeType=image/png、provenance必須。由来はexternal-generated / existing-material / test-fixtureの明示値。
- app-script-image-transfer-chunk：transferId、offset、canonical base64。1chunk最大16384bytes。finish後に非同期hash/CRC/decode/寸法確認、既存の安全なproject由来パスへ公開する。
- app-script-image-transfer-status / cancel：所有transferIdで処理する。adoptは最新projectId/revisionと元requestIdが必須。

人間の入力中はパイプの編集・要求・転送begin・採用・Nextを拒否する。転送完了だけでは作品を更新しない。採用時に要求IDと最新シーン指紋を再確認し、古い結果は人間入力・現在素材を保持して拒否する。成功時はstate=adopted、imageProvenance、adoptedFingerprintを保存する。画像は内容SHA256で指紋化し、保存時のproject.assetsへの移動で未完了要求や採用済み照合を失わない。

プレビューはWorkspaceが所有する実ジョブで作る。描画コピーだけに既存EnableCompositionを適用し、保存済みキャラ配置と現在の配役から合成キャラを導出する。台本正本の配置・Characterリストを再生成しない。project/revision/選択sceneが一致する描画だけを公開する。手動プレビューは同じ入力で再試行できる。旧ジョブは取消後に完了回収する。

## 保存先と後続境界

明示--data-root / --settings-dirおよび既存RIGMMAKER_SETTINGS_DIRを維持する。旧既定D:\Users\take6\RIGMMakerが実在する場合は維持し、不在の場合だけ現在PCのKnownDocuments\RIGMMakerを既定とする。不在の別PCディレクトリは作らない。画像コピー先は現在作品のScriptPathから決定する。

summaryでは『総評なし／あり』を未選択から人間が選ぶ。値やチャートを自動捏造しない。この時点でsummary以降のチャート入力、締め、動画編集への引渡しは後続工程。summaryのNextは未接続のため表示しない。

## 対象検証

標準RIGMMaker.dproj Win64 Debug / Releaseで確認する。Invoke-ScriptScenes.ps1は明示所有markerの架空作品だけをコピーし、既存VOICEVOX 0.25.2の本物の短い音声を使用する。画像はtest-fixtureと明示した600×200 PNGであり、AI生成画像ではない。

GUI編集、入力lock、ローカルコピー、外部要求取消、保存中の未完了要求保持、実分割PNG/hash/decode、順序違反・未完了finish拒否、最新revisionでも古いscene指紋の採用拒否、新要求採用、元文章・字幕・音声・話者UUID・2人分の保存配置保持を確認する。中央/L/逆Lで複数セリフ全期間の描画、画像/説明/非表示と比率fitを確認する。Next先summary保存、選択保存、普通終了と再開、実サムネイル・プレビュー・音声ready保持を確認する。元の架空作品とRIGMのhash不変を確認する。長尺動画encodeは行わない。

総評の次工程は [SCRIPT-STAGE11-20261006.md](SCRIPT-STAGE11-20261006.md) を参照。
