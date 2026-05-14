# Kolo 8 — Upstream Sync Integration Plan (v2)

Date: 2026-05-14
Sync branch: `sync/upstream-2026-05-13` (= `upstream/main` @ `48e19a0`)
Fork main: `5ccffad`

Companion docs:
- `plans/kolo8-fork-delta-inventory.md` — commit window, file classification, PR triage
- `plans/kolo8-migration-audit.md` — per-function A/B/C/D audit, all resolution categories

**Status: v2 — VALIDATED. Codex (gpt-5.5) confirming review = GREEN for Phase 1 execution
after two wording fixes (now applied). Sonnet review of v1 incorporated. Decisions D1/D2/
D4/D5 resolved by user 2026-05-14. The event-queue Phase 4 still needs its own sub-plan
designed jointly with the user + Codex (decision D3) before Phase 4 runs.**
v1→v2 changelog at the bottom.

---

## 0. Guiding rules (from the kolo6 methodology + user instruction 2026-05-14)

- The sync branch IS upstream HEAD. We re-apply fork features ONTO it. We never revert an
  upstream refactor.
- Every fork delta has a verdict in the migration audit: RE-APPLY / DROP / SURGICAL.
- The event-queue migration (Phase 4) is the hardest part — design it WITH the user and
  audit it with Codex BEFORE executing. Test every step in the sandbox.
- Codex review after every phase. Do NOT merge the sync branch to `main` until the user
  runs a live DRM-session test.
- `somewm` framework stays generic — no project-specific code. Generic bugfixes welcome.
- **Diff-direction discipline:** `git diff upstream/main..main` shows `-` = upstream,
  `+` = fork. The fork branched BEFORE both refactors. Always confirm direction with the
  actual repo state (`git show upstream/main:<file>` vs `git show main:<file>`) before
  classifying — v1 misread two files (`lgi_closure_guard.c`, the `exclude` param).

---

## 1. Execution phases (ordered by dependency + risk)

Phases run in order. Each ends with a build + test gate and a Codex review.

### Phase 1 — Build integration + fork-only files (LOW RISK)
No edits to upstream-shared C source. Get SceneFX building on the upstream base.

1.1 **Build files — start FROM upstream, add only fork deltas (do NOT replay fork
    versions).** Upstream's `meson.build` already lists `event_queue.c`,
    `nested_inhibitor.c`, `test_orchestrator.c`, the keyboard-shortcuts-inhibit protocol,
    Lua 5.5 / `-Dlua_pkg`, GPL license/version, dmabuf/content tests. A wholesale fork
    replay would revert all of that. Procedure: open upstream `meson.build` /
    `meson_options.txt` / `Makefile` / `.gitignore` / `.stylua.toml` / `package.nix` and
    ADD only: the `scenefx` dependency + `-Dscenefx` option + `HAVE_SCENEFX` define +
    `scenefx_compat.h`/`shadow.c`/`animation.c` source entries (shadow.c/animation.c may
    already be listed upstream — verify), `subprojects/scenefx.wrap`, the
    `lgi_closure_guard` build target (verify upstream already has it — it does), and the
    fork-only test entries. Diff the result against upstream `meson.build` and confirm
    NOTHING upstream was removed.
1.2 Add fork-only header `scenefx_compat.h`.
1.3 `animation.c`/`animation.h`, `shadow.c`/`shadow.h` — these ARE upstream files (M, not
    A). `shadow.c/h` are a strict superset; `animation.c` is fork-AHEAD (the fork rewrote
    the tick timing — not a literal superset, but the newer/intended version). Upstream did
    NOT touch any of the four in the sync window (verified `git log <merge-base>..upstream/
    main -- animation.* shadow.*` is empty), so applying the fork version wholesale is
    safe. DONE in Phase 1 (commit 55282dc).
