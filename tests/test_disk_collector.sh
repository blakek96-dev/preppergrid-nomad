#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${REPO_ROOT}/install/collect_disk_info_macos.sh"
OUTPUT="/tmp/nomad-disk-info.json"
SCHEMA="${REPO_ROOT}/tests/fixtures/expected_disk_schema.json"

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

rm -f "$OUTPUT"

assert_command "disk collector file exists" test -f "$COLLECTOR"
assert_command "expected disk schema fixture is valid JSON" python3 -m json.tool "$SCHEMA" >/dev/null
assert_command "disk collector runs once" "$COLLECTOR" --once
assert_command "disk collector writes output file" test -f "$OUTPUT"

assert_python "disk output has diskLayout and fsSize keys" "import json; d=json.load(open('$OUTPUT')); assert 'diskLayout' in d and 'fsSize' in d"
assert_python "disk output fsSize is non-empty array" "import json; d=json.load(open('$OUTPUT')); assert isinstance(d['fsSize'], list) and len(d['fsSize']) > 0"
assert_python "disk output fsSize entries have required keys" "import json; d=json.load(open('$OUTPUT')); req={'fs','size','used','available','use','mount'}; assert all(req.issubset(x) for x in d['fsSize'])"
assert_python "disk output fsSize numeric fields are positive integers" "import json; d=json.load(open('$OUTPUT')); assert all(isinstance(x['size'], int) and x['size'] > 0 and isinstance(x['used'], int) and x['used'] > 0 and isinstance(x['available'], int) and x['available'] > 0 for x in d['fsSize'])"
assert_python "disk output fsSize use is integer percent" "import json; d=json.load(open('$OUTPUT')); assert all(isinstance(x['use'], int) and 0 <= x['use'] <= 100 for x in d['fsSize'])"
assert_python "disk output fsSize mount is non-empty string" "import json; d=json.load(open('$OUTPUT')); assert all(isinstance(x['mount'], str) and len(x['mount']) > 0 for x in d['fsSize'])"
assert_python "disk output diskLayout is not null" "import json; d=json.load(open('$OUTPUT')); assert d['diskLayout'] is not None"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
