# Kolo 8 — Phase 4: Event-Queue Migration Sub-Plan (v1)

Date: 2026-05-14
Sync branch: `sync/upstream-2026-05-13` (Phase 3b done at `d76122b`)
Companion docs: `kolo8-migration-audit.md` (per-function A/B/C/D), `kolo8-integration-plan.md`

**Status: v1 — DRAFT. Must be reviewed by Codex (gpt-5.5) MULTIPLE rounds + a
fresh audit before any code is written. Per user instruction 2026-05-14: Codex
must be given the fork commit history so it understands the *essence and original
placement* of every fork change, not just the raw diff.**

This is the hardest phase. Upstream touched `objects/client.c` with 12 commits in
the sync window — the entire event-queue refactor — so the fork's 30+ hunks there
are tightly interleaved feature-vs-signal-vs-content-getter code.

---

## 1. What upstream did — the event-queue model

Upstream replaced synchronous C→Lua signal emission with deferred/queued dispatch
(`event_queue.c`/`event_queue.h`, 16 commits `1b90255`..`4b51122`).

- C code used to call `luaA_object_emit_signal(L, idx, "name", nargs)` inline,
  which crossed into Lua immediately, mid-handler.
- Now C calls `some_event_queue_signal0/signal/global/move/class()` with a `SIG_*`
  enum id. Events accumulate in a buffer and are drained at a frame boundary by
  `some_event_queue_drain()` (Step 0 of `some_refresh()`).
- The `SIG_*` enum (`event_queue.h`) is the **authoritative list of which signals
  were converted**:
  - Property geometry: `SIG_PROPERTY_GEOMETRY/POSITION/SIZE/X/Y/WIDTH/HEIGHT`
  - Focus: `SIG_PROPERTY_ACTIVE` (1 bool arg), `SIG_FOCUS`, `SIG_UNFOCUS`,
    `SIG_CLIENT_FOCUS` (global), `SIG_CLIENT_UNFOCUS` (global)
  - Mouse: `SIG_MOUSE_ENTER`, `SIG_MOUSE_LEAVE`, `SIG_MOUSE_MOVE` (2 args, coalesced)
  - Lifecycle: `SIG_LIST` (class-level), `SIG_SWAPPED` (2 args)
  - Request: `SIG_REQUEST_ACTIVATE`, `SIG_REQUEST_URGENT`, `SIG_REQUEST_TAG`,
    `SIG_REQUEST_SELECT`, `SIG_SYSTRAY_SECONDARY_ACTIVATE`,
    `SIG_SYSTRAY_CONTEXT_MENU`, `SIG_SYSTRAY_SCROLL`
  - Global geometry: `SIG_CLIENT_PROPERTY_GEOMETRY`
- `affdf56` additionally **removed** the bare `manage`/`unmanage` signals (the
  `request::manage`/`request::unmanage` ones are different and were KEPT synchronous).

## 2. Conversion rules — the decision tree for every signal emit

For every `luaA_object_emit_signal` / `luaA_class_emit_signal` /
`luaA_emit_signal_global` the fork carries in a Phase-4 file:

**Rule A — converted signal → DROP fork's synchronous call, TAKE upstream's queued
form.** If the signal name maps to a `SIG_*` enum entry (see §1), upstream already
has the correct `some_event_queue_*` call. The fork's synchronous call is the
pre-refactor original. Discard it; keep upstream's queued line. *Failure mode if
you keep the fork line: double-emit (signal fires once queued, once synchronous).*

**Rule B — KEPT-synchronous signal → leave untouched.** `request::manage`,
`request::unmanage`, `request::geometry`, layer `request::keyboard` are NOT in the
`SIG_*` enum — upstream deliberately keeps them synchronous (verified
`upstream/main:objects/client.c`, `objects/layer_surface.c`). Leave as
`luaA_object_emit_signal`. NOTE: the *bare* `manage`/`unmanage` (no `request::`
prefix) were removed by `affdf56` — every fork emit of those IS dropped.

