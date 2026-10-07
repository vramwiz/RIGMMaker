"""Read-only source checks and adversarial temporary image fixtures; no Delphi build/app.

The separate SceneImageContractCheck.dpr is future native coverage, not an executed
test in the no-build task. This script checks cross-layer safety invariants and
fixture expectations independently using Pillow.
"""
from pathlib import Path
import hashlib, io, json, struct, sys, tempfile, zlib
from PIL import Image

sys.stdout.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(value, label):
    if not value: raise AssertionError(label)
    checks.append(label)
def source(path): return (ROOT / path).read_text(encoding='utf-8-sig')
def body(text, name, next_name):
    return text[text.index(name, text.index('implementation') if 'implementation' in text else 0):text.index(next_name, text.index(name, text.index('implementation') if 'implementation' in text else 0)+len(name))]
model = source('Studio/Model/RigmScriptScenesModel.pas')
asset = source('Studio/Assets/RigmMovieImageTransfer.pas')
workspace = source('Shell/Pages/RigmWizardWorkspace.pas')
flow = source('Shell/Pages/RigmScriptScenesWorkspace.inc')
ui = source('Shell/Pages/RigmScriptScenesFrame.pas')
closing = source('Shell/Pages/RigmScriptClosingWorkspace.inc')
assignment = source('Studio/Model/RigmScriptSceneAssignmentModel.pas')

for field in ['imageApproved','imageApprovalKey','imageEditEpoch','imageFeedback']:
    check(field in source('Studio/Model/RigmMovieComposition.pas'), f'{field} persisted')
apply = body(model, 'procedure ApplyScriptSceneImage', 'function ScriptSceneReady')
check(apply.count('RequireEditableScriptScene(Project,Id)')==2, 'lock checked before validation and before publication')
check(apply.count('RequireSceneImageRequest(Project,Id,RequestId)')==2, 'request rechecked immediately before publication')
check(apply.index('CheckedMovieImageHash(Path,True)')<apply.index('Project.Scene(Id).Image := Path'), 'full image decode before reference switch')
approve = body(model, 'procedure SetScriptSceneApproved', 'procedure ApplyScriptSceneImage')
check('Inc(S.ImageEditEpoch)' in approve and "PsdJson.Put(R,'state','cancelled')" in approve, 'approve/unlock invalidates in-flight results')
check("Name='script-set-scene-approved'" not in workspace and "Name='script-unlock-scene'" not in workspace, 'pipes cannot unlock approvals')
ready = body(model, 'function ScriptSceneReady', 'function ScriptScenesReady')
check('not Scene.ImageApproved' in ready and "Scene.Image=''" in ready and 'Scene.ImageApprovalKey=ScriptSceneFingerprint' in ready, 'ready requires checked valid image and current context')
check('ScriptScenesReady(FScriptDraft,True)' in closing, 'editor entry forces uncached full validation')
check(closing.index("StoreScript(P,'editor')")<closing.index('Session.SetProject'), 'save precedes editor session publication')
check('ScriptScenesAdvanceReason' in workspace and 'ScriptScenesAdvanceReason' in closing, 'Next/status/editor share progress predicate')
check('OldIds<>NewIds' in assignment and 'Scene.ImageApproved := False' in assignment, 'split/merge reopens altered membership')
check("for var Key in ['imageApproved','imageApprovalKey','animation','chart','padding','title']" in model, 'downstream animation excluded from approval identity')
check("'sceneId',Id" in model and "'sceneNumber',ScriptSceneNumber" in model, 'identity and display number distinct')
check("FPipe.Workspace.Resolve(JS(Args,'path'))" in flow and 'CopyCheckedMovieImage' in flow, 'local delivery retains data-root path boundary')
delivery = flow[flow.index('procedure TRigmWizardWorkspace.DeliverScriptSceneImage'):flow.index('procedure TRigmWizardWorkspace.UpdateScriptSceneInputs')]
check(delivery.index('CopyCheckedMovieImage')<delivery.rindex('RequireSceneImageRequest')<delivery.index('ApplyScriptSceneImage'), 'late request check follows successful managed copy')
check('MOVEFILE_REPLACE_EXISTING' not in body(asset,'function CopyCheckedMovieImage','function MovieImageTransferSchema'), 'managed import never overwrites originals or collisions')
for token in ['FILE_FLAG_OPEN_REPARSE_POINT','FILE_ATTRIBUTE_REPARSE_POINT','CREATE_NEW','FlushFileBuffers','ExpectedHash','Bitmap.Assign(Picture.Graphic)','Png.CheckCRC := True']:
    check(token in asset, f'safe import: {token}')
