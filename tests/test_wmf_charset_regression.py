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

    def test_greek_placeholder_keeps_source_bytes_and_advances_distinct(self):
        greek = bytearray(50)
        greek[13] = 161
        greek[18:50] = b'Times New Roman'.ljust(32, b'\0')
        ansi = bytearray(greek)
        ansi[13] = 0
        adv = struct.pack('<h', 67)
        text = struct.pack('<hhHH', 12, 34, 1, 0) + b'\xd3\0' + adv
        records = (record(0x02fb, greek) + record(0x02fb, ansi)
                   + record(0x012d, struct.pack('<H', 0)) + record(0x0a32, text)
                   + record(0x012d, struct.pack('<H', 1)) + record(0x0a32, text)
                   + record(0))
        header = struct.pack('<HHHIHIH', 1, 9, 0x300, (18 + len(records)) // 2, 2, 28, 0)
        original = header + records
        output, inserted, repairs = module.normalize_for_import(original)
        self.assertEqual(inserted, 0)
        self.assertEqual(len(repairs), 1)
        repair = repairs[0]
        self.assertEqual(repair['text'], '\u03a3')
        self.assertEqual(repair['fontFamily'], 'Times New Roman')
        self.assertEqual(repair['count'], 1)
        text_offset = 18 + 2 * 56 + 8 + 6 + 8
        self.assertEqual(output, original[:text_offset] + repair['token'].encode('ascii')
                         + original[text_offset + 1:])
        self.assertEqual(module.normalize(original)[0], original)


if __name__ == '__main__':
    unittest.main()
