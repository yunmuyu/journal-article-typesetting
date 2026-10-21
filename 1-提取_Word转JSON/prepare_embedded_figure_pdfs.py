"""Preserve single raster figures at their authored Word dimensions, with provenance."""
import argparse
import hashlib
import io
import json
import shutil
from pathlib import Path

import fitz
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-map', 'probe', 'author', 'existing-directory', 'output-directory'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    source = json.loads(Path(args.source_map).read_text(encoding='utf-8-sig'))
    probe = json.loads(Path(args.probe).read_text(encoding='utf-8-sig'))
    word = next(a for a in probe['assets'] if a['id'] == 'word')
    if word['sha256'].lower() != source['sourceSha256'].lower():
        raise ValueError('FIGURE_WORD_PROVENANCE_MISMATCH')
    output = Path(args.output_directory).resolve()
    output.mkdir(exist_ok=False)
    records = []
    for figure in source['figures']:
        number = figure['number']
        target = output / f'{args.author}-图{number}.pdf'
        existing = Path(args.existing_directory) / target.name
        if existing.is_file():
            shutil.copyfile(existing, target)
            records.append({'number': number, 'source': str(existing.resolve()), 'output': str(target), 'mode': 'existing-pdf', 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
            continue
        described = next(f for f in word['probe']['figures'] if int(f['number']) == number)
        if len(described['images']) != 1 or figure.get('embedding'):
            raise ValueError(f'FIGURE_SINGLE_RASTER_REQUIRED {number}')
        metadata = described['images'][0]
        raster = Path(figure['path'])
        raw = raster.read_bytes()
        if hashlib.sha256(raw).hexdigest() != metadata['asset_sha256']:
            raise ValueError(f'FIGURE_RASTER_HASH_MISMATCH {number}')
        width, height = metadata['word_extent_mm']
        if min(width, height) <= 0:
            raise ValueError(f'FIGURE_WORD_DIMENSION_REQUIRED {number}')
        with fitz.open() as document:
            page = document.new_page(width=width * 72 / 25.4, height=height * 72 / 25.4)
            page.insert_image(page.rect, stream=raw, keep_proportion=False)
            document.save(target)
        with fitz.open(target) as check:
            if len(check) != 1 or abs(check[0].rect.width * 25.4 / 72 - width) > .001 or abs(check[0].rect.height * 25.4 / 72 - height) > .001:
                raise ValueError(f'FIGURE_PDF_DIMENSION_CHANGED {number}')
            extracted = check.extract_image(check[0].get_images()[0][0])['image']
            with Image.open(io.BytesIO(raw)) as original, Image.open(io.BytesIO(extracted)) as embedded:
                if original.size != embedded.size or original.convert('RGB').tobytes() != embedded.convert('RGB').tobytes():
                    raise ValueError(f'FIGURE_PIXELS_CHANGED {number}')
            check[0].get_pixmap(dpi=150).save(output / f'preview-{number}.png')
        records.append({'number': number, 'source': str(raster), 'sourceSha256': metadata['asset_sha256'], 'output': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'widthMm': width, 'heightMm': height, 'mode': 'raster-preserved', 'pixelsIdentical': True})
    (output / 'provenance.json').write_text(json.dumps({'sourceWordSHA256': source['sourceSha256'], 'figures': records}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'figures': len(records), 'preservedRaster': sum(r['mode'] == 'raster-preserved' for r in records)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
