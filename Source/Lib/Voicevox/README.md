# VOICEVOX再利用部品

Syncroh2の`Plugin_Extension/Serif/Voicevox`から合成API、話者カタログ、音声設定、診断ログをコピーし、`Lib/SoundFileUtils`からWAV長取得をコピーした。元ファイルは変更していない。コピー元とSHA-256は[provenance.json](provenance.json)。

ローカルコピーの変更は、ワーカーごとの接続URL、HTTPリダイレクト禁止、要求の前後での取消検査、RIGMMaker専用一時ディレクトリ・ログ、UTF-8 BOM、Delphiのユニットスコープ名、未使用変数の除去。音声設定INIストアはコピーしたが、制作プロジェクトは自身のJSON設定を使い、元プロジェクトのINIを開かない。

`audio_query`→音声設定適用→`synthesis`→WAVと音素LABという既存の処理を利用する。台本の接続先はloopback HTTPに限定する。制作画面と共通パイプに接続済み。ワーカーの進行中IHTTPRequestを登録し、取消時にRequest.Cancelを呼ぶ。1500ms応答を遅らせた試験用合成HTTPで、取消が800ms未満で完了することを確認した。実VOICEVOXの取消は未検証。取消直後の再試行は一度だけ待機させる。生成出力を絶対パスに統一し、保存済みプロジェクトから再試行した音声が反映されない問題を修正した。古い台本・別プロジェクトの結果の排除、部分成功の保持、失敗時の既存音声保持を共通パイプの回帰検査で確認した。

2026-10-03、インストール済み`C:/Users/zan12/AppData/Local/Programs/VOICEVOX/vv-engine/run.exe`を非表示で起動したが、`engine_internal/setuptools/_vendor/jaraco/text/Lorem ipsum.txt`不足でPyInstallerの初期化中に停止した。インストール先は変更していない。API疎通・実音声生成は未成功。不存在ポートへの接続失敗がジョブのエラーとして返り、台本を保持することは検証済み。

API参考: [VOICEVOX Engine](https://github.com/VOICEVOX/voicevox_engine)。