1.4 Add fork-only Lua: `lua/awful/anim_client.lua`, `lua/somewm/tag_slide.lua`.
1.5 Add fork-only infra: remaining `plans/**` (this doc + the two companion docs already
    live here), `AGENTS.md`, `CLAUDE.md`, `INSTALL.md`, `ARCH-DEP-INSTALL.md`, `.codex`,
    `somewm-session`, `plans/scripts/*`.
1.6 Add fork-only tests: `tests/test-scenefx-*.lua`, `tests/test-tag-slide.lua`,
    `tests/test-kolo7-regression.lua`, `tests/test-keyboard-focus-sync.lua`,
    `tests/test-memory-stats.lua`, `tests/test-signal-*.lua`, `tests/test-xdg-*-crash.lua`,
    `tests/test-disconnect-mid-map-client.c`, `spec/menu_spec.lua`,
    `spec/menu_standalone_test.lua`.
1.7 **somewm-client.c — DROP all fork deltas, take upstream verbatim.** The fork's version
    removes upstream's `screenshot interactive` subcommand + nested test-mode dispatch
    (`test_orchestrator_run`). Take upstream.
1.8 **somewmrc.lua — DROP fork delta, take upstream `ba586fd` verbatim** on the sync
    branch. The desired behavior is ported into the standalone `somewm-one` repo in
    Phase 7, not carried in the framework repo.
1.9 **Icon/theme files — D2 RESOLVED (smart merge). DONE in the Phase 1 follow-up commit.**
    - `themes/{catppuccin,gruvbox,nord}/theme.lua`, `themes/CREDITS` — KEEP the fork's
      deletion (`git rm`; we maintain our own themes; upstream's are not needed).
    - Consequence: upstream's `somewmrc.lua` referenced `gruvbox`/`catppuccin`/`nord` (default
      `theme_name` + theme-switcher menu). Minimal patch applied to point the default at
      `default` and the switcher at `default`/`zenburn`/`sky` (themes that still exist).
      `somewmrc.lua` is the framework's example config; the user's real config lives in
      the separate `somewm-one` repo, so this is hygiene only.
    - `icons/somewm-logo.svg` — TAKE upstream's new logo (already present; somewm branding).
    - `icons/lucide/*` (33 files) — TAKE upstream's (already present; generic icon set).

**Gate:** `ninja -C build-test` clean with `-Dscenefx=auto` AND with scenefx disabled.
Fork-only Lua specs pass. `meson.build` diff vs upstream confirmed additive-only. Codex
review of Phase 1.

### Phase 2 — Headers + globalconf + lifecycle + lgi guard (MEDIUM RISK)
Files: `globalconf.h`, `somewm.h`, `somewm_internal.h`, `somewm_types.h`, `somewm.c`,
`luaa.c`, `luaa.h`, `somewm_api.h`, `protocols.h`, `x11_compat.h`, `objects/spawn.h`,
`spawn.c`, `objects/client.h`, `objects/layer_surface.h`, `client.h` (struct/decl parts
only), `lgi_closure_guard.c`.

2.1 `globalconf.h` — RE-APPLY fork fields (`memory_stats`, `somewm_ready_seen`,
    `xwayland_ready_seen`, `wallpaper_cache_entry_t` size fields, `MemoryStats` typedef,
    `wallpaper_cache_lookup` decl, `<stddef.h>`). DROP the fork's `xkb_model`/`xkb_rules`
    removal — keep upstream's keyboard fields.
2.2 `somewm_types.h`, `somewm.h` — `scenefx_compat.h` swap; `optimized_blur_layer`
    extern/global.
2.3 `somewm_internal.h`, `protocols.h` — **DROP the fork's `exclude`-param signatures**
    for `some_recompute_idle_inhibit` / `some_is_idle_inhibited`. Upstream `7aa9351`
    removed the param; take upstream's `(void)` form. (v1 had this backwards.)
2.4 `somewm_api.h` — RE-APPLY only `some_update_pointer_constraint`, `cold_restart`,
    `rebuild_restart` decls. DROP the idle-inhibit / hot-reload / `apply_input_settings`
    dup decls (`ed4b4cf` removed them; canonical decls live in module headers). Any
    `exclude`-param idle-inhibit decl here is also DROP per 2.3.
