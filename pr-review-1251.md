Looks good to me — I support this change as it is.

### Testing

I ran the full GitHub Actions test workflow (different Bash versions, macOS and Windows runners). `./shellcheck.sh` also passed.

### Implementation

I considered a few alternative ways to structure the short-option unpacking, but none looked better than the current implementation. In detail:

- Keeping the old preprocessing pass unchanged would still unpack filenames after `--`, defeating the purpose of the terminator.
- Teaching that preprocessing pass to stop at the first `--` looks simpler, but it cannot tell a terminator from an option value. For example, in `bats -f -- -ct test.bats`, the first `--` belongs to `-f`, and `-ct` still needs to be parsed as bundled options.
- Handling bundles in another `case` branch is possible, but introduces subtle pattern-order and control-flow requirements and makes the already substantial option switch harder to follow.

Expanding only the argument currently being parsed avoids those problems. The current placement immediately before the `case` looks like the clearest and least error-prone option: normalize one argument, then dispatch it.

### Why this is useful

`--` is the standard way to separate options from operands, and it fixes some real edge cases for Bats users:

- A glob such as `bats -- *.bats` can safely include a file named `-regression.bats`.
- Option-looking filenames can be run directly, for example `bats -- --help` or `bats -- -tr`.
- Dash-prefixed directories work too, including `bats -r -- -nightly-tests`.
- Wrapper scripts can safely use `bats -- "$test_path"` without first checking whether a user-provided or generated path starts with `-`.

The implementation, documentation, and regression coverage all look solid. Thanks for the contribution!
