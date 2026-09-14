#!/usr/bin/env bash
#
# Compare the cost of gathering many small test files between two Git revisions.
#
# The script exports each revision into an isolated temporary tree, generates
# suites containing a configurable number of files and static tests per file,
# and times `bats -c`. Counting tests measures discovery and gathering without
# adding test-execution time. This specifically checks whether deferred,
# sort-based duplicate detection penalizes suites split across many files.
#
# Usage:
#   docs/PR-review/1249/benchmark-many-files.sh
#
# Override the defaults with BEFORE_REVISION, AFTER_REVISION, FILE_COUNTS,
# TESTS_PER_FILE_COUNTS, or RUNS. RUNS must be odd so the script can report an
# observed median. Temporary source trees, generated suites, command output,
# errors, and raw timings are retained.

set -Eeuo pipefail

readonly BEFORE_REVISION="${BEFORE_REVISION:-06e5f10^}"
readonly AFTER_REVISION="${AFTER_REVISION:-06e5f10}"
readonly FILE_COUNTS="${FILE_COUNTS:-100 500 1000}"
readonly TESTS_PER_FILE_COUNTS="${TESTS_PER_FILE_COUNTS:-1 2 5}"
readonly RUNS="${RUNS:-3}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
repo_root=$(cd -- "$script_dir/../../.." && pwd)
readonly repo_root

if ! [[ $RUNS =~ ^[1-9][0-9]*$ ]] || (( RUNS % 2 == 0 )); then
  printf 'ERROR: RUNS must be a positive odd integer, got: %s\n' "$RUNS" >&2
  exit 2
fi

validate_count_list() {
  local variable_name=$1
  local values=$2
  local value

  if [[ -z $values ]]; then
    printf 'ERROR: %s must contain at least one positive integer.\n' "$variable_name" >&2
    exit 2
  fi
  for value in $values; do
    if ! [[ $value =~ ^[1-9][0-9]*$ ]]; then
      printf 'ERROR: invalid value in %s: %s\n' "$variable_name" "$value" >&2
      exit 2
    fi
  done
}

validate_count_list FILE_COUNTS "$FILE_COUNTS"
validate_count_list TESTS_PER_FILE_COUNTS "$TESTS_PER_FILE_COUNTS"
read -r -a file_counts <<<"$FILE_COUNTS"
read -r -a tests_per_file_counts <<<"$TESTS_PER_FILE_COUNTS"

before_commit=$(git -C "$repo_root" rev-parse --verify "${BEFORE_REVISION}^{commit}")
readonly before_commit
after_commit=$(git -C "$repo_root" rev-parse --verify "${AFTER_REVISION}^{commit}")
readonly after_commit

benchmark_temp_base=${TMPDIR:-/tmp}
benchmark_root=$(mktemp -d "$benchmark_temp_base/bats-many-files-benchmark.XXXXXX")
readonly benchmark_root
readonly before_tree="$benchmark_root/before"
readonly after_tree="$benchmark_root/after"
readonly suites_root="$benchmark_root/suites"
readonly raw_results_dir="$benchmark_root/raw"
readonly results_file="$benchmark_root/results.tsv"

report_failure() {
  local status=$?
  printf '\nBenchmark failed. Retained artifacts: %s\n' "$benchmark_root" >&2
  exit "$status"
}
trap report_failure ERR

mkdir "$before_tree" "$after_tree" "$suites_root" "$raw_results_dir"

printf 'Repository:       %s\n' "$repo_root"
printf 'Before revision:  %s (%s)\n' "$BEFORE_REVISION" "$before_commit"
printf 'After revision:   %s (%s)\n' "$AFTER_REVISION" "$after_commit"
printf 'File counts:      %s\n' "$FILE_COUNTS"
printf 'Tests per file:   %s\n' "$TESTS_PER_FILE_COUNTS"
printf 'Runs per case:    %s\n' "$RUNS"
printf 'Temporary root:   %s\n' "$benchmark_root"
printf 'Before tree:      %s\n' "$before_tree"
printf 'After tree:       %s\n' "$after_tree"
printf 'Generated suites: %s\n' "$suites_root"
printf 'Raw results:      %s\n\n' "$raw_results_dir"

git -C "$repo_root" archive "$before_commit" | tar -x -C "$before_tree"
git -C "$repo_root" archive "$after_commit" | tar -x -C "$after_tree"

