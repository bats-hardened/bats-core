# This file is loaded through BASH_ENV to inject a failure at an exact command
# boundary in another Bash process.
set -T

_bats_inject_fault() {
  local command=$1

  [[ ${0##*/} == "${BATS_FAULT_SCRIPT:-}" ]] || return 0
  # shellcheck disable=SC2053 # BATS_FAULT_COMMAND is intentionally a pattern.
  [[ $command == ${BATS_FAULT_COMMAND:-} ]] || return 0

  trap - DEBUG
  kill -TERM "$$"
}

trap '_bats_inject_fault "$BASH_COMMAND"' DEBUG
