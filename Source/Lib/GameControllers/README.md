# GameControllers

MMDAnimationStudioで使われているSwitch Pro Controllerの処理をコピーし、MMD/PMXやフォームへの依存を外したライブラリ。元プロジェクトは変更していない。対応する機器はNintendo VID `$057E`、Pro Controller PID `$2009`。任意のゲームパッドを自動推測するドライバーではない。

## 構成

| ユニット | 役割 | コピー元 |
| --- | --- | --- |
| `GamepadState` | -1～1の左右スティック、12ボタン、POVの共通状態 | `MmdProControllerInput` の状態とボタン定義 |
| `SwitchProInput` | Windows HID検出、overlapped読取、1秒間隔の再探索、切断処理 | `Source/AI/Controller/MmdProControllerInput.pas` |
| `SwitchProReportDecoder` | `$21/$30/$31` の12bitスティック、`$3F` の16bit標準入力、デッドゾーン、短い押下の保持 | `Source/AI/Controller/Protocol/MmdProControllerReportDecoder.pas` |
| `SwitchProOutput` | フルモード・通常モード・プレイヤーLEDのサブコマンド構築/送信 | `Source/AI/Controller/Protocol/MmdProControllerOutput.pas` |
| `GamepadNavigation` | 押下エッジ、経過時間による速度補正、中立待ち | `MmdTimelinePoseControllerDriver` の入力処理 |

必要な外部機能はDelphi RTL、Winapi.Windows、Windows標準の `setupapi.dll`・`hid.dll`・`kernel32.dll`。VCL、PMX、AviUtl2、MMDのモデルやポーズ編集クラスには依存しない。検索パスにこのフォルダーを追加して利用する。

## 入力の使い方

```pascal
Input := TSwitchProInput.Create;
try
  // 33ms程度のタイマーで、対象画面がアクティブな間だけ呼ぶ。
  if Input.Poll(State) then
    ApplyPreview(State);
  // 非アクティブ化・ページ変更・操作OFF時には即時切断する。
  Input.Disconnect;
finally
  Input.Free;
end;
```

生成時にはデバイスを開かない。初回PollでHIDを検索し、適合したデバイスへ `$03/$30` のフルレポートモード要求と `$30/$01` のプレイヤー1 LED要求を送る。モード要求の書込みに成功した接続は、終了時に `$03/$3F` を送って通常モードへ戻す。これは既存MMD実装の一時的なデバイス操作で、ペアリングやドライバー設定を変更しない。

未接続時は1秒に1回再探索する。読取エラーではハンドルを閉じ、以後のPollで再接続する。250ms以上有効な報告が来なければ出力状態を中立にし、古いスティックや押下を継続しない。`Connected` はHIDハンドルの接続状態であり、レポート受信を保証しない。`ReportCount` で有効な入力報告の受信も確認できる。

`TSwitchProInput.Create(False, False)` と `EnumerateDevices` はモード・LEDを書き換えない診断用。テストの `--probe-readonly` もこの経路を使う。`ProbeConnection` は設定済みの動作でPollするので、既定インスタンスでは読み取り専用ではない。

Bluetooth/USBの独自ペアリング処理はない。Windowsが既に列挙するHIDインターフェースを開く。元ノートにはBluetoothで接続・切断・再接続を確認した記録がある。USB用の追加初期化ハンドシェイクは元コードに存在せず、今回も新設していない。したがってUSB接続の実動作は未保証で、実機確認が必要。

## 汎用化時の変更

- MMD接頭辞を除き、共通状態を別ユニットへ抽出。レポートパーサーは入力クラスに依存しない。
- MMDのDocumentsログ保存を除き、Debug時の出力は `OutputDebugString` へ変更。
- 短い/実バッファを超える入力を拒否。有効な形式を解析したときだけ最終受信時刻を更新する。
- MMDのPMX・履歴・ホスト呼出しを持たず、ナビゲーションは入力状態だけを処理する。対象変更・再接続時には左右両スティックの中立を待つ。
- RIGMへの割当は `Source/Integrations/RigmGamepadPreview.pas` に置く。別アプリへ再利用するときはこのRIGM側の割当を持ち込む必要はない。

## RIGMへの割当

ダイレクトプレビューで「Proコントローラーで操作する」を有効にする。操作OFF、他ページ、パラメータモード、画面非アクティブ、非表示、終了では入力を閉じる。マウスのドラッグ中はコントローラーによる変更を停止する。

| 操作 | 動作 |
| --- | --- |
| 十字キー上下 | 左スティックの対象を目→口→頭→体で選ぶ |
| 左スティック | 選択対象の視線/口の開き/顔角度/体角度を相対操作 |
| 右スティック左右 | 顔角度。Rを押しながらなら体角度 |
| L | 微調整（速度20%） |
| ZR / ZL | 瞬き / 口を開く。離す・切断で前の値へ戻す |
| A / B | 現在のプレビュー操作を確定 / 操作前へ戻す |
| Y | 選択対象を定義済み初期値へ戻す |

左/右スティックと表情ボタンを同時に操作できる。A/Bは画面を閉じず、RIGMの保存や工程完了を行わない。プレビューの値のみを変え、パーツ・ボーン・メッシュの永続データやrevisionを更新しない。

## 検証とコピー記録

旧 `Tests/RigmControllerTests.dpr` の35項目で、出力レポート、各入力形式、軸とボタン、短い押下、再接続時の中立待ち、RIGM同時操作、A/B/Y、範囲制限、切断時の一時表情復帰を検証した。検証プロジェクトは2026-10-05の整理で削除済みで、削除前のGit履歴に残る。

コピー元の絶対パスとSHA-256は `copy-record.json` に保存する。ローカルのコピー元をビルド参照しない。