**Rule C — fork-new signal → RE-APPLY as synchronous, do NOT drop.** Signals
upstream never had and that are NOT in the enum: `screen::focus` (input.c
motionnotify hover crossing — fork commit `edc5605`), `somewm::ready` (done in
Phase 2), `xwayland::ready` (fork commit `85c227f`), and fork property setters
(`property::_c_floating`, `property::corner_radius`, `property::backdrop_blur`,
layer `property::opacity`). These stay `luaA_emit_signal_global` /
`luaA_object_emit_signal`. Verified: no must-add `SIG_*` case; upstream still
emits `screen::focus` synchronously at `input.c:567`.

**Rule D — fork removal of upstream queue lifecycle → REJECT.** Any place the fork
diff *deletes* `some_event_queue_*` calls or `#include "event_queue.h"`: do NOT
carry the deletion. The fork removed those only because fork `main` predates the
queue.

**Rule E — fork feature interleaved with a converted emit → re-express onto the
queued form.** Do not paste the fork feature *around* a synchronous call. Apply it
relative to upstream's queued line.

## 3. Fork commit context — essence & original placement

The 37 fork commits touching Phase-4 files (`git log <merge-base>..main -- <files>`).
Codex MUST read these — `git log -p` for the diffs and intent. Key groups:

### 3a. kolo6/kolo7 — prior-sync reintegration (HOW fork code was placed last time)
- `77d7494` refactor(kolo6): port fork infrastructure onto refactored tree (Group A)
- `30c1898` fix(kolo6): de-duplicate SOMEWM_BENCH impl in somewm.c
- `4a810cb` feat(kolo6): port NVIDIA/SceneFX/bench deltas to refactored modules
- `6a6aef5` fix(kolo6): address Codex Round 5 findings on Groups F/G/H port
- `a109dc4` fix(kolo6): restore Lgi guard ordering + pointer-constraint on Lua focus
- `f464860` fix(kolo6): route refactored modules through scenefx_compat.h
- `2bffa5b` fix(kolo6): restore fork pointer/layer deltas dropped by refactor
- `18cc414` fix(kolo6): split LISTEN order to avoid layer-surface destroy SIGSEGV
- `f5c6753` protocols: Simplify code of unmaplayersurfacenotify()  [== upstream `64fe6a7`]
- `7a3e449` fix: Use-after-free of wlr_scene_tree  [== upstream `bad997d`]
- `46703ad` fix(kolo7): preserve titlebar/border clearing after upstream UAF fix
- `622cde3` fix: Use static inline for scene-tree surface helpers  [== upstream `d27fa2b`]
- `ddd921a` fix(kolo7): remove XDG commit listener in !globalconf_L unmap path
- `3042fd5` fix(kolo7): fire motionnotify on monitor-hotplug banning
- `ce1a98c` fix(kolo6): stop key repeat when a keygrabber starts mid-binding  [== upstream `cb6c2c1`]
**These tell us where fork deltas landed in the LAST refactored tree** — the same
placement logic applies again. Several (`f5c6753`, `7a3e449`, `622cde3`, `ce1a98c`)
are fork ports of commits upstream ALSO has — those are DUP, take upstream.

### 3b. Fork features touching Phase-4 files (the work to re-integrate)
- `f756ead` fix(focus): preserve focus during cross-monitor mouse-drag —
  THREE coordinated changes: `client_ban_unfocus` mousegrabber early-return
  (objects/client.c), `unmaplayersurfacenotify` exclusive_focus + mousegrabber
  guard (protocols.c), `motionnotify(0,...)` rebase after grabber returns false
  (input.c). PR #521.
- `ed894df` fix(window): defer wl_display_flush_clients out of mapnotify —
  `schedule_flush_clients` (DONE Phase 2) + the mapnotify call site change. #530.
- `85c227f` feat(api): emit xwayland::ready after EWMH init — xwayland.c (Rule C).
- `4c5b23e` fix(input): gate motionnotify pin on seat button_count not cursor_mode —
  the `cursor_mode == CurPressed` → `button_count > 0` change in input.c.
- `edc5605` fix(input): emit screen::focus on monitor-boundary cross — input.c
  motionnotify (Rule C, synchronous global).
- `06ca83e` docs: sonnet review nits — comments only.
- `4dc0fbf` fix(tag_slide): strict_clip per-client flag — objects/client.h (DONE
  Phase 2: the field), objects/client.c, window.c apply_geometry_to_wlroots,
  luaa.c `_client_scene_set_strict_clip`, lua/somewm/tag_slide.lua.
