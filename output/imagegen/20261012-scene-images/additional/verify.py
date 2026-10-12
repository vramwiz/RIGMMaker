import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

job=Path(__file__).parent
repo=job.parents[3]
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
initial=read(job/'initial-scenes.json')
current=read(job/'latest-scenes.json')
status=read(job/'latest-status.json')
saved_path=Path(status['path'])
saved=read(saved_path)
old_cues={c['cueId']:(r['id'],c['sourceText']) for r in initial['rows'] for c in r['sourceCues']}
new_cues={c['cueId']:(r['id'],c['sourceText']) for r in current['rows'] for c in r['sourceCues']}
assert old_cues==new_cues
assert initial['projectId']==current['projectId']==saved['projectId']
images=[]
for key in ('background','summary','thumbnail'):
    receipt_path=job/f'receipt-{key}.json'
    if not receipt_path.exists():continue
    receipt=read(receipt_path)
    if key=='background':image=saved['themeBackground']
    elif key=='thumbnail':image=saved['thumbnail']['image']
    else:image=next(r['image'] for r in saved['scenes'] if r['id']==receipt['sceneId'])
    saved_asset=Path(image)
    if not saved_asset.is_absolute():saved_asset=saved_path.parent/saved_asset
    assert sha(saved_asset)==sha(receipt['workspacePath'])==sha(receipt['managedPath'])==receipt['sha256']
    with Image.open(receipt['workspacePath']) as im:im.verify()
    with Image.open(receipt['workspacePath']) as im:dims=im.size;mode=im.mode
    receipt.update(savedAssetPath=str(saved_asset),savedAssetHashVerified=True,width=dims[0],height=dims[1],mode=mode)
    images.append(receipt)
summary_id=read(job/'requested-summary.json')['id']
for before in initial['rows']:
    if before['id']==summary_id:continue
    now=next(r for r in current['rows'] if r['id']==before['id'])
    assert sha(before['imagePath'])==sha(now['imagePath'])
    if before['imageApproved']:assert now['imageApproved']
summary_before=next(r for r in initial['rows'] if r['id']==summary_id)
summary_now=next(r for r in current['rows'] if r['id']==summary_id)
assert summary_before['chart']==summary_now['chart']
verification={'checkedAt':datetime.now(timezone.utc).isoformat(),'projectId':current['projectId'],'revision':current['revision'],'generatedAndSent':[r['key'] for r in images],'workspaceManagedSavedHashesMatch':True,'other10ImagesAndExistingApprovalsPreserved':True,'source44CuesAndAssignmentsPreserved':True,'summaryChartPreserved':True,'thumbnailSourcesReady':current['thumbnail']['sourcesReady'],'thumbnailReady':current['thumbnail']['ready'],'images':images}
(job/'asset-verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
record_dir=repo/'制作支援'/'学習記録'/'RIGM'/'20261012-isekai-uso-scenes'/'additional'
record_dir.mkdir(parents=True,exist_ok=True)
record={'schemaVersion':1,'recordType':'rigm_scene_image_creation_learning','date':'2026-10-12','purpose':'背景・総評の追加画像と最後のサムネイル','userInstruction':'サムネイル　背景　ほか1シーンの画像が来ていないので作って送って','method':'内蔵image_gen.imagegenで既存生成画像を参照し、現行pending要求を照合してパイプ採用・保存。','initialRequirements':str(job/'initial-scenes.json'),'prompts':[str(p) for p in job.glob('*-prompt.json')],'verification':verification,'observations':['共通背景の新しい要望は人物なしの単純な異世界イラスト。','未着のシーンは新しくナナの色白・細身・小柄さを指定された総評。既存チャートは保持し、別途画像を採用。','通常の9画像は既にユーザー確定済みであり、上書きせず維持。','サムネイル要求は共通背景・全通常シーンの人間確定後にのみ有効。'],'userVisualEvaluation':'see live approvals; no inferred approval','artifacts':{'finalImages':[r['workspacePath'] for r in images],'verification':str(job/'asset-verification.json'),'savedProject':str(saved_path)}}
(record_dir/'learning_record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in verification.items() if k!='images'},ensure_ascii=False,indent=2))
