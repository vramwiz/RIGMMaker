# VOICEVOX再利用部品

Syncroh2の`Plugin_Extension/Serif/Voicevox`から合成API、話者カタログ、音声設定、診断ログをコピーし、`Lib/SoundFileUtils`からWAV長取得をコピーした。元ファイルは変更していない。コピー元とSHA-256は[provenance.json](provenance.json)。

ローカルコピーの変更は、ワーカーごとの接続URL、HTTPリダイレクト禁止、要求の前後での取消検査、RIGMMaker専用一時ディレクトリ・ログ、UTF-8 BOM、Delphiのユニットスコープ名、未使用変数の除去。音声設定INIストアはコピーしたが、制作プロジェクトは自身のJSON設定を使い、元プロジェクトのINIを開かない。

`audio_query`→音声設定適用→`synthesis`→WAVと音素LABという既存の処理を利用する。台本の接続先はloopback HTTPに限定する。制作画面と共通パイプに接続済み。ワーカーの進行中IHTTPRequestを登録し、取消時にRequest.Cancelを呼ぶ。1500ms応答を遅らせた試験用合成HTTPで、取消が800ms未満で完了することを確認した。実VOICEVOXの取消は未検証。取消直後の再試行は一度だけ待機させる。生成出力を絶対パスに統一し、保存済みプロジェクトから再試行した音声が反映されない問題を修正した。古い台本・別プロジェクトの結果の排除、部分成功の保持、失敗時の既存音声保持を共通パイプの回帰検査で確認した。

2026-10-03、インストール済み`C:/Users/zan12/AppData/Local/Programs/VOICEVOX/vv-engine/run.exe`を非表示で起動したが、`engine_internal/setuptools/_vendor/jaraco/text/Lorem ipsum.txt`不足でPyInstallerの初期化中に停止した。インストール先は変更していない。API疎通・実音声生成は未成功。不存在ポートへの接続失敗がジョブのエラーとして返り、台本を保持することは検証済み。

API参考: [VOICEVOX Engine](https://github.com/VOICEVOX/voicevox_engine)。

## 2026-10-07 詳細UIコピー

現行参照元の `AviUtl2PluginLib/Serif/Voicevox` からSettingsFrame・AccentView・IntonationFrame・LengthFrame・AudioSettingsFrame・EngineConfig、共通Libから縦スライダー・横スクロールバー・VOICEVOXツールバー・配色を採用。コピー元SHA-256は [ui-provenance.json](ui-provenance.json)。AviUtl入力一覧とプロジェクトINIは採用せず、RIGMMakerの選択cue、voiceSettings/voiceQueryへ接続した。原本は変更していない。

UI解析ワーカーは `RigmVoicevoxUiWorker` で作品URLとHTTP取消を適用する。EngineConfigは実行ファイルの隣のVoicevoxEngine.iniに限定し、競合/保存失敗を通知する。連続生成・再生はRigmScriptVoiceWorkspace.incが所有する。今回の追加・変更は静的確認のみ、ビルド・アプリ実行・Engine起動・実音声検証は未実行。

## 2026-10-07 配役工程の声選択・詳細UI空欄修正（今回未ビルド/未実行）

既存の保存済みDebugログでは、/speakersのHTTP 200と43話者取得を確認した一方、選択行はspeaker=-1でaudio_queryを要求していなかった。EXE選択と声選択は別だが、旧コンボの未選択表示が空欄で必要操作を案内していなかった。ツールバーのVoicevoxPages文字はTCustomPanelのName由来の自動Caption。参照元のParent/Align・初期Activate(vtpAccent)は正常だった。

配役画面に接続URL、EXE選択、接続・更新/取消、使用キャラと話者・スタイルの選択、登録初期値保存を追加した。登録済みの声を配役準備/再入場/保存再開時の初期値へ復元し、既存の台本固有の声を上書きしない。未使用キャラを必須にせず、実セリフが使う配役番号だけを判定する。各行は配役済と声設定済を分けて表示する。

配役工程のNextは全配役確認、使用キャラのUUID/styleId設定、現在のEngineの実一覧との一致が揃うまで拒否する。工程アイコンの後工程移動も同じ共通条件を通す。後工程では保存された配役/声設定を検査し、保存音声だけで進める場合までEngine再接続を強制しない。後で使用キャラが変われば必須対象を再計算する。声未設定の旧台本は保存済みstage/furthestStageや原稿・字幕・音声を保持し、必要に応じて配役画面へ案内する。字幕/音声の準備処理も声未設定を拒否する。

EXE選択・保存・非同期準備はRigmVoiceConnectionを配役/第9段階で共有する。保存先は従来どおりRIGMMaker.exe隣のVoicevoxEngine.ini。Engine起動/接続は既存MovieJobを使い、取消でEngineプロセスを停止しない。第9段階には配役のSpeakerを引き継ぎ、明示した声でaudio_query取得→アクセント/音高/音素長表示へ接続する。声未選択コンボには案内行を表示し、詳細領域に未接続・未選択・解析中・失敗・編集開始の案内を表示する。初回解析の表示だけでは設定や既存WAVの指紋を変更しない。自動Captionを抑止し、ページパネルの配色・Alignを明示した。

既存の行別query保存・連続再生・停止と配役一覧のネイティブ二重バッファ/全幅選択解除描画を保持。声画面の既存検証は、配役での明示選択とコンボ案内行へ追従させた。今回はソースの静的確認とハッシュ照合のみ。ビルド、アプリ起動/再起動、EXE更新、Engine起動、API要求、音声生成/試聴、検証コード実行は行っていない。残る実確認は段階1→配役での声設定→字幕→詳細表示、未使用キャラ・未設定の進行拒否、保存再開、話者切替の旧解析排除、連続再生。過去の配役/字幕fixture作成フローも新しい声設定条件へ追従が必要な場合がある。

## 2026-10-07 音素長の独立表示と文字描画

アクセントと音高だけモーラ列・横スクロールを共有する。音素長は子音・母音・休止を各32px（DPI比例）の独立要素として並べ、専用の横スクロール範囲を使う。3段の高さと余白ホイールの縦スクロールは保持する。音素長の文字もバーと同じ二重バッファ内で描く。

スタイル付きFrameが画面DCを先に消す処理は共通RigmBufferedControlsで抑制し、メモリDC・PaintTo・親背景の合成を保持する。文字の親Panelも画面DCの先行消去だけを抑え、元のParentBackground設定とテーマ背景の継承を保持してメモリDC内で合成する。音声の人物名・接続案内は最終文言だけを同値比較して反映する。音声生成・再生・query保存の処理は保持する。
