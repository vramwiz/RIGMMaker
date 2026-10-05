# 2026-10-05 検証・配置結果

通常RIGMMaker.exeへの統合Release配置を完了しました。最新の操作と登録は[OPERATIONS.md](OPERATIONS.md)、統合検証は[INTEGRATION.md](INTEGRATION.md)。以下は独立版完成時の履歴であり、その時点の「未接続」「元EXE/dproj一致」は現在の統合版には適用しません。

独立したRelease版を `D:\DelphiProg\MyApp\RIGMMaker\PsdStudio.exe` に配置しました。起動時に指定データルートのキャラを開きます。既存RIGMMakerの入口分岐・旧パイプ・制作経路は未接続です。既定データルートと一時整理はPsdStudioだけに適用します。

## 開いて確認できる成果物

- キャラ1ファイル: `D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar`（10,173,412 bytes）
- 追加後のPSD: `Characters\blonde-android-20261005-v2.psd`（14,078,629 bytes、59画像/10グループ）
- FullHD例: `Characters\blonde-android-20261005-fullhd-0045ef0c.png`
- 視線比較: `Work\PsdGenerated-20261005\gaze-contact-sheet.png`
- 全方向/横向き/後ろ向き確認画像: 同Work下の `Preview`
- 生成原本・登録PNG・ハッシュ/位置/倍率: 同Work下の `prepared-assets.json` と `generation-provenance.json`

通常の保存/読込にはpsdcharだけで足ります。PSDは画像レイヤーの書き出し用です。生成原本は制作履歴として別途保全しました。

## 確認結果

- Delphi 37.0 Win64でDebug/ReleaseのGUIビルド成功。新規Pascal/DPR14ファイルのUTF-8 BOM/CRLFを確認。
- PsdValidationはDebug/Releaseそれぞれ29項目PASS。瞬き/高速音素、非正面の顔除外、小動作と顔制御の併用、全身連番の境界/ループ、PSD/ZIP往復と安定ID、外部PSD編集禁止/原バイト保存、パス/不正画像/ZIP逸脱、所有印/完了/期限/活動leaseを含む復元可能な回収を検証。
- PsdVerifyRegisteredは実キャラ93項目PASS。元51差分と非表示原画1枚のRGBA/配置一致、通常合成の追加前一致、表情8組、視線6方向、非正面2ポーズ、追加7絵のPNG一致/履歴、非正面で表情/瞬き/音素を指定しても合成不変を確認。
- psdcharだけを元Workがない別ルートへコピーし、通常合成一致と非正面FullHD描画を確認。
- 配置したEXEを実際に起動。status、古いrevision拒否、未編集saveのタイムスタンプ維持、喜び+a口形+呼吸、FullHD PNG出力、正常終了、接続印の回収を実パイプで確認。
- 元RIGM/Workの入力74ファイルは全ハッシュ/サイズ一致。既存RIGMMaker.exe/dpr/dprojも元ハッシュ一致。ユーザーの未追跡「制作支援/制作物」を保持。参照元プロジェクトを変更せず、コピーしたSYNC_Motionの2ユニットも元ハッシュ一致。

証拠は `Win64\Validation\PsdStudio` の build-debug.log/build-release.log、validation-debug.log/validation-release.log、registered-validation.log、generated-registration.json、smoke-result.json、preservation-result.json。最新の配置EXEと登録キャラのSHA-256は refinement-result.json を参照してください。

## 生成と残る確認

哀しみ/解説は既存パーツの組み合わせです。視線5方向/全身横向き/全身後ろ向きの7絵は内蔵画像生成による新規描画です。新規ソフト・追加有料APIは使っていません。原画の正確な分離や同一ピクセルとは主張しません。

新規絵はpending-user-reviewです。視線の強さ/造形の採用確認と、新規ポーズの輪郭の色にじみの改善が残っています。現在のキャラは正面を初期表示し、新規絵は選択して確認できます。実キャラの全身連番素材は未配置です。2枚の静止ポーズと呼吸等の連続変形を全身連番として扱っていません。

内部画面PNGはプレビューの向き・合成を確認できましたが、標準Windows部品の描画がキャプチャに収録されない環境制限があります。診断JSONでは10ボタン、64項目ツリー、各選択部品の可視性・ハンドル・配置を確認しました。マウスによる全GUI操作/標準部品の実画面は未確認です。

