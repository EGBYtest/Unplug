# Unplug — agent rules

## Tag history: two v1.x series, then v2

The repository carries **two overlapping `v1.x` tag series** on the same
repository, plus a `v0.x.y-beta` one. This is why numbering here has been
error-prone, and it is worth understanding before cutting a release.

**Series 1 — pre-1.0.0 development (July–Oct 2026), never published.**
Roughly 40 lightweight tags, mostly with no release entry:

```
v1.2.0+2  v1.2.0-beta  v1.2.1  v1.3.1  v1.3.2  v1.3.3
v1.4.0  v1.4.1  v1.5.0  v1.5.1  v1.6.0  v1.6.1
v1.7.0  v1.7.1  v1.7.2  v1.7.3  v1.7.4  v1.8.0
v1.8.2-beta … v1.8.7-beta
```

**Series 2 — the real releases (Oct 2026 onward).** The only `v1.x` tags that
were actually published:

```
v1.0.0  v1.1.0  v1.1.1 … v1.1.9  v1.2.0
```

**Series 3 — `v0.x.y-beta`**, the pre-1.0.0 beta line, already retired.

The two v1.x series collide on the same namespace. Concretely, this has
happened:

- `v1.2.1` **already exists** as an unpublished July tag, so it cannot be cut
  again even though no release was ever published under it.
- Publishing `v1.8.9` to test the banner comparison left every `1.1.x` release
  numerically older than the published `latest`, so the entire 1.1.x series
  could no longer trigger the update banner. It had to be renamed to `v1.1.9`.
- `v1.8.2-beta` … `v1.8.7-beta` are easy to mistake for current 1.8.x work.

**Consequence: releases move to the `v2` series from here.** `v2.0.0` is the
first. The v1 tags stay on the remote untouched — they are history, and
rewriting published tags breaks anyone who bookmarked them.

Check for a collision before cutting any tag:

```bash
git ls-remote --tags origin | grep -E 'refs/tags/v2'
```

## Version scheme

`MAJOR.MINOR.PATCH`, and the two lower numbers mean different things:

- **MAJOR** — a breaking change to how the app behaves or is configured.
- **MINOR** — small changes, bug fixes, security patches. Bumping the second
  number is the owner's call: it means a run of pre-releases has been tested
  and declared good enough to ship.
- **PATCH** — a live pre-release. Always published with `--prerelease`, always
  something the owner still needs to try on a device.

So a change goes out as `v2.0.1` (pre-release, test it), and when the owner
says it is good enough, the shipped release becomes `v2.1.0`.

### The minor number must climb, never dip

The update checker compares numerically, component by component. A release
numbered *below* the current latest can never be seen by anyone on that
latest, so its banner never appears and the release is invisible to users who
do not find it by hand.

Never publish a version number below the current latest, and never burn a
version number to test the banner. `test/version_test.dart` and
`test/update_detection_test.dart` cover the comparison against the real
sources; a release-day banner test needs an on-device person, not a version
number.

### Pre-releases are invisible to the checker

GitHub's `releases/latest` **excludes pre-releases**, and that is the endpoint
the in-app checker reads. A pre-release is never offered to anyone, however
new its number is. This is not a comparison failure — the checker simply never
learns the release exists.

So while `v2.0.1` is a pre-release, users still see `v2.0.0`. Intended:
pre-release users install by hand, and everyone else is not offered something
unfinished.

Check what the checker will actually see:

```bash
gh api repos/EGBYtest/Unplug/releases/latest --jq .tag_name
```

## Release rule: the README is part of every release

When cutting a version bump, tagging, or publishing a release to GitHub, the
README must be updated in the same change. A release that ships with a stale
README is not finished.

Checklist before tagging:

- [ ] `VERSION` and the `version:` line in `pubspec.yaml` agree, and match the tag
- [ ] `lib/generated/app_version.dart` regenerated via `./tool/gen_version.sh`
- [ ] No tag collision — `git ls-remote --tags origin | grep -E 'refs/tags/v2'`
- [ ] README "Version" line near the top matches the new version
- [ ] README **Download** section points at the new release, with the real APK
      size and the current minSdk — not the previous release's numbers
- [ ] Every stale version reference swept: `grep -n "v1\.[0-9]*\.[0-9]*" README.md`
      and check each hit is either current or deliberately historical
- [ ] Anything user-visible that changed since the last release is described
- [ ] Release notes state what to spot-check on device
- [ ] Pre-release or not, decided per the version scheme above

`releases/latest` is what the in-app update checker reads, so the tag is the
user-visible version. If the README and the tag disagree, the README is wrong.

## Verify claims against the built artifact, not the source

Anything the README asserts about the shipped APK must be checked against a
built artifact, not inferred from the source tree. Manifest permissions are the
recurring trap: a permission declared only in `debug/` or `profile/` does **not**
reach a release build, so the source looks correct while the shipped APK is
missing it.

```bash
flutter build apk --release
~/Android/Sdk/build-tools/36.0.0/aapt2 dump badging \
  build/app/outputs/flutter-apk/app-release.apk | grep -i uses-permission
```

Prefer this over reasoning about what the manifest "obviously" contains. The
missing-`INTERNET` bug in v1.1.0–v1.1.7 shipped for seven releases because the
source read correctly, and v1.1.0–v1.2.0 all lack `bonus_anchor_` handling that
the v2 limiter expects.

## Known pre-existing test failures

Two tests in `test/version_test.dart` fail with HTTP 403 against the GitHub
Releases API:

- `update sources / both sources are reachable and report a parseable version`
- `update sources / the VERSION file at the release tag matches the release tag`

These hit the live unauthenticated API, which allows 60 requests per hour per IP.
They are not throttled like the app is, so they exhaust the shared budget and
then fail on their own once the window resets — they have passed and failed
across runs on an identical tree. Do not treat them as a regression, and do not
try to "fix" them as part of an unrelated task. Verify against a stashed tree if
in doubt.

## Building

```bash
flutter pub get
./tool/gen_version.sh     # after any pubspec version change
flutter build apk --release
```

Requires Gradle ≥ 8.14, AGP ≥ 8.11.1, Kotlin ≥ 2.2.20, NDK 28.x. Built and
released against Flutter 3.47.7.