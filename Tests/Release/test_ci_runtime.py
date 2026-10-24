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

class RuntimeExtractionTests(unittest.TestCase):
    def test_dmg_validates_ticket_and_always_unmounts_after_copy_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); archive = base / 'runtime.dmg'; archive.touch()
            calls = []
            def run(*args, **kwargs):
                calls.append(tuple(str(a) for a in args))
                if args[:2] == ('hdiutil', 'attach'):
                    (base / 'runtime-mount/Saywing.app').mkdir()
                if args[0] == '/usr/bin/ditto': raise RuntimeError('copy failed')
            with patch.object(ci, 'run', side_effect=run):
                with self.assertRaisesRegex(RuntimeError, 'copy failed'):
                    ci.extract_runtime(archive, base / 'saywing-runtime', 'dmg')
            self.assertEqual(calls[0][:3], ('xcrun', 'stapler', 'validate'))
            self.assertIn('-readonly', calls[1]); self.assertIn('-nobrowse', calls[1])
            self.assertEqual(calls[-1][:2], ('hdiutil', 'detach'))

    def test_zip_compatibility_and_unknown_format_rejection(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            with patch.object(ci, 'run') as run:
                ci.extract_runtime(base / 'runtime.zip', base / 'output', 'zip')
                self.assertEqual(run.call_args.args[:4], ('/usr/bin/ditto', '-x', '-k', base / 'runtime.zip'))
                run.reset_mock()
                with self.assertRaises(ValueError): ci.extract_runtime(base / 'runtime', base / 'output', 'exe')
                run.assert_not_called()


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
