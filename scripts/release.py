#!/usr/bin/env python3
"""Build, seal and optionally notarize Saywing. Never publishes or downloads models.

Runtime input is a previously verified self-contained app; CI additionally pins
its archive by SHA-256. Signing refreshes runtime receipts only after verification.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
from urllib.parse import urlsplit

REPO = Path(__file__).resolve().parents[1]
RELEASE_GATES = ('license_review', 'clean_mac', 'offline_privacy', 'update_roundtrip')
MACHO = {bytes.fromhex(value) for value in (
    'cffaedfe', 'cefaedfe', 'feedfacf', 'feedface', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def https_url(value):
    url = urlsplit(value)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.query or url.fragment or '$(' in value):
        raise ValueError('Expected a public HTTPS URL without credentials, query or fragment')
    return value


def validate_version(version, build):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Version must be x.y.z; build must be a positive increasing integer')


def require_release_approval(path):
    record = json.loads(path.read_text())
    missing = [key for key in RELEASE_GATES if record.get(key) is not True]
    if missing:
        raise ValueError('Public release gates remain open: ' + ', '.join(missing))


def contained(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or '..' in Path(relative).parts or not path.resolve(strict=True).is_relative_to(root.resolve()):
        raise ValueError('Resource path escapes its root')
    return path


def verify_receipt(root, receipt_path):
    receipt = json.loads(receipt_path.read_text())
    if not receipt.get('files'):
        raise ValueError('Empty runtime receipt')
    for relative, expected in receipt['files'].items():
        if digest(contained(root, relative)) != expected:
            raise ValueError('Runtime receipt mismatch: ' + relative)
    return receipt


def receipts(app):
    resources = app / 'Contents/Resources'
    return [(resources / 'Speech', resources / 'Speech/SupertonicRuntime/installation-receipt.json'),
            (resources / 'Dictation', resources / 'Dictation/installation-receipt.json')]


def verify_speech_model(app):
    speech = app / 'Contents/Resources/Speech'
    manifest = json.loads((REPO / 'docs/research/supertonic-comparison-manifest.json').read_text())
    bundled = json.loads((speech / 'SupertonicRuntime/model-manifest.json').read_text())
    if bundled != manifest:
        raise ValueError('Bundled speech manifest differs from pinned repository manifest')
    model = speech / 'DevelopmentModels/supertonic-3-3cadd1ee'
    for entry in manifest['files']:
        path = contained(model, entry['path'])
        if path.stat().st_size != entry['bytes']:
            raise ValueError('Speech model size mismatch')
        actual = digest(path) if entry.get('sha256') else hashlib.sha1(
            f'blob {path.stat().st_size}\0'.encode() + path.read_bytes()).hexdigest()
        if actual != (entry.get('sha256') or entry['git_blob']):
            raise ValueError('Speech model hash mismatch')


def sign_bundle(app, identity):
    verified = [(root, path, verify_receipt(root, path)) for root, path in receipts(app)]
    verify_speech_model(app)
    for path in app.rglob('*'):
        if path.is_symlink() and not path.resolve(strict=True).is_relative_to(app):
            raise ValueError('External or broken app symlink')
    native = []
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    native.append(path)
    # Framework and XPC bundle seals must be created after their contained code.
    nested_bundles = [path for path in app.rglob('*') if path.is_dir()
                      and not path.is_symlink() and path.suffix in ('.framework', '.xpc', '.app', '.bundle')]
    targets = set(native + nested_bundles)
    for path in sorted(targets, key=lambda p: (-len(p.parts), str(p))):
        run('/usr/bin/codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime',
            '--preserve-metadata=identifier,entitlements', path)
    for root, receipt_path, receipt in verified:
        receipt['files'] = {relative: digest(contained(root, relative)) for relative in receipt['files']}
        receipt['signing'] = {'identity': identity, 'reason': 'Refresh native-code hashes after Developer ID signing'}
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    run('/usr/bin/codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime',
        '--entitlements', REPO / 'OpenScreenReaderApp/Saywing.entitlements', app)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    for path in native:
        run('/usr/bin/codesign', '--verify', '--strict', path)
    for root, path in receipts(app):
        verify_receipt(root, path)
    verify_speech_model(app)
    run('python3', REPO / 'scripts/verify-app-permissions.py', app)


def notarize(path, profile, keychain, log_dir):
    # notarytool timeout leaves Apple's job running. Retain the submission ID/log;
    # never treat a timeout as accepted or automatically resubmit that upload.
    command = ['xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile,
               '--wait', '--timeout', '30m', '--output-format', 'json']
    if keychain:
        command += ['--keychain', keychain]
    log = log_dir / (path.name + '.notary.json')
    with log.open('w') as stream:
        result = subprocess.run([str(part) for part in command], stdout=stream)
    record = json.loads(log.read_text() or '{}')
    if result.returncode or record.get('status') != 'Accepted':
        raise ValueError('Notarization not accepted; inspect ' + str(log))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New directory, never an installed app')
    parser.add_argument('--derived-data', type=Path, help='Reuse a separate Xcode build cache')
    parser.add_argument('--packages', type=Path, help='Reuse a separate resolved package directory')
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--feed-url', required=True)
    parser.add_argument('--download-url-prefix', required=True)
    parser.add_argument('--public-key', required=True)
    parser.add_argument('--identity', default='Developer ID Application: Christopher Böbel (S28WSHSSJD)')
    parser.add_argument('--notary-profile', default='Saywing-Notary-S28WSHSSJD')
    parser.add_argument('--keychain')
    parser.add_argument('--sparkle-account', default='saywing')
    parser.add_argument('--notarize', action='store_true')
    parser.add_argument('--public-release', action='store_true', help='Requires completed release-approval.json gates and notarization')
    args = parser.parse_args()
    validate_version(args.version, args.build)
    https_url(args.feed_url)
    https_url(args.download_url_prefix)
    key = base64.b64decode(args.public_key, validate=True)
    if len(key) != 32 or not any(key):
        raise ValueError('Invalid Sparkle public key')
    if not args.identity.startswith('Developer ID Application:'):
        raise ValueError('Release signing requires a Developer ID Application identity')
    if args.public_release:
        require_release_approval(REPO / 'docs/release-approval.json')
        if not args.notarize:
            raise ValueError('Public releases must be notarized')
    source = args.runtime_app.resolve(strict=True)
    for root, receipt in receipts(source):
        verify_receipt(root, receipt)
    verify_speech_model(source)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    derived = args.derived_data.resolve() if args.derived_data else output / 'DerivedData'
    packages = args.packages.resolve() if args.packages else output / 'packages'
    run('xcodebuild', '-project', REPO / 'OpenScreenReader.xcodeproj', '-scheme', 'OpenScreenReader',
        '-configuration', 'Release', '-derivedDataPath', derived, '-clonedSourcePackagesDirPath', packages,
        '-disableAutomaticPackageResolution', 'build', 'ARCHS=arm64', 'CODE_SIGNING_ALLOWED=NO',
        f'MARKETING_VERSION={args.version}', f'CURRENT_PROJECT_VERSION={args.build}',
        f'SAYWING_UPDATE_FEED_URL={args.feed_url}', f'SAYWING_UPDATE_PUBLIC_KEY={args.public_key}')
    app = output / 'Saywing.app'
    run('/usr/bin/ditto', derived / 'Build/Products/Release/Saywing.app', app)
    dictation = source / 'Contents/Resources/Dictation'
    run('python3', REPO / 'scripts/bundle-dictation-runtime.py', app, dictation,
        '--speech-from', source, '--whisper-model', dictation / 'WhisperTurbo', '--development-only', '--defer-app-signing')
    # Full upstream notice chain accompanies every distribution, including Sparkle.
    shutil.copy2(REPO / 'docs/licenses/Sparkle-2.10.0.txt', app / 'Contents/Resources/LICENSE-Sparkle')
    if args.public_release:
        (app / 'Contents/Resources/DEVELOPMENT-PREVIEW.txt').unlink(missing_ok=True)
    sign_bundle(app, args.identity)
    package_signed_app(app, output, args, sparkle_tools(packages))


def sparkle_tools(packages):
    artifact = packages / 'artifacts/sparkle/Sparkle'
    for directory in (artifact / 'bin', artifact / 'Sparkle/bin'):
        if all((directory / tool).is_file() for tool in ('generate_keys', 'generate_appcast', 'sign_update')):
            return directory
    raise ValueError('Pinned Sparkle tools were not resolved by Xcode')


def package_signed_app(app, output, args, tools):
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = {'CFBundleVersion': args.build, 'CFBundleShortVersionString': args.version,
                'SUFeedURL': args.feed_url, 'SUPublicEDKey': args.public_key}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('Signed app metadata differs from the requested release')
    publish = output / 'publish'
    publish.mkdir(exist_ok=True)
    actual_key = run(tools / 'generate_keys', '--account', args.sparkle_account, '-p', capture_output=True, text=True).stdout.strip()
    if actual_key != args.public_key:
        raise ValueError('Sparkle signing key does not match the public key embedded in the app')
    if args.notarize:
        upload = output / 'notary-upload.zip'
        run('/usr/bin/ditto', '-c', '-k', '--keepParent', app, upload)
        notarize(upload, args.notary_profile, args.keychain, output)
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=4', app)
    image_root = output / 'image'
    image_root.mkdir()
    run('/usr/bin/ditto', app, image_root / 'Saywing.app')
    (image_root / 'Applications').symlink_to('/Applications')
    image = publish / f'Saywing-{args.version}-{args.build}.dmg'
    run('/usr/bin/hdiutil', 'create', '-volname', 'Saywing', '-srcfolder', image_root, '-format', 'UDZO', image)
    run('/usr/bin/codesign', '--sign', args.identity, '--timestamp', image)
    if args.notarize:
        notarize(image, args.notary_profile, args.keychain, output)
        run('xcrun', 'stapler', 'staple', image)
        run('xcrun', 'stapler', 'validate', image)
        run('/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', image)
    # Generate the signed feed only after the final DMG bytes are immutable.
    run(tools / 'generate_appcast', '--account', args.sparkle_account,
        '--download-url-prefix', args.download_url_prefix.rstrip('/') + '/',
        '--maximum-deltas', '0', '-o', publish / 'appcast.xml', publish)
    run(tools / 'sign_update', '--account', args.sparkle_account, '--verify', publish / 'appcast.xml')
    (publish / 'SHA256SUMS').write_text(f'{digest(image)}  {image.name}\n')
    (publish / 'latest.json').write_text(json.dumps({
        'version': args.version, 'build': args.build, 'url': args.download_url_prefix.rstrip('/') + '/' + image.name,
        'bytes': image.stat().st_size, 'sha256': digest(image), 'minimum_macos': '14.0', 'architecture': 'arm64',
    }, indent=2) + '\n')
    (output / 'release-result.json').write_text(json.dumps({
        'public_release_approved': args.public_release, 'notarized': args.notarize,
        'version': args.version, 'build': args.build, 'publish_directory': str(publish),
        'source_commit': run('git', '-C', REPO, 'rev-parse', 'HEAD', capture_output=True, text=True).stdout.strip(),
    }, indent=2) + '\n')
    print('Prepared:', publish, '(not published)')


if __name__ == '__main__':
    main()
