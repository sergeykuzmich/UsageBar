#!/bin/bash
# Builds from source and installs into /Applications. For development.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="/Applications/UsageBar.app"

"$repo_dir/scripts/build-app.sh"

osascript -e 'quit app "UsageBar"' 2>/dev/null || true
rm -rf "$target"
cp -R "$repo_dir/dist/UsageBar.app" /Applications/
open "$target"

echo "$target"
