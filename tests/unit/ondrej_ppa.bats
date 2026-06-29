#!/usr/bin/env bats
#
# get_ondrej_php_ppa_release_status() — returns curl's HTTP status string for the
# ondrej/php PPA Release file of a given Ubuntu codename.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  stub_init
  load_functions
}

teardown() {
  stub_cleanup
}

@test "returns the HTTP code curl reports (200)" {
  make_stub curl <<'EOF'
#!/usr/bin/env bash
echo "200"
EOF
  run get_ondrej_php_ppa_release_status noble
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "returns 404 for a codename with no PPA build" {
  make_stub curl <<'EOF'
#!/usr/bin/env bash
echo "404"
EOF
  run get_ondrej_php_ppa_release_status plucky
  [ "$output" = "404" ]
}

@test "tolerates curl failure without aborting (trailing || true)" {
  make_stub curl <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  run get_ondrej_php_ppa_release_status noble
  [ "$status" -eq 0 ]
}
