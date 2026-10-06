# 第6段階：Codex校正の受信と人間による採否

2026-10-06の自律継続許可により、台本入力のNextから校正画面へ接続した。
確定仕様は `auto_video_ui_spec.md` 15・16節。アプリ内で文字ルールをAI校正と称する処理は追加していない。

## 操作

3区分の原稿を入力し、入力完了アイコンで入力ロックを解除してNextを押す。
空の原稿は進めない。Nextは本文・校正依頼・到達先reviewを同じproject.rigmovieへ保存した後に進む。
保存失敗時は台本画面と入力を保つ。戻る・ホーム・終了時の保存と、最後のNext到達先からの再開を維持する。

校正画面ではCodexへ入力完了を伝える。Codexが原稿をパイプから読み、対象範囲・修正案・理由を返す。
指摘一覧から選ぶと、その区分の本文と対象位置を表示する。
4つの採否アイコンはAI案採用・現在の文章採用・編集した案採用・保留。各アイコンのヒントでも識別できる。
提案編集欄の入力はeditedDraftとして即座に正本へ反映され、戻る・終了・任意Saveで保存される。
保留では本文を変更しない。採用済みの文章・採否・保留・修正案は保存再開で保持する。
上下・左右の区切りはドラッグで調整でき、長い理由・本文・案はスクロールできる。

採用で文章の長さが変わった場合、後ろにある未確定指摘のoffsetを調整する。
対象が重なる未確定指摘はstaleとして再確認対象にする。
台本入力に戻って原稿を変えると旧依頼を失効させ、次のNextで新しい依頼を保存する。
再依頼アイコンは現在の原稿から依頼を作り直す。以前採用した本文は保持するが、古い提案一覧は置き換える。
配役以降へのNextはこの工程では未接続。後工程実装時に校正の確定と配役へ接続する。

## 共通パイプ契約

`Exchange/workspace-<PID>.json` のcommandPipe。既存schemaVersion=1の封筒を使用する。
全変更に最新のprojectId/revisionを指定し、応答ごとにrevisionを更新する。

- `app-script-status`：implementedStage=review。reviewは依頼ID・指紋・状態・件数のみの短い要約。
- `app-script-text`：既存の分割読取。原稿3区分を同じprojectId/revisionで読み取る。
- `app-script-review`：必須projectId/revisionとoffset。1件ずつ返し、nextOffset/hasMoreで続ける。
- `app-script-submit-review`：projectId/revision/requestId/fingerprint/items/complete。
  itemsは最大20件ずつ、既存のパイプ60KB上限内で送る。
  各項目は一意のid（64文字まで）、section、offset、original、proposed、reason。
  offsetは0始まりUTF-16コード単位、original/proposedは4096、reasonは2048単位まで。
  originalはその範囲の現在本文に完全一致させる。絵文字のサロゲートペアを分割する範囲は拒否する。
  proposedの改行はCRLFに正規化する。最後の送信にcomplete=trueを指定する。指摘なしも空items＋complete=trueで表せる。
- `app-script-request-review`：最新projectId/revisionで再依頼。人の確認を代行する命令ではない。

指紋は区分IDと本文だけから計算する。区分表示の選択変更は原稿変更に数えない。
依頼ID・指紋・revision・originalのいずれかが違えば更新前に拒否する。
複数提案は複製上で一括検査し、不正項目が1つあっても部分反映しない。
complete後の追加・重複ID・古い結果を拒否する。
人の提案編集中は読取を許し、変更・再依頼・別作品への切替を拒否する。
採否はGUIから共通Workspaceへ反映する。AI提案の受信だけでは人の採用扱いにしない。

## 保存と確認

`scriptWizard.review` のformat=RIGMMaker.ScriptReview/schemaVersion=1に依頼と項目を保存する。
旧第1〜5段階データは開くだけでは書き換えない。表示文・音声文・配役・シーン・合成は生成しない。
読み込み時に形式・文字数・重複・現在原稿との整合を検査する。

このPCの正規リポジトリは `D:\DelphiProg\RIGMMaker`、データルートはKnownDocumentsの
`C:\Users\zan12\Documents\RIGMMaker`。以前のtake6パスを作成していない。
開始時のmainとGitHub mainは1446d64791a91a5068bb491e3ae7bf0b07904ee2で一致し、作業差分・未pushコミットはなかった。
AGENTS.md／ローカルの関連skillsは見つからなかった。Source/README.md・各工程記録・PSDの最新運用記録を参照した。

通常 `RIGMMaker.dproj` のWin64 Debug/Releaseを検索パス・出力先の上書きなしでビルドする。
EXEは使用中プロセスがないことを確認し、直前版を保存してから標準ビルドで更新する。
対象検証は `Invoke-ScriptReview.ps1` / `VerifyScriptReview`。
KnownDocumentsの既存RIGMを所有Tempへコピーし、分離した小さな確認作品を使う。
校正案は輸送・採否確認用として明記した固定fixtureであり、実作品のAI校正完了とは扱わない。
GUIイベント、原子的Next失敗、採否4種類、範囲補正、重複失効、提案編集ロック、保存再開、
実Workspaceパイプの送受信・不正batch拒否・古い結果拒否を対象にする。

ビルドログ・原本バックアップ・検証EXE・JSON・実ウィンドウ5枚は
`Win64/Validation/ScriptReview/Recovery/review-20261006-1124` に保管する。
所有検証は正常終了を確認する。完了したTemp作品は同Recoveryへ復元可能に移動し、対応表を残す。
ユーザー原本のSHA-256は不変。新画像生成・音声合成・長尺動画・install・課金・資格情報設定はしていない。


最終結果：標準Debug/Release Win64はいずれもエラー0（既存警告・ヒント17件）。両構成でGUI26項目・再起動5項目・実パイプ16項目が成功し、所有アプリは正常終了した。通常EXEのSHA-256は `59FF92643AE18E18E344913C39152078B07E1B8E7C012535AAE338B885FF067A`。直前版は `597960069B293B0AD2DE2D7731A2217AE0311F94DCF6A9B546999C362253FC0F`。最終JSONは同Recoveryのverified-release／verified-debugに保存した。
