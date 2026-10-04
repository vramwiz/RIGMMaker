// キャラクター編集のツールバー・属性ボタンが共有するTag操作番号。既存の番号対応を保持する。
unit RigmEditorActions;
interface
const
  acSave          =  1; // 現在の保存先へ明示保存。
  acSaveAs        =  2; // 別の保存先へ明示保存。
  acUndo          =  3; // 編集履歴を一段戻す。
  acRedo          =  4; // 戻した編集を再適用。
  acPng           =  5; // PNGパーツの取込。
  acPsd           =  6; // 分解済みPSDの取込。
  acGroup         =  7; // レイヤーグループ追加。
  acComplete      =  8; // 工程を検証して次へ進む。
  acMode          =  9; // 編集とパラメータプレビューの切替。
  acAddBone       = 10; // 親を指定したボーン追加。
  acHideBone      = 11; // 子を含むボーンの非表示。
  acRestoreBone   = 12; // 既存の子ボーンを復活。
  acResetBone     = 13; // ボーンを初期位置へ戻す。
  acGenerate      = 14; // 不足メッシュの生成。
  acAddVertex     = 15; // 選択メッシュの頂点追加。
  acDeleteVertex  = 16; // 選択頂点の削除。
  acResetPose     = 17; // 未保存姿勢の初期化。
  acBones         = 18; // ボーンオーバーレイの切替。
  acMeshes        = 19; // メッシュオーバーレイの切替。
  acDirect        = 20; // プレビューの直接操作切替。
  acLayerUp       = 21; // レイヤーの表示順を上へ移動。
  acLayerDown     = 22; // レイヤーの表示順を下へ移動。
  acDeleteLayer   = 23; // 選択レイヤーの削除。
  acReference     = 24; // 比較用元画像の表示切替。
  acTriangles     = 25; // 選択メッシュの面を再構成。
  acReplace       = 27; // 選択パーツのPNG差替え。
  acClassify      = 28; // 未分類レイヤーの再判定。
  acMovie         = 29; // キャラクターから動画制作を開く。
implementation
end.
