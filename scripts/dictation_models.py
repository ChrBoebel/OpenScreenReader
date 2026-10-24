"""Copy exactly the files a pinned dictation model manifest lists. No downloads."""
import hashlib
from pathlib import Path, PurePosixPath
import shutil


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verified(path, item):
    if path.stat().st_size != item['size'] or sha256(path) != item['verified_sha256']:
        raise ValueError('Pinned model verification failed: ' + item['rfilename'])
    return path


def model_plan(manifest, model_source, licenses):
    """Return [(verified source path, relative name)] for every installable manifest entry.

    Entries without a pinned digest (such as .gitattributes) are never bundled. Entries with a
    `source` field are license texts that the model repository lacks; they come from `licenses`
    (the bundled Dictation/Licenses folder), never from the model directory."""
    plan = []
    root = model_source.resolve(strict=True)
    for item in manifest['files']:
        if not item.get('verified_sha256'):
            continue
        name = item['rfilename']
        parts = PurePosixPath(name).parts
        if not parts or PurePosixPath(name).is_absolute() or '..' in parts:
            raise ValueError('Model path escapes source: ' + name)
        if 'source' in item:
            if len(parts) != 1:
                raise ValueError('Bundled license text escapes Licenses: ' + name)
            path = (licenses / name).resolve(strict=True)
            if path.parent != licenses.resolve(strict=True):
                raise ValueError('Bundled license text escapes Licenses: ' + name)
        else:
            path = (root / name).resolve(strict=True)
            if not path.is_relative_to(root):
                raise ValueError('Model path escapes source: ' + name)
        plan.append((verified(path, item), name))
    return plan


def copy_model(manifest, model_source, licenses, target):
    """Copy only the manifest's files into the new directory `target` and verify the copies."""
    plan = model_plan(manifest, model_source, licenses)
    target.mkdir()
    items = {item['rfilename']: item for item in manifest['files']}
    for path, name in plan:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        verified(destination, items[name])
    return [name for _, name in plan]
