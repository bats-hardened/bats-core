I added a [temporary Windows diagnostic](https://github.com/bats-hardened/bats-core/blob/e7a35c942726851195ebc675d4859503d4f70e1d/.github/workflows/timeout_watchdog_race_diagnostic.yml) against the pre-PR watchdog implementation.

It runs a minimal passing Bats test 1,000 times with a timeout and checks for a surviving `sleep` process after each run.

```shell
@test fast_exit {
  :' '
}
```

Results:

- windows-2025:
  1. 985 orphaned sleeps / 1,000 runs
  2. 895 orphaned sleeps / 1,000 runs
- windows-2022:
  1. job aborted when Win2025 job failed (first test version)
  2. 726 orphaned sleeps / 1,000 runs

So your intuition was right: for this fast-test workload, the behavior is not a rare one-in-many-runs event.

This measures orphaned `sleep` processes, not normal-suite failures.
The old implementation closes the child’s inherited FDs, so regular tests may still pass despite the leak.

It therefore does not by itself prove the exact original failure mechanism, but it does show that the relevant cleanup failure is frequent on both Windows runners.

<details>

<summary>Unfold for test workflow</summary>

### Test workflow

> Change trigger to your branch.

name: Timeout watchdog race diagnostic

on:
workflow_dispatch:
push:
branches:
- wip/upstream-pr/12-PROOF-fix-timeout-watchdog-cleanup

permissions:
contents: read

jobs:
timeout_watchdog_race_diagnostic:
strategy:
fail-fast: false
matrix:
os: ['windows-2022', 'windows-2025']
runs-on: ${{ matrix.os }}
steps:
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
with:
persist-credentials: false

      - name: Measure orphaned timeout sleeps
        shell: bash
        run: |
          timeout=31337
          iterations=1000
          fixture="$RUNNER_TEMP/timeout-watchdog-race.bats"
          printf '%s\n' '@test fast_exit { :' '}' > "$fixture"

          find_timeout_sleeps() {
            ps -ef | awk -v timeout="$timeout" '
              $NF == timeout && $(NF - 1) ~ /(^|[/\\])sleep(\.exe)?$/ { print $2 }
            '
          }

          initial_pids=$(find_timeout_sleeps)
          orphans=0
          for ((iteration = 1; iteration <= iterations; ++iteration)); do
            BATS_TEST_TIMEOUT="$timeout" bin/bats "$fixture" >/dev/null
            iteration_orphans=0
            for pid in $(find_timeout_sleeps); do
              if ! printf '%s\n' "$initial_pids" | grep -Fxq "$pid"; then
                printf 'iteration %d/%d: orphaned sleep %s\n' "$iteration" "$iterations" "$pid"
                kill -KILL "$pid" || true
                ((++iteration_orphans))
                ((++orphans))
              fi
            done
            if ((iteration_orphans == 0)); then
              printf 'iteration %d/%d: no orphan (total: %d)\n' "$iteration" "$iterations" "$orphans"
            else
              printf 'iteration %d/%d: %d orphan(s) (total: %d)\n' \
                "$iteration" "$iterations" "$iteration_orphans" "$orphans"
            fi
          done

          printf 'result: %d orphaned timeout sleep(s) in %d iteration(s)\n' "$orphans" "$iterations"
          ((orphans == 0))


</details>
