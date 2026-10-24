#!/usr/bin/env python3
"""Publish approved releases to a private S3-compatible download bucket.

Corresponding-source archives first (written offer, ADR 0007), immutable release files
second, full public download verification third, one conditional current.json pointer
last. Does not create resources or export credentials.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.request

from bundle_notices import corresponding_sources, fetch_source as fetch_upstream_source
from release import REPO, digest, https_url, public_download_prefix, require_release_approval, validate_version, release_target

# Override with SAYWING_PUBLIC_DOWNLOAD_PREFIX and SAYWING_RELEASE_REPOSITORY.
PUBLIC_PREFIX = public_download_prefix()
DEFAULT_REPOSITORY = 'ChrBoebel/saywing'
MAX_SINGLE_UPLOAD = 5 * 1024**3


def missing(error):
    return getattr(error, 'response', {}).get('Error', {}).get('Code') in ('404', 'NoSuchKey', 'NotFound')


def read_current(client, bucket, prefix="saywing"):
    try:
        result = client.get_object(Bucket=bucket, Key=f'{prefix}/current.json')
    except Exception as error:
        if missing(error):
            return None, None
        raise
    with result['Body'] as body:
        data = body.read(131073)
    if len(data) > 131072:
        raise ValueError('Release pointer is too large')
    return json.loads(data), result['ETag']


def stored(client, bucket, key, size, sha256):
    """True if the object already holds exactly these bytes, False if absent; raises otherwise."""
    try:
        existing = client.head_object(Bucket=bucket, Key=key)
    except Exception as error:
        if not missing(error):
            raise
        return False
    if existing['ContentLength'] != size or existing.get('Metadata', {}).get('sha256') != sha256:
        raise ValueError('Refusing to overwrite immutable release object: ' + key)
    return True


def immutable_upload(client, bucket, key, path, content_type):
    expected = digest(path)
    if stored(client, bucket, key, path.stat().st_size, expected):
        return
    # Single conditional PUT avoids a last-writer-wins race. Current DMGs are
    # below S3's 5 GiB limit. Fail explicitly if future packages exceed it.
    if path.stat().st_size > MAX_SINGLE_UPLOAD:
        raise ValueError('Archive exceeds the supported 5 GiB conditional upload limit')
    with path.open('rb') as body:
        client.put_object(Bucket=bucket, Key=key, Body=body, ContentLength=path.stat().st_size,
                          ContentType=content_type, Metadata={'sha256': expected}, IfNoneMatch='*')


def archive_corresponding_sources(client, bucket, prefix, release, records, fetch_source):
    """Keep the exact source archives the app points to, so the written offer can be fulfilled.

    Archives are stored once by SHA-256 under a prefix that no public route serves; a
    per-build manifest records which of them belong to the build. Already archived files
    are reused without downloading them again.
    """
    archived = []
    with tempfile.TemporaryDirectory() as work:
        for item in records:
            key = f"{prefix}/corresponding-source/sha256/{item['sha256']}/{item['file']}"
            if not stored(client, bucket, key, item['bytes'], item['sha256']):
                path = fetch_source(item, Path(work))
                if path.stat().st_size != item['bytes'] or digest(path) != item['sha256']:
                    raise ValueError('Corresponding source hash/size mismatch: ' + item['file'])
                immutable_upload(client, bucket, key, path, 'application/octet-stream')
                path.unlink()
            archived.append({**item, 'key': key})
        manifest = Path(work) / 'manifest.json'
        manifest.write_text(json.dumps({**release, 'sources': archived}, indent=2) + '\n')
        immutable_upload(client, bucket, f"{prefix}/corresponding-source/builds/{release['build']}.json",
                         manifest, 'application/json')


def publish(root, client, bucket, main_commit, verify_public, *, fetch_source):
    result = json.loads((root / 'release-result.json').read_text())
    if result.get('notarized') is not True or result.get('public_release_approved') is not True:
        raise ValueError('Only approved, notarized release outputs may be published')
    folder = root / 'publish'
    metadata = json.loads((folder / 'latest.json').read_text())
    architecture = metadata.get('architecture')
    target = release_target(architecture)
    prefix = target['storage_prefix']
    if result.get('architecture') != architecture:
        raise ValueError('Release result architecture does not match metadata')
    version, build = metadata['version'], metadata['build']
    validate_version(version, build)
    filename = f'Saywing-{version}-{build}.dmg'
    archive = folder / filename
    if (result['version'] != version or result['build'] != build
            or metadata['url'] != target['url_prefix'] + '/' + filename
            or metadata['bytes'] != archive.stat().st_size or metadata['sha256'] != digest(archive)):
        raise ValueError('Release metadata or archive does not match')
    if (folder / 'SHA256SUMS').read_text() != f"{metadata['sha256']}  {filename}\n":
        raise ValueError('Checksum manifest does not match')
    pointer = {'version': version, 'build': build, 'filename': filename,
               'sha256': metadata['sha256'], 'source_commit': result['source_commit'], 'architecture': architecture}
    previous, etag = read_current(client, bucket, prefix)
    if previous and previous.get('architecture', 'arm64') != architecture:
        raise ValueError('Published pointer architecture does not match namespace')
    if previous and (int(previous['build']) > int(build) or
                     (int(previous['build']) == int(build) and previous != pointer)):
        raise ValueError('Refusing downgrade or replacement of a published build')
    if main_commit() != result['source_commit']:
        raise ValueError('This release is no longer the current main commit')
    sources = result.get('corresponding_sources')
    if sources is None or sources != corresponding_sources(architecture):
        raise ValueError('Corresponding-source records of the app differ from the repository')
    # Archive the sources before anything becomes downloadable, so no published build lacks them.
    archive_corresponding_sources(client, bucket, prefix, {
        'version': version, 'build': build, 'architecture': architecture, 'source_commit': result['source_commit'],
    }, sources, fetch_source)
    files = [(filename, 'application/x-apple-diskimage'), ('appcast.xml', 'application/xml'),
             ('latest.json', 'application/json'), ('SHA256SUMS', 'text/plain')]
    for name, content_type in files:
        immutable_upload(client, bucket, f'{prefix}/releases/{build}/{name}', folder / name, content_type)
    verify_public(metadata)
    if main_commit() != result['source_commit']:
        raise ValueError('Main changed during upload; previous release remains current')
    if previous == pointer:
        print('Release already current:', build)
        return
    condition = {'IfMatch': etag} if etag else {'IfNoneMatch': '*'}
    client.put_object(Bucket=bucket, Key=f'{prefix}/current.json',
                      Body=(json.dumps(pointer) + '\n').encode(), ContentType='application/json',
                      CacheControl='no-store', **condition)
    print('Published verified release:', version, 'build', build)


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith('https://'):
            raise ValueError('Refusing non-HTTPS download redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def verify_public_download(metadata):
    https_url(metadata['url'])
    checksum = hashlib.sha256()
    size = 0
    opener = urllib.request.build_opener(HTTPSRedirect())
    with opener.open(metadata['url'], timeout=120) as response:
        if response.status != 200:
            raise ValueError('Public download is not available')
        for chunk in iter(lambda: response.read(8 * 1024 * 1024), b''):
            size += len(chunk)
            if size > metadata['bytes']:
                raise ValueError('Public download exceeds expected size')
            checksum.update(chunk)
    if size != metadata['bytes'] or checksum.hexdigest() != metadata['sha256']:
        raise ValueError('Public download size or SHA-256 does not match')


def current_main():
    repository = os.environ['GITHUB_REPOSITORY']
    if repository != (os.environ.get('SAYWING_RELEASE_REPOSITORY') or DEFAULT_REPOSITORY):
        raise ValueError('Unexpected release repository')
    request = urllib.request.Request(f'https://api.github.com/repos/{repository}/git/ref/heads/main',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)['object']['sha']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', required=True, type=Path)
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('Publication requires the main-branch GitHub workflow')
    metadata = json.loads((args.release / 'publish/latest.json').read_text())
    architecture = metadata.get('architecture')
    require_release_approval(release_target(architecture)['approval'], architecture)
    import boto3
    from botocore.config import Config
    client = boto3.client('s3', endpoint_url=https_url(os.environ['SAYWING_S3_ENDPOINT']),
        region_name=os.environ.get('SAYWING_S3_REGION', 'auto'),
        aws_access_key_id=os.environ['SAYWING_S3_ACCESS_KEY_ID'],
        aws_secret_access_key=os.environ['SAYWING_S3_SECRET_ACCESS_KEY'],
        config=Config(signature_version='s3v4', s3={'addressing_style': 'virtual'}, connect_timeout=30, read_timeout=900,
                      request_checksum_calculation='when_required', response_checksum_validation='when_required'))
    publish(args.release.resolve(strict=True), client, os.environ['SAYWING_S3_BUCKET'],
            current_main, verify_public_download, fetch_source=fetch_upstream_source)


if __name__ == '__main__':
    main()
