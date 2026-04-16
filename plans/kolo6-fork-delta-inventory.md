# Kolo 6 — Fork Delta Inventory (Phase 1)

**Date:** 2026-04-16
**Branch:** `chore/upstream-sync-kolo6` @ `upstream-base-kolo6` (493fda4)
**Scope:** Everything in `main` that must be replayed onto upstream refactored tree.

## Raw counts

```
git diff --name-only HEAD..main = 470 files

Breakdown by filter:
  A (added in main, missing in upstream)   : 342 files
  M (modified in both)                     : 109 files
  D (only in upstream-base-kolo6, missing in main): 19 files

Commit classification (git cherry upstream-base-kolo6 main):
  + (our fork only)                        : 222 commits
  - (equivalent in upstream already)       : 38 commits
  unaccounted (merges etc)                 : 29 commits
  Total cb0b8e4..main                      : 289 commits
```

## Upstream-only (19 files — from refactor split)

These exist in `upstream-base-kolo6` but NOT in our main. **Action: we adopt them as-is (branch already has them).**

### Refactor outputs (15)
- `focus.c`, `focus.h` — focusclient, focustop, focus_restore
- `input.c`, `input.h` — pointer, keyboard, gestures, seat, cursor
- `monitor.c`, `monitor.h` — createmon, rendermon, output mgmt
- `protocols.c`, `protocols.h` — layer shell, idle, session lock, foreign toplevel
- `window.c`, `window.h` — XDG shell, mapnotify, commitnotify, arrange
- `xwayland.c`, `xwayland.h` — XWayland handlers
- `somewm.h` — 40 extern globals
- `somewm_internal.h` — coordinator helpers

### Upstream regression tests (4) — must verify our code passes these
- `tests/test-layer-shell-focus-escape.lua`
- `tests/test-layer-shell-focus-restore.lua`
- `tests/test-layer-shell-keyboard-focus.lua`
- `tests/test-xdg-unmap-focus-transfer.lua`

### Style (1)
- `.editorconfig`

## Modified files (109 — exist in both, need merge)

### ROOT C/H (19 files — critical)

| File | Target | Risk | Notes |
|---|---|---|---|
| `somewm.c` | split across focus/window/input/monitor/protocols/xwayland | **CRITICAL** | Main distribution task. Contains NVIDIA focus fixes, SceneFX hooks, bench hooks. |
| `somewm_api.c` | same file | HIGH | `some_update_pointer_constraint()` API break (Phase 1b) |
| `somewm_api.h` | same file | HIGH | API declarations |
| `somewm_types.h` | same file | MEDIUM | shadow/opacity/animation fields |
| `client.h` | same file | MEDIUM | client_activate_surface, client_notify_enter inline helpers |
| `globalconf.h` | same file | LOW | awesome_t struct extensions |
| `shadow.c`, `shadow.h` | same file | MEDIUM | **WAIT** — not in upstream refactored tree at this commit. Actually modified? Check. |
| `animation.c`, `animation.h` | same file | MEDIUM | fadeIn, bezier timing |
| `luaa.c` | same file | MEDIUM | Lua state lifecycle, exec() fix |
| `property.c`, `property.h` | same file | LOW | client property system |
| `root.c` | same file | LOW | root object |
| `selection.c` | same file | LOW | X11 selection |
| `stack.c`, `stack.h` | same file | LOW | client stacking |
| `systray.c` | same file | MEDIUM | system tray |
| `lgi_closure_guard.c` | same file | MEDIUM | lgi closure lifetime |

### objects/ (9 files)

| File | Risk | Notes |
|---|---|---|
| `objects/client.c` | **HIGH** | 292159b sloppy focus fix, 0955251 icons, many bugfixes |
| `objects/client.h` | MEDIUM | client_t struct extensions |
| `objects/layer_surface.c` | MEDIUM | opacity field (8feb622) |
| `objects/layer_surface.h` | MEDIUM | layer_surface_t extensions |
| `objects/screen.c` | MEDIUM | fake_remove, virtual_output |
| `objects/button.c`, `objects/button.h` | LOW | button events |
| `objects/drawin.c` | LOW | drawin drawing |
| `objects/wibox.c` | LOW | wibox rendering |

### lua/ (5 files)

| File | Risk | Notes |
|---|---|---|
| `lua/awful/client.lua` | MEDIUM | focus rules, rules engine |
| `lua/awful/ipc.lua` | MEDIUM | IPC handlers |
| `lua/lockscreen.lua` | LOW | lockscreen module |
| `lua/somewm/init.lua` | LOW | module init |
| `lua/wibox/init.lua` | LOW | wibox Lua entry |

### common/ (3 files)
- `common/lualib.h`, `common/luaobject.c`, `common/luaobject.h` — Lua infrastructure

### Build/meta
- `meson.build`, `meson_options.txt`, `Makefile`, `package.nix`
- `.gitignore`, `.stylua.toml`, `CHANGELOG.md`, `CONTRIBUTING.md`
- `DEVIATIONS.md`, `README.md`, `somewmrc.lua`, `somewm-session`
- `spec/awful/keygrabber_release_spec.lua`
- `tests/README.md`
- `.github/ISSUE_TEMPLATE/bug_report.md`

