"""Stage existing verified assets as a self-contained future app exchange package."""
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image
import argparse, hashlib, json, shutil, zipfile

parser=argparse.ArgumentParser()
parser.add_argument('--destination',required=True)
args=parser.parse_args()
source=Path(__file__).parent
addition=source/'感情記号9種'
work=Path(args.destination).resolve()
package=work/'金髪アンドロイド-20261005'
if package.exists():
    raise RuntimeError(f'Work package already exists; preserve it before creating another: {package}')
package.mkdir(parents=True)
for directory in ['character','reference','images','data','processing','previews','results']:
    (package/directory).mkdir()

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def write_json(relative,value):
    (package/relative).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def copy_file(original,relative):
    target=package/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():raise RuntimeError(f'Unexpected existing destination: {target}')
    shutil.copy2(original,target)
    assert hashlib.sha256(original.read_bytes()).digest()==hashlib.sha256(target.read_bytes()).digest()
def sha256(path):return hashlib.sha256(path.read_bytes()).hexdigest()

registration=read_json(addition/'registration.json')
rigm=Path(registration['artifact'])
copy_file(rigm,'character/character.rigm')
original=Path(r'C:\Users\vramw\Pictures\magnific__background__16889.png')
copy_file(original,'reference/original.png')
old_assets={a['id']:(source/a['file']) for a in read_json(source/'native-assets.json')}
new_symbols=read_json(addition/'symbols.json')
new_assets={a['id']:(addition/a['file']) for a in new_symbols}
asset_sources={**old_assets,**new_assets}
group_folders={'体':'body','後ろ髪':'back-hair','顔色':'face','髪':'hair','目':'eyes','眉':'brows','口':'mouth','感情記号':'symbols'}
copied_pixels=True
with zipfile.ZipFile(rigm) as archive:
    model=json.loads(archive.read('manifest.json'))
    native_groups={p['id']:p for p in model['parts'] if p['kind']=='group'}
    children={}
    for part in model['parts']:children.setdefault(part['parentId'],[]).append(part)
    paint_ids=[]
    def visit(parent):
        for p in sorted(children.get(parent,[]),key=lambda v:v['order'],reverse=True):
            if p['referenceOnly']:continue
            if p['kind']=='group':visit(p['id'])
            else:paint_ids.append(p['id'])
    visit('')
    paint_order={part_id:index for index,part_id in enumerate(paint_ids)}
    groups=[]
    parts=[]
    for p in model['parts']:
        if p['kind']=='group':
            group_parts=children[p['id']]
            groups.append(dict(id=p['id'],name=p['name'],parentId=p['parentId'],siblingOrder=p['order'],
                visible=p['visible'],opacityByte=p['opacity'],blendMode=p['blendKey'],
                selectionMode='fixed' if len(group_parts)==1 else 'exclusive',
                partIds=[c['id'] for c in sorted(group_parts,key=lambda v:v['order'])],
                defaultPartId=next(c['id'] for c in group_parts if c['visible'])))
            continue
        if p['referenceOnly']:
            relative='reference/original.png'
            group_name=None
        else:
            group_name=native_groups[p['parentId']]['name']
            image_source=asset_sources[p['id']]
            folder=group_folders[group_name]
            if group_name=='感情記号':folder+='/added-9' if p['id'] in new_assets else '/original'
            relative=f'images/{folder}/{image_source.name}'
            copy_file(image_source,relative)
        im=Image.open(package/relative).convert('RGBA')
        assert im.size==(p['imageWidth'],p['imageHeight'])
        copied_pixels=copied_pixels and im.tobytes()==archive.read(p['asset'])
        assert p['rotation']==0 and p['scaleX']==1 and p['scaleY']==1
        parts.append(dict(id=p['id'],name=p['name'],label=p['name'].removeprefix('*'),
            file=relative,groupId=p['parentId'],groupName=group_name,role=p['role'],
            referenceOnly=p['referenceOnly'],defaultVisible=p['visible'],
            siblingOrder=p['order'],paintOrder=paint_order.get(p['id']),
            width=p['imageWidth'],height=p['imageHeight'],
            placement=dict(left=p['x']+model['width']/2-p['imageWidth']/2,
                top=p['y']+model['height']/2-p['imageHeight']/2,
                centerX=p['x'],centerY=p['y'],rotationDegrees=p['rotation'],
                scaleX=p['scaleX'],scaleY=p['scaleY'],opacityByte=p['opacity']),
            boneId=p['boneId'],locked=p['locked'],tags=p['tags']))
    assert copied_pixels