check('HeaderSize=40' in asset and 'Colors>256' in asset and 'Int64(HeaderSize)+14>Stream.Size' in asset, 'BMP allocation bounded before native decoder')
check('Result.Left := MaxInt' in ui, 'left-column order preserved')
columns = [ui.index("Column('"+x) for x in ['シーン','画像要望','画像補足','要求画像','確定']]
check(columns==sorted(columns), 'scene/requirement/caption/preview/check order')
check('S.ImageApproved' in ui and 'Row.Prompt.ReadOnly' in ui and 'Row.Description.ReadOnly' in ui, 'approved row input locked')
check('UpdateScriptSceneInputs(A)' in ui, 'row inputs apply atomically through model')
check('Row.SceneId' in ui and 'FRows[I].SceneId<>P.Scenes[I].Id' in ui, 'row reuse follows stable IDs')

def chunk(kind, data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
def png_preflight(data):
    # Independent strict format oracle; proves adversarial fixture expectations, not native execution.
    if data[:8]!=b'\x89PNG\r\n\x1a\n': return False
    pos=8; kinds=[]; pixels=bytearray(); geometry=None
    while pos<len(data):
        if pos+12>len(data): return False
        n=struct.unpack_from('>I',data,pos)[0]; kind=data[pos+4:pos+8]; payload=data[pos+8:pos+8+n]
        if len(payload)!=n or pos+12+n>len(data): return False
        if zlib.crc32(kind+payload)&0xffffffff!=struct.unpack_from('>I',data,pos+8+n)[0]: return False
        kinds.append(kind)
        if len(kinds)>4096: return False
        if kind==b'IHDR':
            if len(kinds)!=1 or n!=13: return False
            geometry=struct.unpack('>IIBBBBB',payload)
        elif kind not in [b'PLTE',b'IDAT',b'IEND',b'tRNS',b'gAMA',b'cHRM',b'sRGB',b'pHYs',b'tEXt',b'sBIT',b'bKGD',b'tIME']: return False
        if kind==b'IDAT': pixels+=payload
        pos+=n+12
        if kind==b'IEND' and (n!=0 or pos!=len(data)): return False
    if not geometry or kinds[-1]!=b'IEND': return False
    w,h,depth,color,compression,filtering,interlace=geometry
    allowed={0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]}
    if color not in allowed or depth not in allowed[color] or compression or filtering or interlace: return False
    if not 1<=w<=8192 or not 1<=h<=8192 or w*h>16777216: return False
    channels={0:1,2:3,3:1,4:2,6:4}[color]; row=(w*channels*depth+7)//8+1; expected=row*h
    z=zlib.decompressobj(); decoded=z.decompress(pixels,expected+1)
    if len(decoded)!=expected or not z.eof or z.unused_data or z.unconsumed_tail: return False
    return all(decoded[i]<=4 for i in range(0,len(decoded),row))
def fixture_accept(data, ext):
    # Independent bounded format oracle, not the Delphi implementation.
    if not (0<len(data)<=32*1024*1024): return False
    try:
        if ext=='.png' and not png_preflight(data): return False
        if ext=='.bmp':
            h=struct.unpack_from('<I',data,14)[0]
            if h not in (40,52,56) or 14+h>len(data): return False
            colors=struct.unpack_from('<I',data,46)[0]
            if colors>256: return False
        if ext in ('.jpg','.jpeg') and data[-2:]!=b'\xff\xd9': return False
        im=Image.open(io.BytesIO(data)); w,h=im.size
        if not (1<=w<=8192 and 1<=h<=8192 and w*h<=16777216): return False
        im.verify(); im=Image.open(io.BytesIO(data)); im.load()
        return True
    except Exception: return False

