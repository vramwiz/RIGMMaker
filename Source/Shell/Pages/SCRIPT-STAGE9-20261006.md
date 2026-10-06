# 第9段階：読み・VOICEVOX基本調整

字幕工程の入力完了後、Nextは内容と移動先 `voice` を同じ保存で確定してから遷移する。音声フレームは初回だけ生成し、メインフォーム内で保持する。戻る・終了で下書きを保持し、再開先は最後にNextで到達した工程。シーン工程への接続は後続作業。

## 操作と登録

↑↓でセリフを選択、Enterで読み・数値を編集する。Ctrl+Enter / Escまたは入力完了アイコンで編集を終える。F5は選択セリフだけ生成して試聴し、生成済みで入力に一致する場合は保存WAVを再生する。生成アイコンは試聴せず選択生成、取消アイコンは再生停止・所有ジョブ取消。全セリフの音声確認完了アイコンは、現在の入力と一致する音声が全て揃った場合だけ完了状態にする。

接続先を適用して実話者一覧を取得し、登録キャラへUUIDとstyleIdを明示的に紐付ける。名前・外見からの推定や自動選択はしない。未割当は未割当のまま表示し、該当セリフの新規合成を拒否する。

登録初期値保存アイコンは、選択キャラの声をdata rootの `CharacterVoiceBindings.json` に保存する。現在は音声工程から登録初期値を設定する。キャラ登録編集画面への専用話者選択UI追加は行っていない。ファイルは `RIGMMaker.CharacterVoiceBindings` schemaVersion 1、bindingsは小文字相対キャラパスをキーとする。値はuuid/name/style/styleId/engineUrl。

新しいキャラ選択時に登録初期値を作品へコピーし、音声準備時に未割当Speakerだけへ適用する。既存の選択・Speaker・WAV/LABは保持し、旧作品を一括変更しない。接続先は作品側の値を保持する。RIGM原本を更新しない。登録ファイルの読込前後hash、保存時expected hash、同じファイルを扱う協調mutexと一時ファイルのatomic replaceで競合を検出する。外部変更があれば内容を残して保存を拒否し、再起動して再取得する。

## 読み・音声データ

Cueの `voiceReading` は表示字幕・元原稿・シーンから独立する。空は従来のtextへ戻す。`voiceSettings` は有限の数値だけを持ち、次の範囲を検査する。

| JSON項目 | 範囲 |
| --- | --- |
| speedScale | 0.5–2 |
| pitchScale | −0.15–0.15 |
| intonationScale / volumeScale | 0–2 |
| prePhonemeLength / postPhonemeLength | 0–5秒 |

読みは2000 UTF16以内。制御文字と不完全なサロゲートを拒否する。表示字幕・元原稿・配役fingerprintは変えず、音声fingerprintは実際の読み、Speaker、query、接続先から計算する。新フィールドがない旧データのfingerprintは変わらない。変更しない詳細編集ではrevisionとfingerprintを維持する。

従来の生成ジョブ・VOICEVOXライブラリを再利用し、cueIdを指定した生成は1セリフだけを対象とする。結果回収時にprojectId、最新の配役と音声fingerprintを照合する。取消・失敗・生成中の新しい読み変更では古い結果を採用しない。以前のWAV/LAB/秒数/keyを保持し、現在の入力と不一致なら旧音声状態にする。正常生成の実測秒数変更は後続へrippleする。

基本調整は話速・音高・抑揚・音量・開始/終了無音。仕様の候補にあるアクセント・モーラ詳細編集UIは未実装。試聴呼出しと実PCMは検証しているが、人間の聴感評価は行っていない。

## 共通パイプ

readは `app-script-voice`（1セリフずつ、offset）と `app-script-voice-catalog`（20styleずつ）。実一覧を取得した接続先も返す。変更は以下。全て最新projectId/revisionと共通人間入力ロックを検査する。

- app-script-select-voice：cueId
- app-script-edit-voice：cueId、reading文字列、settingsオブジェクト
- app-script-set-voice-engine：engineUrl
- app-script-refresh-voice：実一覧の非同期取得
- app-script-bind-voice：role、実一覧のstyleId/uuid
- app-script-save-character-voice：role
- app-script-generate-voice：cueId、play
- app-script-cancel-voice

不正な値・古いrevision・異なるprojectId・存在しないcue・実一覧にないUUID/styleは、入力を部分反映せず拒否する。校正や配役のAI契約に音声のダミー処理を加えていない。

## 正常エンジンと確認

このPCの正常既存配置は **`V:\voicevox-windows-directml-0.25.2\VOICEVOX\vv-engine\run.exe`**。Syncroh2のKnownDocuments/Syncroh2/Launcher/LauncherList.iniにある起動先から特定した。配布を変更せず再利用する。Local Programs側の起動失敗は別の既存配布の問題であり、この正常配布には該当しない。

専用port50022、CPU2、mutable API無効で起動した既存0.25.2を使用し、43話者を取得。架空作品のコピーに限って東北きりたんノーマル108（UUID `1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b`）を明示選択した。ユーザーの声・接続先設定は変更しない。インストール・修復・課金・資格情報設定なし。

標準 `RIGMMaker.dproj` Win64 Debug/Releaseを出力設定の上書きなしで確認。各0エラー、従来12警告。各版で短い実UI37項目、保存再開と登録再利用12項目、共有パイプ18項目が成功。実PCM/WAV/LAB、遅い結果・取消・実HTTP失敗時の旧音声保持、実測尺ripple、登録ファイルの外部変更拒否を確認。表示の重なりを解消し、通常Release EXEへ反映した。長尺動画エンコードなし。

検証入口は `Source/Psd/Validation/Invoke-ScriptVoice.ps1` と `--verify-script-voice` / `--verify-script-voice-reopen`。明示された専用fixtureのコピーに限って動作し、所有markerを検査する。証跡と原本backup、専用作品はignored `Win64/Validation/ScriptVoice/Recovery/voice-20261006-1314` に保存する。
