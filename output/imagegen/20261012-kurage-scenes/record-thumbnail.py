import json, hashlib
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

job=Path(__file__).parent
root=job.parents[2]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prepared=read(job/'thumbnail-prepared.json')
prompt=read(job/'thumbnail-prompt.json')
with Image.open(prepared['workspacePath']) as im:
    im.load()
    dimensions={'width':im.width,'height':im.height,'format':im.format,'mode':im.mode}
assert hashlib.sha256(Path(prepared['workspacePath']).read_bytes()).hexdigest()==prepared['sha256']
assert hashlib.sha256(Path(prepared['exchangePath']).read_bytes()).hexdigest()==prepared['sha256']
record={
 'schemaVersion':1,'recordType':'rigm_thumbnail_creation_learning','date':'2026-10-12',
 'checkedAt':datetime.now(timezone.utc).isoformat(),
 'userInstruction':'最後の タイトルロゴ付きサムネイル画像が無い',
 'projectId':prepared['projectId'],'revision':prepared['revision'],
 'method':'built-in image_gen.imagegen。既存の先生・男子生徒・作品ロゴと指定のきりたん原画を参照し、最後のサムネイル画像を1枚生成。',
 'prompt':prompt,
 'artifacts':prepared,
 'verification':{**dimensions,'workspaceAndExchangeHashesMatch':True,
    'visualReview':'漫画・男子校のくらげ先生の文字を確認。濃紺ロゴ背面、原画に合うきりたんの色、指さしポーズ、既存人物の外見を確認。',
    'sourcesReady':prepared['sourcesReady'],'applicationImport':'not_done_pending_human_scene_approval',
    'humanThumbnailReview':'not_reviewed'},
 'workflowNote':'前回、全行の確定待ちでサムネイル画像自体を未作成にしていた。今回の明示指示で画像を先に完成させ、チャットへ提示。全行確定前のアプリ取り込みは行わず、承認状態の代行や作品JSONの直接変更もしない。',
 'unverified':['アプリへの取り込み・プレビュー','ユーザーの見た目評価','サムネイルの確定・保存再開']}
learn=root/'制作支援'/'学習記録'/'RIGM'/'20261012-kurage-scenes'
write(learn/'thumbnail_learning_record.json',record)
write(job/'thumbnail-verification.json',record['verification'])
parent=read(learn/'learning_record.json')
parent['followUps']=[{'record':str(learn/'thumbnail_learning_record.json'),
 'status':'タイトルロゴ付きサムネイル生成・提示済み。アプリへの送信は全行の人間確定待ち。'}]
write(learn/'learning_record.json',parent)
readme=job/'README.md'
content=readme.read_text(encoding='utf-8')
content=content.replace('全行の「確定」後、最後のサムネイルを生成・送信します。','最後のタイトルロゴ付きサムネイルも生成済みです。全行の「確定」後にアプリへ送信します。')
if '## タイトルロゴ付きサムネイル' not in content:
 content+='\n## タイトルロゴ付きサムネイル\n\n[完成画像](thumbnail-logo.png)／[生成指示（内蔵imagegen）](thumbnail-prompt.json)\n\nきりたん・くらげ先生・男子生徒と、大きな作品名ロゴを含む。ロゴ背面は濃紺、きりたんは指定原画色のまま指さし。アプリは全行の人間確定を待っており、取り込みは未実施。\n'
readme.write_text(content,encoding='utf-8')
print(json.dumps({'dimensions':dimensions,'workspacePath':prepared['workspacePath'],'applicationImported':False},ensure_ascii=False))