groups.sort(key=lambda g:g['siblingOrder'])
parts.sort(key=lambda p:(p['referenceOnly'],p['paintOrder'] if p['paintOrder'] is not None else 999))
part_by_id={p['id']:p for p in parts}
group_by_name={g['name']:g for g in groups}
def choice(group,label):
    return next(p['id'] for p in parts if p['groupName']==group and p['label']==label)

write_json('data/groups.json',groups)
write_json('data/parts.json',parts)
write_json('data/current-selection.json',dict(schemaVersion=1,
    selections=[dict(groupId=g['id'],partId=g['defaultPartId']) for g in groups]))
write_json('data/rig.json',dict(coordinates=model['coordinates'],canvas=dict(width=model['width'],height=model['height']),
    bodyRig=model['bodyRig'],bones=model['bones'],meshes=model['meshes'],parameters=model['parameters']))
expressions=read_json(source/'表情設定.json')
write_json('data/expression-presets.json',expressions)
symbol_group=group_by_name['感情記号']
symbol_presets=[]
for part_id in symbol_group['partIds']:
    p=part_by_id[part_id]
    symbol_presets.append(dict(name=p['label'],variants=[dict(groupId=symbol_group['id'],partId=part_id)],
        blinkAnimate=True,mouthAnimate=True,rigSafe=True,
        batch='added-9' if part_id in new_assets else 'original'))
write_json('data/symbol-presets.json',symbol_presets)
write_json('data/animation.json',dict(schemaVersion=1,mode='asset-switch',
    blink=dict(groupId=group_by_name['目']['id'],
        normalPartId=choice('目','通常'),halfOpenPartId=choice('目','半開き'),closedPartId=choice('目','閉じ'),
        example=dict(status='implementation-example',intervalMs=4000,steps=[
            dict(partId=choice('目','半開き'),durationMs=80),dict(partId=choice('目','閉じ'),durationMs=100),
            dict(partId=choice('目','半開き'),durationMs=80),dict(partId=choice('目','通常'),durationMs=0)])),
    lipSync=dict(groupId=group_by_name['口']['id'],neutralPartId=choice('口','通常'),closedPartId=choice('口','閉じ'),
        halfOpenPartId=choice('口','半開き'),phonemePartIds={phoneme:choice('口',label) for phoneme,label in
            [('a','あ'),('i','い'),('u','う'),('e','え'),('o','お'),('N','ん'),('closed','閉じ')]},
        audioTiming='supply-by-application; no audio or LAB timing in this package')))

learning=read_json(source/'learning_record.json')
rules=learning['reusable_rules']
rules=[('パーツ一覧のページ分割を最後まで読み、すべての画像・グループを取得する。現行RIGMは60項目。'
        if '先頭50件' in rule else rule) for rule in rules]
write_json('processing/provenance.json',dict(schemaVersion=1,recordType='production-history-data',
    characterName=model['name'],sourceImage='reference/original.png',sourceSha256=sha256(original),
    rigmFile='character/character.rigm',rigmSha256=sha256(rigm),
    counts=dict(editableImages=51,referenceImages=1,groups=8,bones=6,meshes=51),
    method=learning['method'],reusableRules=rules,
    addedSymbols=dict(count=9,method='Code-native vector paths rasterized to transparent PNG at 3x resolution',
        names=[s['name'] for s in new_symbols]),
    verificationScope=dict(previousAssetAnimationPreviews=4,addedSymbolNativePreviews=9,
        audioDrivenVowelTiming='not tested; no audio/LAB file',sourceImagePreserved=True)))
copy_file(source/'prompts.json','processing/image-generation-prompts.json')
copy_file(addition/'verification.json','processing/symbol-enhancement-verification.json')
copy_file(source/'saved-neutral.png','previews/neutral.png')
copy_file(source/'saved-variants-review.png','previews/expression-poses.png')
copy_file(addition/'感情記号9種-キャラクター確認.png','previews/emotion-symbols-9.png')
copy_file(source/'目パチ-口形-確認.gif','previews/blink-mouth.gif')

