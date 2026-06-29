# Tests

Automated tests for the EasyEngine installer. Two layers:

| Layer | Location | What it covers | Needs |
|-------|----------|----------------|-------|
| Unit | `tests/unit/*.bats` | Pure-ish logic in `functions`, with all external commands stubbed | [bats-core] |
| Integration | `tests/integration/host-prep.sh` | The host-prep stage run against a distro's **real** apt repos | Docker (or run inside a container) |

CI wires both up plus ShellCheck — see `.github/workflows/ci.yml`.

## Why integration stops before the phar

`do_install()` ends with `pull_easyengine_images`, which runs `ee cli info` and
makes EasyEngine bootstrap its global Docker services (multi-GB image pulls,
a running Docker daemon, migrations). That is EasyEngine-**core** behaviour, not
the installer's, and is slow/flaky to reproduce in CI. So the integration test is
bounded **before** the phar download/pull and stubs `docker`, exercising only the
OS-version–dependent surface that has actually regressed in the past:

```
check_dependencies → setup_host_dependencies → setup_php → setup_php_extensions
```

PHP selection in particular can only be validated against real distro repos +
the real ondrej/sury PPA — a stub can't reproduce "ondrej has no build for this
codename yet", which is exactly the Ubuntu 26.04 class of bug.

## Running

### Unit tests

```bash
# With bats installed locally:
bats tests/unit

# Or via Docker, no local install:
docker run --rm -v "$PWD":/code -w /code bats/bats:latest tests/unit
```

### Integration tests

```bash
# One distro:
docker run --rm -v "$PWD":/installer:ro -w /installer ubuntu:24.04 \
  bash tests/integration/host-prep.sh

# Full local matrix (same images as CI):
tests/integration/run-matrix.sh
# ...or a subset:
tests/integration/run-matrix.sh ubuntu:24.04 debian:12
```

### ShellCheck

```bash
shellcheck setup.sh functions migration/migrate.sh migration/remote-migrate
```

## How the unit stubs work

`tests/helpers/common.bash` prepends a temp dir to `PATH` and drops fake
executables into it (`make_stub apt-get <<'EOF' … EOF`), so calls to `apt-get`,
`curl`, `sleep`, etc. hit the stub instead of the host. The PHP-selection test
goes one step further and overrides the four `ee_php_*` helpers as shell
functions to drive the algorithm through every branch deterministically.

## Coverage today

- `parse_args` — every flag, including the `--remote-host` value-consuming case.
- `ee_apt_update` — succeeds first try / retries only on lock contention / aborts
  on a non-lock error.
- `get_ondrej_php_ppa_release_status` — 200/404/curl-failure.
- `ee_select_and_install_php` — native vs PPA, version-first ordering, no-candidate.
- `download_and_install_easyengine` — checksum match / mismatch / empty phar /
  empty checksum / download failure.
- Host-prep integration — php + the three required extensions install across
  Ubuntu 22.04/24.04/rolling/devel and Debian 12/13.

## Not yet covered (candidate follow-ups)

- **`pull_easyengine_images` / full `setup.sh` end-to-end.** Would need a small
  testability seam: an `EE_LOCAL_PHAR` override mirroring the existing
  `EE_LOCAL_FUNCTIONS` hook so a fake `ee` can stand in for the real phar (also
  useful for air-gapped/mirror installs). Not added here to keep this change
  test-only with zero production edits.
- **Idempotency** — running the installer twice and asserting the second run is a
  clean no-op. Needs the seam above.
- **`add_ssl_renew_cron`** — cron-entry creation (incl. the no-existing-crontab case).
- **Migration scripts** (`migration/*`) — only ShellCheck'd today; see below.

## Known issues these tests / ShellCheck surface

Found while building the suite; not fixed here (test-only change):

- `--dry-run` is documented in `migration/README.md` and parsed by `parse_args`
  (sets `EE_DRY_RUN`), but `EE_DRY_RUN` is read **nowhere** — `ee migrate --dry-run`
  performs a real migration.
- `--trace` sets `EE_TRACE`, but the migration scripts check `$TRACE` → the flag
  is a no-op. `--all` sets `EE_SITE_ALL`, also unused.
- `migration/migrate.sh:156` references `$new_site_name`, which is never assigned
  (the site is created with an empty name).
- `migration/{migrate,remote-migrate}` reference undefined `$migrate`, `$Red`,
  `$RCol`, and have 8 error-level `SC2068` unquoted array expansions.

[bats-core]: https://github.com/bats-core/bats-core
