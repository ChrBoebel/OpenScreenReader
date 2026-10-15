# Apple Silicon beta publication — 2026-10-15

The owner explicitly authorized committing and pushing both prepared branches,
merging their PRs after the real website HTTPS update test passes, and publishing
an Apple Silicon beta. Intel remains private. This supersedes the previous
no-publication instruction only within that scope.

## Deliberate scope

The owner accepted the still-open fresh-Mac permission walkthrough and physical
macOS 14 execution tests. `clean_mac` stays false; the separately recorded,
ARM-only beta exception permits this gap without declaring it passed. Licensing,
offline/privacy and actual signed-update reviews remain mandatory. The website
labels the release as a beta and discloses the incomplete device matrix.

## Release sequence

1. Complete actual Sparkle installation of accepted ARM build 9 through the
   production website's temporary, six-hour capability route. Confirm exact feed
   bytes/signature, HTTPS download/redirect, final DMG size/hash, installed app seal,
   Gatekeeper and original notice/Rust-code proof. Retire the capability afterward.
2. Review both feature-branch diffs, commit/push, open PRs, require passing CI and
   merge. The website deploy must be ready before public app promotion.
3. Upload the complete reviewed runtime privately, read it back and pin its SHA-256
   in the main-only GitHub release environment. Never put weights or credentials
   in Git. Public build numbers start above 100, beyond all private builds 1–9.
4. Enable the approved main-branch release workflow. It rebuilds from merged source,
   removes the private-candidate marker, includes full notices/corresponding source,
   signs and notarizes both the app and DMG, and generates final signed metadata.
5. Publish immutable artifacts, download through the public website and verify the
   entire file, then atomically promote the release pointer. Check the actual
   public Sparkle installation and the live beta download page afterward.

## Evidence

Build-9 baseline: [release checks](release-build9-checks-2026-10-15.md).
Local beta-gate regression: 31 release tests pass, including rejection of attempts
to use the beta exception for licensing/privacy/update failures or Intel.
Website: 15 download tests, 20 dependency-security tests, lint, production build
and typecheck pass. Production license presentation is readable on the DE page.

The HTTPS installation result, PRs and final public release are recorded below
once completed; this plan is not a claim that those later steps have passed.

CI may consume the accepted build-9 DMG directly as its pinned private runtime.
The server-side copy avoids a redundant ZIP upload; CI checks the full SHA-256,
validates the stapled ticket, mounts read-only and always detaches after copying.
The source app is still rebuilt from the merged commit before public signing.

## Completed production-host HTTPS installation

On 2026-10-15 the official Sparkle CLI downloaded and installed final accepted
ARM build 9 over the production Railway website's HTTPS feed and HTTPS storage
redirect, replacing an isolated stopped build-8 app. Exact feed bytes/signature,
HEAD size/hash and the full downloaded DMG SHA-256 matched the accepted package.
Installed app seal, Gatekeeper, all 1,330 notices and Rust code proof passed.
Machine-readable evidence: `release-https-update-2026-10-15.json`.
The temporary feed was revoked after the test. No GUI/relaunch claim is made.

The accepted DMG was server-side copied to the private runtime prefix and fully
read back; GitHub's `saywing-release` environment pins format `dmg` and SHA-256
`4d3f4bdd0681c4197e3242731d0e6628b609b73674470674511bfa779c392e3e`.
The real local CI extraction also passed staple validation, read-only mount,
app seal, receipts and license inventory checks; its temporary copy was removed.
