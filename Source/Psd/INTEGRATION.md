# 2026-10-05 PSD統合完了

独立PSD系統を基に、後続の依頼で共通一覧・動画へ接続しました。通常RIGMMaker.exeへRelease版を配置済み。起動/編集/共通制作の操作、登録数/名前、正式作品パスは[OPERATIONS.md](OPERATIONS.md)。Git commit/pushは行っていません。

## 到達した実装

- 共通ライブラリと動画作成一覧で、Characters/*.psdcharとRIGM/*.rigmを形式付きで表示する。同じキャラのPSDとRIGMは別のファイル/キャラIDのまま保持する。古いRIGM登録も消さない。
- 一覧のダブルクリック/編集は同じOpenCharacterEditorから形式別の編集画面を開く。PSDはTPsdStudioForm、RIGMは既存TRigmEditorForm。PSD保存後は両方の一覧を更新する。
- 共通作品のactorにrenderFormatとpsdViewを保存する。旧作品でrenderFormatがない場合は拡張子から補完する。台本・話者・字幕・配置・時刻・音声ジョブは共通のモデル/画面を使う。
- RenderMovieFrame/RenderComposition内でPSD actorをTPsdRendererに委譲する。通常プレビュージョブと動画出力ジョブは同じ入口を使う。表情の共通感情IDは既存PSDプリセットに対応づける。LABがある場合は既存音素サンプラーを使う。音声終了後は閉じ口にする。
- 動画作成画面にPSDの視線、正面/登録済み非正面、小さな動きの設定を追加する。旧ボーン/メッシュ系モーション生成をPSDで使わない。連番はキャラパッケージ側へ登録してnonFrontIdで選択する。
- PSDパッケージも作品保存時にCharactersへハッシュ付き複製を格納する。共通パイプのregister-characterはRIGM/PSDキャラ/PSDを扱う。PSD入力を旧RIGMへ変換しない。
- アプリの既定データルートはD:\Users\take6\RIGMMaker。検証では--data-rootと--settings-dirを必ず隔離フォルダへ指定する。元のユーザーデータ/実行ファイルは保持する。

## 検証入口

    .\Source\Psd\build-integrated.ps1 -Configuration Debug
    .\Source\Psd\build-integrated.ps1 -Configuration Debug -Project Source\Psd\Validation\IntegratedPsdValidation.dpr

出力はWin64/Validation/IntegratedPsd/{Debug,Release}に隔離する。IntegratedPsdValidationは実素材の複製だけに限定し、所有マーカーのあるGUI保存試験、形式別編集、作品の保存再読込、FullHDプレビュー一致、無音0.2秒/6フレームAVIを検証する。実音声との同期や物理マウス操作の検証とは区別する。新しい絵は今回生成していない。

## 最終検証と配置

Debug/Releaseビルドと統合各34項目、PSD GUIイベント/保存再読込9項目、PSD核心29項目が成功。実キャラ名とPSD制作元RIGMハッシュの一致も確認しました。PSD/RIGMのFullHDプレビュージョブは同時刻のRenderMovieFrameと画素一致し、無音0.2秒/6フレームAVIを出力しました。最終一覧は[PSD]/[RIGM]を先頭に表示します。初回のAVIサイズ検査を未圧縮相当からMJPEG向けに修正した後、両形式の出力に成功しました。

通常EXEを更新前/直前ともプロセス不在確認し、旧EXEをBackups/20261005-psd-integrationへ保全して原子的に置換しました。正式比較作品はD:\Users\take6\RIGMMaker\Scripts\PSD比較-20261005のPSD/RIGMフォルダに配置。各8秒、無音4区間、FullHD、実キャラの複製パッケージを含みます。SaveMovie/LoadMovieで再読込と素材検証、共通描画プレビューを確認しました。元入力74ファイルと登録PSDパッケージはハッシュ不変。

証拠はWin64/Validation/PsdStudioのintegration-checks-debug.json、integration-checks-release.json、integration-gui-release.json、core-after-integration.log、integration-deployment-result.json、formal-comparison-result.json、actual-character-catalog.json。試験EXE/DCU/複製10フォルダはRecovery/integration-20261005-031713へ移動し、recovery-index.jsonで元位置へ復元できます。旧EXEバックアップは移動対象外です。永久削除/強制終了はしていません。

依頼範囲の実装/配備に残る阻害要因はありません。実音声/LAB同期、実キャラ全身連番、追加生成済み素材の採用確認は未完。物理マウス/ファイルダイアログの実操作は確認していません。今回新規素材生成、長尺MP4、新規インストール、追加課金は行っていません。
