"""Read-only DOCX extraction. python extract_journal_article.py INPUT.docx -o DIRECTORY.

Offsets are UTF-16 code units in the emitted paragraph text. Formula/figure
markers retain object positions; no equation number is invented. OMML and
missing equation previews block readiness while leaving diagnostic JSON.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import posixpath
import re
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

from word_numbering import WordNumbering
from docx_to_id_json import W, W_NS, M_NS, NS, attr, body_items, inline_items, paragraph_role, run_content, run_flags

R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
O = '{urn:schemas-microsoft-com:office:office}'
V = '{urn:schemas-microsoft-com:vml}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
M = '{' + M_NS + '}'


UNICODE_SCRIPT_MAP = {
    **{char: (value, 'superscript') for char, value in zip('¹²³⁰ⁱ⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ', '1230i456789+-=()n')},
    **{char: (value, 'subscript') for char, value in zip('₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₕₖₗₘₙₚₛₜ', '0123456789+-=()aeoxhklmnpst')},
}


def normalize_unicode_scripts(paragraph: dict) -> dict:
    original = paragraph['text']
    changes, pieces, offset = [], [], 0
    for char in original:
        length = len(char.encode('utf-16-le')) // 2
        if char in UNICODE_SCRIPT_MAP:
            replacement, position = UNICODE_SCRIPT_MAP[char]
            changes.append({'start': offset, 'end': offset + length, 'source': char,
                            'replacement': replacement, 'position': position})
            pieces.append(replacement)
        else:
            pieces.append(char)
        offset += length
    if not changes:
        return paragraph
    boundaries = {0, offset}
    for run in paragraph['runs']:
        boundaries.update((run['start'], run['end']))
    for change in changes:
        boundaries.update((change['start'], change['end']))
    runs = []
    ordered = sorted(boundaries)
    for start, end in zip(ordered, ordered[1:]):
        flags = {}
        for run in paragraph['runs']:
            if run['start'] <= start and end <= run['end']:
                flags.update({k: v for k, v in run.items() if k not in ('start', 'end')})
        for change in changes:
            if change['start'] <= start and end <= change['end']:
                if 'position' in flags and flags['position'] != change['position']:
                    raise ValueError('UNICODE_SCRIPT_POSITION_CONFLICT: ' + str(paragraph.get('location', {})) + ' at ' + str(start))
                flags['position'] = change['position']
        if flags:
            if runs and runs[-1]['end'] == start and {k: v for k, v in runs[-1].items() if k not in ('start', 'end')} == flags:
                runs[-1]['end'] = end
            else:
                runs.append({'start': start, 'end': end, **flags})
    text = ''.join(pieces)
    encoded = text.encode('utf-16-le')
    return {**paragraph, 'text': text, 'runs': runs, 'unicodeScriptTransformations': changes,
            'superscripts': [encoded[r['start'] * 2:r['end'] * 2].decode('utf-16-le') for r in runs if r.get('position') == 'superscript'],
            'subscripts': [encoded[r['start'] * 2:r['end'] * 2].decode('utf-16-le') for r in runs if r.get('position') == 'subscript']}


def project_body_paragraph(paragraph: dict) -> dict:
    text = paragraph['text']
    removed = [(len(text[:match.start()].encode('utf-16-le')) // 2, len(text[:match.end()].encode('utf-16-le')) // 2) for match in re.finditer(r'\[\[FIGURE:\d+\]\]', text)]

    def position(offset):
        return offset - sum(max(0, min(offset, end) - start) for start, end in removed)

    runs = []
    for run in paragraph['runs']:
        start, end = position(run['start']), position(run['end'])
        if start < end:
            runs.append({**run, 'start': start, 'end': end})
    return {**paragraph, 'text': re.sub(r'\[\[FIGURE:\d+\]\]', '', text), 'runs': runs}


def extract_article(source: Path, output: Path, body_start_text: str = '0 引言') -> dict:
    source = source.resolve()
    output = output.resolve()
    if not zipfile.is_zipfile(source):
        raise ValueError('SOURCE_NOT_DOCX_ZIP: convert legacy .doc with Word before extraction')
    if output == source.parent:
        raise ValueError('OUTPUT_MUST_BE_SEPARATE_FROM_SOURCE_DIRECTORY')
    output.mkdir(parents=True, exist_ok=True)
    assets, formulas, figures, omml, issues, paragraphs, tables, structures = [], [], [], [], [], [], [], []
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    with zipfile.ZipFile(source) as z:
        if 'word/document.xml' not in z.namelist() or '[Content_Types].xml' not in z.namelist():
            raise ValueError('SOURCE_NOT_WORD_DOCUMENT')
        root = ET.fromstring(z.read('word/document.xml'))
        WordNumbering(z).materialize(root)
        body = root.find('w:body', NS)
        if body is None:
            raise ValueError('DOCUMENT_BODY_MISSING')
        relationships = {}
        if 'word/_rels/document.xml.rels' in z.namelist():
            for rel in ET.fromstring(z.read('word/_rels/document.xml.rels')):
                target = rel.get('Target', '')
                relationships[rel.get('Id')] = {'target': target, 'type': rel.get('Type'), 'external': rel.get('TargetMode') == 'External', 'part': posixpath.normpath(posixpath.join('word', target.lstrip('/'))) if not target.startswith('/') else target.lstrip('/')}

        def save_asset(rid, stem):
            rel = relationships.get(rid)
            if not rel or rel['external'] or rel['part'] not in z.namelist():
                issues.append({'code': 'ASSET_RELATIONSHIP_MISSING', 'relationshipId': rid})
                return None
            part = rel['part']
            data = z.read(part)
            suffix = Path(part).suffix.lower() or '.bin'
            name = stem + suffix
            path = output / name
            path.write_bytes(data)
            record = {'relationshipId': rid, 'sourcePart': part, 'path': str(path), 'sha256': hashlib.sha256(data).hexdigest()}
            assets.append(record)
            return record

        def parse_paragraph(p, location):
            text, runs, objects = '', [], []
            for item in inline_items(p):
                offset = len(text.encode('utf-16-le')) // 2
                if item.tag == M + 'oMath':
                    number = len(omml) + 1
                    marker = '[[OMML:%d]]' % number
                    omml.append({'number': number, 'location': location, 'start': offset, 'end': offset + len(marker), 'xml': ET.tostring(item, encoding='unicode')})
                    text += marker
                    continue
                chunk = ''
                for child in item:
                    if child.tag == W + 'rPr':
                        continue
                    if child.tag in (W + 'object', W + 'drawing', W + 'pict'):
                        ole = child.find('.//' + O + 'OLEObject')
                        progid = ole.get('ProgID', '') if ole is not None else ''
                        is_formula = bool(re.match(r'^(?:Equation(?:\.|$)|MathType(?:\.|$))', progid, re.I))
                        group = formulas if is_formula else figures
                        number = len(group) + 1
                        marker = ('⟦EQ-%03d⟧' % number) if is_formula else ('[[FIGURE:%d]]' % number)
                        preview = child.find('.//' + V + 'imagedata')
                        if preview is None:
                            preview = child.find('.//' + A + 'blip')
                        rid = (preview.get(R + 'id') or preview.get(R + 'embed') or preview.get(R + 'link')) if preview is not None else None
                        stem = ('formula-' if is_formula else 'figure-') + str(number)
                        asset = save_asset(rid, stem) if rid else None
                        ole_rid = ole.get(R + 'id') if ole is not None else None
                        embedding = save_asset(ole_rid, stem + '-ole') if ole_rid else None
                        shape = child.find('.//' + V + 'shape')
                        start = offset + len(chunk.encode('utf-16-le')) // 2
                        record = {'number': number, 'marker': marker, 'location': location, 'start': start, 'end': start + len(marker), 'sourceStart': len(re.sub(r'⟦EQ-\d+⟧|\[\[(?:FIGURE|OMML):\d+\]\]', '', text + chunk).encode('utf-16-le')) // 2, 'progId': progid or None, 'preview': asset, 'embedding': embedding, 'shape': shape.get('style') if shape is not None else None, 'path': asset['path'] if asset else None}
                        group.append(record)
                        objects.append(record)
                        chunk += marker
                        if asset is None:
                            issues.append({'code': 'FORMULA_PREVIEW_MISSING' if is_formula else 'FIGURE_PREVIEW_MISSING', 'number': number, 'location': location})
                    else:
                        holder = ET.Element(W + 'r')
                        holder.append(child)
                        chunk += run_content(holder)
                text += chunk
                flags = run_flags(item, chunk)
                if flags and chunk:
                    runs.append({'start': offset, 'end': len(text.encode('utf-16-le')) // 2, **flags})
            # The source text excludes object markers but never removes source punctuation.
            plain = re.sub(r'⟦EQ-\d+⟧|\[\[(?:FIGURE|OMML):\d+\]\]', '', text)
            for record in objects:
                if record['progId'] and re.match(r'^(?:Equation(?:\.|$)|MathType(?:\.|$))', record['progId'], re.I):
                    number_match = re.fullmatch(r'\s*[（(]\s*(\d+)\s*[）)]\s*', plain)
                    record['inline'] = bool(plain.strip()) and number_match is None
                    record['displayNumber'] = number_match.group(1) if number_match and not record['inline'] else None
            return {'text': text, 'runs': runs, 'sourceText': plain, 'location': location, 'superscripts': [text.encode('utf-16-le')[r['start'] * 2:r['end'] * 2].decode('utf-16-le') for r in runs if r.get('position') == 'superscript'], 'subscripts': [text.encode('utf-16-le')[r['start'] * 2:r['end'] * 2].decode('utf-16-le') for r in runs if r.get('position') == 'subscript']}

        def border_evidence(container, selector):
            borders = container.find(selector, NS)
            return {side: {'val': attr(edge, 'val'), 'sz': attr(edge, 'sz')}
                    for side in ('top', 'bottom', 'left', 'right', 'insideH', 'insideV')
                    if borders is not None and (edge := borders.find('w:' + side, NS)) is not None}

        for body_index, element in enumerate(body_items(body)):
            if element.tag == W + 'p':
                record = parse_paragraph(element, {'bodyIndex': body_index, 'paragraphIndex': len(paragraphs)})
                record['index'] = len(paragraphs)
                record['role'] = paragraph_role(record['sourceText'], record['index'] + 1)
                paragraphs.append(record)
            else:
                number = len(tables) + 1
                rows, structure_rows, header_rows = [], [], 0
                widths = [int(attr(c, 'w') or 0) for c in element.findall('w:tblGrid/w:gridCol', NS)]
                for row_index, row in enumerate(element.findall('w:tr', NS)):
                    header = row.find('w:trPr/w:tblHeader', NS)
                    if header is not None and attr(header, 'val') not in ('0', 'false', 'off') and header_rows == row_index:
                        header_rows += 1
                    cells, structure_cells = [], []
                    column = int(attr(row.find('w:trPr/w:gridBefore', NS), 'val') or 0)
                    for cell_index, cell in enumerate(row.findall('w:tc', NS)):
                        cell_paras = [parse_paragraph(p, {'bodyIndex': body_index, 'table': number, 'row': row_index, 'cell': cell_index, 'paragraph': i}) for i, p in enumerate(cell.findall('w:p', NS))]
                        text, cell_runs = '', []
                        for cp in cell_paras:
                            shift = len(text.encode('utf-16-le')) // 2
                            cell_runs.extend({**r, 'start': r['start'] + shift, 'end': r['end'] + shift} for r in cp['runs'])
                            text += cp['text'] + '\n'
                        cells.append({'text': text.rstrip('\n'), 'runs': cell_runs, 'paragraphs': cell_paras})
                        span = int(attr(cell.find('w:tcPr/w:gridSpan', NS), 'val') or 1)
                        merge = cell.find('w:tcPr/w:vMerge', NS)
                        structure_cells.append({'start': column, 'span': span, 'gridSpan': span, 'vertical': (attr(merge, 'val') or 'continue') if merge is not None else None, 'width': attr(cell.find('w:tcPr/w:tcW', NS), 'w'), 'widthType': attr(cell.find('w:tcPr/w:tcW', NS), 'type'),
                                                'borders': border_evidence(cell, 'w:tcPr/w:tcBorders')})
                        column += span
                    rows.append(cells)
                    structure_rows.append(structure_cells)
                tables.append({'number': number, 'bodyIndex': body_index, 'rows': [[c['text'] for c in row] for row in rows], 'cellRuns': [[c['runs'] for c in row] for row in rows], 'cellParagraphs': [[c['paragraphs'] for c in row] for row in rows]})
                structures.append({'number': number, 'widths': widths, 'rows': structure_rows, 'headerRows': header_rows, 'headerRowsSource': 'explicit-w:tblHeader',
                                   'sourceFormatting': {'styleId': attr(element.find('w:tblPr/w:tblStyle', NS), 'val'),
                                                        'borders': border_evidence(element, 'w:tblPr/w:tblBorders')},
                                   'needsInput': [] if header_rows else ['headerRows not explicitly marked in source']})
    starts = [p['index'] for p in paragraphs if p['sourceText'].strip() == body_start_text.strip() or (body_start_text == '0 引言' and re.fullmatch(r'\s*0\s*引\s*言\s*', p['sourceText']))]
    start = starts[0] if len(starts) == 1 else None
    if start is None:
        issues.append({'code': 'BODY_START_AMBIGUOUS', 'candidates': starts})
    front = []
    received, funds = [], []
    for p in paragraphs:
        if re.match(r'^\s*收稿日期', p['sourceText']):
            received.append(p)
        if re.match(r'^\s*(?:基金项目|基金资助|项目来源)', p['sourceText']):
            funds.append(p)
        if start is not None and p['index'] < start:
            candidates = []
            if re.match(r'^\s*(摘要|关键词|Abstract|Key\s*words)\s*[:：]', p['sourceText'], re.I):
                candidates.append('abstract_or_keywords')
            if re.match(r'^\s*(基金项目|收稿日期)', p['sourceText']):
                candidates.append('metadata')
            front.append({**p, 'roleCandidates': candidates, 'needsInput': not bool(candidates)})
    blocks = []
    if start is not None:
        start_body = paragraphs[start]['location']['bodyIndex']
        ordered = [(p['location']['bodyIndex'], normalize_unicode_scripts(project_body_paragraph(p))) for p in paragraphs if p['index'] >= start]
        ordered += [(t['bodyIndex'], t) for t in tables if t['bodyIndex'] >= start_body]
        for _, p in sorted(ordered, key=lambda pair: pair[0]):
            if 'rows' in p:
                blocks.append({'role': 'table_gap', 'text': '   ', 'runs': [], 'tableNumber': p['number']})
            elif p['text'].strip():
                role = p['role']
                # One display formula, or several side-by-side display formulas separated only by
                # whitespace (e.g. "⟦EQ-007⟧     ⟦EQ-008⟧"); an optional source number follows the last.
                formula_only = re.fullmatch(r'\s*⟦EQ-\d+⟧(?:\s+⟦EQ-\d+⟧)*\s*(?:[（(]\s*\d+\s*[）)])?\s*', p['text'])
                blocks.append({'role': 'math' if formula_only else role, 'text': p['text'], 'runs': p['runs'], 'sourceParagraphIndex': p['index'], **({'unicodeScriptTransformations': p['unicodeScriptTransformations']} if p.get('unicodeScriptTransformations') else {})})
        for seq, block in enumerate(blocks, 1):
            block['seq'] = seq
    front = [normalize_unicode_scripts(p) for p in front]
    for table in tables:
        table['cellUnicodeScriptTransformations'] = []
        for row_index, row in enumerate(table['rows']):
            row_changes = []
            for cell_index, text in enumerate(row):
                projected = normalize_unicode_scripts({'text': text, 'runs': table['cellRuns'][row_index][cell_index],
                    'location': {'table': table['number'], 'row': row_index, 'cell': cell_index}})
                row[cell_index] = projected['text']
                table['cellRuns'][row_index][cell_index] = projected['runs']
                row_changes.append(projected.get('unicodeScriptTransformations', []))
            table['cellUnicodeScriptTransformations'].append(row_changes)
    if omml:
        issues.append({'code': 'OMML_REQUIRES_RENDERING', 'count': len(omml)})
    provenance = {'source': str(source), 'sourceSha256': source_hash, 'offsetUnit': 'utf16', 'schemaVersion': 1, 'bodyStartText': body_start_text, 'unicodeScriptProjection': {'version': 'unicode-script-position-v1', 'mappingSource': 'import_word_article_to_indesign.jsx#normalizeUnicodeSuperSubscript', 'offsetsPreserved': True, 'conflictPolicy': 'block-conflicting-explicit-position'}}
    result = {**provenance, 'status': 'blocked' if issues else 'extracted', 'issues': issues, 'paragraphCount': len(paragraphs), 'tableCount': len(tables), 'formulaCount': len(formulas), 'figureCount': len(figures), 'ommlCount': len(omml)}
    data = {
        'logical-article.json': {**provenance, 'blocks': blocks, 'summary': {r: sum(b['role'] == r for b in blocks) for r in sorted({b['role'] for b in blocks})}},
        'supplement.json': {**provenance, 'front': front, 'received': received[0]['sourceText'] if len(received) == 1 else '', 'receivedCandidates': received, 'fundCandidates': funds, 'unitCandidates': [p for p in front if re.search(r'大学|学院|研究院|研究所|公司|University|College|Institute|Laboratory|Corporation', p['sourceText'], re.I)], 'tables': tables, 'formulas': formulas, 'figures': figures},
        'table-structure.json': {**provenance, 'tables': structures},
        'source-paragraphs.json': paragraphs,
        'formula-source-map.json': {**provenance, 'offsetText': 'source-paragraphs.json text (before body figure projection)', 'formulas': formulas, 'omml': omml},
        'figure-source-map.json': {**provenance, 'offsetText': 'source-paragraphs.json text (before body figure projection)', 'figures': figures},
        'extraction-report.json': {**result, 'assets': assets, 'relationships': relationships},
    }
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise RuntimeError('SOURCE_CHANGED_DURING_EXTRACTION')
    for name, payload in data.items():
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('docx', type=Path)
    parser.add_argument('-o', '--output', type=Path, required=True)
    parser.add_argument('--body-start-text', default='0 引言', help='Exact source paragraph identifying body start; no automatic heading guess')
    args = parser.parse_args()
    try:
        result = extract_article(args.docx, args.output, args.body_start_text)
    except (ValueError, zipfile.BadZipFile, ET.ParseError) as error:
        parser.exit(2, str(error) + '\n')
    print(json.dumps(result, ensure_ascii=False))
    return 2 if result['status'] == 'blocked' else 0


if __name__ == '__main__':
    raise SystemExit(main())
