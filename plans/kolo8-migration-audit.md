# Kolo 8 — Per-Function Migration Audit

Date: 2026-05-14
Sync branch: `sync/upstream-2026-05-13` (= `upstream/main` @ `48e19a0`)
Fork main: `5ccffad` (163 commits ahead of merge-base `493fda4`)

**Diff direction:** `git diff upstream/main..main` → `-` lines = upstream (post-refactor),
`+` lines = fork (pre-refactor). The fork branched BEFORE both upstream refactors
(event-queue, header-dedup ed4b4cf), so many "fork deltas" are just the fork being
*behind* — those must take the upstream side, not be re-applied.

**Three resolution categories per fork delta:**
- **RE-APPLY** — genuine fork feature, port onto upstream base
- **DROP** — fork is behind upstream, or upstream solved it differently (triage); take upstream
- **SURGICAL** — take upstream base, re-apply only the true fork-additive hunks on top

---

## GROUP 1 — focus.c, input.c, mouse.c (event-queue zone, HIGH RISK)

All fork signal hunks here are pre-refactor synchronous `luaA_object_emit_signal`.
Upstream already migrated to `some_event_queue_*`. **A naive 3-way merge keeping fork
lines causes DOUBLE-EMIT** (`client::focus/unfocus`, `mouse::enter/leave/move` fire
twice) and loses `mouse::move` coalescing.

### focus.c
- **focusclient() unfocus + focus signals** → DROP fork's synchronous emits, take
  upstream's `some_event_queue_signal(SIG_PROPERTY_ACTIVE)`, `..signal0(SIG_UNFOCUS/SIG_FOCUS)`,
  `..global(SIG_CLIENT_UNFOCUS/SIG_CLIENT_FOCUS)`. No fork-unique logic in these hunks.
- **includes** → keep `scenefx_compat.h` swap (SceneFX); MUST re-add `#include "event_queue.h"`
  (fork removed it).

### input.c
- **buttonpress()/keypress() bench guard** → RE-APPLY: fork gates `bench_input_event_record()`
  on `state == PRESSED`, moved after struct decls. Real improvement.
- **motionnotify() bench removal** → RE-APPLY: fork deletes `bench_input_event_record()` from
  motionnotify (motion shouldn't count as latency start).
- **motionnotify() CurPressed → button_count** → RE-APPLY: fork changes
  `cursor_mode == CurPressed` → `seat->pointer_state.button_count > 0` at input.c:760.
  This is the pointer-focus regression fix (project_pointer_focus_curpressed_fix). Only
  that one site; upstream keeps CurPressed elsewhere (485, 1876, 1892).
- **mouse_emit_leave/enter + mouse::move emits** → DROP fork's synchronous calls, take
  upstream's `some_event_queue_signal0(SIG_MOUSE_LEAVE/ENTER)` and `some_event_queue_move()`.
- **motionnotify() screen::focus on hover crossing** → RE-APPLY (multi-monitor fix:
  emit `screen::focus` when `mon != selmon` during hover). FLAG: decide sync vs queued
  form — match whatever form upstream's buttonpress `screen::focus` (input.c:567) uses
  post-refactor (it survived synchronous, so synchronous may be fine).
- **motionnotify() grab-end re-entry** → RE-APPLY: `motionnotify(0,NULL,0,0,0,0)` after
  `luaA_mousegrabber_stop()`. Not signal-related, clean add.
- **deferred_pointer_enter() + pointerfocus() idle re-delivery** → RE-APPLY: static
  `pointer_enter_deferred_pending` flag + idle callback when client has no wl_pointer
  resources yet. Focus/pointer regression fix.
- **keyrepeat() locked guard removal** → ⚠️ SCRUTINIZE: fork drops `!locked` (session-lock)
  check: `if (!locked && some_keygrabber_is_running())` → `if (some_keygrabber_is_running())`.
  Likely a fork bug or stale edit. Do NOT blindly re-apply — verify intent.
- **createkeyboardgroup() xkb rules/model NULLed** → ⚠️ DIRECT CONFLICT with upstream HEAD
  `48e19a0` ("support specifying XKB model and rules"). Fork sets `rules.rules=NULL;
  rules.model=NULL;`; upstream sets them from `globalconf.keyboard.xkb_rules/xkb_model`.
  **DROP fork side, take upstream.** Verify the fork's original XKB-fix motivation is
  satisfied by upstream's new mechanism.
- **includes** → keep `scenefx_compat.h`; re-add `#include "event_queue.h"`.

### mouse.c
- **luaA_mouse_fake_motion removed** → DROP fork's deletion. The fork only "removed" it
  because it's behind; `some_fake_motion` still exists upstream (somewm_api.c:1365, root.c).
  Keep upstream's `luaA_mouse_fake_motion` + `_fake_motion` method registration.

### input.c stale removals
- `some_update_pointer_constraint` / `some_fake_motion` show as fork-removed but exist
  upstream — these were upstreamed. Check upstream input.c/somewm_api.c before re-adding;
  likely already present, do not duplicate. (See Group 4 somewm_api.h.)

---

## GROUP 2 — window.c, objects/client.c, objects/layer_surface.c, client.h,
##           objects/client.h, objects/layer_surface.h (event-queue zone, HIGH RISK)

### window.c
- **manage/unmanage signal re-emit** (mapnotify, both transient + normal paths) → DROP.
  Upstream `affdf56` removed these signals entirely.
- **synchronous property emits in mapnotify()** → DROP fork's `luaA_object_emit_signal`,
  take upstream's `some_event_queue_signal0(SIG_PROPERTY_*)`. Same for `createnotify()`
  `client::list` → `some_event_queue_class(&client_class, SIG_LIST)`, `swapstack()`
  (SIG_LIST, SIG_SWAPPED), `request::activate` → `some_event_queue_signal(SIG_REQUEST_ACTIVATE)`.
- **setfullscreen() per-client property::geometry (PR #478)** → DROP. Upstream `58915a2`
  reimplemented this inside `resize()`. Double-emit risk if kept.
- **resize() per-instance geometry signals** → DROP fork's signal block (upstream `58915a2`
  has the queued version). RE-APPLY only the fork's aspect-ratio content-area math.
- **fullscreennotify() rework** → DROP fork's extra `property::fullscreen` emit (upstream's
  `setfullscreen` already emits it unconditionally → double-emit).
