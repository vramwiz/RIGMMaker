// GUIの選択肢を保存形式の識別子へ対応付ける。表示名と保存値の順序を固定する。
unit RigmMovieUiValues;
interface
const
  OutputPresetIds: array[0..3] of string = ('draft','hd','fullhd','custom'); // 寸法プリセットの選択順。独自寸法はcustom。
  EncodeProfileIds: array[0..2] of string = ('fast','balanced','quality'); // 圧縮速度と画質の選択順。
  FeatureModeIds: array[0..2] of string = ('auto','assets','deform'); // 口パク・瞬きで既存素材と変形の使用方法を選ぶ。
  ImageAttentionModes: array[0..2] of string = ('auto','off','head'); // 場面画像への注視を自動・無効・頭部で選ぶ。
  MovieActingKeys: array[0..11] of string = ('mouthGain','lipLead','blinkStrength','blinkInterval','blinkDuration','blinkPhase','headGain','bodyGain','onset','duration','fadeIn','fadeOut'); // 演技入力欄とJSONへ保存するキーの対応順。
  MovieActingLabels: array[0..11] of string = ('口パク強度 0～2','口パク先行 ±0.3秒','瞬き強度 0～1','瞬き間隔 0.3～30秒','瞬き時間 0.04～1秒','瞬き位相 0～30秒','頭の動き 0～3','上半身の動き 0～3','演技開始（秒）','演技時間（-1=終端）','フェードイン（秒）','フェードアウト（秒）'); // MovieActingKeysに対応する表示名と単位・有効範囲。


implementation
end.
