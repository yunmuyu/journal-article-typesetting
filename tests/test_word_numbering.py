"""Regression for labels absent from literal Word text."""
import io
import sys
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '1-提取_Word转JSON'))
from word_numbering import W, WordNumbering, UnsupportedNumberingError


class NumberingTests(unittest.TestCase):
 def test_decimal_levels_restart_and_no_source_write(self):
    xml = f'<w:numbering xmlns:w="{W[1:-1]}"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1"/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2"/></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        archive.writestr('word/numbering.xml', xml)
    source = stream.getvalue()
    with zipfile.ZipFile(stream) as archive:
        numbering = WordNumbering(archive)
        def paragraph(level):
            return ET.fromstring(f'<w:p xmlns:w="{W[1:-1]}"><w:pPr><w:numPr><w:ilvl w:val="{level}"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>标题</w:t></w:r></w:p>')
        assert [numbering.prefix(paragraph(n)) for n in [0,1,1,0,1]] == ['1 ', '1.1 ', '1.2 ', '2 ', '2.1 ']
        definition = numbering.root.find(W+'abstractNum/'+W+'lvl/'+W+'numFmt')
        definition.set(W+'val','bullet')
        with self.assertRaises(UnsupportedNumberingError):
            numbering.prefix(paragraph(0))
    assert stream.getvalue() == source

if __name__ == "__main__":
    unittest.main()
