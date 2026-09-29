"""Check the art breakdown and its textured templates, then package them. Nothing else is written.

    python tools/package_art_breakdown.py

Every check runs before any file is written. On failure this exits non-zero with the list of
problems and leaves the folder exactly as it was: no half-updated manifest, no package-check
claiming a pass. The source documents (kit-manifest.json, generation-prompts.json, the sheets)
are only ever read here; edit those by hand and commit them.

What it checks:
  - textured/validation.json passed, AND every sha256 it recorded still matches the file on
    disk, AND it covers every contract part. A GLB re-exported after the check fails here.
  - 01-hull-modules.png and 01b-hull-assembly.png are pixel-identical to a fresh render of the
    current textured GLBs, so the sheet cannot show an older mesh than the one packaged.
  - every sheet, template and path the manifest names exists, except sheets it lists under
    source.sheets_not_in_repo; every image decodes.
  - the part-group and family counts come from the manifest, not from constants.

Writes art-breakdown/package-check.json and art-breakdown.zip (fixed timestamps, sorted, so the
same inputs give the same bytes).
"""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_textured  # noqa: E402  (sibling tool; renders the sheets for comparison)

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'art-breakdown'
TEXTURED = ROOT / 'textured'
CONTRACT = ROOT / 'canonical' / 'contract.json'
ARCHIVE = ROOT / 'art-breakdown.zip'
ZIP_TIME = (2026, 1, 1, 0, 0, 0)
TOOLS = ['glb_io.py', 'texture_kit.py', 'check_textured_kit.py', 'render_textured.py', 'package_art_breakdown.py']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def verify():
    """Returns (problems, facts). Reads only."""
    problems, facts = [], {}
    manifest, contract = read(REF / 'kit-manifest.json'), read(CONTRACT)
    part_ids = [p['id'] for p in contract['parts']]

    report_path = TEXTURED / 'validation.json'
    report = read(report_path) if report_path.is_file() else {}
    if not report.get('passed'):
        problems.append(f"textured/validation.json does not report a pass: {report.get('failures', 'missing')}")
    recorded = report.get('sha256', {})
    for name, digest in recorded.items():
        path = ROOT / name
        if not path.is_file():
            problems.append(f'validation.json checked {name}, which no longer exists')
        elif sha(path) != digest:
            problems.append(f'{name} changed after textured/validation.json was written; re-run check_textured_kit.py')
    for part in part_ids:
        if f'textured/meshes/{part}.glb' not in recorded:
            problems.append(f'validation.json does not cover textured/meshes/{part}.glb')
    if 'canonical/contract.json' not in recorded:
        problems.append('validation.json does not record the contract it checked against')

    sheets = {}
    if not problems:  # Rendering stale inputs would only repeat the same complaint.
        ids = render_textured.manifest_ids()
        sheets = {'01-hull-modules.png': render_textured.hull_sheet(ids),
                  '01b-hull-assembly.png': render_textured.assembly_sheet(ids)}
    for name, fresh in sheets.items():
        path = REF / name
        if not path.is_file():
            problems.append(f'{name} missing; run render_textured.py')
            continue
        with Image.open(path) as on_disk:
            same = on_disk.size == fresh.size and np.array_equal(np.asarray(on_disk.convert('RGB')),
                                                                 np.asarray(fresh.convert('RGB')))
        if not same:
            problems.append(f'{name} is not a render of the current textured GLBs; run render_textured.py')

    absent_ok = set(manifest['source'].get('sheets_not_in_repo', []))
    named = {manifest['source']['art_reference_path']}
    named |= {family['reference_sheet'] for family in manifest['families']}
    templates = manifest['fit_status']['textured_construction_templates']
    named |= {templates['reference_sheet'], templates['assembly_reference']}
    for sheet in sorted(named):
        if sheet in absent_ok:
            continue
        if not (REF / sheet).is_file():
            problems.append(f'manifest names {sheet}, which is not in art-breakdown/')
    for key in ('texture_recipe', 'validation'):
        if not (REF / templates[key]).resolve().is_file():
            problems.append(f'manifest template path {templates[key]} does not exist')
    for path in templates['assemblies'] + templates['textures'] + templates['builders']:
        if not (REF / path).resolve().is_file():
            problems.append(f'manifest template path {path} does not exist')
    for path in [manifest['source']['structural_contract_path'], manifest['source']['structural_guide_path']]:
        if not (REF / path).resolve().is_file():
            problems.append(f'manifest source path {path} does not exist')

    images = []
    for path in sorted(REF.rglob('*')):
        if path.suffix.lower() not in ('.png', '.webp', '.jpg'):
            continue
        try:
            with Image.open(path) as im:
                im.verify()
            with Image.open(path) as im:
                images.append({'file': path.relative_to(REF).as_posix(), 'size_px': list(im.size), 'mode': im.mode})
        except Exception as error:
            problems.append(f'{path.relative_to(ROOT)} does not decode: {error}')

    facts.update({
        'part_groups': sum(len(f['parts']) for f in manifest['families']),
        'families': len(manifest['families']),
        'canonical_parts': len(part_ids),
        'textured_parts': sum(1 for p in part_ids if f'textured/meshes/{p}.glb' in recorded),
        'textured_assemblies': report.get('assemblies', []),
        'textured_checks_run': report.get('checks_run'),
        'sheets_not_in_repo': sorted(absent_ok),
        'images': images,
    })
    return problems, facts


def package_files():
    files = [p for p in sorted(REF.rglob('*')) if p.is_file() and p.name != 'package-check.json']
    files += sorted(p for p in TEXTURED.rglob('*') if p.is_file())
    files += [CONTRACT, ROOT / 'START_HERE.md'] + [ROOT / 'tools' / t for t in TOOLS]
    return files


def main():
    problems, facts = verify()
    if problems:
        print('Not packaged:')
        for problem in problems:
            print(' -', problem)
        raise SystemExit(1)

    files = package_files()
    check = {
        'check_type': 'Art-breakdown package integrity plus textured construction-template parity',
        **facts,
        'textured_exports_preserve_canonical_geometry': True,
        'sheets_match_current_render': True,
        'new_finished_art_geometry_validated': False,
        'scope_limit': 'Construction geometry with UVs and albedo only. Rails, cabin, rigging, fittings, '
                       'bevels and any new art geometry need their own modelling and validation.',
        'file_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in files},
    }
    (REF / 'package-check.json').write_text(json.dumps(check, indent=2) + '\n', encoding='utf-8')
    files.append(REF / 'package-check.json')

    with zipfile.ZipFile(ARCHIVE, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            info = zipfile.ZipInfo(f'ship-kit/{path.relative_to(ROOT).as_posix()}', ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(ARCHIVE) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(files):
            raise SystemExit(f'{ARCHIVE.name} did not read back cleanly')
    print(json.dumps({'archive': ARCHIVE.relative_to(ROOT).as_posix(), 'files': len(files),
                      'bytes': ARCHIVE.stat().st_size, 'part_groups': facts['part_groups'],
                      'textured_parts': facts['textured_parts'], 'checks_passed': True}, indent=2))


if __name__ == '__main__':
    main()
