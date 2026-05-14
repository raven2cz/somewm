# Kolo 8 Upstream Sync — STATUS / Handoff

Date: 2026-05-14
Branch: `sync/upstream-2026-05-13` (based on `upstream/main` HEAD `48e19a0`)
Fork main: `5ccffad`

## TL;DR

The C/Lua sync (Phases 1–5) is **code-complete, build-clean, Codex-GREEN,
sandbox-verified**. NOT merged to `main`. Remaining: Phase 6 (full test
suite), Phase 7 (somewm-one ports), the user's live DRM test, and 2 memory
findings to investigate.

## Commits on the branch (14)

```
bef7410 phase 5: Lua fork features
8e59c14 phase 4c: event-queue migration — window.c + tag-slide helpers
a2b6474 phase 4b: event-queue migration — objects/client.c   (Codex GREEN)
9874446 phase 4a: event-queue migration — protocols/focus/input/xwayland/layer_surface
d09957d..ef5ccf4  Phase 4 sub-plan v1→v3 GREEN (Codex R1/R2/R3 + Sonnet audit)
3e00ad2 docs: Phase 3a/3b done, objects/client.c folded into Phase 4
d76122b phase 3b: root.c, somewm_api.c, stack, monitor, pointer constraint
6dda930 phase 3a: scenefx swaps, memory diagnostics, selection hardening
f3d5e9b phase 2: headers, globalconf, lifecycle, lgi guard
ee8c3fa phase 1: D2 theme removal + somewmrc.lua fix
55282dc phase 1: build integration + fork-only files
21525d9 docs: kolo8 planning documents
```

## Planning docs (all committed in plans/)

- `kolo8-fork-delta-inventory.md` — 65 upstream commits, file classification, PR triage
- `kolo8-migration-audit.md` — per-function A/B/C/D audit (6 parallel agents + Codex corrections)
- `kolo8-integration-plan.md` — 7-phase plan v2, decisions D1–D5 resolved
- `kolo8-event-queue-migration.md` — Phase 4 sub-plan v3 GREEN, reconciled 33-hunk objects/client.c table
- this file

## DONE — Phases 1–5

- **Phase 1**: build integration (meson.build additive-only — scenefx dep), fork-only
  files (scenefx_compat.h, animation/shadow, anim_client.lua, tag_slide.lua, docs,
  plans/, fork tests). D2 resolved: dropped themes/{catppuccin,gruvbox,nord}, kept
  upstream logo+lucide, patched somewmrc.lua. somewm-client.c/somewmrc.lua = take upstream.
