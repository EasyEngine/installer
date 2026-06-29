# Shared helpers for the bats unit suite.
#
# These tests source the real `functions` file and replace external commands
# (apt-get, curl, sleep, …) with stubs on PATH, so the installer's logic can be
# exercised without touching the host or the network.

# Absolute path to the repo root (this file lives in tests/helpers/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Create a private dir at the front of PATH to hold command stubs.
stub_init() {
  STUB_DIR="$(mktemp -d)"
  PATH="$STUB_DIR:$PATH"
  export STUB_DIR PATH
}

stub_cleanup() {
  [ -n "${STUB_DIR:-}" ] && rm -rf "$STUB_DIR"
}

# make_stub NAME  — body is read from stdin and becomes an executable on PATH.
#   make_stub apt-get <<'EOF'
#   #!/usr/bin/env bash
#   exit 0
#   EOF
make_stub() {
  local p="$STUB_DIR/$1"
  cat > "$p"
  chmod +x "$p"
}

# Source the installer functions under test.
load_functions() {
  # shellcheck source=/dev/null
  source "$REPO_ROOT/functions"
}
