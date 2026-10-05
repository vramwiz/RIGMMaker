"""Verify the native-saved enhancement against the previous registered character."""
from pathlib import Path
from PIL import Image
import json, zipfile, hashlib
root=Path(__file__).parent
source=root.parent/'金髪アンドロイド-解説用.rigm'
target=root/'金髪アンドロイド-解説用-感情記号9種追加.rigm'
signs=json.loads((root/'symbols.json').read_text(encoding='utf-8'))
checks={}
with zipfile.ZipFile(source) as old,zipfile.ZipFile(target) as new:
    a=json.loads(old.read('manifest.json'));b=json.loads(new.read('manifest.json'))
    parts={p['id']:p for p in b['parts']}
    checks['existing_part_metadata_preserved']=all({k:v for k,v in p.items() if k!='asset'}=={k:v for k,v in parts[p['id']].items() if k!='asset'} for p in a['parts'])
    checks['existing_pixels_preserved']=all(old.read(p['asset'])==new.read(parts[p['id']]['asset']) for p in a['parts'] if p['kind']=='image')
    checks['existing_bones_preserved']=a['bones']==b['bones']
    meshes={p['id']:p for p in b['meshes']}
    checks['existing_meshes_preserved']=all(p==meshes[p['id']] for p in a['meshes'])
    checks['existing_parameters_preserved']=a['parameters']==b['parameters']
    checks['existing_body_rig_preserved']=a['bodyRig']==b['bodyRig']
    checks['all_stages_complete']=all(b['stages'].values())
    checks['nine_new_parts_and_meshes']=len(b['parts'])==len(a['parts'])+9 and len(b['meshes'])==len(a['meshes'])+9
    checks['new_symbols_pixels_equal_png']=all(new.read(parts[s['id']]['asset'])==Image.open(root/s['file']).convert('RGBA').tobytes() for s in signs)
    checks['new_symbols_are_head_bound_accessories']=all(parts[s['id']]['role']=='accessory' and parts[s['id']]['boneId']==s['boneId'] and parts[s['id']]['parentId']==s['parentId'] and not parts[s['id']]['visible'] for s in signs)
    checks['new_symbols_meshes_valid']=all(meshes[s['meshId']]['partId']==s['id'] and len(meshes[s['meshId']]['vertices'])==16 and len(meshes[s['meshId']]['triangles'])==18 and all(v['weights']==[dict(boneId=s['boneId'],value=1)] for v in meshes[s['meshId']]['vertices']) for s in signs)
    group=signs[0]['parentId'];children=[p for p in b['parts'] if p['parentId']==group]
    checks['one_default_symbol_visible']=len(children)==16 and sum(p['visible'] for p in children)==1 and next(p for p in children if p['visible'])['name']=='*なし'
result=dict(passed=all(checks.values()),checks=checks,counts=dict(parts=len(b['parts']),editable_images=51,bones=len(b['bones']),meshes=len(b['meshes']),symbol_choices=len(children)),sha256=hashlib.sha256(target.read_bytes()).hexdigest())
(root/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=True))
assert result['passed'],result
