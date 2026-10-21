"""Synthetic DOCX contract tests: no Word/Adobe dependency."""
import hashlib
import importlib.util
import json
import sys
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SOURCE_DIR = Path(__file__).resolve().parents[1] / '1-提取_Word转JSON'
sys.path.insert(0, str(SOURCE_DIR))
from extract_journal_article import extract_article, normalize_unicode_scripts, UNICODE_SCRIPT_MAP

HEAD = '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><w:body>'''

def para(text):
    return '<w:p><w:r><w:t>' + text + '</w:t></w:r></w:p>'


def ole(prog, image, binary):
    return '<w:r><w:object><v:shape style="width:30pt;height:12pt"><v:imagedata r:id="' + image + '"/></v:shape><o:OLEObject ProgID="' + prog + '" r:id="' + binary + '"/></w:object></w:r>'


class ExtractTests(unittest.TestCase):
    def extract(self, xml, body_start_text='0 引言'):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        source = base / 'source.docx'
        with zipfile.ZipFile(source, 'w') as z:
            z.writestr('[Content_Types].xml', '<Types/>')
            z.writestr('word/document.xml', HEAD + xml + '</w:body></w:document>')
            z.writestr('word/_rels/document.xml.rels', '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rImage1" Target="media/image1.wmf"/><Relationship Id="rOle1" Target="embeddings/ole1.bin"/><Relationship Id="rImage2" Target="media/image2.png"/><Relationship Id="rOle2" Target="embeddings/ole2.bin"/></Relationships>''')
            z.writestr('word/media/image1.wmf', b'actual-preview-wmf')
            z.writestr('word/embeddings/ole1.bin', b'equation-ole')
            z.writestr('word/media/image2.png', b'actual-preview-png')
            z.writestr('word/embeddings/ole2.bin', b'visio-ole')
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        out = base / 'derived'
        result = extract_article(source, out, body_start_text)
        self.assertEqual(before, hashlib.sha256(source.read_bytes()).hexdigest())
        return result, out

    def read(self, out, filename):
        return json.loads((out / filename).read_text(encoding='utf-8'))

    def test_visio_is_figure_equation_inline_offsets_and_flags(self):
        equation = ole('Equation.DSMT4', 'rImage1', 'rOle1')
        visio = ole('Visio.Drawing.15', 'rImage2', 'rOle2')
        result, out = self.extract(para('标题') + para('0 引言') + '<w:p><w:r><w:t>😀变量</w:t></w:r>' + equation + '<w:r><w:rPr><w:i/><w:vertAlign w:val="subscript"/></w:rPr><w:t>x</w:t></w:r></w:p><w:p>' + visio + '</w:p>')
        self.assertEqual(result['status'], 'extracted')
        self.assertEqual(result['formulaCount'], 1)
        self.assertEqual(result['figureCount'], 1)
        data = self.read(out, 'logical-article.json')
        block = data['blocks'][1]
        self.assertEqual(block['text'], '😀变量⟦EQ-001⟧x')
        self.assertEqual(block['runs'], [{'start': 12, 'end': 13, 'italic': True, 'position': 'subscript'}])
        formula = self.read(out, 'formula-source-map.json')['formulas'][0]
        self.assertTrue(formula['inline'])
        self.assertIsNone(formula['displayNumber'])
        self.assertEqual(formula['start'], 4)
        self.assertEqual(formula['sourceStart'], 4)
        self.assertEqual(Path(formula['path']).read_bytes(), b'actual-preview-wmf')
        self.assertEqual((out / 'figure-1.png').read_bytes(), b'actual-preview-png')

    def test_figure_projection_drops_object_only_blocks_and_preserves_adjacent_runs(self):
        image = ole('Visio.Drawing.15', 'rImage2', 'rOle2')
        result, out = self.extract(para('0 引言') + '<w:p>' + image + '</w:p><w:p><w:r><w:rPr><w:i/></w:rPr><w:t>😀x</w:t></w:r>' + image + '<w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>2</w:t></w:r></w:p>' + para('图1 源图标题'))
        blocks = self.read(out, 'logical-article.json')['blocks']
        self.assertEqual(len(blocks), 3)
        self.assertEqual(blocks[1]['text'], '😀x2')
        self.assertEqual(blocks[1]['runs'], [{'start': 0, 'end': 3, 'italic': True}, {'start': 3, 'end': 4, 'position': 'subscript'}])
        self.assertEqual(blocks[2]['text'], '图1 源图标题')
        self.assertFalse(any('[[FIGURE:' in b['text'] for b in blocks))
        figures = self.read(out, 'figure-source-map.json')['figures']
        self.assertEqual(len(figures), 2)
        self.assertEqual(figures[1]['start'], 3)
        source = self.read(out, 'source-paragraphs.json')
        self.assertIn('[[FIGURE:2]]', source[2]['text'])

    def test_display_number_only_from_source(self):
        equation = ole('Equation.3', 'rImage1', 'rOle1')
        result, out = self.extract(para('0 引言') + '<w:p>' + equation + '<w:r><w:t>（9）</w:t></w:r></w:p><w:p>' + equation + '</w:p>')
        formulas = self.read(out, 'formula-source-map.json')['formulas']
        self.assertEqual([f['displayNumber'] for f in formulas], ['9', None])
        self.assertEqual([f['inline'] for f in formulas], [False, False])
        self.assertEqual([b['role'] for b in self.read(out, 'logical-article.json')['blocks']], ['heading1', 'math', 'math'])

    def test_side_by_side_display_formulas_are_math_not_blank(self):
        equation = ole('Equation.3', 'rImage1', 'rOle1')
        result, out = self.extract(para('0 引言') + '<w:p>' + equation + '<w:r><w:t>     </w:t></w:r>' + equation + '</w:p>')
        formulas = self.read(out, 'formula-source-map.json')['formulas']
        self.assertEqual([f['inline'] for f in formulas], [False, False])
        self.assertEqual([f['displayNumber'] for f in formulas], [None, None])
        self.assertEqual([b['role'] for b in self.read(out, 'logical-article.json')['blocks']], ['heading1', 'math'])

    def test_table_merge_header_and_runs(self):
        table = '''<w:tbl><w:tblGrid><w:gridCol w:w="1200"/><w:gridCol w:w="1300"/></w:tblGrid><w:tr><w:trPr><w:tblHeader/></w:trPr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge w:val="restart"/><w:tcW w:w="2500" w:type="dxa"/></w:tcPr><w:p><w:r><w:rPr><w:i/></w:rPr><w:t>x</w:t></w:r><w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>2</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge/></w:tcPr><w:p/></w:tc></w:tr></w:tbl>'''
        _, out = self.extract(para('0 引言') + table)
        table = self.read(out, 'table-structure.json')['tables'][0]
        self.assertEqual(table['widths'], [1200, 1300])
        self.assertEqual(table['headerRows'], 1)
        self.assertEqual(table['rows'][0][0]['span'], 2)
        self.assertEqual(table['rows'][1][0]['vertical'], 'continue')
        table = self.read(out, 'supplement.json')['tables'][0]
        self.assertEqual(table['rows'][0][0], 'x2')
        self.assertEqual(table['cellRuns'][0][0], [{'start': 0, 'end': 1, 'italic': True}, {'start': 1, 'end': 2, 'position': 'subscript'}])

    def test_omml_blocks_readiness_without_discarding_source(self):
        result, out = self.extract(para('0 引言') + '<w:p><w:r><w:t>公式</w:t></w:r><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></w:p>')
        self.assertEqual(result['status'], 'blocked')
        self.assertEqual(result['ommlCount'], 1)
        self.assertIn('OMML_REQUIRES_RENDERING', [i['code'] for i in result['issues']])
        self.assertIn('[[OMML:1]]', self.read(out, 'logical-article.json')['blocks'][1]['text'])
        self.assertIn('>x<', self.read(out, 'formula-source-map.json')['omml'][0]['xml'])

    def test_front_original_paragraphs_not_guessed_or_deleted(self):
        _, out = self.extract(para('基金项目：甲') + para('论文题目') + para('张甲 李乙') + para('单位') + para('收稿日期：2026-10-20') + para('0 引言') + para('正文'))
        supplement = self.read(out, 'supplement.json')
        self.assertEqual([p['text'] for p in supplement['front']], ['基金项目：甲', '论文题目', '张甲 李乙', '单位', '收稿日期：2026-10-20'])
        self.assertTrue(supplement['front'][2]['needsInput'])
        self.assertEqual(supplement['received'], '收稿日期：2026-10-20')
        self.assertEqual(supplement['fundCandidates'][0]['text'], '基金项目：甲')

    def test_unicode_scripts_preserve_utf16_flags_and_raw_evidence(self):
        result, out = self.extract(para('标题R²') + para('0 引言') + '<w:p><w:r><w:rPr><w:i/><w:b/></w:rPr><w:t>😀Cl⁻ SO₂ H₂S R²</w:t></w:r></w:p>')
        self.assertEqual(result['status'], 'extracted')
        block = self.read(out, 'logical-article.json')['blocks'][1]
        self.assertEqual(block['text'], '😀Cl- SO2 H2S R2')
        encoded = block['text'].encode('utf-16-le')
        script_runs = [r for r in block['runs'] if r.get('position')]
        self.assertEqual([(encoded[r['start']*2:r['end']*2].decode('utf-16-le'), r['position']) for r in script_runs],
                         [('-', 'superscript'), ('2', 'subscript'), ('2', 'subscript'), ('2', 'superscript')])
        self.assertTrue(all(r['italic'] and r['bold'] for r in block['runs']))
        self.assertEqual(len(encoded), len('😀Cl⁻ SO₂ H₂S R²'.encode('utf-16-le')))
        self.assertEqual(self.read(out, 'source-paragraphs.json')[2]['text'], '😀Cl⁻ SO₂ H₂S R²')
        self.assertEqual(self.read(out, 'supplement.json')['front'][0]['text'], '标题R2')
        self.assertTrue(block['unicodeScriptTransformations'])

    def test_unicode_scripts_in_table_have_required_position_runs(self):
        _, out = self.extract(para('0 引言') + '<w:tbl><w:tblGrid><w:gridCol w:w="1000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>SO₂ R²</w:t></w:r></w:p></w:tc></w:tr></w:tbl>')
        table = self.read(out, 'supplement.json')['tables'][0]
        self.assertEqual(table['rows'][0][0], 'SO2 R2')
        self.assertEqual(table['cellRuns'][0][0], [{'start': 2, 'end': 3, 'position': 'subscript'}, {'start': 5, 'end': 6, 'position': 'superscript'}])
        self.assertEqual(table['cellParagraphs'][0][0][0]['text'], 'SO₂ R²')
        self.assertEqual(len(table['cellUnicodeScriptTransformations'][0][0]), 2)

    def test_unicode_conflicting_explicit_position_blocks(self):
        with self.assertRaisesRegex(ValueError, 'UNICODE_SCRIPT_POSITION_CONFLICT'):
            normalize_unicode_scripts({'text': 'R²', 'runs': [{'start': 1, 'end': 2, 'position': 'subscript'}]})
        normalized = normalize_unicode_scripts({'text': 'R²', 'runs': [{'start': 1, 'end': 2, 'position': 'superscript', 'italic': True}]})
        self.assertEqual(normalized['runs'], [{'start': 1, 'end': 2, 'position': 'superscript', 'italic': True}])

    @unittest.skipUnless(shutil.which('node'), 'Node needed to compare the actual importer mapping')
    def test_unicode_mapping_matches_actual_importer_function(self):
        source = (SOURCE_DIR.parent / '2-导入_InDesign/import_word_article_to_indesign.jsx').read_text(encoding='utf-8-sig')
        function = re.search(r'    function normalizeUnicodeSuperSubscript\(c, code\) \{.*?\n    \}', source, re.S).group(0)
        script = "const Position={SUPERSCRIPT:'superscript',SUBSCRIPT:'subscript'};" + function + ";const result={};for(let code=0;code<=0x20ff;code++){const c={};if(normalizeUnicodeSuperSubscript(c,code))result[String.fromCharCode(code)]=[c.contents,c.position];}process.stdout.write(JSON.stringify(result));"
        actual = json.loads(subprocess.run(['node', '-e', script], check=True, capture_output=True, encoding='utf-8').stdout)
        self.assertEqual(actual, {k: list(v) for k, v in UNICODE_SCRIPT_MAP.items()})

    def test_body_start_override_is_exact(self):
        result, out = self.extract(para('作者甲') + para('1 研究背景') + para('正文'), '1 研究背景')
        self.assertEqual(result['status'], 'extracted')
        self.assertEqual(self.read(out, 'logical-article.json')['blocks'][0]['text'], '1 研究背景')
        result, _ = self.extract(para('1 研究背景') + para('正文'), '1 研究背')
        self.assertEqual(result['status'], 'blocked')

    def test_fake_docx_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'fake.docx'
            p.write_bytes(b'legacy binary')
            with self.assertRaisesRegex(ValueError, 'SOURCE_NOT_DOCX_ZIP'):
                extract_article(p, Path(directory) / 'out')


if __name__ == '__main__':
    unittest.main()
