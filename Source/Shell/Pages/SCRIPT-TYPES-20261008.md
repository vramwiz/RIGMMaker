# 台本の種類と保存識別

題名画面の「台本の種類」コンボボックスから選ぶ。選択はGUIとパイプで共通の台本データへ反映し、通常の保存・Next・終了時保存で作品ファイルに残す。題名やファイル名に種類名を埋め込まず、固定IDで識別する。

| 表示名 | 保存するID |
| --- | --- |
| アニメ批評 | `anime-review` |
| 漫画紹介 | `manga-introduction` |

保存先は`.rigmovie`内の`scriptWizard.scriptType`。文字列の表示名やコンボボックスの番号は保存しない。

```json
{
  "scriptWizard": {
    "format": "RIGMMaker.ScriptWizard",
    "schemaVersion": 1,
    "titleInput": "作品の紹介",
    "scriptType": "manga-introduction"
  }
}
```

新規台本も旧台本も、選択するまでは未設定。旧ファイルにフィールドがなくても読み込みを拒否せず、作品名やセリフから種類を推測して付けない。種類の選択を新しいNextの必須条件にはしていない。分類のみの変更で原稿・配役・音声・画像・工程の完了状態を変更しない。

## パイプ

- `app-script-status`は`scriptType`、`scriptTypeName`、`scriptTypes`（IDと表示名の一覧）を返す。
- `app-script-list`の各作品にも`scriptType`と`scriptTypeName`を返す。既存の`kind: wizard|legacy|unreadable`は作品形式の識別なので変更しない。
- `app-schema`の`workspace`から`script-set-type`と`scriptTypes`を取得できる。
- `app-script-set-type`へ現在の`projectId`、`revision`、`scriptType`を渡す。既存の入力編集中・古いrevision・別作品の拒否を共用する。

```json
{
  "command": "app-script-set-type",
  "args": {
    "projectId": "現在の作品ID",
    "revision": 123,
    "scriptType": "anime-review"
  }
}
```

選択可能なID以外や非文字列は拒否する。空文字は未設定へ戻す。同じIDの再指定は変更せず、revisionも増やさない。変更はアプリ内の未保存状態で、保存は`app-script-save`またはGUIの通常保存を使う。

## 将来の追加

[RigmScriptTypes.pas](../../Studio/Model/RigmScriptTypes.pas)の固定IDと表示名の一覧へ追加する。GUI・状態・パイプの候補一覧は同じ定義から生成する。既存IDは変更・再利用しない。

保存済みの未知の種類は、64文字以内の小文字英数字・単独ハイフン（先頭は英字、末尾はハイフン不可）なら保持する。旧版の題名画面では「未対応の種類（ID）」として表示し、題名だけの編集・保存で別の種類へ置換しない。これは種類の分類であり、画像の画風・ジャンル・シリーズ設定や、校正の作品情報UIを追加したものではない。

## 検証

Win64 Debug／Releaseは専用出力でビルド成功。`Source/Psd/Validation/ScriptTypeCheck.dpr`による29項目と実パイプ6通信を確認した。両種類のGUI選択、保存と独立読込、別Workspaceでの再開、旧台本・将来IDの保持、不正値・古いrevisionの拒否、一覧の識別、96／144／192 DPIの配置を含む。隔離フレームの描画も確認した。実ユーザー作品は今回分類していない。出力先・既存警告・保護対象の照合は[開発履歴](../../../note-history.md)へ記録する。
