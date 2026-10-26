"""Exercise Homebrew release verification and updates without network access."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/update-homebrew.py'
CASK = '''cask "reson" do
  version "0.5.3"
  sha256 "{sha}"
  url "https://github.com/example/reson/releases/download/v#{{version}}/reson-#{{version}}-macos-arm64.dmg"
  name "reson"
  app "reson.app"
end
'''


class HomebrewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / 'reson-0.5.4-macos-arm64.dmg'
        self.image.write_bytes(b'published release fixture')
        self.sha = hashlib.sha256(self.image.read_bytes()).hexdigest()
        self.image.with_suffix('.dmg.sha256').write_text(f'{self.sha}  {self.image.name}\n')
        self.release = self.root / 'release.json'
        self.release.write_text(json.dumps({
            'tagName': 'v0.5.4', 'isDraft': False, 'isPrerelease': False,
            'assets': [{'name': self.image.name, 'digest': 'sha256:' + self.sha,
                        'url': 'https://github.com/example/reson/releases/download/v0.5.4/' + self.image.name},
                       {'name': self.image.name + '.sha256'}]}))
        self.mirror = self.root / 'mirror.rb'
        self.tap = self.root / 'tap.rb'
        self.remote = self.root / 'remote.rb'
        for p in [self.mirror, self.tap, self.remote]:
            p.write_text(CASK.format(sha='0' * 64))
        binary = self.root / 'bin'
        binary.mkdir()
        fake = binary / 'gh'
        fake.write_text('''#!/usr/bin/env python3
import base64,json,os,pathlib,shutil,sys
root=pathlib.Path(os.environ['FIXTURE_ROOT']); args=sys.argv[1:]
if args[:2]==['release','view']:
 print((root/'release.json').read_text())
elif args[:2]==['release','download']:
 target=pathlib.Path(args[args.index('--dir')+1])
 for p in root.glob('*.dmg*'): shutil.copyfile(p,target/p.name)
elif args[0]=='api':
 if '--input' in args:
  payload=json.load(sys.stdin)
  (root/'put.json').write_text(json.dumps(payload))
  (root/'remote.rb').write_bytes(base64.b64decode(payload['content']))
  print('{}')
 else:
  print(json.dumps({'sha':'current-sha','content':base64.b64encode((root/'remote.rb').read_bytes()).decode()}))
else: sys.exit(99)
''')
        fake.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
                    'FIXTURE_ROOT': str(self.root)}

    def run_update(self, version='0.5.4', publish=False):
        args = ['python3', str(SCRIPT), '--repository', 'example/reson', '--version', version,
                '--mirror', str(self.mirror), '--tap', str(self.tap)]
        if publish:
            args.append('--publish-mirror')
        return subprocess.run(args, env=self.env, capture_output=True, text=True)

    def change_release(self, **changes):
        data = json.loads(self.release.read_text()); data.update(changes)
        self.release.write_text(json.dumps(data))

    def test_updates_both_casks_from_verified_published_artifact(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mirror.read_bytes(), self.tap.read_bytes())
        self.assertIn('version "0.5.4"', self.tap.read_text())
        self.assertIn(self.sha, self.tap.read_text())
        self.assertFalse((self.root / 'put.json').exists())

    def test_mirror_publication_is_idempotent_and_uses_current_blob_sha(self):
        first = self.run_update(publish=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        payload = json.loads((self.root / 'put.json').read_text())
        self.assertEqual(payload['sha'], 'current-sha')
        self.assertEqual(base64.b64decode(payload['content']), self.mirror.read_bytes())
        (self.root / 'put.json').unlink()
        second = self.run_update(publish=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertFalse((self.root / 'put.json').exists())

    def test_corrupt_download_cannot_update_either_cask(self):
        before = self.tap.read_bytes()
        self.image.write_bytes(b'corrupt download')
        self.assertNotEqual(self.run_update(publish=True).returncode, 0)
        self.assertEqual(self.tap.read_bytes(), before)
        self.assertEqual(self.mirror.read_bytes(), before)
        self.assertFalse((self.root / 'put.json').exists())

    def test_github_digest_mismatch_is_rejected(self):
        data = json.loads(self.release.read_text()); data['assets'][0]['digest'] = 'sha256:' + 'f' * 64
        self.release.write_text(json.dumps(data))
        self.assertNotEqual(self.run_update().returncode, 0)

    def test_wrong_checksum_filename_is_rejected(self):
        self.image.with_suffix('.dmg.sha256').write_text(f'{self.sha}  other.dmg\n')
        self.assertNotEqual(self.run_update().returncode, 0)

    def test_drafts_prereleases_and_wrong_tags_are_rejected(self):
        for changes in [{'isDraft': True}, {'isPrerelease': True}, {'tagName': 'v9.9.9'}]:
            with self.subTest(changes=changes):
                self.change_release(isDraft=False, isPrerelease=False, tagName='v0.5.4')
                self.change_release(**changes)
                self.assertNotEqual(self.run_update().returncode, 0)

    def test_missing_asset_is_rejected(self):
        self.change_release(assets=[])
        self.assertNotEqual(self.run_update().returncode, 0)

    def test_older_release_cannot_downgrade_the_tap_or_remote_mirror(self):
        self.tap.write_text(self.tap.read_text().replace('0.5.3', '0.5.5'))
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assertIn('0.5.5', self.tap.read_text())
        self.tap.write_text(self.mirror.read_text())
        self.remote.write_text(self.remote.read_text().replace('0.5.3', '0.5.5'))
        self.assertNotEqual(self.run_update(publish=True).returncode, 0)
        self.assertFalse((self.root / 'put.json').exists())

    def test_invalid_versions_are_rejected(self):
        for version in ['--latest', 'v0.5.4', '../0.5.4', '0.5', '0.05.4']:
            with self.subTest(version=version):
                self.assertNotEqual(self.run_update(version=version).returncode, 0)
