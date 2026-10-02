"""Read-only verification of saved PSD pixels and rendering of review contact sheets."""
import hashlib
import json
import math
import sys
from collections import Counter
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1] / 'Analysis'))
from inspect_psd import Reader, channel, inspect


def load_json(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8-sig'))


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def read_layers(path):
    info = inspect(path, ROOT, ROOT)
    assert not info['warnings'], info['warnings']
    images = {}
    with path.open('rb') as f:
        for layer in info['layers']:
            if layer['section_type']:
                continue
            t, l, b, r = layer['rect']
            size = (r-l, b-t)
            planes = {}
            for c in layer['channels']:
                f.seek(c['offset'])
                _, raw = channel(Reader(f, c['end']), *size, 8, True)
                planes[c['id']] = Image.frombytes('L', size, raw)
            assert layer['name'] not in images
            images[layer['name']] = (layer, Image.merge('RGBA', [planes[c] for c in (0, 1, 2, -1)]))
    return info, images


def place(canvas, pair):
    layer, image = pair
    t, l, b, r = layer['rect']
    canvas.alpha_composite(image, (l, t))


def render(base, layers, names):
    canvas = base.copy()
    for name in names:
        place(canvas, layers[name])
    return canvas


def contact_sheet(filename, items, base, after, defaults, title):
    columns, cell_w, cell_h = 3, 400, 370
    title_h = 45
    sheet = Image.new('RGB', (columns*cell_w, title_h + math.ceil(len(items)/columns)*cell_h), (228, 230, 232))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc', 19)
    draw.text((12, 9), title, font=font, fill=(25, 25, 25))
    for i, (label, names) in enumerate(items):
        canvas = render(base, after, names)
        crop = canvas.crop((270, 120, 470, 285)).resize((400, 330), Image.Resampling.NEAREST)
        x, y = (i % columns)*cell_w, title_h + (i // columns)*cell_h
        tile = Image.new('RGBA', crop.size, (215, 218, 223, 255))
        tile.alpha_composite(crop)
        sheet.paste(tile.convert('RGB'), (x, y+36))
        draw.text((x+12, y+5), label, font=font, fill=(25, 25, 25))
    sheet.save(ROOT / filename)


def main():
    path = ROOT / 'blonde_expressions_review.psd'
    before_info, before = read_layers(ROOT / 'before-expressions.psd')
    info, after = read_layers(path)
    assert len(before) == 5 and len(after) == 29
    assert info['header']['width'] == 752 and info['header']['height'] == 1344
    assert sum(x['section_type'] in (1, 2) for x in info['layers']) == 4
    archive_names = ['口（原画画素）', '両眉（原画画素）', '両目（原画画素）']
    base_name = 'ベース（背景透過・目眉口補完）'
    unchanged = []
    for name, (layer, pixels) in before.items():
        new_layer, new_pixels = after[name]
        assert new_pixels.tobytes() == pixels.tobytes(), name
        for key in ('rect', 'opacity', 'blend', 'clipping', 'mask'):
            assert layer[key] == new_layer[key], (name, key)
        if name in archive_names:
            assert layer['visible'] and not new_layer['visible']
        else:
            assert layer['visible'] == new_layer['visible']
        unchanged.append(name)
    assert not after['元画像（比較用・原寸）'][0]['visible']
    manifest = load_json('manifest.json')
    details = []
    for item in manifest:
        layer, actual = after[item['name']]
        bounds = item['bounds']
        assert layer['rect'] == [bounds[k] for k in ('top', 'left', 'bottom', 'right')]
        assert layer['visible'] == item['visible']
        assert layer['opacity'] == 255 and layer['blend'] == 'norm' and not layer['clipping'] and layer['mask']['length'] == 0
        prepared = Image.open(ROOT / item['file']).convert('RGBA')
        assert actual.size == prepared.size
        diff = ImageChops.difference(prepared, actual)
        maxima = [b for a, b in diff.getextrema()]
        if item['original']:
            assert actual.tobytes() == prepared.tobytes(), item['name']
        else:
            # Independent C# area resize and Delphi separable area resize can differ
            # by one byte because their floating-point accumulation orders differ.
            assert max(maxima) <= 1, (item['name'], maxima)
        alpha = actual.getchannel('A')
        assert alpha.getextrema()[0] == 0 and alpha.getbbox() is not None
        details.append({'name': item['name'], 'original': item['original'], 'bounds': bounds,
                        'size': list(actual.size), 'alpha_range': alpha.getextrema(),
                        'nonzero_alpha_pixels': sum(v for k, v in Counter(alpha.get_flattened_data()).items() if k),
                        'prepared_vs_saved_max_rgba_difference': maxima})

    defaults = {'mouths': '*00 口（原画）', 'brows': '*00 両眉（原画）', 'eyes': '*00 両目（原画）'}
    ordered_kinds = ['mouths', 'brows', 'eyes']
    originals = [defaults[k] for k in ordered_kinds]
    base = after[base_name][1]
    before_composite = render(before[base_name][1], before, archive_names)
    composite = render(base, after, originals)
    assert composite.tobytes() == before_composite.tobytes(), 'Original expression composite changed'
    merged = Image.open(path).convert('RGBA')
    assert merged.getchannel('A').tobytes() == base.getchannel('A').tobytes()
    max_diff, changed = 0, 0
    for a, b in zip(composite.get_flattened_data(), merged.get_flattened_data()):
        expected = tuple((c*a[3] + 255*(255-a[3]) + 127)//255 for c in a[:3]) + (a[3],)
        difference = max(abs(x-y) for x, y in zip(expected, b))
        max_diff = max(max_diff, difference)
        changed += difference != 0
    assert max_diff <= 1, max_diff
    background_checks = []
    for item in manifest:
        if item['original']:
            continue
        names = [item['name'] if k == item['kind'] else defaults[k] for k in ordered_kinds]
        rendered = render(base, after, names)
        assert rendered.getchannel('A').tobytes() == base.getchannel('A').tobytes(), item['name']
        # Every newly drawn part is inside the face; the rest of the character is preserved.
        assert rendered.crop((0, 285, 752, 1344)).tobytes() == composite.crop((0, 285, 752, 1344)).tobytes()
        background_checks.append(item['name'])

    for kind in ('mouths', 'eyes', 'brows'):
        items = [(i['name'].lstrip('*'), [i['name'] if k == kind else defaults[k] for k in ordered_kinds])
                 for i in manifest if i['kind'] == kind]
        title = {'mouths': '保存PSD：口の差分', 'eyes': '保存PSD：目の差分', 'brows': '保存PSD：眉の差分'}[kind]
        contact_sheet(kind+'-review.png', items, base, after, defaults, title)
    combinations = [
        ('原画', originals),
        ('微笑む', ['*01 口 閉じ', '*01 両眉 喜', '*00 両目（原画）']),
        ('笑う', ['*04 口 あ', '*04 両眉 楽', '*03 両目 笑顔閉じ']),
        ('驚く', ['*08 口 お', '*01 両眉 喜', '*05 両目 見開き']),
        ('怒る', ['*04 口 あ', '*02 両眉 怒', '*00 両目（原画）']),
        ('悲しい', ['*09 口 ん', '*03 両眉 哀', '*02 両目 少し伏せる']),
        ('困る', ['*02 口 半開き', '*05 両眉 困る', '*04 両目 ほぼ閉じ']),
        ('閉じ目', ['*01 口 閉じ', '*00 両眉（原画）', '*01 両目 閉じ']),
        ('片眉上げ', ['*06 口 う', '*06 両眉 画面左上げ', '*00 両目（原画）']),
    ]
    contact_sheet('expressions-overview.png', combinations, base, after, defaults, '保存PSD：表情の組み合わせ例')
    composite.save(ROOT / 'saved-composite.png')
    checker = Image.new('RGBA', composite.size)
    pixels = checker.load()
    for y in range(checker.height):
        for x in range(checker.width):
            shade = 210 if (x//20 + y//20) % 2 else 160
            pixels[x, y] = (shade, shade, shade, 255)
    checker.alpha_composite(composite)
    checker.save(ROOT / 'saved-checker-preview.png')
    dark = Image.new('RGBA', composite.size, (40, 60, 90, 255))
    dark.alpha_composite(composite)
    dark.save(ROOT / 'saved-dark-preview.png')
    status = load_json('saved-status.json')
    assert status['ok'] and not status['data']['modified'] and not status['data']['busy']
    managed = Path(status['data']['fileName'])
    assert sha(managed) == sha(path)
    selection = load_json('selection-verification.json')
    assert selection['result'] == 'passed' and selection['selectionCount'] == 24 and selection['originalRestored']
    counts = Counter(base.getchannel('A').get_flattened_data())
    samples = {name: composite.getpixel(xy) for name, xy in {'background': (20, 500), 'leg_gap': (373, 1000),
               'dress': (370, 570), 'sock': (317, 1170), 'shoe': (323, 1270)}.items()}
    assert samples['background'][3] == samples['leg_gap'][3] == 0
    assert all(samples[name][3] == 255 for name in ('dress', 'sock', 'shoe'))
    report = {'result': 'passed', 'canvas': [752, 1344], 'images': 29, 'groups': 4,
              'generated_states': {'mouths': 9, 'eyes': 5, 'brows': 7}, 'original_copies': 3,
              'saved_psd': str(path), 'managed_psd': str(managed), 'sha256': sha(path),
              'all_five_existing_layers_rgba_and_nonvisibility_attributes_unchanged': unchanged,
              'original_composite_exactly_unchanged': True, 'originals_hidden_except_selected_copies': True,
              'all_21_variants_preserve_background_alpha_and_body': background_checks,
              'merged_alpha_matches_base': True, 'merged_rgb_uses_white_matte': True,
              'merged_white_matte_max_difference': max_diff, 'merged_white_matte_pixel_differences': changed,
              'transparent_pixels': counts[0], 'opaque_pixels': counts[255],
              'partial_alpha_pixels': sum(v for k, v in counts.items() if 0 < k < 255), 'sample_rgba': samples,
              'exclusive_selections_passed': 24, 'final_state': 'original expression',
              'saved_and_not_busy': True, 'quality_status': 'review version; user visual acceptance pending',
              'parts': details}
    (ROOT / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    (ROOT / 'psd-structure.json').write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'parts' and not isinstance(v, list)}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
