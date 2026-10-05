#!/usr/bin/env bash

# setup the semaphore environment for the loading file
bats_semaphore_setup() {
  export BATS_SEMAPHORE_DIR="$BATS_RUN_TMPDIR/semaphores"
}

# $1 - output directory for stdout/stderr
# $@ - command to run
# run the given command in a semaphore
# block when there is no free slot for the semaphore
# when there is a free slot, run the command in background
# gather the output of the command in files in the given directory
bats_semaphore_run() {
  local output_dir=$1
  local wrapper_pid
  shift

  # Before Bash 5.2, an EXIT trap can run after this function's local scope is gone.
  BATS_SEMAPHORE_ACQUISITION_SLOT=
  # `trap -p` prints a reusable trap definition, including its action.
  BATS_SEMAPHORE_SAVED_EXIT_TRAP=$(trap -p EXIT)
  if [[ -n $BATS_SEMAPHORE_SAVED_EXIT_TRAP ]]; then
    # Extract the trap action.
    BATS_SEMAPHORE_SAVED_EXIT_TRAP=$(
      eval "set -- ${BATS_SEMAPHORE_SAVED_EXIT_TRAP#trap -- }"
      printf '%s' "$1"
    )
  fi
  trap bats_semaphore_acquisition_exit_trap EXIT
  bats_semaphore_acquire_slot

  bats_semaphore_release_wrapper "$output_dir" "$BATS_SEMAPHORE_ACQUISITION_SLOT" "$@" &
  wrapper_pid=$!

  BATS_SEMAPHORE_ACQUISITION_SLOT=
  if [[ -n $BATS_SEMAPHORE_SAVED_EXIT_TRAP ]]; then
    # shellcheck disable=SC2064 # Restore the action saved from the caller's EXIT trap.
    trap "$BATS_SEMAPHORE_SAVED_EXIT_TRAP" EXIT
  else
    trap - EXIT
  fi
  unset BATS_SEMAPHORE_ACQUISITION_SLOT BATS_SEMAPHORE_SAVED_EXIT_TRAP
  printf "%d\n" "$wrapper_pid"
}

bats_semaphore_acquisition_exit_trap() {
  local status=$?
  trap - EXIT
  if [[ -n $BATS_SEMAPHORE_ACQUISITION_SLOT ]]; then
    bats_semaphore_release_slot "$BATS_SEMAPHORE_ACQUISITION_SLOT" || true
  fi
  if [[ -n $BATS_SEMAPHORE_SAVED_EXIT_TRAP ]]; then
    eval "$BATS_SEMAPHORE_SAVED_EXIT_TRAP"
  fi
  exit "$status"
}

# $1 - output directory for stdout/stderr
# $@ - command to run
# this wraps the actual function call to install some traps on exiting
bats_semaphore_release_wrapper() {
  local output_dir="$1"
  local semaphore_name="$2"
  shift 2 # all other parameters will be use for the command to execute

  trap 'status=$?; bats_semaphore_release_slot "$semaphore_name"; exit "$status"' EXIT

  mkdir -p "$output_dir"
  "$@" 2>"$output_dir/stderr" >"$output_dir/stdout"
  local status=$?

  # bash bug: the exit trap is not called for the background process
  bats_semaphore_release_slot "$semaphore_name"
  trap - EXIT # avoid calling release twice
  return $status
}

# block until a semaphore slot becomes free
# stores the number of the acquired slot in BATS_SEMAPHORE_ACQUISITION_SLOT
bats_semaphore_acquire_slot() {
  mkdir -p "$BATS_SEMAPHORE_DIR"
  local slot
  while true; do
    for ((slot = 0; slot < BATS_SEMAPHORE_NUMBER_OF_SLOTS; ++slot)); do
      # POSIX directory operations are atomic and serializable, so only one
      # process can successfully create a given slot directory.
      if mkdir "$BATS_SEMAPHORE_DIR/slot-$slot" 2>/dev/null; then
        BATS_SEMAPHORE_ACQUISITION_SLOT=$slot
        return 0
      fi
    done
    sleep 1
  done
}

bats_semaphore_release_slot() {
  # We don't need additional synchronization: only our process owns this slot
  # directory, and releasing a slot cannot conflict with another process.
  rmdir "$BATS_SEMAPHORE_DIR/slot-$1" # fails if we did not acquire this slot
}
