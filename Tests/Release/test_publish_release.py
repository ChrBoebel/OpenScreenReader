import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('publish_release', SCRIPTS / 'publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class Missing(Exception):
    response = {'Error': {'Code': 'NoSuchKey'}}

class Store:
    def __init__(self):
        self.objects = {}
        self.writes = []
    def head_object(self, Bucket, Key):
        if Key not in self.objects:
            raise Missing()
        body, metadata = self.objects[Key]
        return {'ContentLength': len(body), 'Metadata': metadata, 'ETag': '"etag"'}
    def get_object(self, Bucket, Key):
        result = self.head_object(Bucket, Key)
        return {**result, 'Body': io.BytesIO(self.objects[Key][0])}
    def put_object(self, **args):
        key = args['Key']
        if args.get('IfNoneMatch') == '*' and key in self.objects:
            raise ValueError('Conditional write conflict')
        if key.endswith('/current.json') and key in self.objects:
            assert args['IfMatch'] == '"etag"'
        body = args['Body']
        self.objects[key] = (body.read() if hasattr(body, 'read') else body, args.get('Metadata', {}))
        self.writes.append(key)

SOURCE = b'pinned corresponding source'
SOURCES = [{'file': 'gcc.tar.xz', 'url': 'https://example.invalid/gcc.tar.xz', 'bytes': len(SOURCE),
            'sha256': publisher.hashlib.sha256(SOURCE).hexdigest(), 'component': 'GCC', 'license': 'LGPL-2.1-or-later'}]


def fetch(item, directory, content=SOURCE):
    """Stands in for the verified upstream download; never touches the network."""
    path = directory / item['file']
    path.write_bytes(content)
    return path


def no_fetch(item, directory):
    raise AssertionError('archived source must not be downloaded again')


def publish(root, store, main_commit=lambda: 'commit', verify=lambda _: None, fetch_source=fetch):
    with patch.object(publisher, 'corresponding_sources', return_value=SOURCES):
        publisher.publish(root, store, 'bucket', main_commit, verify, fetch_source=fetch_source)


def released(store):
    return [key for key in store.objects if '/releases/' in key]


class PublishTests(unittest.TestCase):
    def release(self, root, architecture="arm64"):
        folder = root / 'publish'
        folder.mkdir()
        archive = folder / 'Saywing-0.1.2-3.dmg'
        archive.write_bytes(b'fixture archive - not a notarized app')
        prefix = publisher.PUBLIC_PREFIX + ('/x86_64' if architecture == 'x86_64' else '')
        meta = {'version': '0.1.2', 'build': '3', 'architecture': architecture, 'url': prefix + '/' + archive.name,
                'bytes': archive.stat().st_size, 'sha256': publisher.digest(archive)}
        (folder / 'latest.json').write_text(json.dumps(meta))
        (folder / 'appcast.xml').write_text('<rss/>')
        (folder / 'SHA256SUMS').write_text(meta['sha256'] + '  ' + archive.name + '\n')
        (root / 'release-result.json').write_text(json.dumps({'version': '0.1.2', 'build': '3',
            'notarized': True, 'public_release_approved': True, 'source_commit': 'commit', 'architecture': architecture,
            'corresponding_sources': SOURCES}))
        return meta
    def test_promotes_only_after_immutable_files_and_public_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store(); verified = []
            def verify(meta):
                self.assertNotIn('saywing/current.json', store.objects)
                self.assertEqual(len(released(store)), 4)
                verified.append(meta['build'])
            publish(root, store, verify=verify)
            self.assertEqual(verified, ['3'])
            self.assertEqual(store.writes[-1], 'saywing/current.json')
            before = list(store.writes)
            publish(root, store, fetch_source=no_fetch)
            self.assertEqual(store.writes, before) # Idempotent retry.
    def test_failed_download_or_stale_main_never_promotes(self):
        for failure in ['download', 'stale']:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root); store = Store()
                def verify(_):
                    if failure == 'download': raise ValueError('Public digest mismatch')
                with self.assertRaises(ValueError):
                    publish(root, store, lambda: 'newer' if failure == 'stale' else 'commit', verify)
                self.assertNotIn('saywing/current.json', store.objects)
    def test_refuses_unapproved_tampered_and_downgrade_releases(self):
        for failure in ['unapproved', 'tampered', 'downgrade']:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root); store = Store()
                if failure == 'unapproved':
                    result = root / 'release-result.json'; data = json.loads(result.read_text())
                    data['notarized'] = False; result.write_text(json.dumps(data))
                elif failure == 'tampered':
                    (root / 'publish/Saywing-0.1.2-3.dmg').write_bytes(b'changed')
                else:
                    store.objects['saywing/current.json'] = (json.dumps({'build': '4'}).encode(), {})
                with self.assertRaises(ValueError):
                    publish(root, store)
                self.assertEqual(store.writes, [])
    def test_existing_versioned_object_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store()
            store.objects['saywing/releases/3/Saywing-0.1.2-3.dmg'] = (b'other', {'sha256': 'wrong'})
            with self.assertRaises(ValueError):
                publish(root, store)
            self.assertNotIn('saywing/current.json', store.objects)

    def test_intel_promotion_does_not_read_or_change_arm_release(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root, 'x86_64'); store = Store()
            arm = (json.dumps({'build': '108'}).encode(), {})
            store.objects['saywing/current.json'] = arm
            publish(root, store)
            self.assertEqual(store.objects['saywing/current.json'], arm)
            self.assertEqual(store.writes[-1], 'saywing/x86_64/current.json')
            self.assertTrue(all(key.startswith('saywing/x86_64/') for key in store.writes))
            self.assertEqual(json.loads(store.objects[store.writes[-1]][0])['architecture'], 'x86_64')

    def test_cross_architecture_metadata_rejected_before_upload(self):
        for changed in ['url', 'architecture']:
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); self.release(root, 'x86_64'); store=Store()
                path=root/'publish/latest.json'; meta=json.loads(path.read_text())
                meta[changed] = publisher.PUBLIC_PREFIX + '/Saywing-0.1.2-3.dmg' if changed == 'url' else 'arm64'
                path.write_text(json.dumps(meta))
                with self.assertRaises(ValueError): publish(root, store)
                self.assertEqual(store.writes, [])

    def test_pointer_architecture_must_match_namespace(self):
        for architecture, previous_architecture in [('arm64', 'x86_64'), ('x86_64', 'arm64'), ('x86_64', None)]:
            with self.subTest(architecture=architecture, previous=previous_architecture), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root, architecture); store = Store()
                prefix = publisher.release_target(architecture)['storage_prefix']
                previous = {'build': '2'}
                if previous_architecture: previous['architecture'] = previous_architecture
                store.objects[prefix + '/current.json'] = (json.dumps(previous).encode(), {})
                with self.assertRaisesRegex(ValueError, 'architecture'):
                    publish(root, store)
                self.assertEqual(store.writes, [])

    def test_intel_retry_and_downgrade_are_independent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root, 'x86_64'); store = Store()
            publish(root, store)
            writes = list(store.writes)
            publish(root, store)
            self.assertEqual(store.writes, writes)
            key = 'saywing/x86_64/current.json'
            store.objects[key] = (json.dumps({'build': '4', 'architecture': 'x86_64'}).encode(), {})
            with self.assertRaisesRegex(ValueError, 'downgrade'):
                publish(root, store)
            self.assertEqual(store.writes, writes)

    def test_corresponding_sources_are_archived_before_any_release_file(self):
        for architecture in ['arm64', 'x86_64']:
            with self.subTest(architecture=architecture), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root, architecture); store = Store()
                publish(root, store)
                prefix = publisher.release_target(architecture)['storage_prefix'] + '/corresponding-source'
                source_key = f"{prefix}/sha256/{SOURCES[0]['sha256']}/gcc.tar.xz"
                self.assertEqual(store.objects[source_key], (SOURCE, {'sha256': SOURCES[0]['sha256']}))
                manifest = json.loads(store.objects[f'{prefix}/builds/3.json'][0])
                self.assertEqual((manifest['build'], manifest['version'], manifest['architecture'], manifest['source_commit']),
                                 ('3', '0.1.2', architecture, 'commit'))
                self.assertEqual(manifest['sources'], [{**SOURCES[0], 'key': source_key}])
                first_release = min(store.writes.index(key) for key in released(store))
                self.assertLess(store.writes.index(source_key), first_release)
                self.assertLess(store.writes.index(f'{prefix}/builds/3.json'), first_release)
                self.assertFalse([key for key in store.writes if '/corresponding-source/' in key and '/releases/' in key])

    def test_source_archived_by_an_earlier_build_is_reused_without_download(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store()
            key = f"saywing/corresponding-source/sha256/{SOURCES[0]['sha256']}/gcc.tar.xz"
            store.objects[key] = (SOURCE, {'sha256': SOURCES[0]['sha256']})
            publish(root, store, fetch_source=no_fetch)
            self.assertNotIn(key, store.writes)
            self.assertEqual(store.writes[-1], 'saywing/current.json')

    def test_unverifiable_source_blocks_publication(self):
        def unavailable(item, directory):
            raise OSError('upstream unavailable')
        cases = {'tampered': lambda item, directory: fetch(item, directory, b'tampered corresponding source'),
                 'truncated': lambda item, directory: fetch(item, directory, SOURCE[:-1]),
                 'unavailable': unavailable}
        for name, fetcher in cases.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root); store = Store()
                with self.assertRaises((ValueError, OSError)):
                    publish(root, store, fetch_source=fetcher)
                self.assertEqual(released(store), [])
                self.assertNotIn('saywing/current.json', store.objects)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store()
            key = f"saywing/corresponding-source/sha256/{SOURCES[0]['sha256']}/gcc.tar.xz"
            store.objects[key] = (b'other bytes', {'sha256': '0' * 64})
            with self.assertRaisesRegex(ValueError, 'immutable'):
                publish(root, store)
            self.assertEqual(released(store), [])

    def test_shipped_source_pointers_must_match_the_repository(self):
        for change in ['missing', 'different']:
            with self.subTest(change), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root); store = Store()
                path = root / 'release-result.json'; data = json.loads(path.read_text())
                if change == 'missing':
                    del data['corresponding_sources']
                else:
                    data['corresponding_sources'] = [{**SOURCES[0], 'sha256': '1' * 64}]
                path.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, 'Corresponding-source'):
                    publish(root, store)
                self.assertEqual(store.writes, [])

    def test_release_repository_is_pinned_but_overridable(self):
        import os
        from unittest.mock import patch
        class Response(io.BytesIO):
            def __enter__(self): return self
            def __exit__(self, *_): return False
        requested = []
        def urlopen(request, timeout):
            requested.append(request.full_url)
            return Response(json.dumps({'object': {'sha': 'abc'}}).encode())
        cases = [({'GITHUB_REPOSITORY': publisher.DEFAULT_REPOSITORY}, True),
                 ({'GITHUB_REPOSITORY': 'someone/fork'}, False),
                 ({'GITHUB_REPOSITORY': 'someone/fork', 'SAYWING_RELEASE_REPOSITORY': 'someone/fork'}, True)]
        for env, allowed in cases:
            with self.subTest(env=env), patch.dict(os.environ, {**env, 'GH_TOKEN': 'test-token'}), \
                 patch.object(publisher.urllib.request, 'urlopen', side_effect=urlopen):
                if 'SAYWING_RELEASE_REPOSITORY' not in env:
                    os.environ.pop('SAYWING_RELEASE_REPOSITORY', None)
                if allowed:
                    self.assertEqual(publisher.current_main(), 'abc')
                    self.assertEqual(requested[-1], f"https://api.github.com/repos/{env['GITHUB_REPOSITORY']}/git/ref/heads/main")
                else:
                    count = len(requested)
                    with self.assertRaisesRegex(ValueError, 'repository'): publisher.current_main()
                    self.assertEqual(len(requested), count)