- **forward declarations (~25)** → DROP. Header-dedup `ed4b4cf` moved these to `window.h`.
- **fork-unique, RE-APPLY as-is:** `client_clear_scene_child_pointers()` + calls from both
  unmap paths; `schedule_flush_clients()`/`flush_clients_idle()` (issue #530);
  `commitnotify()` bench-ordering + `client_apply_corner_radius/backdrop_blur`;
  `maximizenotify()`/`minimizenotify()` full Lua-routing rework (upstream still has stubs —
  large conflict, no queue API involved); `apply_geometry_to_wlroots()` initialized-guard;
  `setmon()` `c->prev` ownership comment; `unmapnotify()` early-exit `commit.link` removal;
  `initialcommitnotify` maximize/minimize capability bits; `scenefx_compat.h` swap.
  ⚠️ OVERLAP: fork's `client_layout_clips_offscreen` removal + cross-monitor rendering in
  `apply_geometry_to_wlroots()` partially duplicates upstream `9774101`/`2b6413c`/`e7c14e6` —
  reconcile, don't double-apply.

### objects/client.c
- **event-queue emits throughout** (`client_unfocus_internal`, `client_focus_update`,
  `client_manage`, `client_resize_do`, `client_unmanage`, `luaA_client_swap`) → DROP fork's
  `luaA_*` form, take upstream's `some_event_queue_*`.
- **manage/unmanage re-emit** (client_manage `/*TODO v6*/`, client_unmanage) → DROP (`affdf56`).
- **client_set_fullscreen / client_set_maximized_common comment-only deltas** → take upstream
  (keeps the "Synchronous:" comments explaining queue interaction).
- **includes** → re-add `#include "../event_queue.h"`; `screenshot_compose.h` removal pairs
  with B6 below; `mousegrabber.h` added by fork.
- **fork-unique, RE-APPLY as-is:** `client_ban_unfocus` mousegrabber guard; `client_border_refresh`
  rounded-corner + opacity-alpha preservation; corner_radius/backdrop_blur subsystems
  (`client_apply_corner_radius`, `client_update_border_for_corners`, `client_apply_backdrop_blur`
  + Lua props); `client_set_minimized` xdg-state-via-arrange rework;
  `client_set_maximized_common` `wlr_xdg_toplevel_set_maximized` call; `luaA_client_set_floating`
  + `_c_floating` property; `client_apply_opacity_to_scene` extended to borders/shadow/frame;
  titlebar corner-radius hooks.
- **luaA_client_get_content rewrite + _scene_layer removal** → RE-APPLY as-is (issue #539,
  direct buffer/texture readback; deletes `luaA_client_get__scene_layer` + `extern layers[]`
  dependency). No refactor conflict; confirm upstream didn't touch `content` (it didn't).

### objects/layer_surface.c
- **layer_surface_manage / layer_surface_emit_unmanage** `luaA_class_emit_signal("list")` →
  DROP, take upstream's `some_event_queue_class(&layer_surface_class, SIG_LIST)`; re-add
  `#include "../event_queue.h"`.
- **fork-unique opacity subsystem** → RE-APPLY as-is: `ls_apply_opacity_to_tree`,
  `layer_surface_apply_opacity_to_scene`, `luaA_layer_surface_{get,set}_opacity`, `opacity`
  class property, includes. No event-queue interaction (`property::opacity` via plain
  `luaA_object_emit_signal` is correct on a fresh push). Consider downgrading the
  `[LS-OPACITY] SKIP` `wlr_log(WLR_ERROR,...)` debug noise.

