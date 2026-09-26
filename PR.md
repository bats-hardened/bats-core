# PR title

fix: support parallel self-tests with `--jobs`

# PR body

[Fixes #1225][issue].

[Closes #1234][alternative-pr].

## Problem

Running the bats-core test suite with `--jobs` exposed failures that the existing
parallel CI job did not cover:

- Ctrl-C tests shared suite-level latch state and interfered with each other.
- Bash starts asynchronous jobs with `SIGINT` ignored when job control is off.
  Nested Bats processes launched by the semaphore worker inherited that state.
- Recursive Bats invocations relied on the exported `bats_readlinkf` function.
  Rush does not preserve exported Bash functions.

CI used `BATS_NUMBER_OF_PARALLEL_JOBS=2`, which is inherited by nested Bats
invocations and makes the Ctrl-C tests skip. That differs intentionally from
passing `--jobs 2` to the outer invocation only.

## Changes

- Run the full Linux self-test suite with `--jobs 2` in the Rush CI jobs.
- Isolate Ctrl-C coordination under `BATS_TEST_TMPDIR`.
- Bound the Ctrl-C hang test's latch wait and clean up a stuck process on timeout.
- Restore the default `SIGINT` disposition in semaphore workers before running a
  test command.
- Make the internal launcher derive `BATS_LIBEXEC` from its own location.
- Stop exporting `bats_readlinkf` and add regression coverage for recursive Bats
  invocation without inherited launcher state.

## Why not export `BATS_NUMBER_OF_PARALLEL_JOBS`?

Exporting it when `--jobs` is used, as proposed in #1234, changes the behavior of
nested Bats invocations. In the self-test suite it also activates skip guards in
the Ctrl-C tests, hiding the failures reported in #1225.

This keeps the existing distinction:

- `--jobs N`: parallelize this invocation.
- `BATS_NUMBER_OF_PARALLEL_JOBS=N`: also configure nested invocations through the
  inherited environment.

## Verification

- [GitHub Actions][ci-run]: full suite passed with Rush and `--jobs 2` on Ubuntu
  22.04 and 24.04.
- [Gentoo ebuild test][ebuild]: full suite passed with GNU Parallel,
  `--jobs "$(get_nproc)"`, and no `BATS_NUMBER_OF_PARALLEL_JOBS` override, using
  the [proposed bats-core branch][test-branch].
- Existing environment-variable-based parallel CI coverage remains in place.

- [ ] I have reviewed the [Contributor Guidelines][contributor].
- [ ] I have reviewed the [Code of Conduct][coc] and agree to abide by it.

[issue]: https://github.com/bats-core/bats-core/issues/1225
[alternative-pr]: https://github.com/bats-core/bats-core/pull/1234
[ci-run]: https://github.com/bats-hardened/bats-core/actions/runs/36197956971
[ebuild]: https://github.com/bats-hardened/gentoo-tests/blob/main/local_overlay/dev-util/bats/bats-9999.ebuild
[test-branch]: https://github.com/bats-hardened/bats-core/tree/PR-review/fork/henning-schild/henning/staging0.ALTERNATIVE.new
[contributor]: https://github.com/bats-core/bats-core/blob/master/docs/CONTRIBUTING.md
[coc]: https://github.com/bats-core/bats-core/blob/master/docs/CODE_OF_CONDUCT.md
