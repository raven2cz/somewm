# Kolo 8 — Upstream Sync Fork Delta Inventory

Date started: 2026-05-14
Sync branch: `sync/upstream-2026-05-13` (based on `upstream/main` @ `48e19a0`)
Fork main HEAD: `5ccffad`
Merge-base: `493fda4` (`chore: remove stale externs and redundant guards`, 2026-04-10)

Upstream is 65 commits ahead of merge-base. Fork main is 163 commits ahead.
289 files differ, +27218 / -8166.

---

## 1. Upstream commit window (merge-base..upstream/main), grouped by theme

### A. Event-queue refactor — THE HARD PART (16 commits)
Adds `event_queue.c`/`event_queue.h`; converts synchronous signal emit to
deferred/queued dispatch. Fork is based on a pre-event-queue upstream, so
`event_queue.c/h` show as `D` (upstream-only) in the fork delta.

- `1b90255` refactor: add event queue infrastructure for deferred signal dispatch
- `72a1504` feat: convert geometry signals to queued event dispatch
- `c13d161` feat: convert focus signals to queued event dispatch
- `7119308` feat: convert mouse signals to queued event dispatch with coalescing
- `84a5d0b` feat: convert lifecycle signals to queued event dispatch
- `affdf56` refactor: remove deprecated manage/unmanage signals
- `c2d4700` feat: convert request signals to queued event dispatch
- `6205f73` fix: harden event queue against OOM, shutdown leaks, bad signal ids
- `9c2d5da` fix: address event queue review findings
- `e609c61` fix: address second round of event queue review findings
- `6e5bcc3` refactor(event-queue): apply minor review fixes
- `02ca436` fix(event-queue): defensive reset after hot-reload state swap
- `820e043` refactor(event-queue): document stack convention; collapse systray enum
- `df9b245` feat: warn on removed client.manage / client.unmanage connections
- `ae28d8e` test: event queue coverage; expose mouse._fake_motion helper
- `4b51122` docs: expand cross-API stale-read window with at-risk APIs

### B. Header dedup refactor
- `ed4b4cf` refactor(headers): deduplicate function declarations across module headers

### C. Test orchestrator / nested compositor (feat/test-orchestrator branch merge)
Adds `test_orchestrator.c/h`, `nested_inhibitor.c/h`, `lua/awful/test_marker.lua`,
`spec/awful/test_marker_spec.lua`, `tests/test-test-orchestrator.sh`.
- `e5d7dfe` feat: benchmark and profiling infrastructure for 2.0 performance tracking
- `746d59d` feat: add make profile targets for repeatable profiling workflow
- `e82fc45` feat(client): port nested test compositor mode to main
- `b6103fb` fix(client): tighten test mode
- `48e19a0` feat(input): support specifying XKB model and rules