## Fork-only (342 files)

### plans/ (315 files) — SKIP
Documentation only. No port.

### tests/ (16 fork-specific files) — PORT
```
tests/test-xdg-hotplug-crash.lua
tests/test-xwayland-keyboard-focus.sh
tests/smoke-hotplug.sh
tests/test-crash-reproducer.sh
tests/test-restart-leaks.sh
... (and 11 more)
```

### spec/ (2 fork-only files) — PORT
Unit test additions beyond keygrabber_release_spec.lua.

### lua/ (2 fork-only files) — PORT
New Lua modules we added.

### Root fork-only files
| File | Action |
|---|---|
| `bench.c`, `bench.h` | PORT (Group A) — upstream adds them post-refactor, we port first |
| `scenefx_compat.h` | PORT (Group G) — SceneFX API shim |
| `CLAUDE.md` | PORT (docs, top-level) |
| `.codex` | PORT (Codex config) |
| `somewm-session` | PORT (session launcher) |
| `subprojects/...` | CHECK — scenefx submodule |

## Commit classification summary

Instead of classifying 222 commits individually, we rely on **file-level coverage** through 8 thematic groups (Phase 3 Groups A-H). Each group is a thematic port of all relevant changes to its domain; as long as every touched file above lands correctly into its target group, the commit history is covered.

### Group → File mapping

| Group | Scope | Files |
|---|---|---|
| **A** Build + fork-only | `meson.build`, `meson_options.txt`, `Makefile`, `bench.c/h`, `shadow.c/h`, `common/`, `stack.c/h`, `systray.c`, `somewm_types.h`, `animation.c/h`, `scenefx_compat.h`, `package.nix`, `.gitignore`, `.stylua.toml` | 23 |
| **B** Lua + objects | `lua/**`, `objects/**`, `spec/**`, `somewmrc.lua` | 30+ |
| **C** Hot-reload/lgi | `lgi_closure_guard.c`, `somewm.c` (restart bits) → `somewm.c` | 2 |
| **D** Low-risk bugfixes | `client.h`, `root.c`, `selection.c`, `property.c/h`, various | 10+ |
| **E** Input/keygrabber/idle | `somewm.c` (input bits) → `input.c`, `somewm.c` (idle bits) → `protocols.c` | distributed |
| **F** NVIDIA focus | `somewm.c` (focus bits) → `focus.c`, `window.c`, `somewm_api.c`, `objects/client.c` | distributed |
| **G** SceneFX | `somewm.c` (rendering) → `monitor.c`, `window.c`, `shadow.c/h`, `objects/layer_surface.c` | distributed |
| **H** Bench hooks | `input.c`, `window.c`, `monitor.c` (6 call sites), `Makefile` bench targets | distributed |

### Critical cross-cutting files
- **`somewm.c`** — touches every group. Each group ports relevant sections to respective target module.
- **`somewm_api.c`** — touches A, F, G (not split by upstream).
- **`globalconf.h`** — touches A, G (shadow theme), H (bench).

## Pre-existing upstream post-refactor commits (beyond 493fda4)

These are in `upstream/main` but NOT in `upstream-base-kolo6` (493fda4). They are Kolo 7 scope:

```
44f842b Kill trailing whitespace                    → NEW (Kolo 7)
c510efa send exit signal parameter                  → NEW (Kolo 7)
cb6c2c1 fix: stop key repeat                        → DUPE (our 7d0ede8)
64fe6a7 simplify unmaplayersurfacenotify            → NEW (Kolo 7)
d354433 fix: pair send_leave with send_enter        → DUPE (our a411860)
9e05267 fix(xdg): restore set_bounds hint           → DUPE (our 9012e25)
8a64a43 chore: issue templates YAML                 → SKIP (docs)
746d59d feat: make profile targets                  → DUPE (our 87cdd69)
e5d7dfe feat: benchmark infrastructure              → DUPE (our 12fb825)
fb74146 fix: revert bug report template             → SKIP (docs)
```

## Risks identified from inventory

1. **`shadow.c/h` in both "modified" and possibly fork-only region** — need verification. If shadow existed in upstream-base-kolo6 pre-SceneFX, we only merge deltas. Otherwise fork-only (Group A).

2. **`animation.c/h` are MODIFIED not fork-only** — upstream has them. This is surprising; Kolo 4 we introduced fadeIn. Check the diff to understand what upstream animation.c looks like.

3. **`somewm.c` still exists in upstream-base-kolo6** (1818 lines, lifecycle) — our main somewm.c is 7570 lines. The distribution task is sizable.

4. **4 upstream regression tests must pass** (test-layer-shell-*, test-xdg-unmap-focus-transfer). If they fail, our port has broken something.

## Next steps

- **Phase 1b:** API compat preflight (`some_update_pointer_constraint` + privatized symbols)
- **Phase 3 Group A:** Start with build infrastructure (lowest risk, establishes foundations)
