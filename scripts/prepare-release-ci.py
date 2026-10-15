#!/usr/bin/env python3
"""Provision an ephemeral GitHub runner. Never export the local login keychain."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

from release import REPO, digest, https_url, require_release_approval, run, sparkle_tools, release_target


def required(name):
    value = os.environ.get(name, '')
    if not value:
        raise ValueError('Missing CI configuration: ' + name)
    return value


def extract_runtime(archive, destination, archive_format):
    if archive_format == 'zip':
        run('/usr/bin/ditto', '-x', '-k', archive, destination)
        return
    if archive_format != 'dmg':
        raise ValueError('Unsupported pinned runtime format')
    # The archive SHA-256 is checked before this function. Reuse the notarized
    # candidate directly instead of uploading the same large resources twice.
    run('xcrun', 'stapler', 'validate', archive)
    mount = destination.parent / 'runtime-mount'
    mount.mkdir(exist_ok=False)
    run('hdiutil', 'attach', '-nobrowse', '-readonly', '-mountpoint', mount, archive)
    try:
        source = mount / 'Saywing.app'
        if not source.is_dir() or source.is_symlink():
            raise ValueError('Pinned DMG has no regular Saywing app bundle')
        destination.mkdir(exist_ok=True)
        run('/usr/bin/ditto', source, destination / 'Saywing.app')
    finally:
        run('hdiutil', 'detach', mount)


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('This helper is only for disposable GitHub Actions runners')
    temp = Path(required('RUNNER_TEMP')).resolve(strict=True)
    keychain = temp / 'saywing-release.keychain-db'
    mode = sys.argv[1]
    if mode == 'runtime':
        architecture = os.environ.get('SAYWING_ARCHITECTURE', 'arm64')
        target = release_target(architecture)
        require_release_approval(target['approval'], architecture)
        https_url(required('SAYWING_FEED_URL'))
        https_url(required('SAYWING_DOWNLOAD_URL_PREFIX'))
        expected = required('SAYWING_RUNTIME_SHA256')
        if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
            raise ValueError('Expected an exact SHA-256 for the approved runtime archive')
        archive_format = os.environ.get('SAYWING_RUNTIME_FORMAT', 'zip')
        if archive_format not in ('zip', 'dmg'):
            raise ValueError('Unsupported pinned runtime format')
        archive = temp / ('saywing-runtime.' + archive_format)
        # Runtime-source archives are private. The website allowlist never
        # exposes this prefix; no public URL or expiring token is needed in Git.
        import boto3
        from botocore.config import Config
        client = boto3.client('s3', endpoint_url=https_url(required('SAYWING_S3_ENDPOINT')),
            region_name=os.environ.get('SAYWING_S3_REGION', 'auto'),
            aws_access_key_id=required('SAYWING_S3_ACCESS_KEY_ID'),
            aws_secret_access_key=required('SAYWING_S3_SECRET_ACCESS_KEY'),
            config=Config(signature_version='s3v4', s3={'addressing_style': 'virtual'}, connect_timeout=30, read_timeout=900,
                          request_checksum_calculation='when_required', response_checksum_validation='when_required'))
        client.download_file(required('SAYWING_S3_BUCKET'), f'saywing/runtime/{expected}.{archive_format}', str(archive))
        if digest(archive) != expected:
            archive.unlink()
            raise ValueError('Runtime archive SHA-256 mismatch')
        extract_runtime(archive, temp / 'saywing-runtime', archive_format)
        archive.unlink()
    elif mode == 'credentials':
        # Read all required secrets before creating any credential files.
        certificate = base64.b64decode(required('SAYWING_CERTIFICATE_P12'), validate=True)
        certificate_password = required('SAYWING_CERTIFICATE_PASSWORD')
        sparkle_key = required('SAYWING_SPARKLE_PRIVATE_KEY')
        apple_id = required('SAYWING_APPLE_ID')
        apple_password = required('SAYWING_APPLE_APP_PASSWORD')
        password = secrets.token_urlsafe(32)
        # Mask the temporary keychain password before invoking tools.
        print('::add-mask::' + password, flush=True)
        original = run('security', 'list-keychains', '-d', 'user', capture_output=True, text=True).stdout
        (temp / 'saywing-keychain-search-list.json').write_text(json.dumps([line.strip().strip('"') for line in original.splitlines()]))
        run('security', 'create-keychain', '-p', password, keychain)
        run('security', 'set-keychain-settings', '-lut', '7200', keychain)
        run('security', 'unlock-keychain', '-p', password, keychain)
        run('security', 'list-keychains', '-d', 'user', '-s', keychain)
        cert_file, key_file = temp / 'saywing-cert.p12', temp / 'saywing-sparkle.key'
        try:
            with cert_file.open('xb') as stream:
                os.chmod(cert_file, 0o600)
                stream.write(certificate)
            run('security', 'import', cert_file, '-k', keychain, '-P', certificate_password,
                '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, keychain,
                stdout=subprocess.DEVNULL)
            with key_file.open('x') as stream:
                os.chmod(key_file, 0o600)
                stream.write(sparkle_key)
            # Sparkle uses the default keychain for newly imported keys.
            default = run('security', 'default-keychain', '-d', 'user', capture_output=True, text=True).stdout.strip().strip('"')
            (temp / 'saywing-default-keychain.txt').write_text(default)
            run('security', 'default-keychain', '-d', 'user', '-s', keychain)
            run(sparkle_tools(REPO / '.build/packages') / 'generate_keys', '--account', 'saywing', '-f', key_file)
            run('xcrun', 'notarytool', 'store-credentials', 'Saywing-CI', '--keychain', keychain,
                '--apple-id', apple_id, '--team-id', 'S28WSHSSJD', '--password', apple_password)
        finally:
            cert_file.unlink(missing_ok=True)
            # Keep the mode-0600 Sparkle key until the always-run cleanup step.
            # Separate Sparkle executables cannot share an interactive keychain ACL in CI.
    elif mode == 'cleanup':
        # Remove secret files even if restoring the runner keychain later fails.
        for name in ('saywing-cert.p12', 'saywing-sparkle.key'):
            (temp / name).unlink(missing_ok=True)
        default = temp / 'saywing-default-keychain.txt'
        if default.exists():
            run('security', 'default-keychain', '-d', 'user', '-s', default.read_text())
        original = temp / 'saywing-keychain-search-list.json'
        if original.exists():
            run('security', 'list-keychains', '-d', 'user', '-s', *json.loads(original.read_text()))
        if keychain.exists():
            run('security', 'delete-keychain', keychain)
    else:
        raise ValueError('Expected runtime, credentials or cleanup')


if __name__ == '__main__':
    main()
