# Public beta readiness — 2026-10-15

Latest checkpoint: [build 9 with completed Rust evidence](release-build9-checks-2026-10-15.md). Earlier findings below are historical where superseded there.

Status: not published. The owner requested publication after successfully using
private Apple-Silicon build 7. This request authorizes preparation; it does not
supply missing verification evidence. Public release flags remain disabled.

## Owner-reported device test

The owner confirmed **installation, reading, and dictation** on the second Mac.
The chip was previously described as probably a Mac mini M4; exact chip and
macOS version remain unconfirmed. The supplied test was the private ARM build 7.
This is a successful basic device test, not evidence of a fresh user account,
all permission-denial paths, macOS 14 execution, or offline operation.
The owner subsequently confirmed that both reading and dictation work after
restarting Saywing with networking disabled, following the requested procedure.
This establishes owner-reported offline functionality for both bundled defaults.
It does not establish all permission-denial paths or a full persistence/data-flow
audit, and does not establish execution under macOS 14.

## Initial distribution findings (superseded where noted below)

1. **Supertonic downstream terms.** The pinned model license requires supplying
   the license and passing its paragraph 5 restrictions to recipients through
   the agreement/license governing use or distribution (4a, 4b, 5). Sharing
   with friends is still distribution under its definition 1g. The original
   license already accompanies the model; Settings currently displays only its
   name. The download-page/application presentation of these terms and their
   incorporation still needs to be completed and reviewed. This is a finding
   from the license text, not a legal opinion that any particular UI is sufficient.
   A checkbox specifically is not prescribed by the upstream text.
2. **Runtime notice chain.** The mechanical inventory identifies 9 speech
   packages per architecture, 52 ARM dictation packages, and 5 Intel dictation
   packages. Twelve extra setuptools-vendored metadata records accompany ARM.
   Flatbuffers 25.12.19 and tokenizers 0.23.3 lack dist-info notice files; inspect
   their exact source/wheel licenses and notices before claiming completeness.
   ONNX Runtime notices are in its package directory, and mlx-whisper has the
   retained LICENSE-mlx-examples notice. Their missing dist-info notice files
   alone are not missing-license findings. Setuptools vendors autocommand 2.2.2
   with LGPLv3 metadata; SoundFile carries a native libsndfile binary. Check the
   applicable source/notices/replacement obligations rather than treating the
   top-level MIT/BSD package labels as the entire native dependency license.
3. **Stale private-package text.** Build 7 contains DEVELOPMENT-PREVIEW.txt with
   "Not notarized or approved for redistribution." Apple has since accepted
   both packages, so the first assertion is stale. The redistribution gate
   remains open. Some inherited dictation notices describe Python 3.12.14,
   whereas the new portable runtime is pinned separately. Correct final notices
   before signing a new candidate; do not edit an already signed app in place.

Exact model source:
https://huggingface.co/Supertone/supertonic-3/blob/3cadd1ee6394adea1bd021217a0e650ede09a323/LICENSE

The original 15,007-byte model license is now retained as
`licenses/Supertonic-3-Open-RAIL-M.txt`, copied byte-for-byte from the verified
candidate; SHA-256 `0d944a9110fed9a9602d60e0423a272903e7bd21ab060490774efc77c2275e9f`.
This repository copy does not by itself satisfy the downstream agreement step.
Do not apply the model's restrictions to the project's Apache-2.0 source license
or imply that they govern unrelated components.

## Current checkpoint after privacy, license and update work

See `privacy-and-update-checks-2026-10-15.md` for executable evidence and limits.
The bundled ARM privacy gate and actual signed Sparkle installation/relaunch gate
now pass within that documented scope. The owner also confirmed restart into
0.1.4. Production HTTPS and final-package in-app UI remain separate checks.

The new resource stage indexes 243 original notices and includes 11 pinned source
archives/build-control inputs. Missing Flatbuffers/tokenizers texts and the
matching ARM Python/native notices have been supplemented. Vendored autocommand
matches its original source. Settings/setup and both website languages expose
the Supertonic model terms. App Release build, 190 app tests, 24 release tests,
website build/lint/typecheck and local license-link/hash checks pass, with the
explicit permission/network skips and speech-load limitation in the detailed
report. None of these changes has been distributed as a new signed artifact.

## Remaining release work

- Complete compiled dependency notice coverage and the native rebuild/replacement
  procedure; review the final model-terms presentation. `license_review` remains
  false. Correct the inherited historical Python notices for the final candidate.
- Obtain the second Mac's actual OS version and evidence for first-use permissions
  on a fresh account. `clean_mac` remains false. Actual macOS 14 execution is not
  established by a binary minimum-version inspection or a newer-Mac test.
- Create a newly signed/notarized candidate with build greater than 7, then verify
  its license UI and actual production HTTPS update path using protected staging.
- Review the prepared changes through the feature-branch PR flow. Current changes
  remain uncommitted; no direct main push, deployment or public flag activation.
- Scope the first release to Apple Silicon. Native Intel/macOS 14 execution and
  the measured Intel 2x playback gap remain separate unresolved work.

No public pointer, feed, package or release flags were changed for this review.
The accepted build 7 and protected test download remain intact.
