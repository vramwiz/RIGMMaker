# 同梱FFmpeg MP4出力

`RigmFFmpegApi`がEXE隣の`Runtime/FFmpeg`からWin64 DLLを絶対パスでロードし、`RigmFFmpegWriter`がBGRAのVCL Bitmapと48000 Hz mono PCM16からH.264/AAC MP4を逐次作成する。UI・作品・VOICEVOXには依存しない。入力は借用し、FFmpegリソースと新規出力はwriterが所有する。作成・呼出・破棄は同一スレッドで行う。

`D:\DelphiProg\VM_Media_Output`のFFmpeg API・出力実装を参考にした。ABI定義は同梱8.1.1のソースcommit `239f2c733d`の公式ヘッダーと対応させる。部分recordをDelphi側で確保したり、異なるmajorのDLLと混在させたりしない。Cライブラリに合わせて浮動小数点例外を一時マスクし、破棄・ロード失敗時に呼出スレッドの元の設定へ戻す。

必要DLLはavutil-60、swresample-6、swscale-9、avcodec-62、avformat-62の5個。復元は`Setup/Prepare-FFmpegRuntime.ps1`、通常のWin64ビルドではdprojの`DeployFFmpegRuntime`がEXE出力先へDLL・ライセンス・manifestを配置する。DLLバイナリはGit対象外なので新規チェックアウト後に復元する。

3品質設定（fast/balanced/quality）、AAC端数、負のBitmap stride、最終映像packetのdurationを扱う。完成前に破棄したwriterは自身が新規作成したファイルだけを削除し、既存の同名ファイルは拒否する。`Finish`はcodecの残りを排出しMP4 trailerとfaststartを書いてからI/Oを閉じる。

実出力・全フレーム復号・非同期取消・DLL不足の検証は`Source/Psd/Validation/Run-BundledMp4Check.ps1 -OutDir <新規の隔離フォルダー>`で実行する。出力統合の詳細は[MP4実装記録](../../Studio/Output/MP4-RUNTIME-20261010.md)を参照。
