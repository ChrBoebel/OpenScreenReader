#!/usr/bin/env python3
"""Checks the string catalogs: every key has a German translation, and app
sources contain no German text that bypasses the catalog (one language per surface)."""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
app = root / "OpenScreenReaderApp"
problems = []
for name in ["Localizable.xcstrings", "InfoPlist.xcstrings"]:
    catalog = json.loads((app / name).read_text())
    for key, entry in catalog["strings"].items():
        if not key:
            continue
        german = entry.get("localizations", {}).get("de", {})
        unit = german.get("stringUnit", {})
        plural = german.get("variations", {}).get("plural", {})
        if unit.get("state") != "translated" and len(plural) < 2:
            problems.append(f"{name}: missing German for {key!r}")
for source in app.rglob("*.swift"):
    for number, line in enumerate(source.read_text().splitlines(), 1):
        if re.search(r"[äöüÄÖÜß]", line):
            problems.append(f"{source.relative_to(root)}:{number}: German text outside the catalog")
print("\n".join(problems) or "Localization check passed.")
sys.exit(1 if problems else 0)
