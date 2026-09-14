#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$root/.build/build-metadata-tests"
fake_bin="$test_root/bin"
built_bin="$test_root/built"
mkdir -p "$fake_bin" "$built_bin"
printf '#!/bin/bash\nexit 0\n' >"$built_bin/usagebar"
chmod +x "$built_bin/usagebar"

cat >"$fake_bin/swift" <<'EOF'
#!/bin/bash
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$BUILD_METADATA_BIN_PATH"
fi
EOF
cat >"$fake_bin/git" <<'EOF'
#!/bin/bash
if [[ "$*" == "remote get-url origin" ]]; then
  printf '%s\n' "$BUILD_METADATA_ORIGIN"
fi
EOF
cat >"$fake_bin/codesign" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$fake_bin/swift" "$fake_bin/git" "$fake_bin/codesign"

assert_repository() {
  local origin="$1"
  local expected="$2"
  BUILD_METADATA_BIN_PATH="$built_bin" BUILD_METADATA_ORIGIN="$origin" \
    PATH="$fake_bin:$PATH" make -s -C "$root" build >/dev/null
  local actual
  actual="$(/usr/libexec/PlistBuddy -c 'Print :UsageBarUpdateRepository' \
    "$root/dist/UsageBar.app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'origin %q: expected repository %q, got %q\n' "$origin" "$expected" "$actual" >&2
    return 1
  fi
}

assert_no_repository() {
  local origin="$1"
  assert_repository "$origin" ""
}

assert_repository "https://github.com/github/.github.git" "github/.github"
assert_repository "git@github.com:github/.github.git" "github/.github"
assert_repository "https://github.com/981011512/--.git" "981011512/--"
assert_repository "git@github.com:981011512/--.git" "981011512/--"
assert_no_repository "https://github.com/owner/.git"
assert_no_repository "git@github.com:owner/...git"
assert_no_repository "https://github.com/owner/repo/extra.git"
assert_no_repository "https://github.com/owner/repo.git?tab=readme"
assert_no_repository "git@github.com:owner/repo.git#readme"

rm -rf "$test_root"
printf 'Build metadata tests passed.\n'
