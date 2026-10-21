import importlib.util
import json
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import MagicMock, patch

SPEC = importlib.util.spec_from_file_location('prepare_article_job', Path(__file__).parents[1] / '2-导入_InDesign/prepare_article_job.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class PrepareJobTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.extracted = self.root / 'extracted-v2'
        self.extracted.mkdir()
        self.art = self.root / 'art'
        self.art.mkdir()
        self.source = self.root / 'source.docx'
        self.source.write_bytes(b'source')
        self.template = self.root / 'template.indd'
        self.template.write_bytes(b'template')
        self.figure = self.art / '测试-图1.pdf'
        self.figure.write_bytes(b'figure')
        self.base = {'source': str(self.source), 'sourceSha256': module.digest(self.source)}
        texts = ['收稿日期：2026-01-01', '示例标题', '测试，作者', '（单位，地址 100000）', '摘要：摘要内容',
                 '关键词：关键', '中图分类号：TP1', 'Example Title', 'TEST Author', '(Institute, City 100000)',
                 'Abstract: Example.', 'Keywords: sample']
        self.records = [{'index': i, 'text': text, 'runs': [], 'superscripts': [], 'subscripts': []}
                        for i, text in enumerate(texts)]
        self.blocks = [{'role': 'body', 'text': '完整段落先说明图1。这一段必须完整保留。', 'runs': []},
                       {'role': 'figure_caption', 'text': '图1  示例图', 'runs': []}]
        self.report = dict(self.base, issues=[], formulaCount=0, figureCount=1, tableCount=0)
        self.supp = dict(self.base, front=self.records, received=texts[0], tables=[])
        self.structures = dict(self.base, tables=[])
        self.reference = self.root / 'reference.json'
        module.write(self.reference, {'templateContractVersion': 'qa-template-contract-v2',
            'article': '旧作者', 'layoutProfile': {'stale': True},
            'templateContract': {'geometry': {'columnWidthMm': 85.5, 'spreadWidthMm': 178}, 'styles': {}},
            'frontmatter': {'doiText': 'DOI:10.19850/j.cnki.2096-4706.2024.19.000', 'contract': {'receivedSeparatorBaselineGapMm': 4.8965711806, 'frontAnchor': {'top': 30, 'left': 21, 'width': 165},
                'footerAnchor': {'bottom': 265, 'left': 14.5, 'width': 85.5}, 'styleMap': {},
                'enTitleLastLeadingPt': 17, 'enTitleUpperLeadingPt': 17, 'enTitleAuthorBaselineGapPt': 15.089}}})
        self.refresh()

    def refresh(self):
        module.write(self.extracted / 'logical-article.json', dict(self.base, blocks=self.blocks))
        module.write(self.extracted / 'supplement.json', self.supp)
        module.write(self.extracted / 'table-structure.json', self.structures)
        module.write(self.extracted / 'extraction-report.json', self.report)
        module.write(self.extracted / 'source-paragraphs.json', self.records + [dict(index=99, text='', runs=[])])

    def build(self, **kwargs):
        figure_size = kwargs.pop('figure_size', (120, 60))
        with patch.object(module, 'figure_metrics', return_value=figure_size):
            return module.build(self.extracted, self.art, '测试', self.template, self.root / 'input',
                                self.root / 'deliver/测试_初排_QA.indd', reference=self.reference, pages=6, **kwargs)

    def test_missing_reference_doi_blocks_before_writing_job(self):
        reference = module.read(self.reference)
        reference['frontmatter']['doiText'] = ''
        module.write(self.reference, reference)
        with self.assertRaisesRegex(ValueError, 'REFERENCE_DOI_REQUIRED'):
            self.build()
        self.assertFalse((self.root / 'input' / 'job.json').exists())

    def test_missing_receipt_distance_blocks_before_writing_job(self):
        reference = module.read(self.reference)
        reference['frontmatter']['contract'].pop('receivedSeparatorBaselineGapMm')
        module.write(self.reference, reference)
        with self.assertRaisesRegex(ValueError, 'RECEIVED_SEPARATOR_CONTRACT'):
            self.build()

    def test_explicit_small_figure_fit_preserves_source_size_and_scale(self):
        result = self.build(fit_near_column=True, figure_size=(87, 47))
        job = module.read(result['job'])
        self.assertEqual(job['panels'], [])
        self.assertEqual(job['figures'][0]['mode'], 'inline')
        self.assertEqual(job['assets'][0]['width'], 85.5)
        self.assertEqual(job['assets'][0]['sourceWidthMm'], 87)
        self.assertAlmostEqual(job['assets'][0]['height'], 47 * 85.5 / 87)
        self.assertAlmostEqual(job['assets'][0]['layoutScalePercent'], 85.5 / 87 * 100)

    def test_isolated_job_contract_and_whole_paragraph_panel(self):
        result = self.build()
        job = module.read(result['job'])
        audit = module.read(job['auditConfigPath'])
        self.assertEqual(job['pageNumberStart'], 2)
        self.assertTrue(job['allowPageGrowth'])
        self.assertEqual(job['expected']['pages'], 6)
        self.assertEqual(audit['pageBudget'], 6)
        self.assertEqual(job['panels'][0]['afterParagraphText'], self.blocks[0]['text'])
        self.assertNotIn('layoutProfile', job)
        self.assertNotIn('enTitleLastLeadingPt', job['frontmatter']['contract'])
        self.assertNotIn('旧作者', json.dumps(job, ensure_ascii=False))
        self.assertEqual(job['frontmatter']['doiText'], 'DOI:10.19850/j.cnki.2096-4706.2024.19.000')
        self.assertEqual(audit['doiContract']['text'], job['frontmatter']['doiText'])
        self.assertEqual(audit['receivedSeparatorBaselineGapMm'], 4.8965711806)
        self.assertEqual(audit['assets'][0]['sha256'], module.digest(self.figure).upper())
        self.assertEqual(len(set(job['frontmatter']['indices'].values())), 12)
        self.assertTrue(audit['requireNativeFormulaPaste'])
        self.assertEqual(len(module.read(audit['sourceParagraphs'])), 14)
        self.assertEqual(audit['sourceParagraphProvenance']['sha256'], module.digest(self.extracted / 'source-paragraphs.json'))
        supplement = module.read(job['supplementPath'])
        self.assertEqual(supplement['front'][-1]['text'], '')
        self.assertEqual(supplement['received'], self.records[0]['text'])

    def test_vertical_merges_keep_restart_root_and_full_expected_span(self):
        rows = [['header', 'value']]
        geometry = [[{'start': 0, 'span': 1}, {'start': 1, 'span': 1}]]
        for size in (10, 5, 5):
            for index in range(size):
                rows.append(['group' if index == 0 else '', str(index)])
                geometry.append([{'start': 0, 'span': 1, 'vertical': 'restart' if index == 0 else 'continue'},
                                 {'start': 1, 'span': 1}])
        merges = module.vertical_merges([{'rows': rows}], [{'rows': geometry}])
        self.assertEqual(len(merges), 17)
        self.assertEqual([(m['intoRow'], m['expectedRowSpan']) for m in merges],
                         [(1, 10)] * 9 + [(11, 5)] * 4 + [(16, 5)] * 4)
        self.assertEqual(merges[-1]['rowIndex'], 20)

    def test_vertical_merges_reject_nonempty_or_orphan_continuations(self):
        cells = [{'start': 0, 'span': 1, 'vertical': 'restart'}]
        continuation = [{'start': 0, 'span': 1, 'vertical': 'continue'}]
        with self.assertRaisesRegex(ValueError, 'NONEMPTY_CONTINUATION'):
            module.vertical_merges([{'rows': [['head'], ['must preserve']]}],
                                   [{'rows': [cells, continuation]}])
        with self.assertRaisesRegex(ValueError, 'ORPHAN_CONTINUATION'):
            module.vertical_merges([{'rows': [['']]}], [{'rows': [continuation]}])
        with self.assertRaisesRegex(ValueError, 'ORPHAN_CONTINUATION'):
            module.vertical_merges([{'rows': [['head'], ['']]}],
                                   [{'rows': [cells, [{'start': 0, 'span': 2, 'vertical': 'continue'}]]}])

    def test_builder_emits_source_vertical_merge_contract(self):
        self.supp['tables'] = [{'rows': [['head'], ['group'], [''], ['']], 'cellRuns': [[[]], [[]], [[]], [[]]]}]
        self.structures['tables'] = [{'widths': [1000], 'headerRows': 1, 'rows': [
            [{'start': 0, 'span': 1}], [{'start': 0, 'span': 1, 'vertical': 'restart'}],
            [{'start': 0, 'span': 1, 'vertical': 'continue'}],
            [{'start': 0, 'span': 1, 'vertical': 'continue'}]]}]
        self.report['tableCount'] = 1
        self.blocks.append({'role': 'table_gap', 'text': '   ', 'runs': [], 'tableNumber': 1})
        self.refresh()
        job = module.read(self.build()['job'])
        audit = module.read(job['auditConfigPath'])
        self.assertEqual(audit['mergedEmptyCells'], [
            {'tableIndex': 0, 'rowIndex': 2, 'cellIndex': 0, 'intoRow': 1, 'intoCell': 0, 'expectedRowSpan': 3},
            {'tableIndex': 0, 'rowIndex': 3, 'cellIndex': 0, 'intoRow': 1, 'intoCell': 0, 'expectedRowSpan': 3}])

    def test_front_duplicate_anchor_blocks(self):
        self.supp['front'].append(dict(self.records[4], index=99))
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'FRONT_ANCHOR_cnAbstract'):
            self.build()

    def test_layout_check_required_audit_fields(self):
        result = self.build()
        job = module.read(result['job'])
        audit = module.read(job['auditConfigPath'])
        required = ('sourceLogicalArticle', 'configVersion', 'templateContractVersion', 'documentPath',
                    'auditPath', 'reviewedContinuedTables', 'sourceParagraphs', 'sourceTables',
                    'mergedEmptyCells', 'assets', 'bindings')
        for field in required:
            self.assertIn(field, audit)
        self.assertEqual(audit['templateContractVersion'], job['templateContractVersion'])
        self.assertTrue(audit['templateContractVersion'])
        for field in ('sourceLogicalArticle', 'sourceParagraphs', 'sourceTables'):
            self.assertTrue(Path(audit[field]).is_file())

    def test_pdf_metrics_match_media_crop_used_by_assembly(self):
        document = MagicMock()
        document.__enter__.return_value = document
        document.__len__.return_value = 1
        page = SimpleNamespace(mediabox=SimpleNamespace(width=212.3125, height=255.88643),
                               rect=SimpleNamespace(width=209.2025, height=255.88643), rotation=0)
        document.__getitem__.return_value = page
        with patch.dict('sys.modules', {'fitz': SimpleNamespace(open=lambda path: document)}):
            width, height = module.figure_metrics(self.figure)
            self.assertAlmostEqual(width, 212.3125 * 25.4 / 72)
            self.assertAlmostEqual(height, 255.88643 * 25.4 / 72)
            page.rotation = 90
            width, height = module.figure_metrics(self.figure)
            self.assertAlmostEqual(width, 255.88643 * 25.4 / 72)
            self.assertAlmostEqual(height, 212.3125 * 25.4 / 72)

    def test_received_not_fund(self):
        supplement, indices, received = module.frontmatter(self.supp, '测试')
        self.assertEqual(supplement['front'][indices['fund']]['text'], '')
        self.assertEqual(received['text'], self.records[0]['text'])

    def test_multiple_units_preserve_utf16_runs(self):
        records = [dict(index=1, text='😀单位', runs=[{'start': 2, 'end': 4, 'italic': True}]),
                   dict(index=2, text='单位二', runs=[{'start': 0, 'end': 2, 'position': 'superscript'}])]
        merged = module.merge_records(records)
        self.assertEqual(merged['text'], '😀单位\n单位二')
        self.assertEqual(merged['runs'][1]['start'], 5)

    def test_check_skips_picture_only_and_preserves_inline_neighbors(self):
        supplement, indices, _ = module.frontmatter(self.supp, '测试')
        records = module.check_paragraphs(supplement, indices, {'blocks': [
            {'text': '[[FIGURE:1]]', 'runs': []}, {'text': '⟦EQ-001⟧', 'runs': []},
            {'text': '甲⟦EQ-002⟧乙😀下', 'runs': [{'start': 9, 'end': 13, 'position': 'subscript'}]},
            {'text': '(2)', 'runs': []}]})
        self.assertEqual([r['text'] for r in records[-2:]], ['甲乙😀下', '(2)'])
        self.assertEqual(records[-2]['subscripts'], ['乙😀下'])
        self.assertFalse(any('FIGURE:' in r['text'] or 'EQ-' in r['text'] for r in records))

    def test_check_uses_merged_units_and_run_positions(self):
        supplement, indices, _ = module.frontmatter(self.supp, '测试')
        merged = module.merge_records([
            {'text': '(1.Unit)', 'index': 1, 'runs': [{'start': 1, 'end': 2, 'position': 'superscript'}]},
            {'text': '(2.Unit)', 'index': 2, 'runs': [{'start': 1, 'end': 2, 'position': 'superscript'}]}])
        supplement['front'][indices['enAffiliation']] = dict(merged, role='enAffiliation')
        records = module.check_paragraphs(supplement, indices, {'blocks': []})
        units = [r for r in records if r.get('role') == 'enAffiliation']
        self.assertEqual(len(units), 1)
        self.assertEqual(units[0]['text'], '(1.Unit)\n(2.Unit)')
        self.assertEqual(units[0]['superscripts'], ['1', '2'])

    def test_missing_and_duplicate_figures_block(self):
        self.figure.unlink()
        with self.assertRaisesRegex(ValueError, 'FIGURE_ASSET_COUNT'):
            self.build()
        self.figure.write_bytes(b'figure')
        (self.art / '测试-图1.jpg').write_bytes(b'figure')
        with self.assertRaisesRegex(ValueError, 'FIGURE_ASSET_COUNT'):
            self.build()

    def test_figure_groups_cover_every_source_object_and_pin_mapping(self):
        self.report['figureCount'] = 3
        self.refresh()
        groups = self.root / 'figure-groups.json'
        module.write(groups, {'1': [1, 2, 3]})
        result = self.build(figure_groups=groups)
        job = module.read(result['job'])
        audit = module.read(job['auditConfigPath'])
        self.assertEqual(job['expected']['figures'], 1)
        self.assertEqual(audit['figureCount'], 1)
        self.assertEqual(audit['figureGroupProvenance']['sourceObjectCount'], 3)
        self.assertEqual(audit['figureGroupProvenance']['groups'], {'1': [1, 2, 3]})
        self.assertEqual(job['figureGroupProvenance'], audit['figureGroupProvenance'])
        self.assertEqual([e for e in job['inputs'] if e['name'] == 'figure-groups'],
                         [{'name': 'figure-groups', 'path': str(groups), 'sha256': module.digest(groups)}])

    def test_figure_groups_reject_incomplete_duplicate_or_wrong_caption_mapping(self):
        self.report['figureCount'] = 3
        self.refresh()
        groups = self.root / 'figure-groups.json'
        for mapping, code in [({'1': [1, 2]}, 'FIGURE_GROUP_OBJECT_COVERAGE'),
                              ({'1': [1, 2, 2]}, 'FIGURE_GROUP_OBJECT_COVERAGE'),
                              ({'1': [1, 2, 4]}, 'FIGURE_GROUP_OBJECT_COVERAGE'),
                              ({'2': [1, 2, 3]}, 'FIGURE_GROUP_CAPTION_KEYS'),
                              ({'1': []}, 'FIGURE_GROUP_OBJECT_NUMBERS'),
                              ({'1': [True, 2, 3]}, 'FIGURE_GROUP_OBJECT_NUMBERS')]:
            module.write(groups, mapping)
            with self.subTest(mapping=mapping):
                with self.assertRaisesRegex(ValueError, code):
                    self.build(figure_groups=groups)
        with self.assertRaisesRegex(ValueError, 'FIGURE_CAPTION_COUNT'):
            self.build()

    def test_wide_panel_without_body_reference_blocks(self):
        self.blocks[0]['text'] = '没有引用图件。'
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'FIGURE_REFERENCE_PARAGRAPH'):
            self.build()

    def test_wrong_source_identity_blocks(self):
        self.report['sourceSha256'] = '0' * 64
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'EXTRACTION_SOURCE_IDENTITY'):
            self.build()

    def test_formulas_require_explicit_native_manifest(self):
        self.report['formulaCount'] = 1
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'NATIVE_IDMS_MANIFEST_REQUIRED'):
            self.build()

    def test_native_formula_cache_contract_reaches_whole_article_audit(self):
        self.report['formulaCount'] = 1
        self.refresh()
        native = self.root / 'formula.idms'
        native.write_bytes(b'native outlines')
        entry = {'number': 1, 'path': str(native), 'sha256': module.digest(native),
                 'basePointSize': 10.5, 'cacheKey': 'current-cache',
                 'sourceSha256': 'source-formula-hash', 'ruleVersion': 'outline-v2'}
        manifest = self.root / 'native-manifest.json'
        module.write(manifest, {'mode': 'native-idms', 'entries': [entry]})
        result = self.build(native_manifest=manifest)
        audit = module.read(module.read(result['job'])['auditConfigPath'])
        self.assertEqual(audit['formulaCacheContract'], [{key: entry[key] for key in
                         ('number', 'cacheKey', 'sha256', 'sourceSha256', 'ruleVersion')}])

    def test_tables_require_explicit_header_rows(self):
        self.report['tableCount'] = 1
        self.supp['tables'] = [{'rows': [['标题'], ['数据']]}]
        self.structures['tables'] = [{}]
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'TABLE_HEADER_REQUIRED'):
            self.build()

    def test_table_cell_runs_keep_utf16_and_paragraph_breaks(self):
        tables = [{'rows': [['😀x\nH2O']], 'cellRuns': [[[{'start': 2, 'end': 3, 'italic': True},
                    {'start': 5, 'end': 6, 'position': 'subscript'}]]]}]
        runs = module.table_text_runs(tables)
        self.assertEqual(''.join(r['text'] for r in runs), '😀x\nH2O')
        self.assertEqual([(r['start'], r['text'], r['italic'], r['position']) for r in runs],
                         [(0, '😀', False, 'baseline'), (2, 'x', True, 'baseline'),
                          (3, '\nH', False, 'baseline'), (5, '2', False, 'subscript'),
                          (6, 'O', False, 'baseline')])

    def test_table_plain_cells_have_explicit_baseline_contract(self):
        runs = module.table_text_runs([{'rows': [['正常', '']], 'cellRuns': [[[], []]]}])
        self.assertEqual(runs, [{'tableIndex': 0, 'rowIndex': 0, 'cellIndex': 0, 'start': 0,
                                'text': '正常', 'italic': False, 'position': 'baseline'}])
        with self.assertRaisesRegex(ValueError, 'TABLE_CELL_RUNS_REQUIRED'):
            module.table_text_runs([{'rows': [['source']]}])

    def test_original_doc_and_converted_source_have_separate_hash_inputs(self):
        original = self.root / 'source-original.doc'
        original.write_bytes(b'original binary Word data')
        result = self.build(original_doc=original)
        job = module.read(result['job'])
        audit = module.read(job['auditConfigPath'])
        manifest = module.read(result['manifest'])
        self.assertEqual(job['sourceConversion'], audit['sourceConversion'])
        self.assertEqual(job['sourceConversion'], manifest['sourceConversion'])
        self.assertEqual(job['sourceConversion']['originalDoc']['sha256'], module.digest(original))
        self.assertEqual(job['sourceConversion']['convertedDocx']['sha256'], module.digest(self.source))
        entry = [v for v in job['inputs'] if v['name'] == 'source-original-doc']
        self.assertEqual(len(entry), 1)
        self.assertEqual(entry[0]['sha256'], module.digest(original))
        self.assertEqual(manifest['sourceWord'], str(self.source))

    def test_does_not_overwrite_configs(self):
        self.build()
        with self.assertRaisesRegex(ValueError, 'OUTPUT_CONFIG_EXISTS'):
            self.build()


if __name__ == '__main__':
    unittest.main()
