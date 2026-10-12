#!/usr/bin/env bash
# Generates lib/generated/app_version.dart from the version in pubspec.yaml.
# pubspec.yaml is the single source of truth for the app version.
# Run via: ./tool/gen_version.sh  (or automatically through the prebuild hook)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec="$root/pubspec.yaml"
out="$root/lib/generated/app_version.dart"

if [ ! -f "$pubspec" ]; then
  echo "error: pubspec.yaml not found at $pubspec" >&2
  exit 1
fi

version_line="$(grep -E '^version:' "$pubspec" | head -1)"
if [ -z "$version_line" ]; then
  echo "error: no 'version:' key in pubspec.yaml" >&2
  exit 1
fi

full="${version_line#version:}"
full="$(echo "$full" | tr -d '[:space:]')"

if [ -z "$full" ]; then
  echo "error: 'version:' in pubspec.yaml is empty" >&2
  exit 1
fi

name="${full%%+*}"
build="${full#*+}"
if [ "$build" = "$full" ]; then
  echo "error: version '$full' has no '+build' suffix (expected e.g. 1.0.0+26)" >&2
  exit 1
fi

if ! [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version name '$name' is not MAJOR.MINOR.PATCH" >&2
  exit 1
fi
if ! [[ "$build" =~ ^[0-9]+$ ]]; then
  echo "error: build number '$build' is not an integer" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"

cat > "$out" <<EOF
// GENERATED FILE - DO NOT EDIT BY HAND.
// Source: pubspec.yaml  version: $full
// Regenerate with: ./tool/gen_version.sh
//
// To change the app version, edit the 'version:' line in pubspec.yaml only.

class AppVersion {
  const AppVersion._();

  /// Version name without the build suffix, e.g. '1.0.0'.
  static const String name = '$name';

  /// Build number, e.g. 26.
  static const int buildNumber = $build;

  /// Full pubspec version string, e.g. '1.0.0+26'.
  static const String full = '$full';
}
EOF

echo "generated $out (name=$name build=$build)"