#!/usr/bin/env python3
"""Build isolated Python runtimes from reviewed, hash-pinned artifacts. Build-time network only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import zipfile

MACHO = {bytes.fromhex(x) for x in ('cffaedfe','cefaedfe','feedfacf','feedface','cafebabe','bebafeca','cafebabf','bfbafeca')}

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(8*1024*1024),b''): h.update(block)
    return h.hexdigest()

def verify_file(path, pin):
    if path.stat().st_size != pin['bytes'] or digest(path) != pin['sha256']:
        raise ValueError('Artifact size/hash mismatch: '+path.name)

def download(pin, cache):
    if not pin['url'].startswith('https://'): raise ValueError('HTTPS required')
    cache.mkdir(parents=True,exist_ok=True)
    path=cache/pin['sha256']
    if not path.exists():
        temp=path.with_suffix('.partial')
        try:
            print('Fetching',pin.get('filename',pin.get('version','Python')),flush=True)
            subprocess.run(['/usr/bin/curl','--fail','--location','--silent','--show-error',
                            '--proto','=https','--proto-redir','=https','--retry','3','--retry-all-errors','--connect-timeout','30','--max-time','600',
                            '--output',str(temp),pin['url']],check=True)
            verify_file(temp,pin);temp.rename(path)
        finally: temp.unlink(missing_ok=True)
    verify_file(path,pin)
    return path

def safe_path(root, relative):
    if Path(relative).is_absolute() or '..' in Path(relative).parts:
        raise ValueError('Archive path escapes output')
    result=root/relative
    if not result.resolve().is_relative_to(root.resolve()): raise ValueError('External archive path')
    return result

def install_wheel(archive, site):
    site.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as wheel:
        for entry in wheel.infolist():
            safe_path(site,entry.filename)
            if (entry.external_attr >> 16) & 0o170000 == 0o120000: raise ValueError('Wheel symlink')
            parts=Path(entry.filename).parts
            if not parts: continue
            if parts[0].endswith('.data'):
                if len(parts)<3: continue
                relative=Path(*parts[2:]) if parts[1] in ('purelib','platlib') else Path('_wheel_data',*parts)
            else: relative=Path(*parts)
            target=safe_path(site,relative)
            if entry.is_dir(): target.mkdir(parents=True,exist_ok=True);continue
            target.parent.mkdir(parents=True,exist_ok=True)
            if target.exists(): raise ValueError('Overlapping wheel file: '+str(relative))
            with wheel.open(entry) as source,target.open('wb') as out: shutil.copyfileobj(source,out)
            target.chmod(0o755 if (entry.external_attr >> 16) & 0o111 else 0o644)

def version(value): return tuple((list(map(int,value.split('.')))+[0,0])[:3])

def validate_load_commands(text, minimum):
    # LC_ID_DYLIB may retain a build-machine identifier; only load commands are dependencies.
    for block in re.split(r'(?=\s*cmd LC_)',text):
        if re.search(r'cmd LC_BUILD_VERSION\b',block):
            platform=re.search(r'\bplatform (\S+)',block)
            if platform and platform[1] not in ('1','macos','MACOS'): raise ValueError('Non-macOS native code')
            match=re.search(r'\bminos ([0-9.]+)',block)
        elif re.search(r'cmd LC_VERSION_MIN_MACOSX\b',block): match=re.search(r'\bversion ([0-9.]+)',block)
        else: match=None
        if match and version(match[1])>version(minimum): raise ValueError('Native minimum macOS '+match[1]+' exceeds '+minimum)
        if match:
            sdk = re.search(r'\bsdk (\S+)', block)
            if not sdk or not re.fullmatch(r'[0-9.]+', sdk[1]) or version(sdk[1]) < version('10.9'):
                raise ValueError('Native SDK is missing or too old for hardened library validation')
        if re.search(r'cmd LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD)_DYLIB\b',block):
            match=re.search(r'\bname (.+?) \(offset',block)
            if match and match[1].startswith('/') and not match[1].startswith(('/usr/lib/','/System/Library/')):
                raise ValueError('External native dependency: '+match[1])

def audit(root, arch, minimum='14.0'):
    records=[]
    boundary = root.parent if root.is_file() else root
    for path in ([root] if root.is_file() else sorted(root.rglob('*'))):
        if path.is_symlink():
            if not path.resolve(strict=True).is_relative_to(boundary.resolve()): raise ValueError('External bundle symlink: '+str(path))
            continue
        if not path.is_file(): continue
        with path.open('rb') as f:
            if f.read(4) not in MACHO: continue
        arches=subprocess.check_output(['/usr/bin/lipo','-archs',path],text=True).split()
        if arch not in arches: raise ValueError('Missing '+arch+' slice: '+str(path))
        text=subprocess.check_output(['/usr/bin/otool','-l',path],text=True)
        try: validate_load_commands(text,minimum)
        except ValueError as e: raise ValueError(str(path)+': '+str(e)) from e
        records.append({'path':str(path.relative_to(boundary)),'architectures':arches})
    if not records: raise ValueError('No native runtime files')
    return records

def extract_python(archive, staging):
    # Called only after download() verified the archive's pinned size and SHA-256.
    with tarfile.open(archive) as tar:
        for entry in tar.getmembers():
            dest=safe_path(staging,entry.name)
            if entry.isdev() or entry.isfifo() or entry.islnk(): raise ValueError('Unsupported tar member')
            if entry.issym() and not (dest.parent/entry.linkname).resolve().is_relative_to(staging.resolve()): raise ValueError('External tar symlink')
        tar.extractall(staging)
    return staging/'python'

def build(lock_path, output, cache):
    lock=json.loads(lock_path.read_text())
    if output.exists(): raise ValueError('Refusing existing output')
    archive=download(lock['python'],cache)
    staging=output.with_name(output.name+'.staging')
    if staging.exists(): raise ValueError('Refusing existing staging directory')
    staging.mkdir(parents=True)
    python=extract_python(archive,staging)
    site=python/'lib/python3.12/site-packages'
    if site.exists(): shutil.rmtree(site)
    site.mkdir(parents=True)
    # Wheel entrypoints and bundled pip are development tools, not runtime dependencies.
    for path in (python/'bin').iterdir():
        if path.name not in ('python3','python3.12','python'): path.unlink()
    for pin in lock['wheels']: install_wheel(download(pin,cache),site)
    native=audit(python,lock['architecture'],lock['minimum_macos'])
    (python/'runtime-provenance.json').write_text(json.dumps({'lock':lock,'native_audit':native},indent=2)+'\n')
    python.rename(output);staging.rmdir()
    print('Built verified runtime:',output,flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lock',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--cache',type=Path,required=True)
    a=p.parse_args();build(a.lock,a.output,a.cache)
