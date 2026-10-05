"""Read-only validation and independent rendering of the saved RIGM artifact."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, zipfile, hashlib

root=Path(__file__).parent
final=root/'金髪アンドロイド-解説用.rigm'
assets=json.loads((root/'native-assets.json').read_text(encoding='utf-8-sig'))
groups=json.loads((root/'native-groups.json').read_text(encoding='utf-8-sig'))
checks={}
with zipfile.ZipFile(final) as z:
    m=json.loads(z.read('manifest.json')); parts={p['id']:p for p in m['parts']}
    images={p['id']:Image.frombytes('RGBA',(p['imageWidth'],p['imageHeight']),z.read(p['asset'])) for p in m['parts'] if p['kind']=='image'}
    checks['all_png_pixels_equal_saved_rgba']=all(Image.open(root/a['file']).convert('RGBA').tobytes()==images[a['id']].tobytes() for a in assets)
    checks['all_positions_equal']=all(parts[a['id']]['x']==a['centerX'] and parts[a['id']]['y']==a['centerY'] for a in assets)
    checks['all_visibility_equal']=all(parts[a['id']]['visible']==a['visible'] for a in assets)
    checks['all_roles_equal']=all(parts[a['id']]['role']==a['role'] for a in assets)
    checks['all_parent_ids_equal']=all(parts[a['id']]['parentId']==a['parentId'] for a in assets)
    checks['all_stages_complete']=all(m['stages'].values())
    checks['reference_rgba_equal_source']=z.read(next(p['asset'] for p in m['parts'] if p['referenceOnly']))==Image.open(r'C:\Users\vramw\Pictures\magnific__background__16889.png').convert('RGBA').tobytes()
    checks['each_exclusive_group_one_visible']=all(sum(parts[a['id']]['visible'] for a in assets if a['group']==g)==1 for g in groups)
    checks['42_meshes']=len(m['meshes'])==42
    checks['6_bones']=len(m['bones'])==6

    def render(choices=None):
        choices=choices or {}
        canvas=Image.new('RGBA',(m['width'],m['height']))
        children={}
        for p in m['parts']: children.setdefault(p['parentId'],[]).append(p)
        def draw(parent):
            for p in sorted(children.get(parent,[]),key=lambda p:p['order'],reverse=True):
                show=p['visible']
                if p['parentId'] in choices: show=p['id']==choices[p['parentId']]
                if not show or p['referenceOnly']: continue
                if p['kind']=='group': draw(p['id'])
                else:
                    im=images[p['id']]
                    x=round(p['x']-im.width/2+m['width']/2);y=round(p['y']-im.height/2+m['height']/2)
                    canvas.alpha_composite(im,(x,y))
        draw(''); return canvas

    neutral=render(); neutral.save(root/'saved-neutral.png')
    reference=Image.new('RGBA',neutral.size)
    for g in ['体','後ろ髪','顔色','眉','目','口','髪','感情記号']:
        a=next(a for a in assets if a['group']==g and a['visible'])
        reference.alpha_composite(Image.open(root/a['file']).convert('RGBA'),(a['x'],a['y']))
    checks['saved_neutral_equals_input_composition']=neutral.tobytes()==reference.tobytes()
    # Build a review exclusively from the saved RGBA and stored positions.
    settings=[{}, {'目':'*笑顔閉じ','口':'*微笑み','眉':'*喜','体':'*手のひらで紹介','顔色':'*赤面','感情記号':'*きらめき'}, {'目':'*見開き','口':'*お','眉':'*疑問','体':'*左上を指さす','感情記号':'*驚き'}, {'目':'*閉じ','口':'*悲しい','眉':'*哀','体':'*胸に手を添える','顔色':'*青ざめ','感情記号':'*汗'}, {'目':'*半開き','口':'*い','眉':'*怒','顔色':'*不調','感情記号':'*怒り'}]
    review=Image.new('RGB',(1500,860),(36,40,48))
    for i,setting in enumerate(settings):
        choices={groups[g]:next(a['id'] for a in assets if a['group']==g and a['name']==name) for g,name in setting.items()}
        im=render(choices);small=im.resize((300,533),Image.Resampling.LANCZOS)
        review.paste(small,(i*300,20),small)
        face=im.crop((455,260,695,440)).resize((300,225),Image.Resampling.LANCZOS)
        review.paste(face,(i*300,595),face)
    review.save(root/'saved-variants-review.png')
    frames=[]
    mouths=['*閉じ','*あ','*い','*う','*え','*お','*ん','*微笑み']
    eyes=['*通常','*半開き','*閉じ','*半開き','*通常','*通常','*通常','*通常']
    for mouth,eye in zip(mouths,eyes):
        choices={groups['口']:next(a['id'] for a in assets if a['group']=='口' and a['name']==mouth),groups['目']:next(a['id'] for a in assets if a['group']=='目' and a['name']==eye)}
        im=render(choices).crop((400,80,800,540)).resize((400,460),Image.Resampling.LANCZOS)
        bg=Image.new('RGBA',im.size,(44,48,57,255));bg.alpha_composite(im);frames.append(bg.convert('RGB'))
    frames[0].save(root/'目パチ-口形-確認.gif',save_all=True,append_images=frames[1:],duration=[450,140,110,140,250,250,350,500],loop=0)

result={'checks':checks,'passed':all(checks.values()),'final':str(final),'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'counts':{'images':len(images),'editable_images':len(assets),'groups':len(groups),'bones':len(m['bones']),'meshes':len(m['meshes'])}}
(root/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
assert result['passed'], result
