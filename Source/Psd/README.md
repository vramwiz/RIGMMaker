# PSD立ち絵編集と共通動画

操作手順、実際の登録名/件数、比較作品は[OPERATIONS.md](OPERATIONS.md)。統合の実装/検証/配置は[INTEGRATION.md](INTEGRATION.md)を参照。

通常は D:\DelphiProg\MyApp\RIGMMaker\RIGMMaker.exe を起動します。共通一覧から形式別の編集画面を開き、PSDも共通動画制作で使えます。PsdStudio.exe/PsdStudio.dprは補助の独立入口として保持しています。

既定データルートは D:\Users\take6\RIGMMaker。通常アプリは --data-root、独立入口は --root で検証ルートへ切り替えます。通常アプリのPSDセッション/描画も同ルートの専用Tempを使い、完了済み所有ジョブを保守的に回収します。旧登録や既存作品は削除しません。

## 使い始める

独立入口では起動時にCharacters内のキャラを開きます。通常アプリは共通ライブラリからPSD行をダブルクリックします。「キャラを開く」で Characters\blonde-android-20261005.psdchar を選べます。右側で表情、視線、正面/非正面、小さな動き、瞬き、手動口形を選びます。左ツリーの差分をダブルクリックすると初期の部位選択を変更します。PNG追加、全身ポーズ/連番の追加、保存、PSD/FullHD PNG出力、音素LAB読込を独立画面から使えます。

通常は .psdchar を開きます。PSD・設定・全身連番を内包する1キャラ1ファイルです。.psd はレイヤー画像の書き出し用で、表情/音素/連番の設定は .psdchar に入ります。既存 .rigm と別の拡張子・識別子を使います。

## ビルド

このPCのDelphi 37.0 Win64コンパイラを使います。

    .\Source\Psd\build.ps1 -Configuration Debug
    .\Source\Psd\build.ps1 -Configuration Release
    .\Source\Psd\build.ps1 -Configuration Debug -Project Source\Psd\Validation\PsdValidation.dpr
    .\Win64\Validation\PsdStudio\Debug\PsdValidation.exe

出力は Win64/Validation/PsdStudio/{Debug,Release} へ隔離します。通常配置のEXEへ自動上書きはしません。新規Pascal/DPRはUTF-8 BOM・CRLFです。Referenceの2ユニットはコピー元のバイトを保ちます。

## 登録済みキャラと制作履歴

Work/金髪アンドロイド-20261005/manifest.json から、1152×2048のキャンバス、分離済みPNG51枚、比較用原画1枚、8部位グループ、表情6組、瞬き/音素ID、制作履歴を登録しました。配置・サイズ・alpha・手前順・部位IDを保持しています。元のRIGM/PNG/PSDは加工していません。

登録先は Characters/blonde-android-20261005.psdchar。追加後のPSDは Characters/blonde-android-20261005-v2.psd（59画像・10グループ）。初回登録の同名 .psd と blonde-android-20261005-neutral.png は保全しています。原画は非表示の比較用レイヤーです。

元の通常・喜び・怒り・驚き・疑問・困惑に、既存の口/眉/体だけで「哀しみ」「解説」を加えました。この2組は新規描画ではありません。元プリセットの blinkAnimate/mouthAnimate を守ります。

別途、内蔵画像生成で画面基準の視線5方向の両目一組、横向き/後ろ向きの全身2ポーズを新規描画して登録しました。単純な原画切り出しと区別し、assetHistory に newDrawing、原生成/受信PNGのSHA-256、制作方法、pending-user-review を残しています。透過余白を測り、X/Y共通倍率で整えました。白色の透過化や元51パーツの加工はしていません。

生成原本、登録用PNG、配置計測、FullHD確認画像は Work/PsdGenerated-20261005 へ制作履歴として永続保存しています。このWorkは一時整理対象外です。新規ポーズには輪郭の色にじみがあり、造形や視線の強さも採用確認が必要です。ユーザー確認済みとは記録しません。新規ソフトや有料APIの追加契約・呼び出しはしていません。

## パッケージと保存

