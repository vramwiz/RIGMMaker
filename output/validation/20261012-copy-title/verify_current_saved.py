import json, hashlib, subprocess
from pathlib import Path

job = Path(__file__).parent
repo = job.parents[2]
baseline = json.loads((job / 'project-after.rigmovie').read_text(encoding='utf-8-sig'))
path = Path('C:/Users/zan12/Documents/RIGMMaker/Projects/{0C6B3396-4F42-46DE-8A5F-EF3A0DD84AEF}/project.rigmovie')
current = json.loads(path.read_text(encoding='utf-8-sig'))
assert current['scriptWizard']['closingData']['draft']['title'] == '異世界「嘘」ガイド'
changed_cue_fields = sorted({key for a, b in zip(baseline['cues'], current['cues']) for key in a.keys() | b.keys() if a.get(key) != b.get(key)})
report = {
    'revision': current['revision'], 'stage': current['scriptWizard']['stage'],
    'closingTitle': current['scriptWizard']['closingData']['draft']['title'],
    'currentCueCount': len(current['cues']),
    'changedCueFieldsSinceRepairVerification': changed_cue_fields,
    'sceneDataUnchangedSinceRepairVerification': current['scenes'] == baseline['scenes'],
    'thumbnailUnchangedSinceRepairVerification': current['thumbnail'] == baseline['thumbnail'],
    'backgroundUnchangedSinceRepairVerification': current['commonBackground'] == baseline['commonBackground'],
    'endCardsUnchangedSinceRepairVerification': current['endCards'] == baseline['endCards'],
    'note': '修復直後の全データ保持はlive-verification.jsonで確認済み。後続の別操作後の状態は独立して記録する。',
    'savedProjectSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
}
(job / 'current-saved-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

for name in ('note-history.md',):
    original = subprocess.run(['git', 'show', f'HEAD:{name}'], cwd=repo, check=True, capture_output=True).stdout
    target = repo / name
    data = target.read_bytes()
    if original.startswith(b'\xef\xbb\xbf') and not data.startswith(b'\xef\xbb\xbf'):
        target.write_bytes(b'\xef\xbb\xbf' + data)

print(json.dumps(report, ensure_ascii=True))
