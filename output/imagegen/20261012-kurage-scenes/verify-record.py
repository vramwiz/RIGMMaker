import hashlib, json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

job = Path(__file__).parent
root = job.parents[2]
def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

m = read(job/'prompts.json')
before = read(job/'project-saved-before.rigmovie')
after = read(job/'project-saved-after.rigmovie')
status = read(job/'status-final.json')
page = read(job/'scenes-final-page.json')
delivered = [read(p) for p in sorted(job.glob('delivery-*.json'))]
images = []
for a in m['assets']:
    p = job/a['filename']
    if not p.exists():
        continue
    with Image.open(p) as im:
        im.load()
        info = dict(key=a['key'], path=str(p), width=im.width, height=im.height,
                    format=im.format, mode=im.mode, bytes=p.stat().st_size,
                    alphaExtrema=im.getchannel('A').getextrema() if 'A' in im.getbands() else None,
                    sha256=sha(p))
    if not (info['format']=='PNG' and info['bytes'] < 32*1024*1024 and info['width']*info['height']<=16_000_000):
        raise RuntimeError('Unexpected image format or dimensions: '+str(p))
    d = next((d for d in delivered if d['key']==a['key']), None)
    info['applicationImported'] = d is not None
    if d:
        info['importedHashesMatch'] = info['sha256']==d['sha256']==sha(d['exchangePath'])==sha(d['managedPath'])
        if not info['importedHashesMatch']:
            raise RuntimeError('Delivery hash mismatch')
    images.append(info)

before_chart=next(s['chart'] for s in before['scenes'] if s['id']=='{C5F3B8EF-F7F0-4DE6-ABC4-B2754176550F}')
after_chart=next(s['chart'] for s in after['scenes'] if s['id']=='{C5F3B8EF-F7F0-4DE6-ABC4-B2754176550F}')
verification = dict(checkedAt=datetime.now(timezone.utc).isoformat(), projectId=m['projectId'],
    revision=status['revision'], savedProjectPath=status['path'], projectModified=status['modified'],
    generatedImages=len(images), importedImages=len(delivered), activeSceneImages=10,
    cueCount=len(after['cues']), allCuesAndAudioFieldsUnchanged=before['cues']==after['cues'],
    sceneIdsAndOrderUnchanged=[s['id'] for s in before['scenes']]==[s['id'] for s in after['scenes']],
    summaryChartUnchanged=before_chart==after_chart,
    layoutUnchanged=before.get('layout')==after.get('layout'),
    characterPlacementUnchanged=before.get('characters')==after.get('characters'),
    pendingRequests=page['pendingRequests'], thumbnailSourcesReady=page['thumbnailSourcesReady'],
    images=images, humanApproval='部分確定済み。未確定行はユーザーの確認待ち', reopen='not_run')
write(job/'verification.json', verification)

learn = root/'制作支援'/'学習記録'/'RIGM'/'20261012-kurage-scenes'
learn.mkdir(parents=True, exist_ok=True)
write(learn/'prompts.json', m)
record = dict(schemaVersion=1, recordType='rigm_scene_image_creation_learning', date='2026-10-12',
    purpose='男子校のくらげ先生：全台本を先読みし人物を統一したシーン画像を生成・送信',
    userInstruction='シーンの画像まで進めたので 画像を生成しておくって', projectId=m['projectId'],
    method='built-in image_gen.imagegen。1画像1呼出し、計14枚。人物の基準画像を参照して生成。現行未確定要求を照合し、Exchange経由のmetadata送信・各画像採用後に保存。',
    sourceImages=[
      dict(path=str(job/'references'/'official-cover.jpg'), sourceUrl='https://www.akitashoten.co.jp/comics/4253018041/cover', role='くらげ先生の色・髪・瞳の公式参照'),
      dict(path=str(job/'references'/'official-character-panel.jpg'), sourcePage='https://creatorslab.kodansha.co.jp/topics/5040/', role='先生の服装・髪の公式参照'),
      dict(path=str(job/'references'/'official-story-page.jpg'), sourcePage='https://creatorslab.kodansha.co.jp/topics/5040/', role='男子生徒の髪型・制服の公式参照'),
      dict(path='D:\\Manga\\基本テンプレート\\東北きりたん\\東北きりたん_草履あり.png', role='ユーザー指定のきりたん原画。色とデザイン保持、ポーズのみ変更')],
    imageSpecificConditions=[
      '開始時の全要望欄は空欄。全14シーン・全セリフを先読みして構図を準備した。',
      '生成中にユーザーが短い要望・シーン名・表示方法を入力し確定を操作。最新内容を再読込し、以後のUI要望を上書きせず、変更された未確定8件へ新しい要求を作成。',
      '増える妄想は最新の要望に合わせ授業中の構図に変更した。',
      'くらげ先生は黒いボブ・紫の毛先・緑の瞳・灰色カーディガン・白衣。主人公は短い黒髪・白い半袖制服・紺のズボンで統一。',
      '冒頭の画像は採用後にユーザーが非表示で確定。作品名は文字のみ、最後にも画像なしへ変更されたため、生成した作品名・締め画像は未送信の候補としてワークスペースへ保持。',
      '総評は既存の5項目レーダーチャートを保持。',
      '最後のサムネイルは全行の人間確定後に作る仕様。現時点では未要求・未生成・未採用。'],
    preservedInformation=['全セリフ・字幕・音声フィールド','14シーンのIDと順序','総評の5項目と点数','人間が選んだ要望・表示方式・確定状態','キャラクター配置'],
    verification=verification, artifacts=dict(finalImages=images, prompt=str(job/'prompts.json'), deliveries=delivered,
      verification=str(job/'verification.json'), sourceSnapshot=str(job/'project-saved-before.rigmovie')),
    reusableRules=['最新の全要望を読み、途中の人間の編集を検出して尊重する。','人物の基準画像を以降の生成へ参照する。','きりたんは原画色を保ち、場面に合う動きと表情を付ける。','大きな作品ロゴは濃色図形を背面に置いて読みやすくする。'],
    unverified=['未確定行の人間の見た目評価','保存終了後の再開','最後のサムネイル'])
write(learn/'learning_record.json', record)
summary = '''# 男子校のくらげ先生のシーン画像

内蔵 imagegen で14枚を生成。現在使用する10シーンと共通背景を送信・保存しました。冒頭も送信後にユーザーが画像なしへ変更して確定しています。作品名画像と締め画像は現在の表示設定に合わせて未送信の候補として保存しました。

人物は公式参照と生成した基準画像で統一。きりたんは指定原画の色を保ち、紹介・手振りの動きを付けています。総評のレーダーチャート、全セリフ・字幕・音声・配置を保持しました。

全行の「確定」後、最後のサムネイルを生成・送信します。

- [生成指示](prompts.json)
- [検証結果](verification.json)
- [学習記録](../../../制作支援/学習記録/RIGM/20261012-kurage-scenes/learning_record.json)
'''
summary += '\n## 保存した画像\n\n| 画像 | 保存先 | 送信 |\n| --- | --- | --- |\n'
for im in images:
    filename=Path(im['path']).name
    summary += f"| {im['key']} | [{filename}]({filename}) | {'済み' if im['applicationImported'] else '現在の表示設定により候補として保管'} |\n"
(job/'README.md').write_text(summary,encoding='utf-8')
print(json.dumps({k:v for k,v in verification.items() if k!='images'},ensure_ascii=False,indent=2))
