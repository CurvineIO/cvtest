# cvtest

Testing flow for Curvine, including CVbench, LTP, Xfstest and other customized cases.

## Status (2026-09-01)

LTP lane is live with the three-lane curated set below; the early `cv-fs`
smoke file was removed 2026-09-01 (strict subset of `syscalls-cv`).
xfstests and CVbench are planned (see "Roadmap").

## Layout

```
cvtest                     # CLI entrypoint (python3, stdlib only)
suites/<tool>/             # curated suite definitions, one directory per tool
  ltp/runtest/             #   LTP command files (installed into $LTP/runtest)
    fs-cv / fs-cv-smoke / syscalls-cv / ...
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
| `name` | Tool-specific suite id | LTP: runtest file stem (`fs-cv-smoke`); xfstests: group (`generic/001`) |

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
  "suite": "fs-cv-smoke",
  "status": "completed",
  "return_code": 0,
  "log_file": "...",
  "passed_count": 20,
  "failed_count": 0,
  "total_count": 20,
  "success_rate": 100.0,
  "test_cases": [{"name": "ftest01", "status": "PASSED"}]
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
| fs_perms_simple | 18 | 18/18 | permission matrix (upstream LTP built-in; not vendored here) |
| fcntl-locktests | 1 | 1/1 | record locks |
| fs_bind | 95 | 95/95 | bind mounts / rename |
| fs-cv | 56 | 52/56 | upstream `fs` minus 12 entries (see file header); red: gf20/23/26/29 growfiles data mismatch (known bug, fix in flight) |
| fs-cv-smoke | 20 | 20/20 | fs-cv minus the stress block (gf01-30, rwtest01-05, iogen01); CI fast-lane gate |
| syscalls-cv | 557 | 557/557 with LTP_TIMEOUT_MUL=4 | FS-related syscall whitelist; daily regression (~3h35m measured) |

Curation policy (aligned with JuiceFS's published POSIX-compat approach):

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

# 3. Run suites (examples from the fast / daily lanes).
./cvtest run --suite ltp:fs_perms_simple --mount /curvine-fuse --json out1.json
./cvtest run --suite ltp:fs-cv-smoke     --mount /curvine-fuse --json out2.json
./cvtest run --suite ltp:syscalls-cv     --mount /curvine-fuse --json out3.json
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

## CI lanes (curvine `e2e-ltp.yml`)

Manifest files under `suites/ci-*.txt` document which `tool:suite` names each lane runs.

| Lane | Manifest | Trigger | ~wall time (FUSE) |
|------|----------|---------|-------------------|
| **fast** | `ci-fast.txt` | nightly 18:00 UTC, PR label `run-ltp` | **15–25 min** (146 cases) |
| **syscalls** | `ci-daily-syscalls.txt` | daily 02:00 UTC, dispatch `lane=syscalls` | **~3h35m measured** (557 cases; the mount/mkfs family dominates — budget >=5h incl. build; measured 2026-08-27, log /tmp/cv-suites-syscalls-cv.log) |
| **pressure** | `ci-pressure.txt` | PR label `run-ltp-pressure` | **20–40 min** (56 cases; growfiles reds expected until fix lands) |

Fast lane deliberately **excludes** `syscalls-cv` (too heavy) and **full** `fs-cv` (known growfiles reds). Pin cvtest at `feat/cv-suites-2026-08-26` until review merges.

## Roadmap

1. LTP: installer, curated suites, cvtest run entry (done 2026-08-25; obsolete `cv-fs` removed 2026-09-01)
2. curvine CI: `e2e-ltp.yml` three-lane workflow (done 2026-08-27; NOT a PR gate until privileged FUSE proves stable on hosted runners)
3. xfstests: pick runnable groups from Curvine's POSIX support matrix, add per-group command files
4. CVbench / fio performance lane on the same runner contract
5. kirk migration for LTP >= 20260529 (runltp removed upstream)
