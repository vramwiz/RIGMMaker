# 学習記録一覧

参考元の成功条件・失敗理由・生成指示・検証と、元の分解・検査スクリプトを `AIArtToPSD/Sample` にコピーした。
以下は参考元での評価。RIGM への移植や別の原画での再現は、今回まだ検証していない。

| 用途 | 参考元での評価 | 学習記録 |
| --- | --- | --- |
| 額・頭部の肌素体、前髪境界 | ユーザー採用済み。素体単独と髪の移動時も確認 | [肌素体](AIArtToPSD/Sample/face_foundation_fix_20261002/learning_record.json) |
| 口9種のシート | ユーザー採用済み。「い」の改善形は次回の指針 | [口9種](AIArtToPSD/Sample/mouth_sheet_retry_20261001/learning_record.json) |
| 両目6種のシート | ユーザー採用済み。左右一組と共通倍率 | [両目6種](AIArtToPSD/Sample/eyes_sheet_trial_20261001/learning_record.json) |
| 両眉8種のシート | ユーザー採用済み。前髪の遮蔽と非対称形を保持 | [両眉8種](AIArtToPSD/Sample/brows_sheet_trial_20261001/learning_record.json) |
| 頭部と体、体全体のポーズ差分 | ユーザー採用済み。体全体へ変化が広がることも記録 | [体の差し替え](AIArtToPSD/Sample/body_pose_trial_20261001/learning_record.json) |
| 手足の分割とポーズ | 条件付きの補助方式。基本方式にはしていない | [手足の分割](AIArtToPSD/Sample/limb_pose_trial_20261001/learning_record.json) |
| 胴体の後ろへ回す腕 | 接続点の違和感を記録。衣装等による条件付き | [背面腕](AIArtToPSD/Sample/arm_behind_trial_20261001/learning_record.json) |
| 首の接続を合わせる全身ポーズ | 取込・幾何検証済み、個別の見た目は確認待ち | [全身ポーズ](AIArtToPSD/Sample/full_body_pose_trial_20261001/learning_record.json) |
| 髪の分離、後ろ髪の補完 | 取込・検証済み、後ろ髪の採用判断は確認待ち。肌素体には後続修正あり | [髪の分離](AIArtToPSD/Sample/hair_separation_trial_20261002/learning_record.json) |
| 最終ベースへ背景透過を引き継ぐ | ミスと再発防止を記録。修正を検証、見た目は確認待ち | [背景透過](AIArtToPSD/Sample/syncroh2_blonde_native_20261002/background-alpha-fix/learning_record.json) |
| 口・目・眉の差分をまとめて追加 | 取込・保存・検証済み、ユーザーの見た目は確認待ち | [表情一式](AIArtToPSD/Sample/syncroh2_expressions_20261002/learning_record.json) |
| 台本のシーン画像・ジャンル固定・前シーン参照 | ユーザーの制作方針を記録。生成・採用の状態は記録本体を参照 | [シーン画像の連続性](RIGM/20261008-scene-image-continuity/learning_record.json) |
| テスト台本の5シーンへの画像割り当て | 生成・パイプ採用・最後の合成表示を確認。ユーザー確定・保存再開は未確認 | [準備から小さな開始へ](RIGM/20261009-script-test-images/learning_record.json) |
| 第16段階の共通背景 | 人物なしの背景を生成し、現行要求へパイプ採用。原本SHA一致を確認。ユーザー確定・保存再開は未確認 | [物語紹介用の読書室](RIGM/20261010-common-background/learning_record.json) |
| 漫画紹介台本の全11シーン | セリフから創作画像を生成・パイプ採用。原本SHAとセリフ保持を確認。ユーザー確定・保存再開・最後のサムネイルは未確認 | [それは、降り積もる雪のような。](RIGM/20261011-soreyuki-scenes/learning_record.json) |
| タイトル指定2か所の大きなロゴ修正 | 雪景色と画面の大半を占める太字ロゴへ変更して採用。ほか9枚の画像・確定状態と全セリフを保持。対象のユーザー確定・保存再開は未確認 | [大きく目立つタイトル](RIGM/20261011-soreyuki-scenes/logo-fix/learning_record.json) |
| 共通背景・必須サムネイルと動画編集への移動 | 内蔵imagegenで作成・採用後、ユーザーが確定して動画編集へ移動。保存資産を照合。サムネイルのチェックが一度で反映されない症状は未修正 | [雪景色と最終サムネイル](RIGM/20261011-soreyuki-scenes/background-thumbnail/learning_record.json) |
| 漫画紹介の人物を統一したシーン画像・背景・最後のロゴサムネイル | 全44行を先に読み、内蔵imagegenで全11シーン・背景・サムネイルを作成・パイプ採用・保存。原本・管理コピー・保存資産のSHAを照合。後続の色・ロゴ修正後、背景・通常シーン・サムネイルの人間確定を確認 | [異世界「嘘」ガイド](RIGM/20261012-isekai-uso-scenes/learning_record.json)、[背景・総評・サムネイル](RIGM/20261012-isekai-uso-scenes/additional/learning_record.json) |
| サムネイルのきりたんの色・ロゴの視認性 | 原画を参照して色を修正し、ロゴ背面へ濃色パネルを追加して採用・保存。ユーザーが画像を採用。次回は棒立ちにせず、場面に合う表情・ポーズを付ける制作ルールへ更新 | [きりたんの差し替えとロゴ背面](RIGM/20261012-isekai-uso-scenes/additional/thumbnail-fix/learning_record.json) |
| 男子校のくらげ先生のシーン画像と共通背景 | 全44行を先読みし、公式参照と人物基準画像で統一。10シーンと背景を採用・保存後、10/13にロゴ画像を最終発話シーン「最後に」へ送信・保存。全通常シーンと背景の人間確定後、専用サムネイル欄にも送信・保存。字幕・音声・通常シーン・確定状態の保持と画像SHA一致を確認。サムネイル自体のチェックは未確定 | [男子校のくらげ先生](RIGM/20261012-kurage-scenes/learning_record.json)、[サムネイル生成](RIGM/20261012-kurage-scenes/thumbnail_learning_record.json)、[最終シーンへ送信](RIGM/20261012-kurage-scenes/last_scene_delivery_20261013.json)、[専用サムネイル欄へ送信](RIGM/20261012-kurage-scenes/thumbnail_delivery_20261013.json) |

