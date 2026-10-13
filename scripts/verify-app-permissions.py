#!/usr/bin/env python3
"""Check the actual signed app's prerequisites for an explicit microphone request."""
import plistlib
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve(strict=True)
with (app / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
if not info.get('NSMicrophoneUsageDescription', '').strip():
    raise SystemExit('FAIL: Missing microphone usage description')
result = subprocess.run(
    ['/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', str(app)],
    check=True, capture_output=True,
)
if not result.stdout.strip():
    raise SystemExit('FAIL: Signature has no entitlements; microphone request is blocked with Hardened Runtime')
entitlements = plistlib.loads(result.stdout)
if entitlements.get('com.apple.security.device.audio-input') is not True:
    raise SystemExit('FAIL: Signature is missing the Audio Input entitlement')
print('PASS: Signed app declares Audio Input and a microphone usage description')
print('User consent and live recording are separate checks; no permission was requested.')
