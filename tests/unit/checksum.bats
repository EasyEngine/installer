#!/usr/bin/env bats
#
# download_and_install_easyengine() — the security-critical path: download the
# phar, verify its SHA-512 against the published checksum, and only then install
# it. These tests stub `curl` so the phar/checksum bytes are fully controlled.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  stub_init
  export EE_QUIET_OUTPUT=""
  # Install target lives in a throwaway path, not /usr/local/bin.
  EE4_BINARY="$(mktemp -u "${BATS_TMPDIR:-/tmp}/ee.XXXXXX")"
  export EE4_BINARY
  load_functions

  # curl stub: writes controlled bytes to --output based on the URL suffix.
  #   CK_PHAR       -> phar contents
  #   CK_CHECKSUM   -> hex hash written as "<hash>  easyengine.phar"
  #                    (empty => an empty checksum file)
  #   CK_CURL_EXIT  -> curl exit code (default 0)
  make_stub curl <<'EOF'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) out="$2"; shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *.sha512)
    if [ -n "${CK_CHECKSUM:-}" ]; then
      printf '%s  easyengine.phar\n' "$CK_CHECKSUM" > "$out"
    else
      : > "$out"
    fi
    ;;
  *)
    printf '%s' "${CK_PHAR:-}" > "$out"
    ;;
esac
exit "${CK_CURL_EXIT:-0}"
EOF
}

teardown() {
  rm -f "$EE4_BINARY"
  stub_cleanup
}

@test "installs the phar when the checksum matches" {
  export CK_PHAR="FAKE-PHAR-CONTENTS"
  CK_CHECKSUM="$(printf '%s' "$CK_PHAR" | sha512sum | awk '{print $1}')"
  export CK_CHECKSUM
  run download_and_install_easyengine
  [ "$status" -eq 0 ]
  [ -f "$EE4_BINARY" ]
  [ "$(cat "$EE4_BINARY")" = "FAKE-PHAR-CONTENTS" ]
  [ -x "$EE4_BINARY" ]
}

@test "aborts and installs nothing on a checksum mismatch" {
  export CK_PHAR="TAMPERED"
  export CK_CHECKSUM="deadbeef"
  run download_and_install_easyengine
  [ "$status" -ne 0 ]
  [ ! -f "$EE4_BINARY" ]
  [[ "$output" == *"checksum mismatch"* ]]
}

@test "aborts when the downloaded phar is empty" {
  export CK_PHAR=""
  export CK_CHECKSUM="anything"
  run download_and_install_easyengine
  [ "$status" -ne 0 ]
  [ ! -f "$EE4_BINARY" ]
}

@test "aborts when the checksum file is empty" {
  export CK_PHAR="SOME-PHAR"
  export CK_CHECKSUM=""
  run download_and_install_easyengine
  [ "$status" -ne 0 ]
  [ ! -f "$EE4_BINARY" ]
}

@test "aborts when the phar download fails" {
  export CK_PHAR="whatever"
  export CK_CURL_EXIT=22
  run download_and_install_easyengine
  [ "$status" -ne 0 ]
  [ ! -f "$EE4_BINARY" ]
}