音声生成/再生同期、台本/タイムライン編集、アプリ内AI直接接続、肌補完、外部PSD名編集、旧制作系への接続は未実装です。次の接続点は共有Session.Commandと作品時刻のSession.Frameです。長尺MP4は出力せず、commit/pushもしていません。

## 復元可能な整理

検証EXE/DCU/TestData/移動検証ルート/画像作業複製は `Win64\Validation\PsdStudio\Recovery\20261005-103820` へ移動しました。復元先は同階層のrecovery-index.jsonに記録しています。再利用するテストDPR/スクリプトはSource/Psd/Validationへ保持しました。ログ・画像証拠も保持しています。

今回作成した同一FullHD試験PNG6枚だけをデータルートの `Temp\PsdRecovery\validation-20261005` へ移しました。最新FullHDとキャラ/PSD/生成原本/入力は保持しました。永久削除・ごみ箱消去・強制終了はしていません。

通常の起動時回収は30日経過した所有するcompleted/expiredジョブだけです。活動lease・入力素材・台本・永続作品を除外し、Recoveryへ移動する方式です。

## 追加仕上げ

輪郭清掃の内蔵画像編集を2件試しました。Windows保存には成功しましたが、色にじみが残り細部も再描画されたため、改善版として採用しませんでした。元の登録PSD/psdchar/PNGを維持し、候補はWork/PsdGenerated-20261005/CleanupCandidatesへ分離保存しています。具体的な受信/Windows保存経路はIMAGE_TRANSFER.mdに記録しました。

開く→表情/視線/正面/非正面選択→ツリー選択→保存→再読込→新Session読込のGUI部品イベント回帰がDebug/Release各9項目PASS。生産キャラは検証ルートへコピーして試し、選択変更を生産データへ保存していません。Source/Psd/Validation/Invoke-GuiFlow.ps1で再実行できます。結果JSON・画面PNGはgui-flow-*。標準部品が内部キャプチャに描かれない制限と、物理マウス/ファイル選択ダイアログの未確認は残っています。

指定データルートおよび既存の制作物に音声/LAB素材はありません。実音声同期は確認できません。利用可能な生成手段は静止画生成/編集で、同一形状を固定した自然な動画/連番生成は検証できないため、擬似移動や独立再描画を全身動作として登録していません。新規課金・インストール・旧分岐接続はしていません。

## PSD制作状態・動き基準の追加検証（2026-10-05）

単一フォーム・遅延生成の最新中間成果は[WIZARD.md](WIZARD.md)。新シェルDebugの導線14項目とPSD編集11項目が成功。通常起動先は変更していない。

PsdProductionValidation.dpr（Debug）の24項目が成功。未完成PSDのキャラ編集、AI/GUI共通の動き基準検証、無効値の保存拒否、制作中の自動保存、保存再開、仕様検査結果の永続化、新規台本追加のGUI/命令両方での拒否、保存済み動画の互換読み込み、上半身下端より下の呼吸画素の保持、登録原本のハッシュ不変を確認した。GUIイベントは実部品を使い、画面外では描画イベントを明示実行した。検証用の基準点は素材複製だけに設定した。

既存PsdValidation.dprの29項目と、Release PsdStudioのGUI保存/再開9項目も成功。RIGMMaker/PsdStudioの隔離Releaseビルド成功。通常EXEのSHA-256は85D724CB1F4EE829D7FAA8A745AC69DE52E78072E1A1D78329235940D1B212B8、登録キャラは1DFAAEFE9377AE0F4C4E3B4D76A1E02F09D085940228CB3C4DFA8E006E1E2EC4で不変。診断証拠はWin64/Validation/PsdStudio/production-validation.json。使い捨てEXE/DCU/素材複製は同Recovery/production-20261005へ移動し、recovery-index.jsonを保存した。Releaseの起動用EXEは保持した。

必須感情の一覧が未確定なので完成付与は保留。完成済み編集の明示保存経路は用意したが、確定条件を満たした実キャラの完成/再編集試験は未実施。過去の34項目統合試験は未完成PSDの新規追加を許可する旧仕様の前提が含まれるため、今回そのまま再実行していない。新しい追加拒否と過去作品維持は今回の24項目で対象限定検証した。AI画像生成・Syncroh2交換の本アプリへの接続・長尺MP4出力は実施していない。
