"""Build isolated assembly inputs from verified Word extraction and explicit artwork."""
import argparse
import copy
import hashlib
import json
import math
import re
from pathlib import Path


ROLES = ('cnTitle', 'cnAuthor', 'cnAffiliation', 'cnAbstract', 'cnKeywords',
         'classification', 'enTitle', 'enAuthor', 'enAffiliation', 'enAbstract', 'enKeywords')


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def require(condition, code):
    if not condition:
        raise ValueError(code)


def merge_records(records):
    require(bool(records), 'FRONT_EMPTY_GROUP')
    merged = copy.deepcopy(records[0])
    merged['text'] = '\n'.join(r['text'] for r in records)
    merged['sourceText'] = merged['text']
    merged['sourceParagraphIndices'] = [r['index'] for r in records]
    merged['runs'] = []
    offset = 0
    for record in records:
        for run in record.get('runs', []):
            merged['runs'].append(dict(run, start=run['start'] + offset, end=run['end'] + offset))
        offset += len(record['text'].encode('utf-16-le')) // 2 + 1
    for kind in ('superscripts', 'subscripts'):
        merged[kind] = [v for r in records for v in r.get(kind, [])]
    return merged


def check_paragraphs(supplement, indices, logical):
    records = [supplement['front'][indices[role]] for role in ROLES]
    records += [{'role': 'received', 'text': supplement['received'], 'runs': []},
                supplement['front'][indices['fund']]]
    records += logical['blocks']
    out = []
    for record in records:
        text = record['text']
        kept = []
        previous = 0
        for match in re.finditer(r'\[\[FIGURE:\d+\]\]|⟦EQ-\d+⟧', text):
            kept.append((previous, match.start()))
            previous = match.end()
        kept.append((previous, len(text)))
        clean = ''.join(text[start:end] for start, end in kept)
        if not clean.strip():
            continue
        result = copy.deepcopy(record)
        result['index'] = record.get('index', record.get('sourceParagraphIndex', len(out)))
        result['text'] = clean
        result['runs'] = []
        clean_offset = 0
        for start, end in kept:
            original_start = len(text[:start].encode('utf-16-le')) // 2
            original_end = len(text[:end].encode('utf-16-le')) // 2
            for run in record.get('runs', []):
                overlap_start = max(original_start, run['start'])
                overlap_end = min(original_end, run['end'])
                if overlap_start < overlap_end:
                    result['runs'].append(dict(run, start=clean_offset + overlap_start - original_start,
                                               end=clean_offset + overlap_end - original_start))
            clean_offset += original_end - original_start
        encoded = clean.encode('utf-16-le')
        for kind, position in (('superscripts', 'superscript'), ('subscripts', 'subscript')):
            result[kind] = [encoded[r['start'] * 2:r['end'] * 2].decode('utf-16-le')
                            for r in result['runs'] if r.get('position') == position]
        out.append(result)
    return out


