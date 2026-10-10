# Investigation note: intermittent semaphore-slot cleanup failure

## Summary

An intermittent CI failure was observed in the Linux matrix job `linux (ubuntu-26.04, BATS_PARALLEL_BINARY_NAME=rush)` in Actions run [38061871436](https://github.com/bats-core/bats-core/actions/runs/38061871436/job/114241607307).

The failure was test 81 in `test/bats.bats`:

```text
Parallel mode works on MacOS with over subscription (issue #433)
```

Despite the historical test name, this is not a macOS-only test.  It runs on any platform on which the configured cross-file parallel runner is available. The failing job ran on Ubuntu 26.04 with `rush`.

The failure is important because it indicates a problem in the semaphore implementation used for parallel execution, not a problem with the test's assertion.

## Exact observed failure

The nested `bats -j 2` command run by the test produced:

```text
rmdir: failed to remove '/tmp/bats-run-027QpI/semaphores/slot-0': No such file or directory
```

The test deliberately treats that text as a failure:

```bash
[[ "$output" != *"No such file or directory"* ]] || exit 1
```

Therefore:

* A normal `rmdir` succeeds and prints nothing; the test passes.
* If the slot directory is already absent, `rmdir` writes the diagnostic above
  to stderr; it becomes part of the nested command's captured output; the test   exits 1 intentionally.

The four fixture tests themselves completed successfully.  The outer regression test failed because of the leaked cleanup diagnostic.

## Relevant implementation

`lib/bats-core/semaphore.bash` represents a semaphore slot as a directory.

1. `bats_semaphore_acquire_slot` claims a slot with:

   ```bash
   mkdir "$BATS_SEMAPHORE_DIR/slot-$slot"
   ```

2. `bats_semaphore_release_slot` releases it with:

   ```bash
   rmdir "$BATS_SEMAPHORE_DIR/slot-$1"
   ```

The slot acquisition was changed in commit `e5b6e1b1` (`parallel: claim semaphore slots atomically`, 2026-09-18).  Before that change, slots were files, claimed through a check/`touch` sequence protected by `flock` or `shlock`, and released with `rm`.

`mkdir` is the right primitive for an atomic claim: two processes cannot both successfully create the same directory.  This failure does **not** show that the filesystem violates that guarantee.

It shows that, by the time a release path invoked `rmdir`, the directory it expected to own had already disappeared.  The remaining question is which control-flow path removed it early or attempted release twice.

## Why it is intermittent

The failure only occurs if the premature/duplicate removal wins the timing race before the affected release calls `rmdir`.  When that does not happen, the directory is present, `rmdir` succeeds silently, and the same test passes.

At the time of the failure:

* the identical `rush` configuration passed on Ubuntu 22.04 and 24.04;
* it also passed on macOS 15 and 26;
* a subsequent run of the same Ubuntu 26.04 + `rush` configuration passed.

Ubuntu 26.04 was newly added to the matrix shortly before the failing run, so it exposed the issue.  That result alone does not establish an Ubuntu-specific bug; it is consistent with a timing-sensitive race.

## Scope relative to PR #1269

PR #1269 does not change `lib/bats-core/semaphore.bash` or the slot algorithm. It does modify `reentrant_run` test-harness variable preservation because several Bats-owned variables became readonly.  Since the failing regression test uses `reentrant_run`, that is worth keeping in mind while reproducing, but there is no direct semaphore-code change in the PR.

The atomic-directory semaphore implementation came from upstream separately and was already present in the merge base used by the PR.

## Reproduction starting point

Run the specific regression test while selecting `rush`:

```bash
BATS_PARALLEL_BINARY_NAME=rush \
  bin/bats --print-output-on-failure \
  --filter 'Parallel mode works on MacOS with over subscription' \
  test/bats.bats
```

Because it is intermittent, repeat this command many times and retain the output from any failure.  Do not conclude that one successful run disproves the race.

The test starts a nested `bats -j 2` run over `test/fixtures/bats/issue-433/`; the fixture has two files containing two sleeping tests each.  That gives the semaphore code concurrent work while keeping the reproduction small.

## Suggested next investigation

Instrument only a temporary working tree, then remove the instrumentation before proposing a fix.  Log the following at every successful acquisition and every release attempt:

* `BASHPID`, parent PID, and command/process role;
* `BATS_RUN_TMPDIR`, `BATS_SEMAPHORE_DIR`, and slot number;
* whether `mkdir` succeeded;
* whether `rmdir` succeeded;
* whether the release occurred through the normal path or the `EXIT` trap.

The decisive evidence will associate both removals (or the early removal and the later failed removal) with concrete processes and code paths.  In particular, verify the interaction between the normal release call and the `EXIT` trap in `bats_semaphore_release_wrapper`, rather than weakening this regression test or suppressing `rmdir` stderr.

## Do not paper over the signal

Do not change the test to ignore `No such file or directory`, and do not add `2>/dev/null` to the release operation as a final fix.  Either would hide a broken semaphore ownership/lifecycle invariant and could allow excess parallelism or other hard-to-diagnose failures.