### client.h
- **PR #394 `initialized` guards** in `client_activate_surface()` (`if (!toplevel->base->initialized)
  return;` + `[FOCUS-ACTIVATE]` debug logs) and `client_set_size()`
  (`if (!c->surface.xdg->initialized) return 0;`) → DROP. Upstream rejected #394 and fixed
  the crash by clearing stale seat keyboard focus in `unmapnotify()`
  (`wlr_seat_keyboard_clear_focus`, present upstream). Drop both guards + all `[FOCUS-*]`
  `wlr_log` debug lines in `client_activate_surface`/`client_notify_enter`.
- **client_set_border_color scenefx border_frame branch** → RE-APPLY as-is.

### objects/client.h
- forward decls `client_apply_corner_radius/backdrop_blur/update_border_for_corners` → keep,
  single declaration (ed4b4cf rule); verify no dup in objects/client.c.
- struct fields `border_frame`, `corner_radius`, `backdrop_blur`, `struct wl_listener minimize`,
  `bool floating`, `bool strict_clip` + `scenefx_compat.h` swap → RE-APPLY as-is, no conflict.

### objects/layer_surface.h
- `layer_surface_apply_opacity_to_scene` decl → RE-APPLY, single declaration, no dedup conflict.

---

## GROUP 3 — event.c, common/luaclass.c, luaa.c, luaa.h, somewm.c, somewm.h,
##           globalconf.h, somewm_internal.h, somewm_types.h (event infra + main loop)

### event.c
- No fork feature. Fork shows synchronous `mouse::enter/leave` + no `event_queue.h` include.
  → DROP fork side entirely, take upstream verbatim (`some_event_queue_signal0`).

### common/luaclass.c
- No fork delta. The ~20 added lines are upstream's `client.manage/unmanage` deprecation shim.
  → take upstream verbatim.

### luaa.c — HIGH RISK, multiple genuine fork features
- **RE-APPLY:** `luaA_cold_restart`/`luaA_rebuild_restart` + `awesome_methods[]` entries;
  `luaA_awesome_sync` deferred flush (`wl_display_flush_clients` → `schedule_flush_clients`);
  tag-slide helpers `luaA_awesome_client_scene_set_enabled`/`_set_strict_clip`;
  `somewm_ready`/`xwayland_ready` index keys in `luaA_awesome_index`; SceneFX include swap;
  hot-reload Lgi closure-guard (`lgi_guard_begin_reload()` dlsym block in `luaA_hot_reload`
  and config-timeout path; `luaA_cleanup_stale_glib_sources` drops per-call
  `lgi_guard_bump_generation`); `somewm::ready`/`xwayland::ready` re-emit at end of
  `luaA_hot_reload`.
- ⚠️ **DO NOT carry fork's DELETIONS of `some_event_queue_reset()`/`some_event_queue_pending()`**
  in `luaA_hot_reload`. Keep upstream's queue lifecycle; insert `lgi_guard_begin_reload()`
  gate before Phase A teardown (sits before the queue reset — ordering compatible).
- ⚠️ **hot-reload screen-assignment two-pass:** fork diff removes the two-pass split +
  queued `SIG_PROPERTY_*` emissions, replacing with synchronous emit + extra `"manage"` emit.
  Fork is behind here — but note fork commit `7c932c7` DID want the two-pass. Upstream
  independently has the two-pass with queued emissions. **Keep upstream's two-pass + queued
  emits; do NOT re-apply fork's synchronous single-pass.** Verify the extra `"manage"` emit
  isn't needed (superseded).
- header-dedup: fork diff removes some of upstream's 4 added explicit includes — keep
  upstream's explicit includes, only swap the scene header.
- `luaA_loadrc config_paths[8] = {NULL}` initializer — keep upstream (fork removed it).
- `some_recompute_idle_inhibit(NULL)`/`some_is_idle_inhibited(NULL)` — ⚠️ CORRECTED: the
  fork's `(NULL)` args are the stale pre-`7aa9351` form. DROP them; take upstream's no-arg
  `some_recompute_idle_inhibit()`/`some_is_idle_inhibited()` calls.

### luaa.h
- Fork caps Lua at 5.4 (`< 505`); upstream raised to 5.5 (`< 506`). → DROP fork side,
  keep upstream's `< 506` (fork's own later commit `b9113cf` also wants 5.5).

### somewm.c — HIGH RISK, main-loop + lifecycle
- **RE-APPLY:** `optimized_blur_layer` global (`#ifdef HAVE_SCENEFX`) + scene header swap +
  `setup()` blur init block; `cold_restart()`/`rebuild_restart()` setting `globalconf.exit_code`;
  `main()` returns `globalconf.exit_code` instead of `EXIT_SUCCESS`; `run()`
  `somewm_ready_seen`/`somewm::ready` emit after post-startup `some_refresh()`.
- **`some_recompute_idle_inhibit` / `some_is_idle_inhibited` `exclude` param** — ⚠️
  **CORRECTED (Codex review, verified in repo):** the fork has the OLD
  `(struct wlr_surface *exclude)` signature. Upstream commit `7aa9351` ("Broken exclude
  mechanism for some_is_idle_inhibited #446") **REMOVED** the param: `protocols.h:28` is
  now `bool some_is_idle_inhibited(void)`, `somewm_internal.h:24` is
  `void some_recompute_idle_inhibit(void)`, and `7aa9351` fixes #446 instead by skipping
  `!inhibitor->surface->mapped` inhibitors. **→ DROP the fork's `exclude` signatures AND
  the `(NULL)`/`(...)` call args everywhere (somewm.c, somewm_internal.h, protocols.c/h,
  somewm_api.h, luaa.c). Take upstream's no-arg `void` form.** This is fork-behind, not a
  fork feature.
- ⚠️ **DO NOT carry fork's DELETIONS:** `some_event_queue_wipe()` in `cleanup()`,
  `some_event_queue_drain()` Step 0 in `some_refresh()`, `nested_inhibitor_init()` +
  `some_event_queue_init()` in `setup()`. Keep all upstream queue/nested-inhibitor lifecycle.
- **some_refresh()**: keep upstream's `some_event_queue_drain()` as Step 0 (before
  `luaA_emit_signal_global("refresh")` and before `animation_tick_all()`). Fork's
  `animation_tick_all()` (Step 1.5) correctly runs AFTER the drain. Reconcile fork's bench
  rewrite (scalar `bench_start/stage_start` vs array `bench_ts[]`) but preserve the drain.
