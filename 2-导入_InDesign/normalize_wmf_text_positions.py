"""Make WMF current-position text explicit for importers that ignore TA_UPDATECP advances."""
from __future__ import annotations

import json
import string
import struct
import sys
from pathlib import Path
from typing import NamedTuple, TypedDict


class Font(NamedTuple):
    charset: int
    name: bytes

    @property
    def transcode(self) -> bool:
        return self.charset == 128 and self.name.replace(b' ', b'').lower() == b'notosanssc'


class GreekRepair(TypedDict):
    token: str
    text: str
    fontFamily: str
    count: int


def _normalize(data: bytes, repair_greek: bool) -> tuple[bytes, int, list[GreekRepair]]:
    header = 22 if data[:4] == bytes.fromhex('d7cdc69a') else 0
    offset = header + 18
    parts = [data[:offset]]
    current = None
    explicit = False
    update = False
    inserted = 0
    objects: dict[int, Font | None] = {}
    selected_font: Font | None = None
    saved_fonts: list[Font | None] = []
    occupied: set[int] = set()
    greek_runs: list[tuple[int, int, bytes, str]] = []
    while offset + 6 <= len(data):
        words, function = struct.unpack_from('<IH', data, offset)
        if words < 3 or offset + words * 2 > len(data):
            raise ValueError('Invalid WMF record')
        record = data[offset:offset + words * 2]
        payload = record[6:]
        if function in (0x02fb, 0x02fa, 0x02fc, 0x06ff, 0x00f7, 0x02fd, 0x0142):
            slot = next(i for i in range(len(objects) + 1) if i not in objects)
            font = Font(payload[13], payload[18:].split(b'\0')[0]) if function == 0x02fb else None
            objects[slot] = font
            if font and font.transcode:
                payload = bytearray(payload)
                payload[13] = 134
                payload[18:50] = b'SimSun'.ljust(32, b'\0')
                record = struct.pack('<IH', (6 + len(payload)) // 2, function) + payload
        elif function == 0x01f0:
            objects.pop(struct.unpack_from('<H', payload)[0], None)
        elif function == 0x012d:
            index = struct.unpack_from('<H', payload)[0]
            selected = objects.get(index)
            if selected:
                selected_font = selected
            elif repair_greek and index in (0x800a, 0x800b, 0x800c, 0x800d, 0x800e, 0x8010, 0x8011):
                selected_font = None
        elif repair_greek and function == 0x001e:
            saved_fonts.append(selected_font)
        elif repair_greek and function == 0x0127:
            index = struct.unpack_from('<h', payload)[0]
            restore = len(saved_fonts) + index if index < 0 else index - 1
            if not 0 <= restore < len(saved_fonts):
                raise ValueError('Invalid WMF saved font state')
            selected_font = saved_fonts[restore]
            del saved_fonts[restore:]
        if function == 0x0a32 and selected_font and selected_font.transcode:
            y, x, count, options = struct.unpack_from('<hhHH', payload)
            start = 8 + (8 if options & 6 else 0)
            text = payload[start:start + count]
            converted = text.decode('cp932').encode('gbk')
            if len(converted) != len(text):
                raise ValueError('WMF charset conversion changes text advance count')
            payload = payload[:start] + converted + payload[start + count:]
            record = struct.pack('<IH', (6 + len(payload)) // 2, function) + payload
        if function == 0x012e:
            update = bool(struct.unpack_from('<H', payload)[0] & 1)
        elif function == 0x0214:
            current = struct.unpack_from('<hh', payload)
            explicit = True
        elif function == 0x0a32 and update:
            y, x, count, options = struct.unpack_from('<hhHH', payload)
            if current is not None and not explicit:
                parts.append(struct.pack('<IHhh', 5, 0x0214, current[0], current[1]))
                inserted += 1
            start = 8 + (8 if options & 6 else 0)
            dx_offset = start + ((count + 1) // 2) * 2
            dx = payload[dx_offset:]
            if current is not None and len(dx) >= count * 2:
                advances = struct.unpack_from('<' + 'h' * count, dx)
                current = (current[0], current[1] + sum(advances))
            else:
                current = None
            explicit = False
        if repair_greek and function in (0x0a32, 0x0521):
            if function == 0x0a32:
                _, _, count, options = struct.unpack_from('<hhHH', payload)
                start = 8 + (8 if options & 6 else 0)
            else:
                count = struct.unpack_from('<H', payload)[0]
                options = 0
                start = 2
            text = payload[start:start + count]
            if len(text) != count:
                raise ValueError('Truncated WMF text record')
            occupied.update(text)
            if selected_font and selected_font.charset == 161 and any(value >= 128 for value in text):
                if options & 0x0010:
                    raise ValueError('WMF Greek glyph-index records cannot be decoded as text')
                family = selected_font.name.decode('cp1253').strip()
                if not family:
                    raise ValueError('WMF Greek text requires a named font')
                greek_runs.append((len(parts), start + 6, text, family))
        parts.append(record)
        offset += words * 2
        if function == 0:
            break
    repairs = _apply_greek_tokens(parts, greek_runs, occupied)
    result = bytearray(b''.join(parts))
    struct.pack_into('<I', result, header + 6, (len(result) - header) // 2)
    return bytes(result), inserted, repairs


def _apply_greek_tokens(
    parts: list[bytes],
    runs: list[tuple[int, int, bytes, str]],
    occupied: set[int],
) -> list[GreekRepair]:
    """Keep WMF text byte counts and advance arrays intact for Illustrator import."""
    tokens = iter(value for value in (string.ascii_letters + string.digits).encode() if value not in occupied)
    repairs: dict[tuple[str, int], GreekRepair] = {}
    for index, start, text, family in runs:
        replacement = bytearray(text)
        for offset, value in enumerate(text):
            if value < 128:
                continue
            key = (family, value)
            if key not in repairs:
                token = next(tokens, None)
                if token is None:
                    raise ValueError('WMF Greek import has no unused single-byte placeholders')
                repairs[key] = {'token': chr(token), 'text': bytes([value]).decode('cp1253'),
                                'fontFamily': family, 'count': 0}
            repair = repairs[key]
            repair['count'] += 1
            replacement[offset] = ord(repair['token'])
        record = parts[index]
        parts[index] = record[:start] + replacement + record[start + len(text):]
    return list(repairs.values())


def normalize(data: bytes) -> tuple[bytes, int]:
    """Normalize WMF text positions without the Illustrator Greek import workaround."""
    normalized, inserted, _ = _normalize(data, repair_greek=False)
    return normalized, inserted


def normalize_for_import(data: bytes) -> tuple[bytes, int, list[GreekRepair]]:
    """Normalize WMF and return the source-bound Greek replacements for Illustrator."""
    return _normalize(data, repair_greek=True)


if __name__ == '__main__':
    source, output = map(Path, sys.argv[1:3])
    if source.resolve() == output.resolve() or output.exists():
        raise ValueError('Output must be a new derivative file')
    if sys.argv[3:] not in ([], ['--greek-import']):
        raise ValueError('Unknown WMF normalization option')
    data, inserted, repairs = _normalize(source.read_bytes(), repair_greek=bool(sys.argv[3:]))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    print(json.dumps({'insertedExplicitPositions': inserted, 'output': str(output),
                      'greekRepairs': repairs}, ensure_ascii=True))