- `1809506` fix(client): keep border hidden for fullscreen during refresh —
  `client_border_refresh` c->fullscreen guard.
- `84aa3cb`, `36e939f`, `b1cded2` — CSD-DIAG instrumentation add+revert, net zero.
- `387e26a` fix(csd): stop poisoning c->prev from setmon + skip no-op unfullscreen —
  window.c `setmon`, `setfullscreen`.
- `f842847` fix(csd): remove xdg state driving from client_set_minimized —
  objects/client.c `client_set_minimized`.
- `8a42b35` fix(csd): reorder maximize ack + refresh configure on unminimize —
  window.c `maximizenotify`, objects/client.c.
- `748070e` feat: wire CSD maximize/minimize buttons — window.c `maximizenotify` +
  new `minimizenotify` + listener lifecycle in `createnotify`/hot-reload/destroy,
  `initialcommitnotify` capability bits, objects/client.c `client_set_maximized_common`.
- `6fb4db8` fix(fullscreen): emit per-client property::geometry in setfullscreen —
  ⚠ window.c. **This is fork PR #478 — CLOSED. Upstream reimplemented it as
  `58915a2` (queues per-client geometry from `resize()`). DROP the fork's
  setfullscreen geometry emit; take upstream `58915a2`.** (triage)
- `f5164d2` fix(scenefx): disable optimized backdrop blur on client buffers —
  objects/client.c scenefx.
- `25a1708`, `e7eb6c5`, `8eef823` fullscreen geometry preservation — window.c
  `setfullscreen` reentrance/no-op guards + max→fs→unfull memento.
- `0c839f4` perf(opacity): skip no-op opacity re-apply at 1.0 — objects/client.c
  `client_apply_opacity_to_scene`, objects/layer_surface.c.
- `867ba20` fix(stack): skip unmanaged clients in stack_refresh — == upstream `07ac746`
  (DUP, take upstream; stack.c already done Phase 3b).

---

## 4. Per-file execution plan

Files with NO fork features — take upstream verbatim, drop the entire fork delta:

### event.c — take upstream verbatim
Fork delta is only the pre-refactor synchronous `mouse::enter/leave` + removed
`event_queue.h` include. Rule A + Rule D. **No edit needed — the branch already
has upstream's `event.c`.** Confirm `git diff upstream/main..HEAD -- event.c` is
empty at the end.

### common/luaclass.c — take upstream verbatim
The ~20 added lines are upstream's `client.manage/unmanage` deprecation shim. Fork
has no delta of its own. **No edit needed.** Confirm empty diff.

### ewmh.c — take upstream verbatim
Fork delta is pre-refactor synchronous `request::urgent/tag/select/activate` +
removed `event_queue.h`. Upstream `c2d4700` converted them to
`some_event_queue_signal(SIG_REQUEST_*)`. `request::geometry` stays synchronous
(Rule B). No fork feature. **No edit needed.** Confirm empty diff.

### objects/systray.c — take upstream verbatim
Fork delta is pre-refactor synchronous `request::*` emits + removed `event_queue.h`.
Upstream uses `some_event_queue_signal(SIG_REQUEST_ACTIVATE / SIG_SYSTRAY_*)`. No
fork feature. **No edit needed.** Confirm empty diff.

### xwayland.c — minimal
- RE-APPLY (Rule C): the `xwaylandready()` tail — `globalconf.xwayland_ready_seen =
  true; luaA_emit_signal_global("xwayland::ready");` + the explanatory comment
  (fork commit `85c227f`). Upstream restructured xwayland-ready into a
  `xwayland_ready_listener`; the flag still slots into `xwaylandready()`'s body.
- DROP (Rule A): the `request::activate`/`request::urgent` emit-call conversions,
  the `client::list` emit, removed `event_queue.h`/`objects/signal.h` includes —
  take upstream's queued forms.
- RE-APPLY: `scenefx_compat.h` include swap.

