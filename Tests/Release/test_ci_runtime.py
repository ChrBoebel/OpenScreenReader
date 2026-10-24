import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

scripts = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(scripts))
spec = importlib.util.spec_from_file_location('prepare_release_ci', scripts / 'prepare-release-ci.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

class RuntimePreparationTests(unittest.TestCase):
    def prepare(self, temp, architecture='arm64', approval=None, run=None):
        import os
        from unittest.mock import MagicMock
        run = run or MagicMock()
        env = {'GITHUB_ACTIONS': 'true', 'RUNNER_TEMP': temp, 'SAYWING_ARCHITECTURE': architecture,
               'SAYWING_FEED_URL': 'https://downloads.example.com/saywing/appcast.xml',
               'SAYWING_DOWNLOAD_URL_PREFIX': 'https://downloads.example.com/saywing'}
        with patch.dict(os.environ, env), patch.object(ci, 'run', run), \
             patch.object(ci, 'require_release_approval', side_effect=approval) as gate, \
             patch.object(sys, 'argv', ['prepare-release-ci.py', 'runtime']):
            ci.main()
        return run, gate

    def test_builds_the_runtime_from_pinned_public_inputs_for_each_architecture(self):
        for architecture in ['arm64', 'x86_64']:
            with self.subTest(architecture=architecture), tempfile.TemporaryDirectory() as temp:
                run, gate = self.prepare(temp, architecture)
                base = Path(temp).resolve()
                gate.assert_called_once()
                self.assertEqual(gate.call_args.args[1], architecture)
                args = [str(a) for a in run.call_args.args]
                self.assertTrue(args[1].endswith('scripts/assemble-release-runtime.py'))
                option = lambda name: args[args.index(name) + 1]
                self.assertEqual(option('--architecture'), architecture)
                # release.yml restores its download cache at exactly this path.
                self.assertEqual(option('--cache'), str(base / 'saywing-runtime-cache'))
                # release.yml passes this path to scripts/release.py --runtime-app.
                self.assertEqual(option('--output'), str(base / 'saywing-runtime/Saywing.app'))
                self.assertIn('--public-release', args)

    def test_open_release_gate_fails_before_any_download_or_build(self):
        from unittest.mock import MagicMock
        with tempfile.TemporaryDirectory() as temp:
            run = MagicMock()
            with self.assertRaisesRegex(ValueError, 'gates'):
                self.prepare(temp, approval=ValueError('Public release gates remain open: clean_mac'), run=run)
            run.assert_not_called()
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_no_private_runtime_archive_or_storage_credentials_remain(self):
        source = (scripts / 'prepare-release-ci.py').read_text()
        for name in ['SAYWING_RUNTIME_SHA256', 'SAYWING_RUNTIME_FORMAT', 'SAYWING_S3', 'boto3', 'saywing/runtime/']:
            self.assertNotIn(name, source)
        workflow = (scripts.parent / '.github/workflows/release.yml').read_text()
        package = workflow[workflow.index('\n  package:'):workflow.index('\n  publish:')]
        for name in ['SAYWING_RUNTIME_SHA256', 'SAYWING_INTEL_RUNTIME_SHA256', 'SAYWING_RUNTIME_FORMAT', 'SAYWING_S3', 'saywing-publisher']:
            self.assertNotIn(name, package)
        self.assertIn('--runtime-app "$RUNNER_TEMP/saywing-runtime/Saywing.app"', package)
        self.assertIn('path: ${{ runner.temp }}/saywing-runtime-cache', package)


class CredentialLifetimeTests(unittest.TestCase):
    def test_sparkle_key_survives_setup_until_cleanup_and_is_private(self):
        from types import SimpleNamespace
        import os
        with tempfile.TemporaryDirectory() as temp:
            env = {'GITHUB_ACTIONS': 'true', 'RUNNER_TEMP': temp,
                   'SAYWING_CERTIFICATE_P12': 'Y2VydA==', 'SAYWING_CERTIFICATE_PASSWORD': 'test',
                   'SAYWING_SPARKLE_PRIVATE_KEY': 'test-only-key',
                   'SAYWING_APPLE_ID': 'test@example.com', 'SAYWING_APPLE_APP_PASSWORD': 'test'}
            with patch.dict(os.environ, env), patch.object(ci, 'sparkle_tools', return_value=Path('/tools')), \
                 patch.object(ci, 'run', return_value=SimpleNamespace(stdout='"/original.keychain"\n')):
                with patch.object(sys, 'argv', ['prepare-release-ci.py', 'credentials']):
                    ci.main()
                key = Path(temp) / 'saywing-sparkle.key'
                self.assertEqual(key.read_text(), 'test-only-key')
                self.assertEqual(key.stat().st_mode & 0o777, 0o600)
                self.assertFalse((Path(temp) / 'saywing-cert.p12').exists())
                with patch.object(sys, 'argv', ['prepare-release-ci.py', 'cleanup']):
                    ci.main()
                self.assertFalse(key.exists())


class NotaryCredentialTests(unittest.TestCase):
    BASE = {'GITHUB_ACTIONS': 'true', 'SAYWING_CERTIFICATE_P12': 'Y2VydA==', 'SAYWING_CERTIFICATE_PASSWORD': 'test',
            'SAYWING_SPARKLE_PRIVATE_KEY': 'test-only-key'}
    OPTIONAL = ('SAYWING_APPLE_ID', 'SAYWING_APPLE_APP_PASSWORD', 'SAYWING_TEAM_ID', 'SAYWING_NOTARY_API_KEY',
                'SAYWING_NOTARY_API_KEY_ID', 'SAYWING_NOTARY_API_ISSUER')

    def provision(self, temp, extra):
        from types import SimpleNamespace
        import os
        calls, key_seen = [], []
        def run(*args, **kwargs):
            calls.append(tuple(str(a) for a in args))
            if args[:3] == ('xcrun', 'notarytool', 'store-credentials') and '--key' in args:
                key = Path(args[args.index('--key') + 1])
                key_seen.append((key.read_text(), key.stat().st_mode & 0o777))
            return SimpleNamespace(stdout='"/original.keychain"\n')
        with patch.dict(os.environ, {**self.BASE, 'RUNNER_TEMP': temp, **extra}), \
             patch.object(ci, 'sparkle_tools', return_value=Path('/tools')), patch.object(ci, 'run', side_effect=run):
            for name in set(self.OPTIONAL) - extra.keys():
                os.environ.pop(name, None)
            with patch.object(sys, 'argv', ['prepare-release-ci.py', 'credentials']):
                ci.main()
        return [call for call in calls if call[:3] == ('xcrun', 'notarytool', 'store-credentials')][0], key_seen

    def test_apple_id_path_uses_default_or_overridden_team(self):
        apple = {'SAYWING_APPLE_ID': 'test@example.com', 'SAYWING_APPLE_APP_PASSWORD': 'app-password'}
        for extra, team in [({}, ci.DEFAULT_TEAM_ID), ({'SAYWING_TEAM_ID': 'TEAM123456'}, 'TEAM123456')]:
            with self.subTest(team=team), tempfile.TemporaryDirectory() as temp:
                call, _ = self.provision(temp, {**apple, **extra})
                self.assertEqual(call[call.index('--team-id') + 1], team)
                self.assertEqual(call[3], ci.NOTARY_PROFILE)

    def test_api_key_path_keeps_secret_off_argv_and_deletes_key_file(self):
        secret = '-----BEGIN PRIVATE KEY-----\ntest-only\n-----END PRIVATE KEY-----\n'
        with tempfile.TemporaryDirectory() as temp:
            call, seen = self.provision(temp, {'SAYWING_NOTARY_API_KEY': secret, 'SAYWING_NOTARY_API_KEY_ID': 'KEY1234567',
                                               'SAYWING_NOTARY_API_ISSUER': '00000000-0000-0000-0000-000000000000'})
            self.assertEqual(seen, [(secret, 0o600)])
            self.assertFalse(any(secret in part or 'test-only' in part for part in call))
            self.assertNotIn('--password', call)
            self.assertNotIn('--apple-id', call)
            self.assertEqual(call[call.index('--key-id') + 1], 'KEY1234567')
            self.assertIn('--issuer', call)
            self.assertFalse((Path(temp) / 'saywing-notary-key.p8').exists())

    def test_incomplete_notary_configuration_fails_before_creating_files(self):
        for extra in [{}, {'SAYWING_NOTARY_API_KEY': '-----BEGIN PRIVATE KEY-----\nx\n'},
                      {'SAYWING_NOTARY_API_KEY': 'not a key', 'SAYWING_NOTARY_API_KEY_ID': 'KEY1234567'}]:
            with self.subTest(extra=list(extra)), tempfile.TemporaryDirectory() as temp:
                with self.assertRaises(ValueError):
                    self.provision(temp, extra)
                self.assertEqual(list(Path(temp).iterdir()), [])
