# 架空作品での実AI提案往復

校正・配役の既存共通パイプとGUIを、本文の意味を読んだAI提案で確認した。ユーザー作品ではなく、Codex著「架空の星空観測所」の確認用複製のみを使用する。

## 提案と採用

親AIが原文を読んで提供した任意の表記提案は、本文のUTF-16 offset 7の「明り」を「明かり」にする1件。他の本文や出だし・締めを変更しない。「明り」も意味は通じるため、必須の誤字修正とは扱わない。

配役は、歓迎・手順の回答・色の説明・締めを案内役、許可を尋ねる文と色を尋ねる文を質問役に提案する。実際にパイプから取得したキャラpath、キャラ番号、cueId、section/offset/lengthの原文アンカーに対応させる。並びだけで配役しない。

`Invoke-ScriptSemantic.ps1` はこのAI提案を再生する確認用ハーネスであり、アプリにAIを装う文字ルールを組み込んでいない。毎回実アプリのパイプから最新revision、requestId、fingerprintと本文を取得する。受信直後は校正pending、配役origin=ai/confirmed=false。ユーザーが明示的に許可した確認用GUI操作で、校正のAI案採用ボタンと6行のEnter採用を実行する。実ユーザーがボタンを押したとの主張はしない。

採用後はパイプで再取得し、古い校正・配役の再送拒否を確認。Nextで配役・字幕の各移動先を保存してから遷移し、通常終了・再起動で校正採否、6つの配役、字幕・音声文の分離、再開先を照合する。

## 実行と根拠

標準 `RIGMMaker.dproj` Win64 Debug/Releaseでビルド。両EXEで限定フローを確認し、各GUI 29、再起動4、パイプ6項目が成功。元の架空作品と2つのキャラ元ファイルはSHA256不変。初回検証はキャラキャッシュを読み終わる前にNextを押して停止したため、既存の読込待ちをハーネスへ追加した。アプリの本番処理は変更していない。

手順は `Invoke-ScriptSemantic.ps1 -ExecutablePath ... -OutputDirectory ... -FixtureProject ... -FixtureDataRoot ...`。所有マーカーと作品タイトル・キャラpathの一致が必須。新しいTemp rootへ複製して、実ユーザールートを使わない。GUIの保存再開・パイプのrequest/response全文・画面PNG・元ファイルハッシュを出力する。

根拠は `Win64\Validation\ScriptSemantic\Recovery\semantic-20261006-1301`。`verified-release` と `verified-debug` が最終成功分。採用直後・字幕引渡し・再開後の実キャラpathとの一致も照合する。`final-release-2` と `final-debug` は追加照合前の成功分。初回失敗分も復元可能な形で保持する。確認用.rigm・制作データ・EXE・画像・パイプ全文はignoreされたRecoveryに置き、Gitにはソースと手順のみを含める。
