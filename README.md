# cvtest

Testing flow for Curvine, including CVbench, LTP, Xfstest and other customized cases.

## Status (2026-09-09)

The LTP fast gate uses a focused POSIX/filesystem-semantics suite instead of
upstream LTP's generic `smoketest` or the stress-oriented `fs-cv-smoke`.
Additional CI lanes will be added only after their contents and trigger policy
have been validated.
xfstests and CVbench are planned (see "Roadmap").

## Layout

```
cvtest                     # CLI entrypoint (python3, stdlib only)
suites/<tool>/             # curated suite definitions, one directory per tool
  ltp/runtest/             #   LTP command files (installed into $LTP/runtest)
    posix-cv-smoke / fs-cv / syscalls-cv / ...
  xfstests/                #   (planned) group lists / runner args
  cvbench/                 #   (planned) scenario manifests
tools/<tool>/              # pinned installers / wrappers (e.g. tools/ltp/install-ltp.sh)
suites/ci-*.txt            # lane manifests: one `tool:suite` per line
```

Today only `ltp` is wired in `cvtest`; other tools follow the same contract
below when added.

## Multi-tool extension convention

All POSIX / FS test harnesses are **peer tools** under one CLI. Names are
stable across cvtest, curvine CI, and the regression Portal.

### Suite naming

```
cvtest run --suite <tool>:<name> --mount <path> [--json out.json]
```

| Part | Meaning | Example |
|------|---------|---------|
| `tool` | Which harness runs the suite | `ltp`, `xfstests`, `cvbench`, `pjdfstest` |
| `name` | Tool-specific suite id | LTP: runtest file stem (`posix-cv-smoke`); xfstests: group (`generic/001`) |

Rules:

- **Always** use the `tool:name` form on the CLI and in CI manifests — never
  bare suite names (avoids collisions when multiple tools define `quick`).
- Curated files live under `suites/<tool>/…`; upstream/built-in names (e.g.
  LTP `fs_perms_simple`) need no vendored file but still use the prefix
  (`ltp:fs_perms_simple`).
- Lane manifests (`suites/ci-*.txt`) are tool-agnostic: one `tool:suite` per
  line; a single lane may mix tools once more than one is implemented.

### JSON contract (all tools)

Every run emits **one** JSON object. The `tool` field identifies the harness;
remaining fields are normalized so curvine can aggregate runs the same way:

```json
{
  "tool": "ltp",
  "suite": "posix-cv-smoke",
  "status": "completed",
  "return_code": 0,
  "log_file": "...",
  "passed_count": 53,
  "failed_count": 0,
  "total_count": 53,
  "success_rate": 100.0,
  "test_cases": [{"name": "open01", "status": "PASSED"}]
}
```

- `tool` + `suite` together are the stable id (Portal / dashboards group by
  `tool`, drill down by `suite`).
- `test_cases[].status` is always `PASSED` or `FAILED`.
- Tool-specific details belong in `log_file`, not new top-level keys, unless
  the Portal contract is extended deliberately.

### Adding a new tool (checklist)

1. **Pin** the upstream version under `tools/<tool>/` (install script or
   documented image layer).
2. **Curate** suites under `suites/<tool>/` (command files, group lists, or
   scenario YAML — whatever the harness expects).
3. **Implement** a runner branch in `cvtest` that: validates env, runs the
   harness against `--mount`, parses output into the JSON contract above.
4. **Document** the tool row in "Pinned tool versions" and any suite table.
5. **Wire CI** by appending `tool:suite` lines to the appropriate
   `suites/ci-*.txt`; curvine workflows stay mount-centric and do not
   hard-code tool names beyond what the manifest lists.

Peer tools (same bar): **LTP**, **xfstests**, **CVbench**, **pjdfstest**.
Do not add one-off scripts outside this layout — cvtest remains the single
entrypoint for Curvine automated FS testing.

## Curated suites (canonical)

Baseline: 2026-08-26 full-suite run against Curvine FUSE (rocky9, kernel 6.17,
LTP 20250930); classification details in the #curvine-tests thread.

