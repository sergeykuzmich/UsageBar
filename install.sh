#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/sergeykuzmich/UsageBar/main/install.sh | bash
set -euo pipefail

repo="sergeykuzmich/UsageBar"
asset="https://github.com/$repo/releases/latest/download/UsageBar.dmg"

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
image="$work/UsageBar.dmg"
mount="$work/mount"
mkdir -p "$mount"

echo "Downloading UsageBar…"
curl -fsSL -o "$image" "$asset"
hdiutil attach "$image" -nobrowse -readonly -mountpoint "$mount" >/dev/null
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

osascript -e 'quit app "UsageBar"' >/dev/null 2>&1 || true
rm -rf "${dest:?}/UsageBar.app"
ditto "$mount/UsageBar.app" "$dest/UsageBar.app"

open "$dest/UsageBar.app"
echo "Installed to $dest/UsageBar.app"
