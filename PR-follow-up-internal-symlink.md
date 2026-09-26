### Known limitation

- `cd -P` resolves symlinked directories, but not a symlinked internal launcher.
- Symlinking `libexec/bats-core/bats` onto `PATH` therefore produces a wrong `BATS_LIBEXEC`.

### Why this PR does not handle it

- `libexec/bats-core/bats` is internal; the supported entry point is `bin/bats`.
- `bin/bats` already resolves symlinks and invokes the real internal launcher.
- Triggering the bug requires deliberately bypassing that entry point and symlinking an internal implementation file.
- The [experimental fix](https://github.com/bats-hardened/bats-core/commit/3a6737eb0c6613e2bbb6ec59adba26f4f59b75d2) adds another symlink walker, relative-target handling, loop protection, `readlink` portability concerns, and tests.
- Limitations of bash on macOS make such symlink walkers quite complex

That complexity is not justified for an unsupported invocation path.
