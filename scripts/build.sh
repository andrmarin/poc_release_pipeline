#!/usr/bin/env bash
# Builds the release artifact: dist/sample-app-<version>-<environment>.zip
# plus a .sha256 checksum file next to it.
#
# Inputs (environment variables, all optional except in CI):
#   ENVIRONMENT   development | staging | production   (default: development)
#   VERSION       artifact version                      (default: local pseudo-version)
#   COMMIT        full git SHA                          (default: from local git)
#   WORKFLOW_RUN  URL of the CI run                     (default: "local")
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-development}"
VERSION="${VERSION:-}"
COMMIT="${COMMIT:-}"
WORKFLOW_RUN="${WORKFLOW_RUN:-local}"

case "$ENVIRONMENT" in
  development|staging|production) ;;
  *)
    echo "ERROR: ENVIRONMENT must be one of development|staging|production, got '$ENVIRONMENT'" >&2
    exit 1
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$COMMIT" ]]; then
  COMMIT="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
if [[ -z "$VERSION" ]]; then
  short_sha="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  VERSION="v$(date -u +%Y.%m.%d).0-local+${short_sha}"
fi

build_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

dist="$repo_root/dist"
stage="$dist/.stage"
rm -rf "$dist"
mkdir -p "$stage"

cp -r "$repo_root/src/." "$stage/"

cat > "$stage/build.info" <<EOF
environment=$ENVIRONMENT
build_timestamp=$build_timestamp
version=$VERSION
commit=$COMMIT
workflow_run=$WORKFLOW_RUN
EOF

artifact="sample-app-${VERSION}-${ENVIRONMENT}.zip"

# zip is present on GitHub runners; fall back to Python locally (e.g. Git Bash).
# Probe that the interpreter actually runs: on Windows, 'python3' can resolve
# to the Microsoft Store alias stub.
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

if command -v zip >/dev/null 2>&1; then
  (cd "$stage" && zip -qr "$dist/$artifact" .)
else
  py="$(find_python)" || {
    echo "ERROR: need either 'zip' or a working Python to create the archive" >&2
    exit 1
  }
  (cd "$stage" && "$py" -m zipfile -c "$dist/$artifact" .)
fi

rm -rf "$stage"
(cd "$dist" && sha256sum "$artifact" > "$artifact.sha256")

echo "Built $dist/$artifact"
cat "$dist/$artifact.sha256"
