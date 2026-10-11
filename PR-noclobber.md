# Claim parallel slots with noclobber instead of mkdir

After the recent move from files to dirs for parallelization this may sound like an Aprils fools joke - it's not.
You can chuckle though :wink:

## Problem: Ubuntu 26 uses non-mutex Rust mkdir

Ubuntu 26 (LTS) uses a faulty Rust `mkdir` which is not mutex.
The current GitHub Actions `ubuntu-26.04` runner has this broken `mkdir` and starts replacing `ubuntu-latest` on 2026-10-19.

`mkdir` can **exit 0 even though the kernel returned EEXIST** for the underlying mkdir(2) syscall.  
Two processes racing to create the same directory then both believe they succeeded — which silently breaks the classic mkdir-as-mutex shell pattern.

- uutils/coreutils:
  - [issue 13970](https://github.com/uutils/coreutils/issues/13970) opened 2026-08-16
  - [PR 13986](https://github.com/uutils/coreutils/pull/13986) merged 2026-08-28
  - [Release notes for 0.11.0](https://github.com/uutils/coreutils/releases/tag/0.11.0) released 2026-08-31; mention PR 13986

With Ubuntu 26 being LTS - `mkdir` can't be trusted on random systems or in images for years to come.

## Solution: Create file with set -C, which uses O_EXCL.

The important distinction is not “directories versus files”; it is whether the **claim operation itself** reaches the kernel as an exclusive-create syscall.

The shell uses a kernel primitive flag to write a file, thus avoiding the broken Rust `mkdir`.
```bash
if (set -C; : > "$BATS_SEMAPHORE_DIR/slot-$slot") 2>/dev/null; then
  # this process owns the slot
fi
```

What each piece means:

- `set -C` enables Bash’s `noclobber` option.
- `:` is Bash’s no-op command.
- `> slot-N` is performed by Bash before `:` runs.
- The parentheses make it a subshell, so `set -C` affects only this one attempt.

With `noclobber`, Bash passes the pathname to one openat() call with O_CREAT|O_EXCL.

If the file does not exist: the kernel creates it and returns an open file descriptor.

If it already exists: the kernel returns EEXIST; Bash makes the redirection fail.
The kernel performs pathname lookup and exclusive creation as one atomic operation.

Bash redirection only exists for files, so this can't use dirs.

---

> [Quote](https://github.com/jcosborn/qex/commit/725ee056eb522a618581b219227c42d7879a095e)
> The Rust kids rewrote a 50-year-old wheel and it came back square; mkdir as a mutex is older than most of them.

I would chuckle, but I'm a bit embarrassed because I suggested using dirs; who'd think `mkdir` is broken.

This occurred seemingly at random in job [linux (ubuntu-26.04, BATS_PARALLEL_BINARY_NAME=rush)](https://github.com/bats-core/bats-core/actions/runs/38061871436/job/114241607307?pr=1269#step:4:95) and a job re-run and other test runs passed.

Error Output:
```text

not ok 81 Parallel mode works on MacOS with over subscription (issue #433)
# (in test file test/bats.bats, line 850)
#   `[[ "$output" != *"No such file or directory"* ]] || exit 1 # ensure failures are detected with old bash' failed
# Last output:
# 1..4
# rmdir: failed to remove '/tmp/bats-run-027QpI/semaphores/slot-0': No such file or directory
# ok 1 1
# ok 2 2
# ok 3 11
# ok 4 12
```

I tracked this down with test series where it occurred between 2/1000 and ~300/1000 times (different debug setups) and only on Ubuntu 26 runners.


