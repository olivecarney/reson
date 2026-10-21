"""Exercise release decisions without calling GitHub or publishing anything."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/publish-release.sh'
COMMIT = 'a' * 40


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(SCRIPT, self.root / 'scripts/publish-release.sh')
        self.dist = self.root / 'build/dist'
        self.dist.mkdir(parents=True)
        self.image = self.dist / 'Reson-1.2.3-macos-arm64.dmg'
        self.image.write_bytes(b'verified disk image fixture')
        digest = hashlib.sha256(self.image.read_bytes()).hexdigest()
        self.image.with_suffix('.dmg.sha256').write_text(f'{digest}  {self.image.name}\n')
        binary = self.root / 'bin'
        binary.mkdir()
        fake = binary / 'gh'
        fake.write_text('''#!/bin/bash
set -eu
if [[ "$1 $2" == "release view" ]]; then
    if [[ "${CASE:-}" == published ]]; then echo false; exit 0; fi
    echo '{"message":"Not Found"}'; exit 1
elif [[ "$1 $2" == "release create" ]]; then
    printf '%s\\n' "$@" > "$RELEASE_LOG"; exit 0
elif [[ "$1" == api && "$2" == *matching-refs* ]]; then
    if [[ "${CASE:-}" == api_error ]]; then echo '{"message":"Unavailable"}'; exit 1; fi
    if [[ "${CASE:-}" == conflict || "${CASE:-}" == matching ]]; then echo refs/tags/v1.2.3; fi
    exit 0
elif [[ "$1" == api && "$2" == *commits* ]]; then
    if [[ "${CASE:-}" == conflict ]]; then printf '%040d\\n' 0; exit 0; fi
    if [[ "${CASE:-}" == matching ]]; then echo "$EXPECTED_COMMIT"; exit 0; fi
    echo '{"message":"No commit found for SHA"}'; exit 1
fi
exit 99
''')
        fake.chmod(0o755)
        self.log = self.root / 'release.log'
        self.env = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
                    'GH_REPO': 'example/reson', 'RELEASE_LOG': str(self.log),
                    'EXPECTED_COMMIT': COMMIT}

    def run_publish(self, case=''):
        return subprocess.run(['bash', str(self.root / 'scripts/publish-release.sh'),
                               '1.2.3', COMMIT], env={**self.env, 'CASE': case},
                              capture_output=True, text=True)

    def test_absent_tag_publishes_verified_image_at_tested_commit(self):
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = self.log.read_text().splitlines()
        self.assertIn(COMMIT, args)
        self.assertIn('v1.2.3', args)
        self.assertIn('build/dist/' + self.image.name, args)

    def test_existing_release_is_unchanged(self):
        self.assertEqual(self.run_publish('published').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_tag_at_different_commit_cannot_publish(self):
        self.assertNotEqual(self.run_publish('conflict').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_matching_unreleased_tag_can_publish(self):
        self.assertEqual(self.run_publish('matching').returncode, 0)
        self.assertTrue(self.log.exists())

    def test_corrupt_download_cannot_publish(self):
        self.image.write_bytes(b'changed after verification')
        self.assertNotEqual(self.run_publish('matching').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_api_failure_cannot_publish(self):
        self.assertNotEqual(self.run_publish('api_error').returncode, 0)
        self.assertFalse(self.log.exists())
