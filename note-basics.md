# RIGM Maker 基本事項

[開発ノート](note.md) ／ [対応課題](note-tasks.md) ／ [開発履歴](note-history.md)

## プロジェクト

- アプリ名はRIGM Maker、Delphiプロジェクト名・ファイル名はRIGMMaker。AviUtl2プラグイン版の名称はRIGMスタジオ。
- Delphi 37／VCL、Win64 Debug／Release、PerMonitorV2、Windows Modern Dark。
- 起動プロジェクトはRIGMMaker.dpr、現在のメインフォームはSource/Shell/RigmWizardMainForm.pas。
- キャラクターは.rigm、動画作品は.rigmovieとして管理する。形式と編集仕様は[RIGM仕様](RIGM仕様.md)と[編集仕様](RIGM_Maker_編集仕様.md)を参照する。

## 制作とデータ

Codexの指示とGUIの調整は共通のモデル・処理を使う。対象は固定IDで識別し、現在のprojectId・revision・要求IDを取得してから適用する。過去の要求・パーツID・接続情報を新しい作品へ再送しない。

題名画面で台本の種類を選び、scriptWizard.scriptTypeへ固定IDを保存する。現在の種類はアニメ批評（anime-review）と漫画紹介（manga-introduction）。未設定の旧台本は自動分類しない。追加方法とパイプは[種類選択・保存識別](Source/Shell/Pages/SCRIPT-TYPES-20261008.md)を参照する。

ユーザーの原稿、元画像・音声、過去版、未保存入力を保持する。実行中の通常アプリや通常EXEの扱いは、その作業でのユーザー指示と状態を確認する。過去の履歴にある許可・禁止を一律の現行指示として扱わない。

データルートはRigmAppSettingsの設定・起動引数に従う。通常はWindowsのドキュメント配下のRIGMMakerを使い、既存環境の旧ルートも保持する。新しい制作で過去のユーザー名・ドライブを推測しない。

シーン画像は生成元→Exchange→パイプ採用→作品の管理Imagesへの検証付きコピー→画像参照更新→行内再描画で受け渡す。生成・採用・人間の確定・作品保存は別の操作である。画像工程では人間の「確定」を必要とする。手順と上限は[画像受渡し](Source/Shell/Pages/IMAGE-WORKFLOW-20261007.md)を参照する。

生成時は明示された画像要望と関連セリフを読み、作品のジャンル・シリーズを優先する。続く場面は前画像を参照して場所・登場物・光・画風を継続する。推定した設定はユーザー確定と区別し、[学習記録](制作支援/学習記録/README.md)へ条件・プロンプト・参照画像・検証・評価を残す。

## 実装方針

- MainFormは画面の組み立てと機能間の接続を担当し、モデル・編集・保存・描画・指示実行・出力を責務ごとのユニットへ分ける。下位層からMainFormを参照しない。
- 1,000行や1フォルダ10ユニットは分割を検討する目安とする。詳細は[ソース構成](Source/README.md)を参照する。
- 再利用部品は[Lib索引](Source/Lib/INDEX.md)と対象の説明を確認し、必要なものだけコピーする。参考元のプロジェクトは変更しない。
- 日本語を含むPascalはUTF-8 BOM付き・CRLFで保存する。その他のファイルも既存の文字コード・改行規則を保持する。
- Win64 Debug／Releaseのビルドを確認し、警告・エラー0を完了条件とする。git diff --checkも確認し、実行した検証と未確認の範囲を記録する。
- 検証用EXE・DCU・画像・fixtureは同期対象外の専用出力へ置く。GUI描画の試験結果と、実作品・デスクトップでの確認を区別する。

## ビルド

RAD Studio 37の環境を読み込んだコマンドプロンプトで実行する。

```bat
msbuild RIGMMaker.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal
msbuild RIGMMaker.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal
```

通常の出力はプロジェクト直下のRIGMMaker.exe、中間生成物はWin64/DebugまたはWin64/Release。通常EXEが起動中の場合は、現在の作品を保存・終了してから反映する。独立検証ではEXEとDCUの出力先を分け、通常EXEを置換しない。

## 文書の置き場所

| 文書 | 役割 |
| --- | --- |
| [note.md](note.md) | 基本情報・未完了課題・リンクの短い入口 |
| [note-basics.md](note-basics.md) | 基本方針・開発条件・ビルド手順 |
| [note-tasks.md](note-tasks.md) | 対応課題・必要な確認・関連仕様 |
| [note-history.md](note-history.md) | 過去の作業・変更・検証・失敗・制約。末尾へ日付付き追記 |
| [制作支援](制作支援/README.md) | 制作手順と学習記録。元資料のnote.mdは参照資料として保持 |
