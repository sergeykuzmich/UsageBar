#!/bin/bash
# Builds dist/UsageBar.app. Pass --universal to produce an arm64 + x86_64 binary.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_dir/dist/UsageBar.app"

build_args=(-c release)
if [[ "${1:-}" == "--universal" ]]; then
	build_args+=(--arch arm64 --arch x86_64)
fi

cd "$repo_dir"
swift build "${build_args[@]}"
bin_path="$(swift build "${build_args[@]}" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_path/usagebar" "$app_dir/Contents/MacOS/usagebar"
cp "$repo_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"

if [[ -n "${USAGEBAR_VERSION:-}" ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${USAGEBAR_VERSION}" "$app_dir/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${USAGEBAR_VERSION}" "$app_dir/Contents/Info.plist"
fi

# Ad-hoc signing is what lets an unnotarized app launch on Apple silicon. It is not
# a Developer ID signature, so the app must also arrive without a quarantine flag.
codesign --force --sign - --timestamp=none "$app_dir"

echo "$app_dir"
