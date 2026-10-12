import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

job=Path(__file__).parent
repo=job.parents[2]
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
before=read(job/'all-scenes.json')
final=read(job/'final-verification.json')
status=read(job/'final-status.json')
saved_path=Path(status['path'])
saved=read(saved_path)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before_cues={c['cueId']:(r['id'],c['sourceText']) for r in before['rows'] for c in r['sourceCues']}
after_cues={c['cueId']:(r['id'],c['sourceText']) for r in final['rows'] for c in r['sourceCues']}
saved_cues={c['id']:(c['scene'],c['text']) for c in saved['cues']}
assert before_cues==after_cues==saved_cues, 'Source text or scene assignment changed'
assert len(saved_cues)==44
assert [r['id'] for r in before['rows']]==[r['id'] for r in final['rows']]
initial_chart=next(r for r in before['rows'] if r.get('chart'))
final_chart=next(r for r in final['rows'] if r.get('chart'))
saved_chart=next(r for r in saved['scenes'] if r.get('chart'))
assert initial_chart['chart']==final_chart['chart']==saved_chart['chart']
assert not final_chart['imagePath']
assert not final['modified'] and final['pending']==0
images=[]
for receipt_path in sorted(job.glob('receipt-*.json')):
    receipt=read(receipt_path)
    workspace=Path(receipt['workspacePath'])
    managed=Path(receipt['managedPath'])
    scene=next(r for r in saved['scenes'] if r['id']==receipt['sceneId'])
    saved_asset=saved_path.parent/scene['image']
    assert sha(workspace)==sha(managed)==sha(saved_asset)==receipt['sha256']
    with Image.open(workspace) as im:
        im.verify()
    with Image.open(workspace) as im:
        dims=im.size
        mode=im.mode
        fmt=im.format
    assert fmt=='PNG' and dims[0]<=8192 and dims[1]<=8192 and dims[0]*dims[1]<=16000000
    assert workspace.stat().st_size<=32*1024*1024
    receipt.update(width=dims[0],height=dims[1],mode=mode,format=fmt,bytes=workspace.stat().st_size,savedAssetPath=str(saved_asset),savedAssetHashVerified=True)
    images.append(receipt)
images.sort(key=lambda r:r['sceneNumber'])
assert len(images)==10
audio_files=[]
for cue in saved['cues']:
    assert cue['waveFile'], 'Missing audio reference'
    wave=Path(cue['waveFile'])
    if not wave.is_absolute(): wave=saved_path.parent/wave
    assert wave.is_file(), str(wave)
    audio_files.append(str(wave))
verification={'projectId':saved['projectId'],'savedProjectPath':str(saved_path),'revision':saved['revision'],'checkedAt':datetime.now(timezone.utc).isoformat(),'generatedAndAdoptedImages':len(images),'sceneCountPreserved':len(saved['scenes']),'sourceCueCountPreserved':len(saved_cues),'sourceTextsAndSceneAssignmentsUnchanged':True,'summaryChartUnchanged':True,'audioReferencesResolved':len(audio_files),'workspaceManagedAndSavedAssetHashesMatch':True,'pendingRequests':0,'projectModified':False,'thumbnailSourcesReady':final['thumbnail']['sourcesReady'],'humanVisualEvaluation':'not_reviewed','saveAndReopen':'not_run','images':images}
(job/'asset-verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
record_dir=repo/'制作支援'/'学習記録'/'RIGM'/'20261012-isekai-uso-scenes'
record_dir.mkdir(parents=True,exist_ok=True)
record={'schemaVersion':1,'recordType':'rigm_scene_image_creation_learning','date':'2026-10-12','purpose':'異世界「嘘」ガイド：全要望と44行を先に読み、人物の描写を維持して10枚を生成・パイプ採用・保存','userInstruction':'シーンの画像の段階に進んだので画像を生成し送信　全ての画像の要望を一度読み込み　登場人物の描写をできるだけ維持する','projectId':saved['projectId'],'sourceImages':[{'path':str(job/'official-character-reference.jpg'),'sourceUrl':'https://cdn.comic-walker.com/integration/cdpf/resources/019962/43f8bf63-8ac0-4d90-824b-ba1900c9665b.jpg','sourcePage':'https://comic-walker.com/detail/KC_019962_S','role':'ナナの公式の髪・目・服装の確認'},{'path':str(job/'official-episode-reference.jpg'),'sourcePage':'https://comic-walker.com/detail/KC_019962_S','role':'ナナとながれの公式の顔の確認'}],'prompt':str(job/'actual-prompts.json'),'method':'built-in image_gen.imagegen、10場面を順次生成。第7場面のみ衣装連続性のため1回編集。各最終PNGをワークスペースとExchangeへ非上書きコピーし、現行pending要求のsceneId/requestId/fingerprint/current/未確定を検査後app-script-adopt-scene-image。各採用後app-script-save。','imageSpecificConditions':['通常シーン・共通背景の画像要望はすべて空欄だったため、ユーザーの生成指示に基づき全台本から場面案を作成。既存の人間の要望の上書きはなし。','ナナは公式参照で白銀の長髪・赤い目・黒いチョーカー・黒い上着・クリーム色の上衣を確認。','ながれの服の色は公式参照では確認できず、生成用の解釈として青い上衣と灰色のズボンに統一。','生成済み第1場面を人物の基準に、直前の情景または町の画像を場所・画風の参照に使用。','第7場面でタイツが追加されたため、第3場面と同じ普通の素足へ内蔵imagegenで修正。','総評は既存のレーダーチャートを使用。任意の共通背景は要望なしの状態を保持。','必須サムネイルは通常シーンの人間確定前でsourcesReady=falseのため未要求・未生成・未採用。'],'preservedInformation':['全44行のセリフとsceneId所属','11シーンのIDと順序','総評チャートの5項目と点数','44件の保存済み音声参照','人間の確定操作を代行していない'],'verification':verification,'userFeedback':'今回の生成画像への人間の評価は未取得。','reusableRules':['全要望と関連セリフを生成前に読み、人物と場所の基準を作る。','人物基準画像と前シーン画像を区別して参照し、場面転換時には新しい構図を明記する。','服装が小さく変化した場合も、採用前に画像編集で揃える。','番号だけで採用せず、現行の固定sceneIdとpending要求を照合する。'],'lessons':['初回の生成画像が人物の全身を含まない場合、後続で靴・脚の衣装に差が出るため、初めから全身衣装を言語化するとよい。','元のPNGを変換せず採用し、作業用・管理用・保存資産の3か所でSHA256一致を確認できた。'],'limitations':['人物と背景の細部はAI生成のため完全一致ではない。','生成寸法は1672x941で、目標1920x1080に近い16:9。アプリが元バイトを保持して表示寸法へ拡大縮小する。'],'unverified':['ユーザーの画像確定','必須サムネイルの制作','アプリを終了して再開後の表示','動画出力での確認'],'artifacts':{'finalImages':[r['workspacePath'] for r in images],'prompt':str(job/'actual-prompts.json'),'plan':str(job/'generation-plan.json'),'verification':str(job/'asset-verification.json'),'allInitialRequirements':str(job/'all-scenes.json'),'finalLiveState':str(job/'final-verification.json'),'savedProject':str(saved_path)}}
(record_dir/'learning_record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in verification.items() if k!='images'},ensure_ascii=False,indent=2))