- **run()**: keep upstream's `SOMEWM_TEST_NAME`/test_marker block; re-apply only the
  `somewm_ready_seen`/`somewm::ready` emit.
- **setup()**: keep upstream's `nested_inhibitor_init()`, `some_event_queue_init()`, and
  xkb_model/xkb_rules init (`48e19a0`); layer SceneFX renderer/blur block around them.

### somewm.h
- `optimized_blur_layer` extern decl (`#ifdef HAVE_SCENEFX`) → RE-APPLY verbatim.

### globalconf.h — NO field collision (verified)
- RE-APPLY all fork additions: `wallpaper_cache_entry_t` gains `width/height/cairo_bytes/
  shm_bytes`; `wallpaper_cache_lookup()` decl + `MemoryStats` typedef; globalconf struct
  gains `MemoryStats memory_stats` + `bool somewm_ready_seen/xwayland_ready_seen`;
  `<stddef.h>` include.
- ⚠️ Fork diff REMOVES `xkb_model`/`xkb_rules` from `keyboard` sub-struct — DROP that removal,
  keep upstream's fields (`48e19a0`).
- Event-queue refactor added NO globalconf fields — fork additions land in untouched regions.

### somewm_internal.h
- `some_recompute_idle_inhibit` — ⚠️ CORRECTED: fork has stale `(struct wlr_surface
  *exclude)`; upstream `7aa9351` is `(void)`. DROP fork's signature, take upstream `void`.

### somewm_types.h
- Scene header swap → `scenefx_compat.h` → RE-APPLY verbatim.

---

## GROUP 4 — ewmh.c, protocols.c/h, xwayland.c, objects/systray.c, systray.c,
##           selection.c, root.c, somewm_api.c/h, x11_compat.h, objects/spawn.h, spawn.c

### ewmh.c
- No fork feature — all `+` lines are pre-refactor synchronous `request::*` emits + removed
  `event_queue.h` include. → DROP entirely, take upstream verbatim (`c2d4700` converted
  these to `some_event_queue_signal(SIG_REQUEST_*)`; upstream keeps `request::geometry` sync).

### protocols.c — contains PR #521 overlap
- **RE-APPLY genuine fork features:**
  1. `commitlayersurfacenotify`: `[LS-COMMIT]` debug log + opacity re-apply block
     (`layer_surface_apply_opacity_to_scene` when `0 <= opacity < 1.0`).
  2. `createlayersurface`: reordered listener registration + opacity-timing comment.
  3. `unmaplayersurfacenotify`: **PR #521 focus guard** — `bool had_exclusive_focus =
     (l == exclusive_focus)` captured early + `focus_restore` gated by
     `if (had_exclusive_focus && !mousegrabber_isrunning())`.
- ⚠️ **PR #521 / `64fe6a7` overlap:** `64fe6a7` only simplified the `send_leave`/`arrangelayers`
  block (single `if (l->layer_surface && l->layer_surface->output)`, factored
  `l->mon = ...->output->data` out). It did NOT touch the `exclusive_focus`/`focus_restore`
  lines. **PR #521 re-applies cleanly on top of upstream's simplified body — no conflict.**
  Fork's `send_leave` block already matches upstream's simplified form (fork arrived there
  independently).
- **DROP:** the `some_is_idle_inhibited`/`createidleinhibitor`/`destroyidleinhibitor`/
  `some_recompute_idle_inhibit` changes — the fork has the stale `exclude`-param form;
  upstream `7aa9351` removed the param and fixes #446 by skipping unmapped inhibitors.
  Take upstream.
- restore `#include "scenefx_compat.h"`.

### protocols.h
- `some_is_idle_inhibited` — ⚠️ CORRECTED: fork has the OLD `(struct wlr_surface *exclude)`
  form; upstream `7aa9351` is `(void)`. → DROP fork side, take upstream `void`.
  (Phase 2 in the integration plan.)

### xwayland.c
- **RE-APPLY genuine fork feature:** the `xwaylandready` addition —
  `globalconf.xwayland_ready_seen = true; luaA_emit_signal_global("xwayland::ready");` +
  comment. NOTE upstream restructured xwayland-ready into a `xwayland_ready_listener`
  (line 44/280) — the fork's flag still slots into `xwaylandready`'s body; verify
  `globalconf.xwayland_ready_seen` field gets re-added (it does, Group 3).
- **DROP:** the `request::activate`/`request::urgent` emit calls + `client::list` emit +
  removed `event_queue.h`/`objects/signal.h` includes — pre-refactor originals. Take
  upstream's queued API (`some_event_queue_signal(SIG_REQUEST_ACTIVATE)`, etc).
- restore `scenefx_compat.h` include.

### objects/systray.c
- No fork feature. All `+` lines are pre-refactor synchronous `request::*` emits + removed
  `event_queue.h`. → DROP entirely, take upstream verbatim.

### systray.c
- Single change: `<wlr/types/wlr_scene.h>` → `scenefx_compat.h`. → RE-APPLY (SceneFX).