2.5 `x11_compat.h`, `objects/spawn.h`, `spawn.c` — DROP all fork deltas (header-dedup
    collisions). Keep upstream verbatim.
2.6 `client.h`, `objects/client.h`, `objects/layer_surface.h` — RE-APPLY fork struct
    fields (`border_frame`, `corner_radius`, `backdrop_blur`, `minimize` listener,
    `floating`, `strict_clip`) + fork-new function decls (`client_apply_corner_radius`
    etc., `layer_surface_apply_opacity_to_scene`) + `scenefx_compat.h` swaps. DROP the
    PR #394 `initialized` guards in `client.h` (triage drop). Single declaration per
    `ed4b4cf` rule.
2.7 `lgi_closure_guard.c` — **RE-APPLY the fork version wholesale.** The FORK is ahead
    (413 lines, two-layer rewrite: `lgi_guard_begin_reload`/`mark_ready`,
    `closure_registry`, `safe_cif`, `ffi_closure_free` interpose); upstream is the old
    216-line single-layer guard. (v1 had this backwards.) `luaa.c`'s hot-reload dlsym
    calls depend on this — must land before / with 2.9.
2.8 `somewm.c` lifecycle — RE-APPLY: `optimized_blur_layer` global + `setup()` blur init;
    `cold_restart()`/`rebuild_restart()` + `globalconf.exit_code`; `main()` returns
    `exit_code`; `run()` `somewm_ready_seen`/`somewm::ready` emit. KEEP upstream's
    `nested_inhibitor_init()`, `some_event_queue_init()` in `setup()`,
    `some_event_queue_wipe()` in `cleanup()`, `some_event_queue_drain()` Step 0 in
    `some_refresh()`, `SOMEWM_TEST_NAME`/test_marker block in `run()`, xkb init, and the
    no-arg `some_recompute_idle_inhibit()` calls. Reconcile fork's `some_refresh()` bench
    rewrite (scalar vs array timers) while preserving the drain. `animation_tick_all()`
    slots in AFTER the drain.
2.9 `luaa.c` lifecycle — RE-APPLY: `cold_restart`/`rebuild_restart` Lua methods;
    `luaA_awesome_sync` deferred flush; tag-slide helpers
    (`luaA_awesome_client_scene_set_enabled`/`_set_strict_clip`); `somewm_ready`/
    `xwayland_ready` index keys; SceneFX include swap; hot-reload Lgi closure-guard
    (`lgi_guard_begin_reload()` gate before Phase A teardown);
    `somewm::ready`/`xwayland::ready` re-emit at end of `luaA_hot_reload`. KEEP upstream's
    `some_event_queue_reset()`/`some_event_queue_pending()` in `luaA_hot_reload`, the
    two-pass screen-assignment with queued `SIG_PROPERTY_*` emits, `config_paths[8]={NULL}`
    init, and the 4 explicit dedup includes. DROP the fork's `(NULL)` idle-inhibit call
    args — take upstream's no-arg calls. Lua 5.5 cap (`< 506`) — keep upstream.
2.10 `luaa.h` — keep upstream's `< 506` Lua 5.5 cap.

**Gate:** build clean (scenefx on + off). Hot-reload smoke test in sandbox (confirm the
lgi guard preload works — no "stale closures may crash" warning). Codex review.

### Phase 3 — Non-event-queue C fork features (MEDIUM RISK)
Files: `root.c`, `somewm_api.c`, `stack.c`/`stack.h`, `monitor.c`, `property.c`/`property.h`,
`selection.c`, `bench.c`, `systray.c`, `objects/drawable.c`, `objects/wibox.c`,
`objects/button.c`/`objects/button.h`, `objects/client.c` (feature subsystems only — NOT
the signal-emit hunks), `objects/layer_surface.c` (opacity subsystem only),
`objects/drawin.c` + `objects/screen.c` (include swap only).