def frontmatter(supplement, author):
    records = [copy.deepcopy(r) for r in supplement['front'] if r['text'].strip()]
    patterns = {'cnAbstract': r'^摘\s*要\s*[:：]', 'cnKeywords': r'^关\s*键\s*词\s*[:：]',
                'classification': r'^中图分类号\s*[:：]', 'enAbstract': r'^Abstract\s*[:：]',
                'enKeywords': r'^Key\s*words\s*[:：]'}
    anchors = {}
    for role, pattern in patterns.items():
        found = [i for i, r in enumerate(records) if re.match(pattern, r['text'].strip(), re.I)]
        require(len(found) == 1, 'FRONT_ANCHOR_' + role)
        anchors[role] = found[0]
    a, k, c, e, ek = [anchors[r] for r in patterns]
    require(a + 1 == k and k + 1 == c and c < e and e + 1 == ek and ek == len(records) - 1,
            'FRONT_ANCHOR_ORDER')
    metadata = [r for r in records[:a] if re.match(r'^(收稿日期|基金项目)\s*[:：]', r['text'].strip())]
    cn = [r for r in records[:a] if r not in metadata]
    en = records[c + 1:e]
    require(len(cn) >= 3 and len(en) >= 3, 'FRONT_TITLE_AUTHOR_UNIT_COUNT')
    require(author in re.sub(r'\s', '', cn[1]['text']), 'FRONT_CN_AUTHOR')
    require(not re.match(r'^[（(\d]', cn[0]['text']) and not re.match(r'^[（(]', cn[1]['text']),
            'FRONT_CN_ORDER')
    require(all(re.match(r'^[（(\d]', r['text'].strip()) for r in cn[2:]), 'FRONT_CN_UNIT_ORDER')
    require(re.search(r'[A-Za-z]', en[0]['text']) and not re.match(r'^[（(]', en[0]['text']),
            'FRONT_EN_TITLE')
    require(re.fullmatch(r'[A-Z][A-Za-z\s,，.\-\d*;；]+', en[1]['text'].strip()) is not None,
            'FRONT_EN_AUTHOR')
    require(all(re.match(r'^[（(\d]', r['text'].strip()) for r in en[2:]), 'FRONT_EN_UNIT_ORDER')
    received = [r for r in metadata if re.match(r'^收稿日期\s*[:：]', r['text'].strip())]
    fund = [r for r in metadata if re.match(r'^基金项目\s*[:：]', r['text'].strip())]
    require(len(received) == 1 and len(fund) <= 1, 'FRONT_METADATA_AMBIGUOUS')
    require(supplement.get('received', '').strip() == received[0]['text'].strip(), 'RECEIVED_MISMATCH')
    mapped = dict(zip(('cnTitle', 'cnAuthor', 'cnAffiliation'), (cn[0], cn[1], merge_records(cn[2:]))))
    mapped.update(zip(('enTitle', 'enAuthor', 'enAffiliation'), (en[0], en[1], merge_records(en[2:]))))
    mapped.update({role: records[index] for role, index in anchors.items()})
    require(set(mapped) == set(ROLES), 'FRONT_ROLE_COUNT')
    out = copy.deepcopy(supplement)
    out['front'] = [dict(mapped[role], role=role, needsInput=False) for role in ROLES]
    out['front'].append(dict(fund[0], role='fund') if fund else
                        {'role': 'fund', 'text': '', 'runs': [], 'sourceParagraphIndices': []})
    indices = {role: i for i, role in enumerate(ROLES)}
    indices['fund'] = len(ROLES)
    return out, indices, received[0]


def figure_metrics(path):
    if path.suffix.lower() == '.pdf':
        import fitz
        with fitz.open(path) as document:
            require(len(document) == 1, 'FIGURE_PDF_PAGE_COUNT')
            page = document[0]
            # Assembly places PDFCrop.CROP_MEDIA; page.rect instead describes CropBox.
            width, height = page.mediabox.width, page.mediabox.height
            if page.rotation % 180:
                width, height = height, width
            return width * 25.4 / 72, height * 25.4 / 72
    from PIL import Image
    with Image.open(path) as image:
        dpi = image.info.get('dpi')
        require(dpi and min(dpi) > 0, 'FIGURE_RASTER_DPI_REQUIRED')
        return image.width * 25.4 / dpi[0], image.height * 25.4 / dpi[1]


