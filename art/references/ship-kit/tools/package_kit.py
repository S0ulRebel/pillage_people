"""Package only the active kit; never include archived revisions."""
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parent.parent
archive=ROOT/'ship-modeling-kit.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for name in ['START_HERE.md','index.html']:
        z.write(ROOT/name,Path('ship-kit')/name)
    for folder in ['canonical','accessories','previews','tools']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.ps1':
                z.write(p,Path('ship-kit')/p.relative_to(ROOT))
print(archive)