.psdchar はZIPで manifest.json、character.psd、motions/<id>/<frame>.png を内包します。既存 .rigm もZIPを使うため、同じ標準ライブラリで依存ソフトを増やさず実現できます。manifestは format=RIGMMaker.PsdCharacter, version=1。PSDの階層・名前を照合してmanifestの安定IDを復元します。

ZIPは展開前に名前・階層・重複・サイズを検証し、必要なPSD/PNGだけを固定された所有ジョブへ書きます。表示はパッケージ内だけで完結し、履歴に書かれた外部PNGには依存しません。保存候補を再読込してから置換し、同じキャラIDだけを更新します。旧版は所有ジョブへ保全します。未編集saveは再書込しません。PSD書き出しは新規ファイル名のみです。

## 合成と動き

PSDルート近くの「*正面」と「*非正面・全身ポーズと連番」を排他的に使います。正面は初期選択→表情→視線→瞬き→音素口形の順で合成します。視線は画面基準の front,left,left-up,up,right-up,right で、左→上→右の時計回りです。正面は元の目を保持し、追加5方向を選べます。未登録方向を別の絵で代用しません。

瞬きは約4秒ごとの260ms（半開80ms、閉100ms、半開80ms）。瞬き後は選択中の目へ戻ります。口形は a/i/u/e/o/N/closed。LABは100ns単位、JSONは秒単位で [{"start":0,"end":0.03,"phoneme":"a"}]。半開区間を二分探索し、区間外/未知の子音はclosedです。音素指定がなければ表情の口を保ちます。

その後、合成画像全体へ呼吸/揺れ/ジャンプを適用します。SYNC_Motionの CalculateRhythmTransform と腰/首/頭の重みを使います。補間はalphaを重みにして色漏れを抑えます。目パチ・口パクと同時に動かせます。画面プレビューは960×540、PNG出力は1920×1080です。

非正面ポーズ/全身連番中は正面の顔・髪・体を残しません。瞬き/口パク/視線は無効で、横向き専用の顔制御はありません。連番はfps/loopを保持し、非ループは最終フレームを保持します。切替補間は行いません。GUI追加はゼロ埋めファイル名順、24fps、ループが初期値です。パイプから1〜120fps/loopを指定できます。

## ファイル受信と編集制限

大きなPNGはデータルート内に置き、パイプへ path と sha256 を渡します。root外、同じprefixの別フォルダ、UNC/デバイス、ADS、..、曖昧な名前、予約名、reparse pointを拒否します。読み取りをロックして所有ジョブへコピーし、SHA-256とPNG形式・寸法・デコードを検証後に反映します。

この入口は分離済みの透過部位を受信します。矩形切り出しを意味的分離と扱いません。1枚絵の肌補完/新規差分はSyncroh2の制作手順で別途生成・分離・alpha検証して受信します。

外部PSDは editPolicy=external を保ち、画像追加/加工/構造/表情変更を拒否します。保存先を管理フォルダへ移しても編集権限は変わりません。PSD書き出しは原アーカイブをバイト保存します。外部PSDの名前編集UIは未実装です。

## PSD専用パイプと共通入口

独立起動中の接続情報は Exchange/psd-<pid>-<sessionId>.json。schemaVersion 1/requestId/command/args/ok/dataの既存プロトコルを再利用し、status/document以外には現在の sessionId と文字列 revision を指定します。GUIとパイプは同じ TPsdSession.Command を呼びます。編集はコピー/検証後に反映し、失敗時に元状態を保ちます。

| command | 主なargs |
| --- | --- |
| status / document | ID・編集権限・設定・保存先の取得 |
| open / import-prepared / import-psd | path |
| save / export-psd | path（saveは省略可） |
| add-layer-file | groupId,name,path,sha256,x,y、任意gaze |
| select-part | groupId,partId |
| set-expression | name,preset:{variants:[{groupId,partId}],blinkAnimate,mouthAnimate} |
| add-nonfront-file | kind=pose,name,path,sha256,x,y |
| add-nonfront-file | kind=sequence,name,fps,loop,x,y,frames:[{path,sha256},...] |
| set-view | expression,gaze,phoneme,hasPhoneme,nonFrontId,motion,autoBlink,strength |
| load-lab / set-phonemes | path、またはevents配列 |
| render-file | 新規PNG path,seconds（FullHD） |