### protocols.c — surgical
- RE-APPLY fork features:
  1. `commitlayersurfacenotify`: `[LS-COMMIT]` debug log + opacity re-apply block
     (`layer_surface_apply_opacity_to_scene` when `0 <= opacity < 1.0`).
  2. `createlayersurface`: reordered listener registration + opacity-timing comment
     (fork commit `18cc414` — split LISTEN order to avoid destroy SIGSEGV).
  3. `unmaplayersurfacenotify`: **PR #521 focus guard** (fork commit `f756ead`) —
     capture `had_exclusive_focus = (l == exclusive_focus)` early; gate
     `focus_restore` with `if (had_exclusive_focus && !mousegrabber_isrunning())`.
     Re-applies cleanly on top of upstream `64fe6a7`'s simplified body — `64fe6a7`
     only touched the `send_leave`/`arrangelayers` block, not the focus lines.
- DROP: the `some_is_idle_inhibited`/`createidleinhibitor`/`destroyidleinhibitor`/
  `some_recompute_idle_inhibit` changes — fork has the stale pre-`7aa9351`
  `exclude`-param form; take upstream's no-arg form (consistent with Phase 2).
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"` if
  the fork removed it (Rule D).

### focus.c — surgical
- DROP (Rule A): `focusclient()` unfocus + focus signal blocks — fork's synchronous
  `property::active`/`unfocus`/`focus` + global `client::unfocus`/`client::focus`.
  Take upstream's `some_event_queue_signal(SIG_PROPERTY_ACTIVE)`,
  `..signal0(SIG_UNFOCUS/SIG_FOCUS)`, `..global(SIG_CLIENT_UNFOCUS/SIG_CLIENT_FOCUS)`.
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"`.
- No fork feature logic in focus.c's signal hunks (verified Group 1 audit).

### mouse.c — minimal
- DROP the fork's deletion of `luaA_mouse_fake_motion` + the `_fake_motion` method
  registration (Rule D — fork is behind; `some_fake_motion` still exists upstream).
  **Take upstream verbatim — confirm empty diff at the end.**