原画の両目の髪除去、両眉・口の周囲透明化の成功は、各 [目](AIArtToPSD/Sample/eyes_no_hair_20261001/README.md)・[眉](AIArtToPSD/Sample/brows_only_20261001/README.md)・[口](AIArtToPSD/Sample/mouth_only_20261001/README.md) の制作記録にも保存されている。
過去の失敗・途中結果も原文の評価とともに保持した。制作時の一般ルールは [RIGM 用パーツ分解](../制作手順/パーツ分解.md) と [差分作成](../制作手順/差分作成.md) を使う。

## コール・ミー・フランケンシュタインの低頭身画像

[制作記録](RIGM/20261016-call-me-frankenstein-chibi/learning_record.json)：作中のカラー原稿を参照し、約2.5頭身で8シーンと東北きりたん入りサムネイルを生成・パイプ採用・保存。博士の作中の髪色・衣装とはるかの電池を次回の参照基準として記録した。保存画像の照合と人間の確定状態は記録内の検証ファイルを参照する。

## コピーした資料

- `learning_record.json`：条件、評価、再利用手順、制約。
- `*prompt*.json` 等：実際の生成・加工の指示。
- 検証・測定・配置等の JSON と README：何を検証したか、何が未確認か。
- PowerShell / Python のスクリプト：元画素の分解・透明化、シート分割、結果作成、検証の参考。

スクリプトと過去の `result.json` は元環境・原画・ジョブ専用の参考資料。過去の識別子や座標で新しい文書へ適用しない。
PSD を解析する検証スクリプトや PSD への保存処理は、RIGM の保存・再読み込みへ移植してから使用する。
PNG・PSD 本体、実行中ジョブ、接続情報、パイプ応答等はコピー対象にしていない。画像や履歴上の参照先は `D:\DelphiProg\test\AIArtToPSD\Sample` にある元資料を使う。

