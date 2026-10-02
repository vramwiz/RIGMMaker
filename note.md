# RIGMMaker

RIGMMaker は、独自形式「RIGM」のキャラクターデータを使って動画を制作する Delphi VCL アプリケーション。
RIGM のキャラクターは、疑似2D画像・メッシュ・ボーンで構成する。
制作は主に Codex からの指示で進め、ユーザーは結果の確認、調整、動画の出力を行う。

## 制作方針

- Codex からの指示を、キャラクターの配置や動きなどを制作する主な操作方法とする。
- ユーザーが画面上で行う主な作業は、制作結果の確認と調整、最終的な動画の出力とする。
- RIGM データ、アニメーション、描画、指示の実行を UI から分離し、同じ制作処理を Codex からの指示とユーザーの調整に利用できる構成を目指す。
- RIGM の詳細なファイル仕様、指示の受け渡し方法、動画の出力形式は、今後の実装時に決める。

## 画面と RIGM データの管理方針

アプリ全体は、AviUtl2 風の UI に Syncroh2 拡張プラグインの表示を組み合わせたような構成を目指す。
RIGM キャラクターの編集画面は `D:\DelphiProg\test\AIArtToPSD\AIArtToPSD.dpr` のエディタを参考にし、元の PSD 入出力を RIGM 入出力へ置き換える。

- 左側には専用 GUI を置き、RIGM データをサムネイル付きで縦方向に一覧表示する。
- 初期状態では RIGM データが存在せず、一覧は空になる。
- ツールアイコンの追加操作で空の RIGM ファイルを作成し、同時にそのデータの編集画面を開く。
- 既存の RIGM データは、一覧のダブルクリックで同じ編集画面を開く。
- 管理場所はマイドキュメント配下の `RIGMMaker` フォルダーとし、その中に RIGM データ用のフォルダーを置く。子フォルダー名は `RIGM` を予定する。
- 実装時は Windows が返すドキュメントの場所を使い、ユーザー名やドライブを固定しない。

予定する管理場所:

```text
<マイドキュメント>\RIGMMaker\RIGM\
```

RIGM の詳細仕様が未提示のため、ファイルの内容・初期構造・読み書きはまだ定義しない。

## 現在の実装

`D:\DelphiProg\test\DelphiVclAppTemplate\DelphiVclAppTemplate.dpr` を開始点として、ビルドに必要なプロジェクト設定、メインフォーム、リソースをコピーした。
プロジェクト名、フォームのタイトル、アプリのタイトル、バージョン情報を `RIGMMaker` に変更し、プロジェクト GUID を新しく発行した。

現在はメインフォームだけの初期プロジェクト。RIGM の読み書き、キャラクターの描画、アニメーション、Codex からの指示を受け取る機構、動画出力は未実装。

AIArtToPSD の編集画面とその依存ソースを確認し、必要な 24 ファイルを `Source\Reference\AIArtToPSD` へ無変更でコピーした。
コピー内容と移植時の変更箇所は [エディタ移植準備](Source/Reference/AIArtToPSD/README.md) を参照する。
参考ソースはアプリに未接続。左側の RIGM 一覧、フォルダー・空ファイルの作成、RIGM エディタ起動も今後の実装とする。

## 基本条件

- Delphi 37 / VCL
- Win64 のみ、Debug / Release 構成
- PerMonitorV2 DPI 対応
- `Windows Modern Dark` VCL スタイル
- メインフォームは `Source\Shell\RIGMMakerMainForm.pas`

## 実装方針

- MainForm は画面の組み立てと機能間の接続を担当する。
- データモデル、編集、保存、描画、指示の実行、動画出力は、責務ごとに `Source` 配下のユニットへ分ける。
- 下位層から MainForm を参照しない。
- 必要になるまで空のフォルダーは作らない。
- 再利用部品が必要なときは、テンプレートの `Source\Lib\INDEX.md` と該当部品の説明を確認し、必要なものだけ本プロジェクトへコピーする。
- Pascal ソースに日本語を書く場合は UTF-8 BOM 付きで保存する。
- Debug / Release の Win64 ビルドを確認し、警告・エラーともに 0 を完了条件とする。
- Git 管理下では `git diff --check` も確認する。

## ビルド

RAD Studio 37 の環境を読み込んだコマンドプロンプトで実行する。

```bat
msbuild RIGMMaker.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal
msbuild RIGMMaker.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal
```

実行ファイルはプロジェクト直下の `RIGMMaker.exe`、DCU などの中間生成物は `Win64\Debug` または `Win64\Release` に出力する。

## 確認結果（2026-10-02）

- Delphi 37 で Win64 の Debug / Release ビルド成功。警告 0、エラー 0。
- 実行ファイルの製品名と説明が `RIGMMaker`、バージョンが `1.0.0.0` であることを確認。
- プロジェクトから参照するソースファイルの存在を確認。
- 画面の起動・操作確認は未実施。
- 現在は Git リポジトリではないため、`git diff --check` は対象外。
- AIArtToPSD からのコピー 24 ファイルの SHA-256 一致と、19 ユニットの依存関係が揃っていることを確認。参考ソースは未接続・コンパイル未確認。
