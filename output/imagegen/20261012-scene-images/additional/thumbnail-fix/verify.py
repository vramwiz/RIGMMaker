import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

job=Path(__file__).parent
repo=job.parents[4]
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before=read(job/'initial-scenes.json')
after=read(job/'final-scenes.json')
status=read(job/'final-status.json')
receipt=read(job/'receipt-thumbnail.json')
saved_path=Path(status['path'])
saved=read(saved_path)
assert before['projectId']==after['projectId']==saved['projectId']
for old,new in zip(before['rows'],after['rows']):
    assert old['id']==new['id']
    assert sha(old['imagePath'])==sha(new['imagePath'])
    for key in ('imageApproved','imageApprovalKey','imagePrompt','imageEditEpoch','description','chart','sourceCues'):
        assert old.get(key)==new.get(key), (old['id'],key)
for key in ('imageApproved','imageApprovalKey','imagePrompt','imageEditEpoch'):
    assert before['background'].get(key)==after['background'].get(key)
assert sha(before['background']['imagePath'])==sha(after['background']['imagePath'])
old_cues={c['cueId']:(r['id'],c['sourceText']) for r in before['rows'] for c in r['sourceCues']}
saved_cues={c['id']:(c['scene'],c['text']) for c in saved['cues']}
assert old_cues==saved_cues and len(saved_cues)==44
saved_asset=saved_path.parent/saved['thumbnail']['image']
assert sha(saved_asset)==sha(receipt['workspacePath'])==sha(receipt['managedPath'])==receipt['sha256']
assert sha(before['thumbnail']['imagePath'])!=receipt['sha256']
with Image.open(receipt['workspacePath']) as im:im.verify()
with Image.open(receipt['workspacePath']) as im:dimensions=im.size;mode=im.mode
verification={'checkedAt':datetime.now(timezone.utc).isoformat(),'projectId':saved['projectId'],'revision':saved['revision'],'thumbnailAdopted':after['thumbnail']['imageRequest']['state']=='adopted','thumbnailHumanApproved':after['thumbnail']['imageApproved'],'workspaceManagedSavedHashesMatch':True,'all11SceneImagesBackgroundAndApprovalsPreserved':True,'source44CuesAndAssignmentsPreserved':True,'oldThumbnailFilePreserved':Path(before['thumbnail']['imagePath']).is_file(),'dimensions':dimensions,'mode':mode,'savedAssetPath':str(saved_asset),'sha256':receipt['sha256'],'projectModified':status['modified']}
(job/'asset-verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
record_dir=repo/'制作支援'/'学習記録'/'RIGM'/'20261012-isekai-uso-scenes'/'additional'/'thumbnail-fix'
record_dir.mkdir(parents=True,exist_ok=True)
reference=Path('D:/Manga/基本テンプレート/東北きりたん/東北きりたん_草履あり.png')
record={'schemaVersion':1,'recordType':'rigm_thumbnail_image_edit_learning','date':'2026-10-12','purpose':'サムネイルのきりたんの色とロゴの視認性を修正','userInstruction':'東北きりたんがなぜか青いので　これに差し替え　ロゴの後ろを図形か何かでロゴを背景より目立たせる修正','sourceImages':[{'path':before['thumbnail']['imagePath'],'role':'編集前のサムネイル'},{'path':str(reference),'sha256':sha(reference),'role':'ユーザー提供。中央の正面姿だけを使用し、赤茶の髪・自然な肌色・衣服・足袋・草履を参照。'}],'method':'内蔵image_gen.imagegenによる画像編集。色が青いアプリのキャラプレビューより、ユーザー提供原画を優先。現行未確定サムネイルへ修正要望を加えて新しい要求を作成し、PNGの現行requestIdとfingerprintを照合してパイプ採用・保存。','prompt':str(job/'edit-prompt.json'),'observations':['左下のきりたんを、提供原画の正面姿を参照した自然な色の立ち姿へ置換。三面図の側面・背面と白背景は使用しない。','元の作品名ロゴの背面へ、不透明なえんじから焦げ茶の角丸パネルと明るい縁を追加。','ナナ・少年の顔と衣装、ロゴの文字・サイズ・配色、全体構図は画像生成結果を目視して維持を確認。対象外画素の完全一致は主張しない。','変更対象はサムネイルのみ。キャラクターのRIGM素材や他のシーンを変更する操作は実行していない。'],'verification':verification,'userVisualEvaluation':'not_reviewed','limitations':['内蔵画像編集による差し替えで、元のキャラ画素の機械的コピーではない。','サムネイルの人間確定・動画出力での確認は未実施。'],'reusableRules':['キャラプレビューと提供原画の色が異なる時は、ユーザー指定の原画を最優先の参照にする。','ロゴと背景の明度差を大きくし、不透明な背面形状で背景の細部を抑える。'],'artifacts':{'finalImage':receipt['workspacePath'],'previousImage':before['thumbnail']['imagePath'],'prompt':str(job/'edit-prompt.json'),'verification':str(job/'asset-verification.json'),'savedProject':str(saved_path)}}
(record_dir/'learning_record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(verification,ensure_ascii=False,indent=2))
