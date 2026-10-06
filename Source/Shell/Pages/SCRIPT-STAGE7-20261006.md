# 第7段階：配役の提案受信と人による確定

2026-10-06の自律継続許可により、校正のNextを配役へ接続した。確定仕様は `auto_video_ui_spec.md` の配役・字幕・保存モデルの節。アプリ内の文字ルールでAI配役を行う処理はない。

## 進行と操作

校正依頼の受信が完了し、未確定・保留・要再確認の指摘がなくなった場合にNextが有効になる。本文、配役データ、到達先castingを同じproject.rigmovieへ保存してから遷移する。保存失敗では元画面・原稿・ディスクを維持する。

配役画面は同じメインフォーム内で初回だけ生成し、その後保持する。キャラ番号と発話一覧を表示し、番号キー1～9／テンキー1～9は人の配役を確定して次の発話へ進む。Enterは現在のAI案または単独候補を受け入れて次へ進む。未割当へのEnterは確定も移動もしない。上下キーで発話を移動する。

複数キャラの場合は初めに未割当。Codexの提案は「AI案」として表示し、受信だけでは確認済みにしない。キャラ1人の既定割当は「単独候補」とし、AIの提案や人の完了と区別する。再依頼も人の確定済み配役は保持する。

番号は作品内でキャラの登録相対パスに対応し、再選択や保存再開でも変えない。外した番号は履歴用に予約し、同じキャラを戻すと同じ番号になる。1作品で履歴を含め9番号を使い切った場合、新しいキャラを無言で既存番号へ割り当てず説明して停止する。

## 原稿・発話・シーン

opening、body、closingの原稿をそのまま保存し、キャラ名の接頭辞は必須にしない。コロンを配役区切りとして勝手に除去しない。

初期発話は空行で区切った段落単位。通常の改行は同じ発話内に保持する。段落をシーンにし、各シーンは1件以上の既存TRigmMovieCueを持つ。既存モデルの音声文2000文字上限を超える段落は同じシーン内の複数発話に分ける。UTF-16のサロゲートとCRLFの途中で切らない。

選択発話の音声文でカーソル位置を決め、分割アイコンで同じシーン内の2発話に分けられる。結合アイコンは同じシーン・区分の次の発話と結合する。原稿3区分は変更せず、配役を再確認対象にして新しい依頼を作る。字幕または音声ファイルを編集済みの発話はこの工程で分割・結合しない。

TRigmMovieCue.Textは音声文、Subtitleは表示文として独立する。前工程の原稿変更では、同じ区分の原稿が未変更なら発話ID・シーン・人の確定配役・字幕・音声設定を保持する。変更した区分の旧配役・発話・シーンはcastingArchivesに保全し、新しい原稿から準備する。失効した配役は再依頼だけで有効にせず、校正のNextから再準備する。

話者は既存Speakersを保持し、今回新しく作るキャラ話者のStyleIdは-1。VOICEVOXへの紐付け完了とは扱わない。EnableComposition時にも同じ番号の話者を配置キャラへ接続する。最終の字幕・音声工程は後続実装である。

## 共通パイプ

`Exchange/workspace-<PID>.json` のcommandPipeを使う。schemaVersion=1の既存封筒で、全変更と配役取得に最新projectId/revisionを指定する。応答ごとにrevisionを更新する。

| コマンド | argsと動作 |
| --- | --- |
| app-script-casting | projectId, revision, offset。rowsは1件ずつ、nextOffset/hasMoreで読む。番号、役名、cueId、原稿区分・位置、音声文text、表示文subtitle、sceneId、採否を返す。 |
| app-script-request-casting | projectId, revision。新しいrequestId/fingerprintを作る。人の確定済み配役を維持。 |
| app-script-submit-casting | projectId, revision, requestId, fingerprint, items[{cueId,role,reason}], complete。最大50件、理由2048文字。 |
| app-script-select-casting | projectId, revision, cueId。選択のみ。 |
| app-script-split-casting | projectId, revision, cueId, offset。選択発話内の0始まりUTF-16位置。 |
| app-script-merge-casting | projectId, revision, cueId。同じシーン・区分の次の発話と結合。 |

提案の指紋は原稿、キャラ番号、発話IDと境界、音声文から計算する。古いrevision・requestId・指紋、未知cueId、無効番号、重複cueId、人の確定済み発話を含むバッチは全体を拒否し、部分反映しない。提案受信は暫定割当のみ。人の確定操作をパイプに追加していない。入力ロック中の外部変更拒否は既存Workspaceに従う。

app-script-statusは配役の件数、未割当、未確認、選択、役一覧と依頼情報だけを返し、全発話・原稿・履歴を埋め込まない。実際の内容判断はCodexが原稿／発話を取得して提案する。

## 狭い検証と次の工程

`Source/Psd/Validation/Invoke-ScriptCasting.ps1` は実登録RIGMを所有Temp内の2ファイルへ複製し、明示的な確認用の案内役／質問役として使う。原本ハッシュを前後比較する。標準RIGMMaker.dproj Win64 Debug/Releaseの成果物で、GUIキー操作、失敗時Next、実パイプの原子的な拒否、分割結合、表示文と音声文の分離、原稿変更、保存再開を確認する。各確認アプリは通常終了する。長尺動画出力は行わない。

テストで送る空の校正完了や番号2への配役提案は輸送fixtureであり、AIによる意味の校正／配役が済んだとは扱わない。別途、Codexが書いた架空の星空観測所の短い原稿をreviewで保存し、`script-casting.json.semantic-fixture.json` にUID・保存先・依頼情報を記録する。親が実際に原稿を読み、校正と役割の理由を提案できる。ユーザー作品ではない。

今回の到達境界は配役。字幕の上下行移動・左右折り返し・Enter編集、VOICEVOX紐付け・読み／音声調整・試聴、シーン画像と説明、総評、締め、動画編集への引渡しはまだ未接続。次工程で同じCues／Scenes／Speakersと配置を使う。