### selection.c
- `luaA_selection_get`: fork changed `luaA_deprecate(...) + return 0` →
  `return luaL_error(L, "...")` (hard error). → RE-APPLY if intentional (behavior hardening,
  low risk, no refactor conflict). VERIFY it's wanted.

### root.c
- **RE-APPLY entire fork delta as-is** (no refactor interaction, pure fork feature work):
  `luaA_root_geometry` new API; `wallpaper_cache_lookup` made non-static;
  `create_wallpaper_cache_entry` gains `layout_x/layout_y` + size accounting;
  `root_set_wallpaper_cached` uses `layout_box.x/.y` as origin (off-origin/portrait fix);
  `luaA_root_wallpaper_cache_invalidate_screen` new API; `wallpaper_cache_preload_path`
  gains `screen_t*` + `cover_mode`; inlined `struct screenshot_render_data` +
  `composite_scene_buffer_to_cairo` static again (fork removed `screenshot_compose.h`);
  wallpaper-overlay tag-slide animation block (`wp_overlays`, `wp_overlay_create`);
  `#include <malloc.h>` under `__GLIBC__` (malloc_trim); `scenefx_compat.h` swap.
  Confirm `screenshot_compose.h` removal is consistent with `objects/client.c`.

### somewm_api.c
- **RE-APPLY genuine fork features:** `some_set_seat_keyboard_focus` large new old-surface
  handling block (popup teardown, top-layer layer-shell skip, `exclusive_focus` skip,
  deactivate old client) + new-surface activation (`client_activate_surface(surface, 1)`
  for non-X11) + `some_update_pointer_constraint(surface)` call; `wlr_layer_shell_v1.h`
  include. Focus/pointer + Chromium paint-stall fix.
- **DROP:** the `rules.model`/`rules.rules` removal in `some_rebuild_keyboard_keymap` — that
  is upstream `48e19a0` XKB work. Take upstream's `rules.model`/`rules.rules`.

### somewm_api.h — collides with dedup refactor ed4b4cf
- **RE-APPLY only:** `some_update_pointer_constraint`, `cold_restart`, `rebuild_restart`
  decls (genuinely fork-new).
- **DROP:** `apply_input_settings_to_all_devices`, `some_recompute_idle_inhibit`,
  `some_is_idle_inhibited`, `some_idle_inhibitor_count`, `some_push_idle_inhibitors`,
  `client_remove_all_listeners`, `client_reregister_listeners` decls — `ed4b4cf` removed
  these as duplicates; canonical decls live in protocols.h / other module headers. Use
  upstream's canonical **no-arg** signatures from those headers (`7aa9351` removed the
  `exclude` param — the fork's `exclude` form is stale, see cross-cutting decision #1).

### x11_compat.h — collides with dedup refactor
- Fork adds `screen_t` typedef + `luaA_screen_getbycoord`/`screen_getbycoord` forward decls.
  → DROP entirely. `ed4b4cf` deliberately removed these porting-era forward decls. If fork
  x11-compat code calls them, include the proper module header instead.

### objects/spawn.h — collides with dedup refactor
- Fork adds `activation_token_create`/`activation_token_cleanup` decls. → DROP. `ed4b4cf`
  removed these as duplicates.

### spawn.c — collides with dedup refactor
- Fork removes `#include "protocols.h"`. → DROP the removal. `ed4b4cf` ADDED that include
  precisely to compensate for the spawn.h dedup.

---

## GROUP 5 — animation/shadow/scenefx/property/stack/monitor/objects subset
None of these are in the event-queue zone — no sync→queued conversions apply.

### RE-APPLY fork code wholesale (fork is ahead):
- **animation.c/h** — absolute `start_time` timing rework (replaces global `last_tick_time`
  + dt-accumulation; fixes stale-dt drift after suspend). Adds `double start_time` to struct.
- **shadow.c/h** — SceneFX GPU-shadow path (`#ifdef HAVE_SCENEFX`): `wlr_scene_shadow_create`
  replaces 9-slice; `shadow_set_corner_radius`; `sfx_shadow` field; `scenefx_compat.h` swap.
- **scenefx_compat.h** — FORK-ONLY new file (20-line shim, `HAVE_SCENEFX` → scenefx headers,
  else wlroots fallback). Re-integrate wholesale.
- **bench.c** — one-line `scenefx_compat.h` swap.
- **property.c/h** — three xproperty stub functions (`luaA_register/set/get_xproperty`,
  each `luaL_error` "not yet implemented") + prototypes. AwesomeWM API-surface placeholders.
- **objects/drawable.c** — memory diagnostics: `size` field on `DrawableShmBuffer`, correct
  `munmap`, `globalconf.memory_stats.drawable_shm_*` accounting, `globalconf.h` include.
- **objects/wibox.c** — memory diagnostics: `memory_stats.wibox_*` accounting in
  create/destroy, `scenefx_compat.h` swap, `globalconf.h` include.
- **objects/button.c/h** — button-matching helper layer: `button_number_to_event_code`,
  `button_matches`, public `button_array_check` (callback dispatch is a TODO).
- **lgi_closure_guard.c** — ⚠️ CORRECTED (Codex + Sonnet, verified in repo): the FORK is
  AHEAD. Upstream `lgi_closure_guard.c` = 216 lines, only `lgi_guard_bump_generation()`.
  Fork = 413 lines with the two-layer rewrite (`lgi_guard_begin_reload`/`mark_ready`,
  `closure_registry`, `safe_cif`, `ffi_closure_free` interpose). RE-APPLY fork version
  wholesale — it is a pure superset. `luaa.c`'s hot-reload `lgi_guard_begin_reload` dlsym
  calls depend on this. Belongs in Phase 2 with the hot-reload luaa.c work.