## 今後の記録

[検証と学習記録](../制作手順/検証と学習記録.md) と [記録テンプレート](記録テンプレート.json) に従い、RIGM 用の制作例を追加する。
過去の原文を採用済みのまま RIGM の成功記録へ書き換えず、今回の入力・保存形式・実施した検証・評価を記録する。

## 宿屋の錬金術師と三姉妹のちびキャラ画像

[制作記録](RIGM/20261017-inn-alchemist-chibi/learning_record.json)：内蔵imagegenで共通背景・本編9シーン・東北きりたんと全文タイトル入りサムネイルの計11枚を生成し、開いている台本へ送信・保存。人物はちびキャラで、襟元を閉じた長袖衣装と穏やかな日常表現に統一。全46セリフのJSON保持と全保存画像のSHA256一致を確認。背景と本編は人間の確定を確認、サムネイル自体は確定待ち。

## 50年後の老人ホームのコメディ調画像

[制作記録](RIGM/20261017-senior-home/learning_record.json)：内蔵imagegenで背景・本編8シーン・東北きりたん入りサムネイルの計10枚を生成し、開いている台本へ送信・保存。人物は少し低めの頭身で、白髪やしわなどの年齢の特徴とコミカルな表情を両立。全41cueのJSON保持と全画像のSHA256一致を確認。背景と本編は人間の確定を確認、サムネイル自体は確定待ち。

## ロストサマー・ジャーニーの低頭身アニメ画像

[制作記録](RIGM/20261018-lost-summer-journey/learning_record.json)：内蔵imagegenで背景・本編8シーン・東北きりたん入りサムネイルの計10枚を生成し、開いている台本へ送信・保存。公式紹介画像の二人の外見を低頭身のアニメ調へ反映し、船・海・夏空を前画像の参照で継続。全43cueのJSON保持と全保存画像のSHA256一致を確認。背景・本編は人間の確定を確認、サムネイル自体は確定待ち。

## ぷれいめ～との健全な低頭身アニメ画像

[制作記録](RIGM/20261018-playmate/learning_record.json)：内蔵imagegenで背景・本編9枚・東北きりたん入りサムネイルの計11枚を生成し、開いている台本へ送信・保存。人物は約2.5〜3頭身、長袖・長ズボン・長い服と不透明なタイツで露出を抑え、田舎での遊びを中心にした。全45cueのJSON保持と全11枚の生成元・作業コピー・保存先のSHA256一致を確認。背景・本編は人間の確定済み、サムネイル自体は確定待ち。
## 鬱展開大好き主人公VS優しい世界の低頭身アニメ画像

[制作記録](RIGM/20261018-utsutenkai-chibi/learning_record.json)：内蔵imagegenで背景・本編8シーン・東北きりたんと主題・副題全文入りサムネイルの計10枚を生成し、実行中台本へ送信・保存。公式表紙の金髪・緑の目・白と金の王子服を低頭身アニメ調へ反映し、平和な王国と紫の内心のギャップをコミカルに表現。全40cueのJSON保持と全画像の生成元・作業コピー・保存先のSHA256一致を確認。元画像は人間の確定済み、サムネイル自体は確定待ち。
## 可愛いはすべてを破壊するの低頭身・かわいい学園画像

[制作記録](RIGM/20261018-kawaii-destroys-all/learning_record.json)：内蔵imagegenで背景・本編9シーン・東北きりたんと題名入りサムネイルの計11枚を生成し、実行中台本へ送信・保存。公式試し読みのひよの金髪・金色の目・黄色のカーディガンと、クラスメイトの髪型を低頭身アニメ調へ反映。モノクロ資料の一部の色と教師の後ろ姿・背景細部は創作。全44cueのJSON保持、全画像の生成元・作業コピー・保存先のSHA256一致を確認。元画像は人間の確定済み、サムネイル自体は確定待ち。
