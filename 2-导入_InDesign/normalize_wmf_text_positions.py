"""Make WMF current-position text explicit for importers that ignore TA_UPDATECP advances."""
import json
import struct
import sys
from pathlib import Path


def normalize(data):
    header = 22 if data[:4] == bytes.fromhex('d7cdc69a') else 0
    offset = header + 18
    parts = [data[:offset]]
    current = None
    explicit = False
    update = False
    inserted = 0
    objects = {}
    selected_font = None
    while offset + 6 <= len(data):
        words, function = struct.unpack_from('<IH', data, offset)
        if words < 3 or offset + words * 2 > len(data):
            raise ValueError('Invalid WMF record')
        record = data[offset:offset + words * 2]
        payload = record[6:]
        if function in (0x02fb, 0x02fa, 0x02fc, 0x06ff, 0x00f7, 0x02fd, 0x0142):
            slot = next(i for i in range(len(objects) + 1) if i not in objects)
            transcode = function == 0x02fb and payload[13] == 128 and payload[18:].split(b'\0')[0].replace(b' ', b'').lower() == b'notosanssc'
            objects[slot] = {'font': function == 0x02fb, 'transcode': transcode}
            if transcode:
                payload = bytearray(payload)
                payload[13] = 134
                payload[18:50] = b'SimSun'.ljust(32, b'\0')
                record = struct.pack('<IH', (6 + len(payload)) // 2, function) + payload
        elif function == 0x01f0:
            objects.pop(struct.unpack_from('<H', payload)[0], None)
        elif function == 0x012d:
            selected = objects.get(struct.unpack_from('<H', payload)[0])
            if selected and selected['font']:
                selected_font = selected
        if function == 0x0a32 and selected_font and selected_font['transcode']:
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
        parts.append(record)
        offset += words * 2
        if function == 0:
            break
    result = bytearray(b''.join(parts))
    struct.pack_into('<I', result, header + 6, (len(result) - header) // 2)
    return bytes(result), inserted


if __name__ == '__main__':
    source, output = map(Path, sys.argv[1:3])
    if source.resolve() == output.resolve() or output.exists():
        raise ValueError('Output must be a new derivative file')
    data, inserted = normalize(source.read_bytes())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    print(json.dumps({'insertedExplicitPositions': inserted, 'output': str(output)}, ensure_ascii=True))
