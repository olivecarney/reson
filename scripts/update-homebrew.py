#!/usr/bin/env python3
"""Sync casks only from a verified, already-published release; never build or publish it."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
MIRROR_PATH = "packaging/homebrew/Casks/reson.rb"


def gh(*args, payload=None):
    result = subprocess.run(["gh", *args], input=json.dumps(payload) if payload is not None else None,
                            capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"GitHub operation failed: {result.stderr.strip()}")
    return result.stdout


def version_of(cask):
    matches = re.findall(r'^[ \t]*version "(' + VERSION + r')"[ \t]*$', cask, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("Expected one stable cask version")
    return tuple(map(int, matches[0].split('.')))


def update(cask, version, digest, repository):
    if version_of(cask) > tuple(map(int, version.split('.'))):
        raise ValueError("Refusing to downgrade a newer cask")
    replacements = [
        (r'^[ \t]*version "[^"]+"[ \t]*$', f'  version "{version}"'),
        (r'^[ \t]*sha256 "[^"]+"[ \t]*$', f'  sha256 "{digest}"'),
        (r'^[ \t]*url "[^"]+"[ \t]*$', '  url "https://github.com/' + repository + '/releases/download/v#{version}/reson-#{version}-macos-arm64.dmg"'),
        (r'^[ \t]*app "[^"]+"(?:,[ \t]*target: "[^"]+")?[ \t]*$', '  app "reson.app"'),
    ]
    for pattern, replacement in replacements:
        cask, count = re.subn(pattern, replacement, cask, flags=re.MULTILINE)
        if count != 1:
            raise ValueError("Unexpected cask structure")
    return cask


def published_digest(repository, version):
    tag = 'v' + version
    release = json.loads(gh('release', 'view', tag, '--repo', repository,
                            '--json', 'tagName,isDraft,isPrerelease,assets'))
    if release['tagName'] != tag or release['isDraft'] or release['isPrerelease']:
        raise ValueError("Expected an already-published stable release with the requested tag")
    name = f'reson-{version}-macos-arm64.dmg'
    assets = {asset['name']: asset for asset in release['assets']}
    if name not in assets or name + '.sha256' not in assets:
        raise ValueError("Published DMG or checksum asset is missing")
    expected_url = f'https://github.com/{repository}/releases/download/{tag}/{name}'
    if assets[name]['url'] != expected_url:
        raise ValueError("Unexpected release asset URL")
    with tempfile.TemporaryDirectory(prefix='reson-homebrew-') as directory:
        gh('release', 'download', tag, '--repo', repository, '--dir', directory,
           '--pattern', name, '--pattern', name + '.sha256')
        root = Path(directory)
        fields = (root / (name + '.sha256')).read_text().split()
        if len(fields) != 2 or fields[1] != name or not re.fullmatch('[0-9a-f]{64}', fields[0]):
            raise ValueError("Invalid release checksum or filename")
        digest = hashlib.sha256()
        with (root / name).open('rb') as image:
            for chunk in iter(lambda: image.read(1024 * 1024), b''):
                digest.update(chunk)
        actual = digest.hexdigest()
        if actual != fields[0] or assets[name].get('digest') != 'sha256:' + actual:
            raise ValueError("Published DMG, checksum and GitHub asset digest do not match")
    return actual


def publish_mirror(repository, version, digest):
    endpoint = f'repos/{repository}/contents/{MIRROR_PATH}'
    current = json.loads(gh('api', endpoint))
    original = base64.b64decode(current['content']).decode('utf-8')
    updated = update(original, version, digest, repository)
    if original == updated:
        print('Mirrored cask is already current; no commit needed.')
        return
    gh('api', endpoint, '--method', 'PUT', '--input', '-', payload={
        'message': f'packaging: sync verified Homebrew cask for {version} [skip ci]',
        'sha': current['sha'], 'content': base64.b64encode(updated.encode()).decode(),
    })
    print('Updated mirrored cask without triggering another build.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--mirror', type=Path, default=Path(MIRROR_PATH))
    parser.add_argument('--tap', type=Path, required=True)
    parser.add_argument('--publish-mirror', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(VERSION, args.version):
        raise ValueError("Expected a stable three-part version without a v prefix")
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        raise ValueError("Expected an owner/repository name")
    digest = published_digest(args.repository, args.version)
    # Validate both versions/structures before writing either local file.
    candidates = [(path, update(path.read_text(), args.version, digest, args.repository))
                  for path in [args.mirror, args.tap]]
    if args.publish_mirror:
        publish_mirror(args.repository, args.version, digest)
    for path, content in candidates:
        if path.read_text() != content:
            path.write_text(content)
            print(f'Updated {path}')
    print(f'Verified published reson {args.version}: sha256:{digest}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(f'Homebrew sync failed: {error}') from error