manifest=dict(format='RIGMMaker.Exchange',schemaVersion=1,status='files-prepared',
    packageId='blonde-android-20261005',createdUtc=datetime.now(timezone.utc).isoformat(),
    character=dict(id=model['documentId'],name=model['name'],canvas=dict(width=model['width'],height=model['height']),
        stages=model['stages']),
    textEncoding='UTF-8 without BOM',pathBase='package-folder',pathSeparator='/',
    png=dict(colorMode='RGBA',alpha='straight',placementOrigin='canvas-top-left',xPositive='right',yPositive='down'),
    render=dict(paintOrder='ascending; larger value overlays smaller',selection='one child per exclusive group',
        excludeReferenceOnly=True),
    counts=dict(editableImages=51,referenceImages=1,imageGroups=8,bones=6,meshes=51,
        expressionPresets=len(expressions),symbolChoices=len(symbol_presets),addedSymbols=9),
    files=dict(character='character/character.rigm',sourceImage='reference/original.png',
        groups='data/groups.json',parts='data/parts.json',rig='data/rig.json',
        currentSelection='data/current-selection.json',expressions='data/expression-presets.json',
        symbols='data/symbol-presets.json',animation='data/animation.json',
        provenance='processing/provenance.json',verification='data/package-verification.json',
        checksums='checksums.sha256',documentation='README.md'),
    outputDirectory='results')
write_json('manifest.json',manifest)

