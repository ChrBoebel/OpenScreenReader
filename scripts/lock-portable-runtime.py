#!/usr/bin/env python3
"""Resolve an already version-pinned requirements file to exact macOS-14 wheel artifacts.

Development tool only. Run with a clean Python providing packaging (or pip's vendored copy).
Review the generated lock before building; this command never installs packages/models.
"""
import argparse,concurrent.futures,json,re,urllib.request
from pathlib import Path
try:
    from packaging.tags import cpython_tags,compatible_tags,mac_platforms
    from packaging.utils import parse_wheel_filename
except ImportError:
    from pip._vendor.packaging.tags import cpython_tags,compatible_tags,mac_platforms
    from pip._vendor.packaging.utils import parse_wheel_filename

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--requirements',type=Path,required=True);p.add_argument('--architecture',choices=['arm64','x86_64'],required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    platforms=list(mac_platforms(version=(14,0),arch=a.architecture))
    tags=list(cpython_tags((3,12),platforms=platforms))+list(compatible_tags((3,12),interpreter='cp312',platforms=platforms))
    ranks={tag:n for n,tag in reversed(list(enumerate(tags)))}
    requirements=[]
    for line in a.requirements.read_text().splitlines():
        line=line.strip()
        if not line or line.startswith('#'):continue
        if not re.fullmatch(r'[A-Za-z0-9_.-]+==[A-Za-z0-9_.+!-]+',line):raise ValueError('Expected exact version pins: '+line)
        requirements.append(line.split('=='))
    def pin(pair):
        name,version=pair
        with urllib.request.urlopen('https://pypi.org/pypi/'+name+'/'+version+'/json',timeout=60) as f:d=json.load(f)
        candidates=[]
        for item in d['urls']:
            if not item['filename'].endswith('.whl') or item.get('yanked'):continue
            parsed=parse_wheel_filename(item['filename']);matches=[ranks[t] for t in parsed[3] if t in ranks]
            if matches:candidates.append((min(matches),item))
        if not candidates:raise ValueError('No macOS 14 wheel for '+name+' '+version+' '+a.architecture)
        item=min(candidates,key=lambda x:x[0])[1]
        if not item['url'].startswith('https://files.pythonhosted.org/'):raise ValueError('Unexpected wheel host')
        return {'name':name,'version':version,'filename':item['filename'],'url':item['url'],'sha256':item['digests']['sha256'],'bytes':item['size'],'declared_license':d['info'].get('license_expression') or d['info'].get('license') or 'REVIEW REQUIRED'}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:wheels=list(pool.map(pin,requirements))
    python=json.loads((Path(__file__).resolve().parents[1]/'Runtime/Portable/python.json').read_text())[a.architecture]
    a.output.write_text(json.dumps({'architecture':a.architecture,'minimum_macos':'14.0','python':python,'wheels':wheels},indent=2)+'\n')
    print('Locked',len(wheels),'wheels for',a.architecture,flush=True)
if __name__=='__main__':main()