3.1 `root.c` — RE-APPLY entire fork delta as-is (wallpaper multi-monitor/negative-origin,
    memory diagnostics, tag-slide overlays, `luaA_root_geometry`, screenshot_compose
    inlining, `malloc_trim`, scenefx swap).
3.2 `somewm_api.c` — RE-APPLY `some_set_seat_keyboard_focus` old/new surface handling +
    `some_update_pointer_constraint` call + `wlr_layer_shell_v1.h` include. DROP the
    `rules.model`/`rules.rules` removal (upstream `48e19a0`). DROP any `exclude`-param
    idle-inhibit call args (per 2.3).
3.3 `stack.c`/`stack.h` — SURGICAL: keep upstream `07ac746` `stack_refresh` + xwayland
    include; RE-APPLY `WINDOW_LAYER_FLOATING` enum + `client_layer_translator` rewrite +
    `get_scene_layer` `LyrFloat` case + scenefx swap. Verify no conflict with `2b6413c`
    carousel cross-monitor rendering.
3.4 `monitor.c` — SURGICAL: keep upstream `b2d98fe` `createmon` guards +
    `nested_inhibitor_attach_output` + include; RE-APPLY scenefx swap, `fx_renderer_create`,
    `optimized_blur_layer` resize, `rendermon` bench restructure, `banning_pending`/
    `motionnotify(0,...)` pointer-focus-after-hotplug fix.
3.5 `property.c`/`property.h` — RE-APPLY xproperty stubs.
3.6 `selection.c` — RE-APPLY `luaA_selection_get` hard-error. D4 RESOLVED: the change to
    `luaL_error` is intentional API hardening — re-apply it.
3.7 `bench.c`, `systray.c` — RE-APPLY `scenefx_compat.h` swap.
3.8 `objects/drawable.c`, `objects/wibox.c` — RE-APPLY memory diagnostics + scenefx swap.
3.9 `objects/button.c`/`objects/button.h` — RE-APPLY button-matching helper layer.
3.10 `objects/client.c` feature subsystems — RE-APPLY corner_radius/backdrop_blur subsystems,
    `client_border_refresh` rounded-corner+opacity, `client_apply_opacity_to_scene` extended,
    `client_ban_unfocus` mousegrabber guard, `client_set_minimized` arrange rework,
    `client_set_maximized_common` toplevel_set_maximized, `luaA_client_set_floating` +
    `_c_floating`, titlebar corner hooks, `luaA_client_get_content` rewrite + `_scene_layer`
    removal, `client_clear_scene_child_pointers`. DROP PR #394 leftovers. Re-add
    `#include "../event_queue.h"`. **Mark every Phase-4 signal-emit hunk with a
    `// TODO(kolo8-phase4)` comment instead of leaving it bare** — Phase 4 resolves the
    TODOs. Codex diff review after 3.10 must confirm NO signal-emit hunk was modified.
3.11 `objects/layer_surface.c` opacity subsystem — RE-APPLY (`ls_apply_opacity_to_tree`
    etc.). Downgrade the `[LS-OPACITY] SKIP` log from `WLR_ERROR` to `WLR_DEBUG`.
    Signal-emit hunks deferred to Phase 4.
3.12 `objects/drawin.c`, `objects/screen.c` — RE-APPLY only the `scenefx_compat.h` include
    swap. Everything else: take upstream (`b66d3cf`, `e3c6990`, `6ead9d8` already merged).
3.13 `objects/ipc.c`, `lgi-check.c` — DROP all fork deltas, take upstream (fork is behind).
    (`lgi_closure_guard.c` moved to Phase 2.7 — fork is AHEAD there.)

**Gate:** build clean. Run carousel + lock + xwayland + scenefx test suites in sandbox.
Codex review (must confirm 3.10 left signal hunks untouched).

