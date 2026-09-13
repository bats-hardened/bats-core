## PR fix

todo: Add Markdown diff view of fix in commit `7c85dae0` and explain why
otherwise the `lib64-install` tests (bettwe wroding) in CI pipelines will fail.

FYI, here's the log output of failure:
```text
2026-09-13T13:27:06.4946537Z ok 428 a failing test in a suite results in an error exit code # in 155 ms
2026-09-13T13:27:06.5574858Z not ok 429 errors when loading common helper from multiple tests in a suite # in 46 ms
2026-09-13T13:27:06.5581809Z # (in test file test/suite.bats, line 63)
2026-09-13T13:27:06.5594962Z #   `[ "${lines[3]}" = "#  from function \`bats_internal_load' in file ${RELATIVE_BATS_ROOT}lib/bats-core/test_functions.bash, line 67," ]' failed
2026-09-13T13:27:06.5618169Z # Last output:
2026-09-13T13:27:06.5619831Z # 1..1
2026-09-13T13:27:06.5620219Z # not ok 1 bats-gather-tests
2026-09-13T13:27:06.5620890Z # # (in file test/fixtures/suite/errors_in_multiple_load/test_helper.bash, line 1,
2026-09-13T13:27:06.5621705Z # #  from function `bats_internal_load' in file /usr/lib64/bats-core/test_functions.bash, line 67,
2026-09-13T13:27:06.5622339Z # #  from function `bats_load_safe' in file /usr/lib64/bats-core/test_functions.bash, line 98,
2026-09-13T13:27:06.5622887Z # #  from function `load' in file /usr/lib64/bats-core/test_functions.bash, line 150,
2026-09-13T13:27:06.5623396Z # #  in test file test/fixtures/suite/errors_in_multiple_load/a.bats, line 1)
2026-09-13T13:27:06.5623805Z # #   `load test_helper' failed
2026-09-13T13:27:06.5624459Z # # /home/runner/work/bats-core/bats-core/test/fixtures/suite/errors_in_multiple_load/test_helper.bash: line 1: call-to-undefined-command: command not found
2026-09-13T13:27:06.5625760Z # # Error while sourcing library loader at '/home/runner/work/bats-core/bats-core/test/fixtures/suite/errors_in_multiple_load/test_helper.bash'
2026-09-13T13:27:06.7358149Z ok 430 running an ad-hoc suite by specifying multiple test files # in 157 ms
```

## Summary

### Before vs. after

todo: Add Markdown diff view of `before-PR1250.txt` vs. `after-PR1250.txt`
and mention that `bin/bats test/fixtures/load/failing_load_after_success.bats`
produces those before/after outputs and why new one is better/correct.

## Explain chenge to bash version handling in `test/suite.bats`

todo

## bits and bites

contract for BATS_DEBUG_LAST_STACK_TRACE is in lib/bats-core/tracing.bash:348
