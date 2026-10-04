# アイコンツールバー

コピー元は `D:\DelphiProg\Syncroh2\Lib\ToolBarPanelManager\ToolBarPanelManager.pas` と `D:\DelphiProg\Syncroh2\Plugin_Extension\Serif\SerifToolbarIcons.pas`。コピー時のSHA-256は [provenance.json](provenance.json) に保存した。コピー元プロジェクトは変更しない。

`SerifToolbarIcons.pas` は無変更でコピーし、フォルダー・人物・目・鉛筆・比較枠の線画を再利用する。`RigmToolbarIcons.pas` は工程、保存、Undo/Redo、追加削除などのRIGM操作用の線画を追加する。外部PNGや追加DLLは不要。

`ToolBarPanelManager.pas` のローカルコピーには、既存ハンドラーと選択状態を保つ `Attach(Bar, False)`、終了時の `Detach`、区切りと無効画像の描画を追加した。従来のパネル連動機能は既定値 `True` で保持する。RIGMの工程判定・切替は編集コントローラーに任せ、管理クラスは共通描画に使用する。

`TRigmIconToolbar` は親の設定後にネイティブツールバーを初期化し、24pxのアイコンと40pxのボタンを現在DPIへ再生成する。通常・無効アイコン、選択・押下・ホバー色、名前付きツールチップ、Tabによるフォーカス、狭幅での折り返しを扱う。操作ボタンはフォーム更新ごとに作り直さず、ページに応じて表示・有効状態を更新する。

依存はDelphi RTL・VCL・Windows標準APIのみ。文書、PSD、HID、パイプへの依存はない。`RIGMMaker.dproj` の検索パスへこのフォルダーを追加する。

旧 `Tests/RigmToolbarTests.dpr` と `Tests/Run-Validation.ps1` で、実フォーム上のアイコンイベント、通常open→自動判定→工程進行、保存・Undo/Redo・並べ替え削除・ボーン復帰・頂点追加削除、無効/選択状態、96/144/192 DPI、狭幅のネイティブ矩形を検証した。物理マウス入力・複数モニター間のDPI移動とは区別して記録する。検証プロジェクトとスクリプトは2026-10-05の整理で削除済みで、削除前のGit履歴に残る。