### Phase 4 — EVENT-QUEUE MIGRATION (HIGHEST RISK — design with user + Codex first)
Files: `focus.c`, `input.c`, `mouse.c`, `window.c`, `window.h`, `objects/client.c` (signal
hunks), `objects/layer_surface.c` (signal hunks), `ewmh.c`, `protocols.c`, `xwayland.c`,
`objects/systray.c`, `event.c`, `common/luaclass.c`.

**This phase is NOT executed until its sub-plan is designed jointly with the user and
audited by Codex.** The sub-plan will be written as `plans/kolo8-event-queue-migration.md`
(decision D3).

Principles established by the audit (NARROWED after Codex review, twice):
- The rule "DROP the fork's synchronous emit, take upstream's queued form" applies ONLY to
  the *exact* signals upstream moved into the `SIG_*` enum (`event_queue.h`): the property
  geometry family (`SIG_PROPERTY_GEOMETRY/POSITION/SIZE/X/Y/WIDTH/HEIGHT`), focus
  (`SIG_PROPERTY_ACTIVE/FOCUS/UNFOCUS/CLIENT_FOCUS/CLIENT_UNFOCUS`), mouse
  (`SIG_MOUSE_ENTER/LEAVE/MOVE`), lifecycle (`SIG_LIST/SWAPPED`), the request set
  (`SIG_REQUEST_ACTIVATE/URGENT/TAG/SELECT`, `SIG_SYSTRAY_SECONDARY_ACTIVATE/CONTEXT_MENU/
  SCROLL`), `SIG_CLIENT_PROPERTY_GEOMETRY`, plus the bare `manage`/`unmanage` removal
  (`affdf56`). The upstream queued form (`some_event_queue_signal0/signal/global/move/class`)
  is authoritative for those.
- **KEPT SYNCHRONOUS by upstream — do NOT convert, do NOT drop:** `request::manage`,
  `request::unmanage`, `request::geometry`, and layer `request::keyboard` are NOT in the
  `SIG_*` enum — upstream deliberately keeps them synchronous (verified in
  `upstream/main:objects/client.c` and `objects/layer_surface.c`). Leave them as
  `luaA_object_emit_signal`. Note the distinction: the BARE `manage`/`unmanage` signals
  were removed by `affdf56` and every fork emit of them IS dropped; the `request::`-prefixed
  ones are different signals and survive.
- **EXCEPTION — fork-new signals that upstream never had and that are NOT in the `SIG_*`
  enum stay SYNCHRONOUS `luaA_emit_signal_global` and are RE-APPLIED, not dropped:**
  `screen::focus` (input.c motionnotify hover crossing), `somewm::ready` (somewm.c run +
  luaa.c hot-reload), `xwayland::ready` (xwayland.c + luaa.c hot-reload). Verified: upstream
  still emits `screen::focus` synchronously at `input.c:567`; no `SIG_*` entry exists for
  any of these; no must-add `SIG_*` case. Fork property-setter signals
  (`property::_c_floating`, `property::corner_radius`, `property::backdrop_blur`, layer
  `property::opacity`) also stay synchronous — emitted on a fresh object push, which is
  correct.
- `ewmh.c`, `objects/systray.c`, `event.c`, `common/luaclass.c` have NO fork features —
  take upstream verbatim, drop the entire fork delta.
