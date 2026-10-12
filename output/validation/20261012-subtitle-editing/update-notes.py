from pathlib import Path

root = Path(r'D:\DelphiProg\RIGMMaker')
def update(name, transform):
    p = root / name
    data = p.read_bytes()
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    text = transform(text)
    p.write_bytes((b'\xef\xbb\xbf' if data.startswith(b'\xef\xbb\xbf') else b'') + text.replace('\n', '\r\n').encode('utf-8'))

anchor = '字幕から音声へ進む場合は字幕入力を確認し、'
paragraph = '第12段階の字幕欄とメモ欄は、セリフを選んだ時点で直接編集できる。編集アイコン・一覧のEnter・ダブルクリックは字幕欄へフォーカスを移す補助操作とし、入力の前提にはしない。入力完了・保存・行切替・工程への再表示でも再び読み取り専用にしない。入力の変更で字幕確認を未完了へ戻し、無効な文字数などは入力を保持して保存・移動を拒否する。前工程の原稿・配役が古い場合は理由を表示して編集を止める。原稿・音声文・音声指紋・シーンは字幕の編集で変更しない。\n\n'
def navigation(text):
    assert text.count(anchor) == 1
    return text.replace(anchor, paragraph + anchor)
update('Source/Shell/Pages/SCRIPT-NAVIGATION-20261009.md', navigation)
update('note-basics.md', lambda text: text.rstrip() + '\n\n2026-10-12の第12段階の字幕編集修正は、起動中の通常アプリを保持して`D:\\DelphiProg\\RIGMMaker\\RIGMMaker-MP4.exe`へ反映した。字幕・メモは行選択後すぐに直接入力でき、入力完了後も編集できる。保存して通常アプリを終了し、別名EXEから起動する。検証と配置の記録は[開発履歴](note-history.md)を参照する。\n')
history = '''
## 2026-10-12 第12段階の字幕・メモを直接編集可能に修正

ユーザーから「字幕編集なのに字幕が編集できない」と報告。RigmScriptSubtitleFrameが字幕欄・メモ欄を読み取り専用で開き、編集アイコンかEnterの操作だけで解除するため、行選択・入力完了・保存後に再び入力できなくなっていた。実アプリはPID 6936で制作を継続しており、読み取り時点では同じ「男子校のくらげ先生」の音声生成中だった。実作品の工程・入力・生成処理は変更していない。

現在の配役と字幕の前提が有効なら、選択直後から字幕・メモを直接編集できるよう変更。キー・マウス・貼り付けによる変更を共通モデルへ反映し、入力完了・保存後も編集可能にする。編集アイコンとEnterは入力欄へのフォーカス移動として維持し、一覧のダブルクリックも同じ処理へ接続した。旧い配役では理由を表示して欄を読み取り専用にする。正規化した文が同じならMemo.Textを設定し直さず、選択範囲・カーソル・Undoを保持する。原稿・音声・シーンのモデルと保存形式は変更していない。

所有fixtureの実VCL画面へネイティブWM_CHAR・複数行の日本語貼り付けを送り、修正前に「第12段階を開いた直後から字幕とメモへ入力できる」の項目が失敗することを確認した。修正後の全工程477項目は成功。今回追加した19項目で、直接入力・貼り付け・Undo、10回の同一状態通知での選択保持、メモ、別行の編集、完了後の再編集と確認解除、保存前の入力検証、無効なメモの保持、古い配役での編集禁止と復帰、前工程からの再表示、原稿・音声指紋・シーンの保持を確認。所有fixtureの字幕画面も画像で目視確認した。物理キーボードの実IME操作は未実施。

正規dprojと同じ検索パスを使う隔離Win64 Debug/Releaseは成功。各エラー0・既存W警告13・Hヒント55、字幕画面の追加警告0。検証済みReleaseのSHA256は8EEF5373A690366051102842391EAD944763050CDCA3798697EAB9135AFD9C9A。停止中・開始時SHA一致を確認したRIGMMaker-MP4.exeへ配置し、旧別名EXEを退避した。PID 6936が使用する通常EXEは保持し、SHA256 ABC31BCF16204FE7D54D917E6C0EE6359B6B30AE3669F48CD1D53F6485861F9Eのまま。修正版を使うには制作を保存して通常アプリを終了し、別名EXEから起動する。

仕様はSource/Shell/Pages/SCRIPT-NAVIGATION-20261009.md。修正前ソース、再現結果、477項目と画面、Debug/Releaseログ・EXE、旧別名EXE、配置記録はoutput/validation/20261012-subtitle-editing。実作品や音声・画像の生成、動画出力は行っていない。
'''
update('note-history.md', lambda text: text.rstrip() + '\n\n' + history.strip() + '\n')
