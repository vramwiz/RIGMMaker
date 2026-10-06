# 台本 第11段階：任意総評・人間の評価値・追加音声

2026-10-06。確定仕様 auto_video_ui_spec.md の総評工程を、Stage10 のシーン確認の後へ接続する。

総評の有無は none / yes を人間が選ぶ。none の Next は内容と closing 到達先を先に保存し、総評データを新規生成しない。yes の Next は summary-edit 到達先を保存する。総評の文章・独立字幕・読み・キャラ番号、チャート題名・種別・最小/最大・3～8評価要素と今回値を編集する。初期値は空の文章/要素/評価値、未選択の配役。AI評価を装う規則処理を行わない。

既存 RigmMovieChart / GraphRadarGeometry を再利用し、人間の有効な評価値からレーダー/棒チャートを描画する。最小値は省略時0で従来チャート互換。途中の数値文字列（例 `-`）は下書きとして保持するが、確認完了・Nextは厳密な数値と範囲検査を要求する。音声用本文/読み2000文字、字幕3000文字を既存の文字検査で確認する。

確認完了後の Next は正本の opening/body/closing 配役行を変更せず、総評専用の1セリフ/1シーンを closing の直前へ追加して、同じ voice 工程へ移動する。追加セリフは通常のUUID/style/query/WAV/LAB/音声指紋を利用する。全音声の確認完了後、内容と closing 移動先を保存する。既存本文の配役指紋・音声・字幕・シーン素材・保存配置を保持する。尺は既存scene順とdurationから後続へ反映される。

総評なしへの変更は専用セリフ/シーンだけを保管して取り外し、文章/評価値と音声ファイルを保持する。再度有効にすると保存した同じIDを復元し、指紋が同じ音声を再利用する。前工程で再配役する場合も補助データを先に保管する。総評の字幕編集・左右折返し・読みの変更は総評draftへ反映され、後で戻って古い入力に上書きされない。

共通パイプ：`app-script-summary` は projectId/revision 付きの取得、`app-script-set-summary` は人間draft、`app-script-complete-summary` は内容検査。変更は共通projectId/revisionとGUI入力ロックを要求する。statusは長い総評本文・保管情報を含めず、必要な総評入力は専用取得で読む。古いrevision、別project、無効な型/文字数/制御文字/キャラ番号は変更前に拒否する。

確認は通常 RIGMMaker.dproj Win64 Debug/Release。`Source/Psd/Validation/Invoke-ScriptSummary.ps1`（PowerShell7）で分離した明示的な架空作品をコピーし、UI、実パイプ、既存VOICEVOXの短い追加音声、voice中断再開、closing再開、総評取り外し/復元を確認する。長尺動画エンコードなし。元確認作品とRIGMのhashを保持する。

この区切りでは closing の到達先保存まで。締め文章/終了画像/サムネイルのUI接続と既存動画編集への引渡しは次工程。シリーズ管理・過去作品値からの新作コピーは既存管理実装がなく未接続で、旧作品の自動更新は行わない。VOICEVOXのアクセント/mora詳細UIも残工程。

第10段階の記録：[SCRIPT-STAGE10-20261006.md](SCRIPT-STAGE10-20261006.md)。検証ログ・EXE/変更前原本・分離確認作品は `Win64/Validation/ScriptSummary/Recovery/summary-20261006-1525` に保存する。

2026-10-06最終整理：この工程で12→13に増えたものは、RigmScriptSummaryFrameのH2443（TJSONArray.GetValueのインライン展開に必要なSystem.Generics.Collectionsのuses不足）1件。参照を追加して解消した。動作の変更はない。締め設定・終了画像・サムネイル・動画編集への引き渡しは現在[第12段階](SCRIPT-STAGE12-20261006.md)まで接続済み。上の「次工程」はStage11実装時点の記録である。