### input.c — surgical (partly done in Phase 3b)
Already done in Phase 3b: `some_update_pointer_constraint` definition.
Remaining:
- RE-APPLY fork features:
  - `buttonpress()`/`keypress()` bench gating on `state == PRESSED` (move
    `bench_input_event_record()` after struct decls, gate it).
  - `motionnotify()` bench removal (fork deletes `bench_input_event_record()` from
    motionnotify — motion isn't a latency start).
  - `motionnotify()` `cursor_mode == CurPressed` → `seat->pointer_state.button_count
    > 0` (fork commit `4c5b23e` — the pointer-focus-stuck fix).
  - `motionnotify()` `screen::focus` on hover crossing (fork commit `edc5605` —
    Rule C, synchronous `luaA_emit_signal_global("screen::focus")` when
    `mon != selmon`). The button-press path's `screen::focus` (input.c:567) is
    ALSO synchronous upstream — so synchronous is the right form.
  - `motionnotify()` grab-end re-entry: `motionnotify(0,NULL,0,0,0,0)` after
    `luaA_mousegrabber_stop()` (fork commit `f756ead` — the PR #521 rebase).
  - `deferred_pointer_enter()` + `pointerfocus()` idle re-delivery (fork's
    `pointer_enter_deferred_pending` static + idle callback).
- DROP (Rule A): `mouse_emit_leave/enter` synchronous calls + `motionnotify()`
  manual `mouse::move` push/emit — take upstream's `some_event_queue_signal0(
  SIG_MOUSE_LEAVE/ENTER)` and `some_event_queue_move()`.
- DROP: `createkeyboardgroup()` xkb `rules.rules = NULL; rules.model = NULL;` — the
  fork NULLs them; upstream `48e19a0` sets them from `globalconf.keyboard.*`. Take
  upstream (consistent with Phase 2/3 — fork's NULLing is pre-`48e19a0`).
- ⚠ DO NOT re-apply the `keyrepeat()` `!locked` guard removal — D5 RESOLVED: keep
  upstream's `!locked` session-lock guard.
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"`.

### window.c — surgical (schedule_flush_clients done in Phase 2)
- DROP (Rule A): all `manage`/`unmanage` bare-signal emits in `mapnotify()` (×2);
  the synchronous `property::x/y/width/height/geometry` emits in `mapnotify()`;
  the `createnotify()` `client::list` emit; `swapstack()` SIG_LIST/SIG_SWAPPED;
  `request::activate`. Take upstream's queued forms.
- DROP (triage): the fork's PR #478 `setfullscreen()` per-client
  `property::geometry` emit (fork commit `6fb4db8`) — upstream `58915a2`
  reimplemented it in `resize()`. Also drop the fork's `resize()` signal block
  (keep only the fork's aspect-ratio content-area math). Drop the fork's
  `fullscreennotify()` rework's extra `property::fullscreen` emit (upstream's
  `setfullscreen` already emits it — double-emit).
- DROP: the ~25 re-added forward declarations — header-dedup `ed4b4cf` moved them
  to `window.h`.
- RE-APPLY fork features (NOT signal-related — clean adds):
  - `client_clear_scene_child_pointers()` + calls from both unmap paths.
  - `mapnotify()` call-site change for `schedule_flush_clients` (fork commit
    `ed894df` — the helper itself is already in Phase 2; here only the call site).
  - `commitnotify()` bench-ordering + `client_apply_corner_radius/backdrop_blur`.
  - `maximizenotify()` + new `minimizenotify()` Lua-routing rework + listener
    lifecycle (fork commits `748070e`, `8a42b35`, `f842847`) — upstream still has
    `maximizenotify` as a near-stub; large but no queue API in the rework.
  - `initialcommitnotify` maximize/minimize capability bits.
  - `setmon()` `c->prev` ownership fix (fork commit `387e26a` — stop poisoning the
    memento).
  - `setfullscreen()` reentrance + no-op transition guards + max→fs→unfull memento
    (fork commits `e7eb6c5`, `25a1708`, `8eef823`, `387e26a`).
  - `apply_geometry_to_wlroots()` `strict_clip` decoration-hiding branch (fork
    commit `4dc0fbf`).
  - `unmapnotify()` early-exit `commit.link` removal (fork commit `ddd921a`).
  - `scenefx_compat.h` include swap.
  ⚠ OVERLAP: the fork's offscreen-rendering changes in `apply_geometry_to_wlroots()`
  partially duplicate upstream `e7c14e6`/`2b6413c`/`9774101` — reconcile per the
  audit; do not double-apply.

### objects/client.c — the hardest file, per-function plan
30+ hunks. `/tmp/kolo8-client-c-delta.txt` has the full 953-line delta (regenerate
with `git diff upstream/main..main -- objects/client.c`). Upstream's current queued
signal sites (TAKE these, drop the fork's synchronous twins):
`client_unfocus_internal` 1921-1922, `client_focus_update` 2048-2049,
`client_manage` 2419-2424 + 2469, `client_resize_do` 2695-2710, `client_unmanage`
3191 + 3233, `luaA_client_swap` 3594-3603.

Per-function classification:
- `client_unfocus_internal` (hunk @1918): DROP fork synchronous emits — take
  upstream's `SIG_PROPERTY_ACTIVE`/`SIG_UNFOCUS`. (Rule A)
- `client_ban_unfocus` (hunk @1954): RE-APPLY — the mousegrabber early-return
  (fork commit `f756ead`). Clean feature add, no signal interaction.
- `client_focus_update` (hunk @2045): DROP fork synchronous — take upstream's
  `SIG_PROPERTY_ACTIVE`/`SIG_FOCUS`. (Rule A)
- `client_border_refresh` (hunk @2141): RE-APPLY — rounded-corner + opacity-alpha
  preservation + the `c->fullscreen` border-hidden guard (fork commit `1809506`).
  No signal interaction.
- `client_manage` (hunks @2416, @2466, @2480): DROP the fork's synchronous
  `property::*` + `client::list` + the bare `manage` emit (Rule A + `affdf56`).
  RE-APPLY any fork feature lines NOT signal-related (check the hunk).
- `client_resize_do` (hunk @2692): DROP the fork's synchronous geometry-signal
  block — take upstream's `some_event_queue_signal0(SIG_PROPERTY_*)`. RE-APPLY any
  fork aspect-ratio / content math interleaved. (Rule A + Rule E)
- `client_resize` (hunk @2768): inspect — likely fork geometry math, RE-APPLY.
- `client_set_minimized` (hunk @2824): RE-APPLY — the xdg-state-removal rework
  (fork commit `f842847`). No signal interaction (the `property::minimized` emit
  is unchanged / not in the SIG_ enum — verify).
- `client_set_fullscreen` (hunk @2942): inspect — fork comment-only delta per
  Group 2 audit; take upstream.
- `client_set_maximized_common` (hunks @2991, @3007): RE-APPLY — the
  `wlr_xdg_toplevel_set_maximized` sync (fork commit `748070e`).
- `client_unmanage` (hunks @3188, @3228): DROP synchronous `SIG_MOUSE_LEAVE`/
  `SIG_LIST` twins + bare `unmanage` emit — take upstream queued. RE-APPLY
  `client_clear_scene_child_pointers` call if present. (Rule A + Rule D)
- `luaA_client_swap` (hunk @3591): DROP fork synchronous `SIG_LIST`/`SIG_SWAPPED`
  twins — take upstream queued. (Rule A)
- `luaA_client_get_first_tag` area (hunk @3685, -39 lines): this is the
  `luaA_client_get_content` rewrite + `_scene_layer` removal region. **DROP the
  content-getter "rewrite"** — fork is pre-`5f3c4ef` (#539 is Jimmy's issue,
  `5f3c4ef` his fix; root.c already kept upstream's `5f3c4ef` infra in Phase 3b).
  Take upstream's scene-walk content getter. The `_scene_layer` removal — inspect:
  if it's a deliberate fork API removal, RE-APPLY; if fork-behind, take upstream.
- `titlebar_get_drawable` / `titlebar_resize` (hunks @3953, @4023): RE-APPLY —
  titlebar corner-radius hooks.
- `luaA_client_set_ontop` (hunk @4305): inspect — likely fork z-order/`_c_floating`
  related, RE-APPLY.
- `client_apply_opacity_to_scene` (hunk @4365): RE-APPLY — extended to borders/
  shadow/frame + the no-op-at-1.0 skip (fork commit `0c839f4`).
- `luaA_client_set_opacity` + the +285-line hunk @4407: RE-APPLY — the
  corner_radius / backdrop_blur subsystems (`client_apply_corner_radius`,
  `client_update_border_for_corners`, `client_apply_backdrop_blur`), the scenefx
  disable-on-client-buffers fix (`f5164d2`), `luaA_client_set_floating` +
  `_c_floating` property. The biggest single feature block.
- hunks @4552, @4638 (+118 lines): inspect — more corner/blur/floating subsystem.
- `luaA_client_border_is_*_color` (hunks @5224, @5248): inspect — likely
  scenefx border_frame, RE-APPLY.
- `client_class_setup` (hunks @5316, @5336): RE-APPLY — register the new Lua
  properties (`corner_radius`, `backdrop_blur`, `_c_floating`, opacity extensions).
- Header includes (hunks @92-@133): RE-APPLY `scenefx_compat.h` swap, re-add
  `#include "../event_queue.h"`, `mousegrabber.h`. DROP `screenshot_compose.h`
  removal — keep upstream's (root.c kept `5f3c4ef`'s screenshot infra).
  ⚠ Note `screenshot_compose.h` decision: since we kept upstream's `5f3c4ef`,
  objects/client.c must use upstream's content getter which `#include`s
  `screenshot_compose.h` — keep it.
- DROP throughout: PR #394 `initialized`-guard leftovers (client.h guards already
  dropped Phase 2).

### objects/layer_surface.c — surgical
- DROP (Rule A): `layer_surface_manage` / `layer_surface_emit_unmanage` synchronous
  `luaA_class_emit_signal("list")` — take upstream's `some_event_queue_class(
  &layer_surface_class, SIG_LIST)`. `request::manage`/`request::unmanage`/
  `request::keyboard` stay synchronous (Rule B).
- RE-APPLY: the fork opacity subsystem — `ls_apply_opacity_to_tree`,
  `layer_surface_apply_opacity_to_scene`, `luaA_layer_surface_{get,set}_opacity`,
  the `opacity` class property, the no-op-at-1.0 skip (fork commit `0c839f4`),
  includes. `property::opacity` stays synchronous (Rule C — fork property setter).
- RE-APPLY: re-add `#include "../event_queue.h"`. `scenefx_compat.h` swap.
- Downgrade the `[LS-OPACITY] SKIP` `wlr_log(WLR_ERROR,...)` to `WLR_DEBUG`.

