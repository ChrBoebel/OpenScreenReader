#!/usr/bin/env python3
"""Mirror a published Saywing release to GitHub Releases.

Runs after both architectures are public on the download host. Checks every disk image
against the published latest.json of its architecture, renames the images per architecture,
writes one SHA256SUMS and release notes from CHANGELOG.md, then creates the tag on the built
commit and the release with `gh`. An existing tag or release is verified, never moved or
overwritten; an interrupted upload is resumed without replacing any asset.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from release import REPO, digest, release_target, require_release_approval, validate_version

ARCHITECTURES = ('arm64', 'x86_64')
LABELS = {'arm64': 'Apple Silicon', 'x86_64': 'Intel (x86_64)'}
# GitHub accepts release assets below 2 GiB each.
GITHUB_ASSET_LIMIT = 2 * 1024**3
DEFAULT_REPOSITORY = 'ChrBoebel/saywing'
FORK_NOTE = 'Unsigned builds from forks are not official.'


def tag_name(version, build):
    validate_version(version, build)
    return f'v{version}-build{build}'


def changelog_section(text, version):
    """Entries of the section for this version, otherwise of [Unreleased]."""
    headings = list(re.finditer(r'^## (.+?)\s*$', text, re.MULTILINE))
    def body(index):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        return text[headings[index].end():end].strip()
    for wanted in (re.compile(r'\[?' + re.escape(version) + r'\]?(\s.*)?'), re.compile(r'\[Unreleased\]')):
        for index, heading in enumerate(headings):
            if wanted.fullmatch(heading.group(1)):
                entries = body(index)
                if not entries:
                    raise ValueError(f'CHANGELOG.md section "{heading.group(1)}" is empty')
                return entries
    raise ValueError(f'CHANGELOG.md has neither a section for {version} nor [Unreleased]')


def absolute_links(markdown, repository, commit):
    """Repository-relative Markdown links do not resolve on a release page; pin them to the commit."""
    def rewrite(match):
        target = match.group(1)
        if target.startswith('#') or '://' in target or target.startswith('mailto:'):
            return match.group(0)
        path = target[2:] if target.startswith('./') else target
        return f'](https://github.com/{repository}/blob/{commit}/{path})'
    return re.sub(r'\]\(([^)\s]+)\)', rewrite, markdown)


def release_notes(*, version, build, prerelease, repository, commit, downloads, checksums, changelog,
                  remaining_tests):
    blob = f'https://github.com/{repository}/blob/{commit}'
    tree = f'https://github.com/{repository}/tree/{commit}'
    if prerelease:
        lines = [f'Beta pre-release of Saywing {version} (build {build}) for macOS 14 or later. '
                 'Device testing is not complete; these tests are still open:', '']
        lines += [f'- {item}' for item in remaining_tests] + ['']
    else:
        lines = [f'Saywing {version} (build {build}) for macOS 14 or later.', '']
    lines += [
        '## Download', '',
        "Download Saywing from the official download page on the maintainer's website:", '',
        *[f'- {LABELS[architecture]}: {downloads[architecture]}' for architecture in ARCHITECTURES], '',
        'The disk images attached here are byte-identical copies of those downloads. Once installed, '
        "Saywing updates itself via Sparkle from the maintainer's site, not from GitHub; update checks "
        'can be turned off.', '',
        '## SHA-256', '', '```', checksums.rstrip('\n'), '```', '',
        'Each checksum equals the published `latest.json` of its architecture, attached as '
        '`latest-arm64.json` and `latest-x86_64.json`. Check a download with `shasum -a 256 <file>`.', '',
        '## Changes', '', absolute_links(changelog, repository, commit), '',
        '## Source and licenses', '',
        f'Built from commit {commit}. The corresponding source of the bundled GNU runtime libraries and the '
        "other components listed in each build's `sources.json` is served publicly next to the download; see "
        f'the [corresponding-source notice]({blob}/docs/licenses/CorrespondingSource-README.md), the '
        f'[license texts]({tree}/docs/licenses) and [ADR 0007]({blob}/docs/decisions/0007-gcc-runtime-libraries.md).',
        '', FORK_NOTE,
    ]
    return '\n'.join(lines) + '\n'


def checked_release(folder, architecture, commit):
    """The release outputs of one architecture, after the same checks the publish job applies."""
    result = json.loads((folder / 'release-result.json').read_text())
    if result.get('notarized') is not True or result.get('public_release_approved') is not True:
        raise ValueError('Only approved, notarized release outputs may be mirrored: ' + architecture)
    raw = (folder / 'publish/latest.json').read_bytes()
    metadata = json.loads(raw)
    if metadata.get('architecture') != architecture or result.get('architecture') != architecture:
        raise ValueError('Release architecture does not match: ' + architecture)
    version, build = metadata['version'], metadata['build']
    validate_version(version, build)
    if result.get('version') != version or result.get('build') != build:
        raise ValueError('Release result and latest.json differ: ' + architecture)
    if result.get('source_commit') != commit:
        raise ValueError(f'{architecture} release was built from {result.get("source_commit")}, not {commit}')
    filename = f'Saywing-{version}-{build}.dmg'
    archive = folder / 'publish' / filename
    if metadata.get('url') != release_target(architecture)['url_prefix'] + '/' + filename:
        raise ValueError('Download URL in latest.json is not the official one: ' + architecture)
    size = archive.stat().st_size
    if size != metadata.get('bytes'):
        raise ValueError('Disk image size differs from latest.json: ' + architecture)
    if size >= GITHUB_ASSET_LIMIT:
        raise ValueError(f'{filename} ({architecture}, {size} bytes) exceeds the GitHub release asset limit of 2 GiB')
    sha256 = digest(archive)
    if sha256 != metadata.get('sha256'):
        raise ValueError('Disk image SHA-256 differs from the published latest.json: ' + architecture)
    if (folder / 'publish/SHA256SUMS').read_text() != f'{sha256}  {filename}\n':
        raise ValueError('Checksum manifest does not match: ' + architecture)
    return {'version': version, 'build': build, 'archive': archive, 'sha256': sha256, 'metadata': metadata,
            'raw_metadata': raw}


def place(source, target):
    """Hard-link (same bytes, no copy of a gigabyte image) or copy into the asset folder."""
    if target.exists():
        target.unlink()
    try:
        os.link(source, target)
    except OSError:
        shutil.copyfile(source, target)


def prepare(release_dirs, output, *, commit, repository, changelog, approvals):
    if sorted(release_dirs) != sorted(ARCHITECTURES) or sorted(approvals) != sorted(ARCHITECTURES):
        raise ValueError('A GitHub release needs both published architectures: ' + ', '.join(ARCHITECTURES))
    releases = {architecture: checked_release(Path(release_dirs[architecture]), architecture, commit)
                for architecture in ARCHITECTURES}
    if len({(item['version'], item['build']) for item in releases.values()}) != 1:
        raise ValueError('Architectures were released with different versions or builds')
    version, build = releases['arm64']['version'], releases['arm64']['build']
    # Pre-release while any approval record relies on the owner's beta exception for clean_mac.
    prerelease = (any(approvals[architecture].get('clean_mac') is not True for architecture in ARCHITECTURES)
                  or any(item['metadata'].get('channel') != 'stable' for item in releases.values()))
    remaining = [f'{LABELS[architecture]}: {test}' for architecture in ARCHITECTURES
                 if approvals[architecture].get('clean_mac') is not True
                 for test in approvals[architecture].get('owner_beta_exception', {}).get('remaining_tests', [])]
    entries = changelog_section(changelog, version)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    images, checksums = [], ''
    for architecture in ARCHITECTURES:
        target = output / f'Saywing-{version}-{build}-{architecture}.dmg'
        place(releases[architecture]['archive'], target)
        images.append(target)
        checksums += f"{releases[architecture]['sha256']}  {target.name}\n"
    (output / 'SHA256SUMS').write_text(checksums)
    for architecture in ARCHITECTURES:
        (output / f'latest-{architecture}.json').write_bytes(releases[architecture]['raw_metadata'])
    notes = output / 'release-notes.md'
    notes.write_text(release_notes(
        version=version, build=build, prerelease=prerelease, repository=repository, commit=commit,
        downloads={architecture: releases[architecture]['metadata']['url'] for architecture in ARCHITECTURES},
        checksums=checksums, changelog=entries, remaining_tests=remaining))
    files = images + [output / 'SHA256SUMS'] + [output / f'latest-{architecture}.json' for architecture in ARCHITECTURES]
    assets = []
    for path in files:
        size = path.stat().st_size
        if size >= GITHUB_ASSET_LIMIT:
            raise ValueError(f'{path.name} exceeds the GitHub release asset limit of 2 GiB')
        assets.append({'name': path.name, 'path': str(path), 'size': size, 'sha256': digest(path)})
    return {'version': version, 'build': build, 'tag': tag_name(version, build),
            'title': f'Saywing {version} (beta)' if prerelease else f'Saywing {version}',
            'prerelease': prerelease, 'notes': str(notes), 'assets': assets}


def find_release(gh, repository, tag):
    """The release for this tag, drafts included (the tag lookup endpoint omits drafts)."""
    pages = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repository}/releases?per_page=100'))
    matches = [item for page in pages for item in page if item.get('tag_name') == tag]
    if len(matches) > 1:
        raise ValueError(f'More than one release uses tag {tag}; resolve this manually')
    return matches[0] if matches else None


def tag_commit(gh, repository, tag):
    refs = json.loads(gh('api', f'repos/{repository}/git/matching-refs/tags/{tag}'))
    target = next((ref['object'] for ref in refs if ref.get('ref') == 'refs/tags/' + tag), None)
    for _ in range(3):  # Annotated tags point to a tag object first.
        if target is None or target.get('type') == 'commit':
            return target and target['sha']
        if target.get('type') != 'tag':
            break
        target = json.loads(gh('api', f"repos/{repository}/git/tags/{target['sha']}"))['object']
    raise ValueError(f'Tag {tag} does not point to a commit')


def verify_assets(release, assets, tag, download, allow_missing):
    """Missing expected assets; raises on any differing, broken or unexpected asset."""
    expected = {asset['name']: asset for asset in assets}
    present = {}
    for item in release.get('assets', []):
        if item['name'] in present:
            raise ValueError('Release has duplicate asset: ' + item['name'])
        present[item['name']] = item
    extra = sorted(set(present) - set(expected))
    if extra:
        raise ValueError(f'Release {tag} has unexpected assets: ' + ', '.join(extra))
    missing = []
    for name, asset in expected.items():
        item = present.get(name)
        if item is None:
            missing.append(asset)
            continue
        if item.get('state') != 'uploaded' or item.get('size') != asset['size']:
            raise ValueError(f'Release asset {name} is incomplete or differs; it is never overwritten')
        reported = item.get('digest')
        actual = (reported[len('sha256:'):] if isinstance(reported, str) and reported.startswith('sha256:')
                  else download(tag, name))
        if actual != asset['sha256']:
            raise ValueError(f'Release asset {name} has a different SHA-256; it is never overwritten')
    if missing and not allow_missing:
        raise ValueError(f'Release {tag} lacks assets: ' + ', '.join(asset['name'] for asset in missing))
    return missing


def mirror(gh, repository, plan, commit, *, download):
    tag, prerelease = plan['tag'], plan['prerelease']
    release = find_release(gh, repository, tag)
    tagged = tag_commit(gh, repository, tag)
    if tagged is not None and tagged != commit:
        raise ValueError(f'Tag {tag} already points to {tagged}, not {commit}; tags are never moved')
    wrote = False
    if release is None:
        args = ['release', 'create', tag, *[asset['path'] for asset in plan['assets']],
                '--title', plan['title'], '--notes-file', plan['notes'], '--target', commit]
        if tagged:
            args.append('--verify-tag')
        if prerelease:
            args += ['--prerelease', '--latest=false']
        gh(*args)
        wrote = True
    else:
        if release.get('draft'):
            if release.get('target_commitish') != commit:
                raise ValueError(f'Draft release {tag} targets {release.get("target_commitish")}, not {commit}')
        elif tagged is None:
            raise ValueError(f'Release {tag} exists without its tag; resolve this manually')
        if prerelease and not release.get('prerelease'):
            raise ValueError(f'Existing release {tag} is not marked as a pre-release')
        missing = verify_assets(release, plan['assets'], tag, download, allow_missing=True)
        if missing:
            gh('release', 'upload', tag, *[asset['path'] for asset in missing])
            wrote = True
        if release.get('draft'):
            args = ['api', '-X', 'PATCH', f"repos/{repository}/releases/{release['id']}", '-F', 'draft=false']
            if prerelease:
                args += ['-f', 'make_latest=false']
            gh(*args)
            wrote = True
    if wrote:
        release = find_release(gh, repository, tag)
        if release is None or release.get('draft') or tag_commit(gh, repository, tag) != commit:
            raise ValueError(f'Release {tag} was not published on {commit}')
        if prerelease and not release.get('prerelease'):
            raise ValueError(f'Release {tag} is not marked as a pre-release')
        verify_assets(release, plan['assets'], tag, download, allow_missing=False)
    if prerelease:
        listed = json.loads(gh('release', 'list', '--limit', '1000', '--json', 'tagName,isLatest'))
        if any(item.get('tagName') == tag and item.get('isLatest') for item in listed):
            raise ValueError(f'Pre-release {tag} is marked latest')
    print(('Published' if wrote else 'Verified existing'), 'GitHub release', tag, 'on', commit)


def run_gh(*args):
    return subprocess.run(['gh', *args], check=True, stdout=subprocess.PIPE, text=True).stdout


def download_digest(tag, name):
    with tempfile.TemporaryDirectory() as work:
        run_gh('release', 'download', tag, '--pattern', name, '--dir', work)
        return digest(Path(work) / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arm64', required=True, type=Path, help='release artifact of the arm64 publish job')
    parser.add_argument('--x86_64', required=True, type=Path, help='release artifact of the x86_64 publish job')
    parser.add_argument('--output', required=True, type=Path, help='empty folder for the renamed assets')
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('GitHub releases are created by the main-branch release workflow only')
    repository = os.environ['GITHUB_REPOSITORY']
    if repository != (os.environ.get('SAYWING_RELEASE_REPOSITORY') or DEFAULT_REPOSITORY):
        raise ValueError('Unexpected release repository')
    commit = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('GITHUB_SHA is not a full commit SHA')
    approvals = {}
    for architecture in ARCHITECTURES:
        path = release_target(architecture)['approval']
        require_release_approval(path, architecture)
        approvals[architecture] = json.loads(path.read_text())
    plan = prepare({'arm64': args.arm64, 'x86_64': args.x86_64}, args.output, commit=commit,
                   repository=repository, changelog=(REPO / 'CHANGELOG.md').read_text(), approvals=approvals)
    print('Prepared', plan['tag'], '(pre-release)' if plan['prerelease'] else '(release)')
    print(Path(plan['notes']).read_text())
    mirror(run_gh, repository, plan, commit, download=download_digest)


if __name__ == '__main__':
    main()
