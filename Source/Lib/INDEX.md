# 再利用ライブラリ

| モジュール | 用途 | 依存 |
| --- | --- | --- |
| [GameControllers](GameControllers/README.md) | Switch Pro Controller HID入力、出力プロトコル、共通入力状態・ナビゲーション | Delphi RTL、Winapi.Windows、Windows標準DLL。VCL/MMD/RIGM依存なし |
| [IconToolbar](UI/IconToolbar/README.md) | Syncroh2由来のツールバー描画と線画アイコン、無効/選択状態、ツールチップ、DPIと折り返し | Delphi RTL、VCL、Windows標準API |
| [Voicevox](Voicevox/README.md) | Syncroh2由来のローカル音声合成API・話者一覧・音素LAB・音声設定 | Delphi RTL HTTP/JSON、Windows、ローカルVOICEVOX Engine |
