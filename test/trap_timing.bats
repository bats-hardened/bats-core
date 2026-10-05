#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper
fixtures trap_timing

@test "run temporary directory is cleaned up if startup is interrupted" {
  local run_dir="$BATS_TEST_TMPDIR/interrupted-run"

  run env \
    BASH_ENV="$FIXTURE_ROOT/fault_injection.bash" \
    BATS_FAULT_SCRIPT=bats \
    BATS_FAULT_COMMAND='export BATS_WARNING_FILE=*' \
    "$BATS_ROOT/bin/bats" --tempdir "$run_dir" \
    "$BATS_TEST_DIRNAME/fixtures/bats/passing.bats"

  [ "$status" -eq 143 ]
  [ ! -d "$run_dir" ]
}

@test "suite exit trap handler exists when the trap is installed" {
  local source_file="$BATS_ROOT/libexec/bats-core/bats-exec-suite"
  local handler_line trap_line

  handler_line=$(awk '/^bats_suite_exit_trap\(\)/ { print NR; exit }' "$source_file")
  trap_line=$(awk '/^trap bats_suite_exit_trap EXIT$/ { print NR; exit }' "$source_file")

  echo "handler line: $handler_line; trap line: $trap_line"
  ((handler_line < trap_line))
}
