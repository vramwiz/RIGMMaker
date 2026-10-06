# 第8段階：表示字幕の折返しと詳細編集

確定仕様 `auto_video_ui_spec.md` 18・19節に基づき、配役のNextから字幕工程へ接続した。VOICEVOX設定は次の工程であり、今回の境界は字幕の編集・保存・再開。

## 操作と正本

未割当・未確認の配役がなくなったらNextが有効になる。配役と字幕工程の到達先をproject.rigmovieへ保存してから画面を切り替える。保存失敗では元の配役画面とディスクを保持する。

同じメインフォームに字幕フレームを初回だけ生成し、以後保持する。一覧ではキャラ番号と表示字幕を別の列に表示し、選択発話のキャラ名を主領域の上に表示する。

- ↑↓：発話の選択。
- ←→：最初の折返しを1文字ずつ移動。サロゲートペアを分割しない。
- Enter：表示文・改行・メモの詳細編集を開始。
- 編集欄のEnter：改行を入力。
- Ctrl+Enter／Esc／入力完了アイコン：詳細編集を終了。

表示文とメモは入力ごとに同じWorkspaceの正本へ反映する。編集欄のカーソルは更新で戻さない。戻る・ホーム・終了で途中の文も保存し、再開は最後にNextで到達した字幕画面。選択発話・表示文・メモを保持する。

表示用の正本は既存TRigmMovieCue.Subtitle。音声用のText、元台本3区分、SpeakerId、Scene、音声設定・音声キー、他発話は変更しない。字幕専用メモは同じCueの任意フィールドsubtitleNoteとして保存し、音声指紋には含めない。旧作品にメモがない場合は空として読む。

左右操作は最初のCRLFだけを取り除いた表示文内で、その改行位置を移す。後ろにある手入力の改行を維持し、後続の改行を越える移動は拒否する。最初の手入力改行がない場合は、既存動画字幕と同じ幅・フォントで求めた最初の自動折返しを基準にする。右端まで移動した場合はその改行をなくせる。詳細編集では全ての表示文・改行を編集できる。

字幕3000 UTF-16単位、メモ2048単位以内。無効な制御文字、切れたサロゲート、無効なcueId／折返し位置は更新前に拒否する。字幕とメモのどちらかが不正なら両方とも変更しない。

前工程の原稿変更や校正採用で配役が失効した場合、字幕工程を要確認に戻す。旧字幕とメモを保持して表示するが、校正・配役のNextから準備し直すまで旧発話への表示文更新を拒否する。

## 既存動画字幕と同じプレビュー

RigmMovieLayoutの比率字幕領域（FHDで40,855〜1880,1045）、内側余白30×14、Yu Gothic UIの44pxフォントを既存合成と共有する。画面では字幕領域を拡大表示し、サイズが違う動画でも同じ比率で確認する。長い表示文は既存のMovieSubtitlePageと同じ複数ページに分かれ、前後のページアイコンで全ページを確認できる。

RigmMovieRenderingの折返し処理をMovieSubtitleLinesに抽出した。MovieSubtitlePageは同じ処理を呼ぶ。MovieSubtitleStyle／MovieSubtitleContentRectを合成と字幕プレビューの双方で使い、画面独自の文字数ルールを追加していない。

## 共通パイプと競合

Exchange/workspace-<PID>.jsonのcommandPipeと既存schemaVersion=1封筒を使用する。最新projectId／revisionで操作し、応答ごとにrevisionを更新する。

| コマンド | args |
| --- | --- |
| app-script-subtitles | projectId, revision, offset。rowsは1件ずつ、nextOffset/hasMoreで続ける。cueId、role、character、subtitle、voiceText、note、sceneId、breakOffsetを取得。 |
| app-script-select-subtitle | projectId, revision, cueId。選択のみ。 |
| app-script-edit-subtitle | projectId, revision, cueId, subtitle, note（省略時は既存メモを保持）。字幕とメモだけを原子的に更新。 |
| app-script-set-subtitle-break | projectId, revision, cueId, offset。最初のCRLFを除いた表示文内の0始まりUTF-16位置。 |

GUIで詳細編集中は既存の共通入力ロックを保持し、外部の変更・別作品切替を拒否する。読取は可能。古いrevisionや別projectIdを拒否し、人の編集を古い結果で上書きしない。app-script-statusは件数・選択・工程状態だけを返し、全表示文やメモを埋め込まない。

字幕の入力完了は人のGUI操作。音声工程の完了にはしない。字幕画面のNextは未接続のため非表示。

## 対象を絞った確認

Invoke-ScriptSubtitles.ps1は第7段階の所有確認作品だけを新しいTempへ複製し、元の確認作品・キャラのハッシュを照合する。ユーザー作品と実AI往復用の架空作品は変更しない。標準RIGMMaker.dproj Win64 Debug／Releaseの成果物で確認する。

GUIの上下・左右・Enter・入力完了、未確認配役の進行拒否、Nextの保存失敗、字幕・メモと原稿／音声／他区分の独立、サロゲート境界、実パイプの原子的な不正更新拒否、入力ロック、戻る・保存再開を対象とする。長い字幕の1ページを既存Compositorの1フレームと画素比較する。長尺動画エンコードやVOICEVOX合成は行わない。

通常EXEは使用状態を確認し直前版をRecoveryへ保存して更新する。全所有プロセスの通常終了後に、検証TempをRecovery/CompletedTestDataへ復元可能に移動する。

次の工程はVOICEVOX登録紐付け・読み／音声調整・試聴。その後のシーン画像と説明、総評、締め、動画編集への引渡しは未接続。
