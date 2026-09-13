I found one test issue that needs fixing before merge.

## Required fix: respect `BATS_LIBDIR`

The new expectations in `test/suite.bats` hard-code `lib`. That breaks the
[`lib64-install` job](https://github.com/bats-hardened/bats-core/actions/runs/34759651573/job/103730094348),
which installs Bats with `./install.sh /usr/ lib64`. The produced trace is
correctly rooted at `/usr/lib64`; the assertion incorrectly expects `/usr/lib`.

```diff
-  [ "${lines[3]}" = "#  from function \`bats_internal_load' in file ${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash, line 67," ]
-  [ "${lines[4]}" = "#  from function \`bats_load_safe' in file ${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash, line 98," ]
-  [ "${lines[5]}" = "#  from function \`load' in file ${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash, line 150," ]
+  [ "${lines[3]}" = "#  from function \`bats_internal_load' in file ${RELATIVE_BATS_ROOT}${BATS_LIBDIR}/bats-core/test_functions.bash, line 67," ]
+  [ "${lines[4]}" = "#  from function \`bats_load_safe' in file ${RELATIVE_BATS_ROOT}${BATS_LIBDIR}/bats-core/test_functions.bash, line 98," ]
+  [ "${lines[5]}" = "#  from function \`load' in file ${RELATIVE_BATS_ROOT}${BATS_LIBDIR}/bats-core/test_functions.bash, line 150," ]
```

The correction is available as
[`7c85dae0`](https://github.com/bats-hardened/bats-core/commit/7c85dae0).
After applying it, the source-tree tests pass 47/47 and the same suite passes
24/24 from a temporary `lib64` installation.

## What I checked

I reproduced #1186 by running the new fixture before and after the change:

```console
bin/bats test/fixtures/load/failing_load_after_success.bats
```

The fixture intentionally fails all four tests. This is the relevant output
diff:

```diff
 not ok 1 missing helper after successful load
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 2)
-#   `load test_helper' failed
+# (in test file test/fixtures/load/failing_load_after_success.bats, line 3)
+#   `load nonexistent' failed

 not ok 2 helper returning nonzero after successful load
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 8)
+# (from function `source' in file test/fixtures/load/return1.bash, line 1,
+#  from function `bats_internal_load' in file lib/bats-core/test_functions.bash, line 67,
+#  from function `bats_load_safe' in file lib/bats-core/test_functions.bash, line 98,
+#  from function `load' in file lib/bats-core/test_functions.bash, line 150,
+#  in test file test/fixtures/load/failing_load_after_success.bats, line 8)
 #   `load return1' failed

 not ok 3 missing library after successful load
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 12)
-#   `bats_load_library "$BATS_TEST_DIRNAME/test_helper.bash"' failed
+# (in test file test/fixtures/load/failing_load_after_success.bats, line 13)
+#   `bats_load_library "$BATS_TEST_DIRNAME/nonexistent.bash"' failed

 not ok 4 library returning nonzero after successful load
-# (in test file test/fixtures/load/failing_load_after_success.bats, line 18)
+# (from function `source' in file test/fixtures/load/return1.bash, line 1,
+#  from function `bats_internal_load' in file lib/bats-core/test_functions.bash, line 67,
+#  from function `bats_load_library_safe' in file lib/bats-core/test_functions.bash, line 135,
+#  from function `bats_load_library' in file lib/bats-core/test_functions.bash, line 141,
+#  in test file test/fixtures/load/failing_load_after_success.bats, line 18)
 #   `bats_load_library "$BATS_TEST_DIRNAME/return1.bash"' failed
```

This fixes both problems I could reproduce: missing loads no longer blame the
preceding successful load, and a helper returning nonzero retains the source
location where the status originated.

## `test/suite.bats` changes

I initially wasn't sure why this part of the test changed so much, so I ran the
old and new code under Bash 3.2.57, 4.0.44, and 4.1.17:

| Bash | Before | After |
|---|---|---|
| 3.2 | Full helper trace; status 127 | Same trace and status |
| 4.0 | Full helper trace | Same trace |
| 4.1+ | Only the outer `load` frame | Full helper trace |

The old conditional was recording a real Bash-version difference. The PR
makes Bash 4.1+ produce the same full trace as 3.2 and 4.0, so moving the common
assertions out of the conditional is correct. The remaining branch covers the
Bash 3 status-127 exit versus Bash 4+'s `Error while sourcing library loader`.

I also traced why the two assignments are sufficient:

- The loader handles the failure under `if !` and then calls `exit`, so no
  `ERR` trap marks the latest trace as valid.
- `bats_get_failure_stack_trace` therefore falls back to
  `BATS_DEBUG_LASTLAST_STACK_TRACE`.
- Bats' internal paths do not update the DEBUG trace, so explicitly selecting
  `BATS_DEBUG_LAST_STACK_TRACE` at this controlled exit preserves the correct
  user-code trace.

With the `BATS_LIBDIR` correction included, this looks good to me.
