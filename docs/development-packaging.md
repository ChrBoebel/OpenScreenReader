# Private offline packaging spike

This is a local development artifact, not a release or a redistribution approval.

Build the Release target, then run:

```sh
ruby scripts/package-development-app.rb /absolute/path/to/Release/OpenScreenReader.app --development-only --dmg
```

The script refuses other modes. It creates a new ignored `.build/packaging-*` staging directory, optionally a sibling DMG, and never overwrites the installed app. Existing model/worker/dependency files must match their installation receipt and the pinned model manifest. Nothing is downloaded.

## Bundle contents

- Release app and project Apache-2.0 license.
- Supertonic 3 M1 resources from revision `3cadd1ee6394adea1bd021217a0e650ede09a323`; the ten pinned model assets total 398,969,192 bytes. See `research/supertonic-comparison-manifest.json` for sources, per-file size/hash and model/voice license (BigScience Open RAIL-M).
- Pinned MIT inference helper and upstream notices.
- The existing CPython 3.12.14 interpreter/standard library and pinned ONNX 1.23.2/NumPy 2.2.6 package environment. Unrelated base-interpreter packages, bytecode caches in the standard library, and build-time pkgconfig links are excluded.
- Post-signing SHA-256 inventory without the development receipt's external interpreter path.

The package uses ad-hoc signatures. No certificate purchase, Developer ID signing, notarization, publication or runtime update service is performed. A DMG offers an Applications shortcut for a conventional drag-to-install flow; it does not bypass Gatekeeper or macOS privacy permissions.

## Evidence and limits

On the development Mac, isolated imports resolved inside the bundle. A relocated bundle's real local speech, three-second pause/resume and playback/loading cancellation passed under the worker's deny-network/deny-write sandbox. Deep strict signature verification passed. See `everyday-reading-verification.md` for measurements and the GUI blocker.

Before distribution, obtain a reproducible, independently pinned interpreter source/build provenance record, audit every native and transitive license/notice (including any notices not present in wheel metadata), verify load-command resolution and signing on a fresh Mac, audit offline/data flows, and complete the selected distribution signing/notarization workflow. Existing licenses are retained; their presence alone is not a complete legal/redistribution audit. Do not publish this development DMG as an end-user release.
