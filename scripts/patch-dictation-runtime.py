#!/usr/bin/env python3
"""Apply the audited mlx-whisper 0.4.3 lazy timing import before sealing a bundle.

Word timestamps are disabled by Saywing. Importing their optional Numba/LLVM JIT
at startup otherwise kills hardened Python with CODESIGNING Invalid Page.
This patch retains the upstream implementation/license and does not add a JIT
entitlement or weaken the worker's network/write sandbox.
"""
import hashlib
import json
from pathlib import Path
import sys

SOURCE_SHA256 = '21f015e0d56c5e6194d07d86d772730940fff52d8f06d55838ae92ebccc24fbb'
IMPORT = b'from .timing import add_word_timestamps\n'
BRANCH = b'                if word_timestamps:\n'


def defer_timing_import(source):
    if source.count(IMPORT) != 1 or source.count(BRANCH) != 1:
        raise ValueError('Unexpected mlx-whisper word-timing import structure')
    return source.replace(IMPORT, b'', 1).replace(BRANCH, BRANCH + b'                    ' + IMPORT, 1)


def patch(root):
    candidates = list(root.glob('Python/lib/python*/site-packages/mlx_whisper/transcribe.py'))
    if len(candidates) != 1:
        raise ValueError('Expected one pinned mlx-whisper installation')
    path = candidates[0]
    source = path.read_bytes()
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        # Already-patched approved source is accepted only if undoing exactly
        # our change reconstructs the audited upstream bytes.
        marker = BRANCH + b'                    ' + IMPORT
        anchor = b'from .load_models import load_model\n'
        original = source.replace(marker, BRANCH, 1).replace(anchor, anchor + IMPORT, 1)
        if source.count(marker) != 1 or hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
            raise ValueError('Unknown mlx-whisper source; review this patch before upgrading the runtime')
        source = original
    metadata = path.parent.parent / 'mlx_whisper-0.4.3.dist-info/METADATA'
    text = metadata.read_text()
    if '\nLicense: MIT\n' not in text or '\nVersion: 0.4.3\n' not in text:
        raise ValueError('Expected the audited MIT-licensed mlx-whisper 0.4.3 package')
    result = defer_timing_import(source)
    path.write_bytes(result)
    record = {'package': 'mlx-whisper', 'version': '0.4.3', 'license': 'MIT',
              'file': str(path.relative_to(root)), 'upstream_sha256': SOURCE_SHA256,
              'patched_sha256': hashlib.sha256(result).hexdigest(),
              'change': 'Import optional word-timestamp timing code only inside its enabled branch; Saywing disables word timestamps.'}
    (root / 'WHISPER-HARDENED-RUNTIME-PATCH.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


if __name__ == '__main__':
    print(json.dumps(patch(Path(sys.argv[1]).resolve(strict=True)), indent=2))
