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
  local ready_pipe="$output_dir/semaphore-ready"
  local wrapper_pid
  shift

  # EXIT traps may run after this function's local scope has been unwound.
  # Keep the acquisition state global until the wrapper has installed its
  # cleanup trap.
  semaphore_slot=''
  saved_exit_trap=$(trap -p EXIT)
  trap bats_semaphore_acquisition_exit_trap EXIT
  bats_semaphore_acquire_slot

  mkfifo "$ready_pipe"
  bats_semaphore_release_wrapper "$output_dir" "$semaphore_slot" "$@" >"$ready_pipe" &
  wrapper_pid=$!

  if ! IFS= read -r <"$ready_pipe"; then
    bats_semaphore_release_slot "$semaphore_slot" || true
  fi
  rm -f "$ready_pipe"

  semaphore_slot=
  if [[ -n $saved_exit_trap ]]; then
    eval "$saved_exit_trap"
  else
    trap - EXIT
  fi
  unset semaphore_slot saved_exit_trap
  printf "%d\n" "$wrapper_pid"
}

bats_semaphore_acquisition_exit_trap() {
  local status=$?
  trap - EXIT
  if [[ -n $semaphore_slot ]]; then
    bats_semaphore_release_slot "$semaphore_slot" || true
  fi
  if [[ -n $saved_exit_trap ]]; then
    (eval "$saved_exit_trap"; exit "$status")
    exit $?
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

  trap 'status=$?; [[ -z $semaphore_name ]] || bats_semaphore_release_slot "$semaphore_name"; exit $status' EXIT
  printf 'ready\n'
  mkdir -p "$output_dir"
  "$@" 2>"$output_dir/stderr" >"$output_dir/stdout"
  local status=$?

  # bash bug: the exit trap is not called for the background process
  bats_semaphore_release_slot "$semaphore_name"
  trap - EXIT # avoid calling release twice
  return $status
}

# block until a semaphore slot becomes free
# stores the number of the acquired slot in semaphore_slot
bats_semaphore_acquire_slot() {
  mkdir -p "$BATS_SEMAPHORE_DIR"
  local slot
  while true; do
    for ((slot = 0; slot < BATS_SEMAPHORE_NUMBER_OF_SLOTS; ++slot)); do
      semaphore_slot=$slot
      # POSIX directory operations are atomic and serializable, so only one
      # process can successfully create a given slot directory.
      if mkdir "$BATS_SEMAPHORE_DIR/slot-$slot" 2>/dev/null; then
        return 0
      fi
      semaphore_slot=
    done
    sleep 1
  done
}

bats_semaphore_release_slot() {
  # We don't need additional synchronization: only our process owns this slot
  # directory, and releasing a slot cannot conflict with another process.
  rmdir "$BATS_SEMAPHORE_DIR/slot-$1" # fails if we did not acquire this slot
}
