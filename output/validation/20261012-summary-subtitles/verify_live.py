import json
from pathlib import Path

job = Path(__file__).parent
before = json.loads((job / 'project-live-before.rigmovie').read_text(encoding='utf-8-sig'))
after = json.loads((job / 'project-live-after.rigmovie').read_text(encoding='utf-8-sig'))
status = json.loads((job / 'status-after.json').read_text(encoding='utf-8-sig'))
scene_id = before['scriptWizard']['summaryData']['sceneId']
changed = []
for a, b in zip(before['cues'], after['cues']):
    a, b = dict(a), dict(b)
    if a['scene'] == scene_id:
        assert a['subtitle'] == '' and b['subtitle'] == a['text']
        changed.append({'id': b['id'], 'subtitle': b['subtitle']})
        a.pop('subtitle'); b.pop('subtitle')
    assert a == b, a['id']
assert len(changed) == 6 and len(before['cues']) == len(after['cues']) == 44
allowed = {'cues', 'revision'}
assert all(before.get(key) == after.get(key) for key in before.keys() | after.keys() if key not in allowed)
assert not status['modified']
report = {
    'projectId': status['projectId'], 'revision': status['revision'],
    'savedUnmodified': not status['modified'], 'changedSummarySubtitles': changed,
    'all44SpokenLinesReadingsAudioAndAssignmentsUnchanged': True,
    'allScenesImagesBackgroundThumbnailApprovalsAndClosingTitleUnchanged': True,
    'otherProjectFieldsUnchanged': True,
    'videoNeedsReexportForChangedSubtitles': True,
}
(job / 'live-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'revision': status['revision'], 'restoredSummarySubtitles': len(changed), 'allOtherDataPreserved': True}))