counts_table='\n'.join(f"| {g['name']} | {len(g['partIds'])} | `images/{group_folders[g['name']]}/` |" for g in groups)
group_choices='\n'.join(f"- **{g['name']}**："+'、'.join(part_by_id[i]['label'] for i in g['partIds'])+'。' for g in groups)
example=next(p for p in parts if p['groupName']=='目' and p['label']=='通常')
readme=f'''# RIGMMaker アプリ連携用・作業データ

このフォルダーは「金髪アンドロイド」の分解画像と設定を、これから実装するアプリへ渡すための一時作業用パッケージです。アプリ側では `manifest.json` を入口にして読み込む構成にしています。JSONの形式は今回の受け渡し用として用意した仕様案です。

配置先は Windows がマイドキュメントとして返すフォルダー内の `RIGMMaker/Work/金髪アンドロイド-20261005/` です。この環境では `{package}` に配置しました。

## 置いたファイル

| パス | 内容・用途 |
| --- | --- |
| `manifest.json` | パッケージの入口。キャンバス、件数、座標規則、各設定ファイルの相対パス。 |
| `character/character.rigm` | 感情記号9種追加後の最新版キャラクター。PNGと設定の元になった保存済みデータ。 |
| `reference/original.png` | 元画像。1152×2048、透明背景。通常の合成には使わない比較用。 |
| `images/` | 分解・差分の透過PNG 51枚。下の表の部位別フォルダーに配置。 |
| `data/parts.json` | 全52画像のID、PNGの場所、役割、初期表示、寸法、配置、描画順、親グループ、ボーンID。比較用の元画像1枚を含む。 |
| `data/groups.json` | 8グループのID、名前、候補パーツID、初期選択、排他／固定の区別。 |
| `data/current-selection.json` | 初期表示で使う8グループの選択状態。アプリの読み込み開始時に利用。 |
| `data/rig.json` | 既存の6ボーン、51メッシュ、頂点・三角形・重み、6パラメータ、体リグ。 |
| `data/expression-presets.json` | 通常・喜び・怒り・驚き・疑問・困惑の6組み合わせ。グループIDとパーツIDで選択。 |
| `data/symbol-presets.json` | 感情記号16項目の選択設定。「なし」・既存6記号・追加9記号を含む。 |
| `data/animation.json` | 目パチの通常／半開き／閉じ、口パクの五母音・ん・閉じとパーツIDの対応。瞬きの時刻例。 |
| `processing/provenance.json` | 元画像のハッシュ、加工方法、再利用時の注意、今回の件数と検証範囲。 |
| `processing/image-generation-prompts.json` | 表情やポーズを生成した際の指示文の保存記録。制作資料として扱う。 |
| `processing/symbol-enhancement-verification.json` | 9記号追加時に、既存画像・ボーン・メッシュ・設定を保持したことの検証記録。 |
| `previews/neutral.png` | 初期表示の透過合成見本。 |
| `previews/expression-poses.png` | 表情・顔色・ポーズの組み合わせ見本。 |
| `previews/emotion-symbols-9.png` | 追加した漫画風感情記号9種類の見本。 |
| `previews/blink-mouth.gif` | 目パチと口形の切り替え見本。音声なし。 |
| `data/package-verification.json` | 配置したPNG、ID、相対パス、初期表示、RIGMの一致確認結果。 |
| `checksums.sha256` | 配置ファイルのSHA-256一覧。コピー後の破損や変更を検出するために使用。 |
| `results/` | アプリ側が今後作成する加工画像・処理結果・作業メモの保存先。現時点では空。 |
| `README.md` | この説明。 |

JSON・Markdown・ハッシュ一覧は **UTF-8、BOMなし** です。JSON内のファイル参照は、このREADMEと同じフォルダーを基準にした相対パスで、区切りは `/` です。フォルダーを移動しても画像参照を解決できます。

## 画像の内訳

| グループ | 分解・差分PNG枚数 | 配置先 |
| --- | ---: | --- |
{counts_table}
| 合計 | 51 | 比較用の元画像は別に1枚 |

`images/symbols/original/` に元の記号7項目、`images/symbols/added-9/` に追加9項目を置きました。「なし」は意図した透明PNGです。顔は顔色グループ内の肌素体、髪は前面の髪・機械耳カバーと後ろ髪、体は全身ポーズ差分です。体の差分は胴体と両手足を含む一体画像です。目と眉は左右一組の画像です。

各グループの候補は以下の通りです。

{group_choices}

## アプリ側で最初に読む順序

1. `manifest.json` からキャンバス寸法と設定ファイルの場所を読む。
2. `data/groups.json` と `data/parts.json` を読み、パーツIDから画像と属性を引けるようにする。
3. `data/current-selection.json` の選択状態を適用する。排他グループでは1枚だけ表示し、「後ろ髪」は固定表示する。
4. `referenceOnly=true` を通常表示から除外し、表示中の画像を `paintOrder` の小さい順に合成する。
5. 表情・記号はプリセットの `variants` にある実際の `groupId` / `partId` を使って切り替える。
6. 目パチ・口パクは `data/animation.json` のIDを使って対応グループの選択を切り替える。
7. ボーンとメッシュを使う場合は `data/rig.json` を読む。アプリの出力は `results/` に保存する。

パーツ名の先頭の `*` は既存RIGMにおける差分の目印です。表示名には `label` を使えます。同名の「通常」が部位ごとにあるため、識別と更新には名前だけでなくIDを使います。IDは同梱RIGMと一致しています。

## 配置と描画順の規則

基準キャンバスは **1152×2048 px**。PNGは透明な余白を切り詰めた個別サイズなので、キャンバスの左上へ一律に並べず、`placement.left` と `placement.top` の位置に置きます。PNGの透明部分・半透明の輪郭を保持します。

- `width` / `height`：PNGの実ピクセル寸法。
- `placement.left` / `top`：基準キャンバス左上から測ったPNGの左上位置。右・下が正。
- `placement.centerX` / `centerY`：既存RIGMとボーン・メッシュで使うキャンバス中央基準の画像中心。右・下が正。
- `rotationDegrees`：回転角度。今回の初期値は0。
- `scaleX` / `scaleY`：画像倍率。今回の初期値は1。
- `opacityByte`：0～255の不透明度。今回の画像は255。各PNGのアルファも適用。
- `paintOrder`：小さい順に描く。大きい値が手前。同時に使わない差分にも順序を付与。比較用の元画像は `null`。
- `siblingOrder`：元RIGMの兄弟順序。こちらは0が最も手前なので、初期PNG合成では `paintOrder` を使う。

座標変換は以下です。

```text
left = centerX + 576 - width / 2
top  = centerY + 1024 - height / 2
```

例えば通常の目は `{example['file']}`、サイズ{example['width']}×{example['height']}、左上({example['placement']['left']:g}, {example['placement']['top']:g})、RIGM中心({example['placement']['centerX']:g}, {example['placement']['centerY']:g})です。

グループの後ろから手前への並びは **体 → 後ろ髪 → 顔色 → 眉 → 目 → 口 → 髪 → 感情記号** です。髪と顔色を重ねることで、顔の肌・目・口を表示します。

## 表情・目パチ・口パク・記号

表情プリセットを適用する際は、指定されたグループだけをその候補へ切り替えます。記号のみのプリセットでは感情記号グループだけを切り替えます。初期記号は「なし」です。記号は頭のボーンに結び付けてあります。

目パチの例は **通常 → 半開き → 閉じ → 半開き → 通常**。`animation.json` の80ms/100ms/80ms、間隔4000msはアプリ実装用の例で、既存アプリの動作時刻を再現する保証値ではありません。「笑顔閉じ」「見開き」「やさしい目」は表情の固定選択として扱えます。

口形は `a=あ、i=い、u=う、e=え、o=お、N=ん、closed=閉じ` です。音声やLAB時刻ファイルはこの作業フォルダーに含まれていないので、音声に合わせる時刻はアプリ側で与える構成です。GIFは形の切り替え確認用です。

## 制作記録と確認結果

51枚の分解・差分PNGと元画像1枚のRGBAは、最新版RIGMに格納した画素と一致しています。配置、グループとIDの関係、プリセットの参照、初期選択、6ボーンと51メッシュ、コピーしたファイルの一致を確認しました。

通常の目・口、自動まばたきは前の素材制作時に4枚のアプリ描画で確認し、追加した9記号はその後のアプリ描画9枚で確認しています。今回はファイルの配置と整合性確認を行いました。

顔の補完・表情・ポーズには生成画像が含まれます。顔の分解結果と生成ポーズは原画の全画素一致を意味せず、元画像そのものは `reference/original.png` に保持しています。加工方法は `processing/provenance.json` に記録しました。

`processing/` 内の生成指示文や作業規則は、制作経緯を理解するための保存データです。アプリ連携ファイルの読み込みに必要な仕様は、このREADMEと `manifest.json` / `data/` に記載しています。
'''
(package/'README.md').write_text(readme,encoding='utf-8')

