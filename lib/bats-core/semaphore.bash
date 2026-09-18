#!/usr/bin/env bash

bats_parallel_diagnostic() {
  [[ -n "${BATS_PARALLEL_DIAGNOSTICS_FILE:-}" ]] || return 0
  printf '%s pid=%s ppid=%s semaphore %s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "$PPID" "$*" >>"$BATS_PARALLEL_DIAGNOSTICS_FILE"
}

# setup the semaphore environment for the loading file
bats_semaphore_setup() {
  export -f bats_parallel_diagnostic
  export BATS_SEMAPHORE_DIR="$BATS_RUN_TMPDIR/semaphores"
  bats_parallel_diagnostic "setup implementation=mkdir slots=$BATS_SEMAPHORE_NUMBER_OF_SLOTS dir=$BATS_SEMAPHORE_DIR"
}

# $1 - output directory for stdout/stderr
# $@ - command to run
# run the given command in a semaphore
# block when there is no free slot for the semaphore
# when there is a free slot, run the command in background
# gather the output of the command in files in the given directory
bats_semaphore_run() {
  local output_dir=$1
  shift
  local semaphore_slot
  bats_parallel_diagnostic "slot requested output=$output_dir"
  semaphore_slot=$(bats_semaphore_acquire_slot)
  bats_parallel_diagnostic "slot acquired slot=$semaphore_slot output=$output_dir"
  bats_semaphore_release_wrapper "$output_dir" "$semaphore_slot" "$@" &
  bats_parallel_diagnostic "worker started worker=$! slot=$semaphore_slot output=$output_dir"
  printf "%d\n" "$!"
}

# $1 - output directory for stdout/stderr
# $@ - command to run
# this wraps the actual function call to install some traps on exiting
bats_semaphore_release_wrapper() {
  local output_dir="$1"
  local semaphore_name="$2"
  shift 2 # all other parameters will be use for the command to execute

  # shellcheck disable=SC2064 # we want to expand the semaphore_name right now!
  trap "status=$?; bats_semaphore_release_slot '$semaphore_name'; exit $status" EXIT

  mkdir -p "$output_dir"
  "$@" 2>"$output_dir/stderr" >"$output_dir/stdout"
  local status=$?

  # bash bug: the exit trap is not called for the background process
  bats_semaphore_release_slot "$semaphore_name"
  trap - EXIT # avoid calling release twice
  return $status
}

# block until a semaphore slot becomes free
# prints the number of the slot that it received
bats_semaphore_acquire_slot() {
  mkdir -p "$BATS_SEMAPHORE_DIR"
  local slot
  while true; do
    for ((slot = 0; slot < BATS_SEMAPHORE_NUMBER_OF_SLOTS; ++slot)); do
      # mkdir is atomic: only one process can successfully claim a given slot.
      if mkdir "$BATS_SEMAPHORE_DIR/slot-$slot" 2>/dev/null; then
        printf "%d\n" "$slot"
        return 0
      fi
    done
    sleep 1
  done
}

bats_semaphore_release_slot() {
  # we don't need to lock this, since only our process owns this file
  # and freeing a semaphore cannot lead to conflicts with others
  rmdir "$BATS_SEMAPHORE_DIR/slot-$1" # this will fail if we had not acquired a semaphore!
  bats_parallel_diagnostic "slot released slot=$1"
}