def table_text_runs(tables):
    out = []
    for table_index, table in enumerate(tables):
        rows, cell_runs = table['rows'], table.get('cellRuns')
        require(isinstance(cell_runs, list) and len(cell_runs) == len(rows), 'TABLE_CELL_RUNS_REQUIRED')
        for row_index, row in enumerate(rows):
            require(len(cell_runs[row_index]) == len(row), 'TABLE_CELL_RUNS_SHAPE')
            for cell_index, text in enumerate(row):
                encoded = text.encode('utf-16-le')
                length = len(encoded) // 2
                runs = cell_runs[row_index][cell_index]
                boundaries = {0, length}
                for run in runs:
                    require(0 <= run['start'] < run['end'] <= length, 'TABLE_CELL_RUN_RANGE')
                    boundaries.update((run['start'], run['end']))
                spans = []
                ordered = sorted(boundaries)
                for start, end in zip(ordered, ordered[1:]):
                    italic, position = False, 'baseline'
                    for run in runs:
                        if run['start'] <= start and end <= run['end']:
                            italic = run.get('italic', italic)
                            position = run.get('position', position)
                    require(position in ('baseline', 'subscript', 'superscript') and isinstance(italic, bool),
                            'TABLE_CELL_RUN_FORMAT')
                    segment = encoded[start * 2:end * 2].decode('utf-16-le')
                    if spans and spans[-1]['italic'] == italic and spans[-1]['position'] == position:
                        spans[-1]['text'] += segment
                    else:
                        spans.append({'tableIndex': table_index, 'rowIndex': row_index, 'cellIndex': cell_index,
                                      'start': start, 'text': segment, 'italic': italic, 'position': position})
                out.extend(spans)
    return out


def vertical_merges(tables, structures):
    merges = []
    for table_index, (table, structure) in enumerate(zip(tables, structures)):
        rows, geometry = table['rows'], structure.get('rows', [])
        require(len(rows) == len(geometry), 'TABLE_MERGE_STRUCTURE_ROWS')
        groups, active = [], {}
        for row_index, (row, cells) in enumerate(zip(rows, geometry)):
            require(len(row) == len(cells), 'TABLE_MERGE_STRUCTURE_CELLS')
            following = {}
            for cell_index, cell in enumerate(cells):
                key = (cell['start'], cell['span'])
                vertical = cell.get('vertical')
                if vertical == 'restart':
                    group = {'root': (row_index, cell_index), 'continuations': []}
                    groups.append(group)
                    following[key] = group
                elif vertical == 'continue':
                    require(key in active, 'TABLE_MERGE_ORPHAN_CONTINUATION')
                    require(not re.sub(r'\s', '', row[cell_index]), 'TABLE_MERGE_NONEMPTY_CONTINUATION')
                    group = active[key]
                    group['continuations'].append((row_index, cell_index))
                    following[key] = group
                else:
                    require(vertical is None, 'TABLE_MERGE_VERTICAL_VALUE')
            active = following
        for group in groups:
            root_row, root_cell = group['root']
            expected = len(group['continuations']) + 1
            for row_index, cell_index in group['continuations']:
                merges.append({'tableIndex': table_index, 'rowIndex': row_index, 'cellIndex': cell_index,
                               'intoRow': root_row, 'intoCell': root_cell, 'expectedRowSpan': expected})
    return merges


