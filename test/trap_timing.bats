#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper
fixtures trap_timing

@test "timeout watchdog is cleaned up if setup is interrupted" {
  local timeout=3
  SECONDS=0

  run env \
    BASH_ENV="$FIXTURE_ROOT/fault_injection.bash" \
    BATS_FAULT_SCRIPT=bats-exec-test \
    BATS_FAULT_COMMAND='BATS_TEST_COMPLETED=' \
    BATS_FAULT_ACTION=exit \
    BATS_TEST_TIMEOUT=$timeout \
    "$BATS_ROOT/bin/bats" "$BATS_TEST_DIRNAME/fixtures/bats/passing.bats"

  echo "elapsed: $SECONDS seconds"
  ((SECONDS < timeout))
}

@test "run temporary directory is cleaned up if startup is interrupted" {
  local run_dir="$BATS_TEST_TMPDIR/interrupted-run"

  run env \
    BASH_ENV="$FIXTURE_ROOT/fault_injection.bash" \
    BATS_FAULT_SCRIPT=bats \
    BATS_FAULT_COMMAND='export BATS_WARNING_FILE=*' \
    BATS_FAULT_ACTION=TERM \
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

@test "install_libs temporary directory is cleaned up if startup is interrupted" {
  local capture_file="$BATS_TEST_TMPDIR/install-libs-tmpdir"
  local temporary_dir

  run env \
    TMPDIR="$BATS_TEST_TMPDIR" \
    BASH_ENV="$FIXTURE_ROOT/fault_injection.bash" \
    BATS_FAULT_SCRIPT=install_libs.sh \
    BATS_FAULT_COMMAND='USAGE=*' \
    BATS_FAULT_CAPTURE=TMPDIR \
    BATS_FAULT_CAPTURE_FILE="$capture_file" \
    BATS_FAULT_ACTION=TERM \
    bash "$BATS_ROOT/docker/install_libs.sh" support 0.3.0

  read -r temporary_dir <"$capture_file"
  [ "$status" -eq 143 ]
  [ ! -d "$temporary_dir" ]
}

@test "install_libs exits after handling TERM" {
  local continued_file="$BATS_TEST_TMPDIR/continued-after-term"

  run env \
    TMPDIR="$BATS_TEST_TMPDIR" \
    BASH_ENV="$FIXTURE_ROOT/fault_injection.bash" \
    BATS_FAULT_SCRIPT=install_libs.sh \
    BATS_FAULT_COMMAND='*# -ne 2*' \
    BATS_FAULT_ACTION=TERM-then-mark \
    BATS_FAULT_CONTINUED_FILE="$continued_file" \
    bash "$BATS_ROOT/docker/install_libs.sh" support 0.3.0

  [ ! -e "$continued_file" ]
}
