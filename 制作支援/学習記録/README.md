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

原画の両目の髪除去、両眉・口の周囲透明化の成功は、各 [目](AIArtToPSD/Sample/eyes_no_hair_20261001/README.md)・[眉](AIArtToPSD/Sample/brows_only_20261001/README.md)・[口](AIArtToPSD/Sample/mouth_only_20261001/README.md) の制作記録にも保存されている。
過去の失敗・途中結果も原文の評価とともに保持した。制作時の一般ルールは [RIGM 用パーツ分解](../制作手順/パーツ分解.md) と [差分作成](../制作手順/差分作成.md) を使う。

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