| Suite | Size | Baseline | Notes |
|-------|------|----------|-------|
| smoketest | 12 | 12/12 | quick sanity |
| posix-cv-smoke | 53 | 53/53 on Rocky 9 container + Curvine FUSE | representative Curvine POSIX/filesystem interface families; fast CI gate |
| fs_perms_simple | 18 | 18/18 | permission matrix (upstream LTP built-in; not vendored here) |
| fcntl-locktests | 1 | 1/1 | record locks |
| fs_bind | 95 | 95/95 | bind mounts / rename |
| fs-cv | 56 | 52/56 | upstream `fs` minus 12 entries (see file header); red: gf20/23/26/29 growfiles data mismatch (known bug, fix in flight) |
| fs-cv-smoke | 20 | 20/20 | fs-cv minus the stress block (gf01-30, rwtest01-05, iogen01); CI fast-lane gate |
| syscalls-cv | 557 | 557/557 with LTP_TIMEOUT_MUL=4 | FS-related syscall whitelist; candidate source for a future extended lane (~3h35m measured) |

Curation policy (aligned with JuiceFS's published POSIX-compat approach):

- **posix-cv-smoke**: select one or two known-green cases for each critical
  filesystem interface family. Exclude tests that target networking, loop
  devices, mount namespaces, pseudo filesystems, or sustained stress. Add new
  cases only after validating them on the target Curvine CI environment.
- **fs-cv**: drop tests that never terminate or don't apply on a quota-less
  distributed FUSE FS (ENOSPC loops, loop mounts, procfs). Unlike JuiceFS we
  KEEP the growfiles/rwtest/iogen pressure tests — they found a real bug.
- **syscalls-cv**: whitelist filesystem-related syscall families
  (open/read/write/truncate/link/rename/stat/chmod/chown/utime/xattr/
  mmap+sync/getdents/inotify/io_uring/mount/handles/path_resolution, ...);
  signals/sched/ipc/network/ptrace stay out. Then drop every tag that failed
  in the baseline so the suite is a green CI gate on this runner class.

## Quick start

```bash
# 1. Install pinned LTP (default 20250930; the release must ship runltp —
#    upstream removed it in 20260529 in favor of kirk).
./tools/ltp/install-ltp.sh /opt/ltp

# 2. Ensure a Curvine cluster is mounted (see curvine repo:
#    build/dist + bin/curvine-{master,worker,fuse}.sh; fuse must be
#    started as root; probe with a touch+read on the mount).

# 3. Run the fast gate or a larger suite manually.
./cvtest run --suite ltp:posix-cv-smoke --mount /curvine-fuse --json out1.json
./cvtest run --suite ltp:syscalls-cv    --mount /curvine-fuse --json out2.json
```

Exit code: 0 = all tests passed AND runltp rc 0; 1 = failures; 2 = usage/env error.

## JSON contract

Each run emits one object as specified in [Multi-tool extension convention](#multi-tool-extension-convention).
Fields match the curvine regression Portal's `test_summary.json` parsing semantics
(`curvine-tests/regression/tests/ltp_test.py` today; generalize by `tool` as more
harnesses land).

## Pinned tool versions

| Tool | Version | Why |
|------|---------|-----|
| LTP  | 20250930 | newest release verified green on Curvine that still ships `runltp`; 20260529+ removed runltp in favor of kirk |

## CI lanes (Curvine workflows)

Manifest files under `suites/ci-*.txt` document which `tool:suite` names each
validated lane runs. Currently only the fast gate is defined.

| Lane | Manifest | Trigger | ~wall time (FUSE) |
|------|----------|---------|-------------------|
| **fast** | `ci-fast.txt` | pull-request build | 53 selected cases; ~15s test execution locally (cluster startup excluded) |

Fast lane deliberately excludes generic `smoketest` (non-filesystem cases and
environment dependencies), `fs-cv-smoke` (known `ftest` failures), full
`syscalls-cv` (too slow), and full `fs-cv` (known growfiles failures).
The latter suites remain available as curation inputs and for manual runs, but
they are not advertised as supported CI lanes. Add a new `ci-*.txt` only after
the selected cases pass in the target environment and the lane's trigger,
runtime budget, and failure policy are explicit.

## Roadmap

1. LTP: installer, curated suites, cvtest run entry (done 2026-08-25; obsolete `cv-fs` removed 2026-09-01)
2. Curvine CI: wire the pull-request build to the validated `ci-fast.txt` manifest
3. xfstests: pick runnable groups from Curvine's POSIX support matrix, add per-group command files
4. CVbench / fio performance lane on the same runner contract
5. kirk migration for LTP >= 20260529 (runltp removed upstream)
