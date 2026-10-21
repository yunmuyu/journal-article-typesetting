"""Universal recoverable entry for journal article typesetting pipeline.

Usage: python run_journal_article.py CONFIG.json

Stages: extract → formula-cache → prepare-job → assemble → validate
Checkpoints preserve passed stages. Rerun same config to retry from failure.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write_json(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_stage(stage_name, command, work_dir, checkpoint_path, force_rerun=False):
    """Run stage if not completed or forced. Return True if stage passed."""
    checkpoint = read_json(checkpoint_path) if Path(checkpoint_path).exists() else {}
    stages = checkpoint.get('stages', {})

    if not force_rerun and stages.get(stage_name, {}).get('status') == 'passed':
        print(f'[{stage_name}] Checkpoint already passed, skipping')
        return True

    print(f'[{stage_name}] Running: {" ".join(command)}')
    start = time.time()

    result = subprocess.run(command, cwd=work_dir, capture_output=True, text=True, encoding='utf-8')
    elapsed = time.time() - start

    status = 'passed' if result.returncode == 0 else 'failed'
    stages[stage_name] = {
        'status': status,
        'returncode': result.returncode,
        'elapsed': round(elapsed, 3),
        'stdout': result.stdout[-2000:] if len(result.stdout) > 2000 else result.stdout,
        'stderr': result.stderr[-2000:] if len(result.stderr) > 2000 else result.stderr,
    }
    checkpoint['stages'] = stages
    write_json(checkpoint_path, checkpoint)

    if status == 'failed':
        print(f'[{stage_name}] FAILED (exit {result.returncode})', file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return False

    print(f'[{stage_name}] Passed in {elapsed:.2f}s')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path, help='Article configuration JSON')
    parser.add_argument('--force-stage', help='Force rerun specific stage even if checkpoint passed')
    args = parser.parse_args()

    config = read_json(args.config)
    work_root = Path(config['workRoot'])
    work_root.mkdir(parents=True, exist_ok=True)

    checkpoint_path = work_root / 'pipeline-checkpoint.json'
    extraction_dir = work_root / 'extracted'
    cache_root = work_root / 'formula-cache'
    manifest_path = work_root / 'formula-manifest.json'
    job_path = work_root / 'assembly-job.json'
    qa_indd = work_root / 'QA.indd'
    qa_pdf = work_root / 'QA-preview.pdf'
    validation_report = work_root / 'validation-report.json'
    delivery_report = work_root / 'delivery.json'

    python_exe = config.get('pythonExe', 'python')
    source_docx = Path(config['sourceDocx'])

    if not source_docx.exists():
        sys.exit(f'ERROR: Source document not found: {source_docx}')

    start_time = time.time()
    rework_count = 0

    # Stage 1: Extract
    force = args.force_stage == 'extract'
    if not run_stage('extract', [
        python_exe, '-I',
        'G:/000完成项目/期刊文章自动排版系统/1-提取_Word转JSON/extract_journal_article.py',
        str(source_docx),
        '-o', str(extraction_dir),
    ], work_root, checkpoint_path, force):
        sys.exit(1)

    extraction_report = read_json(extraction_dir / 'extraction-report.json')
    if extraction_report['status'] != 'extracted':
        sys.exit(f'ERROR: Extraction blocked: {extraction_report.get("issues", [])}')

    formula_count = extraction_report['formulaCount']

    # Stage 2: Formula cache (Plan)
    force = args.force_stage == 'formula-cache-plan'
    if not run_stage('formula-cache-plan', [
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', 'G:/000完成项目/期刊文章自动排版系统/2-导入_InDesign/Prepare-JournalFormulaCache.ps1',
        '-InputDirectory', str(extraction_dir),
        '-CacheRoot', str(cache_root),
        '-ManifestPath', str(manifest_path) + '.plan',
        '-Numbers', ','.join(map(str, range(1, formula_count + 1))),
        '-Mode', 'Plan',
    ], work_root, checkpoint_path, force):
        sys.exit(2)

    # Stage 3: Formula cache (Execute)
    force = args.force_stage == 'formula-cache-execute'
    if not run_stage('formula-cache-execute', [
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', 'G:/000完成项目/期刊文章自动排版系统/2-导入_InDesign/Prepare-JournalFormulaCache.ps1',
        '-InputDirectory', str(extraction_dir),
        '-CacheRoot', str(cache_root),
        '-ManifestPath', str(manifest_path),
        '-Numbers', ','.join(map(str, range(1, formula_count + 1))),
        '-Mode', 'Execute',
    ], work_root, checkpoint_path, force):
        sys.exit(3)

    # Stage 4: Prepare assembly job
    force = args.force_stage == 'prepare-job'
    # This will be a Python script that combines extraction + manifest into assembly job JSON
    # For now, placeholder: copy extraction as-is
    if force or not Path(job_path).exists():
        import shutil
        shutil.copy(extraction_dir / 'logical-article.json', job_path)

    # Stage 5: InDesign assembly
    # This requires ExtendScript invocation via Windows Adobe COM or batch runner
    # Placeholder: assume manual or separate orchestration
    print('[assemble] InDesign assembly requires Adobe runtime - manual or separate orchestration')

    # Stage 6: Validation
    print('[validate] Validation requires Check工具 - manual or separate orchestration')

    # Delivery report
    elapsed = time.time() - start_time
    delivery = {
        'articleId': config.get('articleId', 'unknown'),
        'status': 'formula-cache-ready-awaiting-indesign',
        'elapsedSeconds': round(elapsed, 2),
        'reworkCount': rework_count,
        'humanInterventionCount': 0,
        'checkpoint': str(checkpoint_path),
        'outputs': {
            'extraction': str(extraction_dir),
            'formulaManifest': str(manifest_path),
            'qaIndd': str(qa_indd) if qa_indd.exists() else None,
            'qaPdf': str(qa_pdf) if qa_pdf.exists() else None,
            'validationReport': str(validation_report) if validation_report.exists() else None,
        }
    }
    write_json(delivery_report, delivery)
    print(f'\n=== Delivery report written to {delivery_report} ===')
    print(json.dumps(delivery, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
