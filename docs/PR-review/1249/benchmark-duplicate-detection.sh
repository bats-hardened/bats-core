#!/usr/bin/env bash
#
# Compare test-gathering performance between two bats-core Git revisions.
#
# The script exports each revision into an isolated temporary tree and times
# `bats -c` against dynamically registered, fixed-width unique test identities.
# Counting tests exercises preprocessing, gathering, and duplicate detection
# without adding test-execution time. Fixed-width identities avoid accidental
# prefix matches and model the unique UUID-style names from issue #1036.
#
# Usage:
#   docs/PR-review/1249/benchmark-duplicate-detection.sh
#
# Override the defaults with BEFORE_REVISION, AFTER_REVISION, TEST_COUNTS, or
# RUNS. RUNS must be odd so the script can report an observed median. Temporary
# source trees, command output, errors, and raw timings are retained.

set -Eeuo pipefail

readonly BEFORE_REVISION="${BEFORE_REVISION:-06e5f10^}"
readonly AFTER_REVISION="${AFTER_REVISION:-06e5f10}"
readonly TEST_COUNTS="${TEST_COUNTS:-500 1000 2000 4000}"
readonly RUNS="${RUNS:-3}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
repo_root=$(cd -- "$script_dir/../../.." && pwd)
readonly repo_root

if ! [[ $RUNS =~ ^[1-9][0-9]*$ ]] || (( RUNS % 2 == 0 )); then
  printf 'ERROR: RUNS must be a positive odd integer, got: %s\n' "$RUNS" >&2
  exit 2
fi

if [[ -z $TEST_COUNTS ]]; then
  printf 'ERROR: TEST_COUNTS must contain at least one positive integer.\n' >&2
  exit 2
fi

read -r -a test_counts <<<"$TEST_COUNTS"
for test_count in "${test_counts[@]}"; do
  if ! [[ $test_count =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: invalid test count: %s\n' "$test_count" >&2
    exit 2
  fi
done

before_commit=$(git -C "$repo_root" rev-parse --verify "${BEFORE_REVISION}^{commit}")
readonly before_commit
after_commit=$(git -C "$repo_root" rev-parse --verify "${AFTER_REVISION}^{commit}")
readonly after_commit

benchmark_temp_base=${TMPDIR:-/tmp}
benchmark_root=$(mktemp -d "$benchmark_temp_base/bats-duplicate-benchmark.XXXXXX")
readonly benchmark_root
readonly before_tree="$benchmark_root/before"
readonly after_tree="$benchmark_root/after"
readonly fixture="$benchmark_root/many-tests.bats"
readonly raw_results_dir="$benchmark_root/raw"
readonly results_file="$benchmark_root/results.tsv"

report_failure() {
  local status=$?
  printf '\nBenchmark failed. Retained artifacts: %s\n' "$benchmark_root" >&2
  exit "$status"
}
trap report_failure ERR

mkdir "$before_tree" "$after_tree" "$raw_results_dir"

printf 'Repository:       %s\n' "$repo_root"
printf 'Before revision:  %s (%s)\n' "$BEFORE_REVISION" "$before_commit"
printf 'After revision:   %s (%s)\n' "$AFTER_REVISION" "$after_commit"
printf 'Test counts:      %s\n' "$TEST_COUNTS"
printf 'Runs per count:   %s\n' "$RUNS"
printf 'Temporary root:   %s\n' "$benchmark_root"
printf 'Before tree:      %s\n' "$before_tree"
printf 'After tree:       %s\n' "$after_tree"
printf 'Generated fixture:%s\n' " $fixture"
printf 'Raw results:      %s\n\n' "$raw_results_dir"

git -C "$repo_root" archive "$before_commit" | tar -x -C "$before_tree"
git -C "$repo_root" archive "$after_commit" | tar -x -C "$after_tree"

cat >"$fixture" <<'BATS'
#!/usr/bin/env bats

benchmark_test() {
  :
}

for ((i = 0; i < ${TEST_COUNT:?}; ++i)); do
  printf -v test_id '%08d' "$i"
  bats_test_function --description "benchmark $test_id" -- benchmark_test "$test_id"
done
BATS

printf 'revision\ttest_count\trun\telapsed_seconds\n' >|"$results_file"

measure() {
  local label=$1
  local test_count=$2
  local run=$3
  local revision_tree="$benchmark_root/$label"
  local output_file="$raw_results_dir/$label-$test_count-$run.out"
  local error_file="$raw_results_dir/$label-$test_count-$run.err"
  local timing_file="$raw_results_dir/$label-$test_count-$run.time"
  local elapsed actual_count

  TIMEFORMAT='%R'
  { time env TEST_COUNT="$test_count" "$revision_tree/bin/bats" -c "$fixture" >"$output_file" 2>"$error_file"; } 2>"$timing_file"

  actual_count=$(<"$output_file")
  if [[ $actual_count != "$test_count" ]]; then
    printf 'ERROR: %s at %s tests reported %s tests. See %s\n' "$label" "$test_count" "$actual_count" "$output_file" >&2
    return 1
  fi

  elapsed=$(<"$timing_file")
  printf '%s\n' "$elapsed" >>"$raw_results_dir/$label-$test_count.seconds"
  printf '%s\t%s\t%s\t%s\n' "$label" "$test_count" "$run" "$elapsed" >>"$results_file"
  printf '%-6s tests=%-5s run=%s  %s s\n' "$label" "$test_count" "$run" "$elapsed"
}

printf 'Validating both archived revisions with 10 gathered tests...\n'
for label in before after; do
  validation_output=$(env TEST_COUNT=10 "$benchmark_root/$label/bin/bats" -c "$fixture")
  if [[ $validation_output != 10 ]]; then
    printf 'ERROR: %s validation reported %s tests instead of 10.\n' "$label" "$validation_output" >&2
    exit 1
  fi
done
printf 'Validation passed.\n\n'

for test_count in "${test_counts[@]}"; do
  for ((run = 1; run <= RUNS; ++run)); do
    # Alternate execution order to reduce systematic cache and temperature bias.
    if (( run % 2 == 1 )); then
      labels=(before after)
    else
      labels=(after before)
    fi
    for label in "${labels[@]}"; do
      measure "$label" "$test_count" "$run"
    done
  done
done

median_line=$((RUNS / 2 + 1))
printf '\nMedian elapsed seconds:\n'
printf '%-12s %12s %12s\n' 'test count' 'before' 'after'
for test_count in "${test_counts[@]}"; do
  before_median=$(sort -n "$raw_results_dir/before-$test_count.seconds" | sed -n "${median_line}p")
  after_median=$(sort -n "$raw_results_dir/after-$test_count.seconds" | sed -n "${median_line}p")
  printf '%-12s %12s %12s\n' "$test_count" "$before_median" "$after_median"
done

trap - ERR
printf '\nResults table:     %s\n' "$results_file"
printf 'Artifacts retained: %s\n' "$benchmark_root"
