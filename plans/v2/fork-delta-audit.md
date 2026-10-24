<!-- Produced 2026-10-24 by a research agent on boxszn, read-only against legacy/v1, c7b3208 and upstream/main (6eaa61e). Status column describes UPSTREAM; what the v2 line did with each item is in HANDOFF.md section 4. "somewm-one v2/main" below = today's main. -->

# Fork delta audit: `legacy/v1` vs `upstream/main` (somewm 2.1+)

Delta audited: `git diff c7b3208 legacy/v1 -- . ':!plans' ':!tests' ':!spec' ':!*.md'` (56 files, +5675/-828).
Upstream evidence is cited as `file:line` **in `upstream/main`** unless noted. "v1" = `legacy/v1`.
Config evidence: `~/git/github/somewm-one` (branch `v2/main`) and `~/git/github/somewm-shell`.

Status legend: **covered** (upstream does it, maybe differently) / **partial** / **missing** /
**obsolete** (the C structures or the mechanism no longer exist in the Clay architecture).

## Headline facts about upstream/main

- XWayland override-redirect (OR) windows are **still Lua `client` objects**: `createnotifyx11()` has
  no OR branch (xwayland.c:249-300), `client_is_unmanaged()` still exists (client.h:241), the map
  path sets `exclusive_focus = c` (window.c:906-916), and they are listed in `client.get()` once mapped
  (objects/client.c `luaA_client_get` filters on `c->scene` only). Stacking is handled by Clay:
  `declare_unmanaged_clients()` (declare.c:1388) at `Z_CLIENT_UNMANAGED` (declare.c:1244).
  **No `set_override_redirect` listener anywhere** (`git grep set_override_redirect upstream/main` is empty).
  Upstream xwayland.c commits since c7b3208: 7361388, 765d282, 927a898, d2cc97b, 24ce108 (Clay geometry
  solving, listed-from-first-map, always-on XWayland). None touch the OR model.
