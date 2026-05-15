#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${REPO_ROOT}/install/install_preppergrid_nomad_macos.sh"

failures=0

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1: $2"
  failures=$((failures + 1))
}

assert_file_exists() {
  local test_name="$1"
  local file="$2"
  if [[ -f "$file" ]]; then
    pass "$test_name"
  else
    fail "$test_name" "missing file $file"
  fi
}

assert_not_contains() {
  local test_name="$1"
  local pattern="$2"
  local file="$3"
  if grep -Eq "$pattern" "$file"; then
    fail "$test_name" "unexpected pattern found: $pattern"
  else
    pass "$test_name"
  fi
}

assert_contains() {
  local test_name="$1"
  local pattern="$2"
  local file="$3"
  if grep -Eq "$pattern" "$file"; then
    pass "$test_name"
  else
    fail "$test_name" "required pattern not found: $pattern"
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

assert_file_exists "installer file exists" "$INSTALLER"

if [[ -f "$INSTALLER" ]]; then
  assert_not_contains "installer has zero apt-get references" "apt-get" "$INSTALLER"
  assert_not_contains "installer has zero systemctl references" "systemctl" "$INSTALLER"
  assert_not_contains "installer has zero /etc/debian_version references" "/etc/debian_version" "$INSTALLER"
  assert_not_contains "installer has zero lsblk references" "lsblk" "$INSTALLER"
  assert_not_contains "installer has zero hostname -I references" "hostname -I" "$INSTALLER"
  assert_not_contains "installer has no curl pipe bash pattern" "curl[[:space:]]*\\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh)" "$INSTALLER"
  assert_contains "installer Homebrew missing message includes brew.sh" "brew\\.sh" "$INSTALLER"
  assert_contains "installer uses ipconfig getifaddr for local IP" "ipconfig getifaddr" "$INSTALLER"
  assert_contains "installer uses uname -s for OS detection" "uname -s" "$INSTALLER"
  assert_contains "installer contains NOMAD_DIR or preppergrid path" "(NOMAD_DIR|\\.preppergrid-nomad)" "$INSTALLER"
  assert_contains "installer defaults NOMAD_DIR under /Users user path" 'DEFAULT_NOMAD_DIR="/Users/\$USER/\.preppergrid-nomad"' "$INSTALLER"
  assert_not_contains "installer default NOMAD_DIR does not use HOME" 'HOME.*\.preppergrid-nomad|\.preppergrid-nomad.*HOME' "$INSTALLER"
  assert_command "installer bash syntax is valid" bash -n "$INSTALLER"
  assert_not_contains "installer has no nvidia references" "[Nn][Vv][Ii][Dd][Ii][Aa]" "$INSTALLER"
  assert_contains "installer contains Metal or Ollama GPU notice" "(Metal|Ollama)" "$INSTALLER"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
