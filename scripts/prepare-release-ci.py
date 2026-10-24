#!/usr/bin/env python3
"""Prepare an ephemeral GitHub release runner. Never export the local login keychain.

runtime:     check the release gates, then build the runtime input from pinned public sources
credentials: import signing and notarization credentials into a temporary keychain
cleanup:     remove those credentials again
"""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

from release import REPO, https_url, require_release_approval, run, sparkle_tools, release_target

# Owner defaults; forks override these through repository variables.
DEFAULT_TEAM_ID = 'S28WSHSSJD'
NOTARY_PROFILE = 'Saywing-CI'


def required(name):
    value = os.environ.get(name, '')
    if not value:
        raise ValueError('Missing CI configuration: ' + name)
    return value


def notary_credentials(temp):
    """Read notarization credentials without creating files.

    Preferred: an App Store Connect API key (SAYWING_NOTARY_API_KEY = .p8 contents,
    SAYWING_NOTARY_API_KEY_ID, optional SAYWING_NOTARY_API_ISSUER for team keys).
    notarytool then reads the key from a mode-0600 file, so no secret is on argv.
    Fallback: Apple ID + app-specific password. notarytool has no non-interactive
    stdin/env input for that password, so it remains visible in the runner's
    process list for the duration of store-credentials (documented residual risk).
    """
    api_key = os.environ.get('SAYWING_NOTARY_API_KEY', '')
    if api_key:
        if '-----BEGIN PRIVATE KEY-----' not in api_key:
            raise ValueError('SAYWING_NOTARY_API_KEY must contain the .p8 private key')
        options = ['--key', temp / 'saywing-notary-key.p8', '--key-id', required('SAYWING_NOTARY_API_KEY_ID')]
        issuer = os.environ.get('SAYWING_NOTARY_API_ISSUER', '')
        if issuer:
            options += ['--issuer', issuer]
        return options, api_key
    team_id = os.environ.get('SAYWING_TEAM_ID') or DEFAULT_TEAM_ID
    return ['--apple-id', required('SAYWING_APPLE_ID'), '--team-id', team_id,
            '--password', required('SAYWING_APPLE_APP_PASSWORD')], None


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
        # Build the runtimes and fetch the pinned models from public sources; every input
        # is size- and SHA-256-verified (docs/runtime-build.md). No storage credentials.
        # release.yml restores the download cache at this path; entries are re-verified.
        run(sys.executable, REPO / 'scripts/assemble-release-runtime.py', '--architecture', architecture,
            '--cache', temp / 'saywing-runtime-cache', '--work', temp / 'saywing-runtime-work',
            '--output', temp / 'saywing-runtime/Saywing.app', '--public-release')
    elif mode == 'credentials':
        # Read all required secrets before creating any credential files.
        certificate = base64.b64decode(required('SAYWING_CERTIFICATE_P12'), validate=True)
        certificate_password = required('SAYWING_CERTIFICATE_PASSWORD')
        sparkle_key = required('SAYWING_SPARKLE_PRIVATE_KEY')
        notary_options, notary_key = notary_credentials(temp)
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
        notary_key_file = temp / 'saywing-notary-key.p8'
        try:
            with cert_file.open('xb') as stream:
                os.chmod(cert_file, 0o600)
                stream.write(certificate)
            # Residual risk: `security import` accepts the P12 password only via -P (or an
            # interactive prompt), so it is briefly visible to processes on this runner.
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
            if notary_key is not None:
                with notary_key_file.open('x') as stream:
                    os.chmod(notary_key_file, 0o600)
                    stream.write(notary_key)
            # The stored profile keeps its credentials inside the temporary keychain.
            run('xcrun', 'notarytool', 'store-credentials', NOTARY_PROFILE, '--keychain', keychain, *notary_options)
        finally:
            cert_file.unlink(missing_ok=True)
            notary_key_file.unlink(missing_ok=True)
            # Keep the mode-0600 Sparkle key until the always-run cleanup step.
            # Separate Sparkle executables cannot share an interactive keychain ACL in CI.
    elif mode == 'cleanup':
        # Remove secret files even if restoring the runner keychain later fails.
        for name in ('saywing-cert.p12', 'saywing-sparkle.key', 'saywing-notary-key.p8'):
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