with tempfile.TemporaryDirectory(prefix='rigm-scene-contract-') as td:
    td=Path(td)
    original={}
    for ext,fmt in [('.png','PNG'),('.jpg','JPEG'),('.bmp','BMP')]:
        buf=io.BytesIO(); Image.new('RGB',(32,16),'blue').save(buf,fmt); data=buf.getvalue()
        check(fixture_accept(data,ext), f'fixture valid {fmt}')
        original[ext]=data; (td/('fixture'+ext)).write_bytes(data)
        check(not fixture_accept(data[:len(data)//2],ext), f'fixture truncated {fmt}')
    bad=bytearray(original['.png']); bad[-8]^=1
    check(not fixture_accept(bytes(bad),'.png'), 'fixture PNG CRC rejection')
    huge=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',8193,1,8,2,0,0,0))+chunk(b'IEND',b'')
    check(not fixture_accept(huge,'.png'), 'fixture oversized dimensions rejected before decode')
    malicious=bytearray(original['.bmp']); struct.pack_into('<I',malicious,14,0x7ffffff0)
    check(not fixture_accept(bytes(malicious),'.bmp'), 'fixture enormous BMP DIB header rejected')
    check(not fixture_accept(b'broken','.png'), 'fixture broken image rejected')
    def png(w,h,raw): return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',raw)+chunk(b'IEND',b'')
    pixels=zlib.compress(b'\0'+bytes(3))
    duplicate=png(1,1,pixels).replace(chunk(b'IDAT',pixels),chunk(b'IHDR',struct.pack('>IIBBBBB',65535,65535,8,2,0,0,0))+chunk(b'IDAT',pixels))
    check(not fixture_accept(duplicate,'.png'),'fixture duplicate IHDR rejected before native allocation')
    metadata=png(1,1,pixels).replace(chunk(b'IDAT',pixels),chunk(b'zTXt',b'x\0\0'+zlib.compress(b'x'*1048576))+chunk(b'IDAT',pixels))
    check(not fixture_accept(metadata,'.png'),'fixture compressed metadata excluded')
    check(not fixture_accept(png(1,2,pixels+b'extra'),'.png'),'fixture premature zlib end plus trailing bytes rejected')
    check(not fixture_accept(png(1,1,pixels[:-2]),'.png'),'fixture missing zlib checksum rejected')
    check(not fixture_accept(png(1,1,zlib.compress(bytes(100000))),'.png'),'fixture excess pixel expansion bounded')
    check(not fixture_accept(png(1,1,zlib.compress(b'\5'+bytes(3))),'.png'),'fixture invalid row filter rejected')
    bad_palette=bytearray(original['.bmp']);struct.pack_into('<I',bad_palette,46,0x40000000)
    check(not fixture_accept(bytes(bad_palette),'.bmp'),'fixture overflowing BMP palette rejected')
    for token in ['HeaderFound or (Chunks<>1)','Chunks>4096',"CheckPngPixels(Pixels",'Status=Z_STREAM_END','BeforeIn=Z.total_in','Total<>Expected','Z.avail_in<>0',"ImageHeader(Stream,'.png')"]:
        check(token in asset, 'strict image preflight: '+token)

    # Content addressing retains both revisions and never modifies the source.
    managed=td/'Images'; managed.mkdir()
    for ext,data in original.items():
        dest=managed/(hashlib.sha256(data).hexdigest()+ext); dest.write_bytes(data)
        check((td/('fixture'+ext)).read_bytes()==data, f'fixture original {ext} preserved')
    check(len(list(managed.iterdir()))==3, 'fixture same base name does not collide across images')

print(json.dumps({'passed':len(checks),'checks':checks,'limitations':['No Delphi compilation or product execution; native model harness supplied for later user build.','Fixture image checks use independent Pillow decoder, not VCL.']},ensure_ascii=False,indent=2))