部位/pose受信は任意の productionMethod,newDrawing,visualState,rawSourcePath,rawSourceSha256 も保持します。原本パスもroot内で検証します。履歴は参照用で、表示時に外部PNGは必要ありません。空のnonFrontIdは正面へ戻ります。未保存変更の破棄は明示的 discardChanges=true のみです。

1命令はUTF-8 60KB以内、受信PNG128MB以内、画像1600万画素以内、ZIP展開合計512MB以内、連番PNG合計256MB以内、連番2000枚以内です。

共通パイプのapp-library/app-edit-character/app-register-characterが一覧と編集/登録を扱います。開いたPSD画面は専用パイプとGUIで同じSessionを使います。共通動画のactorはrenderFormat/psdViewを保存し、作品時刻のTPsdRenderer.Frameへ委譲します。台本、字幕、音声、時刻、出力ジョブは既存の共通系統です。

## 永続データと安全な一時整理

Charactersはキャラ、Scriptsは台本/音素情報、Exchangeは大容量ファイル受渡し先です。元Work/RIGM/入力PSD/原画は回収しません。一時画像は Temp/PsdJobs/<GUID>。所有印 RIGMMaker.PsdJobs.v1、jobId、status、finishedUtcを記録し、活動中の排他leaseは Temp/PsdLeases/<GUID>.lock に置きます。

起動時は所有印・GUID・completed/expired・30日経過・非活動・リンクなしの全条件を確認し、Temp/PsdRecovery/<GUID>-日時へ移動します。永久削除/ごみ箱消去はしません。Recoveryからコピーして復元できます。異常終了のactive、破損印、無関係ファイル、不明なleaseを保全します。終了済み接続情報も所有ジョブへ移します。

## 未完事項と検証

全身連番の枠・ループ・顔除外は合成試験用2フレームで検証しました。実キャラの全身連番は未配置です。動作を選び、同じキャンバス/配置/解像度で頭から足まで含む透過PNG連番が必要です。静止2ポーズ、小さな連続変形、全身連番は別の素材/機構です。

アプリ内のAI生成直接接続、自動肌補完、外部PSD名編集は未実装です。台本/タイムライン/音声制作は共通画面を使えますが、実音声/LABは未配置で、PSDの実録音との同期を確認済みとはしません。長尺MP4は今回出力していません。

詳細は VALIDATION.md。この環境の内部画面キャプチャは標準Windows部品の文字/枠を収録できません。モデル、パイプ、実キャラ描画、部品のハンドル/可視性/配置は確認しています。マウスによる全GUI動作と標準部品の実画面は未確認です。

追加仕上げで、GUIの実部品/既存イベントによる開く→表情/視線/非正面選択→保存→再読込→新Sessionの限定回帰9項目がDebug/Releaseとも成功しました。Source/Psd/Validation/Invoke-GuiFlow.ps1で、実キャラを検証ルートへコピーして再実行できます。ファイル選択ダイアログや物理マウスの自動操作はしていません。画像のWindows保存経路と未採用の輪郭清掃候補は IMAGE_TRANSFER.md に記録しました。

## 参照元

PSD/PNG/合成/変換は既存 Source/Reference/AIArtToPSD、通信workerは Source/Integrations/RigmPipe.pas をコピー再利用しています。最新の制作制限と交換経路はSyncroh2の Doc/PSDArtEditor/README.md、LearningData/PSD制作手順.md、パイプ操作手順.md、AI画像交換仕様.md、通信仕様.mdを確認しました。共通PSDArtEditorライブラリは実在します。今回の状態・動き基準と接続上の未完事項はPRODUCTION.mdに記載しています。参照元は変更していません。

SYNC_Motionの2ユニットはReferenceへ無変更でコピーしました。コピー元パスとSHA-256は同フォルダの provenance.json にあります。
