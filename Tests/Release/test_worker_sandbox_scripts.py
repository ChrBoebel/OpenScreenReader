"""Developer scripts must confine workers with the app's profile, not a private, looser one."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

root = Path(__file__).resolve().parents[2]
helper = root / 'scripts/worker_sandbox.rb'
profile = root / 'Runtime/Dictation/worker.sb'


def sources():
    for directory in ['scripts', 'Tests']:
        for path in sorted((root / directory).rglob('*')):
            if path.is_file() and path.suffix in {'.rb', '.py', '.sh', '.swift'} and path != Path(__file__).resolve():
                yield path


def command(resources, executable, model_root=None):
    script = ('require "json"; puts JSON.generate(WorkerSandbox.command(resources: ARGV[0], executable: ARGV[1], '
              'model_root: ARGV[2]))')
    arguments = ['ruby', '-r', str(helper), '-e', script, str(resources), str(executable)]
    arguments += [str(model_root)] if model_root else []
    return json.loads(subprocess.run(arguments, check=True, capture_output=True, text=True).stdout)


class WorkerSandboxScriptTests(unittest.TestCase):
    def test_no_script_or_test_embeds_an_allow_default_profile(self):
        offenders = [str(path.relative_to(root)) for path in sources() if '(allow default)' in path.read_text()]
        self.assertEqual(offenders, [], 'Use scripts/worker_sandbox.rb, which loads Runtime/Dictation/worker.sb.')

    def test_scripts_start_sandbox_exec_only_through_the_shared_helper(self):
        launchers = [str(path.relative_to(root)) for path in sources()
                     if path.is_relative_to(root / 'scripts') and path != helper and '/usr/bin/sandbox-exec' in path.read_text()]
        self.assertEqual(launchers, [])
        for name in ['verify-speech-worker.rb', 'verify-supertonic-worker.rb', 'compare-german-voices.rb']:
            self.assertIn("require_relative 'worker_sandbox'", (root / 'scripts' / name).read_text(), name)

    def test_helper_passes_the_app_profile_with_canonical_parameters(self):
        with tempfile.TemporaryDirectory() as tmp:
            # macOS temporary folders live behind the /var -> /private/var symlink, like Foundation paths.
            base = Path(tmp)
            runtime, models = base / 'Runtime', base / 'Models'
            (runtime / 'bin').mkdir(parents=True)
            models.mkdir()
            python = runtime / 'bin/python3'
            python.write_text('')
            canonical = os.path.realpath(base)
            result = command(runtime, python, models)
            self.assertEqual(result[:3], ['/usr/bin/sandbox-exec', '-p', profile.read_text()])
            self.assertEqual(result[3:], [
                '-D', f'RESOURCES={canonical}/Runtime', '-D', f'MODEL_ROOT={canonical}/Models',
                '-D', f'PYTHON={canonical}/Runtime/bin/python3', '-D', f'PYTHON_HOME={canonical}/Runtime',
                str(python)])
            self.assertIn(f'MODEL_ROOT={canonical}/Runtime', command(runtime, python),
                          'Without a model folder the runtime is the model root, as in the app.')

    def test_helper_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp)
            self.assertIsNone(command(runtime / 'missing', '/bin/cat'))
            self.assertIsNone(command(runtime, runtime / 'missing'))
            self.assertIsNone(command(runtime, '/bin/cat'), 'An executable directly below / would expose the disk.')


if __name__ == '__main__':
    unittest.main()