- Fork features interleaved with converted signal emits must be re-expressed onto the
  queued form, NOT pasted around synchronous calls. Biggest cases:
  - `window.c`: `maximizenotify()`/`minimizenotify()` Lua-routing rework (upstream still
    has stubs), `client_clear_scene_child_pointers`, `schedule_flush_clients`,
    `commitnotify` bench + corner/blur. DROP PR #478 setfullscreen geometry emit + the
    fork `resize()` signal block (keep only aspect-ratio math). `window.h` — RE-APPLY the
    `schedule_flush_clients` + `struct wl_display` forward decls (pairs with the impl).
  - `objects/client.c`: resolve the `// TODO(kolo8-phase4)` markers from Phase 3.10 — the
    `client_unfocus_internal`/`client_focus_update`/`client_manage`/`client_resize_do`/
    `client_unmanage`/`luaA_client_swap` emit conversions.
  - `protocols.c`: PR #521 focus guard in `unmaplayersurfacenotify` (re-applies cleanly on
    top of `64fe6a7` — no conflict), `commitlayersurfacenotify` opacity re-apply,
    `createlayersurface` listener reorder. DROP the idle-inhibit `exclude` hunks (fork is
    behind — upstream `7aa9351` removed the param).
  - `xwayland.c`: RE-APPLY only the `xwaylandready` `xwayland::ready` synchronous emit;
    DROP the `request::*` / `client::list` emit-call conversions (take upstream queued).
  - `input.c`/`focus.c`/`mouse.c`: see Group 1 audit — bench gating, `CurPressed`→
    `button_count`, `screen::focus` on hover (synchronous, RE-APPLY), grab-end re-entry,
    `deferred_pointer_enter` are RE-APPLY; xkb NULLing and `luaA_mouse_fake_motion` removal
    are DROP. `keyrepeat()` `!locked` guard — D5 RESOLVED: DROP the fork's change, keep
    upstream's `!locked` session-lock guard (fork's removal was a stale edit).
- ⚠️ Double-emit is the primary failure mode. After this phase, grep these files for any
  surviving `luaA_object_emit_signal` of a `SIG_*`-converted signal name.

**Gate:** the 4 upstream `tests/test-event-queue-*.lua` MUST pass, plus all focus/mouse/
xwayland regression tests. Live sandbox test of focus, mouse hover across monitors, drag,
layer-surface map. Codex review of the diff. THEN user live DRM test gate at the very end.

### Phase 5 — Lua fork features (MEDIUM RISK)
Files: `lua/awful/mouse/snap.lua`, `lua/awful/wallpaper.lua`, `lua/lockscreen.lua`,
`lua/somewm/init.lua`, `lua/awful/client.lua`, `lua/awful/widget/clienticon.lua`,
`lua/awful/widget/tasklist.lua`.