# Read-only integrity checks on the actual staged files.
checks={
    'latest_rigm_copy_exact':sha256(package/'character/character.rigm')==sha256(rigm),
    'original_image_copy_exact':sha256(package/'reference/original.png')==sha256(original),
    'all_52_png_rgba_equal_rigm':copied_pixels,
    '51_editable_images_and_1_reference':len(parts)==52 and sum(not p['referenceOnly'] for p in parts)==51,
    'all_part_files_present':all((package/p['file']).is_file() for p in parts),
    'all_png_sizes_equal_metadata':all(Image.open(package/p['file']).size==(p['width'],p['height']) for p in parts),
    'all_ids_unique':len(part_by_id)==len(parts) and len({g['id'] for g in groups})==8,
    'one_default_selection_per_group':all(sum(part_by_id[i]['defaultVisible'] for i in g['partIds'])==1 for g in groups),
    'all_group_part_links_valid':all(part_by_id[i]['groupId']==g['id'] for g in groups for i in g['partIds']),
    'all_preset_links_valid':all(v['partId'] in part_by_id and part_by_id[v['partId']]['groupId']==v['groupId']
        for preset in list(expressions.values())+symbol_presets for v in preset['variants']),
    'paint_order_unique_and_complete':sorted(p['paintOrder'] for p in parts if not p['referenceOnly'])==list(range(51)),
    'all_coordinates_match_png_dimensions':all(p['placement']['left']==p['placement']['centerX']+576-p['width']/2
        and p['placement']['top']==p['placement']['centerY']+1024-p['height']/2 for p in parts),
    'rig_references_valid':len(model['bones'])==6 and len(model['meshes'])==51 and
        all(mesh['partId'] in part_by_id for mesh in model['meshes']) and
        all(v['weights'] and all(w['boneId'] in {b['id'] for b in model['bones']} for w in v['weights']) for mesh in model['meshes'] for v in mesh['vertices']),
    'manifest_references_exist':all((package/path).is_file() for key,path in manifest['files'].items() if key not in {'verification','checksums'}),
    'results_directory_empty':not any((package/'results').iterdir())
}
write_json('data/package-verification.json',dict(passed=all(checks.values()),checks=checks,counts=manifest['counts'],
    status='file-placement-verified',applicationRunForThisPlacement=False))
assert all(checks.values()),checks
hash_entries=[]
for file in sorted(package.rglob('*')):
    if file.is_file():hash_entries.append(f'{sha256(file)}  {file.relative_to(package).as_posix()}')
(package/'checksums.sha256').write_text('\n'.join(hash_entries)+'\n',encoding='utf-8')
for line in hash_entries:
    digest,relative=line.split('  ',1)
    assert sha256(package/relative)==digest
assert all((package/relative).is_file() for relative in manifest['files'].values())
work_readme=work/'README.md'
if not work_readme.exists():
    work_readme.write_text('''# RIGMMaker アプリ連携の作業用フォルダー

このフォルダーは、分解画像と設定をアプリへ渡す一時作業領域です。キャラクターごとに子フォルダーを作り、各子フォルダーの `manifest.json` を読み込みの入口にします。

- [金髪アンドロイドのファイル説明](金髪アンドロイド-20261005/README.md)
- `金髪アンドロイド-20261005/manifest.json`：51枚の分解・差分、元画像、配置と差分設定。
- `金髪アンドロイド-20261005/results/`：今後アプリが保存する処理結果用の空フォルダー。

詳細は各パッケージのREADMEを参照してください。
''',encoding='utf-8')
summary=dict(package=str(package),documentation=str(package/'README.md'),manifest=str(package/'manifest.json'),
    files=sum(p.is_file() for p in package.rglob('*')),pngs=sum(p.suffix.lower()=='.png' for p in package.rglob('*') if p.is_file()),
    editableImages=51,referenceImages=1,verified=True,bytes=sum(p.stat().st_size for p in package.rglob('*') if p.is_file()))
(source/'work-folder-placement.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(summary,ensure_ascii=True))
