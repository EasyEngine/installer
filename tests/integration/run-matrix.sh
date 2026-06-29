#!/usr/bin/env bash
#
# Local convenience: run the host-prep integration test across a matrix of
# distro containers, the same way CI does. Requires Docker.
#
#   tests/integration/run-matrix.sh                 # default image set
#   tests/integration/run-matrix.sh ubuntu:24.04    # one or more specific images

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

IMAGES=("$@")
if [ "${#IMAGES[@]}" -eq 0 ]; then
  IMAGES=(
    ubuntu:22.04
    ubuntu:24.04
    ubuntu:rolling
    ubuntu:devel
    debian:12
    debian:13
  )
fi

rc=0
for img in "${IMAGES[@]}"; do
  echo "=================================================================="
  echo "==> $img"
  echo "=================================================================="
  if docker run --rm -v "$REPO_ROOT":/installer:ro -w /installer "$img" \
      bash tests/integration/host-prep.sh; then
    echo "==> PASS: $img"
  else
    echo "==> FAIL: $img"
    rc=1
  fi
  echo
done

exit "$rc"
