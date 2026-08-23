# Kolo 9 — Upstream Sync Plan (kolo9b, CORRECTED)

Date: 2026-07-18
Branch: `sync/upstream-2026-07-18b` (from `upstream/main` @ `9721b46`)
Methodology: **branch FROM upstream, re-apply fork features** (kolo8 rule, NOT cherry-pick).
Status: **Phases 0-4 DONE + tested. NOT merged — awaiting user live DRM test at home.**

## Correction note (why "b")

The first attempt (`sync/upstream-2026-07-18`, deleted) audited against a STALE local
`main` (fd19dde) instead of `origin/main`. `origin/main` (c747585) had a May "mini-sync"
from another machine plus two fork features the stale audit missed. Redone against
`origin/main` as the authoritative fork reference. Merge-base (48e19a0) and the 44 upstream
commits are identical either way; only the fork-feature reference changed.

## Audit (against origin/main c747585)

- Merge-base(origin/main, upstream/main) = `48e19a0`; 44 upstream commits (Clay add+revert
  nets to zero).
- `git diff upstream/main..origin/main`: 189 files — 106 A (fork-only), 11 D (7 upstream
  tests kept + 4 themes deleted), 71 M (32 take-ours net-unchanged, 39 surgical), 1 rename.
- 12/13 hard C files have identical fork delta vs the stale audit → same validated
  reconciliation. monitor.c differs (createmon bail now in the upstream base = cleaner).

## Two fork features the stale audit had missed (now present)
- `is_geo_animating(c)` — `lua/awful/anim_client.lua` (upstream fork commit c747585)
- `property::floating -> _c_floating` handler — `lua/awful/client.lua` (540f44e)

## Revert-gate corrections (origin was BEHIND upstream on build files)
- `wlroots.wrap`: took upstream **0.19.3** (origin had 0.19.2)
- `Makefile` test-signal: kept upstream (origin lacked 9b680d6 SIGTERM+test)
- `lgi-glib-2.88-enum.patch`: **removed** (upstream dropped this approach in 4d2aef4;
  Nix-only concern — verify `nix build` if packaging for NixOS, per Codex Q1)
- `package.nix`: took upstream GLib approach
- `meson.build`: upstream base + fork scenefx block + somewm-session install
- `meson_options.txt`: take-ours (scenefx option only)

## Overlaps resolved (fork had own fix; upstream now also has it)
- **K9-D1** SIGTERM/quit: took upstream unified `some_compositor_quit()`; fork
  `cold_restart`/`rebuild_restart` set `globalconf.exit_code` then route through it;
  `main()` returns exit_code. Verified: quit→0, SIGTERM→0.
- **K9-D2** mapnotify flush: took upstream `schedule_flush_clients` (= our #530).
- **K9-D3** ready signals: upstream owns them (merged #515); xwayland.c keeps only the
  scenefx include swap; no double-emit.
- `objects/client.c` two-pass: `client_ban_unfocus` keeps the fork mousegrabber guard
  (PR #521 cross-monitor drag) adapted to upstream `client_unfocus(c,false)` queued form;
  the unmanage path keeps upstream `client_unfocus(c,true)` SYNCHRONOUS (9721b46
  invalidation exception).

## Codex SOL reviews
- Round 1 (on the plan): YELLOW → 6 fixes folded in (31-file proof, client.c two-pass,
  permissions rationale, protect-list, exit-code tests, build wording).
- Round 2 (on the corrected reconciliation): YELLOW. Q3/Q4 clean — no fork feature dropped,
  no wrong downgrade. Finding 1 (test-signal fails under SceneFX) did NOT reproduce
  empirically (PASS on build-test + scenefx=enabled). Finding 2 (xwayland-ready test
  downgrade) fixed — restored fork version.

## Verification (empirical, in nested sandbox — live session untouched)
- Build: scenefx OFF + ON both link clean.
- Real `~/.config/somewm` config: fishlive loaded, 9 tags, `is_geo_animating`=function,
  `root.memory_stats`=table, hot-reload survives with no crash / no stale-closure.
- Tests PASS: test-signal, test-signal-somewm-ready, test-signal-xwayland-ready,
  test-memory-stats, test-scenefx-corner-radius, test-kolo7-regression.
- `test-keyboard-focus-sync` was FAILING (pre-existing — fails identically on origin/main).
  Diagnosed as a STALE TEST: focus signals are event-queued (SIG_CLIENT_FOCUS, async drain)
  since the kolo8 event-queue migration; the test measured them synchronously. Instrumented
  proof: sync=0, after_drain=3. Fixed the test to be event-queue-aware (poll for drain in
  Step 3; settle-then-measure in Step 4). Now 3x stable PASS. Compositor behavior is correct.

## Commits on the branch
```
af4410a phase 0: branch from upstream + mechanical bulk (vs origin/main)
a0018b4 phase 1: build files (revert-gate corrected)
e613e04 phase 2: hard C reconcile (vs origin/main)
c8e7bbe phase 3: Lua/tests no-op (take-upstream)
f3842b3 phase 3b: restore fork xwayland-ready test (Codex finding 2)
5faacbd fix(test): make keyboard-focus-sync event-queue-aware
```

## Remaining (at home)
1. **Live DRM test**: `git checkout sync/upstream-2026-07-18b` → `install-scenefx.sh` →
   reboot → `start.sh`. Test Steam focus, multi-monitor hotplug, KeyRelease keybinds,
   hot-reload, cold-restart exit codes.
2. **Merge** to `main` via `git merge -s ours` + take sync tree (kolo8 pattern, both
   histories preserved, no force-push); tag `kolo9-merged`.
3. **Phase 6** — somewm-one API ports for the 44 new upstream commits (KeyRelease keybind
   semantics, switch-device signals, `-c NONE`, ready-signal property access). somewm-one
   and somewm-shell are both clean/up-to-date; no changes needed for the compositor sync.

Note: the older `plans/done/kolo9-mini-sync.md` (May) documents the partial mini-sync that
`origin/main` already carried; this doc supersedes it for the full sync.
