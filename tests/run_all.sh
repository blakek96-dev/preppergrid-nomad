#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests=(
  "tests/test_installer.sh"
  "tests/test_disk_collector.sh"
  "tests/test_compose.sh"
  "tests/test_launchd.sh"
  "tests/test_integration.sh"
)

declare -a names=()
declare -a statuses=()
declare -a durations=()
overall=0

for test_file in "${tests[@]}"; do
  start_time="$(date +%s)"
  echo "Running ${test_file}"
  if bash "${REPO_ROOT}/${test_file}"; then
    status="PASS"
  else
    status="FAIL"
    overall=1
  fi
  end_time="$(date +%s)"
  names+=("$test_file")
  statuses+=("$status")
  durations+=("$((end_time - start_time))")
done

echo ""
printf '%-35s | %-7s | %s\n' "test file" "result" "duration seconds"
printf '%-35s-+-%-7s-+-%s\n' "-----------------------------------" "-------" "----------------"
for i in "${!names[@]}"; do
  printf '%-35s | %-7s | %s\n' "${names[$i]}" "${statuses[$i]}" "${durations[$i]}"
done

exit "$overall"
