#!/usr/bin/env bash
# Minimal "application": prints a greeting using the build.info stamped into
# the same ZIP. Gives build-verify.sh a behavioral assertion, not just file presence.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info_file="$here/build.info"

if [[ ! -f "$info_file" ]]; then
  echo "ERROR: build.info not found next to hello.sh" >&2
  exit 1
fi

get() { sed -n "s/^$1=//p" "$info_file" | head -n 1; }

echo "Hello from $(get environment) $(get version)"
