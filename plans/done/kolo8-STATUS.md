# Kolo 8 Upstream Sync — STATUS (CLOSED)

Date opened: 2026-05-13 · Date closed: 2026-05-14
Result: **COMPLETE — merged to `main`, live-tested, all regressions fixed.**

## Outcome

The kolo8 upstream sync is done. `main` now equals `upstream/main` HEAD
(`48e19a0`) with all fork features re-applied, plus the fixes below. The fork
is on upstream HEAD with fork features reconciled — objectively ahead of the
pre-sync state.

- Sync branch `sync/upstream-2026-05-13` was built FROM `upstream/main` and
  re-applied fork features onto it (Phases 1–5).
- Phase 6: full 136-test integration suite run — **130 pass, 6 fail**; all 6
  failures verified pre-existing (not sync regressions). Phase 4 event-queue
  gate (4 event-queue + 3 focus + 13 xwayland = 20 tests) fully green.
- Merged to `main` as merge commit `0583e82` (strategy: `git merge -s ours` +
  take sync tree; both histories preserved, no force-push).
- Phase 7 (somewm-one config ports) done in the `somewm-one` repo.
- User live DRM-session test passed.

## Fixes committed during the sync (framework `main`)

| commit | fix |
|--------|-----|
| `dc8175a` | quit GLib main loop on SIGINT/SIGTERM (was a no-op) |
| `367fec0` | break deferred pointer-enter re-delivery infinite loop |
| `d115991` | quit cleanly on Ctrl-Alt-Backspace |
| `2e6ebf7` | test runner reaps the real compositor, not the timeout wrapper |
| `c1722e6` | restore reverse maximize/fullscreen animation |
| `89f09eb` | restore `transient_for.screen` nil-guard in `permissions.tag` |

Most were bit-identical-to-fork-main pre-existing bugs; `c1722e6` and `89f09eb`
were sync regressions (a deferred-signal interaction and a dropped fork
nil-guard, respectively). Every fix Codex-reviewed.

## Phase 7 (somewm-one repo)

API audit found one real breakage (removed `manage`/`unmanage` signals →
migrated to `request::manage`/`request::unmanage`). Plus: somewm "S" launcher
icon, interactive screenshot keybind, `awful.ipc.register` scaffold, `wlroots`
client rule, pointer-settings scaffold. Committed `4fb1ac2` + `3bcaa1d`,
Codex+Sonnet reviewed, deployed.

## Planning docs (this set, now archived alongside this file)

- `kolo8-fork-delta-inventory.md` — commit window, file classification, PR triage
- `kolo8-migration-audit.md` — per-function A/B/C/D audit
- `kolo8-integration-plan.md` — 7-phase plan
- `kolo8-event-queue-migration.md` — Phase 4 sub-plan

## Open follow-ups

Three items surfaced during kolo8 but are **not** kolo8 regressions — moved to
`plans/post-kolo8-followups.md` (still open): the 6 pre-existing failing
integration tests, the broken busted/luarocks env, and the pre-existing
~88 MB/reload hot-reload leak.

## Methodology notes for future syncs

- Branch FROM upstream, re-apply fork features (don't merge upstream into the
  divergent fork main).
- Codex + Sonnet review every phase / every fix — they caught real bugs.
- Diagnose before hypothesizing: instrument and reproduce in an isolated
  headless sandbox, read the real logs. (Two fixes this round were initially
  mis-diagnosed by hypothesis and corrected once actually measured.)
- Run sandbox/test work one compositor at a time with an RSS cap — the
  integration runner leaked compositors and spiked host RAM before that.
