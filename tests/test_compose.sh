#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/install/compose.macos.yml"
COMPOSE_ENV="${REPO_ROOT}/install/compose.macos.env"
STDERR_FILE=""
TEMP_COMPOSE=""
TEMP_ENV=""
failures=0

cleanup() {
  [[ -z "$STDERR_FILE" ]] || rm -f "$STDERR_FILE" || true
  [[ -z "$TEMP_COMPOSE" ]] || rm -f "$TEMP_COMPOSE" || true
  [[ -z "$TEMP_ENV" ]] || rm -f "$TEMP_ENV" || true
}
trap cleanup EXIT

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1: $2"
  failures=$((failures + 1))
}

assert_contains() {
  local test_name="$1"
  local pattern="$2"
  if grep -Eq "$pattern" "$COMPOSE_FILE"; then
    pass "$test_name"
  else
    fail "$test_name" "required pattern not found: $pattern"
  fi
}

assert_not_contains() {
  local test_name="$1"
  local pattern="$2"
  if grep -Eq "$pattern" "$COMPOSE_FILE"; then
    fail "$test_name" "unexpected pattern found: $pattern"
  else
    pass "$test_name"
  fi
}

assert_command() {
  local test_name="$1"
  shift
  if "$@"; then
    pass "$test_name"
  else
    fail "$test_name" "command failed: $*"
  fi
}

assert_compose_config() {
  local test_name="$1"
  STDERR_FILE="$(mktemp -t preppergrid-compose-config.XXXXXX)"

  if [[ -f "$COMPOSE_ENV" ]]; then
    if docker compose --env-file "$COMPOSE_ENV" -f "$COMPOSE_FILE" config --quiet 2>"$STDERR_FILE"; then
      rm -f "$STDERR_FILE"
      STDERR_FILE=""
      pass "$test_name"
      return
    fi
  else
    TEMP_COMPOSE="$(mktemp -t preppergrid-compose.XXXXXX.yml)"
    TEMP_ENV="$(mktemp -t preppergrid-compose.XXXXXX.env)"
    cat > "$TEMP_ENV" <<EOF
NOMAD_DIR=/tmp/preppergrid-nomad-compose-test
NOMAD_IMAGE=ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest
EOF
    python3 - "$COMPOSE_FILE" "$TEMP_COMPOSE" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text().splitlines()
out = []
skip_next_compose_env = False
for line in source:
    if skip_next_compose_env and line.strip() == "- compose.macos.env":
        skip_next_compose_env = False
        continue
    skip_next_compose_env = False
    if line.strip() == "env_file:":
        skip_next_compose_env = True
        continue
    out.append(line)

Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
    if docker compose --env-file "$TEMP_ENV" -f "$TEMP_COMPOSE" config --quiet 2>"$STDERR_FILE"; then
      rm -f "$STDERR_FILE" "$TEMP_COMPOSE" "$TEMP_ENV"
      STDERR_FILE=""
      TEMP_COMPOSE=""
      TEMP_ENV=""
      pass "$test_name"
      return
    fi

    if grep -v 'The "NOMAD_DIR" variable is not set' "$STDERR_FILE" >&2; then
      :
    fi
    rm -f "$STDERR_FILE" "$TEMP_COMPOSE" "$TEMP_ENV"
    STDERR_FILE=""
    TEMP_COMPOSE=""
    TEMP_ENV=""
    fail "$test_name" "docker compose config failed"
    return
  fi

  cat "$STDERR_FILE" >&2
  rm -f "$STDERR_FILE"
  STDERR_FILE=""
  fail "$test_name" "docker compose config failed"
}

assert_command "compose file exists" test -f "$COMPOSE_FILE"

if [[ -f "$COMPOSE_FILE" ]]; then
  assert_contains "compose declares linux arm64 platform" "linux/arm64"
  assert_not_contains "compose has no host-gateway entry" "host-gateway"
  assert_not_contains "compose has no /opt/project-nomad path" "/opt/project-nomad"
  assert_not_contains "compose has no mysql host port binding" "3306:3306"
  assert_not_contains "compose has no HOME variable" '\\$HOME'
  assert_contains "compose project name is preppergrid-nomad" "name:[[:space:]]*preppergrid-nomad"
  assert_contains "compose has env_file key" "env_file:"
  assert_contains "compose env_file references compose.macos.env" "compose\\.macos\\.env"
  assert_contains "compose volume paths use NOMAD_DIR" '\${NOMAD_DIR}'
  assert_contains "compose has admin service" "^[[:space:]]{2}admin:"
  assert_contains "compose has mysql service" "^[[:space:]]{2}mysql:"
  assert_contains "compose has redis service" "^[[:space:]]{2}redis:"
  assert_contains "compose has dozzle service" "^[[:space:]]{2}dozzle:"
  assert_contains "compose has updater service" "^[[:space:]]{2}updater:"
  assert_contains "compose admin healthcheck is present" "healthcheck:"
  assert_contains "compose admin image references fork ghcr image" "ghcr\\.io/blakek96-dev/preppergrid-nomad"

  if command -v docker >/dev/null 2>&1; then
    assert_compose_config "docker compose config is valid"
  else
    fail "docker compose config is valid" "docker command is not available"
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
