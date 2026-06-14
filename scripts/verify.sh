#!/usr/bin/env bash
# Verifies a built artifact: checksum, content, build.info fields, and the
# behavior of the packaged hello.sh.
#
# Usage: verify.sh <path-to-zip> <expected-environment> <expected-app>
set -euo pipefail

fail() { echo "VERIFY FAILED: $*" >&2; exit 1; }

[[ $# -eq 3 ]] || fail "usage: verify.sh <path-to-zip> <expected-environment> <expected-app>"
zip_path="$1"
expected_env="$2"
expected_app="$3"

case "$expected_env" in
  development|staging|production) ;;
  *) fail "expected environment must be development|staging|production, got '$expected_env'" ;;
esac
case "$expected_app" in
  desktop|browser) ;;
  *) fail "expected app must be desktop|browser, got '$expected_app'" ;;
esac

[[ -f "$zip_path" ]] || fail "artifact not found: $zip_path"
zip_dir="$(cd "$(dirname "$zip_path")" && pwd)"
zip_name="$(basename "$zip_path")"

# 1. Checksum
[[ -f "$zip_dir/$zip_name.sha256" ]] || fail "checksum file missing: $zip_name.sha256"
(cd "$zip_dir" && sha256sum -c "$zip_name.sha256" >/dev/null) \
  || fail "sha256 checksum mismatch for $zip_name"
echo "ok: checksum matches"

# 2. Extract
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
find_python() {
  local cand
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import zipfile' >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

if command -v unzip >/dev/null 2>&1; then
  unzip -q "$zip_dir/$zip_name" -d "$workdir"
else
  py="$(find_python)" || fail "need 'unzip' or a working Python to extract"
  "$py" -m zipfile -e "$zip_dir/$zip_name" "$workdir"
fi

# 3. Expected content
for f in app.txt notes.txt hello.sh build.info; do
  [[ -f "$workdir/$f" ]] || fail "expected file missing from ZIP: $f"
done
echo "ok: all expected files present"

# 4. build.info fields
get() { sed -n "s/^$1=//p" "$workdir/build.info" | head -n 1; }
app="$(get app)"
environment="$(get environment)"
build_timestamp="$(get build_timestamp)"
version="$(get version)"
commit="$(get commit)"

[[ -n "$app" ]]             || fail "build.info: app is empty"
[[ -n "$environment" ]]     || fail "build.info: environment is empty"
[[ -n "$build_timestamp" ]] || fail "build.info: build_timestamp is empty"
[[ -n "$version" ]]         || fail "build.info: version is empty"
[[ -n "$commit" ]]          || fail "build.info: commit is empty"
[[ "$app" == "$expected_app" ]] \
  || fail "build.info: app is '$app', expected '$expected_app'"
[[ "$environment" == "$expected_env" ]] \
  || fail "build.info: environment is '$environment', expected '$expected_env'"
[[ "$build_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || fail "build.info: build_timestamp '$build_timestamp' is not ISO 8601 UTC (YYYY-MM-DDThh:mm:ssZ)"
echo "ok: build.info valid (app=$app environment=$environment version=$version)"

# 5. Behavioral check
output="$(bash "$workdir/hello.sh")"
[[ "$output" == *"$app"* ]]         || fail "hello.sh output missing app: '$output'"
[[ "$output" == *"$environment"* ]] || fail "hello.sh output missing environment: '$output'"
[[ "$output" == *"$version"* ]]     || fail "hello.sh output missing version: '$output'"
echo "ok: hello.sh says: $output"

echo "VERIFY PASSED: $zip_name (app=$expected_app env=$expected_env)"
