# 検証記録 2026-10-15

## Dots本体での成功報告

利用者からDots実行画面の画像と「成功しました」の報告を受けた。提示された画面には、更新されたMarkdownに従ったDots→アプリ→Codexのテキスト往復、画像生成・パイプ経由の取得、保存元と受信画像のSHA256一致、日本語・改行・絵文字の正常処理、18要求で通信エラー・タイムアウトなしと記載されている。固定AppContainer SIDに依存しない方式がDots実行環境でも動いたとの報告。生成画像は指定512pxに対して1254×1254であり、サイズ指定の遵守は通信成功と区別する。これは利用者提供のDots側結果であり、こちらの独立AppContainer試験や本編統合試験とは別の証拠として記録する。

## Low AppContainer・変動SIDへの対応

Dots側から同一ユーザーSID・Low整合性・変動するAppContainer SIDとエラー5が報告された。通常ACLは維持し、`--allow-appcontainer` の明示起動でだけAppContainer系グループの読み書きACEとLow必須ラベルを設定する試験モードを追加。各要求の受信後にクライアントを偽装して同一ユーザーSIDを確認し、さらに起動ごとの接続トークンを検査する。固定のAppContainer SID、Everyone許可、他プロセスの権限変更は使わない。

`appcontainer-final-02/result.json` の27項目に成功した。実際のWindows APIで一時AppContainerを複数起動し、通常モードでOpenがエラー5になること、試験モードでは異なるSIDのAppContainerとLPACからping/pongできること、接続トークン欠落でunauthorizedとなること、日本語・改行の往復、画像のアップロード・復号・保存、さらに別SIDから画像を取得してバイト列が一致することを確認した。成功した6コンテナのSIDは全て異なり、Low整合性である。

既存のオフライン試験は `appcontainer-regression/result.json` と `default-regression/result.json` で各30項目に成功した。新しいコードのWin64 Debug/Releaseは専用dprojで警告0・エラー0。起動中の通常EXEを保持するため、出力先は `Win64/DotsCodexProbe/AppContainerFix/<構成>/`。利用者が新しい試験モードを起動できる `Start-AppContainerProbe.ps1` とDotsへの追試依頼を同梱した。

Dots本体からの追試はこれからであり、こちらの実AppContainer試験と区別する。Codex通信処理は変更しておらず、今回のAppContainer試験から実モデルへの送信はしていない。検証で作ったプロファイルは各所有プロセス終了後に削除し、検証出力のACL追加は新規の試験フォルダだけに限定した。