### DROP — take upstream, NO fork re-integration (fork is behind, stale):
- **objects/ipc.c** — fork "removes" the `lua_isnil(L,-1)` claimed-fd early return; that's
  upstream `0bc89de` (interactive screenshot). Fork predates it. Take upstream.
- **lgi-check.c** — fork "removes" the Lua 5.5 / lgi PR #359 note; that's upstream `b9113cf`.
  Take upstream.
- **objects/drawin.c** non-include parts — fork's single-screen `luaA_drawin_struts` is
  pre-`b66d3cf`; fork lacks `_border_color` prop entry from `6ead9d8` (PR #407). Take
  upstream. Re-apply ONLY the `scenefx_compat.h` include swap.
- **objects/screen.c** non-include parts — fork's coord-based `screen_update_workarea` filter
  is pre-`b66d3cf`; fork lacks `luaA_screen_module_newindex` from `e3c6990`. Take upstream.
  Re-apply ONLY the `scenefx_compat.h` include swap.

### SURGICAL — take upstream base, re-apply only true fork additions:
- **stack.c/h** — keep upstream's `07ac746` `stack_refresh` + `<wlr/xwayland.h>` include
  (the merged PR #427). RE-APPLY: fork's `WINDOW_LAYER_FLOATING` enum + `client_layer_translator`
  rewrite (dedicated floating layer, maximized → NORMAL, transient-before-floating,
  fullscreen always LyrFULLSCREEN) + `get_scene_layer` `LyrFloat` case + `scenefx_compat.h`
  swap. ⚠️ verify `WINDOW_LAYER_FLOATING` placement doesn't conflict with `2b6413c` carousel
  cross-monitor rendering.
- **monitor.c** — keep upstream's `b2d98fe` `createmon` idempotency guards + `nested_inhibitor_
  attach_output` + `#include "nested_inhibitor.h"`. RE-APPLY: `scenefx_compat.h` swap,
  `fx_renderer_create` in `gpureset`, `optimized_blur_layer` resize in `updatemons`,
  `rendermon` bench restructure, `banning_pending`/`motionnotify(0,...)` pointer-focus-
  after-hotplug fix.

---

## GROUP 6 — Lua files

### lua/awful/client.lua — two changes
- **`property::floating` → `_c_floating` sync** → RE-APPLY (z-order stacking; depends on
  fork C-side `_c_floating` setter — verify it exists, see objects/client.c).
- **`resolve_icon` → `get_icon_path` rewrite** → ⚠️ CONFLICT. Fork replaced upstream's
  `client.resolve_icon` (sets `c.icon` directly, `build_desktop_cache`) with
  `client.get_icon_path` (returns path string) + inline pixbuf load in `request::manage`.
  Upstream's `resolve_icon` is richer (StartupWMClass + `.desktop` cache). Fork's
  `get_icon_path` is consumed by clienticon.lua + tasklist.lua. **DECISION NEEDED** (for
  integration plan / Codex): keep fork's `get_icon_path` API and port upstream's
  desktop-cache logic into it, OR adopt upstream's `resolve_icon` and rewrite widget
  consumers. client.lua + clienticon.lua + tasklist.lua migrate as a UNIT.

### lua/awful/input.lua
- Upstream-ahead only (`xkb_rules`/`xkb_model` in `state`/`property_types` from `48e19a0`).
  → take upstream, nothing to re-apply.

### lua/awful/ipc.lua
- Upstream-ahead only (`ipc.DEFERRED`, `ipc.current_fd()`, screenshot.interactive command,
  xkb fields, `request::manage`/`unmanage` → `manage`/`unmanage` rename from `affdf56`).
  → take upstream wholesale. Confirm no fork code connects to old signal names.

### lua/awful/mouse/snap.lua
- **aerosnap dwell-time gate** (`snap_dwell_ms = 150`, PR #522) → RE-APPLY cleanly. Adds
  `GLib` import, dwell state, `reset_snap_state()`/`show_snap_for()`, rewrites
  `detect_areasnap`/`apply_areasnap`. No upstream divergence in this file.

### lua/awful/permissions/init.lua
- **PR #516 nil-screen handling** in `permissions.tag` (~line 322) → ⚠️ **DROP.** Upstream
  rejected the Lua fix ("c layer is the right place"), merged C-layer fix instead
  (PR #558 → `7c932c7`). Verify the C fix is on the sync branch, then drop fork's Lua delta.

### lua/awful/screenshot.lua
- Upstream-ahead only (`surface_scale = 1.0` HiDPI fix, issue #541). → take upstream.
  Note: somewm-one's manual `surface_scale = 1.0` workaround becomes redundant (harmless).

### lua/awful/wallpaper.lua
- **`paint()` uses `capi.root.geometry()` + translates by `-root_x,-root_y`** (PR #484,
  negative-origin multi-output fix) → RE-APPLY cleanly. No upstream divergence. Depends on
  `capi.root.geometry()` returning x/y — confirm fork C layer provides it (root.c `luaA_root_geometry`).

### lua/awful/widget/clienticon.lua
- Full widget rewrite (`find_best_icon()`, `get_fallback_surface()`, `c:get_icon(index)` +
  fallback path) → RE-APPLY but COUPLED with client.lua + tasklist.lua. Depends on
  `aclient.get_icon_path` + `c.icon_sizes`/`c:get_icon(index)` C APIs. Migrate as a unit.

### lua/awful/widget/tasklist.lua
- icon line `not tasklist_disable_icon and (c.icon or aclient.get_icon_path(c)) or nil` →
  RE-APPLY cleanly, COUPLED (depends on `aclient.get_icon_path`).

### lua/lockscreen.lua
- Large lockscreen background-image feature (PR #476: `bg_image`, `bg_image_overlay`,
  `bg_image_blur`; `multipass_blur()`, `load_bg_image()`, `invalidate_bg_cache()`,
  `bg_surface_cache`; two-layer bg widget; `falsey_valid` config handling;
  `lock_screen` default `nil` → `false`) → RE-APPLY wholesale. No upstream divergence.

### lua/somewm/init.lua
- One-line `tag_slide = "somewm.tag_slide"` added to `submodules` → RE-APPLY.

### Fork-only Lua (re-integrate wholesale):
- `lua/awful/anim_client.lua`, `lua/somewm/tag_slide.lua` (latter needs the init.lua line).

---

## rc.lua → somewm-one ports (task #152, upstream ba586fd + 0bc89de + d0e8ef4)

Fork does NOT track `somewmrc.lua`. The separate `~/git/github/somewm-one` config repo
should be aware of these new/changed API surfaces from upstream's rc.lua rewrite:

- `screen.connect_signal("request::wallpaper", ...)` — per-screen wallpaper signal;
  `awful.wallpaper` accepts `bg = { type="linear", from, to, stops }` gradient spec;
  `beautiful.wallpaper_colors`/`wallpaper_logo_color` + `gears.color.recolor_image`.
- `tag.connect_signal("request::default_layouts", ...)` + `awful.layout.append_default_layouts({})`
  — signal-driven layout registration. New default layout `awful.layout.suit.carousel`.
- `screen.connect_signal("request::desktop_decoration", ...)` fires per-screen at startup
  AND on hotplug. Tag persistence via `awful.permissions.saved_tags[output_name]` keyed by
  connector name + `awful.permissions.tag_screen` on `request::screen`. `s.output.name` =
  connector identity. Default tags now named (`dev/web/chat/files/media`).
- `request::default_keybindings`/`request::default_mousebindings`/`request::rules` +
  `ruled.notification request::rules` — all via signals + `append_*` so user config
  composes. New-style `awful.key { modifiers=, key=, on_press=, description=, group= }`
  table form; `keygroup = "numrow"/"numpad"`.
- Interactive screenshot (Mod+Ctrl+p): `awful.screenshot { interactive = true }` → emits
  `snipping::start`; pattern uses `s._private.frame`/`imagebox`, sets `frame.bg` +
  `frame.surface_scale = 1.0`, `s:refresh()`. ALSO a CLI/IPC path:
  `somewm-client run screenshot.interactive <path>` (`d0e8ef4`, `ipc.DEFERRED` async).
- `wlroots` tag rule (`0bc89de`): `ruled.client.append_rule { rule = { class = "wlroots" },
  properties = { tag = "media", switchtotag = false, focus = false } }` — routes nested
  test compositors away from the active session.
- `naughty.suspended` (do-not-disturb, Mod+Shift+d); `naughty.notification` accepts
  `ignore_suspend = true`.
- `awesome.lock()` lockscreen invocation + `require("lockscreen").init()` after
  `beautiful.init`. `awesome.set_idle_timeout(name, seconds, cb)`, `awesome.idle_inhibit`/
  `awesome.idle_inhibited`.
- `awful.input.*` config surface (compositor-side, no setxkbmap): `xkb_layout`, `xkb_variant`,
  `xkb_options`, + new `xkb_model`/`xkb_rules` (`48e19a0`); pointer `tap_to_click`,
  `natural_scrolling`, `pointer_speed`.
- `output.connect_signal("added", function(o) ... end)` with settable `o.scale` (per-monitor
  fractional scaling).
- `somewm.layout_animation` — `require("somewm.layout_animation")` with `.duration`/`.easing`.
- `awful.ipc.register(name, function() ... end)` — custom IPC commands via
  `somewm-client run <name>`.
- `awesome.x11_fallback_info` — populated when user config tripped X11 patterns + fallback
  config loaded; rc.lua surfaces it as a critical notification.
- Default titlebar dropped `stickybutton`/`ontopbutton` (cosmetic; somewm-one may keep them).

---

## Cross-cutting decisions for the integration plan / Codex review

1. **`exclude` param ownership — CORRECTED.** `7aa9351` ("Broken exclude mechanism for
   some_is_idle_inhibited #446") **REMOVED** the `exclude` parameter (verified: upstream
   `protocols.h:28` = `bool some_is_idle_inhibited(void)`, `somewm_internal.h:24` =
   `void some_recompute_idle_inhibit(void)`). The FORK carries the stale pre-`7aa9351`
   `(struct wlr_surface *exclude)` form. **→ DROP the fork's `exclude` signatures and all
   `(NULL)`/`(...)` call args; take upstream's no-arg `void` form everywhere** (protocols.c/h,
   somewm.c, somewm_internal.h, somewm_api.h, luaa.c). This is fork-behind, NOT a fork
   feature. (Original audit had this backwards — corrected after Codex review.)
2. **Icon resolution** — client.lua + clienticon.lua + tasklist.lua are a coupled unit with
   a real API conflict (fork's `get_icon_path` vs upstream's `resolve_icon`). Needs an
   explicit decision before integration (decision D1 in the integration plan).
3. **Event-queue migration — principle NARROWED (Codex review, twice).** The rule "DROP the
   fork's synchronous emit, take upstream's queued form" applies ONLY to the *exact* signals
   upstream actually moved into the `SIG_*` enum (`event_queue.h`): the property geometry
   family (`SIG_PROPERTY_GEOMETRY/POSITION/SIZE/X/Y/WIDTH/HEIGHT`), focus
   (`SIG_PROPERTY_ACTIVE/FOCUS/UNFOCUS/CLIENT_FOCUS/CLIENT_UNFOCUS`), mouse
   (`SIG_MOUSE_ENTER/LEAVE/MOVE`), lifecycle (`SIG_LIST/SWAPPED`), the request set
   (`SIG_REQUEST_ACTIVATE/URGENT/TAG/SELECT`, `SIG_SYSTRAY_SECONDARY_ACTIVATE/CONTEXT_MENU/
   SCROLL`), `SIG_CLIENT_PROPERTY_GEOMETRY`, plus the bare `manage`/`unmanage` removal
   (`affdf56`). **Signals upstream deliberately KEPT synchronous must NOT be touched:**
   `request::manage`, `request::unmanage`, `request::geometry`, layer `request::keyboard`
   (verified in `upstream/main:objects/client.c` and `objects/layer_surface.c`) — these are
   NOT in the `SIG_*` enum and stay as synchronous `luaA_object_emit_signal`.
   The rule ALSO does NOT apply to **fork-new global signals that upstream never had and
   that are NOT in the `SIG_*` enum**: `screen::focus` (input.c motionnotify hover),
   `somewm::ready` (somewm.c run + luaa.c hot-reload), `xwayland::ready` (xwayland.c +
   luaa.c hot-reload). These stay as synchronous `luaA_emit_signal_global` — RE-APPLY, do
   not drop. Likewise fork property-setter signals (`property::_c_floating`,
   `property::corner_radius`, `property::backdrop_blur`, layer `property::opacity`) stay
   synchronous — they are emitted on a fresh object push, which is correct. Verified: no
   must-add `SIG_*` case exists;
   upstream still emits `screen::focus` synchronously at `input.c:567`. Every "DO NOT carry
   fork's deletion" is a fork removal of upstream queue lifecycle that must be rejected.
   Design + Codex-audit the Phase 4 sub-plan before executing (per user instruction).
4. **scenefx_compat.h include swap** — appears in ~12 files. Mechanical, but every one must
   be re-applied (fork-only header, drop-in for `<wlr/types/wlr_scene.h>`).
5. **Triage DROPs confirmed (Codex verified):** PR #478 (window.c setfullscreen geometry
   emit — upstream `58915a2` queues per-client geometry from `resize()`), PR #516
   (permissions/init.lua nil-screen — upstream `7c932c7` does the two-pass hot-reload
   screen assignment), PR #394 (client.h initialized guards — upstream clears stale seat
   keyboard focus in `unmapnotify` at `window.c:1731`). Keep their regression tests where
   they exist (`tests/test-xdg-activate-crash.lua`).

## Additional verdicts added after review (Codex + Sonnet)

6. **somewm-client.c** — was untriaged. Fork removes upstream's `screenshot interactive`
   subcommand + nested test-mode dispatch (`test_orchestrator_run`). → DROP all fork
   deltas, take upstream `somewm-client.c` verbatim. (Phase 1, build/client group.)
7. **somewmrc.lua** — `git diff upstream/main..main` IS large (fork has an old version).
   On the sync branch: take upstream `ba586fd` `somewmrc.lua` verbatim (DROP fork delta).
   Separately, port the desired behavior into the standalone `somewm-one` repo per the
   "rc.lua → somewm-one ports" list above. (Phase 1 takes upstream; Phase 7 ports.)
8. **window.h** — fork adds `struct wl_display` forward decl + `schedule_flush_clients(struct
   wl_display *)` decl. RE-APPLY just that decl (pairs with `schedule_flush_clients` impl
   in window.c). Belongs in Phase 4 with window.c. (Was missing from the plan.)
9. **Queued-signal test deltas** — `tests/test-client-silent-geometry.lua`: fork asserts
   immediately after `c:geometry()`; upstream split the assertion into the next runner step
   for queued dispatch. → DROP the fork hunk, take upstream. Keep upstream's kitty
   initial-size pin in `tests/_client.lua` (`386d232`). (Phase 6.)
10. **objects/client.c two-phase hazard** — the file is edited in Phase 3 (feature
    subsystems) AND Phase 4 (signal hunks), and the hunks are interleaved (e.g.
    `client_border_refresh` sits ~70 lines from the `SIG_FOCUS` emit). Mitigation: Phase
    3.10 marks every Phase-4 signal hunk with a `TODO(kolo8-phase4)` comment rather than
    leaving it bare; Phase 4 resolves the TODOs; Codex diff review after Phase 3.10 must
    confirm no signal hunk was touched.
