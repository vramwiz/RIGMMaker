# Windowsへの生成画像保存経路

2026-10-05に成功したのは、内蔵 **image_gen.imagegen** の画像データをこのWindows実行環境へ直接保存する経路です。新しい外部API契約・APIキー・ソフトのインストールは使っていません。Libraryからの取り出しや旧PCからのファイル転送は今回検証していません。

1. Windowsに配置済みの原画と通常目PNGを view_image で確認しました。imagegenへのWindows絶対パス指定は AbsolutePathBuf の解析エラーとなったため、表示済み参照画像を num_last_images_to_include:2 で渡しました。
2. image_gen.imagegen は image_url=data:image/png;base64,... を返しました。Windowsローカルパスではなく、PNGのBase64データです。
3. 返却データをfunctionsのstoreに保持し、全データをログ出力せず、tools.apply_patchでWindows作業フォルダへ .base64 を書きました。
4. PowerShellの [Convert]::FromBase64String と [IO.File]::WriteAllBytes で .png に復元しました。初回の場所は Win64/Validation/PsdStudio/ImageWork。現在は復元用Recoveryへ整理済みです。
5. アプリのPNGデコーダで透過・寸法を確認し、透過余白の計測とX/Y共通倍率で登録用PNGを作りました。原生成PNGと登録用PNGを D:\Users\take6\RIGMMaker\Work\PsdGenerated-20261005 に保存し、prepared-assets.jsonへ両方のSHA-256・サイズ・倍率・位置を記録しました。
6. 独立アプリのNamedPipeへ、データルート内のPNG path と sha256、配置、制作履歴をJSON命令として送りました。画像本体はパイプへ送りません。受信側はroot逸脱/リンク/不正PNGを拒否し、読込ロックしたコピーのSHA-256を確認して取り込みます。
7. キャラを同じ .psdchar へ保存し、再読込後に元パーツ52枚と新規7絵のRGBA/配置を照合しました。元Workがない別フォルダでも .psdchar だけで表示できることを確認しました。

したがって、成功した受渡しは **生成ツールのPNGデータ → Windows作業ファイル → 指定データルートのPNG → ファイル参照＋パイプ命令 → 自立したPSDキャラパッケージ** です。

## 輪郭清掃の試行

横向き・後ろ向きの原生成PNGを同じ方法で画像編集ツールへ渡し、色付きの輪郭/にじみだけを清掃する編集を2件実行しました。返却PNGのWindows保存も同じ経路で成功しました。しかし目視で色にじみが残り、髪/装甲の細部も描き直されています。改善済みとは判断せず、登録キャラを置き換えていません。

試行原本・サイズ調整PNG・編集要求・比較結果は Work/PsdGenerated-20261005/CleanupCandidates に残しています。登録中の原画像とキャラパッケージは保全しました。候補は rejected-no-clear-improvement、登録絵は pending-user-review です。

## 全身連番と音声

現在使える内蔵生成は静止画像の生成/編集です。フレーム間の同一形状を固定する動画生成/補間ツールはありません。今回の静止ポーズ編集でも細部の再描画が生じたため、独立生成した複数静止画を自然な全身動作として登録する品質を確認できません。画像の位置移動/変形を全身動作の連番素材とは扱っていません。既存エンジンの連番読込・ループ機能は保持しています。

指定データルートには WAV/MP3/OGG/M4A/LAB の実入力がありません。既存の30ms音素切替テストは通っていますが、実音声再生との同期は検証していません。今回、音声生成/再生の新規実装は加えていません。
