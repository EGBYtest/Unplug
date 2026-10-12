# Unplug — agent rules

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