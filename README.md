# AnimationNuke

Nukes the wait: scale every decorative UI animation 0.5x–100x.

Install: add `https://nucleartweaks.github.io/` in Sileo/Cydia (rootless, iOS 15+).

## Development

Org-standard scaffold — pipeline lives in `$ORG/.github` (reusable `tweak-ci.yml`).

* Local sim loop: `tools/sim-test.sh AnimationNuke` from the workspace root (Mac + JB-13mini; CI never builds for sim).
* Release: push to `main` → CI opens a release PR → merge → GitHub Release + APT repo update.
* `Package:` id `com.nucleartweaks.animation-nuke` is immutable after the first release. See the org KB (`meta` repo → knowledge/pitfalls.md).
