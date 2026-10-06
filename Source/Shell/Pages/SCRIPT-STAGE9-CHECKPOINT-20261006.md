# 第9段階：音声工程の中間チェックポイント

> 後続の音声基本調整・登録再利用・外部競合確認は SCRIPT-STAGE9-20261006.md を参照。この文書は13:52時点の中間記録です。

2026-10-06 13:52 UTC。ソース変更は未コミット。次の継続で差分レビュー・登録設定の追加確認後に選択的commit/pushする。第10段階以降は未着手。

字幕完了のNextで音声工程と内容を保存して遷移する。フレームは初回生成後に保持し、↑↓でセリフ、Enterで読み・数値編集、F5で選択セリフだけ生成・試聴する。登録キャラの声は実一覧のUUID/styleIdを明示選択する。外見や名前からの自動推定、鍵作成はない。

CueのvoiceReading（空なら従来text）とvoiceSettingsを新設。元原稿・字幕・scene・配役fingerprintを変えず、話速・音高・抑揚・音量・開始/終了無音を調整する。アクセント・モーラの詳細編集UIは未実装。旧音声情報を保持し、読みやquery変更では音声fingerprintにより古い状態にする。取消・失敗・入力後の遅い生成結果は旧WAV/LAB/秒数を置換しない。正常結果の実測秒数変更は後続へrippleする。

登録初期値はdata rootのCharacterVoiceBindings.jsonに別保存。新規選択へコピーし、既存作品を一括更新しない。ファイル全体hashとmutexで外部競合を拒否する実装。保存再起動・新作コピー・外部競合の追加検証は次の区切りで行う。RIGM原本には書き込まない。

共通パイプ：app-script-voiceは1セリフ、app-script-voice-catalogは20styleずつ。script-select-voice / script-edit-voice / script-set-voice-engine / script-refresh-voice / script-bind-voice / script-save-character-voice / script-generate-voice / script-cancel-voiceをapp-接頭辞付きのコマンドとして提供する。projectId/revision、入力ロック、存在cue、実UUID/style、設定値を検査してから反映する。

既存正常エンジンはSyncroh2のDocuments/Launcher/LauncherList.iniから特定した V:\voicevox-windows-directml-0.25.2\VOICEVOX\vv-engine\run.exe。新規導入・修復なし。専用port50022、CPU2、mutable API無効で起動し、実version0.25.2・話者43・東北きりたんノーマル108のUUIDを確認した。これは架空テスト作品への明示選択で、ユーザー作品の声を決めたものではない。

標準RIGMMaker.dprojのWin64 Debug/Releaseを出力設定変更なしでbuild。各0エラー・従来12警告。各ビルドの短い実UI31項目、保存再開5項目、共有パイプ16項目が成功。実PCM/WAV/LAB、選択生成、独立した読み、旧音声保持、遅い結果、取消、実HTTP接続失敗、後続rippleを確認した。試聴APIの呼出しとPCMは確認済みだが、人間の聴感評価はしていない。長尺エンコードなし。

未整理事項：無音欄の見出し重なりと接続先適用ボタン幅、旧字幕検証のNext境界assertion、全差分レビュー。第9段階完成や次工程への引渡し完了はまだ主張しない。

証跡・原本backup・復元可能な専用作品は Win64/Validation/ScriptVoice/Recovery/voice-20261006-1314。handoff.jsonとowned-root-recovery-map.jsonを参照。検証用RIGMMaker/VOICEVOXは終了し、ユーザー登録RIGMのSHA256は9F9FCB38F0B586F5AAC0898E100E068EA8FBF3EA0079474617705D0B75A79B27のまま。
