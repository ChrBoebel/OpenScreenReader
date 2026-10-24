# Security policy

Saywing processes screen content, microphone audio and clipboard data, and it ships local model runtimes and a self-updater. We take reports about any of these seriously.

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, discussions or pull requests.**

Report them privately through GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the issue, the affected Saywing version (shown in Settings), your macOS version and Mac model, and the steps to reproduce it. Include a proof of concept if you have one.

Do not include private screen content, recordings, transcripts or credentials in your report. Use synthetic text and audio.

We aim to acknowledge reports within 7 days and to agree on a disclosure timeline with you. Please give us a reasonable amount of time to release a fix before you disclose publicly. We will credit you in the advisory unless you prefer otherwise.

## Supported versions

Only the **latest release** receives security fixes. Saywing is in beta, and older builds are not patched. Update through **Check for Updates…** or download the current release.

## Scope

We are especially interested in:

- **Worker sandbox:** escapes from the macOS sandbox profiles of the speech and dictation workers (`OpenScreenReaderApp/LocalSpeechService.swift`, `Runtime/Dictation/worker.sb`). This includes network access or file writes from a worker, and injection through the worker protocol.
- **Model downloads:** bypasses of the pinned-revision and SHA-256 verification for optional dictation models, path traversal or symlink escapes during installation, or downloads that start without explicit user confirmation.
- **Sparkle updates:** feed or signature verification weaknesses, downgrade attacks, or installation of unsigned or foreign updates.
- **Clipboard and paste:** dictated text pasted into the wrong application or field, including secure input fields; clipboard contents leaking or failing to be restored; Saywing overwriting a newer copy.
- **Permissions:** misuse of Screen Recording, Input Monitoring, Accessibility, Microphone or system-audio capture beyond the documented purpose. Examples are capturing outside the selected region, observing keys other than Escape, or recording without an explicit start.
- **Data persistence:** screenshots, recognized text, audio or transcripts written to disk, logs or caches contrary to [docs/privacy.md](docs/privacy.md).

Out of scope:

- Issues that require an already compromised user account or administrator access.
- Problems in third-party models or libraries that Saywing does not expose. Please report those upstream, although we appreciate a heads-up.
- Model output quality, such as misrecognized words or mispronunciations, unless it causes one of the issues above.
