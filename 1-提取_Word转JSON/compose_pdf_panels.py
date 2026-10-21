"""Compose reviewed single-page PDF panels without changing their source files."""
import argparse
import hashlib
import json
from pathlib import Path

import fitz


def compose(spec_path, output):
    spec_path, output = Path(spec_path).resolve(), Path(output).resolve()
    spec = json.loads(spec_path.read_text(encoding='utf-8-sig'))
    sources = [Path(p).resolve() for p in spec['sources']]
    columns, gap = spec['columns'], float(spec.get('gapMm', 2)) * 72 / 25.4
    if not isinstance(columns, int) or isinstance(columns, bool) or columns < 1 or gap < 0:
        raise ValueError('PANEL_LAYOUT')
    if not sources or len(set(sources)) != len(sources) or output in sources or output.exists():
        raise ValueError('PANEL_OUTPUT_OR_SOURCES')
    documents, provenance = [], []
    for source in sources:
        doc = fitz.open(source)
        if len(doc) != 1:
            raise ValueError('SINGLE_PAGE_REQUIRED ' + str(source))
        page = doc[0]
        page.set_cropbox(page.mediabox)
        documents.append(doc)
        provenance.append({'path': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                           'widthPt': page.rect.width, 'heightPt': page.rect.height})
    widths = [max(documents[i][0].rect.width for i in range(c, len(documents), columns))
              for c in range(min(columns, len(documents)))]
    natural_width = sum(widths)
    scale = 1.0
    if 'widthMm' in spec:
        scale = (float(spec['widthMm']) * 72 / 25.4 - gap * (len(widths) - 1)) / natural_width
        if scale <= 0:
            raise ValueError('PANEL_WIDTH')
        if abs(scale - 1) > 0.00001 and (not spec.get('allowRasterScaling') or
                any(d[0].get_text().strip() or not d[0].get_images() for d in documents)):
            raise ValueError('TEXT_OR_VECTOR_PANEL_RESCALE_REQUIRES_REBUILD')
    heights = [max(d[0].rect.height for d in documents[r:r + columns]) * scale
               for r in range(0, len(documents), columns)]
    result = fitz.open()
    page = result.new_page(width=natural_width * scale + gap * (len(widths) - 1),
                           height=sum(heights) + gap * (len(heights) - 1))
    for i, doc in enumerate(documents):
        row, column = divmod(i, columns)
        x = sum(widths[:column]) * scale + column * gap
        y = sum(heights[:row]) + row * gap
        rect = fitz.Rect(x, y, x + doc[0].rect.width * scale, y + doc[0].rect.height * scale)
        page.show_pdf_page(rect, doc, 0)
        provenance[i]['placementPt'] = list(rect)
        provenance[i]['scale'] = scale
    output.parent.mkdir(parents=True, exist_ok=True)
    result.save(output)
    page.get_pixmap(dpi=150).save(output.with_suffix('.png'))
    for item in provenance:
        if hashlib.sha256(Path(item['path']).read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('SOURCE_CHANGED')
    record = {'output': str(output), 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'sizeMm': [page.rect.width * 25.4 / 72, page.rect.height * 25.4 / 72],
              'spec': str(spec_path), 'specSHA256': hashlib.sha256(spec_path.read_bytes()).hexdigest(),
              'panels': provenance, 'sourceFilesUnchanged': True}
    output.with_suffix('.provenance.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(output), 'panels': len(documents), 'sizeMm': record['sizeMm']}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    compose(args.spec, args.output)