5.1 `snap.lua` — RE-APPLY aerosnap dwell-gate (PR #522). Clean.
5.2 `wallpaper.lua` — RE-APPLY `paint()` negative-origin fix (PR #484). Clean. Depends on
    `root.c` `luaA_root_geometry` (Phase 3.1).
5.3 `lockscreen.lua` — RE-APPLY background-image feature (PR #476) wholesale.
5.4 `somewm/init.lua` — RE-APPLY `tag_slide` submodule line.
5.5 **Icon resolution unit** (`client.lua` + `clienticon.lua` + `tasklist.lua`) —
    D1 RESOLVED: adopt upstream's `resolve_icon`. DROP the fork's `client.get_icon_path`
    API + inline pixbuf load in `request::manage`; take upstream's `client.resolve_icon`
    (StartupWMClass + `.desktop` cache). Rewrite the two widget consumers (`clienticon.lua`
    full-widget rewrite and `tasklist.lua` icon line) to use upstream's `c.icon` /
    `resolve_icon` instead of `get_icon_path`. Keep RE-APPLY: the separate `property::floating`
    → `_c_floating` handler in `client.lua` (it is unrelated to icons). Migrate the three
    icon files atomically as a unit; busted specs after.
5.6 `lua/awful/input.lua`, `lua/awful/ipc.lua`, `lua/awful/screenshot.lua` — DROP all fork
    deltas, take upstream (fork is behind).
5.7 `lua/awful/permissions/init.lua` — DROP the PR #516 nil-screen change (triage drop;
    upstream's C-layer fix `7c932c7` supersedes it).

**Gate:** busted specs pass. Sandbox test of wallpaper, lockscreen, tasklist icons,
tag-slide. Codex review.

### Phase 6 — Tests + triage cleanup (LOW RISK)
6.1 Reconcile M test files (`tests/test-carousel-*`, `tests/test-xwayland-*`, lock tests,
    `tests/_client.lua`, `tests/test-layer-client.c`) — most fork deltas here are
    test-helper updates; merge per migration audit, keep upstream's new tests
    (`tests/test-event-queue-*`, etc.).
6.2 `tests/test-client-silent-geometry.lua` — DROP the fork hunk (fork asserts immediately
    after `c:geometry()`; upstream split the assertion into the next runner step for
    queued dispatch). Take upstream. Keep upstream's kitty initial-size pin in
    `tests/_client.lua` (`386d232`).
6.3 Confirm triage-drop regression tests are kept: `tests/test-xdg-activate-crash.lua`
    (from PR #394 — the test stays even though the C guard is dropped; it now exercises
    upstream's `unmapnotify` fix).
6.4 Full test suite green on the sync branch.

**Gate:** full `ninja test` green. Codex review of the whole branch diff vs `main`.

### Phase 7 — somewm-one ports (SEPARATE REPO, LOW RISK)
Not on the sync branch. In `~/git/github/somewm-one`: review the rc.lua API/behavior list
in `plans/kolo8-migration-audit.md` §"rc.lua → somewm-one ports". Port what the user's
config needs (per-screen wallpaper signal, named tags + connector-keyed persistence,
signal-driven layouts/keybindings/rules, interactive screenshot, `naughty.suspended`,
`awful.input.*` xkb surface, etc.). Config work, done after the compositor sync is
live-tested and merged.

---

## 2. Decisions

**D1 — Icon resolution API (Phase 5.5). RESOLVED 2026-05-14:** adopt upstream's
`resolve_icon`. DROP the fork's `client.get_icon_path` API; rewrite `clienticon.lua` +
`tasklist.lua` to use upstream's `c.icon` / `resolve_icon`.

**D2 — icon/theme file deletions (Phase 1.9). RESOLVED 2026-05-14 (smart merge):** keep the
fork's deletion of `themes/{catppuccin,gruvbox,nord}/theme.lua` + `themes/CREDITS` (we keep
our own themes); take upstream's new `icons/somewm-logo.svg` (somewm branding) and
`icons/lucide/*` (generic, may be referenced).

**D3 — Event-queue migration sub-plan (Phase 4). OPEN.** Per user instruction, the
event-queue migration must be designed jointly with the user and Codex before execution.
After this v2 plan is confirmed, write `plans/kolo8-event-queue-migration.md` and review it
with the user + Codex.

**D4 — `selection.c` hard-error (Phase 3.6). RESOLVED 2026-05-14:** the change to
`luaL_error` is intentional API hardening — re-apply it.

**D5 — `input.c` `keyrepeat()` `!locked` guard (Phase 4). RESOLVED 2026-05-14:** DROP the
fork's change, keep upstream's `!locked` session-lock guard (fork's removal was a stale
edit).

---

## 3. Risk register

| Risk | Phase | Mitigation |
|------|-------|------------|
| Double-emit of converted signals | 4 | Post-phase grep for `luaA_object_emit_signal` of `SIG_*` names; event-queue test suite must pass |
| Fork removal of upstream queue lifecycle silently reverts the refactor | 2, 4 | Audit explicitly lists every "DO NOT carry deletion"; Codex review |
| `objects/client.c` edited in Phase 3 AND Phase 4 (interleaved feature + signal hunks) — double-edit hazard | 3, 4 | Phase 3.10 marks every Phase-4 hunk with `// TODO(kolo8-phase4)`; Codex review after 3.10 confirms no signal hunk touched; Phase 4 resolves the TODOs |
| Build-file replay reverts upstream additions (event_queue.c, test_orchestrator.c, Lua 5.5) | 1 | Phase 1.1 starts FROM upstream `meson.build`; final diff-vs-upstream must be additive-only |
| Diff-direction misread (fork-ahead vs fork-behind) | all | v2 added diff-direction discipline rule §0; verify each file's direction against repo state, not just the diff sign |
| `maximizenotify`/`minimizenotify` rework is large and lives among queued emits | 4 | Isolate the Lua-routing rework from the emit conversion; review separately |
| Header-dedup collisions re-introduce duplicate decls | 2 | Audit lists every collision; build will catch dup-decl errors |
| Icon unit migration breaks tasklist/clienticon | 5 | D1 decided up front; migrate the 3 files atomically; busted specs |
| `scenefx_compat.h` swap missed in some file | 1-4 | Final grep for `<wlr/types/wlr_scene.h>` in fork-touched files |
| stack.c `WINDOW_LAYER_FLOATING` conflicts with carousel cross-monitor render | 3 | Explicit verification step in 3.3 against `2b6413c` |
| Branch merged before live test | end | Hard rule: no merge to `main` until user DRM-session test |

---

## 4. v1 → v2 changelog (from Codex + Sonnet review, both YELLOW)

1. **`exclude` param direction corrected** — `7aa9351` REMOVED the `exclude` param; fork
   has the stale form. DROP fork's `exclude` signatures + `(NULL)` call args everywhere
   (Phase 2.3, 2.4, 2.8, 2.9, 3.2; Phase 4 protocols.c). v1 had it backwards.
2. **`lgi_closure_guard.c` direction corrected** — fork is AHEAD (two-layer rewrite, 413
   lines vs upstream 216). Moved from Phase 3.13 DROP to Phase 2.7 RE-APPLY.
3. **Build-file phase tightened** — Phase 1.1 now explicitly starts FROM upstream
   `meson.build` and adds only fork deltas; wholesale replay would revert upstream.
4. **`somewm-client.c` triaged** — added Phase 1.7, DROP fork delta, take upstream.
5. **`somewmrc.lua` verdict added** — Phase 1.8 takes upstream `ba586fd`; Phase 7 ports
   behavior to `somewm-one`.
6. **`window.h` added to Phase 4** — RE-APPLY the `schedule_flush_clients` + `struct
   wl_display` decls.
7. **`protocols.h` added to Phase 2.3** — DROP fork's `exclude`-param signature.
8. **Event-queue principle narrowed** — Phase 4 now explicitly lists the fork-new
   synchronous signals (`screen::focus`, `somewm::ready`, `xwayland::ready`, fork property
   setters) that are RE-APPLIED, not dropped.
9. **`objects/client.c` two-phase hazard** — added to risk register; Phase 3.10 marks
   Phase-4 hunks with TODO comments.
10. **`tests/test-client-silent-geometry.lua`** — explicit DROP verdict added (Phase 6.2).
11. **`[LS-OPACITY]` log** — Phase 3.11 downgrades `WLR_ERROR` → `WLR_DEBUG`.
12. **D2 gating** — Phase 1.9 explicitly BLOCKED on the D2 user decision.

**Post-v2 Codex confirming review (GREEN for Phase 1) — two wording fixes applied:**
13. `somewm_api.h` audit wording corrected: "use upstream's no-arg signatures" (not
    "exclude-param signatures").
14. Event-queue principle narrowed again in both docs: only the exact `SIG_*` enum signals
    are converted; `request::manage`/`request::unmanage`/`request::geometry`/layer
    `request::keyboard` are explicitly KEPT synchronous (upstream never queued them).

**Decisions resolved by user 2026-05-14:** D1 (upstream `resolve_icon`), D2 (smart merge:
keep our themes, take upstream logo + lucide icons), D4 (re-apply hard error), D5 (keep
upstream `!locked` guard). D3 (event-queue sub-plan) remains open by design.

---

## 5. Next actions

1. Confirming review pass of v2 with Codex + Sonnet (task #154). Iterate to GREEN.
2. Resolve open decisions D1, D2, D4, D5 with the user.
3. Write the Phase-4 event-queue migration sub-plan; review it with user + Codex (D3).
4. Execute Phases 1-7 in order, Codex review after each, sandbox tests throughout.
5. User live DRM-session test before merging `sync/upstream-2026-05-13` to `main`.
