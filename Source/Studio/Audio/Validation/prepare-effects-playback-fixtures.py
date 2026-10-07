from pathlib import Path
import hashlib, json, struct, sys, wave

output = Path(sys.argv[1]).resolve()
root = output / 'fixtures'
if '--verify' in sys.argv[2:]:
    snapshot = json.loads((output / 'before-sha256.json').read_text(encoding='utf-8'))
    for path, expected in snapshot.items():
        actual = hashlib.sha256(Path('\\\\?\\' + path).read_bytes()).hexdigest()
        if actual != expected:
            raise AssertionError(f'Fixture changed: {path}')
    print(f'Unchanged fixture SHA256: {len(snapshot)} files.')
    raise SystemExit(0)
root.mkdir(parents=True, exist_ok=True)
def io_path(p):
    return Path('\\\\?\\' + str(p))
paths = [root / 'plain.wav', root / '\u65e5\u672c\u8a9e \u97f3\u58f0\u7d20\u6750.wav']
for target_length in (129, 180, 240):
    name = '\u65e5\u672c\u8a9e \u7a7a\u767d \u97f3\u58f0_' + str(target_length) + '_'
    padding = target_length - len(str(root)) - 1 - len(name) - 4
    paths.append(root / (name + 'x' * padding + '.wav'))
long_dir = root
for i in range(5):
    long_dir /= f'\u9577\u3044\u65e5\u672c\u8a9e\u30d5\u30a9\u30eb\u30c0 \u7a7a\u767d\u4ed8\u304d_{i}_' + 'x' * 28
io_path(long_dir).mkdir(parents=True, exist_ok=True)
paths.append(long_dir / '\u9078\u629e\u3057\u305f\u53f0\u8a5e \u8a66\u8074\u306e\u30c6\u30b9\u30c8.wav')
# Silent PCM16 avoids changing system volume or disturbing existing user playback.
for i, p in enumerate(paths):
    with wave.open(str(io_path(p)), 'wb') as w:
        channels = 2 if i == len(paths) - 1 else 1
        w.setparams((channels, 2, 48000, 0, 'NONE', 'not compressed'))
        w.writeframes(b'\0' * (48000 * channels * 2))
good = io_path(paths[0]).read_bytes()
invalid = []
def bad(name, content):
    p = root / (name + '.wav')
    io_path(p).write_bytes(content)
    invalid.append({'name': name, 'path': str(p)})
bad('truncated', good[:40])
bad('truncated-data', good[:-2])
bad('not-riff', b'NOPE' + good[4:])
bad('float-format', good[:20] + struct.pack('<H', 3) + good[22:])
bad('wrong-align', good[:32] + struct.pack('<H', 4) + good[34:])
bad('zero-align', good[:32] + struct.pack('<H', 0) + good[34:])
bad('wrong-rate', good[:28] + struct.pack('<I', 1) + good[32:])
bad('no-data', good[:36] + b'JUNK' + good[40:])
duplicate_data = good + b'data' + struct.pack('<I', 2) + b'\0\0'
duplicate_data = duplicate_data[:4] + struct.pack('<I', len(duplicate_data)-8) + duplicate_data[8:]
bad('duplicate-data', duplicate_data)
bad('empty-data', good[:4] + struct.pack('<I', 36) + good[8:40] + struct.pack('<I', 0))
bad('non-pcm16', good[:34] + struct.pack('<H', 8) + good[36:])
invalid.append({'name': 'missing', 'path': str(root / 'missing.wav')})
manifest = {'valid': [{'path': str(p), 'duration': 1.0} for p in paths], 'invalid': invalid}
(root.parent / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
files = paths + [Path(c['path']) for c in invalid if c['name'] != 'missing']
snapshot = {str(p): hashlib.sha256(io_path(p).read_bytes()).hexdigest() for p in files}
(root.parent / 'before-sha256.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding='utf-8')
print('Created isolated fixtures; valid path lengths:', [len(str(p)) for p in paths])
