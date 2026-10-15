import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

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
            'notarized': True, 'public_release_approved': True, 'source_commit': 'commit', 'architecture': architecture}))
        return meta
    def test_promotes_only_after_immutable_files_and_public_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store(); verified = []
            def verify(meta):
                self.assertNotIn('saywing/current.json', store.objects)
                self.assertEqual(len(store.objects), 4)
                verified.append(meta['build'])
            publisher.publish(root, store, 'bucket', lambda: 'commit', verify)
            self.assertEqual(verified, ['3'])
            self.assertEqual(store.writes[-1], 'saywing/current.json')
            before = list(store.writes)
            publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
            self.assertEqual(store.writes, before) # Idempotent retry.
    def test_failed_download_or_stale_main_never_promotes(self):
        for failure in ['download', 'stale']:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.release(root); store = Store()
                def verify(_):
                    if failure == 'download': raise ValueError('Public digest mismatch')
                with self.assertRaises(ValueError):
                    publisher.publish(root, store, 'bucket', lambda: 'newer' if failure == 'stale' else 'commit', verify)
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
                    publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
                self.assertEqual(store.writes, [])
    def test_existing_versioned_object_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root); store = Store()
            store.objects['saywing/releases/3/Saywing-0.1.2-3.dmg'] = (b'other', {'sha256': 'wrong'})
            with self.assertRaises(ValueError):
                publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
            self.assertNotIn('saywing/current.json', store.objects)

    def test_intel_promotion_does_not_read_or_change_arm_release(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root, 'x86_64'); store = Store()
            arm = (json.dumps({'build': '108'}).encode(), {})
            store.objects['saywing/current.json'] = arm
            publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
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
                with self.assertRaises(ValueError): publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
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
                    publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
                self.assertEqual(store.writes, [])

    def test_intel_retry_and_downgrade_are_independent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.release(root, 'x86_64'); store = Store()
            publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
            writes = list(store.writes)
            publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
            self.assertEqual(store.writes, writes)
            key = 'saywing/x86_64/current.json'
            store.objects[key] = (json.dumps({'build': '4', 'architecture': 'x86_64'}).encode(), {})
            with self.assertRaisesRegex(ValueError, 'downgrade'):
                publisher.publish(root, store, 'bucket', lambda: 'commit', lambda _: None)
            self.assertEqual(store.writes, writes)
