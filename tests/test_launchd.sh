#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="${REPO_ROOT}/install/com.preppergrid.nomad.agent.plist"
failures=0

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1: $2"
  failures=$((failures + 1))
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

assert_python() {
  local test_name="$1"
  local code="$2"
  if python3 -c "$code"; then
    pass "$test_name"
  else
    fail "$test_name" "python assertion failed"
  fi
}

assert_command "launchd plist exists" test -f "$PLIST"

if [[ -f "$PLIST" ]]; then
  if command -v xmllint >/dev/null 2>&1; then
    assert_command "launchd plist XML is valid with xmllint" xmllint --noout "$PLIST"
  else
    assert_python "launchd plist XML is valid with plistlib fallback" "import plistlib; plistlib.load(open('$PLIST','rb'))"
  fi

  assert_python "launchd plist label is com.preppergrid.nomad.agent" "import plistlib; d=plistlib.load(open('$PLIST','rb')); assert d.get('Label') == 'com.preppergrid.nomad.agent'"
  assert_python "launchd plist contains ProgramArguments" "import plistlib; d=plistlib.load(open('$PLIST','rb')); assert isinstance(d.get('ProgramArguments'), list) and len(d['ProgramArguments']) > 0"
  assert_python "launchd plist RunAtLoad is true" "import plistlib; d=plistlib.load(open('$PLIST','rb')); assert d.get('RunAtLoad') is True"
  assert_python "launchd plist StandardOutPath points to logs directory" "import plistlib; d=plistlib.load(open('$PLIST','rb')); p=d.get('StandardOutPath'); assert isinstance(p, str) and '/logs/' in p and p.endswith('launchd.log')"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
