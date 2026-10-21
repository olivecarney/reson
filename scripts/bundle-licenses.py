#!/usr/bin/env python3
"""Include source locations and dependency license texts with distributed apps."""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
resources = root / 'build/Reson.app/Contents/Resources'
notices = resources / 'Licenses'
if notices.exists():
    shutil.rmtree(notices)
notices.mkdir(parents=True)
shutil.copyfile(root / 'LICENSE', notices / 'Reson-LICENSE.txt')
metadata = json.loads(subprocess.check_output(
    ['cargo', 'metadata', '--locked', '--format-version=1',
     '--filter-platform', 'aarch64-apple-darwin'], cwd=root))
lines = ['Reson dependency notices', '',
         'Original Reson source: https://github.com/olivecarney/reson',
         'Dependencies retain their own licenses. Source for each version is linked below.',
         'Symphonia is distributed under MPL-2.0; its unmodified source is available at the links below.',
         'The Rust standard library is MIT OR Apache-2.0: https://github.com/rust-lang/rust/tree/'
         + subprocess.check_output(['rustc', '--version'], text=True).split()[1] + '/library', '']
for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
    if package['source'] is None:
        continue
    name, version = package['name'], package['version']
    lines.append(f"{name} {version}: {package.get('license') or 'See included license'}")
    lines.append(f'https://crates.io/crates/{name}/{version}')
    source = Path(package['manifest_path']).parent
    license_files = [p for p in source.iterdir() if p.is_file()
                     and p.name.lower().startswith(('license', 'licence', 'copying', 'notice'))]
    if not license_files:
        repository = (package.get('repository') or '').removesuffix('.git')
        fallback = root / 'licenses' / repository.rsplit('/', 1)[-1]
        if fallback.is_dir():
            license_files = [p for p in fallback.iterdir() if p.is_file()]
        else:
            raise SystemExit(f'No license text found for {name} {version}')
    destination = notices / f'{name}-{version}'
    destination.mkdir()
    for path in license_files:
        shutil.copyfile(path, destination / path.name)
(notices / 'THIRD-PARTY-NOTICES.txt').write_text('\n'.join(lines) + '\n')
# Include the standard library licenses shipped with the compiler where available.
sysroot = Path(subprocess.check_output(['rustc', '--print', 'sysroot'], text=True).strip())
for name in ('LICENSE-APACHE', 'LICENSE-MIT', 'COPYRIGHT'):
    path = sysroot / 'share/doc/rust' / name
    if path.is_file():
        shutil.copyfile(path, notices / f'Rust-{name}.txt')

for path in (root / 'licenses/rust').iterdir():
    if path.is_file():
        shutil.copyfile(path, notices / f'Rust-{path.name}')
