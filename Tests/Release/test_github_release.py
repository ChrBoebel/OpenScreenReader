import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('github_release', SCRIPTS / 'github-release.py')
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)

COMMIT = 'a' * 40
REPOSITORY = 'ChrBoebel/saywing'
CHANGELOG = """# Changelog

Intro.

## [Unreleased]

- **Faster speech.** See [ADR 0007](docs/decisions/0007-gcc-runtime-libraries.md) and [notes](https://example.invalid/x).

## 2026-10-24

- Older entry.
"""


def approval(clean_mac=False):
    record = {'clean_mac': clean_mac}
    if not clean_mac:
        record['owner_beta_exception'] = {'approved': True, 'channel': 'beta', 'gate': 'clean_mac',
                                          'remaining_tests': ['Physical macOS 14 execution']}
    return record


def write_release(root, architecture, version='0.1.30', build='130', commit=COMMIT, channel='beta',
                  content=None, metadata_sha256=None):
    folder = root / architecture / 'publish'
    folder.mkdir(parents=True)
    archive = folder / f'Saywing-{version}-{build}.dmg'
    archive.write_bytes(content or f'fixture {architecture} image - not a notarized app'.encode())
    sha256 = hashlib.sha256(archive.read_bytes()).hexdigest()
    meta = {'version': version, 'build': build, 'architecture': architecture,
            'url': mirror.release_target(architecture)['url_prefix'] + '/' + archive.name,
            'bytes': archive.stat().st_size, 'sha256': metadata_sha256 or sha256, 'minimum_macos': '14.0',
            'channel': channel}
    (folder / 'latest.json').write_text(json.dumps(meta, indent=2) + '\n')
    (folder / 'SHA256SUMS').write_text(f"{meta['sha256']}  {archive.name}\n")
    (folder / 'appcast.xml').write_text('<rss/>')
    (root / architecture / 'release-result.json').write_text(json.dumps({
        'version': version, 'build': build, 'architecture': architecture, 'notarized': True,
        'public_release_approved': True, 'source_commit': commit}))
    return root / architecture


def prepare(root, approvals=None, commit=COMMIT, changelog=CHANGELOG, **releases):
    dirs = {arch: releases.get(arch) or write_release(root, arch) for arch in mirror.ARCHITECTURES}
    return mirror.prepare(dirs, root / 'assets', commit=commit, repository=REPOSITORY, changelog=changelog,
                          approvals=approvals or {arch: approval() for arch in mirror.ARCHITECTURES})


class NotesTests(unittest.TestCase):
    def test_tag_follows_version_and_build(self):
        self.assertEqual(mirror.tag_name('0.1.30', '130'), 'v0.1.30-build130')
        with self.assertRaises(ValueError):
            mirror.tag_name('0.1', '130')

    def test_changelog_prefers_version_section_and_falls_back_to_unreleased(self):
        self.assertIn('Faster speech', mirror.changelog_section(CHANGELOG, '0.1.30'))
        self.assertNotIn('Older entry', mirror.changelog_section(CHANGELOG, '0.1.30'))
        versioned = CHANGELOG.replace('## 2026-10-24', '## [0.1.30] - 2026-10-27')
        self.assertEqual(mirror.changelog_section(versioned, '0.1.30'), '- Older entry.')
        for broken in ['# Changelog\n', '## [Unreleased]\n\n## 2026-10-24\n- Older.\n']:
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                mirror.changelog_section(broken, '0.1.30')

    def test_relative_links_point_to_the_built_commit(self):
        text = mirror.absolute_links('[a](docs/x.md#part) [b](https://example.invalid) [c](#local)', REPOSITORY, COMMIT)
        self.assertEqual(text, f'[a](https://github.com/{REPOSITORY}/blob/{COMMIT}/docs/x.md#part) '
                               '[b](https://example.invalid) [c](#local)')

    def test_notes_carry_downloads_updates_checksums_sources_and_fork_warning(self):
        notes = mirror.release_notes(
            version='0.1.30', build='130', prerelease=True, repository=REPOSITORY, commit=COMMIT,
            downloads={'arm64': 'https://dl.invalid/Saywing-0.1.30-130.dmg',
                       'x86_64': 'https://dl.invalid/x86_64/Saywing-0.1.30-130.dmg'},
            checksums='f' * 64 + '  Saywing-0.1.30-130-arm64.dmg\n', changelog='- Change.',
            remaining_tests=['Physical macOS 14 execution'])
        for expected in ['https://dl.invalid/Saywing-0.1.30-130.dmg', 'https://dl.invalid/x86_64/Saywing-0.1.30-130.dmg',
                         'Sparkle', 'f' * 64 + '  Saywing-0.1.30-130-arm64.dmg', '- Change.', 'Beta pre-release',
                         'Physical macOS 14 execution',
                         f'https://github.com/{REPOSITORY}/blob/{COMMIT}/docs/licenses/CorrespondingSource-README.md',
                         f'https://github.com/{REPOSITORY}/tree/{COMMIT}/docs/licenses',
                         f'https://github.com/{REPOSITORY}/blob/{COMMIT}/docs/decisions/0007-gcc-runtime-libraries.md',
                         'Unsigned builds from forks are not official.']:
            self.assertIn(expected, notes)
        stable = mirror.release_notes(
            version='0.1.30', build='130', prerelease=False, repository=REPOSITORY, commit=COMMIT,
            downloads={'arm64': 'https://dl.invalid/a.dmg', 'x86_64': 'https://dl.invalid/b.dmg'},
            checksums='', changelog='- Change.', remaining_tests=[])
        self.assertNotIn('pre-release', stable)