- No blur anywhere in upstream. Corners come from `subprojects/packagefiles/wlroots-corners.diff`,
  which patches **gles2 and pixman only** (render/gles2/*, render/pixman/*, types/scene/wlr_scene.c) —
  no Vulkan renderer patch. Relevant for NVIDIA with `WLR_RENDERER=vulkan`.
- Drawables hold no cairo surface (objects/drawable.h, struct `drawable_t` has only geometry/owner),
  `objects/wibox.c` no longer exists, drawin shape surfaces are gone (CHANGELOG 2.1 "Client shape masks
  are accepted and never read"). Wallpaper is one `globalconf.wallpaper` cairo surface + `wallpaper_gen`
  (root.c:735-768) drawn per output as a Clay image leaf (declare.c:3160-3180).
- `awesome.start_animation` removed (CHANGELOG 2.1 Removed). Animation is declarative:
  `c.animation = {appear, disappear, tag, focus, maximize, floating}`, `animation_layout_duration`,
  drawin `animation = {visible = {enter, exit, ...}}`, slide/grow/fade/scale states (declare.c:1141-1189).

## Item table

| # | Item | Fork files / functions | Upstream 2.1 status + evidence | Recommendation | Port size |
|---|------|------------------------|-------------------------------|----------------|-----------|
| **XWayland** |||||
| 1 | OR ("unmanaged") rewrite: OR surfaces out of the client model (`UnmanagedSurface`, own list, `LyrUnmanaged`), typed keyboard ownership (`unmanaged_focus`, `unmanaged_holds_focus` guard in `focusclient` + `some_set_seat_keyboard_focus`), synchronous parent-menu focus hand-back, click routing (`unmanaged_click` in `buttonpress`), `set_geometry` tracking, role flips both directions (`unmanaged_override_redirect`, `managed_override_redirect`) | xwayland.c (+390), xwayland.h, client.h `toplevel_from_wlr_surface` X11Unmanaged branch, focus.c, input.c, somewm_api.c, somewm_types.h, window.c, stack.c | **partial**. Stacking above everything: covered by Clay (declare.c:1244, 1388). Lua client per OR window: still upstream design (xwayland.c:249). exclusive_focus hold: only the narrow `old_c == exclusive_focus && client_wants_focus(old_c)` check (somewm_api.c:259-262, focus.c:101) — sloppy focus to a *different* client still steals. Role flip: **missing** (no listener). Menu repositions: upstream tracks via `configurex11` unmanaged branch (xwayland.c:117-125) only on request_configure, not on `set_geometry`. | **verify-on-Wine first** (wine-sandbox: Sierra Chart menus, submenus, role-flip windows). If reproducible, port re-architected: Clay's `declare_unmanaged_clients` iterates `globalconf.stack` of `Client*`, so a non-client model needs its own declare loop + hit-test path. Cheaper first step: keep upstream's client model, port only role-flip handlers + unmanaged focus-hold guard. | Full: L (600-900 C incl. declare.c integration). Minimal: S-M (~150) |
| 2 | Map surfaces whose buffer was committed before `associate` (Sierra Chart dialogs never appearing) | xwayland.c `associatex11()` (f09d639) | **missing**: `associatex11` only subscribes map/unmap (xwayland.c:81-92). Bundled wlroots 0.20.2 still has the gap: `xwayland_surface_associate()` subscribes `surface_commit` without checking an existing buffer (subprojects/wlroots-0.20.2/xwayland/xwm.c:1186-1203). | **port + upstream-candidate** (also report to wlroots) | S (~25) |
| 3 | X11 lifecycle trace logs `[X11-CREATE/ASSOC/DISASSOC/MAP/DESTROY]` | xwayland.c, window.c | missing | drop (re-add ad hoc when debugging) | S |
| 4 | `root.xwayland_unmanaged()` introspection | root.c `luaA_root_xwayland_unmanaged` | missing (no match in upstream) | port only together with #1; otherwise unmanaged windows are already visible via `client.get()` upstream | S (~80) |
| **Rendering / effects (SceneFX)** |||||
| 5 | SceneFX build integration (meson `scenefx` option, 0.4/0.5 wraps, `fx_renderer_create`, shared wlroots, `scenefx_compat.h`, optimized blur layer) | meson.build, meson_options.txt (option declared **twice**), subprojects/scenefx-*.wrap, scenefx_compat.h, somewm.c `setup()`, monitor.c `gpureset`/`updatemons` | **obsolete**: upstream builds its own wlroots 0.20.2 with corners patch (subprojects/wlroots.wrap `diff_files = wlroots-corners.diff`), renderer is render.c over wlr_scene | **drop** | — |
| 6 | `c.corner_radius` (surface, titlebar, rounded border frame) | objects/client.c `client_apply_corner_radius`, `client_update_border_for_corners`, window.c `mapnotify` border_frame | **covered (different API)**: `client.shape` = radius or `gears.shape.rounded_rect` (CHANGELOG 2.1 Added/Fixed), drawn via wlroots-corners.diff. gles2/pixman only. somewm-one v2 already migrated (`fishlive/config/animations.lua:43` -> `c.shape`). | drop; **verify-on-NVIDIA first** (gles2 path; corners absent under Vulkan) | — |
| 7 | `c.backdrop_blur` + global blur params (`SOMEWM_BLUR_*`) + `_has_blur_node` | objects/client.c `client_apply_backdrop_blur`, somewm.c `wlr_scene_set_blur_data` | **missing**: no blur code in upstream (`git grep blur upstream/main -- '*.c'` -> only a render.c comment) | drop (would need a blur pass in render.c or the wlroots patch; feature request upstream if wanted) | L |
| 8 | SceneFX GPU shadow path + `shadow_set_corner_radius` | shadow.c, shadow.h | **covered**: rounded nine-patch shadows with corner_radius (CHANGELOG 2.0.1 Changed; declare.c:983-986) | drop | — |
| 9 | Border plumbing fixes: border-exclusive sizing (6c57e17), no per-refresh border toggling (5dcb798), border alpha kept during fades, focus/normal colour test helpers reading `border_frame` | objects/client.c `client_border_refresh`, window.c `apply_geometry_to_wlroots` | **obsolete**: `apply_geometry_to_wlroots` no longer exists; borders are declared by Clay; focus colour easing via `animation_focus_duration` | drop | — |
| 10 | Opacity propagated to shadow/border rects and newly created popups | objects/client.c `client_apply_opacity_to_scene`, window.c `commitpopup` | **covered**: renderer applies declared opacity per command (render.c:632-634) and keeps it across subsurface commits (69ab89a, render.c:681-700) | drop; quick visual check of popup opacity | — |
| 11 | `layer_surface.opacity` property + re-apply on commit | objects/layer_surface.c, protocols.c `commitlayersurfacenotify` | **missing** (no `"opacity"` property in objects/layer_surface.c) | drop unless rofi/QS fade is wanted; would be a declare-side opacity on layer leaves | M (~80) |
| **Animation** |||||
| 12 | `anim_client.lua`: maximize/fullscreen geometry, fade in/out, minimize fade, tiling swap, float toggle, layer-surface fade, dialog handling (all via `awesome.start_animation`) | lua/awful/anim_client.lua (698) | **partial**: appear/disappear (fade/grow/slide/scale), maximize, floating, layout (covers swap), focus, tag (CHANGELOG 2.1 Added). **Missing**: minimize fade, layer-surface fade, distinct fullscreen trigger, dialog special-casing. `start_animation` removed. somewm-one v2 already maps it (`fishlive/config/animations.lua:1-30`). | **drop** | — |
| 13 | `animation.c` absolute-start-time elapsed (no dt drift) | animation.c, animation.h | **obsolete**: `start_animation` gone; Clay transitions advance by frame dt only while transitioning (declare.c ~4431 `elapse = band->transitioning ? dt : 0`) | drop | — |
| 14 | KDE-style tag slide: `lua/somewm/tag_slide.lua`, `awesome._client_scene_set_enabled`, `awesome._client_scene_set_strict_clip`, `c->strict_clip` clip path, `root.wp_snapshot / wp_snapshot_path / wp_overlay_move / wp_overlay_destroy`, `tag_slide::start/end` signals (consumed by somewm-shell Collage) | lua/somewm/tag_slide.lua (498), luaa.c, root.c (wp_*), window.c `apply_geometry_to_wlroots`, objects/client.h | **missing as a feature; machinery partially there**: per-client tag entrance/exit `slide_left/right` (declare.c:1143-1146; animation.lua:183 maps `c.animation.tag` to both `tag_exit` and enter), per-output Clay tree (no cross-output bleed, so `strict_clip` is obsolete), drawin `animation.visible` enter/exit (usable for a sliding wallpaper wibox). Gaps: one word per client for both enter and exit (needs per-switch reassignment from Lua so old clients exit left and new enter right); slide goes to/from the output edge (`-width` / layout width), not a rigid offset of one screen width, so it is not a true parallax "desktop slide"; easing is fixed `Clay_EaseOut`. `_client_scene_set_enabled` and `wp_*` operate on wlr_scene nodes Clay now owns -> obsolete. | **port as Lua prototype first** on upstream machinery (set `c.animation.tag` per direction on `tag::request::select`, wallpaper as two `type="desktop"` wiboxes with `animation.visible`). Add C only if the look is wrong: a "slide by output width" transition state in `transition_compose` + a direction hint. Upstream-candidate (upstream #393 is tagged 2.x). | Lua M (150-300); optional C S-M (50-150) |
| **Wallpaper** |||||
| 15 | Per-screen wallpaper scene-buffer cache + `root.wallpaper_cache_{has,show,clear,invalidate_screen,preload}` + `wallpaper_cache_init()` | root.c (~800 lines), globalconf.h, somewm.c `setup()` | **obsolete**: upstream removed it in d8568ae ("remove gears.wallpaper and its cache machinery", in 2.0); wallpaper is one surface + generation counter cached per output (`image_entry`, declare.c:3165-3175). somewm-one guards every call (`if root.wallpaper_cache_preload`, fishlive/services/wallpaper.lua:345, 494, 499, 528, 538; services/themes.lua:298, 320) -> silent no-op. | **drop**; verify per-tag wallpaper switch latency on 4K (each switch repaints the full-layout surface in root_set_wallpaper and re-uploads) | — |
| 16 | `gears.wallpaper` module reinstated | lua/gears/wallpaper.lua (+277) | **obsolete**: removed in 2.0 (CHANGELOG 2.0 Removed: "`gears.wallpaper` and its cache. Use `awful.wallpaper`"). Not used by somewm-one. | drop | — |
| 17 | `awful.wallpaper` negative layout origin fix + `root.geometry()` | lua/awful/wallpaper.lua `paint()`, root.c `luaA_root_geometry` | **obsolete** for awful.wallpaper: it is now a per-screen `type = "desktop"` wibox (lua/awful/wallpaper.lua:611), no root-sized paint. `root.geometry` missing upstream but only this code used it. `root._wallpaper(pattern)` still paints a layout-box-sized surface without an origin offset (root.c:741-760) — UNVERIFIED with a portrait monitor left of primary. | drop; verify negative-origin layout | — |
| **Diagnostics** |||||
| 18 | `root.memory_stats(gc)`, `root.drawable_stats()`, `root.wallpaper_cache_stats()`, `MemoryStats` counters | root.c, globalconf.h, objects/drawable.c (shm counters), objects/wibox.c | **missing, and most inputs are obsolete**: drawable shm buffers, `drawable->surface`, `objects/wibox.c`, drawin `shape_*` surfaces and the wallpaper cache no longer exist. Still meaningful: `lua_bytes`, object counts, `mallinfo2`, `globalconf.wallpaper` bytes. New things worth counting: per-output Clay arenas/element budget, image cache, retained dump. Note: somewm-shell `services/MemoryDetail.qml:279` calls `somewm.memory.stats(true)`, which exists in **neither** v1 nor upstream, so that panel already shows `error=memory_stats_failed`. | **rewrite small + upstream-candidate** (debug tooling); fix the QML call to whatever name is chosen | S-M (80-150) |
| 19 | `root.scene_tree_dump(c)`, `root.layer_order(layer)` (+ direct pixman link) | root.c, meson.build | **partial/covered**: `awesome._clay_tree` / `somewm-client clay tree` (luaa.c:1435-1461, 2349), Clay inspector (`screen.inspector`), `c._scene_layer` (objects/client.c:3299-3305) | drop; port a wlr_scene dump only if debugging render.c reconcile | S-M (~150) |
| 20 | Bench: input latency stamped on press only; some_refresh stage timing refactor | input.c `buttonpress/keypress/motionnotify`, somewm.c | **missing**: upstream stamps every event incl. motion/release (input.c:507, 845, 1209) | upstream-candidate (tiny) or drop | S (~10) |
| **Session / restart** |||||
| 21 | `awesome.cold_restart()` (execvp re-exec), `awesome.rebuild_restart()` (exit 2), `cold_restart()/rebuild_restart()` C helpers, `main()` returning `globalconf.exit_code` | luaa.c, somewm.c, somewm_api.h | **missing**. Upstream: `awesome.restart` = in-process hot reload (luaa.c:395-407), `awesome.exec(cmd)` exists (luaa.c:321), `awesome.quit(code)` stores `globalconf.exit_code` (luaa.c:456) **but `main()` returns `EXIT_SUCCESS`** (somewm.c:1431) — upstream bug. somewm-one v2 still calls `awesome.rebuild_restart()` (fishlive/config/menus.lua:49) -> runtime error on upstream. | **upstream-candidate**: `return globalconf.exit_code;` (2 lines). Then drop both Lua APIs: cold = `awesome.exec(...)`, rebuild = `awesome.quit(2)`; update the menu. | S |
| 22 | `somewm-session` launcher (environment.d import, gnome-keyring, gcr ssh agent, `systemctl --user import-environment`, lgi closure guard LD_PRELOAD, restart/rebuild loop) + meson install | somewm-session, meson.build | **partial**: upstream exports WAYLAND_DISPLAY/DISPLAY/XDG_CURRENT_DESKTOP to systemd + D-Bus itself (CHANGELOG Unreleased Fixed) and ships a systemd session wrapper (CHANGELOG 2.0.1). No restart loop, no keyring/ssh setup. | keep **fork-only** under `plans/scripts/` (not in meson install) | S |
| 23 | NumLock on startup | (v1 delta: none; already in base) | **covered**: `awesome._set_keyboard_setting("numlock", true)` (luaa.c:1184-1185, somewm_api.c:965). somewm-one rc.lua:98 uses this form. | none | — |
| 24 | `awesome._set_keyboard_setting`, `awesome.xwayland_ready`, `awesome.somewm_ready` | (already in base) | **covered**: luaa.c:1149, 2335; luaa.c:2495-2501; globalconf.h:323-324 | none | — |
| 25 | `awesome._notif_history`, `awesome._shell_overlay` | none in compositor | **not compositor APIs**: plain fields written by somewm-one (fishlive/components/notifications.lua:142) and somewm-shell (core/Panels.qml:96, modules/collage/Collage.qml:505). Upstream `awesome.__newindex` falls through to `lua_rawset` (luaa.c:2593-2640), so they keep working. | none | — |
| 26 | `objects/timer.c` (`_timer` global) | objects/timer.c/.h, meson.build | **dead in v1**: `luaA_timer_setup` is defined but never called (`git grep luaA_timer_setup legacy/v1` -> definition only). Not in upstream meson. | **drop** | — |
| 27 | `some_update_pointer_constraint()` | input.c, somewm_api.h | **dead in v1** (no caller). Upstream does constraint activation in the Lua focus path (somewm_api.c:310-313) | drop | — |
| **Focus / input / stacking fixes** |||||
| 28 | Emit `screen::focus` when the pointer crosses monitors (QS panels gated on focused screen) | input.c `motionnotify` | **missing**: motion updates `selmon` silently (input.c:893-900); only the empty-space button path queues `SIG_SCREEN_FOCUS` (input.c:640-646) | **port + upstream-candidate** (`some_event_queue_global(SIG_SCREEN_FOCUS)`) | S (~5) |
| 29 | Re-base pointer focus when a mousegrabber ends (drop on other monitor gets no clicks) | input.c `motionnotify` | **partial**: `luaA_mousegrabber_stop` marks all outputs dirty (mousegrabber.c), and `rendermon` re-runs `motionnotify` only if the frame changed (monitor.c:525-533) | verify (cross-monitor drag, click immediately without moving) | S (~5) |
| 30 | Deferred one-shot pointer-enter retry for clients that have not bound wl_pointer yet | input.c `pointerfocus`, `deferred_pointer_enter` | **missing**: upstream only clears focus (input.c `pointerfocus`, "client had no wl_pointer resources") | verify still reproducible, then port | S (~20) |
| 31 | Skip ban-unfocus while a mousegrabber drag is active (focus stolen mid cross-monitor drag) | objects/client.c `client_ban_unfocus` | **missing**: no grab check (objects/client.c:1910-1937) | verify, then upstream-candidate | S (~5) |
| 32 | Layer-surface unmap restores focus only if it held `exclusive_focus` and no grab is running (notifications/tooltips/QS popups stealing focus) | protocols.c `unmaplayersurfacenotify` | **missing**: unconditional `focus_restore()` (protocols.c:285-286) | **port + upstream-candidate** | S (~5) |
| 33 | Hotplug: `motionnotify` after `banning_refresh` in `updatemons` | monitor.c | **covered**: rendermon re-evaluates pointer focus after any declared change (monitor.c:525-533) | drop | — |
| 34 | Stacking model: floating layer above tiled (`c->floating` C cache via `_c_floating`, `WINDOW_LAYER_FLOATING`), fullscreen always top, maximized stays in normal layer, floating transients not pinned under tiled parent (Sierra Chart dialogs, 328f2e9) | stack.c, stack.h, objects/client.c `luaA_client_set_floating`, lua/awful/client.lua | Fullscreen: **covered** (`client_z` returns FS band for any fullscreen client, declare.c:1246-1247). Floating above tiled: **covered per CHANGELOG 2.1** ("...a floating client is above the layout's clients whatever the raise order, as under tile") — mechanism not located, UNVERIFIED in code. Floating transient of a tiled parent: upstream rides parent (`stack_rides`/`stack_place`, stack.c:140-175; effective layer = parent's, stack.c:120-131) -> **likely still broken**, UNVERIFIED. Maximized-in-normal: UNVERIFIED. `_c_floating` cache: obsolete. | **verify-on-Wine first** (Sierra Chart dialog vs unrelated floating window); port as a declare/stack rule if broken | S-M (30-80) |
| 35 | Aspect ratio applied to content (titlebars excluded) for mpv | objects/client.c `client_resize`, window.c `resize` | **missing**: upstream ratio on full geometry incl. titlebars (objects/client.c:2431-2440) | verify geometry semantics under Clay, then upstream-candidate | S (~20) |
| 36 | NVIDIA hotplug guard: don't configure an uninitialized XDG surface (#216) | window.c `apply_geometry_to_wlroots` | **covered**: `client_configure_to_box` returns unless the surface is mapped (window.c:1617-1623); other `initialized` checks at window.c:1250, 1267, 1282 | drop; keep the hotplug test on NVIDIA | — |
| 37 | `unmapnotify` `!globalconf_L` path: remove XDG commit listener, clear scene child pointers | window.c `unmapnotify`, `client_clear_scene_child_pointers` | **missing** (upstream early path only destroys the scene) — whether it still leaks/asserts depends on upstream `destroynotify`, UNVERIFIED | verify at shutdown under ASAN; small upstream-candidate if real | S (~10) |
| 38 | NVIDIA focus: `wlr_xwayland_set_seat` on every X11 focus, keyboard enter without keyboard device, KWin clear/re-enter for X11 same-surface, keep constraint-backed X11 grabs (71827dc) | (focus paths) | **covered**: focus.c:174, somewm_api.c:279, 291-298, 198-224 | none | — |
| 39 | `selection()` deprecation turned into an error | selection.c | upstream still warns (selection.c:68) | drop | — |
| 40 | Default rc theme `default` + deletion of themes catppuccin/gruvbox/nord | somewmrc.lua, themes/ | upstream ships them (`git ls-tree upstream/main themes/`); fork deletion is a split/merge artefact | drop (take upstream) | — |
| 41 | Lockscreen background image: `bg_image`, `bg_image_overlay`, `bg_image_blur` (Lua multipass blur), `lock_screen = false` default | lua/lockscreen.lua (+318/-?) | **partial**: upstream `wallpaper` + `wallpaper_overlay` options / `beautiful.lockscreen_wallpaper(_overlay)` (lua/lockscreen.lua:50-51, 183-199, 307-312; CHANGELOG 2.1 Added), letterboxed like the desktop. **Blur missing.** somewm-one themes still set `theme.lockscreen_bg_image` (themes/*/theme.lua:94-95), which upstream ignores -> plain colour lock screen. | rename keys in somewm-one to `lockscreen_wallpaper` / `lockscreen_wallpaper_overlay`; drop fork blur (or offer it upstream as an option) | config S; blur port S-M (~120 Lua) |

