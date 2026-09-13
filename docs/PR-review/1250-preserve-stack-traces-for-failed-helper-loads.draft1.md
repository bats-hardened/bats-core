# Review of PR #1250

Thanks for the fix. I reproduced #1186 and reviewed the changed tracing
behavior on Bash 3.2.57, 4.0.44, 4.1.17, and 5.x. The implementation looks
sound; one test-path correction is needed for non-default installations.

## Why the fix works

`load` and `bats_load_library` handle a nonzero result under `if !` and then
call `exit 1`. No `ERR` trap runs on this path, so nothing normally marks the
latest DEBUG trace as trustworthy.

The selection contract in `lib/bats-core/tracing.bash` is:

```bash
if [[ -n "${BATS_DEBUG_LAST_STACK_TRACE_IS_VALID:-}" ]]; then
  stack_trace_var=BATS_DEBUG_LAST_STACK_TRACE
else
  stack_trace_var=BATS_DEBUG_LASTLAST_STACK_TRACE
fi
```

Bats' internal paths are excluded from DEBUG tracing. At the controlled exit
in these loader functions, `BATS_DEBUG_LAST_STACK_TRACE` therefore still
contains the relevant user-code trace. Marking it valid prevents the reporter
from falling back to the preceding trace.

## Before and after

I compared both implementations with:

```console
bin/bats test/fixtures/load/failing_load_after_success.bats
```

The fixture intentionally reports four failures; its diagnostics are what the
regression tests inspect.

For a missing helper, the old output blamed the preceding successful load:

```diff
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 2)
-#   `load test_helper' failed
+# (in test file test/fixtures/load/failing_load_after_success.bats, line 3)
+#   `load nonexistent' failed
```

For a helper returning nonzero, the new output retains the origin and
propagation path:

```diff
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 8)
+# (from function `source' in file test/fixtures/load/return1.bash, line 1,
+#  from function `bats_internal_load' in file lib/bats-core/test_functions.bash, line 67,
+#  from function `bats_load_safe' in file lib/bats-core/test_functions.bash, line 98,
+#  from function `load' in file lib/bats-core/test_functions.bash, line 150,
+#  in test file test/fixtures/load/failing_load_after_success.bats, line 8)
 #   `load return1' failed
```

The `bats_load_library` cases show the same corrections: the missing library
is attributed to line 13 instead of the successful load on line 12, and a
nonzero return retains `return1.bash:1` as its first frame.

## Why the Bash-version handling can be simplified

Before this PR, the failed-source fixture produced different traces:

| Bash | Old behavior |
|---|---|
| 3.2 | Full helper trace; exits while sourcing with status 127 |
| 4.0 | Full helper trace; `source` returns nonzero to the loader |
| 4.1+ | Only the outer `load test_helper` frame |

On Bash 4.1+, the correct helper trace was in
`BATS_DEBUG_LAST_STACK_TRACE`, but the unset validity marker made Bats select
`BATS_DEBUG_LASTLAST_STACK_TRACE`. The new assignment makes Bash 4.1+ retain
the same full trace already seen on 3.2 and 4.0.

The common stack assertions can consequently move outside the version check.
The remaining conditional is still necessary: Bash 3 exits during `source`
with status 127, whereas Bash 4+ returns through the loader and prints the
additional `Error while sourcing library loader` message.

## Required test-path correction

The updated `test/suite.bats` assertions initially hardcoded `lib`:

```diff
-${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash
+${RELATIVE_BATS_ROOT}${BATS_LIBDIR}/bats-core/test_functions.bash
```

The `lib64-install` job installs Bats with:

```console
sudo ./install.sh /usr/ lib64
```

Its trace correctly uses `/usr/lib64/bats-core/test_functions.bash`; the
hardcoded assertion expects `/usr/lib/bats-core/test_functions.bash`:

```text
not ok 429 errors when loading common helper from multiple tests in a suite
# `[ "${lines[3]}" = "...${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash..." ]' failed
# Last output:
#  from function `bats_internal_load' in file /usr/lib64/bats-core/test_functions.bash, line 67,
```

Commit [`7c85dae0`](https://github.com/bats-hardened/bats-core/commit/7c85dae0)
uses `${BATS_LIBDIR}` in all three affected assertions. With that correction:

- `bin/bats test/load.bats test/suite.bats`: 47/47 passed.
- Temporary `lib64` installation: 24/24 suite tests passed.
- `git diff --check`: clean.

With the test-path correction included, this looks good to me.
