"""Minimal .glb reading and writing shared by the textured-kit tools. Stdlib only.

Handles what the kit writes: one JSON chunk, one BIN chunk, float/unsigned accessors.
"""
import json
import struct
from pathlib import Path

MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
COMPONENTS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
COMPONENT_BYTES = {5126: 4, 5125: 4, 5123: 2, 5121: 1}


def read(path):
    """(gltf dict, binary chunk bytes) for a .glb, rejecting anything malformed."""
    raw = Path(path).read_bytes()
    if len(raw) < 12:
        raise ValueError(f'{path}: too short for a .glb')
    magic, version, length = struct.unpack_from('<III', raw, 0)
    if magic != MAGIC or version != 2 or length != len(raw):
        raise ValueError(f'{path}: bad .glb header')
    gltf, binary, offset = None, b'', 12
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        chunk = raw[offset + 8:offset + 8 + size]
        if len(chunk) != size:
            raise ValueError(f'{path}: chunk runs past the end of the file')
        if kind == JSON_CHUNK:
            gltf = json.loads(chunk)
        elif kind == BIN_CHUNK:
            binary = chunk
        offset += 8 + size
    if gltf is None:
        raise ValueError(f'{path}: no JSON chunk')
    return gltf, binary


def view_bytes(gltf, binary, index):
    view = gltf['bufferViews'][index]
    start = view.get('byteOffset', 0)
    data = binary[start:start + view['byteLength']]
    if len(data) != view['byteLength']:
        raise ValueError(f'bufferView {index} runs past the binary chunk')
    return data


def accessor_bytes(gltf, binary, index):
    """The tightly packed bytes of one accessor."""
    accessor = gltf['accessors'][index]
    view = gltf['bufferViews'][accessor['bufferView']]
    size = COMPONENT_BYTES[accessor['componentType']] * COMPONENTS[accessor['type']]
    stride = view.get('byteStride', size)
    base = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    if stride == size:
        data = binary[base:base + size * accessor['count']]
    else:
        data = b''.join(binary[base + i * stride:base + i * stride + size]
                        for i in range(accessor['count']))
    if len(data) != size * accessor['count']:
        raise ValueError(f'accessor {index} runs past the binary chunk')
    return data


class Writer:
    """Accumulates one binary buffer and the views/accessors that point into it."""

    def __init__(self):
        self.binary = bytearray()
        self.views = []
        self.accessors = []

    def view(self, data, target=None):
        self.binary += b'\0' * (-len(self.binary) % 4)
        entry = {'buffer': 0, 'byteOffset': len(self.binary), 'byteLength': len(data)}
        if target:
            entry['target'] = target
        self.binary += data
        self.views.append(entry)
        return len(self.views) - 1

    def floats(self, data, kind, bounds=False):
        """An accessor over already-packed little-endian float32 bytes."""
        per = COMPONENTS[kind]
        count = len(data) // (4 * per)
        accessor = {'bufferView': self.view(data, 34962), 'componentType': 5126,
                    'count': count, 'type': kind}
        if bounds:
            values = struct.unpack(f'<{count * per}f', data)
            accessor['min'] = [min(values[i::per]) for i in range(per)]
            accessor['max'] = [max(values[i::per]) for i in range(per)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def glb(self, gltf):
        gltf['buffers'] = [{'byteLength': len(self.binary)}]
        gltf['bufferViews'] = self.views
        gltf['accessors'] = self.accessors
        text = json.dumps(gltf, separators=(',', ':')).encode()
        text += b' ' * (-len(text) % 4)
        binary = bytes(self.binary) + b'\0' * (-len(self.binary) % 4)
        total = 12 + 8 + len(text) + 8 + len(binary)
        return (struct.pack('<III', MAGIC, 2, total)
                + struct.pack('<II', len(text), JSON_CHUNK) + text
                + struct.pack('<II', len(binary), BIN_CHUNK) + binary)
