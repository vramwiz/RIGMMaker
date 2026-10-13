# RIGM Maker 開発ノート

RIGMキャラクターの編集と、台本・音声・字幕・シーン画像からの動画制作を行うDelphi VCLアプリ。プロジェクト名はRIGMMaker、Win64 Debug／Release、PerMonitorV2、Windows Modern Darkを使用する。

[基本事項・ビルド](note-basics.md) ／ [課題の詳細](note-tasks.md) ／ [開発履歴](note-history.md)

## 今後の方針

今回確認した「アプリのボタン操作で専用Codexを起動し、入力内容をパイプで送り、生成結果や画像の保存先を受信する」機能を利用して、今後は制作工程の複数段階でAI操作を行えるようにする。対象の段階・操作内容・導入順序は今後決め、段階ごとに検証して本編へ組み込む。現時点では独立テストで画像生成・受信・表示まで確認済みで、本編への組込みは未実施。[検証結果とテストプロジェクト](Source/Diagnostics/CodexPipeProbe/README.md)を参照する。

## 対応すべき課題

| 課題 | 状態 |
| --- | --- |
| 台本画面内の横スクロール | 方針変更で保留。左の工程リストだけ幅調整・バー非表示を対応済み |
| シーン画像の確定・保存再開を確認 | 実台本11枚・背景・サムネイルの人間確定と工程移動時の保存を確認。終了後の再開は未確認 |
| サムネイルの確定チェックが一度で反映されない | 実作品で報告。繰り返し操作で確定・動画編集へ移動したが、再現条件・原因は未確認 |
| 同じ台本の外部更新後の再読込 | 別Workspaceによる保存後、既存インスタンスへ戻る症状を隔離検証で観測。キャッシュの差し替えを確認する |
| アプリからの画像要求操作をわかりやすくする | ユーザーの不安を記録。後日修正 |
| 台本のジャンル・シリーズで画像生成の画風を固定 | 方針記録済み。設定UIは未実装 |
| 掘り下げ要素を台本種類ごとに定義 | 第6段階のUI・保存・パイプは実装。種類・件数は今後決定 |
| キャラのVOICEVOX初期話者・選択後の一覧順 | 後日実装 |

詳細と確認範囲は[対応課題](note-tasks.md)に記す。解決した課題は一覧から外し、結果を履歴へ残す。

## 関連文書

| 内容 | 参照先 |
| --- | --- |
| 形式・編集仕様 | [RIGM仕様](RIGM仕様.md)、[編集仕様](RIGM_Maker_編集仕様.md) |
| ソース構成・実装の検証 | [Source](Source/README.md)、[編集実装と検証](編集実装と検証.md) |
| 制作手順・他のノート | [制作支援](制作支援/README.md)、[参照元note](制作支援/元資料/AIArtToPSD/note.md) |
| 動画制作 | [利用手順](制作支援/動画制作/README.md)、[制作仕様](制作支援/動画制作/仕様.md) |
| 動画編集のDPI | [フォントの基準・表示検証](Source/Studio/Views/Editor/MOVIE-DPI-20261009.md) |
| 動画プレビューの負荷・画面表示 | [描画・素材・音声・表示の改善](Source/Studio/Views/Editor/MOVIE-PREVIEW-20261010.md) |
| 投稿用タイトル・概要・親作品とコピー | [投稿欄・初期値・保存](Source/Studio/Views/Editor/MOVIE-POSTING-20261011.md) |
| MP4単体出力・同梱DLL | [配置・エンコード・検証](Source/Studio/Output/MP4-RUNTIME-20261010.md) |
| パイプ通信 | [パイプ手順](制作支援/パイプ/README.md) |
| ボタンからCodexを起動する独立テスト | [1フォーム・2送信ボタン・画像生成/受信/表示の結果](Source/Diagnostics/CodexPipeProbe/README.md) |
| 台本制作の画面・工程移動・VOICEVOX調整・動画からの復帰 | [工程リスト・入力とちらつき抑制・設定・保存・復帰](Source/Shell/Pages/SCRIPT-NAVIGATION-20261009.md) |
| 台本一覧から本文を除いてコピー | [コピー対象・操作・保存](Source/Shell/Pages/SCRIPT-COPY-20261012.md) |
| 作品情報・掘り下げ確認 | [第6段階の画面・通信・保存](Source/Shell/Pages/SCRIPT-RESEARCH-20261009.md) |
| キャラ配置・画面外からの復帰 | [第4段階のはみ出し・初期座標とサイズ](Source/Shell/Pages/SCRIPT-PLACEMENT-20261010.md) |
| 配役の声・映像表情・待機表示 | [選択欄・自動表情・個別差分](Source/Shell/Pages/SCRIPT-CASTING-20261009.md) |
| 台本の種類 | [種類選択・保存識別](Source/Shell/Pages/SCRIPT-TYPES-20261008.md) |
| 共通背景・シーン画像・必須サムネイル・学習記録 | [画像受渡し](Source/Shell/Pages/IMAGE-WORKFLOW-20261007.md)、[学習記録一覧](制作支援/学習記録/README.md) |

## 更新ルール

note.mdは基本情報・未完了課題・リンクだけを保つ。作業経過、検証件数、エラー、EXEの提供記録は[開発履歴](note-history.md)へ日付付きで追記する。仕様や制作例の詳細は対応する文書へ記録し、ここからリンクする。
