# Unplug — agent rules

## Version scheme

`MAJOR.MINOR.PATCH`, and the two lower numbers mean different things:

- **MAJOR** — a breaking change to how the app behaves or is configured.
- **MINOR** — small changes, bug fixes, security patches. Bumping the second
  number is the owner's call: it means a run of pre-releases has been tested
  and declared good enough to ship.
- **PATCH** — a live pre-release. Always published with `--prerelease`, always
  something the owner still needs to try on a device.

So a change goes out as `v1.1.10` (pre-release, test it), and when the owner
says it is good enough, the shipped release becomes `v1.2.0`.

### The minor number must climb, never dip

The update checker compares numerically, component by component. A release
numbered *below* the current latest can never be seen by anyone on that
latest, so its banner never appears and the release is invisible to users who
do not find it by hand.

This is not theoretical. `v1.8.9` was published to prove that comparison does
real numeric ordering across the minor component — it did, the banner fired —
but it left the whole 1.1.x series permanently unable to trigger the banner,
because `1.1.x` is numerically older than the published `1.8.9`. It had to be
renamed to `v1.1.9` and marked a pre-release.

Never publish a version number below the current latest, and never burn a
version number to test the banner. `test/version_test.dart` and
`test/update_detection_test.dart` already cover the comparison against the real
sources; a release-day banner test needs an on-device person, not a version
number.

### Pre-releases and `releases/latest`

GitHub's `releases/latest` **excludes pre-releases**, and that is the endpoint
the in-app checker reads. So while `v1.1.10` is a pre-release, users still see
`v1.1.8` or whatever the last shipped release was. That is intended: pre-release
users install by hand, and everyone else is not offered something unfinished.

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
source read correctly.

## Known pre-existing test failures

Two tests in `test/version_test.dart` fail with HTTP 403 against the GitHub
Releases API:

- `update sources / both sources are reachable and report a parseable version`
- `update sources / the VERSION file at the release tag matches the release tag`

These hit the live unauthenticated API, which allows 60 requests per hour per IP.
They are not throttled like the app is, so they exhaust the shared budget. They
fail on a clean tree — do not treat them as a regression from your change, and
do not try to "fix" them as part of an unrelated task. Verify against a stashed
tree if in doubt.

## Building

```bash
flutter pub get
./tool/gen_version.sh     # after any pubspec version change
flutter build apk --release
```

Requires Gradle ≥ 8.14, AGP ≥ 8.11.1, Kotlin ≥ 2.2.20, NDK 28.x. Built and
released against Flutter 3.47.7.