def build(extracted, figure_directory, author, template, destination, output_document,
          reference=None, contracts=None, pages=None, inventory=None, page_number_start=2,
          native_manifest=None, table_headers=None, table_kinds=None, original_doc=None, figure_groups=None, fit_near_column=False):
    extracted, figure_directory = Path(extracted).resolve(), Path(figure_directory).resolve()
    template, destination, output_document = Path(template).resolve(), Path(destination).resolve(), Path(output_document).resolve()
    require(template.is_file(), 'TEMPLATE_MISSING')
    require(output_document != template and re.search(r'QA|copy|副本', output_document.name, re.I), 'OUTPUT_QA_REQUIRED')
    logical = read(extracted / 'logical-article.json')
    supp = read(extracted / 'supplement.json')
    structures = read(extracted / 'table-structure.json')
    report = read(extracted / 'extraction-report.json')
    raw_paragraphs = extracted / 'source-paragraphs.json'
    read(raw_paragraphs)
    source = Path(logical['source']).resolve()
    require(source.is_file(), 'SOURCE_MISSING')
    source_hash = digest(source)
    conversion = None
    if original_doc:
        original_doc = Path(original_doc).resolve()
        require(original_doc.is_file() and original_doc.suffix.lower() == '.doc' and original_doc != source,
                'ORIGINAL_DOC_REQUIRED')
        conversion = {'originalDoc': {'path': str(original_doc), 'sha256': digest(original_doc)},
                      'convertedDocx': {'path': str(source), 'sha256': source_hash}}
    for record in (logical, supp, structures, report):
        require(Path(record['source']).resolve() == source and record['sourceSha256'].lower() == source_hash,
                'EXTRACTION_SOURCE_IDENTITY')
    require(not report.get('issues'), 'EXTRACTION_ISSUES')
    if inventory:
        inventory = read(inventory)
        require(inventory['author'] == author and inventory['sourceWordSHA256'].lower() == source_hash,
                'INVENTORY_SOURCE_IDENTITY')
    if pages is None:
        budget = re.search(r'(\d+(?:\.\d+)?)\s*P\b', inventory['sourceWord'], re.I) if inventory else None
        require(budget is not None, 'PAGE_BUDGET_REQUIRED')
        pages = math.ceil(float(budget[1]))
    require(isinstance(pages, int) and pages > 0 and page_number_start > 0, 'PAGE_BUDGET_INVALID')
    base = read(contracts or reference) if (contracts or reference) else {}
    require('templateContract' in base and 'contract' in base.get('frontmatter', {}), 'BASE_CONTRACT_REQUIRED')
    template_contract = {k: copy.deepcopy(base['templateContract'][k]) for k in ('geometry', 'styles')}
    front_contract = copy.deepcopy(base['frontmatter']['contract'])
    require(isinstance(base['frontmatter'].get('doiText'), str)
            and bool(base['frontmatter']['doiText'].strip()), 'REFERENCE_DOI_REQUIRED')
    receipt_gap = front_contract.get('receivedSeparatorBaselineGapMm')
    require(type(receipt_gap) in (int, float) and math.isfinite(receipt_gap)
            and receipt_gap > 0, 'RECEIVED_SEPARATOR_CONTRACT')
    for key in ('enTitleUpperLeadingPt', 'enTitleLastLeadingPt', 'enTitleAuthorBaselineGapPt'):
        front_contract.pop(key, None)
    supp, indices, received = frontmatter(supp, author)
    blocks = logical['blocks']
    captions = []
    for i, block in enumerate(blocks):
        if block['role'] != 'figure_caption' or not block['text'].strip():
            continue
        match = re.match(r'^图\s*(\d+)\s+\S', block['text'])
        require(match is not None, 'FIGURE_CAPTION_NUMBER')
        captions.append((int(match[1]), i, block['text']))
    numbers = [n for n, _, _ in captions]
    require(len(numbers) == len(set(numbers)), 'FIGURE_CAPTION_COUNT')
    group_provenance = None
    if figure_groups:
        group_path = Path(figure_groups).resolve()
        groups = read(group_path)
        require(isinstance(groups, dict) and set(groups) == {str(number) for number in numbers},
                'FIGURE_GROUP_CAPTION_KEYS')
        require(all(isinstance(objects, list) and objects and all(type(n) is int and n > 0 for n in objects)
                    for objects in groups.values()), 'FIGURE_GROUP_OBJECT_NUMBERS')
        object_numbers = [n for objects in groups.values() for n in objects]
        require(sorted(object_numbers) == list(range(1, report['figureCount'] + 1)),
                'FIGURE_GROUP_OBJECT_COVERAGE')
        group_provenance = {'path': str(group_path), 'sha256': digest(group_path),
                            'sourceObjectCount': report['figureCount'], 'groups': copy.deepcopy(groups)}
    else:
        require(len(numbers) == report['figureCount'], 'FIGURE_CAPTION_COUNT')
    assets, figures, panels = [], [], []
    for number, index, caption in captions:
        matches = [p for p in figure_directory.iterdir() if p.is_file() and
                   re.fullmatch(re.escape(author) + r'-图' + str(number) + r'\.(pdf|jpe?g)', p.name, re.I)]
        require(len(matches) == 1, f'FIGURE_ASSET_COUNT {number} matches={len(matches)}')
        path = matches[0].resolve()
        width, height = figure_metrics(path)
        require(0 < width <= template_contract['geometry']['spreadWidthMm'] + .1 and height > 0,
                f'FIGURE_SIZE {number}')
        source_width, source_height = width, height
        column_width = template_contract['geometry']['columnWidthMm']
        scale = column_width / width if fit_near_column and column_width < width <= column_width / .95 else 1
        width, height = width * scale, height * scale
        assets.append({'name': path.name, 'path': str(path), 'source': str(path), 'number': number,
                       'kind': 'figure', 'width': width, 'height': height, 'sha256': digest(path).upper()})
        if scale != 1:
            assets[-1].update(sourceWidthMm=source_width, sourceHeightMm=source_height, layoutScalePercent=scale * 100)
        if width > template_contract['geometry']['columnWidthMm']:
            prior = [b for b in blocks[:index] if b['role'] == 'body' and
                     re.search(r'图\s*' + str(number) + r'(?!\d)', b['text'])]
            require(bool(prior), f'FIGURE_REFERENCE_PARAGRAPH {number}')
            anchor = prior[-1]['text']
            require(sum(b['text'] == anchor for b in blocks) == 1, f'FIGURE_REFERENCE_AMBIGUOUS {number}')
            require(not any(p['afterParagraphText'] == anchor for p in panels), 'PANEL_ANCHOR_COLLISION')
            panels.append({'numbers': [number], 'columns': 1, 'pageTop': False,
                           'afterParagraphText': anchor, 'keepFollowingAfterPanel': True})
            figures.append({'mode': 'band', 'numbers': [number], 'columns': 1,
                            'markerPrefix': caption, 'captions': [caption], 'flowAroundText': True})
        else:
            figures.append({'mode': 'inline', 'number': number, 'captionPrefix': caption})
    formulas = {'mode': 'none', 'items': []}
    if report['formulaCount']:
        require(native_manifest is not None, 'NATIVE_IDMS_MANIFEST_REQUIRED')
        formulas = read(native_manifest)
        require(formulas.get('mode') == 'native-idms' and len(formulas.get('entries', [])) == report['formulaCount'],
                'NATIVE_IDMS_MANIFEST_COUNT')
        require(len({e['number'] for e in formulas['entries']}) == report['formulaCount'], 'NATIVE_IDMS_DUPLICATE')
        for entry in formulas['entries']:
            path = Path(entry['path'])
            require(path.is_absolute() and path.suffix.lower() == '.idms' and path.is_file() and
                    digest(path) == entry['sha256'].lower() and entry['basePointSize'] == 10.5,
                    'NATIVE_IDMS_PROVENANCE')
    headers = read(table_headers) if table_headers else {}
    reviewed_kinds = read(table_kinds) if table_kinds else {}
    require(isinstance(reviewed_kinds, dict), 'TABLE_KINDS_FORMAT')
    require(all(str(i) in {str(n) for n in range(1, report['tableCount'] + 1)}
                for i in reviewed_kinds), 'TABLE_KINDS_INDEX')
    require(len(supp['tables']) == len(structures['tables']) == report['tableCount'], 'TABLE_SOURCE_COUNT')
    tables = []
    for i, structure in enumerate(structures['tables']):
        header = headers.get(str(i + 1), structure.get('headerRows'))
        require(isinstance(header, int) and not isinstance(header, bool) and 0 < header <= len(supp['tables'][i]['rows']),
                f'TABLE_HEADER_REQUIRED {i + 1}')
        structure['headerRows'] = header
        candidates = [n for n, b in enumerate(blocks) if b['role'] == 'table_gap' and
                      b.get('tableNumber') == i + 1]
        require(len(candidates) == 1, f'TABLE_BLOCK_AMBIGUOUS {i + 1}')
        review = reviewed_kinds.get(str(i + 1))
        if review is not None:
            require(isinstance(review, dict) and review.get('kind') in ('ordinary', 'three-line', 'algorithm')
                    and isinstance(review.get('reviewEvidence'), str) and review['reviewEvidence'].strip(),
                    f'TABLE_KIND_REVIEW_REQUIRED {i + 1}')
        kind = review['kind'] if review else 'unclassified'
        tables.append({'number': i + 1, 'sourceIndex': i, 'blockIndex': candidates[0],
                       'kind': kind, 'reviewEvidence': review['reviewEvidence'] if review else None,
                       'sourceEvidence': structure.get('sourceFormatting', {})})
    source_records = check_paragraphs(supp, indices, logical)
    destination.mkdir(parents=True, exist_ok=True)
    output_document.parent.mkdir(parents=True, exist_ok=True)
    files = {'logical': destination / 'logical-article.json', 'supplement': destination / 'supplement.json',
             'tables': destination / 'table-structure.json', 'paragraphs': destination / 'source-paragraphs.json',
             'sourceTables': destination / 'source-tables.json', 'audit': destination / '检查配置.json',
             'job': destination / 'assembly-job.json', 'manifest': destination / 'task-manifest.json'}
    require(not any(p.exists() for p in files.values()), 'OUTPUT_CONFIG_EXISTS')
    write(files['logical'], logical)
    write(files['supplement'], supp)
    write(files['tables'], structures)
    write(files['paragraphs'], source_records)
    write(files['sourceTables'], {'tables': copy.deepcopy(supp['tables'])})
    template_version = base.get('templateContractVersion', 'qa-template-contract-v2')
    audit = {'configVersion': 'source-derived-job-v1', 'templateContractVersion': template_version,
             'documentPath': str(output_document),
             'auditPath': str(output_document.parent / '初排.audit.xml'), 'bindings': [],
             'sourceParagraphs': str(files['paragraphs']), 'sourceTables': str(files['sourceTables']),
             'sourceParagraphProvenance': {'path': str(raw_paragraphs), 'sha256': digest(raw_paragraphs),
                                           'transformation': 'front-roles-plus-logical-blocks-remove-object-markers-v1'},
             'sourceLogicalArticle': str(files['logical']), 'sourceTextFormatting': blocks,
             'figureCount': len(captions), 'graphicCount': len(captions), 'tableCount': len(tables),
             'pageBudget': pages, 'startOnLeft': page_number_start % 2 == 0,
             'assets': assets, 'requireOriginalFigureLinks': True, 'requireNativeFormulaPaste': True,
             'tableHeaderRows': [s['headerRows'] for s in structures['tables']],
             'tableKinds': [{key: t[key] for key in ('number', 'kind', 'reviewEvidence', 'sourceEvidence')} for t in tables],
             'mergedEmptyCells': vertical_merges(supp['tables'], structures['tables']),
             'fixedFrames': [dict(front_contract['frontAnchor'], role='front'), dict(front_contract['footerAnchor'], role='footer')],
             'templateAnchors': [], 'figurePanels': [], 'localBottomPairs': [], 'widePanelFrameBreaks': [],
             'reviewedContinuedTables': [], 'tableTextRuns': table_text_runs(supp['tables']),
             'sourceCaptionRuns': [], 'formulaNumbers': []}
    audit['doiContract'] = {'text': base['frontmatter'].get('doiText'), 'source': 'reference-template-placeholder'}
    audit['receivedSeparatorBaselineGapMm'] = front_contract.get('receivedSeparatorBaselineGapMm')
    audit['formulaCacheContract'] = [{key: entry[key] for key in
                                     ('number', 'cacheKey', 'sha256', 'sourceSha256', 'ruleVersion')}
                                    for entry in formulas.get('entries', [])]
    template_manifest = Path(str(template) + '.template.json')
    if template_manifest.is_file():
        template_record = read(template_manifest)
        master_text = template_record.get('masterTextExpectations')
        if master_text:
            require(template_record.get('outputSha256', '').upper() == digest(template).upper(), 'TEMPLATE_MANIFEST_CHANGED')
            audit['masterTextExpectations'] = master_text
            audit['requireMasterTextContract'] = True
    if group_provenance:
        audit['figureGroupProvenance'] = group_provenance
    if conversion:
        audit['sourceConversion'] = conversion
    write(files['audit'], audit)
    module_dir = Path(__file__).resolve().parent
    task_id = 'article-' + source_hash[:16]
    job = {'schemaVersion': 1, 'configVersion': 'source-derived-job-v1', 'taskId': task_id, 'article': author,
           'templateContractVersion': template_version, 'allowPageGrowth': True,
           'templatePath': str(template), 'outputPath': str(output_document),
           'logicalArticlePath': str(files['logical']), 'supplementPath': str(files['supplement']),
           'tableStructurePath': str(files['tables']), 'auditConfigPath': str(files['audit']),
           'statePath': str(destination / 'assembly.state.json'), 'resultPath': str(destination / 'assembly.result.json'),
           'pageNumberStart': page_number_start,
           'expected': {'blocks': len(blocks), 'tables': len(tables), 'figures': len(captions),
                        'formulas': report['formulaCount'], 'pages': pages},
           'templateContract': template_contract, 'frontmatter': {'indices': indices, 'contract': front_contract,
           'doiText': base['frontmatter'].get('doiText'), 'restoreSourceFormatting': True}, 'assets': assets, 'tables': tables,
           'formulas': formulas, 'figures': figures, 'panels': panels, 'paragraphAdjustments': [],
           'panelPositionSearch': False, 'modules': {'documentSession': str(module_dir / 'journal_document_session.jsxinc'),
           'frontmatter': str(module_dir / 'journal_frontmatter.jsxinc')},
           'importerPath': str(module_dir / 'import_word_article_to_indesign.jsx')}
    inputs = [('source-word', source), ('template', template), ('logical-article', files['logical']),
              ('supplement', files['supplement']), ('table-structure', files['tables']), ('audit-config', files['audit']),
              ('source-paragraphs-original', raw_paragraphs), ('source-paragraphs-check', files['paragraphs']),
              ('source-tables-check', files['sourceTables'])]
    if conversion:
        job['sourceConversion'] = conversion
        inputs.append(('source-original-doc', original_doc))
    inputs += [(p.name, p) for p in module_dir.glob('*.jsx*')]
    inputs += [('figure-' + str(a['number']), Path(a['path'])) for a in assets]
    if table_kinds:
        inputs.append(('table-kinds-reviewed', Path(table_kinds)))
    if group_provenance:
        job['figureGroupProvenance'] = copy.deepcopy(group_provenance)
        inputs.append(('figure-groups', Path(group_provenance['path'])))
    job['inputs'] = [{'name': name, 'path': str(path), 'sha256': digest(path)} for name, path in inputs]
    write(files['job'], job)
    manifest = {'taskId': task_id, 'author': author, 'sourceWord': str(source),
                'articleJson': str(files['logical']), 'tableJson': str(files['sourceTables']),
                'figureDirectory': str(figure_directory), 'outputDirectory': str(output_document.parent),
                'expectedPages': pages, 'assemblyJob': str(files['job']), 'auditConfigPath': str(files['audit'])}
    if conversion:
        manifest['sourceConversion'] = conversion
    if native_manifest:
        manifest['formulaManifest'] = str(Path(native_manifest).resolve())
    write(files['manifest'], manifest)
    return {'taskId': task_id, 'job': str(files['job']), 'manifest': str(files['manifest']), 'expected': job['expected']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('extracted', 'figure-directory', 'author', 'template', 'destination', 'output-document'):
        parser.add_argument('--' + name, required=True)
    for name in ('reference', 'contracts', 'inventory', 'native-manifest', 'table-headers', 'table-kinds', 'original-doc', 'figure-groups'):
        parser.add_argument('--' + name)
    parser.add_argument('--pages', type=int)
    parser.add_argument('--page-number-start', type=int, default=2)
    parser.add_argument('--fit-near-column', action='store_true')
    args = vars(parser.parse_args())
    print(json.dumps(build(**args), ensure_ascii=False))


if __name__ == '__main__':
    main()
