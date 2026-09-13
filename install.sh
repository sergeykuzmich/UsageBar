#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/sergeykuzmich/UsageBar/main/install.sh | bash
set -euo pipefail

repo="sergeykuzmich/UsageBar"
asset="https://github.com/$repo/releases/latest/download/UsageBar.zip"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "UsageBar is a macOS menu bar app." >&2
	exit 1
fi

dest="${USAGEBAR_DEST:-/Applications}"
if [[ ! -w "$dest" ]]; then
	dest="$HOME/Applications"
	mkdir -p "$dest"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading UsageBar…"
curl -fsSL -o "$work/UsageBar.zip" "$asset"
# ditto preserves the ad-hoc code signature that plain unzip would strip.
ditto -x -k "$work/UsageBar.zip" "$work/unpacked"

osascript -e 'quit app "UsageBar"' >/dev/null 2>&1 || true
rm -rf "${dest:?}/UsageBar.app"
ditto "$work/unpacked/UsageBar.app" "$dest/UsageBar.app"
xattr -dr com.apple.quarantine "$dest/UsageBar.app" 2>/dev/null || true

open "$dest/UsageBar.app"
echo "Installed to $dest/UsageBar.app"
