# 実際に動作したVOICEVOX設定と完成プレビュー

この環境のSyncroh2は `C:\Users\zan12\Documents\Syncroh2\Serif\VoicevoxEngine.ini` の `[VOICEVOX] EngineExe` に `V:\Program Files\VOICEVOX\vv-engine\run.exe` を保存している。Syncroh2の `Plugin_Extension\Serif\Voicevox\SerifVoicevoxEngineConfig.pas` は保存された有効なパスを標準インストール先より先に選ぶ。`SerifVoicevoxEngineSession.pas` はエンジンのフォルダーを作業ディレクトリにし、下記引数で非表示起動して `/version` を確認する。元プロジェクトは変更していない。

APIが既に応答する場合は、その起動済みエンジンを使う。接続確認は次のとおり。

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:50021/version'
Invoke-RestMethod -Uri 'http://127.0.0.1:50021/speakers'
```

未起動時の既存エンジンの通常起動は次のとおり。インストール・修復・セキュリティ設定変更は含まない。

```powershell
Start-Process -FilePath 'V:\Program Files\VOICEVOX\vv-engine\run.exe' `
  -ArgumentList '--host','127.0.0.1','--port','50021','--output_log_utf8' `
  -WorkingDirectory 'V:\Program Files\VOICEVOX\vv-engine' -WindowStyle Hidden
```

RIGMMakerの接続先設定 `MovieEngineUrl` と完成した `.rigmovie` の `engineUrl` は `http://127.0.0.1:50021`。実際の `/version` は `0.25.2`、`/speakers` には東北きりたん／ノーマル `styleId=108`、UUID `1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b` があり、この話者で4区間の実台詞を生成した。話速1.05、ピッチ0、抑揚1、音量1。話者番号は今回の取得結果で確定したもの。

以前の「エンジン修復が必要」という判断は、Syncroh2の実設定を調べる前に試した別経路 `C:\Users\zan12\AppData\Local\Programs\VOICEVOX\vv-engine\run.exe` の不足ファイルに基づいていた。今回のVドライブの正規設定では修復不要だった。また、サンドボックス内の起動では通常の辞書一時ファイル書込みが拒否されたため、ユーザーが許可した通常起動を通常ユーザー権限で行った。VOICEVOXのインストールファイル、Syncroh2の保存設定、権限は修復・変更していない。

完成物は `D:\DelphiProg\RIGMMaker\制作成果\星灯り郵便局-20261003T224130881\星灯り郵便局.rigmovie`。`RIGMMaker.preview.exe` を起動し、ライブラリの「台本から動画を制作」アイコン→動画画面の「開く」→このファイル→「再生 / 停止」。保存済みWAVはエンジンが停止していても再生できる。台詞・音声設定を変えた場合は実エンジンから再生成する。

タイトルと台詞に架空作品である旨を明示した。クレジットは **VOICEVOX:東北きりたん**。公式紹介は https://voicevox.hiroshiba.jp/dormitory/tohoku_kiritan/ 、音源規約は https://zunko.jp/con_ongen_kiyaku.html 。今回のエンジンが返した利用クレジットも `Win64\Validation\AnimePreview\kiritan-voice-policy.txt` に保存した。立ち絵は登録済み素材の作者・利用条件を引き継ぐ。

全区間は約37.21秒。独立ffprobeは連結WAVを48kHz PCM16 mono、37.210688秒と確認した。保存済みタイムライン37.210666667秒との差は約0.0000213秒で、区間のサンプル丸めと表示精度の範囲。共同編集回帰のAVIも全8フレームを独立デコードし、0.8秒の映像と48kHz音声38,400サンプルの一致を確認した。このAVI回帰だけは明示的なテスト音源で、完成プレビューの実台詞とは別の検証である。

実台詞の生成・携帯可能な保存/再読込・区間選択/シーク・Windows音声再生開始/進行/停止・発話時の開口/無音時の閉口・瞬き復帰を検証した。描画フレームで配置・字幕・キャラの破綻がないことを確認した。PaintTo画像はネイティブ編集欄の内容を完全には写さない。主観試聴、全GUIの手動目視、物理モニター間DPI移動は未実施。