## What a user would notice in daily use if the fork delta is dropped

1. **Wine / Sierra Chart menus and dialogs** (#1, #2, #34): menus closing when the mouse moves over
   another window under sloppy focus, menus breaking when an app flips a window's override_redirect,
   dialogs that intermittently never appear (buffer-before-associate, confirmed still present in
   wlroots 0.20.2), and floating dialogs stuck under unrelated floating windows. Test in
   `plans/scripts/wine-sandbox.sh` before deciding how much of #1 to port; #2 is a small, clear port.
2. **No KDE-style tag slide** (#14): tag switches use upstream's tag entrance (fade/grow/slide to edge).
   somewm-shell Collage listens for `tag_slide::start/end`; those signals stop firing.
3. **No backdrop blur** on terminals/panels (#7) and no blurred lock-screen background (#41).
4. **Lock screen loses its image** until somewm-one themes rename `lockscreen_bg_image` to
   `lockscreen_wallpaper` (#41).
5. **"Rebuild & restart" menu entry errors** (`awesome.rebuild_restart` missing, #21), and
   `awesome.quit(code)` exit codes are swallowed upstream, so the somewm-session loop cannot tell
   quit from restart.
6. **Focus stealing by notifications / QS popups** when they unmap (#32), and QS panels following the
   focused screen only on clicks, not on pointer moves (#28).
7. **Memory panel in somewm-shell** shows an error (#18); it is already broken against v1 because it
   calls `somewm.memory.stats`.
8. **Corners on NVIDIA**: upstream corners exist only for gles2/pixman (#6). With `WLR_RENDERER=vulkan`
   windows are square.
9. Less visible: minimize and layer-surface (rofi) fades (#11, #12), mpv aspect with titlebars (#35),
   cross-monitor drag focus/click glitches (#29, #31). Verify before porting.

Items that need nothing: numlock, `_set_keyboard_setting`, `xwayland_ready`/`somewm_ready`,
`_notif_history`/`_shell_overlay`, the NVIDIA XWayland focus guards, the XDG `initialized` hotplug guard,
fullscreen stacking, opacity propagation, shadows, wallpaper cache (config calls are guarded).

## UNVERIFIED list

- #34 floating-above-tiled mechanism in upstream code (only the CHANGELOG statement was found);
  floating-transient-of-tiled-parent and maximized layering behaviour upstream.
- #17 `root._wallpaper` with negative output-layout origin.
- #29, #30, #31, #35, #37: whether the original bugs still reproduce under Clay.
- #14: whether per-client `c.animation.tag` reassigned right before a switch is read in time for both
  the exit of old clients and the entrance of new ones (animation.lua:183 maps one word to both).
- #15: per-tag wallpaper switch latency without the cache.
