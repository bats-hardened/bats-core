I added a [temporary Windows diagnostic](https://github.com/bats-hardened/bats-core/blob/e7a35c942726851195ebc675d4859503d4f70e1d/.github/workflows/timeout_watchdog_race_diagnostic.yml) against the pre-PR watchdog implementation.

It runs this minimal passing Bats test 1,000 times with a timeout and checks for a surviving `sleep` process after each run.

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