### D. Bugfixes — isolated
- `fb74146` fix: revert bug report template to somewm --version
- `9e05267` fix(xdg): restore set_bounds hint for initial configure
- `d354433` fix: pair send_leave with send_enter for layer surfaces
- `64fe6a7` protocols: Simplify code of unmaplayersurfacenotify()  [overlaps PR #521 area]
- `cb6c2c1` fix: stop key repeat when a keygrabber starts mid-press      [DUP? → ce1a98c]
- `c510efa` send exit signal parameter
- `44f842b` Kill trailing whitespace
- `df53154` client: Guard client->scene access                          [DUP? → 2a2befa]
- `9774101` client: Remove obsolete client_is_rendered_on_mon()          [DUP? → e2a196f]
- `bad997d` fix: Use-after-free of wlr_scene_tree via wlr_surface->data  [DUP? → 7a3e449]
- `901e363` fix: re-evaluate pointer focus after banning refresh        [DUP? → ea7e1aa]
- `d27fa2b` fix: Use static inline for scene-tree surface helpers        [DUP? → 622cde3]
- `b2d98fe` fix: make createmon() idempotent to prevent post-resume segfault
- `e3c6990` fix: make screen.primary setter use the primary_screen var
- `e7c14e6` fix(client): keep borders visible when client partially offscreen
- `2b6413c` fix(client): render clients across monitors outside carousel layout
- `7aa9351` fix: Broken exclude mechanism for some_is_idle_inhibited() #446
- `263ff72` fix(icons): resolve client icons via desktop-entry Icon field
- `3d41255` fix: Sync meson license with actual LICENSE file
- `069c229` fix: Wrong SPDX identifier in meson.build
- `4906140` fix: clean -Werror hits in luaa.c (GCC 15+) and button.c (GCC 16)
  → button.c part done on fork (`21b99d0`); luaa.c part still pending on fork
- `100826c` fix(client): scale c.content to logical size for HiDPI
- `5f3c4ef` fix(client): capture c.content via scene-tree walk
- `551d4d5` fix(client): drop scene-coords offset from c.content walk
- `1ec02b1` fix(screenshot): render snipping wibox at logical resolution
- `b66d3cf` fix(screen): aggregate drawin struts by explicit screen pointer
- `7c932c7` fix(hot-reload): assign all client screens before emitting restore signals
  → upstream's PR #558, the C-layer replacement for our closed PR #516
- `58915a2` fix(geometry): emit per-client signals from resize()
  → upstream's reimplementation of our closed PR #478

### E. Features
- `d0e8ef4` feat(ipc): add screenshot interactive CLI subcommand
- `0bc89de` feat(rc): add interactive screenshot binding and wlroots tag rule
- `b9113cf` build: support Lua 5.5 and add lua_pkg override
- `6ead9d8` fix(wibox): propagate opacity/border to underlying C drawin   → our PR #407 (Jimmy's split)
- `4be9f21` fix: deliver pointer enter to newly mapped layer surfaces      → our PR #421 (merged)
- `07ac746` fix(stack): preserve LyrOverlay placement for override_redirect → our PR #427 (merged)

### F. rc.lua — CHECK FOR somewm-one PORTS
- `ba586fd` feat(config): rewrite default somewmrc.lua to showcase somewm
  → Fork does NOT track rc.lua. Review this diff for behavior to port into the
    separate `somewm-one` repo (~/git/github/somewm-one). Task #152.

### G. Docs / chore
- `8a64a43` chore: convert issue templates to branch-aware YAML forms
- `6861e7b` docs: link to supported Wayland protocols reference
- `20444fa` docs: point README links at 2.0-dev docs
- `386d232` test: pin kitty initial size to fix test-floating-layout flake
- `26c30db` test: wait for spawn autofocus in carousel tests
- `097d025` test: regression test for c.content at non-unit screen scale
- `bc95dea` test: trim test file headers per CLAUDE.md style
- `1a28429` test: skip content-pattern test on non-LuaJIT builds

---

## 2. PR/issue triage — fork features upstream solved differently

Cross-referencing every raven2cz PR/issue on `trip-zip/somewm`.
**Rule: where upstream solved it correctly, DROP the fork version and take
upstream's. Do not carry fork code that now sits in the wrong place.**

| Our PR | Title | Upstream outcome | Upstream commit | Action |
|--------|-------|------------------|-----------------|--------|
| #478 CLOSED | emit per-client property::geometry in setfullscreen | Jimmy: "got this implemented" — reimplemented his way | `58915a2` | DROP fork version, take `58915a2` |
| #516 CLOSED | handle nil screen on transient_for tag fallback (Lua) | Jimmy: closed in favor of #558, "c layer is the right place... this PR fixes the symptom" | `7c932c7` (PR #558) | DROP fork Lua fix, take `7c932c7` |
| #394 CLOSED | guard XDG surface ops against uninitialized state | Jimmy: fixed "from a different angle by clearing stale seat keyboard focus in unmapnotify()... root cause in one place" | (pre-merge-base unmapnotify fix) | DROP fork guards in client.h/client_activate_surface/client_set_size. KEEP regression test `tests/test-xdg-activate-crash.lua` |
| #427 CLOSED | override_redirect XWayland → overlay layer | MERGED after raven2cz refactored per Jimmy's feedback | `07ac746` | Take `07ac746` (this IS our merged version) |
| #421 CLOSED | deliver pointer enter to newly mapped layer surfaces | MERGED. raven2cz note: complementary to `901e363`, neither subsumes the other | `4be9f21` | Take `4be9f21` |
| #420 CLOSED | (same as #421, closed for unrelated fork history) | superseded by #421 | — | ignore |
| #407 CLOSED | propagate opacity/border to underlying C drawin | MERGED, Jimmy split it for 1.4 + main | `6ead9d8` | Take `6ead9d8` |
| #400 MERGED | drawin shadow/border not refreshed on resize | merged 2026-04-03 (before merge-base) | — | already in fork |
| #391 MERGED | layoutlist assertion crash on monitor hotplug | merged 2026-04-02 (before merge-base) | — | already in fork |
| #384 MERGED | retroactive added::connected signal | merged 2026-04-02 (before merge-base) | — | already in fork |
| #382 MERGED | set_bounds instead of set_size for initial XDG configure | merged 2026-04-02 (before merge-base) | — | already in fork |
| #522 OPEN | defer aerosnap placeholder by dwell | open, undecided | — | re-integrate fork version (still ours) |
| #521 OPEN | preserve focus during cross-monitor mouse-drag | open; `64fe6a7` touches same `unmaplayersurfacenotify()` | `64fe6a7` overlaps | re-evaluate against `64fe6a7`; upstream may not have the bug |
| #515 OPEN | emit somewm::ready / xwayland::ready milestone signals | open, undecided | — | re-integrate fork version |
| #484 OPEN | wallpaper paint with negative output-layout origin | open, undecided | — | re-integrate fork version |
| #476 OPEN | lockscreen background image + blur | open, undecided | — | re-integrate fork version |

### Known DUP commits (fork already has these upstream bugfixes under different SHAs)
From prior-session analysis — VERIFY each by content during migration audit:
`4be9f21`→`6e55d00`, `cb6c2c1`→`ce1a98c`, `901e363`→`ea7e1aa`,
`d27fa2b`→`622cde3`, `bad997d`→`7a3e449`, `9774101`→`e2a196f`, `df53154`→`2a2befa`

---

## 3. File-level classification (git diff --name-status upstream/main..main)

Legend: A = fork-only (re-integrate), M = modified in both (merge), D = upstream-only (adopt as-is)

### D — upstream-only, adopt as-is (the sync branch already has these)
- `event_queue.c`, `event_queue.h` — event-queue infra (fork must migrate ONTO this)
- `nested_inhibitor.c`, `nested_inhibitor.h` — nested compositor test mode
- `test_orchestrator.c`, `test_orchestrator.h`, `tests/test-test-orchestrator.sh`
- `lua/awful/test_marker.lua`, `spec/awful/test_marker_spec.lua`
- `screenshot_compose.h`
- `icons/lucide/*` (32 files), `icons/somewm-logo.svg` — fork removed these; re-confirm intent
- `themes/CREDITS`, `themes/catppuccin/theme.lua`, `themes/gruvbox/theme.lua`, `themes/nord/theme.lua` — fork removed extra themes; re-confirm intent
- `tests/test-event-queue-*.lua` (4), `tests/test-fullscreen-protocol-geometry.lua`,
  `tests/test-hot-reload-transient-screen.lua`, `tests/test-layer-shell-pointer-enter.lua`,
  `tests/test-client-content-dmabuf.lua`, `tests/test-client-content-pattern.lua`,
  `tests/test-content-pattern-client.c`, `tests/test-dmabuf-pattern-client.c`,
  `tests/test-screenshot-interactive-ipc.lua`, `tests/test-screenshot-snipping-surface-scale.lua`,
  `tests/test-wibox-property-propagation.lua`

### A — fork-only, must re-integrate onto upstream base
Core C: `animation.c/h`, `bench.c`(M actually), `scenefx_compat.h`, `shadow.c/h`
Lua: `lua/awful/anim_client.lua`, `lua/somewm/tag_slide.lua`
Build: `subprojects/scenefx.wrap`, `somewm-session`
Docs/infra: `AGENTS.md`, `CLAUDE.md`, `INSTALL.md`, `ARCH-DEP-INSTALL.md`, `.codex`,
  all of `plans/**`, fork test files (`tests/test-scenefx-*`, `tests/test-tag-slide.lua`,
  `tests/test-kolo7-regression.lua`, `tests/test-keyboard-focus-sync.lua`,
  `tests/test-memory-stats.lua`, `tests/test-signal-*.lua`, `tests/test-xdg-*-crash.lua`,
  `tests/test-disconnect-mid-map-client.c`, `spec/menu_spec.lua`, `spec/menu_standalone_test.lua`)

### M — modified in both, needs per-function merge (the migration-audit targets)
C core: `event.c`, `ewmh.c`, `focus.c`, `globalconf.h`, `input.c`, `luaa.c/h`, `monitor.c`,
  `mouse.c`, `property.c/h`, `protocols.c/h`, `root.c`, `selection.c`, `somewm.c/h`,
  `somewm_api.c/h`, `somewm_internal.h`, `somewm_types.h`, `spawn.c`, `stack.c/h`,
  `systray.c`, `window.c/h`, `x11_compat.h`, `xwayland.c`, `client.h`
objects/: `button.c/h`, `client.c/h`, `drawable.c`, `drawin.c`, `ipc.c`,
  `layer_surface.c/h`, `screen.c`, `spawn.h`, `systray.c`, `wibox.c`
common/: `luaclass.c`
animation: `animation.c/h` (fork-heavy, also listed A — actually M, upstream has stubs?)
lgi: `lgi-check.c`, `lgi_closure_guard.c`
Lua: `lua/awful/client.lua`, `lua/awful/input.lua`, `lua/awful/ipc.lua`,
  `lua/awful/mouse/snap.lua`, `lua/awful/permissions/init.lua`, `lua/awful/screenshot.lua`,
  `lua/awful/wallpaper.lua`, `lua/awful/widget/clienticon.lua`, `lua/awful/widget/tasklist.lua`,
  `lua/lockscreen.lua`, `lua/somewm/init.lua`
Build: `Makefile`, `meson.build`, `meson_options.txt`, `package.nix`, `.gitignore`,
  `.stylua.toml`
Docs: `DEVIATIONS.md`, `README.md`, `somewm.1`
Tests (M): many `tests/test-carousel-*.lua`, `tests/test-xwayland-*.lua`, lock tests,
  `tests/_client.lua`, `tests/test-layer-client.c`, etc.

---

## 4. Next steps (per kolo6 methodology)

- [ ] #150 Per-function migration audit of every M file vs upstream refactor
- [ ] #151 Finish triage (verify DUP commits by content; confirm icon/theme removals)
- [ ] #152 Review `ba586fd` rc.lua diff for somewm-one ports
- [ ] #153 Integration plan grouped by feature; dedicated event-queue migration section
      designed WITH the user + Codex
- [ ] #154 Validate plan with Codex gpt-5.5 + Sonnet until GREEN
- [ ] #155 Execute feature-by-feature; event-queue migration tested in sandbox;
      Codex review per block; no merge to main until user live test
