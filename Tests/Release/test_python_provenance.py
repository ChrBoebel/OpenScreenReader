import copy
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, REPO / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = load('python_provenance', 'scripts/python_provenance.py')
builder = load('build_python_runtime', 'scripts/build-python-runtime.py')
HEX40 = re.compile(r'^[0-9a-f]{40}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')


class PythonProvenanceRecordTests(unittest.TestCase):
    def setUp(self):
        self.pins = json.loads((REPO / 'Runtime/Portable/python.json').read_text())
        self.record = json.loads((REPO / provenance.RECORD).read_text())

    def test_record_matches_every_pinned_interpreter(self):
        provenance.check_pins(self.record, self.pins)
        self.assertEqual(sorted(self.record['architectures']), sorted(self.pins))
        for architecture, pin in self.pins.items():
            stripped = self.record['architectures'][architecture]['stripped']
            self.assertEqual((stripped['url'], stripped['bytes'], stripped['sha256']), (pin['url'], pin['bytes'], pin['sha256']))
            self.assertEqual((self.record['release'], self.record['version']), (pin['release'], pin['version']))

    def test_pin_bump_without_new_provenance_fails(self):
        for field, value in [('sha256', '0' * 64), ('bytes', 1), ('release', '20991231'), ('version', '3.12.99'),
                             ('url', 'https://example.invalid/python.tar.gz')]:
            pins = copy.deepcopy(self.pins)
            pins['arm64'][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'provenance'):
                provenance.check_pins(self.record, pins)
        pins = copy.deepcopy(self.pins)
        pins['riscv64'] = pins['arm64']
        with self.assertRaisesRegex(ValueError, 'provenance'):
            provenance.check_pins(self.record, pins)

    def test_source_recipe_and_patches_are_exact_git_pointers(self):
        self.assertRegex(self.record['source']['commit'], HEX40)
        self.assertEqual(self.record['source']['repository'], self.pins['arm64']['provider'])
        recipe = {entry['path'] for entry in self.record['recipe']['files']}
        self.assertTrue({'cpython-unix/build-cpython.sh', 'cpython-unix/targets.yml', 'pythonbuild/downloads.json'} <= recipe)
        patches = self.record['cpython_patches']['applied']
        self.assertTrue(patches)
        for entry in self.record['recipe']['files'] + patches:
            self.assertRegex(entry['blob'], HEX40, entry['path'])
        for patch in patches:
            self.assertRegex(patch['path'], r'^cpython-unix/patch-[^/]+\.patch$')
            self.assertTrue(set(patch['architectures']) <= set(self.pins), patch['path'])

    def test_full_archive_is_the_same_release_and_target_and_was_checked(self):
        for architecture, entry in self.record['architectures'].items():
            full, stripped = entry['full'], entry['stripped']
            self.assertEqual(full['url'].rsplit('/', 1)[0], stripped['url'].rsplit('/', 1)[0])
            self.assertIn('-%s-pgo%%2Blto-full.tar.zst' % entry['target_triple'], full['url'])
            self.assertIn('-%s-install_only_stripped.tar.gz' % entry['target_triple'], stripped['url'])
            self.assertRegex(full['sha256'], HEX64)
            checks = entry['consistency']
            self.assertEqual(checks['full_python_json']['python_version'], self.record['version'])
            self.assertEqual(checks['full_python_json']['target_triple'], entry['target_triple'])
            self.assertEqual(checks['unexplained_differences'], [], architecture)
            self.assertEqual(checks['byte_identical_files'] + len(checks['mach_o_debug_stripped_same_lc_uuid_and_sections'])
                             + len(checks['pe_debug_stripped_same_sections']), checks['stripped_files'])

    def test_recorded_license_set_is_the_one_the_runtime_ships(self):
        for architecture, entry in self.record['architectures'].items():
            licenses = entry['licenses']
            self.assertEqual(licenses['notice_directory'], builder.CPYTHON_NOTICES[architecture])
            shipped = sorted(path.name for path in (REPO / licenses['notice_directory']).glob('LICENSE.*.txt'))
            self.assertEqual(licenses['shipped_files'], shipped)
            self.assertTrue(set(shipped) <= set(licenses['full_archive_files']))
            self.assertTrue(licenses['shipped_files_identical_to_full_archive'])

    def test_runtime_provenance_names_the_interpreter_build(self):
        reference = builder.interpreter_provenance(self.pins['arm64'], 'arm64')
        self.assertEqual(reference['record'], provenance.RECORD)
        self.assertEqual(reference['source_commit'], self.record['source']['commit'])
        self.assertEqual(reference['full_archive_sha256'], self.record['architectures']['arm64']['full']['sha256'])
        changed = dict(self.pins['arm64'], sha256='0' * 64)
        with self.assertRaisesRegex(ValueError, 'provenance'):
            builder.interpreter_provenance(changed, 'arm64')


class ArchiveComparisonTests(unittest.TestCase):
    def test_tree_comparison_reports_changed_and_missing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            stripped, full = Path(temp) / 'stripped', Path(temp) / 'full'
            (stripped / 'python/lib').mkdir(parents=True)
            (full / 'python/install/lib').mkdir(parents=True)
            for name, content in [('same.py', 'x'), ('changed.py', 'a')]:
                (stripped / 'python/lib' / name).write_text(content)
            (full / 'python/install/lib/same.py').write_text('x')
            (full / 'python/install/lib/changed.py').write_text('b')
            (stripped / 'python/lib/extra.py').write_text('y')
            result = provenance.compare_trees(stripped / 'python', full / 'python/install')
            self.assertEqual(result['byte_identical'], 1)
            self.assertEqual(result['problems'], ['content differs: lib/changed.py', 'missing in full archive: lib/extra.py'])


if __name__ == '__main__':
    unittest.main()
