#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

@test "semaphore cleanup trap preserves the command status" {
  run bash -c '
    set -e
    source "$1"

    output_dir=$2/output
    BATS_SEMAPHORE_DIR=$2/semaphores
    mkdir -p "$BATS_SEMAPHORE_DIR/slot-0"

    run_with_caller_status() {
      local status=0
      bats_semaphore_release_wrapper "$output_dir" 0 false
    }

    run_with_caller_status
  ' _ "$BATS_ROOT/$BATS_LIBDIR/bats-core/semaphore.bash" "$BATS_TEST_TMPDIR"

  echo "semaphore wrapper status: $status"
  [ "$status" -eq 1 ]
}

@test "semaphore slot is released when startup is interrupted" {
  local semaphore_dir="$BATS_TEST_TMPDIR/semaphores"

  run bash -c '
    set -T
    source "$1"

    BATS_RUN_TMPDIR=$2
    BATS_SEMAPHORE_NUMBER_OF_SLOTS=1
    bats_semaphore_setup

    trap '\''
      if [[ $BASH_COMMAND == bats_semaphore_release_wrapper* ]]; then
        trap - DEBUG
        exit 23
      fi
    '\'' DEBUG

    bats_semaphore_run "$2/output" false
  ' _ "$BATS_ROOT/$BATS_LIBDIR/bats-core/semaphore.bash" "$BATS_TEST_TMPDIR"

  [ "$status" -eq 23 ]
  [ ! -d "$semaphore_dir/slot-0" ]
}

@test "semaphore startup cleanup preserves the caller's EXIT trap" {
  local semaphore_dir="$BATS_TEST_TMPDIR/semaphores"
  local exit_trap_file="$BATS_TEST_TMPDIR/exit-trap-ran"

  run bash -c '
    set -T
    source "$1"

    BATS_RUN_TMPDIR=$2
    BATS_SEMAPHORE_NUMBER_OF_SLOTS=1
    bats_semaphore_setup
    trap "touch \"$3\"" EXIT

    trap '\''
      if [[ $BASH_COMMAND == bats_semaphore_release_wrapper* ]]; then
        trap - DEBUG
        exit 23
      fi
    '\'' DEBUG

    bats_semaphore_run "$2/output" false
  ' _ "$BATS_ROOT/$BATS_LIBDIR/bats-core/semaphore.bash" "$BATS_TEST_TMPDIR" "$exit_trap_file"

  [ "$status" -eq 23 ]
  [ -e "$exit_trap_file" ]
  [ ! -d "$semaphore_dir/slot-0" ]
}
