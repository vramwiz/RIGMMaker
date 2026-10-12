import json
from pathlib import Path

job = Path(__file__).parent
repo = job.parents[2]
before = json.loads((job / 'project-immediately-before.rigmovie').read_text(encoding='utf-8-sig'))
after = json.loads((job / 'project-after.rigmovie').read_text(encoding='utf-8-sig'))
status = json.loads((job / 'status-after-repair.json').read_text(encoding='utf-8-sig'))

def differences(a, b, path=''):
    if isinstance(a, dict) and isinstance(b, dict):
        for key in a.keys() | b.keys():
            yield from differences(a.get(key), b.get(key), f'{path}.{key}'.lstrip('.'))
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            yield {'path': path, 'beforeCount': len(a), 'afterCount': len(b)}
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                yield from differences(x, y, f'{path}[{i}]')
    elif a != b:
        yield {'path': path, 'before': a, 'after': b}

diffs = list(differences(before, after))
allowed = {'revision', 'scriptWizard.updatedAt', 'scriptWizard.closingData.draft.title'}
allowed |= {f'scenes[{i}].animation.closingCard.title' for i in range(len(after['scenes']))}
assert all(x['path'] in allowed for x in diffs), diffs
assert before['cues'] == after['cues'] and len(after['cues']) == 44
assert before['thumbnail'] == after['thumbnail']
assert before['commonBackground'] == after['commonBackground']
assert before['endCards'] == after['endCards']
assert status['voiceReady'] and status['scenesReady'] and not status['modified']
assert status['wizard']['stage'] == 'scenes'
assert after['thumbnail']['imageApproved']

old_title_matches = []
def scan(value, path=''):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'castingArchives':
                continue
            scan(child, f'{path}.{key}'.lstrip('.'))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            scan(child, f'{path}[{i}]')
    elif isinstance(value, str) and '降り積もる雪' in value:
        old_title_matches.append(path)
scan(after)
assert not old_title_matches, old_title_matches

report = {
    'projectId': status['projectId'], 'revision': status['revision'],
    'title': status['title'], 'stage': status['wizard']['stage'],
    'savedUnmodified': not status['modified'],
    'all44CuesAudioAndAssignmentsUnchanged': True,
    'all11SceneImagesPromptsAndApprovalsUnchanged': True,
    'backgroundThumbnailAndEndCardsUnchanged': True,
    'voiceReady': status['voiceReady'], 'scenesReady': status['scenesReady'],
    'thumbnailHumanApproved': after['thumbnail']['imageApproved'],
    'oldTitleMatchesOutsideHistoricalArchives': old_title_matches,
    'historicalCastingArchivesPreserved': before['scriptWizard'].get('castingArchives') == after['scriptWizard'].get('castingArchives'),
    'changes': diffs,
}
(job / 'live-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

record_path = repo / '制作支援/学習記録/RIGM/20261012-isekai-uso-scenes/additional/thumbnail-fix/learning_record.json'
record = json.loads(record_path.read_text(encoding='utf-8-sig'))
record['userVisualEvaluation'] = 'accepted'
record['followupUserInstruction'] = '画像はそれで良いです。次回はきりたんを棒立ちにせず、制作に関するルールを修正。'
record['acceptance'] = {
    'date': '2026-10-12', 'currentImageAccepted': True,
    'imageRegeneratedAfterAcceptance': False,
    'thumbnailHumanApprovedInApp': True, 'verifiedRevision': status['revision'],
    'futurePoseRule': '原画の外見と配色を維持し、場面・セリフに合う表情、視線、身振り、体の向きを指定する。参照画像の棒立ち姿勢は固定しない。',
}
record['limitations'] = [
    '内蔵画像編集による差し替えで、元のキャラ画素の機械的コピーではない。',
    '採用後の動画出力での確認は未実施。verificationは画像受渡し時点の記録として保持。',
]
pose_rule = 'きりたんの原画は外見・配色の参照とし、次回は場面に合う表情・視線・身振り・体の向きを付け、棒立ちにしない。'
if pose_rule not in record['reusableRules']:
    record['reusableRules'].append(pose_rule)
with record_path.open('w', encoding='utf-8', newline='\r\n') as f:
    f.write(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'changes': diffs, 'activeOldTitleMatches': old_title_matches, 'userImageEvaluation': record['userVisualEvaluation']}, ensure_ascii=True))
