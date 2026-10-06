# 第9段階：VOICEVOX接続前の確認（未実装）

2026-10-06 12:57 UTC時点、既存エンジンは `C:\Users\zan12\AppData\Local\Programs\VOICEVOX\vv-engine\run.exe`。新規導入はしていない。起動中のVOICEVOX/RIGMMakerとlocalhost:50021の待受はなく、`/version` は接続拒否。

`run.exe --help` が起動前に失敗した。PyInstallerの `pyi_rth_pkgres` → `pkg_resources` → `setuptools._vendor.jaraco.text` で、配布内の `engine_internal\setuptools\_vendor\jaraco\text\Lorem ipsum.txt` にFileNotFoundError。該当フォルダも存在しない。既存配布は変更せず、修復・再インストールは行っていない。この状態では実API一覧、実speaker/style選択、短い音声生成・試聴を確認できない。

実装の前提になる既存コードは確認済み：

- `Source\Lib\Voicevox\SerifVoicevoxSpeakerCatalog.pas`：APIのspeaker UUID/styleIdを実一覧で取得。既定styleを返す関数を自動紐付けには使用しない。
- `Source\Lib\Voicevox\SerifVoicevoxApi.pas`：audio_query、accent_phrases、mora_data、synthesis、WAV/TXT/LAB。Syncroh2の既存APIを既にコピー利用している。
- `Source\Lib\Voicevox\RigmVoicevoxConfig.pas`：threadごとのEngineUrlとキャンセル。リダイレクトを禁止。
- `Source\Studio\Workflow\RigmMovieJobs.pas`：スナップショットでの音声生成。現行audioジョブは全セリフ対象であり、第9段階には選択cueの指定を追加する必要がある。
- `Source\Studio\Session\RigmMovieSession.pas`：projectId/revisionと音声fingerprintを照合して完了結果を回収。古い結果で人間の変更を置換しない既存処理を再利用する。
- `Source\Studio\Model\RigmMovieModel.pas`：字幕と音声文は別フィールド。既存speed/pitch/intonation/volumeと音声fingerprint、WAV/LAB/audioSecondsを維持する。

現在の台本フローは字幕まで。音声フレーム、登録キャラのspeaker/style永続紐付け、読み調整、選択発話の生成とF5試聴は未実装。今回のコミットで音声完成を主張しない。次の継続では親が利用可能な既存エンジンを特定するか、ユーザー許可のある修復を調整してから、音声工程を一つのまとまりとして接続・検証する。キャラの名前・外見から声を推測せず、新作へ設定をコピーしても既存作品を一括更新しない。失敗・キャンセル・古い結果では既存WAV/LABを保持する。