class PrepareTests(unittest.TestCase):
    def test_renames_both_images_with_combined_checksums_and_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plan = prepare(root)
            self.assertEqual(plan['tag'], 'v0.1.30-build130')
            self.assertEqual(plan['title'], 'Saywing 0.1.30 (beta)')
            self.assertIs(plan['prerelease'], True)
            names = [asset['name'] for asset in plan['assets']]
            self.assertEqual(names, ['Saywing-0.1.30-130-arm64.dmg', 'Saywing-0.1.30-130-x86_64.dmg',
                                     'SHA256SUMS', 'latest-arm64.json', 'latest-x86_64.json'])
            for asset in plan['assets']:
                path = Path(asset['path'])
                self.assertEqual(path.name, asset['name'])
                self.assertEqual(asset['size'], path.stat().st_size)
                self.assertEqual(asset['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
            sums = (root / 'assets/SHA256SUMS').read_text().splitlines()
            for architecture, line in zip(mirror.ARCHITECTURES, sums):
                meta = json.loads((root / architecture / 'publish/latest.json').read_text())
                self.assertEqual(line, f"{meta['sha256']}  Saywing-0.1.30-130-{architecture}.dmg")
                self.assertEqual((root / f'assets/latest-{architecture}.json').read_text(),
                                 (root / architecture / 'publish/latest.json').read_text())
            notes = Path(plan['notes']).read_text()
            self.assertIn('\n'.join(sums), notes)
            self.assertIn('Faster speech', notes)

    def test_stable_only_when_every_record_closes_the_device_gate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dirs = {arch: write_release(root, arch, channel='stable') for arch in mirror.ARCHITECTURES}
            plan = prepare(root, approvals={arch: approval(clean_mac=True) for arch in mirror.ARCHITECTURES}, **dirs)
            self.assertIs(plan['prerelease'], False)
            self.assertEqual(plan['title'], 'Saywing 0.1.30')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plan = prepare(root, approvals={'arm64': approval(clean_mac=True), 'x86_64': approval()})
            self.assertIs(plan['prerelease'], True)

    def test_aborts_on_mismatched_or_incomplete_releases(self):
        cases = {
            'checksum': lambda root: {'arm64': write_release(root, 'arm64', metadata_sha256='0' * 64)},
            'commit': lambda root: {'x86_64': write_release(root, 'x86_64', commit='b' * 40)},
            'build': lambda root: {'x86_64': write_release(root, 'x86_64', build='131')},
            'unnotarized': lambda root: {'arm64': self.unnotarized(write_release(root, 'arm64'))},
        }
        for name, make in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                with self.assertRaises(ValueError):
                    prepare(root, **make(root))
                self.assertFalse((root / 'assets/SHA256SUMS').exists())
        with tempfile.TemporaryDirectory() as temp, self.assertRaises(ValueError):
            mirror.prepare({'arm64': write_release(Path(temp), 'arm64')}, Path(temp) / 'assets', commit=COMMIT,
                           repository=REPOSITORY, changelog=CHANGELOG, approvals={'arm64': approval()})

    def test_fails_clearly_above_the_github_asset_limit(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(mirror, 'GITHUB_ASSET_LIMIT', 8):
            with self.assertRaisesRegex(ValueError, '2 GiB'):
                prepare(Path(temp))

    @staticmethod
    def unnotarized(folder):
        result = folder / 'release-result.json'
        data = json.loads(result.read_text())
        data['notarized'] = False
        result.write_text(json.dumps(data))
        return folder


class FakeGitHub:
    """Stands in for `gh`: records every call and never touches the network."""

    def __init__(self, releases=(), tags=None, latest=None):
        self.releases = [dict(item) for item in releases]
        self.tags = dict(tags or {})
        self.latest = latest
        self.calls = []

    def find(self, tag):
        return next(item for item in self.releases if item['tag_name'] == tag)

    def __call__(self, *args):
        self.calls.append(args)
        if args[:3] == ('api', '--paginate', '--slurp'):
            return json.dumps([self.releases])
        if args[0] == 'api' and '/git/matching-refs/tags/' in args[1]:
            tag = args[1].rsplit('/', 1)[1]
            return json.dumps([{'ref': 'refs/tags/' + tag, 'object': {'type': 'commit', 'sha': self.tags[tag]}}]
                              if tag in self.tags else [])
        if args[:2] == ('release', 'create'):
            tag, files = args[2], list(itertools.takewhile(lambda value: not value.startswith('--'), args[3:]))
            target = args[args.index('--target') + 1]
            self.tags.setdefault(tag, target)
            self.releases.append({'id': len(self.releases) + 1, 'tag_name': tag, 'draft': False,
                                  'prerelease': '--prerelease' in args, 'target_commitish': target,
                                  'assets': [self.uploaded(path) for path in files]})
            if '--prerelease' not in args and '--latest=false' not in args:
                self.latest = tag
            return ''
        if args[:2] == ('release', 'upload'):
            self.find(args[2])['assets'] += [self.uploaded(path) for path in args[3:]]
            return ''
        if args[:3] == ('api', '-X', 'PATCH'):
            release = next(item for item in self.releases if args[3].endswith('/releases/%d' % item['id']))
            release['draft'] = False
            self.tags.setdefault(release['tag_name'], release['target_commitish'])
            return ''
        if args[:2] == ('release', 'list'):
            return json.dumps([{'tagName': item['tag_name'], 'isLatest': item['tag_name'] == self.latest}
                               for item in self.releases])
        raise AssertionError('unexpected gh call: %r' % (args,))

    @staticmethod
    def uploaded(path):
        data = Path(path).read_bytes()
        return {'name': Path(path).name, 'size': len(data), 'state': 'uploaded',
                'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}

    def writes(self):
        return [call for call in self.calls if call[:2] in (('release', 'create'), ('release', 'upload'))
                or call[:3] == ('api', '-X', 'PATCH')]


class MirrorTests(unittest.TestCase):
    def run_mirror(self, github, plan):
        mirror.mirror(github, REPOSITORY, plan, COMMIT, download=self.no_download)

    @staticmethod
    def no_download(tag, name):
        raise AssertionError('assets with a digest must not be downloaded')

    def test_creates_a_tagged_pre_release_that_is_never_latest_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub()
            self.run_mirror(github, plan)
            create = github.writes()[0]
            self.assertEqual(create[2], 'v0.1.30-build130')
            self.assertEqual(create[create.index('--target') + 1], COMMIT)
            self.assertEqual(create[create.index('--title') + 1], 'Saywing 0.1.30 (beta)')
            self.assertIn('--prerelease', create)
            self.assertIn('--latest=false', create)
            self.assertNotIn('--clobber', create)
            self.assertEqual(github.tags, {'v0.1.30-build130': COMMIT})
            before = len(github.writes())
            self.run_mirror(github, plan)  # Re-run of the same workflow run.
            self.assertEqual(len(github.writes()), before)

    def test_stable_release_lets_github_choose_latest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dirs = {arch: write_release(root, arch, channel='stable') for arch in mirror.ARCHITECTURES}
            plan = prepare(root, approvals={arch: approval(clean_mac=True) for arch in mirror.ARCHITECTURES}, **dirs)
            github = FakeGitHub()
            self.run_mirror(github, plan)
            create = github.writes()[0]
            self.assertNotIn('--prerelease', create)
            self.assertNotIn('--latest=false', create)

    def test_never_moves_an_existing_tag(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub(tags={'v0.1.30-build130': 'b' * 40})
            with self.assertRaisesRegex(ValueError, 'never moved'):
                self.run_mirror(github, plan)
            self.assertEqual(github.writes(), [])

    def test_existing_tag_on_the_built_commit_is_reused(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub(tags={'v0.1.30-build130': COMMIT})
            self.run_mirror(github, plan)
            self.assertIn('--verify-tag', github.writes()[0])

    def test_refuses_existing_release_with_different_assets(self):
        for change in ['digest', 'extra', 'incomplete']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temp:
                plan = prepare(Path(temp))
                github = FakeGitHub()
                self.run_mirror(github, plan)
                assets = github.releases[0]['assets']
                if change == 'digest':
                    assets[0]['digest'] = 'sha256:' + '0' * 64
                elif change == 'extra':
                    assets.append({'name': 'other.zip', 'size': 1, 'state': 'uploaded', 'digest': None})
                else:
                    assets[1]['state'] = 'starter'
                before = len(github.writes())
                with self.assertRaises(ValueError):
                    self.run_mirror(github, plan)
                self.assertEqual(len(github.writes()), before)

    def test_resumes_an_interrupted_upload_without_overwriting(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            first = FakeGitHub.uploaded(plan['assets'][0]['path'])
            github = FakeGitHub(releases=[{'id': 1, 'tag_name': plan['tag'], 'draft': True, 'prerelease': True,
                                           'target_commitish': COMMIT, 'assets': [first]}])
            self.run_mirror(github, plan)
            upload = next(call for call in github.writes() if call[:2] == ('release', 'upload'))
            self.assertEqual([Path(path).name for path in upload[3:]],
                             [asset['name'] for asset in plan['assets'][1:]])
            patch_call = next(call for call in github.writes() if call[:3] == ('api', '-X', 'PATCH'))
            self.assertIn('make_latest=false', patch_call)
            self.assertFalse(github.releases[0]['draft'])
            self.assertEqual(github.tags, {plan['tag']: COMMIT})

    def test_refuses_a_draft_for_another_commit(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub(releases=[{'id': 1, 'tag_name': plan['tag'], 'draft': True, 'prerelease': True,
                                           'target_commitish': 'b' * 40, 'assets': []}])
            with self.assertRaises(ValueError):
                self.run_mirror(github, plan)
            self.assertEqual(github.writes(), [])

    def test_pre_release_marked_latest_fails_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub()
            self.run_mirror(github, plan)
            github.latest = plan['tag']
            with self.assertRaisesRegex(ValueError, 'latest'):
                self.run_mirror(github, plan)

    def test_asset_without_digest_is_verified_by_download(self):
        with tempfile.TemporaryDirectory() as temp:
            plan = prepare(Path(temp))
            github = FakeGitHub()
            self.run_mirror(github, plan)
            for asset in github.releases[0]['assets']:
                asset['digest'] = None
            downloaded = []
            def download(tag, name):
                downloaded.append(name)
                return next(asset['sha256'] for asset in plan['assets'] if asset['name'] == name)
            mirror.mirror(github, REPOSITORY, plan, COMMIT, download=download)
            self.assertEqual(sorted(downloaded), sorted(asset['name'] for asset in plan['assets']))


if __name__ == '__main__':
    unittest.main()
