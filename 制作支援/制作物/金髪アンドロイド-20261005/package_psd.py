"""Package unmodified PNG channels into a simple RGBA PSD for native app import."""
from pathlib import Path
from PIL import Image
import struct, sys

def h(v): return struct.pack('>H', v)
def u(v): return struct.pack('>I', v)
def s(v): return struct.pack('>h', v)
def package(src, dst):
    im = Image.open(src).convert('RGBA')
    w, height = im.size
    channels = [c.tobytes() for c in im.split()]
    name = b'original'
    pascal = bytes([len(name)]) + name
    pascal += b'\0' * (-len(pascal) % 4)
    extra = u(0) + u(0) + pascal
    record = struct.pack('>iiii', 0, 0, height, w) + h(4)
    for cid in [0, 1, 2, -1]: record += s(cid) + u(w * height + 2)
    record += b'8BIMnorm' + bytes([255, 0, 0, 0]) + u(len(extra)) + extra
    layer = s(-1) + record + b''.join(h(0) + c for c in channels)
    layer += b'\0' * (len(layer) % 2)
    section = u(len(layer)) + layer + u(0)
    header = b'8BPS' + h(1) + b'\0' * 6 + h(4) + u(height) + u(w) + h(8) + h(3)
    Path(dst).write_bytes(header + u(0) + u(0) + u(len(section)) + section + h(0) + b''.join(channels))

if __name__ == '__main__': package(sys.argv[1], sys.argv[2])