### luaa.c — tag-slide helpers (deferred from Phase 2)
RE-APPLY `luaA_awesome_client_scene_set_enabled` + `luaA_awesome_client_scene_set_
strict_clip` (fork commit `4dc0fbf`) + their `awesome_methods[]` table entries.
They depend on `client_update_border_for_corners` (objects/client.c, this phase).

### lua/somewm/tag_slide.lua
Already fork-only, brought in Phase 1. Verify it feature-detects `strict_clip` and
the `_client_scene_set_*` methods (fork commit `4dc0fbf`). No edit expected.

---

## 5. Execution order

1. Trivial / take-upstream-verbatim: confirm `event.c`, `common/luaclass.c`,
   `ewmh.c`, `objects/systray.c`, `mouse.c` have empty diff vs `upstream/main`
   (no edits — they should already be upstream).
2. `xwayland.c` — small, RE-APPLY `xwayland::ready` only.
3. `protocols.c` — surgical, the PR #521 guard + layer-surface opacity.
4. `focus.c` — drop synchronous emits, include swaps.
5. `input.c` — the fork input features (bench, button_count, screen::focus,
   grab-end rebase, deferred_pointer_enter).
6. `objects/layer_surface.c` — opacity subsystem + SIG_LIST conversion.
7. `objects/client.c` — the big one, per-function per §4. Do it in sub-batches
   (signal-emit functions first to establish "take upstream", then the feature
   subsystem blocks). Codex review after this file specifically.
