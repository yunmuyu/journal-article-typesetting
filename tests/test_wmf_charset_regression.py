import importlib.util
import os
import struct
import unittest
from pathlib import Path

source = Path(os.environ.get('WMF_NORMALIZER_OVERRIDE', Path(__file__).resolve().parents[1] / '2-导入_InDesign/normalize_wmf_text_positions.py'))
spec = importlib.util.spec_from_file_location('wmf_normalizer', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def record(function, payload=b''):
    return struct.pack('<IH', 3 + len(payload) // 2, function) + payload


class CharsetRegression(unittest.TestCase):
    def test_shift_jis_noto_comparison_is_transcoded_with_font(self):
        font = bytearray(50)
        font[13] = 128
        font[18:50] = b'Noto Sans SC'.ljust(32, b'\0')
        text = struct.pack('<hhHH', 0, 0, 2, 0) + bytes.fromhex('8184') + struct.pack('<hh', 10, 0)
        records = record(0x02fb, font) + record(0x012d, struct.pack('<H', 0)) + record(0x0a32, text) + record(0)
        header = struct.pack('<HHHIHIH', 1, 9, 0x300, (18 + len(records)) // 2, 1, 28, 0)
        output, inserted = module.normalize(header + records)
        self.assertEqual(output[18 + 6 + 13], 134)
        self.assertEqual(output[18 + 6 + 18:18 + 6 + 50].split(b'\0')[0], b'SimSun')
        text_offset = 18 + 56 + 8 + 6 + 8
        self.assertEqual(output[text_offset:text_offset + 2].decode('gbk'), '＞')
        self.assertEqual(inserted, 0)
        self.assertEqual(struct.unpack_from('<I', output, 6)[0] * 2, len(output))

    def test_other_ansi_fonts_are_not_transcoded(self):
        font = bytearray(50)
        font[18:50] = b'Times New Roman'.ljust(32, b'\0')
        records = record(0x02fb, font) + record(0)
        header = struct.pack('<HHHIHIH', 1, 9, 0x300, (18 + len(records)) // 2, 1, 28, 0)
        data = header + records
        self.assertEqual(module.normalize(data)[0], data)


if __name__ == '__main__':
    unittest.main()
