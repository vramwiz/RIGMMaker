"""Append transparent vector signs and head-bound meshes without changing old assets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import copy, hashlib, json, uuid, zipfile

root=Path(__file__).parent
source=root.parent/'金髪アンドロイド-解説用.rigm'
output=root/'金髪アンドロイド-解説用-感情記号9種追加.rigm'
signs=json.loads((root/'symbols.json').read_text(encoding='utf-8-sig'))
def new_id(): return '{'+str(uuid.uuid4()).upper()+'}'
with zipfile.ZipFile(source) as old:
    m=json.loads(old.read('manifest.json'))
    group=next(p for p in m['parts'] if p['name']=='感情記号' and p['kind']=='group')
    template=next(p for p in m['parts'] if p['parentId']==group['id'] and p['role']=='accessory' and not p['visible'])
    mesh_template=next(p for p in m['meshes'] if p['partId']==template['id'])
    blobs={}
    for index,sign in enumerate(signs,7):
        im=Image.open(root/sign['file']).convert('RGBA')
        assert im.size==(sign['width'],sign['height'])
        assert im.getextrema()[3][0]==0 and im.getextrema()[3][1]==255
        p=copy.deepcopy(template)
        p.update(id=new_id(),name='*'+sign['name'],order=index,visible=False,
                 imageWidth=im.width,imageHeight=im.height,
                 bounds=dict(left=0,top=0,right=im.width,bottom=im.height),
                 x=sign['x']+im.width/2-m['width']/2,y=sign['y']+im.height/2-m['height']/2,
                 tags='android,narrator,感情記号,manga',asset=f"images/manga-{index}.rgba")
        m['parts'].append(p);blobs[p['asset']]=im.tobytes()
        mesh=copy.deepcopy(mesh_template)
        mesh.update(id=new_id(),name=p['name'],partId=p['id'])
        for v in mesh['vertices']:
            v['x']=p['x']+(v['u']-.5)*im.width
            v['y']=p['y']+(v['v']-.5)*im.height
            v['weights']=[dict(boneId=p['boneId'],value=1)]
        m['meshes'].append(mesh)
        sign.update(id=p['id'],parentId=group['id'],boneId=p['boneId'],meshId=mesh['id'])
    m['revision']=str(int(m['revision'])+1)
    m['name']='金髪アンドロイド・解説用（感情記号9種追加）'
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as new:
        for item in old.infolist():
            new.writestr(item.filename,json.dumps(m,ensure_ascii=False,separators=(',',':')).encode('utf-8') if item.filename=='manifest.json' else old.read(item.filename))
        for name,data in blobs.items():new.writestr(name,data)
(root/'symbols.json').write_text(json.dumps(signs,ensure_ascii=False,indent=2),encoding='utf-8')

# Independent preview rendered solely from the saved artifact.
with zipfile.ZipFile(output) as z:
    m=json.loads(z.read('manifest.json'))
    children={}
    for p in m['parts']:children.setdefault(p['parentId'],[]).append(p)
    images={p['id']:Image.frombytes('RGBA',(p['imageWidth'],p['imageHeight']),z.read(p['asset'])) for p in m['parts'] if p['kind']=='image'}
    font=ImageFont.truetype('C:/Windows/Fonts/YuGothM.ttc',25)
    review=Image.new('RGB',(1530,1110),(32,37,46))
    draw=ImageDraw.Draw(review)
    for index,sign in enumerate(signs):
        canvas=Image.new('RGBA',(m['width'],m['height']))
        def render(parent):
            for p in sorted(children.get(parent,[]),key=lambda p:p['order'],reverse=True):
                visible=(p['id']==sign['id']) if p['parentId']==group['id'] else p['visible']
                if not visible or p['referenceOnly']:continue
                if p['kind']=='group':render(p['id'])
                else:
                    im=images[p['id']]
                    canvas.alpha_composite(im,(round(p['x']-im.width/2+m['width']/2),round(p['y']-im.height/2+m['height']/2)))
        render('')
        card=canvas.crop((110,0,1130,650)).resize((510,325),Image.Resampling.LANCZOS)
        x=(index%3)*510;y=(index//3)*370
        if index%2==0:
            draw.rectangle((x,y,x+509,y+324),fill=(234,238,244))
        review.paste(card,(x,y),card)
        draw.text((x+18,y+334),f"{index+1:02}  {sign['name']}",font=font,fill='white')
    review.save(root/'感情記号9種-キャラクター確認.png')
print(json.dumps(dict(path=str(output),signs=len(signs),parts=len(m['parts']),meshes=len(m['meshes']),sha256=hashlib.sha256(output.read_bytes()).hexdigest()),ensure_ascii=False))