8. `window.c` — the CSD/maximize/minimize rework + drops.
9. `luaa.c` tag-slide helpers + `awesome_methods` entries.
10. Build (scenefx on + off) after each of 7, 8; full build at the end.

## 6. Test plan

- Build clean scenefx ON + OFF after `objects/client.c` and after `window.c`.
- `somewm --check` 30/30.
- The 4 upstream `tests/test-event-queue-*.lua` MUST pass.
- focus / mouse / xwayland regression test suites.
- **Double-emit grep:** after the phase, grep all Phase-4 files for any surviving
  `luaA_object_emit_signal` of a name that maps to a `SIG_*` enum entry — must be
  zero (except the Rule-B kept-synchronous `request::manage/unmanage/geometry`).
- Sandbox (headless, lgi guard LD_PRELOADed):
  - startup, hot-reload, client map/unmap, focus changes.
  - mouse hover across monitors (screen::focus), drag (PR #521 cross-monitor).
  - layer-surface map/unmap (PR #521 exclusive_focus guard).
  - CSD maximize/minimize via a GTK client if available.
- THEN the user live DRM-session test gate (per kolo6 methodology — no merge to
  `main` until that passes).

## 7. Codex review instructions (per user 2026-05-14)

Codex must be run MULTIPLE rounds, plus a fresh audit, and must be **given the fork
commit history** so it understands the essence and original placement of every
fork change — not just the raw diff. Concretely, the Codex prompt must instruct it
to:
- `git log -p <merge-base>..main -- focus.c input.c mouse.c window.c
  objects/client.c objects/layer_surface.c ewmh.c protocols.c xwayland.c
  objects/systray.c event.c common/luaclass.c` — read the commit messages AND
  diffs to understand WHY each fork change exists and WHERE it originally lived.
- Cross-check this sub-plan's per-function classification against (a) that fork
  history, (b) upstream's current queued-signal sites, (c) the `SIG_*` enum.
- Specifically validate: every Rule-A drop is genuinely a converted signal; every
  Rule-C keep is genuinely fork-new and absent from the enum; the
  `screenshot_compose.h` / content-getter decision; the PR #478 / `6fb4db8` drop;
  the `objects/client.c` per-hunk feature-vs-signal split.
- A SEPARATE round: a fresh audit agent re-derives the objects/client.c hunk
  classification independently and the two are reconciled.
- Iterate to GREEN before any code is written.

## 8. Open items carried in

- `wallpaper_cache_lookup` — DONE (Phase 3b).
- busted test environment is broken (lua 5.3→5.5 system update) — pre-existing,
  not a sync regression; flagged to user, does not block C work but DOES block the
  `tests/test-event-queue-*.lua` gate in §6 until the user fixes the rocks stack.
