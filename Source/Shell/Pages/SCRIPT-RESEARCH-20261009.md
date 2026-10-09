# 第6段階：作品情報・掘り下げ確認

2026-10-09の指定に合わせ、旧校正画面を作品の特定と調査結果の確認へ変更した。既存の工程ID `review`、工程番号、保存・再開、後続の配役／字幕／音声／動画編集は維持する。工程リストは「第6段階  作品情報・掘り下げ確認」の1行表示。

## 画面と進行

作品タイトルは最初に台本名から取り、人間が編集できる。候補一覧、選択候補の概要・作者等の識別情報・詳細・参照URL、確認チェックを上から順に表示する。1候補なら選択だけを自動で行う。複数候補は人間またはCodexが候補を選び、人間が「この作品で正しい」をチェックする。チェック前は掘り下げ結果を確定できない。

作品の確認後は同じページに掘り下げ一覧を表示する。閉じた行は要素名、取得名称、改行を空白に変えた概要、状態を横1行に配置する。通信中の要素は自動展開する。ユーザーも行のボタンで開閉でき、一度に1項目だけを展開する。

状態は `unconfirmed`（未確認）、`checking`（確認中）、`confirmed-info`（情報あり・確定）、`confirmed-none`（情報なし・確定）。確定状態には専用色と文字を付け、情報なしは「該当情報なし」と表示する。Codexによる確定と人間による確定は `confirmedBy` で識別する。

作品が人間によって確認され、要素定義が設定済みで、既定・追加の全項目が確定した時だけ、左の工程リストで次の工程へ進める。既存のリスト移動方式に合わせ、新しいNext／Backボタンは追加しない。追加項目を作れる案内を画面下部へ表示する。追加項目が未確認なら進行を止める。

タイトル編集、候補の選択変更、候補一覧の再取得、確認チェックの解除では作品承認と調査情報を解除する。台本種類の変更では既定要素も未定義へ戻す。解除前の内容は `scriptWizard.researchArchives` に保管する。空の状態をタイトルの1文字入力ごとに重複保管しない。

## 要素を固定しない

現段階で作者・制作会社・音楽などの種類や件数を製品コードに固定していない。定義のない種類は「既定要素は未定義」と表示し、自動で確認完了にはしない。

将来の種類別の定義はデータルートの `Settings/script-research-elements.json` から初期化できる。形式は `format: RIGMMaker.ScriptResearchDefinitions`、`schemaVersion: 1`、`types` オブジェクト。`types` の台本種類IDをキーとして `{id,label}` の配列を置く。このファイルがなくても正常に画面を開ける。

現在の台本だけの定義はパイプの `app-script-research-definitions` で設定できる。明示的な空配列は「既定要素を0件と定義した」扱いで、未定義とは区別する。任意の追加要素は既定要素がすべて確定した後に作成できる。種類ごとの差異と実際の項目は今後決める。

## パイプ

既存の `Exchange/workspace-<PID>.json` のcommandPipeと、schemaVersion=1の封筒を使う。UIからCodexへプロンプトは送信しない。ユーザーがCodex側で検索を指示し、Codexが読み取り・Web調査・結果反映を行う。台本制作では入力中による通信ロックを設けず、タイトル欄にフォーカスがあるままでも結果を反映できる。textEditingは常にfalse。入力値の検証と人間の最終承認は維持する。

読取と変更には現在の `projectId/revision` を指定する。変更時は `app-script-research` から得た `researchId` も指定する。作品を特定してからの項目更新には `workId=selectedCandidateId` が必要。検索条件・作品・版の違う結果を拒否し、失敗時には部分更新しない。

| 命令 | 引数・用途 |
| --- | --- |
| `app-script-research` | `section: summary/candidates/candidate/elements/element/integration`。一覧は `offset/limit`、詳細は `id` |
| `app-script-research-title` | `title`。タイトル変更と既存結果の無効化 |
| `app-script-research-candidates` | `candidates` 配列。各候補は `id/name/overview` と任意の `identity/details/sources` |
| `app-script-research-select` | 候補の `id`。選択しても承認はしない |
| `app-script-research-definitions` | 現在の `scriptType` と `elements: [{id,label},...]`。旧定義・結果は履歴へ保管 |
| `app-script-research-element` | `id/workId`、任意の `name/summary/details/sources/state`。状態省略は確認中へ戻す |
| `app-script-research-expand` | 展開する `id`。空文字はすべて閉じる |
| `app-script-research-add` | 追加要素の `id/label` |

`summary` には現在ページ・工程・第1／第2段階・台本種類・タイトル・候補選択・人間の確認・展開項目・次へ進めるかを返す。`candidate` で選択候補の完全な概要、`element` で各項目の詳細を取得する。既定／追加は `kind=default/extra` で区別する。

一覧では概要の冒頭160文字を返し、詳細は1件ずつ取得する。既存の60KB通信上限を維持し、画像や長大な全文を一覧へ埋め込まない。上限は候補100件、項目200件、名称256文字、概要3000文字、詳細8000文字、参照URL12件（各2048文字）。これらは輸送・保存上の上限であり、実際の掘り下げ件数の既定値ではない。

作品の最終承認はGUIのチェック操作専用。外部から `app-script-research-confirm-work` を呼んでも拒否する。項目の確認結果はCodexから更新できるが、人間の作品承認を代行するものではない。元の校正用パイプと保存データは互換維持し、第6段階の新しい進行条件は作品情報の状態で判定する。

## 保存と次工程

`scriptWizard.research`（format=RIGMMaker.ScriptResearch、schemaVersion=1）に候補、選択、作品承認、定義、全項目、詳細、参照、確認者、展開状態を保持する。旧台本の校正データは破棄せず、第6段階を開く時に作品情報を初期化する。

次工程へ保存して移動する時は、確定作品と `confirmed-info` の項目だけを `scriptWizard.researchIntegration` に渡す。情報なしの項目は補完材料から除外する。作品情報を変更すると、この受渡し用データも無効化する。人間が作成した `scriptText` はこのページで変更しない。自然な文章統合そのものは次工程側の処理として別に扱う。

## 検証

`Source/Psd/Validation/Run-ScriptResearchCheck.ps1 -OutDir <新しい検証出力>` で独立した確認用キャラ・台本を作成する。作品名や検索結果はすべて輸送用fixtureであり、実作品のWeb調査結果ではない。

新規台本から第6段階への移動、GUIだけの作品承認、外部自動承認の拒否、再検索・候補変更・種類変更、異作品・古い版の拒否、折りたたみ、DPI、追加要素、保存再開、原稿保持、次工程への受渡し、実Named Pipeを確認する。画像はVCLのPaintToによるレイアウト記録で、標準TMemoの本文描画は含まれない場合がある。Memo本文はコントロールの値とパイプを別途照合する。ユーザーの実作品・通常アプリへ試験命令を送らない。
