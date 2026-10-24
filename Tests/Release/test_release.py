import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release', Path(__file__).resolve().parents[2] / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_receipt_rejects_changed_missing_and_escaping_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'runtime'
            root.mkdir()
            asset = root / 'worker.py'
            asset.write_text('original')
            receipt = root / 'installation-receipt.json'
            receipt.write_text(json.dumps({'files': {'worker.py': release.digest(asset)}}))
            release.verify_receipt(root, receipt)
            asset.write_text('tampered')
            with self.assertRaises(ValueError):
                release.verify_receipt(root, receipt)
            outside = Path(temp) / 'outside'
            outside.write_text('original')
            receipt.write_text(json.dumps({'files': {'../outside': release.digest(outside)}}))
            with self.assertRaises(ValueError):
                release.verify_receipt(root, receipt)
            receipt.write_text(json.dumps({'files': {'missing': '0' * 64}}))
            with self.assertRaises((ValueError, FileNotFoundError)):
                release.verify_receipt(root, receipt)

    def test_worker_refresh_verifies_input_and_changes_only_project_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            for root, receipt in release.receipts(app):
                receipt.parent.mkdir(parents=True)
                worker = receipt.parent / 'worker.py'
                worker.write_text('old project worker')
                asset = root / 'model.dat'
                asset.write_text('unchanged model')
                receipt.write_text(json.dumps({'files': {
                    str(worker.relative_to(root)): release.digest(worker),
                    'model.dat': release.digest(asset)}}))
            release.refresh_project_workers(app)
            for root, receipt in release.receipts(app):
                release.verify_receipt(root, receipt)
                self.assertEqual((root / 'model.dat').read_text(), 'unchanged model')
            self.assertEqual((app / 'Contents/Resources/Dictation/worker.py').read_bytes(),
                             (release.REPO / 'Runtime/Dictation/worker.py').read_bytes())
            self.assertEqual((app / 'Contents/Resources/Speech/SupertonicRuntime/worker.py').read_bytes(),
                             (release.REPO / 'Runtime/Supertonic/worker.py').read_bytes())
            speech, speech_receipt = release.receipts(app)[0]
            (speech / 'model.dat').write_text('tampered')
            with self.assertRaises(ValueError): release.refresh_project_workers(app)

    def test_public_endpoints_reject_credentials_and_non_https(self):
        self.assertEqual(release.https_url('https://downloads.example.com/saywing/'), 'https://downloads.example.com/saywing/')
        for url in ['', 'http://example.com', 'https://user:pass@example.com', 'https://example.com?token=secret', 'file:///tmp/feed']:
            with self.assertRaises(ValueError):
                release.https_url(url)

    def test_release_gate_requires_every_completed_review(self):
        with tempfile.TemporaryDirectory() as temp:
            record = Path(temp) / 'approval.json'
            record.write_text(json.dumps({'license_review': True, 'clean_mac': False, 'offline_privacy': True}))
            with self.assertRaises(ValueError):
                release.require_release_approval(record)
            record.write_text(json.dumps({**{key: True for key in release.RELEASE_GATES}, 'scope': {'architecture': 'arm64'}}))
            release.require_release_approval(record)

    def test_owner_beta_exception_only_covers_documented_device_test_gap(self):
        with tempfile.TemporaryDirectory() as temp:
            record = Path(temp) / 'approval.json'
            data = {key: True for key in release.RELEASE_GATES}
            data['clean_mac'] = False
            data['scope'] = {'architecture': 'arm64'}
            exception = {'approved': True, 'channel': 'beta', 'gate': 'clean_mac',
                         'owner_decision': '2026-10-15: publish ARM beta with documented device gaps',
                         'remaining_tests': ['fresh Mac permissions', 'macOS 14 device']}
            data['owner_beta_exception'] = exception
            record.write_text(json.dumps(data))
            release.require_release_approval(record)
            for changes in [{'approved': False}, {'channel': 'stable'}, {'gate': 'license_review'},
                            {'owner_decision': ''}, {'remaining_tests': []}]:
                record.write_text(json.dumps({**data, 'owner_beta_exception': {**exception, **changes}}))
                with self.assertRaises(ValueError): release.require_release_approval(record)
            for gate in ['license_review', 'offline_privacy', 'update_roundtrip']:
                record.write_text(json.dumps({**data, gate: False}))
                with self.assertRaises(ValueError): release.require_release_approval(record)
            record.write_text(json.dumps({**data, 'scope': {'architecture': 'x86_64'}}))
            with self.assertRaises(ValueError): release.require_release_approval(record)

    def test_intel_beta_exception_is_explicit_and_architecture_bound(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'approval.json'
            data = {**{key: True for key in release.RELEASE_GATES}, 'clean_mac': False,
                    'scope': {'architecture': 'x86_64'},
                    'owner_beta_exception': {'approved': True, 'architecture': 'x86_64',
                        'channel': 'beta', 'gate': 'clean_mac',
                        'owner_decision': 'Owner requests Intel beta despite unavailable physical Intel test',
                        'remaining_tests': ['physical Intel macOS14 and fresh permissions']}}
            path.write_text(json.dumps(data))
            release.require_release_approval(path, 'x86_64')
            for changes in [{'architecture': 'arm64'}, {'approved': False}, {'channel': 'stable'},
                            {'gate': 'license_review'}, {'owner_decision': ''}, {'remaining_tests': []}]:
                path.write_text(json.dumps({**data, 'owner_beta_exception': {**data['owner_beta_exception'], **changes}}))
                with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')
            for gate in ['license_review', 'offline_privacy', 'update_roundtrip']:
                path.write_text(json.dumps({**data, gate: False}))
                with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')
            exception = dict(data['owner_beta_exception']); del exception['architecture']
            path.write_text(json.dumps({**data, 'owner_beta_exception': exception}))
            with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')

    def test_headless_sparkle_signing_uses_private_file_without_keychain(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            key = Path(temp) / 'sparkle.key'
            key.write_text('test-only-secret')
            key.chmod(0o600)
            args = SimpleNamespace(sparkle_key_file=key, sparkle_account='saywing',
                                   download_url_prefix='https://example.com')
            with patch.object(release, 'run') as run:
                release.generate_feed(Path('/tools'), Path('/publish'), args)
                calls = [call.args for call in run.call_args_list]
                self.assertEqual(len(calls), 2)
                for call in calls:
                    self.assertIn('--ed-key-file', call)
                    self.assertIn(key, call)
                    self.assertNotIn('--account', call)
                    self.assertNotIn('test-only-secret', call)
                self.assertTrue(all(call.kwargs.get('timeout') == 300 for call in run.call_args_list))
            key.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'private'):
                release.generate_feed(Path('/tools'), Path('/publish'), args)

    def test_intel_requires_its_own_complete_approval(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'approval.json'
            approved = {**{key: True for key in release.RELEASE_GATES}, 'scope': {'architecture': 'arm64'}}
            path.write_text(json.dumps(approved))
            with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')
            approved['scope']['architecture'] = 'x86_64'
            path.write_text(json.dumps(approved))
            release.require_release_approval(path, 'x86_64')
            approved['clean_mac'] = False
            path.write_text(json.dumps(approved))
            with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')

    def test_owner_constants_have_overridable_defaults(self):
        import os
        from unittest.mock import patch
        with patch.dict(os.environ):
            os.environ.pop('SAYWING_PUBLIC_DOWNLOAD_PREFIX', None)
            self.assertEqual(release.release_target('arm64')['url_prefix'], release.DEFAULT_PUBLIC_DOWNLOAD_PREFIX)
        with patch.dict(os.environ, {'SAYWING_PUBLIC_DOWNLOAD_PREFIX': 'https://downloads.example.org/app/'}):
            self.assertEqual(release.release_target('arm64')['url_prefix'], 'https://downloads.example.org/app')
            self.assertEqual(release.release_target('x86_64')['url_prefix'], 'https://downloads.example.org/app/x86_64')
            self.assertEqual(release.release_target('x86_64')['storage_prefix'], 'saywing/x86_64')
        for unsafe in ['http://downloads.example.org/app', 'https://downloads.example.org/app?token=secret']:
            with patch.dict(os.environ, {'SAYWING_PUBLIC_DOWNLOAD_PREFIX': unsafe}), self.assertRaises(ValueError):
                release.release_target('arm64')
        self.assertTrue(release.DEFAULT_SIGNING_IDENTITY.startswith('Developer ID Application:'))

    def test_signing_identity_and_notary_profile_follow_environment(self):
        import argparse, os
        from unittest.mock import patch
        required = ['--runtime-app', '/nonexistent', '--output', '/nonexistent', '--version', '0.1.0', '--build', '1',
                    '--feed-url', 'https://example.com/appcast.xml', '--download-url-prefix', 'https://example.com',
                    '--public-key', 'AA==']
        parsed = []
        def capture(parser, *_):
            parsed.append(parser.parse_known_args(required)[0])
            raise SystemExit(0)  # Stop before any build, signing or network step.
        env = {'SAYWING_SIGNING_IDENTITY': 'Developer ID Application: Example (TEAM123456)',
               'SAYWING_NOTARY_PROFILE': 'Example-Notary'}
        for environment, identity, profile in [
                (env, env['SAYWING_SIGNING_IDENTITY'], env['SAYWING_NOTARY_PROFILE']),
                ({}, release.DEFAULT_SIGNING_IDENTITY, release.DEFAULT_NOTARY_PROFILE)]:
            with patch.dict(os.environ, environment), \
                 patch.object(argparse.ArgumentParser, 'parse_args', autospec=True, side_effect=capture):
                for name in env.keys() - environment.keys():
                    os.environ.pop(name, None)
                with self.assertRaises(SystemExit):
                    release.main()
            self.assertEqual((parsed[-1].identity, parsed[-1].notary_profile), (identity, profile))

    def license_repo(self, root, omit=()):
        for relative, _ in release.DMG_LICENSE_FILES:
            if relative not in omit:
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_text('text of ' + relative)
        return root

    def signed_app(self, root):
        app = root / 'Saywing.app'
        (app / 'Contents/Resources').mkdir(parents=True)
        (app / 'Contents/Resources/THIRD-PARTY-NOTICES.html').write_text('<html>notices</html>')
        (app / 'Contents/Resources/CorrespondingSource').mkdir()
        (app / 'Contents/Resources/CorrespondingSource/sources.json').write_text(json.dumps(self.SOURCES))
        return app

    SOURCES = [{'file': 'gcc.tar.xz', 'url': 'https://example.org/gcc.tar.xz', 'bytes': 1, 'sha256': '0' * 64}]

    def test_dmg_license_documents_fail_loudly_when_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = self.license_repo(Path(temp), omit=('NOTICE', 'docs/licenses/SUPERTONIC-MODEL-TERMS.md'))
            with self.assertRaisesRegex(ValueError, 'NOTICE, docs/licenses/SUPERTONIC-MODEL-TERMS.md'):
                release.dmg_license_files(repo)
            (repo / 'NOTICE').write_text('')
            (repo / 'docs/licenses/SUPERTONIC-MODEL-TERMS.md').symlink_to(repo / 'LICENSE')
            with self.assertRaisesRegex(ValueError, 'NOTICE, docs/licenses/SUPERTONIC-MODEL-TERMS.md'):
                release.dmg_license_files(repo)

    def test_dmg_shows_license_and_model_terms_beside_the_app(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo, image = self.license_repo(root / 'repo'), root / 'image'
            image.mkdir()
            names = release.stage_dmg_licenses(image, self.signed_app(root), repo)
            self.assertEqual(names, ['LICENSE', 'NOTICE', 'SUPERTONIC-MODEL-TERMS.md', 'Supertonic-3-Open-RAIL-M.txt',
                                     'THIRD-PARTY-NOTICES.html'])
            self.assertEqual((image / 'Licenses/SUPERTONIC-MODEL-TERMS.md').read_text(),
                             'text of docs/licenses/SUPERTONIC-MODEL-TERMS.md')
            self.assertFalse(any(path.is_symlink() for path in (image / 'Licenses').iterdir()))
            (root / 'Saywing.app/Contents/Resources/THIRD-PARTY-NOTICES.html').unlink()
            with self.assertRaisesRegex(ValueError, 'THIRD-PARTY-NOTICES'):
                release.stage_dmg_licenses(root / 'other', root / 'Saywing.app', repo)

    def test_repository_license_documents_for_the_dmg(self):
        # NOTICE and SUPERTONIC-MODEL-TERMS.md are added by the model-terms change; until it is
        # merged the release script must refuse to build.
        present = [relative for relative, _ in release.DMG_LICENSE_FILES if (release.REPO / relative).is_file()]
        if len(present) == len(release.DMG_LICENSE_FILES):
            release.dmg_license_files()
        else:
            with self.assertRaises(ValueError):
                release.dmg_license_files()
        self.assertIn('LICENSE', present)
        self.assertIn('docs/licenses/Supertonic-3-Open-RAIL-M.txt', present)

    def test_packaged_dmg_contains_licenses_folder(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        import plistlib
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo, app, output = self.license_repo(root / 'repo'), self.signed_app(root), root / 'out'
            output.mkdir()
            args = SimpleNamespace(build='7', version='1.2.3', feed_url='https://example.com/appcast.xml',
                                   public_key='key', sparkle_account='saywing', notarize=False, public_release=False,
                                   download_url_prefix='https://example.com', sparkle_key_file=None, architecture='arm64',
                                   identity='Developer ID Application: Example (TEAM123456)')
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleVersion': '7', 'CFBundleShortVersionString': '1.2.3',
                'SUFeedURL': args.feed_url, 'SUPublicEDKey': 'key'}))
            seen = {}
            def fake_run(*command, **kwargs):
                if command[0] == '/usr/bin/hdiutil':
                    source = Path(command[command.index('-srcfolder') + 1])
                    seen['licenses'] = sorted(path.name for path in (source / 'Licenses').iterdir())
                    seen['app'] = (source / 'Saywing.app').is_dir()
                    Path(command[-1]).write_bytes(b'dmg')
                return SimpleNamespace(stdout='key' if str(command[0]).endswith('generate_keys') else '')
            with patch.object(release, 'run', side_effect=fake_run), patch.object(release, 'REPO', repo), \
                 patch.object(release, 'generate_feed'):
                release.package_signed_app(app, output, args, Path('/tools'))
            self.assertTrue(seen['app'])
            self.assertEqual(seen['licenses'], ['LICENSE', 'NOTICE', 'SUPERTONIC-MODEL-TERMS.md',
                                                'Supertonic-3-Open-RAIL-M.txt', 'THIRD-PARTY-NOTICES.html'])
            self.assertFalse((output / 'image').exists())
            # The publish job archives exactly the sources this signed app points to.
            result = json.loads((output / 'release-result.json').read_text())
            self.assertEqual(result['corresponding_sources'], self.SOURCES)

    def test_committed_approvals_explain_an_open_license_review(self):
        for architecture in ['arm64', 'x86_64']:
            path = release.release_target(architecture)['approval']
            record = json.loads(path.read_text())
            if record['license_review'] is not True:
                self.assertTrue(record.get('license_review_note', '').strip(), path.name)
                with self.assertRaisesRegex(ValueError, 'license_review'):
                    release.require_release_approval(path, architecture)

    def test_version_numbers_are_monotonic_and_path_safe(self):
        release.validate_version('0.1.0', '42')
        for version, build in [('0.1.0', '0'), ('../oops', '3'), ('1.0', 'abc'), ('1.2.3', '1/2')]:
            with self.assertRaises(ValueError):
                release.validate_version(version, build)


if __name__ == '__main__':
    unittest.main()