名前の `LOCAL\` 接頭辞も試したが、この端末の別AppContainerからはエラー2となった（appcontainer-03）。この実装ではWin32サーバーの従来のパイプ名を保ち、appcontainer-final-02の接続成功を確認した。MSIXパッケージ同士の接続と、このWin32サーバーへの接続は同一と仮定しない。

## Dots接続時のアクセス拒否の切り分け

Dots側から `0x80070005`（パイプOpen時のアクセス拒否）の報告。稼働中の通常Releaseに対し、こちらの送信器では `ping/pong` が成功した。同じ接続へWindows APIのCreateFileでも接続でき、診断結果は `nativeOpenWin32Error=0`, `pingSucceeded=true`。送信側は通常ユーザー、Medium整合性、restrictedSidsなし、AppContainerではない。

Dots側のトークン情報はまだ取得しておらず、拒否原因は未確定。アプリ側ACLは起動ユーザーのSIDのみを許可するため、Dots側の別ユーザー・制限SID・整合性・AppContainer等を比較する必要がある。診断用 `Diagnose-PipeAccess.ps1` と利用手順を追加した。接続可否を確認するためのアクセス制限解除は行っていない。

古い接続情報2件も残っていた。送信器へ終了済みPIDの検出とアクセス拒否の診断案内を追加。現在の接続へのping成功、終了済み接続の `stale_connection` 拒否、既存オフライン30項目を確認。証跡は `output/validation/20261015-dots-probe/normal-access.json` と `access-diagnostic-regression/result.json`。Pascalソース・EXEはこの切り分けでは変更していない。

本編と分離したテストアプリ・専用作業ディレクトリ・所有プロセスだけで試験した。Dots本体からの操作は行っていない。Dotsの能力は [問い合わせ文](DOTS-QUESTION.md) に従って別途確認する。

## 追加検証とタスクバー修正（2026-10-15）

以下はこの追加作業の結果。後続の既存検証記録とは別の実行であり、以前の成功記録を今回の成功として扱わない。

- 現行Release EXEを起動し、接続情報を確認した。最初の `ping` は `NamedPipeClientStream.Connect(15000)` が約15秒でタイムアウト。同一コマンド内でアプリの生存を確認した試行は同APIで `Access to the path is denied`。`connection.json` の読取拒否ではない。
- 送信器側はAppContainer・Low整合性。ユーザー手動起動後の接続情報に記載されたPIDへの `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` もWin32エラー5で拒否。相手側トークン・EXEの比較は不能。パイプ拒否の直接原因は未確定。
- この追加作業では `codex.start` 未送信。テキスト往復・画像生成・画像取得・クラウド転送はいずれも未検証。再接続やACL・許可SID・昇格・サンドボックス設定の変更は行っていない。
- `MainFormOnTaskbar=True` は既存コードにもあった。VCLソースでは通常の `TCustomForm.Create` が `FCreatingMainForm` を設定する一方、`CreateNew` はその設定を通らない。コンストラクタ内の早期ハンドル作成時に、非表示ApplicationウィンドウがOwnerになる経路がある。
- 専用フォームの `CreateParams` で `WndParent=0`、`WS_EX_APPWINDOW` 設定、`WS_EX_TOOLWINDOW` 除去を明示。初回作成とハンドル再作成後の条件を検査する `--window-check` を追加した。パイププロトコル・ACLは変更していない。
- `Build-Probe.ps1 -OutputRoot` を追加し、既存EXEに触れず別出力先でビルド可能にした。
- `Win64/DotsCodexProbe/TaskbarFix-20261015/Debug/build.log` に今回のビルド失敗を保存。MSBuildのBRCC32タスク初期化中、`Borland.Globalization.ResourceStringManager.GetUILocaleOverrideString()` のレジストリアクセスが `SecurityException` で拒否された。Debugコンパイルに進まず、Releaseビルドも未実行。権限変更や別手段による回避は行っていない。
- 修正版EXEは未作成、`--window-check` と通常デスクトップのタスクバー表示は未実行。ユーザー起動アプリを閉じたり既存Release EXEを置換したりしていない。

通信試験の証拠は `output/validation/dots-delegated-20261015-113635-1ab9203f/`。ビルド制限がないユーザーの通常の開発環境で別出力先ビルドとREADMEの無音検査を行い、通常起動のタスクバー表示を確認する必要がある。

## ビルド（以下は既存記録）

`Build-Probe.ps1` で専用dprojをWin64 Debug / ReleaseともMSBuild。最終版は両構成とも警告0・エラー0。EXEとログは `Win64/DotsCodexProbe/<構成>/`。

## 実施結果

| 証跡（リポジトリのoutput/validation/20261015-dots-probe配下） | 結果 |
| --- | --- |
| `final-offline/result.json` | 30項目成功。パイプ疎通、UTF-8、日本語・絵文字・改行、1バイトずつの分割送信、大きいフレームの往復、不正JSON・引数・コマンド、再送の二重実行防止、テキスト保存、PNG/JPEG/BMP受信、画像往復・SHA256、PNG寸法上限、1フォーム、接続中の正常終了と接続情報削除 |
| `live-01/result.json` | 当時の32項目成功。共通のパイプ試験に加えて、本物のCodexへテキスト送信、受付再送で同一jobId、多重開始拒否、回答受信、参照画像の認識、中止・復帰 |
| `image-01/result.json` | 当時の27項目成功。共通のパイプ試験に加えて、本物のCodexによる画像生成、正式な完了通知、受信・復号・ローカル保存、生成画像のパイプ返却 |

テキストの実回答は `DOTS_TEXT_OK`。画像入力には青一色の64×48 PNGを使い、実回答は “The image is a solid medium blue with a slight periwinkle tint.”。Codexからのテキストと画像理解の往復を確認した。

生成画像は白背景の青い球体の試験指示で取得。1254×1254 PNG、1,101,415 bytes、SHA256 `246f7cf9329e14ed4a860adcd882486c8a4b9fe04ea303f7f8531095cb0e72da`。`image.get` の返却ハッシュも一致。元画像と通信ログはローカル証跡に保持する。

実Codex試験後、要求キャッシュのメモリ上限とecho/text.saveの型検査を追加した。再ビルドと最終オフライン30項目で確認した。Codexの通信処理自体はこの追加で変更していない。

## 未確認・対象外

Dots本体のファイル読込・EXE起動・パイプ/API接続能力、リモートからの実操作、常駐起動機構、任意フォルダへの配置、再起動後のジョブ再開は未確認または未実装。GUIは同じフォームの画像デコーダーと表示コントロール更新を通したが、物理マウス操作・スクリーンショットによる目視の確認は行っていない。本編の再ビルドや実作品の変更は行っていない。