generate_suite() {
  local file_count=$1
  local tests_per_file=$2
  local suite_dir="$suites_root/files-$file_count-tests-$tests_per_file"
  local file_index test_index test_file

  mkdir "$suite_dir"
  for ((file_index = 1; file_index <= file_count; ++file_index)); do
    printf -v test_file '%s/benchmark-%05d.bats' "$suite_dir" "$file_index"
    {
      printf '#!/usr/bin/env bats\n\n'
      for ((test_index = 1; test_index <= tests_per_file; ++test_index)); do
        printf '@test "benchmark file %05d test %03d" { :; }\n' "$file_index" "$test_index"
      done
    } >|"$test_file"
  done

  printf 'Generated %s files x %s tests: %s\n' "$file_count" "$tests_per_file" "$suite_dir"
}

printf 'Generating benchmark suites...\n'
for tests_per_file in "${tests_per_file_counts[@]}"; do
  for file_count in "${file_counts[@]}"; do
    generate_suite "$file_count" "$tests_per_file"
  done
done
printf '\n'

printf 'revision\tfile_count\ttests_per_file\ttotal_tests\trun\telapsed_seconds\n' >|"$results_file"

measure() {
  local label=$1
  local file_count=$2
  local tests_per_file=$3
  local run=$4
  local revision_tree="$benchmark_root/$label"
  local suite_dir="$suites_root/files-$file_count-tests-$tests_per_file"
  local case_name="$label-files-$file_count-tests-$tests_per_file"
  local output_file="$raw_results_dir/$case_name-run-$run.out"
  local error_file="$raw_results_dir/$case_name-run-$run.err"
  local timing_file="$raw_results_dir/$case_name-run-$run.time"
  local timings_file="$raw_results_dir/$case_name.seconds"
  local total_tests=$((file_count * tests_per_file))
  local elapsed actual_count

  TIMEFORMAT='%R'
  { time "$revision_tree/bin/bats" -c "$suite_dir" >"$output_file" 2>"$error_file"; } 2>"$timing_file"

  actual_count=$(<"$output_file")
  if [[ $actual_count != "$total_tests" ]]; then
    printf 'ERROR: %s reported %s tests instead of %s. See %s\n' "$case_name" "$actual_count" "$total_tests" "$output_file" >&2
    return 1
  fi

  elapsed=$(<"$timing_file")
  printf '%s\n' "$elapsed" >>"$timings_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$file_count" "$tests_per_file" "$total_tests" "$run" "$elapsed" >>"$results_file"
  printf '%-6s files=%-5s tests/file=%-3s run=%s  %s s\n' "$label" "$file_count" "$tests_per_file" "$run" "$elapsed"
}

validation_file_count=${file_counts[0]}
validation_tests_per_file=${tests_per_file_counts[0]}
validation_total=$((validation_file_count * validation_tests_per_file))
validation_suite="$suites_root/files-$validation_file_count-tests-$validation_tests_per_file"
printf 'Validating both archived revisions with %s gathered tests...\n' "$validation_total"
for label in before after; do
  validation_output=$("$benchmark_root/$label/bin/bats" -c "$validation_suite")
  if [[ $validation_output != "$validation_total" ]]; then
    printf 'ERROR: %s validation reported %s tests instead of %s.\n' "$label" "$validation_output" "$validation_total" >&2
    exit 1
  fi
done
printf 'Validation passed.\n\n'

for tests_per_file in "${tests_per_file_counts[@]}"; do
  for file_count in "${file_counts[@]}"; do
    for ((run = 1; run <= RUNS; ++run)); do
      # Alternate execution order to reduce systematic cache and temperature bias.
      if (( run % 2 == 1 )); then
        labels=(before after)
      else
        labels=(after before)
      fi
      for label in "${labels[@]}"; do
        measure "$label" "$file_count" "$tests_per_file" "$run"
      done
    done
  done
done

median_line=$((RUNS / 2 + 1))
printf '\nMedian elapsed seconds:\n'
printf '%-10s %-12s %12s %12s\n' 'files' 'tests/file' 'before' 'after'
for tests_per_file in "${tests_per_file_counts[@]}"; do
  for file_count in "${file_counts[@]}"; do
    before_timings="$raw_results_dir/before-files-$file_count-tests-$tests_per_file.seconds"
    after_timings="$raw_results_dir/after-files-$file_count-tests-$tests_per_file.seconds"
    before_median=$(sort -n "$before_timings" | sed -n "${median_line}p")
    after_median=$(sort -n "$after_timings" | sed -n "${median_line}p")
    printf '%-10s %-12s %12s %12s\n' "$file_count" "$tests_per_file" "$before_median" "$after_median"
  done
done

trap - ERR
printf '\nResults table:      %s\n' "$results_file"
printf 'Artifacts retained: %s\n' "$benchmark_root"
