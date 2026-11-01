# AnimationNuke

**Scale every decorative UI animation from 0.5× (slow motion) to 100× (effectively gone) — with one slider in Settings.**

Install: add `https://nucleartweaks.github.io/` in Sileo/Cydia (rootless, iOS 15+). Applies live — moving the slider changes animation speed in every app immediately, no respring.

## Why it exists

iOS is full of animations that exist purely to look nice. App opening, app closing, the switcher, the lock-screen dismiss, the rubber-band bounce at the end of a scroll — none of it moves information faster; it all just makes you wait. On older devices or a fresh install the tax adds up to seconds per interaction. Apple exposes "Reduce Motion" (which replaces animations with different animations, not fewer) and nothing else. If your phone is a tool, you should be able to tell it to stop performing.

## What it does

A single Settings slider (`Settings → AnimationNuke`):

- **1× (default, position 25)** — stock iOS.
- **Left of center: 0.5×–1×** — slow motion, for when you actually want to watch the animations.
- **Right of center: 1×–100×** — logarithmic, so the whole usable range is reachable. **At 100× every decorative animation resolves in under a frame: it's gone.**
- Speed applies **live everywhere** (Darwin notification, no respring) and is remembered.

Covers anything that animates for fun, system-wide: app open/close (icon zoom), app switcher, lock-screen dismiss, scroll bounce/rubber-band, view controller transitions, keyboard, alerts, layer fades — everything that goes through UIKit or CoreAnimation timing.

It does **not** touch finger-following behavior (scrolling tracks your finger exactly), does not break video/games (AVFoundation playback is not UIKit animation), and does not change frame rates.

## How it works

Instead of patching SpringBoard internals (version-fragile), AnimationNuke scales the *duration argument* at the ~12 chokepoints every decorative animation on iOS must pass through, in every GUI process:

- **`UIView` animate blocks** — all six public entry points, including the spring variants (`animateWithSpringDuration:bounce:...`) and keyframes. Delays are scaled too — waiting is the waste.
- **`UIViewPropertyAnimator`** — the interruptible fraction-driven animators modern iOS uses for app transitions and icon zoom; init + `setDuration:` with a re-entrancy guard so durations scale exactly once.
- **`CAAnimation setDuration:`** — the base class of every basic/keyframe/spring CoreAnimation, which covers scroll rebound and raw layer animations that never touch the UIView API.
- **`CATransaction setAnimationDuration:`** — the implicit-animation clock.

Everything resolves at runtime (`-undefined dynamic_lookup` + `mobilesubstrate` dependency), so it links against whatever substrate the jailbreak provides (ElleKit/libhooker) and hooks are installed only where the selector exists — future iOS versions degrade to a partial no-op, never a crash. Speed is stored in the `com.nucleartweaks.animation-nuke` preference domain; the Settings pane is a PreferenceLoader bundle whose private `Preferences` classes are declared in-source and resolved at runtime (no SDK stubs, so SDK drift can't break the build).

Sub-1ms durations snap instead of animating — at 100× there is simply nothing left to draw.

## Coverage notes

- Scroll rubber-band that is CADisplayLink-driven rather than CAAnimation-driven may not scale on every iOS version; if a bounce survives at 100× on your build, file an issue with the iOS version and we'll add the internal hook.
- Apps that hardcode their own frame-stepped animations (some games) are intentionally left alone — they are content, not chrome.

## Testing in the jailbroken iOS 27 simulator

The production filter (`Classes = ( UIApplication )`) loads fine on the JB sim —
ship it unchanged. Two sim quirks: the guest unified log doesn't surface tweak
logging, so load/scale proof lands in `/Users/spencer/animationnuke-proof.txt`
on the Mac host (path absent on device → write fails silently there); and any
injected crash arms `/private/var/tmp/.injection_safemode` (guest FS), which
silently disables ALL injection until deleted — if the tweak "won't load",
check that flag first, then full shutdown→jb.sh→boot if SpringBoard is wedged.

## Development

Org-standard scaffold — pipeline lives in `NuclearTweaks/.github` (reusable `tweak-ci.yml`).

* Local sim loop: `tools/sim-test.sh AnimationNuke` from the workspace root (Mac + JB-13mini; CI never builds for sim).
* Release: push to `main` → CI opens a release PR → merge → GitHub Release + APT repo update.
* `Package:` id `com.nucleartweaks.animation-nuke` is immutable after the first release. See the org KB (`meta` repo → knowledge/pitfalls.md).
