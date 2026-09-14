# PR #1249 duplicate-detection performance

The benchmarks compare three implementations:

- `23414861`: upstream/master
- `8ecffdab`: deferred duplicate detection using `sort`
- `bc5c0eea`: deferred duplicate detection using `awk`

Both benchmarks use `bats -c`, which exercises test discovery and duplicate detection without adding test-execution time. Each alternative was measured in three runs paired with upstream/master. Because upstream was measured in both comparisons, its column below uses the median of all six measurements for each workload. Each alternative column uses its respective three-run median.

| Scenario | Files | Tests/file | Total tests | Upstream `23414861` | Sort `8ecffdab` | `awk` `bc5c0eea` |
|---|---:|---:|---:|---:|---:|---:|
| Large file | 1 | 500 | 500 | 1.482 s | 1.470 s | 1.348 s |
| Large file | 1 | 1,000 | 1,000 | 3.295 s | 2.915 s | 2.621 s |
| Large file | 1 | 2,000 | 2,000 | 8.184 s | 5.835 s | 5.164 s |
| Large file | 1 | 4,000 | 4,000 | 22.175 s | 11.619 s | 10.542 s |
| Many files | 100 | 1 | 100 | 0.667 s | 0.655 s | 0.660 s |
| Many files | 500 | 1 | 500 | 3.288 s | 3.262 s | 3.354 s |
| Many files | 1,000 | 1 | 1,000 | 6.659 s | 6.652 s | 6.717 s |
| Many files | 100 | 2 | 200 | 0.951 s | 1.246 s | 1.144 s |
| Many files | 500 | 2 | 1,000 | 4.755 s | 6.295 s | 5.722 s |
| Many files | 1,000 | 2 | 2,000 | 9.596 s | 12.704 s | 11.769 s |
| Many files | 100 | 5 | 500 | 1.845 s | 2.198 s | 2.096 s |
| Many files | 500 | 5 | 2,500 | 9.220 s | 11.015 s | 10.528 s |
| Many files | 1,000 | 5 | 5,000 | 18.127 s | 22.100 s | 21.172 s |

## Main takeaways

- Both alternatives remove the nonlinear scaling for many tests in one file.
- At 4,000 tests, `sort` is 47.6% faster than upstream and `awk` is 52.5% faster.
- With one test per file, both alternatives are effectively unchanged from upstream.
- With two tests per file, `sort` is approximately 32–33% slower than upstream; `awk` is approximately 20–23% slower.
- With five tests per file, `sort` is approximately 19–22% slower than upstream; `awk` is approximately 11–17% slower.
- Compared with the `sort` implementation, `awk` is about 8–12% faster for large files, 7–9% faster for two-test files, and 4–5% faster for five-test files.
- These measurements isolate gathering overhead. The relative difference will be smaller during normal execution of nontrivial tests because test execution time is excluded here.