- **Phase 2**: globalconf.h fields, scenefx_compat.h swaps in headers, somewm.c/luaa.c
  lifecycle (cold/rebuild_restart, somewm::ready, Lgi guard gating), lgi_closure_guard.c
  (fork-ahead — RE-APPLY), window.h/window.c schedule_flush_clients (#530).
  DROPPED: `exclude` param (7aa9351 removed it), header-dedup collisions.
- **Phase 3a/3b**: scenefx swaps (bench/systray/drawin/screen), memory diagnostics
  (drawable/wibox), selection.c hard-error; root.c (wallpaper/memory/tag-slide, kept
  upstream 5f3c4ef screenshot infra), somewm_api.c (focus Path-B parity), stack.c/h
  (WINDOW_LAYER_FLOATING), monitor.c (surgical), input.c some_update_pointer_constraint.
  SKIPPED as dead code: property.c/h xproperty stubs, objects/button.c/h button_array_check.
- **Phase 4a/b/c**: event-queue migration. xwayland/protocols/focus/input/layer_surface;
  objects/client.c (33-hunk table, Codex GREEN); window.c (~40 hunks) + luaa.c tag-slide.
  Conversion rules: DROP fork synchronous emits of SIG_* signals (take upstream queued);
  KEEP synchronous request::manage/unmanage/geometry + Rule-C fork-new (screen::focus,
  xwayland::ready, somewm::ready, property setters). apply_geometry_to_wlroots RECONCILED
  (upstream clamp_to_mon + fork strict_clip). Double-emit grep clean. Final Codex: GREEN.
- **Phase 5**: snap.lua (aerosnap dwell PR#522), wallpaper.lua (negative-origin PR#484),
  lockscreen.lua (bg image PR#476), somewm/init.lua (tag_slide). KEEP-UPSTREAM:
  input/ipc/screenshot.lua (fork behind), permissions/init.lua (PR#516 dropped — C-layer
  7c932c7 supersedes), icon unit client/clienticon/tasklist.lua (D1 — adopt upstream
  resolve_icon, drop fork get_icon_path).

Build verified clean **scenefx ON + OFF** + `somewm --check` 30/30 after every phase.

## REMAINING

### Phase 6 — Tests
- Test-file reconciliation: **confirmed no-op** — all modified-in-both test files were
  correctly left at upstream throughout (only fork-only A test files were brought in).
- Full integration test suite (136 `tests/test-*.lua`) — NOT run. Runner is
  `tests/run-integration.sh` (HEADLESS=1). Sub-plan §6 wants the 4 `test-event-queue-*.lua`
  + focus/mouse/xwayland regression to pass.
- busted unit specs — **environment is broken** (system lua 5.3→5.5 update fragmented the
  rocks: busted only for 5.4/5.5, penlight/lfs split, lgi only for 5.1). Pre-existing, NOT
  a sync regression. Needs the user to install a consistent `busted+penlight+lfs+lgi` stack
  (probably for luajit/5.1, since the compositor runs luajit and lgi is 5.1-only).

### Phase 7 — somewm-one ports (separate repo, post-merge)
- `~/git/github/somewm-one` — port the rc.lua API/behavior surface from upstream `ba586fd`:
  per-screen `request::wallpaper`, named tags + connector-keyed persistence, signal-driven
  layouts/keybindings/rules, interactive screenshot, `naughty.suspended`, `awful.input.*`
  xkb surface, `output added` per-monitor scale, `awful.ipc.register`. Full list in
  `kolo8-migration-audit.md` §"rc.lua → somewm-one ports".

### Live DRM test (kolo6 methodology gate)
- Do NOT merge `sync/upstream-2026-05-13` to `main` until the user runs a real
  half-to-full-day DRM-session test.

### Open findings (investigate in fresh session)
1. **Hot-reload leak ~4.5 MB per `awesome.restart()`** — RSS 78→100 MB over 5 reloads,
   monotonic. LIKELY by-design (hot-reload intentionally leaks the old Lua state — the
   whole lgi_closure_guard exists because of it; `cold_restart`/`rebuild_restart` are the
   non-leaking alternatives). MUST confirm vs regression: run the same test on pre-sync
   fork `main` and compare. Use `plans/scripts/somewm-memory-trend.sh --reload 5`.
2. **somewm-headless ignores SIGTERM** — needs `kill -9`. Caused stuck sandbox processes /
   the RAM spike during this session. Possibly a Phase-2 shutdown regression (cleanup() /
   some_event_queue_wipe / main() return path) OR pre-existing headless behavior. Verify.

## Verification done this session

- Headless sandbox (3 runs): startup clean, `#530` disconnect-mid-map ×10 survived,
  hot-reload complete (lgi guard rewired closures, marked ready), `somewm::ready`
  introspection = true, all 4 fork Lua modules `require()` ok, **0 crashes/asserts/
  double-emit** in logs.
- Visible nested-wayland run: window opened, alacritty spawned, tag-switch IPC sent.

## ⚠️ Process lesson — sandbox

This session repeatedly **hand-rolled the sandbox launch** instead of using the
documented `plans/scripts/somewm-sandbox.sh` (CLAUDE.md "Nested compositor sandbox").
That caused: unreaped/stuck processes, the RAM spike, unreliable IPC. **In the fresh
session: USE `somewm-sandbox.sh`** — it handles the IPC-vs-Wayland socket distinction,
the cleanup trap, and the isolated runtime dir. See also memory
`feedback_sandbox_runtime_testing` (updated with the RAM-safety rules).

## Next-session entry point

1. Read this file + `kolo8-integration-plan.md` + `kolo8-event-queue-migration.md`.
2. Verify findings #1/#2 (memory-trend + SIGTERM) — decide regression vs by-design.
3. Run Phase 6 integration tests via `tests/run-integration.sh` (or fix busted env first).
4. Run the visible/headless sandbox via `somewm-sandbox.sh` — NOT a hand-rolled launch.
5. Hand off to the user for the live DRM test before any merge to `main`.
6. Phase 7 (somewm-one) after merge.
